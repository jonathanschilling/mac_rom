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
| _GetPattern ($A9B8) - load 'PAT ' resource by ID.
| Returns a Handle in result word.
| ----------------------------------------------------------
| Apple source module: GMGR
GETPATTERN:
    MOVE.L	#0x50415420,D0                       | D0 = 'PAT ' resource type
GETPATTERN_EXIT:
    SUBQ.W	#0x4,A7                              | space for GetResource result
    MOVE.L	D0,-(A7)                             | push resource type
    MOVE.W	0xC(A7),-(A7)                        | push resource ID (param)
    _GetResource                                | load resource -> handle on stack
    MOVE.L	(A7)+,D0                             | D0 = resource handle
    MOVEA.L	(A7)+,A0                            | A0 = return address
    ADDQ.W	#0x2,A7                              | pop resID parameter
    MOVE.L	D0,(A7)                              | store handle as return value
    JMP	(A0)                                    | tail-call return from GETPATTERN_EXIT via A0
| ----------------------------------------------------------
| _GetCursor ($A9B9) - load 'CURS' resource by ID.
| ----------------------------------------------------------
GETCURSOR:
    MOVE.L	#0x43555253,D0                       | D0 = 'CURS' resource type
    BRA.B	GETPATTERN_EXIT                       | -> get and return resource
| ----------------------------------------------------------
| _GetString ($A9BA) - load 'STR ' resource by ID.
| ----------------------------------------------------------
GETSTRING:
    MOVE.L	#0x53545220,D0                       | D0 = 'STR ' resource type
    BRA.B	GETPATTERN_EXIT                       | -> get and return resource
| ----------------------------------------------------------
| _GetIcon ($A9BB) - load 'ICON' resource by ID.
| ----------------------------------------------------------
GETICON:
    MOVE.L	#0x49434F4E,D0                       | D0 = 'ICON' resource type
    BRA.B	GETPATTERN_EXIT                       | -> get and return resource
| ----------------------------------------------------------
| _GetPicture ($A9BC) - load 'PICT' resource by ID.
| ----------------------------------------------------------
GETPICTURE:
    MOVE.L	#0x50494354,D0                       | D0 = 'PICT' resource type
    BRA.B	GETPATTERN_EXIT                       | -> get and return resource
| ----------------------------------------------------------
| _GetNewWindow ($A9BD) - create window from WIND template.
| Loads WIND resource by ID and calls NewWindow with the
| boundsRect, title, visible flag, procID, behind window,
| goAwayFlag and refCon from the template.
| ----------------------------------------------------------
GETNEWWINDOW:
    LINK	A6,#-0x2                               | set up frame with 2-byte local
    CLR.W	-0x2(A6)                              | clear local flag word
    MOVE.L	A3,-(A7)                             | save A3
    CLR.L	0x12(A6)                              | clear return value (window ptr)
    SUBQ.W	#0x4,A7                              | space for GetResource result
    MOVE.L	#0x57494E44,-(A7)                    | push 'WIND' resource type
    MOVE.W	0x10(A6),-(A7)                       | push resource ID (param)
    _GetResource                                | load WIND template
    MOVEA.L	(A7)+,A3                            | A3 = WIND resource handle
    MOVE.L	A3,D0                                | test for nil
    BEQ.B	GETNEWWINDOW_FOUND                    | not found -> bail
    MOVEA.L	(A3),A0                             | A0 = dereferenced WIND data
    SUBQ.W	#0x4,A7                              | space for NewWindow result
    MOVE.L	0xC(A6),-(A7)                        | push wStorage (behind param)
    MOVE.L	A0,-(A7)                             | push boundsRect from template
    PEA.L	0x12(A0)                              | push title string from template
    MOVE.L	0x8(A0),-(A7)                        | push visible + procID from template
    MOVE.L	0x8(A6),-(A7)                        | push behind window (param)
    MOVE.W	0xC(A0),-(A7)                        | push goAwayFlag from template
    MOVE.L	0xE(A0),-(A7)                        | push refCon from template
    MOVEA.L	A3,A0                               | A0 = WIND handle for HLock
    _HLock                                      | lock WIND handle during NewWindow
    _NewWindow                                  | create the window
    MOVE.L	(A7)+,0x12(A6)                       | store window ptr as return value
    MOVE.L	A3,-(A7)                             | push WIND handle
    _ReleaseResource                            | release the WIND template
GETNEWWINDOW_FOUND:
    MOVEA.L	(A7)+,A3                            | restore A3
    UNLK	A6                                     | tear down frame
    MOVEA.L	(A7)+,A0                            | A0 = return address
    ADDA.W	#0xA,A7                              | pop parameters (10 bytes)
    JMP	(A0)                                    | tail-call return from GETNEWWINDOW_FOUND via A0
