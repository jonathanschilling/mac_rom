| Toolbox Equates - Window, Control, Menu, Dialog, TE field offsets
| Source: MPW 1.0 ToolEqu.a, Apple Computer Inc. 1984-1986
| Converted to GNU as syntax for use in Mac Plus ROM source


| File: ToolEqu.a
|
| Version 2.0
|
| Copyright Apple Computer, Inc. 1984, 1985, 1986
| All Rights Reserved
|

| Toolbox Equates -- This file defines the high-level equates for the
| Macintosh toolbox software.  This is divided into two pieces for assembly
| space and speed considerations.  The wholeTools flag is used to include
| the less common equates which realizes a complete set.	The comments
| marked with ";+" denote managers.

.equ wholeTools, 1


| + Resource Manager

| Resource attributes

.equ resSysRef, 7                               | reference to system/local reference
.equ resSysHeap, 6                              | In system/in application heap
.equ resPurgeable, 5                            | Purgeable/not purgeable
.equ resLocked, 4                               | Locked/not locked
.equ resProtected, 3                            | Protected/not protected
.equ resPreload, 2                              | Read in at OpenResource?
.equ resChanged, 1                              | Existing resource changed since last update

.equ rcbMask, 0xFD                              | Must preserve ResChanged over _ResAttrs

| Map attributes

.equ mapReadOnly, 7                             | is this file read-only?
.equ mapCompact, 6                              | Is a compact necessary?
.equ mapChanged, 5                              | Is it necessary to write map?

| Resource Manager Globals

.equ TopMapHndl, 0xA50                          | topmost map in list [handle]
.equ SysMapHndl, 0xA54                          | system map [handle]
.equ SysMap, 0xA58                              | reference number of system map [word]
.equ CurMap, 0xA5A                              | reference number of current map [word]
.equ ResReadOnly, 0xA5C                         | Read only flag [word]
.equ ResLoad, 0xA5E                             | Auto-load feature [word]
.equ ResErr, 0xA60                              | Resource error code [word]
.equ ResErrProc, 0xAF2                          | Resource error procedure [pointer]
.equ SysResName, 0xAD8                          | Name of system resource file [STRING[19]]

| new Resource Manager stuff

.equ RomMapInsert, 0xB9E                        | (byte) determines if we should link in map
.equ TmpResLoad, 0xB9F                          | second byte is temporary ResLoad value.

| the following word values are to be placed into the
| word located at RomMapInsert

.equ MapTrue, 0xFFFF                            | link in ROM map with resload true
.equ MapFalse, 0xFF00                           | link in ROM map with resload false

| + Font Manager


| Standard font ID's

.equ sysFont, 0                                 | system font ID
.equ applFont, 1                                | application font ID

.equ newYork, 2                                 | standard release fonts
.equ geneva, 3
.equ monaco, 4
.equ venice, 5
.equ london, 6
.equ athens, 7
.equ sanFran, 8
.equ toronto, 9
.equ cairo, 11
.equ losAngeles, 12
.equ times, 20
.equ helvetica, 21
.equ courier, 22
.equ symbol, 23
.equ mobile, 24

| Font Manager Globals

.equ ApFontID, 0x984                            | resource ID of application font [word]
.equ FMDefaultSize, 0x987                       | default size [byte]
.equ CurFMInput, 0x988                          | quickdraw FMInput Record [pointer]
.equ FMgrOutRec, 0x998                          | quickdraw FontOutput Record [pointer]
.equ FScaleDisable, 0xA63                       | disable font scaling? [byte]

| new FONT manager stuff

.equ WidthListHand, 0x8E4                       | list of extra width tables, or nil.
.equ WidthPtr, 0xB10                            | (long) Font Mgr global
.equ WidthTabHandle, 0xB2A                      | Font width table handle for measure
.equ LastSPExtra, 0xB4C                         | (long) most recent value of space extra
.equ SysFontFam, 0xBA6                          | (word) System font family ID or zero
.equ SysFontSize, 0xBA8                         | (word) System font size (or zero for 12 pt)
.equ FDevDisable, 0xBB3                         | (byte) $FF to disable device-defined style extra
.equ LastFOND, 0xBC2                            | (long) handle of last font def record
.equ FONDID, 0xBC6                              | (word) ID of last font def record
.equ FractEnable, 0xBF4                         | (byte) flag for fractional font widths
.equ UsedFWidths, 0xBF5                         | (byte) flag saying if we used fract widths
.equ FScaleHFact, 0xBF6                         | (long) horz. font scale factor
.equ FScaleVFact, 0xBFA                         | (long) vertical font scale factor

