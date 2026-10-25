| =========================================================================
| CDEF 1 -- the standard scroll bar control definition function (Apple:
| ScrollBarProc, ScrollBarCDEF.a)
| =========================================================================
| ROM offsets +0x37D52..+0x3824B: the 8-byte header of the ROM resource at
| +0x37D52 (see CDEF 0), then the resource data, 1266 bytes from +0x37D5A
| (_CDEF_1_ in MacSEROM.lst) on; type CDEF, ID 1, no name, attributes $58
| (resSysHeap, resLocked, resProtected). The same in both SE ROMs.
|
| Version: the defproc header says version 2. Against the change history
| of Apple's ScrollBarCDEF.a (System 7.1 sources, version 11, rewritten in
| 1990 for shaded color scroll bars) this is the code of Andy Hertzfeld
| (1982-83) with variant 1 (SC, 7/30/83: "no grey or elevator"), "254"
| hiliting and min = max acting inactive (12/27/83), the thumb filled
| white with FillRgn (SC, 4/13/84) and EHB's changes of 1985 (4/18/85: no
| frame when only an arrow is drawn; 5/16/85: return 254 only if the point
| is in the control) -- but none of the color support of 1986 (Reno,
| nuMac: auxiliary control color tables) and nothing later (messages
| 10-12, DeviceLoop drawing, arrow and thumb icons).
|
| Calling convention as for CDEF 0 (IM I-328):
|   FUNCTION ScrollBarProc(varCode: INTEGER; theControl: ControlHandle;
|                          message: INTEGER; param: LONGINT): LONGINT;
| with the same stack frame (.set names below); IndicatorRect (-30) holds
| the thumb rectangle computed by CalcIBox.
|
| Variation code: 0 = standard scroll bar (procID 16, scrollBarProc);
| 1 = arrows only: no gray page area, no thumb (procID 17). Whether a bar
| is vertical or horizontal follows from contrlRect (TestHV): the shorter
| side, the "minor dimension" (normally 16), is the size of the two arrow
| boxes and of the square thumb; the gray area between the arrows minus
| the thumb is the travel that the value range is mapped onto.
|
| Messages (IM I-329..I-332); there is no range check (the Control Manager
| sends only 0-8):
|   0 drawCntl   DrawSBar   param low byte = part to draw: 0 or 255 = all;
|                           inUpButton (20), inDownButton (21) = that
|                           arrow; inThumb (129) = gray area and thumb;
|                           anything else (254) = nothing
|   1 testCntl   HitSBar    param = point; result inUpButton,
|                           inDownButton, inPageUp (22), inPageDown (23),
|                           inThumb; 254 for contrlHilite 254; 0 outside
|                           or when inactive
|   2 calcCRgns  CalcSBar   param = region handle; high bit set: the thumb
|                           region (and DragPattern := the scroll bar
|                           pattern), else contrlRect
|   3 initCntl   InitSBar   contrlData := a new (thumb) region
|   4 dispCntl   DispSBar   dispose of the thumb region
|   5 posCntl    MoveSBar   param = offset the thumb was dragged by:
|                           compute and set (SetCtlValue) the new value
|   6 thumbCntl  ThumbSBar  param = pointer to limitRect, slopRect, axis
|                           for the thumb drag (DragGrayRgn)
|   7 dragCntl   StubSBar   result 0: default dragging
|   8 autoTrack  StubSBar   nothing to do
|
| Drawing: the arrows are 16 x 16 bitmaps (with the box frame) copied into
| the arrow boxes by CopyBits, scaled to the box size; the arrow whose part
| code is in contrlHilite is drawn filled. The gray area is filled with
| pattern PAT 17 (sBarPatID, light gray, from the System file via
| GetPattern), the thumb region (contrlData, a rectangle inset by 1 across
| the bar) filled white and framed, then contrlRect is framed. Inactive
| ("disabled": contrlHilite 255 or 254, or contrlMin = contrlMax): the gray
| area is white and there is no thumb.
|
| Registers in the message routines: A3 = control handle, A0 = control
| pointer (on entry), D3 = param, D6 = variation code. TempRect (the
| low-memory scratch rectangle at $9FA) holds the rectangle being drawn,
| IconBitmap ($A0E) the BitMap of the arrow being copied.
|
| Sources: Mac OS 7.1 Toolbox/ControlMgr/ScrollBarCDEF.a (Apple's routine
| and label names; its comments where the code is still the same: the
| dispatcher, ShouldIDraw, TestHV, CalcIBox, GetCtlRect, HitSBar,
| CalcSBar, MoveSBar, InitSBar, DispSBar, RoundOff, ThumbSBar), Inside
| Macintosh I "The Control Manager".
| =========================================================================