| ----------------------------------------------------------
| _GetNewControl ($A9BE) - create control from CNTL template.
| Loads CNTL resource by ID, then calls NewControl with the
| boundsRect, title, visible+value, min+max, procID and refCon
| from the template.
| ----------------------------------------------------------
GETNEWCONTROL:
    LINK	A6,#0x0                                | set up stack frame
    MOVE.L	A3,-(A7)                             | save A3
    CLR.L	0xE(A6)                               | clear return value (ControlHandle)
    SUBQ.W	#0x4,A7                              | space for GetResource result
    MOVE.L	#0x434E544C,-(A7)                    | push 'CNTL' resource type
    MOVE.W	0xC(A6),-(A7)                        | push resource ID (param)
    _GetResource                                | load CNTL template
    MOVEA.L	(A7)+,A3                            | A3 = CNTL resource handle
    MOVE.L	A3,D0                                | test for nil
    BEQ.B	GETNEWCONTROL_FOUND                   | not found -> bail
    MOVEA.L	(A3),A0                             | A0 = dereferenced CNTL data
    SUBQ.W	#0x4,A7                              | space for NewControl result
    MOVE.L	0x8(A6),-(A7)                        | push owning window (param)
    MOVE.L	A0,-(A7)                             | push boundsRect from template
    PEA.L	0x16(A0)                              | push title string from template
    LEA.L	0x8(A0),A1                            | A1 = pointer past boundsRect
    MOVE.L	(A1)+,-(A7)                          | push visible + initial value
    MOVE.L	(A1)+,-(A7)                          | push min + max
    MOVE.W	(A1)+,-(A7)                          | push procID
    MOVE.L	(A1)+,-(A7)                          | push refCon
    MOVEA.L	A3,A0                               | A0 = CNTL handle for HLock
    _HLock                                      | lock CNTL handle during NewControl
    _NewControl                                 | create the control
    MOVE.L	(A7)+,0xE(A6)                        | store ControlHandle as return value
    MOVE.L	A3,-(A7)                             | push CNTL handle
    _ReleaseResource                            | release the CNTL template
GETNEWCONTROL_FOUND:
    MOVEA.L	(A7)+,A3                            | restore A3
    UNLK	A6                                     | tear down frame
    MOVEA.L	(A7)+,A0                            | A0 = return address
    ADDQ.W	#0x6,A7                              | pop parameters (6 bytes)
    JMP	(A0)                                    | tail-call return from GETNEWCONTROL_FOUND via A0
| ----------------------------------------------------------
| _GetRMenu ($A9BF) / GETMENU - load MENU resource by ID.
| Loads the menuProc (MDEF) referenced by the MENU template
| if not already an MDEF resource, then calls _CalcMenuSize.
| ----------------------------------------------------------
GETMENU:
    LINK	A6,#0x0                                | set up stack frame
    MOVE.L	A3,-(A7)                             | save A3
    MOVE.W	(ResLoad).W,-(A7)                    | save current ResLoad state
    MOVEQ.L	#0x0,D0                             | ResLoad = false (don't auto-load)
    BSR.B	GETRMENU_CONT                         | get MENU resource -> A3
    BEQ.B	GETRMENU_DONE                         | nil -> bail
    MOVE.L	(A3),D0                              | is MENU already loaded?
    BEQ.B	GETRMENU_NO                           | no -> try loading with ResLoad
    CLR.L	-(A7)                                 | space for GetResInfo result
    MOVEA.L	(A3),A0                             | dereference MENU handle
    MOVE.L	0x6(A0),-(A7)                        | push menuProc handle
    CLR.L	-(A7)                                 | ID placeholder (not needed)
    PEA.L	0x8(A7)                               | push ptr for type result
    CLR.L	-(A7)                                 | name placeholder (nil)
    _GetResInfo                                 | get resource type of menuProc
    MOVE.L	(A7)+,D0                             | D0 = resource type
    CMPI.L	#0x4D444546,D0                       | is it 'MDEF'?
    BEQ.B	GETRMENU_DONE                         | yes -> already set up, done
    BRA.B	GETRMENU_NO_2                         | no -> need to find MDEF
| ----------------------------------------------------------
|
| GETRMENU_NO - MENU not loaded yet: reload with ResLoad=1
|
GETRMENU_NO:
    MOVEQ.L	#0x1,D0                             | ResLoad = true (auto-load)
    BSR.B	GETRMENU_CONT                         | reload MENU resource -> A3
    BEQ.B	GETRMENU_DONE                         | nil -> bail