| + Window Manager

.equ dialogKind, 2                              | dialog windows
.equ userKind, 8                                | this and above numbers are for user

| Values returned by window definition function's hit routine

.equ wNoHit, 0                                  | not in window at all
.equ wInContent, 1                              | in content area
.equ wInDrag, 2                                 | in drag area
.equ wInGrow, 3                                 | in grow area
.equ wInGoAway, 4                               | in go away area
.equ wInZoomIn, 5                               | in zoom in
.equ wInZoomOut, 6                              | in zoom out

| FindWindow Return Codes

.equ inDesk, 0                                  | not in any window
.equ inMenuBar, 1                               | in the menu bar
.equ inSysWindow, 2                             | in a system window
.equ inContent, 3                               | in content area of user window
.equ inDrag, 4                                  | in drag area of user window
.equ inGrow, 5                                  | in grow area of user window
.equ inGoAway, 6                                | in go away area of user window
.equ inZoomIn, 7                                | in zoom in part code
.equ inZoomOut, 8                               | in zoom out part code

| Resource ID's for windows

.equ deskPatID, 16                              | desk pattern PAT ID

.equ documentProc, 0                            | standard document WDEF ID
.equ dBoxProc, 1                                | dialog box (document without titleBar) WDEF ID
.equ plainDBox, 2                               | no border WDEF ID
.equ altDBoxProc, 3                             | no shadow or title WDEF ID
.equ noGrowDocProc, 4                           | no grow area WDEF ID
.equ zoomDocProc, 8                             | with zoom box WDEF ID
.equ zoomNoGrow, 12                             | zoom with no grow box WDEF ID
.equ rDocProc, 16                               | document with rounded corners WDEF ID

| Window Data Structure Definition

.equ windowPort, 0                              | grafPort [108 bytes]
.equ windowKind, 0x6C                           | type of window [word]
.equ wVisible, 0x6E                             | visible flag [byte]
.equ wHilited, 0x6F                             | select (hilite) flag [byte]
.equ wGoAway, 0x70                              | has go away button [byte]
.equ wZoom, 0x71                                | has zoom box [byte]
.equ structRgn, 0x72                            | structure region of window [Handle]
.equ contRgn, 0x76                              | content region of window [Handle]
.equ updateRgn, 0x7A                            | update region of window [Handle]
.equ windowDef, 0x7E                            | window definition procedure [Handle]
.equ wDataHandle, 0x82                          | window proc-defined data [Handle]
.equ wTitleHandle, 0x86                         | title string [Handle]
.equ wTitleWidth, 0x8A                          | width in pixels of title string [word]
.equ wControlList, 0x8C                         | control list of this window [handle]
.equ nextWindow, 0x90                           | next window in z-ordered list [pointer]
.equ windowPic, 0x94                            | picture handle for updates [handle]
.equ wRefCon, 0x98                              | application use [long]
.equ windowSize, 0x9C                           | size of window data structure

| Window Manager Globals

.equ WindowList, 0x9D6                          | Z-ordered linked list of windows [pointer]
.equ PaintWhite, 0x9DC                          | erase newly drawn windows? [word]
.equ WMgrPort, 0x9DE                            | window manager's grafport [pointer]
.equ GrayRgn, 0x9EE                             | rounded gray desk region [handle]
.equ CurActivate, 0xA64                         | window slated for activate event [pointer]
.equ CurDeactive, 0xA68                         | window slated for deactivate event [pointer]

.equ DragHook, 0x9F6                            | user hook during dragging [pointer]
.equ DeskPattern, 0xA3C                         | desk pattern [8 bytes]
.equ DeskHook, 0xA6C                            | hook for painting the desk [pointer]
.equ GhostWindow, 0xA84                         | window hidden from FrontWindow [pointer]



| + Menu Manager

| "ASCII" marks for menu characters

.equ noMark, 0
.equ commandMark, 0x11                          | command fan (cloverleaf)
.equ checkMark, 0x12                            | check mark for menus
.equ diamondMark, 0x13                          | diamond mark for menus
.equ appleMark, 0x14                            | desk ornament menu title

| MenuList Data Structure Definition -- one per menuBar

