| Menu Manager
|
| Apple source: MenuMgr.a (MacSEROM.lst module MMGR). In ROM order:
| InitProcMenu ($A808, SE: InitMenus with a given MBDF), InitMenus,
| ClearMenuBar, InsertMenu, DeleteMenu, DrawMenuBar,
| HiliteMenu, EnableItem, DisableItem, MenuSelect, GetMenuBar, SetMenuBar,
| DisposMenu, FlashMenuBar, the GetItemRecord helper (RETURNS_16), the item
| attribute accessors, CheckItem, MenuKey, GetItem, CalcMenuSize, NewMenu,
| AppendMenu/InsMenuItem (with the item-string parser), GetMHandle,
| DelMenuItem, SetItem, SetMFlash, AddResMenu/InsertResMenu, CountMItems,
| PlotIcon. The SE draws the menu bar through its MBDF (resources/
| res_mbdf.s), the menus through the MDEF.
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
| _InitProcMenu ($A808): SE-only entry to initialize Menu Manager with a
| specific 'MBDF' resource ID. If the requested MBDF can't be loaded, falls
| back to the standard InitMenus path (loads 'MBDF' #0).
| Pascal: procedure InitProcMenu(resID: INTEGER);
| Stack: 4(SP) = resID
MMGR:                                           | Apple source module (MacSEROM.lst)
INITPROCMENU:
    SUBQ.W      #0x4,A7                         | reserve _GetResource result slot
    MOVE.L      #0x4D424446,-(A7)               | push 'MBDF' resType
    MOVE.W      0xE(A7),-(A7)                   | push resID arg (caller's param)
    _GetResource                                | resource handle -> (A7)
    MOVE.L      (A7)+,(MBProcHndl).W            | save handle in MBProcHndl
    BEQ.B       INITMENUS_NO_MBDF               | failed -> standard InitMenus fallback
    BSR.B       INITMENUS_BODY                  | shared menu-init body
    MOVEA.L     (MenuList).W,A1                 | A1 = MenuList handle
    MOVEA.L     (A1),A1                         | A1 = deref MenuList
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    MOVE.W      (A7)+,0x4(A1)                   | save resID into MenuList[+4] (lastRight init)
    ADDQ.W      #0x2,A7                         | strip 2 bytes of padding
INITMENUS_RTS_INDIRECT:
    JMP         (A0)                            | indirect return
| Fallback path: 'MBDF' resID not found, do standard InitMenus and return.
INITMENUS_NO_MBDF:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDQ.W      #0x4,A7                         | strip resID + padding (4 bytes)
    MOVE.L      A0,-(A7)                        | re-push return addr (so RTS works)
    BSR.B       INITMENUS                       | standard init (loads MBDF #0)
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    BRA.B       INITMENUS_RTS_INDIRECT          | -> indirect return
| ----------------------------------------------------------
|
| _InitMenus ($A930): initialize the Menu Manager.
| Loads 'MBDF' #0 (standard menu-bar definition function), allocates
| MenuList, sets flash count from PRAM, fires MBDF init message,
| draws empty menu bar.
| Pascal: procedure InitMenus;
INITMENUS:
    MOVEQ.L     #0x0,D0                         | resID = 0 (default MBDF)
    SUBQ.W      #0x4,A7                         | reserve _GetResource result slot
    MOVE.L      #0x4D424446,-(A7)               | push 'MBDF' resType
    MOVE.W      D0,-(A7)                        | push resID = 0
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | force search of ROM resource map
    _GetResource                                | resource handle -> (A7)
    MOVE.L      (A7)+,(MBProcHndl).W            | save MBDF handle
    BNE.B       INITMENUS_BODY                  | got it -> shared init body
    MOVE.W      #0xFF82,D0                      | nbpErr / -126: missing MBDF
    _SysError                                   | fatal: cannot find MBDF
| ----------------------------------------------------------
|
| Shared init body (called from InitMenus and InitProcMenu).
| Allocates MenuList if not yet created, programs MenuFlash from PRAM,
| zeros MBarEnable/MBarHook/MenuHook/MBFlash, fires MBDF init (msg=3),
| then ClearMenuBar + DrawMenuBar.
INITMENUS_BODY:
    MOVE.L      (MenuList).W,D0                 | already initialized?
    BNE.W       INITMENUS_ALREADY_INIT          | yes -> nothing to do
    BSR.B       CALCMBHEIGHT_EMPTY              | allocate empty MenuList -> A0
    MOVE.L      A0,(MenuList).W                 | save MenuList handle
    MOVEQ.L     #0xC,D0                         | mask for PRAM flash bits
    AND.B       (SPMisc2).W,D0                  | get flash count from PRAM
    LSR.W       #0x2,D0                         | shift to 0..3 range
    MOVE.W      D0,(MenuFlash).W                | program MenuFlash
    CLR.W       (MBarEnable).W                  | menu bar disabled initially
    CLR.L       (MBarHook).W                    | no menu bar hook
    CLR.L       (MenuHook).W                    | no menu hook
    CLR.W       (MBFlash).W                     | flash counter = 0
    MOVE.W      #0x3,D0                         | MBDF message #3 = init
    MOVEQ.L     #0x0,D1                         | param = 0
    BSR.W       MENU_CALL_MBDF                  | dispatch to MBDF
    _ClearMenuBar                               | clear menu bar content
    _DrawMenuBar                                | draw empty menu bar
INITMENUS_ALREADY_INIT:
    RTS                                         | return from INITMENUS_BODY / InitMenus
| ----------------------------------------------------------
|
| CalcMBHeight: compute menu bar height from system font ascent+descent.
| MBarHeight = ascent + descent + 5 (baseline padding)
| Called during boot.
CALCMBHEIGHT:
    BSR.B       GETSYSMENUFONTINFO              | get font metrics -> D0 (ascent:descent)
    MOVEQ.L     #0x5,D1                         | D1 = 5 (baseline padding)
    ADD.W       D0,D1                           | + descent (low word of D0)
    SWAP.W      D0                              | D0.w = ascent
    ADD.W       D0,D1                           | D1 = ascent + descent + 5
    MOVE.W      D1,(MBarHeight).W               | store as menu bar height
    RTS                                         | return from CALCMBHEIGHT
| ----------------------------------------------------------
|
| Get system-font metrics for menu bar layout.
| Saves D4 (used by SETWPORT), switches to WMgr port, calls _GetFontInfo,
| restores port, returns ascent:descent packed in D0 (high:low words).
GETSYSMENUFONTINFO:
    MOVE.L      D4,-(A7)                        | save D4 (used by SETWPORT)
    JSR         SETWPORT(PC)                    | save port, switch to WMgr port
    SUBQ.W      #0x8,A7                         | space for FMOutput (ascent,descent,widMax,leading)
    MOVE.L      A7,-(A7)                        | push ptr to FMOutput buffer
    _GetFontInfo                                | fill metrics for system font
    JSR         RESTOREPORT(PC)                 | restore original port
    MOVE.L      (A7)+,D0                        | D0 = ascent:descent (packed words)
    ADDQ.W      #0x4,A7                         | discard widMax:leading
    MOVE.L      (A7)+,D4                        | restore D4
    RTS                                         | return from GETSYSMENUFONTINFO
| ----------------------------------------------------------
|
| CALCMBHEIGHT_EMPTY
|
| Called during boot.
CALCMBHEIGHT_EMPTY:
    MOVEQ.L     #0x66,D0                        | 102 bytes = MenuList header + 16 menu entries
    _NewHandle                                  | allocate MenuList handle -> A0
| CALCMBHEIGHT_EMPTY_2 -- reinitialize to empty list.
CALCMBHEIGHT_EMPTY_2:
    MOVEA.L     (A0),A1                         | A1 = deref MenuList ptr
    CLR.W       (A1)+                           | lastMenu = 0 (no menus yet)
    MOVE.W      #0xA,(A1)+                      | lastRight = 10 (initial left margin)
    CLR.W       (A1)+                           | first menuLeft = 0
    MOVEQ.L     #0x17,D0                        | 23+1 = 24 longwords to clear
CALCMBHEIGHT_LOOP:
    CLR.L       (A1)+                           | zero out menu entry slots
    DBF.W       D0,CALCMBHEIGHT_LOOP            | loop 24 times (96 bytes)
    RTS                                         | return from CALCMBHEIGHT_EMPTY_2
| ----------------------------------------------------------
|
| _ClearMenuBar ($A934): empty the menu bar.
| Pascal: procedure ClearMenuBar;
CLEARMENUBAR:
    BSR.W       DISABLEITEM_CONT                | dereference MenuList -> A0
    MOVEA.L     (MenuList).W,A0                 | A0 = MenuList handle
    BSR.B       CALCMBHEIGHT_EMPTY_2            | reinitialize to empty list
    CLR.W       (TheMenu).W                     | no highlighted menu
    RTS                                         | return from CLEARMENUBAR
| ----------------------------------------------------------
|
| _InsertMenu ($A935): add a menu to the menu bar.
| Pascal: procedure InsertMenu(theMenu: MenuHandle; beforeID: INTEGER);
| beforeID = 0 means append at end. The SE delegates layout work
| (title metrics, lastRight update) to the MBDF via MENU_CALL_MBDF msg=2.
INSERTMENU:
    MOVEM.L     D3-D4/A2-A4,-(A7)               | save regs
    BSR.W       DISABLEITEM_CONT                | get MenuList handle -> A0
    MOVEA.L     A0,A3                           | A3 = deref MenuList
    CMPI.W      #0x60,(A3)                      | MenuList full? (max 96 entries)
    BGE.B       INSERTMENU_SKIP                 | yes -> skip
    MOVEA.L     0x1A(A7),A4                     | A4 = MenuHandle to insert
    MOVEA.L     (A4),A2                         | A2 = deref MenuInfo
    MOVE.W      (A2),D1                         | D1 = menuID
    BSR.B       INSERTMENU_CONT_2               | search MenuList for this menuID
    BNE.B       INSERTMENU_SKIP                 | already there -> skip
    MOVE.W      0x18(A7),D1                     | D1 = beforeID arg
    BSR.B       INSERTMENU_CONT_2               | search for beforeID
    BNE.B       INSERTMENU_SHIFT_LOOP           | found -> insert before that slot
    MOVE.W      (A3),D0                         | D0 = lastMenu (current byte count)
    ADDQ.W      #0x6,D0                         | D0 = offset for new entry at end
    BRA.B       INSERTMENU_STORE                | -> store new entry
| Insertion point found: shift later entries down by one slot (6 bytes each).
INSERTMENU_SHIFT_LOOP:
    MOVE.W      (A3),D2                         | D2 = lastMenu (last entry offset)
INSERTMENU_NO:
    MOVE.L      0x0(A3,D2.W),0x6(A3,D2.W)       | shift MenuHandle down
    MOVE.W      0x4(A3,D2.W),0xA(A3,D2.W)       | shift menuLeft down
    SUBQ.W      #0x6,D2                         | back up one entry
    CMP.W       D0,D2                           | reached insertion point?
    BGE.B       INSERTMENU_NO                   | no -> continue shifting
| Store new MenuHandle and dispatch MBDF "InsertMenu" message (#2).
INSERTMENU_STORE:
    MOVE.L      A4,0x0(A3,D0.W)                 | MenuList[D0] = new MenuHandle
    ADDQ.W      #0x6,(A3)                       | lastMenu += 6 (one entry)
    MOVE.W      #0x2,D0                         | MBDF msg #2 = InsertMenu
    MOVEQ.L     #0x0,D1                         | param = 0 (MBDF computes layout)
    BSR.W       MENU_CALL_MBDF                  | dispatch to MBDF
INSERTMENU_SKIP:
    MOVEM.L     (A7)+,D3-D4/A2-A4               | restore regs
INSERTMENU_EXIT:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDQ.W      #0x6,A7                         | strip 6 bytes of params
    JMP         (A0)                            | tail-call return from INSERTMENU_EXIT via A0
| ----------------------------------------------------------
|
| Search MenuList for an entry by menuID.
| In:  D1 = menuID to find (0 = "not in list")
| Out: D2/D0 = byte offset in MenuList (0 if not found),
|      A1 = deref MenuList ptr, Z flag set if not found
| Called by: INSERTMENU, DELETEMENU, HILITEMENU, HILITEMENU_NEW, FLASHMENUBAR (and 1 more)
INSERTMENU_CONT_2:
    TST.W       D1                              | menuID = 0?
    BEQ.B       INSERTMENU_EMPTY                | yes -> not found
    BSR.W       DISABLEITEM_CONT_3              | A1 = deref MenuList
    MOVE.W      (A1),D2                         | D2 = lastMenu (byte count)
    BEQ.B       INSERTMENU_EMPTY                | empty list -> not found
INSERTMENU_CONT_3:
    MOVE.L      0x0(A1,D2.W),D0                 | D0 = MenuHandle at offset D2
    BEQ.B       INSERTMENU_SKIP_2               | nil handle -> skip
    MOVEA.L     D0,A0                           | A0 = MenuHandle
    MOVEA.L     (A0),A0                         | deref to MenuInfo
    CMP.W       (A0),D1                         | menuID matches target?
    BEQ.B       INSERTMENU_FOUND_2              | yes -> found
INSERTMENU_SKIP_2:
    SUBQ.W      #0x6,D2                         | back up one entry
    BNE.B       INSERTMENU_CONT_3               | more entries -> continue scan
INSERTMENU_EMPTY:
    MOVEQ.L     #0x0,D2                         | not found: D2 = 0
INSERTMENU_FOUND_2:
    MOVE.W      D2,D0                           | D0 = offset (0 = not found)
    RTS                                         | return from INSERTMENU_EMPTY
| ----------------------------------------------------------
|
| _DeleteMenu ($A936): remove a menu from the menu bar.
| Pascal: procedure DeleteMenu(menuID: INTEGER);
DELETEMENU:
    MOVE.W      0x4(A7),D1                      | D1 = menuID to delete
    BSR.B       INSERTMENU_CONT_2               | search MenuList for this menuID
    BEQ.B       MENUMGR_STRIP_PARAM_RTS         | not found -> just strip param and return
    BSR.W       DISABLEITEM_CONT_3              | A1 = deref MenuList
    CMP.W       (A1),D0                         | deleting last entry?
    BNE.B       DELETEMENU_NO                   | no -> shift entries up
    MOVE.W      0x4(A1,D0.W),0x2(A1)            | lastRight = deleted menu's menuLeft
    BRA.B       DELETEMENU_CONT                 | -> decrement count
| ----------------------------------------------------------
|
| DELETEMENU_NO: shift later entries up to fill the gap.
DELETEMENU_NO:
    MOVE.W      0xA(A1,D0.W),D2                 | D2 = next menu's menuLeft
    SUB.W       0x4(A1,D0.W),D2                 | D2 = width of deleted menu's title
    SUB.W       D2,0x2(A1)                      | lastRight -= deleted title width
DELETEMENU_NO_2:
    MOVE.L      0x6(A1,D0.W),0x0(A1,D0.W)       | shift next MenuHandle into current slot
    MOVE.W      0xA(A1,D0.W),0x4(A1,D0.W)       | shift next menuLeft into current slot
    SUB.W       D2,0x4(A1,D0.W)                 | adjust by deleted title width
    ADDQ.W      #0x6,D0                         | advance to next entry
    CMP.W       (A1),D0                         | past last entry?
    BLE.B       DELETEMENU_NO_2                 | no -> continue shifting
DELETEMENU_CONT:
    SUBQ.W      #0x6,(A1)                       | lastMenu -= 6 (one entry)
| Called by: DELETEMENU, HILITEMENU_RESTORE_VISRGN, MENUKEY_DONE, GETMHANDLE_RTS, SETMENUFLASH
MENUMGR_STRIP_PARAM_RTS:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDQ.W      #0x2,A7                         | strip menuID param (2 bytes)
    JMP         (A0)                            | tail-call return from MENUMGR_STRIP_PARAM_RTS via A0
| ----------------------------------------------------------
|
| DrawMBar (MBDF helper): force MBDF redraw with no flash flag.
| param = -1 means "internal redraw" (skip alarm-bit reset).
DRAWMBAR:
    CLR.W       D0                              | MBDF msg #0 = draw
    MOVEQ.L     #-0x1,D1                        | param = -1 (internal redraw)
    BSR.W       MENU_CALL_MBDF                  | dispatch to MBDF
    RTS                                         | return from DRAWMBAR
| ----------------------------------------------------------
|
| _DrawMenuBar ($A937): redraw the entire menu bar.
| Pascal: procedure DrawMenuBar;
| Sets AlarmState bit 7 (alarm acknowledged) so the apple icon won't flash.
DRAWMENUBAR:
    BSET        #0x7,(AlarmState)               | clear pending alarm flash
    CLR.W       D0                              | MBDF msg #0 = draw
    MOVEQ.L     #0x0,D1                         | param = 0 (full draw)
    BSR.W       MENU_CALL_MBDF                  | dispatch to MBDF
    RTS                                         | return from DRAWMENUBAR
| ----------------------------------------------------------
|
| _HiliteMenu ($A938): highlight the title of a menu in the menu bar.
| Pascal: procedure HiliteMenu(menuID: INTEGER);
| menuID=0 = unhighlight current. Hilites at most one title at a time.
HILITEMENU:
    MOVE.W      (TheMenu).W,D1                  | D1 = currently highlighted menuID
    BEQ.B       HILITEMENU_NEW                  | none -> just hilite new one
    CMP.W       0x4(A7),D1                      | already highlighted?
    BEQ.B       HILITEMENU_SET_THEMENU          | yes -> nothing to do, return
    BSR.W       INSERTMENU_CONT_2               | locate current menuID in MenuList
    BEQ.B       HILITEMENU_NEW                  | not found -> skip unhilite
    MOVEQ.L     #0x0,D1                         | D1.h = 0 (unhilite flag)
    MOVE.W      D0,D1                           | D1.l = byte offset
    MOVE.W      #0x5,D0                         | MBDF msg #5 = hilite
    BSR.W       MENU_CALL_MBDF                  | dispatch unhilite to MBDF
HILITEMENU_NEW:
    MOVE.W      0x4(A7),D1                      | D1 = new menuID to hilite
    BSR.W       INSERTMENU_CONT_2               | locate it in MenuList
    BEQ.B       HILITEMENU_NOT_FOUND            | not found -> set TheMenu = 0
    SWAP.W      D0                              | put offset in D0.h
    MOVE.W      #0x1,D0                         | D0.l = 1 (hilite flag)
    SWAP.W      D0                              | offset back in D0.l, flag in D0.h
    MOVE.L      D0,D1                           | D1 = (offset, hilite=1)
    MOVE.W      #0x5,D0                         | MBDF msg #5 = hilite
    BSR.W       MENU_CALL_MBDF                  | dispatch hilite to MBDF
HILITEMENU_SET_THEMENU:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    MOVE.W      (A7)+,(TheMenu).W               | TheMenu = new menuID; strip param
    JMP         (A0)                            | tail-call return from HILITEMENU_SET_THEMENU via A0
| Not-found path: clear TheMenu and return.
HILITEMENU_NOT_FOUND:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDQ.L      #0x2,A7                         | strip menuID param
    CLR.W       (TheMenu).W                     | TheMenu = 0
    JMP         (A0)                            | tail-call return from HILITEMENU_NOT_FOUND via A0
| ----------------------------------------------------------
|
| _EnableItem ($A93A): enable a menu item.
| Pascal: procedure EnableItem(theMenu: MenuHandle; item: INTEGER);
| item=0 enables the entire menu (item-0 = title flag).
ENABLEITEM:
    BSR.B       ENABLEITEM_CONT                 | A0 = MenuInfo, D0 = item, D1 = enableFlags
    BSET        D0,D1                           | set bit for item
ENABLEITEM_EXIT:
    MOVE.L      D1,0xA(A0)                      | store updated enableFlags in MenuInfo
    BRA.W       INSERTMENU_EXIT                 | -> strip params + return
| ----------------------------------------------------------
|
| ENABLEITEM_CONT: shared header for EnableItem/DisableItem/CheckItem.
| In:  stack frame with theMenu (long) and item (word)
| Out: A0 = deref MenuInfo, D0 = item index, D1 = current enableFlags
| Called during boot (157,003 times in 30s trace).
ENABLEITEM_CONT:
    MOVEA.L     0xA(A7),A0                      | A0 = MenuHandle (10 bytes deep on stack)
    MOVEA.L     (A0),A0                         | deref to MenuInfo
    MOVE.W      0x8(A7),D0                      | D0 = item
    MOVE.L      0xA(A0),D1                      | D1 = current enableFlags (32 bits)
    RTS                                         | return from ENABLEITEM_CONT
| ----------------------------------------------------------
|
| _DisableItem ($A93B): disable a menu item.
| Pascal: procedure DisableItem(theMenu: MenuHandle; item: INTEGER);
DISABLEITEM:
    BSR.B       ENABLEITEM_CONT                 | A0/D0/D1 setup
    BCLR        D0,D1                           | clear bit for item
    BRA.B       ENABLEITEM_EXIT                 | -> store and return
| ----------------------------------------------------------
|
| DISABLEITEM_NEXT: get the MenuHandle at MenuList[D5] and deref to MenuInfo.
| In:  D5 = byte offset within MenuList header
| Out: A0 = deref MenuInfo, A1 = MenuHandle
| Called during boot (57,585 times in 30s trace).
DISABLEITEM_NEXT:
    BSR.B       DISABLEITEM_CONT                | A0 = deref MenuList header
    MOVEA.L     0x0(A0,D5.W),A1                 | A1 = MenuHandle at offset D5
    TST.L       (A1)                            | empty handle (purged)?
    BEQ.B       DISABLEITEM_ERR                 | yes -> SysError 84
    MOVEA.L     (A1),A0                         | A0 = deref MenuInfo
    RTS                                         | return from DISABLEITEM_NEXT
| ----------------------------------------------------------
|
| DISABLEITEM_CONT / _2 / _3: deref MenuList handle, validate not purged.
| Out: A0 (or A1) = deref MenuList header. SysError 84 if MenuList purged.
| Called during boot (63,856 times in 30s trace).
DISABLEITEM_CONT:
    MOVEA.L     (MenuList).W,A0                 | A0 = MenuList handle
| DISABLEITEM_CONT_2 -- A0 = handle on entry, deref in place.
DISABLEITEM_CONT_2:
    TST.L       (A0)                            | handle empty (purged)?
    BEQ.B       DISABLEITEM_ERR                 | yes -> SysError 84
    MOVEA.L     (A0),A0                         | A0 = deref ptr
    RTS                                         | return from DISABLEITEM_CONT_2
| ----------------------------------------------------------
|
| DISABLEITEM_CONT_3: same but returns in A1 (preserves A0).
| Called during boot.
DISABLEITEM_CONT_3:
    MOVEA.L     (MenuList).W,A1                 | A1 = MenuList handle
    TST.L       (A1)                            | purged?
    BEQ.B       DISABLEITEM_ERR                 | yes -> SysError 84
    MOVEA.L     (A1),A1                         | A1 = deref ptr
    RTS                                         | return from DISABLEITEM_CONT_3
DISABLEITEM_ERR:
    MOVEQ.L     #0x54,D0                        | error #84 = nilHandleErr
    _SysError                                   | fatal: MenuList was purged
| ----------------------------------------------------------
|
| MBDF hilite helpers: dispatch msg #5 (hilite/unhilite) given an offset in D0.
| In:  D0 = byte offset of menu in MenuList header
| MBDF_UNHILITE_OFFSET unhilites (flag=0); MBDF_HILITE_OFFSET hilites (flag=1).
MBDF_UNHILITE_OFFSET:
    MOVEQ.L     #0x0,D1                         | hilite flag = 0 (unhilite)
    BRA.B       MBDF_HILITE_DISPATCH            | -> common dispatch
MBDF_HILITE_OFFSET:
    MOVEQ.L     #0x1,D1                         | hilite flag = 1 (hilite)
MBDF_HILITE_DISPATCH:
    SWAP.W      D1                              | move flag to D1.h
    MOVE.W      D0,D1                           | D1.l = byte offset
    MOVE.W      #0x5,D0                         | MBDF msg #5 = hilite
    BSR.W       MENU_CALL_MBDF                  | dispatch to MBDF
    RTS                                         | return from MBDF_UNHILITE_OFFSET/MBDF_HILITE_OFFSET
| ----------------------------------------------------------
|
| _MenuSelect ($A93D): track mouse through the menu bar and into a menu.
| Pascal: function MenuSelect(startPt: Point): LongInt;
| Returns: high word = chosen menuID (0 if none), low word = item index
| Stack frame (A6+offset): saved A6 / RA / startPt(8) / result(C)
| Locals (A6-offset): rect(-8..-1), savedPort(-C..-9), unused(-14..-D)
MENUSELECT:
    LINK        A6,#-0x14                       | reserve 20 bytes of locals
    MOVEM.L     D3-D7/A3,-(A7)                  | save regs
    CLR.L       -(A7)                           | _HiliteMenu(0): unhilite any active menu
    _HiliteMenu                                 | clear current menu hilite
    CLR.L       0xC(A6)                         | result = 0L (no choice yet)
    _WaitMouseUp                                | mouse button still down?
    TST.B       (A7)+                           | test result of WaitMouseUp
    BEQ.W       MENUSELECT_NO_7                 | button up -> exit (no choice)
    PEA.L       -0xC(A6)                        | push &savedPort
    _GetPort                                    | save current port
    MOVE.L      (WMgrPort).W,-(A7)              | push WMgrPort
    _SetPort                                    | switch to WMgr port
    CLR.W       D5                              | D5 = newMenuOffset = 0
    CLR.W       D4                              | D4 = currentMenuOffset = 0
    MOVE.L      0x8(A6),D3                      | D3 = startPt (mouse position)
| Main tracking loop: ask MBDF which menu (if any) the mouse is over,
| switch hilite if the mouse moved between titles, then track item.
MENUSELECT_TRACK_LOOP:
    MOVE.W      #0x1,D0                         | MBDF msg #1 = FindMenu
    MOVE.L      D3,D1                           | param = mouse point
    BSR.W       MENU_CALL_MBDF                  | dispatch -> D0 = result
    TST.L       D0                              | check result
    BMI.W       MENUSELECT_SKIP                 | <0 -> apple/system menu (or no change)
    BEQ.W       MENUSELECT_NO_3                 | =0 -> not over any menu
    MOVE.L      D0,D5                           | D5 = byte offset of new menu
    BSR.W       DISABLEITEM_NEXT                | A0 = MenuInfo for D5 (via D5 as offset)
    MOVE.W      (A0),0xC(A6)                    | result.menuID = MenuInfo.menuID
    CMP.W       D5,D4                           | same as previous menu?
    BEQ.W       MENUSELECT_SKIP                 | yes -> just track item
    TST.W       D4                              | had a previous menu?
    BEQ.B       MENUSELECT_NO                   | no -> just hilite new
    BSR.W       MENUSELECT_CONT_5               | yes -> MBDF msg #8 (hide previous menu)
    MOVE.W      D4,D0                           | D0 = previous offset
    BSR.B       MBDF_UNHILITE_OFFSET            | unhilite previous title
MENUSELECT_NO:
    MOVE.W      D5,D4                           | currentMenuOffset = newMenuOffset
    CLR.W       0xE(A6)                         | result.item = 0
    TST.W       D5                              | new menu valid?
    BEQ.B       MENUSELECT_SKIP_2               | no -> tracking with no menu
    MOVE.W      D5,D0                           | D0 = new offset
    BSR.B       MBDF_HILITE_OFFSET              | hilite new title
    MOVE.L      (MBarHook).W,D0                 | MBarHook installed?
    BEQ.B       MENUSELECT_SHOW                 | no -> show menu directly
    MOVEA.L     D0,A0                           | A0 = MBarHook ptr
    PEA.L       -0x8(A6)                        | push &rect (will be filled by MBDF)
    JSR         (A0)                            | call MBarHook
    TST.W       D0                              | hook says cancel?
    BNE.B       MENUSELECT_NORMAL_COMMIT        | yes -> exit
MENUSELECT_SHOW:
    BSR.W       MBDF_SHOW_MENU                  | MBDF msg #7 (calc rect, save bits, draw menu)
MENUSELECT_SKIP:
    TST.W       D5                              | menu currently shown?
MENUSELECT_SKIP_2:
    BEQ.B       MENUSELECT_NO_3                 | no -> just track mouse
    PEA.L       -0x8(A6)                        | clip to menu rect
    _ClipRect                                   | restrict drawing to menu
    BSR.W       DISABLEITEM_NEXT                | A1 = MenuHandle for D5
    MOVE.W      #0x1,-(A7)                      | MDEF msg #1 = MDrawMsg / MChooseMsg
    MOVE.L      A1,-(A7)                        | push MenuHandle
    PEA.L       -0x8(A6)                        | push &menuRect
    MOVE.L      D3,-(A7)                        | push mouse point
    PEA.L       0xE(A6)                         | push &item (where MDEF returns chosen)
    BSR.W       MENUSELECT_CONT_8               | load MDEF if needed; A0 = MDEF code ptr
    JSR         (A0)                            | call MDEF
    BSR.W       MDEF_UNLOCK                     | unlock MDEF if loaded
    BSR.W       FULLCLIP                        | restore full WMgr clip rect
| Track-mouse loop tail: wait for next event, refresh mouse, run hook, repeat.
MENUSELECT_NO_3:
    CLR.W       -(A7)                           | _WaitMouseUp result slot
    _WaitMouseUp                                | mouse still down? (yields one tick)
    TST.B       (A7)+                           | check
    BEQ.B       MENUSELECT_NO_5                 | button up -> commit selection
    SUBQ.W      #0x4,A7                         | reserve 4 bytes for mouse pt
    MOVE.L      A7,-(A7)                        | push &mousePt
    _GetMouse                                   | refresh mouse position
    MOVE.L      (A7)+,D3                        | D3 = current mouse point
    MOVE.L      (MenuHook).W,D0                 | MenuHook installed?
    BEQ.B       MENUSELECT_AFTER_HOOK           | no -> skip
    MOVEA.L     D0,A0                           | A0 = MenuHook ptr
    JSR         (A0)                            | call hook
MENUSELECT_AFTER_HOOK:
    BRA.W       MENUSELECT_TRACK_LOOP           | -> next iteration
| Mouse-up commit: flash, hide menu, set TheMenu, possibly call SystemMenu.
MENUSELECT_NO_5:
    TST.W       D5                              | menu currently shown?
    BEQ.B       MENUSELECT_NO_6                 | no -> skip flash/hide
    BSR.W       MENUSELECT_CONT_11              | flash chosen item N times
    BSR.B       MENUSELECT_CONT_5               | MBDF msg #8 (hide menu)
MENUSELECT_NO_6:
    TST.W       0xE(A6)                         | item chosen?
    BNE.B       MENUSELECT_EXIT                 | yes -> set TheMenu
    CLR.W       0xC(A6)                         | no item -> clear menuID part
    MOVE.W      D5,D0                           | D0 = current offset
    BEQ.B       MENUSELECT_EXIT                 | no menu was hilited -> skip unhilite
    BSR.W       MBDF_UNHILITE_OFFSET            | unhilite the title
MENUSELECT_EXIT:
    MOVE.W      0xC(A6),(TheMenu).W             | TheMenu = chosen menuID (0 if none)
    BMI.B       MENUSELECT_CONT_2               | system menu (negative ID) -> dispatch
    TST.W       (MBarEnable).W                  | MBar disabled (system mode)?
    BMI.B       MENUSELECT_CONT_2               | yes -> dispatch system menu
MENUSELECT_NORMAL_COMMIT:
    MOVE.L      -0xC(A6),-(A7)                  | restore saved port
    _SetPort                                    | back to caller's port
| Final exit: pop locals, strip mousePt param, leave result on stack.
MENUSELECT_NO_7:
    MOVEM.L     (A7)+,D3-D7/A3                  | restore regs
    UNLK        A6                              | tear down frame
    MOVE.L      (A7)+,(A7)                      | strip startPt: mv RA up over it
    MOVEQ.L     #0x0,D1                         | clear D1 (legacy convention)
    RTS                                         | return; result is in caller's slot
| System-menu chosen: invoke _SystemMenu and clear local result.
MENUSELECT_CONT_2:
    MOVE.L      0xC(A6),-(A7)                   | push result long (menuID:item)
    _SystemMenu                                 | dispatch desk accessory / Apple-menu item
    CLR.L       0xC(A6)                         | result = 0 (consumed by SystemMenu)
    BRA.B       MENUSELECT_NORMAL_COMMIT        | -> restore port and exit
| ----------------------------------------------------------
|
| MBDF msg #8 dispatch: hide a menu (restore bits beneath it).
| In: D4 = byte offset of menu in MenuList header
MENUSELECT_CONT_5:
    MOVEM.L     D4/A2-A4,-(A7)                  | save scratch regs
    MOVE.W      #0x8,D0                         | MBDF msg #8 = hide menu
    MOVE.L      D4,D1                           | param = menu offset
    BSR.W       MENU_CALL_MBDF                  | dispatch to MBDF
    MOVEM.L     (A7)+,D4/A2-A4                  | restore regs
    RTS                                         | return from MENUSELECT_CONT_5
| ----------------------------------------------------------
|
| MBDF msg #7 dispatch: show menu (compute rect, save bits, draw frame).
| In: D4 = byte offset of menu
| Out: -8(A6)..-1(A6) = menu rect; MDEF msg #0 (draw items) called inside
MBDF_SHOW_MENU:
    MOVEM.L     D4/A2-A4,-(A7)                  | save regs
    MOVE.W      #0x7,D0                         | MBDF msg #7 = show menu
    MOVE.L      D4,D1                           | param = menu offset
    BSR.W       MENU_CALL_MBDF                  | dispatch to MBDF -> A0=&rect
    MOVEA.L     D0,A0                           | A0 = MBDF result (rect ptr)
    MOVE.L      (A0),-0x8(A6)                   | copy topLeft to local rect
    MOVE.L      0x4(A0),-0x4(A6)                | copy botRight to local rect
    PEA.L       -0x8(A6)                        | clip drawing to menu rect
    _ClipRect                                   | restrict to menu region
    CLR.W       -(A7)                           | MDEF msg #0 = MDrawMsg
    BSR.W       DISABLEITEM_NEXT                | A1 = MenuHandle
    MOVE.L      A1,-(A7)                        | push MenuHandle
    PEA.L       -0x8(A6)                        | push &menuRect
    SUBQ.W      #0x8,A7                         | reserve 8 bytes (point + result)
    BSR.B       MENUSELECT_CONT_8               | load MDEF; A0 = MDEF code
    JSR         (A0)                            | call MDEF (draws items)
    BSR.B       MDEF_UNLOCK                     | unlock MDEF
    MOVEM.L     (A7)+,D4/A2-A4                  | restore regs
    RTS                                         | return from MBDF_SHOW_MENU
| ----------------------------------------------------------
|
| Load MDEF code from MenuInfo and lock for execution.
| In:  A0 = deref MenuInfo (set up by DISABLEITEM_NEXT in caller)
| Out: A0 = MDEF entry point (deref of MenuInfo.menuProc)
| If MDEF handle is nil, hijacks return address to MDEF_CLEANUP_STRIP12 (cleanup
| stub that strips the 12 bytes of MDEF args and returns to caller's caller).
MENUSELECT_CONT_8:
    MOVE.L      0x6(A0),D0                      | D0 = MenuInfo.menuProc handle
    LEA.L       MDEF_CLEANUP_STRIP12(PC),A0     | A0 = cleanup stub (default)
    BEQ.B       MENUSELECT_EMPTY_2              | nil handle -> return cleanup stub
    MOVEA.L     D0,A0                           | A0 = MDEF handle
    MOVE.L      A0,-(A7)                        | save handle for HLock below
    _LoadResource                               | reload if purged
    _HLock                                      | lock for execution
    MOVEA.L     (A0),A0                         | A0 = MDEF code ptr (deref handle)
MENUSELECT_EMPTY_2:
    RTS                                         | return from MENUSELECT_CONT_8
| MDEF cleanup stub: strip 12 bytes of MDEF args and return to outer caller.
MDEF_CLEANUP_STRIP12:
    MOVEA.L     (A7)+,A0                        | A0 = return addr to outer caller
    ADDA.W      #0xC,A7                         | strip 12 bytes of MDEF args
    JMP         (A0)                            | return to outer caller
| ----------------------------------------------------------
|
| Unlock MDEF code after dispatch (paired with MENUSELECT_CONT_8).
MDEF_UNLOCK:
    BSR.W       DISABLEITEM_NEXT                | A0 = MenuInfo
MENUSELECT_CONT_10:
    MOVE.L      0x6(A0),D0                      | D0 = MenuInfo.menuProc handle
    BEQ.B       MENUSELECT_EMPTY_3              | nil -> nothing to unlock
    MOVEA.L     D0,A0                           | A0 = handle
    _HUnlock                                    | unlock MDEF
MENUSELECT_EMPTY_3:
    RTS                                         | return from MDEF_UNLOCK/MENUSELECT_CONT_10
| ----------------------------------------------------------
|
| Final-flash helper: blink the chosen item N times before MenuSelect returns.
| N = (MenuFlash) PRAM setting (0 = no flash). Each iteration toggles
| the item hilite via FULLCLIP_CONT and waits 3 ticks.
| Called during boot.
MENUSELECT_CONT_11:
    MOVE.W      D4,-(A7)                        | save current menu offset
    MOVE.W      (MenuFlash).W,D4                | D4 = flash count from PRAM
    BEQ.B       MENUSELECT_SKIP_3               | flash disabled -> skip
    MOVE.W      0xE(A6),(ToolScratch).W         | item index for MDEF dispatch
    BEQ.B       MENUSELECT_SKIP_3               | item = 0 -> nothing to flash
    PEA.L       -0x8(A6)                        | clip to menu rect
    _ClipRect                                   | restrict drawing
MENUSELECT_LOOP_3:
    MOVEQ.L     #0x0,D1                         | flag = 0 (unhilite item)
    BSR.B       FULLCLIP_CONT                   | toggle item -> wait 3 ticks
    MOVE.L      D3,D1                           | flag = mouse pt (nonzero -> hilite)
    BSR.B       FULLCLIP_CONT                   | toggle item -> wait 3 ticks
    SUBQ.W      #0x1,D4                         | flash count -= 1
    BNE.B       MENUSELECT_LOOP_3               | repeat N times
    BSR.B       FULLCLIP                        | restore full WMgr clip rect
MENUSELECT_SKIP_3:
    MOVE.W      (A7)+,D4                        | restore D4
    RTS                                         | return from MENUSELECT_CONT_11
| ----------------------------------------------------------
|
| Restore the WMgr port's full clip region (after a per-menu ClipRect).
FULLCLIP:
    MOVEA.L     (WMgrPort).W,A0                 | A0 = WMgrPort
    PEA.L       0x10(A0)                        | push &portRect (offset 0x10)
    _ClipRect                                   | clip = entire screen
    RTS                                         | return from FULLCLIP
| ----------------------------------------------------------
|
| Flash-helper: dispatch MDEF msg #1 (MChooseMsg) for the current item then
| busy-wait 3 ticks. Used by MENUSELECT_CONT_11 to toggle item hilite.
| In: D1 = mouse-point or 0 (controls hilite/unhilite via MDEF logic)
FULLCLIP_CONT:
    MOVE.W      #0x1,-(A7)                      | MDEF msg #1 = MChooseMsg
    BSR.W       DISABLEITEM_NEXT                | A1 = MenuHandle
    MOVE.L      A1,-(A7)                        | push MenuHandle
    PEA.L       -0x8(A6)                        | push &menuRect
    MOVE.L      D1,-(A7)                        | push hit point
    PEA.L       (ToolScratch).W                 | push &item (will be returned)
    BSR.B       MENUSELECT_CONT_8               | load MDEF; A0 = code
    JSR         (A0)                            | call MDEF
    BSR.B       MDEF_UNLOCK                     | unlock MDEF
    MOVE.L      (Ticks).W,D0                    | D0 = current tick count
    ADDQ.L      #0x3,D0                         | target = now + 3 ticks (~50 ms)
MENUSELECT_FLASH_SPIN:
    CMP.L       (Ticks).W,D0                    | reached target?
    BGT.B       MENUSELECT_FLASH_SPIN           | no -> spin
    RTS                                         | return from FULLCLIP_CONT
| ----------------------------------------------------------
|
| _GetMenuBar ($A93B): copy the current MenuList to a new handle.
| Pascal: function GetMenuBar: Handle;
| Used to save/restore menu-bar state across mode switches.
GETMENUBAR:
    BSR.W       CALCMBHEIGHT_EMPTY              | allocate empty MenuList copy -> A0
    MOVE.L      A0,0x4(A7)                      | store as result on stack
    MOVEA.L     (A0),A1                         | A1 = deref new copy (dest)
    BSR.W       DISABLEITEM_CONT                | A0 = deref current MenuList (src)
GETMENUBAR_CONT:
    MOVEQ.L     #0x66,D0                        | 102 bytes (MenuList header + 16 entries)
    _BlockMove                                  | copy MenuList contents
    RTS                                         | return from GETMENUBAR
| ----------------------------------------------------------
|
| _SetMenuBar ($A93C): restore a saved MenuList.
| Pascal: procedure SetMenuBar(menuList: Handle);
SETMENUBAR:
    MOVEA.L     0x4(A7),A0                      | A0 = saved MenuList handle
    BSR.W       DISABLEITEM_CONT_2              | A0 = deref source
    BSR.W       DISABLEITEM_CONT_3              | A1 = deref current MenuList
    MOVE.L      (A7)+,(A7)                      | strip handle param (RA up)
    BRA.B       GETMENUBAR_CONT                 | -> BlockMove + return
| ----------------------------------------------------------
|
| _DisposeMenu ($A932): free a menu handle.
| Pascal: procedure DisposeMenu(theMenu: MenuHandle);
| Uses TE_APPLY_JUST_MEASURE if it came from a resource file (bit 5 of menuFlags),
| else plain DisposeHandle.
DISPOSEMENU:
    MOVEA.L     0x4(A7),A0                      | A0 = MenuHandle
    BTST        #0x5,(A0)                       | resource-loaded flag set?
    BEQ.B       DISPOSEMENU_NO                  | no -> plain DisposeHandle
    MOVE.L      A0,-(A7)                        | push handle for TE_APPLY_JUST_MEASURE
    _ReleaseResource                            | release resource handle
    BRA.B       DISPOSEMENU_EXIT                | -> exit
| DISPOSEMENU_NO - dispose plain (non-resource) menu handle
DISPOSEMENU_NO:
    _DisposeHandle                              | A-pre-loaded handle in A0
DISPOSEMENU_EXIT:
    MOVE.L      (A7)+,(A7)                      | strip handle param (RA up)
    RTS                                         | return from DISPOSEMENU
| ----------------------------------------------------------
|
| _FlashMenuBar ($A94C): briefly invert a menu title (or whole bar).
| Pascal: procedure FlashMenuBar(menuID: INTEGER);
| menuID = 0 toggles the apple/MBar background; nonzero toggles a single
| title. Implemented by saving the visRgn, doing a hilite/unhilite via
| MBDF msg #5, then CopyRgn back.
FLASHMENUBAR:
    MOVE.L      D4,-(A7)                        | save D4
    MOVEA.L     (WMgrPort).W,A0                 | A0 = WMgrPort
    MOVEA.L     0x1C(A0),A0                     | A0 = WMgrPort.visRgn handle
    MOVE.L      A0,-(A7)                        | push original visRgn handle
    _HandToHand                                 | duplicate -> new handle in A0
    MOVE.L      (A7)+,D0                        | D0 = handToHand result code
    MOVE.L      A0,-(A7)                        | push duplicated visRgn (later DisposeRgn)
    MOVE.L      A0,-(A7)                        | push it again (CopyRgn dest)
    MOVE.L      D0,-(A7)                        | push result (CopyRgn src - garbage if D0!=0)
    MOVE.W      0x14(A7),D1                     | D1 = menuID arg
    BEQ.B       FLASHMENUBAR_APPLE              | menuID=0 -> apple/whole-bar flash
    BSR.W       INSERTMENU_CONT_2               | locate menuID in MenuList
    BEQ.B       HILITEMENU_RESTORE_VISRGN       | not found -> just restore visRgn
    CMP.W       (TheMenu).W,D1                  | this menu currently hilited?
    BEQ.B       HILITEMENU_UNHILITE             | yes -> unhilite first
    BSR.W       MBDF_HILITE_OFFSET              | hilite the title
    BRA.B       HILITEMENU_RESTORE_VISRGN       | -> restore visRgn
HILITEMENU_UNHILITE:
    BSR.W       MBDF_UNHILITE_OFFSET            | unhilite the title
HILITEMENU_RESTORE_VISRGN:
    _CopyRgn                                    | restore original visRgn (undoes draw)
    _DisposeRgn                                 | free temporary handle
    MOVE.L      (A7)+,D4                        | restore D4
    BRA.W       MENUMGR_STRIP_PARAM_RTS         | -> strip param + indirect return
| Apple-menu flash path: toggle MBFlash bit, hilite/unhilite the title region.
FLASHMENUBAR_APPLE:
    MOVEQ.L     #0x0,D0                         | offset 0 = apple-menu / whole bar
    NOT.W       (MBFlash).W                     | toggle MBFlash flag
    BEQ.B       FLASHMENUBAR_UNHILITE           | flag was nonzero (now 0) -> unhilite
    BSR.W       MBDF_HILITE_OFFSET              | hilite (msg #5, flag=1)
    BRA.B       HILITEMENU_RESTORE_VISRGN       | -> restore visRgn
FLASHMENUBAR_UNHILITE:
    BSR.W       MBDF_UNHILITE_OFFSET            | unhilite (msg #5, flag=0)
    BRA.B       HILITEMENU_RESTORE_VISRGN       | -> restore visRgn
| ----------------------------------------------------------
|
| MBDF dispatch helper (SE FDHD-specific).
| Builds an MBDF stack frame, loads the 'MBDF' resource, locks it, calls
| its code, unlocks, and returns the MBDF result in D0.
| In:  D0 = MBDF message number, D1 = parameter long
| Out: D0 = MBDF return value (typically a byte offset or rect ptr)
| MBDF stack frame layout (caller's view): result(L), MenuList[+4](W=resID),
|   msg(W), param(L), padding(L), 'MBDF'(L), ID=0(W) -- last two are for
|   the GetResource call inside this routine.
| Called by: INITMENUS_BODY, INSERTMENU_STORE, DRAWMBAR, DRAWMENUBAR, HILITEMENU (and 5 more)
MENU_CALL_MBDF:
    CLR.L       -(A7)                           | reserve MBDF result slot
    MOVEA.L     (MenuList).W,A0                 | A0 = MenuList handle
    MOVEA.L     (A0),A0                         | deref to MenuList header
    MOVE.W      0x4(A0),-(A7)                   | push MBDF resID (first menuLeft slot)
    MOVE.W      D0,-(A7)                        | push msg
    MOVE.L      D1,-(A7)                        | push param
    SUBQ.W      #0x4,A7                         | reserve _GetResource result slot
    MOVE.L      #0x4D424446,-(A7)               | push 'MBDF' resType
    CLR.W       -(A7)                           | push resID = 0
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | force ROM resource map search
    _GetResource                                | -> handle in result slot
    MOVE.L      (A7)+,(MBProcHndl).W            | save handle in MBProcHndl
    MOVEA.L     (MBProcHndl).W,A0               | A0 = handle
    _HLock                                      | lock MBDF for execution
    MOVEA.L     (MBProcHndl).W,A0               | A0 = handle
    MOVEA.L     (A0),A0                         | A0 = MBDF code ptr
    JSR         (A0)                            | call MBDF (consumes msg/param/resID)
    MOVEA.L     (MBProcHndl).W,A0               | A0 = handle
    _HUnlock                                    | unlock MBDF
    MOVE.L      (A7)+,D0                        | D0 = MBDF return value
    RTS                                         | return from MENU_CALL_MBDF
| ----------------------------------------------------------
|
| Walk MenuInfo to locate the Nth item (item entries are variable-length).
| MenuInfo layout: header(0xE bytes), title(Pascal str), items...
| Each item: nameLen.B, name.B*nameLen, icon.B, key.B, mark.B, style.B
| In:  A0 = deref MenuInfo, D0 = item number (1-based)
| Out: If found: A0 = ptr to item title (Pascal str), A1 = ptr to attribute
|      bytes (icon @ A1+0, key @ A1+1, mark @ A1+2, style @ A1+3); Z clear.
|      If not found: A0 = A1 = 0, D0/D1 = 0; Z set.
| Called by: MENUMGR_CONT, MENUMGR_CONT_2, MENUKEY_NEXT_2, GETITEM, INSMENUITEM_CONT_4 (and 4 more)
GETITEM_FIND:
    TST.W       D0                              | item number valid?
    BLE.B       MENUMGR_FOUND                   | <=0 -> not found
    MOVEQ.L     #0x0,D1                         | clear D1.h for length byte
    LEA.L       0xE(A0),A1                      | A1 = MenuInfo + 0xE (start of title)
    MOVE.B      (A1)+,D1                        | D1 = title length
    ADDA.W      D1,A1                           | A1 = past title (start of items)
| walk through items to find the Nth one
MENUMGR_NEXT:
    SUBQ.W      #0x1,D0                         | item count -= 1
    BEQ.B       RETURNS_17                      | reached target -> return
    MOVE.B      (A1),D1                         | D1 = item nameLen
    BEQ.B       MENUMGR_FOUND                   | 0 = end of items -> not found
    ADDQ.W      #0x5,D1                         | + 5 (nameLen byte + 4 attr bytes)
    ADDA.W      D1,A1                           | advance to next item
    BRA.B       MENUMGR_NEXT                    | continue
| item not found: return nil
MENUMGR_FOUND:
    MOVE.L      A1,D1                           | preserve A1 in D1 (caller may use)
    SUBA.L      A0,A0                           | A0 = 0 (not found)
    MOVEA.L     A0,A1                           | A1 = 0
    MOVE.L      A0,D0                           | D0 = 0 (sets Z flag)
    RTS                                         | return from GETITEM_FIND
| ----------------------------------------------------------
|
| Item-found tail: A1 points to a non-empty item entry, decode title + attrs.
| Out: A0 = ptr to nameLen byte (item title Pascal str start),
|      A1 = ptr to icon attribute byte (immediately after title), Z clear.
| Called during boot (22,222 times in 30s trace).
RETURNS_17:
    TST.B       (A1)                            | nameLen = 0?
    BEQ.B       MENUMGR_FOUND                   | empty entry -> not found
    MOVEA.L     A1,A0                           | A0 = item title start
    MOVE.B      (A1)+,D1                        | D1 = nameLen, A1 -> name body
    ADDA.W      D1,A1                           | A1 = past name (icon byte)
    RTS                                         | return from RETURNS_17
| ----------------------------------------------------------
|
| MENUMGR_CONT: shared body for SetItemIcon / SetItemKey / SetItemMark / SetItemStyle.
| Stack: [ret(4), value.B(1), pad(1), item#(2), MenuHandle(4)]
| In: D2 = attribute index (0=icon, 1=key, 2=mark, 3=style)
| Called during boot (22,164 times in 30s trace).
MENUMGR_CONT:
    MOVEA.L     0x8(A7),A0                      | A0 = MenuHandle
    MOVEA.L     (A0),A0                         | deref to MenuInfo
    MOVE.W      0x6(A7),D0                      | D0 = item number
    BSR.B       GETITEM_FIND                    | locate item -> A1 = attr ptr
    BEQ.B       MENUMGR_SKIP                    | not found -> nothing to set
    MOVE.B      0x5(A7),0x0(A1,D2.W)            | item.attr[D2] = value
    SUBQ.W      #0x2,D2                         | D2 was mark (2)?
    BEQ.B       MENUMGR_SKIP                    | yes -> skip redraw (mark only)
    MOVE.L      0x8(A7),-(A7)                   | push MenuHandle (for redraw)
    BSR.W       STACK_2                         | recompute & redraw if visible
MENUMGR_SKIP:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDQ.W      #0x8,A7                         | strip params (8 bytes)
    JMP         (A0)                            | tail-call return from MENUMGR_SKIP via A0
| ----------------------------------------------------------
|
| MENUMGR_CONT_2: shared body for GetItemIcon / GetItemKey / GetItemMark / GetItemStyle.
| Stack: [ret(4), VAR resultPtr(4), item#(2), pad(2), MenuHandle(4)]
| In: D2 = attribute index (0=icon, 1=key, 2=mark, 3=style)
| Out: *resultPtr.W = (0 high byte, attr.B low byte) = INTEGER
MENUMGR_CONT_2:
    MOVEA.L     0xA(A7),A0                      | A0 = MenuHandle
    MOVEA.L     (A0),A0                         | deref to MenuInfo
    MOVE.W      0x8(A7),D0                      | D0 = item number
    BSR.B       GETITEM_FIND                    | locate item -> A1 = attr ptr
    MOVEA.L     0x4(A7),A0                      | A0 = VAR resultPtr
    CLR.B       (A0)                            | result high byte = 0
    MOVE.L      A1,D0                           | check found?
    BEQ.B       MENUMGR_NO                      | not found -> result = 0
    MOVE.B      0x0(A1,D2.W),0x1(A0)            | result low byte = item.attr[D2]
| Common exit for MENUMGR_CONT_2 / GetMenuItemText / InsMenuItem etc.
| Called by: MENUMGR_CONT_2, GETMENUITEMTEXT_CONT, INSMENUITEM, SETMENUITEMTEXT_FOUND, INSERTRESMENU_DONE
MENUMGR_NO:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    ADDA.W      #0xA,A7                         | strip 10 bytes of params
    JMP         (A0)                            | tail-call return from MENUMGR_NO via A0
| ----------------------------------------------------------
|
| Get/Set item-attribute trap stubs: select attribute index in D2 then
| dispatch to the shared MENUMGR_CONT (set) or MENUMGR_CONT_2 (get).
| _GetItemIcon ($A93F): D2=0
GETITEMICON:
    MOVEQ.L     #0x0,D2                         | attr index 0 = icon
    BRA.B       MENUMGR_CONT_2                  | -> shared get
| _SetItemIcon ($A940): D2=0
SETITEMICON:
    MOVEQ.L     #0x0,D2                         | attr index 0 = icon
    BRA.B       MENUMGR_CONT                    | -> shared set
| _GetItemStyle ($A943): D2=3
GETITEMSTYLE:
    MOVEQ.L     #0x3,D2                         | attr index 3 = style
    BRA.B       MENUMGR_CONT_2                  | -> shared get
| _SetItemStyle ($A942): D2=3
SETITEMSTYLE:
    MOVEQ.L     #0x3,D2                         | attr index 3 = style
    BRA.B       MENUMGR_CONT                    | -> shared set
| _GetItemMark ($A944): D2=2
GETITEMMARK:
    MOVEQ.L     #0x2,D2                         | attr index 2 = mark
    BRA.B       MENUMGR_CONT_2                  | -> shared get
| _SetItemMark ($A945): D2=2
SETITEMMARK:
    MOVEQ.L     #0x2,D2                         | attr index 2 = mark
    BRA.B       MENUMGR_CONT                    | -> shared set
| ----------------------------------------------------------
|
| _CheckItem ($A945): set/clear the check mark on a menu item.
| Pascal: procedure CheckItem(theMenu: MenuHandle; item: INTEGER; checked: BOOLEAN);
| Implements check-mark by overlaying SetItemMark with mark = $12 (check
| character) or 0 (no mark).
CHECKITEM:
    TST.B       0x4(A7)                         | checked argument true?
    BEQ.B       CHECKITEM_NO                    | no -> set mark = 0
    MOVE.W      #0x12,0x4(A7)                   | mark byte = check character (0x12)
    BRA.B       SETITEMMARK                     | -> SetItemMark dispatch
| Called during boot (18,470 times in 30s trace).
CHECKITEM_NO:
    CLR.W       0x4(A7)                         | mark byte = 0 (no mark)
    BRA.B       SETITEMMARK                     | -> SetItemMark dispatch
| ----------------------------------------------------------
|
| Uppercase a single character (used by MenuKey for case-insensitive match).
| In:  D0.B = char to convert
| Out: D0.B = uppercased char (per IUMagString equivalence)
CHECKITEM_CONT:
    MOVE.B      D0,-(A7)                        | push char on stack
    MOVEA.L     A7,A0                           | A0 = ptr to char
    MOVEQ.L     #0x1,D0                         | length = 1
    _UprStringMarks                             | uppercase in place
    MOVE.B      (A7)+,D0                        | D0 = uppercased char
    RTS                                         | return from CHECKITEM_CONT
| ----------------------------------------------------------
|
| _MenuKey ($A93E): map a Cmd-key character to a menuID:item LongInt.
| Pascal: function MenuKey(ch: CHAR): LongInt;
| Returns: high word = menuID, low word = item index, 0L if no match.
| Walks all menus that have item enableFlags bit 0 set, comparing each
| item's key byte (case-insensitive) against the typed char.
MENUKEY:
    MOVEM.L     D3-D5/A3,-(A7)                  | save regs
    MOVE.B      0x15(A7),D0                     | D0 = char arg (low byte)
    BSR.B       CHECKITEM_CONT                  | uppercase the char
    MOVE.B      D0,D4                           | D4 = uppercased target
    BSR.W       DISABLEITEM_CONT                | A0 = deref MenuList header
    MOVE.W      (A0),D5                         | D5 = lastMenu (byte count)
| Scan each menu in the bar.
MENUKEY_SCAN_LOOP:
    BSR.W       DISABLEITEM_NEXT                | A0 = MenuInfo for menu at offset D5
    MOVEA.L     A0,A3                           | A3 = MenuInfo
    BTST        #0x0,0xD(A3)                    | enable-bit-0 = "menu enabled"?
    BEQ.B       MENUKEY_SKIP_2                  | disabled -> skip menu
    MOVEQ.L     #0x1,D3                         | item index = 1
| scan items in this menu
MENUKEY_NEXT_2:
    MOVE.L      0xA(A3),D0                      | D0 = enableFlags (32 items)
    BTST        D3,D0                           | item D3 enabled?
    BEQ.B       MENUKEY_SKIP                    | no -> next item
    MOVEA.L     A3,A0                           | A0 = MenuInfo
    MOVE.W      D3,D0                           | D0 = item index
    BSR.W       GETITEM_FIND                    | locate item -> A1 = attr ptr
    BEQ.B       MENUKEY_SKIP_2                  | not found -> end of items
    MOVE.B      0x1(A1),D0                      | D0 = item key byte (attr+1)
    BSR.B       CHECKITEM_CONT                  | uppercase
    CMP.B       D0,D4                           | matches typed char?
    BEQ.B       MENUKEY_MATCH_FOUND             | yes -> dispatch
MENUKEY_SKIP:
    ADDQ.W      #0x1,D3                         | next item
    BRA.B       MENUKEY_NEXT_2                  | continue
MENUKEY_SKIP_2:
    SUBQ.W      #0x6,D5                         | back up to previous menu
    BNE.B       MENUKEY_SCAN_LOOP               | more menus -> continue
    CLR.L       0x16(A7)                        | result = 0L (no match)
| Common exit: restore regs, strip char param, indirect return.
MENUKEY_DONE:
    MOVEM.L     (A7)+,D3-D5/A3                  | restore regs
    BRA.W       MENUMGR_STRIP_PARAM_RTS         | -> strip param + return
| Match found: hilite the menu, build result LongInt, dispatch system menu if needed.
MENUKEY_MATCH_FOUND:
    BSR.W       DISABLEITEM_NEXT                | A0 = MenuInfo for current menu (D5)
    MOVE.W      (A0),D0                         | D0 = menuID
    SWAP.W      D0                              | D0.h = menuID
    MOVE.W      D3,D0                           | D0.l = item
    MOVE.L      D0,0x16(A7)                     | result = (menuID, item)
    SWAP.W      D0                              | D0.l = menuID (for HiliteMenu)
    MOVE.W      D0,-(A7)                        | push menuID
    _HiliteMenu                                 | hilite chosen menu's title
    TST.W       (MBarEnable).W                  | system mode (negative)?
    BMI.B       MENUKEY_OK                      | yes -> always SystemMenu
    MOVE.L      0x16(A7),D0                     | reload result
    BPL.B       MENUKEY_DONE                    | menuID > 0 -> normal return
MENUKEY_OK:
    MOVE.L      D0,-(A7)                        | push result for SystemMenu
    _SystemMenu                                 | dispatch DA / Apple-menu cmd
    CLR.L       0x16(A7)                        | result = 0 (consumed)
    BRA.B       MENUKEY_DONE                    | -> exit
| ----------------------------------------------------------
|
| _GetItem ($A946): copy a menu item's text into a Pascal-string buffer.
| Pascal: procedure GetItem(theMenu: MenuHandle; item: INTEGER; var s: Str255);
GETITEM:
    MOVEA.L     0xA(A7),A0                      | A0 = MenuHandle
    MOVEA.L     (A0),A0                         | deref to MenuInfo
    MOVE.W      0x8(A7),D0                      | D0 = item number
    BSR.W       GETITEM_FIND                    | locate item -> A0 = title ptr
    MOVEA.L     0x4(A7),A1                      | A1 = VAR result string
    BEQ.B       GETMENUITEMTEXT_EXIT            | not found -> empty string
    MOVEQ.L     #0x0,D0                         | clear D0 high
    MOVE.B      (A0),D0                         | D0 = nameLen
    ADDQ.W      #0x1,D0                         | + 1 for length byte itself
    _BlockMove                                  | copy nameLen+1 bytes
GETMENUITEMTEXT_CONT:
    BRA.W       MENUMGR_NO                      | -> common exit (strips 10 bytes)
| Empty-result path: store length=0 and exit.
GETMENUITEMTEXT_EXIT:
    CLR.B       (A1)                            | result string length = 0
    BRA.B       GETMENUITEMTEXT_CONT            | -> common exit
| ----------------------------------------------------------
|
| STACK_2
|
| STACK_2: invalidate menu dimensions (forces recalc on next draw)
| Stack: [ret, MenuHandle]
STACK_2:
    MOVEA.L     0x4(A7),A0                      | A0 = MenuHandle
    MOVEA.L     (A0),A0                         | deref to MenuInfo
    MOVE.L      #0xFFFFFFFF,0x2(A0)             | width,height := -1 (force recalc)
    BRA.B       CALCMENUSIZE_EXIT               | strip param + return
| ----------------------------------------------------------
|
| _CalcMenuSize ($A948): force a menu's width/height to be
| recomputed by calling MDEF msg=2 (calcSize). Standard MDEF
| then walks the items and stores total dimensions back into
| the MenuInfo header.
|
| Pascal: procedure CalcMenuSize(theMenu: MenuHandle);
|
CALCMENUSIZE:
    MOVE.W      #0x2,-(A7)                      | MDEF message = 2 (calcSize)
    MOVEA.L     0x6(A7),A0                      | A0 = MenuHandle
    MOVE.L      A0,-(A7)                        | push for MDEF call
    CLR.L       -(A7)                           | rect = nil
    CLR.L       -(A7)                           | hitPoint = (0,0)
    CLR.L       -(A7)                           | whichItem var = nil
    MOVEA.L     (A0),A0                         | deref to MenuInfo
    BSR.W       MENUSELECT_CONT_8               | get menuProc handle from MenuInfo
    JSR         (A0)                            | call MDEF (msg=2 calcSize)
    MOVEA.L     0x4(A7),A0                      | A0 = MenuHandle (still on stack)
    MOVEA.L     (A0),A0                         | deref to MenuInfo
    BSR.W       MENUSELECT_CONT_10              | propagate width/height to system
CALCMENUSIZE_EXIT:
    MOVE.L      (A7)+,(A7)                      | strip MenuHandle param
    RTS                                         | return from CalcMenuSize
| Tail of an enable-flag check helper (DisableItem-style branch
| in test). Reads enableFlags long at offset 0xA of MenuInfo.
    MOVEA.L     (A3),A0                         | A0 = MenuInfo
    MOVE.L      0xA(A0),D0                      | D0 = enableFlags long
    BTST        D4,D0                           | item D4 enabled ?
    BEQ.B       CALCMENUSIZE_EXIT_2             | no, return Z set (disabled)
    BTST        #0x0,D0                         | menu itself enabled (bit 0) ?
CALCMENUSIZE_EXIT_2:
    RTS                                         | return with CCR reflecting enable
| ----------------------------------------------------------
|
| _NewMenu ($A931): allocate a new MenuInfo with title and default MDEF.
| Pascal: function NewMenu(menuID: INTEGER; menuTitle: Str255): MenuHandle;
| Allocates 14-byte header + title length + terminator byte. Loads 'MDEF' #0
| as the default menu definition function.
NEWMENU:
    MOVEQ.L     #0x0,D1                         | clear D1 high
    MOVEQ.L     #0x10,D0                        | base size = 16 bytes
    MOVEA.L     0x4(A7),A0                      | A0 = menuTitle Pascal str
    MOVE.B      (A0),D1                         | D1 = title length byte
    ADD.W       D1,D0                           | total size = 16 + titleLen
    _NewHandle                                  | allocate -> A0
    MOVE.L      A0,0xA(A7)                      | store result handle on stack
    MOVEA.L     (A0),A1                         | A1 = deref new MenuInfo
    MOVE.W      D1,-(A7)                        | save titleLen on stack
    MOVE.W      0xA(A7),(A1)+                   | menuID at offset 0
    CLR.L       (A1)+                           | width(W)=0, height(W)=0 at offsets 2,4
    SUBQ.W      #0x4,A7                         | reserve _GetResource result slot
    MOVE.L      #0x4D444546,-(A7)               | push 'MDEF' resType
    CLR.W       -(A7)                           | push resID = 0 (default MDEF)
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | search ROM resource map
    _GetResource                                | -> handle in result slot
    MOVEA.L     (A7)+,A0                        | A0 = MDEF handle
    MOVEA.L     0xC(A7),A1                      | A1 = MenuHandle (saved earlier)
    MOVEA.L     (A1),A1                         | deref to MenuInfo
    ADDQ.W      #0x6,A1                         | A1 = MenuInfo + 6 (menuProc field)
    MOVE.L      A0,(A1)+                        | menuProc = MDEF handle
    MOVE.L      (MinusOne).W,(A1)+              | enableFlags = 0xFFFFFFFF (all enabled)
    MOVE.W      (A7)+,D1                        | D1 = titleLen
    MOVEA.L     0x4(A7),A0                      | A0 = menuTitle str
NEWMENU_LOOP:
    MOVE.B      (A0)+,(A1)+                     | copy nameLen + name bytes to MenuInfo
    DBF.W       D1,NEWMENU_LOOP                 | loop titleLen+1 bytes
    CLR.B       (A1)+                           | terminator byte (no items)
    BRA.W       INSERTMENU_EXIT                 | -> strip params + return
| ----------------------------------------------------------
|
| _AppendMenu ($A933): append items parsed from a Pascal string to a menu.
| Pascal: procedure AppendMenu(theMenu: MenuHandle; data: Str255);
| Same metachar parser as InsMenuItem; insertion position = end (0x3E7=999).
APPENDMENU:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    MOVE.W      #0x3E7,-(A7)                    | push beforeItem = 999 (end)
    MOVE.L      A0,-(A7)                        | re-push return addr
| _InsMenuItem ($A826): insert one or more items into a menu.
| Pascal: procedure InsMenuItem(theMenu: MenuHandle; itemString: Str255; afterItem: INTEGER);
| Parses metachars: ^=icon, /=key, !=mark, <=style, ;/CR=item separator, (=disable.
| Stack frame: A6+0x8 = afterItem (W), A6+0xA = itemString ptr (L), A6+0xE = MenuHandle (L)
INSMENUITEM:
    LINK        A6,#-0x118                      | reserve 280 bytes of locals
    MOVEM.L     D3-D7/A2-A4,-(A7)               | save regs
    MOVEA.L     0xA(A6),A4                      | A4 = itemString ptr (parser cursor)
    MOVEA.L     0xE(A6),A3                      | A3 = MenuHandle
    MOVE.W      0x8(A6),D6                      | D6 = afterItem (insertion point)
    ADDQ.W      #0x1,D6                         | D6 = first new item index
    BSR.B       INSMENUITEM_CONT                | run the parser/insertion loop
    MOVEM.L     (A7)+,D3-D7/A2-A4               | restore regs
    UNLK        A6                              | tear down frame
    BRA.W       MENUMGR_NO                      | -> common exit (strip 10 bytes)
| ----------------------------------------------------------
|
| INSMENUITEM_CONT
|
| INSMENUITEM_CONT: parse item data string and insert items into menu
| A4 = item data string, A3 = MenuHandle, D6 = insertion point
INSMENUITEM_CONT:
    CLR.W       D3                              | clear D3 high
    MOVE.B      (A4)+,D3                        | D3 = string length
    BSR.B       INSMENUITEM_NEXT                | reset parser state
    SUBQ.W      #0x1,D3                         | -1 for DBF
INSMENUITEM_LOOP:
    MOVE.B      (A4)+,D0                        | D0 = next char
    BSR.B       INSMENUITEM_CONT_3              | dispatch to parser state machine
    DBF.W       D3,INSMENUITEM_LOOP             | loop over all chars
    BSR.W       INSMENUITEM_NO_5                | flush final item
    MOVE.L      A3,-(A7)                        | push MenuHandle
    BSR.W       STACK_2                         | recompute and redraw if visible
    RTS                                         | return from parser driver
| ----------------------------------------------------------
|
| INSMENUITEM_NEXT
|
| Called during boot.
| INSMENUITEM_NEXT: initialize item parse state buffer to zero
| Local frame: A6-0x118 = 8-byte attribute/state area
| -0x118(A6): icon byte, -0x117: key byte, -0x116: mark byte, -0x115: style byte
| -0x114: parse state (metachar pending), -0x113: disable flag
| -0x112: title length (word), -0x110: title buffer (256 bytes)
INSMENUITEM_NEXT:
    LEA.L       -0x118(A6),A0                   | A0 = start of attribute buffer
    CLR.L       (A0)+                           | clear icon, key, mark, style bytes
    CLR.L       (A0)                            | clear parse state, disable flag, title length
    RTS                                         | return from INSMENUITEM_NEXT
| ----------------------------------------------------------
|
| METACHAR_TBL
|
| METACHAR_TBL: metachar table for menu item data parsing
| Index 6='^' (icon), 5='/' (key), 4='!' (mark), 3='<' (style)
| Index 2=CR (item separator), 1=';' (item separator), 0='(' (disable)
METACHAR_TBL:
    .short      0x5E2F
    .long       0x213C0D3B
    .byte 0x28
| INSMENUITEM_CONT_2: style character table for '<' metachar
| Index 0='B'(bold), 1='I'(italic), 2='U'(underline), 3='O'(outline), 4='S'(shadow)
INSMENUITEM_CONT_2:
    .byte 0x42
    .short      0x4955
    .short      0x4F53
| INSMENUITEM_CONT_3: process one character from menu item data string
| D0 = current char, parse state in local frame
| State 0: check if char is metachar or title text
| State 1 (after '^'): char is icon number (ASCII digit -> binary)
| State 2 (after '!'): char is mark character
| State 3 (after '/'): char is key equivalent
| State 4 (after '<'): char is style letter (B/I/U/O/S)
INSMENUITEM_CONT_3:
    CLR.W       D1                              | clear D1 high
    MOVE.B      -0x114(A6),D1                   | D1 = current parse state
    BEQ.B       INSMENUITEM_NO_3                | state 0 -> check metachar
    CMPI.B      #0x1,D1                         | state 1 (after '^')?
    BNE.B       INSMENUITEM_NO                  | no -> handle other states
    SUBI.W      #0x30,D0                        | yes: ASCII digit -> binary icon #
INSMENUITEM_NO:
    CMPI.B      #0x4,D1                         | state 4 (after '<')?
    BNE.B       INSMENUITEM_NO_2                | no -> simple attr store
    MOVEQ.L     #0x4,D2                         | yes: scan style table for letter
INSMENUITEM_LOOP_2:
    CMP.B       INSMENUITEM_CONT_2(PC,D2.W),D0  | match style char (B/I/U/O/S)?
    BEQ.B       INSMENUITEM_OK                  | yes -> set bit
    DBF.W       D2,INSMENUITEM_LOOP_2           | next style char
    RTS                                         | unknown style char -> ignore
| ----------------------------------------------------------
|
| INSMENUITEM_OK
|
| INSMENUITEM_OK: matched a style letter - OR its bit into the style byte
INSMENUITEM_OK:
    LEA.L       -0x119(A6),A0                   | A0 = state base - 1 (state 1..4 -> -118..-115)
    MOVE.B      0x0(A0,D1.W),D0                 | load existing style byte
    BSET        D2,D0                           | OR in this style bit
| INSMENUITEM_NO_2: store attribute value and clear parse state.
INSMENUITEM_NO_2:
    LEA.L       -0x119(A6),A0                   | A0 = state base - 1
    MOVE.B      D0,0x0(A0,D1.W)                 | store attr byte at slot D1
    CLR.B       -0x114(A6)                      | parse state = 0 (back to title)
    RTS                                         | return from INSMENUITEM_NO_2
| ----------------------------------------------------------
|
| INSMENUITEM_NO_3
|
| INSMENUITEM_NO_3: state 0 - check if char is a metachar or literal title text
INSMENUITEM_NO_3:
    LEA.L       METACHAR_TBL(PC),A0             | A0 = metachar table
    MOVE.W      #0x6,D1                         | scan from index 6 down to 0
INSMENUITEM_LOOP_3:
    CMP.B       0x0(A0,D1.W),D0                 | char matches metachar at D1?
    BEQ.B       INSMENUITEM_OK_2                | yes -> handle metachar
    DBF.W       D1,INSMENUITEM_LOOP_3           | no -> next metachar
    MOVE.W      -0x112(A6),D1                   | D1 = current title length
    LEA.L       -0x110(A6),A0                   | A0 = title buffer base
    MOVE.B      D0,0x0(A0,D1.W)                 | append char to title buffer
    ADDQ.W      #0x1,-0x112(A6)                 | titleLen += 1
    RTS                                         | return from INSMENUITEM_NO_3
| ----------------------------------------------------------
|
| INSMENUITEM_OK_2
|
| INSMENUITEM_OK_2: matched metachar at index D1 in METACHAR_TBL
| Indices 3-6 (< ! / ^): set parse state to D1+1 for next char
| Index 2 (CR) or 1 (;): item separator -> flush current item
| Index 0 (open paren): mark item as disabled
INSMENUITEM_OK_2:
    CMPI.W      #0x3,D1                         | metachar index <= 3?
    BGT.B       INSMENUITEM_NO_4                | no (4..6) -> separator/disable
    ADDQ.W      #0x1,D1                         | parse state = D1 + 1 (1..4)
    MOVE.B      D1,-0x114(A6)                   | save state for next char
    RTS                                         | return from INSMENUITEM_OK_2
| ----------------------------------------------------------
|
| INSMENUITEM_NO_4
|
| INSMENUITEM_NO_4: handle item separator (index 4-5) or disable marker (index 6)
INSMENUITEM_NO_4:
    SUBQ.W      #0x6,D1                         | index 6 = '(' (disable marker)
    BNE.B       INSMENUITEM_NO_5                | not '(' -> separator (CR or ;): flush
    ST.B        -0x113(A6)                      | yes: disable flag = true
    RTS                                         | return from INSMENUITEM_NO_4
| ----------------------------------------------------------
|
| INSMENUITEM_NO_5
|
| Called during boot.
| INSMENUITEM_NO_5: flush current parsed item into the menu (if any title text)
INSMENUITEM_NO_5:
    MOVE.W      -0x112(A6),D0                   | D0 = current title length
    BEQ.B       INSMENUITEM_NO_6                | empty -> nothing to flush
    BSR.B       INSMENUITEM_CONT_4              | splice item into MenuInfo
    BSR.W       INSMENUITEM_NEXT                | reset state for next item
INSMENUITEM_NO_6:
    RTS                                         | return from INSMENUITEM_NO_5
| ----------------------------------------------------------
|
| RETURNS_19
|
| Called during boot.
| RETURNS_19: clamp insertion point D6 to valid range
| D6 = desired insertion position, A3 = MenuHandle
| Returns: D5 = clamped insertion position (min of D6 and itemCount+1)
RETURNS_19:
    MOVE.W      D6,D5                           | D5 = desired insertion position
    SUBQ.W      #0x2,A7                         | reserve _CountMItems result slot
    MOVE.L      A3,-(A7)                        | push MenuHandle
    _CountMItems                                | -> count of items
    MOVE.W      (A7)+,D0                        | D0 = item count
    ADDQ.W      #0x1,D0                         | max insertion = count + 1
    CMP.W       D0,D5                           | desired exceeds max?
    BLE.B       INSMENUITEM_OK_3                | no -> use D5 as-is
    MOVE.W      D0,D5                           | yes -> clamp to count+1
INSMENUITEM_OK_3:
    RTS                                         | return from RETURNS_19
| ----------------------------------------------------------
|
| INSMENUITEM_CONT_4
|
| Called during boot.
| INSMENUITEM_CONT_4: insert parsed item into menu data at position D6
| Uses _Munger to splice title+attributes into the MenuInfo handle
INSMENUITEM_CONT_4:
    BSR.B       RETURNS_19                      | clamp insertion point -> D5
    MOVE.W      D5,D0                           | D0 = clamped position
    MOVEA.L     (A3),A0                         | A0 = deref MenuInfo
    BSR.W       GETITEM_FIND                    | locate item at D5 -> A0 = title ptr
    BEQ.B       INSMENUITEM_CONT_5              | not found -> append at end
    MOVE.L      A0,D1                           | save item ptr (offset target)
    MOVEA.L     (A3),A0                         | A0 = deref MenuInfo
    BSR.B       INSMENUITEM_CONT_6              | bump enableFlags bits up by 1
| Build splice buffer: title bytes + 4 attr bytes + length-prefix.
INSMENUITEM_CONT_5:
    LEA.L       -0x110(A6),A0                   | A0 = title buffer
    MOVEA.L     A0,A2                           | A2 = title buffer (saved)
    MOVE.W      -0x112(A6),D2                   | D2 = titleLen
    ADDA.W      D2,A0                           | A0 = end of title text
    LEA.L       -0x118(A6),A1                   | A1 = state area (icon/key/mark/style)
    MOVEQ.L     #0x3,D0                         | 4 attribute bytes
INSMENUITEM_LOOP_4:
    MOVE.B      (A1)+,(A0)+                     | append icon/key/mark/style
    DBF.W       D0,INSMENUITEM_LOOP_4           | copy 4 bytes
    SUBQ.W      #0x1,A2                         | A2 = title - 1 (length byte slot)
    ADDQ.W      #0x5,D2                         | D2 = total entry size (len + title + 4 attrs)
    EXT.L       D2                              | sign-extend for _Munger
    MOVEA.L     D1,A1                           | A1 = old item ptr
    SUBA.L      (A3),A1                         | A1 = offset within MenuInfo
    SUBQ.W      #0x4,A7                         | _Munger result slot
    MOVE.L      A3,-(A7)                        | _Munger arg: handle
    MOVE.L      A1,-(A7)                        | _Munger arg: offset
    CLR.L       -(A7)                           | _Munger arg: ptr1 (no search)
    CLR.L       -(A7)                           | _Munger arg: len1
    MOVE.L      A2,-(A7)                        | _Munger arg: ptr2 (insert buffer)
    MOVE.L      D2,-(A7)                        | _Munger arg: len2
    _Munger                                     | splice item into MenuInfo
    ADDQ.W      #0x4,A7                         | discard _Munger result
    TST.B       -0x113(A6)                      | item disabled?
    BEQ.B       INSMENUITEM_NO_7                | no -> done
    MOVE.L      A3,-(A7)                        | push MenuHandle
    MOVE.W      D5,-(A7)                        | push item index
    BSR.W       DISABLEITEM                     | clear enableFlags bit for this item
INSMENUITEM_NO_7:
    RTS                                         | return from INSMENUITEM_CONT_4
| ----------------------------------------------------------
|
| INSMENUITEM_CONT_6
|
| Called during boot.
| INSMENUITEM_CONT_6: shift enableFlags right at position D5 to insert a 0 bit for new item
| A0 = MenuInfo ptr, D5 = item position
| Rotates bits so a cleared bit is inserted at position D5
INSMENUITEM_CONT_6:
    MOVE.L      0xA(A0),D2                      | D2 = current enableFlags
    ROR.L       D5,D2                           | rotate so bit D5-1 is at bit 31
    MOVE.W      D5,D0                           | D0 = D5
    SUBI.W      #0x20,D0                        | D0 = D5 - 32
    NEG.W       D0                              | D0 = 32 - D5
    ROXR.L      D0,D2                           | rotate via X, inserting cleared bit
    MOVE.L      D2,0xA(A0)                      | store updated enableFlags
    RTS                                         | return from INSMENUITEM_CONT_6
| ----------------------------------------------------------
|
| _GetMHandle ($A949): get MenuHandle by menuID.
| Pascal: function GetMHandle(menuID: INTEGER): MenuHandle;
GETMHANDLE:
    CLR.L       0x6(A7)                         | result = nil (default)
    MOVE.W      0x4(A7),D1                      | D1 = menuID arg
    BSR.W       INSERTMENU_CONT_2               | search MenuList for menuID
    BEQ.B       GETMHANDLE_RTS                  | not found -> return nil
    MOVE.W      D5,-(A7)                        | save D5 (caller's reg)
    MOVE.W      D0,D5                           | D5 = byte offset of menu
    BSR.W       DISABLEITEM_NEXT                | A1 = MenuHandle for offset D5
    MOVE.W      (A7)+,D5                        | restore D5
    MOVE.L      A1,0x6(A7)                      | result = MenuHandle
GETMHANDLE_RTS:
    BRA.W       MENUMGR_STRIP_PARAM_RTS         | -> strip param + return
| ----------------------------------------------------------
|
| _DelMenuItem ($A952): delete a menu item.
| Pascal: procedure DelMenuItem(theMenu: MenuHandle; item: INTEGER);
| Removes item via _Munger; also rotates enableFlags to remove the deleted bit.
DELMENUITEM:
    MOVE.L      (A7),-(A7)                      | duplicate return addr (frame trick)
    MOVEM.L     D3-D4/A2-A4,-(A7)               | save regs
    MOVEA.L     0x1E(A7),A3                     | A3 = MenuHandle
    MOVEA.L     (A3),A0                         | deref to MenuInfo
    MOVE.W      0x1C(A7),D0                     | D0 = item index
    MOVE.L      0xA(A0),D1                      | D1 = enableFlags
    MOVE.W      D0,D2                           | D2 = item index
    SUBI.W      #0x20,D2                        | D2 = item - 32
    NEG.W       D2                              | D2 = 32 - item
    ROXL.L      D2,D1                           | rotate so bit at item-1 is at bit 31
    ROL.L       D0,D1                           | rotate left by item: removes that bit
    MOVE.L      D1,0xA(A0)                      | store updated enableFlags
    BSR.W       GETITEM_FIND                    | locate item -> A0 = title ptr
    BEQ.B       SETMENUITEMTEXT_FOUND           | not found -> exit
    MOVEQ.L     #0x5,D4                         | base = 5 bytes (lenByte + 4 attrs)
    MOVEQ.L     #0x0,D2                         | replacement length = 0 (delete)
    MOVEA.L     D2,A2                           | replacement ptr = nil
    BRA.B       SETMENUITEMTEXT_CONT            | -> shared _Munger splice
| ----------------------------------------------------------
|
| _SetItem ($A947): replace a menu item's text.
| Pascal: procedure SetItem(theMenu: MenuHandle; item: INTEGER; itemString: Str255);
SETITEM:
    MOVEM.L     D3-D4/A2-A4,-(A7)               | save regs
    MOVEA.L     0x1E(A7),A3                     | A3 = MenuHandle
    MOVE.W      0x1C(A7),D3                     | D3 = item index
    MOVEA.L     0x18(A7),A2                     | A2 = itemString ptr
    MOVE.W      D3,D0                           | D0 = item index
    MOVEA.L     (A3),A0                         | A0 = deref MenuInfo
    BSR.W       GETITEM_FIND                    | locate item -> A0 = title ptr
    BEQ.B       SETMENUITEMTEXT_FOUND           | not found -> exit
    MOVEQ.L     #0x1,D4                         | base = 1 byte (length byte)
    MOVEQ.L     #0x1,D2                         | replacement = 1 + length
    ADD.B       (A2),D2                         | + new title length
| Shared _Munger splice (entry from DelMenuItem and SetItem).
| In: A0 = old item ptr, A2/D2 = replacement bytes/length, D4 = old length to remove
SETMENUITEMTEXT_CONT:
    MOVEA.L     A0,A4                           | A4 = old item ptr
    SUBA.L      (A3),A4                         | A4 = offset within MenuInfo
    ADD.B       (A0),D4                         | D4 = old item total length (lenByte + str + 4)
    SUBQ.W      #0x4,A7                         | _Munger result slot
    MOVE.L      A3,-(A7)                        | _Munger arg: handle
    MOVE.L      A4,-(A7)                        | _Munger arg: offset
    CLR.L       -(A7)                           | _Munger arg: ptr1 (no search)
    MOVE.L      D4,-(A7)                        | _Munger arg: len1 (bytes to remove)
    MOVE.L      A2,-(A7)                        | _Munger arg: ptr2 (replacement)
    MOVE.L      D2,-(A7)                        | _Munger arg: len2 (replacement length)
    _Munger                                     | splice
    ADDQ.W      #0x4,A7                         | discard result
    MOVE.L      A3,-(A7)                        | push MenuHandle
    BSR.W       STACK_2                         | recompute and redraw
SETMENUITEMTEXT_FOUND:
    MOVEM.L     (A7)+,D3-D4/A2-A4               | restore regs
    BRA.W       MENUMGR_NO                      | -> common exit
| ----------------------------------------------------------
|
| _SetMenuFlash ($A94A): set MenuFlash count.
| Pascal: procedure SetMenuFlash(count: INTEGER);
SETMENUFLASH:
    MOVE.W      0x4(A7),(MenuFlash).W           | MenuFlash = count
    BRA.W       MENUMGR_STRIP_PARAM_RTS         | -> strip param + return
| ----------------------------------------------------------
|
| _AddResMenu ($A94D): append all resources of a type to a menu.
| Pascal: procedure AddResMenu(theMenu: MenuHandle; theType: ResType);
ADDRESMENU:
    MOVEA.L     (A7)+,A0                        | A0 = return addr
    MOVE.W      #0x3E7,-(A7)                    | push beforeItem = 999 (end)
    MOVE.L      A0,-(A7)                        | re-push return addr
| _InsertResMenu ($A951): insert resources of a type into a menu at given position.
| Pascal: procedure InsertResMenu(theMenu: MenuHandle; theType: ResType; afterItem: INTEGER);
| Substitutes 'FOND' for 'FONT' (modern font format alias).
INSRTRESMENU:
    CMPI.L      #0x464F4E54,0x6(A7)             | resType = 'FONT'?
    BNE.B       INSERTRESMENU_NO                | no -> use as-is
    MOVE.B      #0x44,0x9(A7)                   | yes: change 'T' to 'D' -> 'FOND'
INSERTRESMENU_NO:
    LINK        A6,#-0x118                      | reserve 280 bytes of locals
    MOVEM.L     D3-D7/A2-A4,-(A7)               | save regs
    MOVE.W      (ResLoad).W,-(A7)               | save current ResLoad flag
    CLR.W       (ResLoad).W                     | disable resource loading (just headers)
    BSR.W       INSMENUITEM_NEXT                | reset parser state
    MOVEA.L     0xE(A6),A3                      | A3 = MenuHandle
    MOVE.W      0x8(A6),D6                      | D6 = afterItem
    ADDQ.W      #0x1,D6                         | D6 = first new item index
    BSR.W       RETURNS_19                      | clamp insertion -> D5
    MOVE.W      D5,D7                           | D7 = saved insertion start
INSERTRESMENU_RETRY:
    SUBQ.W      #0x2,A7                         | _CountResources result slot
    MOVE.L      0xA(A6),-(A7)                   | push resType arg
    _CountResources                             | -> count
    MOVE.W      (A7)+,D4                        | D4 = total resources of this type
    BEQ.B       INSERTRESMENU_EMPTY             | none -> try 'FOND' fallback
    MOVEQ.L     #0x1,D3                         | D3 = resource index (1-based)
| Loop through each resource of the type, inserting in alphabetical order.
INSERTRESMENU_NEXT:
    SUBQ.W      #0x4,A7                         | _GetIndResource result slot
    MOVE.L      0xA(A6),-(A7)                   | push resType
    MOVE.W      D3,-(A7)                        | push index
    _GetIndResource                             | -> handle (drop result)
    LEA.L       -0x111(A6),A4                   | A4 = name buffer (Str255)
    CLR.L       -(A7)                           | type slot (ignored)
    CLR.L       -(A7)                           | id slot (ignored)
    MOVE.L      A4,-(A7)                        | push &nameBuf
    _GetResInfo                                 | fill name
    TST.B       (A4)                            | name length = 0?
    BEQ.B       INSERTRESMENU_SKIP              | yes -> skip (no display name)
    CMPI.B      #0x2E,0x1(A4)                   | first char = '.'?
    BEQ.B       INSERTRESMENU_SKIP              | yes -> skip (driver name)
    CMPI.B      #0x25,0x1(A4)                   | first char = '%'?
    BEQ.B       INSERTRESMENU_SKIP              | yes -> skip (private)
    MOVE.W      D5,D6                           | D6 = current insertion offset
    CMP.W       D7,D6                           | first new resource?
    BEQ.B       INSERTRESMENU_OK                | yes -> just append
| Walk existing items to find alphabetical insertion point.
    MOVEA.L     (A3),A0                         | A0 = deref MenuInfo
    MOVE.W      D6,D0                           | D0 = offset
    BSR.W       GETITEM_FIND                    | locate item -> A0 = title ptr
    MOVEA.L     A0,A2                           | A2 = current item title
INSERTRESMENU_WALK_LOOP:
    TST.B       (A2)                            | end of items?
    BEQ.B       INSERTRESMENU_OK                | yes -> append at end
    MOVEA.L     A2,A0                           | A0 = current title
    MOVEA.L     A4,A1                           | A1 = new resource name
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (A0)+,D0                        | D0.l = current title length
    SWAP.W      D0                              | D0.h = current length
    MOVE.B      (A1)+,D0                        | D0.l = new name length
    _CompareString                              | compare strings (case/diac sensitive)
    BGT.B       INSERTRESMENU_OK                | new < current -> insert here
    BEQ.B       INSERTRESMENU_SKIP              | duplicate -> skip
    CMP.W       D7,D6                           | reached saved start?
    BEQ.B       INSERTRESMENU_OK                | yes -> insert here (was last)
| Advance past current item.
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      (A2),D0                         | D0 = current item nameLen
    ADDQ.W      #0x5,D0                         | + 5 (lenByte + 4 attrs)
    ADDA.L      D0,A2                           | advance past current item
    ADDQ.W      #0x1,D6                         | bump offset
    BRA.B       INSERTRESMENU_WALK_LOOP         | continue walk
| Insertion point found: parse name and splice.
INSERTRESMENU_OK:
    MOVE.W      D5,-(A7)                        | save D5
    BSR.W       INSMENUITEM_NO_5                | flush current (parsed) item
    MOVE.W      (A7)+,D5                        | restore D5
    ADDQ.W      #0x1,D7                         | items inserted += 1
INSERTRESMENU_SKIP:
    ADDQ.W      #0x1,D3                         | next resource index
    CMP.W       D4,D3                           | done?
    BLE.B       INSERTRESMENU_NEXT              | no -> loop
| 'FOND' returned no resources -- try 'FONT' (legacy) as fallback.
INSERTRESMENU_EMPTY:
    CMPI.L      #0x464F4E44,0xA(A6)             | resType = 'FOND'?
    BNE.B       INSERTRESMENU_DONE              | no -> done
    MOVE.B      #0x54,0xD(A6)                   | yes: change 'D' -> 'T' (try 'FONT')
    BRA.W       INSERTRESMENU_RETRY             | retry
| Recompute menu metrics, restore ResLoad, return.
INSERTRESMENU_DONE:
    MOVE.L      A3,-(A7)                        | push MenuHandle
    _CalcMenuSize                               | recompute width/height
    _SetResLoad                                 | restore ResLoad flag (popped from stack)
    MOVEM.L     (A7)+,D3-D7/A2-A4               | restore regs
    UNLK        A6                              | tear down frame
    BRA.W       MENUMGR_NO                      | -> common exit (strip 10 bytes)
| ----------------------------------------------------------
|
| _CountMItems ($A950): count items in a menu.
| Pascal: function CountMItems(theMenu: MenuHandle): INTEGER;
COUNTMITEMS:
    MOVEQ.L     #0x0,D2                         | item counter = 0
COUNTMITEMS_NEXT:
    ADDQ.W      #0x1,D2                         | try next item index
    MOVEA.L     0x4(A7),A0                      | A0 = MenuHandle
    MOVEA.L     (A0),A0                         | deref to MenuInfo
    MOVE.W      D2,D0                           | D0 = item index
    BSR.W       GETITEM_FIND                    | locate item
    BNE.B       COUNTMITEMS_NEXT                | found -> try next
    SUBQ.W      #0x1,D2                         | back up to last valid index
    MOVE.W      D2,0x8(A7)                      | store result on stack
    MOVE.L      (A7)+,(A7)                      | strip MenuHandle param
    RTS                                         | return from COUNTMITEMS
| ----------------------------------------------------------
|
| _PlotIcon ($A94B): draw a 32x32 icon resource into a rect.
| Pascal: procedure PlotIcon(theRect: Rect; theIcon: Handle);
| Builds a temp BitMap (32x32, rowBytes=4) at IconBitmap and CopyBits
| from icon data into thePort.
PLOTICON:
    LEA.L       (IconBitmap).W,A1               | A1 = scratch BitMap area
    MOVE.L      0x4(A7),D0                      | D0 = icon handle
    BEQ.B       BLITMENUICON_EXIT               | nil -> nothing to draw
    MOVEA.L     D0,A0                           | A0 = handle
    MOVE.L      (A0),(A1)+                      | BitMap.baseAddr = deref'd icon
    MOVE.W      #0x4,(A1)+                      | BitMap.rowBytes = 4
    CLR.L       (A1)+                           | bounds.topLeft = (0,0)
    MOVE.L      #0x200020,(A1)                  | bounds.botRight = (32,32)
    MOVE.L      0x8(A7),D1                      | D1 = destination Rect (long)
    LEA.L       (IconBitmap).W,A1               | A1 = src BitMap
    MOVE.L      A1,-(A7)                        | _CopyBits arg: srcBits
    MOVEA.L     (A5),A0                         | A0 = current GrafPort (via A5)
    MOVEA.L     (A0),A0                         | deref to port (Plus convention)
    PEA.L       0x2(A0)                         | _CopyBits arg: dstBits = thePort.portBits
    PEA.L       0x6(A1)                         | _CopyBits arg: srcRect = bounds
    MOVE.L      D1,-(A7)                        | _CopyBits arg: dstRect (caller's)
    CLR.W       -(A7)                           | mode = 0 (srcCopy)
    CLR.L       -(A7)                           | maskRgn = nil
    _CopyBits                                   | blit the icon
BLITMENUICON_EXIT:
    BRA.W       MENUMGR_SKIP                    | -> common exit (strip 8 bytes)
| ==========================================================
| Control Manager begins here. Boundary: $0xD3F8 (MMGREND = NEWCONTROL).
| ==========================================================
|
| _NewControl ($A954): allocate and initialize a Control record.
| Pascal: function NewControl(theWindow: WindowPtr; boundsRect: Rect;
|         title: Str255; visible: BOOLEAN; value: INTEGER;
|         min, max: INTEGER; procID: INTEGER; refCon: LongInt): ControlHandle;
| Stack frame after LINK: A6+8..0xC=refCon, +0xE=procID, +0x10=max, +0x12=min,
| +0x14=value, +0x16=visible (B), +0x18=title (ptr), +0x1C=boundsRect (8 bytes),
| +0x24=theWindow.
MMGREND:
