| Menu Manager
|
| Apple source: MenuMgr.a (MacSEROM.lst module MMGR). Manages the menu
| bar and the pull-down menus: InitMenus, ClearMenuBar, InsertMenu,
| DeleteMenu, DrawMenuBar, HiliteMenu, EnableItem, DisableItem,
| MenuSelect, GetMenuBar, SetMenuBar, DisposMenu, FlashMenuBar, the item
| attribute calls, CheckItem, MenuKey, GetItem, CalcMenuSize, NewMenu,
| AppendMenu, GetMHandle, SetItem, SetMFlash, AddResMenu, InsertResMenu,
| CountMItems and PlotIcon.
|
| MenuInfo (MPW 1.0 Menus.h):
| Offset 0: menuID INTEGER menu identifier
| Offset 2: menuWidth INTEGER width of menu in pixels
| Offset 4: menuHeight INTEGER height of menu in pixels
| Offset 6: menuProc Handle MDEF resource handle
| Offset 10: enableFlags LongInt bit 0=menu, bits 1-31=items (1=enabled)
| Offset 14: menuData Str255 menu title + item definitions
|
| References:
| Inside Macintosh Vol I, Ch 11: The Menu Manager

| ----------------------------------------------------------
| InitMenus -- _InitMenus ($A930).
| Pascal: procedure InitMenus;
| Initializes the Menu Manager: allocates MenuList ($66 = 102
| bytes for a 24-slot menu bar), reads MenuFlash count from
| parameter RAM (SPMisc2 bits 2-3), clears MBarEnable/MBarHook/
| MenuHook, then clears the menu bar and draws it.
InitMenus:
        BSR.B   INITMENUS_NEWLIST               | allocate MenuList block -> A0
        MOVE.L  A0,(MenuList).w                 | store handle
        MOVEQ.L #0xC,D0                         | mask = bits 2-3
        AND.B   (SPMisc2).w,D0                  | extract flash count from PRAM
        LSR     #0x2,D0                         | shift to count value (0..3)
        MOVE    D0,(MenuFlash).w                | store flash count
        CLR     (MBarEnable).w                  | menu bar enable flags = 0
        CLR.L   (MBarHook).w                    | clear MBarHook proc ptr
        CLR.L   (MenuHook).w                    | clear MenuHook proc ptr
        _ClearMenuBar                           | clear the menu list contents
        _DrawMenuBar                            | draw empty menu bar
        RTS                                     | return from InitMenus
INITMENUS_NEWLIST:
        MOVEQ.L #0x66,D0                        | D0 = sizeof(MenuList) = 102 bytes
        _NewHandle                              | allocate MenuList block -> A0
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
        RTS                                     | return from CALCMBHEIGHT_LOOP

| ----------------------------------------------------------
| ClearMenuBar -- _ClearMenuBar ($A934).
| Pascal: procedure ClearMenuBar;
| Empties MenuList by reinitializing it via CALCMBHEIGHT_EMPTY_2
| and clearing TheMenu. Plus 1986 added a BSR DISABLEITEM_CONT
| prologue that validates the MenuList handle before use; classic
| 1984 trusts that MenuList has been initialized by InitMenus.
ClearMenuBar:
        MOVE.L  (MenuList).w,A0                 | A0 = MenuList handle
        BSR.B   CALCMBHEIGHT_EMPTY_2            | reinitialize to empty list
        CLR     (TheMenu).w                     | no highlighted menu
        RTS                                     | return from ClearMenuBar

| ----------------------------------------------------------
| InsertMenu -- _InsertMenu ($A935).
| Pascal: procedure InsertMenu(theMenu: MenuHandle; beforeID: INTEGER);
| Inserts a menu into MenuList at the position before menu ID
| beforeID (or at the end if beforeID = 0). Computes the new
| title's StringWidth, shifts subsequent entries down, and
| updates each menuLeft to account for the new title's width.
| Bails early if MenuList is already at the 24-menu limit ($60).
InsertMenu:
        MOVEM.L D3-D4/A2-A4,-(SP)               | save regs
        MOVE.L  (MenuList).w,A3                 | A3 = MenuList handle
        MOVE.L  (A3),A3                         | dereference -> MenuList data
        CMPI    #0x60,(A3)                      | already at max ($60 = 24*4)?
        BGE.B   INSERTMENU_CONT_CONT            | yes -> bail (no insert)
        MOVE.L  26(SP),A4                       | A4 = MenuHandle to insert
        MOVE.L  (A4),A2                         | A2 = MenuInfo (deref handle)
        MOVE    (A2),D1                         | D1 = menuID to insert
        BSR.B   INSERTMENU_CONT_2               | search if menuID already in MenuList
        BNE.B   INSERTMENU_CONT_CONT            | already present -> bail
        JSR     GetSetWPort(PC)                 | pc-relative jsr (was raw .short pair)
        CLR.L   -(SP)                           | space for StringWidth result
        _TextFont                               | set system font (font 0)
        _TextFace                               | reset face (param 0 already on stack)
        CLR     -(SP)                           | space for StringWidth result
        PEA.L     14(A2)                        | push title string addr (MenuInfo+14)
        _StringWidth                            | measure title pixel width
        MOVEQ.L #0xD,D3                         | D3 = 13 px padding (6 each side + 1)
        ADD     (SP)+,D3                        | D3 = title width + 13 px slot width
        MOVE    24(SP),D1                       | D1 = beforeID parameter
        BSR.B   INSERTMENU_CONT_2               | find slot of beforeID menu
        BNE.B   CALCMBHEIGHT_LOOP_NO            | found beforeID -> shift entries down
        MOVE    (A3),D0                         | D0 = lastMenu (offset of next free slot)
        ADDQ.W  #0x6,D0                         | advance to insertion slot
        MOVE    2(A3),D1                        | D1 = lastRight (current end of bar)
        BRA.B   INSERTMENU_CONT                 | insert at end (no shift needed)
CALCMBHEIGHT_LOOP_NO:
        MOVE    4(A3,D0.W),D1                   | D1 = menuLeft of beforeID slot
        MOVE    (A3),D2                         | D2 = lastMenu (shift starting point)
INSERTMENU_NO:
        MOVE.L  0x0(A3,D2.W),0x6(A3,D2.W)       | shift menu handle down one slot
        MOVE    0x4(A3,D2.W),0xA(A3,D2.W)       | shift menuLeft down one slot
        ADD     D3,0xA(A3,D2.W)                 | adjust left edge by new title width
        SUBQ.W  #0x6,D2                         | move to previous entry
        CMP     D0,D2                           | reached insertion point?
        BGE.B   INSERTMENU_NO                   | no -> continue shifting
INSERTMENU_CONT:
        ADD     D3,2(A3)                        | advance lastRight by title width
        MOVE.L  A4,0(A3,D0.W)                   | store MenuHandle at insertion slot
        MOVE    D1,4(A3,D0.W)                   | store menuLeft at insertion slot
        ADDQ.W  #0x6,(A3)                       | increment lastMenu (add 6 bytes)
        JSR     RestorePort(PC)                 | restore original port
INSERTMENU_CONT_CONT:
        MOVEM.L (SP)+,D3-D4/A2-A4               | restore saved regs
INSERTMENU_CONT_EXIT:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x6,SP                         | strip 6 bytes of params
        JMP     (A0)                            | RTS
INSERTMENU_CONT_2:
        TST     D1                              | menuID = 0?
        BEQ.B   INSERTMENU_EMPTY                | menuID = 0 -> not found (return 0)
        MOVE.L  (MenuList).w,A1                 | A1 = MenuList handle
        MOVE.L  (A1),A1                         | A1 = dereferenced MenuList ptr
        MOVE    (A1),D2                         | D2 = lastMenu (top offset)
        BEQ.B   INSERTMENU_EMPTY                | empty list -> not found
INSERTMENU_CONT_3:
        MOVE.L  0(A1,D2.W),D0                   | D0 = MenuHandle at offset D2
        BEQ.B   INSERTMENU_SKIP_2               | nil handle -> skip
        MOVE.L  D0,A0                           | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference to MenuInfo
        CMP     (A0),D1                         | menuID matches target?
        BEQ.B   INSERTMENU_FOUND_2              | yes -> return offset in D0
INSERTMENU_SKIP_2:
        SUBQ.W  #0x6,D2                         | step to previous slot
        BNE.B   INSERTMENU_CONT_3               | more entries -> keep searching
INSERTMENU_EMPTY:
        MOVEQ.L #0x0,D2                         | not found: D2 = 0
INSERTMENU_FOUND_2:
        MOVE    D2,D0                           | return offset in D0 (Z reflects found)
        RTS                                     | return from INSERTMENU_FOUND_2

| ----------------------------------------------------------
| DeleteMenu -- _DeleteMenu ($A936).
| Pascal: procedure DeleteMenu(menuID: INTEGER);
| Removes a menu from MenuList by ID. Shifts subsequent entries
| up to fill the gap, decrementing menuLeft of each by the
| removed menu's width. Plus 1986 uses a DISABLEITEM_CONT_3
| helper to dereference MenuList; classic 1984 inlines it.
DeleteMenu:
        MOVE    4(SP),D1                        | D1 = menuID to delete
        BSR.B   INSERTMENU_CONT_2               | search MenuList for this ID
        BEQ.B   DELETEMENU_EXIT                 | not found -> return
        MOVE.L  (MenuList).w,A1                 | A1 = MenuList handle
        MOVE.L  (A1),A1                         | A1 = dereferenced MenuList ptr
        CMP     (A1),D0                         | deleting last entry?
        BNE.B   INSERTMENU_CONT_3_NO            | no -> shift entries up
        MOVE    4(A1,D0.W),2(A1)                | lastRight = deleted's menuLeft
        BRA.B   DELETEMENU_NO_2_CONT            | decrement count and exit
INSERTMENU_CONT_3_NO:
        MOVE    0xA(A1,D0.W),D2                 | D2 = next entry's menuLeft
        SUB     4(A1,D0.W),D2                   | D2 -= 4(A1,D0.W)
        SUB     D2,2(A1)                        | 2(A1) -= D2
DELETEMENU_NO_2:
        MOVE.L  0x6(A1,D0.W),0x0(A1,D0.W)       | shift next MenuHandle into current slot
        MOVE    0xA(A1,D0.W),0x4(A1,D0.W)       | shift next menuLeft into current slot
        SUB     D2,0x4(A1,D0.W)                 | adjust menuLeft by deleted width
        ADDQ.W  #0x6,D0                         | advance to next entry
        CMP     (A1),D0                         | past last entry?
        BLE.B   DELETEMENU_NO_2                 | no -> continue shifting
