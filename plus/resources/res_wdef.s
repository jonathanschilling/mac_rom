| WDEF 0 - Standard window definition function
| resource : 'WDEF' 0
| Handles all messages for standard Mac window styles:
| varCode 0 = documentProc (title bar, close box, drag)
| varCode 1 = dBoxProc (double-border modal dialog)
| varCode 2 = plainDBox (plain dialog, no border)
| varCode 3 = altDBoxProc (shadow dialog)
| varCode bit 3 = zoomDocProc (adds zoom box)
| Messages: wDraw=0, wHit=1, wCalcRgns=2, wNew=3,
| wDispose=4, wGrow=5, wGIcon=6
| Stack frame locals:
| -8(A6) = FontInfo ascent
| -6(A6) = FontInfo descent
| -4(A6) = title bar height (D7 copy)
| -2(A6) = vertical centering offset for close/zoom icons
| -C(A6) = scratch region handle (for clip save/restore)
| After parameter extraction:
| D3 = param (message-specific: point for wHit, subcode for wDraw)
| D5 = varCode masked to low 2 bits (window style)
| D6 = full variation code (includes zoom bit 3)
| D7 = title bar height in pixels (min 19)
| A3 = WindowRecord pointer
WDEF_HEADER:
        BRA.B   WDEF_ENTRY                      | branch to start
  .byte 0x00,0x00                               | flags: unused
  .ascii "WDEF"                                 | resource type identifier
  .byte 0x00,0x00,0x00,0x05                     | resource ID = 0, version = 5

| ----------------------------------------------------------
| WDEF main entry - set up stack frame, compute title bar
| height from current font metrics, dispatch to handler
WDEF_ENTRY:
        LINK    A6,#-0xC                        | allocate 12 bytes for locals
        MOVEM.L D3-D7/A1-A4,-(SP)               | save registers
        MOVE.L  (A5),A0                         | deref QD globals
        MOVE.L  (A0),-(SP)                      | save current port on stack
        MOVE.L  (WMgrPort).w,(A0)               | set WMgrPort as current port
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
        JSR     (A0)                            | dispatch to message handler
        MOVE.L  -0xC(A6),-(SP)                  | push scratch region handle
        _DisposeRgn                             | free scratch region
        _SetPort                                | restore saved port
        MOVEM.L (SP)+,D3-D7/A1-A4               | restore registers
        UNLK    A6                              | destroy stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xC,SP                         | strip 3 params (12 bytes)
        JMP     (A0)                            | return to caller

| Jump table - word offsets for each message handler
| wDraw(0), wHit(1), wCalcRgns(2), wNew(3),
| wDispose(4), wGrow(5), wGIcon(6)
WDEF_JMPTABLE:
  .byte  0x00,0xC2,0x03,0x84,0x04,0x4E          | wDraw=+194, wHit=+900, wCalcRgns=+1102
  .byte 0x00,0x0E,0x00,0xB6,0x04,0xE0           | wNew=+14, wDispose=+182, wGrow=+1248
  .byte 0x05,0x8E                               | wGIcon=+1422

| ----------------------------------------------------------
| wNew handler - initialize zoom box data if requested
| varCode bit 3 means zoomable; allocates 16-byte WStateData:
| bytes 0-7 = userState rect (from current portRect)
| bytes 8-15 = stdState rect (from screen bounds, inset 3)
WDEF_NEW:
        BTst    #0x3,D6                         | zoom box requested?
        BEQ.B   WDEF_NEW_DONE                   | no -> done
        CLR.B   0x71(A3)                        | clear wZoom flag initially
        TST     (ROM85).w                       | check for 128K+ ROM
        BMI.B   WDEF_NEW_DONE                   | old ROM -> no zoom support
        MOVEQ.L #0x10,D0                        | 16 bytes for WStateData
        _NewHandleClear                         | allocate zoom state record
        BNE.B   WDEF_NEW_DONE                   | allocation failed -> done
        ADDQ.B  #0x1,0x71(A3)                   | set wZoom = true
        MOVE.L  A0,0x82(A3)                     | store in wDataHandle
        MOVE.L  (A0),A4                         | deref WStateData
        ADDQ.W  #0x8,A4                         | A4 -> stdState rect
        MOVE.L  (A5),A1                         | deref QD globals
        MOVE.L  -0x74(A1),(A4)+                 | copy screenBits.bounds.topLeft
        MOVE.L  -0x70(A1),(A4)+                 | copy screenBits.bounds.botRight
        MOVEQ.L #0x3,D0                         | inset stdState by 3 pixels
        SUB     D0,-(A4)                        | right -= 3
        SUB     D0,-(A4)                        | bottom -= 3
        ADD     D0,-(A4)                        | left += 3
        ADD     D0,-(A4)                        | top += 3
        ADD     D7,(A4)                         | top += title bar height
        ADD     D7,(A4)                         | (added twice for title bar space)
        MOVE.L  (A0),A4                         | re-deref -> userState rect