| Stack frame of ScrollBarProc (offsets from A6 after the LINK)
.set CDEF1_PARAM, 8                             | param (long)
.set CDEF1_MESSAGE, 12                          | message (word)
.set CDEF1_CTLHNDL, 14                          | theControl (ControlHandle)
.set CDEF1_VARCODE, 18                          | varCode (word)
.set CDEF1_RESULT, 20                           | function result (long)
.set CDEF1_SAVEPEN, -20                         | SavePen: caller's PenState (18 bytes)
.set CDEF1_INDICATORRECT, -30                   | IndicatorRect: the thumb rectangle (8 bytes)
.set CDEF1_FRAMESIZE, -30                       | FrameSize: size of the locals
| thumbCntl parameter record (Apple's local variable equates)
.set CDEF1_BRECT, 0                             | BRect: limitRect (boundsRect)
.set CDEF1_SRECT, 8                             | SRect: slopRect
.set CDEF1_TAXIS, 16                            | TAxis: axis

| -------------------------------------------------------------------------
| ROM resource header (block header, see CDEF 0)
| -------------------------------------------------------------------------
Resource_CDEF_0001:
Resource_CDEF_0001_Header:
        .long   0xC00004FA                      | ROM resource header: tag $C0, physical size $4FA (8 + $4F2)
        .long   0x00000084                      | relative handle: master pointer at ROM zone + $84

| -------------------------------------------------------------------------
| Entry point and Apple's standard defproc header: a branch around it,
| flags, resource type, resource ID and version number.
| -------------------------------------------------------------------------
CDEF1_ENTRY:
_CDEF_1_:
        BRA.B   CDEF1_START                     | skip header
        .short  0x0000                          | flags
        .ascii  "CDEF"                          | resource type
        .short  0x0001                          | resource ID 1
        .short  0x0002                          | version 2

| -------------------------------------------------------------------------
| ScrollBarProc -- save the registers and the pen state, fetch the
| parameters and dispatch on the message through GoScrollBar (no check of
| the message number).
| -------------------------------------------------------------------------
CDEF1_START:
        LINK    A6,#CDEF1_FRAMESIZE             | set up a stack frame to address parameters
        MOVEM.L D3-D6/A1-A4,-(SP)               | save work registers
| save the penState and set it our way
        PEA.L   CDEF1_SAVEPEN(A6)               | push pointer to savePenState
        _GetPenState                            | remember current penState
        _PenNormal                              | set the pen the way we want it
| fetch the parameters into registers
        LEA.L   CDEF1_PARAM(A6),A0              | get ptr to first parameter
        MOVE.L  (A0)+,D3                        | get param in D3
        MOVE.W  (A0)+,D0                        | get message
        MOVEA.L (A0)+,A3                        | get the control handle
        MOVE.W  (A0)+,D6                        | get selection index (variation code)
        CLR.L   (A0)                            | clear out function result
        MOVEA.L (A3),A0                         | get control pointer in A0
| case out on the message number
        ADD.W   D0,D0                           | double for word index
        LEA.L   CDEF1_GOSCROLLBAR(PC),A1        | get table address
        ADDA.W  0x0(A1,D0.W),A1                 | compute dispatch address
        JSR     (A1)                            | dispatch: DrawSBar ... ThumbSBar, StubSBar
| restore original pen state
        PEA.L   CDEF1_SAVEPEN(A6)               | push savePenState
        _SetPenState                            | restore original pen state
| we're done -- restore registers and return to caller
        MOVEM.L (SP)+,D3-D6/A1-A4               | restore work registers
        UNLK    A6                              | unlink stack frame
        MOVEA.L (SP)+,A0                        | get return address
        ADDA.W  #0xC,SP                         | strip parameters
        JMP     (A0)                            | return to caller

| GoScrollBar -- dispatch table: offsets of the message routines from the
| table, indexed by message * 2
CDEF1_GOSCROLLBAR:
        .short  CDEF1_DRAWSBAR-CDEF1_GOSCROLLBAR | draw is message 0
        .short  CDEF1_HITSBAR-CDEF1_GOSCROLLBAR | hit test is message 1
        .short  CDEF1_CALCSBAR-CDEF1_GOSCROLLBAR | calc regions is message 2
        .short  CDEF1_INITSBAR-CDEF1_GOSCROLLBAR | allocate indicator region (3)
        .short  CDEF1_DISPSBAR-CDEF1_GOSCROLLBAR | de-allocate indicator region (4)
        .short  CDEF1_MOVESBAR-CDEF1_GOSCROLLBAR | move indicator call (5)
        .short  CDEF1_THUMBSBAR-CDEF1_GOSCROLLBAR | message 6 is thumb dragging
        .short  CDEF1_STUBSBAR-CDEF1_GOSCROLLBAR | message 7 (dragCntl): stub
        .short  CDEF1_STUBSBAR-CDEF1_GOSCROLLBAR | message 8 (autoTrack): stub

| -------------------------------------------------------------------------
| Arrow bitmaps: 16 x 16 pixels with the box frame, rowBytes 2, 32 bytes
| each; PlotSymbol builds the BitMap around them in IconBitmap. Each
| arrow is followed by its hilited (filled) version. DrawSBar points A1
| at the left arrow (first arrow box, inUpButton) or at the right arrow
| (second box, inDownButton); DrawArrowBox adds $20 for the hilited
| version and $80 for a vertical bar (left -> up, right -> down).
| -------------------------------------------------------------------------
| right arrow (second arrow of a horizontal bar) ($37DB8)
CDEF1_RIGHTARROW:
        .short  0xFFFF                          | ################
        .short  0x8081                          | #.......#......#
        .short  0x80C1                          | #.......##.....#
        .short  0x80A1                          | #.......#.#....#
        .short  0x8F91                          | #...#####..#...#
        .short  0x8809                          | #...#.......#..#
        .short  0x8805                          | #...#........#.#
        .short  0x8803                          | #...#.........##
        .short  0x8805                          | #...#........#.#
        .short  0x8809                          | #...#.......#..#
        .short  0x8F91                          | #...#####..#...#
        .short  0x80A1                          | #.......#.#....#
        .short  0x80C1                          | #.......##.....#
        .short  0x8081                          | #.......#......#
        .short  0x8001                          | #..............#
        .short  0xFFFF                          | ################
| right arrow, hilited ($37DD8)
CDEF1_RIGHTARROWHILITED:
        .short  0xFFFF                          | ################
        .short  0x8081                          | #.......#......#
        .short  0x80C1                          | #.......##.....#
        .short  0x80E1                          | #.......###....#
        .short  0x8FF1                          | #...########...#
        .short  0x8FF9                          | #...#########..#
        .short  0x8FFD                          | #...##########.#
        .short  0x8FFF                          | #...############
        .short  0x8FFD                          | #...##########.#
        .short  0x8FF9                          | #...#########..#
        .short  0x8FF1                          | #...########...#
        .short  0x80E1                          | #.......###....#
        .short  0x80C1                          | #.......##.....#
        .short  0x8081                          | #.......#......#
        .short  0x8001                          | #..............#
        .short  0xFFFF                          | ################
| left arrow (first arrow of a horizontal bar) ($37DF8)
CDEF1_LEFTARROW:
        .short  0xFFFF                          | ################
        .short  0x8101                          | #......#.......#
        .short  0x8301                          | #.....##.......#
        .short  0x8501                          | #....#.#.......#
        .short  0x89F1                          | #...#..#####...#
        .short  0x9011                          | #..#.......#...#
        .short  0xA011                          | #.#........#...#
        .short  0xC011                          | ##.........#...#
        .short  0xA011                          | #.#........#...#
        .short  0x9011                          | #..#.......#...#
        .short  0x89F1                          | #...#..#####...#
        .short  0x8501                          | #....#.#.......#
        .short  0x8301                          | #.....##.......#
        .short  0x8101                          | #......#.......#
        .short  0x8001                          | #..............#
        .short  0xFFFF                          | ################
| left arrow, hilited ($37E18)
CDEF1_LEFTARROWHILITED:
        .short  0xFFFF                          | ################
        .short  0x8101                          | #......#.......#
        .short  0x8301                          | #.....##.......#
        .short  0x8701                          | #....###.......#
        .short  0x8FF1                          | #...########...#
        .short  0x9FF1                          | #..#########...#
        .short  0xBFF1                          | #.##########...#
        .short  0xFFF1                          | ############...#
        .short  0xBFF1                          | #.##########...#
        .short  0x9FF1                          | #..#########...#
        .short  0x8FF1                          | #...########...#
        .short  0x8701                          | #....###.......#
        .short  0x8301                          | #.....##.......#
        .short  0x8101                          | #......#.......#
        .short  0x8001                          | #..............#
        .short  0xFFFF                          | ################
| down arrow (second arrow of a vertical bar) ($37E38)
CDEF1_DOWNARROW:
        .short  0xFFFF                          | ################
        .short  0x8001                          | #..............#
        .short  0x8001                          | #..............#
        .short  0x8FE1                          | #...#######....#
        .short  0x8821                          | #...#.....#....#
        .short  0x8821                          | #...#.....#....#
        .short  0x8821                          | #...#.....#....#
        .short  0xF83D                          | #####.....####.#
        .short  0xA009                          | #.#.........#..#
        .short  0x9011                          | #..#.......#...#
        .short  0x8821                          | #...#.....#....#
        .short  0x8441                          | #....#...#.....#
        .short  0x8281                          | #.....#.#......#
        .short  0x8101                          | #......#.......#
        .short  0x8001                          | #..............#
        .short  0xFFFF                          | ################
| down arrow, hilited ($37E58)
CDEF1_DOWNARROWHILITED:
        .short  0xFFFF                          | ################
        .short  0x8001                          | #..............#
        .short  0x8001                          | #..............#
        .short  0x8FE1                          | #...#######....#
        .short  0x8FE1                          | #...#######....#
        .short  0x8FE1                          | #...#######....#
        .short  0x8FE1                          | #...#######....#
        .short  0xFFFD                          | ##############.#
        .short  0xBFF9                          | #.###########..#
        .short  0x9FF1                          | #..#########...#
        .short  0x8FE1                          | #...#######....#
        .short  0x87C1                          | #....#####.....#
        .short  0x8381                          | #.....###......#
        .short  0x8101                          | #......#.......#
        .short  0x8001                          | #..............#
        .short  0xFFFF                          | ################
| up arrow (first arrow of a vertical bar) ($37E78)
CDEF1_UPARROW:
        .short  0xFFFF                          | ################
        .short  0x8001                          | #..............#
        .short  0x8101                          | #......#.......#
        .short  0x8281                          | #.....#.#......#
        .short  0x8441                          | #....#...#.....#
        .short  0x8821                          | #...#.....#....#
        .short  0x9011                          | #..#.......#...#
        .short  0xA009                          | #.#.........#..#
        .short  0xF83D                          | #####.....####.#
        .short  0x8821                          | #...#.....#....#
        .short  0x8821                          | #...#.....#....#
        .short  0x8821                          | #...#.....#....#
        .short  0x8FE1                          | #...#######....#
        .short  0x8001                          | #..............#
        .short  0x8001                          | #..............#
        .short  0xFFFF                          | ################
| up arrow, hilited ($37E98)
CDEF1_UPARROWHILITED:
        .short  0xFFFF                          | ################
        .short  0x8001                          | #..............#
        .short  0x8101                          | #......#.......#
        .short  0x8381                          | #.....###......#
        .short  0x87C1                          | #....#####.....#
        .short  0x8FE1                          | #...#######....#
        .short  0x9FF1                          | #..#########...#
        .short  0xBFF9                          | #.###########..#
        .short  0xFFFD                          | ##############.#
        .short  0x8FE1                          | #...#######....#
        .short  0x8FE1                          | #...#######....#
        .short  0x8FE1                          | #...#######....#
        .short  0x8FE1                          | #...#######....#
        .short  0x8001                          | #..............#
        .short  0x8001                          | #..............#
        .short  0xFFFF                          | ################

| -------------------------------------------------------------------------
| DrawSBar draws a scroll bar as specified by the controlHandle in A3 (message
| 0, drawCntl). D3 has the desired "hilite" area code.
|   D3 (in)  low byte: part to draw (ShouldIDraw): 0 or 255 = all (255:
|            HiliteControl to or from 255); inUpButton, inDownButton =
|            that arrow box only; inThumb = gray area and thumb (the
|            thumb has moved: SetCtlValue, SetCtlMin, SetCtlMax pass 129)
|   A0 (in)  control pointer
| Draws the two arrow boxes (DrawArrowBox); then, unless only an arrow is
| wanted, for variant 0 the gray area (FillRect with the scroll bar
| pattern, white if inactive) and the thumb (DoIndicator); last frames
| contrlRect (FrameCtl). Changes D0-D4/A0-A1.
| -------------------------------------------------------------------------
CDEF1_DRAWSBAR:
        TST.B   contrlVis(A0)                   | is it visible?
        BEQ.W   CDEF1_STUBSBAR                  | if not, don't draw
| if it was disabled, draw the whole thing
        CMPI.B  #0xFF,D3                        | part code 255 (inactive)?
        BNE.B   CDEF1_DRAWSBAR_GO               | if not, skip
        MOVEQ.L #0x0,D3                         | if so, draw all
CDEF1_DRAWSBAR_GO:
        MOVE.B  contrlHilite(A0),D4             | get current hilite in register (not used)
        BSR.W   CDEF1_GETTCTLRECT               | copy the control rect into tempRect
        BSR.W   CDEF1_TESTHV                    | get horizontal/vertical index in D0
| adjust for 1st arrow (if we're supposed to)
        MOVE.W  0x0(A1,D0.W),D1                 | get vertical coordinate (logical top)
        ADD.W   D2,D1                           | compute bottom
        MOVE.W  D1,0x4(A1,D0.W)                 | update bottom
        LEA.L   CDEF1_LEFTARROW(PC),A1          | left arrow (up arrow if vertical)
        MOVEQ.L #inUpButton,D1                  | signal 1st arrow
        MOVEM.W D0/D2,-(SP)                     | remember hv selector
        BSR.B   CDEF1_SHOULDIDRAW               | test hilite to see if we should draw
        BNE.B   CDEF1_SKIPUP                    | no: skip the first arrow
        BSR.W   CDEF1_DRAWARROWBOX              | draw the arrow box
| now do the other arrow
CDEF1_SKIPUP:
        BSR.W   CDEF1_GETTCTLRECT               | copy bounding rect into tempRect
        MOVEM.W (SP)+,D0/D2                     | restore hv selector
| adjust rect for 2nd arrow
        MOVE.W  0x4(A1,D0.W),D1                 | get bottom coordinate
        SUB.W   D2,D1                           | compute top
        MOVE.W  D1,0x0(A1,D0.W)                 | adjust box top
        LEA.L   CDEF1_RIGHTARROW(PC),A1         | right arrow (down arrow if vertical)
        MOVEQ.L #inDownButton,D1                | signal in 2nd arrow
        BSR.B   CDEF1_SHOULDIDRAW               | dont't draw if we done have to
        BNE.B   CDEF1_SKIPDOWN                  | no: skip the second arrow
        BSR.W   CDEF1_DRAWARROWBOX              | draw the arrow box
| paint the body of the scrollBar light gray
CDEF1_SKIPDOWN:
        CMPI.W  #0x1,D6                         | flavor one has no grey
        BEQ.W   CDEF1_FRAMECTL                  | so just frame it
        MOVE.W  #inThumb,D1                     | get thumb part code
        BSR.B   CDEF1_SHOULDIDRAW               | draw it?
        BNE.B   CDEF1_STUBSBAR                  | don't need to frame scrollbar
        BSR.W   CDEF1_GETTCTLRECT               | get control bounding rectangle
        MOVE.L  A1,-(SP)                        | push the rectangle (TempRect) for FillRect
        BSR.W   CDEF1_GETLTGRAY                 | A0 = the scroll bar pattern
        MOVE.L  A0,-(SP)                        | push the pattern for FillRect
        BSR.B   CDEF1_ISDISABLED                | is it disabled?
        BNE.B   CDEF1_DRAWSBAR_BODY             | if not, keep the gray
        MOVEA.L (A5),A0                         | get grafGlobals
        LEA.L   -0x8(A0),A0                     | get address of white pattern
        MOVE.L  A0,(SP)                         | white out the rect instead
CDEF1_DRAWSBAR_BODY:
        LEA.L   (TempRect).W,A1                 | the control rect
        MOVEA.L A1,A0                           | put in A0 for TestHV
        BSR.B   CDEF1_TESTHV                    | get h/v index
        SWAP    D2                              | get width in high part
        MOVE.W  #0x1,D2                         | get 1 in low part
        TST.W   D0                              | which dimension?
        BEQ.B   CDEF1_DRAWSBAR_INSET            | skip correction if vertical
        SWAP    D2                              | horizontal: inset the other way round
CDEF1_DRAWSBAR_INSET:
        MOVE.L  A1,-(SP)                        | push a pointer to the rectangle
        MOVE.L  D2,-(SP)                        | push inset factor
        _InsetRect                              | inset it: the area between the arrows
        _FillRect                               | fill it with the pattern
        BRA.B   CDEF1_DOINDICATOR               | go draw the thumb

| -------------------------------------------------------------------------
| Utility ShouldIDraw -- to test when to skip drawing a part of the
| scrollBar. On entry, D3 has parameter indicating part that needs drawing
| while D1 holds the part we are about to draw. If D3 is zero, always draw
| it. Otherwise, draw only if it matches. Returns with the Z flag set if
| the part should be drawn.
| StubSBar, its RTS, is also the routine of messages 7 and 8.
| Called by: CDEF1_DRAWSBAR (each arrow, the gray area)
| -------------------------------------------------------------------------
CDEF1_SHOULDIDRAW:
        TST.W   D3                              | examine the parameter
        BEQ.B   CDEF1_STUBSBAR                  | its zero so don't test further
        CMP.W   D1,D3                           | the right part
CDEF1_STUBSBAR:
        RTS                                     | the z-flag has the answer

| -------------------------------------------------------------------------
| IsDisabled is a utility to check to see if a scrollBar is disabled or
| not. It returns with the z-flag set if it is disabled: contrlHilite 255
| or 254, or contrlMin = contrlMax. (Apple's later version does not count
| 254 as disabled.)
|   A3 (in)   control handle
|   A0 (out)  control pointer; D0 changed
| Called by: CDEF1_DRAWSBAR, CDEF1_DOINDICATOR, CDEF1_HITSBAR
| -------------------------------------------------------------------------
CDEF1_ISDISABLED:
        MOVEA.L (A3),A0                         | get sBar pointer
        MOVE.B  contrlHilite(A0),D0             | get the hilite parameter
        ADDQ.B  #0x1,D0                         | was it 255?
        BEQ.B   CDEF1_DONECHECKING              | yes: disabled
        ADDQ.B  #0x1,D0                         | was it 254?
        BEQ.B   CDEF1_DONECHECKING              | yes: disabled
        MOVE.W  contrlMin(A0),D0                | get the min
        CMP.W   contrlMax(A0),D0                | same as the max?
CDEF1_DONECHECKING:
        RTS                                     | return to caller with z-flag result

| -------------------------------------------------------------------------
| DoIndicator -- DrawSBar's tail: compute the thumb (CalcIBox) and, unless
| the scroll bar is inactive, fill the thumb region white and frame it;
| then frame the scroll bar (FrameCtl, also the whole drawing of variant
| 1).
| -------------------------------------------------------------------------
CDEF1_DOINDICATOR:
        BSR.W   CDEF1_CALCIBOX                  | compute the thumb rect and region
        BSR.B   CDEF1_ISDISABLED                | is it disabled?
        BEQ.B   CDEF1_FRAMECTL                  | yes: no thumb, just frame the control
        MOVE.L  contrlData(A0),-(SP)            | push the thumb region for FrameRgn
        MOVE.L  (SP),-(SP)                      | and for FillRgn
        MOVEA.L (A5),A0                         | get grafGlobals
        PEA.L   -0x8(A0)                        | push the white pattern
        _FillRgn                                | fill the thumb white
        _FrameRgn                               | and frame it
| Frame the scroll bar
CDEF1_FRAMECTL:
        MOVEA.L (A3),A0                         | get pointer to control
        PEA.L   contrlRect(A0)                  | push the control rect
        _FrameRect                              | frame it
        RTS                                     | done drawing the scroll bar

| -------------------------------------------------------------------------
| TestHV is a utility that determines if the rectangle pointed to by A0 is
| more horizontal or vertical. Return 0 in D0 if its more vertical and 2
| if its more horizontal. This routine trashes D1. The result is also
| reflected in the condition code. It also returns the width/height of the
| minor dimension in D2.
|   A0 (in)   rectangle
|   D0 (out)  0 = vertical, 2 = horizontal: the offset of the coordinate
|             along the bar in a Rect or Point (top/bottom or left/right)
|   D2 (out)  the minor dimension: the size of the arrow boxes and thumb
|   Z (out)   set if vertical
| Called by: CDEF1_DRAWSBAR (twice), CDEF1_CALCIBOX, CDEF1_NORMALIZEPT, CDEF1_MOVESBAR, CDEF1_THUMBSBAR
| -------------------------------------------------------------------------
CDEF1_TESTHV:
        MOVE.W  0x4(A0),D0                      | bottom
        SUB.W   (A0),D0                         | get height (- top)
        MOVE.W  0x6(A0),D1                      | right
        SUB.W   0x2(A0),D1                      | get width (- left)
        CMP.W   D0,D1                           | compare width and height
        BGT.B   CDEF1_TESTHV_HORIZ              | branch if width is greater
        MOVE.W  D1,D2                           | horizontal (the width) in D2
        MOVEQ.L #0x0,D0                         | signal its vertical
        RTS                                     | return D0 = 0, Z set
CDEF1_TESTHV_HORIZ:
        MOVE.W  D0,D2                           | vertical (the height) in D2
        MOVEQ.L #0x2,D0                         | signal its horizontal
        RTS                                     | return D0 = 2, Z clear

| -------------------------------------------------------------------------
| DrawArrowBox is a routine that blits across the appropriate arrow into
| an arrow box (looks at hilite state); the bitmaps include the box frame.
| On entry, TempRect has the box for the arrow, D0 has h/v selector, D1
| has the arrow's part code, A1 points to the arrow bitMap (left arrow
| for the first box, right arrow for the second), A3 has the control
| handle. Changes D0-D2/A0-A1.
| Called by: CDEF1_DRAWSBAR (each arrow box)
| -------------------------------------------------------------------------
CDEF1_DRAWARROWBOX:
        MOVEA.L (A3),A0                         | get the control pointer
        CMP.B   contrlHilite(A0),D1             | should it be hilited?
        BNE.B   CDEF1_DRAWARROWBOX_VERT         | if not, skip
        ADDA.W  #0x20,A1                        | use the hilited (filled) arrow
CDEF1_DRAWARROWBOX_VERT:
        TST.W   D0                              | horizontal?
        BNE.B   CDEF1_DRAWARROWBOX_PLOT         | yes: left/right arrow
        ADDA.W  #0x80,A1                        | vertical: up/down arrow
CDEF1_DRAWARROWBOX_PLOT:
        CLR.W   D0                              | transfer mode srcCopy
        BSR.B   CDEF1_PLOTSYMBOL                | copy the arrow into TempRect
        RTS                                     | return from DrawArrowBox

| -------------------------------------------------------------------------
| PlotSymbol -- copy a 16 x 16 bitmap into TempRect (scaled if the box is
| not 16 x 16).
|   A1 (in)   the bits (rowBytes 2)
|   D0 (in)   transfer mode
| Builds the BitMap in IconBitmap: baseAddr A1, rowBytes 2, bounds
| (0,0,16,16), then CopyBits from it to thePort's portBits, from bounds
| to TempRect, no mask region. Changes D0-D2/A0-A1.
| Called by: CDEF1_DRAWARROWBOX
| -------------------------------------------------------------------------
CDEF1_PLOTSYMBOL:
        LEA.L   (IconBitmap).W,A0               | get pointer to source bitmap
        MOVE.L  A1,(A0)+                        | baseAddr = the arrow
        MOVE.W  #0x2,(A0)+                      | rowBytes = 2
        CLR.L   (A0)+                           | bounds.topLeft = (0,0)
        MOVE.L  #0x00100010,(A0)                | bounds.botRight = (16,16)
        PEA.L   (IconBitmap).W                  | push pointer source bitmap
        MOVEA.L (SP),A0                         | remember in A0, too
        MOVEA.L (A5),A1                         | get lisaGraf global baseaddress
        MOVEA.L (A1),A1                         | get thePort
        PEA.L   0x2(A1)                         | that's the destination bitmap (portBits)
        PEA.L   0x6(A0)                         | boundsRect of bitmap is source
        PEA.L   (TempRect).W                    | tempRect is the destination
        MOVE.W  D0,-(SP)                        | transfer mode
        CLR.L   -(SP)                           | no mask region
        _CopyBits                               | let Bill stretch those bits
        RTS                                     | return to caller

| -------------------------------------------------------------------------
| CalcIBox is the crucial routine that computes the position of the
| top/left of the thumb by scaling the control's value according to its
| range and the screen area. Return the rectangle in IndicatorRect(A6).
| It expects that A3 will hold the control handle as usual:
|   thumb top = top + minor + (value - min) * (length - 3 * minor)
|               / (max - min), rounded (+ 0 if max = min)
| The thumb is minor pixels long and inset by 1 across the bar; the
| thumb region (contrlData) is set to this rectangle.
|   A0 (out)  control pointer; D0-D2/A1 changed, D3 preserved
| Called by: CDEF1_DOINDICATOR, CDEF1_CHECKIND, CDEF1_GETINDRGN
| -------------------------------------------------------------------------
CDEF1_CALCIBOX:
        MOVE.W  D3,-(SP)                        | preserve D3
        LEA.L   CDEF1_INDICATORRECT(A6),A1      | get address of indicator rectangle
        BSR.B   CDEF1_GETCTLRECT                | first set it to control bounding rect
        MOVEQ.L #0x0,D1                         | clear out high part of D1
        MOVEA.L (A3),A0                         | get pointer to control
        LEA.L   contrlRect(A0),A0               | get pointer to the bounding rectangle
        BSR.B   CDEF1_TESTHV                    | get h/V selector index in D0
        MOVE.W  D2,D3                           | keep minor dimension in D3
| compute control screen area in relevant dimension
        MOVE.W  0x4(A0,D0.W),D1                 | get logical "bottom"
        SUB.W   0x0(A0,D0.W),D1                 | compute "height"
        SUB.W   D2,D1                           | discount arrow box
        SUB.W   D2,D1                           | discount other one, too
        SUB.W   D2,D1                           | and the indicator
| compute "screenSize times value"
        MOVEA.L (A3),A0                         | get control pointer
        MOVE.W  contrlValue(A0),D2              | get current value
        SUB.W   contrlMin(A0),D2                | get delta from min
        MULU.W  D2,D1                           | compute value*screensize
| compute size of logical space
        MOVE.W  contrlMax(A0),D2                | get max
        SUB.W   contrlMin(A0),D2                | compute size of space
        BEQ.B   CDEF1_SCALE0                    | dont divide by 0
| perform the scaling
        DIVU.W  D2,D1                           | compute where iBox should go
        BSR.W   CDEF1_ROUNDOFF                  | round off D1
        ADD.W   D3,D1                           | skip over arrow box
| update indicator rect to correct position
CDEF1_UPDATEIRECT:
        LEA.L   CDEF1_INDICATORRECT(A6),A1      | get pointer to rect
        ADD.W   0x0(A1,D0.W),D1                 | compute the logical "top"
        MOVE.W  D1,0x0(A1,D0.W)                 | update it
        ADD.W   D3,D1                           | bump to "bottom"
        MOVE.W  D1,0x4(A1,D0.W)                 | update "bottom"
        EORI.W  #0x2,D0                         | flip to minor dimension
        ADDQ.W  #0x1,0x0(A1,D0.W)               | inset logical "left"
        SUBQ.W  #0x1,0x4(A1,D0.W)               | inset logical "right"
| set up the indicator region
        MOVE.L  contrlData(A0),-(SP)            | push indicator region handle
        MOVE.L  A1,-(SP)                        | push rect ptr
        _RectRgn                                | make a rectangular region
        MOVE.W  (SP)+,D3                        | restore D3
        RTS                                     | return from CalcIBox
| if min = max, pin at top
CDEF1_SCALE0:
        MOVE.W  D3,D1                           | thumb right after the first arrow box
        BRA.B   CDEF1_UPDATEIRECT               | update the rect

| -------------------------------------------------------------------------
| GetCtlRect is a code saving utility that copies the bounding rectangle
| of the control whose handle is in A3 into the rectangle pointed to by
| A1. This routine blows A0 but preserves A1. GetTCtlRect is an
| alternative entry used to save code: it copies into TempRect.
|   A1 (in/out)  destination (GetTCtlRect: set to TempRect)
|   A0 (out)     contrlRect in the control record
| NoSBarHit, the RTS, is HitSBar's exit with result 0.
| Called by: CDEF1_DRAWSBAR (3 times, GetTCtlRect), CDEF1_CALCIBOX, CDEF1_THUMBSBAR
| -------------------------------------------------------------------------
CDEF1_GETTCTLRECT:
        LEA.L   (TempRect).W,A1                 | destination: TempRect
CDEF1_GETCTLRECT:
        MOVEA.L (A3),A0                         | get pointer to control
        LEA.L   contrlRect(A0),A0               | get pointer to bounding rect
        MOVE.L  (A0),(A1)                       | copy topLeft
        MOVE.L  0x4(A0),0x4(A1)                 | copy botRight
CDEF1_NOSBARHIT:
        RTS                                     | return (NoSBarHit: result 0)

| -------------------------------------------------------------------------
| HitSBar is the hit test routine for the scroll bar definition routine
| (message 1, testCntl). It classifies the position of the mouse passed
| in D3.
|   D3 (in)  the point, in local coordinates of the window
| Result: 0 if inactive (other than 254) or outside contrlRect; 254 for
| contrlHilite 254; inUpButton / inDownButton within the minor dimension
| from either end; for variant 0 then inThumb in the thumb region, or
| inPageUp / inPageDown before / after the thumb's midpoint (variant 1:
| 0). (Apple's version of 1991 returns 0 for contrlHilite 254 too.)
| Changes D0-D4/A0-A1/A4.
| -------------------------------------------------------------------------
CDEF1_HITSBAR:
        MOVE.B  contrlHilite(A0),D4             | get hilite state
        CMPI.B  #0xFE,D4                        | 254 hiliting?
        BEQ.B   CDEF1_HITSBAR_INCTL             | => yes, return 254 if in the control
        BSR.W   CDEF1_ISDISABLED                | otherwise disabled?
        BEQ.B   CDEF1_NOSBARHIT                 | => yes, return with 0
CDEF1_HITSBAR_INCTL:
        LEA.L   contrlRect(A0),A4               | keep rect pointer in A4
        CLR.W   -(SP)                           | make room for function result
        MOVE.L  D3,-(SP)                        | push the point
        MOVE.L  A4,-(SP)                        | push address of rect
        _PtInRect                               | in the rectangle?
        TST.B   (SP)+                           | examine result
        BEQ.B   CDEF1_NOSBARHIT                 | if not, we're done
        ADDQ.B  #0x2,D4                         | 254 hiliting?
        BEQ.B   CDEF1_RETURN254                 | => yes, return 254
| its in the rect, so classify if in upButton,downButton,pageUp,pageDown
| or thumb
        BSR.B   CDEF1_NORMALIZEPT               | relevant coordinate into low part; D0, D2
| see if its in the top button
        MOVE.W  D3,D1                           | get copy of mousePoint
        SUB.W   0x0(A4,D0.W),D1                 | subtract rectangle top
        CMP.W   D2,D1                           | is it within width of the top?
        BGT.B   CDEF1_HITSBAR_DOWN              | it not, go check bottom
        MOVEQ.L #inUpButton,D0                  | classify it
        BRA.B   CDEF1_UPDATERESULT              | all done
| see if its in the bottom button
CDEF1_HITSBAR_DOWN:
        MOVE.W  0x4(A4,D0.W),D1                 | get bottom
        SUB.W   D3,D1                           | get distance from bottom
        CMP.W   D2,D1                           | is it in it?
        BGT.B   CDEF1_CHECKIND                  | if not, go check indicator
        MOVEQ.L #inDownButton,D0                | in the bottom button
| UpdateResult -- store the part code in D0 as the function result
| Called by: (branches) CDEF1_HITSBAR_INCTL, CDEF1_RETURN254, CDEF1_CHECKIND, CDEF1_CHECKPAGE, CDEF1_PAGEITUP
CDEF1_UPDATERESULT:
        MOVE.W  D0,CDEF1_RESULT+2(A6)           | return result
        RTS                                     | return from HitSBar
CDEF1_RETURN254:
        MOVE.W  #0xFE,D0                        | 254: inactive control
        BRA.B   CDEF1_UPDATERESULT              | return it
| its not in either button so it must be the thumb or one of the page
| areas. Check for the thumb first
CDEF1_CHECKIND:
        CMPI.W  #0x1,D6                         | for flavor one don't test
        BEQ.B   CDEF1_NOSBARHIT                 | variant 1: no thumb, no page areas
        BSR.W   CDEF1_CALCIBOX                  | calculate the indicator rectangle
        BSR.B   CDEF1_NORMALIZEPT               | restore back to normal point
        CLR.W   -(SP)                           | make space for boolean result
        MOVE.L  D3,-(SP)                        | push the point
        MOVEA.L (A3),A0                         | get the control pointer
        MOVE.L  contrlData(A0),-(SP)            | push the indicator region
        _PtInRgn                                | is the mouse in the indicator?
        TST.B   (SP)+                           | (..the suspense builds...)
        BEQ.B   CDEF1_CHECKPAGE                 | branch if its not in the indicator
| its in the thumb so report that to the application
        MOVE.W  #inThumb,D0                     | get result
        BRA.B   CDEF1_UPDATERESULT              | all done -- go update result
| it must be in one of the two page areas. Determine which one by looking
| at the midPoint of the indicator's bounding rectangle.
CDEF1_CHECKPAGE:
        BSR.B   CDEF1_NORMALIZEPT               | normalize (get interesting low word)
        MOVEA.L (A3),A0                         | get control pointer
        MOVEA.L contrlData(A0),A0               | get region handle
        MOVEA.L (A0),A0                         | get region pointer
        LEA.L   0x2(A0),A0                      | point to the region bounding box (rgnBBox)
| determine midpoint
        MOVE.W  0x4(A0,D0.W),D1                 | get logical bottom
        SUB.W   0x0(A0,D0.W),D1                 | get logical height
        LSR.W   #0x1,D1                         | divide by 2
        ADD.W   0x0(A0,D0.W),D1                 | add to get the midpoint
| at this point, D1 has the midpoint in the important dimension. Compare
| with the mouse point to decide if its page up or down.
        CMP.W   D1,D3                           | compare mousePt with midPoint
        BLT.B   CDEF1_PAGEITUP                  | if above its the logical "top"
        MOVEQ.L #inPageDown,D0                  | set result code
        BRA.B   CDEF1_UPDATERESULT              | all done -- go update result
CDEF1_PAGEITUP:
        MOVEQ.L #inPageUp,D0                    | set result code
        BRA.B   CDEF1_UPDATERESULT              | all done

| -------------------------------------------------------------------------
| NormalizePt takes a rect pointer in A4 and a point in D3 and swaps the
| points coordinates according to the relevant dimensions: for a vertical
| bar the point's v comes into the low word (calling it again swaps it
| back).
|   D3 (in/out)   point
|   D0, D2 (out)  as TestHV; D1 changed
| Called by: CDEF1_HITSBAR, CDEF1_CHECKIND, CDEF1_CHECKPAGE
| -------------------------------------------------------------------------
CDEF1_NORMALIZEPT:
        MOVEA.L A4,A0                           | get rect pointer in A0
        BSR.W   CDEF1_TESTHV                    | get horizontal vertical offset
        BNE.B   CDEF1_NORMALIZEPT_DONE          | if horizontal, skip
        SWAP    D3                              | its vertical so get y in low part