DELETEMENU_NO_2_CONT:
        SUBQ.W  #0x6,(A1)                       | decrement lastMenu (one fewer entry)
DELETEMENU_EXIT:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x2,SP                         | strip menuID parameter
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| DELETEMENU_CONT_2
| Called during boot.
DELETEMENU_CONT_2:
        LEA.L     (scratch8).w,A0               | A0 = scratch rect for title bbox
        MOVE    #0x1,(A0)+                      | rect.top = 1
        MOVE    4(A1,D0.W),(A0)                 | rect.left = menu's menuLeft
        SUBQ.W  #0x1,(A0)+                      | rect.left -= 1 (1px left margin)
        MOVE    #0x13,(A0)+                     | rect.bottom = 19 (menu bar height)
        CMP     (A1),D0                         | last menu in list?
        BEQ.B   DELETEMENU_LASTRIGHT            | yes -> use lastRight as right edge
        ADDQ.W  #0x6,D0                         | advance to next slot
        MOVE    4(A1,D0.W),(A0)                 | rect.right = next slot's menuLeft
        BRA.B   DELETEMENU_SETRIGHT             | commit right edge
DELETEMENU_LASTRIGHT:
        MOVE    2(A1),(A0)                      | rect.right = lastRight
DELETEMENU_SETRIGHT:
        ADDQ.W  #0x4,(A0)                       | (A0) += 0x4
        RTS                                     | return from DELETEMENU_SETRIGHT
DELETEMENU_CONT_4:
        MOVE.L  (WMgrPort).w,A3                 | A3 = WMgr port
        MOVE.L  28(A3),-(SP)                    | push WMgr clipRgn handle
        CLR.L   -(SP)                           | rect.topLeft = (0,0)
        MOVE    22(A3),-(SP)                    | rect.right = port width
        MOVE    #0x14,-(SP)                     | rect.bottom = 20 (menu bar height)
        _SetRectRgn                             | set clipRgn = menu bar area
        PEA     0x10(A3)                        | push ptr to rect at A3+0x10
        MOVE.L  #0x00100010,-(SP)               | push oval radii (16,16)
        _EraseRoundRect                         | erase rounded-rect area
        MOVE    22(A3),-(SP)                    | x2 = port right edge
        MOVEQ.L #0x13,D0                        | D0 = 19 (menu bar bottom row)
        MOVE    D0,-(SP)                        | y2 = 19 (push v of pt2)
        SWAP    D0                              | swap to high word for pt1.h=0
        MOVE.L  D0,-(SP)                        | push pt1 = (0,19) for MoveTo
DELETEMENU_CONT_4_CONT:
        _MoveTo                                 | move pen to bottom-left of bar
        _LineTo                                 | draw separator line to right edge
        RTS                                     | return from DELETEMENU_CONT_4_CONT

| ----------------------------------------------------------
| DrawMenuBar -- _DrawMenuBar ($A937).
| Pascal: procedure DrawMenuBar;
| Erases the menu bar with a 16x16 rounded rect (clears outside
| visible area), draws a separator line, then walks MenuList
| drawing each menu's title with 8-pixel left padding. Disabled
| menus get a 50%-gray BIC overlay applied via DRAWMENUBAR_CONT_2.
DrawMenuBar:
        MOVEM.L D3-D5/A3-A4,-(SP)               | save regs
        JSR     GetSetWPort(PC)                 | save port, switch to WMgr
        BSR.B   DELETEMENU_CONT_4               | erase menu bar background + line
        JSR     FullClip(PC)                    | reset clip to full port rect
        MOVEQ.L #0x6,D3                         | D3 = first menu entry offset
        MOVE.L  (MenuList).w,A3                 | A3 = MenuList handle
        MOVE.L  (A3),A3                         | A3 = dereferenced MenuList ptr
        TST     (A3)                            | any menus to draw?
        BEQ.B   DRAWMENUBAR_DONE                | empty list -> done
DRAWMENUBAR_NEXT:
        MOVE    4(A3,D3.W),-(SP)                | push this menu's menuLeft
        ADDQ.W  #0x8,(SP)                       | add 8 pixels left padding for title
        MOVE    #0xE,-(SP)                      | y = 14 (text baseline in menu bar)
        _MoveTo                                 | move pen to title position
        MOVE    D3,D5                           | D5 = menu slot index
        BSR.W   DISABLEITEM_NEXT                | A0 = MenuInfo for slot D5
        MOVE.L  A0,A4                           | A4 = MenuInfo for this menu
        PEA.L     14(A4)                        | push title string addr (MenuInfo+14)
        _DrawString                             | draw the menu title text
        BTST    #0x0,13(A4)                     | menu enabled? (bit 0 of enableFlags)
        BEQ.B   DRAWMENUBAR_CONT                | disabled -> dim title
        MOVE    (TheMenu).w,D0                  | D0 = currently highlighted menu ID
        CMP     (A4),D0                         | matches this menu's ID?
        BNE.B   DRAWMENUBAR_NEXT_2              | no -> next menu
        MOVE    D3,D0                           | D0 = slot offset for invert
        BSR.W   DISABLEITEM_CONT_5              | invert title rect (highlight)
        BRA.B   DRAWMENUBAR_NEXT_2              | next menu
DRAWMENUBAR_CONT:
        MOVE    D3,D0                           | D0 = current entry offset
        MOVE.L  A3,A1                           | A1 = MenuList for DELETEMENU_CONT_2
        BSR.W   DELETEMENU_CONT_2               | build title rect in scratch8
        BSR.B   DRAWMENUBAR_CONT_2              | paint gray over title (dim effect)
DRAWMENUBAR_NEXT_2:
        ADDQ.W  #0x6,D3                         | advance to next menu slot
        CMP     (A3),D3                         | past last menu?
        BLE.B   DRAWMENUBAR_NEXT                | more -> draw next title
DRAWMENUBAR_DONE:
        JSR     RestorePort(PC)                 | pc-relative jsr (was raw .short pair)
        MOVEM.L (SP)+,D3-D5/A3-A4               | restore saved regs
        RTS                                     | return from DRAWMENUBAR_DONE

| DRAWMENUBAR_CONT_2 -- paint gray over title (dim effect).
| ----------------------------------------------------------
| DRAWMENUBAR_CONT_2
DRAWMENUBAR_CONT_2:
        MOVE    #0xB,-(SP)                      | patBic mode (clear through pattern)
        _PenMode                                | set pen mode to BIC
        PEA     DRAGPATTERN_SRC(PC)             | push 50% gray pattern addr
        _PenPat                                 | set pen pattern to gray
        PEA.L     (scratch8).w                  | push title rect (built by DELETEMENU_CONT_2)
        _PaintRect                              | paint gray BIC over title (dims it)
        _PenNormal                              | restore default pen
        RTS                                     | return from DRAWMENUBAR_CONT_2

| ----------------------------------------------------------
| HiliteMenu -- _HiliteMenu ($A938).
| Pascal: procedure HiliteMenu(menuID: INTEGER);
| Highlights a menu title in the menu bar (or unhighlights the
| current one if menuID = 0). Calls DISABLEITEM_CONT_4 to invert
| the title rect for both old and new highlighted menus.
HiliteMenu:
        MOVE.L  D4,-(SP)                        | save D4 (used by GetSetWPort)
        JSR     GetSetWPort(PC)                 | save port, switch to WMgr
        BSR.W   FullClip                        | set clip to full port rect
        MOVE    (TheMenu).w,D1                  | D1 = currently highlighted menuID
        CMP     8(SP),D1                        | same as requested menuID?
        BEQ.B   DRAWMENUBAR_CONT_2_OK           | yes -> no change needed
        BSR.B   DISABLEITEM_CONT_4              | invert old highlighted title rect
        MOVE    8(SP),D1                        | D1 = new menuID to highlight
        MOVE    D1,(TheMenu).w                  | set as current highlighted menu
        BSR.B   DISABLEITEM_CONT_4              | invert new title rect
DRAWMENUBAR_CONT_2_OK:
        JSR     RestorePort(PC)                 | pc-relative jsr (was raw .short pair)
        MOVE.L  (SP)+,D4                        | restore D4
        BRA.W   DELETEMENU_EXIT                 | -> strip param and return

| ----------------------------------------------------------
| EnableItem -- _EnableItem ($A939).
| Pascal: procedure EnableItem(theMenu: MenuHandle; item: INTEGER);
| Sets bit (item) in the menu's enableFlags field. Bit 0 = whole
| menu enable; bits 1-31 = items 1..31. BSET Dn,Dn uses the bit
| number mod 32, so item numbers > 31 wrap around (32 -> bit 0).
EnableItem:
        BSR.B   ENABLEITEM_CONT                 | get menu enable flags -> D0=item, D1=flags
        BSET    D0,D1                           | set item's enable bit
DRAWMENUBAR_CONT_2_EXIT:
        MOVE.L  D1,10(A0)                       | store updated enableFlags
        BRA.W   INSERTMENU_CONT_EXIT            | strip params and return

| ----------------------------------------------------------
| ENABLEITEM_CONT
| Called during boot (157,003 times in 30s trace).
ENABLEITEM_CONT:
        MOVE.L  0xA(SP),A0                      | A0 = MenuHandle (past retAddr+retAddr)
        MOVE.L  (A0),A0                         | dereference to MenuInfo
        MOVE    0x8(SP),D0                      | D0 = item number (bit index)
        MOVE.L  0xA(A0),D1                      | D1 = menuEnable flags (32-bit)
        RTS                                     | return from ENABLEITEM_CONT
DisableItem:
        BSR.B   ENABLEITEM_CONT                 | get menu enable flags -> D0=item, D1=flags
        BCLR    D0,D1                           | clear item's enable bit
        BRA.B   DRAWMENUBAR_CONT_2_EXIT         | -> store and return
| Called by: DRAWMENUBAR_NEXT, MENUSELECT_NO, MENUSELECT_SKIP_2, MENUSELECT_CONT_5, FULLCLIP_CONT (and 3 more)
DISABLEITEM_NEXT:
        MOVE.L  (MenuList).w,A0                 | A0 = MenuList handle
        MOVE.L  (A0),A0                         | A0 = dereferenced MenuList ptr
        MOVE.L  0(A0,D5.W),A1                   | A1 = MenuHandle at slot D5
        MOVE.L  (A1),A0                         | A0 = MenuInfo (deref MenuHandle)
DISABLEITEM_EXIT:                               | shared early-exit target
        RTS                                     | return from DISABLEITEM_EXIT
