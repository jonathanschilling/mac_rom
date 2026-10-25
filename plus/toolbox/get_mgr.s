| Resource getters -- GetPattern ... GetNewMBar
|
| Apple source: GetMgr.a (MacSEROM.lst module GMGR). Small Toolbox
| routines that read a resource and hand back the object built from it:
| GetPattern ('PAT '), GetCursor ('CURS'), GetString ('STR '), GetIcon
| ('ICON'), GetPicture ('PICT'), GetNewWindow ('WIND'), GetNewControl
| ('CNTL'), GetRMenu ('MENU', with its MDEF) and GetNewMBar ('MBAR').
|
| References: Inside Macintosh Vol I: Ch 16 Toolbox Utilities (GetPattern,
| GetCursor, GetString, GetIcon, GetPicture), Ch 9 Window Manager
| (GetNewWindow), Ch 10 Control Manager (GetNewControl), Ch 11 Menu
| Manager (GetMenu, GetNewMBar)

| ----------------------------------------------------------
|
| _GetPattern ($A9B8)
|
| Called during boot.
GetPattern:
        MOVE.L  #0x50415420,D0                  | D0 = 'PAT ' resource type
GETPATTERN_EXIT:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  D0,-(SP)                        | push resource type
        MOVE    0xC(SP),-(SP)                   | push resource ID (param)
        _GetResource                            | load resource -> handle on stack
        MOVE.L  (SP)+,D0                        | D0 = resource handle
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x2,SP                         | pop resID parameter
        MOVE.L  D0,(SP)                         | store handle as return value
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _GetCursor ($A9B9)
|
| Called during boot.
GetCursor:
        MOVE.L  #0x43555253,D0                  | D0 = 'CURS' resource type
        BRA.B   GETPATTERN_EXIT                 | -> get and return resource

| GetString -- _GetString ($A9BA): FUNCTION GetString (stringID: INTEGER) : StringHandle;
| ----------------------------------------------------------
|
| _GetString ($A9BA)
|
GetString:
        MOVE.L  #0x53545220,D0                  | D0 = 'STR ' resource type
        BRA.B   GETPATTERN_EXIT                 | -> get and return resource

| GetIcon -- trap handler for _GetIcon ($A9BB).
| ----------------------------------------------------------
|
| _GetIcon ($A9BB)
|
GetIcon:
        MOVE.L  #0x49434F4E,D0                  | D0 = 'ICON' resource type
        BRA.B   GETPATTERN_EXIT                 | -> get and return resource

| GetPicture -- _GetPicture ($A9BC): FUNCTION GetPicture (picID: INTEGER) : PicHandle;
| ----------------------------------------------------------
|
| _GetPicture ($A9BC)
|
GetPicture:
        MOVE.L  #0x50494354,D0                  | D0 = 'PICT' resource type
        BRA.B   GETPATTERN_EXIT                 | -> get and return resource

| ----------------------------------------------------------
|
| _GetNewWindow ($A9BD)
|
GetNewWindow:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        CLR.L   0x12(A6)                        | clear return value (window ptr)
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x57494E44,-(SP)               | push 'WIND' resource type
        MOVE    0x10(A6),-(SP)                  | push resource ID (param)
        _GetResource                            | load WIND template
        MOVE.L  (SP)+,A3                        | A3 = WIND resource handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETNEWWINDOW_FOUND              | not found -> bail
        MOVE.L  (A3),A0                         | A0 = dereferenced WIND data
        SUBQ.W  #0x4,SP                         | space for NewWindow result
        MOVE.L  0xC(A6),-(SP)                   | push wStorage (behind param)
        MOVE.L  A0,-(SP)                        | push boundsRect from template
        PEA.L   0x12(A0)                        | push title string from template
        MOVE.L  0x8(A0),-(SP)                   | push visible + procID from template
        MOVE.L  0x8(A6),-(SP)                   | push behind window (param)
        MOVE    0xC(A0),-(SP)                   | push goAwayFlag from template
        MOVE.L  0xE(A0),-(SP)                   | push refCon from template
        BSET    #0x7,(A3)                       | lock WIND handle during NewWindow
        _NewWindow                              | create the window
        MOVE.L  (SP)+,0x12(A6)                  | store window ptr as return value
        MOVE.L  A3,-(SP)                        | push WIND handle
        _ReleaseResource                        | release the WIND template
GETNEWWINDOW_FOUND:
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDA    #0xA,SP                         | pop parameters (10 bytes)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _GetNewControl ($A9BE)
|
GetNewControl:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        CLR.L   0xE(A6)                         | clear return value (ControlHandle)
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x434E544C,-(SP)               | push 'CNTL' resource type
        MOVE    0xC(A6),-(SP)                   | push resource ID (param)
        _GetResource                            | load CNTL template
        MOVE.L  (SP)+,A3                        | A3 = CNTL resource handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETNEWCONTROL_FOUND             | not found -> bail
        MOVE.L  (A3),A0                         | A0 = dereferenced CNTL data
        SUBQ.W  #0x4,SP                         | space for NewControl result
        MOVE.L  0x8(A6),-(SP)                   | push owning window (param)
        MOVE.L  A0,-(SP)                        | push boundsRect from template
        PEA.L   0x16(A0)                        | push title string from template
        LEA.L   0x8(A0),A1                      | A1 = pointer past boundsRect
        MOVE.L  (A1)+,-(SP)                     | push visible + initial value
        MOVE.L  (A1)+,-(SP)                     | push min + max
        MOVE    (A1)+,-(SP)                     | push procID
        MOVE.L  (A1)+,-(SP)                     | push refCon
        BSET    #0x7,(A3)                       | lock CNTL handle during NewControl
        _NewControl                             | create the control
        MOVE.L  (SP)+,0xE(A6)                   | store ControlHandle as return value
        MOVE.L  A3,-(SP)                        | push CNTL handle
        _ReleaseResource                        | release the CNTL template
