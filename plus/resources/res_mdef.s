| MDEF 0 - Standard menu definition procedure
| resource : 'MDEF' 0
|
| Handles all standard menu rendering and item tracking:
| mDrawMsg (0): draw the entire menu contents
| mChooseMsg (1): track mouse and highlight items
| mSizeMsg (2): calculate menu dimensions
|
| Pascal calling convention:
| procedure MDEF(message: INTEGER; theMenu: MenuHandle;
| VAR menuRect: Rect; hitPt: Point; VAR whichItem: INTEGER);
|
| Stack frame (A6-relative):
| $18(A6) = message (INTEGER)
| $14(A6) = theMenu (MenuHandle, A3)
| $10(A6) = menuRect ptr (A2)
| $0C(A6) = hitPt (Point)
| $08(A6) = whichItem ptr (A4)
|
MDEF_RSRC_HDR:
        BRA.B   MDEF_ENTRY                      | skip resource header
  .byte 0x00,0x00                               | flags: unused
  .ascii "MDEF"                                 | resource type identifier
  .byte 0x00,0x00,0x00,0x04                     | resource ID = 0, version = 4
| MDEF entry: dispatch on message type
MDEF_ENTRY:
        LINK    A6,#-0x8                        | 8 bytes local vars
        MOVEM.L D3-D7/A2-A4,-(SP)               | save registers
        MOVE.L  0x14(A6),A3                     | A3 = theMenu (MenuHandle)
        MOVE    0x18(A6),D0                     | D0 = message
        BEQ     MDEF_DRAW_MSG                   | mDrawMsg (0) ->
        SUBQ.W  #0x1,D0                         | test for mChooseMsg (1)
        BNE     MDEF_SIZE_MSG                   | mSizeMsg (2) ->
| mChooseMsg (1): track mouse position and highlight items
        BSR     MDEF_SETUP_FONT                 | set up menu item drawing state
        MOVE.L  0x8(A6),A4                      | A4 = whichItem ptr
        MOVE    (A4),D3                         | D3 = previously highlighted item
        CLR     (A4)                            | clear current selection
        MOVE.L  0x10(A6),A2                     | A2 = menuRect ptr
        MOVE    (TopMenuItem).w,D4              | D4 = first visible item (for scrolling menus)
        MOVE.L  0xC(A6),D5                      | D5 = hitPt (mouse position)
        BEQ.B   MDEF_UPD_HILITE                 | no mouse position ->
| check if mouse is inside menuRect
        CLR     -(SP)                           | space for result
        MOVE.L  D5,-(SP)                        | push hitPt
        MOVE.L  A2,-(SP)                        | push menuRect
        _PtInRect                               | is mouse in menu?
        TST.B   (SP)+                           | check result
        BNE.B   MDEF_FIND_ITEM                  | yes, find which item ->
        MOVE    -0x2(A6),D7                     | D7 = scroll amount (line height)
        SWAP    D5                              | D5.hi = mouse V coordinate
        CMP     (A2),D5                         | mouse above menu rect top?
        BGE.B   MDEF_CHK_BELOW                  | no, check below ->
        SUBQ.W  #0x1,D4                         | scroll up: decrement top item
        BLE.B   MDEF_UPD_HILITE                 | already at first item ->
MDEF_SCROLL:
        MOVE    D3,D0                           | D0 = old highlighted item
        BSR     MDEF_INVERT_ITEM                | unhighlight old selection
        MOVE    D4,(TopMenuItem).w              | update first visible item
        CLR.L   -(SP)                           | space for NewRgn result
        _NewRgn                                 | create update region
        MOVE.L  (SP),D0                         | D0 = update region handle
        MOVE.L  A2,-(SP)                        | push menuRect
        CLR     -(SP)                           | dH = 0 (vertical scroll only)
        MOVE    D7,-(SP)                        | dV = scroll amount
        MOVE.L  D0,-(SP)                        | push update region
        _ScrollRect                             | scroll menu contents
        _DisposeRgn                             | free update region
        BSR     MDEF_DRAW_ALL                   | redraw newly exposed items
        BRA.B   MDEF_EXIT                       | -> exit