DISABLEITEM_CONT_4:
        BSR.W   INSERTMENU_CONT_2               | look up menu ID -> A1 (zero = not found)
        BEQ.B   DISABLEITEM_EXIT                | not found -> RTS
| IF OP = DIFF AND RGNB = EMPTY, COPY RGNA INTO DST
| Called during boot (10,210 times in 30s trace).
DISABLEITEM_CONT_5:
        MOVE.L  (MenuList).w,A1                 | A1 = MenuList handle
        MOVE.L  (A1),A1                         | A1 = dereferenced MenuList ptr
        CMP     (A1),D0                         | slot offset > lastMenu?
        BGT.B   DISABLEITEM_SKIP                | out of range -> skip
        ANDI    #-0x2,D0                        | clear low bit (force 6-byte align)
        BEQ.B   DISABLEITEM_SKIP                | slot 0 -> skip (no menu)
        BSR.W   DELETEMENU_CONT_2               | build title rect in scratch8
        PEA.L     (scratch8).w                  | push title rect
        _InvertRect                             | invert title rect (highlight toggle)
DISABLEITEM_SKIP:
        RTS                                     | return from DISABLEITEM_SKIP

| ----------------------------------------------------------
| MenuSelect -- _MenuSelect ($A93D).
| Pascal: function MenuSelect(startPt: Point): LONGINT;
| Tracks the mouse through pull-down menus until the button is
| released. Returns menuID<<16 | itemNumber (0 if no selection).
| This is the core menu tracking loop called from the event loop.
| Body spans into menu_mgr.s (the MENUSELECT_FOUND/NO/SKIP/...
| loop labels are in the next include file).
| Plus 1986 uses LINK A6,#-0x28 (40 bytes locals) and clears an
| extra rect at -0x28(A6) for saved menu bits; classic 1984 uses
| LINK A6,#-0x20 (32 bytes) -- no saved-bits rect.
MenuSelect:
        LINK    A6,#-0x20                       | set up stack frame (32 bytes)
        MOVEM.L D3-D7/A3,-(SP)                  | save regs
        CLR.L   -(SP)                           | push menuID 0
        _HiliteMenu                             | unhighlight any previous menu
        CLR.L   12(A6)                          | result = 0 (no selection)
        _WaitMouseUp                            | button still down?
        TST.B   (SP)+                           | check result
        BEQ.W   MENUSELECT_EXIT_2               | button up: no selection
        PEA.L     -0x20(A6)                     | push addr of saved port slot
        _GetPort                                | save current GrafPort
        MOVE.L  (WMgrPort).w,-(SP)              | push WMgr port
        _SetPort                                | switch to WMgr port
        BSR.W   FullClip                        | reset clip to full screen
        CLR     D4                              | D4 = 0 (no menu being tracked yet)
        MOVE.L  8(A6),D3                        | D3 = startPt (mouse position)
        BRA.B   MENUSELECT_LOOP_2               | enter tracking loop
MENUSELECT_LOOP:
        CMPI.L  #0x140000,D3                    | D3 >= $140000? (content-area check)
        BGE.W   MENUSELECT_SKIP                 | below menu bar -> no menu hit
MENUSELECT_LOOP_2:
        CLR     D5                              | D5 = candidate menu offset = 0
        MOVE.L  (MenuList).w,A0                 | A0 = MenuList handle
        MOVE.L  (A0),A0                         | A0 = dereferenced MenuList
        CMP     2(A0),D3                        | mouse.h beyond last menu's right?
        BGE.B   MENUSELECT_FOUND                | yes -> no menu hit
        MOVE    (A0),D5                         | D5 = lastMenu (start at last)
MENUSELECT_CONT:
        CMP     4(A0,D5.W),D3                   | mouse.h > this menu's menuLeft?
        BGT.B   MENUSELECT_FOUND                | yes -> found the menu
        SUBQ.W  #0x6,D5                         | try previous menu
        BNE.B   MENUSELECT_CONT                 | more entries -> continue
MENUSELECT_FOUND:
        MOVE    4(A0,D5.W),D6                   | D6 = menuLeft of hit menu
        CMP     D5,D4                           | same menu as currently open?
        BEQ.B   MENUSELECT_SKIP                 | yes -> skip menu switch
        TST     D4                              | call subroutine via A0
        BEQ.B   MENUSELECT_NO                   | no menu open -> open new
        BSR.W   MENUSELECT_CONT_3               | restore bits behind old menu
        MOVE    D4,D0                           | D0 = old menu entry offset
        BSR.W   DISABLEITEM_CONT_5              | unhighlight old menu title
MENUSELECT_NO:
        MOVE    D5,D4                           | D4 = new current menu offset
        CLR     12(A6)                          | clear result.menuID (high word)
        TST     D5                              | mouse in a menu title?
        BEQ.B   MENUSELECT_SKIP_2               | no -> just wait for mouse
        BSR.W   DISABLEITEM_NEXT                | A0=MenuInfo, A1=MenuHandle
        MOVE    (A0),12(A6)                     | call subroutine via A0
        CLR     14(A6)                          | clear result.itemNumber
        MOVE.L  (WMgrPort).w,A1                 | A1 = WMgr port
        MOVE    D6,D0                           | D0 = menu left edge
        ADD     menuWidth(A0),D0                | D0 = left + menuWidth
        ADDQ.W  #0x8,D0                         | add 8 px right padding
        CMP     22(A1),D0                       | menu extends past screen right?
        BLE.B   MENUSELECT_OK_2                 | menu fits -> skip width clamp
        MOVE    22(A1),D6                       | D6 = screen width
        SUBQ.W  #0x8,D6                         | subtract padding
        SUB     menuWidth(A0),D6                | D6 = adjusted left to fit screen
MENUSELECT_OK_2:
        LEA.L     -28(A6),A1                    | A1 = local menu rect addr
        MOVEQ.L #0x14,D0                        | D0 = 20 (menu bar height)
        MOVE    D0,(A1)+                        | rect.top = below menu bar
        MOVE    D6,(A1)+                        | rect.left = menu left edge
        ADD     menuHeight(A0),D0               | D0 += menuHeight
        MOVE    D0,(A1)+                        | rect.bottom = top + menuHeight
        ADD     menuWidth(A0),D6                | D6 += menuWidth
        MOVE    D6,(A1)+                        | rect.right = left + menuWidth
        MOVE    D5,D0                           | D0 = menu entry offset
        BSR.W   DISABLEITEM_CONT_5              | highlight menu title (invert)
        MOVE.L  (MBarHook).w,D0                 | D0 = MBarHook procedure
        BEQ.B   MENUSELECT_NO_2                 | no hook -> proceed
        MOVE.L  D0,A0                           | A0 = hook address
        PEA.L     -28(A6)                       | push menu rect
        JSR     (A0)                            | call subroutine via A0
        TST     D0                              | hook says abort?
        BNE.B   MENUSELECT_NO_7                 | yes -> exit MenuSelect
MENUSELECT_NO_2:
        BSR.W   MENUSELECT_CONT_5               | save bits behind, draw menu frame
MENUSELECT_SKIP:
        TST     D5                              | menu currently open?
MENUSELECT_SKIP_2:
        BEQ.B   MENUSELECT_GETMOUSE             | no -> just wait for mouse
        PEA.L     -28(A6)                       | push menu rect
        _ClipRect                               | clip to menu area
        BSR.W   DISABLEITEM_NEXT                | A0=MenuInfo, A1=MenuHandle
        MOVE    #0x1,-(SP)                      | message 1 = mChooseMsg
        MOVE.L  A1,-(SP)                        | push MenuHandle
        PEA.L     -28(A6)                       | push menu rect
        MOVE.L  D3,-(SP)                        | push current mouse pos
        PEA.L     14(A6)                        | push ptr to itemNumber result
        BSR.W   MENUSELECT_CONT_8               | load MDEF code -> A0
        JSR     (A0)                            | call subroutine via A0
        BSR.W   MENUSELECT_CONT_9               | unlock MDEF handle
        BSR.W   FullClip                        | restore full clip
MENUSELECT_GETMOUSE:
        SUBQ.W  #0x4,SP                         | space for GetMouse result
        MOVE.L  SP,-(SP)                        | push ptr for GetMouse
        _GetMouse                               | read current mouse position
        MOVE.L  (SP)+,D3                        | D3 = mouse point
        MOVE.L  (MenuHook).w,D0                 | D0 = MenuHook procedure
        BEQ.B   MENUSELECT_WAIT                 | no hook -> continue
        MOVE.L  D0,A0                           | A0 = hook address
        JSR     (A0)                            | call subroutine via A0
MENUSELECT_WAIT:
        CLR     -(SP)                           | space for WaitMouseUp result
        _WaitMouseUp                            | mouse still down?
        TST.B   (SP)+                           | check result
        BNE.W   MENUSELECT_LOOP                 | button down -> keep tracking
        TST     D5                              | was a menu open when released?
        BEQ.B   MENUSELECT_NO_6                 | no -> check result
        BSR.W   MENUSELECT_CONT_11              | flash selected item
        BSR.B   MENUSELECT_CONT_3               | restore bits behind menu
MENUSELECT_NO_6:
        TST     14(A6)                          | item selected? (from MDEF)
        BNE.B   MENUSELECT_EXIT                 | yes -> return selection
        CLR     12(A6)                          | no item: clear menuID
        MOVE    D5,D0                           | D0 = menu entry offset
        BSR.W   DISABLEITEM_CONT_5              | unhighlight menu title
MENUSELECT_EXIT:
        MOVE    12(A6),(TheMenu).w              | TheMenu = selected menuID
        BMI.B   MENUSELECT_CONT_2               | negative ID -> system menu
        TST     (MBarEnable).w                  | menu bar in DA-only mode?
        BMI.B   MENUSELECT_CONT_2               | yes -> dispatch via SystemMenu
MENUSELECT_NO_7:
        MOVE.L  -0x20(A6),-(SP)                 | push saved port
        _SetPort                                | restore caller's port
MENUSELECT_EXIT_2:
        MOVEM.L (SP)+,D3-D7/A3                  | restore saved regs
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,(SP)                      | strip startPt param
        RTS                                     | return menuResult on stack
MENUSELECT_CONT_2:
        MOVE.L  12(A6),-(SP)                    | push menuResult (menuID:item)
        _SystemMenu                             | dispatch to system/DA handler
        CLR.L   12(A6)                          | clear result (system handled it)
        BRA.B   MENUSELECT_NO_7                 | restore port and return