| ----------------------------------------------------------
| WDEF_COPY_PORTRECT - copy portRect to rect at A4, convert to global coords
| by negating portBounds origin. Used to snapshot window position.
WDEF_COPY_PORTRECT:
        MOVE.L  A4,-(SP)                        | push rect ptr for OffsetRect
        MOVE.L  PORTRECT(A3),(A4)               | copy portRect.topLeft
        MOVE.L  0x14(A3),0x4(A4)                | copy portRect.botRight
        MOVE.L  PORTBOUNDS(A3),-(SP)            | push portBounds.topLeft
        NEG     (SP)                            | negate top (local->global)
        NEG     0x2(SP)                         | negate left
        _OffsetRect                             | convert rect to global coords
WDEF_NEW_DONE:
        RTS                                     | return

| ----------------------------------------------------------
| WDEF_CHECK_ZOOM_ST - check if zoom state changed since last snapshot
| Compares current portRect (as global) against both
| userState and stdState rects in WStateData.
| Returns NE (D0=1) if state changed, EQ if unchanged.
WDEF_CHECK_ZOOM_ST:
        SUBQ.W  #0x8,SP                         | local 8-byte rect on stack
        MOVE.L  A7,A4                           | A4 -> local rect
        BSR.B   WDEF_COPY_PORTRECT              | copy portRect to local rect
        MOVE.L  0x82(A3),A0                     | deref wDataHandle
        MOVE.L  (A0),A2                         | A2 -> WStateData
        ADDQ.W  #0x8,A2                         | A2 -> stdState rect
        BSR.B   WDEF_PT_IN_EXPANDED             | point in stdState (with tolerance)?
        BNE.B   WDEF_STATE_CHANGED              | mismatch -> update userState
        BSR.B   WDEF_PT_IN_EXPANDED             | (A2 advanced past stdState)
        BEQ.B   WDEF_STATE_DONE                 | matches userState -> no change
WDEF_STATE_CHANGED:
        MOVE.L  0x82(A3),A0                     | state changed: update userState
        MOVE.L  (A0),A4                         | A4 -> WStateData
        BSR.B   WDEF_COPY_PORTRECT              | copy current portRect as userState
        MOVEQ.L #0x1,D0                         | return NE = state changed
WDEF_STATE_DONE:
        ADDQ.W  #0x8,SP                         | free local rect
        RTS                                     | return

| ----------------------------------------------------------
| WDEF_PT_IN_EXPANDED - expand rect by 7px and test if corner point is inside
| Used to compare window corners against zoom state rects
| with 7-pixel tolerance. A2 -> rect, A4 -> point pair.
WDEF_PT_IN_EXPANDED:
        MOVE.L  (A2),-(SP)                      | push rect topLeft
        MOVE.L  (A2)+,-(SP)                     | push copy for temp rect
        MOVE.L  A7,-(SP)                        | push temp rect address
        MOVE.L  #0xFFF9FFF9,-(SP)               | inset by -7,-7 (expand 7px)
        _InsetRect                              | expand temp rect by 7px
        CLR     -(SP)                           | space for PtInRect result
        MOVE.L  (A4)+,-(SP)                     | push point from A4
        PEA.L   0x6(SP)                         | push addr of temp rect
        _PtInRect                               | test if point is in expanded rect
        SUBQ.B  #0x1,(SP)                       | convert boolean to CC flags
        MOVE.B  (SP)+,D0                        | pop CC flags into D0
        ADDQ.W  #0x8,SP                         | pop temp rect
        RTS                                     | return

| ----------------------------------------------------------
| WDEF_HAS_ZOOM - test if window has zoom box capability
| Returns NE if varCode bit 3 set AND wZoom data allocated
| Called by: WDEF_DISPOSE, WDEF_DRAW, WDEF_DRAW_ZOOM, WDEF_TOGGLE_BOX, WDEF_TITLE_ABS (and 2 more)
WDEF_HAS_ZOOM:
        BTst    #0x3,D6                         | varCode has zoom bit?
        BEQ     WDEF_HAS_ZOOM_RTS               | no -> return EQ
        TST.B   0x71(A3)                        | wZoom flag set?
WDEF_HAS_ZOOM_RTS:
        RTS                                     | return

| ----------------------------------------------------------
| wDispose handler - free WStateData if zoom box allocated
WDEF_DISPOSE:
        BSR.B   WDEF_HAS_ZOOM                   | has zoom data?
        BEQ.B   WDEF_DISPOSE_DONE               | no -> done
        MOVE.L  0x82(A3),A0                     | get wDataHandle
        _DisposeHandle                          | free WStateData
WDEF_DISPOSE_DONE:
        RTS                                     | return