| ----------------------------------------------------------
|
| MDEF_CHK_BELOW
|
MDEF_CHK_BELOW:
        CMP     0x4(A2),D5                      | mouse below menuRect.bottom?
        BLT.B   MDEF_UPD_HILITE                 | no, inside menu bounds ->
        TST     (AtMenuBottom).w                | already at last item?
        BNE.B   MDEF_UPD_HILITE                 | yes, can't scroll further ->
        NEG     D7                              | negate scroll direction (scroll down)
        ADDQ.W  #0x1,D4                         | scroll down: increment top item
        BRA.B   MDEF_SCROLL                     | -> perform scroll

| ----------------------------------------------------------
|
| MDEF_FIND_ITEM
|
MDEF_FIND_ITEM:
        BSR.B   MDEF_GET_MBARHT                 | D0 = menu bar height (initial Y)
        MOVE    D0,D2                           | D2 = running Y position
MDEF_SCAN_ITEMS:
        MOVE.L  (A3),A0                         | dereference MenuHandle
        MOVE    D4,D0                           | D0 = current item index
        BSR     MDEF_FIND_NTH                   | find item D0 in menu data
        BEQ.B   MDEF_UPD_HILITE                 | past last item ->
        BSR.B   MDEF_ITEM_HEIGHT                | D0 = item height
        ADD     D0,D2                           | D2 += item height
        CMP     0xC(A6),D2                      | past mouse V position?
        BGT.B   MDEF_HITTEST                    | yes, mouse is on this item ->
        ADDQ.W  #0x1,D4                         | advance to next item
        BRA.B   MDEF_SCAN_ITEMS                 | continue scanning

| ----------------------------------------------------------
|
| MDEF_HITTEST
|
| mChooseMsg: hit-test current item under mouse
MDEF_HITTEST:
        BSR.B   MDEF_CHK_ENABLED                | find item under mouse -> D4
        BEQ.B   MDEF_UPD_HILITE                 | no item (disabled/separator) ->
        MOVE    D4,(A4)                         | store selected item number
| update highlighting if selection changed
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
|
| MDEF_GET_MBARHT: get menu bar height (20 pixels default)
|
MDEF_GET_MBARHT:
        TST     (ROM85).w                       | Color QuickDraw present?
        BMI.B   MDEF_DFLT_MBAR                  | no, use default ->
        MOVE    (MBarHeight).w,D0               | get configurable menu bar height
        BNE.B   MDEF_GOT_MBAR                   | nonzero ->
MDEF_DFLT_MBAR:
        MOVE    #0x14,D0                        | default = 20 pixels
MDEF_GOT_MBAR:
        RTS                                     | return menu bar height in D0

| ----------------------------------------------------------
|
| MDEF_SETUP_FONT: set up font metrics for menu item drawing
| Returns: D0 = line height (ascent+descent), local vars filled
|
MDEF_SETUP_FONT:
        LEA.L   -0x8(A6),A2                     | A2 = local FontInfo struct
        MOVE.L  A2,-(SP)                        | push FontInfo record pointer
        _GetFontInfo                            | fill ascent/descent/widMax/leading
        MOVE    (A2)+,D0                        | D0 = ascent
        ADD     (A2)+,D0                        | + descent = line height
        CMPI    #0xE,(A2)                       | leading = 14? (Chicago font quirk)
        BNE.B   MDEF_SKIP_LEAD                  | no ->
        SUBQ.W  #0x2,(A2)                       | reduce leading by 2 for tighter spacing
MDEF_SKIP_LEAD:
        ADDQ.W  #0x2,A2                         | skip leading, A2 -> widMax
        ADD     D0,(A2)                         | widMax += line height (total cell height)
        RTS                                     | return line height in D0

| MDEF_ITEM_HEIGHT -- d0 = item height.
| ----------------------------------------------------------
|
| MDEF_ITEM_HEIGHT
|
MDEF_ITEM_HEIGHT:
        MOVE    -0x2(A6),D0                     | D0 = normal line height
        TST.B   (A1)                            | item has icon?
        BEQ.B   MDEF_GOT_HEIGHT                 | no, use text height ->
        MOVEQ.L #0x24,D0                        | icon item height = 36 pixels
MDEF_GOT_HEIGHT:
        RTS                                     | return item height in D0

