| =========================================================================
| MDEF 0 -- the standard menu definition procedure ("TextMenuProc")
| =========================================================================
| Andy Hertzfeld's StandardMDEF.a (1982) as revised by EHB in 1985:
| variable-height system font (v3), ROM85 test (v4, the version word in
| the header: "version 4 = MacPlus" in Apple's list), international
| right-to-left display (v5, 27Sep85), icons, scrolling menus.
| The SE ROM has a version a few weeks newer (src/se/resources/
| resource_mdef_0000.s): it scrolls in pixels ("1/30/86 EHB Re-did
| scrolling so icons would work"), starts at menuRect.top, draws all
| items and tests items above 31 separately ("1/7/86 EHB"). This one:
|   - TopMenuItem is the number of the first visible item, AtMenuBottom
|     a flag (the last item has been drawn); a scroll moves the
|     contents by one line and redraws the whole menu;
|   - the items are placed from the bottom of the menu bar down
|     (MDEF_GET_MBARHT: MBarHeight, 20 on 64K ROMs), not from
|     menuRect.top -- menus hang from the menu bar;
|   - MDEF_DRAW_ALL stops at the bottom of menuRect;
|   - items above 31 have no enable bit of their own: BTST D4,D0 uses
|     D4 mod 32, so item 32 follows the menu's bit 0, item 33 item 1's
|     bit, and so on (the SE's version treats them separately).
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
| scrolling state from one call to the next (mDrawMsg sets them up);
| TESysJust ($BAC, low byte $BAD) < 0 draws items right to left.
|
| Apple's routine names (StandardMDEF.a): MDEF_SETUP_FONT = GetSizes,
| MDEF_ITEM_HEIGHT = GetItemHeight, MDEF_CHK_ENABLED = EnableTest,
| MDEF_INVERT_ITEM = InvertItem, MDEF_TWEAKPOS = TweakPos, MDEF_DRAW_ALL
| = DrawMenu, MDEF_FIND_NTH = GetItemRecord, MDEF_SIZE_MSG = DoCalcMsg,
| MDEF_GRAY_ITEM = GrayRect.
|
| Sources: Apple's StandardMDEF.a (System 7.1 source; history and the
| 1985 lines with <27Sep85>, <11oct85> marks); Inside Macintosh I "The
| Menu Manager" (I-344..345, I-362..363).
| -------------------------------------------------------------------------

| resource header
    ROM_RESOURCE MDEF_0                         | 8-byte resource header (include/romrsrc.inc)
_MDEF_0_:
        BRA.B   MDEF_ENTRY                      | skip resource header
  .byte 0x00,0x00                               | flags: unused
  .ascii "MDEF"                                 | resource type identifier
  .byte 0x00,0x00,0x00,0x04                     | resource ID = 0, version = 4

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

| MDEF entry: dispatch on message type
MDEF_ENTRY:
        LINK    A6,#-0x8                        | 8 bytes local vars (FontInfo)
        MOVEM.L D3-D7/A2-A4,-(SP)               | save registers
        MOVE.L  MDEF_THEMENU(A6),A3             | A3 = theMenu (MenuHandle)
        MOVE    MDEF_MESSAGE(A6),D0             | D0 = message
        BEQ     MDEF_DRAW_MSG                   | mDrawMsg (0) ->
        SUBQ.W  #0x1,D0                         | test for mChooseMsg (1)
        BNE     MDEF_SIZE_MSG                   | mSizeMsg (2) ->
| ----------------------------------------------------------
| mChooseMsg (1): hilite the enabled item under the mouse and
| return its number in whichItem (0 = none); if the mouse is
| above or below the menu and there is more to see, scroll the
| contents by one line first.
| D3 = item hilited on entry, D4 = TopMenuItem (an item number),
| D5 = hitPt, D7 = scroll distance, A2 = menuRect, A4 = @whichItem.
| ----------------------------------------------------------
        BSR     MDEF_SETUP_FONT                 | set up menu item drawing state
        MOVE.L  MDEF_WHICHITEM(A6),A4           | A4 = whichItem ptr
        MOVE    (A4),D3                         | D3 = previously highlighted item
        CLR     (A4)                            | clear current selection
        MOVE.L  MDEF_MENURECT(A6),A2            | A2 = menuRect ptr
        MOVE    (TopMenuItem).w,D4              | D4 = first visible item (scroll position)
        MOVE.L  MDEF_HITPT(A6),D5               | D5 = hitPt (mouse position)
        BEQ.B   MDEF_UPD_HILITE                 | (0,0): no position, just unhilite
| check if mouse is inside menuRect
        CLR     -(SP)                           | space for result
        MOVE.L  D5,-(SP)                        | push hitPt
        MOVE.L  A2,-(SP)                        | push menuRect
        _PtInRect                               | is mouse in menu?
        TST.B   (SP)+                           | check result
        BNE.B   MDEF_FIND_ITEM                  | yes, find which item ->
        MOVE    MDEF_MFHEIGHT(A6),D7            | D7 = scroll amount (line height)
        SWAP    D5                              | D5.W = mouse v
        CMP     (A2),D5                         | mouse above menu rect top?
        BGE.B   MDEF_CHK_BELOW                  | no, check below ->
        SUBQ.W  #0x1,D4                         | scroll up: one item earlier
        BLE.B   MDEF_UPD_HILITE                 | item 1 already at the top ->
| scroll the contents by D7 pixels (down if > 0), D4 = new TopMenuItem
MDEF_SCROLL:
        MOVE    D3,D0                           | D0 = old highlighted item
        BSR     MDEF_INVERT_ITEM                | unhighlight old selection
        MOVE    D4,(TopMenuItem).w              | update first visible item
        CLR.L   -(SP)                           | space for NewRgn result
        _NewRgn                                 | create update region
        MOVE.L  (SP),D0                         | D0 = update region (also left on the stack)
        MOVE.L  A2,-(SP)                        | push menuRect
        CLR     -(SP)                           | dH = 0 (vertical scroll only)
        MOVE    D7,-(SP)                        | dV = scroll amount
        MOVE.L  D0,-(SP)                        | push update region
        _ScrollRect                             | scroll menu contents
        _DisposeRgn                             | free update region (the copy on the stack)
        BSR     MDEF_DRAW_ALL                   | redraw the menu from the new top item
        BRA.B   MDEF_EXIT                       | -> exit

| ----------------------------------------------------------
| mouse not above the menu: below it?
MDEF_CHK_BELOW:
        CMP     0x4(A2),D5                      | mouse below menuRect.bottom?
        BLT.B   MDEF_UPD_HILITE                 | no (beside the menu) ->
        TST     (AtMenuBottom).w                | last item already shown?
        BNE.B   MDEF_UPD_HILITE                 | yes, can't scroll further ->
        NEG     D7                              | scroll the contents up
        ADDQ.W  #0x1,D4                         | one item later
        BRA.B   MDEF_SCROLL                     | -> perform scroll

| ----------------------------------------------------------
| mouse in the menu: walk the items from TopMenuItem (whose top is
| at MBarHeight) down to it
MDEF_FIND_ITEM:
        BSR.B   MDEF_GET_MBARHT                 | D0 = menu bar height = top of the first item
        MOVE    D0,D2                           | D2 = running Y position
MDEF_SCAN_ITEMS:
        MOVE.L  (A3),A0                         | dereference MenuHandle
        MOVE    D4,D0                           | D0 = current item index
        BSR     MDEF_FIND_NTH                   | find item D0 in menu data
        BEQ.B   MDEF_UPD_HILITE                 | past last item ->
        BSR.B   MDEF_ITEM_HEIGHT                | D0 = item height
        ADD     D0,D2                           | D2 = bottom of this item
        CMP     MDEF_HITPT(A6),D2               | below the mouse's v?
        BGT.B   MDEF_HITTEST                    | yes, mouse is on this item ->
        ADDQ.W  #0x1,D4                         | advance to next item
        BRA.B   MDEF_SCAN_ITEMS                 | continue scanning

| ----------------------------------------------------------
| MDEF_HITTEST - the mouse is on item D4: select it if enabled
| ----------------------------------------------------------
MDEF_HITTEST:
        BSR.B   MDEF_CHK_ENABLED                | item D4 enabled?
        BEQ.B   MDEF_UPD_HILITE                 | no (disabled item or menu) -> none
        MOVE    D4,(A4)                         | store selected item number
| update highlighting if selection changed
| Called by: MDEF_ENTRY, MDEF_CHK_BELOW, MDEF_SCAN_ITEMS, MDEF_HITTEST
MDEF_UPD_HILITE:
        CMP     (A4),D3                         | same item as before?
        BEQ.B   MDEF_EXIT                       | yes, no change needed ->
        MOVE    D3,D0                           | unhighlight old item
        BSR.B   MDEF_INVERT_ITEM                | invert previous item rect
        MOVE    (A4),D0                         | highlight new item
        BSR.B   MDEF_INVERT_ITEM                | invert current item rect
| MDEF exit: strip Pascal parameters and return
MDEF_EXIT:
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0x12,SP                        | strip 18 bytes of Pascal params
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
| MDEF_GET_MBARHT: the menu bar height, where the first visible
| item starts: MBarHeight, or 20 on a 64K ROM (ROM85 < 0) or if
| MBarHeight is 0.
| Out: D0 = height. Called by: MDEF_FIND_ITEM, MDEF_INVERT_ITEM,
| MDEF_DRAW_ALL, MDEF_SIZE_MSG
| ----------------------------------------------------------
MDEF_GET_MBARHT:
        TST     (ROM85).w                       | 64K ROM (no MBarHeight)?
        BMI.B   MDEF_DFLT_MBAR                  | yes, use default ->
        MOVE    (MBarHeight).w,D0               | get configurable menu bar height
        BNE.B   MDEF_GOT_MBAR                   | nonzero ->
MDEF_DFLT_MBAR:
        MOVE    #0x14,D0                        | default = 20 pixels
MDEF_GOT_MBAR:
        RTS                                     | return menu bar height in D0

| ----------------------------------------------------------
| MDEF_SETUP_FONT (Apple: GetSizes): font metrics of the current
| font into the FontInfo record at -8(A6); widMax is reduced by 2
| for Chicago (widMax 14) and the leading field becomes the line
| height MFHeight = leading + ascent + descent.
| Out: D0 = ascent + descent. Changes D1-D2/A0-A2.
| Called by: MDEF_ENTRY, MDEF_DRAW_ALL, MDEF_SIZE_MSG
| ----------------------------------------------------------
MDEF_SETUP_FONT:
        LEA.L   MDEF_ASCENT(A6),A2              | A2 = local FontInfo struct
        MOVE.L  A2,-(SP)                        | push FontInfo record pointer
        _GetFontInfo                            | fill ascent/descent/widMax/leading
        MOVE    (A2)+,D0                        | D0 = ascent
        ADD     (A2)+,D0                        | + descent = line height
        CMPI    #0xE,(A2)                       | widMax = 14 (Chicago)?
        BNE.B   MDEF_NOT_CHICAGO                | no ->
        SUBQ.W  #0x2,(A2)                       | narrower mark/command columns for Chicago
MDEF_NOT_CHICAGO:
        ADDQ.W  #0x2,A2                         | A2 -> leading
        ADD     D0,(A2)                         | leading + ascent + descent = MFHeight
        RTS                                     | return from MDEF_SETUP_FONT

| ----------------------------------------------------------
| MDEF_ITEM_HEIGHT (Apple: GetItemHeight): height of an item.
| In:  A1 = the item's attribute bytes (icon number first).
| Out: D0 = MFHeight, or 36 if the item has an icon.
| Called by: MDEF_SCAN_ITEMS, MDEF_WALK_ITEMS, MDEF_MEASURE_LOOP
| ----------------------------------------------------------
MDEF_ITEM_HEIGHT:
        MOVE    MDEF_MFHEIGHT(A6),D0            | D0 = normal line height
        TST.B   (A1)                            | item has icon?
        BEQ.B   MDEF_GOT_HEIGHT                 | no, use text height ->
        MOVEQ.L #0x24,D0                        | icon item height = 36 pixels
MDEF_GOT_HEIGHT:
        RTS                                     | return item height in D0

| ----------------------------------------------------------
| MDEF_CHK_ENABLED (Apple: EnableTest): is item D4 enabled?
| In:  D4 = item number, A3 = menu handle. Out: NE = enabled,
| EQ = disabled (item bit or menu bit 0 of menuEnable clear).
| Items above 31: BTST uses D4 mod 32 (see the banner).
| Changes D0/A0.
| Called by: MDEF_HITTEST, MDEF_RESET_FACE
| ----------------------------------------------------------
MDEF_CHK_ENABLED:
        MOVE.L  (A3),A0                         | dereference MenuHandle
        MOVE.L  menuEnable(A0),D0               | D0 = enableFlags (32-bit mask)
        BTST    D4,D0                           | test bit for item D4 (mod 32)
        BEQ.B   MDEF_CHK_ENABLE                 | item disabled -> Z=1 (return false)
        BTST    #0x0,D0                         | test master enable bit (bit 0)
MDEF_CHK_ENABLE:
        RTS                                     | Z=1 if disabled, Z=0 if enabled

| ----------------------------------------------------------
| MDEF_INVERT_ITEM (Apple: InvertItem): hilite/unhilite an item by
| inverting its rect; with bit 15 of D0 set, gray it instead
| (MDEF_GRAY_ITEM; never a '-' separator).
| In:  D0 = item number (0 = none), A3 = menu handle. The rect is
| menuRect's width from the item's top (MBarHeight plus the
| heights of the items from TopMenuItem on) to its bottom, in
| TempRect. Changes D0-D2/A0-A1. (The item is found by a byte
| compare.)
| Called by: MDEF_SCROLL, MDEF_UPD_HILITE (2), MDEF_RESET_FACE
| ----------------------------------------------------------
MDEF_INVERT_ITEM:
        MOVEM.L D3-D4,-(SP)                     | save working regs
        MOVE    D0,D3                           | D3 = target item number
        BEQ.B   MDEF_HILITE_RTS                 | item 0 = no item ->
        BSR.B   MDEF_GET_MBARHT                 | D0 = menu bar height = top of the first item
        MOVE    D0,D2                           | D2 = running Y position
| walk items from TopMenuItem to find target item's Y position
        MOVE    (TopMenuItem).w,D4              | D4 = first visible item
MDEF_WALK_ITEMS:
        MOVE    D4,D0                           | D0 = item index for MDEF_FIND_NTH
        MOVE.L  (A3),A0                         | A0 = dereferenced menu data
        BSR     MDEF_FIND_NTH                   | A0 = item text, A1 = its attributes
        BSR.B   MDEF_ITEM_HEIGHT                | D0 = item height
        CMP.B   D3,D4                           | reached target item?
        BEQ.B   MDEF_BUILD_RECT                 | yes ->
        ADD     D0,D2                           | accumulate Y offset
        ADDQ.W  #0x1,D4                         | next item
        BRA.B   MDEF_WALK_ITEMS                 | loop to next item
| build the item's rect and invert it
MDEF_BUILD_RECT:
        MOVE.B  0x1(A0),D1                      | D1 = first character of the item text
        LEA.L   (TempRect).w,A0                 | A0 = TempRect
        MOVE.L  MDEF_MENURECT(A6),A1            | A1 = menuRect ptr
        MOVE.L  (A1)+,(A0)                      | copy menuRect.topLeft
        MOVE.L  (A1),0x4(A0)                    | copy menuRect.botRight
        MOVE    D2,(A0)                         | rect.top = item Y
        ADD     D0,D2                           | + item height
        MOVE    D2,0x4(A0)                      | rect.bottom = item Y + height
        TST     D3                              | bit 15 set: gray instead?
        BMI.B   MDEF_DIM_ITEM                   | yes, draw disabled pattern ->
        MOVE.L  A0,-(SP)                        | push item rect
        _InvertRect                             | toggle highlight
MDEF_HILITE_RTS:
        MOVEM.L (SP)+,D3-D4                     | restore working regs
        RTS                                     | return from MDEF_INVERT_ITEM

| ----------------------------------------------------------
| gray request: not for a separator line
MDEF_DIM_ITEM:
        CMPI.B  #0x2D,D1                        | separator line (text starts with '-')?
        BEQ.B   MDEF_HILITE_RTS                 | yes, don't dim separators ->
        BSR     MDEF_GRAY_ITEM                  | gray out disabled item
        BRA.B   MDEF_HILITE_RTS                 | -> restore regs and return

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
        MOVE    D5,D2                           | assume left to right: D2 = left ...
        ADDQ.W  #0x2,D2                         | ... + 2 (indent a little)
        ADD     D0,D5                           | left edge past the column
        TST.B   (TESysJust_1).w                 | right-to-left script?
        BPL.B   MDEF_TWEAKPOS_RTS               | no, normal LTR ->
| RTL: the column goes at the right edge
        SUB     D0,D6                           | right edge in front of the column
        SUB     D0,D5                           | undo the left edge
        MOVE    D6,D2                           | D2 = start of the column (new right)
MDEF_TWEAKPOS_RTS:
        RTS                                     | return from MDEF_TWEAKPOS

| ----------------------------------------------------------
| mDrawMsg (0): draw the whole menu, from item 1
| ----------------------------------------------------------
MDEF_DRAW_MSG:
        MOVE    #0x1,(TopMenuItem).w            | start drawing from item 1 (not scrolled)
        BSR.B   MDEF_DRAW_ALL                   | draw all visible menu items
        BRA     MDEF_EXIT                       | -> MDEF exit
| MDEF_DRAW_ALL exit: all items drawn
MDEF_AT_BOTTOM:
        ST.B    (AtMenuBottom).w                | flag: the last item is visible
MDEF_DRAW_RTS:
        MOVEM.L (SP)+,D3-D4/A4                  | restore regs
        RTS                                     | return from MDEF_DRAW_ALL

| ----------------------------------------------------------
| MDEF_DRAW_ALL (Apple: DrawMenu): draw the items from TopMenuItem
| on, the first one at the bottom of the menu bar, each line D3 =
| baseline, D5/D6 = left/right of the item (narrowed by the mark,
| icon and command key columns); stops at the bottom of menuRect,
| or sets AtMenuBottom after the last item.
| Registers: D4 = item number, D7 = extra height of an icon item,
| A2 = item text, A4 = item attributes. Changes D0-D2/D5-D7/A0-A2.
| Called by: MDEF_SCROLL, MDEF_DRAW_MSG
| ----------------------------------------------------------
MDEF_DRAW_ALL:
        MOVEM.L D3-D4/A4,-(SP)                  | save regs
        CLR     (AtMenuBottom).w                | clear bottom-reached flag
        BSR     MDEF_SETUP_FONT                 | set up font metrics
        MOVE    (TopMenuItem).w,D4              | D4 = first visible item
        BSR     MDEF_GET_MBARHT                 | D0 = menu bar height = its top
        MOVE    D0,D3                           | D3 = current Y position
        ADD     MDEF_ASCENT(A6),D3              | + font ascent = its baseline
| item draw loop
MDEF_DRAW_LOOP:
        MOVE.L  MDEF_MENURECT(A6),A0            | A0 = menuRect ptr
        MOVE.L  (A0)+,D5                        | D5.W = menuRect.left
        MOVE    (A0)+,D2                        | D2 = menuRect.bottom
        MOVE    (A0),D6                         | D6 = menuRect.right
        MOVE    D4,D0                           | D0 = item number
        MOVE.L  (A3),A0                         | dereference MenuHandle
        BSR     MDEF_FIND_NTH                   | find item D0 -> A0=title, A1=attrs
        BEQ.B   MDEF_AT_BOTTOM                  | past last item ->
        CMP     D2,D3                           | baseline at or below menuRect.bottom?
        BGE.B   MDEF_DRAW_RTS                   | yes, stop drawing ->
| prepare to draw this item
        MOVE.L  A0,A2                           | A2 = item title ptr
        MOVE.L  A1,A4                           | A4 = item attributes (icon,key,mark,style)
        MOVE.B  0x3(A4),D0                      | D0 = style byte (not used)
| check for separator line (title = '-')
        CMPI.B  #0x2D,0x1(A2)                   | first char = '-' (separator)?
        BEQ     MDEF_DRAW_SEP                   | yes, draw separator line ->
| check for icon
        MOVE.B  (A4),D0                         | D0 = icon number
        BEQ.B   MDEF_DRAW_MARK                  | no icon ->
        MOVEQ.L #0x24,D0                        | icon item height = 36 pixels
        SUB     MDEF_MFHEIGHT(A6),D0            | - text line height
        MOVE    D0,D7                           | D7 = extra height of the icon item
        LSR     #0x1,D0                         | half of it
        ADD     D0,D3                           | lower the baseline: text centered by the icon
| draw mark character (checkmark, bullet, etc.)
MDEF_DRAW_MARK:
        MOVE    MDEF_WIDMAX(A6),D0              | D0 = width of the mark column
        BSR     MDEF_TWEAKPOS                   | D2 = h of the mark, column reserved
        TST.B   0x2(A4)                         | has mark character?
        BEQ.B   MDEF_DRAW_TEXT                  | no ->
        MOVE    D2,-(SP)                        | push X position
        MOVE    D3,-(SP)                        | push Y position
        _MoveTo                                 | position pen
        CLR     D0                              | zero-extend for DrawChar
        MOVE.B  0x2(A4),D0                      | D0 = mark character
        MOVE    D0,-(SP)                        | push character code
        _DrawChar                               | draw the mark
| draw the icon, if any (Apple: CHKDRAWICON)
MDEF_DRAW_TEXT:
        TST.B   (A4)                            | has icon?
        BEQ.B   MDEF_DRAW_KEY                   | no icon, skip to key equiv ->
        MOVEQ.L #0x28,D0                        | icon column = 40 pixels
        BSR     MDEF_TWEAKPOS                   | D2 = h of the icon column
        LEA.L   (TempRect).w,A0                 | A0 = TempRect: the icon's rect
        MOVE.L  A0,-(SP)                        | push rect ptr for PlotIcon
        MOVE    D3,D1                           | D1 = text baseline Y
        MOVE    D7,D0                           | D0 = icon item's extra height
        LSR     #0x1,D0                         | halve for centering
        SUB     D0,D1                           | undo the baseline offset
        SUB     MDEF_ASCENT(A6),D1              | - ascent = top of the item
        ADDQ.W  #0x2,D1                         | + 2 pixel padding
        MOVE    D1,(A0)+                        | rect.top = icon top
        MOVE    D2,(A0)                         | rect.left = icon column ...
        ADDQ.W  #0x3,(A0)+                      | ... + 3 pixel indent
        MOVE.L  -0x4(A0),(A0)                   | botRight = topLeft
        ADDI    #0x20,(A0)+                     | icon rect bottom = top + 32
        ADDI    #0x20,(A0)                      | icon rect right = left + 32
        CLR.L   -(SP)                           | space for handle
        MOVE.L  #0x49434F4E,-(SP)               | 'ICON' resource type
        MOVE    #0x100,D0                       | icon base ID = 256
        MOVE.B  (A4),D0                         | + item icon number
        MOVE    D0,-(SP)                        | push ICON resource ID
        _GetResource                            | load icon (handle stays as PlotIcon's param)
        _PlotIcon                               | draw it in the rect
| draw key equivalent (Cmd-key shortcut) if present
MDEF_DRAW_KEY:
        TST.B   0x1(A4)                         | has key equivalent?
        BEQ.B   MDEF_APPLY_STYLE                | no ->
        MOVE    MDEF_WIDMAX(A6),D0              | D0 = widMax
        ADD     D0,D0                           | * 2: command mark and key
        SUB     D0,D6                           | right edge in front of them
        MOVE    D6,-(SP)                        | push X: at the right (left to right)
| handle RTL text direction
        TST.B   (TESysJust_1).w                 | right-to-left?
        BPL.B   MDEF_KEY_MOVETO                 | no ->
        MOVE    D5,(SP)                         | RTL: use left edge
        ADDQ.W  #0x2,(SP)                       | + 2 pixel margin
        ADD     D0,D5                           | adjust left margin
        ADD     D0,D6                           | adjust right margin
MDEF_KEY_MOVETO:
        MOVE    D3,-(SP)                        | push Y
        _MoveTo                                 | position pen
        MOVE    #0x11,-(SP)                     | clover leaf char ($11 = Cmd symbol)
        _DrawChar                               | draw Command symbol
        CLR     D0                              | zero-extend for DrawChar
        MOVE.B  0x1(A4),D0                      | key equivalent character
        MOVE    D0,-(SP)                        | push character code
        _DrawChar                               | draw the key character
        CLR     -(SP)                           | push 0 = plain style
        _TextFace                               | reset to plain face
| draw item title text with style
MDEF_APPLY_STYLE:
        CLR     D0                              | zero-extend for TextFace
        MOVE.B  0x3(A4),D0                      | D0 = item text style
        MOVE    D0,-(SP)                        | push style bits
        _TextFace                               | apply style (bold/italic/etc)
        MOVE.B  (TESysJust_1).w,D1              | check script direction
        EXT     D1                              | sign-extend to word
        BNE.B   MDEF_DRAW_RTL                   | RTL ->
| LTR: draw string left-to-right
        MOVE    D5,-(SP)                        | push X
        MOVE    D3,-(SP)                        | push Y
        _MoveTo                                 | position pen
        MOVE.L  A2,-(SP)                        | push item title string
        _DrawString                             | draw it
        BRA.B   MDEF_RESET_FACE                 | -> finish item

| ----------------------------------------------------------
| MDEF_DRAW_RTL - draw the item text with TextBox, justified by
| TESysJust (D1), between D5 and D6
| ----------------------------------------------------------
MDEF_DRAW_RTL:
        LEA.L   (TempRect).w,A0                 | A0 = TempRect for TextBox
        SUBQ.W  #0x1,D5                         | TextBox indents by one
        MOVE    D3,(A0)                         | rect.top = baseline Y
        MOVE    MDEF_ASCENT(A6),D0              | D0 = font ascent
        SUB     D0,(A0)+                        | rect.top -= ascent (align to top)
        MOVE    D5,(A0)+                        | rect.left = adjusted X
        MOVE    D3,(A0)                         | rect.bottom = baseline Y
        MOVE    MDEF_DESCENT(A6),D0             | D0 = font descent
        ADD     D0,(A0)+                        | rect.bottom += descent
        MOVE    D6,(A0)                         | rect.right = right margin
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A2)+,D0                        | D0 = string length byte
        MOVE.L  A2,-(SP)                        | push text pointer
        MOVE.L  D0,-(SP)                        | push text length
        PEA.L   (TempRect).w                    | push dest rect
        MOVE    D1,-(SP)                        | push justification (-1=RTL)
        _TETextBox                              | draw RTL-justified text
MDEF_RESET_FACE:
        CLR     -(SP)                           | push 0 = plain style
        _TextFace                               | reset to plain text face
        BSR     MDEF_CHK_ENABLED                | check if item D4 is enabled
        BNE.B   MDEF_CHK_ICON                   | enabled, skip dimming ->
        MOVE    D4,D0                           | D0 = item number
        ORI     #-0x8000,D0                     | set bit 15 = disabled flag
        BSR     MDEF_INVERT_ITEM                | dim the disabled item
MDEF_CHK_ICON:
        TST.B   (A4)                            | has icon?
        BEQ.B   MDEF_NEXT_ITEM                  | no ->
        MOVE    D7,D0                           | D0 = icon item's extra height
        LSR     #0x1,D0                         | half of it ...
        SUB     D0,D7                           | ... D7 = the other half
        ADD     D7,D3                           | baseline down past the icon
MDEF_NEXT_ITEM:
        ADD     MDEF_MFHEIGHT(A6),D3            | next baseline: + line height
        ADDQ.W  #0x1,D4                         | next item number
        BRA     MDEF_DRAW_LOOP                  | -> draw next item

| ----------------------------------------------------------
| MDEF_DRAW_SEP - a '-' item: a gray line across the middle of the
| item's line
| ----------------------------------------------------------
MDEF_DRAW_SEP:
        MOVE.L  (A5),A0                         | A0 = QD globals ptr
        PEA.L   GRAY(A0)                        | push gray pattern address
        _PenPat                                 | set pen to gray for separator
        MOVE    D3,-(SP)                        | save current Y on stack
        MOVE    D5,-(SP)                        | push start X (left edge)
        MOVE    MDEF_MFHEIGHT(A6),D0            | D0 = line height
        LSR     #0x1,D0                         | halve for vertical centering
        SUB     MDEF_ASCENT(A6),D0              | - ascent = center offset
        ADD     D0,D3                           | D3 = separator Y position
        MOVE    D3,-(SP)                        | push Y for MoveTo
        _MoveTo                                 | move pen to line start
        MOVE    D6,-(SP)                        | push end X (right edge)
        MOVE    D3,-(SP)                        | push Y for LineTo
        _LineTo                                 | draw gray separator line
        MOVE    (SP)+,D3                        | restore baseline Y
        _PenNormal                              | reset pen to normal
        BRA.B   MDEF_CHK_ICON                   | -> check icon adjust, next item

| ----------------------------------------------------------
| MDEF_FIND_NTH (Apple: GetItemRecord) - find item D0 in menu data.
| In:  A0 = menu record, D0 = item number.
| Out: A0 = the item's text (Pascal string), A1 = its 4 attribute
|      bytes, NE; or A0 = A1 = D0 = 0 and EQ if there is no such
|      item. Changes D1.
| Called by: MDEF_SCAN_ITEMS, MDEF_WALK_ITEMS, MDEF_DRAW_LOOP, MDEF_SIZE_MSG
| ----------------------------------------------------------
MDEF_FIND_NTH:
        TST     D0                              | item number <= 0?
        BLE.B   MDEF_NOT_FOUND                  | invalid item -> return null
        MOVEQ.L #0x0,D1                         | clear length register
        LEA.L   menuData(A0),A1                 | A1 = menu title (past MenuInfo header)
        MOVE.B  (A1)+,D1                        | D1 = title string length
        ADDA    D1,A1                           | skip past menu title string
MDEF_WALK_LOOP:
        SUBQ.W  #0x1,D0                         | decrement item counter
        BEQ.B   MDEF_FOUND_ITEM                 | reached target item ->
        MOVE.B  (A1)+,D1                        | D1 = next item title length
        BEQ.B   MDEF_NOT_FOUND                  | zero = end of items -> null
        ADDQ.W  #0x4,D1                         | + 4 attribute bytes (icon,key,mark,style)
        ADDA    D1,A1                           | skip to next item
        BRA.B   MDEF_WALK_LOOP                  | continue walking items

| ----------------------------------------------------------
| no such item
MDEF_NOT_FOUND:
        SUBA.L  A0,A0                           | A0 = nil (item not found)
        MOVE.L  A0,A1                           | A1 = nil
        MOVE.L  A0,D0                           | D0 = 0, sets Z flag (not found)
        RTS                                     | return Z=1 (item not found)

| ----------------------------------------------------------
| A1 points to the item (its length byte)
MDEF_FOUND_ITEM:
        TST.B   (A1)                            | item title length = 0?
        BEQ.B   MDEF_NOT_FOUND                  | end of the list -> return null
        MOVE.L  A1,A0                           | A0 = item title string ptr
        MOVE.B  (A1)+,D1                        | D1 = title length
        ADDA    D1,A1                           | A1 = item attributes (icon,key,mark,style)
        RTS                                     | return Z=0 (item found)

| ----------------------------------------------------------
| mSizeMsg (2) (Apple: DoCalcMsg): calculate menu width and height
| Measures all items in the WMgrPort and sets menuWidth/menuHeight.
| The height stops growing at the screen height minus the menu bar
| and 4 pixels (the menu then scrolls).
| D5 = maximum height, D6 = height (high word) / width (low word),
| D7 = width of the current item, A4 = the current item.
| ----------------------------------------------------------
MDEF_SIZE_MSG:
        SUBQ.W  #0x4,SP                         | save space for GetPort result
        MOVE.L  SP,-(SP)                        | push ptr to save slot on stack
        _GetPort                                | save current port
        MOVE.L  (WMgrPort).w,-(SP)              | push WMgrPort for SetPort
        _SetPort                                | switch to WMgr port (for font metrics)
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr GrafPort
        MOVE    PORTRECT+BOTTOM(A0),D5          | D5 = portRect.bottom (screen height)
        BSR     MDEF_GET_MBARHT                 | D0 = menu bar height
        SUB     D0,D5                           | D5 = max menu height (screen - menubar)
        SUBQ.W  #0x4,D5                         | - 4 pixels margin
        BSR     MDEF_SETUP_FONT                 | set up font metrics
        MOVEQ.L #0x0,D6                         | D6 = max item width found so far
        MOVEQ.L #0x1,D0                         | start with item 1
        MOVE.L  (A3),A0                         | dereference MenuHandle
        BSR.B   MDEF_FIND_NTH                   | advance to first item's data
        BEQ.B   MDEF_STORE_SIZE                 | empty menu ->
        MOVE.L  A0,A4                           | A4 = first item title ptr
| measure each item to find max width and total height
MDEF_MEASURE_LOOP:
        MOVEQ.L #0x0,D7                         | D7 = this item's width accumulator
        MOVE.L  (A3),A0                         | dereference MenuHandle (not used)
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A4),D0                         | D0 = item title length
        BEQ.B   MDEF_END_MEASURE                | zero = end of item list ->
        LEA.L   0x1(A4,D0.W),A1                 | A1 = item attributes (past title)
        BSR     MDEF_ITEM_HEIGHT                | D0 = item height (text or icon)
        TST.B   (A1)                            | has icon?
        BEQ.B   MDEF_NO_ICON_W                  | no ->
        MOVEQ.L #0x28,D7                        | icon adds 40px to width
        MOVEQ.L #0x24,D0                        | icon item height = 36 pixels
MDEF_NO_ICON_W:
        SWAP    D6                              | D6.W = running total height
        ADD     D0,D6                           | accumulate total height
        CMP     D5,D6                           | exceeds max menu height?
        BLT.B   MDEF_CHK_MAXHT                  | no ->
        SUB     D0,D6                           | undo: don't count this item
MDEF_CHK_MAXHT:
        SWAP    D6                              | D6.lo = max width again
        MOVE    MDEF_WIDMAX(A6),D1              | D1 = widMax (char cell width)
        ADD     D1,D7                           | + mark column width
        TST.B   0x1(A1)                         | has key equivalent?
        BEQ.B   MDEF_NO_KEY_W                   | no ->
        ADD     D1,D7                           | + Cmd symbol width
        ADD     D1,D7                           | + key character width
        ADDQ.W  #0x8,D7                         | + 8px spacing for Cmd-key area
MDEF_NO_KEY_W:
        MOVEQ.L #0x0,D1                         | clear high bytes
        MOVE.B  0x3(A1),D1                      | D1 = text style
        MOVE    D1,-(SP)                        | push style
        _TextFace                               | apply item's text style
        CLR     -(SP)                           | space for StringWidth result
        MOVE.L  A4,-(SP)                        | push item title string
        _StringWidth                            | measure title pixel width
        ADD     (SP)+,D7                        | D7 += title width
        CMP     D7,D6                           | new width > current max?
        BGE.B   MDEF_UPD_MAXW                   | no, keep current max ->
        MOVE    D7,D6                           | update max width
MDEF_UPD_MAXW:
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A4),D0                         | D0 = title length
        LEA.L   0x5(A4,D0.W),A4                 | A4 = next item (title+4 attrs+1 len)
        BRA.B   MDEF_MEASURE_LOOP               | -> measure next item

