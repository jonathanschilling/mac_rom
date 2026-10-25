| Menu Manager
|
| Apple source: MenuMgr.a (MacSEROM.lst module MMGR). In ROM order:
| InitMenus, ClearMenuBar, InsertMenu, DeleteMenu, DrawMenuBar,
| HiliteMenu, EnableItem, DisableItem, MenuSelect, GetMenuBar, SetMenuBar,
| DisposMenu, FlashMenuBar, the GetItemRecord helper (RETURNS_16), the item
| attribute accessors, CheckItem, MenuKey, GetItem, CalcMenuSize, NewMenu,
| AppendMenu/InsMenuItem (with the item-string parser), GetMHandle,
| DelMenuItem, SetItem, SetMFlash, AddResMenu/InsertResMenu, CountMItems,
| PlotIcon.
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
        RTS                                     | return from InitMenus

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
        RTS                                     | return from CalcMBHeight

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
        RTS                                     | return from CALCMBHEIGHT_CONT

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
        RTS                                     | return from CALCMBHEIGHT_LOOP

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
        RTS                                     | return from ClearMenuBar

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
        MOVE    lastRight(A3),D1                | D1 = lastRight (next x position)
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
        ADD     D3,lastRight(A3)                | advance lastRight by title width
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
        RTS                                     | return from INSERTMENU_FOUND_2

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
        RTS                                     | return from DELETEMENU_CONT_3

| ----------------------------------------------------------
|
| DELETEMENU_CONT_4
|
| Called during boot.
DELETEMENU_CONT_4:
        MOVE.L  (WMgrPort).w,A3                 | A3 = WMgr port
        MOVE.L  CLIPRGN(A3),-(SP)               | push clipRgn handle for SetRecRgn
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
        RTS                                     | return from DELETEMENU_CONT_4

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
        MOVE    D3,D0                           | D0 = offset for InverRect
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
        RTS                                     | return from DRAWMENUBAR_DONE

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
        RTS                                     | return from DRAWMENUBAR_CONT_2

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
        RTS                                     | return from ENABLEITEM_CONT

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
        RTS                                     | return from DISABLEITEM_EXIT

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
        RTS                                     | return from DISABLEITEM_CONT_2

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
        RTS                                     | return from DISABLEITEM_CONT_3

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
        RTS                                     | return from DISABLEITEM_SKIP

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
        RTS                                     | return from MENUSELECT_CONT_3

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
        RTS                                     | return from MENUSELECT_OK_3

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
        RTS                                     | return from MENUSELECT_EMPTY

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
        RTS                                     | return from MENUSELECT_CONT_7

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
        RTS                                     | return from MENUSELECT_EMPTY_2

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
        RTS                                     | return from MENUSELECT_EMPTY_3

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
        RTS                                     | return from MENUSELECT_SKIP_3

| ----------------------------------------------------------
|
| Full Clip
|
| Called during boot (28,789 times in 30s trace).
FullClip:
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        PEA.L   0x10(A0)                        | push portRect (full screen)
        _ClipRect                               | set clip to full port rect
        RTS                                     | return from FullClip

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
        RTS                                     | return from FULLCLIP_NO

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
        RTS                                     | return from GETMENUBAR_CONT

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
DisposMenu:
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
        RTS                                     | return from DISPOSEMENU_EXIT

| ----------------------------------------------------------
|
| _FlashMenuBar ($A94C)
|
FlashMenuBar:
        MOVE.L  D4,-(SP)                        | save D4 (used by GetSetWPort)
        MOVE.L  (WMgrPort).w,A0                 | A0 = WMgr port
        MOVE.L  0x1C(A0),A0                     | A0 = WMgr clipRgn handle
        MOVE.L  A0,-(SP)                        | push for DisposRgn later
        _HandToHand                             | duplicate clipRgn -> A0 = copy
        MOVE.L  (SP)+,D0                        | D0 = original clipRgn handle
        MOVE.L  A0,-(SP)                        | push copy for CopyRgn (source)
        MOVE.L  A0,-(SP)                        | push copy for DisposRgn
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
        PEA.L   0x10(A0)                        | push portRect (for InverRoundRect)
        MOVE.L  0x1C(A0),-(SP)                  | push clipRgn for SetRecRgn
        CLR.L   -(SP)                           | top=0, left=0
        MOVE    0x16(A0),-(SP)                  | push screen width (right)
        MOVE    #0x14,-(SP)                     | bottom = 20 (menu bar area)
        _SetRectRgn                             | clip to menu bar rect
        MOVE.L  #0x100010,-(SP)                 | corner radius 16x16
        _InvertRoundRect                        | invert menu bar with rounded corners
        BRA.B   FLASHMENUBAR_EXIT               | -> restore and return

| RETURNS_16: find Nth menu item in MenuInfo data
| A0 = dereferenced MenuHandle, D0 = item number (1-based)
| Returns: A0 = ptr to item title, A1 = ptr to item attributes (icon,key,mark,style)
| D0/A0/A1 = 0 if item not found
| Called by: MENUMGR_CONT, MENUMGR_CONT_2, MENUKEY_NEXT_2, GetItem, INSMENUITEM_CONT_4 (and 4 more)
RETURNS_16:
        TST     D0                              | valid item number?
        BLE.B   MENUMGR_FOUND                   | no ->
        MOVEQ.L #0x0,D1                         | clear for byte extend
        LEA.L   menuData(A0),A1                 | A1 = start of menu title string
        MOVE.B  (A1)+,D1                        | D1 = title length
        ADDA    D1,A1                           | skip title -> first item
| walk through items to find the Nth one
MENUMGR_NEXT:
        SUBQ.W  #0x1,D0                         | count down
        BEQ.B   RETURNS_17                      | found it ->
        MOVE.B  (A1),D1                         | item title length
        BEQ.B   MENUMGR_FOUND                   | 0 = end of items ->
        ADDQ.W  #0x5,D1                         | + 5 bytes (icon, key, mark, style, padding)
        ADDA    D1,A1                           | skip to next item
        BRA.B   MENUMGR_NEXT                    | -> check next item
| item not found: return nil
MENUMGR_FOUND:
        MOVE.L  A1,D1                           | save position (for counting)
        SUBA.L  A0,A0                           | A0 = nil
        MOVE.L  A0,A1                           | A1 = nil
        MOVE.L  A0,D0                           | D0 = 0 (not found)
        RTS                                     | return from MENUMGR_FOUND