CDEF1_NORMALIZEPT_DONE:
        RTS                                     | all done

| -------------------------------------------------------------------------
| CalcSBar returns the bounding region of the scroll bar (message 2,
| calcCRgns). D3 holds the region parameter. If the high bit of D3 is set,
| return the indicator region, otherwise return the entire bounding region.
| The indicator case also sets DragPattern to the scroll bar pattern for
| the thumb's drag outline. Changes D0-D2/A0-A1.
| -------------------------------------------------------------------------
CDEF1_CALCSBAR:
        TST.L   D3                              | indicator or body?
        BMI.B   CDEF1_GETINDRGN                 | if negative, go get the indicator
        MOVE.L  D3,-(SP)                        | push the region handle
        PEA.L   contrlRect(A0)                  | push rectangle pointer
        _RectRgn                                | return a rectangular region
        RTS                                     | all done!
| the indicator region was requested so copy the one in the dataHandle
CDEF1_GETINDRGN:
        BSR.W   CDEF1_CALCIBOX                  | calculate indicator region
        MOVEA.L (A3),A0                         | get pointer to control
        MOVE.L  contrlData(A0),-(SP)            | push indicator region
        MOVE.L  D3,-(SP)                        | push result region
        CLR.B   (SP)                            | strip out high byte (the flag)
        _CopyRgn                                | clone the region