| ----------------------------------------------------------
| wDraw handler - draw window frame based on varCode/param
| param 0: draw entire frame (border, title bar, close/zoom)
| param 4: toggle close box highlight
| param 5: toggle zoom box highlight
WDEF_DRAW:
        TST.B   0x6E(A3)                        | wVisible?
        BEQ     WDEF_DRAW_RTS                   | invisible -> do nothing
        CMPI    #0x4,D3                         | param >= 4?
        BGE     WDEF_TOGGLE_BOX                 | yes -> toggle close/zoom box
        _PenNormal                              | reset pen state
        TST     D5                              | varCode 0 = documentProc?
        BNE     WDEF_DRAW_NONDOC                | other style -> skip title bar
        BSR     WDEF_TITLE_RECT                 | compute title bar rect
        PEA.L   (scratch8).w                    | push title bar rect 3 times
        MOVE.L  (SP),-(SP)                      | for FrameRect, InsetRect, EraseRect
        MOVE.L  (SP),-(SP)                      | push copy for InsetRect
        _FrameRect                              | draw title bar outline
        MOVE.L  (OneOne).w,-(SP)                | push inset (1,1)
        _InsetRect                              | inset by (1,1) for interior
        _EraseRect                              | clear title bar interior
        BSR     WDEF_DRAW_TITLE                 | draw title string, D4 = text right
        TST.B   0x6F(A3)                        | wHilited (active window)?
        BEQ     WDEF_DRAW_FRAME                 | inactive -> skip highlight
        PEA.L   (scratch8).w                    | push title bar rect
        MOVE    #0x1,-(SP)                      | inset dh=1
        MOVE    -0x2(A6),-(SP)                  | inset dv=icon centering offset
        _InsetRect                              | shrink to stripe fill area
        MOVE    (scratch8_6).w,-(SP)            | save right edge on stack
        MOVE    D3,(scratch8_6).w               | temp: right = left of title text
        MOVE.L  (scratch8).w,D0                 | D0 = title bar top/left
        ANDI.L  #0x70007,D0                     | mask low bits for pattern align
        MOVE.L  (A5),A4                         | deref QD globals
        MOVE.L  D0,-0xA8(A4)                    | set pnLoc for pattern alignment
        PEA.L   (scratch8).w                    | push left stripe rect
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
        MOVE    (SP)+,(scratch8_6).w            | restore right edge
        MOVE    D4,(scratch8_2).w               | left = after title text
        PEA.L   (scratch8).w                    | push right stripe rect
        PEA.L   WDEF_STRIPE_PAT(PC)             | horizontal stripe pattern
        _FillRect                               | fill right stripe (after title)
        CLR.L   -0xA8(A4)                       | reset pattern alignment
        TST.B   0x70(A3)                        | wGoAway (has close box)?
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
        MOVE.L  0x72(A3),A0                     | deref structRgn handle
        MOVE.L  (A0),A0                         | deref region
        LEA.L   0x2(A0),A4                      | A4 -> structRgn bounding box
        SUB     D4,0x4(A4)                      | shrink bottom by shadow size
        SUB     D4,0x6(A4)                      | shrink right by shadow size
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
        MOVE.L  (A4),(scratch8).w               | copy struct rect to scratch
        MOVE.L  0x4(A4),(scratch8_4).w          | copy struct botRight
        PEA.L   (scratch8).w                    | push for 3 operations
        MOVE.L  (SP),-(SP)                      | push for FrameRect
        MOVE.L  (SP),-(SP)                      | push for PenSize
        MOVE.L  (OneOne).w,-(SP)                | push inset (1,1)
        _InsetRect                              | inset by (1,1) for inner border
        MOVE.L  #0x70007,-(SP)                  | pen size 7x7
        _PenSize                                | thick pen 7x7
        MOVE.L  (A5),A0                         | deref QD globals
        PEA.L   -0x8(A0)                        | push gray pattern
        _PenPat                                 | set gray pattern
        _FrameRect                              | draw thick gray border ring
        MOVE.L  (A5),A0                         | deref QD globals
        PEA.L   -0x10(A0)                       | push black pattern
        _PenPat                                 | set black pattern
        MOVE.L  #0x20002,-(SP)                  | pen size 2x2
        MOVE.L  (SP),-(SP)                      | also used as InsetRect param
        _PenSize                                | pen size 2x2
        _InsetRect                              | inset by (2,2) inside gray
        PEA.L   (scratch8).w                    | push inner frame rect
        _FrameRect                              | draw inner black border
        _PenNormal                              | reset pen state
WDEF_RESTORE_STRUCT:
        ADD     D4,0x4(A4)                      | restore structRgn bottom
        ADD     D4,0x6(A4)                      | restore structRgn right
WDEF_DRAW_RTS:
        RTS                                     | return