| ----------------------------------------------------------
| all items measured
MDEF_END_MEASURE:
        ADDQ.W  #0x4,D6                         | + 4px padding to max width
MDEF_STORE_SIZE:
        MOVE.L  (A3),A0                         | dereference MenuHandle
        MOVE    D6,menuWidth(A0)                | store menuWidth in MenuInfo
        SWAP    D6                              | D6 = total height
        MOVE    D6,menuHeight(A0)               | store menuHeight in MenuInfo
        CLR     -(SP)                           | push 0 = plain style
        _TextFace                               | reset text style
        _SetPort                                | restore saved port
        BRA     MDEF_EXIT                       | -> MDEF exit

| ----------------------------------------------------------
| MDEF_GRAY_ITEM (Apple: GrayRect) - gray out a disabled item by
| painting the gray pattern in patBic mode over its rect.
| In:  A0 = the rect (TempRect). Changes D0-D2/A0-A1.
| Called by: MDEF_DIM_ITEM
| ----------------------------------------------------------
MDEF_GRAY_ITEM:
        MOVE.L  A0,-(SP)                        | push item rect for PaintRect
        MOVE.L  (A5),A0                         | A0 = QD globals ptr
        PEA.L   GRAY(A0)                        | push gray pattern address
        _PenPat                                 | set pen to gray pattern
        MOVE    #0xB,-(SP)                      | patBic (11)
        _PenMode                                | clear where the pattern is black
        _PaintRect                              | paint gray over disabled item
        _PenNormal                              | restore default pen state
        RTS                                     | return from MDEF_GRAY_ITEM
    ROM_RESOURCE_END MDEF_0                     | end of the data: pads to even, sets the sizes

| end of resource : 'MDEF' 0