| set the pattern for dragging
        BSR.B   CDEF1_GETLTGRAY                 | get pointer to light gray
        MOVE.L  (A0)+,(DragPattern).W           | update the drag pattern
        MOVE.L  (A0),(DragPattern+4).W          | update the drag pattern
        RTS                                     | return from CalcSBar

| -------------------------------------------------------------------------
| GetLtGray -- get the scroll bar pattern (Apple's later version,
| GetOldStyleLtGray, returns the handle).
|   A0 (out)  pointer to the pattern, PAT resource 17 (sBarPatID, light
|             gray, in the System file); D0-D2/A1 changed (trap)
| Called by: CDEF1_DRAWSBAR, CDEF1_GETINDRGN
| -------------------------------------------------------------------------
CDEF1_GETLTGRAY:
        SUBQ.W  #0x4,SP                         | room for the PatHandle
        MOVE.W  #sBarPatID,-(SP)                | push resource ID
        _GetPattern                             | get the pattern
        MOVEA.L (SP)+,A0                        | PatHandle
        MOVEA.L (A0),A0                         | return the PatPtr in A0
        RTS                                     | return from GetLtGray

| -------------------------------------------------------------------------
| handle the "position yourself" message (5, posCntl) by figuring out the
| new value and calling SetCtlValue. D3 holds the amount to move by.
|   new value = min + (thumb position - top - minor) * (max - min)
|               / (length - 3 * minor), rounded
| Changes D0-D3/A0-A1/A4.
| -------------------------------------------------------------------------
CDEF1_MOVESBAR:
        MOVEA.L contrlData(A0),A0               | get handle of indicator region
        MOVEA.L (A0),A0                         | get a pointer to it
        LEA.L   0x2(A0),A4                      | get pointer to the bounding rect (rgnBBox)
