| Menu Manager
|
| Manages the menu bar and pull-down menus. Provides InitMenus,
| InsertMenu, DrawMenuBar, MenuSelect, MenuKey, HiliteMenu,
| GetMenuBar, SetMenuBar, and item manipulation routines.
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

| ROM section: src/toolbox/menu_mgr.asm
| RETURNS_16: find Nth menu item in MenuInfo data
| A0 = dereferenced MenuHandle, D0 = item number (1-based)
| Returns: A0 = ptr to item title, A1 = ptr to item attributes (icon,key,mark,style)
| D0/A0/A1 = 0 if item not found
| Called by: MENUMGR_CONT, MENUMGR_CONT_2, MENUKEY_NEXT_2, GetMenuItemText, DISPOSECCURSOR_CONT_4 (and 4 more)
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
        RTS                                     | return to caller

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
        RTS                                     | return to caller

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
        RTS                                     | return to caller

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
| _GetMenuItemText ($A946)
|
| _GetMenuItemText ($A946): copy item title to caller's string buffer
| Pascal: procedure GetItem(theMenu: MenuHandle; item: INTEGER; VAR itemString: Str255);
GetMenuItemText:
        MOVE.L  0xA(SP),A0                      | A0 = MenuHandle
        MOVE.L  (A0),A0                         | dereference -> MenuInfo ptr
        MOVE    0x8(SP),D0                      | D0 = item number
        BSR     RETURNS_16                      | find item -> A0 = title ptr
        MOVE.L  0x4(SP),A1                      | A1 = destination string buffer
        BEQ.B   GETMENUITEMTEXT_EXIT            | item not found -> return empty
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A0),D0                         | D0 = title length
        ADDQ.W  #0x1,D0                         | +1 for length byte itself
        _BlockMove                              | copy Pascal string: A0 -> A1, D0 bytes
GETMENUITEMTEXT_CONT:
        BRA     MENUMGR_NO                      | -> strip 10 bytes of params

| ----------------------------------------------------------
|
| GETMENUITEMTEXT_EXIT
|
GETMENUITEMTEXT_EXIT:
        CLR.B   (A1)                            | return empty string (length=0)
        BRA.B   GETMENUITEMTEXT_CONT            | -> strip params

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
        RTS                                     | return to caller

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
        RTS                                     | return to caller

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
| _AppendMenu ($A933)
|
| _AppendMenu ($A933): add item(s) to end of a menu
| Pascal: procedure AppendMenu(theMenu: MenuHandle; data: Str255);
| Calls InsMenuItem with afterItem=999 to insert at end
AppendMenu:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE    #0x3E7,-(SP)                    | push afterItem = 999 (append)
        MOVE.L  A0,-(SP)                        | push return address back
| fall through to InsMenuItem (InsertMenuItem)
| _InsMenuItem ($A826): insert item(s) after specified position
DisposeCCursor:
        LINK    A6,#-0x118                      | 280 bytes local (item parse buffer)
        MOVEM.L D3-D7/A2-A4,-(SP)               | save registers
        MOVE.L  0xA(A6),A4                      | A4 = item data string
        MOVE.L  0xE(A6),A3                      | A3 = MenuHandle
        MOVE    0x8(A6),D6                      | D6 = afterItem
        ADDQ.W  #0x1,D6                         | convert to 1-based insertion point
        BSR.B   DISPOSECCURSOR_CONT             | parse and insert items
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore registers
        UNLK    A6                              | tear down stack frame
        BRA     MENUMGR_NO                      | -> strip 10 bytes of params

| ----------------------------------------------------------
|
| DISPOSECCURSOR_CONT
|
| DISPOSECCURSOR_CONT: parse item data string and insert items into menu
| A4 = item data string, A3 = MenuHandle, D6 = insertion point
DISPOSECCURSOR_CONT:
        CLR     D3                              | clear item string length counter
        MOVE.B  (A4)+,D3                        | D3 = length of item data string
        BSR.B   DISPOSECCURSOR_NEXT             | init parse state (clear attribute buffer)
        SUBQ.W  #0x1,D3                         | adjust for DBF loop