.equ lastMenu, 0                                | number of bytes in this menuList [word]
.equ lastRight, 2                               | h coordinate of 1st free point in menuBar [word]
.equ menuoH, 0                                  | menu handle [handle]
.equ menuLeft, 4                                | coordinate of left edge of menu [word]

| MenuInfo Data Structure -- one per menu

.equ menuID, 0                                  | unique ID for each menuBar [word]
.equ menuWidth, 2                               | menu width [word]
.equ menuHeight, 4                              | menu height [word]
.equ menuDefHandle, 6                           | menu definition proc [handle]
.equ menuEnable, 0xA                            | enable flags, one bit/item [long]
.equ menuData, 0xE                              | menu item string [STRING]
.equ menuBlkSize, 0xE                           | size of a menu block plus dataString

| MenuString Data Structure -- one per menu item

.equ itemIcon, 0                                | icon byte
.equ itemCmd, 1                                 | apple (command key) byte
.equ itemMark, 2                                | checkmark character byte
.equ itemStyle, 3                               | style byte

| Menu Manager Globals

.equ MenuList, 0xA1C                            | current menuBar list structure [handle]
.equ MenuFlash, 0xA24                           | flash feedback count [word]
.equ MenuHook, 0xA30                            | user hook during menuSelect [pointer]
.equ MBarEnable, 0xA20                          | menuBar enable for desk accessories[word]
.equ MBarHook, 0xA2C                            | user hook during menuSelect [pointer]

| new Menu Manager stuff

.equ MBarHeight, 0xBAA                          | (word) height of menu bar (usually 20)

| + Control Manager

| Part Codes

.equ inButton, 10                               | in a push button
.equ inCheckBox, 11                             | in a checkBox button
.equ inUpButton, 20                             | in up button area of a dial
.equ inDownButton, 21                           | in down button area of a dial
.equ inPageUp, 22                               | in page up (gray) area of a dial
.equ inPageDown, 23                             | in page down (gray) area of a dial
.equ inThumb, 129                               | in thumb area of a dial

| Constants for axis parameter of DragGrayRgn and DragControl

.equ noConstraint, 0                            | free form dragging
.equ hAxisOnly, 1                               | horizontally only
.equ vAxisOnly, 2                               | vertically only

| Resource ID's for controls

.equ pushButProc, 0                             | rounded-corner pushButtons CDEF ID
.equ checkBoxProc, 1                            | check-box type buttons CDEF ID
.equ radioButProc, 2                            | radio buttons  CDEF ID
.equ scrollBarProc, 16                          | scrollBar CDEF ID
.equ useWFont, 8                                | add this to get window font CDEF ID

.equ sBarPatID, 17                              | scrollBar pattern ID

| Control Template

.equ nextControl, 0x0                           | next control in the list [handle]
.equ contrlOwner, 0x4                           | owning window [pointer]
.equ contrlRect, 0x8                            | bounding rectangle [8 bytes]
.equ contrlVis, 0x10                            | visible state [byte]
.equ contrlHilite, 0x11                         | hilite state [byte]
.equ contrlValue, 0x12                          | current value of control [word]
.equ contrlMin, 0x14                            | minimum value of control [word]
.equ contrlMax, 0x16                            | maximum value of control [word]
.equ contrlDefHandle, 0x18                      | control definition procedure [handle]
.equ contrlData, 0x1C                           | data for definition proc [handle]
.equ contrlAction, 0x20                         | local actionProc [pointer]
.equ contrlRFcon, 0x24                          | refcon defined by application [long]
.equ contrlTitle, 0x28                          | title string [STRING]
.equ contrlSize, 0x28                           | size of control data structure less title

| Control Manager Globals

.equ DragPattern, 0xA34                         | DragTheRgn pattern [8 bytes]
.equ DragFlag, 0xA44                            | implicit parameter to DragControl [word]
.equ CurDragAction, 0xA46                       | implicit actionProc for dragControl [pointer]


| + Text Edit


| Justification styles

.equ teJustLeft, 0                              | left justified text
.equ teJustRight, -1                            | right justified text
.equ teJustCenter, 1                            | center justified text

| Text Edit Record

.equ teDestRect, 0x0                            | destination rectangle  [8 bytes]
.equ teViewRect, 0x8                            | view rectangle rectangle [8 bytes]

