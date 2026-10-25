| Cursor core -- cursor drawing, ScrnAddress/ScrnSize/ScrnBitMap, CrsrVBLTask, PinRect
|
| Apple source: CrsrCore.a (System 7.1: QuickDraw/Classic/CrsrCore.a; the
| SE link map calls the module CRSRCORE). The low-level cursor support
| behind the QuickDraw cursor traps in LCursor.s: those traps jump through
| the J-vectors (JHideCursor, JShowCursor, JShieldCursor, JSetCrsr,
| JInitCrsr, JCrsrObscure, JScrnAddr, JScrnSize) that InitCrsr's table
| DT_mCRSRCore installs. CrsrVBLTask, run by the VBL interrupt, moves
| the cursor with the mouse (mouse acceleration from MTemp/RawMouse),
| and PinRect keeps a point inside a rectangle. In the Mac Plus ROM this
| file is linked between the Vertical Retrace Manager and the trap
| dispatcher, far from the rest of QuickDraw.
|
| References: Inside Macintosh Vol I, Ch 6: QuickDraw (cursor handling);
| Inside Macintosh Vol III: hardware (screen buffer, mouse)

| ----------------------------------------------------------
|
| DT_mCRSRCore - Cursor manager dispatch table
|
| 8 words (16 bytes): offsets within GrafBegin for cursor routines.
| Indexed by trap selector to dispatch HideCursor, ShowCursor, etc.
|
DT_mCRSRCore:
  .byte 0x00,0x1E,0x00,0x70,0x01,0x3E           | HideCursor, ShowCursor, ShieldCursor offsets
  .byte 0x01,0xD0,0x01,0xD8,0x00,0x62           | ObscureCursor, SetCrsr, InitCrsr offsets
  .byte 0x01,0x80,0x00,0x10                     | ScrnAddress, ScrnSize offsets

| ----------------------------------------------------------
|
| P_CrsrObscure - Hide cursor and mark as obscured
|
| Called by _ObscureCursor trap. Sets the CrsrObscure flag so the
| cursor stays hidden until the next mouse movement.
|
P_CrsrObscure:
        MOVE.B  #0x1,(CrsrBusy).w               | Set busy semaphore (block VBL updates)
        BSET    #0x0,(CrsrObscure).w            | Set "cursor obscured" flag
        BNE.B   CRSR_CLEAR_BUSY                 | Already obscured, just clear busy and return

| ----------------------------------------------------------
|
| P_HideCursor - Erase cursor from screen, decrement CrsrState
|
| Restores saved background pixels under the cursor rectangle,
| clears CrsrVis, and decrements CrsrState (hide depth counter).
|
P_HideCursor:
        MOVE.B  #0x1,(CrsrBusy).w               | Set busy semaphore (block VBL updates)
        TST.B   (CrsrVis).w                     | Is cursor currently visible on screen?
        BEQ.B   HIDE_DEC_STATE                  | Not visible, skip erase, just decrement state
        MOVEM.L D0-D1/A0-A1,-(SP)               | Save work registers
        LEA.L   (CrsrRect).w,A1                 | A1 = cursor bounding rectangle
        MOVE    (A1),D1                         | D1 = CrsrRect.top (screen row)
        CLR.L   (A1)+                           | Clear top-left of CrsrRect (mark invalid)
        SUB     (A1),D1                         | D1 = top - bottom (negative height)
        CLR.L   (A1)                            | Clear bottom-right of CrsrRect
        NEG     D1                              | D1 = height of cursor rect
        BEQ.B   HIDE_CLEAR_VIS                  | Zero height, nothing to restore
        MOVE.L  (CrsrAddr).w,A1                 | A1 = screen address of cursor top-left
        LEA.L   (CrsrSave).w,A0                 | A0 = saved background pixels (64 bytes)
        MOVEQ.L #0x40,D0                        | D0 = screen row bytes (64 = 512/8)