MENUSELECT_CONT_3:
        MOVE.L  (SavedHandle).w,A0              | A0 = saved bits handle
        MOVE.L  (A0),-20(A6)                    | store baseAddr in local BitMap
        PEA.L     -20(A6)                       | push saved BitMap (source)
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        PEA.L     0x2(A0)                       | push WMgrPort^.portBits (+$2) = dstBits
        BSR.B   MENUSELECT_CONT_4               | CopyBits saved -> screen
        MOVE.L  (SavedHandle).w,A0              | A0 = saved bits handle
        _DisposeHandle                          | free saved bits buffer
        RTS                                     | return from MENUSELECT_CONT_3
MENUSELECT_CONT_4:
        MOVE.L  (SP)+,D7                        | save return address
        PEA.L     -14(A6)                       | push srcRect (saved bounds)
        MOVE.L  (SP),-(SP)                      | push dstRect (same as src)
        CLR     -(SP)                           | srcCopy transfer mode
        CLR.L   -(SP)                           | maskRgn = nil
        _CopyBits                               | blit between BitMaps
        MOVE.L  D7,-(SP)                        | push D7 (result)
        RTS                                     | return via pushed address
MENUSELECT_NEWHANDLE_ERR:
        MOVEQ.L #0x19,D0                        | dsMemFullErr (25)
        _SysError                               | fatal: out of memory
| ----------------------------------------------------------
| MENUSELECT_CONT_5 | call subroutine via A0 | call subroutine via A0
| Called during boot.
MENUSELECT_CONT_5:
        MOVEM.L D4/A2-A4,-(SP)                  | save regs
        MOVE.L  #0x20002,D4                     | D4 = shadow offset (2,2 pixels)
        LEA.L     (scratch8).w,A3               | A3 = scratch rect (expanded for shadow)
        LEA.L     -28(A6),A4                    | A4 = menu rect (locals)
        MOVE.L  A4,A2                           | D0 = menu rect.right
        MOVE.L  A3,-(SP)                        | push right for LineTo end point
        MOVE.L  (A2)+,(A3)+                     | push menu.top for LineTo y
        MOVE.L  (A2),(A3)+                      | copy menu.botRight into scratch
        MOVE.L  #0xFFFCFFFC,-(SP)               | push right for MoveTo x
        _InsetRect                              | expand scratch by (-4,-4) for save area
        MOVEQ.L #0xF,D0                         | D0 = 15 (row-bytes alignment mask)
        ADD     -(A3),D0                        | D0 = 15 + scratch.right
        MOVE    -(A3),D1                        | D1 = scratch.bottom
        SUB     -(A3),D0                        | D0 = width + 15 (right - left)
        SUB     -(A3),D1                        | D1 = height (bottom - top)
        LSR     #0x4,D0                         | D0 = words per row ((width+15)/16)
        ADD     D0,D0                           | D0 = rowBytes (words * 2)
        MOVE    D0,-16(A6)                      | store rowBytes in local BitMap
        MULU    D1,D0                           | D0 = rowBytes * height = total bytes
        _NewHandle                              | allocate offscreen save buffer
        BNE.B   MENUSELECT_NEWHANDLE_ERR        | allocation failed -> SysError
        MOVE.L  A0,(SavedHandle).w              | store handle in SavedHandle
        MOVE.L  (A0),-20(A6)                    | store baseAddr in local BitMap
        MOVE.L  (A3)+,-14(A6)                   | store bounds.topLeft in BitMap
        MOVE.L  (A3),-10(A6)                    | store bounds.botRight in BitMap
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        PEA.L     0x2(A0)                       | push WMgrPort^.portBits (+$2) = srcBits
        PEA.L     -20(A6)                       | push local BitMap (dest)
        BSR.B   MENUSELECT_CONT_4               | CopyBits screen -> save buffer
        MOVE.L  A4,-(SP)                        | push menu rect
        _EraseRect                              | erase menu background
        _PenNormal                              | reset pen for frame drawing
        MOVE.L  (A2),-(SP)                      | push menu botRight (LineTo pt 3)
        MOVE.L  (SP),-(SP)                      | dup for LineTo pt 2
        MOVE.L  (A4),-(SP)                      | push menu topLeft (LineTo pt 1)
        SUBQ.W  #0x1,2(SP)                      | topLeft.h -= 1 (left edge)
        MOVE.L  (SP),-(SP)                      | dup for MoveTo start
        MOVE    (A2),4(SP)                      | overwrite pt2.v = botRight.v
        MOVE    (A4),12(SP)                     | overwrite pt3.h = topLeft.h
        _MoveTo                                 | move to (left-1, top)
        _LineTo                                 | draw right edge down
        _LineTo                                 | draw bottom edge left
        _LineTo                                 | draw left edge up
        BSR.B   MENUSELECT_CONT_7               | draw 2-pixel shadow
        MOVE.L  A4,-(SP)                        | push menu rect
        _ClipRect                               | clip to menu area
        CLR     -(SP)                           | message 0 = mDrawMsg
        BSR.W   DISABLEITEM_NEXT                | A0=MenuInfo, A1=MenuHandle
        MOVE.L  A1,-(SP)                        | push MenuHandle
        MOVE.L  A4,-(SP)                        | push menu rect
        SUBQ.W  #0x8,SP                         | space for hitPt + whichItem (unused)
        BSR.B   MENUSELECT_CONT_8               | restore full clip
        JSR     (A0)                            | call hilite-revert routine via A0 (per-MDEF)
        BSR.B   MENUSELECT_CONT_9               | unlock MDEF handle
        BSR.W   FullClip                        | restore full clip
        MOVEM.L (SP)+,D4/A2-A4                  | restore saved regs
        RTS                                     | return from MENUSELECT_CONT_5
MENUSELECT_CONT_7:
        MOVE.L  D4,-(SP)                        | push pen size (2,2)
        _PenSize                                | set pen to 2x2 for shadow
        MOVE    0x6(A4),D0                      | D0 = rect.right
        MOVE    D0,-(SP)                        | push rect.right
        MOVE    (A4),-(SP)                      | push rect.top (LineTo y)
        ADD     D4,(SP)                         | (SP) += D4
        MOVE    D0,-(SP)                        | push rect.right (LineTo x)
        MOVE    4(A4),D0                        | D0 = rect.bottom
        MOVE    D0,-(SP)                        | push rect.bottom
        MOVE    2(A4),-(SP)                     | push rect.left
        ADD     D4,(SP)                         | (SP) += D4
        MOVE    D0,-(SP)                        | call subroutine via A0
        _MoveTo                                 | move pen to start
        _LineTo                                 | draw shadow segment 1
        _LineTo                                 | draw shadow segment 2
        _PenNormal                              | restore default pen
        RTS                                     | return from MENUSELECT_CONT_7
MENUSELECT_CONT_8:
        MOVE.L  6(A0),A0                        | A0 = menuProc handle (MDEF)
        MOVE.L  A0,-(SP)                        | push handle for LoadResource
        _LoadResource                           | load MDEF resource if purged
        BSET    #0x7,(A0)                       | lock MDEF handle during call
        MOVE.L  (A0),A0                         | A0 = MDEF code address
        RTS                                     | return from MENUSELECT_CONT_8
MENUSELECT_CONT_9:
        BSR.W   DISABLEITEM_NEXT                | A0 = MenuInfo for D5
MENUSELECT_CONT_10:
        MOVE.L  6(A0),A0                        | A0 = menuProc handle (MDEF)
        BCLR    #0x7,(A0)                       | unlock MDEF handle
        RTS                                     | return from MENUSELECT_CONT_10

| ----------------------------------------------------------
| MENUSELECT_CONT_11
| Called during boot.
MENUSELECT_CONT_11:
        MOVE    D4,-(SP)                        | save D4 (current menu offset)
        MOVE    (MenuFlash).w,D4                | D4 = flash count (from PRAM)
        BEQ.B   MENUSELECT_SKIP_3               | flash disabled -> skip
        MOVE    14(A6),(ToolScratch).w          | ToolScratch = selected item number
        BEQ.B   MENUSELECT_SKIP_3               | no item selected -> skip
        PEA.L     -28(A6)                       | push menu rect
        _ClipRect                               | clip to menu area
MENUSELECT_LOOP_3:
        MOVEQ.L #0x0,D1                         | message to MDEF: 0 (un-highlight)
        BSR.B   FULLCLIP_CONT                   | send msg to MDEF + delay 3 ticks
        MOVE.L  D3,D1                           | message to MDEF: D3 (highlight)
        BSR.B   FULLCLIP_CONT                   | send msg to MDEF + delay 3 ticks
        SUBQ.W  #0x1,D4                         | decrement flash count
        BNE.B   MENUSELECT_LOOP_3               | more flashes -> loop
        BSR.B   FullClip                        | restore full screen clip
MENUSELECT_SKIP_3:
        MOVE.W   (SP)+,D4                       | restore D4
        RTS                                     | return from MENUSELECT_SKIP_3
| Called by: DrawMenuBar, HiliteMenu, MenuSelect, MENUSELECT_SKIP_2, MENUSELECT_CONT_5 (and 2 more)
FullClip:
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        PEA.L     16(A0)                        | push WMgr portRect
        _ClipRect                               | clip to full screen
        RTS                                     | return from FullClip
FULLCLIP_CONT:
        MOVE    #0x1,-(SP)                      | message 1 = mChooseMsg
        BSR.W   DISABLEITEM_NEXT                | A0=MenuInfo, A1=MenuHandle
        MOVE.L  A1,-(SP)                        | push MenuHandle
        PEA.L     -28(A6)                       | push menu rect
        MOVE.L  D1,-(SP)                        | push hitPt (D1)
        PEA.L     (ToolScratch).w               | push ptr to itemNumber
        BSR.B   MENUSELECT_CONT_8               | load MDEF code -> A0
        JSR     (A0)                            | call subroutine via A0
        BSR.B   MENUSELECT_CONT_9               | unlock MDEF handle
        MOVE.L  (Ticks).w,D0                    | D0 = current Ticks
        ADDQ.L  #0x3,D0                         | target = now + 3 ticks
FULLCLIP_NO:
        CMP.L   (Ticks).w,D0                    | target reached?
        BGT.B   FULLCLIP_NO                     | no -> spin wait
        RTS                                     | return from FULLCLIP_NO

| ----------------------------------------------------------
|
| _GetMenuBar ($A93B)
|
| _GetMenuBar ($A93B): FUNCTION GetMenuBar: Handle;
| Allocates a new MenuList Handle (102 bytes) and copies the
| current MenuList contents into it. Returns the new handle.
|
GetMenuBar:
        BSR.W   INITMENUS_NEWLIST               | allocate new MenuList -> A0 (Plus: CALCMBHEIGHT_EMPTY)
        MOVE.L  A0,0x4(SP)                      | store as return value (Handle)
        MOVE.L  (A0),A1                         | A1 = dest (new list data)
        MOVE.L  (MenuList).w,A0                 | A0 = MenuList handle