| horizontal stripe pattern for active title bar highlight
WDEF_STRIPE_PAT:
  .byte  0xFF,0x00,0xFF,0x00,0xFF,0x00          | rows 0-5: alternating black/white
  .byte 0xFF,0x00                               | rows 6-7: horizontal stripes

| ----------------------------------------------------------
| WDEF_TITLE_RECT - compute title bar rect into scratch8
| Uses structRgn bounding box; result spans from struct top
| to top+titleBarHeight, full width minus 1px for shadow
| Called by: WDEF_DRAW, WDEF_ZOOM_CLAMP_OK, WDEF_DRAW_ZOOM, WDEF_TOGGLE_BOX, WDEF_TOGGLE_CLOSE (and 1 more)
WDEF_TITLE_RECT:
        LEA.L   (scratch8).w,A0                 | A0 -> scratch8
        MOVE.L  0x72(A3),A1                     | deref structRgn handle
        MOVE.L  (A1),A1                         | A1 = structRgn pointer
        ADDQ.W  #0x2,A1                         | skip rgnSize, point to bbox
        MOVE.L  (A1)+,(A0)                      | copy bbox.topLeft
        MOVE.L  (A1),0x4(A0)                    | copy bbox.botRight
        MOVE    (A0),D0                         | D0 = struct top
        ADD     D7,D0                           | bottom = top + title bar height
        MOVE    D0,0x4(A0)                      | set title bar bottom
        SUBQ.W  #0x1,0x6(A0)                    | right -= 1 (exclude shadow col)
        RTS                                     | return

| ----------------------------------------------------------
| wDraw param >= 4: toggle close box or zoom box highlight
| param = 4 -> close box; param = 5 -> zoom box
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
        LEA.L   (scratch8).w,A0                 | A0 -> scratch8
        MOVE    0x6(A0),0x2(A0)                 | left = right (right-align)
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
        LEA.L   (scratch8).w,A0                 | A0 -> scratch8
        MOVEQ.L #0x7,D1                         | offset +7px from left edge

| WDEF_ICON_DRAW - common icon positioning and CopyBits
| Builds 16x16 dest rect in scratch8, calls WDEF_COPYBITS to blit
WDEF_ICON_DRAW:
        ADD     D1,0x2(A0)                      | adjust left by h offset
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
        RTS                                     | return

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
| WDEF_DRAW_TITLE - draw window title string centered in title bar
| Clips to available space between close/zoom boxes.
| Returns D3 = left stripe right edge, D4 = right stripe left
WDEF_DRAW_TITLE:
        MOVE    (scratch8_6).w,D4               | D4 = title bar right edge
        MOVE    D4,D3                           | D3 = title bar right edge
        SUB     (scratch8_2).w,D3               | D3 = available width
        SUB     0x8A(A3),D3                     | subtract wTitleWidth
        ASR     #0x1,D3                         | center: half of remaining space
        MOVEQ.L #0x2,D0                         | min left margin = 2px
        TST.B   0x70(A3)                        | has close box?
        BEQ.B   WDEF_TITLE_MARGIN               | no -> use 2px margin
        MOVEQ.L #0x20,D0                        | min margin = 32px (past close box)
WDEF_TITLE_MARGIN:
        CMP     D0,D3                           | enough margin?
        BGE.B   WDEF_TITLE_ABS                  | yes -> keep computed width
        MOVE    D0,D3                           | enforce minimum margin
WDEF_TITLE_ABS:
        ADD     (scratch8_2).w,D3               | D3 = absolute title text left
        MOVE    D4,-(SP)                        | save right edge on stack
        BSR     WDEF_HAS_ZOOM                   | has zoom box?
        BEQ.B   WDEF_TITLE_CLIP                 | no -> use full width
        SUBI    #0x20,D4                        | reserve 32px for zoom box
WDEF_TITLE_CLIP:
        MOVE.L  -0xC(A6),-(SP)                  | push scratch region
        MOVE.L  (SP),-(SP)                      | dup for GetClip
        _GetClip                                | save current clip region
        MOVE    D4,(scratch8_6).w               | set clip right boundary
        PEA.L   (scratch8).w                    | push clip rect
        _ClipRect                               | clip to title text area
        MOVE.L  (A5),A0                         | deref QD globals
        MOVE.L  (A0),A0                         | deref thePort
        MOVE.L  0x1C(A0),-(SP)                  | push port's clipRgn handle
        MOVE.L  (SP),-(SP)                      | dup for SectRgn dest
        _SectRgn                                | intersect with port clip
        MOVE    (SP)+,(scratch8_6).w            | restore saved right edge
        MOVE    D3,-(SP)                        | push title text h position
        MOVE    (scratch8).w,D0                 | D0 = title bar top
        ADD     -0x8(A6),D0                     | + font ascent = baseline
        ADDQ.W  #0x1,D0                         | +1 for pixel alignment
        MOVE    D0,-(SP)                        | push v position
        _MoveTo                                 | position pen for title text
        MOVE.L  0x86(A3),A0                     | deref wTitleHandle
        MOVE.L  (A0),-(SP)                      | push title string pointer
        _DrawString                             | draw the window title
        MOVE.L  -0xC(A6),-(SP)                  | push saved clip region
        _SetClip                                | restore saved clip region
        MOVE    D3,D0                           | D0 = title text left
        SUBQ.W  #0x6,D3                         | D3 -= 6 (gap before title text)
        ADD     0x8A(A3),D0                     | D0 += wTitleWidth = text right
        CMP     D4,D0                           | past clip boundary?
        BGE.B   WDEF_TITLE_GAP                  | yes -> keep clip limit
        MOVE    D0,D4                           | clamp D4 to text right edge