| ----------------------------------------------------------
|
| RETURNS_17
|
| Called during boot (22,222 times in 30s trace).
| Found item entry point: A1 points to item title
| Returns: A0 = title ptr, A1 = attribute bytes after title
RETURNS_17:
        TST.B   (A1)                            | zero-length title = end sentinel?
        BEQ.B   MENUMGR_FOUND                   | yes, item not found ->
        MOVE.L  A1,A0                           | A0 = ptr to item title
        MOVE.B  (A1)+,D1                        | D1 = title length, A1 past length byte
        ADDA    D1,A1                           | A1 = ptr to attribute bytes (icon,key,mark,style)
        RTS                                     | return from RETURNS_17

| ----------------------------------------------------------
|
| MENUMGR_CONT
|
| Called during boot (22,164 times in 30s trace).
| Set item attribute: stack = [ret, value.B, pad, item#, MenuHandle]
| D2 = attribute index (0=icon, 1=key, 2=mark, 3=style)
MENUMGR_CONT:
        MOVE.L  0x8(SP),A0                      | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference -> MenuInfo ptr
        MOVE    0x6(SP),D0                      | D0 = item number
        BSR.B   RETURNS_16                      | find item -> A1 = attributes
        BEQ.B   MENUMGR_SKIP                    | item not found ->
        MOVE.B  0x5(SP),0x0(A1,D2.W)            | store new value at attribute[D2]
        SUBQ.W  #0x2,D2                         | was it icon (0) or key (1)?
        BEQ.B   MENUMGR_SKIP                    | key equivalent changed, skip resize
        MOVE.L  0x8(SP),-(SP)                   | push MenuHandle
        BSR     STACK_2                         | invalidate menu dimensions
MENUMGR_SKIP:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x8,SP                         | strip 8 bytes of params
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| MENUMGR_CONT_2
|
| Get item attribute: stack = [ret, resultPtr, item#, pad, MenuHandle]
| D2 = attribute index (0=icon, 1=key, 2=mark, 3=style)
| Returns attribute byte at resultPtr+1 (as VAR INTEGER, high byte cleared)
MENUMGR_CONT_2:
        MOVE.L  0xA(SP),A0                      | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference -> MenuInfo ptr
        MOVE    0x8(SP),D0                      | D0 = item number
        BSR.B   RETURNS_16                      | find item -> A1 = attributes
        MOVE.L  0x4(SP),A0                      | A0 = result VAR ptr
        CLR.B   (A0)                            | clear high byte of result word
        MOVE.L  A1,D0                           | item found? (test for nil)
        BEQ.B   MENUMGR_NO                      | no, leave result as 0 ->
        MOVE.B  0x0(A1,D2.W),0x1(A0)            | store attribute byte in low byte of result
MENUMGR_NO:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _GetItmIcon ($A93F)
|
| Item attribute accessors - D2 selects which attribute byte:
| 0 = icon number, 1 = key equivalent, 2 = mark character, 3 = style
| Get variants -> MENUMGR_CONT_2 (read), Set variants -> MENUMGR_CONT (write)
|
| _GetItmIcon ($A93F)
GetItmIcon:
        MOVEQ.L #0x0,D2                         | attribute index 0 = icon
        BRA.B   MENUMGR_CONT_2                  | -> get

| SetItmIcon -- trap handler for _SetItmIcon ($A940).
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

| GetItmMark -- trap handler for _GetItmMark ($A943).
| _GetItmMark ($A943)
GetItmMark:
        MOVEQ.L #0x2,D2                         | attribute index 2 = mark char
        BRA.B   MENUMGR_CONT_2                  | -> get

| SetItmMark -- trap handler for _SetItmMark ($A944).
| _SetItmMark ($A944)
SetItmMark:
        MOVEQ.L #0x2,D2                         | attribute index 2 = mark char
        BRA.B   MENUMGR_CONT                    | -> set

| _CheckItem ($A945): set/clear checkmark on a menu item
CheckItem:
        TST.B   0x4(SP)                         | checked?
        BEQ.B   CHECKITEM_NO                    | no -> clear mark
        MOVE    #0x12,0x4(SP)                   | set mark to checkmark char ($12)
        BRA.B   SetItmMark                      | -> SetItmMark

| ----------------------------------------------------------
|
| CHECKITEM_NO
|
| Called during boot (18,470 times in 30s trace).
CHECKITEM_NO:
        CLR     0x4(SP)                         | set mark char to 0 (noMark)
        BRA.B   SetItmMark                      | -> clear the checkmark

| ----------------------------------------------------------
|
| CHECKITEM_CONT
|
| CHECKITEM_CONT: uppercase a single character in D0
| Uses _UprString with length=1 on a temp stack byte
CHECKITEM_CONT:
        MOVE.B  D0,-(SP)                        | push char onto stack
        MOVE.L  A7,A0                           | A0 = ptr to the char
        MOVEQ.L #0x1,D0                         | length = 1
        _UprStringMarks                         | uppercase in place (diacritical-aware)
        MOVE.B  (SP)+,D0                        | pop uppercased result into D0
        RTS                                     | return from CHECKITEM_CONT

| ----------------------------------------------------------
|
| _MenuKey ($A93E)
|
| _MenuKey ($A93E): find menu item matching a Command-key equivalent
| Pascal: function MenuKey(ch: CHAR): LongInt; (high=menuID, low=item)
MenuKey:
        MOVEM.L D3-D5/A3,-(SP)                  | save working registers
        MOVE.B  0x15(SP),D0                     | D0 = key character from stack
        BSR.B   CHECKITEM_CONT                  | uppercase the character
        MOVE.B  D0,D4                           | D4 = target key (uppercased)
        BSR     DISABLEITEM_CONT                | get MenuList handle -> A0
        MOVE    (A0),D5                         | D5 = number of menus in bar
| scan each menu for matching key equivalent
MENUKEY_NEXT:
        BSR     DISABLEITEM_NEXT                | get next menu -> A0 = MenuHandle
        MOVE.L  A0,A3                           | A3 = dereferenced MenuInfo
        BTST    #0x0,0xD(A3)                    | menu enabled? (enableFlags bit 0)
        BEQ.B   MENUKEY_SKIP_2                  | no, skip this menu ->
        MOVEQ.L #0x1,D3                         | D3 = item number (start at 1)
| scan items in this menu
MENUKEY_NEXT_2:
        MOVE.L  menuEnable(A3),D0               | D0 = enableFlags
        BTST    D3,D0                           | this item enabled?
        BEQ.B   MENUKEY_SKIP                    | no, skip ->
        MOVE.L  A3,A0                           | A0 = MenuInfo
        MOVE    D3,D0                           | D0 = item number
        BSR     RETURNS_16                      | find item -> A1 = attributes
        BEQ.B   MENUKEY_SKIP_2                  | past last item ->
        MOVE.B  0x1(A1),D0                      | D0 = item's key equivalent
        BSR.B   CHECKITEM_CONT                  | uppercase it
        CMP.B   D0,D4                           | matches target key?
        BEQ.B   MENUKEY_FOUND                   | yes, found it! ->
MENUKEY_SKIP:
        ADDQ.W  #0x1,D3                         | increment item count
        BRA.B   MENUKEY_NEXT_2                  | loop back for next item

| ----------------------------------------------------------
|
| MENUKEY_SKIP_2
|
MENUKEY_SKIP_2:
        SUBQ.W  #0x6,D5                         | advance to next menu (6 bytes/entry in MenuList)
        BNE.B   MENUKEY_NEXT                    | more menus remain -> scan next
        CLR.L   0x16(SP)                        | no match found: result = 0
MENUKEY_DONE:
        MOVEM.L (SP)+,D3-D5/A3                  | restore registers
        BRA     DELETEMENU_EXIT                 | -> strip params and return

| ----------------------------------------------------------
|
| MENUKEY_FOUND: key match found - hilite menu and return menuID:item
|
MENUKEY_FOUND:
        BSR     DISABLEITEM_NEXT                | get matching menu's MenuHandle -> A0
        MOVE    (A0),D0                         | D0.w = menuID of matching menu
        SWAP    D0                              | menuID -> high word
        MOVE    D3,D0                           | item number -> low word
        MOVE.L  D0,0x16(SP)                     | store result (menuID<<16 | item)
        SWAP    D0                              | D0.w = menuID again
        MOVE    D0,-(SP)                        | push menuID
        _HiliteMenu                             | hilite the matched menu title
        TST     (MBarEnable).w                  | desk accessory menu bar active?
        BMI.B   MENUKEY_OK                      | yes, route to SystemMenu ->
        MOVE.L  0x16(SP),D0                     | D0 = result (menuID:item)
        BPL.B   MENUKEY_DONE                    | positive menuID = app menu, done ->
MENUKEY_OK:
        MOVE.L  D0,-(SP)                        | push menuID:item for SystemMenu
        _SystemMenu                             | let system handle DA menu choice
        CLR.L   0x16(SP)                        | clear result (system handled it)
        BRA.B   MENUKEY_DONE                    | -> return

| ----------------------------------------------------------
|
| _GetItem ($A946): return the text of a menu item
| Pascal: PROCEDURE GetItem(theMenu: MenuHandle; item: INTEGER;
|                           VAR itemString: Str255);
| Entry: 0x4(SP) = @itemString, 0x8(SP) = item, 0xA(SP) = theMenu
| Copies the item's title (length byte included) with _BlockMove; returns the
| empty string if the menu has no such item. Exits via MENUMGR_NO (10 bytes).
GetItem:
        MOVE.L  0xA(SP),A0                      | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference -> MenuInfo ptr
        MOVE    0x8(SP),D0                      | D0 = item number
        BSR     RETURNS_16                      | find item -> A0 = title ptr
        MOVE.L  0x4(SP),A1                      | A1 = @itemString (CCR unchanged)
        BEQ.B   GETITEM_EXIT                    | item not found -> return empty
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A0),D0                         | D0 = title length
        ADDQ.W  #0x1,D0                         | +1 for length byte itself
        _BlockMove                              | copy Pascal string: A0 -> A1, D0 bytes
GETITEM_CONT:
        BRA     MENUMGR_NO                      | -> strip 10 bytes of params

| ----------------------------------------------------------
|
| GETITEM_EXIT - GetItem: no such item, return the empty string
|
GETITEM_EXIT:
        CLR.B   (A1)                            | return empty string (length=0)
        BRA.B   GETITEM_CONT                    | -> strip params

| ----------------------------------------------------------
|
| STACK_2
|
| STACK_2: invalidate menu dimensions (forces recalc on next draw)
| Stack: [ret, MenuHandle]
STACK_2:
        MOVE.L  0x4(SP),A0                      | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference -> MenuInfo ptr
        MOVE.L  #0xFFFFFFFF,menuWidth(A0)       | set width/height to -1 (invalid)

        BRA.B   CALCMENUSIZE_EXIT               | -> strip param and return

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
        CLR.L   -(SP)                           | push menuRect (nil)
        CLR.L   -(SP)                           | push hitPt (0,0)
        CLR.L   -(SP)                           | push whichItem (nil)
        MOVE.L  (A0),A0                         | dereference -> MenuInfo
        BSR     MENUSELECT_CONT_8               | get MDEF proc pointer -> A0
        JSR     (A0)                            | call MDEF with mSizeMsg
        MOVE.L  0x4(SP),A0                      | get MenuHandle back
        MOVE.L  (A0),A0                         | dereference
        BSR     MENUSELECT_CONT_10              | store computed width/height in MenuInfo
CALCMENUSIZE_EXIT:
        MOVE.L  (SP)+,(SP)                      | strip 4-byte param (shift ret addr down)
        RTS                                     | return from CALCMENUSIZE_EXIT

| ----------------------------------------------------------
|
| RETURNS_18
|
| RETURNS_18: test if menu item D4 is enabled (checks both item bit and menu bit 0)
| A3 = MenuHandle, D4 = item number
| Returns: Z=1 if disabled (either item bit or menu-global bit 0 is clear)
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
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM resources
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
        DBF     D1,NEWMENU_LOOP                 | loop over title string
        CLR.B   (A1)+                           | terminate item list with 0
        BRA     INSERTMENU_EXIT                 | -> strip params and return

| ----------------------------------------------------------
|
| _AppendMenu ($A933): append one or more items to a menu
| Pascal: PROCEDURE AppendMenu(theMenu: MenuHandle; data: Str255);
| Inserts afterItem = 999 below the return address and falls into InsMenuItem:
| AppendMenu(m, s) = InsMenuItem(m, s, 999); RETURNS_19 clamps 999 to 'after
| the last item'.
AppendMenu:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE    #0x3E7,-(SP)                    | push afterItem = 999 (append)
        MOVE.L  A0,-(SP)                        | push return address back
| (falls through)
|
| _InsMenuItem ($A826): insert one or more items into a menu after a given item
| Pascal: PROCEDURE InsMenuItem(theMenu: MenuHandle; itemString: Str255;
|                               afterItem: INTEGER);
| Entry (after LINK): 0x8(A6) = afterItem, 0xA(A6) = itemString, 0xE(A6) = theMenu
| itemString uses AppendMenu's syntax (items separated by ';' or CR, with the
| metacharacters of METACHAR_TBL). Every item is inserted before item
| afterItem + 1 (afterItem = 0: at the top), so several items from one string
| end up in reverse order unless they go to the end. The 280-byte frame holds
| the pending item (see INSMENUITEM_NEXT); exits via MENUMGR_NO (10 bytes).
InsMenuItem:
        LINK    A6,#-0x118                      | 280 bytes local (item parse buffer)
        MOVEM.L D3-D7/A2-A4,-(SP)               | save registers
        MOVE.L  0xA(A6),A4                      | A4 = item data string
        MOVE.L  0xE(A6),A3                      | A3 = MenuHandle
        MOVE    0x8(A6),D6                      | D6 = afterItem
        ADDQ.W  #0x1,D6                         | D6 = afterItem + 1 (insert before this item)
        BSR.B   INSMENUITEM_CONT                | parse and insert items
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down stack frame
        BRA     MENUMGR_NO                      | -> strip 10 bytes of params