| MDEF_CHK_ENABLED -- find item under mouse -> D4.
| ----------------------------------------------------------
|
| MDEF_CHK_ENABLED
|
MDEF_CHK_ENABLED:
        MOVE.L  (A3),A0                         | dereference MenuHandle
        MOVE.L  0xA(A0),D0                      | D0 = enableFlags (32-bit mask)
        BTST    D4,D0                           | test bit for item D4
        BEQ.B   MDEF_CHK_ENABLE                 | item disabled -> Z=1 (return false)
        BTST    #0x0,D0                         | test master enable bit (bit 0)
MDEF_CHK_ENABLE:
        RTS                                     | Z=1 if disabled, Z=0 if enabled

| ----------------------------------------------------------
|
| MDEF_INVERT_ITEM
|
| MDEF_INVERT_ITEM: highlight/unhighlight menu item D0 (toggle via InvertRect)
| D0 = item number to toggle (0 = none)
MDEF_INVERT_ITEM:
        MOVEM.L D3-D4,-(SP)                     | save working regs
        MOVE    D0,D3                           | D3 = target item number
        BEQ.B   MDEF_HILITE_RTS                 | item 0 = no item ->
        BSR.B   MDEF_GET_MBARHT                 | D0 = menu bar height (item Y start)
        MOVE    D0,D2                           | D2 = running Y position
| walk items from TopMenuItem to find target item's Y position
        MOVE    (TopMenuItem).w,D4              | D4 = current item index
MDEF_WALK_ITEMS:
        MOVE    D4,D0                           | D0 = item index for MDEF_FIND_NTH
        MOVE.L  (A3),A0                         | A0 = dereferenced menu data
        BSR     MDEF_FIND_NTH                   | advance A0 to item D0's data
        BSR.B   MDEF_ITEM_HEIGHT                | D0 = item height
        CMP.B   D3,D4                           | reached target item?
        BEQ.B   MDEF_BUILD_RECT                 | yes ->
        ADD     D0,D2                           | accumulate Y offset
        ADDQ.W  #0x1,D4                         | next item
        BRA.B   MDEF_WALK_ITEMS                 | loop to next item
| build the item's rect and invert it
MDEF_BUILD_RECT:
        MOVE.B  0x1(A0),D1                      | D1 = item icon number
        LEA.L   (scratch8).w,A0                 | A0 = temp Rect in scratch
        MOVE.L  0x10(A6),A1                     | A1 = menuRect ptr
        MOVE.L  (A1)+,(A0)                      | copy menuRect.topLeft
        MOVE.L  (A1),0x4(A0)                    | copy menuRect.botRight
        MOVE    D2,(A0)                         | rect.top = item Y
        ADD     D0,D2                           | + item height
        MOVE    D2,0x4(A0)                      | rect.bottom = item Y + height
        TST     D3                              | item number negative? (disabled)
        BMI.B   MDEF_DIM_ITEM                   | yes, draw disabled pattern ->
        MOVE.L  A0,-(SP)                        | push item rect
        _InvertRect                             | toggle highlight
MDEF_HILITE_RTS:
        MOVEM.L (SP)+,D3-D4                     | restore working regs
        RTS                                     | return from MDEF_INVERT_ITEM

| ----------------------------------------------------------
|
| MDEF_DIM_ITEM
|
MDEF_DIM_ITEM:
        CMPI.B  #0x2D,D1                        | separator line? (icon=0x2D='-')
        BEQ.B   MDEF_HILITE_RTS                 | yes, don't dim separators ->
        BSR     MDEF_GRAY_ITEM                  | gray out disabled item
        BRA.B   MDEF_HILITE_RTS                 | -> restore regs and return

| ----------------------------------------------------------
|
| MDEF_ADVANCE_Y
|
| MDEF_ADVANCE_Y: advance vertical position for next menu item
| D0 = item height, D5 = current Y position
| Handles right-to-left script direction (Arabic/Hebrew)
MDEF_ADVANCE_Y:
        MOVE    D5,D2                           | D2 = current Y for this item
        ADDQ.W  #0x2,D2                         | + 2 pixel margin
        ADD     D0,D5                           | advance Y by item height
        TST.B   (TESysJust_1).w                 | right-to-left script?
        BPL.B   MDEF_ADV_Y_RTS                  | no, normal LTR ->
| RTL: draw from right edge, adjust positions
        SUB     D0,D6                           | adjust right margin
        SUB     D0,D5                           | adjust Y
        MOVE    D6,D2                           | D2 = RTL position