HIDE_RESTORE_ROW:
        MOVE.L  (A0)+,(A1)                      | Restore one longword of background pixels
        ADDA    D0,A1                           | advance A1 to the next line in the screen buffer
        SUBQ.W  #0x1,D1                         | Decrement row counter
        BGT.B   HIDE_RESTORE_ROW                | More rows to restore
HIDE_CLEAR_VIS:
        CLR.B   (CrsrVis).w                     | Mark cursor as not visible
        MOVEM.L (SP)+,D0-D1/A0-A1               | Restore work registers
HIDE_DEC_STATE:
        SUBQ.W  #0x1,(CrsrState).w              | Decrement hide depth counter
CRSR_CLEAR_BUSY:
        CLR.B   (CrsrBusy).w                    | Release busy semaphore
        RTS                                     | return from CRSR_CLEAR_BUSY

| ----------------------------------------------------------
|
| InitCrsr - Initialize cursor state (called once at boot)
|
| Resets CrsrObscure, sets CrsrState to 0, then falls through
| to ShowCursor to draw the initial cursor on screen.
|
| Called during boot.
InitCrsr:
        MOVE.B  #0x1,(CrsrBusy).w               | Set busy semaphore during init
        CLR.B   (CrsrObscure).w                 | Clear obscured flag
        CLR     (CrsrState).w                   | Reset hide depth to 0 (balanced)

| ----------------------------------------------------------
|
| P_ShowCursor - Draw cursor on screen, increment CrsrState
|
| Computes cursor screen position from Mouse and hotspot,
| clips to screen bounds, saves background pixels, then XORs
| cursor data with mask onto the framebuffer.
|
P_ShowCursor:
        MOVE.B  #0x1,(CrsrBusy).w               | Set busy semaphore (block VBL updates)
        ADDQ.W  #0x1,(CrsrState).w              | Increment show depth counter
        BLT.B   CRSR_CLEAR_BUSY                 | Still hidden (negative), just clear busy
        CLR     (CrsrState).w                   | Clamp state to 0 (fully visible)
        TST.B   (CrsrVis).w                     | Already visible on screen?
        BNE.B   CRSR_CLEAR_BUSY                 | Yes, don't double-draw, clear busy and return
        MOVEM.L D0-D5/A0-A3,-(SP)               | Save all work registers
        MOVEQ.L #0x10,D5                        | D5 = 16 (cursor width/height in pixels)
        LEA.L   (CrsrSave).w,A0                 | A0 = background save buffer (64 bytes)
        LEA.L   (TheCrsr_data).w,A2             | A2 = cursor image data (16 words)
        LEA.L   (TheCrsr_mask).w,A3             | A3 = cursor mask data (16 words)
        MOVE    (Mouse_h).w,D0                  | D0 = current mouse X position
        SUB     (TheCrsr_hotspot_h).w,D0        | Subtract hotspot X to get cursor left edge
        MOVEQ.L #0xF,D2                         | D2 = 15 (bit position mask)
        AND     D0,D2                           | D2 = pixel offset within word (0-15)
        NEG     D2                              | Negate for right-shift amount
        ADD     D5,D2                           | D2 = 16 - (D0 & 15) = left shift amount
        MOVEQ.L #0x0,D3                         | Clear D3 for mask construction
        SUBQ.W  #0x1,D3                         | D3 = 0xFFFF (all ones)
        LSL.L   D2,D3                           | D3 = screen clip mask, shifted to align cursor
        ANDI    #-0x10,D0                       | Round X down to word boundary (16-pixel aligned)
        BGE.B   SHOW_CLIP_RIGHT                 | X >= 0, no left-edge clipping needed
        MOVEQ.L #0x0,D0                         | Clip cursor left edge to screen column 0
        SWAP    D3                              | Move mask to low word (clear high = clip left)
        SUB     D3,D3                           | Zero low word of mask (left portion off-screen)
        ADD     D5,D2                           | Adjust shift for clipped position