| ----------------------------------------------------------
|
| INSMENUITEM_CONT - parse an item string and insert its items into the menu
| Apple source name: AddString (System 7.1 MenuMgr.a)
|
| A4 = item string (Pascal), A3 = MenuHandle, D6 = insert-before item number,
| A6 = InsMenuItem frame. Passes each character to INSMENUITEM_CONT_3, then
| flushes the last item and marks the menu size invalid (STACK_2). An empty
| string is not special-cased: D3.W = $FFFF and the DBF loop runs 65536 times
| (Inside Macintosh: the string should not be empty).
INSMENUITEM_CONT:
        CLR     D3                              | D3.W = 0 (for the byte load)
        MOVE.B  (A4)+,D3                        | D3 = length of item data string
        BSR.B   INSMENUITEM_NEXT                | init parse state (clear attribute buffer)
        SUBQ.W  #0x1,D3                         | adjust for DBF loop
INSMENUITEM_LOOP:
        MOVE.B  (A4)+,D0                        | D0 = next char from data string
        BSR.B   INSMENUITEM_CONT_3              | process char (text or metachar)
        DBF     D3,INSMENUITEM_LOOP             | loop through all chars
        BSR     INSMENUITEM_NO_5                | flush last item into menu
        MOVE.L  A3,-(SP)                        | push MenuHandle
        BSR     STACK_2                         | invalidate menu dimensions
        RTS                                     | return from INSMENUITEM_CONT