MDEF_ADV_Y_RTS:
        RTS                                     | return with D2=draw Y, D5=next Y

| ----------------------------------------------------------
|
| MDEF_DRAW_MSG
|
| mDrawMsg (0): draw the entire menu contents
MDEF_DRAW_MSG:
        MOVE    #0x1,(TopMenuItem).w            | start drawing from item 1
        BSR.B   MDEF_DRAW_ALL                   | draw all visible menu items
        BRA     MDEF_EXIT                       | -> MDEF exit
| MDEF_DRAW_ALL exit: all items drawn
MDEF_AT_BOTTOM:
        ST.B    (AtMenuBottom).w                | flag: reached bottom of menu
MDEF_DRAW_RTS:
        MOVEM.L (SP)+,D3-D4/A4                  | restore regs
        RTS                                     | return from MDEF_DRAW_ALL

| ----------------------------------------------------------
|
| MDEF_DRAW_ALL
|
| MDEF_DRAW_ALL: draw all visible menu items (main draw loop)
MDEF_DRAW_ALL:
        MOVEM.L D3-D4/A4,-(SP)                  | save regs
        CLR     (AtMenuBottom).w                | clear bottom-reached flag
        BSR     MDEF_SETUP_FONT                 | set up font metrics
        MOVE    (TopMenuItem).w,D4              | D4 = first visible item
        BSR     MDEF_GET_MBARHT                 | D0 = menu bar height
        MOVE    D0,D3                           | D3 = current Y position
        ADD     -0x8(A6),D3                     | + font ascent
| item draw loop
MDEF_DRAW_LOOP:
        MOVE.L  0x10(A6),A0                     | A0 = menuRect ptr
        MOVE.L  (A0)+,D5                        | D5 = menuRect.topLeft
        MOVE    (A0)+,D2                        | D2 = menuRect.bottom
        MOVE    (A0),D6                         | D6 = menuRect.right
        MOVE    D4,D0                           | D0 = item number
        MOVE.L  (A3),A0                         | dereference MenuHandle
        BSR     MDEF_FIND_NTH                   | find item D0 -> A0=title, A1=attrs
        BEQ.B   MDEF_AT_BOTTOM                  | past last item ->
        CMP     D2,D3                           | past bottom of menu rect?
        BGE.B   MDEF_DRAW_RTS                   | yes, stop drawing ->
| prepare to draw this item
        MOVE.L  A0,A2                           | A2 = item title ptr
        MOVE.L  A1,A4                           | A4 = item attributes (icon,key,mark,style)
        MOVE.B  0x3(A4),D0                      | D0 = style byte
| check for separator line (title = '-')
        CMPI.B  #0x2D,0x1(A2)                   | first char = '-' (separator)?
        BEQ     MDEF_DRAW_SEP                   | yes, draw separator line ->
| check for icon
        MOVE.B  (A4),D0                         | D0 = icon number
        BEQ.B   MDEF_DRAW_MARK                  | no icon ->
        MOVEQ.L #0x24,D0                        | icon width = 36 pixels
        SUB     -0x2(A6),D0                     | - font descent
        MOVE    D0,D7                           | D7 = icon offset
        LSR     #0x1,D0                         | center vertically
        ADD     D0,D3                           | adjust Y for icon
| draw mark character (checkmark, bullet, etc.)
MDEF_DRAW_MARK:
        MOVE    -0x4(A6),D0                     | D0 = item height
        BSR     MDEF_ADVANCE_Y                  | advance Y position
        TST.B   0x2(A4)                         | has mark character?
        BEQ.B   MDEF_DRAW_TEXT                  | no ->
        MOVE    D2,-(SP)                        | push X position
        MOVE    D3,-(SP)                        | push Y position
        _MoveTo                                 | position pen
        CLR     D0                              | zero-extend for DrawChar
        MOVE.B  0x2(A4),D0                      | D0 = mark character
        MOVE    D0,-(SP)                        | push character code
        _DrawChar                               | draw the mark
