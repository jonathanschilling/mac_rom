
| -------------------------------------------------------------------------
| Resource_MDEF_0000 (resource-code-or-driver)
| ROM offsets +0x38DFA..+0x3920A.
| ROM resource type=MDEF id=0 name=- attr=0x58; header +0x38DFA, body +0x38E02
| -------------------------------------------------------------------------
|
| =========================================================================
| MDEF 0 -- the standard menu definition procedure ("TextMenuProc")
| =========================================================================
| Andy Hertzfeld's StandardMDEF.a (1982) as revised by EHB in 1985/86:
| variable-height system font (v3), ROM85 test (v4), international
| right-to-left display (v5, 27Sep85), icons, scrolling menus; the
| header's version word is still 4 ("version 4 = MacPlus" in Apple's
| list), as in the Plus. The labels and most comments come from the Plus
| MDEF 0 (src/plus/resources/res_mdef.s); the SE version is a few weeks
| newer and differs in these places:
|   - scrolling works in pixels ("1/30/86 EHB Re-did scrolling so icons
|     would work"): TopMenuItem is the v coordinate of the top of item 1
|     (Plus: the number of the first visible item) and AtMenuBottom the
|     v coordinate of the bottom of the last item (Plus: a flag); a
|     scroll moves the contents by one line and redraws only the strip
|     that becomes visible (clip = ScrollRect's update region);
|   - mDrawMsg sets TopMenuItem to menuRect.top; MDEF_DRAW_ALL draws all
|     items (the clip limits them) to find AtMenuBottom; the Plus's
|     menu-bar-height helper is folded into mSizeMsg;
|   - MDEF_CHK_ENABLED treats items above 31 (no enable bit) separately
|     ("1/7/86 EHB Fixed enable bug for items > 31") -- see the bug
|     note there.
| Not yet: hierarchical menus, color, pop-up menus, scroll arrows (the
| 1986/87 work of FJL for the Mac II and System 4.1).
|
| Calling convention (Inside Macintosh I-362):
|   PROCEDURE TextMenuProc(message: INTEGER; theMenu: MenuHandle;
|                 VAR menuRect: Rect; hitPt: Point; VAR whichItem: INTEGER);
| Stack after LINK A6 (names: .set constants below):
|   0x18(A6) MDEF_MESSAGE    0 mDrawMsg, 1 mChooseMsg, 2 mSizeMsg (others
|                            are treated as mSizeMsg)
|   0x14(A6) MDEF_THEMENU    theMenu (kept in A3)
|   0x10(A6) MDEF_MENURECT   pointer to menuRect (global coordinates)
|   0x0C(A6) MDEF_HITPT      hitPt (mouse point, v in the high word)
|   0x08(A6) MDEF_WHICHITEM  pointer to whichItem
| Locals: a FontInfo record (MDEF_SETUP_FONT, Apple's GetSizes):
|   -0x8(A6) MDEF_ASCENT     ascent
|   -0x6(A6) MDEF_DESCENT    descent
|   -0x4(A6) MDEF_WIDMAX     widMax (minus 2 for Chicago): width of the
|                            mark column, of a command key character
|   -0x2(A6) MDEF_MFHEIGHT   leading+ascent+descent: height of a text item
| An item with an icon is 36 pixels high and gets a 40-pixel icon
| column ('ICON' 256 + icon number, plotted 32x32).
|
| Item data (Inside Macintosh I-345): after the MenuInfo header (menuID,
| menuWidth, menuHeight, menuProc, menuEnable, menuData = the title),
| one entry per item: the text (Pascal string), then 4 bytes: icon
| number, command key, mark character, style; a 0 length byte ends the
| list. menuEnable: bit 0 = whole menu, bit n = item n (n <= 31).
| Items whose text starts with '-' are drawn as gray separator lines.
| Low memory: TopMenuItem ($B26) and AtMenuBottom ($B28) hold the
| scrolling state from one call to the next (mDrawMsg sets them up;
| Inside Macintosh V-249 gives the later addresses $A0A and $A0C);
| TESysJust ($BAC, low byte $BAD) < 0 draws items right to left.
|
| Sources: Apple's StandardMDEF.a (System 7.1 source; history and the
| 1985/86 lines with <27Sep85>, <11oct85>, <7Jan86> marks); Inside
| Macintosh I "The Menu Manager" (I-344..345, I-362..363) and V-248.
| -------------------------------------------------------------------------

| parameters and locals (see the banner)
.set MDEF_MESSAGE, 0x18                         | message (word)
.set MDEF_THEMENU, 0x14                         | theMenu (MenuHandle)
.set MDEF_MENURECT, 0x10                        | VAR menuRect (pointer)
.set MDEF_HITPT, 0xC                            | hitPt (Point)
.set MDEF_WHICHITEM, 0x8                        | VAR whichItem (pointer)
.set MDEF_ASCENT, -0x8                          | FontInfo.ascent
.set MDEF_DESCENT, -0x6                         | FontInfo.descent
.set MDEF_WIDMAX, -0x4                          | FontInfo.widMax (Chicago: -2)
.set MDEF_MFHEIGHT, -0x2                        | line height (leading+ascent+descent)

Resource_MDEF_0000:
| ROM resource header: a Memory Manager block header, as in front of
| the data of a handle. The relative handle locates the resource's
| master pointer in the ROM zone (INITRESOURCES_CONT_2): 0x54 + 4 *
| its index in the ROM map's reference lists.
Resource_MDEF_0000_Header:
    .long	0xC0000410                            | ROM resource header: tag $C0, physical size $410 (8 + $408)
    .long	0x00000094                            | relative handle: master pointer at ROM zone + $94
| ----------------------------------------------------------
| _MDEF_0_ -- entry point and standard defproc header
| ----------------------------------------------------------
_MDEF_0_:
    BRA.B	MDEF_ENTRY                            | skip the header
    .short	0x0000                               | flags word
    .long	0x4D444546                            | resource type 'MDEF'
    .short	0x0000                               | resource ID 0
    .short	0x0004                               | version 4 ("MacPlus")
| MDEF entry: dispatch on message type
MDEF_ENTRY:
    LINK	A6,#-0x8                               | 8 bytes local vars (FontInfo)
    MOVEM.L	D3-D7/A2-A4,-(SP)                   | save registers
    MOVEA.L	MDEF_THEMENU(A6),A3                 | A3 = theMenu (MenuHandle)
    MOVE.W	MDEF_MESSAGE(A6),D0                  | D0 = message
    BEQ.W	MDEF_DRAW_MSG                         | mDrawMsg (0) ->
    SUBQ.W	#0x1,D0                              | test for mChooseMsg (1)
    BNE.W	MDEF_SIZE_MSG                         | mSizeMsg (2) ->
| ----------------------------------------------------------
| mChooseMsg (1): hilite the enabled item under the mouse and
| return its number in whichItem (0 = none); if the mouse is
| above or below the menu and there is more to see, scroll the
| contents by one line first.
| D3 = item hilited on entry, D4 = TopMenuItem (pixels), D5 =
| hitPt, D7 = scroll distance, A2 = menuRect, A4 = @whichItem.
| ----------------------------------------------------------
    BSR.W	MDEF_SETUP_FONT                       | set up menu item drawing state
    MOVEA.L	MDEF_WHICHITEM(A6),A4               | A4 = whichItem ptr
    MOVE.W	(A4),D3                              | D3 = previously highlighted item
    CLR.W	(A4)                                  | clear current selection
    MOVEA.L	MDEF_MENURECT(A6),A2                | A2 = menuRect ptr
    MOVE.W	(TopMenuItem).W,D4                   | D4 = v of the top of item 1 (scroll position)
    MOVE.L	MDEF_HITPT(A6),D5                    | D5 = hitPt (mouse position)
    BEQ.W	MDEF_UPD_HILITE                       | (0,0): no position, just unhilite
    CLR.W	-(SP)                                 | space for result
    MOVE.L	D5,-(SP)                             | push hitPt
    MOVE.L	A2,-(SP)                             | push menuRect
    _PtInRect                                   | is mouse in menu?
    TST.B	(SP)+                                 | check result
    BNE.B	MDEF_FIND_ITEM                        | yes, find which item ->
    MOVE.W	MDEF_MFHEIGHT(A6),D7                 | D7 = scroll amount (line height)
    SWAP.W	D5                                   | D5.W = mouse v
    CMP.W	(A2),D5                               | mouse above menu rect top?
    BGE.B	MDEF_CHK_BELOW                        | no, check below ->
    ADD.W	D7,D4                                 | scroll down by a line: new TopMenuItem
    CMP.W	(A2),D4                               | would item 1 leave the menu's top?
    BGT.B	MDEF_UPD_HILITE                       | yes -> item 1 already shown, no scroll
| scroll the contents by D7 pixels (down if > 0), D4 = new TopMenuItem
MDEF_SCROLL:
    MOVE.W	D3,D0                                | D0 = old highlighted item
    BSR.W	MDEF_INVERT_ITEM                      | unhighlight old selection
    MOVE.W	D4,(TopMenuItem).W                   | new scroll position
    CLR.L	-(SP)                                 | space for NewRgn result
    _NewRgn                                     | update region (stays on the stack)
    MOVE.L	(SP),D6                              | D6 = update region
    CLR.L	-(SP)                                 | space for NewRgn result
    _NewRgn                                     | region for the saved clip (stays too)
    MOVE.L	A2,-(SP)                             | push menuRect
    CLR.W	-(SP)                                 | dH = 0 (vertical scroll only)
    MOVE.W	D7,-(SP)                             | dV = scroll amount
    MOVE.L	D6,-(SP)                             | updateRgn = the uncovered strip
    _ScrollRect                                 | scroll menu contents
    MOVE.L	(SP),-(SP)                           | the clip save region
    _GetClip                                    | save the current clip in it
    MOVE.L	D6,-(SP)                             | the update region
    _SetClip                                    | clip to the uncovered strip
    BSR.W	MDEF_DRAW_ALL                         | redraw the items (only the strip changes)
    MOVE.L	(SP),-(SP)                           | the saved clip
    _SetClip                                    | restore it
    _DisposeRgn                                 | dispose of the clip save region
    _DisposeRgn                                 | dispose of the update region
    BRA.B	MDEF_EXIT                             | -> exit
| mouse not above the menu: below it?
MDEF_CHK_BELOW:
    MOVE.W	0x4(A2),D0                           | D0 = menuRect.bottom
    CMP.W	D0,D5                                 | mouse below the menu?
    BLT.B	MDEF_UPD_HILITE                       | no (beside it) -> no item
    CMP.W	(AtMenuBottom).W,D0                   | last item's bottom already visible?
    BGE.B	MDEF_UPD_HILITE                       | yes -> nothing more below
    NEG.W	D7                                    | scroll up by a line
    ADD.W	D7,D4                                 | new TopMenuItem
    BRA.B	MDEF_SCROLL                           | -> perform scroll
| mouse in the menu: walk the items from TopMenuItem down to it
MDEF_FIND_ITEM:
    MOVE.W	D4,D2                                | D2 = top of item 1 (TopMenuItem)
    MOVEQ.L	#0x1,D4                             | D4 = item 1
MDEF_SCAN_ITEMS:
    MOVEA.L	(A3),A0                             | dereference MenuHandle
    MOVE.W	D4,D0                                | D0 = current item index
    BSR.W	MDEF_FIND_NTH                         | find item D0 in menu data
    BEQ.B	MDEF_UPD_HILITE                       | past last item ->
    BSR.B	MDEF_ITEM_HEIGHT                      | D0 = item height
    ADD.W	D0,D2                                 | D2 = bottom of this item
    CMP.W	MDEF_HITPT(A6),D2                     | below the mouse's v?
    BGT.B	MDEF_HITTEST                          | yes, mouse is on this item ->
    ADDQ.W	#0x1,D4                              | advance to next item
    BRA.B	MDEF_SCAN_ITEMS                       | continue scanning
| ----------------------------------------------------------
| MDEF_HITTEST - the mouse is on item D4: select it if enabled
| ----------------------------------------------------------
MDEF_HITTEST:
    BSR.B	MDEF_CHK_ENABLED                      | item D4 enabled?
    BEQ.B	MDEF_UPD_HILITE                       | no (disabled item or menu) -> none
    MOVE.W	D4,(A4)                              | store selected item number
| Called by: MDEF_ENTRY, MDEF_CHK_BELOW, MDEF_SCAN_ITEMS, MDEF_HITTEST
MDEF_UPD_HILITE:
    CMP.W	(A4),D3                               | same item as before?
    BEQ.B	MDEF_EXIT                             | yes, no change needed ->
    MOVE.W	D3,D0                                | unhighlight old item
    BSR.B	MDEF_INVERT_ITEM                      | invert previous item rect
    MOVE.W	(A4),D0                              | highlight new item
    BSR.B	MDEF_INVERT_ITEM                      | invert current item rect
| MDEF exit: strip Pascal parameters and return
MDEF_EXIT:
    MOVEM.L	(SP)+,D3-D7/A2-A4                   | restore registers
    UNLK	A6                                     | tear down stack frame
    MOVEA.L	(SP)+,A0                            | pop return address
    ADDA.W	#0x12,SP                             | strip 18 bytes of Pascal params
    JMP	(A0)                                    | return to caller
| ----------------------------------------------------------
| MDEF_SETUP_FONT (Apple: GetSizes): font metrics of the current
| font into the FontInfo record at -8(A6); widMax is reduced by 2
| for Chicago (widMax 14) and the leading field becomes the line
| height MFHeight = leading + ascent + descent.
| Out: D0 = ascent + descent. Changes D1-D2/A0-A2.
| Called by: MDEF_ENTRY, MDEF_DRAW_ALL, MDEF_SIZE_MSG
| ----------------------------------------------------------
MDEF_SETUP_FONT:
    LEA.L	MDEF_ASCENT(A6),A2                    | A2 = local FontInfo struct
    MOVE.L	A2,-(SP)                             | push FontInfo record pointer
    _GetFontInfo                                | fill ascent/descent/widMax/leading
    MOVE.W	(A2)+,D0                             | D0 = ascent
    ADD.W	(A2)+,D0                              | + descent = line height
    CMPI.W	#0xE,(A2)                            | widMax = 14 (Chicago)?
    BNE.B	MDEF_NOT_CHICAGO                      | no ->
    SUBQ.W	#0x2,(A2)                            | narrower mark/command columns for Chicago
MDEF_NOT_CHICAGO:
    ADDQ.W	#0x2,A2                              | A2 -> leading
    ADD.W	D0,(A2)                               | leading + ascent + descent = MFHeight
    RTS                                         | return from MDEF_SETUP_FONT
| ----------------------------------------------------------
| MDEF_ITEM_HEIGHT (Apple: GetItemHeight): height of an item.
| In:  A1 = the item's attribute bytes (icon number first).
| Out: D0 = MFHeight, or 36 if the item has an icon.
| Called by: MDEF_SCAN_ITEMS, MDEF_WALK_ITEMS, MDEF_MEASURE_LOOP
| ----------------------------------------------------------
MDEF_ITEM_HEIGHT:
    MOVE.W	MDEF_MFHEIGHT(A6),D0                 | D0 = normal line height
    TST.B	(A1)                                  | item has icon?
    BEQ.B	MDEF_GOT_HEIGHT                       | no, use text height ->
    MOVEQ.L	#0x24,D0                            | icon item height = 36 pixels
MDEF_GOT_HEIGHT:
    RTS                                         | return item height in D0
| ----------------------------------------------------------
| MDEF_CHK_ENABLED (Apple: EnableTest): is item D4 enabled?
| In:  D4 = item number, A3 = menu handle. Out: NE = enabled,
| EQ = disabled (item bit or menu bit 0 of menuEnable clear).
| Changes D0/A0.
| BUG: for items above 31 the branch skips the load of menuEnable
| and tests bit 0 of whatever D0 holds -- in mChooseMsg the item's
| height (16 with Chicago 12, 36 with an icon: even, so these items
| can never be chosen), in MDEF_DRAW_ALL whatever _DrawString or
| _TETextBox left (the trap dispatcher and _TextFace keep D0), which
| decides whether they are drawn gray. Apple's C466 (FJL 25Nov86,
| "Fixed ENABLETEST ... so enables items > 31 unless whole menu
| disabled") loads menuEnable before the test.
| Called by: MDEF_HITTEST, MDEF_RESET_FACE
| ----------------------------------------------------------
MDEF_CHK_ENABLED:
    CMPI.W	#0x1F,D4                             | item above 31 (no enable bit)?
    BGT.B	MDEF_TEST_MENU_BIT                    | yes -> menu bit only (D0 not loaded!)
    MOVEA.L	(A3),A0                             | dereference MenuHandle
    MOVE.L	menuEnable(A0),D0                    | D0 = enableFlags (32-bit mask)
    BTST	D4,D0                                  | test bit for item D4
    BEQ.B	MDEF_CHK_ENABLE                       | item disabled -> Z=1 (return false)
MDEF_TEST_MENU_BIT:
    BTST	#0x0,D0                                | test master enable bit (bit 0)
MDEF_CHK_ENABLE:
    RTS                                         | Z=1 if disabled, Z=0 if enabled
| ----------------------------------------------------------
| MDEF_INVERT_ITEM (Apple: InvertItem): hilite/unhilite an item by
| inverting its rect; with bit 15 of D0 set, gray it instead
| (MDEF_GRAY_ITEM; never a '-' separator).
| In:  D0 = item number (0 = none), A3 = menu handle. The rect is
| menuRect's width from the item's top (TopMenuItem plus the
| heights of the items above it) to its bottom, in TempRect.
| Changes D0-D2/A0-A1. (The item is found by a byte compare.)
| Called by: MDEF_SCROLL, MDEF_UPD_HILITE (2), MDEF_RESET_FACE
| ----------------------------------------------------------
MDEF_INVERT_ITEM:
    MOVEM.L	D3-D4,-(SP)                         | save working regs
    MOVE.W	D0,D3                                | D3 = target item number
    BEQ.B	MDEF_HILITE_RTS                       | item 0 = no item ->
    MOVE.W	(TopMenuItem).W,D2                   | D2 = top of item 1
    MOVEQ.L	#0x1,D4                             | D4 = item 1
MDEF_WALK_ITEMS:
    MOVE.W	D4,D0                                | D0 = item index for MDEF_FIND_NTH
    MOVEA.L	(A3),A0                             | A0 = dereferenced menu data
    BSR.W	MDEF_FIND_NTH                         | A0 = item text, A1 = its attributes
    BSR.B	MDEF_ITEM_HEIGHT                      | D0 = item height
    CMP.B	D3,D4                                 | reached target item?
    BEQ.B	MDEF_BUILD_RECT                       | yes ->
    ADD.W	D0,D2                                 | accumulate Y offset
    ADDQ.W	#0x1,D4                              | next item
    BRA.B	MDEF_WALK_ITEMS                       | loop to next item
| build the item's rect and invert it
MDEF_BUILD_RECT:
    MOVE.B	0x1(A0),D1                           | D1 = first character of the item text
    LEA.L	(TempRect).W,A0                       | A0 = TempRect
    MOVEA.L	MDEF_MENURECT(A6),A1                | A1 = menuRect ptr
    MOVE.L	(A1)+,(A0)                           | copy menuRect.topLeft
    MOVE.L	(A1),0x4(A0)                         | copy menuRect.botRight
    MOVE.W	D2,(A0)                              | rect.top = item Y
    ADD.W	D0,D2                                 | + item height
    MOVE.W	D2,0x4(A0)                           | rect.bottom = item Y + height
    TST.W	D3                                    | bit 15 set: gray instead?
    BMI.B	MDEF_DIM_ITEM                         | yes, draw disabled pattern ->
    MOVE.L	A0,-(SP)                             | push item rect
    _InvertRect                                 | toggle highlight
MDEF_HILITE_RTS:
    MOVEM.L	(SP)+,D3-D4                         | restore working regs
    RTS                                         | return from MDEF_INVERT_ITEM
| gray request: not for a separator line
MDEF_DIM_ITEM:
    CMPI.B	#0x2D,D1                             | separator line (text starts with '-')?
    BEQ.B	MDEF_HILITE_RTS                       | yes, don't dim separators ->
    BSR.W	MDEF_GRAY_ITEM                        | gray out disabled item
    BRA.B	MDEF_HILITE_RTS                       | -> restore regs and return
| ----------------------------------------------------------
| MDEF_TWEAKPOS (Apple: TweakPos): reserve a column of D0 pixels at
| the leading edge of the item -- the left edge (D5), or the right
| edge (D6) if TESysJust is negative (right-to-left scripts).
| In:  D0 = column width, D5 = left, D6 = right.
| Out: D2 = h where to draw in the column (left + 2, or the new
|      right edge), D5/D6 adjusted.
| Called by: MDEF_DRAW_MARK, MDEF_DRAW_TEXT
| ----------------------------------------------------------
MDEF_TWEAKPOS:
    MOVE.W	D5,D2                                | assume left to right: D2 = left ...
    ADDQ.W	#0x2,D2                              | ... + 2 (indent a little)
    ADD.W	D0,D5                                 | left edge past the column
    TST.B	(TESysJust_1).W                       | right-to-left script?
    BPL.B	MDEF_TWEAKPOS_RTS                     | no, normal LTR ->
    SUB.W	D0,D6                                 | RTL: the column at the right edge
    SUB.W	D0,D5                                 | undo the left edge
    MOVE.W	D6,D2                                | D2 = start of the column (new right)
MDEF_TWEAKPOS_RTS:
    RTS                                         | return from MDEF_TWEAKPOS
| ----------------------------------------------------------
| mDrawMsg (0): draw the whole menu, scrolled to its top
| ----------------------------------------------------------
MDEF_DRAW_MSG:
    MOVEA.L	MDEF_MENURECT(A6),A0                | A0 = menuRect ptr
    MOVE.W	(A0),(TopMenuItem).W                 | TopMenuItem = menuRect.top (not scrolled)
    BSR.B	MDEF_DRAW_ALL                         | draw all menu items
    BRA.W	MDEF_EXIT                             | -> MDEF exit
| MDEF_DRAW_ALL exit: all items drawn; D3 = baseline the next item
| would have
MDEF_AT_BOTTOM:
    SUB.W	MDEF_ASCENT(A6),D3                    | - ascent = bottom of the last item
    MOVE.W	D3,(AtMenuBottom).W                  | AtMenuBottom = it (for scrolling)
    MOVEM.L	(SP)+,D3-D6/A4                      | restore regs
    RTS                                         | return from MDEF_DRAW_ALL
| ----------------------------------------------------------
| MDEF_DRAW_ALL (Apple: DrawMenu): draw all items, item 1 at
| TopMenuItem, each line D3 = baseline, D5/D6 = left/right of the
| item (narrowed by the mark, icon and command key columns); sets
| AtMenuBottom. Items outside the clip (scrolled away) are drawn
| but do not show.
| Registers: D4 = item number, D7 = extra height of an icon item,
| A2 = item text, A4 = item attributes. Changes D0-D2/D7/A0-A2.
| Called by: MDEF_SCROLL, MDEF_DRAW_MSG
| ----------------------------------------------------------
MDEF_DRAW_ALL:
    MOVEM.L	D3-D6/A4,-(SP)                      | save regs
    BSR.W	MDEF_SETUP_FONT                       | set up font metrics
    MOVEQ.L	#0x1,D4                             | D4 = item 1
    MOVE.W	(TopMenuItem).W,D3                   | D3 = top of item 1
    ADD.W	MDEF_ASCENT(A6),D3                    | + font ascent = its baseline
| item draw loop
MDEF_DRAW_LOOP:
    MOVEA.L	MDEF_MENURECT(A6),A0                | A0 = menuRect ptr
    MOVE.L	(A0)+,D5                             | D5.W = menuRect.left
    MOVE.L	(A0),D6                              | D6.W = menuRect.right
    MOVE.W	D4,D0                                | D0 = item number
    MOVEA.L	(A3),A0                             | dereference MenuHandle
    BSR.W	MDEF_FIND_NTH                         | find item D0 -> A0=title, A1=attrs
    BEQ.B	MDEF_AT_BOTTOM                        | past last item ->
| prepare to draw this item
    MOVEA.L	A0,A2                               | A2 = item title ptr
    MOVEA.L	A1,A4                               | A4 = item attributes (icon,key,mark,style)
    MOVE.B	0x3(A4),D0                           | D0 = style byte (not used)
| check for separator line (title = '-')
    CMPI.B	#0x2D,0x1(A2)                        | first char = '-' (separator)?
    BEQ.W	MDEF_DRAW_SEP                         | yes, draw separator line ->
| check for icon
    MOVE.B	(A4),D0                              | D0 = icon number
    BEQ.B	MDEF_DRAW_MARK                        | no icon ->
    MOVEQ.L	#0x24,D0                            | icon item height = 36 pixels
    SUB.W	MDEF_MFHEIGHT(A6),D0                  | - text line height
    MOVE.W	D0,D7                                | D7 = extra height of the icon item
    LSR.W	#0x1,D0                               | half of it
    ADD.W	D0,D3                                 | lower the baseline: text centered by the icon
| draw mark character (checkmark, bullet, etc.)
MDEF_DRAW_MARK:
    MOVE.W	MDEF_WIDMAX(A6),D0                   | D0 = width of the mark column
    BSR.B	MDEF_TWEAKPOS                         | D2 = h of the mark, column reserved
    TST.B	0x2(A4)                               | has mark character?
    BEQ.B	MDEF_DRAW_TEXT                        | no ->
    MOVE.W	D2,-(SP)                             | push X position
    MOVE.W	D3,-(SP)                             | push Y position
    _MoveTo                                     | position pen
    CLR.W	D0                                    | zero-extend for DrawChar
    MOVE.B	0x2(A4),D0                           | D0 = mark character
    MOVE.W	D0,-(SP)                             | push character code
    _DrawChar                                   | draw the mark
| draw the icon, if any (Apple: CHKDRAWICON)
MDEF_DRAW_TEXT:
    TST.B	(A4)                                  | has icon?
    BEQ.B	MDEF_DRAW_KEY                         | no icon, skip to key equiv ->
    MOVEQ.L	#0x28,D0                            | icon column = 40 pixels
    BSR.W	MDEF_TWEAKPOS                         | D2 = h of the icon column
    LEA.L	(TempRect).W,A0                       | A0 = TempRect: the icon's rect
    MOVE.L	A0,-(SP)                             | push rect ptr for PlotIcon
    MOVE.W	D3,D1                                | D1 = text baseline Y
    MOVE.W	D7,D0                                | D0 = icon item's extra height
    LSR.W	#0x1,D0                               | halve for centering
    SUB.W	D0,D1                                 | undo the baseline offset
    SUB.W	MDEF_ASCENT(A6),D1                    | - ascent = top of the item
    ADDQ.W	#0x2,D1                              | + 2 pixel padding
    MOVE.W	D1,(A0)+                             | rect.top = icon top
    MOVE.W	D2,(A0)                              | rect.left = icon column ...
    ADDQ.W	#0x3,(A0)+                           | ... + 3 pixel indent
    MOVE.L	-0x4(A0),(A0)                        | botRight = topLeft
    ADDI.W	#0x20,(A0)+                          | icon rect bottom = top + 32
    ADDI.W	#0x20,(A0)                           | icon rect right = left + 32
    CLR.L	-(SP)                                 | space for handle
    MOVE.L	#0x49434F4E,-(SP)                    | 'ICON' resource type
    MOVE.W	#0x100,D0                            | icon base ID = 256
    MOVE.B	(A4),D0                              | + item icon number
    MOVE.W	D0,-(SP)                             | push ICON resource ID
    _GetResource                                | load icon (handle stays as PlotIcon's param)
    _PlotIcon                                   | draw it in the rect
| draw key equivalent (Cmd-key shortcut) if present
MDEF_DRAW_KEY:
    TST.B	0x1(A4)                               | has key equivalent?
    BEQ.B	MDEF_APPLY_STYLE                      | no ->
    MOVE.W	MDEF_WIDMAX(A6),D0                   | D0 = widMax
    ADD.W	D0,D0                                 | * 2: command mark and key
    SUB.W	D0,D6                                 | right edge in front of them
    MOVE.W	D6,-(SP)                             | push X: at the right (left to right)
| handle RTL text direction
    TST.B	(TESysJust_1).W                       | right-to-left?
    BPL.B	MDEF_KEY_MOVETO                       | no ->
    MOVE.W	D5,(SP)                              | RTL: use left edge
    ADDQ.W	#0x2,(SP)                            | + 2 pixel margin
    ADD.W	D0,D5                                 | adjust left margin
    ADD.W	D0,D6                                 | adjust right margin
MDEF_KEY_MOVETO:
    MOVE.W	D3,-(SP)                             | push Y
    _MoveTo                                     | position pen
    MOVE.W	#0x11,-(SP)                          | clover leaf char ($11 = Cmd symbol)
    _DrawChar                                   | draw Command symbol
    CLR.W	D0                                    | zero-extend for DrawChar
    MOVE.B	0x1(A4),D0                           | key equivalent character
    MOVE.W	D0,-(SP)                             | push character code
    _DrawChar                                   | draw the key character
    CLR.W	-(SP)                                 | push 0 = plain style
    _TextFace                                   | reset to plain face
| draw item title text with style
MDEF_APPLY_STYLE:
    CLR.W	D0                                    | zero-extend for TextFace
    MOVE.B	0x3(A4),D0                           | D0 = item text style
    MOVE.W	D0,-(SP)                             | push style bits
    _TextFace                                   | apply style (bold/italic/etc)
    MOVE.B	(TESysJust_1).W,D1                   | check script direction
    EXT.W	D1                                    | sign-extend to word
    BNE.B	MDEF_DRAW_RTL                         | RTL ->
| LTR: draw string left-to-right
    MOVE.W	D5,-(SP)                             | push X
    MOVE.W	D3,-(SP)                             | push Y
    _MoveTo                                     | position pen
    MOVE.L	A2,-(SP)                             | push item title string
    _DrawString                                 | draw it
    BRA.B	MDEF_RESET_FACE                       | -> finish item
| ----------------------------------------------------------
| MDEF_DRAW_RTL - draw the item text with TextBox, justified by
| TESysJust (D1), between D5 and D6
| ----------------------------------------------------------
MDEF_DRAW_RTL:
    LEA.L	(TempRect).W,A0                       | A0 = TempRect for TextBox
    SUBQ.W	#0x1,D5                              | TextBox indents by one
    MOVE.W	D3,(A0)                              | rect.top = baseline Y
    MOVE.W	MDEF_ASCENT(A6),D0                   | D0 = font ascent
    SUB.W	D0,(A0)+                              | rect.top -= ascent (align to top)
    MOVE.W	D5,(A0)+                             | rect.left = adjusted X
    MOVE.W	D3,(A0)                              | rect.bottom = baseline Y
    MOVE.W	MDEF_DESCENT(A6),D0                  | D0 = font descent
    ADD.W	D0,(A0)+                              | rect.bottom += descent
    MOVE.W	D6,(A0)                              | rect.right = right margin
    MOVEQ.L	#0x0,D0                             | clear high bytes
    MOVE.B	(A2)+,D0                             | D0 = string length byte
    MOVE.L	A2,-(SP)                             | push text pointer
    MOVE.L	D0,-(SP)                             | push text length
    PEA.L	(TempRect).W                          | push dest rect
    MOVE.W	D1,-(SP)                             | push justification (-1=RTL)
    _TETextBox                                  | draw RTL-justified text
MDEF_RESET_FACE:
    CLR.W	-(SP)                                 | push 0 = plain style
    _TextFace                                   | reset to plain text face
    BSR.W	MDEF_CHK_ENABLED                      | check if item D4 is enabled
    BNE.B	MDEF_CHK_ICON                         | enabled, skip dimming ->
    MOVE.W	D4,D0                                | D0 = item number
    ORI.W	#0x8000,D0                            | set bit 15 = disabled flag
    BSR.W	MDEF_INVERT_ITEM                      | dim the disabled item
MDEF_CHK_ICON:
    TST.B	(A4)                                  | has icon?
    BEQ.B	MDEF_NEXT_ITEM                        | no ->
    MOVE.W	D7,D0                                | D0 = icon item's extra height
    LSR.W	#0x1,D0                               | half of it ...
    SUB.W	D0,D7                                 | ... D7 = the other half
    ADD.W	D7,D3                                 | baseline down past the icon
MDEF_NEXT_ITEM:
    ADD.W	MDEF_MFHEIGHT(A6),D3                  | next baseline: + line height
    ADDQ.W	#0x1,D4                              | next item number
    BRA.W	MDEF_DRAW_LOOP                        | -> draw next item
| ----------------------------------------------------------
| MDEF_DRAW_SEP - a '-' item: a gray line across the middle of the
| item's line
| ----------------------------------------------------------
MDEF_DRAW_SEP:
    MOVEA.L	(A5),A0                             | A0 = QD globals ptr
    PEA.L	-0x18(A0)                             | push gray pattern address
    _PenPat                                     | set pen to gray for separator
    MOVE.W	D3,-(SP)                             | save current Y on stack
    MOVE.W	D5,-(SP)                             | push start X (left edge)
    MOVE.W	MDEF_MFHEIGHT(A6),D0                 | D0 = line height
    LSR.W	#0x1,D0                               | halve for vertical centering
    SUB.W	MDEF_ASCENT(A6),D0                    | - ascent = center offset
    ADD.W	D0,D3                                 | D3 = separator Y position
    MOVE.W	D3,-(SP)                             | push Y for MoveTo
    _MoveTo                                     | move pen to line start
    MOVE.W	D6,-(SP)                             | push end X (right edge)
    MOVE.W	D3,-(SP)                             | push Y for LineTo
    _LineTo                                     | draw gray separator line
    MOVE.W	(SP)+,D3                             | restore baseline Y
    _PenNormal                                  | reset pen to normal
    BRA.B	MDEF_CHK_ICON                         | -> check icon adjust, next item
| ----------------------------------------------------------
| MDEF_FIND_NTH (Apple: GetItemRecord) - find item D0 in menu data.
| In:  A0 = menu record, D0 = item number.
| Out: A0 = the item's text (Pascal string), A1 = its 4 attribute
|      bytes, NE; or A0 = A1 = D0 = 0 and EQ if there is no such
|      item. Changes D1.
| Called by: MDEF_SCAN_ITEMS, MDEF_WALK_ITEMS, MDEF_DRAW_LOOP, MDEF_SIZE_MSG
| ----------------------------------------------------------
MDEF_FIND_NTH:
    TST.W	D0                                    | item number <= 0?
    BLE.B	MDEF_NOT_FOUND                        | invalid item -> return null
    MOVEQ.L	#0x0,D1                             | clear length register
    LEA.L	menuData(A0),A1                       | A1 = menu title (past MenuInfo header)
    MOVE.B	(A1)+,D1                             | D1 = title string length
    ADDA.W	D1,A1                                | skip past menu title string
MDEF_WALK_LOOP:
    SUBQ.W	#0x1,D0                              | decrement item counter
    BEQ.B	MDEF_FOUND_ITEM                       | reached target item ->
    MOVE.B	(A1)+,D1                             | D1 = next item title length
    BEQ.B	MDEF_NOT_FOUND                        | zero = end of items -> null
    ADDQ.W	#0x4,D1                              | + 4 attribute bytes (icon,key,mark,style)
    ADDA.W	D1,A1                                | skip to next item
    BRA.B	MDEF_WALK_LOOP                        | continue walking items
| no such item
MDEF_NOT_FOUND:
    SUBA.L	A0,A0                                | A0 = nil (item not found)
    MOVEA.L	A0,A1                               | A1 = nil
    MOVE.L	A0,D0                                | D0 = 0, sets Z flag (not found)
    RTS                                         | return Z=1 (item not found)
| A1 points to the item (its length byte)
MDEF_FOUND_ITEM:
    TST.B	(A1)                                  | item title length = 0?
    BEQ.B	MDEF_NOT_FOUND                        | end of the list -> return null
    MOVEA.L	A1,A0                               | A0 = item title string ptr
    MOVE.B	(A1)+,D1                             | D1 = title length
    ADDA.W	D1,A1                                | A1 = item attributes (icon,key,mark,style)
    RTS                                         | return Z=0 (item found)
| ----------------------------------------------------------
| mSizeMsg (2) (Apple: DoCalcMsg): calculate menu width and height
| Measures all items in the WMgrPort and sets menuWidth/menuHeight.
| The height stops growing at the screen height minus the menu bar
| and 4 pixels (the menu then scrolls).
| D5 = maximum height, D6 = height (high word) / width (low word),
| D7 = width of the current item, A4 = the current item.
| ----------------------------------------------------------
MDEF_SIZE_MSG:
    SUBQ.W	#0x4,SP                              | space for the saved port
    MOVE.L	SP,-(SP)                             | push ptr to save slot on stack
    _GetPort                                    | save current port
    MOVE.L	(WMgrPort).W,-(SP)                   | the Window Manager port
    _SetPort                                    | switch to WMgr port (for font metrics)
    MOVEA.L	(WMgrPort).W,A0                     | A0 = WMgr GrafPort
    MOVE.W	0x14(A0),D5                          | D5 = portRect.bottom (screen height)
    TST.W	(ROM85).W                             | 64K ROM (no MBarHeight)?
    BMI.B	MDEF_DFLT_MBAR                        | yes -> the bar is 20 high
    SUB.W	(MBarHeight).W,D5                     | - menu bar height
    BNE.B	MDEF_MEASURE_INIT                     | (tests the difference, so practically always)
| (the Plus tests MBarHeight = 0 here and then uses 20)
MDEF_DFLT_MBAR:
    SUBI.W	#0x14,D5                             | - 20, the classic menu bar height
MDEF_MEASURE_INIT:
    SUBQ.W	#0x4,D5                              | - 4 pixels margin
    BSR.W	MDEF_SETUP_FONT                       | set up font metrics
    MOVEQ.L	#0x0,D6                             | D6 = max item width found so far
    MOVEQ.L	#0x1,D0                             | start with item 1
    MOVEA.L	(A3),A0                             | dereference MenuHandle
    BSR.B	MDEF_FIND_NTH                         | advance to first item's data
    BEQ.B	MDEF_STORE_SIZE                       | empty menu ->
    MOVEA.L	A0,A4                               | A4 = first item title ptr
| measure each item to find max width and total height
MDEF_MEASURE_LOOP:
    MOVEQ.L	#0x0,D7                             | D7 = this item's width accumulator
    MOVEA.L	(A3),A0                             | dereference MenuHandle (not used)
    MOVEQ.L	#0x0,D0                             | clear high bytes
    MOVE.B	(A4),D0                              | D0 = item title length
    BEQ.B	MDEF_END_MEASURE                      | zero = end of item list ->
    LEA.L	0x1(A4,D0.W),A1                       | A1 = item attributes (past title)
    BSR.W	MDEF_ITEM_HEIGHT                      | D0 = item height (text or icon)
    TST.B	(A1)                                  | has icon?
    BEQ.B	MDEF_NO_ICON_W                        | no ->
    MOVEQ.L	#0x28,D7                            | icon adds 40px to width
    MOVEQ.L	#0x24,D0                            | icon item height = 36 pixels
MDEF_NO_ICON_W:
    SWAP.W	D6                                   | D6.W = running total height
    ADD.W	D0,D6                                 | accumulate total height
    CMP.W	D5,D6                                 | exceeds max menu height?
    BLT.B	MDEF_CHK_MAXHT                        | no ->
    SUB.W	D0,D6                                 | undo: don't count this item
MDEF_CHK_MAXHT:
    SWAP.W	D6                                   | D6.lo = max width again
    MOVE.W	MDEF_WIDMAX(A6),D1                   | D1 = widMax (char cell width)
    ADD.W	D1,D7                                 | + mark column width
    TST.B	0x1(A1)                               | has key equivalent?
    BEQ.B	MDEF_NO_KEY_W                         | no ->
    ADD.W	D1,D7                                 | + Cmd symbol width
    ADD.W	D1,D7                                 | + key character width
    ADDQ.W	#0x8,D7                              | + 8px spacing for Cmd-key area
MDEF_NO_KEY_W:
    MOVEQ.L	#0x0,D1                             | clear high bytes
    MOVE.B	0x3(A1),D1                           | D1 = text style
    MOVE.W	D1,-(SP)                             | push style
    _TextFace                                   | apply item's text style
    CLR.W	-(SP)                                 | space for StringWidth result
    MOVE.L	A4,-(SP)                             | push item title string
    _StringWidth                                | measure title pixel width
    ADD.W	(SP)+,D7                              | D7 += title width
    CMP.W	D7,D6                                 | new width > current max?
    BGE.B	MDEF_UPD_MAXW                         | no, keep current max ->
    MOVE.W	D7,D6                                | update max width
MDEF_UPD_MAXW:
    MOVEQ.L	#0x0,D0                             | clear high bytes
    MOVE.B	(A4),D0                              | D0 = title length
    LEA.L	0x5(A4,D0.W),A4                       | A4 = next item (title+4 attrs+1 len)
    BRA.B	MDEF_MEASURE_LOOP                     | -> measure next item
| all items measured
MDEF_END_MEASURE:
    ADDQ.W	#0x4,D6                              | + 4px padding to max width
MDEF_STORE_SIZE:
    MOVEA.L	(A3),A0                             | dereference MenuHandle
    MOVE.W	D6,menuWidth(A0)                     | store menuWidth in MenuInfo
    SWAP.W	D6                                   | D6 = total height
    MOVE.W	D6,menuHeight(A0)                    | store menuHeight in MenuInfo
    CLR.W	-(SP)                                 | push 0 = plain style
    _TextFace                                   | reset text style
    _SetPort                                    | restore saved port
    BRA.W	MDEF_EXIT                             | -> MDEF exit
| ----------------------------------------------------------
| MDEF_GRAY_ITEM (Apple: GrayRect) - gray out a disabled item by
| painting the gray pattern in patBic mode over its rect.
| In:  A0 = the rect (TempRect). Changes D0-D2/A0-A1.
| Called by: MDEF_DIM_ITEM
| ----------------------------------------------------------
MDEF_GRAY_ITEM:
    MOVE.L	A0,-(SP)                             | push item rect for PaintRect
    MOVEA.L	(A5),A0                             | A0 = QD globals ptr
    PEA.L	-0x18(A0)                             | push gray pattern address
    _PenPat                                     | set pen to gray pattern
    MOVE.W	#0xB,-(SP)                           | patBic (11)
    _PenMode                                    | clear where the pattern is black
    _PaintRect                                  | paint gray over disabled item
    _PenNormal                                  | restore default pen state
    RTS                                         | return from MDEF_GRAY_ITEM

