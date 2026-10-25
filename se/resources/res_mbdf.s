
| -------------------------------------------------------------------------
| Resource_MBDF_0000 (resource-data)
| ROM offsets +0x3884C..+0x38DFA.
| ROM resource type=MBDF id=0 name=- attr=0x58; header +0x3884C, body +0x38854
| -------------------------------------------------------------------------
|
| =========================================================================
| MBDF 0 -- the standard menu bar definition function (1986 B&W version)
| =========================================================================
| New with the SE and Mac II ROMs: their Menu Manager no longer draws the
| menu bar itself (as the Plus ROM did) but calls this definition
| function for everything that touches the bar and the pulled-down menu
| (Inside Macintosh V-250: "All menu drawing-related activities ... have
| been removed from the menu manager code, and placed in the menu bar
| defproc"). The Menu Manager's MENU_CALL_MBDF gets 'MBDF' 0 from the ROM
| map, keeps its handle in MBProcHndl ($D54), locks it and calls it.
|
| Version: Apple's StandardMBDF.a (David Fung, "9/15/86 DAF New today",
| work by FJL through the autumn of 1986), assembled without the Mac II
| (onNuMac) code. The header's version word is 0 ("version 0 = onNuMac
| ROM" in Apple's list). It has C175 (10/8/86: lock the MenuList handle,
| GetMenuAscent), A278 (10/27/86: always the system font; HiliteMenu
| "inverts/inverts on menu select/unselect for Alladin" -- presumably
| the SE, code-named Aladdin: a title is inverted instead of saving the
| bits behind it and redrawing it) and A428 (11/18/86: lock the bits
| handle, draw the selected title after all the others). It lacks what
| the Mac II got -- color, the hierarchical menus of FJL's C222 with
| their save structure behind mbSaveLoc and messages 9..12, the
| portRect-relative coordinates of CXXX (11/5/86; this version assumes
| the screen starts at (0,0)) -- which presumably sat in onNuMac
| conditionals until FJL's "Clean up all OnNuMac conditionals" of
| 3/6/87, and all later work (parameter1, FJL 3Feb87; pop-up menus;
| messages 13..18).
|
| Calling convention (Pascal, 8 bytes of parameters -- Inside Macintosh
| V-251 shows the later 4-parameter form with parameter1):
|   FUNCTION MBarProc(selector: INTEGER; message: INTEGER;
|                     parameter: LONGINT): LONGINT;
| The Menu Manager passes the MenuList's mbResID word as the selector
| (not used here). Stack after LINK A6 (names: .set constants below):
|   0x10(A6) MBDF0_RESULT    function result (the caller pushes 0)
|   0x0E(A6) MBDF0_SELECTOR  mbResID (variant), unused
|   0x0C(A6) MBDF0_MESSAGE   message number 0..8
|   0x08(A6) MBDF0_PARAM     parameter (long)
|   -0x08(A6) MBDF0_MENURECT menuRect: rect of the menu being pulled down
|   -0x1E(A6) MBDF0_SAVED3   saveD3: MenuList offset of the hilited title
| The 20 bytes between these two locals are not used by this build
| (presumably variables of the color code).
|
| Every handler runs with
|   A2 = WMgrPort (the current port; clipRgn = its portRect, system
|        font, plain style)
|   A3 = MenuList pointer (the handle is locked during the call)
| and may change D0-D5/A0-A4 (the entry saves D3-D5/A2-A4).
|
| Messages (MBDF0_GOBARPROC; no range check -- 9 and up jump through the
| code that follows the table):
|   0 Draw     param 0: draw the bar and all titles; -1: clear the bar
|              only, leaving the clip set to the bar (InitWindows)
|   1 Hit      param = mouse point (global). Result: MenuList offset of
|              the title hit, 0 = in the bar but not in a title, -1 =
|              not in the bar. Open menus are not hit-tested.
|   2 Calc     param 0: compute menuLeft of every title and lastRight
|              (param <> 0 would start at that title, but see the bug
|              note at MBDF0_CALCBAR); InsertMenu calls it with 0
|   3 Init     nothing to do (no private data in this version)
|   4 Dispose  nothing to do
|   5 Hilite   param = state (high word) / MenuList offset (low word);
|              offset 0 inverts the whole bar (FlashMenuBar)
|   6 Height   MBarHeight := ascent + descent + 5 (the ROM's InitWindows
|              uses the Menu Manager's own CALCMBHEIGHT instead)
|   7 Save     param = MenuList offset: compute the menu rect, save the
|              screen behind it, draw the empty menu with its frame and
|              shadow; result = pointer to the menu rect (MBSaveLoc)
|   8 Restore  put the saved bits back, or (no memory for them) repaint
|              the windows behind the menu with PaintBehind
| (Inside Macintosh V-250 lists 13 messages; 9 GetRect, 10 SaveAlt, 11
| ResetAlt and 12 MenuRgn belong to the Mac II's hierarchical menus.)
|
| Data structures:
|   MenuList ($A1C) -> handle to the menu bar list: lastMenu (word,
|     offset of the last entry = 6 * number of menus), lastRight (word,
|     right edge of the last title), mbResID (word), then one 6-byte
|     entry per menu at offsets 6, 12, ...: menuoH (handle), menuLeft
|     (word, left edge of the title in pixels from the screen's left).
|   MenuInfo (menu record): menuID, menuWidth/menuHeight (-1 = not yet
|     computed, _CalcMenuSize), menuEnable bit 0 (whole menu enabled),
|     menuData (title string).
|   TempRect ($9FA) the rect of the title being drawn or hilited
|     (MBDF0_GETTITLERECT), or of the screen area being saved.
|   SavedHandle ($A28) handle to the saved screen area behind the open
|     menu: a 14-byte BitMap record (baseAddr -> the bits that follow,
|     rowBytes, bounds = the area in global coordinates), 0 if none.
|   MBSaveLoc ($D58) the open menu's rect (8 bytes, $D58-$D5F; msg 7
|     returns its address). Its second half overlaps the word MBFlash
|     ($D5C) that FlashMenuBar toggles -- harmless, as this MBDF inverts
|     the bar for either value of the flag. (MBSaveLoc and MBFlash are
|     the names lowmem_se.inc gives $D58 and $D5C; Apple's later
|     MBSaveLoc, the handle to the save structure, is at $B5C.)
|   MBarHeight ($BAA), TheMenu ($A26, menuID of the hilited title).
| Geometry: the first title starts at 10 (mbMenu1Loc); a title's text is
| drawn at menuLeft+8 with the baseline at ascent+2; titles are 13
| pixels (mTitleSpace) apart; a title's hilite rect spans (1, menuLeft-1)
| to (MBarHeight-1, next menuLeft+4) -- lastRight+4 for the last one.
| The menu hangs from the bar's bottom line (top = MBarHeight) and is
| moved left if its right edge + 8 would leave the screen.
|
| The resource ends with unused data from the color version: a 16x16
| Apple logo at 4 bits per pixel (twice, on white and on black) and the
| same logo at 1 bit per pixel (normal and inverted); the B&W build draws
| the Apple menu's title with the system font's apple character.
|
| Sources: Apple's StandardMBDF.a and MenuMgr.a (System 7.1 source, CR
| line endings; the 1986 history at their top), Private.a (MenuList
| equates), Inside Macintosh V-250..255 ("The Standard Menu Bar
| Definition Procedure"), the SE Menu Manager in toolbox_main.s
| (MENU_CALL_MBDF and its callers).
| -------------------------------------------------------------------------

| parameters and locals (see the banner)
.set MBDF0_RESULT, 0x10                         | function result (long)
.set MBDF0_SELECTOR, 0xE                        | selector: mbResID (word)
.set MBDF0_MESSAGE, 0xC                         | message (word)
.set MBDF0_PARAM, 0x8                           | parameter (long)
.set MBDF0_MENURECT, -0x8                       | menuRect (8 bytes)
.set MBDF0_SAVED3, -0x1E                        | saveD3 (word)
.set MBDF0_FRAMESIZE, -0x1E                     | size of the locals

Resource_MBDF_0000:
| ROM resource header: a Memory Manager block header, as in front of
| the data of a handle. The relative handle locates the resource's
| master pointer in the ROM zone (INITRESOURCES_CONT_2): 0x54 + 4 *
| its index in the ROM map's reference lists.
Resource_MBDF_0000_Header:
    .long	0xC00005AE                            | ROM resource header: tag $C0, physical size $5AE (8 + $5A6)
    .long	0x00000090                            | relative handle: master pointer at ROM zone + $90
| ----------------------------------------------------------
| _MBDF_0_ -- entry point and standard defproc header
| ----------------------------------------------------------
_MBDF_0_:
    BRA.B	MBDF0_START                           | skip the header
    .short	0x0000                               | flags word
    .long	0x4D424446                            | resource type 'MBDF'
    .short	0x0000                               | resource ID 0
    .short	0x0000                               | version 0
| StartMBDF: save registers and the caller's port, set up the
| WMgrPort and lock the MenuList, then dispatch on the message.
MBDF0_START:
    LINK	A6,#MBDF0_FRAMESIZE                    | frame for menuRect and saveD3
    MOVEM.L	D3-D5/A2-A4,-(SP)                   | save the work registers
    MOVEA.L	(A5),A0                             | A0 = QuickDraw globals
    MOVE.L	(A0),-(SP)                           | save thePort (restored by _SetPort below)
    MOVEA.L	(WMgrPort).W,A2                     | A2 = the Window Manager port
    MOVE.L	A2,-(SP)                             | draw in the WMgrPort
    _SetPort                                    | thePort := WMgrPort
    PEA.L	0x10(A2)                              | WMgrPort.portRect (the whole screen)
    _ClipRect                                   | clip wide open
    CLR.L	-(SP)                                 | font 0 and style [] for the next two calls
    _TextFont                                   | system font (A278: always)
    _TextFace                                   | plain style
    MOVEA.L	(MenuList).W,A0                     | A0 = MenuList handle
    TST.L	(A0)                                  | has the list been purged?
    BNE.B	MBDF0_MENULISTOK                      | no -> go on
    MOVEQ.L	#0x54,D0                            | menuPrgErr (84): MenuList purged
    _SysError                                   | fatal system error (does not return)
MBDF0_MENULISTOK:
    _HLock                                      | lock the MenuList while A3 points into it
    MOVEA.L	(A0),A3                             | A3 = MenuList pointer
    LEA.L	MBDF0_GOBARPROC(PC),A0                | A0 = dispatch table
    MOVE.W	MBDF0_MESSAGE(A6),D0                 | D0 = message number
    ADD.W	D0,D0                                 | word index
    ADDA.W	MBDF0_GOBARPROC(PC,D0.W),A0          | A0 = handler address (table + offset)
    JSR	(A0)                                    | call the message handler
    _SetPort                                    | restore the caller's port
    MOVEA.L	(MenuList).W,A0                     | MenuList handle
    _HUnlock                                    | unlock it again
    MOVEM.L	(SP)+,D3-D5/A2-A4                   | restore the work registers
    UNLK	A6                                     | drop the frame
    MOVEA.L	(SP)+,A0                            | A0 = return address
    ADDQ.W	#0x8,SP                              | strip selector, message, parameter
    JMP	(A0)                                    | return to the Menu Manager, result on the stack
| GoBarProc: message dispatch table, offsets from the table
MBDF0_GOBARPROC:
    .short	MBDF0_DRAWBAR-MBDF0_GOBARPROC        | 0 Draw
    .short	MBDF0_HITBAR-MBDF0_GOBARPROC         | 1 Hit
    .short	MBDF0_CALCBAR-MBDF0_GOBARPROC        | 2 Calc
    .short	MBDF0_INITBAR-MBDF0_GOBARPROC        | 3 Init
    .short	MBDF0_DISPOSEBAR-MBDF0_GOBARPROC     | 4 Dispose
    .short	MBDF0_HILITEBAR-MBDF0_GOBARPROC      | 5 Hilite
    .short	MBDF0_HEIGHTBAR-MBDF0_GOBARPROC      | 6 Height
    .short	MBDF0_SAVEBITSBAR-MBDF0_GOBARPROC    | 7 Save
    .short	MBDF0_RESTOREBITSBAR-MBDF0_GOBARPROC | 8 Restore
| ----------------------------------------------------------
| Msg 3 -- InitBar: this version keeps no private data, so there
| is nothing to allocate (the later version allocates its save
| structure here and keeps it in mbSaveLoc).
| ----------------------------------------------------------
MBDF0_INITBAR:
    RTS                                         | Init: nothing to do
| ----------------------------------------------------------
| Msg 4 -- DisposeBar: nothing to dispose of.
| ----------------------------------------------------------
MBDF0_DISPOSEBAR:
    RTS                                         | Dispose: nothing to do
| ----------------------------------------------------------
| Msg 6 -- HeightBar: MBarHeight := ascent + descent + 5 of the
| system font (20 with Chicago 12). The same computation is in
| the Menu Manager's CALCMBHEIGHT, which InitWindows calls.
| ----------------------------------------------------------
MBDF0_HEIGHTBAR:
    BSR.B	MBDF0_GETMENUINFO                     | D0 = ascent (high word) / descent (low word)
    MOVEQ.L	#0x5,D1                             | 5 pixels of white space
    ADD.W	D0,D1                                 | + descent
    SWAP.W	D0                                   | D0.W = ascent
    ADD.W	D0,D1                                 | + ascent
    MOVE.W	D1,(MBarHeight).W                    | store the menu bar height
    RTS                                         | return from MBDF0_HEIGHTBAR
| ----------------------------------------------------------
| GetMenuInfo -- font metrics of the current (system) font.
| Out: D0 = ascent in the high word, descent in the low word.
| Changes D0-D2/A0-A1 (_GetFontInfo).
| Called by: MBDF0_HEIGHTBAR, MBDF0_GETMENUASCENT
| ----------------------------------------------------------
MBDF0_GETMENUINFO:
    SUBQ.W	#0x8,SP                              | room for a FontInfo record
    MOVE.L	SP,-(SP)                             | point to it
    _GetFontInfo                                | ascent, descent, widMax, leading
    MOVE.L	(SP)+,D0                             | D0 = ascent / descent
    ADDQ.W	#0x4,SP                              | drop widMax and leading
    RTS                                         | return from MBDF0_GETMENUINFO
| ----------------------------------------------------------
| GetMenuAscent -- the baseline of the menu titles.
| Out: D4.L = ascent + 2 (y of the title baseline; the bar starts
|      at y = 0). Changes D0-D2/A0-A1.
| Called by: MBDF0_DRAW1TITLE
| ----------------------------------------------------------
MBDF0_GETMENUASCENT:
    BSR.B	MBDF0_GETMENUINFO                     | D0 = ascent / descent
    SWAP.W	D0                                   | D0.W = ascent
    MOVEQ.L	#0x0,D4                             | clear the high word
    MOVE.W	D0,D4                                | D4 = ascent
    ADDQ.W	#0x2,D4                              | + 2 = baseline
    RTS                                         | return from MBDF0_GETMENUASCENT
| ----------------------------------------------------------
| Msg 0 -- DrawBar: clear the menu bar to white and draw the line
| under it; with param 0 also draw all titles, then hilite the
| one whose menuID is in TheMenu (after all titles, A428).
| With param -1 return after clearing, the clip still set to the
| bar (Inside Macintosh V-251; InitWindows' DRAWMBAR).
| ----------------------------------------------------------
MBDF0_DRAWBAR:
    MOVE.L	0x1C(A2),-(SP)                       | WMgrPort.clipRgn
    CLR.L	-(SP)                                 | left = 0, top = 0
    MOVE.W	0x16(A2),-(SP)                       | right = portRect.right (screen width)
    MOVE.W	(MBarHeight).W,-(SP)                 | bottom = MBarHeight
    _SetRectRgn                                 | ClipMBar: clip to the menu bar
    PEA.L	0x10(A2)                              | WMgrPort.portRect
    MOVE.L	#0x100010,-(SP)                      | screenRadius (16,16)
    _EraseRoundRect                             | clear the bar inside the round screen corners
    MOVE.W	0x16(A2),-(SP)                       | LineTo h = screen right
    MOVEQ.L	#0x0,D0                             | D0 = 0 (h of MoveTo in the high word)
    MOVE.W	(MBarHeight).W,D0                    | bar height
    SUBQ.W	#0x1,D0                              | its last row
    MOVE.W	D0,-(SP)                             | LineTo v = MBarHeight-1
    SWAP.W	D0                                   | D0 = point (v = MBarHeight-1, h = 0)
    MOVE.L	D0,-(SP)                             | MoveTo point
    _MoveTo                                     | pen to the left end of the bottom row
    _LineTo                                     | draw the line under the menu bar
    CMPI.L	#-1,MBDF0_PARAM(A6)                  | param = -1 (just clear)?
    BEQ.B	MBDF0_DRAWDONE                        | yes -> done, clip stays on the bar
    PEA.L	0x10(A2)                              | WMgrPort.portRect
    _ClipRect                                   | clip wide open again
    TST.W	lastMenu(A3)                          | any menus in the list?
    BEQ.B	MBDF0_DRAWDONE                        | no -> done
    CLR.W	MBDF0_SAVED3(A6)                      | no hilited title found yet
    MOVEQ.L	#0x6,D3                             | D3 = offset of the first (leftmost) menu
| main drawing loop: D3 = MenuList offset of the title to draw
MBDF0_DRAWMLOOP:
    MOVE.W	D3,D0                                | this title
    BSR.W	MBDF0_GETTITLERECT                    | TempRect = its hilite rect
    BSR.W	MBDF0_DRAW1TITLE                      | draw the title (gray if disabled)
    MOVE.W	(TheMenu).W,D0                       | menuID of the hilited menu
    MOVEA.L	menuoH(A3,D3.W),A4                  | this menu's handle
    MOVEA.L	(A4),A4                             | A4 = its menu record
    CMP.W	menuID(A4),D0                         | is it the hilited one?
    BNE.B	MBDF0_NEXTDRAW                        | no ->
    MOVE.W	D3,MBDF0_SAVED3(A6)                  | remember it for after the loop
MBDF0_NEXTDRAW:
    ADDQ.W	#0x6,D3                              | next entry
    CMP.W	lastMenu(A3),D3                       | past the last one?
    BLE.B	MBDF0_DRAWMLOOP                       | no -> draw it
| hilite the selected title now that all titles are drawn (A428)
    MOVE.W	MBDF0_SAVED3(A6),D0                  | offset of the hilited title
    BEQ.B	MBDF0_DRAWDONE                        | none -> done
    MOVE.W	D0,D3                                | D3 = its offset
    BSR.W	MBDF0_GETTITLERECT                    | TempRect = its hilite rect
    MOVEA.L	menuoH(A3,D3.W),A0                  | its menu handle
    _HLock                                      | lock it
    MOVEA.L	(A0),A4                             | A4 = menu record
    BSR.W	MBDF0_DOSELECTED                      | invert the title (also unlocks)
    MOVEA.L	menuoH(A3,D3.W),A0                  | menu handle again
    _HUnlock                                    | unlock it
MBDF0_DRAWDONE:
    RTS                                         | return from MBDF0_DRAWBAR
| ----------------------------------------------------------
| Msg 1 -- HitBar: where is the mouse point (global, in param)?
| Result 0 if it is in the bar but left of the first title
| (h < 10) or right of the last (h >= lastRight), -1 if it is
| below the bar, else the MenuList offset of the title whose
| menuLeft is the largest one <= h. The row v = MBarHeight, the
| top row of a pulled-down menu, still counts as the bar (Apple
| later excluded it, CXXX), points above the screen too.
| ----------------------------------------------------------
MBDF0_HITBAR:
    MOVE.L	MBDF0_PARAM(A6),D1                   | D1 = mouse point (v / h)
    SWAP.W	D1                                   | D1.W = v
    CMP.W	(MBarHeight).W,D1                     | below the bar?
    BGT.B	MBDF0_NOTINBAR                        | yes -> -1
    SWAP.W	D1                                   | D1.W = h
    CMP.W	lastRight(A3),D1                      | right of the last title?
    BGE.B	MBDF0_NOTITLE                         | yes -> 0
    CMPI.W	#0xA,D1                              | left of the first title (mbMenu1Loc)?
    BLT.B	MBDF0_NOTITLE                         | yes -> 0
    MOVEQ.L	#0x0,D0                             | clear the high word of the result
    MOVE.W	lastMenu(A3),D0                      | start with the last (rightmost) menu
MBDF0_HITLOOP:
    CMP.W	menuLeft(A3,D0.W),D1                  | h >= this title's left edge?
    BGE.B	MBDF0_HITTHISONE                      | yes -> it is this title
    SUBQ.W	#0x6,D0                              | previous entry
    BRA.B	MBDF0_HITLOOP                         | (the first title's menuLeft is 10 <= h)
MBDF0_HITTHISONE:
    MOVE.L	D0,MBDF0_RESULT(A6)                  | result = MenuList offset of the title
MBDF0_HITDONE:
    RTS                                         | return from MBDF0_HITBAR
MBDF0_NOTITLE:
    CLR.L	MBDF0_RESULT(A6)                      | in the bar, but not in a title
    BRA.B	MBDF0_HITDONE                         | return
MBDF0_NOTINBAR:
    MOVE.L	#-1,MBDF0_RESULT(A6)                 | not in the bar
    BRA.B	MBDF0_HITDONE                         | return
| ----------------------------------------------------------
| Msg 2 -- CalcBar: lay out the titles. param 0: from the first
| title at 10; param = MenuList offset: from that title on. Each
| title is StringWidth(title) + 13 wide; the right edge of the
| last one goes to lastRight.
| BUG: the param <> 0 path loads the start position into D3 but
| leaves the loop index D4 uninitialized (whatever the caller of
| the MBDF had in D4). Apple's later source: "Dave found a bug in
| this due to assumption of D4's value at start of routine ...
| (somebody used D0, then changed to D4 without proper
| initialization)". The ROM's Menu Manager always passes 0.
| ----------------------------------------------------------
MBDF0_CALCBAR:
    MOVE.L	MBDF0_PARAM(A6),D0                   | D0 = MenuList offset to start at
    TST.W	D0                                    | (a long, treated as a word)
    BEQ.B	MBDF0_ENTIREBAR                       | 0 -> the whole bar
    CMP.W	lastMenu(A3),D0                       | beyond the last entry?
    BGT.B	MBDF0_CALCDONE                        | yes -> nothing to do
    MOVE.W	menuLeft(A3,D0.W),D3                 | D3 = left edge of the starting title
    BRA.B	MBDF0_CALCLOOP                        | (BUG: D4 is not set to D0)
MBDF0_ENTIREBAR:
    MOVEQ.L	#0xA,D3                             | the first title starts 10 pixels in
    MOVEQ.L	#0x6,D4                             | D4 = offset of the first entry
    MOVE.W	D3,menuLeft(A3,D4.W)                 | its menuLeft = 10
| measure the title of entry D4; D3 = its left edge
MBDF0_CALCLOOP:
    MOVEA.L	menuoH(A3,D4.W),A0                  | menu handle
    MOVEA.L	(A0),A0                             | menu record
    CLR.W	-(SP)                                 | room for the width
    PEA.L	menuData(A0)                          | the menu title
    _StringWidth                                | width in the system font
    ADD.W	(SP)+,D3                              | + title width
    ADDI.W	#0xD,D3                              | + 13 (mTitleSpace) = left of the next title
    ADDQ.W	#0x6,D4                              | next entry
    CMP.W	lastMenu(A3),D4                       | past the last one?
    BGT.B	MBDF0_CALCLOOPDONE                    | yes -> done
    MOVE.W	D3,menuLeft(A3,D4.W)                 | its menuLeft
    BRA.B	MBDF0_CALCLOOP                        | measure it
MBDF0_CALCLOOPDONE:
    MOVE.W	D3,lastRight(A3)                     | lastRight = end of the last title
MBDF0_CALCDONE:
    RTS                                         | return from MBDF0_CALCBAR
| ----------------------------------------------------------
| Msg 5 -- HiliteBar: param high word = state, low word =
| MenuList offset; offset 0 = invert the whole bar (FlipBar).
| States: 0 normal and 1 selected both invert the title rect
| (A278: on the SE a title is inverted when its menu is pulled
| down and inverted back afterwards, as on the Plus -- the Mac II
| saves the bits and redraws the title in reversed colors);
| 2 disabled paints the title gray, 3 busy paints it with a
| striped pattern (both patBic); higher states are ignored.
| The range check compares with lastRight instead of lastMenu
| (Apple fixed this in 1990: "<10>(lastRight->lastMenu)").
| ----------------------------------------------------------
MBDF0_HILITEBAR:
    MOVE.L	MBDF0_PARAM(A6),D0                   | D0 = state / MenuList offset
    CMPI.W	#0x0,D0                              | offset 0?
    BEQ.W	MBDF0_FLIPBAR                         | yes -> invert the whole bar
    CMP.W	lastRight(A3),D0                      | "legal title?" (should be lastMenu)
    BGT.W	MBDF0_DONEHILITE                      | no -> ignore
    MOVE.L	D0,-(SP)                             | save state / offset
    BSR.W	MBDF0_GETTITLERECT                    | TempRect = the title's hilite rect
    MOVE.L	(SP)+,D0                             | state / offset again
    MOVEQ.L	#0x0,D3                             | clear the high word
    MOVE.W	D0,D3                                | D3 = MenuList offset
    SWAP.W	D0                                   | D0.W = state
    CMPI.W	#0x3,D0                              | state > 3?
    BGT.W	MBDF0_DONEHILITE                      | yes -> ignore
    BEQ.B	MBDF0_PAINTBUSY                       | 3 = busy -> stripes
    CMPI.W	#0x2,D0                              | 2 = disabled?
    BEQ.B	MBDF0_PAINTDISABLED                   | yes -> gray
    CMPI.W	#0x1,D0                              | 1 = selected?
    BEQ.B	MBDF0_DOSELECTED                      | yes -> invert
    PEA.L	(TempRect).W                          | 0 = normal: the title rect
    _InvertRect                                 | invert it back
    BRA.W	MBDF0_DONEHILITE                      | done
| unreachable: in the Mac II version the normal state erases the
| title rect here and falls into Draw1Title to redraw the title;
| the A278 invert-back above branches around it.
    PEA.L	(TempRect).W                          | (unreachable) the title rect
    _EraseRect                                  | (unreachable) erase it
| ----------------------------------------------------------
| Draw1Title -- draw one menu title.
| In:  D3 = MenuList offset of the title, TempRect = its hilite
|      rect (MBDF0_GETTITLERECT).
| Draws the title at (menuLeft+8, ascent+2) and paints TempRect
| gray (patBic) if the whole menu is disabled (menuEnable bit 0
| clear). Locks the menu handle while drawing.
| Out: D4 = baseline, A4 = menu record. Changes D0-D2/A0-A1.
| Called by: MBDF0_DRAWBAR
| ----------------------------------------------------------
MBDF0_DRAW1TITLE:
    MOVEA.L	menuoH(A3,D3.W),A0                  | the menu handle
    _HLock                                      | lock it while drawing its title
    MOVEA.L	(A0),A4                             | A4 = menu record
    BSR.W	MBDF0_GETMENUASCENT                   | D4 = baseline
    MOVE.W	menuLeft(A3,D3.W),-(SP)              | h = menuLeft
    ADDQ.W	#0x8,(SP)                            | + 8 (indent)
    MOVE.W	D4,-(SP)                             | v = baseline
    _MoveTo                                     | pen to the title's start
    PEA.L	menuData(A4)                          | the title string
    _DrawString                                 | draw it
    MOVEA.L	menuoH(A3,D3.W),A4                  | menu handle again
    MOVEA.L	(A4),A4                             | menu record
    BTST	#0x0,menuEnable+3(A4)                  | menu enabled (menuEnable bit 0)?
    BEQ.B	MBDF0_PAINTDISABLED                   | no -> gray the title
    BRA.B	MBDF0_UNLOCKTITLE                     | yes -> unlock and return
| ----------------------------------------------------------
| DoSelected -- show a title as selected: invert TempRect, then
| unlock the title's menu handle (MBDF0_UNLOCKTITLE).
| In:  D3 = MenuList offset, TempRect = the title's hilite rect.
| Changes D0-D2/A0-A1. Reached by BSR from MBDF0_DRAWBAR and by BEQ from
| MBDF0_HILITEBAR (state 1), where the RTS ends the message.
| ----------------------------------------------------------
MBDF0_DOSELECTED:
    PEA.L	(TempRect).W                          | the title rect
    _InvertRect                                 | invert it
    BRA.B	MBDF0_UNLOCKTITLE                     | unlock and return
| Hilite states 3 (busy) and 2 (disabled), and Draw1Title's gray
| (PaintTitleDisable): paint TempRect with a pattern in patBic
| mode, clearing every pixel where the pattern has a 1.
MBDF0_PAINTBUSY:
    LEA.L	MBDF0_BUSYPAT(PC),A0                  | A0 = striped pattern (busy)
    BRA.B	MBDF0_PAINTTITLE                      | paint with it
MBDF0_PAINTDISABLED:
    LEA.L	MBDF0_GRAYPAT(PC),A0                  | A0 = gray pattern (disabled)
MBDF0_PAINTTITLE:
    MOVE.L	A0,-(SP)                             | the pattern, for PenPat
    MOVE.W	#0xB,-(SP)                           | patBic (11)
    _PenMode                                    | pen mode patBic
    _PenPat                                     | pen pattern
    PEA.L	(TempRect).W                          | the title rect
    _PaintRect                                  | clear the pattern's pixels
    _PenNormal                                  | pen back to normal
| unlock the menu handle of title D3 and return
MBDF0_UNLOCKTITLE:
    MOVEA.L	menuoH(A3,D3.W),A0                  | the menu handle
    _HUnlock                                    | unlock it
MBDF0_DONEHILITE:
    RTS                                         | return
| FlipBar (hilite offset 0, used by FlashMenuBar(0)): invert the
| whole menu bar inside the round screen corners.
MBDF0_FLIPBAR:
    MOVEQ.L	#0x0,D0                             | title 0 = the whole bar
    BSR.W	MBDF0_GETTITLERECT                    | TempRect = (0,0)-(MBarHeight, screen right)
    PEA.L	(TempRect).W                          | the bar rect
    _ClipRect                                   | clip to the bar
    PEA.L	0x10(A2)                              | WMgrPort.portRect
    MOVE.L	#0x100010,-(SP)                      | screenRadius (16,16)
    _InvertRoundRect                            | invert the bar (corners stay)
    PEA.L	0x10(A2)                              | WMgrPort.portRect
    _ClipRect                                   | clip wide open again
    BRA.B	MBDF0_DONEHILITE                      | done
| ----------------------------------------------------------
| GetTitleRect -- the rect of a title that hiliting inverts.
| In:  D0.W = MenuList offset of the title; 0 = the whole bar.
| Out: TempRect = (top 1, left menuLeft-1, bottom MBarHeight-1,
|      right = next title's menuLeft + 4, or lastRight + 4 for the
|      last title); for 0: (0, 0, MBarHeight, screen right).
|      A0 points into TempRect. Changes D0.
| Called by: MBDF0_DRAWBAR (2), MBDF0_HILITEBAR, MBDF0_FLIPBAR
| ----------------------------------------------------------
MBDF0_GETTITLERECT:
    TST.W	D0                                    | title 0?
    BEQ.B	MBDF0_WHOLEBAR                        | yes -> the whole bar
    LEA.L	(TempRect).W,A0                       | A0 = TempRect
    MOVE.W	#0x1,(A0)+                           | top = 1 (below the screen's top row)
    MOVE.W	menuLeft(A3,D0.W),(A0)               | left = menuLeft
    SUBQ.W	#0x1,(A0)+                           | - 1
    MOVE.W	(MBarHeight).W,(A0)                  | bottom = MBarHeight
    SUBQ.W	#0x1,(A0)+                           | - 1 (above the line under the bar)
    CMP.W	lastMenu(A3),D0                       | the last title?
    BEQ.B	MBDF0_GTLASTMENU                      | yes -> right = lastRight
    ADDQ.W	#0x6,D0                              | next entry
    MOVE.W	menuLeft(A3,D0.W),(A0)               | right = next title's left edge
    BRA.B	MBDF0_GTMARGIN                        | + margin
MBDF0_GTLASTMENU:
    MOVE.W	lastRight(A3),(A0)                   | right = end of the last title
MBDF0_GTMARGIN:
    ADDQ.W	#0x4,(A0)                            | + 4 pixels of margin
MBDF0_GTDONE:
    RTS                                         | return from MBDF0_GETTITLERECT
MBDF0_WHOLEBAR:
    LEA.L	(TempRect).W,A0                       | A0 = TempRect
    CLR.L	(A0)+                                 | top = left = 0
    MOVE.W	(MBarHeight).W,(A0)+                 | bottom = MBarHeight
    MOVE.W	0x16(A2),(A0)                        | right = portRect.right (screen width)
    BRA.B	MBDF0_GTDONE                          | return
| ----------------------------------------------------------
| Msg 7 -- SaveBitsBar: param = MenuList offset of the menu that
| is being pulled down. Computes its rect (MBDF0_MAKEMRECT),
| saves the screen under it -- the rect grown by 4 on the left,
| right and bottom for the frame and the shadow -- in a new
| handle (SavedHandle; 0 if there is no memory), erases the
| menu rect and draws the frame (left, bottom, right; the top is
| the bar's bottom line) and a 2-pixel shadow (bottom, right).
| Result: pointer to the menu rect, copied to MBSaveLoc.
| Note: A2 and A3 are reused as scratch registers from the
| InsetRect on; the dispatcher no longer needs them.
| ----------------------------------------------------------
MBDF0_SAVEBITSBAR:
    MOVE.L	MBDF0_PARAM(A6),D0                   | D0 = MenuList offset of the menu
    MOVEA.L	menuoH(A3,D0.W),A1                  | A1 = menu handle
    MOVE.W	menuLeft(A3,D0.W),D3                 | D3 = its title's left edge
    MOVEA.L	(A1),A0                             | A0 = menu record
    TST.L	menuWidth(A0)                         | menuWidth/menuHeight valid (not -1)?
    BPL.B	MBDF0_SKIPCALCSIZE                    | yes ->
    MOVE.L	A1,-(SP)                             | save the menu handle
    MOVE.L	A1,-(SP)                             | menu handle for CalcMenuSize
    _CalcMenuSize                               | have the MDEF compute width and height
    MOVEA.L	(SP)+,A0                            | menu handle again
    MOVEA.L	(A0),A0                             | A0 = menu record
MBDF0_SKIPCALCSIZE:
    BSR.W	MBDF0_MAKEMRECT                       | menuRect(A6) = the menu's rect
    LEA.L	(TempRect).W,A3                       | A3 = TempRect (A3 reused!)
    LEA.L	MBDF0_MENURECT(A6),A4                 | A4 = menuRect
    MOVEA.L	A4,A2                               | A2 = menuRect (A2 reused!)
    MOVE.L	A3,-(SP)                             | TempRect, for InsetRect
    MOVE.W	(A2)+,(A3)                           | TempRect.top = menuRect.top
    ADDQ.W	#0x4,(A3)+                           | + 4: the inset below keeps the top row
    MOVE.W	(A2)+,(A3)+                          | left
    MOVE.L	(A2),(A3)+                           | bottom, right
    MOVE.L	#0xFFFCFFFC,-(SP)                    | grow by 4 pixels
    _InsetRect                                  | TempRect = area to save (incl. frame, shadow)
| SaveDemBits: a BitMap record followed by its bits
    MOVEQ.L	#0xF,D3                             | 15 (round up to whole words)
    ADD.W	-(A3),D3                              | + right
    MOVE.W	-(A3),D4                             | D4 = bottom
    SUB.W	-(A3),D3                              | - left
    SUB.W	-(A3),D4                              | D4 = height; A3 = TempRect again
    LSR.W	#0x4,D3                               | words per row
    ADD.W	D3,D3                                 | D3 = rowBytes
    MOVE.W	D3,D0                                | rowBytes
    MULU.W	D4,D0                                | * height = size of the bits
    ADDI.W	#0xE,D0                              | + 14 for the BitMap record
    _NewHandle                                  | allocate (in the current heap)
    BNE.W	MBDF0_NOSAVEMEM                       | no memory -> draw without saving
    _HLock                                      | lock it (A428)
    MOVE.L	A0,(SavedHandle).W                   | SavedHandle = the saved bits
    MOVEA.L	(A0),A0                             | A0 = the BitMap record
    MOVE.W	D3,0x4(A0)                           | rowBytes
    MOVE.L	A0,(A0)                              | baseAddr = the record ...
    ADDI.L	#0xE,(A0)                            | ... + 14: the bits that follow it
    MOVE.L	(A3),0x6(A0)                         | bounds.topLeft = TempRect.topLeft
    MOVE.L	0x4(A3),0xA(A0)                      | bounds.botRight = TempRect.botRight
    MOVEA.L	(WMgrPort).W,A1                     | A1 = WMgrPort
    PEA.L	0x2(A1)                               | srcBits = WMgrPort.portBits (the screen)
    MOVE.L	A0,-(SP)                             | dstBits = the saved BitMap
    BSR.W	MBDF0_COPYSAVED                       | copy the screen area into it
| DrawStruct: erase the menu and frame it
MBDF0_DRAWSTRUCT:
    LEA.L	MBDF0_MENURECT(A6),A4                 | A4 = menuRect
    MOVE.L	A4,-(SP)                             | the menu rect
    _EraseRect                                  | erase it (white)
    SUBQ.W	#0x2,SP                              | room for the result
    MOVE.L	A4,-(SP)                             | the menu rect
    _EmptyRect                                  | empty menu?
    TST.B	(SP)+                                 | (an empty menu casts no shadow)
    BNE.B	MBDF0_SAVEBITSDONE                    | yes -> no frame
    _PenNormal                                  | 1x1 black pen
    MOVE.L	0x4(A4),-(SP)                        | (bottom, right): last LineTo is (right, top) ...
    MOVE.L	(SP),-(SP)                           | (bottom, right): LineTo(right, bottom)
    MOVE.L	(A4),-(SP)                           | (top, left) ...
    SUBQ.W	#0x1,0x2(SP)                         | ... -> (top, left-1) ...
    MOVE.L	(SP),-(SP)                           | (top, left-1): MoveTo(left-1, top)
    MOVE.W	0x4(A4),0x4(SP)                      | (bottom, left-1): LineTo(left-1, bottom)
    MOVE.W	(A4),0xC(SP)                         | (top, right) for the last LineTo
    _MoveTo                                     | MoveTo(left-1, top)
    _LineTo                                     | left edge down to (left-1, bottom)
    _LineTo                                     | bottom edge to (right, bottom)
    _LineTo                                     | right edge up to (right, top)
    MOVE.L	#0x20002,-(SP)                       | 2x2 pen for the shadow
    _PenSize                                    | pen size (2,2)
    MOVE.W	0x6(A4),D0                           | D0 = right
    MOVE.W	D0,-(SP)                             | 2nd LineTo h = right
    MOVE.W	(A4),-(SP)                           | 2nd LineTo v = top ...
    ADDQ.W	#0x2,(SP)                            | ... + 2
    MOVE.W	D0,-(SP)                             | 1st LineTo h = right
    MOVE.W	0x4(A4),D0                           | D0 = bottom
    MOVE.W	D0,-(SP)                             | 1st LineTo v = bottom
    MOVE.W	0x2(A4),-(SP)                        | MoveTo h = left ...
    ADDQ.W	#0x2,(SP)                            | ... + 2
    MOVE.W	D0,-(SP)                             | MoveTo v = bottom
    _MoveTo                                     | MoveTo(left+2, bottom)
    _LineTo                                     | shadow under the menu to (right, bottom)
    _LineTo                                     | shadow right of it up to (right, top+2)
    _PenNormal                                  | pen back to normal
MBDF0_SAVEBITSDONE:
    MOVE.L	MBDF0_MENURECT(A6),(MBSaveLoc).W     | MBSaveLoc = menuRect.topLeft
    MOVE.L	MBDF0_MENURECT+4(A6),(MBSaveLoc+4).W | menuRect.botRight ($D5C, overlaps MBFlash)
    LEA.L	(MBSaveLoc).W,A0                      | A0 = the saved menu rect
    MOVE.L	A0,MBDF0_RESULT(A6)                  | result = pointer to the menu rect
    RTS                                         | return from MBDF0_SAVEBITSBAR
| ----------------------------------------------------------
| MakeMRect -- the rect of a pulled-down menu.
| In:  A0 = menu record (menuWidth/menuHeight valid), D3 = left
|      edge of its title (menuLeft), A2 = WMgrPort.
| If menuLeft + menuWidth + 8 is beyond the screen's right edge,
| the menu is moved left to end 8 pixels before it.
| Out: menuRect(A6) = (MBarHeight, left, MBarHeight + menuHeight,
|      left + menuWidth). Changes D0-D1/D3/A1.
| Called by: MBDF0_SAVEBITSBAR, MBDF0_MAKEUPDATE
| ----------------------------------------------------------
MBDF0_MAKEMRECT:
    MOVE.W	D3,D0                                | menuLeft
    ADD.W	menuWidth(A0),D0                      | + menuWidth = right edge
    ADDQ.W	#0x8,D0                              | + 8 pixels of margin
    CMP.W	0x16(A2),D0                           | still on the screen (portRect.right)?
    BLE.B	MBDF0_STORERECT                       | yes ->
    MOVE.W	0x16(A2),D3                          | no: screen right
    SUBQ.W	#0x8,D3                              | - 8
    SUB.W	menuWidth(A0),D3                      | - menuWidth = new left edge
MBDF0_STORERECT:
    LEA.L	MBDF0_MENURECT(A6),A1                 | A1 = menuRect
    MOVE.W	(MBarHeight).W,D1                    | D1 = MBarHeight
    MOVE.W	D1,(A1)+                             | top = MBarHeight
    MOVE.W	D3,(A1)+                             | left
    ADD.W	menuHeight(A0),D1                     | + menuHeight
    MOVE.W	D1,(A1)+                             | bottom
    ADD.W	menuWidth(A0),D3                      | left + menuWidth
    MOVE.W	D3,(A1)                              | right
    RTS                                         | return from MBDF0_MAKEMRECT
| ----------------------------------------------------------
| CopySaved -- copy between the screen and the saved bits.
| In:  stack: srcBits and dstBits pushed by the caller (one of them
|      the saved BitMap), A0 = the saved BitMap record. Does
|      CopyBits(srcBits, dstBits, bounds, bounds, srcCopy, NIL)
|      with bounds = the saved BitMap's bounds (global coordinates)
|      and removes the two parameters.
| Changes D4 (keeps the return address), D0-D2/A0-A1 (CopyBits).
| Called by: MBDF0_SAVEBITSBAR, MBDF0_RESTOREBITSBAR
| ----------------------------------------------------------
MBDF0_COPYSAVED:
    MOVE.L	(SP)+,D4                             | D4 = return address
    PEA.L	0x6(A0)                               | srcRect = saved BitMap's bounds
    MOVE.L	(SP),-(SP)                           | dstRect = the same rect
    CLR.W	-(SP)                                 | mode srcCopy
    CLR.L	-(SP)                                 | no mask region
    _CopyBits                                   | copy the bits
    MOVE.L	D4,-(SP)                             | return address back
    RTS                                         | return from MBDF0_COPYSAVED
| unreachable: the Mac II version disposes of its pixmap here before
| clearing SavedHandle; _DisposPixMap ($AA04) is a Color QuickDraw
| trap, not implemented on the SE.
    MOVEA.L	(SavedHandle).W,A0                  | (unreachable) the saved pixmap
    MOVE.L	A0,-(SP)                             | (unreachable) push it
    .short	0xAA04                               | (unreachable) _DisposPixMap
| no memory for the saved bits: draw the menu anyway; the Restore
| message will then repaint the windows behind it
MBDF0_NOSAVEMEM:
    CLR.L	(SavedHandle).W                       | no bits saved
    BRA.W	MBDF0_DRAWSTRUCT                      | erase and frame the menu
| ----------------------------------------------------------
| Msg 8 -- RestoreBitsBar: the menu is closed. If its bits were
| saved, copy them back and dispose of them; otherwise (param =
| its MenuList offset) let the windows behind it redraw it.
| ----------------------------------------------------------
MBDF0_RESTOREBITSBAR:
    MOVE.L	(SavedHandle).W,D0                   | the saved bits
    BEQ.B	MBDF0_MAKEUPDATE                      | none -> repaint instead
    MOVEA.L	D0,A0                               | the handle
    MOVEA.L	(A0),A0                             | A0 = the saved BitMap record
    MOVE.L	A0,-(SP)                             | srcBits = the saved bits
    PEA.L	0x2(A2)                               | dstBits = WMgrPort.portBits (the screen)
    BSR.B	MBDF0_COPYSAVED                       | copy them back to the screen
    MOVEA.L	(SavedHandle).W,A0                  | the handle
    _DisposeHandle                              | free it
    CLR.L	(SavedHandle).W                       | no saved bits any more
    RTS                                         | return from MBDF0_RESTOREBITSBAR
| MakeUpdate: rebuild the menu's rect, grow it by the frame and the
| shadow and repaint everything behind the front window there
MBDF0_MAKEUPDATE:
    MOVE.L	MBDF0_PARAM(A6),D0                   | D0 = MenuList offset of the menu
    MOVE.W	menuLeft(A3,D0.W),D3                 | D3 = its title's left edge
    MOVEA.L	menuoH(A3,D0.W),A4                  | A4 = menu handle
    MOVEA.L	(A4),A0                             | A0 = menu record
    TST.L	menuWidth(A0)                         | size valid?
    BPL.B	MBDF0_UPDSIZEOK                       | yes ->
    MOVE.L	A4,-(SP)                             | menu handle
    _CalcMenuSize                               | compute width and height
    MOVEA.L	(A4),A0                             | A0 = menu record again
MBDF0_UPDSIZEOK:
    BSR.W	MBDF0_MAKEMRECT                       | menuRect = the menu's rect
    LEA.L	MBDF0_MENURECT(A6),A1                 | A1 = menuRect
    ADDQ.W	#0x2,A1                              | -> left
    SUBQ.W	#0x1,(A1)+                           | left - 1 (the frame)
    ADDQ.W	#0x2,(A1)+                           | bottom + 2 (frame and shadow)
    ADDQ.W	#0x2,(A1)                            | right + 2 (frame and shadow)
    SUBQ.W	#0x4,SP                              | room for the region
    _NewRgn                                     | a new region (stays on the stack)
    MOVE.L	(SP),-(SP)                           | the region
    PEA.L	MBDF0_MENURECT(A6)                    | the grown menu rect
    _RectRgn                                    | region = that rect
    SUBQ.W	#0x4,SP                              | room for the window
    _FrontWindow                                | startWindow = the front window
    MOVE.L	0x4(SP),-(SP)                        | clobberedRgn = the region
    _PaintBehind                                | repaint it (desk, frames, update events)
    _DisposeRgn                                 | dispose of the region (still on the stack)
    RTS                                         | return from MBDF0_RESTOREBITSBAR
| ----------------------------------------------------------
| Data
| ----------------------------------------------------------
| hilite state 3 (busy): horizontal stripes
MBDF0_BUSYPAT:
    .long	0xFF00FF00                            | rows 0-3: black, white, black, white
    .long	0xFF00FF00                            | rows 4-7: black, white, black, white
| hilite state 2 / disabled title: 50% gray
MBDF0_GRAYPAT:
    .long	0xAA55AA55                            | rows 0-3: gray
    .long	0xAA55AA55                            | rows 4-7: gray
| Unused here: the color Apple menu title of the Mac II version (C175
| "Added 4-bit color apple"): a 16x16 image at 4 bits per pixel, 8
| bytes per row, background 0, the logo's six color bands drawn with
| pixel values 6, 2, 11, 10, 8, 12 (green to blue; the color table
| is not part of this resource) ...
MBDF0_APPLE4BIT:
    .long	0x00000000,0x00000000                 | row  0: ................
    .long	0x00000000,0x06600000                 | row  1: .........66.....
    .long	0x00000000,0x66000000                 | row  2: ........66......
    .long	0x00000000,0x60000000                 | row  3: ........6.......
    .long	0x00006666,0x06666000                 | row  4: ....6666.6666...
    .long	0x00066666,0x66666600                 | row  5: ...66666666666..
    .long	0x00022222,0x22220000                 | row  6: ...222222222....
    .long	0x000BBBBB,0xBBBB0000                 | row  7: ...BBBBBBBBB....
    .long	0x000BBBBB,0xBBBB0000                 | row  8: ...BBBBBBBBB....
    .long	0x000AAAAA,0xAAAAAA00                 | row  9: ...AAAAAAAAAAA..
    .long	0x0000AAAA,0xAAAAA000                 | row 10: ....AAAAAAAAA...
    .long	0x00008888,0x88888000                 | row 11: ....888888888...
    .long	0x00000CCC,0xCCCC0000                 | row 12: .....CCCCCCC....
    .long	0x000000CC,0x0CC00000                 | row 13: ......CC.CC.....
    .long	0x00000000,0x00000000                 | row 14: ................
    .long	0x00000000,0x00000000                 | row 15: ................
| ... the same image with background 15 (for the inverted title) ...
MBDF0_APPLE4BITINV:
    .long	0xFFFFFFFF,0xFFFFFFFF                 | row  0: ................
    .long	0xFFFFFFFF,0xF66FFFFF                 | row  1: .........66.....
    .long	0xFFFFFFFF,0x66FFFFFF                 | row  2: ........66......
    .long	0xFFFFFFFF,0x6FFFFFFF                 | row  3: ........6.......
    .long	0xFFFF6666,0xF6666FFF                 | row  4: ....6666.6666...
    .long	0xFFF66666,0x666666FF                 | row  5: ...66666666666..
    .long	0xFFF22222,0x2222FFFF                 | row  6: ...222222222....
    .long	0xFFFBBBBB,0xBBBBFFFF                 | row  7: ...BBBBBBBBB....
    .long	0xFFFBBBBB,0xBBBBFFFF                 | row  8: ...BBBBBBBBB....
    .long	0xFFFAAAAA,0xAAAAAAFF                 | row  9: ...AAAAAAAAAAA..
    .long	0xFFFFAAAA,0xAAAAAFFF                 | row 10: ....AAAAAAAAA...
    .long	0xFFFF8888,0x88888FFF                 | row 11: ....888888888...
    .long	0xFFFFFCCC,0xCCCCFFFF                 | row 12: .....CCCCCCC....
    .long	0xFFFFFFCC,0xFCCFFFFF                 | row 13: ......CC.CC.....
    .long	0xFFFFFFFF,0xFFFFFFFF                 | row 14: ................
    .long	0xFFFFFFFF,0xFFFFFFFF                 | row 15: ................
| ... and the logo at 1 bit per pixel, black on white ...
MBDF0_APPLE1BIT:
    .short	0x0000                               | ................
    .short	0x0060                               | .........##.....
    .short	0x00C0                               | ........##......
    .short	0x0080                               | ........#.......
    .short	0x0F78                               | ....####.####...
    .short	0x1FFC                               | ...###########..
    .short	0x1FF0                               | ...#########....
    .short	0x1FF0                               | ...#########....
    .short	0x1FF0                               | ...#########....
    .short	0x1FFC                               | ...###########..
    .short	0x0FF8                               | ....#########...
    .short	0x0FF8                               | ....#########...
    .short	0x07F0                               | .....#######....
    .short	0x0360                               | ......##.##.....
    .short	0x0000                               | ................
    .short	0x0000                               | ................
| ... and white on black
MBDF0_APPLE1BITINV:
    .short	0xFFFF                               | ################
    .short	0xFF9F                               | #########..#####
    .short	0xFF3F                               | ########..######
    .short	0xFF7F                               | ########.#######
    .short	0xF087                               | ####....#....###
    .short	0xE003                               | ###...........##
    .short	0xE00F                               | ###.........####
    .short	0xE00F                               | ###.........####
    .short	0xE00F                               | ###.........####
    .short	0xE003                               | ###...........##
    .short	0xF007                               | ####.........###
    .short	0xF007                               | ####.........###
    .short	0xF80F                               | #####.......####
    .short	0xFC9F                               | ######..#..#####
    .short	0xFFFF                               | ################
    .short	0xFFFF                               | ################