DISPOSECCURSOR_LOOP:
        MOVE.B  (A4)+,D0                        | D0 = next char from data string
        BSR.B   DISPOSECCURSOR_CONT_3           | process char (text or metachar)
        DBF     D3,DISPOSECCURSOR_LOOP          | loop through all chars
        BSR     DISPOSECCURSOR_NO_5             | flush last item into menu
        MOVE.L  A3,-(SP)                        | push MenuHandle
        BSR     STACK_2                         | invalidate menu dimensions
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISPOSECCURSOR_NEXT
|
| Called during boot.
| DISPOSECCURSOR_NEXT: initialize item parse state buffer to zero
| Local frame: A6-0x118 = 8-byte attribute/state area
| -0x118(A6): icon byte, -0x117: key byte, -0x116: mark byte, -0x115: style byte
| -0x114: parse state (metachar pending), -0x113: disable flag
| -0x112: title length (word), -0x110: title buffer (256 bytes)
DISPOSECCURSOR_NEXT:
        LEA.L   -0x118(A6),A0                   | A0 = start of attribute buffer
        CLR.L   (A0)+                           | clear icon, key, mark, style bytes
        CLR.L   (A0)                            | clear parse state, disable flag, title length
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| METACHAR_TBL
|
| METACHAR_TBL: metachar table for menu item data parsing
| Index 6='^' (icon), 5='/' (key), 4='!' (mark), 3='<' (style)
| Index 2=CR (item separator), 1=';' (item separator), 0='(' (disable)
METACHAR_TBL:
  .byte 0x5E,0x2F,0x21,0x3C,0x0D,0x3B           | ^ / ! < CR ;
  .byte 0x28                                    | (

| DISPOSECCURSOR_CONT_2: style character table for '<' metachar
| Index 0='B'(bold), 1='I'(italic), 2='U'(underline), 3='O'(outline), 4='S'(shadow)
DISPOSECCURSOR_CONT_2:
  .byte 0x42,0x49,0x55,0x4F,0x53                | B I U O S

| DISPOSECCURSOR_CONT_3: process one character from menu item data string
| D0 = current char, parse state in local frame
| State 0: check if char is metachar or title text
| State 1 (after '^'): char is icon number (ASCII digit -> binary)
| State 2 (after '!'): char is mark character
| State 3 (after '/'): char is key equivalent
| State 4 (after '<'): char is style letter (B/I/U/O/S)
DISPOSECCURSOR_CONT_3:
        CLR     D1                              | clear high byte
        MOVE.B  -0x114(A6),D1                   | D1 = current parse state
        BEQ.B   DISPOSECCURSOR_NO_3             | state 0: no metachar pending ->
        CMPI.B  #0x1,D1                         | state 1: icon number pending?
        BNE.B   DISPOSECCURSOR_NO               | no ->
        SUBI    #0x30,D0                        | convert ASCII digit to binary ('0'=0x30)
DISPOSECCURSOR_NO:
        CMPI.B  #0x4,D1                         | state 4: style letter pending?
        BNE.B   DISPOSECCURSOR_NO_2             | no -> store directly as attribute
        MOVEQ.L #0x4,D2                         | D2 = 4 (scan style table from end)
DISPOSECCURSOR_LOOP_2:
        CMP.B   DISPOSECCURSOR_CONT_2(PC,D2.W),D0 | match style letter?
        BEQ.B   DISPOSECCURSOR_OK               | yes -> set style bit
        DBF     D2,DISPOSECCURSOR_LOOP_2        | try next style letter
        RTS                                     | unknown style letter, ignore

| ----------------------------------------------------------
|
| DISPOSECCURSOR_OK
|
| DISPOSECCURSOR_OK: matched a style letter - OR its bit into the style byte
DISPOSECCURSOR_OK:
        LEA.L   -0x119(A6),A0                   | A0 = attribute base (1 before icon byte)
        MOVE.B  0x0(A0,D1.W),D0                 | D0 = current style byte value
        BSET    D2,D0                           | set bit for matched style (B=0,I=1,U=2,O=3,S=4)
| DISPOSECCURSOR_NO_2: store attribute value and clear parse state
DISPOSECCURSOR_NO_2:
        LEA.L   -0x119(A6),A0                   | A0 = attribute base
        MOVE.B  D0,0x0(A0,D1.W)                 | store value at attribute[state]
        CLR.B   -0x114(A6)                      | reset parse state to 0 (normal)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISPOSECCURSOR_NO_3
|
| DISPOSECCURSOR_NO_3: state 0 - check if char is a metachar or literal title text
DISPOSECCURSOR_NO_3:
        LEA.L   METACHAR_TBL(PC),A0             | A0 = metachar table
        MOVE    #0x6,D1                         | D1 = 6 (scan from index 6 down to 0)
DISPOSECCURSOR_LOOP_3:
        CMP.B   0x0(A0,D1.W),D0                 | char matches metachar[D1]?
        BEQ.B   DISPOSECCURSOR_OK_2             | yes -> handle metachar
        DBF     D1,DISPOSECCURSOR_LOOP_3        | try next metachar
        MOVE    -0x112(A6),D1                   | D1 = current title length
        LEA.L   -0x110(A6),A0                   | A0 = title buffer
        MOVE.B  D0,0x0(A0,D1.W)                 | append char to title buffer
        ADDQ.W  #0x1,-0x112(A6)                 | increment title length
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISPOSECCURSOR_OK_2
|
| DISPOSECCURSOR_OK_2: matched metachar at index D1 in METACHAR_TBL
| Indices 3-6 (< ! / ^): set parse state to D1+1 for next char
| Index 2 (CR) or 1 (;): item separator -> flush current item
| Index 0 (open paren): mark item as disabled
DISPOSECCURSOR_OK_2:
        CMPI    #0x3,D1                         | metachar index <= 3?
        BGT.B   DISPOSECCURSOR_NO_4             | no, index 4-6 -> separator or disable
        ADDQ.W  #0x1,D1                         | state = index+1 (1=icon,2=mark,3=key,4=style)
        MOVE.B  D1,-0x114(A6)                   | set parse state for next char
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISPOSECCURSOR_NO_4
|
| DISPOSECCURSOR_NO_4: handle item separator (index 4-5) or disable marker (index 6)
DISPOSECCURSOR_NO_4:
        SUBQ.W  #0x6,D1                         | index 6 ('(')? -> D1=0
        BNE.B   DISPOSECCURSOR_NO_5             | no, it's CR or ';' -> flush item
        ST.B    -0x113(A6)                      | set disable flag for current item
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISPOSECCURSOR_NO_5
|
| Called during boot.
| DISPOSECCURSOR_NO_5: flush current parsed item into the menu (if any title text)
DISPOSECCURSOR_NO_5:
        MOVE    -0x112(A6),D0                   | D0 = title length
        BEQ.B   DISPOSECCURSOR_NO_6             | no title text, nothing to flush ->
        BSR.B   DISPOSECCURSOR_CONT_4           | insert the item into menu data
        BSR     DISPOSECCURSOR_NEXT             | re-init parse state for next item
DISPOSECCURSOR_NO_6:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| RETURNS_19
|
| Called during boot.
| RETURNS_19: clamp insertion point D6 to valid range
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
        BLE.B   DISPOSECCURSOR_OK_3             | no, D5 is valid ->
        MOVE    D0,D5                           | clamp to max position
DISPOSECCURSOR_OK_3:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISPOSECCURSOR_CONT_4
|
| Called during boot.
| DISPOSECCURSOR_CONT_4: insert parsed item into menu data at position D6
| Uses _Munger to splice title+attributes into the MenuInfo handle
DISPOSECCURSOR_CONT_4:
        BSR.B   RETURNS_19                      | clamp insertion point -> D5
        MOVE    D5,D0                           | D0 = clamped insertion position
        MOVE.L  (A3),A0                         | dereference MenuHandle
        BSR     RETURNS_16                      | find insertion point -> D1 = offset
        BEQ.B   DISPOSECCURSOR_CONT_5           | past end -> insert at end
        MOVE.L  A0,D1                           | D1 = ptr to insertion point in data
        MOVE.L  (A3),A0                         | re-dereference (may have moved)
        BSR.B   DISPOSECCURSOR_CONT_6           | shift enableFlags to make room for new item
DISPOSECCURSOR_CONT_5:
        LEA.L   -0x110(A6),A0                   | A0 = title buffer
        MOVE.L  A0,A2                           | A2 = title buffer base
        MOVE    -0x112(A6),D2                   | D2 = title length
        ADDA    D2,A0                           | A0 = end of title in buffer
        LEA.L   -0x118(A6),A1                   | A1 = attribute bytes (icon,key,mark,style)
        MOVEQ.L #0x3,D0                         | copy 4 attribute bytes
DISPOSECCURSOR_LOOP_4:
        MOVE.B  (A1)+,(A0)+                     | append attributes after title
        DBF     D0,DISPOSECCURSOR_LOOP_4        | loop 4 bytes
        SUBQ.W  #0x1,A2                         | A2 = 1 byte before title (for length byte)
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
        BEQ.B   DISPOSECCURSOR_NO_7             | no ->
        MOVE.L  A3,-(SP)                        | push MenuHandle
        MOVE    D5,-(SP)                        | push item number
        BSR     DisableItem                     | disable the newly inserted item
DISPOSECCURSOR_NO_7:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DISPOSECCURSOR_CONT_6
|
| Called during boot.
| DISPOSECCURSOR_CONT_6: shift enableFlags right at position D5 to insert a 0 bit for new item
| A0 = MenuInfo ptr, D5 = item position
| Rotates bits so a cleared bit is inserted at position D5
DISPOSECCURSOR_CONT_6:
        MOVE.L  menuEnable(A0),D2               | D2 = current enableFlags
        ROR.L   D5,D2                           | rotate right by item position
        MOVE    D5,D0                           | D0 = position
        SUBI    #0x20,D0                        | D0 = position - 32
        NEG     D0                              | D0 = 32 - position (bits remaining)
        ROXR.L  D0,D2                           | rotate through X bit, inserting 0
        MOVE.L  D2,menuEnable(A0)               | store updated enableFlags
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _GetMenuHandle ($A949)
|
| _GetMenuHandle ($A949): find a menu in the menu bar by ID
| Pascal: function GetMHandle(menuID: INTEGER): MenuHandle;
GetMenuHandle:
        CLR.L   0x6(SP)                         | result = nil initially
        MOVE    0x4(SP),D1                      | D1 = menuID to find
        BSR     INSERTMENU_CONT_2               | search MenuList for matching ID
        BEQ.B   GETMENUHANDLE_FOUND             | not found ->
        MOVE    D5,-(SP)                        | save menu counter
        MOVE    D0,D5                           | D5 = index in MenuList
        BSR     DISABLEITEM_NEXT                | get MenuHandle at index -> A1
        MOVE    (SP)+,D5                        | restore counter
        MOVE.L  A1,0x6(SP)                      | store result MenuHandle
GETMENUHANDLE_FOUND:
        BRA     DELETEMENU_EXIT                 | -> strip params and return

| ----------------------------------------------------------
|
| _DeleteMenuItem ($A952): remove item from a menu
| Pascal: procedure DelMenuItem(theMenu: MenuHandle; item: INTEGER);
DeleteMenuItem:
        MOVE.L  (SP),-(SP)                      | dup return address (make room for saves)
        MOVEM.L D3-D4/A2-A4,-(SP)               | save registers
        MOVE.L  0x1E(SP),A3                     | A3 = MenuHandle
        MOVE.L  (A3),A0                         | dereference -> MenuInfo ptr
        MOVE    0x1C(SP),D0                     | D0 = item number to delete
        MOVE.L  menuEnable(A0),D1               | D1 = enableFlags
        MOVE    D0,D2                           | D2 = item number
        SUBI    #0x20,D2                        | D2 = item - 32
        NEG     D2                              | D2 = 32 - item (bits to shift)
        ROXL.L  D2,D1                           | rotate left, removing item's bit via X
        ROL.L   D0,D1                           | rotate back to original alignment
        MOVE.L  D1,menuEnable(A0)               | store updated enableFlags
        BSR     RETURNS_16                      | find item -> A0 = title ptr
        BEQ.B   SETMENUITEMTEXT_FOUND           | item not found ->
        MOVEQ.L #0x5,D4                         | D4 = 5 (delete title + 4 attr bytes + len)
        MOVEQ.L #0x0,D2                         | D2 = 0 (replacement length = 0 for delete)
        MOVE.L  D2,A2                           | A2 = nil (no replacement data)
        BRA.B   SETMENUITEMTEXT_CONT            | -> use Munger to remove item data

| ----------------------------------------------------------
|
| _SetMenuItemText ($A947)
|
| _SetMenuItemText ($A947): change a menu item's title
| Pascal: procedure SetItem(theMenu: MenuHandle; item: INTEGER; itemString: Str255);
| Uses _Munger to replace the old title with the new one in the menu data
SetMenuItemText:
        MOVEM.L D3-D4/A2-A4,-(SP)               | save working registers
        MOVE.L  0x1E(SP),A3                     | A3 = MenuHandle
        MOVE    0x1C(SP),D3                     | D3 = item number
        MOVE.L  0x18(SP),A2                     | A2 = new item string
        MOVE    D3,D0                           | D0 = item number for RETURNS_16
        MOVE.L  (A3),A0                         | dereference MenuHandle
        BSR     RETURNS_16                      | find item -> A0 = old title ptr
        BEQ.B   SETMENUITEMTEXT_FOUND           | not found ->
| set up Munger parameters to replace old title with new
        MOVEQ.L #0x1,D4                         | D4 = 1 (include length byte)
        MOVEQ.L #0x1,D2                         | D2 = new title size
        ADD.B   (A2),D2                         | + string length
SETMENUITEMTEXT_CONT:
        MOVE.L  A0,A4                           | A4 = item title pointer
        SUBA.L  (A3),A4                         | convert to offset in handle
        ADD.B   (A0),D4                         | D4 = old title size (length + string)
| call _Munger to replace old title with new in menu data handle
        SUBQ.W  #0x4,SP                         | space for result
        MOVE.L  A3,-(SP)                        | push handle
        MOVE.L  A4,-(SP)                        | push offset
        CLR.L   -(SP)                           | push target (nil = by offset)
        MOVE.L  D4,-(SP)                        | push old length
        MOVE.L  A2,-(SP)                        | push replacement ptr
        MOVE.L  D2,-(SP)                        | push replacement length
        _Munger                                 | replace text in handle
        ADDQ.W  #0x4,SP                         | discard result
        MOVE.L  A3,-(SP)                        | invalidate menu dimensions
        BSR     STACK_2                         | recalc menu size
SETMENUITEMTEXT_FOUND:
        MOVEM.L (SP)+,D3-D4/A2-A4               | restore registers
        BRA     MENUMGR_NO                      | -> strip params

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
| _AppendResMenu ($A94D): add all resources of a type to menu
| Used to populate Apple menu with DAs, Font menu with fonts, etc.
|
AppendResMenu:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE    #0x3E7,-(SP)                    | afterItem = 999 (append)
        MOVE.L  A0,-(SP)                        | push return address back
| _InsertResMenu ($A951): insert resources after specified position
InsertResMenu:
        CMPI.L  #0x464F4E54,0x6(SP)             | resource type == 'FONT'?

        BNE.B   INSERTRESMENU_NO                | no, normal resource scan ->
        MOVE.B  #0x44,0x9(SP)                   | change 'T' to 'D': 'FONT' -> 'FOND'
INSERTRESMENU_NO:
        LINK    A6,#-0x118                      | 280 bytes local (parse buffer)
        MOVEM.L D3-D7/A2-A4,-(SP)               | save registers
        MOVE    (ResLoad).w,-(SP)               | save current ResLoad state
        CLR     (ResLoad).w                     | disable auto-loading (just need names)
        BSR     DISPOSECCURSOR_NEXT             | init parse state buffer
        MOVE.L  0xE(A6),A3                      | A3 = MenuHandle
        MOVE    0x8(A6),D6                      | D6 = afterItem
        ADDQ.W  #0x1,D6                         | convert to 1-based insertion point
        BSR     RETURNS_19                      | clamp insertion point -> D5
        MOVE    D5,D7                           | D7 = starting insertion position
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
        _GetIndResource                         | get resource handle by index
        LEA.L   -0x111(A6),A4                   | A4 = name buffer (local frame)
        CLR.L   -(SP)                           | push nil (don't need type back)
        CLR.L   -(SP)                           | push nil (don't need ID back)
        MOVE.L  A4,-(SP)                        | push name buffer ptr
        _GetResInfo                             | get resource name into A4 buffer
        TST.B   (A4)                            | name length = 0?
        BEQ.B   INSERTRESMENU_SKIP              | unnamed resource, skip ->
        CMPI.B  #0x2E,0x1(A4)                   | name starts with '.'?
        BEQ.B   INSERTRESMENU_SKIP              | skip drivers (e.g. ".Print") ->
        CMPI.B  #0x25,0x1(A4)                   | name starts with '%'?
        BEQ.B   INSERTRESMENU_SKIP              | skip internal resources ->
| find alphabetical insertion position for this resource name
        MOVE    D5,D6                           | D6 = current insertion point
        CMP     D7,D6                           | at starting position?
        BEQ.B   INSERTRESMENU_OK                | yes, insert here (first item) ->
        MOVE.L  (A3),A0                         | dereference MenuHandle
        MOVE    D6,D0                           | D0 = item number to start searching
        BSR     RETURNS_16                      | find item -> A0 = title ptr
        MOVE.L  A0,A2                           | A2 = current menu item to compare
| scan existing items to find alphabetical position
INSERTRESMENU_NEXT_2:
        TST.B   (A2)                            | end of item list?
        BEQ.B   INSERTRESMENU_OK                | yes, insert at end ->
        MOVE.L  A2,A0                           | A0 = existing item title
        MOVE.L  A4,A1                           | A1 = new resource name
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A0)+,D0                        | D0.hi = existing title length
        SWAP    D0                              | move to high word
        MOVE.B  (A1)+,D0                        | D0.lo = new name length
        _CompareString                          | compare strings (case-insensitive)
        BGT.B   INSERTRESMENU_OK                | existing > new: insert before it ->
        BEQ.B   INSERTRESMENU_SKIP              | duplicate name: skip this resource ->
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A2),D0                         | D0 = existing title length
        ADDQ.W  #0x5,D0                         | + 5 attribute/padding bytes
        ADDA.L  D0,A2                           | advance A2 to next item
        ADDQ.W  #0x1,D6                         | increment insertion point
        BRA.B   INSERTRESMENU_NEXT_2            | compare with next item

| ----------------------------------------------------------
|
| INSERTRESMENU_OK
|
| Called during boot.
| INSERTRESMENU_OK: insert the resource name as a new menu item
INSERTRESMENU_OK:
        MOVE    D5,-(SP)                        | save insertion position
        BSR     DISPOSECCURSOR_NO_5             | flush parsed item into menu
        MOVE    (SP)+,D5                        | restore insertion position
        ADDQ.W  #0x1,D7                         | advance starting position for next insert
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
        RTS                                     | return to caller

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
        PEA.L   menuWidth(A0)                   | push dstBits (thePort.portBits at offset 2)
        PEA.L   0x6(A1)                         | push srcRect (icon bounds at offset 6)
        MOVE.L  D1,-(SP)                        | push dstRect
        CLR     -(SP)                           | push mode = srcCopy (0)
        CLR.L   -(SP)                           | push maskRgn = nil
        _CopyBits                               | draw icon into port
PLOTICON_SKIP:
        BRA     MENUMGR_SKIP                    | -> strip 8 bytes of params

