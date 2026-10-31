
| -------------------------------------------------------------------------
| Resource_WDEF_0001 (resource-code-or-driver)
| ROM offsets +0x3920A..+0x395A4.
| ROM resource type=WDEF id=1 name=- attr=0x58; header +0x3920A, body +0x39212
| -------------------------------------------------------------------------
|
| =========================================================================
| WDEF 1 -- the rounded-corner window (rDocProc), Apple's "RDocProc"
| =========================================================================
| The window definition function for procIDs 16..31 (rDocProc + n,
| Inside Macintosh I-273): a document window without size box whose
| corners are rounded with FrameRoundRect, often used by desk
| accessories. The active window's whole title bar is inverted (white
| title on black), its go-away box is drawn left in the title bar.
| Andy Hertzfeld's RoundedWDEF.a ("written by Andy Hertzfeld Aug 4,
| 1982"); this is the black-and-white build: the header says version 4
| ("v4 7-Aug-85 EHB did variable system font height version") and the
| code has the 1986 changes up to <Cxxx/06Oct86> (DLD 22Aug86: go-away
| box drawn before the title bar is inverted; DAF: centered go-away
| mask), but not yet PortToMap (C424, 18Nov86: portBits.bounds is used
| directly), the locked title (C491, 08Dec86) or the message range
| check of the universal version 10 (C700, 26Jan87). The Mac II color
| code (IsColor, wctb colors, UpdateCPort) is not assembled.
|
| Calling convention (Pascal, Inside Macintosh I-299):
|   FUNCTION RDocProc(varCode: INTEGER; theWindow: WindowPtr;
|                     message: INTEGER; param: LONGINT): LONGINT;
| Stack after LINK A6: 0x14(A6) result, 0x12(A6) varCode, 0x0E(A6)
| theWindow, 0x0C(A6) message, 0x08(A6) param; the Window Manager
| (MOVEWINDOW_OK) passes varCode = procID mod 16. Registers in the
| message handlers: A3 = the window (a WindowPeek: GrafPort fields by
| offset, window fields by toolequ.inc name), D3 = param, D5 = radius
| table index (varCode DIV 2, times 4), D4/A4 scratch. The handlers run
| in the WMgrPort, which the entry sets (the caller's port is restored).
|
| Locals (WInfoRec, LINK A6,#-8), from GetFontInfo of the system font:
|   -8(A6) WAscent    ascent, raised for fonts shorter than 19 so that
|                     the title is centered vertically
|   -6(A6) WDescent   descent
|   -4(A6) WHeight    title bar height: ascent+descent+4 made odd,
|                     at least 19
|   -2(A6) WBoxDelta  (WHeight-13)/2, centers the go-away box
|
| Messages (WDEF1_GODOCPROC; the others, wNew 3 ... wDrawGIcon 6, do
| nothing):
|   0 wDraw      param 0: draw the frame, the title bar, the title and
|                (active window with go-away box) the box; param 4
|                (wInGoAway): toggle the box's highlight (XOR mask)
|   1 wHit       param = point (global): wInContent, wInGoAway (active
|                window with box only), wInDrag (rest of the title
|                bar), else wNoHit (the result is 0 on entry)
|   2 wCalcRgns  contRgn = portRect in global coordinates with round
|                bottom corners, structRgn = that rect grown by the
|                frame and the title bar, all corners round
|
| Corner diameters (WDEF1_RADIUSTABLE): Inside Macintosh I-273 gives
| rDocProc+0..7 = 16, 4, 6, 8, 10, 12, 20, 24. This version first
| shifts varCode right by one, so +0/+1 give 16, +2/+3 4, +4/+5 6 and
| +6/+7 8 -- 10..24 are out of reach. Apple's 1991 source: "<4> Remove
| a shift which prevented half of the variations from being used".
|
| Sources: Apple's RoundedWDEF.a (System 7.1 source; CR line endings;
| code compared routine by routine, Apple's labels with the WDEF1_
| prefix), Inside Macintosh I "The Window Manager" (I-273, I-297..301:
| messages wDrawMsg 0, wHitMsg 1, wCalcRgnMsg 2, hit codes wNoHit 0,
| wInContent 1, wInDrag 2, wInGoAway 4).
| -------------------------------------------------------------------------

| locals (WInfoRec)
.set WDEF1_WASCENT, -0x8                        | title ascent (word)
.set WDEF1_WDESCENT, -0x6                       | descent (word)
.set WDEF1_WHEIGHT, -0x4                        | title bar height (word)
.set WDEF1_WBOXDELTA, -0x2                      | go-away box offset (word)
.set WDEF1_RESULT, 0x14                         | function result (long)

Resource_WDEF_0001:
| ROM resource header: a Memory Manager block header, as in front of
| the data of a handle. The relative handle locates the resource's
| master pointer in the ROM zone (INITRESOURCES_CONT_2): 0x54 + 4 *
| its index in the ROM map's reference lists.
Resource_WDEF_0001_Header:
    ROM_RESOURCE WDEF_1                         | 8-byte resource header (include/romrsrc.inc)
| ----------------------------------------------------------
| _WDEF_1_ -- entry point and standard defproc header
| ----------------------------------------------------------
_WDEF_1_:
    BRA.B       WDEF1_ENTRY                     | skip the header
    .short      0x0000                          | flags word
    .long       0x57444546                      | resource type 'WDEF'
    .short      0x0001                          | resource ID 1
    .short      0x0004                          | version 4
| set up the WMgrPort and the title metrics, fetch the parameters,
| dispatch on the message
WDEF1_ENTRY:
    LINK        A6,#-0x8                        | frame for WInfoRec
    MOVEM.L     D3-D5/A3-A4,-(SP)               | save the work registers
    MOVEA.L     (A5),A0                         | A0 = QuickDraw globals
    MOVE.L      (A0),-(SP)                      | save thePort (restored at WDEF1_RETURN)
    MOVE.L      (WMgrPort).W,-(SP)              | draw in the WMgrPort
    _SetPort                                    | thePort := WMgrPort
| rdocprocs have asymmetric titles that are 19 high: fonts up to
| Chicago's size get 19, bigger ones an odd height for centering
    LEA.L       WDEF1_WASCENT(A6),A3            | A3 = WInfoRec
    MOVE.L      A3,-(SP)                        | point to it
    _GetFontInfo                                | ascent, descent, widMax, leading
    MOVE.W      (A3)+,D0                        | ascent
    ADD.W       (A3)+,D0                        | + descent; A3 -> WHeight
    ADDQ.W      #0x4,D0                         | + 4 = height
    BSET        #0x0,D0                         | make it odd for symmetry
    MOVEQ.L     #0x13,D1                        | 19
    CMP.W       D1,D0                           | at least 19?
    BGE.B       WDEF1_GOTHEIGHT                 | yes ->
    SUB.W       D0,D1                           | how much less than 19
    LSR.W       #0x1,D1                         | half of it
    ADD.W       D1,WDEF1_WASCENT(A6)            | lower the baseline to center a tiny font
    MOVEQ.L     #0x13,D0                        | height = 19
WDEF1_GOTHEIGHT:
    MOVE.W      D0,(A3)+                        | WHeight
    SUBI.W      #0xD,D0                         | - 13 (height of the go-away box)
    LSR.W       #0x1,D0                         | / 2
    MOVE.W      D0,(A3)                         | WBoxDelta
| fetch the parameters
    LEA.L       0x8(A6),A0                      | A0 -> param (the last pushed)
    MOVE.L      (A0)+,D3                        | D3 = param
    MOVE.W      (A0)+,D0                        | D0 = message
    MOVEA.L     (A0)+,A3                        | A3 = theWindow
    MOVE.W      (A0)+,D5                        | D5 = varCode (procID mod 16)
    LSR.W       #0x1,D5                         | / 2 (halves the variations, see the banner)
    ASL.W       #0x2,D5                         | * 4 = index into WDEF1_RADIUSTABLE
    CLR.L       (A0)                            | result := 0
    CMPI.W      #0x3,D0                         | draw, hit or calc?
    BGE.B       WDEF1_RETURN                    | no -> ignore the message
    ASL.W       #0x2,D0                         | * 4 = BRA.W entry
    JSR         WDEF1_GODOCPROC(PC,D0.W)        | call the handler through the table
WDEF1_RETURN:
    _SetPort                                    | restore the caller's port
    MOVEM.L     (SP)+,D3-D5/A3-A4               | restore the work registers
    UNLK        A6                              | drop the frame
    MOVEA.L     (SP)+,A0                        | A0 = return address
    ADDA.W      #0xC,SP                         | strip param, message, theWindow, varCode
    JMP         (A0)                            | return to the Window Manager
| GoDocProc: dispatch table, entries must be long branches
WDEF1_GODOCPROC:
    BRA.W       WDEF1_DRAWDOC                   | 0 wDraw
    BRA.W       WDEF1_HITDOC                    | 1 wHit
    BRA.W       WDEF1_CALCDOC                   | 2 wCalcRgns
WDEF1_DONEDOC:
    RTS                                         | (invisible window: nothing to draw)
| ----------------------------------------------------------
| DrawDoc (wDraw) -- draw the window frame. param 4 (wInGoAway)
| only toggles the go-away box (WDEF1_EORGOAWAY). Otherwise the
| title bar (TempRect, from the top of structRgn's box down by
| WHeight) is built as a region with round top corners, framed
| and erased; the title is drawn into it. An active window gets
| its go-away box drawn and the whole bar inverted (the box is
| drawn first, DLD 22Aug86). Finally structRgn is framed.
| ----------------------------------------------------------
WDEF1_DRAWDOC:
    TST.B       wVisible(A3)                    | is the window visible?
    BEQ.B       WDEF1_DONEDOC                   | no -> nothing to draw
    CMPI.W      #0x4,D3                         | param = wInGoAway?
    BEQ.W       WDEF1_EORGOAWAY                 | yes -> toggle the go-away box
    LEA.L       (TempRect).W,A0                 | A0 = TempRect
    MOVEA.L     structRgn(A3),A1                | the structure region
    MOVEA.L     (A1),A1                         | its pointer
    ADDQ.W      #0x2,A1                         | -> rgnBBox
    MOVE.L      (A1)+,(A0)+                     | TempRect.topLeft = box topLeft
    MOVE.L      (A1),(A0)                       | TempRect.botRight = box botRight
    MOVE.W      -0x4(A0),D0                     | top
    ADD.W       WDEF1_WHEIGHT(A6),D0            | + WHeight
    MOVE.W      D0,(A0)                         | bottom = top + title bar height
    CLR.L       -(SP)                           | room for the region
    _NewRgn                                     | allocate the title bar region
    MOVEA.L     (SP),A4                         | A4 = it (left on the stack: theRgn)
    PEA.L       (TempRect).W                    | theRect = the title bar
    BSR.W       WDEF1_GETRADPOINT               | D0 = corner diameters
    MOVE.L      D0,-(SP)                        | radius
    ST.B        -(SP)                           | topRound = true
    CLR.W       -(SP)                           | botRound = false
    BSR.W       WDEF1_MAKEROUNDREGION           | A4 = title bar with round top corners
    MOVE.L      A4,-(SP)                        | the title bar region
    _FrameRgn                                   | draw its outline
    MOVE.L      A4,-(SP)                        | the region
    MOVE.L      (OneOne).W,-(SP)                | (1,1)
    _InsetRgn                                   | inset it by one pixel
    MOVE.L      A4,-(SP)                        | the inside
    _EraseRgn                                   | erase it
WDEF1_DRAWTHETITLE:
    BSR.W       WDEF1_DOTITLESTRING             | draw the centered title
    TST.B       wHilited(A3)                    | active window?
    BEQ.B       WDEF1_DISPOSIT                  | no -> no box, no inversion
    TST.B       wGoAway(A3)                     | has it a go-away box?
    BEQ.B       WDEF1_DOHILITE                  | no ->
    MOVEQ.L     #0x0,D1                         | mode srcCopy (inverted below)
    LEA.L       WDEF1_GOAWAYSYMBOL(PC),A1       | the go-away box symbol
    BSR.B       WDEF1_PLOTGOAWAY                | draw it
WDEF1_DOHILITE:
    SUBQ.W      #0x1,(TempRect+4).W             | title bar bottom - 1 (keep the line under it)
    PEA.L       (TempRect).W                    | the title bar
    _InvertRect                                 | invert it: active window
WDEF1_DISPOSIT:
    MOVE.L      A4,-(SP)                        | the title bar region
    _DisposeRgn                                 | dispose of it
WDEF1_DRAWFRAME:
    MOVE.L      structRgn(A3),-(SP)             | the structure region
    _FrameRgn                                   | frame the body of the window
    RTS                                         | return from WDEF1_DRAWDOC
| ----------------------------------------------------------
| BuildTBarRect -- TempRect := the title bar: structRgn's box with
| bottom = top + WHeight and right - 1.
| Out: A0 = TempRect. Changes D0/A1.
| Called by: WDEF1_EORGOAWAY, WDEF1_PLOTGOAWAY, WDEF1_DOTITLESTRING
| ----------------------------------------------------------
WDEF1_BUILDTBARRECT:
    LEA.L       (TempRect).W,A0                 | A0 = TempRect
    MOVEA.L     structRgn(A3),A1                | the structure region
    MOVEA.L     (A1),A1                         | its pointer
    ADDQ.W      #0x2,A1                         | -> rgnBBox
    MOVE.L      (A1)+,(A0)                      | topLeft
    MOVE.L      (A1),0x4(A0)                    | botRight
    MOVE.W      (A0),D0                         | top
    ADD.W       WDEF1_WHEIGHT(A6),D0            | + WHeight
    MOVE.W      D0,0x4(A0)                      | bottom = top + title bar height
    SUBQ.W      #0x1,0x6(A0)                    | right - 1 (inset)
    RTS                                         | return from WDEF1_BUILDTBARRECT
| ----------------------------------------------------------
| EorGoAway (wDraw with param wInGoAway) -- toggle the go-away box
| of the active window by XORing its mask over it; falls into
| PlotGoAway.
| ----------------------------------------------------------
WDEF1_EORGOAWAY:
    BSR.B       WDEF1_BUILDTBARRECT             | TempRect = the title bar
    LEA.L       WDEF1_GOAWAYSYMBOL(PC),A1       | the go-away symbol ...
    ADDA.W      #0x20,A1                        | ... + 32 = the XOR mask
    MOVEQ.L     #0x2,D1                         | mode srcXor
| ----------------------------------------------------------
| PlotGoAway -- plot a 16x16 symbol at the go-away box position:
| 8 pixels right of the title bar's left edge, WBoxDelta-1 below
| its top.
| In:  A1 = the symbol's bits, D1 = transfer mode, TempRect = the
|      title bar. Out: TempRect = the title bar again (rebuilt).
| Changes D0-D1/A0-A1.
| ----------------------------------------------------------
WDEF1_PLOTGOAWAY:
    LEA.L       (TempRect).W,A0                 | A0 = TempRect
    MOVE.W      WDEF1_WBOXDELTA(A6),D0          | offset from the top to the box
    ADD.W       D0,(A0)                         | top + WBoxDelta
    SUBQ.W      #0x1,(A0)                       | - 1 to align the bitmap
    ADDQ.W      #0x8,0x2(A0)                    | left + 8 (margin)
    MOVE.L      (A0)+,(A0)                      | botRight = topLeft
    MOVEQ.L     #0x10,D0                        | 16
    ADD.W       D0,(A0)+                        | bottom = top + 16
    ADD.W       D0,(A0)                         | right = left + 16
    MOVE.W      D1,D0                           | D0 = mode for PlotSymbol
    MOVE.L      #0x100010,D1                    | (16,16), not used by PlotSymbol
    BSR.B       WDEF1_PLOTSYMBOL                | plot it into TempRect
    BSR.B       WDEF1_BUILDTBARRECT             | rebuild TempRect = the title bar
    RTS                                         | return from WDEF1_PLOTGOAWAY
| ----------------------------------------------------------
| PlotSymbol -- CopyBits a 16x16 symbol into TempRect of the
| current port, through the BitMap record IconBitmap ($A0E);
| bounds.topLeft is assumed to be (0,0) already.
| In:  A1 = the bits (2 bytes per row), D0 = transfer mode.
| Changes D0-D2/A0-A1.
| ----------------------------------------------------------
WDEF1_PLOTSYMBOL:
    LEA.L       (IconBitmap).W,A0               | A0 = the source BitMap
    MOVE.L      A1,(A0)                         | baseAddr = the symbol
    MOVE.W      #0x2,0x4(A0)                    | rowBytes = 2
    MOVE.L      #0x100010,0xA(A0)               | bounds.botRight = (16,16)
    MOVE.L      A0,-(SP)                        | srcBits = IconBitmap
    MOVEA.L     (A5),A1                         | QuickDraw globals
    MOVEA.L     (A1),A1                         | thePort
    PEA.L       0x2(A1)                         | dstBits = thePort's portBits
    PEA.L       0x6(A0)                         | srcRect = IconBitmap.bounds
    PEA.L       (TempRect).W                    | dstRect = TempRect
    MOVE.W      D0,-(SP)                        | transfer mode
    CLR.L       -(SP)                           | no mask region
    _CopyBits                                   | copy the symbol
    RTS                                         | return from WDEF1_PLOTSYMBOL
| ----------------------------------------------------------
| DoTitleString -- draw the window title centered in the title
| bar (TempRect), at least 28 pixels from its left edge when the
| window has a go-away box; baseline WAscent+2 below the top.
| The title handle is not locked while DrawString runs (Apple's
| C491, 08Dec86: "Locked title string before drawing it (OLD
| BUG!)").
| Out: TempRect = the title bar. Changes D0-D3/A0-A1.
| Called by: WDEF1_DRAWDOC
| ----------------------------------------------------------
WDEF1_DOTITLESTRING:
    BSR.W       WDEF1_BUILDTBARRECT             | TempRect = the title bar
    MOVE.W      (TempRect+6).W,D3               | right
    SUB.W       (TempRect+2).W,D3               | - left = width of the bar
    SUB.W       wTitleWidth(A3),D3              | - width of the title
    ASR.W       #0x1,D3                         | / 2 = indent of the centered title
    TST.B       wGoAway(A3)                     | go-away box?
    BEQ.B       WDEF1_TITLEX                    | no -> keep the indent
    TST.W       D3                              | title wider than the bar?
    BMI.B       WDEF1_MINMARGIN                 | yes -> pin at 28
    CMPI.W      #0x1C,D3                        | at least 28 pixels?
    BGT.B       WDEF1_TITLEX                    | yes ->
WDEF1_MINMARGIN:
    MOVEQ.L     #0x1C,D3                        | indent = 28 (clear of the box)
WDEF1_TITLEX:
    ADD.W       (TempRect+2).W,D3               | + left = x of the title
    MOVE.W      D3,-(SP)                        | h for MoveTo
    MOVE.W      (TempRect).W,D0                 | top of the bar
    ADD.W       WDEF1_WASCENT(A6),D0            | + ascent
    ADDQ.W      #0x2,D0                         | + 2 of white space = baseline
    MOVE.W      D0,-(SP)                        | v for MoveTo
    _MoveTo                                     | pen to the title's start
    MOVEA.L     wTitleHandle(A3),A0             | the title handle (not locked)
    MOVE.L      (A0),-(SP)                      | the title string
    _DrawString                                 | draw it
    RTS                                         | return from WDEF1_DOTITLESTRING
| ----------------------------------------------------------
| GetRadPoint -- the corner diameters selected by varCode.
| In:  D5 = table index (WDEF1_ENTRY). Out: D0 = (height, width).
| Called by: WDEF1_DRAWDOC, WDEF1_GOMAKERGN
| ----------------------------------------------------------
WDEF1_GETRADPOINT:
    MOVE.L      WDEF1_RADIUSTABLE(PC,D5.W),D0   | D0 = diameters for this variation
    RTS                                         | return from WDEF1_GETRADPOINT
| RadiusTable: ovalHeight/ovalWidth for FrameRoundRect
WDEF1_RADIUSTABLE:
    .long       0x00100010                      | (16,16): varCode 0, 1
    .long       0x00040004                      | (4,4):   varCode 2, 3
    .long       0x00060006                      | (6,6):   varCode 4, 5
    .long       0x00080008                      | (8,8):   varCode 6, 7
    .long       0x000A000A                      | (10,10): varCode 8, 9 (not an rDocProc)
    .long       0x000C000C                      | (12,12): varCode 10, 11
    .long       0x00140014                      | (20,20): varCode 12, 13
    .long       0x00180018                      | (24,24): varCode 14, 15
| ----------------------------------------------------------
| MakeRoundRegion -- make a round-rect region; either half can be
| squared off.
|   PROCEDURE MakeRoundRegion(theRgn: RgnHandle; theRect: Rect;
|                  radius: Point; topRound, botRound: BOOLEAN);
| (pushed in this order; 16 bytes, removed on return). Both flags
| false or radius 0: a plain rect. Else the FrameRoundRect outline
| is recorded; a false botRound (or topRound) squares the bottom
| (top) by uniting it with an 8-pixel-high rect (in ToolScratch).
| Changes D0-D2/A0-A1.
| Called by: WDEF1_DRAWDOC, WDEF1_GOMAKERGN
| ----------------------------------------------------------
WDEF1_MAKEROUNDREGION:
    LINK        A6,#0x0                         | frame for the parameters
    MOVE.L      A3,-(SP)                        | save A3 (the window)
    TST.L       0x8(A6)                         | botRound and topRound both false?
    BEQ.B       WDEF1_PLAINRECT                 | yes -> just a rect
    TST.L       0xC(A6)                         | radius 0?
    BNE.B       WDEF1_COMPLEXRECT               | no -> a round one
WDEF1_PLAINRECT:
    MOVE.L      0x14(A6),-(SP)                  | theRgn
    MOVE.L      0x10(A6),-(SP)                  | theRect
    _RectRgn                                    | rectangular region
    BRA.B       WDEF1_MMRDONE                   | done
| record a round rect, then square up the top or the bottom
WDEF1_COMPLEXRECT:
    _HidePen                                    | record without drawing
    _OpenRgn                                    | start recording
    MOVE.L      0x10(A6),-(SP)                  | theRect
    MOVE.L      0xC(A6),-(SP)                   | radius
    _FrameRoundRect                             | the rounded outline
    MOVE.L      0x14(A6),-(SP)                  | theRgn
    _CloseRgn                                   | theRgn = the round rect
    _ShowPen                                    | drawing on again
    MOVEA.L     0x10(A6),A0                     | A0 = theRect
    TST.W       0x8(A6)                         | botRound?
    BNE.B       WDEF1_CHECKTROUND               | yes -> maybe the top
    MOVE.W      0x4(A0),D1                      | D1 = bottom
    MOVE.W      D1,D0                           | D0 = bottom ...
    SUBQ.W      #0x8,D0                         | ... - 8
    BRA.B       WDEF1_SQUAREIT                  | square the bottom 8 rows
WDEF1_CHECKTROUND:
    TST.W       0xA(A6)                         | topRound?
    BNE.B       WDEF1_MMRDONE                   | yes -> both round, done
    MOVE.W      (A0),D0                         | D0 = top
    MOVE.W      D0,D1                           | D1 = top ...
    ADDQ.W      #0x8,D1                         | ... + 8: square the top 8 rows
| ToolScratch := (D0, theRect.left, D1, theRect.right), unite it
WDEF1_SQUAREIT:
    LEA.L       (ToolScratch).W,A1              | A1 = ToolScratch
    MOVE.W      D0,(A1)+                        | top
    MOVE.W      0x2(A0),(A1)+                   | left = theRect.left
    MOVE.W      D1,(A1)+                        | bottom
    MOVE.W      0x6(A0),(A1)                    | right = theRect.right
    CLR.L       -(SP)                           | room for the region
    _NewRgn                                     | a temporary region
    MOVEA.L     (SP),A3                         | A3 = it (stays on the stack)
    PEA.L       (ToolScratch).W                 | the strip
    _RectRgn                                    | temporary region = the strip
    MOVE.L      0x14(A6),-(SP)                  | srcRgnA = theRgn
    MOVE.L      A3,-(SP)                        | srcRgnB = the strip
    MOVE.L      0x14(A6),-(SP)                  | dstRgn = theRgn
    _UnionRgn                                   | square up the corners
    MOVE.L      A3,-(SP)                        | the temporary region
    _DisposeRgn                                 | dispose of it
WDEF1_MMRDONE:
    MOVEA.L     (SP)+,A3                        | restore A3
    UNLK        A6                              | drop the frame
    MOVEA.L     (SP)+,A0                        | A0 = return address
    ADDA.W      #0x10,SP                        | strip the 16 bytes of parameters
    JMP         (A0)                            | return
| ----------------------------------------------------------
| HitDoc (wHit) -- D3 = the mouse point (global). wInContent in
| contRgn; in structRgn and in contRgn's box extended up by
| WHeight (the title bar): wInGoAway on the active window's box
| (h 8..18 from the left edge, the box's 11 rows), else wInDrag;
| on the frame or outside: 0 (wNoHit).
| ----------------------------------------------------------
WDEF1_HITDOC:
    MOVEQ.L     #0x10,D4                        | 16 (not used: the document WDEF's grow box)
    CLR.W       -(SP)                           | room for the result
    MOVE.L      D3,-(SP)                        | the point
    MOVE.L      contRgn(A3),-(SP)               | the content region
    _PtInRgn                                    | in the content?
    TST.B       (SP)+                           | well?
    BEQ.B       WDEF1_NOTINCONTENT              | no -> check the title bar
    MOVEQ.L     #0x1,D0                         | wInContent
    BRA.B       WDEF1_DONEHITDOC                | return it
| not in the content: in the window at all?
WDEF1_NOTINCONTENT:
    CLR.W       -(SP)                           | room for the result
    MOVE.L      D3,-(SP)                        | the point
    MOVE.L      structRgn(A3),-(SP)             | the structure region
    _PtInRgn                                    | in the window?
    TST.B       (SP)+                           | well?
    BEQ.B       WDEF1_DONEHIT1                  | no -> wNoHit
    CLR.W       -(SP)                           | room for the result
    MOVE.L      D3,-(SP)                        | the point
    MOVEA.L     contRgn(A3),A4                  | the content region
    MOVEA.L     (A4),A4                         | its pointer
    ADDQ.W      #0x2,A4                         | A4 -> its rgnBBox
    MOVE.W      WDEF1_WHEIGHT(A6),D0            | title bar height
    SUB.W       D0,(A4)                         | box top - WHeight: content + title bar
    MOVE.L      A4,-(SP)                        | that rect
    _PtInRect                                   | in the title bar (or the content)?
    MOVE.W      WDEF1_WHEIGHT(A6),D0            | title bar height
    ADD.W       D0,(A4)                         | restore the box top
    TST.B       (SP)+                           | well?
    BEQ.B       WDEF1_DONEHIT1                  | no -> on the frame: wNoHit
| in the title bar: is it the go-away box (active windows only)?
    TST.B       wGoAway(A3)                     | has it a go-away box?
    BEQ.B       WDEF1_ITSINDRAG                 | no -> drag
    TST.B       wHilited(A3)                    | active?
    BEQ.B       WDEF1_ITSINDRAG                 | no -> drag
    MOVE.W      D3,D0                           | h (global)
    ADD.W       0xA(A3),D0                      | + portBits.bounds.left = local h
    SUB.W       0x12(A3),D0                     | - portRect.left = from the window's left edge
    CMPI.W      #0x12,D0                        | more than 18?
    BGT.B       WDEF1_ITSINDRAG                 | yes -> drag
    SUBQ.W      #0x8,D0                         | less than 8?
    BMI.B       WDEF1_ITSINDRAG                 | yes -> drag
    MOVE.L      D3,D0                           | now the vertical:
    SWAP.W      D0                              | v (global)
    ADD.W       0x8(A3),D0                      | + portBits.bounds.top = local v
    SUB.W       0x10(A3),D0                     | - portRect.top: 0 = bottom of the title bar
    ADD.W       WDEF1_WBOXDELTA(A6),D0          | below the box?
    BPL.B       WDEF1_ITSINDRAG                 | yes -> drag
    ADDI.W      #0xB,D0                         | in the box's 11 rows?
    BMI.B       WDEF1_ITSINDRAG                 | no (above it) -> drag
    MOVEQ.L     #0x4,D0                         | wInGoAway
    BRA.B       WDEF1_DONEHITDOC                | return it
| in the title bar, but not on the go-away box: drag
| Called by: WDEF1_HITDOC (6 branches: no box, inactive window, h or v
| outside the box)
WDEF1_ITSINDRAG:
    MOVEQ.L     #0x2,D0                         | wInDrag
WDEF1_DONEHITDOC:
    MOVE.L      D0,WDEF1_RESULT(A6)             | function result
WDEF1_DONEHIT1:
    RTS                                         | return from WDEF1_HITDOC
| ----------------------------------------------------------
| CalcDoc (wCalcRgns) -- TempRect = portRect in global coordinates
| (offset by -portBits.bounds.topLeft). contRgn = TempRect with
| round bottom and square top corners; structRgn = TempRect grown
| by 1 (the frame) and up by WHeight-1 (the title bar), all four
| corners round.
| ----------------------------------------------------------
WDEF1_CALCDOC:
    LEA.L       (TempRect).W,A0                 | A0 = TempRect
    MOVE.L      A0,-(SP)                        | for OffsetRect below
    MOVE.L      0x10(A3),(A0)+                  | portRect.topLeft
    MOVE.L      0x14(A3),(A0)                   | portRect.botRight
    MOVE.L      0x8(A3),-(SP)                   | portBits.bounds.topLeft ...
    NEG.W       0x2(SP)                         | ... negated (h)
    NEG.W       (SP)                            | ... (v) = local to global offset
    _OffsetRect                                 | TempRect in global coordinates
    MOVEA.L     contRgn(A3),A0                  | A0 = the content region
    CLR.W       D1                              | topRound = false
    BSR.B       WDEF1_GOMAKERGN                 | contRgn = round bottom corners
    PEA.L       (TempRect).W                    | the rect
    MOVE.L      (MinusOne).W,-(SP)              | (-1,-1)
    _InsetRect                                  | grow it by one pixel: the frame
    MOVE.W      WDEF1_WHEIGHT(A6),D0            | title bar height
    SUBQ.W      #0x1,D0                         | - 1 (shares the content's top line)
    SUB.W       D0,(TempRect).W                 | top of the structure region
    MOVEQ.L     #0x1,D1                         | topRound = true
    MOVEA.L     structRgn(A3),A0                | A0 = the structure region
| ----------------------------------------------------------
| GoMakeRgn -- MakeRoundRegion(A0, TempRect, radius, D1, TRUE).
| In:  A0 = region, D1.W = topRound (botRound is always true).
| Called by: WDEF1_CALCDOC (and falls in from it)
| ----------------------------------------------------------
WDEF1_GOMAKERGN:
    MOVE.L      A0,-(SP)                        | theRgn
    PEA.L       (TempRect).W                    | theRect = TempRect
    BSR.W       WDEF1_GETRADPOINT               | D0 = corner diameters
    MOVE.L      D0,-(SP)                        | radius
    MOVE.W      D1,-(SP)                        | topRound
    ST.B        -(SP)                           | botRound = true
    BSR.W       WDEF1_MAKEROUNDREGION           | make the region
    RTS                                         | return from WDEF1_GOMAKERGN
| GoAwaySymbol: the go-away box, 16x16, drawn srcCopy ...
WDEF1_GOAWAYSYMBOL:
    .short      0x0000                          | ................
    .short      0x0000                          | ................
    .short      0x7FF0                          | .###########....
    .short      0x4010                          | .#.........#....
    .short      0x4010                          | .#.........#....
    .short      0x4010                          | .#.........#....
    .short      0x4010                          | .#.........#....
    .short      0x4010                          | .#.........#....
    .short      0x4010                          | .#.........#....
    .short      0x4010                          | .#.........#....
    .short      0x4010                          | .#.........#....
    .short      0x4010                          | .#.........#....
    .short      0x7FF0                          | .###########....
    .short      0x0000                          | ................
    .short      0x0000                          | ................
    .short      0x0000                          | ................
| ... and the mask XORed over it to show the box pressed (Cxxx
| 06Oct86: "brand-new, centered mask")
WDEF1_GOAWAYMASK:
    .short      0x0000                          | ................
    .short      0x0000                          | ................
    .short      0x7FF0                          | .###########....
    .short      0x4210                          | .#....#....#....
    .short      0x5250                          | .#.#..#..#.#....
    .short      0x4A90                          | .#..#.#.#..#....
    .short      0x4010                          | .#.........#....
    .short      0x5DD0                          | .#.###.###.#....
    .short      0x4010                          | .#.........#....
    .short      0x4A90                          | .#..#.#.#..#....
    .short      0x5250                          | .#.#..#..#.#....
    .short      0x4210                          | .#....#....#....
    .short      0x7FF0                          | .###########....
    .short      0x0000                          | ................
    .short      0x0000                          | ................
    .short      0x0000                          | ................
    ROM_RESOURCE_END WDEF_1                     | end of the data: pads to even, sets the sizes