GETMENUBAR_CONT:
        MOVE.L  (A0),A0                         | A0 = source (current MenuList data)
        MOVEQ.L #0x66,D0                        | 102 bytes to copy
        _BlockMove                              | copy MenuList data from A0 to A1
        RTS                                     | return from GETMENUBAR_CONT

| ----------------------------------------------------------
|
| _SetMenuBar ($A93C)
|
| _SetMenuBar ($A93C): PROCEDURE SetMenuBar(menuList: Handle);
| Replaces the current MenuList contents with the caller's handle.
|
SetMenuBar:
        MOVE.L  0x4(SP),A0                      | A0 = caller's MenuList handle
        MOVE.L  (MenuList).w,A1                 | A1 = current MenuList handle
        MOVE.L  (A1),A1                         | dereference dest
        MOVE.L  (SP)+,(SP)                      | strip caller's param
        BRA.B   GETMENUBAR_CONT                 | -> BlockMove + return

| ----------------------------------------------------------
|
| _DisposMenu ($A932): dispose of a menu
| Pascal: PROCEDURE DisposeMenu(theMenu: MenuHandle);
| Disposes the MenuHandle with _DisposHandle.;
| the Plus first checks the resource bit (BTST #5,(A0)) and releases
| resource menus with _ReleaseResource, the 1984 ROM always disposes.
| Apple source name: DisposeMenu (MacSEROM.lst: DISPOSEMENU)
|
DisposMenu:
        MOVE.L  0x4(SP),A0                      | A0 = MenuHandle to dispose
        _DisposeHandle                          | free the handle
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from DisposMenu

| ----------------------------------------------------------
|
| _FlashMenuBar ($A94C)
|
| Classic's 1984 implementation: simpler than Plus -- does not save
| and restore the WMgrPort clipRgn around the flash; just sets it,
| flashes, and returns. Plus added the HandToHand/CopyRgn save dance
| so multitasking-friendly callers don't lose their clip state.
|
FlashMenuBar:
        MOVE.L  D4,-(SP)                        | save D4 (used by GetSetWPort)
        JSR     GetSetWPort(PC)                 | save port, switch to WMgr
        BSR.B   FullClip                        | set clip to full port rect
        MOVE    0x8(SP),D1                      | D1 = menuID to flash
        BEQ.B   FLASHMENUBAR_EMPTY              | zero -> flash entire menu bar
        BSR.W   DISABLEITEM_CONT_4              | invert specific menu title
FLASHMENUBAR_EXIT:
        JSR     RestorePort(PC)                 | restore original port
        MOVE.L  (SP)+,D4                        | restore D4
        BRA.W   DELETEMENU_EXIT                 | -> strip param and return

| ----------------------------------------------------------
|
| FLASHMENUBAR_EMPTY - flash entire menu bar (invert rounded rect)
|
FLASHMENUBAR_EMPTY:
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        PEA.L   0x10(A0)                        | push portRect (for InverRoundRect)
        MOVE.L  0x1C(A0),-(SP)                  | push clipRgn for SetRecRgn
        CLR.L   -(SP)                           | top=0, left=0
        MOVE    0x16(A0),-(SP)                  | push screen width (right)
        MOVE    #0x14,-(SP)                     | bottom = 20 (menu bar area)
        _SetRectRgn                             | clip to menu bar rect
        MOVE.L  #0x00100010,-(SP)               | corner radius 16x16
        _InvertRoundRect                        | invert menu bar with rounded corners
        BRA.B   FLASHMENUBAR_EXIT               | -> restore and return

| ----------------------------------------------------------
|
| RETURNS_16 - find Nth menu item in MenuInfo data
|
| A0 = dereferenced MenuHandle, D0 = item number (1-based)
| Returns: A0 = ptr to item title, A1 = ptr to item attributes
| (icon, key, mark, style)
| D0/A0/A1 = 0 if item not found
| Called during boot (22,222 times in 30s trace).
RETURNS_16:
        TST     D0                              | valid item number?
        BLE.B   MENUMGR_FOUND                   | no ->
        MOVEQ.L #0x0,D1                         | clear for byte extend
        LEA.L     menuData(A0),A1               | A1 = start of menu title string
        MOVE.B  (A1)+,D1                        | D1 = title length
        ADDA.W  D1,A1                           | skip title -> first item

| walk through items to find the Nth one
MENUMGR_NEXT:
        SUBQ.W  #0x1,D0                         | count down
        BEQ.B   RETURNS_17                      | reached Nth item -> extract
        MOVE.B  (A1)+,D1                        | D1 = item title length byte
        BEQ.B   MENUMGR_FOUND                   | 0 = end of items ->
        ADDQ.W  #0x4,D1                         | skip 4 attribute bytes after title
        ADDA.W  D1,A1                           | skip to next item
        BRA.B   MENUMGR_NEXT                    | -> check next item
MENUMGR_FOUND:
        SUBA.L  A0,A0                           | A0 = nil (not found)
        MOVE.L  A0,A1                           | A1 = nil
        MOVE.L  A0,D0                           | D0 = 0 (Z set: not found)
        RTS                                     | return from MENUMGR_FOUND

| ----------------------------------------------------------
| RETURNS_17
| Called during boot (22,222 times in 30s trace).
| Found item entry point: A1 points to item title
| Returns: A0 = title ptr, A1 = attribute bytes after title
RETURNS_17:
        TST.B   (A1)                            | zero-length title = end sentinel?
        BEQ.B   MENUMGR_FOUND                   | yes -> not found, return nil
        MOVE.L  A1,A0                           | A0 = ptr to item title
        MOVE.B  (A1)+,D1                        | D1 = title length, A1 past length byte
        ADDA.W  D1,A1                           | A1 = ptr to attribute bytes (icon,key,mark,style)
        RTS                                     | return from RETURNS_17
MENUMGR_CONT:
        MOVE.L  8(SP),A0                        | A0 = MenuHandle param
        MOVE.L  (A0),A0                         | A0 = MenuInfo (deref handle)
        MOVE    6(SP),D0                        | D0 = item number param
        BSR.B   RETURNS_16                      | locate Nth item -> A1=attrs
        BEQ.B   MENUMGR_SKIP                    | item not found -> skip write
        MOVE.B  5(SP),0(A1,D2.W)                | store new attribute byte
        MOVE.L  8(SP),-(SP)                     | push MenuHandle
        _CalcMenuSize                           | recompute menu size
MENUMGR_SKIP:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | RTS
MENUMGR_CONT_2:
        MOVE.L  10(SP),A0                       | A0 = MenuHandle param
        MOVE.L  (A0),A0                         | A0 = MenuInfo (deref handle)
        MOVE    8(SP),D0                        | D0 = item number param
        BSR.B   RETURNS_16                      | locate Nth item -> A1=attrs
        MOVE.L  4(SP),A0                        | A0 = VAR result ptr
        CLR     (A0)                            | clear high word of result
        MOVE.L  A1,D0                           | test: item found?
        BEQ.B   MENUMGR_NO                      | not found -> result = 0
        MOVE.B  0(A1,D2.W),1(A0)                | VAR result.lo = attribute byte
MENUMGR_NO:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
|
| Item attribute accessors - D2 selects which attribute byte:
| 0 = icon number, 1 = key equivalent, 2 = mark character, 3 = style
| Get variants -> MENUMGR_CONT_2 (read), Set variants -> MENUMGR_CONT (write)

| _GetItmIcon ($A93F)
GetItmIcon:
        MOVEQ.L #0x0,D2                         | attribute index 0 = icon
        BRA.B   MENUMGR_CONT_2                  | -> get

| _SetItmIcon ($A940)
SetItmIcon:
        MOVEQ.L #0x0,D2                         | attribute index 0 = icon
        BRA.B   MENUMGR_CONT                    | -> set

| _GetItmStyle ($A941)
GetItmStyle:
        MOVEQ.L #0x3,D2                         | attribute index 3 = style
        BRA.B   MENUMGR_CONT_2                  | -> get

| _SetItmStyle ($A942)
SetItmStyle:
        MOVEQ.L #0x3,D2                         | attribute index 3 = style
        BRA.B   MENUMGR_CONT                    | -> set

| _GetItmMark ($A943)
GetItmMark:
        MOVEQ.L #0x2,D2                         | attribute index 2 = mark char
        BRA.B   MENUMGR_CONT_2                  | -> get

| _SetItmMark ($A944)
SetItmMark:
        MOVEQ.L #0x2,D2                         | attribute index 2 = mark char
        BRA.B   MENUMGR_CONT                    | -> set

| ----------------------------------------------------------
|
| _CheckItem ($A945)
|
| _CheckItem ($A945): set or clear the checkmark on a menu item
| Pascal: procedure CheckItem(theMenu: MenuHandle; item: INTEGER;
| checked: BOOLEAN);
| If checked, sets mark to checkmark character (chr 18); else clears it.
CheckItem:
        TST.B   0x4(SP)                         | checked?
        BEQ.B   CHECKITEM_NO                    | no -> clear mark
        MOVE    #0x12,0x4(SP)                   | set mark to checkmark char ($12)
        BRA.B   SetItmMark                      | -> SetItmMark
CHECKITEM_NO:
        CLR     0x4(SP)                         | set mark to 0 (no mark)
        BRA.B   SetItmMark                      | forward to SetItmMark

| ----------------------------------------------------------
|
| _MenuKey ($A93E)
|
| _MenuKey ($A93E): find menu item matching a Command-key equivalent
| Pascal: function MenuKey(ch: CHAR): LongInt; (high=menuID, low=item)
MenuKey:
        MOVEM.L D3-D5/A3,-(SP)                  | save working registers
        MOVE.B  0x15(SP),D4                     | D4 = target key character from stack
        CMPI.B  #0x60,D4                        | is key lowercase?
        BLT.B   MENUMGR_CONT_5                  | no, already uppercase
        SUBI.B  #0x20,D4                        | yes, convert to uppercase
MENUMGR_CONT_5:
        MOVE.L  (MenuList).w,A0                 | A0 = MenuList handle
        MOVE.L  (A0),A0                         | dereference
        MOVE    (A0),D5                         | D5 = number of menus in bar
| scan each menu for matching key equivalent
MENUKEY_NEXT:
        BSR.W   DISABLEITEM_NEXT                | get next menu -> A0 = MenuHandle
        MOVE.L  A0,A3                           | A3 = dereferenced MenuInfo
        BTST    #0x0,13(A3)                     | menu enabled? (enableFlags bit 0)
        BEQ.B   MENUKEY_SKIP_2                  | menu disabled -> next menu
        MOVEQ.L #0x1,D3                         | D3 = item number (start at 1)
MENUKEY_NEXT_2:
        MOVE.L  menuEnable(A3),D0               | D0 = enableFlags
        BTST    D3,D0                           | this item enabled?
        BEQ.B   MENUKEY_SKIP                    | disabled -> next item
        MOVE.L  A3,A0                           | A0 = MenuInfo
        MOVE    D3,D0                           | D0 = item number
        BSR.W   RETURNS_16                      | find item -> A1 = attributes
        BEQ.B   MENUKEY_SKIP_2                  | past last item -> next menu
        MOVE.B  1(A1),D0                        | D0 = item's key equivalent
        CMPI.B  #0x60,D0                        | already uppercase?
        BLT.B   MENUKEY_UPPER                   | yes -> compare as-is
        SUBI.B  #0x20,D0                        | convert lowercase to upper
MENUKEY_UPPER:
        CMP.B   D0,D4                           | matches target key?
        BEQ.B   MENUKEY_FOUND                   | yes -> hilite and return
MENUKEY_SKIP:
        ADDQ.W  #0x1,D3                         | next item number
        BRA.B   MENUKEY_NEXT_2                  | loop
MENUKEY_SKIP_2:
        SUBQ.W  #0x6,D5                         | advance to next menu (6 bytes/entry in MenuList)
        BNE.B   MENUKEY_NEXT                    | more menus -> continue
        CLR.L   22(SP)                          | no match found: result = 0
MENUKEY_DONE:
        MOVEM.L (SP)+,D3-D5/A3                  | restore saved regs
        BRA.W   DELETEMENU_EXIT                 | strip param and return

| ----------------------------------------------------------
| MENUKEY_FOUND: key match found - hilite menu and return menuID:item
MENUKEY_FOUND:                                  | call subroutine via A0
        BSR.W   DISABLEITEM_NEXT                | get matching menu's MenuHandle -> A0
        MOVE    (A0),D0                         | D0.w = menuID of matching menu
        SWAP    D0                              | menuID -> high word
        MOVE    D3,D0                           | item number -> low word
        MOVE.L  D0,22(SP)                       | store result (menuID<<16 | item)
        SWAP    D0                              | D0.w = menuID again
        MOVE    D0,-(SP)                        | push menuID
        _HiliteMenu                             | hilite the matched menu title
        TST     (MBarEnable).w                  | desk accessory menu bar active?
        BMI.B   MENUKEY_OK                      | yes, route to SystemMenu ->
        MOVE.L  22(SP),D0                       | D0 = result (menuID:item)
        BPL.B   MENUKEY_DONE                    | positive menuID = app menu, done ->
MENUKEY_OK:
        MOVE.L  D0,-(SP)                        | dereference MenuHandle
        _SystemMenu                             | dispatch to system/DA handler
        CLR.L   22(SP)                          | clear result (system handled)
        BRA.B   MENUKEY_DONE                    | restore regs and return

| ----------------------------------------------------------
|
| _GetItem ($A946): return the text of a menu item
| Pascal: PROCEDURE GetItem(theMenu: MenuHandle; item: INTEGER;
|                           VAR itemString: Str255);
| Finds the item (RETURNS_16) and copies its Pascal string to
| itemString; returns the empty string if the item does not exist.
|
GetItem:
        MOVE.L  0xA(SP),A0                      | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference -> MenuInfo ptr
        MOVE    0x8(SP),D0                      | D0 = item number
        BSR.W   RETURNS_16                      | find item -> A0 = item string, Z if none
        MOVE.L  0x4(SP),A1                      | A1 = destination string buffer
        BEQ.B   GETITEM_EXIT                    | item not found -> return empty
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A0),D0                         | D0 = title length
        ADDQ.W  #0x1,D0                         | +1 for length byte itself
        _BlockMove                              | copy Pascal string: A0 -> A1, D0 bytes