GETRMENU_NO_2:
    SUBQ.W	#0x4,A7                              | space for GetResource result
    MOVE.L	#0x4D444546,-(A7)                    | push 'MDEF' resource type
    MOVEA.L	(A3),A0                             | dereference MENU handle
    MOVE.W	0x6(A0),-(A7)                        | push menuProc ID from MENU data
    MOVE.W	#0xFFFF,(ROMMapInsert).W             | include ROM map in search
    _GetResource                                | load MDEF resource
    MOVEA.L	(A3),A0                             | dereference MENU handle
    MOVE.L	(A7)+,0x6(A0)                        | store MDEF handle into MENU.menuProc
    MOVE.L	A3,-(A7)                             | push MENU handle
    _CalcMenuSize                               | compute menu dimensions
GETRMENU_DONE:
    _SetResLoad                                 | restore saved ResLoad state
    MOVEA.L	(A7)+,A3                            | restore A3
    UNLK	A6                                     | tear down frame
    MOVEA.L	(A7)+,A0                            | A0 = return address
    ADDQ.W	#0x2,A7                              | pop menuID parameter
    JMP	(A0)                                    | tail-call return from GETRMENU_DONE via A0
| ----------------------------------------------------------
|
| GETRMENU_CONT - shared MENU loader: sets ResLoad to D0,
| then calls _GetResource with the menuID from caller's frame.
|
| Called during boot.
GETRMENU_CONT:
    MOVE.B	D0,-(A7)                             | push ResLoad flag (0 or 1)
    _SetResLoad                                 | set auto-load mode
    SUBQ.W	#0x4,A7                              | space for GetResource result
    MOVE.L	#0x4D454E55,-(A7)                    | push 'MENU' resource type
    MOVE.W	0x8(A6),-(A7)                        | push menu ID (param)
    _GetResource                                | load MENU resource
    MOVEA.L	(A7)+,A3                            | A3 = MENU handle
    MOVE.L	A3,0xA(A6)                           | store as return value
    RTS                                         | return newly loaded MENU handle
| ----------------------------------------------------------
| _GetNewMBar ($A9C0) - build menu bar from MBAR template.
| Loads MBAR resource, then for each menuID in the template
| calls _GetRMenu and _InsertMenu. Returns the resulting
| menu list handle (caller may pass to _SetMenuBar).
| ----------------------------------------------------------
GETNEWMBAR:
    LINK	A6,#0x0                                | set up stack frame
    MOVEM.L	D3/A3,-(A7)                         | save registers
    CLR.L	0xA(A6)                               | clear return value (menu bar handle)
    SUBQ.W	#0x4,A7                              | space for GetMenuBar result
    _GetMenuBar                                 | save current menu bar
    _ClearMenuBar                               | clear menu list
    SUBQ.W	#0x4,A7                              | space for GetResource result
    MOVE.L	#0x4D424152,-(A7)                    | push 'MBAR' resource type
    MOVE.W	0x8(A6),-(A7)                        | push resource ID (param)
    _GetResource                                | load MBAR resource
    MOVEA.L	(A7)+,A3                            | A3 = MBAR handle
    MOVE.L	A3,D0                                | test for nil
    BEQ.B	GETNEWMBAR_FOUND                      | not found -> restore old bar
    MOVEQ.L	#0x0,D3                             | D3 = menu index counter
GETNEWMBAR_LOOP:
    SUBQ.W	#0x4,A7                              | space for GetRMenu result
    MOVEA.L	(A3),A0                             | dereference MBAR
    MOVE.W	D3,D0                                | D0 = index
    ADD.W	D0,D0                                 | word offset
    MOVE.W	0x2(A0,D0.W),-(A7)                   | push menu ID from MBAR list
    _GetRMenu                                   | load MENU resource -> handle on stack
    CLR.W	-(A7)                                 | beforeID = 0 (append)
    _InsertMenu                                 | add menu to menu bar
    MOVEA.L	(A3),A0                             | dereference MBAR (may have moved)
    ADDQ.W	#0x1,D3                              | next index
    CMP.W	(A0),D3                               | processed all menus?
    BLT.B	GETNEWMBAR_LOOP                       | no -> continue loop
    SUBQ.W	#0x4,A7                              | space for GetMenuBar result
    _GetMenuBar                                 | get newly built menu bar
    MOVE.L	(A7)+,0xA(A6)                        | store as return value
    MOVE.L	A3,-(A7)                             | push MBAR handle
    _ReleaseResource                            | release MBAR template
GETNEWMBAR_FOUND:
    MOVE.L	(A7),-(A7)                           | dup saved menu bar handle on stack
    _SetMenuBar                                 | restore original menu bar
    MOVEA.L	(A7)+,A0                            | A0 = old menu bar handle
    _DisposeHandle                              | dispose old menu bar copy
    MOVEM.L	(A7)+,D3/A3                         | restore registers
    UNLK	A6                                     | tear down frame
    MOVEA.L	(A7)+,A0                            | A0 = return address
    ADDQ.W	#0x2,A7                              | pop resource ID parameter
    JMP	(A0)                                    | tail-call return from GETNEWMBAR_FOUND via A0