.equ teSelRect, 0x10                            | select rectangle [8 bytes]
.equ teLineHite, 0x18                           | lineheight [word]
.equ teAscent, 0x1A                             | first baseline offset [word]
.equ teSelPoint, 0x1C                           | selection point [long]

.equ teSelStart, 0x20                           | selection start [word]
.equ teSelEnd, 0x22                             | selection end [word]

.equ teActive, 0x24                             | active [byte]

.equ teWordBreak, 0x26                          | word break routine [pointer]
.equ teClikProc, 0x2A                           | click loop routine [pointer]

.equ teClikTime, 0x2E                           | time of last click [long]
.equ teClikLoc, 0x32                            | location of double click [long]

.equ teCarTime, 0x34                            | time for next caret toggle [long]
.equ teCarOn, 0x38                              | is caret on? [byte]
.equ teCarAct, 0x39                             | is caret active? [byte]
.equ teJust, 0x3A                               | fill style [word]

.equ teLength, 0x3C                             | length of text below [word]
.equ teTextH, 0x3E                              | text [handle]

.equ teRecBack, 0x42                            | unused [word]
.equ teRecLine, 0x44                            | unused [word]
.equ teLftClick, 0x46                           | click was to left? [byte]
.equ teLftCaret, 0x47                           | caret was to left? [byte]

.equ teCROnly, 0x48                             | <CR> only for line breaks? [byte]

.equ teFontStuff, 0x4A                          | space for font specifier [8 bytes]
.equ teFont, 0x4A                               | text font [word]
.equ teFace, 0x4C                               | text face [word]
.equ teMode, 0x4E                               | text mode [word]
.equ teSize, 0x50                               | text size [word]
.equ teGrafPort, 0x52                           | grafport for editting [pointer]

.equ teHiHook, 0x56                             | hook for hilite routine [pointer]
.equ teCarHook, 0x5A                            | hook for hilite routine [pointer]

.equ teNLines, 0x5E                             | number of lines [word]
.equ teLines, 0x60                              | line starts [words...]

.equ teRecSize, 0x68                            | base size of a record w/o lines

| Text Edit Globals

.equ TEScrpLength, 0xAB0                        | textEdit Scrap Length [word]
.equ TEScrpHandle, 0xAB4                        | textEdit Scrap [handle]
.equ TEWdBreak, 0xAF6                           | default word break routine [pointer]

| new TE stuff

.equ WordRedraw, 0xBA5                          | (byte) - used by TextEdit RecalDraw
.equ TESysJust, 0xBAC                           | (word) system justification (intl. textEdit)
.equ TEFlags, teRecBack                         | turn whole byte into bit flags
.equ teFAutoPos, 6                              | set this bit for auto position/scroll

| + Dialog Manager

| Item codes in item list

.equ userItem, 0                                | application-defined (dialog only)
.equ ctrlItem, 4                                | must be added to following four items
.equ btnCtrl, 0                                 | standard button
.equ chkCtrl, 1                                 | standard check box
.equ radCtrl, 2                                 | standard radio button
.equ resCtrl, 3                                 | control defined in resource file
.equ statText, 8                                | static text
.equ editText, 16                               | editable text (dialog only)
.equ iconItem, 32                               | icon
.equ picItem, 64                                | quickdraw picture
.equ itemDisable, 128                           | add to any of above to disable


| Generic buttons

.equ okButton, 1                                | OK button
.equ cancelButton, 2                            | Cancel button

| Alert/Dialog Resource ID's

.equ stopIcon, 0                                | stop icon ID
.equ noteIcon, 1                                | note icon ID
.equ cautionIcon, 2                             | caution icon ID

| Dialog Template

.equ dBounds, 0x0                               | dialog bounds rectangle
.equ dWindProc, 0x8                             | window proc ID
.equ dVisible, 0xA                              | visible flag
.equ dGoAway, 0xC                               | go away flag
.equ dRefCon, 0xE                               | reference constant
.equ dItems, 0x12                               | item list ID and handle
.equ dTitle, 0x14                               | dialog window title

| Alert Template

.equ aBounds, 0x0                               | alert box height and width
.equ aItems, 0x8                                | item list ID
.equ aStages, 0xA                               | stages word

| Dialog/Alert Window Record