SHOW_CLIP_RIGHT:
        CMPI    #0x1E0,D0                       | Compare X with 480 (512-32): right edge check
        BLE.B   SHOW_CLIP_VERT                  | Within bounds, no right-edge clipping
        MOVE    #0x1E0,D0                       | Clip X to 480 (rightmost cursor position)
        SUB     D3,D3                           | Zero high word of mask (right portion off-screen)
        SWAP    D3                              | Move mask to high word (clip right)
        ADD     D5,D2                           | Adjust shift for clipped position
SHOW_CLIP_VERT:
        MOVE    D5,D4                           | D4 = 16 (initial cursor height)
        MOVE    (Mouse_v).w,D1                  | D1 = current mouse Y position
        SUB     (TheCrsr_hotspot_v).w,D1        | Subtract hotspot Y to get cursor top edge
        BGE.B   SHOW_CLIP_BOTTOM                | Y >= 0, no top-edge clipping needed
        ADD     D1,D4                           | Reduce visible height by off-screen rows
        ADD     D1,D1                           | D1*2 = byte offset for skipped cursor rows
        SUBA    D1,A2                           | Advance cursor data past clipped rows
        SUBA    D1,A3                           | Advance cursor mask past clipped rows
        MOVEQ.L #0x0,D1                         | Clip Y to row 0 (top of screen)
SHOW_CLIP_BOTTOM:
        CMPI    #0x146,D1                       | Compare Y with 326 (342-16): bottom edge check
        BLE.B   SHOW_SET_RECT                   | Within bounds, no bottom clipping
        MOVE    #0x156,D4                       | D4 = 342 + 16 = 358 (max unclipped extent)
        SUB     D1,D4                           | D4 = remaining visible rows at bottom
SHOW_SET_RECT:
        LEA.L   (CrsrRect).w,A1                 | A1 = cursor bounding rectangle
        MOVE    D1,(A1)+                        | CrsrRect.top = clipped Y
        MOVE    D0,(A1)+                        | CrsrRect.left = clipped X
        MOVE    D1,(A1)                         | Store top again for bottom calculation
        ADD     D4,(A1)+                        | CrsrRect.bottom = top + visible height
        MOVE    D0,(A1)                         | Store left again for right calculation
        ADDI    #0x20,(A1)                      | CrsrRect.right = left + 32 (cursor is 2 words wide)
        MOVE.L  (ScrnBase).w,A1                 | A1 = framebuffer base address
        LSR     #0x3,D0                         | Convert X pixels to byte offset (X/8)
        ADDA    D0,A1                           | Offset A1 to cursor column in framebuffer
        MOVEQ.L #0x40,D5                        | D5 = screen row bytes (64)
        MULU    D5,D1                           | D1 = Y * 64 = byte offset to cursor row
        ADDA.L  D1,A1                           | A1 = framebuffer address of cursor top-left
        MOVE.L  A1,(CrsrAddr).w                 | Save screen address for HideCursor restore
        BRA.B   SHOW_DRAW_TEST                  | Enter drawing loop (test D4 first)

| ----------------------------------------------------------
|
| SHOW_DRAW_ROW - Cursor drawing inner loop
|
| For each row: reads cursor data and mask, shifts/clips to screen
| alignment, saves background longword, applies mask (AND NOT) then
| XORs cursor data onto screen. This produces a proper masked cursor.
|
| Called during boot (4,543 times in 30s trace).
SHOW_DRAW_ROW:
        MOVE    (A2)+,D0                        | Load one row of cursor image data (16 bits)
        ROL.L   D2,D0                           | Rotate to align with screen pixel position
        AND.L   D3,D0                           | Apply clip mask (zero off-screen portions)
        MOVE    (A3)+,D1                        | Load one row of cursor mask (16 bits)
        ROL.L   D2,D1                           | Rotate mask to match screen alignment
        AND.L   D3,D1                           | Apply clip mask to mask data
        NOT.L   D1                              | Invert mask: 0=cursor pixel, 1=keep background
        MOVE.L  (A1),(A0)+                      | Save background longword to CrsrSave buffer
        AND.L   D1,(A1)                         | Erase cursor area: AND background with inverted mask
        EOR.L   D0,(A1)                         | XOR cursor data onto cleared area
        ADDA    D5,A1                           | Advance to next screen row (add row bytes)