| figure out new position by adding topLeft of current position to offset
        ADD.W   0x2(A4),D3                      | add the x coordinates
        SWAP    D3                              | get y in low word
        ADD.W   (A4),D3                         | add the y coordinates
| select the relevant dimension and get it into the low word of D3
        MOVEA.L (A3),A0                         | get the control pointer
        LEA.L   contrlRect(A0),A0               | get the bounding rectangle
        BSR.W   CDEF1_TESTHV                    | get h/v index
        BEQ.B   CDEF1_MOVESBAR_VERT             | if its y, we're cool
        SWAP    D3                              | get x into D3
| determine amount of screen area devoted to the scrollBar
CDEF1_MOVESBAR_VERT:
        SUB.W   0x0(A0,D0.W),D3                 | make size ctl-relative
        SUB.W   D2,D3                           | subtract arrow offset
        MOVE.W  0x4(A0,D0.W),D1                 | get logical bottom
        SUB.W   0x0(A0,D0.W),D1                 | compute logical height
        SUB.W   D2,D1                           | compute active area:
        SUB.W   D2,D1                           | less both arrow boxes
        SUB.W   D2,D1                           | and the thumb
        MOVE.W  D1,D2                           | get answer in D2
| compute range of logical values: controlMax - controlMin
        MOVEA.L (A3),A0                         | get control pointer
        MOVE.W  contrlMax(A0),D1                | get max value
        SUB.W   contrlMin(A0),D1                | compute range