| draw item text
MDEF_DRAW_TEXT:
        TST.B   (A4)                            | has icon?
        BEQ.B   MDEF_DRAW_KEY                   | no icon, skip to key equiv ->
        MOVEQ.L #0x28,D0                        | icon+text line height = 40 pixels
        BSR     MDEF_ADVANCE_Y                  | advance Y, get draw position in D2
        LEA.L   (scratch8).w,A0                 | A0 = scratch rect for icon
        MOVE.L  A0,-(SP)                        | push rect ptr for PlotIcon
        MOVE    D3,D1                           | D1 = text baseline Y
        MOVE    D7,D0                           | D0 = icon vertical offset
        LSR     #0x1,D0                         | halve for centering
        SUB     D0,D1                           | center icon relative to text
        SUB     -0x8(A6),D1                     | adjust for font ascent
        ADDQ.W  #0x2,D1                         | + 2 pixel padding
        MOVE    D1,(A0)+                        | rect.top = icon top
        MOVE    D2,(A0)                         | rect.left = item left edge
        ADDQ.W  #0x3,(A0)+                      | rect.left += 3 pixel indent
| draw icon if present
        MOVE.L  -0x4(A0),(A0)                   | set icon rect top
        ADDI    #0x20,(A0)+                     | icon rect bottom = top + 32
        ADDI    #0x20,(A0)                      | icon rect right = left + 32
        CLR.L   -(SP)                           | space for handle
        MOVE.L  #0x49434F4E,-(SP)               | 'ICON' resource type
        MOVE    #0x100,D0                       | icon base ID = 256
        MOVE.B  (A4),D0                         | + item icon number
        MOVE    D0,-(SP)                        | push ICON resource ID
        _GetResource                            | load icon
        _PlotIcon                               | draw it in the rect
| draw key equivalent (Cmd-key shortcut) if present
MDEF_DRAW_KEY:
        TST.B   0x1(A4)                         | has key equivalent?
        BEQ.B   MDEF_APPLY_STYLE                | no ->
        MOVE    -0x4(A6),D0                     | D0 = item height
        ADD     D0,D0                           | * 2 for margin
        SUB     D0,D6                           | move X left for key equiv
        MOVE    D6,-(SP)                        | push X
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
|
| MDEF_DRAW_RTL
|
MDEF_DRAW_RTL:
        LEA.L   (scratch8).w,A0                 | A0 = scratch rect for TETextBox
        SUBQ.W  #0x1,D5                         | adjust left edge for RTL
        MOVE    D3,(A0)                         | rect.top = baseline Y
        MOVE    -0x8(A6),D0                     | D0 = font ascent
        SUB     D0,(A0)+                        | rect.top -= ascent (align to top)
        MOVE    D5,(A0)+                        | rect.left = adjusted X
        MOVE    D3,(A0)                         | rect.bottom = baseline Y
        MOVE    -0x6(A6),D0                     | D0 = font descent
        ADD     D0,(A0)+                        | rect.bottom += descent
        MOVE    D6,(A0)                         | rect.right = right margin
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A2)+,D0                        | D0 = string length byte
        MOVE.L  A2,-(SP)                        | push text pointer
        MOVE.L  D0,-(SP)                        | push text length
        PEA.L   (scratch8).w                    | push dest rect
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
        MOVE    D7,D0                           | D0 = icon offset
        LSR     #0x1,D0                         | halve for centering
        SUB     D0,D7                           | remaining offset
        ADD     D7,D3                           | adjust baseline past icon
MDEF_NEXT_ITEM:
        ADD     -0x2(A6),D3                     | advance Y by font descent
        ADDQ.W  #0x1,D4                         | next item number
        BRA     MDEF_DRAW_LOOP                  | -> draw next item

| ----------------------------------------------------------
|
| MDEF_DRAW_SEP
|
MDEF_DRAW_SEP:
        MOVE.L  (A5),A0                         | A0 = QD globals ptr
        PEA.L   -0x18(A0)                       | push gray pattern address
        _PenPat                                 | set pen to gray for separator
        MOVE    D3,-(SP)                        | save current Y on stack
        MOVE    D5,-(SP)                        | push start X (left edge)
        MOVE    -0x2(A6),D0                     | D0 = font descent
        LSR     #0x1,D0                         | halve for vertical centering
        SUB     -0x8(A6),D0                     | - ascent = center offset
        ADD     D0,D3                           | D3 = separator Y position
        MOVE    D3,-(SP)                        | push Y for MoveTo
        _MoveTo                                 | move pen to line start
        MOVE    D6,-(SP)                        | push end X (right edge)
        MOVE    D3,-(SP)                        | push Y for LineTo
        _LineTo                                 | draw gray separator line
        MOVE    (SP)+,D3                        | restore baseline Y
        _PenNormal                              | reset pen to normal
        BRA.B   MDEF_CHK_ICON                   | -> check icon adjust, next item