GETNEWCONTROL_FOUND:
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x6,SP                         | pop parameters (6 bytes)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _GetRMenu ($A9BF)
|
| Called during boot.
GetRMenu:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        MOVE    (ResLoad).w,-(SP)               | save current ResLoad state
        MOVEQ.L #0x0,D0                         | ResLoad = false (don't auto-load)
        BSR.B   GETRMENU_CONT                   | get MENU resource -> A3
        BEQ.B   GETRMENU_DONE                   | nil -> bail
        MOVE.L  (A3),D0                         | is MENU already loaded?
        BEQ.B   GETRMENU_NO                     | no -> try loading with ResLoad
        CLR.L   -(SP)                           | space for GetResInfo result
        MOVE.L  (A3),A0                         | dereference MENU handle
        MOVE.L  0x6(A0),-(SP)                   | push menuProc handle
        CLR.L   -(SP)                           | ID placeholder (not needed)
        PEA.L   0x8(SP)                         | push ptr for type result
        CLR.L   -(SP)                           | name placeholder (nil)
        _GetResInfo                             | get resource type of menuProc
        MOVE.L  (SP)+,D0                        | D0 = resource type
        CMPI.L  #0x4D444546,D0                  | is it 'MDEF'?
        BEQ.B   GETRMENU_DONE                   | yes -> already set up, done
        BRA.B   GETRMENU_NO_2                   | no -> need to find MDEF

| ----------------------------------------------------------
|
| GETRMENU_NO
|
GETRMENU_NO:
        MOVEQ.L #0x1,D0                         | ResLoad = true (auto-load)
        BSR.B   GETRMENU_CONT                   | reload MENU resource -> A3
        BEQ.B   GETRMENU_DONE                   | nil -> bail
GETRMENU_NO_2:
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D444546,-(SP)               | push 'MDEF' resource type
        MOVE.L  (A3),A0                         | dereference MENU handle
        MOVE    0x6(A0),-(SP)                   | push menuProc ID from MENU data
        MOVE    #-0x1,(ROMMapInsert).w          | include ROM map in search
        _GetResource                            | load MDEF resource
        MOVE.L  (A3),A0                         | dereference MENU handle
        MOVE.L  (SP)+,0x6(A0)                   | store MDEF handle into MENU.menuProc
        MOVE.L  A3,-(SP)                        | push MENU handle
        _CalcMenuSize                           | compute menu dimensions
GETRMENU_DONE:
        _SetResLoad                             | restore saved ResLoad state
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x2,SP                         | pop menuID parameter
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| GETRMENU_CONT
|
| Called during boot.
GETRMENU_CONT:
        MOVE.B  D0,-(SP)                        | push ResLoad flag (0 or 1)
        _SetResLoad                             | set auto-load mode
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D454E55,-(SP)               | push 'MENU' resource type
        MOVE    0x8(A6),-(SP)                   | push menu ID (param)
        _GetResource                            | load MENU resource
        MOVE.L  (SP)+,A3                        | A3 = MENU handle
        MOVE.L  A3,0xA(A6)                      | store as return value
        RTS                                     | return newly loaded MENU handle

| GetNewMBar -- _GetNewMBar ($A9C0): FUNCTION GetNewMBar (menuBarID: Integer): Handle;
| ----------------------------------------------------------
|
| _GetNewMBar ($A9C0)
|
GetNewMBar:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D3/A3,-(SP)                     | save registers
        CLR.L   0xA(A6)                         | clear return value (menu bar handle)
        SUBQ.W  #0x4,SP                         | space for GetMenuBar result
        _GetMenuBar                             | save current menu bar
        _ClearMenuBar                           | clear menu list
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D424152,-(SP)               | push 'MBAR' resource type
        MOVE    0x8(A6),-(SP)                   | push resource ID (param)
        _GetResource                            | load MBAR resource
        MOVE.L  (SP)+,A3                        | A3 = MBAR handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETNEWMBAR_FOUND                | not found -> restore old bar
        MOVEQ.L #0x0,D3                         | D3 = menu index counter
GETNEWMBAR_LOOP:
        SUBQ.W  #0x4,SP                         | space for GetRMenu result
        MOVE.L  (A3),A0                         | dereference MBAR
        MOVE    D3,D0                           | D0 = index
        ADD     D0,D0                           | word offset
        MOVE    0x2(A0,D0.W),-(SP)              | push menu ID from MBAR list
        BSR     GetRMenu                        | load MENU resource -> handle on stack
        CLR     -(SP)                           | beforeID = 0 (append)
        _InsertMenu                             | add menu to menu bar
        MOVE.L  (A3),A0                         | dereference MBAR (may have moved)
        ADDQ.W  #0x1,D3                         | next index
        CMP     (A0),D3                         | processed all menus?
        BLT.B   GETNEWMBAR_LOOP                 | no -> continue loop
        SUBQ.W  #0x4,SP                         | space for GetMenuBar result
        _GetMenuBar                             | get newly built menu bar
        MOVE.L  (SP)+,0xA(A6)                   | store as return value
        MOVE.L  A3,-(SP)                        | push MBAR handle
        _ReleaseResource                        | release MBAR template
GETNEWMBAR_FOUND:
        MOVE.L  (SP),-(SP)                      | dup saved menu bar handle on stack
        _SetMenuBar                             | restore original menu bar
        MOVE.L  (SP)+,A0                        | A0 = old menu bar handle
        _DisposeHandle                          | dispose old menu bar copy
        MOVEM.L (SP)+,D3/A3                     | restore registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x2,SP                         | pop resource ID parameter
        JMP     (A0)                            | return to caller