SHOW_DRAW_TEST:
        DBF     D4,SHOW_DRAW_ROW                | Decrement row counter, loop if rows remain
        MOVE.B  #0x1,(CrsrVis).w                | Mark cursor as visible on screen
        MOVEM.L (SP)+,D0-D5/A0-A3               | Restore all work registers
        CLR.B   (CrsrBusy).w                    | Release busy semaphore
        RTS                                     | return from SHOW_DRAW_TEST

| ----------------------------------------------------------
|
| P_ShieldCursor - Temporarily hide cursor if it overlaps a rectangle
|
| Called before drawing into a screen area. If the cursor's bounding
| rectangle (CrsrRect) intersects the shield rectangle passed on the
| stack, the cursor is hidden. Otherwise CrsrState is decremented
| (to be balanced by a later ShowCursor call).
| Stack: retAddr, shieldRect (top, left, bottom, right = 8 bytes)
|
| Called during boot.
P_ShieldCursor:
        MOVEM.L D0/A0,-(SP)                     | Save work registers
        LEA.L   (CrsrRect).w,A0                 | A0 = cursor bounding rectangle
        MOVE    0xC(SP),D0                      | D0 = shield rect top
        CMP     (A0)+,D0                        | Compare shield.top with CrsrRect.top
        BLT.B   SHIELD_NO_OVERLAP               | Shield above cursor top: no overlap possible
        CMPI    #0x1F0,(A0)                     | Check CrsrRect.left against 496 (off-screen)
        BGE.B   SHIELD_DO_HIDE                  | Cursor is off-screen right: force hide
        MOVE    0xE(SP),D0                      | D0 = shield rect left
        CMP     (A0)+,D0                        | Compare shield.left with CrsrRect.left
        BLE.B   SHIELD_NO_OVERLAP               | Shield left of cursor left: check other edges
        MOVE    0x10(SP),D0                     | D0 = shield rect bottom
        CMP     (A0)+,D0                        | Compare shield.bottom with CrsrRect.bottom
        BGE.B   SHIELD_NO_OVERLAP               | Shield below cursor bottom: no overlap
        MOVE    0x12(SP),D0                     | D0 = shield rect right
        CMP     (A0),D0                         | Compare shield.right with CrsrRect.right
        BGE.B   SHIELD_NO_OVERLAP               | Shield right of cursor right: no overlap
SHIELD_DO_HIDE:
        BSR     P_HideCursor                    | Rectangles overlap: hide cursor
        BRA.B   SHIELD_RETURN                   | Skip state decrement (HideCursor did it)

| ----------------------------------------------------------
|
| SHIELD_NO_OVERLAP - No overlap: just decrement CrsrState
|
| Called during boot.
SHIELD_NO_OVERLAP:
        SUBQ.W  #0x1,(CrsrState).w              | Decrement hide depth (balanced by ShowCursor)
SHIELD_RETURN:
        MOVEM.L (SP)+,D0/A0                     | Restore work registers
        MOVE.L  (SP)+,(SP)                      | Collapse stack: overwrite shield.top with retAddr
        MOVE.L  (SP)+,(SP)                      | Collapse stack: remove shield rect bytes
        RTS                                     | Return (8 bytes of shield rect removed)

