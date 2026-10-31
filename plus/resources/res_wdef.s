| =========================================================================
| WDEF 0 -- the standard window definition function ("DocumentProc")
| =========================================================================
| Andy Hertzfeld's StandardWDEF.a, version 5 ("v5 29-Aug-85 EHB Variant 8
| knows how to zoom", the zoom box of 1985). The SE ROM has the same code
| (src/se/resources/resource_wdef_0000.s) with two changes about the
| port: its entry calls _SetPort where this one stores the WMgrPort into
| thePort directly, and its wDrawGIcon sets the WMgrPort again before it
| returns (here the handler returns with the window's port set; the exit
| restores the caller's port in both). Not yet in this version: the 1986
| Mac II changes (color, PortToMap, the locked title of C491) and the
| later rewrite (StandardWDEF.a of System 7, DeviceLoop and shaded
| windows).
|
| Window types (procID 0..15; varCode = procID mod 16, Inside Macintosh
| I-273 and IV-49):
|   bits 0-1 (D5)   0 documentProc (title bar, go-away box, grow box),
|                   1 dBoxProc (frame, 2-pixel border 2 pixels inside),
|                   2 plainDBox (frame), 3 altDBoxProc (2-pixel shadow)
|   bit 2           no grow box (noGrowDocProc = 4)
|   bit 3           zoom box (variation code 8; 12 without grow box);
|                   needs a 128K or newer ROM (ROM85) and WStateData
| Messages (WDEF_JMPTABLE, Inside Macintosh I-299..301, IV-50): 0 wDraw
| (param 0: whole frame; 4: toggle the go-away box; 5: toggle the zoom
| box), 1 wHit (result wNoHit 0, wInContent 1, wInDrag 2, wInGrow 3,
| wInGoAway 4, wInZoomIn 5, wInZoomOut 6), 2 wCalcRgns, 3 wNew (allocate
| WStateData for a zoom window), 4 wDispose, 5 wGrow (draw the grow
| outline in the rect param points to), 6 wDrawGIcon (size box and
| scroll bar lines).
| WStateData (the window's wDataHandle, 16 bytes, Inside Macintosh
| IV-49): userState rect at 0, stdState rect at 8 (global coordinates);
| wZoom (IV-49's "spareFlag") is set once wNew has allocated it.
|
| Calling convention (Pascal):
|   FUNCTION MyWindow(varCode: INTEGER; theWindow: WindowPtr;
|                     message: INTEGER; param: LONGINT): LONGINT;
| Stack after LINK A6: 0x14(A6) result, 0x12(A6) varCode, 0x0E(A6)
| theWindow, 0x0C(A6) message, 0x08(A6) param.
| Locals (filled at entry):
|   -0x8(A6) title ascent (raised to center fonts shorter than 19)
|   -0x6(A6) descent
|   -0x4(A6) title bar height (= D7)
|   -0x2(A6) offset of the go-away and zoom boxes: (height-13)/2
|   -0xC(A6) scratch region handle (saved clip, shadow region)
| Registers in the handlers: D3 = param, D5 = varCode AND 3 (window
| style), D6 = varCode, D7 = title bar height (at least 19, odd),
| A3 = the window (GrafTypes names for its GrafPort fields, toolequ.inc
| names for the window fields). The handlers draw in the WMgrPort.
|
| Apple's routine names (StandardWDEF.a) where they help: WDEF_TITLE_RECT
| = BuildTBarRect, WDEF_CHECK_ZOOM_ST = IsItSmall, WDEF_PT_IN_EXPANDED =
| ChkPoint, WDEF_COPY_PORTRECT = GetRect, WDEF_DRAW = DrawDoc, WDEF_HIT =
| HitDoc, WDEF_CALCRGNS = CalcDoc, WDEF_GROW = GrowDoc, WDEF_GICON =
| DrawGIcon, WDEF_DRAW_TITLE = DoTitleString.
| -------------------------------------------------------------------------

| resource header
    ROM_RESOURCE WDEF_0                         | 8-byte resource header (include/romrsrc.inc)
_WDEF_0_:
        BRA.B   WDEF_ENTRY                      | branch to start
  .byte 0x00,0x00                               | flags: unused
  .ascii "WDEF"                                 | resource type identifier
  .byte 0x00,0x00,0x00,0x05                     | resource ID = 0, version = 5

| ----------------------------------------------------------
| WDEF main entry - set up stack frame, compute title bar
| height from current font metrics, dispatch to handler
| ----------------------------------------------------------
WDEF_ENTRY:
        LINK    A6,#-0xC                        | allocate 12 bytes for locals
        MOVEM.L D3-D7/A1-A4,-(SP)               | save registers
        MOVE.L  (A5),A0                         | deref QD globals
        MOVE.L  (A0),-(SP)                      | save current port on stack
        MOVE.L  (WMgrPort).w,(A0)               | thePort := WMgrPort (the SE calls _SetPort)
        LEA.L   -0x8(A6),A3                     | A3 -> FontInfo local
        MOVE.L  A3,-(SP)                        | push FontInfo pointer
        _GetFontInfo                            | get system font metrics
        MOVE    (A3)+,D7                        | D7 = ascent
        ADD     (A3)+,D7                        | D7 += descent
        ADDQ.W  #0x4,D7                         | add 4 pixels padding
        BSET    #0x0,D7                         | round up to odd number
        MOVEQ.L #0x13,D1                        | minimum title bar = 19 pixels
        CMP     D1,D7                           | is height < 19?
        BGE.B   WDEF_HEIGHT_OK                  | tall enough already
        SUB     D7,D1                           | center short font vertically
        LSR     #0x1,D1                         | divide difference by 2
        ADD     D1,-0x8(A6)                     | adjust ascent for centering
        MOVEQ.L #0x13,D7                        | enforce 19-pixel minimum
WDEF_HEIGHT_OK:
        MOVE    D7,(A3)+                        | store title bar height
        MOVE    D7,D0                           | copy height to calculate icon offset
        SUBI    #0xD,D0                         | D0 = height - 13
        LSR     #0x1,D0                         | vertical center for icons
        MOVE    D0,(A3)                         | store icon centering offset
        CLR.L   -(SP)                           | space for region handle
        _NewRgn                                 | allocate scratch region
        MOVE.L  (SP)+,-0xC(A6)                  | save in local
        LEA.L   0x8(A6),A0                      | A0 -> stacked parameters
        MOVE.L  (A0)+,D3                        | D3 = param (long)
        MOVE    (A0)+,D0                        | D0 = message selector
        MOVE.L  (A0)+,A3                        | A3 = WindowRecord ptr
        MOVE    (A0)+,D5                        | D5 = varCode
        MOVE    D5,D6                           | D6 = full varCode (keep zoom bit)
        ANDI    #0x3,D5                         | D5 = low 2 bits only (style)
        CLR.L   (A0)                            | clear return value
        ADD     D0,D0                           | word index into jump table
        LEA.L   WDEF_JMPTABLE(PC),A0            | A0 -> jump table
        ADDA    WDEF_JMPTABLE(PC,D0.W),A0       | compute handler address
        JSR     (A0)                            | call the message handler (no range check)
        MOVE.L  -0xC(A6),-(SP)                  | push scratch region handle
        _DisposeRgn                             | free scratch region
        _SetPort                                | restore saved port
        MOVEM.L (SP)+,D3-D7/A1-A4               | restore registers
        UNLK    A6                              | destroy stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xC,SP                         | strip 4 params (12 bytes)
        JMP     (A0)                            | return to caller

| Jump table - word offsets for each message handler
WDEF_JMPTABLE:
  .short WDEF_DRAW-WDEF_JMPTABLE                | 0 wDraw
  .short WDEF_HIT-WDEF_JMPTABLE                 | 1 wHit
  .short WDEF_CALCRGNS-WDEF_JMPTABLE            | 2 wCalcRgns
  .short WDEF_NEW-WDEF_JMPTABLE                 | 3 wNew
  .short WDEF_DISPOSE-WDEF_JMPTABLE             | 4 wDispose
  .short WDEF_GROW-WDEF_JMPTABLE                | 5 wGrow
  .short WDEF_GICON-WDEF_JMPTABLE               | 6 wDrawGIcon

| ----------------------------------------------------------
| wNew handler - initialize zoom box data if requested
| varCode bit 3 means zoomable; allocates 16-byte WStateData:
| bytes 0-7 = userState rect (from current portRect)
| bytes 8-15 = stdState rect (the screen inset by 3, below the
| menu bar and the title bar); sets wZoom only if this worked
WDEF_NEW:
        BTst    #0x3,D6                         | zoom box requested (varCode bit 3)?
        BEQ.B   WDEF_NEW_DONE                   | no -> done
        CLR.B   wZoom(A3)                       | clear wZoom flag initially
        TST     (ROM85).w                       | check for 128K+ ROM
        BMI.B   WDEF_NEW_DONE                   | old ROM -> no zoom support
        MOVEQ.L #0x10,D0                        | 16 bytes for WStateData
        _NewHandleClear                         | allocate zoom state record
        BNE.B   WDEF_NEW_DONE                   | allocation failed -> done
        ADDQ.B  #0x1,wZoom(A3)                  | set wZoom = true
        MOVE.L  A0,wDataHandle(A3)              | store in wDataHandle
        MOVE.L  (A0),A4                         | deref WStateData
        ADDQ.W  #0x8,A4                         | A4 -> stdState rect
        MOVE.L  (A5),A1                         | deref QD globals
        MOVE.L  SCREENBITS+BOUNDS(A1),(A4)+     | copy screenBits.bounds.topLeft
        MOVE.L  SCREENBITS+BOUNDS+4(A1),(A4)+   | copy screenBits.bounds.botRight
        MOVEQ.L #0x3,D0                         | inset stdState by 3 pixels
        SUB     D0,-(A4)                        | right -= 3
        SUB     D0,-(A4)                        | bottom -= 3
        ADD     D0,-(A4)                        | left += 3
        ADD     D0,-(A4)                        | top += 3
        ADD     D7,(A4)                         | top += title bar height (room for the menu bar)
        ADD     D7,(A4)                         | and once more for the window's own title bar
        MOVE.L  (A0),A4                         | re-deref -> userState rect

| ----------------------------------------------------------
| WDEF_COPY_PORTRECT (Apple: GetRect) - copy portRect to the rect
| at A4 and convert it to global coordinates by negating the
| portBits.bounds origin. Used to snapshot the window's position.
| Changes D0-D2/A0-A1.
| Called by: WDEF_NEW (falls in), WDEF_CHECK_ZOOM_ST (2)
WDEF_COPY_PORTRECT:
        MOVE.L  A4,-(SP)                        | the rect, for OffsetRect
        MOVE.L  PORTRECT(A3),(A4)               | copy portRect.topLeft
        MOVE.L  PORTRECT+BOTTOM(A3),0x4(A4)     | copy portRect.botRight
        MOVE.L  PORTBOUNDS(A3),-(SP)            | push portBits.bounds.topLeft
        NEG     (SP)                            | negate top (local->global)
        NEG     0x2(SP)                         | negate left
        _OffsetRect                             | convert rect to global coords
WDEF_NEW_DONE:
        RTS                                     | return from WDEF_NEW / WDEF_COPY_PORTRECT

| ----------------------------------------------------------
| WDEF_CHECK_ZOOM_ST (Apple: IsItSmall) - is the window in its
| standard (zoomed-out) state? The window counts as "big" if both
| corners of its global portRect are within 7 pixels of the
| corners of stdState. If not, the current rect is saved as the
| new userState.
| Out: EQ = at stdState; NE (D0 = 1) = elsewhere (userState updated).
| Changes D0-D2/A0-A2/A4.
| Called by: WDEF_HIT_ZOOM, WDEF_CALCRGNS
WDEF_CHECK_ZOOM_ST:
        SUBQ.W  #0x8,SP                         | local 8-byte rect on stack
        MOVE.L  SP,A4                           | A4 -> local rect
        BSR.B   WDEF_COPY_PORTRECT              | local rect = portRect, global
        MOVE.L  wDataHandle(A3),A0              | the WStateData handle
        MOVE.L  (A0),A2                         | A2 -> WStateData
        ADDQ.W  #0x8,A2                         | A2 -> stdState rect
        BSR.B   WDEF_PT_IN_EXPANDED             | topLeft within 7 of stdState's?
        BNE.B   WDEF_STATE_CHANGED              | no -> not zoomed out
        BSR.B   WDEF_PT_IN_EXPANDED             | botRight within 7 of stdState's?
        BEQ.B   WDEF_STATE_DONE                 | yes -> at stdState (EQ)
WDEF_STATE_CHANGED:
        MOVE.L  wDataHandle(A3),A0              | the WStateData handle
        MOVE.L  (A0),A4                         | A4 -> userState rect
        BSR.B   WDEF_COPY_PORTRECT              | userState = current portRect, global
        MOVEQ.L #0x1,D0                         | return NE = not at stdState
WDEF_STATE_DONE:
        ADDQ.W  #0x8,SP                         | free local rect
        RTS                                     | return from WDEF_CHECK_ZOOM_ST

| ----------------------------------------------------------
| WDEF_PT_IN_EXPANDED (Apple: ChkPoint) - is the point at (A4)
| within 7 pixels of the point at (A2)? Called twice in a row:
| first for topLeft, then for botRight.
| In:  A2 -> point of stdState, A4 -> point of the current rect;
|      both are advanced by 4.
| Out: EQ if within 7 pixels, NE if not. Changes D0-D2/A0-A1.
| Called by: WDEF_CHECK_ZOOM_ST (2)
WDEF_PT_IN_EXPANDED:
        MOVE.L  (A2),-(SP)                      | an empty rect at the stdState point ...
        MOVE.L  (A2)+,-(SP)                     | ... (pushed twice)
        MOVE.L  SP,-(SP)                        | that rect
        MOVE.L  #0xFFF9FFF9,-(SP)               | inset by -7,-7 (expand 7px)
        _InsetRect                              | 14x14 rect around the point
        CLR     -(SP)                           | room for the result
        MOVE.L  (A4)+,-(SP)                     | the point of the current rect
        PEA.L   0x6(SP)                         | the 14x14 rect
        _PtInRect                               | test if point is in expanded rect
        SUBQ.B  #0x1,(SP)                       | TRUE (1) -> 0, FALSE (0) -> 0xFF
        MOVE.B  (SP)+,D0                        | D0 = 0 (EQ: close) or 0xFF (NE)
        ADDQ.W  #0x8,SP                         | pop temp rect
        RTS                                     | return from WDEF_PT_IN_EXPANDED

| ----------------------------------------------------------
| WDEF_HAS_ZOOM - test if window has zoom box capability
| Returns NE if varCode bit 3 set AND wZoom set (WStateData
| allocated by wNew), else EQ.
| Called by: WDEF_DISPOSE, WDEF_DRAW, WDEF_DRAW_ZOOM, WDEF_TOGGLE_BOX, WDEF_TITLE_ABS (and 2 more)
WDEF_HAS_ZOOM:
        BTst    #0x3,D6                         | varCode has zoom bit?
        BEQ     WDEF_HAS_ZOOM_RTS               | no -> return EQ
        TST.B   wZoom(A3)                       | wZoom flag set?
WDEF_HAS_ZOOM_RTS:
        RTS                                     | return from WDEF_HAS_ZOOM

| ----------------------------------------------------------
| wDispose handler - free WStateData if zoom box allocated
WDEF_DISPOSE:
        BSR.B   WDEF_HAS_ZOOM                   | has zoom data?
        BEQ.B   WDEF_DISPOSE_DONE               | no -> done
        MOVE.L  wDataHandle(A3),A0              | get wDataHandle
        _DisposeHandle                          | free WStateData
WDEF_DISPOSE_DONE:
        RTS                                     | return from WDEF_DISPOSE

| ----------------------------------------------------------
| wDraw handler (Apple: DrawDoc) - draw window frame based on
| varCode/param
| param 0: draw entire frame (border, title bar, close/zoom)
| param 4: toggle close box highlight
| param 5: toggle zoom box highlight
WDEF_DRAW:
        TST.B   wVisible(A3)                    | wVisible?
        BEQ     WDEF_DRAW_RTS                   | invisible -> do nothing
        CMPI    #0x4,D3                         | param >= 4?
        BGE     WDEF_TOGGLE_BOX                 | yes -> toggle close/zoom box
        _PenNormal                              | reset pen state
        TST     D5                              | varCode 0 = documentProc?
        BNE     WDEF_DRAW_NONDOC                | other style -> skip title bar
        BSR     WDEF_TITLE_RECT                 | compute title bar rect
        PEA.L   (TempRect).w                    | push title bar rect 3 times
        MOVE.L  (SP),-(SP)                      | for FrameRect, InsetRect, EraseRect
        MOVE.L  (SP),-(SP)                      | push copy for InsetRect
        _FrameRect                              | draw title bar outline
        MOVE.L  (OneOne).w,-(SP)                | push inset (1,1)
        _InsetRect                              | inset by (1,1) for interior
        _EraseRect                              | clear title bar interior
        BSR     WDEF_DRAW_TITLE                 | draw title; D3/D4 = gap left/right of it
        TST.B   wHilited(A3)                    | wHilited (active window)?
        BEQ     WDEF_DRAW_FRAME                 | inactive -> skip highlight
        PEA.L   (TempRect).w                    | push title bar rect
        MOVE    #0x1,-(SP)                      | inset dh=1
        MOVE    -0x2(A6),-(SP)                  | inset dv = box offset: stripes as high as the boxes
        _InsetRect                              | shrink to stripe fill area
        MOVE    (TempRect+RIGHT).w,-(SP)        | save right edge on stack
        MOVE    D3,(TempRect+RIGHT).w           | temp: right = left of title text
        MOVE.L  (TempRect).w,D0                 | D0 = title bar top/left
        ANDI.L  #0x70007,D0                     | mod 8: the pattern's phase
        MOVE.L  (A5),A4                         | deref QD globals
        MOVE.L  D0,PATALIGN(A4)                 | patAlign (QD private): stripes start at the bar's top
        PEA.L   (TempRect).w                    | push left stripe rect
        PEA.L   WDEF_STRIPE_PAT(PC)             | horizontal stripe pattern
        _FillRect                               | fill left stripe (before title)
        BSR     WDEF_HAS_ZOOM                   | has zoom box?
        BEQ.B   WDEF_ZOOM_CLAMP_OK              | no -> skip zoom clearance
        MOVE    (SP),D0                         | D0 = saved right edge
        SUBI    #0x1A,D0                        | leave 26px for zoom box area
        CMP     D4,D0                           | enough room for title?
        BGE.B   WDEF_ZOOM_CLAMP_OK              | enough room for title
        MOVE    D0,D4                           | clamp stripe to zoom box edge
WDEF_ZOOM_CLAMP_OK:
        MOVE    (SP)+,(TempRect+RIGHT).w        | restore right edge
        MOVE    D4,(TempRect+LEFT).w            | left = after title text
        PEA.L   (TempRect).w                    | push right stripe rect
        PEA.L   WDEF_STRIPE_PAT(PC)             | horizontal stripe pattern
        _FillRect                               | fill right stripe (after title)
        CLR.L   PATALIGN(A4)                    | reset pattern alignment (patAlign = 0,0)
        TST.B   wGoAway(A3)                     | wGoAway (has close box)?
        BEQ.B   WDEF_DRAW_ZOOM                  | no -> skip close box
        BSR     WDEF_TITLE_RECT                 | recompute title bar rect
        LEA.L   WDEF_CLOSE_NORMAL(PC),A1        | close box bitmap (normal)
        MOVEQ.L #0x0,D0                         | srcCopy mode
        BSR     WDEF_ICON_LEFT                  | draw close box at left edge
WDEF_DRAW_ZOOM:
        BSR     WDEF_HAS_ZOOM                   | has zoom box?
        BEQ.B   WDEF_DRAW_FRAME                 | no -> skip
        BSR     WDEF_TITLE_RECT                 | recompute title bar rect
        LEA.L   WDEF_ZOOM_NORMAL(PC),A1         | zoom box bitmap (normal)
        MOVEQ.L #0x0,D0                         | srcCopy mode
        BSR     WDEF_ICON_RIGHT                 | draw zoom box at right edge
WDEF_DRAW_FRAME:
        MOVE.L  (OneOne).w,D4                   | D4 = shadow offset (1,1) for doc
WDEF_DRAW_STRUCT:
        MOVE.L  structRgn(A3),A0                | deref structRgn handle
        MOVE.L  (A0),A0                         | deref region
        LEA.L   RGNBBOX(A0),A4                  | A4 -> structRgn bounding box
        SUB     D4,BOTTOM(A4)                   | shrink bottom by shadow size
        SUB     D4,RIGHT(A4)                    | shrink right by shadow size
        MOVE.L  A4,-(SP)                        | push structRgn bounding box
        _FrameRect                              | draw outer window border
        CMPI    #0x3,D5                         | altDBoxProc?
        BEQ.B   WDEF_DRAW_SHADOW                | altDBoxProc -> draw shadow
        TST     D5                              | documentProc?
        BNE.B   WDEF_CHECK_DBOX                 | dBox/plainDBox -> no shadow
WDEF_DRAW_SHADOW:
        BSR     WDEF_DROP_SHADOW                | draw drop shadow (L-shaped)
WDEF_CHECK_DBOX:
        CMPI    #0x1,D5                         | dBoxProc (modal dialog)?
        BNE.B   WDEF_RESTORE_STRUCT             | no -> done with frame
        MOVE.L  (A4),(TempRect).w               | copy struct rect to TempRect
        MOVE.L  0x4(A4),(TempRect+BOTTOM).w     | copy struct botRight
        PEA.L   (TempRect).w                    | push for 3 operations
        MOVE.L  (SP),-(SP)                      | for FrameRect (white ring)
        MOVE.L  (SP),-(SP)                      | for InsetRect (2,2)
        MOVE.L  (OneOne).w,-(SP)                | push inset (1,1)
        _InsetRect                              | inset by (1,1) for inner border
        MOVE.L  #0x70007,-(SP)                  | pen size 7x7
        _PenSize                                | thick pen 7x7
        MOVE.L  (A5),A0                         | deref QD globals
        PEA.L   WHITE(A0)                       | push white pattern
        _PenPat                                 | set white pattern
        _FrameRect                              | clear a 7-pixel ring inside the frame
        MOVE.L  (A5),A0                         | deref QD globals
        PEA.L   BLACK(A0)                       | push black pattern
        _PenPat                                 | set black pattern
        MOVE.L  #0x20002,-(SP)                  | pen size 2x2
        MOVE.L  (SP),-(SP)                      | also used as InsetRect param
        _PenSize                                | pen size 2x2
        _InsetRect                              | inset by (2,2): 3 pixels inside the frame
        PEA.L   (TempRect).w                    | push inner frame rect
        _FrameRect                              | draw the 2-pixel black border
        _PenNormal                              | reset pen state
WDEF_RESTORE_STRUCT:
        ADD     D4,BOTTOM(A4)                   | restore structRgn bottom
        ADD     D4,RIGHT(A4)                    | restore structRgn right
WDEF_DRAW_RTS:
        RTS                                     | return from WDEF_DRAW

| horizontal stripe pattern for active title bar highlight
WDEF_STRIPE_PAT:
  .long 0xFF00FF00                              | rows 0-3: black, white, black, white
  .long 0xFF00FF00                              | rows 4-7: black, white, black, white

| ----------------------------------------------------------
| WDEF_TITLE_RECT (Apple: BuildTBarRect) - compute title bar rect
| into TempRect: structRgn's bounding box with bottom = top +
| title bar height (D7) and right - 1 (exclude the shadow column).
| Out: A0 = TempRect. Changes D0/A1.
| Called by: WDEF_DRAW, WDEF_DRAW_ZOOM, WDEF_TOGGLE_BOX, WDEF_TOGGLE_CLOSE, WDEF_HIT_TITLEBAR (and 1 more)
WDEF_TITLE_RECT:
        LEA.L   (TempRect).w,A0                 | A0 -> TempRect
        MOVE.L  structRgn(A3),A1                | deref structRgn handle
        MOVE.L  (A1),A1                         | A1 = structRgn pointer
        ADDQ.W  #0x2,A1                         | skip rgnSize, point to bbox
        MOVE.L  (A1)+,(A0)                      | copy bbox.topLeft
        MOVE.L  (A1),0x4(A0)                    | copy bbox.botRight
        MOVE    (A0),D0                         | D0 = struct top
        ADD     D7,D0                           | bottom = top + title bar height
        MOVE    D0,BOTTOM(A0)                   | set title bar bottom
        SUBQ.W  #0x1,RIGHT(A0)                  | right -= 1 (exclude shadow col)
        RTS                                     | return from WDEF_TITLE_RECT

| ----------------------------------------------------------
| wDraw param >= 4: toggle close box or zoom box highlight
| param = 4 -> close box; param = 5 -> zoom box
| (entered with the flags of CMPI #4,D3)
WDEF_TOGGLE_BOX:
        BEQ.B   WDEF_TOGGLE_CLOSE               | param == 4 -> toggle close box
        BSR     WDEF_HAS_ZOOM                   | param >= 5: has zoom box?
        BEQ.B   WDEF_TOGGLE_DONE                | no -> done
        BSR.B   WDEF_TITLE_RECT                 | compute title bar rect
        LEA.L   WDEF_ZOOM_TOGGLE(PC),A1         | zoom box toggled bitmap (XOR)
        MOVEQ.L #0x2,D0                         | srcXor mode

| WDEF_ICON_RIGHT - position and draw icon at right side of title bar
| A1 = bitmap data, D0 = transfer mode
WDEF_ICON_RIGHT:
        LEA.L   (TempRect).w,A0                 | A0 -> TempRect
        MOVE    RIGHT(A0),LEFT(A0)              | left = right (right-align)
        MOVEQ.L #-0x16,D1                       | offset -22px from right edge
        BRA.B   WDEF_ICON_DRAW                  | common setup

| ----------------------------------------------------------
| wDraw param = 4: toggle close box highlight
WDEF_TOGGLE_CLOSE:
        BSR.B   WDEF_TITLE_RECT                 | compute title bar rect
        LEA.L   WDEF_CLOSE_TOGGLE(PC),A1        | close box toggled bitmap (XOR)
        MOVEQ.L #0x2,D0                         | srcXor mode

| WDEF_ICON_LEFT - position and draw icon at left side of title bar
| A1 = bitmap data, D0 = transfer mode
WDEF_ICON_LEFT:
        LEA.L   (TempRect).w,A0                 | A0 -> TempRect
        MOVEQ.L #0x7,D1                         | offset +7px from left edge

| WDEF_ICON_DRAW - common icon positioning and CopyBits
| Builds 16x16 dest rect in TempRect, calls WDEF_COPYBITS to blit
WDEF_ICON_DRAW:
        ADD     D1,LEFT(A0)                     | adjust left by h offset
        MOVE    -0x2(A6),D1                     | icon vertical centering offset
        ADD     D1,(A0)                         | adjust top for centering
        SUBQ.W  #0x1,(A0)                       | fine-tune vertical alignment
        MOVE.L  (A0)+,(A0)                      | set botRight = topLeft initially
        MOVEQ.L #0x10,D1                        | icon is 16x16 pixels
        ADD     D1,(A0)+                        | bottom = top + 16
        ADD     D1,(A0)                         | right = left + 16
        MOVE.L  #0x100010,D1                    | source bounds = 16x16
        BSR     WDEF_COPYBITS                   | CopyBits the icon bitmap
WDEF_TOGGLE_DONE:
        RTS                                     | return from WDEF_TOGGLE_BOX / WDEF_ICON_*

| ----------------------------------------------------------
| wDraw for non-document styles (varCode 1/2/3)
| Sets shadow offset D4 based on style, then draws frame
WDEF_DRAW_NONDOC:
        MOVE.L  #0x20002,D4                     | altDBoxProc: 2-pixel shadow
        CMPI    #0x3,D5                         | is altDBoxProc?
        BEQ     WDEF_DRAW_STRUCT                | go draw frame with shadow
        MOVEQ.L #0x0,D4                         | plainDBox/dBoxProc: no shadow
        BRA     WDEF_DRAW_STRUCT                | go draw frame without shadow

| ----------------------------------------------------------
| WDEF_DRAW_TITLE (Apple: DoTitleString) - draw window title string
| centered in title bar (TempRect), at least 2 pixels (32 with a
| close box) from its left edge, clipped to the space left of the
| zoom box. The baseline is ascent+1 below the bar's top.
| Returns D3 = left stripe right edge, D4 = right stripe left
| (6 pixels of white space on each side of the title).
| Changes D0-D2/A0-A1.
WDEF_DRAW_TITLE:
        MOVE    (TempRect+RIGHT).w,D4           | D4 = title bar right edge
        MOVE    D4,D3                           | D3 = title bar right edge
        SUB     (TempRect+LEFT).w,D3            | D3 = available width
        SUB     wTitleWidth(A3),D3              | subtract wTitleWidth
        ASR     #0x1,D3                         | center: half of remaining space
        MOVEQ.L #0x2,D0                         | min left margin = 2px
        TST.B   wGoAway(A3)                     | has close box?
        BEQ.B   WDEF_TITLE_MARGIN               | no -> use 2px margin
        MOVEQ.L #0x20,D0                        | min margin = 32px (past close box)
WDEF_TITLE_MARGIN:
        CMP     D0,D3                           | enough margin?
        BGE.B   WDEF_TITLE_ABS                  | yes -> keep computed width
        MOVE    D0,D3                           | enforce minimum margin
WDEF_TITLE_ABS:
        ADD     (TempRect+LEFT).w,D3            | D3 = absolute title text left
        MOVE    D4,-(SP)                        | save right edge on stack
        BSR     WDEF_HAS_ZOOM                   | has zoom box?
        BEQ.B   WDEF_TITLE_CLIP                 | no -> use full width
        SUBI    #0x20,D4                        | reserve 32px for zoom box
WDEF_TITLE_CLIP:
        MOVE.L  -0xC(A6),-(SP)                  | push scratch region
        MOVE.L  (SP),-(SP)                      | dup: one for GetClip, one for SectRgn
        _GetClip                                | save current clip region
        MOVE    D4,(TempRect+RIGHT).w           | set clip right boundary
        PEA.L   (TempRect).w                    | push clip rect
        _ClipRect                               | clip to title text area
        MOVE.L  (A5),A0                         | deref QD globals
        MOVE.L  (A0),A0                         | deref thePort
        MOVE.L  CLIPRGN(A0),-(SP)               | push port's clipRgn handle
        MOVE.L  (SP),-(SP)                      | dup for SectRgn dest
        _SectRgn                                | clip = saved clip AND title area
        MOVE    (SP)+,(TempRect+RIGHT).w        | restore saved right edge
        MOVE    D3,-(SP)                        | push title text h position
        MOVE    (TempRect).w,D0                 | D0 = title bar top
        ADD     -0x8(A6),D0                     | + font ascent = baseline
        ADDQ.W  #0x1,D0                         | +1 for pixel alignment
        MOVE    D0,-(SP)                        | push v position
        _MoveTo                                 | position pen for title text
        MOVE.L  wTitleHandle(A3),A0             | deref wTitleHandle
        MOVE.L  (A0),-(SP)                      | push title string pointer (not locked)
        _DrawString                             | draw the window title
        MOVE.L  -0xC(A6),-(SP)                  | push saved clip region
        _SetClip                                | restore saved clip region
        MOVE    D3,D0                           | D0 = title text left
        SUBQ.W  #0x6,D3                         | D3 -= 6 (gap before title text)
        ADD     wTitleWidth(A3),D0              | D0 += wTitleWidth = text right
        CMP     D4,D0                           | past clip boundary?
        BGE.B   WDEF_TITLE_GAP                  | yes -> keep clip limit
        MOVE    D0,D4                           | clamp D4 to text right edge
WDEF_TITLE_GAP:
        ADDQ.W  #0x6,D4                         | add 6px gap after title text
        RTS                                     | return from WDEF_DRAW_TITLE

| ----------------------------------------------------------
| Bitmap data for close and zoom box icons (16x16 each)
| (2 bytes per row). The boxes carry the title bar's stripes on their
| outer columns (every other row), so srcCopy keeps the stripes; the
| *_TOGGLE masks are XORed over the boxes to show them pressed.
|
| WDEF_ZOOM_NORMAL - zoom box, normal (a small rect in a big one)
WDEF_ZOOM_NORMAL:
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0xBFFB                                 | #.###########.##
  .short 0x2088                                 | ..#.....#...#...
  .short 0xA08B                                 | #.#.....#...#.##
  .short 0x2088                                 | ..#.....#...#...
  .short 0xA08B                                 | #.#.....#...#.##
  .short 0x2088                                 | ..#.....#...#...
  .short 0xBF8B                                 | #.#######...#.##
  .short 0x2008                                 | ..#.........#...
  .short 0xA00B                                 | #.#.........#.##
  .short 0x2008                                 | ..#.........#...
  .short 0xBFFB                                 | #.###########.##
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
| WDEF_ZOOM_TOGGLE - zoom box, toggled (XOR pattern for highlight)
WDEF_ZOOM_TOGGLE:
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0180                                 | .......##.......
  .short 0x09A0                                 | ....#..##.#.....
  .short 0x05C0                                 | .....#.###......
  .short 0x0080                                 | ........#.......
  .short 0x1CF0                                 | ...###..####....
  .short 0x1F80                                 | ...######.......
  .short 0x0540                                 | .....#.#.#......
  .short 0x0920                                 | ....#..#..#.....
  .short 0x0100                                 | .......#........
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
| WDEF_CLOSE_NORMAL - close box, normal (empty square)
WDEF_CLOSE_NORMAL:
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0xBFFB                                 | #.###########.##
  .short 0x2008                                 | ..#.........#...
  .short 0xA00B                                 | #.#.........#.##
  .short 0x2008                                 | ..#.........#...
  .short 0xA00B                                 | #.#.........#.##
  .short 0x2008                                 | ..#.........#...
  .short 0xA00B                                 | #.#.........#.##
  .short 0x2008                                 | ..#.........#...
  .short 0xA00B                                 | #.#.........#.##
  .short 0x2008                                 | ..#.........#...
  .short 0xBFFB                                 | #.###########.##
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
| WDEF_CLOSE_TOGGLE - close box, toggled (XOR pattern for highlight)
WDEF_CLOSE_TOGGLE:
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0100                                 | .......#........
  .short 0x0920                                 | ....#..#..#.....
  .short 0x0540                                 | .....#.#.#......
  .short 0x0000                                 | ................
  .short 0x1C70                                 | ...###...###....
  .short 0x0000                                 | ................
  .short 0x0540                                 | .....#.#.#......
  .short 0x0920                                 | ....#..#..#.....
  .short 0x0100                                 | .......#........
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................

| ----------------------------------------------------------
| wHit handler (Apple: HitDoc) - determine which window part was
| clicked
| D3 = click point (global; v in high word, h in low word)
| Returns via 0x14(A6): wNoHit=0, wInContent=1, wInDrag=2,
| wInGrow=3, wInGoAway=4, wInZoomIn=5, wInZoomOut=6
WDEF_HIT:
        CLR     -(SP)                           | space for PtInRgn result
        MOVE.L  D3,-(SP)                        | push click point
        MOVE.L  contRgn(A3),-(SP)               | push contRgn handle
        _PtInRgn                                | check if point is in contRgn
        TST.B   (SP)+                           | in content region?
        BEQ.B   WDEF_HIT_TITLEBAR               | no -> test title bar
        TST     D5                              | documentProc?
        BNE.B   WDEF_HIT_CONTENT                | other style -> wInContent
        BTST    #0x2,D6                         | varCode bit 2 set?
        BGT.B   WDEF_HIT_CONTENT                | yes (noGrowDocProc) -> no grow box test
        TST.B   wHilited(A3)                    | wHilited (active)?
        BEQ.B   WDEF_HIT_CONTENT                | inactive -> wInContent
        MOVE.L  contRgn(A3),A0                  | deref contRgn
        MOVE.L  (A0),A0                         | A0 = contRgn pointer
        MOVE.L  RGNBBOX+BOTTOM(A0),D0           | D0 = contRgn bbox botRight
        MOVEQ.L #0xE,D4                         | grow box = 14px from corner
        SUB     D4,D0                           | D0.w = right - 14
        CMP     D0,D3                           | click h >= right-14?
        BLT.B   WDEF_HIT_CONTENT                | no -> wInContent
        SWAP    D0                              | D0.w = bottom
        SUB     D4,D0                           | bottom -= 14
        SWAP    D3                              | D3.w = click v
        CMP     D0,D3                           | click v >= bottom-14?
        BLT.B   WDEF_HIT_CONTENT                | no -> wInContent
        MOVEQ.L #0x3,D0                         | wInGrow
        BRA     WDEF_HIT_RETURN                 | return hit result

| ----------------------------------------------------------
| return wInContent
| Called by: WDEF_HIT (5 branches: not a documentProc, no grow box,
| inactive window, outside the grow box)
WDEF_HIT_CONTENT:
        MOVEQ.L #0x1,D0                         | wInContent
        BRA     WDEF_HIT_RETURN                 | return hit result

| ----------------------------------------------------------
| not in content - test title bar for drag, close, zoom
WDEF_HIT_TITLEBAR:
        TST     D5                              | only documentProc has title bar
        BNE     WDEF_HIT_NOHIT                  | other styles -> wNoHit
        BSR     WDEF_TITLE_RECT                 | compute title bar rect
        CLR     -(SP)                           | space for PtInRect result
        MOVE.L  D3,-(SP)                        | push click point
        MOVE.L  A0,-(SP)                        | push title bar rect
        _PtInRect                               | check if point is in title bar
        TST.B   (SP)+                           | in title bar?
        BEQ.B   WDEF_HIT_NOHIT                  | no -> wNoHit
        TST.B   wHilited(A3)                    | wHilited (active)?
        BEQ.B   WDEF_HIT_DRAG                   | inactive -> wInDrag only
        MOVE.L  D3,D0                           | compute vertical offset in title
        SWAP    D0                              | D0.w = click v
        ADD     PORTBOUNDS(A3),D0               | + portBits.bounds.top = local v
        SUB     PORTRECT(A3),D0                 | - portRect.top: 0 = bottom of the title bar
        ADD     -0x2(A6),D0                     | add icon centering offset
        BPL.B   WDEF_HIT_DRAG                   | below icon row -> wInDrag
        ADDI    #0xB,D0                         | within 11px of icon center?
        BMI.B   WDEF_HIT_DRAG                   | above icon row -> wInDrag
        TST.B   wGoAway(A3)                     | wGoAway (has close box)?
        BEQ.B   WDEF_HIT_ZOOM                   | no -> check zoom box
        MOVE.L  D3,D0                           | test close box h range
        ADD     PORTBOUNDS+LEFT(A3),D0          | + portBits.bounds.left
        SUB     PORTRECT+LEFT(A3),D0            | - portRect.left
        CMPI    #0x12,D0                        | within 18px of left edge?
        BGT.B   WDEF_HIT_ZOOM                   | no -> check zoom box
        SUBQ.W  #0x8,D0                         | past 8px indent?
        BMI.B   WDEF_HIT_DRAG                   | too far left -> wInDrag
        MOVEQ.L #0x4,D0                         | wInGoAway
        BRA.B   WDEF_HIT_RETURN                 | return hit result

| ----------------------------------------------------------
| test zoom box hit (right side of title bar)
WDEF_HIT_ZOOM:
        BSR     WDEF_HAS_ZOOM                   | has zoom box?
        BEQ.B   WDEF_HIT_DRAG                   | no -> wInDrag
        MOVE    D3,D0                           | D0 = click h
        ADD     PORTBOUNDS+LEFT(A3),D0          | + portBits.bounds.left
        SUB     PORTRECT+RIGHT(A3),D0           | - portRect.right
        CMPI    #-0x13,D0                       | >= 19px left of right edge?
        BLT.B   WDEF_HIT_DRAG                   | too far left -> wInDrag
        CMPI    #-0x9,D0                        | <= 9px left of right edge?
        BGT.B   WDEF_HIT_DRAG                   | too close to edge -> wInDrag
        BSR     WDEF_CHECK_ZOOM_ST              | at stdState? (else userState updated)
        BEQ.B   WDEF_HIT_ZOOM_IN                | yes -> wInZoomIn
        MOVEQ.L #0x6,D0                         | wInZoomOut (user state: zoom out to stdState)
        BRA.B   WDEF_HIT_RETURN                 | return hit result

| ----------------------------------------------------------
| at the standard state: clicking zoom -> zoom in to the user state
WDEF_HIT_ZOOM_IN:
        MOVEQ.L #0x5,D0                         | wInZoomIn
        BRA.B   WDEF_HIT_RETURN                 | return hit result

| ----------------------------------------------------------
| in title bar but not on close/zoom -> drag region
| Called by: WDEF_HIT_TITLEBAR (4 branches), WDEF_HIT_ZOOM (3 branches)
WDEF_HIT_DRAG:
        MOVEQ.L #0x2,D0                         | wInDrag
| Called by: WDEF_HIT, WDEF_HIT_CONTENT, WDEF_HIT_TITLEBAR, WDEF_HIT_ZOOM, WDEF_HIT_ZOOM_IN
WDEF_HIT_RETURN:
        MOVE.L  D0,0x14(A6)                     | store hit result for caller
WDEF_HIT_NOHIT:
        RTS                                     | return from WDEF_HIT

| ----------------------------------------------------------
| wCalcRgns handler (Apple: CalcDoc) - compute contRgn and
| structRgn; first updates userState if a zoom window was moved or
| sized (WDEF_CHECK_ZOOM_ST)
| contRgn = portRect converted to global coordinates
| structRgn = contRgn expanded by border, title bar, shadow
WDEF_CALCRGNS:
        BSR     WDEF_HAS_ZOOM                   | has zoom box?
        BEQ.B   WDEF_CALC_CONT                  | no -> skip zoom state update
        BSR     WDEF_CHECK_ZOOM_ST              | update zoom state if needed
WDEF_CALC_CONT:
        LEA.L   (TempRect).w,A0                 | A0 -> TempRect
        MOVE.L  A0,-(SP)                        | push rect ptr for OffsetRect
        MOVE.L  PORTRECT(A3),(A0)+              | copy portRect.topLeft
        MOVE.L  PORTRECT+BOTTOM(A3),(A0)        | copy portRect.botRight
        MOVE.L  PORTBOUNDS(A3),-(SP)            | push portBits.bounds origin
        NEG     (SP)                            | negate top (local->global)
        NEG     0x2(SP)                         | negate left
        _OffsetRect                             | convert rect to global coords
        MOVE.L  contRgn(A3),-(SP)               | push contRgn handle
        PEA.L   (TempRect).w                    | push global portRect
        _RectRgn                                | contRgn = global portRect
        MOVE.L  #0x20002,D4                     | shadow offset (2,2) for altDBoxProc
        MOVE.L  structRgn(A3),-(SP)             | push structRgn handle
        PEA.L   (TempRect).w                    | push rect for InsetRect
        MOVE.L  (SP),-(SP)                      | dup for RectRgn
        MOVE.L  (MinusOne).w,-(SP)              | expand by (-1,-1) for border
        _InsetRect                              | grow rect by 1px for border
        TST     D5                              | documentProc?
        BNE.B   WDEF_CALC_DBOX                  | other style -> check dBoxProc
        MOVE    D7,D0                           | title bar height
        SUBQ.W  #0x1,D0                         | minus 1 for border overlap
        SUB     D0,(TempRect).w                 | extend top for title bar
        LSR.L   #0x1,D4                         | shadow = (1,1) for document
WDEF_CALC_STRUCT:
        _RectRgn                                | structRgn = expanded rect
        TST     D5                              | doc or altDBox need shadow rgn
        BEQ.B   WDEF_CALC_SHADOW                | documentProc -> needs shadow rgn
        CMPI    #0x3,D5                         | altDBoxProc?
        BNE.B   WDEF_CALC_DONE                  | plainDBox/dBox -> no shadow
WDEF_CALC_SHADOW:
        MOVE.L  -0xC(A6),-(SP)                  | push scratch region
        PEA.L   (TempRect).w                    | push shadow rect
        MOVE.L  (SP),-(SP)                      | dup for RectRgn
        MOVE.L  D4,-(SP)                        | push shadow offset
        _OffsetRect                             | shift rect down-right for shadow
        _RectRgn                                | scratch = shadow rect region
        MOVE.L  structRgn(A3),-(SP)             | push structRgn
        MOVE.L  -0xC(A6),-(SP)                  | push shadow region
        MOVE.L  structRgn(A3),-(SP)             | push dest = structRgn
        _UnionRgn                               | structRgn = frame union shadow
WDEF_CALC_DONE:
        RTS                                     | return from WDEF_CALCRGNS

| ----------------------------------------------------------
| dBoxProc: expand struct rect by 7px for thick double border
WDEF_CALC_DBOX:
        CMPI    #0x1,D5                         | dBoxProc?
        BNE.B   WDEF_CALC_STRUCT                | no -> plainDBox or altDBox
        PEA.L   (TempRect).w                    | push struct rect
        MOVE.L  #0xFFF9FFF9,-(SP)               | inset by -7,-7 (expand 7px)
        _InsetRect                              | grow rect for double border
        BRA.B   WDEF_CALC_STRUCT                | go create structRgn

| ----------------------------------------------------------
| wGrow handler (Apple: GrowDoc) - draw grow image (rubber-band
| outline)
| D3 = pointer to grow rect; draws frame with crosshair
| lines showing scroll bar divider positions at 16px inset
WDEF_GROW:
        MOVE.L  D3,-(SP)                        | push grow rect ptr
        MOVE.L  (MinusOne).w,-(SP)              | expand by (-1,-1)
        _InsetRect                              | expand grow rect by 1px
        MOVE.L  D3,A3                           | A3 = grow rect ptr
        MOVE.L  (A3),-(SP)                      | save original top-left
        MOVE    D7,D0                           | title bar height
        SUBQ.W  #0x1,D0                         | minus 1 for overlap
        SUB     D0,(A3)                         | extend top for title bar
        MOVE.L  D3,-(SP)                        | push extended grow rect
        _FrameRect                              | draw outer grow outline
        MOVE    LEFT(A3),-(SP)                  | push rect.left (h)
        MOVE    BOTTOM(A3),-(SP)                | push rect.bottom
        SUBI    #0x10,(SP)                      | bottom - 16 = h scroll divider
        MOVE.L  (SP),-(SP)                      | push copy for MoveTo
        _MoveTo                                 | move to h scroll divider left
        MOVE    RIGHT(A3),0x2(SP)               | set h = right edge
        _LineTo                                 | draw horizontal scroll divider
        MOVE.L  (SP),(A3)                       | restore original top
        MOVE.L  (SP),-(SP)                      | push copy for MoveTo
        _MoveTo                                 | move to title bar bottom
        MOVE    RIGHT(A3),0x2(SP)               | set h = right
        _LineTo                                 | draw title bar bottom line
        MOVE    RIGHT(A3),-(SP)                 | push right edge
        SUBI    #0x10,(SP)                      | right - 16 = v scroll divider
        MOVE    (A3),-(SP)                      | push top
        MOVE.L  (SP),-(SP)                      | push copy for MoveTo
        _MoveTo                                 | move to v scroll divider top
        MOVE    BOTTOM(A3),(SP)                 | set v = bottom
        _LineTo                                 | draw vertical scroll divider
        MOVE.L  D3,-(SP)                        | push grow rect
        MOVE.L  (OneOne).w,-(SP)                | push inset (1,1)
        _InsetRect                              | shrink back by (1,1)
        RTS                                     | return from WDEF_GROW

| ----------------------------------------------------------
| WDEF_DROP_SHADOW - draw drop shadow (L-shaped: bottom + right edges)
| A4 -> struct bounding rect, D4 = shadow pen size
| Called by: WDEF_DRAW_SHADOW
WDEF_DROP_SHADOW:
        MOVE.L  D4,-(SP)                        | push pen size
        _PenSize                                | set pen to shadow thickness
        MOVE    RIGHT(A4),D0                    | D0 = right edge
        MOVE    D0,-(SP)                        | push right for top-right corner
        MOVE    (A4),-(SP)                      | push top
        ADD     D4,(SP)                         | offset top down by shadow width
        MOVE    D0,-(SP)                        | push right for bottom-right
        MOVE    BOTTOM(A4),D0                   | D0 = bottom edge
        MOVE    D0,-(SP)                        | push bottom
        MOVE    LEFT(A4),-(SP)                  | push left edge
        ADD     D4,(SP)                         | offset left by shadow width
        MOVE    D0,-(SP)                        | push bottom for start point
        _MoveTo                                 | move to bottom-left of shadow
        _LineTo                                 | draw bottom shadow line (right)
        _LineTo                                 | draw right shadow line (up)
        _PenNormal                              | reset pen state
        RTS                                     | return from WDEF_DROP_SHADOW

| ----------------------------------------------------------
| WDEF_COPYBITS - CopyBits a small icon bitmap into the current port
| A1 = source bitmap data, D0 = transfer mode, D1 = bounds
| Builds temporary BitMap struct in IconBitmap low-memory,
| blits from icon data into thePort at TempRect
| Called by: WDEF_ICON_DRAW, WDEF_GICON
WDEF_COPYBITS:
        LEA.L   (IconBitmap).w,A0               | A0 -> temp BitMap struct
        MOVE.L  A1,(A0)+                        | baseAddr = icon bitmap data
        MOVE    #0x2,(A0)+                      | rowBytes = 2 (16px wide)
        CLR.L   (A0)+                           | bounds.topLeft = (0,0)
        MOVE.L  D1,(A0)                         | bounds.botRight = D1
        PEA.L   (IconBitmap).w                  | push source BitMap
        MOVE.L  (SP),A0                         | A0 = source BitMap for later
        MOVE.L  (A5),A1                         | deref QD globals
        MOVE.L  (A1),A1                         | deref thePort
        PEA.L   PORTBITS(A1)                    | push dest portBits
        PEA.L   BOUNDS(A0)                      | push source bounds rect
        PEA.L   (TempRect).w                    | push dest rect
        MOVE    D0,-(SP)                        | push transfer mode
        CLR.L   -(SP)                           | no mask region
        _CopyBits                               | blit icon to window frame
        RTS                                     | return from WDEF_COPYBITS

| ----------------------------------------------------------
| wGIcon handler (Apple: DrawGIcon) - draw grow icon (size box) in
| content region
| Switches to the window's own port, draws size box bitmap
| at bottom-right corner, and scroll bar divider lines; returns
| with the window's port set (the exit restores the caller's
| port; the SE's version sets the WMgrPort again first).
WDEF_GICON:
        MOVE.L  A3,-(SP)                        | push WindowRecord pointer
        _SetPort                                | set port to window itself
        LEA.L   (TempRect).w,A4                 | A4 -> TempRect
        MOVE.L  PORTRECT+BOTTOM(A3),0x4(A4)     | botRight = portRect.botRight
        MOVE.L  0x4(A4),(A4)                    | topLeft = botRight initially
        SUBI    #0xF,(A4)                       | top = bottom - 15
        SUBI    #0xF,LEFT(A4)                   | left = right - 15
        TST.B   wHilited(A3)                    | wHilited (window active)?
        BEQ.B   WDEF_GICON_INACTIVE             | inactive -> erase size box
        LEA.L   WDEF_SIZEBOX_ICON(PC),A1        | size box icon bitmap
        MOVEQ.L #0x0,D0                         | srcCopy mode
        MOVE.L  #0x100010,D1                    | bounds = 16x16
        BSR.B   WDEF_COPYBITS                   | draw size box icon
WDEF_GICON_DIVIDERS:
        MOVE    LEFT(A4),-(SP)                  | push size box left (= divider x)
        MOVE    (SP),-(SP)                      | x again: one for MoveTo, one for LineTo
        MOVE    PORTRECT(A3),-(SP)              | push portRect.top
        _MoveTo                                 | move to top of vertical divider
        MOVE    PORTRECT+BOTTOM(A3),-(SP)       | push portRect.bottom
        _LineTo                                 | draw vertical scroll bar divider
        MOVE    PORTRECT+LEFT(A3),-(SP)         | push portRect.left
        MOVE    (A4),-(SP)                      | push size box top (= divider y)
        _MoveTo                                 | move to left of horizontal divider
        MOVE    PORTRECT+RIGHT(A3),-(SP)        | push portRect.right
        MOVE    (A4),-(SP)                      | push same top
        _LineTo                                 | draw horizontal scroll bar divider
        RTS                                     | return from WDEF_GICON

| ----------------------------------------------------------
| inactive window: erase size box area, then draw dividers
WDEF_GICON_INACTIVE:
        PEA.L   (TempRect).w                    | push size box rect
        _EraseRect                              | erase size box area
        BRA.B   WDEF_GICON_DIVIDERS             | draw divider lines anyway

| ----------------------------------------------------------
| WDEF_SIZEBOX_ICON - size box (grow icon) bitmap, 16x16
| Two overlapping rectangles representing a resizable window
WDEF_SIZEBOX_ICON:
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x0000                                 | ................
  .short 0x1FE0                                 | ...########.....
  .short 0x1020                                 | ...#......#.....
  .short 0x103E                                 | ...#......#####.
  .short 0x1022                                 | ...#......#...#.
  .short 0x1022                                 | ...#......#...#.
  .short 0x1022                                 | ...#......#...#.
  .short 0x1022                                 | ...#......#...#.
  .short 0x1FE2                                 | ...########...#.
  .short 0x0402                                 | .....#........#.
  .short 0x0402                                 | .....#........#.
  .short 0x0402                                 | .....#........#.
  .short 0x07FE                                 | .....##########.
  .short 0x0000                                 | ................
    ROM_RESOURCE_END WDEF_0                     | end of the data: pads to even, sets the sizes

| end of resource : 'WDEF' 0