WDEF_TITLE_GAP:
        ADDQ.W  #0x6,D4                         | add 6px gap after title text
        RTS                                     | return

| ----------------------------------------------------------
| Bitmap data for close and zoom box icons (16x16 each)
| Each is 32 bytes: 2 blank rows, 12 icon rows, 2 blank rows
|
| WDEF_ZOOM_NORMAL - zoom box, normal (two overlapping rectangles)
WDEF_ZOOM_NORMAL:
  .byte  0x00,0x00,0x00,0x00,0xBF,0xFB          | rows 0-2: blank, blank, top border
  .byte 0x20,0x88,0xA0,0x8B,0x20,0x88           | rows 3-5: overlapping rect interior
  .byte 0xA0,0x8B,0x20,0x88,0xBF,0x8B           | rows 6-8: front rect bottom border
  .byte 0x20,0x08,0xA0,0x0B,0x20,0x08           | rows 9-11: back rect interior
  .byte 0xBF,0xFB,0x00,0x00,0x00,0x00           | rows 12-14: bottom border, blank
  .byte 0x00,0x00                               | row 15: blank
| WDEF_ZOOM_TOGGLE - zoom box, toggled (XOR pattern for highlight)
WDEF_ZOOM_TOGGLE:
  .byte  0x00,0x00,0x00,0x00,0x00,0x00          | rows 0-2: blank
  .byte 0x01,0x80,0x09,0xA0,0x05,0xC0           | rows 3-5: XOR highlight bits
  .byte 0x00,0x80,0x1C,0xF0,0x1F,0x80           | rows 6-8: center XOR pattern
  .byte 0x05,0x40,0x09,0x20,0x01,0x00           | rows 9-11: lower XOR bits
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | rows 12-14: blank
  .byte 0x00,0x00                               | row 15: blank
| WDEF_CLOSE_NORMAL - close box, normal (empty square)
WDEF_CLOSE_NORMAL:
  .byte  0x00,0x00,0x00,0x00,0xBF,0xFB          | rows 0-2: blank, blank, top border
  .byte 0x20,0x08,0xA0,0x0B,0x20,0x08           | rows 3-5: hollow square interior
  .byte 0xA0,0x0B,0x20,0x08,0xA0,0x0B           | rows 6-8: hollow square interior
  .byte 0x20,0x08,0xA0,0x0B,0x20,0x08           | rows 9-11: hollow square interior
  .byte 0xBF,0xFB,0x00,0x00,0x00,0x00           | rows 12-14: bottom border, blank
  .byte 0x00,0x00                               | row 15: blank
| WDEF_CLOSE_TOGGLE - close box, toggled (XOR pattern for highlight)
WDEF_CLOSE_TOGGLE:
  .byte  0x00,0x00,0x00,0x00,0x00,0x00          | rows 0-2: blank
  .byte 0x01,0x00,0x09,0x20,0x05,0x40           | rows 3-5: XOR highlight bits
  .byte 0x00,0x00,0x1C,0x70,0x00,0x00           | rows 6-8: center X pattern
  .byte 0x05,0x40,0x09,0x20,0x01,0x00           | rows 9-11: lower XOR bits
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | rows 12-14: blank
  .byte 0x00,0x00                               | row 15: blank