| ----------------------------------------------------------
|
| SetCrsr - Set the current cursor image and hotspot
|
| Stack: retAddr, cursorPtr (68 bytes: 32 data + 32 mask + 4 hotspot)
| Compares new cursor with current TheCrsr; if different, hides
| old cursor and shows new one. Hotspot values clamped to 0-16.
|
| Called during boot (3,700 times in 30s trace).
SetCrsr:
        MOVE.L  0x8(SP),A0                      | A0 = pointer to new cursor record
        LEA.L   (TheCrsr_data).w,A1             | A1 = current cursor data in low memory
        MOVEQ.L #0xF,D2                         | D2 = 15 (loop counter: 16 longwords)
        MOVEQ.L #0x0,D1                         | D1 = change counter (0 = no difference)
SETCRSR_CMP_LOOP:
        MOVE.L  (A0)+,D0                        | Load next longword from new cursor
        CMP.L   (A1),D0                         | Compare with current cursor data
        BEQ.B   SETCRSR_STORE                   | Same, skip change count
        ADDQ.W  #0x1,D1                         | Different: increment change counter
SETCRSR_STORE:
        MOVE.L  D0,(A1)+                        | Store new cursor data (even if unchanged)
        DBF     D2,SETCRSR_CMP_LOOP             | Loop for all 16 longwords (data + mask)
        MOVE.L  0xE(SP),D0                      | D0 = new hotspot (v:h packed as two words)
        MOVEQ.L #0x10,D2                        | D2 = 16 (max hotspot coordinate)
        CMP     D2,D0                           | Compare hotspot.h with 16
        BLS.B   SETCRSR_CLAMP_V                 | hotspot.h <= 16, keep it
        MOVE    D2,D0                           | Clamp hotspot.h to 16
SETCRSR_CLAMP_V:
        SWAP    D0                              | D0.W = hotspot.v
        CMP     D2,D0                           | Compare hotspot.v with 16
        BLS.B   SETCRSR_CHECK_CHG               | hotspot.v <= 16, keep it
        MOVE    D2,D0                           | Clamp hotspot.v to 16
SETCRSR_CHECK_CHG:
        SWAP    D0                              | D0 = hotspot.v:hotspot.h (clamped)
        CMP.L   (TheCrsr_hotspot_v).w,D0        | Compare with current hotspot
        BEQ.B   SETCRSR_REDRAW                  | Same hotspot, skip update
        ADDQ.W  #0x1,D1                         | Different: increment change counter
        MOVE.L  D0,(TheCrsr_hotspot_v).w        | Store new hotspot
SETCRSR_REDRAW:
        TST     D1                              | Any differences detected?
        BEQ.B   SETCRSR_RETURN                  | No changes, skip redraw
        BSR     P_HideCursor                    | Erase old cursor from screen
        BSR     P_ShowCursor                    | Draw new cursor on screen
SETCRSR_RETURN:
        MOVE.L  (SP)+,A0                        | Pop return address
        ADDA    #0xE,SP                         | Remove 14 bytes of parameters (ptr+hotspot+pad)
        JMP     (A0)                            | Return to caller

| ----------------------------------------------------------
|
| ScrnAddress - Return the screen base address
|
| Stack: retAddr, result (longword pointer to fill)
| Stores ScrnBase into the result location on the stack.
|
ScrnAddress:
        MOVE.L  (ScrnBase).w,0x4(SP)            | Store screen base address in result slot
        RTS                                     | return from ScrnAddress

| ----------------------------------------------------------
|
| ScrnSize - Return screen dimensions (height and width)
|
| Stack: retAddr, heightPtr, widthPtr
| Stores 342 (0x156) for height, 512 (0x200) for width.
|
ScrnSize:
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = pointer for height result
        MOVE    #0x156,(A0)                     | Store screen height: 342 pixels
        MOVE.L  (SP)+,A0                        | A0 = pointer for width result
STORE_SCRN_WIDTH:
        MOVE    #0x200,(A0)                     | Store screen width: 512 pixels
        JMP     (A1)                            | Return to caller

