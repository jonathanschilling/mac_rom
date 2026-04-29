| QuickDraw Color/Scroll Support
|
| Contains FillCRgn, FillCArc, FillCPoly - Color QuickDraw fill
| routines with origin adjustment for scrolled/offset ports.
| Also contains the scroll acceleration routines that handle
| adjusting pen/pattern origins when content has been scrolled.
|
| On the Mac Plus, these handle pattern alignment and origin
| offset calculations for the monochrome screen.
|

| ----------------------------------------------------------
|
| Fill C Rgn
|
| FillCRgn: fill region with pattern, adjusting for scroll origin
| Adjusts pattern origin so pattern tiles correctly after ScrollRect
FillCRgn:
        BSR     XTRIMMEASURE_CONT_10            | set up region parameters
        BSR     P_TERECAL_CONT_3                | get pattern/mode
        MOVE    (A2),D0                         | D0 = current V origin offset
        BPL.B   CFILL_POS_VOFF                  | positive ->
| negative V offset: adjust for visible region
        MOVE    VISRGN(A3),D1                   | visible region height
        MULU    0x5E(A3),D1                     | * row bytes
        ADD     (A3),D1                         | + port origin
        SUB     0xC(A3),D1                      | - clip origin
        BLE.B   CFILL_ADJ_DV                    | no adjustment needed ->
        ADD     D1,D0                           | adjust offset
        BPL.B   CFILL_CHK_DH                    | now positive ->
        ADD     D0,(A2)                         | apply remaining offset
        BRA.B   CFILL_CHK_DH                    | ->

| ----------------------------------------------------------
|
| CFILL_POS_VOFF
|
CFILL_POS_VOFF:
        MOVE    (A3),D1                         | D1 = destRect.top
        SUB     PORTBOUNDS(A3),D1               | subtract viewRect.top
        BPL.B   CFILL_ADJ_DV                    | if destRect >= viewRect, skip scroll
        ADD     D1,D0                           | D0 = dv + top difference
        BMI.B   CFILL_CHK_DH                    | if negative, skip adjustment
CFILL_ADJ_DV:
        SUB     D0,(A2)                         | adjust dv to avoid scrolling past top
CFILL_CHK_DH:
        MOVE    0x2(A2),D0                      | D0 = horizontal scroll delta (dh)
        BPL.B   CFILL_POS_HOFF                  | if positive, scrolling right ->
        MOVE    0x6(A3),D1                      | D1 = destRect.right
        SUB     0xE(A3),D1                      | subtract viewRect.right
        BLE.B   CFILL_ADJ_DH                    | if destRect <= viewRect, skip scroll
        ADD     D1,D0                           | D0 = dh + right difference
        BPL.B   CFILL_APPLY_SCROLL              | if positive, skip adjustment
        ADD     D0,0x2(A2)                      | adjust dh to avoid scrolling past right
        BRA.B   CFILL_APPLY_SCROLL              | ->

| ----------------------------------------------------------
|
| CFILL_POS_HOFF
|
CFILL_POS_HOFF:
        MOVE    PORTBITS(A3),D1                 | D1 = destRect.left
        SUB     0xA(A3),D1                      | subtract viewRect.left
        BPL.B   CFILL_ADJ_DH                    | if destRect >= viewRect, skip scroll
        ADD     D1,D0                           | D0 = dh + left difference
        BMI.B   CFILL_APPLY_SCROLL              | if negative, skip adjustment
CFILL_ADJ_DH:
        SUB     D0,0x2(A2)                      | adjust dh to avoid scrolling past left
CFILL_APPLY_SCROLL:
        MOVE.L  (A2)+,D3                        | pop dv and dh into D3
        BSR     TESCROLL_CONT                   | apply scroll to text
        BSR     P_TERECAL_NO_3                  | show caret
        BRA     TESCROLL_EXIT                   | -> return

| ----------------------------------------------------------
|
| Fill C Arc
|
| FillCArc: fill arc with pattern, adjusting for scroll
FillCArc:
        BSR     XTRIMMEASURE_CONT_12            | set up arc parameters
        BSR.B   FILLCARC_CONT                   | do the fill with origin adjustment
        BRA     TECALTEXT_EXIT                  | -> return

| ----------------------------------------------------------
|
| FILLCARC_CONT: fill with origin-adjusted pattern (checks if scrolled)
|
FILLCARC_CONT:
        BTST    #0x6,PNVIS(A3)                  | pattern origin adjusted?
        BEQ.B   CFILL_ORIGIN_RTS                | no, use normal fill ->
        BSR     XTRIMMEASURE_CONT_15            | set up fill state
        MOVE    BKPAT(A3),D3                    | D3 = selStart
        MOVE    D3,D4                           | D4 = selStart
        MOVEQ.L #-0x2,D7                        | D7 = action code for calculating caret (-2)
        BSR     P_doTEDoText                    | calculate caret position into selRect
        MOVE.L  PORTRECT(A3),D7                 | D7 = selRect.topLeft (caret position)
        LEA.L   (OneOne).w,A2                   | A2 = low memory scratch rect pointer
        LEA.L   PORTRECT(A3),A0                 | A0 = pointer to end of viewRect
| build adjusted rect for origin test
        MOVE.L  -(A0),-(A2)                     | copy portRect.botRight
        MOVE.L  -(A0),-(A2)                     | copy portRect.topLeft
        MOVE    VISRGN(A3),D0                   | D0 = visible region height
        SUB     D0,0x4(A2)                      | shrink rect bottom by vis height
        SUBQ.W  #0x1,0x6(A2)                    | shrink rect right by 1