| ----------------------------------------------------------
| wHit handler - determine which window part was clicked
| D3 = click point (v in high word, h in low word)
| Returns via 0x14(A6): wNoHit=0, wInContent=1, wInDrag=2,
| wInGrow=3, wInGoAway=4, wInZoomIn=5, wInZoomOut=6
WDEF_HIT:
        CLR     -(SP)                           | space for PtInRgn result
        MOVE.L  D3,-(SP)                        | push click point
        MOVE.L  0x76(A3),-(SP)                  | push contRgn handle
        _PtInRgn                                | check if point is in contRgn
        TST.B   (SP)+                           | in content region?
        BEQ.B   WDEF_HIT_TITLEBAR               | no -> test title bar
        TST     D5                              | documentProc?
        BNE.B   WDEF_HIT_CONTENT                | other style -> wInContent
        BTST    #0x2,D6                         | varCode bit 2 set?
        BGT.B   WDEF_HIT_CONTENT                | yes -> no grow box test
        TST.B   0x6F(A3)                        | wHilited (active)?
        BEQ.B   WDEF_HIT_CONTENT                | inactive -> wInContent
        MOVE.L  0x76(A3),A0                     | deref contRgn
        MOVE.L  (A0),A0                         | A0 = contRgn pointer
        MOVE.L  0x6(A0),D0                      | D0 = contRgn bbox botRight
        MOVEQ.L #0xE,D4                         | grow box = 14px from corner
        SUB     D4,D0                           | D0.w = right - 14
        CMP     D0,D3                           | click h >= right-14?
        BLT.B   WDEF_HIT_CONTENT                | no -> wInContent
        SWAP    D0                              | D0.w = bottom - 14
        SUB     D4,D0                           | bottom -= 14
        SWAP    D3                              | D3.w = click v
        CMP     D0,D3                           | click v >= bottom-14?
        BLT.B   WDEF_HIT_CONTENT                | no -> wInContent
        MOVEQ.L #0x3,D0                         | wInGrow
        BRA     WDEF_HIT_RETURN                 | return hit result

| ----------------------------------------------------------
| return wInContent
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
        TST.B   0x6F(A3)                        | wHilited (active)?
        BEQ.B   WDEF_HIT_DRAG                   | inactive -> wInDrag only
        MOVE.L  D3,D0                           | compute vertical offset in title
        SWAP    D0                              | D0.w = click v
        ADD     PORTBOUNDS(A3),D0               | convert to local v coord
        SUB     PORTRECT(A3),D0                 | offset from port top
        ADD     -0x2(A6),D0                     | add icon centering offset
        BPL.B   WDEF_HIT_DRAG                   | below icon row -> wInDrag
        ADDI    #0xB,D0                         | within 11px of icon center?
        BMI.B   WDEF_HIT_DRAG                   | above icon row -> wInDrag
        TST.B   0x70(A3)                        | wGoAway (has close box)?
        BEQ.B   WDEF_HIT_ZOOM                   | no -> check zoom box
        MOVE.L  D3,D0                           | test close box h range
        ADD     0xA(A3),D0                      | + portBounds.left
        SUB     0x12(A3),D0                     | - portRect.left
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
        ADD     0xA(A3),D0                      | + portBounds.left
        SUB     0x16(A3),D0                     | - portRect.right
        CMPI    #-0x13,D0                       | >= 19px left of right edge?
        BLT.B   WDEF_HIT_DRAG                   | too far left -> wInDrag
        CMPI    #-0x9,D0                        | <= 9px left of right edge?
        BGT.B   WDEF_HIT_DRAG                   | too close to edge -> wInDrag
        BSR     WDEF_CHECK_ZOOM_ST              | check if zoom state changed
        BEQ.B   WDEF_HIT_ZOOM_IN                | at user state -> wInZoomIn
        MOVEQ.L #0x6,D0                         | wInZoomOut (return to user state)
        BRA.B   WDEF_HIT_RETURN                 | return hit result

| ----------------------------------------------------------
| at user state: clicking zoom -> zoom to standard state
WDEF_HIT_ZOOM_IN:
        MOVEQ.L #0x5,D0                         | wInZoomIn
        BRA.B   WDEF_HIT_RETURN                 | return hit result

| ----------------------------------------------------------
| in title bar but not on close/zoom -> drag region
WDEF_HIT_DRAG:
        MOVEQ.L #0x2,D0                         | wInDrag
WDEF_HIT_RETURN:
        MOVE.L  D0,0x14(A6)                     | store hit result for caller
WDEF_HIT_NOHIT:
        RTS                                     | return

| ----------------------------------------------------------
| wCalcRgns handler - compute contRgn and structRgn
| contRgn = portRect converted to global coordinates
| structRgn = contRgn expanded by border, title bar, shadow
WDEF_CALCRGNS:
        BSR     WDEF_HAS_ZOOM                   | has zoom box?
        BEQ.B   WDEF_CALC_CONT                  | no -> skip zoom state update
        BSR     WDEF_CHECK_ZOOM_ST              | update zoom state if needed