| ----------------------------------------------------------
|
| ScrnBitMap - Return screen bitmap info (base, rowBytes, bounds)
|
| On Mac Plus (1-bit display), returns a bitmap descriptor:
| ScrnBase, ScreenRow (64), bounds rect (0,0,342,512).
| Re-uses STORE_SCRN_WIDTH to store the width as the last step.
|
| Called during boot.
ScrnBitMap:
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = pointer to bitmap record to fill
        MOVE.L  (ScrnBase).w,(A0)+              | Store baseAddr = screen base
        MOVE    (ScreenRow).w,(A0)+             | Store rowBytes = 64
        CLR.L   (A0)+                           | Store bounds.topLeft = (0,0)
        MOVE    #0x156,(A0)+                    | Store bounds.bottom = 342
        BRA.B   STORE_SCRN_WIDTH                | Store bounds.right = 512 and return

| ----------------------------------------------------------
|
| CrsrVBLTask - Cursor update task called every VBL (60.15 Hz)
|
| Processes pending mouse movement (from SCC quadrature interrupts):
| applies mouse scaling/acceleration, constrains to CrsrPin rect,
| applies MouseMask/MouseOffset, and redraws cursor at new position.
|
| Called during boot.
CrsrVBLTask:
        TST.B   (CrsrNew).w                     | non-zero if mouse position has changed
        BEQ.B   CRSVBL_RETURN                   | No movement, return immediately
        TST.B   (CrsrBusy).w                    | semaphore
        BNE.B   CRSVBL_RETURN                   | Cursor locked by another operation, defer
        TST.B   (CrsrCouple).w                  | if 0, we will redraw the cursor but not move it
        BEQ.B   CRSVBL_REDRAW                   | Uncoupled: skip position update, just redraw
        MOVE    (MTemp_v).w,D0                  | new location of the mouse as updated by the mouse interrupt handler
        SUB     (RawMouse_v).w,D0               | current mouse cursor position
        MOVE    D0,D2                           | D2 = vertical delta (signed)
        BGE.B   CRSVBL_HORIZ_DELTA              | Delta >= 0, already positive
        NEG     D2                              | D2 = |vertical delta|
CRSVBL_HORIZ_DELTA:
        MOVE    (MTemp_h).w,D1                  | D1 = new horizontal mouse position
        SUB     (RawMouse_h).w,D1               | D1 = horizontal delta (signed)
        BGE.B   CRSVBL_ADD_HDELTA               | Delta >= 0, add to distance
        SUB     D1,D2                           | Negative: subtract (add absolute value)
        BRA.B   CRSVBL_ACCEL                    | Skip positive path

| ----------------------------------------------------------
|
| CRSVBL_ADD_HDELTA - Add positive horizontal delta to Manhattan distance
|
| Called during boot.
CRSVBL_ADD_HDELTA:
        ADD     D1,D2                           | D2 += horizontal delta (Manhattan distance)

| ----------------------------------------------------------
|
| CRSVBL_ACCEL - Apply mouse acceleration if distance exceeds threshold
|
CRSVBL_ACCEL:
        TST.B   (CrsrScale).w                   | D2 is now the absolute manhattan distance displacement
        BEQ.B   CRSVBL_APPLY_DELTA              | Scaling disabled, use raw deltas
        CMP     (CrsrThresh).w,D2               | Compare distance with acceleration threshold
        BLT.B   CRSVBL_APPLY_DELTA              | Below threshold, no acceleration
        ADD     D1,D1                           | Double horizontal delta (mouse acceleration)
        ADD     D0,D0                           | double the displacement if it's over a threshold