.equ dWindow, 0x0                               | window record
.equ items, 0x9C                                | Item list [handle]
.equ teHandle, 0xA0                             | textEdit object [handle]
.equ editField, 0xA4                            | current field being edited [word]
.equ editOpen, 0xA6                             | is editting open? [word]
.equ aDefItem, 0xA8                             | default item for alerts [word]
.equ dWindLen, 0xAA                             | dialog record length

| In each item

.equ itmHndl, 0                                 | handle to the item
.equ itmRect, 0x4                               | bounding rect of item
.equ itmType, 0xC                               | item type
.equ itmData, 0xD                               | item string, must be even length

| Dialog Manager Globals

.equ ANumber, 0xA98                             | active alert ID [word]
.equ ACount, 0xA9A                              | # times this alert called [word]
.equ DABeeper, 0xA9C                            | beep routine [pointer]
.equ DAStrings, 0xAA0                           | paramText substutution strings [4 handles]
.equ DlgFont, 0xAFA                             | default dialog font ID [word]


| + Package Globals


.equ AppPacks, 0xAB8                            | packages' code [8 handles]


| + Finder related Globals


.equ FinderName, 0x2E0                          | "Finder" name [STRING[15]]
.equ AppParmHandle, 0xAEC                       | handle to hold application parameters


| + Miscellaneous Globals


.equ ApplScratch, 0xA78                         | application scratch area [12 Bytes]
.equ ToolScratch, 0x9CE                         | scratch area [8 bytes]
.equ TempRect, 0x9FA                            | scratch rectangle [8 bytes]

| System Patterns

.equ sysPatListID, 0                            | ID of PAT# which contains 38 patterns


| Resource Manager

.equ mCCMask, 0x60                              | mapCompact + mapChanged
.equ mChMask, 0x20                              | mapChanged
.equ mCoMask, 0x40                              | mapCompact

| Font Manager

| Font header values

.equ propFont, 0x9000                           | proportional font type
.equ prpFntH, 0x9001                            | with height table
.equ prpFntW, 0x9002                            | with width table
.equ prpFntHW, 0x9003                           | with height & width table

.equ fixedFont, 0xB000                          | fixed-pitch font type
.equ fxdFntH, 0xB001                            | with height table
.equ fxdFntW, 0xB002                            | with width table
.equ fxdFntHW, 0xB003                           | with height & width table

.equ fontWid, 0xACB0                            | width-only font type

| control/status codes for linkage w/font manager

.equ fMgrCtl1, 8                                | printer drivers

| Font Header Data Record

.equ fFontType, 0                               | font type [word]
.equ fFirstChar, 2                              | ASCII code of first char [word]
.equ fLastChar, 4                               | ASCII code of last char [word]
.equ fWidMax, 6                                 | maximum width of any char in pixels [word]
.equ fKernMax, 8                                | Negative of maximum character kern [word]
.equ fNDescent, 10                              | negative of descent [word]
.equ fFRectWidth, 12                            | width of font rectangle [word]
.equ fFRectHeight, 14                           | height of font rectangle [word]
.equ fOWTLoc, 16                                | offset to offset/width table [word]
.equ fAscent, 18                                | ascent above baseline in pixels [word]
.equ fDescent, 20                               | descent below baseline in pixels [word]
.equ fLeading, 22                               | space between lines in pixels [word]
.equ fRowWords, 24                              | row width of bit image / 2 [word]

| Font Manager Input Record (CurFMInput)

.equ fmInFamily, 0                              | family [word]
.equ fmInSize, 2                                | size [word]
.equ fmInFace, 4                                | face [word]
.equ fmInNeedBits, 5                            | needBits [byte]
.equ fmInDevice, 6                              | device number [byte]
.equ fmInNumer, 8                               | numerator of scale [fixed]
.equ fmInDenom, 12                              | denominator of scale [fixed]


| Font Manager Output record (FMgrOutRec)

.equ fmOutError, 0                              | error code [word]
.equ fmOutFontH, 2                              | the actual font [handle]
.equ fmOutBold, 6                               | bolding factor [byte]
.equ fmOutItalic, 7                             | italic factor [byte]
.equ fmOutULOffset, 8                           | underline offset [byte]
.equ fmOutULShadow, 9                           | underline halo [byte]
.equ fmOutULThick, 10                           | underline thickness [byte]
.equ fmOutShadow, 11                            | shadow factor [byte]
.equ fmOutExtra, 12                             | extra horizontal width [byte]
.equ fmOutAscent, 13                            | height above baseline [byte]
.equ fmOutDescent, 14                           | height below baseline [byte]
.equ fmOutWidMax, 15                            | maximum width of character [byte]
.equ fmOutLeading, 16                           | space between lines [byte]
.equ fmOutNumer, 18                             | point for numerators of scale factor [long]
.equ fmOutDenom, 22                             | point for denominators of scale factor [long]


