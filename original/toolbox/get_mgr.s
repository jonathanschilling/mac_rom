| Resource getters -- GetPattern ... GetNewMBar
|
| Apple source: GetMgr.a (MacSEROM.lst module GMGR). Small Toolbox
| routines that read a resource and hand back the object built from it:
| GetPattern ('PAT '), GetCursor ('CURS'), GetString ('STR '), GetIcon
| ('ICON'), GetPicture ('PICT'), GetNewWindow ('WIND'), GetNewControl
| ('CNTL'), GetRMenu ('MENU') and GetNewMBar ('MBAR').
|
| References: Inside Macintosh Vol I: Ch 16 Toolbox Utilities, Ch 9
| Window Manager, Ch 10 Control Manager, Ch 11 Menu Manager

| ----------------------------------------------------------
| GetPattern -- _GetPattern ($A9B8).
| Gets a 'PAT ' resource by ID. Common epilog GETPATTERN_EXIT
| is shared with GetCursor/GetString/GetIcon/GetPicture.
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
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| GetCursor -- _GetCursor ($A9B9).
GetCursor:                                      | jump via A0
        MOVE.L  #0x43555253,D0                  | D0 = 'CURS' resource type
        BRA.B   GETPATTERN_EXIT                 | share GetResource epilog

| ----------------------------------------------------------
| GetString -- _GetString ($A9BA).
GetString:
        MOVE.L  #0x53545220,D0                  | D0 = 'STR ' resource type
        BRA.B   GETPATTERN_EXIT                 | share GetResource epilog

| ----------------------------------------------------------
| GetIcon -- _GetIcon ($A9BB).
GetIcon:
        MOVE.L  #0x49434F4E,D0                  | D0 = 'ICON' resource type
        BRA.B   GETPATTERN_EXIT                 | share GetResource epilog

| ----------------------------------------------------------
| GetPicture -- _GetPicture ($A9BC).
GetPicture:
        MOVE.L  #0x50494354,D0                  | D0 = 'PICT' resource type
        BRA.B   GETPATTERN_EXIT                 | share GetResource epilog

| ----------------------------------------------------------
| GetNewWindow -- _GetNewWindow ($A9BD).
| Loads a 'WIND' resource and creates a new window from the template.
GetNewWindow:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        CLR.L   18(A6)                          | clear return value (window ptr)
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x57494E44,-(SP)               | push 'WIND' resource type
        MOVE    16(A6),-(SP)                    | push resource ID (param)
        _GetResource                            | load WIND template
        MOVE.L  (SP)+,A3                        | A3 = WIND resource handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETPATTERN_EXIT_FOUND           | not found -> bail
        MOVE.L  (A3),A0                         | A0 = dereferenced WIND data
        SUBQ.W  #0x4,SP                         | space for NewWindow result
        MOVE.L  12(A6),-(SP)                    | push wStorage (behind param)
        MOVE.L  A0,-(SP)                        | push boundsRect from template
        PEA.L     18(A0)                        | push title string from template
        MOVE.L  8(A0),-(SP)                     | push visible + procID from template
        MOVE.L  8(A6),-(SP)                     | push behind window (param)
        MOVE    12(A0),-(SP)                    | push goAwayFlag from template
        MOVE.L  14(A0),-(SP)                    | push refCon from template
        BSET    #0x7,(A3)                       | lock WIND handle during NewWindow
        _NewWindow                              | create the window
        MOVE.L  (SP)+,18(A6)                    | store window ptr as return value
        MOVE.L  A3,-(SP)                        | push WIND handle
        _ReleaseResource                        | release the WIND template
GETPATTERN_EXIT_FOUND:
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0xA,SP                         | strip 10 bytes of params
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
| _GetNewControl ($A9BE)
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
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| GetRMenu -- _GetRMenu ($A9BF).
| Loads a MENU resource by ID and inserts it via _InsertMenu.
| Resolves MDEF reference to actual menu definition proc.
GetRMenu:
        LINK    A6,#0x0                         | set up stack frame
        MOVE.L  A3,-(SP)                        | save A3
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D454E55,-(SP)               | push 'MENU' resource type
        MOVE    8(A6),-(SP)                     | push resource ID (param)
        _GetResource                            | load MENU resource
        MOVE.L  (SP)+,A3                        | A3 = MENU resource handle
        MOVE.L  A3,10(A6)                       | store handle as result
        BEQ.B   GETRMENU_EXIT                   | NIL - bail
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D444546,-(SP)               | push 'MDEF' resource type
        MOVE.L  (A3),A0                         | dereference MENU handle
        MOVE    6(A0),-(SP)                     | push procID from MENU
        _GetResource                            | load MDEF resource
        MOVE.L  (A3),A0                         | dereference MENU handle (may have moved)
        MOVE.L  (SP)+,6(A0)                     | store MDEF handle in MENU's procID slot
        MOVE.L  A3,-(SP)                        | push MENU handle
        _CalcMenuSize                           | calculate menu width/height
GETRMENU_EXIT:
        MOVE.L  (SP)+,A3                        | restore A3
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x2,SP                         | pop resID parameter
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| GetNewMBar -- _GetNewMBar ($A9C0).
| Loads an MBAR resource and inserts each menu via GetRMenu.
GetNewMBar:
        LINK    A6,#0x0                         | set up stack frame
        MOVEM.L D3/A3,-(SP)                     | save registers
        CLR.L   10(A6)                          | clear return value (menu bar handle)
        SUBQ.W  #0x4,SP                         | space for GetMenuBar result
        _GetMenuBar                             | save current menu bar
        _ClearMenuBar                           | clear menu list
        SUBQ.W  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x4D424152,-(SP)               | push 'MBAR' resource type
        MOVE    8(A6),-(SP)                     | push resource ID (param)
        _GetResource                            | load MBAR resource
        MOVE.L  (SP)+,A3                        | A3 = MBAR handle
        MOVE.L  A3,D0                           | test for nil
        BEQ.B   GETNEWMBAR_FOUND                | MBAR not found: bail
        MOVEQ.L #0x0,D3                         | D3 = menu index counter
GETNEWCONTROL_FOUND_CONT_3:
        SUBQ.W  #0x4,SP                         | space for GetRMenu result
        MOVE.L  (A3),A0                         | A0 = MBAR data ptr
        MOVE    D3,D0                           | D0 = current menu index
        ADD     D0,D0                           | index *= 2 (word entries)
        MOVE    2(A0,D0.W),-(SP)                | push menu resID from MBAR[i]
        BSR.B   GetRMenu                        | load MENU + MDEF resource
        CLR     -(SP)                           | push beforeID = 0 (append)
        _InsertMenu                             | insert into current menu list
        MOVE.L  (A3),A0                         | reload MBAR ptr (may have moved)
        ADDQ.W  #0x1,D3                         | advance to next index
        CMP     (A0),D3                         | more menus to load?
        BLT.B   GETNEWCONTROL_FOUND_CONT_3      | yes: continue
        SUBQ.W  #0x4,SP                         | space for GetMenuBar result
        _GetMenuBar                             | grab handle to new menu bar
        MOVE.L  (SP)+,10(A6)                    | return menu bar handle
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
        JMP     (A0)                            | RTS