CRSVBL_APPLY_DELTA:
        ADD     D1,(RawMouse_h).w               | Apply horizontal delta to raw mouse position
        ADD     D0,(RawMouse_v).w               | Apply vertical delta to raw mouse position
        LEA.L   (CrsrPin).w,A0                  | A0 = cursor pinning rectangle
        MOVE.L  (RawMouse_v).w,D0               | D0 = raw mouse position (v:h packed)
        BSR.B   PIN_POINT_TO_RECT               | constrain the cursor position
        MOVE.L  D0,(RawMouse_v).w               | Store constrained raw position
        MOVE.L  D0,(MTemp_v).w                  | Sync MTemp with constrained position
        AND.L   (MouseMask).w,D0                | mask the mouse location
        MOVE.L  (MouseOffset).w,D1              | Load mouse coordinate offset
        BEQ.B   CRSVBL_UPDATE_POS               | No offset, skip second constrain
        ADD.L   D1,D0                           | Apply offset to masked position
        BSR.B   PIN_POINT_TO_RECT               | if mouse is offset, constrain the offset position
CRSVBL_UPDATE_POS:
        MOVE.L  D0,(Mouse_v).w                  | update the software-visible mouse location
CRSVBL_REDRAW:
        TST.B   (CrsrObscure).w                 | Is cursor currently obscured?
        BNE.B   CRSVBL_CLEAR_FLAGS              | Yes, skip HideCursor (already hidden)
        BSR     P_HideCursor                    | Erase cursor at old position
CRSVBL_CLEAR_FLAGS:
        CLR.B   (CrsrNew).w                     | Clear "mouse moved" flag
        CLR.B   (CrsrObscure).w                 | Clear "cursor obscured" flag
        BSR     P_ShowCursor                    | Redraw cursor at new position
CRSVBL_RETURN:
        RTS                                     | return from CRSVBL_RETURN

| ----------------------------------------------------------
|
| PIN_POINT_TO_RECT - PinRect helper: constrain a point within a rectangle
|
| D0 = point (v:h packed as two 16-bit words)
| A0 = pointer to pin rectangle (top, left, bottom, right)
| Returns D0 with point clamped to rectangle bounds.
| Horizontal clamped to [left, right-1], vertical to [top, bottom-1].
|
| Called during boot.
PIN_POINT_TO_RECT:
        CMP     0x2(A0),D0                      | Compare point.h with pinRect.left
        BGE.B   PIN_CHECK_RIGHT                 | h >= left, OK
        MOVE    0x2(A0),D0                      | Clamp h to pinRect.left
PIN_CHECK_RIGHT:
        CMP     0x6(A0),D0                      | Compare point.h with pinRect.right
        BLT.B   PIN_CHECK_TOP                   | h < right, OK
        MOVE    0x6(A0),D0                      | Clamp h to pinRect.right
        SUBQ.W  #0x1,D0                         | Adjust to right-1 (stay inside rect)
PIN_CHECK_TOP:
        SWAP    D0                              | Switch to vertical word
        CMP     (A0),D0                         | Compare point.v with pinRect.top
        BGE.B   PIN_CHECK_BOTTOM                | v >= top, OK
        MOVE    (A0),D0                         | Clamp v to pinRect.top
PIN_CHECK_BOTTOM:
        CMP     0x4(A0),D0                      | Compare point.v with pinRect.bottom
        BLT.B   PIN_DONE                        | v < bottom, OK
        MOVE    0x4(A0),D0                      | Clamp v to pinRect.bottom
        SUBQ.W  #0x1,D0                         | Adjust to bottom-1 (stay inside rect)
PIN_DONE:
        SWAP    D0                              | Restore point to v:h packed format
        RTS                                     | return from PIN_DONE

| ----------------------------------------------------------
|
| _PinRect ($A94E) - Constrain a point within a rectangle
|
| Stack: retAddr, point (longword v:h), rectPtr (longword)
| Returns point (clamped to rect) in place of the rect pointer.
|
PinRect:
        MOVE.L  0x4(SP),D0                      | D0 = point to pin (v:h packed)
        MOVE.L  0x8(SP),A0                      | A0 = pointer to pin rectangle
        BSR.B   PIN_POINT_TO_RECT               | Constrain point to rectangle
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x8,SP                         | Remove 8 bytes of parameters
        MOVE.L  D0,(SP)                         | Store result (pinned point) on stack
        JMP     (A0)                            | Return to caller