| compute position*logical range/physical range
        MULU.W  D3,D1                           | D3 has current position
        DIVU.W  D2,D1                           | divide by physical range
        BSR.B   CDEF1_ROUNDOFF                  | round to nearest integer
| at this point D1 has the value so set it, after offsetting by the minimum
        ADD.W   contrlMin(A0),D1                | offset by minimum
        MOVE.L  A3,-(SP)                        | push control handle
        MOVE.W  D1,-(SP)                        | push the new value
        _SetControlValue                        | go set the new value
        RTS                                     | all done!

| -------------------------------------------------------------------------
| InitSBar gets called when the scroll bar is allocated (message 3,
| initCntl). It allocates an empty region to use as the indicator region.
| -------------------------------------------------------------------------
CDEF1_INITSBAR:
        SUBQ.W  #0x4,SP                         | room for the region handle
        _NewRgn                                 | get a new region on the stack top
        MOVEA.L (A3),A0                         | get control pointer
        MOVE.L  (SP)+,contrlData(A0)            | remember new region in control data
        RTS                                     | return from InitSBar

| -------------------------------------------------------------------------
| DispSBar de-allocates the region used for the indicator (message 4,
| dispCntl).
| -------------------------------------------------------------------------
CDEF1_DISPSBAR:
        MOVEA.L contrlData(A0),A0               | get handle of indicator region
        _DisposeHandle                          | dispose of it
        RTS                                     | return from DispSBar