GETITEM_CONT:
        BRA.W   MENUMGR_NO                      | -> strip 10 bytes of params
GETITEM_EXIT:
        CLR.B   (A1)                            | return empty string (length=0)
        BRA.B   GETITEM_CONT                    | -> strip params

| ----------------------------------------------------------
|
| _CalcMenuSize ($A948)
|
| _CalcMenuSize ($A948): calculate menu dimensions via MDEF
| Sends mSizeMsg (2) to the menu's MDEF to compute width/height
CalcMenuSize:
        MOVE    #0x2,-(SP)                      | push mSizeMsg
        MOVE.L  0x6(SP),A0                      | A0 = MenuHandle
        MOVE.L  A0,-(SP)                        | push theMenu
        SUBA.W  #0xC,SP                         | push menuRect+hitPt+whichItem placeholders
        MOVE.L  (A0),A0                         | dereference -> MenuInfo
        BSR.W   MENUSELECT_CONT_8               | get MDEF proc pointer -> A0
        JSR     (A0)                            | call MDEF with mSizeMsg
        MOVE.L  0x4(SP),A0                      | get MenuHandle back
        MOVE.L  (A0),A0                         | dereference
        BSR.W   MENUSELECT_CONT_10              | store computed width/height in MenuInfo
        MOVE.L  (SP)+,(SP)                      | strip 4-byte param (shift ret addr down)
        RTS                                     | return from CalcMenuSize

| ----------------------------------------------------------
|
| RETURNS_18 - test if menu item D4 is enabled
|
| Checks both the item bit and the menu-global enable bit (bit 0).
| A3 = MenuHandle, D4 = item number.
| Returns: Z=1 if disabled (either item bit or menu-global bit 0 is clear).
RETURNS_18:
        MOVE.L  (A3),A0                         | dereference MenuHandle
        MOVE.L  menuEnable(A0),D0               | D0 = enableFlags longword
        BTST    D4,D0                           | test item's enable bit
        BEQ.B   CALCMENUSIZE_EXIT_2             | item disabled -> return Z=1
        BTST    #0x0,D0                         | test menu-global enable (bit 0)
CALCMENUSIZE_EXIT_2:
        RTS                                     | return from CALCMENUSIZE_EXIT_2

| ----------------------------------------------------------
|
| _NewMenu ($A931)
|
| _NewMenu ($A931): create a new menu
| Pascal: function NewMenu(menuID: INTEGER; menuTitle: Str255): MenuHandle;
NewMenu:
        MOVEQ.L #0x0,D1                         | clear for byte extend
        MOVEQ.L #0x10,D0                        | base size = 16 (MenuInfo header)
        MOVE.L  0x4(SP),A0                      | A0 = title string
        MOVE.B  (A0),D1                         | D1 = title length
        ADD     D1,D0                           | + title bytes
        _NewHandle                              | allocate MenuInfo
        MOVE.L  A0,0xA(SP)                      | store result handle (return value)
| fill MenuInfo header
        MOVE.L  (A0),A1                         | A1 = dereferenced MenuInfo
        MOVE    D1,-(SP)                        | save title length
        MOVE    0xA(SP),(A1)+                   | menuID from stack param
        CLR.L   (A1)+                           | menuWidth = 0, menuHeight = 0
| load default MDEF 0
        SUBQ.W  #0x4,SP                         | space for handle
        MOVE.L  #0x4D444546,-(SP)               | 'MDEF' resource type
        CLR     -(SP)                           | MDEF ID 0
        _GetResource                            | load MDEF 0
        MOVE.L  (SP)+,A0                        | A0 = MDEF handle
        MOVE.L  0xC(SP),A1                      | A1 = our MenuHandle
        MOVE.L  (A1),A1                         | dereference
        ADDQ.W  #0x6,A1                         | skip to menuProc field
        MOVE.L  A0,(A1)+                        | menuProc = MDEF handle
        MOVE.L  (MinusOne).w,(A1)+              | enableFlags = all enabled ($FFFFFFFF)
| copy menu title into menuData
        MOVE    (SP)+,D1                        | restore title length
        MOVE.L  0x4(SP),A0                      | A0 = title string
NEWMENU_LOOP:
        MOVE.B  (A0)+,(A1)+                     | copy title (including length byte)
        DBRA    D1,NEWMENU_LOOP                 | loop over title string
        CLR.B   (A1)+                           | terminate item list with 0
        BRA.W   INSERTMENU_CONT_EXIT            | -> strip params and return

| ----------------------------------------------------------
|
| _AppendMenu ($A933): append one or more items to a menu
| Pascal: PROCEDURE AppendMenu(theMenu: MenuHandle; data: Str255);
| Parses data one character at a time (APPENDMENU_CONT_3): items are
| separated by ';' or CR; '^' icon number, '/' key equivalent, '!' mark
| character and '<' style letter (B/I/U/O/S) set an attribute from the
| next character; '(' disables the item. Each item is added at the end
| of the item list (APPENDMENU_NO_5), then CalcMenuSize is called.
| Classic's 1984 implementation appends only -- Plus added InsMenuItem
| and turned AppendMenu into a thin wrapper around it.
|
AppendMenu:
        LINK    A6,#-0x118                      | set up stack frame (280 bytes locals)
        MOVEM.L D3-D4/A3-A4,-(SP)               | save registers
        MOVE.L  0x8(A6),A4                      | A4 = item data string
        MOVE.L  0xC(A6),A3                      | A3 = MenuHandle
        CLR     D3                              | clear item string length counter
        MOVE.B  (A4)+,D3                        | D3 = length of item data string
        BSR.B   APPENDMENU_NEXT                 | init parse state (clear attr buffer)
        SUBQ.W  #0x1,D3                         | adjust for DBF loop
APPENDMENU_LOOP:
        MOVE.B  (A4)+,D0                        | D0 = next char from data string
        BSR.B   APPENDMENU_CONT_3               | process one char (parse state machine)
        DBRA    D3,APPENDMENU_LOOP              | loop through all chars
        BSR.W   APPENDMENU_NO_5                 | flush last item into menu
        MOVE.L  A3,-(SP)                        | push MenuHandle
        _CalcMenuSize                           | recompute menu size after appends
        MOVEM.L (SP)+,D3-D4/A3-A4               | restore saved regs
        UNLK    A6                              | tear down frame
        BRA.W   MENUMGR_SKIP                    | strip params and return