| ----------------------------------------------------------
|
| INSMENUITEM_NEXT - clear the pending-item state before the next item
| Apple source name: InitItem (System 7.1 MenuMgr.a)
|
| Called during boot.
| Clears the first 8 bytes of the item frame (InsMenuItem/InsertResMenu, A6):
| -0x118(A6): icon byte, -0x117: key byte, -0x116: mark byte, -0x115: style byte
| -0x114: parse state (0 = text, 1..4 = metachar value pending), -0x113: disable
| flag, -0x112: title length (word; its low byte -0x111 serves as the length
| byte of the item), -0x110: title buffer (256 bytes)
INSMENUITEM_NEXT:
        LEA.L   -0x118(A6),A0                   | A0 = start of attribute buffer
        CLR.L   (A0)+                           | clear icon, key, mark, style bytes
        CLR.L   (A0)                            | clear parse state, disable flag, title length
        RTS                                     | return from INSMENUITEM_NEXT

| ----------------------------------------------------------
|
| METACHAR_TBL - AppendMenu metacharacters (Apple: MCHARTABLE)
|
| Index 0 '^' icon, 1 '/' key equivalent, 2 '!' mark, 3 '<' style: the next
| character is the value (parse state = index + 1); 4 CR and 5 ';' end the
| item; 6 '(' disables the item.
METACHAR_TBL:
  .byte 0x5E,0x2F,0x21,0x3C,0x0D,0x3B           | ^ / ! < CR ;
  .byte 0x28                                    | (

| INSMENUITEM_CONT_2 - style letters for '<' (Apple: STYLECHRTAB); index = style
| bit: 0='B' bold, 1='I' italic, 2='U' underline, 3='O' outline, 4='S' shadow
INSMENUITEM_CONT_2:
  .byte 0x42,0x49,0x55,0x4F,0x53                | B I U O S

| INSMENUITEM_CONT_3 - process one item-string character (Apple: AppendChar)
| D0 = character, -0x114(A6) = parse state:
| State 0: metacharacter (INSMENUITEM_NO_3) or title text
| State 1 (after '^'): icon number, stored as char - '0'
| State 2 (after '/'): key equivalent character
| State 3 (after '!'): mark character
| State 4 (after '<'): style letter, ORed into the style byte (an unknown
| letter is ignored and leaves state 4 set)
| A value goes to attribute byte (state - 1); the state then returns to 0.
INSMENUITEM_CONT_3:
        CLR     D1                              | clear high byte
        MOVE.B  -0x114(A6),D1                   | D1 = current parse state
        BEQ.B   INSMENUITEM_NO_3                | state 0: no metachar pending ->
        CMPI.B  #0x1,D1                         | state 1: icon number pending?
        BNE.B   INSMENUITEM_NO                  | no ->
        SUBI    #0x30,D0                        | convert ASCII digit to binary ('0'=0x30)
INSMENUITEM_NO:
        CMPI.B  #0x4,D1                         | state 4: style letter pending?
        BNE.B   INSMENUITEM_NO_2                | no -> store directly as attribute
        MOVEQ.L #0x4,D2                         | D2 = 4 (scan style table from end)
INSMENUITEM_LOOP_2:
        CMP.B   INSMENUITEM_CONT_2(PC,D2.W),D0  | match style letter?
        BEQ.B   INSMENUITEM_OK                  | yes -> set style bit
        DBF     D2,INSMENUITEM_LOOP_2           | try next style letter
        RTS                                     | unknown letter: ignore (state stays 4)

| ----------------------------------------------------------
|
| INSMENUITEM_OK - style letter D2 matched: OR bit D2 into the style byte
| (Apple: ADDTOSTYLE)
INSMENUITEM_OK:
        LEA.L   -0x119(A6),A0                   | A0 = attribute base (1 before icon byte)
        MOVE.B  0x0(A0,D1.W),D0                 | D0 = current style byte value
        BSET    D2,D0                           | set bit for matched style (B=0,I=1,U=2,O=3,S=4)
| INSMENUITEM_NO_2: attribute byte (state - 1) = D0, parse state = 0
| (Apple: UPDATEPROP)
INSMENUITEM_NO_2:
        LEA.L   -0x119(A6),A0                   | A0 = attribute base
        MOVE.B  D0,0x0(A0,D1.W)                 | attribute byte (state - 1) = D0
        CLR.B   -0x114(A6)                      | reset parse state to 0 (normal)
        RTS                                     | return from INSMENUITEM_NO_2

| ----------------------------------------------------------
|
| INSMENUITEM_NO_3 - state 0: metacharacter or title text (Apple: NORMSTATE)
| Scans METACHAR_TBL from index 6 down; any other character is appended to
| the title buffer.
INSMENUITEM_NO_3:
        LEA.L   METACHAR_TBL(PC),A0             | A0 = metachar table
        MOVE    #0x6,D1                         | D1 = 6 (scan from index 6 down to 0)
INSMENUITEM_LOOP_3:
        CMP.B   0x0(A0,D1.W),D0                 | char matches metachar[D1]?
        BEQ.B   INSMENUITEM_OK_2                | yes -> handle metachar
        DBF     D1,INSMENUITEM_LOOP_3           | try next metachar
        MOVE    -0x112(A6),D1                   | D1 = current title length
        LEA.L   -0x110(A6),A0                   | A0 = title buffer
        MOVE.B  D0,0x0(A0,D1.W)                 | append char to title buffer
        ADDQ.W  #0x1,-0x112(A6)                 | increment title length
        RTS                                     | return from INSMENUITEM_NO_3

| ----------------------------------------------------------
|
| INSMENUITEM_OK_2 - D0 is METACHAR_TBL entry D1 (Apple: SPECIALCHAR)
|
| Index 0-3 (^ / ! <): parse state = D1 + 1, the next char is the value
| Index 4 (CR) or 5 (;): end of item -> flush it (INSMENUITEM_NO_5)
| Index 6 ('('): mark the current item as disabled
INSMENUITEM_OK_2:
        CMPI    #0x3,D1                         | metachar index <= 3?
        BGT.B   INSMENUITEM_NO_4                | no, index 4-6 -> separator or disable
        ADDQ.W  #0x1,D1                         | state = index+1 (1=icon,2=key,3=mark,4=style)
        MOVE.B  D1,-0x114(A6)                   | set parse state for next char
        RTS                                     | return from INSMENUITEM_OK_2

| ----------------------------------------------------------
|
| INSMENUITEM_NO_4 - item separator (index 4-5) or disable marker (index 6)
| (Apple: CHECKTERM)
INSMENUITEM_NO_4:
        SUBQ.W  #0x6,D1                         | index 6 ('(')? -> D1=0
        BNE.B   INSMENUITEM_NO_5                | no, it's CR or ';' -> flush item
        ST.B    -0x113(A6)                      | set disable flag for current item
        RTS                                     | return from INSMENUITEM_NO_4

| ----------------------------------------------------------
|
| INSMENUITEM_NO_5 - insert the pending item (if it has title text) and clear
| the pending-item state. Apple source name: CloseItem (System 7.1 MenuMgr.a)
|
| Called during boot.
| Also used by InsertResMenu, whose resource name is the pending item.
INSMENUITEM_NO_5:
        MOVE    -0x112(A6),D0                   | D0 = title length
        BEQ.B   INSMENUITEM_NO_6                | no title text, nothing to flush ->
        BSR.B   INSMENUITEM_CONT_4              | insert the item into menu data
        BSR     INSMENUITEM_NEXT                | re-init parse state for next item
INSMENUITEM_NO_6:
        RTS                                     | return from INSMENUITEM_NO_5

| ----------------------------------------------------------
|
| RETURNS_19 - clamp an insertion point to the menu's item count
| Apple source name: GetGoodIndex (System 7.1 MenuMgr.a)
|
| Called during boot.
| D6 = desired insertion position, A3 = MenuHandle
| Returns: D5 = clamped insertion position (min of D6 and itemCount+1)
RETURNS_19:
        MOVE    D6,D5                           | D5 = desired insertion point
        SUBQ.W  #0x2,SP                         | space for CountMItems result
        MOVE.L  A3,-(SP)                        | push MenuHandle
        _CountMItems                            | count items in menu
        MOVE    (SP)+,D0                        | D0 = item count
        ADDQ.W  #0x1,D0                         | D0 = max valid insertion point
        CMP     D0,D5                           | desired > max?
        BLE.B   INSMENUITEM_OK_3                | no, D5 is valid ->
        MOVE    D0,D5                           | clamp to max position
INSMENUITEM_OK_3:
        RTS                                     | return from INSMENUITEM_OK_3

| ----------------------------------------------------------
|
| INSMENUITEM_CONT_4 - insert the pending item before item D6
| Apple source name: InsertTheItem (System 7.1 MenuMgr.a)
|
| Called during boot.
| D5 = min(D6, item count + 1) = number of the new item. If item D5 exists, an
| enable bit is inserted for it (INSMENUITEM_CONT_6); otherwise the item goes
| to the end (D1 = end of item list). Length byte, title and the 4 attribute
| bytes are spliced in with _Munger; DisableItem if '(' was seen.
INSMENUITEM_CONT_4:
        BSR.B   RETURNS_19                      | clamp insertion point -> D5
        MOVE    D5,D0                           | D0 = clamped insertion position
        MOVE.L  (A3),A0                         | dereference MenuHandle
        BSR     RETURNS_16                      | item D5: A0 = its title, else D1 = list end
        BEQ.B   INSMENUITEM_CONT_5              | past end -> insert at end
        MOVE.L  A0,D1                           | D1 = ptr to insertion point in data
        MOVE.L  (A3),A0                         | A0 = MenuInfo ptr again
        BSR.B   INSMENUITEM_CONT_6              | insert enable bit at D5 for the new item
INSMENUITEM_CONT_5:
        LEA.L   -0x110(A6),A0                   | A0 = title buffer
        MOVE.L  A0,A2                           | A2 = title buffer base
        MOVE    -0x112(A6),D2                   | D2 = title length
        ADDA    D2,A0                           | A0 = end of title in buffer
        LEA.L   -0x118(A6),A1                   | A1 = attribute bytes (icon,key,mark,style)
        MOVEQ.L #0x3,D0                         | copy 4 attribute bytes
INSMENUITEM_LOOP_4:
        MOVE.B  (A1)+,(A0)+                     | append attributes after title
        DBF     D0,INSMENUITEM_LOOP_4           | loop 4 bytes
        SUBQ.W  #0x1,A2                         | A2 -> -0x111(A6): length byte + title
        ADDQ.W  #0x5,D2                         | D2 = total item size (title + len + 4 attrs)
        EXT.L   D2                              | extend to long for _Munger
        MOVE.L  D1,A1                           | A1 = insertion ptr (absolute)
        SUBA.L  (A3),A1                         | convert to offset within handle
        SUBQ.W  #0x4,SP                         | space for Munger result
        MOVE.L  A3,-(SP)                        | push handle (MenuHandle)
        MOVE.L  A1,-(SP)                        | push offset in handle
        CLR.L   -(SP)                           | push target (nil = insert at offset)
        CLR.L   -(SP)                           | push target length (0 = pure insert)
        MOVE.L  A2,-(SP)                        | push replacement ptr (length byte + title + attrs)
        MOVE.L  D2,-(SP)                        | push replacement length
        _Munger                                 | splice item data into menu handle
        ADDQ.W  #0x4,SP                         | discard Munger result
        TST.B   -0x113(A6)                      | disable flag set for this item?
        BEQ.B   INSMENUITEM_NO_7                | no ->
        MOVE.L  A3,-(SP)                        | push MenuHandle
        MOVE    D5,-(SP)                        | push item number
        BSR     DisableItem                     | disable the newly inserted item
INSMENUITEM_NO_7:
        RTS                                     | return from INSMENUITEM_CONT_4

| ----------------------------------------------------------
|
| INSMENUITEM_CONT_6 - insert an enable bit for new item D5 into enableFlags
| Apple source name: InsertEnableBit (System 7.1 MenuMgr.a)
|
| Called during boot.
| A0 = MenuInfo ptr. Bits 0..D5-1 stay, bits D5..30 move up one place (bit 31
| is lost) and bit D5 becomes 1: the X flag that NEG leaves set is rotated in,
| so the new item starts out enabled. No check for D5 > 31.
INSMENUITEM_CONT_6:
        MOVE.L  menuEnable(A0),D2               | D2 = current enableFlags
        ROR.L   D5,D2                           | rotate right by item position
        MOVE    D5,D0                           | D0 = position
        SUBI    #0x20,D0                        | D0 = D5 - 32
        NEG     D0                              | D0 = 32 - D5; X = 1 (result <> 0)
        ROXR.L  D0,D2                           | rotate back through X: bit D5 = 1
        MOVE.L  D2,menuEnable(A0)               | store updated enableFlags
        RTS                                     | return from INSMENUITEM_CONT_6

| ----------------------------------------------------------
|
| _GetMHandle ($A949): return the handle of the menu with a given menu ID
| Pascal: FUNCTION GetMHandle(menuID: INTEGER): MenuHandle;
| Entry: 0x4(SP) = menuID, 0x6(SP) = result. Searches the menu list
| (INSERTMENU_CONT_2); returns NIL if no installed menu has this ID.
GetMHandle:
        CLR.L   0x6(SP)                         | result = nil initially
        MOVE    0x4(SP),D1                      | D1 = menuID to find
        BSR     INSERTMENU_CONT_2               | D0 = MenuList offset of menuID (0 = none)
        BEQ.B   GETMHANDLE_FOUND                | not found ->
        MOVE    D5,-(SP)                        | save D5
        MOVE    D0,D5                           | D5 = MenuList offset of the entry
        BSR     DISABLEITEM_NEXT                | A1 = MenuHandle at offset D5
        MOVE    (SP)+,D5                        | restore D5
        MOVE.L  A1,0x6(SP)                      | store result MenuHandle
GETMHANDLE_FOUND:
        BRA     DELETEMENU_EXIT                 | strip 2 bytes (menuID) and return

| ----------------------------------------------------------
|
| _DelMenuItem ($A952): delete an item from a menu
| Pascal: PROCEDURE DelMenuItem(theMenu: MenuHandle; item: INTEGER);
| Pushes a copy of the return address as a dummy third parameter so that the
| stack looks like SetItem's; this lets it share SetItem's Munger tail
| (SETITEM_CONT) and 10-byte exit. First removes the item's enable bit (higher
| items move down one bit, bit 31 becomes 1; no check for item > 31), then, if
| the item exists, deletes its length byte, title and 4 attribute bytes.
DelMenuItem:
        MOVE.L  (SP),-(SP)                      | dup return address = dummy 3rd parameter
        MOVEM.L D3-D4/A2-A4,-(SP)               | save registers
        MOVE.L  0x1E(SP),A3                     | A3 = MenuHandle
        MOVE.L  (A3),A0                         | dereference -> MenuInfo ptr
        MOVE    0x1C(SP),D0                     | D0 = item number to delete
        MOVE.L  menuEnable(A0),D1               | D1 = enableFlags
        MOVE    D0,D2                           | D2 = item number
        SUBI    #0x20,D2                        | D2 = item - 32
        NEG     D2                              | D2 = 32 - item; X = 1 (result <> 0)
        ROXL.L  D2,D1                           | rotate left through X: X (=1) enters bit 0
        ROL.L   D0,D1                           | realign: item's bit gone, bit 31 = 1
        MOVE.L  D1,menuEnable(A0)               | store updated enableFlags
        BSR     RETURNS_16                      | find item -> A0 = title ptr
        BEQ.B   SETITEM_FOUND                   | item not found ->
        MOVEQ.L #0x5,D4                         | D4 = length byte + 4 attribute bytes
        MOVEQ.L #0x0,D2                         | D2 = 0 (replacement length = 0 for delete)
        MOVE.L  D2,A2                           | A2 = nil (no replacement data)
        BRA.B   SETITEM_CONT                    | -> use Munger to remove item data