| -------------------------------------------------------------------------
| Utility RoundOff -- RoundOff the number in D1 to the nearest integer.
| The remainder from dividing by D2 is in the high part of the word.
|   D1 (in)    result of a DIVU by D2: remainder:quotient
|   D2 (in)    the divisor
|   D1 (out)   low word: the quotient, + 1 if remainder > divisor / 2
| Called by: CDEF1_CALCIBOX, CDEF1_MOVESBAR
| -------------------------------------------------------------------------
CDEF1_ROUNDOFF:
        MOVE.W  D0,-(SP)                        | preserve D0
        MOVE.W  D2,D0                           | get old divisor
        LSR.W   #0x1,D0                         | divide by 2
        SWAP    D1                              | get remainder
        CMP.W   D0,D1                           | compare remainder with 1/2 divisor
        BLE.B   CDEF1_TRUNCATEIT                | if smaller, we're done
        SWAP    D1                              | get normal D1 back
        ADDQ.W  #0x1,D1                         | round up
CDEF1_ROUNDDONE:
        MOVE.W  (SP)+,D0                        | restore D0
        RTS                                     | return the rounded quotient in D1
|  no need to round up so just truncate it
CDEF1_TRUNCATEIT:
        SWAP    D1                              | restore quotient
        BRA.B   CDEF1_ROUNDDONE                 | all done with roundOff