WDEF_CALC_CONT:
        LEA.L   (scratch8).w,A0                 | A0 -> scratch8
        MOVE.L  A0,-(SP)                        | push rect ptr for OffsetRect
        MOVE.L  PORTRECT(A3),(A0)+              | copy portRect.topLeft
        MOVE.L  0x14(A3),(A0)                   | copy portRect.botRight
        MOVE.L  PORTBOUNDS(A3),-(SP)            | push portBounds origin
        NEG     (SP)                            | negate top (local->global)
        NEG     0x2(SP)                         | negate left
        _OffsetRect                             | convert rect to global coords
        MOVE.L  0x76(A3),-(SP)                  | push contRgn handle
        PEA.L   (scratch8).w                    | push global portRect
        _RectRgn                                | contRgn = global portRect
        MOVE.L  #0x20002,D4                     | shadow offset (2,2) for dBoxProc
        MOVE.L  0x72(A3),-(SP)                  | push structRgn handle
        PEA.L   (scratch8).w                    | push rect for InsetRect
        MOVE.L  (SP),-(SP)                      | dup for RectRgn
        MOVE.L  (MinusOne).w,-(SP)              | expand by (-1,-1) for border
        _InsetRect                              | grow rect by 1px for border
        TST     D5                              | documentProc?
        BNE.B   WDEF_CALC_DBOX                  | other style -> check dBoxProc
        MOVE    D7,D0                           | title bar height
        SUBQ.W  #0x1,D0                         | minus 1 for border overlap
        SUB     D0,(scratch8).w                 | extend top for title bar
        LSR.L   #0x1,D4                         | shadow = (1,1) for document
WDEF_CALC_STRUCT:
        _RectRgn                                | structRgn = expanded rect
        TST     D5                              | doc or altDBox need shadow rgn
        BEQ.B   WDEF_CALC_SHADOW                | documentProc -> needs shadow rgn
        CMPI    #0x3,D5                         | altDBoxProc?
        BNE.B   WDEF_CALC_DONE                  | plainDBox/dBox -> no shadow
WDEF_CALC_SHADOW:
        MOVE.L  -0xC(A6),-(SP)                  | push scratch region
        PEA.L   (scratch8).w                    | push shadow rect
        MOVE.L  (SP),-(SP)                      | dup for RectRgn
        MOVE.L  D4,-(SP)                        | push shadow offset
        _OffsetRect                             | shift rect down-right for shadow
        _RectRgn                                | scratch = shadow rect region
        MOVE.L  0x72(A3),-(SP)                  | push structRgn
        MOVE.L  -0xC(A6),-(SP)                  | push shadow region
        MOVE.L  0x72(A3),-(SP)                  | push dest = structRgn
        _UnionRgn                               | structRgn = frame union shadow
WDEF_CALC_DONE:
        RTS                                     | return

| ----------------------------------------------------------
| dBoxProc: expand struct rect by 7px for thick double border
WDEF_CALC_DBOX:
        CMPI    #0x1,D5                         | dBoxProc?
        BNE.B   WDEF_CALC_STRUCT                | no -> plainDBox or altDBox
        PEA.L   (scratch8).w                    | push struct rect
        MOVE.L  #0xFFF9FFF9,-(SP)               | inset by -7,-7 (expand 7px)
        _InsetRect                              | grow rect for double border
        BRA.B   WDEF_CALC_STRUCT                | go create structRgn

| ----------------------------------------------------------
| wGrow handler - draw grow image (rubber-band outline)
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
        MOVE    PORTBITS(A3),-(SP)              | push rect.top
        MOVE    0x4(A3),-(SP)                   | push rect.bottom
        SUBI    #0x10,(SP)                      | bottom - 16 = h scroll divider
        MOVE.L  (SP),-(SP)                      | push copy for MoveTo
        _MoveTo                                 | move to h scroll divider left
        MOVE    0x6(A3),0x2(SP)                 | set h = right edge
        _LineTo                                 | draw horizontal scroll divider
        MOVE.L  (SP),(A3)                       | restore original top
        MOVE.L  (SP),-(SP)                      | push copy for MoveTo
        _MoveTo                                 | move to title bar bottom
        MOVE    0x6(A3),0x2(SP)                 | set h = right
        _LineTo                                 | draw title bar bottom line
        MOVE    0x6(A3),-(SP)                   | push right edge
        SUBI    #0x10,(SP)                      | right - 16 = v scroll divider
        MOVE    (A3),-(SP)                      | push top
        MOVE.L  (SP),-(SP)                      | push copy for MoveTo
        _MoveTo                                 | move to v scroll divider top
        MOVE    0x4(A3),(SP)                    | set v = bottom
        _LineTo                                 | draw vertical scroll divider
        MOVE.L  D3,-(SP)                        | push grow rect
        MOVE.L  (OneOne).w,-(SP)                | push inset (1,1)
        _InsetRect                              | shrink back by (1,1)
        RTS                                     | return