| ----------------------------------------------------------
|
| _SetItem ($A947): change the text of a menu item
| Pascal: PROCEDURE SetItem(theMenu: MenuHandle; item: INTEGER;
|                           itemString: Str255);
| Entry (after MOVEM): 0x18(SP) = itemString, 0x1C(SP) = item, 0x1E(SP) = theMenu
| Replaces the old title (length byte + text) with itemString via _Munger; the
| attribute bytes are kept and metacharacters are not interpreted. Then marks
| the menu size invalid (STACK_2). No-op if the item does not exist.
| SETITEM_CONT is shared with DelMenuItem: A0 = item, A2/D2 = new data and
| length, D4 = bytes to replace besides the old title text.
SetItem:
        MOVEM.L D3-D4/A2-A4,-(SP)               | save working registers
        MOVE.L  0x1E(SP),A3                     | A3 = MenuHandle
        MOVE    0x1C(SP),D3                     | D3 = item number
        MOVE.L  0x18(SP),A2                     | A2 = new item string
        MOVE    D3,D0                           | D0 = item number for RETURNS_16
        MOVE.L  (A3),A0                         | dereference MenuHandle
        BSR     RETURNS_16                      | find item -> A0 = old title ptr
        BEQ.B   SETITEM_FOUND                   | not found ->