| -------------------------------------------------------------------------
| ThumbSBar receives the "drag thumb" message (6, thumbCntl) for the scroll
| bar. On entry, D3 points to a structure that contains the starting
| point, it returns with pointers to the bounds and slopRect and the axis
| parameter.
|   D3 (in)  pointer to the record limitRect (BRect), slopRect (SRect),
|            axis (TAxis); limitRect.topLeft = the mouse-down point
| limitRect: contrlRect less the arrow boxes along the bar and 24 pixels
| wider across it (the hysteresis: farther away the drag is cancelled),
| its ends moved by the mouse's offset within the thumb so that the
| thumb stays between the arrows; slopRect: the limitRect before that
| adjustment, 128 pixels longer at both ends; axis: vAxisOnly (2) for a
| vertical bar, hAxisOnly (1) for a horizontal one. Changes D0-D4/A0-A2/A4.
| -------------------------------------------------------------------------
CDEF1_THUMBSBAR:
        MOVEA.L D3,A4                           | keep pointer to parameter block
        MOVE.L  (A4),D3                         | get the mouse point
        LEA.L   (A4),A2                         | get pointer to boundsRect (BRect)
        MOVEA.L A2,A1                           | get pointer in A1
        BSR.W   CDEF1_GETCTLRECT                | copy control bounds rect
        MOVEA.L A2,A0                           | point to boundsRect
        BSR.W   CDEF1_TESTHV                    | get h/v selector in D0
        MOVE.W  D2,-(SP)                        | preserve D2 (the minor dimension)
        SWAP    D2                              | minor dimension in the high word
        MOVE.W  #0xFFE8,D2                      | get inset factor (24 pixels hyst)
        MOVE.W  D0,D4                           | keep selector in D4
        BEQ.B   CDEF1_THUMBSBAR_VERT            | if vertical, we're cool
        SWAP    D2                              | adjust inset factor
        BRA.B   CDEF1_THUMBSBAR_INSET           | go inset the limitRect
CDEF1_THUMBSBAR_VERT:
        SWAP    D3                              | adjust mouse pt (v in the low word)
CDEF1_THUMBSBAR_INSET:
        MOVE.L  A2,-(SP)                        | push pointer to rectangle
        MOVE.L  D2,-(SP)                        | push inset factor
        _InsetRect                              | go inset it
| build the slopRect by insetting the boundsRect
        LEA.L   CDEF1_SRECT(A4),A0              | get slopRect pointer
        MOVE.L  (A4),(A0)                       | copy boundsRect into slopRect
        MOVE.L  0x4(A4),0x4(A0)                 | copy botRight, too
        MOVE.L  #0xFF800000,D0                  | get inset factor (assume vertical)
        TST.W   D4                              | which dimension
        BEQ.B   CDEF1_THUMBSBAR_SLOP            | if vertical, we're cool
        SWAP    D0                              | horizontal: dh = -128
CDEF1_THUMBSBAR_SLOP:
        MOVE.L  A0,-(SP)                        | push slopRect pointer
        MOVE.L  D0,-(SP)                        | push inset factor
        _InsetRect                              | inset it
| now further adjust the boundsRect depending where the mousePt is
| relative to the indicator box.
        MOVEA.L (A3),A0                         | get control pointer
        MOVEA.L contrlData(A0),A0               | get region handle
        MOVEA.L (A0),A0                         | get region pointer
        SUB.W   0x2(A0,D4.W),D3                 | subtract relevant coordinate (rgnBBox)
        ADD.W   D3,0x0(A2,D4.W)                 | offset logical top
| fix up logical bottom, too
        MOVE.W  (SP)+,D2                        | get back D2
        SUBQ.W  #0x1,D2                         | minor dimension - 1
        SUB.W   D2,0x4(A2,D4.W)                 | logical bottom less (minor - 1)
        ADD.W   D3,0x4(A2,D4.W)                 | plus the mouse's offset in the thumb
| now set up axis parameter
        LSR.W   #0x1,D4                         | divide by 2
        EORI.W  #0x1,D4                         | flip the sense
        ADDQ.W  #0x1,D4                         | add increment
        MOVE.W  D4,CDEF1_TAXIS(A4)              | to derive axis parameter
        RTS                                     | return from ThumbSBar