| WidthTable data structure

.equ widTabData, 0                              | ARRAY[1..256] OF LONGINT character widths
.equ widTabFont, 1024                           | Handle	font record used to build table
.equ widthSExtra, 1028                          | LONGINT space extra used for table
.equ widthStyle, 1032                           | LONGINT extra due to style
.equ widthFID, 1036                             | INTEGER font family ID
.equ widthFSize, 1038                           | INTEGER font size request
.equ widthFace, 1040                            | INTEGER style (face) request
.equ widthDevice, 1042                          | INTEGER device requested
.equ widthVInScale, 1044                        | FIXED scale factors requested
.equ widthHInScale, 1048                        | FIXED scale factors requested
.equ widthAFID, 1052                            | INTEGER actual font family ID for table
.equ widthFHand, 1054                           | Handle family record used to build up table
.equ widthUsedFam, 1058                         | BOOLEAN used fixed point family widths
.equ widthAFace, 1059                           | BYTE actual face produced
.equ widthVOutput, 1060                         | INTEGER vertical scale output value
.equ widthHOutput, 1062                         | INTEGER horizontal scale output value
.equ widthVFactor, 1064                         | INTEGER vertical scale output value
.equ widthHFactor, 1066                         | INTEGER horizontal scale output value
.equ widthASize, 1068                           | INTEGER actual size of actual font used
.equ widTabSize, 1070                           | INTEGER total size of table

| Font Family Definition

.equ ffFlags, 0                                 | flags for family (word)
.equ ffFamID, 2                                 | family ID number (word)
.equ ffFirst, 4                                 | ASCII code of first character (word)
.equ ffLast, 6                                  | ASCII code of last character (word)
.equ ffAscent, 8                                | maximum ascent expressed for 1 pt (word)
.equ ffDescent, 10                              | maximum descent expressed for 1 pt (word)
.equ ffLeading, 12                              | maximum leading expressed for 1 pt (word)
.equ ffWidMax, 14                               | maximum widMax expressed for 1 pt (word)
.equ ffWTabOff, 16                              | offset to width table (long)
.equ ffKernOff, 20                              | offset to kerning table (long)
.equ ffStylOff, 24                              | offset to style mapping table (long)
.equ ffProperty, 28                             | style property info (12 words)
.equ ffIntl, 52                                 | reserved for international use (2 words)
.equ ffVersion, 56                              | FOND version number

| Font Characterization Table

.equ dpiVert, 0                                 | vertical dots per inch [word]
.equ dpiHoriz, 2                                | horizontal dots per inch [word]
.equ boldChr, 4                                 | bold characteristics [3 bytes]
.equ italChr, 7                                 | italic characteristics [3 bytes]
.equ outlineChr, 13                             | outline characteristics [3 bytes]
.equ shadowChr, 16                              | shadow characteristics [3 bytes]
.equ condChr, 19                                | condensed characteristics [3 bytes]
.equ extendChr, 22                              | extended characteristics [3 bytes]
.equ underChr, 25                               | underline characteristics [3 bytes]

| Globals

.equ CurFMFamily, 0x988                         | current font family
.equ CurFMSize, 0x98A                           | current font size
.equ CurFMFace, 0x98C                           | current font face
.equ CurFMNeedBits, 0x98D                       | boolean specifying whether it needs strike
.equ CurFMDevice, 0x98E                         | current font device
.equ CurFMNumer, 0x990                          | current numerator of scale factor
.equ CurFMDenom, 0x994                          | current denominator of scale factor

.equ FOutRec, 0x998                             | Font Manager output record

.equ FMDotsPerInch, 0x9B2                       | h,v dotsPerInch of current device
.equ FMStyleTab, 0x9B6                          | style heuristic table supplied by device

.equ RomFont0, 0x980                            | system font [handle]
.equ GotStrike, 0x986                           | Do we have the strike? [byte]


| Window Manager

| Window Definition Procedure Messages