| set up Munger parameters to replace old title with new
        MOVEQ.L #0x1,D4                         | D4 = 1 (include length byte)
        MOVEQ.L #0x1,D2                         | D2 = 1 (length byte of new string)
        ADD.B   (A2),D2                         | + string length
SETITEM_CONT:
        MOVE.L  A0,A4                           | A4 = item title pointer
        SUBA.L  (A3),A4                         | convert to offset in handle
        ADD.B   (A0),D4                         | D4 += old title length = bytes to replace
| _Munger: replace D4 bytes at the item with D2 bytes at A2 (D2 = 0: delete)
        SUBQ.W  #0x4,SP                         | space for result
        MOVE.L  A3,-(SP)                        | push handle
        MOVE.L  A4,-(SP)                        | push offset
        CLR.L   -(SP)                           | push target (nil = by offset)
        MOVE.L  D4,-(SP)                        | push old length
        MOVE.L  A2,-(SP)                        | push replacement ptr
        MOVE.L  D2,-(SP)                        | push replacement length
        _Munger                                 | replace text in handle
        ADDQ.W  #0x4,SP                         | discard result
        MOVE.L  A3,-(SP)                        | push MenuHandle
        BSR     STACK_2                         | mark menu size invalid (recalc later)
SETITEM_FOUND:
        MOVEM.L (SP)+,D3-D4/A2-A4               | restore registers
        BRA     MENUMGR_NO                      | strip 10 bytes and return