| ----------------------------------------------------------
| WDEF_DROP_SHADOW - draw drop shadow (L-shaped: bottom + right edges)
| A4 -> struct bounding rect, D4 = shadow pen size
WDEF_DROP_SHADOW:
        MOVE.L  D4,-(SP)                        | push pen size
        _PenSize                                | set pen to shadow thickness
        MOVE    0x6(A4),D0                      | D0 = right edge
        MOVE    D0,-(SP)                        | push right for top-right corner
        MOVE    (A4),-(SP)                      | push top
        ADD     D4,(SP)                         | offset top down by shadow width
        MOVE    D0,-(SP)                        | push right for bottom-right
        MOVE    0x4(A4),D0                      | D0 = bottom edge
        MOVE    D0,-(SP)                        | push bottom
        MOVE    0x2(A4),-(SP)                   | push left edge
        ADD     D4,(SP)                         | offset left by shadow width
        MOVE    D0,-(SP)                        | push bottom for start point
        _MoveTo                                 | move to bottom-left of shadow
        _LineTo                                 | draw bottom shadow line (right)
        _LineTo                                 | draw right shadow line (up)
        _PenNormal                              | reset pen state
        RTS                                     | return

| ----------------------------------------------------------
| WDEF_COPYBITS - CopyBits a small icon bitmap into the window frame
| A1 = source bitmap data, D0 = transfer mode, D1 = bounds
| Builds temporary BitMap struct in IconBitmap low-memory,
| blits from icon data into WMgrPort at scratch8 dest rect
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
        PEA.L   0x2(A1)                         | push dest portBits
        PEA.L   0x6(A0)                         | push source bounds rect
        PEA.L   (scratch8).w                    | push dest rect
        MOVE    D0,-(SP)                        | push transfer mode
        CLR.L   -(SP)                           | no mask region
        _CopyBits                               | blit icon to window frame
        RTS                                     | return

| ----------------------------------------------------------
| wGIcon handler - draw grow icon (size box) in content region
| Switches to the window's own port, draws size box bitmap
| at bottom-right corner, and scroll bar divider lines
WDEF_GICON:
        MOVE.L  A3,-(SP)                        | push WindowRecord pointer
        _SetPort                                | set port to window itself
        LEA.L   (scratch8).w,A4                 | A4 -> scratch8
        MOVE.L  0x14(A3),0x4(A4)                | botRight = portRect.botRight
        MOVE.L  0x4(A4),(A4)                    | topLeft = botRight initially
        SUBI    #0xF,(A4)                       | top = bottom - 15
        SUBI    #0xF,0x2(A4)                    | left = right - 15
        TST.B   0x6F(A3)                        | wHilited (window active)?
        BEQ.B   WDEF_GICON_INACTIVE             | inactive -> erase size box
        LEA.L   WDEF_SIZEBOX_ICON(PC),A1        | size box icon bitmap
        MOVEQ.L #0x0,D0                         | srcCopy mode
        MOVE.L  #0x100010,D1                    | bounds = 16x16
        BSR.B   WDEF_COPYBITS                   | draw size box icon
WDEF_GICON_DIVIDERS:
        MOVE    0x2(A4),-(SP)                   | push size box left (= divider x)
        MOVE    (SP),-(SP)                      | dup for LineTo h
        MOVE    PORTRECT(A3),-(SP)              | push portRect.top
        _MoveTo                                 | move to top of vertical divider
        MOVE    0x14(A3),-(SP)                  | push portRect.bottom
        _LineTo                                 | draw vertical scroll bar divider
        MOVE    0x12(A3),-(SP)                  | push portRect.left
        MOVE    (A4),-(SP)                      | push size box top (= divider y)
        _MoveTo                                 | move to left of horizontal divider
        MOVE    0x16(A3),-(SP)                  | push portRect.right
        MOVE    (A4),-(SP)                      | push same top
        _LineTo                                 | draw horizontal scroll bar divider
        RTS                                     | return

| ----------------------------------------------------------
| inactive window: erase size box area, then draw dividers
WDEF_GICON_INACTIVE:
        PEA.L   (scratch8).w                    | push size box rect
        _EraseRect                              | erase size box area
        BRA.B   WDEF_GICON_DIVIDERS             | draw divider lines anyway

| ----------------------------------------------------------
| WDEF_SIZEBOX_ICON - size box (grow icon) bitmap, 16x16
| Two overlapping rectangles representing a resizable window
WDEF_SIZEBOX_ICON:
  .byte  0x00,0x00,0x00,0x00,0x00,0x00          | rows 0-2: blank
  .byte 0x1F,0xE0,0x10,0x20,0x10,0x3E           | rows 3-5: large rect top + small rect
  .byte 0x10,0x22,0x10,0x22,0x10,0x22           | rows 6-8: overlapping interiors
  .byte 0x10,0x22,0x1F,0xE2,0x04,0x02           | rows 9-11: large bottom, small interior
  .byte 0x04,0x02,0x04,0x02,0x07,0xFE           | rows 12-14: small rect bottom border
  .byte 0x00,0x00                               | row 15: blank

| end of resource : 'WDEF' 0

| resource header
  .long 0xC000054E                              | Length
  .long 0x00000074                              | ?