.equ wDrawMsg, 0                                | draw yourself
.equ wHitMsg, 1                                 | hit test
.equ wCalcRgnMsg, 2                             | recalculate your regions
.equ wInitMsg, 3                                | initialize yourself
.equ wDisposeMsg, 4                             | dispose any private data
.equ wGrowMsg, 5                                | drag out grow outline
.equ wGIconMsg, 6                               | draw the grow icon

.equ OldStructure, 0x9E6                        | saved structure region [handle]
.equ OldContent, 0x9EA                          | saved content region [handle]
.equ SaveVisRgn, 0x9F2                          | temporarily saved visRegion [handle]
.equ CurDeKind, 0xA22                           | window kind of deactivated window [word]
.equ SaveUpdate, 0x9DA                          | Enable update accumulation? [word]

| Menu Manager

| Menu Definition Procedure Messages

.equ mDrawMsg, 0                                | draw yourself
.equ mChooseMsg, 1                              | select an item
.equ mSizeMsg, 2                                | calculate your size

| Menu Resource IDs

.equ textMenuProc, 0                            | standard text menu MDEF ID

.equ maxMenu, 0x60                              | maximum of 16*6 menus in menuBar
.equ mListSize, 0x66                            | menu list is 102 bytes long

.equ TheMenu, 0xA26                             | ID of hilited menu [word]
.equ SavedHandle, 0xA28                         | saved bits under a menu [handle]

| misc Menu stuff

.equ MrMacHook, 0xA2C                           | Mr. Macintosh hook [pointer]

| Control manager

| Control Definition Procedure Messages

.equ drawCtlMsg, 0                              | draw message
.equ hitCtlMsg, 1                               | hit test message
.equ calcCtlMsg, 2                              | calc region message
.equ newCtlMsg, 3                               | init message
.equ dispCtlMsg, 4                              | dispose any private data message
.equ posCtlMsg, 5                               | adjust indicator position message
.equ thumbCtlMsg, 6                             | calculate rectangles for thumb dragging
.equ dragCtlMsg, 7                              | custom drag message
.equ trackCtlMsg, 8                             | track yourself message


| Text Edit

.equ TEDoText, 0xA70                            | textEdit doText proc hook [pointer]
.equ TERecal, 0xA74                             | textEdit recalText proc hook [pointer]

| stage definition--packed 2 to a byte, 4 stages in a word

.equ volBits, 3                                 | number of beeps
.equ alBit, 4                                   | alert bit (put up box this time?)
.equ okDismissal, 8                             | bit for OK/Cancel default in each stage

| DialogList Data Structure Definitions

.equ dlgMaxIndex, 0                             | maximum index (=items-1) stored here


.equ SaveProc, 0xA90                            | address of Save failsafe procedure
.equ SaveSP, 0xA94                              | Safe SP for restart or save

| Package Manager

.equ FPState, 0xA4A                             | floating point state [6 bytes]
.equ App2Packs, 0xBC8                           | $BC8-$BE7 eight more package handles

| Resource Manager

.equ RMGRPerm, 0xBA4                            | (byte) - permission byte for OpenResFile

| Miscellaneous Constants

.equ screenRadius, 0x00100010                   | rounded corners for desk area

| Miscellaneous Globals

.equ IconBitmap, 0xA0E                          | bitmap used for plotting things
.equ TaskLock, 0xA62                            | re-entering SystemTask [byte]
.equ CloseOrnHook, 0xA88                        | hook for closing desk ornaments

| new MacApp stuff

.equ MAErrProc, 0xBE8                           | (long) MacApp error proc address
.equ MASuperTab, 0xBEC                          | (long) handle to MacApp superclass table






| Additional TERec field offsets (from MPW 1.0 TextEdit.h C struct):
| teSelRect and teClikLoc are defined above — see the TERec block
| around line 303 for the canonical definitions.
.equ teFontAsc, 0x1A                            | font ascent [word] (alias for teAscent)
.equ teSelPt, 0x1C                              | selection point [Point] (alias for teSelPoint)
.equ teCaretTime, 0x34                          | caret blink time [long] (alias for teCarTime)
.equ teCaretState, 0x38                         | caret on/off [word]
.equ teRecLines, 0x44                           | recalculate lines [word]
.equ teClikStuff, 0x46                          | click internal [word]
.equ teInPort, 0x52                             | port for drawing [GrafPtr]
.equ teHighHook, 0x56                           | highlighting hook [ProcPtr]
.equ teCaretHook, 0x5A                          | caret drawing hook [ProcPtr]