| ----------------------------------------------------------
|
| Set M Flash
|
| _SetMFlash: set menu flash count (number of blinks on selection)
SetMFlash:
        MOVE    0x4(SP),(MenuFlash).w           | store flash count
        BRA     DELETEMENU_EXIT                 | -> strip params

| ----------------------------------------------------------
|
| _AddResMenu ($A94D): append the names of all resources of a type to a menu
| Pascal: PROCEDURE AddResMenu(theMenu: MenuHandle; theType: ResType);
| Inserts afterItem = 999 below the return address and falls into
| InsertResMenu (RETURNS_19 clamps 999 to 'after the last item'). Used to
| fill the Apple menu ('DRVR') and font menus ('FONT').
|
AddResMenu:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE    #0x3E7,-(SP)                    | afterItem = 999 (append)
        MOVE.L  A0,-(SP)                        | push return address back
| (falls through)
|
| _InsertResMenu ($A951): insert the names of all resources of a type into a menu
| Pascal: PROCEDURE InsertResMenu(theMenu: MenuHandle; theType: ResType;
|                                 afterItem: INTEGER);
| Apple source name: InsrtResMenu (MacSEROM.lst: INSRTRESMENU)
| Entry (after LINK): 0x8(A6) = afterItem, 0xA(A6) = theType, 0xE(A6) = theMenu
| Skips unnamed resources and names starting with '.' or '%'. Names are kept in
| alphabetical order (_RelString, case-insensitive) and duplicates dropped: the
| first goes after afterItem, later ones are compared with the items from there
| to the end of the menu. 'FONT' is changed to 'FOND' in the parameter; after
| the 'FOND' pass the type becomes 'FONT' and is scanned again, so either type
| adds both. ResLoad is FALSE during the scan and restored afterwards.
InsertResMenu:
        CMPI.L  #0x464F4E54,0x6(SP)             | resource type == 'FONT'?

        BNE.B   INSERTRESMENU_NO                | no, normal resource scan ->
        MOVE.B  #0x44,0x9(SP)                   | change 'T' to 'D': 'FONT' -> 'FOND'
INSERTRESMENU_NO:
        LINK    A6,#-0x118                      | same 280-byte item frame as InsMenuItem
        MOVEM.L D3-D7/A2-A4,-(SP)               | save registers
        MOVE    (ResLoad).w,-(SP)               | save current ResLoad state
        CLR     (ResLoad).w                     | disable auto-loading (just need names)
        BSR     INSMENUITEM_NEXT                | clear pending item (count high byte = 0)
        MOVE.L  0xE(A6),A3                      | A3 = MenuHandle
        MOVE    0x8(A6),D6                      | D6 = afterItem
        ADDQ.W  #0x1,D6                         | D6 = afterItem + 1 (insert before this item)
        BSR     RETURNS_19                      | clamp insertion point -> D5
        MOVE    D5,D7                           | D7 = D5 + number of names inserted
INSERTRESMENU_RETRY:
        SUBQ.W  #0x2,SP                         | space for CountResources result
        MOVE.L  0xA(A6),-(SP)                   | push resource type
        _CountResources                         | count resources of this type
        MOVE    (SP)+,D4                        | D4 = resource count
        BEQ     INSERTRESMENU_EMPTY             | none found ->
        MOVEQ.L #0x1,D3                         | D3 = resource index (start at 1)
| loop through each resource of the type
INSERTRESMENU_NEXT:
        SUBQ.W  #0x4,SP                         | space for GetIndResource result
        MOVE.L  0xA(A6),-(SP)                   | push resource type
        MOVE    D3,-(SP)                        | push index
        _GetIndResource                         | handle stays on stack for GetResInfo
        LEA.L   -0x111(A6),A4                   | A4 = item length byte + title buffer
        CLR.L   -(SP)                           | VAR theID = NIL (not wanted)
        CLR.L   -(SP)                           | VAR theType = NIL (not wanted)
        MOVE.L  A4,-(SP)                        | push name buffer ptr
        _GetResInfo                             | name -> pending item (count low byte = len)
        TST.B   (A4)                            | name length = 0?
        BEQ.B   INSERTRESMENU_SKIP              | unnamed resource, skip ->
        CMPI.B  #0x2E,0x1(A4)                   | name starts with '.'?
        BEQ.B   INSERTRESMENU_SKIP              | skip drivers (e.g. ".Print") ->
        CMPI.B  #0x25,0x1(A4)                   | name starts with '%'?
        BEQ.B   INSERTRESMENU_SKIP              | skip internal resources ->