| ----------------------------------------------------------
| APPENDMENU_NEXT: clear the item parse state in the local frame:
| -0x114(A6): parse state (metachar pending), -0x113: disable flag,
| -0x112: title length (word), -0x110..-0x10D: icon, key equivalent,
| mark and style bytes. The title text is collected at -0x10C(A6).
| Called during boot.
APPENDMENU_NEXT:
        LEA.L     -0x114(A6),A0                 | A0 = parse state / disable flag / title length
        CLR.L   (A0)+                           | clear parse state, disable flag, title length
        CLR.L   (A0)                            | clear icon, key, mark, style bytes
        RTS                                     | return from APPENDMENU_NEXT
APPENDMENU_CONT_2:                              | METACHAR_TBL: ^ / ! < CR ; ( then BIUOS
        ADDQ.B  #0x7,0x213C(SP)                 | data, not code: bytes '^' '/' '!' '<'
| The 7 metacharacters (indices 0-6: '^' '/' '!' '<' CR ';' '(') are
| followed by the 5 style letters "BIUOS" (bold..shadow = style bits 0-4).
        .short  0x0D3B, 0x2842                  | bytes CR ';' '(' 'B'
        .ascii  "IUOS"                          | style letters Italic/Underline/Outline/Shadow

| APPENDMENU_CONT_3: process one character from menu item data string
| D0 = current char, parse state in local frame
| State 0: check if char is metachar or title text
| State 1 (after '^'): char is icon number (ASCII digit -> binary)
| State 2 (after '/'): char is key equivalent
| State 3 (after '!'): char is mark character
| State 4 (after '<'): char is style letter (B/I/U/O/S)
APPENDMENU_CONT_3:
        CLR     D1                              | clear high byte
        MOVE.B  -0x114(A6),D1                   | D1 = current parse state
        BEQ.B   APPENDMENU_NO_3                 | state 0: no metachar pending ->
        CMPI.B  #0x1,D1                         | state 1: icon number pending?
        BNE.B   APPENDMENU_NO                   | no ->
        SUBI    #0x30,D0                        | convert ASCII digit to binary ('0'=0x30)
APPENDMENU_NO:
        CMPI.B  #0x4,D1                         | state 4: style letter pending?
        BNE.B   APPENDMENU_NO_2                 | no -> store directly as attribute
        MOVEQ.L #0x4,D2                         | D2 = 4 (scan style table from end)
APPENDMENU_LOOP_2:
        CMP.B   -0x21(PC,D2.W),D0               | D0 == BIUOS_TABLE[D2]?
        BEQ.B   APPENDMENU_OK                   | yes -> set style bit
        DBRA    D2,APPENDMENU_LOOP_2            | try next style letter
        RTS                                     | unknown style letter, ignore
APPENDMENU_OK:
        LEA.L     -0x111(A6),A0                 | A0 = attribute[state] base (state 4 = style)
        MOVE.B  0(A0,D1.W),D0                   | D0 = current style byte
        BSET    D2,D0                           | set style bit (B/I/U/O/S)
APPENDMENU_NO_2:
        LEA.L     -0x111(A6),A0                 | A0 = attribute base
        MOVE.B  D0,0(A0,D1.W)                   | store value at attribute[state]
        CLR.B   -0x114(A6)                      | reset parse state to 0 (normal)
        RTS                                     | return from APPENDMENU_NO_2
APPENDMENU_NO_3:
        LEA     APPENDMENU_CONT_2(PC),A0        | A0 = METACHAR_TBL
        MOVE    #0x6,D1                         | D1 = 6 (scan from end of table)
APPENDMENU_LOOP_3:
        CMP.B   0(A0,D1.W),D0                   | char matches metachar[D1]?
        BEQ.B   APPENDMENU_OK_2                 | yes -> handle metachar
        DBRA    D1,APPENDMENU_LOOP_3            | try next metachar
        MOVE    -0x112(A6),D1                   | D1 = current title length
        LEA.L     -0x10C(A6),A0                 | A0 = title buffer
        MOVE.B  D0,0(A0,D1.W)                   | append char to title buffer
        ADDQ.W  #0x1,-0x112(A6)                 | increment title length
        RTS                                     | return from APPENDMENU_LOOP_3

| ----------------------------------------------------------
| APPENDMENU_OK_2: matched metachar at index D1 in METACHAR_TBL
| Indices 0-3 (^ / ! <): set parse state to D1+1 for the next char
| Index 4 (CR) or 5 (;): item separator -> flush current item
| Index 6 (open paren): mark item as disabled
APPENDMENU_OK_2:
        CMPI    #0x3,D1                         | metachar index <= 3?
        BGT.B   APPENDMENU_NO_4                 | no, index 4-6 -> separator or disable
        ADDQ.W  #0x1,D1                         | state = index+1 (1=icon,2=key,3=mark,4=style)
        MOVE.B  D1,-0x114(A6)                   | set parse state for next char
        RTS                                     | return from APPENDMENU_OK_2
APPENDMENU_NO_4:
        SUBQ.W  #0x6,D1                         | index 6 ('(')? -> D1=0
        BNE.B   APPENDMENU_NO_5                 | no, it's CR or ';' -> flush item
        ST      -0x113(A6)                      | set disable flag for current item
        RTS                                     | return from APPENDMENU_NO_4
APPENDMENU_NO_5:
        MOVE    -0x112(A6),D1                   | D1 = current title length
        BEQ.B   APPENDMENU_NO_6                 | empty title -> reset state only
        MOVE.L  A3,A0                           | A0 = MenuHandle
        _GetHandleSize                          | D0 = current MenuInfo size
        ADDQ.W  #0x5,D0                         | + 5 (length byte + 4 attribute bytes)
        ADD     D1,D0                           | + new title length
        _SetHandleSize                          | grow MenuInfo for new item
        CLR     D0                              | clear high byte
        MOVE.L  (A3),A1                         | A1 = MenuInfo (deref handle)
        LEA.L     14(A1),A1                     | A1 = menu title start
        MOVE.B  (A1)+,D0                        | D0 = title length
        ADDA.W  D0,A1                           | A1 = first item
        MOVEQ.L #0x1,D2                         | D2 = 1 (item count, 1-based)
APPENDMENU_FIND_END:
        MOVE.B  (A1),D0                         | D0 = item title length byte
        BEQ.B   APPENDMENU_OK_2_CONT_2          | 0 = end of items, append here
        ADDA.W  D0,A1                           | skip title bytes
        ADDQ.W  #0x5,A1                         | skip length + 4 attr bytes
        ADDQ.W  #0x1,D2                         | increment item count
        BRA.B   APPENDMENU_FIND_END             | loop
APPENDMENU_OK_2_CONT_2:
        LEA.L     -0x10C(A6),A0                 | A0 = title buffer ptr
        MOVE.B  D1,(A1)+                        | write item title length byte
APPENDMENU_OK_2_NO_3:
        MOVE.B  (A0)+,(A1)+                     | copy title char
        SUBQ.W  #0x1,D1                         | decrement remaining count
        BNE.B   APPENDMENU_OK_2_NO_3            | more chars -> continue
        LEA.L     -0x110(A6),A0                 | A0 = attribute buffer (icon..style)
        MOVE    #0x3,D1                         | 4 attribute bytes (DBRA: 0..3)
APPENDMENU_ATTR_COPY:
        MOVE.B  (A0)+,(A1)+                     | copy attribute byte
        DBRA    D1,APPENDMENU_ATTR_COPY         | loop 4 times
        CLR.B   (A1)+                           | terminate item list with 0
        TST.B   -0x113(A6)                      | disable flag set?
        BEQ.B   APPENDMENU_NO_6                 | no -> skip DisableItem
        MOVE.L  A3,-(SP)                        | push MenuHandle
        MOVE    D2,-(SP)                        | push item number
        BSR.W   DisableItem                     | disable the new item
APPENDMENU_NO_6:
        BSR.W   APPENDMENU_NEXT                 | reset attribute parse state
        RTS                                     | return from APPENDMENU_NO_6

| ----------------------------------------------------------
|
| _GetMHandle ($A949): return the handle of a menu in the menu list
| Pascal: FUNCTION GetMHandle(menuID: INTEGER): MenuHandle;
| Searches MenuList for menuID (INSERTMENU_CONT_2) and returns its
| MenuHandle, or NIL if the menu is not in the current menu list.
|
GetMHandle:
        CLR.L   6(SP)                           | result = nil initially
        MOVE    4(SP),D1                        | D1 = menuID to find
        BSR.W   INSERTMENU_CONT_2               | D0 = MenuList offset of menuID, Z if none
        BEQ.B   GETMHANDLE_FOUND                | not found ->
        MOVE    D5,-(SP)                        | save menu counter
        MOVE    D0,D5                           | D5 = MenuList offset
        BSR.W   DISABLEITEM_NEXT                | A1 = MenuHandle at that offset
        MOVE    (SP)+,D5                        | restore counter
        MOVE.L  A1,6(SP)                        | store result MenuHandle
GETMHANDLE_FOUND:                               | exit (also taken when not found)
        BRA.W   DELETEMENU_EXIT                 | strip param and return

| ----------------------------------------------------------
|
| _SetItem ($A947): change the text of a menu item
| Pascal: PROCEDURE SetItem(theMenu: MenuHandle; item: INTEGER;
|                           itemString: Str255);
| Replaces the item's string (including its length byte) by itemString
| with _Munger (ptr1 = NIL: replace at the item's offset), then calls
| CalcMenuSize. Does nothing if the item does not exist.
|
SetItem:
        MOVEM.L D3-D4/A2-A4,-(SP)               | save working registers
        MOVE.L  30(SP),A3                       | A3 = MenuHandle
        MOVE    28(SP),D3                       | D3 = item number
        MOVE.L  24(SP),A2                       | A2 = new item string
        MOVE    D3,D0                           | D0 = item number for RETURNS_16
        MOVE.L  (A3),A0                         | dereference MenuHandle
        BSR.W   RETURNS_16                      | find item -> A0 = old title ptr
        BEQ.B   SETITEM_FOUND                   | item not found -> exit
        MOVE.L  A0,A4                           | A4 = old title ptr
        SUBA.L  (A3),A4                         | A4 = byte offset within MenuInfo
        MOVEQ.L #0x1,D4                         | D4 = 1 (length byte)
        ADD.B   (A0),D4                         | D4 = old title length + 1
        MOVEQ.L #0x1,D2                         | D2 = 1 (length byte)
        ADD.B   (A2),D2                         | D2 = new title length + 1
        SUBQ.W  #0x4,SP                         | space for Munger result
        MOVE.L  A3,-(SP)                        | push MenuHandle
        MOVE.L  A4,-(SP)                        | push offset to old title
        CLR.L   -(SP)                           | ptr1 = nil (means at offset)
        MOVE.L  D4,-(SP)                        | push old length (bytes to remove)
        MOVE.L  A2,-(SP)                        | push new title string
        MOVE.L  D2,-(SP)                        | push new length (bytes to insert)
        _Munger                                 | splice new title into MenuInfo
        ADDQ.W  #0x4,SP                         | strip Munger result
        MOVE.L  A3,-(SP)                        | push MenuHandle
        _CalcMenuSize                           | recompute menu size
SETITEM_FOUND:                                  | exit (also taken when the item is missing)
        MOVEM.L (SP)+,D3-D4/A2-A4               | restore saved regs
        BRA.W   MENUMGR_NO                      | strip 10 bytes of params and return

| ----------------------------------------------------------
| SetMFlash -- _SetMFlash ($A94A).
| Pascal: procedure SetMFlash(count: INTEGER);
| Stores the menu-flash count (number of blinks on selection).
SetMFlash:
        MOVE    4(SP),(MenuFlash).w             | store flash count
        BRA.W   DELETEMENU_EXIT                 | -> strip params

| ----------------------------------------------------------
|
| _AddResMenu ($A94D): append the names of all resources of a type to a menu
| Pascal: PROCEDURE AddResMenu(theMenu: MenuHandle; theType: ResType);
| Pushes afterItem = 999 and falls into InsertResMenu.
|
AddResMenu:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE    #0x3E7,-(SP)                    | afterItem = 999 (append)
        MOVE.L  A0,-(SP)                        | push return address back
| _InsertResMenu ($A951): insert the names of all resources of a type
| Pascal: PROCEDURE InsertResMenu(theMenu: MenuHandle; theType: ResType;
|                                 afterItem: INTEGER);
| With ResLoad off, walks the resources of theType in index order
| (GetIndResource, GetResInfo), skipping unnamed ones and names that
| start with '.' or '%'. Each name becomes item afterItem+1, inserted
| with _Munger (empty attributes; enableFlags shifted, new bit set), or
| is appended with _AppendMenu if afterItem+1 is past the last item (as
| for AddResMenu's 999). Then CalcMenuSize and ResLoad on again.
| The Plus version scans 'FOND' before 'FONT' and inserts the names
| in alphabetical order.
| Note: theMenu is loaded into A4 only for a name that passes the filter;
| if every resource is skipped, CalcMenuSize gets the caller's A4.
InsertResMenu:
        LINK    A6,#-0x10E                      | set up stack frame
        MOVEM.L D3-D6/A3-A4,-(SP)               | save regs
        CLR     -(SP)                           | SetResLoad: don't auto-load resources
        _SetResLoad                             | disable resource loading (just names)
        SUBQ.W  #0x2,SP                         | space for CountResources result
        MOVE.L  10(A6),-(SP)                    | push resource type
        _CountResources                         | count resources of this type
        MOVE    (SP)+,D4                        | D4 = resource count
        BEQ.W   ADDRESMENU_EXIT                 | none found ->
        MOVEQ.L #0x1,D3                         | D3 = resource index (start at 1)
APPENDMENU_OK_2_CONT_5:                         | loop over the resources (index D3)
        SUBQ.W  #0x4,SP                         | space for GetIndResource result
        MOVE.L  10(A6),-(SP)                    | push resource type
        MOVE    D3,-(SP)                        | push resource index
        _GetIndResource                         | get nth resource of type
        LEA.L     -0x10E(A6),A3                 | A3 = local Str255 buffer
        PEA.L     -4(A6)                        | push VAR resID
        PEA.L     -8(A6)                        | push VAR theType
        MOVE.L  A3,-(SP)                        | push VAR name buffer
        _GetResInfo                             | fetch type/id/name of resource
        TST.B   (A3)                            | name length zero?
        BEQ.B   APPENDMENU_OK_2_CONT_6          | unnamed -> skip
        CMPI.B  #0x2E,1(A3)                     | first char '.' (driver)?
        BEQ.B   APPENDMENU_OK_2_CONT_6          | yes -> skip drivers
        CMPI.B  #0x25,1(A3)                     | first char '%' (DA)?
        BEQ.B   APPENDMENU_OK_2_CONT_6          | yes -> skip DAs
        MOVE.L  14(A6),A4                       | A4 = MenuHandle param
        MOVE.L  (A4),A0                         | A0 = MenuInfo (deref)
        MOVE    8(A6),D0                        | D0 = afterItem param
        ADDQ.W  #0x1,D0                         | D0 = insertion item number
        MOVE    D0,D6                           | D6 = saved item index for enable
        BSR.W   RETURNS_16                      | locate insertion point in menu
        BEQ.B   APPENDMENU_OK_2_CONT_7          | past end -> append
        MOVE.L  A0,D0                           | D0 = insertion ptr
        SUB.L   (A4),D0                         | D0 = byte offset within MenuInfo
        SUBQ.W  #0x4,SP                         | space for Munger result
        MOVE.L  A4,-(SP)                        | push MenuHandle
        EXT.L    D0                             | sign-extend offset to long
        MOVE.L  D0,-(SP)                        | push insert offset
        MOVE.L  A0,-(SP)                        | push ptr1 (current data ptr)
        CLR.L   -(SP)                           | push len1 = 0 (insert only)
        MOVEQ.L #0x0,D0                         | clear high byte
        MOVE.B  (A3),D0                         | D0 = name length
        LEA.L     1(A3,D0.W),A0                 | A0 = byte after name
        CLR.B   (A0)+                           | attribute icon = 0
        CLR.B   (A0)+                           | attribute key = 0
        CLR.B   (A0)+                           | attribute mark = 0
        CLR.B   (A0)+                           | attribute style = 0
        ADDQ.L  #0x5,D0                         | total bytes: name + 5 (lenbyte+attrs)
        MOVE.L  A3,-(SP)                        | push ptr2 (name + attrs)
        MOVE.L  D0,-(SP)                        | push len2 (insert byte count)
        _Munger                                 | splice item into MenuInfo
        ADDQ.W  #0x4,SP                         | strip Munger result
        MOVE.L  (A4),A0                         | A0 = updated MenuInfo
        MOVE.L  menuEnable(A0),D5               | D5 = old enableFlags
        MOVEQ.L #0x1F,D0                        | loop counter (32 bits, DBRA: 31..0)
APPENDMENU_OK_2_LOOP_2:
        ASL.L   #0x1,D5                         | shift old flags left
        ROXL.L  #0x1,D1                         | rotate carry into new flags
        CMP     D6,D0                           | at insertion item position?
        BNE.B   APPENDMENU_OK_2_NO_4            | no -> skip insert bit
        ASL.L   #0x1,D1                         | shift to make room for new bit
        ADDQ.W  #0x1,D1                         | set new item bit = 1 (enabled)
APPENDMENU_OK_2_NO_4:
        DBRA    D0,APPENDMENU_OK_2_LOOP_2       | loop 32 times
        MOVE.L  D1,menuEnable(A0)               | store new enableFlags
APPENDMENU_OK_2_CONT_6:
        ADDQ.W  #0x1,D3                         | next resource index
        CMP     D4,D3                           | past last resource?
        BLE.W   APPENDMENU_OK_2_CONT_5          | more -> continue scan
        MOVE.L  A4,-(SP)                        | push MenuHandle
        _CalcMenuSize                           | recompute menu size
ADDRESMENU_EXIT:
        MOVE    #0x100,-(SP)                    | push TRUE
        _SetResLoad                             | re-enable resource loading
        MOVEM.L (SP)+,D3-D6/A3-A4               | restore saved regs
        UNLK    A6                              | tear down frame
        BRA.W   MENUMGR_NO                      | strip params and return
APPENDMENU_OK_2_CONT_7:
        MOVE.L  A4,-(SP)                        | push MenuHandle (for AppendMenu)
        MOVE.L  A3,-(SP)                        | push name string (Str255)
        .short  0xA933                          | _AppendMenu(theMenu, name)
        BRA.B   APPENDMENU_OK_2_CONT_6          | next resource

| ----------------------------------------------------------
|
| _CountMItems ($A950)
|
| _CountMItems ($A950): count the items in a menu
| Pascal: function CountMItems(theMenu: MenuHandle): INTEGER;
| Walks items via RETURNS_16 until the search returns "not found".
CountMItems:
        MOVEQ.L #0x0,D2                         | D2 = item count (start at 0)
COUNTMITEMS_NEXT:
        ADDQ.W  #0x1,D2                         | try next item
        MOVE.L  0x4(SP),A0                      | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference
        MOVE    D2,D0                           | D0 = item number to find
        BSR.W   RETURNS_16                      | search for item D0
        BNE.B   COUNTMITEMS_NEXT                | found -> count next
        SUBQ.W  #0x1,D2                         | back up (last was past end)
        MOVE    D2,0x8(SP)                      | store result
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from COUNTMITEMS_NEXT

| ----------------------------------------------------------
|
| PlotIcon - blit a 32x32 icon resource into a destRect
|
| Stack: [ret, destRect, theIcon: Handle].
| Builds a temporary BitMap pointing at the icon data, then calls
| _CopyBits with srcCopy mode and no mask region.
|
PlotIcon:
        LEA.L   (IconBitmap).w,A1               | A1 = temp BitMap for icon
        MOVE.L  4(SP),D0                        | D0 = icon Handle
        BEQ.B   PLOTICON_SKIP                   | nil handle -> skip
        MOVE.L  D0,A0                           | A0 = icon Handle
        MOVE.L  (A0),(A1)+                      | BitMap.baseAddr = icon data ptr
        MOVE    #0x4,(A1)+                      | BitMap.rowBytes = 4 (32 pixels / 8)
        CLR.L   (A1)+                           | BitMap.bounds.topLeft = (0,0)
        MOVE.L  #0x00200020,(A1)                | BitMap.bounds.botRight = (32,32)
        MOVE.L  8(SP),D1                        | D1 = destRect ptr
        LEA.L     (IconBitmap).w,A1             | A1 = icon BitMap (repoint after writes)
        MOVE.L  A1,-(SP)                        | push srcBits (icon BitMap)
        MOVE.L  (A5),A0                         | A0 = QD globals ptr
        MOVE.L  (A0),A0                         | A0 = thePort
        PEA.L     0x2(A0)                       | push dstBits = thePort^.portBits (+$2)
        PEA.L     6(A1)                         | push srcRect (icon bounds at offset 6)
        MOVE.L  D1,-(SP)                        | push dstRect
        CLR     -(SP)                           | push mode = srcCopy (0)
        CLR.L   -(SP)                           | push maskRgn = nil
        _CopyBits                               | draw icon into port
PLOTICON_SKIP:
        BRA.W   MENUMGR_SKIP                    | strip 8 bytes of params and return