| MDEF_FIND_NTH -- find item D0 in menu data.
| ----------------------------------------------------------
|
| MDEF_FIND_NTH
|
MDEF_FIND_NTH:
        TST     D0                              | item number <= 0?
        BLE.B   MDEF_NOT_FOUND                  | invalid item -> return null
        MOVEQ.L #0x0,D1                         | clear length register
        LEA.L   0xE(A0),A1                      | A1 = menu title (past MenuInfo header)
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
|
| MDEF_NOT_FOUND
|
MDEF_NOT_FOUND:
        SUBA.L  A0,A0                           | A0 = nil (item not found)
        MOVE.L  A0,A1                           | A1 = nil
        MOVE.L  A0,D0                           | D0 = 0, sets Z flag (not found)
        RTS                                     | return Z=1 (item not found)

| ----------------------------------------------------------
|
| MDEF_FOUND_ITEM
|
MDEF_FOUND_ITEM:
        TST.B   (A1)                            | item title length = 0?
        BEQ.B   MDEF_NOT_FOUND                  | empty item -> return null
        MOVE.L  A1,A0                           | A0 = item title string ptr
        MOVE.B  (A1)+,D1                        | D1 = title length
        ADDA    D1,A1                           | A1 = item attributes (icon,key,mark,style)
        RTS                                     | return Z=0 (item found)

| ----------------------------------------------------------
|
| MDEF_SIZE_MSG
|
| mSizeMsg (2): calculate menu width and height
| Measures all items and sets menuWidth/menuHeight in MenuInfo
MDEF_SIZE_MSG:
        SUBQ.W  #0x4,SP                         | save space for GetPort result
        MOVE.L  A7,-(SP)                        | push ptr to save slot on stack
        _GetPort                                | save current port
        MOVE.L  (WMgrPort).w,-(SP)              | push WMgrPort for SetPort
        _SetPort                                | switch to WMgr port (for font metrics)
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr GrafPort
        MOVE    0x14(A0),D5                     | D5 = port height (screen bottom)
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
        MOVE.L  (A3),A0                         | dereference MenuHandle (may move)
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
        SWAP    D6                              | D6.hi = running total height
        ADD     D0,D6                           | accumulate total height
        CMP     D5,D6                           | exceeds max menu height?
        BLT.B   MDEF_CHK_MAXHT                  | no ->
        SUB     D0,D6                           | undo: don't count this item
MDEF_CHK_MAXHT:
        SWAP    D6                              | D6.lo = max width again
        MOVE    -0x4(A6),D1                     | D1 = widMax (char cell width)
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
|
| MDEF_END_MEASURE
|
MDEF_END_MEASURE:
        ADDQ.W  #0x4,D6                         | + 4px padding to max width
MDEF_STORE_SIZE:
        MOVE.L  (A3),A0                         | dereference MenuHandle
        MOVE    D6,0x2(A0)                      | store menuWidth in MenuInfo
        SWAP    D6                              | D6 = total height
        MOVE    D6,0x4(A0)                      | store menuHeight in MenuInfo
        CLR     -(SP)                           | push 0 = plain style
        _TextFace                               | reset text style
        _SetPort                                | restore saved port
        BRA     MDEF_EXIT                       | -> MDEF exit

| MDEF_GRAY_ITEM -- gray out disabled item.
| ----------------------------------------------------------
|
| MDEF_GRAY_ITEM
|
MDEF_GRAY_ITEM:
        MOVE.L  A0,-(SP)                        | push item rect for PaintRect
        MOVE.L  (A5),A0                         | A0 = QD globals ptr
        PEA.L   -0x18(A0)                       | push gray pattern address
        _PenPat                                 | set pen to gray pattern
        MOVE    #0xB,-(SP)                      | push notSrcBic mode (11)
        _PenMode                                | set transfer mode for dimming
        _PaintRect                              | paint gray over disabled item
        _PenNormal                              | restore default pen state
        RTS                                     | return from MDEF_GRAY_ITEM

| end of resource : 'MDEF' 0

| resource header
  .long 0xC000069A                              | Length
  .long 0x00000070                              | ?