| find alphabetical insertion position for this resource name
        MOVE    D5,D6                           | D6 = first insertion position
        CMP     D7,D6                           | no name inserted yet (D7 = D5)?
        BEQ.B   INSERTRESMENU_OK                | yes: insert at D5 without comparing
        MOVE.L  (A3),A0                         | dereference MenuHandle
        MOVE    D6,D0                           | D0 = item number to start searching
        BSR     RETURNS_16                      | find item -> A0 = title ptr
        MOVE.L  A0,A2                           | A2 = current menu item to compare
| compare with the items from D6 up to the end of the menu
INSERTRESMENU_NEXT_2:
        TST.B   (A2)                            | end of item list?
        BEQ.B   INSERTRESMENU_OK                | yes, insert at end ->
        MOVE.L  A2,A0                           | A0 = existing item title
        MOVE.L  A4,A1                           | A1 = new resource name
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A0)+,D0                        | D0 = existing title length
        SWAP    D0                              | move to high word
        MOVE.B  (A1)+,D0                        | D0.lo = new name length
        _CompareString                          | RelString, case-insens.: existing vs new
        BGT.B   INSERTRESMENU_OK                | existing > new: insert before it ->
        BEQ.B   INSERTRESMENU_SKIP              | duplicate name: skip this resource ->
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A2),D0                         | D0 = existing title length
        ADDQ.W  #0x5,D0                         | + length byte + 4 attribute bytes
        ADDA.L  D0,A2                           | advance A2 to next item
        ADDQ.W  #0x1,D6                         | increment insertion point
        BRA.B   INSERTRESMENU_NEXT_2            | compare with next item

| ----------------------------------------------------------
|
| INSERTRESMENU_OK - insert the resource name (the pending item) before item D6
|
| Called during boot.
INSERTRESMENU_OK:
        MOVE    D5,-(SP)                        | save D5 (INSMENUITEM_CONT_4 changes it)
        BSR     INSMENUITEM_NO_5                | insert the name before item D6
        MOVE    (SP)+,D5                        | restore D5 (first insertion position)
        ADDQ.W  #0x1,D7                         | one more name inserted
INSERTRESMENU_SKIP:
        ADDQ.W  #0x1,D3                         | next resource index
        CMP     D4,D3                           | more resources to scan?
        BLE.B   INSERTRESMENU_NEXT              | yes -> next resource
INSERTRESMENU_EMPTY:
        CMPI.L  #0x464F4E44,0xA(A6)             | resource type == 'FOND'?

        BNE.B   INSERTRESMENU_DONE              | no -> done
        MOVE.B  #0x54,0xD(A6)                   | change 'D' to 'T': 'FOND' -> 'FONT'
        BRA     INSERTRESMENU_RETRY             | scan again for 'FONT' resources

| ----------------------------------------------------------
|
| INSERTRESMENU_DONE
|
| Called during boot.
| INSERTRESMENU_DONE: done adding resources - recalculate menu size and clean up
INSERTRESMENU_DONE:
        MOVE.L  A3,-(SP)                        | push MenuHandle
        _CalcMenuSize                           | recalculate menu width/height
        _SetResLoad                             | restore ResLoad from saved value on stack
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down stack frame
        BRA     MENUMGR_NO                      | -> strip params

| ----------------------------------------------------------
|
| _CountMItems ($A950)
|
| _CountMItems ($A950): count items in a menu
| Pascal: function CountMItems(theMenu: MenuHandle): INTEGER;
CountMItems:
        MOVEQ.L #0x0,D2                         | D2 = item counter
COUNTMITEMS_NEXT:
        ADDQ.W  #0x1,D2                         | try next item
        MOVE.L  0x4(SP),A0                      | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference
        MOVE    D2,D0                           | D0 = item number to find
        BSR     RETURNS_16                      | search for item D0
        BNE.B   COUNTMITEMS_NEXT                | found -> count next
        SUBQ.W  #0x1,D2                         | back up (last was past end)
        MOVE    D2,0x8(SP)                      | store result
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from COUNTMITEMS_NEXT

| ----------------------------------------------------------
|
| _PlotIcon ($A94B)
|
| Called during boot.
| _PlotIcon ($A94B): draw a 32x32 icon at specified rectangle
| Pascal: procedure PlotIcon(theRect: Rect; theIcon: Handle);
PlotIcon:
        LEA.L   (IconBitmap).w,A1               | A1 = temp BitMap for icon
        MOVE.L  0x4(SP),D0                      | D0 = icon Handle
        BEQ.B   PLOTICON_SKIP                   | nil handle -> skip
        MOVE.L  D0,A0                           | A0 = icon Handle
        MOVE.L  (A0),(A1)+                      | BitMap.baseAddr = icon data ptr
        MOVE    #0x4,(A1)+                      | BitMap.rowBytes = 4 (32 pixels / 8)
        CLR.L   (A1)+                           | BitMap.bounds.topLeft = (0,0)
        MOVE.L  #0x200020,(A1)                  | BitMap.bounds.botRight = (32,32)
        MOVE.L  0x8(SP),D1                      | D1 = destRect ptr
        LEA.L   (IconBitmap).w,A1               | A1 = icon BitMap (repoint after writes)
        MOVE.L  A1,-(SP)                        | push srcBits (icon BitMap)
        MOVE.L  (A5),A0                         | A0 = QD globals ptr
        MOVE.L  (A0),A0                         | dereference -> thePort
        PEA.L   PORTBITS(A0)                    | push dstBits (thePort.portBits at offset 2)
        PEA.L   0x6(A1)                         | push srcRect (icon bounds at offset 6)
        MOVE.L  D1,-(SP)                        | push dstRect
        CLR     -(SP)                           | push mode = srcCopy (0)
        CLR.L   -(SP)                           | push maskRgn = nil
        _CopyBits                               | draw icon into port
PLOTICON_SKIP:
        BRA     MENUMGR_SKIP                    | -> strip 8 bytes of params