| test if current pen position is outside adjusted rect
        SUBQ.W  #0x2,SP                         | space for PtInRect result
        MOVE.L  D7,-(SP)                        | push current point
        MOVE.L  A2,-(SP)                        | push adjusted rect
        _PtInRect                               | point inside?
        TST.B   (SP)+                           | check result
        BNE.B   CFILL_ORIGIN_RTS                | yes: no adjustment needed ->
| point is outside: compute origin offset and apply to region
        MOVE.L  (A2)+,-(SP)                     | push rect topLeft
        MOVE.L  (A2),-(SP)                      | push rect botRight
        MOVE.L  -(A2),-(SP)                     | push topLeft again
        PEA.L   0x4(SP)                         | push ptr to botRight
        _SubPt                                  | botRight -= topLeft (get size)
        PEA.L   0x4(SP)                         | push ptr to topLeft
        _AddPt                                  | topLeft += size (wrap around)
        MOVE.L  D7,-(SP)                        | push current point
        PEA.L   0x4(SP)                         | push ptr to adjusted topLeft
        _SubPt                                  | compute offset
        MOVE.L  A4,-(SP)                        | push region handle
        BSR     FillCRgn                        | apply offset to region
CFILL_ORIGIN_RTS:
        RTS                                     | return

| ----------------------------------------------------------
|
| Fill C Poly
|
| FillCPoly: fill polygon with pattern
FillCPoly:
        BSR     XTRIMMEASURE_CONT_11            | set up polygon parameters
        TST.B   (A2)+                           | check fill mode flag
        BEQ.B   CPOLY_CLR_ORIGIN                | zero: clear origin flag ->
        BSET    #0x6,PNVIS(A3)                  | set origin-adjusted fill flag
        BRA.B   CPOLY_DO_FILL                   | ->
CPOLY_CLR_ORIGIN:
        BClr    #0x6,PNVIS(A3)                  | clear origin-adjusted flag
CPOLY_DO_FILL:
        BRA     TEKEY_DONE                      | -> do polygon fill

| ----------------------------------------------------------
|
| CPOLY_DO_FILL_LOOP
|
| CPOLY_DO_FILL_LOOP: auto-scroll detection for scrolling content
| Checks if mouse is outside the visible area and determines scroll direction
| Returns scroll delta in D5 (vertical) or D4 (horizontal)
CPOLY_DO_FILL_LOOP:
        MOVEM.L D0-D7/A0-A4,-(SP)               | save all regs
        BTST    #0x6,PNVIS(A3)                  | scroll enabled?
        BEQ.B   AUTOSCROLL_NONE                 | no ->
| build inset rect for scroll detection zone
        MOVE    VISRGN(A3),D5                   | D5 = scroll step size
        MOVEQ.L #0x0,D4                         | D4 = 0 (no horizontal scroll yet)
        LEA.L   PORTRECT(A3),A0                 | source: port rect
        LEA.L   (OneOne).w,A2                   | dest: scratch rect
        MOVE.L  -(A0),-(A2)                     | copy botRight
        MOVE.L  -(A0),-(A2)                     | copy topLeft
| inset the rect by scroll margin
        MOVE.L  A2,-(SP)                        | push rect
        MOVE    #-0x8,-(SP)                     | horizontal inset = -8 (expand)
        MOVE    D5,D0                           | vertical inset
        ASR     #0x1,D0                         | / 2
        NEG     D0                              | negate (expand)
        MOVE    D0,-(SP)                        | push vertical inset
        _InsetRect                              | expand rect
| get current mouse position
        SUBQ.W  #0x4,SP                         | space for Point
        MOVE.L  A7,-(SP)                        | push ptr to Point on stack
        _GetMouse                               | get mouse in local coords
        MOVE    (SP)+,D6                        | D6 = mouse.v
        MOVE    (SP)+,D7                        | D7 = mouse.h
| check if mouse is outside the inset rect
        CMP     (A2)+,D6                        | above top?
        BLT.B   AUTOSCROLL_UP                   | yes: scroll up ->
        CMP     (A2)+,D7                        | left of left?
        BLT.B   AUTOSCROLL_LEFT                 | yes: scroll left ->
        CMP     (A2)+,D6                        | below bottom?
        BGT.B   AUTOSCROLL_DOWN                 | yes: scroll down ->
        CMP     (A2)+,D7                        | right of right?
        BGT.B   AUTOSCROLL_RIGHT                | yes: scroll right ->
| mouse inside rect: no scroll needed
AUTOSCROLL_NONE:
        MOVEQ.L #0x1,D0                         | return true (no scroll)
        MOVEM.L (SP)+,D0-D7/A0-A4               | restore regs
        RTS                                     | return

| scroll down (mouse below bottom)
AUTOSCROLL_DOWN:
        NEG     D5                              | negate for downward scroll
| scroll up (mouse above top)
AUTOSCROLL_UP:
        BRA.B   AUTOSCROLL_APPLY                | -> apply vertical scroll

| scroll right (mouse right of right edge)
AUTOSCROLL_RIGHT:
        NEG     D5                              | negate for rightward scroll
| scroll left (mouse left of left edge)
AUTOSCROLL_LEFT:
        exg     D4,D5                           | swap: D4=scroll step, D5=0
| apply scroll: offset the region by (D4, D5) pixels
AUTOSCROLL_APPLY:
        MOVE    D4,-(SP)                        | push horizontal scroll delta
        MOVE    D5,-(SP)                        | push vertical scroll delta
        MOVE.L  0x8(A6),-(SP)                   | push region handle
        BSR     FillCRgn                        | scroll content by offset
        BRA.B   AUTOSCROLL_NONE                 | -> return
