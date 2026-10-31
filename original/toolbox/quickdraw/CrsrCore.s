| Cursor core -- cursor drawing, ScrnAddress/ScrnSize, mouse interrupts, PinRect
|
| Apple source: CrsrCore.a (System 7.1: QuickDraw/Classic/CrsrCore.a). The
| low-level cursor support behind the QuickDraw cursor traps in
| LCursor.s: those traps jump through the J-vectors (JHideCursor,
| JShowCursor, JShieldCursor, JSetCrsr, JInitCrsr, JCrsrObscure,
| JScrnAddr, JScrnSize) that InitCrsr's table DT_mCRSRCore installs. In
| the 64K ROM the mouse quadrature interrupt handlers (SCCInt_AChng_MouseH,
| SCCInt_BChng_MouseV, which move MTemp) sit inside this file; the Mac Plus
| moved them to hw/interrupts.s. PinRect keeps a point inside a rectangle
| (used by the cursor code and by DragTheRgn).
|
| References: Inside Macintosh Vol I, Ch 6: QuickDraw (cursor handling)

| ----------------------------------------------------------
| DT_mCRSRCore -- cursor manager dispatch table (8 word offsets, 16 B).
| Each word is an offset within the GrafBegin jump-vector area for one
| cursor routine. Indexed by trap selector to dispatch HideCursor,
| ShowCursor, ShieldCursor, ObscureCursor, SetCursor, InitCrsr,
| ScrnAddress, ScrnSize. Loaded at boot via DT_mCRSRCore(PC) reference
| from vectors.s (the "VBL-record end marker" comment there is a
| historical misnomer -- it's really this dispatch table).
DT_mCRSRCore:                                   | DT_mCRSRCore
        .byte   0x00,0x1E,0x00,0x6E,0x01,0x3C   | HideCursor, ShowCursor, ShieldCursor offsets
        .byte   0x01,0xB2,0x01,0xBA,0x00,0x60   | ObscureCursor, SetCrsr, InitCrsr offsets
        .byte   0x01,0x7E,0x00,0x10             | ScrnAddress, ScrnSize offsets

| ----------------------------------------------------------
| P_CrsrObscure -- _ObscureCursor trap implementation.
| Sets the "cursor obscured" flag so the cursor stays hidden until
| the next mouse movement re-shows it via the VBL handler. Falls
| through to P_HideCursor below if the flag was previously clear.
P_CrsrObscure:
        MOVE.B  #0x1,(CrsrBusy).w               | block VBL updates while we touch state
        BSET    #0x0,(CrsrObscure).w            | set "cursor obscured" flag
        BNE.B   CRSR_CLEAR_BUSY                 | already obscured: just clear busy + exit

| ----------------------------------------------------------
| P_HideCursor - Erase cursor from screen, decrement CrsrState
| Restores saved background pixels under the cursor rectangle,
| clears CrsrVis, and decrements CrsrState (hide depth counter).
P_HideCursor:
        MOVE.B  #0x1,(CrsrBusy).w               | Set busy semaphore (block VBL updates)
        TST.B   (CrsrVis).w                     | Is cursor currently visible on screen?
        BEQ.B   HIDE_DEC_STATE                  | No: skip restore, just decrement state
        MOVEM.L D0-D1/A0-A1,-(SP)               | Save work registers
        LEA.L     (CrsrRect).w,A1               | A1 = cursor bounding rectangle
        MOVE    (A1),D1                         | D1 = CrsrRect.top (screen row)
        CLR.L   (A1)+                           | Clear top-left of CrsrRect (mark invalid)
        SUB     (A1),D1                         | D1 = top - bottom (negative height)
        CLR.L   (A1)                            | Clear bottom-right of CrsrRect
        NEG     D1                              | D1 = height of cursor rect
        MOVE.L  (CrsrAddr).w,A1                 | A1 = screen address of cursor top-left
        LEA.L     (CrsrSave).w,A0               | A0 = saved-pixels buffer (64 bytes)
        MOVEQ.L #0x40,D0                        | D0 = 64 (screen-row stride in bytes)
HIDE_RESTORE_ROW:
        MOVE.L  (A0)+,(A1)                      | Restore one longword of background pixels
        ADDA.W  D0,A1                           | advance A1 to the next line in the screen buffer
        SUBQ.W  #0x1,D1                         | Decrement row counter
        BNE.B   HIDE_RESTORE_ROW                | loop until full cursor rect restored
        CLR.B   (CrsrVis).w                     | mark cursor no longer visible
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore work registers
HIDE_DEC_STATE:
        SUBQ.W  #0x1,(CrsrState).w              | decrement hide-depth counter
CRSR_CLEAR_BUSY:                                | shared exit from Show/HideCursor
        CLR.B   (CrsrBusy).w                    | release busy semaphore
        RTS                                     | return from CRSR_CLEAR_BUSY

| ----------------------------------------------------------
| InitCrsr - Initialize cursor state (called once at boot)
| Resets CrsrObscure, sets CrsrState to 0, then falls through
| to ShowCursor to draw the initial cursor on screen.
| Called during boot.
InitCrsr:
        MOVE.B  #0x1,(CrsrBusy).w               | Set busy semaphore during init
        CLR.B   (CrsrObscure).w                 | Clear obscured flag
        CLR     (CrsrState).w                   | Reset hide depth to 0 (balanced)
| InitCrsr falls through into P_ShowCursor to draw the initial cursor.
P_ShowCursor:
        MOVE.B  #0x1,(CrsrBusy).w               | Set busy semaphore (block VBL updates)
        ADDQ.W  #0x1,(CrsrState).w              | Increment show depth counter
        BLT.B   CRSR_CLEAR_BUSY                 | Still hidden (negative): clear busy and exit
        CLR     (CrsrState).w                   | Clamp state to 0 (fully visible)
        TST.B   (CrsrVis).w                     | Already visible on screen?
        BNE.B   CRSR_CLEAR_BUSY                 | Yes: don't double-draw, clear busy and return
        MOVEM.L D0-D5/A0-A3,-(SP)               | Save all work registers
        MOVEQ.L #0x10,D5                        | D5 = 16 (cursor width/height in pixels)
        LEA.L     (CrsrSave).w,A0               | A0 = background save buffer (64 bytes)
        LEA.L     (TheCrsr_data).w,A2           | A2 = cursor image data (16 words)
        LEA.L     (TheCrsr_mask).w,A3           | A3 = cursor mask data (16 words)
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
        BGE.B   SHOW_CLIP_RIGHT                 | X >= 0: no left-edge clipping needed
        MOVEQ.L #0x0,D0                         | Clip cursor left edge to screen column 0
        SWAP    D3                              | Move mask to low word (clear high = clip left)
        SUB     D3,D3                           | Zero low word of mask (left portion off-screen)
        ADD     D5,D2                           | Adjust shift for clipped position
SHOW_CLIP_RIGHT:
        CMPI    #0x1E0,D0                       | Compare X with 480 (512-32): right edge check
        BLE.B   SHOW_CLIP_VERT                  | Within bounds: no right-edge clipping
        MOVE    #0x1E0,D0                       | Clip X to 480 (rightmost cursor position)
        SUB     D3,D3                           | Zero high word of mask (right portion off-screen)
        SWAP    D3                              | Move mask to high word (clip right)
        ADD     D5,D2                           | Adjust shift for clipped position
SHOW_CLIP_VERT:
        MOVE    D5,D4                           | D4 = 16 (initial cursor height)
        MOVE    (Mouse_v).w,D1                  | D1 = current mouse Y position
        SUB     (TheCrsr_hotspot_v).w,D1        | Subtract hotspot Y to get cursor top edge
        BGE.B   SHOW_CLIP_BOTTOM                | Y >= 0: no top-edge clipping needed
        ADD     D1,D4                           | Reduce visible height by off-screen rows
        ADD     D1,D1                           | D1*2 = byte offset for skipped cursor rows
        SUBA.W  D1,A2                           | Advance cursor data past clipped rows
        SUBA.W  D1,A3                           | Advance cursor mask past clipped rows
        MOVEQ.L #0x0,D1                         | Clip Y to row 0 (top of screen)
SHOW_CLIP_BOTTOM:
        CMPI    #0x146,D1                       | Compare Y with 326 (342-16): bottom edge check
        BLE.B   SHOW_SET_RECT                   | Within bounds: proceed to rect setup
        MOVE    #0x156,D4                       | Clip Y so cursor fits within screen
        SUB     D1,D4                           | D4 = visible height after bottom clip
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
| SHOW_DRAW_ROW - Cursor drawing inner loop
| For each row: reads cursor data and mask, shifts/clips to screen
| alignment, saves background longword, applies mask (AND NOT) then
| XORs cursor data onto screen. This produces a proper masked cursor.
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
| P_ShieldCursor -- _ShieldCursor trap implementation.
| Hides the cursor only if it overlaps the supplied rectangle.
| Used by QuickDraw to temporarily move the cursor out of the way
| during drawing operations into specific screen regions.
| Stack on entry (ShieldCursor is a Pascal procedure, no return value):
| 0(SP) = return address (4 bytes)
| 4(SP) = shield rect.top
| 6(SP) = shield rect.left
| 8(SP) = shield rect.bottom
| 10(SP) = shield rect.right
| After MOVEM.L D0/A0,-(SP) adds 8 bytes, fields are at 12/14/16/18(SP).
P_ShieldCursor:
        MOVEM.L D0/A0,-(SP)                     | save work regs (8 bytes pushed)
        LEA.L     (CrsrRect).w,A0               | A0 = current cursor bounding rect
        MOVE    12(SP),D0                       | D0 = shield rect.top
        CMP     (A0)+,D0                        | shield.top vs CrsrRect.top
        BLT.B   SHIELD_NO_OVERLAP               | shield above cursor: no overlap
        CMPI    #0x1F0,(A0)                     | CrsrRect.left vs 496 (off-screen)?
        BGE.B   SHIELD_DO_HIDE                  | cursor off-screen right: force hide
        MOVE    14(SP),D0                       | D0 = shield.left
        CMP     (A0)+,D0                        | shield.left vs CrsrRect.left
        BLE.B   SHIELD_NO_OVERLAP               | shield left of cursor: no overlap
        MOVE    16(SP),D0                       | D0 = shield.bottom
        CMP     (A0)+,D0                        | shield.bottom vs CrsrRect.bottom
        BGE.B   SHIELD_NO_OVERLAP               | shield below cursor: no overlap
        MOVE    18(SP),D0                       | D0 = shield.right
        CMP     (A0),D0                         | shield.right vs CrsrRect.right
        BGE.B   SHIELD_NO_OVERLAP               | shield right of cursor: no overlap
SHIELD_DO_HIDE:
        BSR.W   P_HideCursor                    | overlap: hide cursor (decrements CrsrState)
        BRA.B   SHIELD_RETURN                   | skip fake-decrement
SHIELD_NO_OVERLAP:
        SUBQ.W  #0x1,(CrsrState).w              | account: still "hidden" for caller
SHIELD_RETURN:
        MOVEM.L (SP)+,D0/A0                     | restore work regs
        MOVE.L  (SP)+,(SP)                      | collapse stack: retAddr over shield.top/left
        MOVE.L  (SP)+,(SP)                      | collapse stack: remove shield.bottom/right
        RTS                                     | return (8 bytes of shield rect removed)

| ----------------------------------------------------------
| SetCrsr - Set the current cursor image and hotspot
| Stack: retAddr, cursorPtr (68 bytes: 32 data + 32 mask + 4 hotspot)
| Compares new cursor with current TheCrsr; if different, hides
| old cursor and shows new one. Hotspot values clamped to 0-16.
| Called during boot (3,700 times in 30s trace).
SetCrsr:
        MOVE.L  0x8(SP),A0                      | A0 = pointer to new cursor record
        LEA.L   (TheCrsr_data).w,A1             | A1 = current cursor data in low memory
        MOVEQ.L #0xF,D2                         | D2 = 15 (loop counter: 16 longwords)
        MOVEQ.L #0x0,D1                         | D1 = change counter (0 = no difference)
SETCRSR_CMP_LOOP:
        MOVE.L  (A0)+,D0                        | Load next longword from new cursor
        CMP.L   (A1),D0                         | Compare with current cursor data
        BEQ.B   SETCRSR_STORE                   | Same: skip change count
        ADDQ.W  #0x1,D1                         | Different: increment change counter
SETCRSR_STORE:
        MOVE.L  D0,(A1)+                        | Copy new longword into TheCrsr
        DBF     D2,SETCRSR_CMP_LOOP             | Loop for all 16 longwords (64 bytes)
        MOVE.L  14(SP),(TheCrsr_hotspot_v).w    | Store hotspot (v, h) from caller stack
        TST     D1                              | Any differences detected?
        BEQ.B   SETCRSR_RETURN                  | No changes, skip redraw
        BSR.W   P_HideCursor                    | Erase old cursor from screen
        BSR.W   P_ShowCursor                    | Draw new cursor on screen
SETCRSR_RETURN:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xE,SP                         | remove 14 bytes of parameters (ptr+hotspot+pad)
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
| P_ScrnAddress -- ScrnAddress (same label as in the Plus tree; not in the
| trap dispatch table). Returns the screen base address in the longword on the stack at +4
| (the caller's reserved result slot). Trivial: just copies (ScrnBase).w.
P_ScrnAddress:
        MOVE.L  (ScrnBase).w,4(SP)              | result = ScrnBase
        RTS                                     | return from ScrnAddress

| ----------------------------------------------------------
| P_ScrnSize -- ScrnSize (same label as in the Plus tree; not in the trap
| dispatch table). Returns the framebuffer dimensions (width x height) via two pointers
| pushed on the stack. Mac 128K/512K screen = 512 x 342 mono pixels.
P_ScrnSize:
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = ptr for height result
        MOVE    #0x156,(A0)                     | *A0 = 342 (screen height in pixels)
        MOVE.L  (SP)+,A0                        | A0 = ptr for width result
        MOVE    #0x200,(A0)                     | *A0 = 512 (screen width in pixels)
        JMP     (A1)                            | return via A1 (already popped)
| ----------------------------------------------------------
| SCCInt_AChng_MouseH -- Mouse horizontal quadrature handler.
| Installed as ExtStsDT[3] (SCC channel A DCD-change handler).
| Mouse X-axis tracking uses two quadrature signals:
| X1 = SCC channel A DCD (transitions trigger this handler)
| X2 = VIA PortB bit 4
| Direction = X1 XOR X2: 1 = move right, 0 = move left.
| Increments / decrements MTemp_h, the QD-globals mouse X coord.
SCCInt_AChng_MouseH:
        MOVE.B  (VIA_Base).l,D1                 | D1 = VIA PortB (PB4 = MouseX2)
        ADD     D0,D0                           | shift RR0 bit 3 (X1) into bit 4 position
        EOR     D0,D1                           | D1 bit 4 = X1 XOR X2 (direction)
        BTST    #0x4,D1                         | test quadrature direction bit
        BEQ.B   MOUSE_MOVE_LEFT                 | X1^X2 = 0: move left
        ADDQ.W  #0x1,(MTemp_h).w                | X1^X2 = 1: move right
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | signal cursor update needed
        RTS                                     | return from interrupt sub-handler
MOUSE_MOVE_LEFT:
        SUBQ.W  #0x1,(MTemp_h).w                | X1^X2 = 0: move left
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | signal cursor update needed
        RTS                                     | return from MOUSE_MOVE_LEFT
| ----------------------------------------------------------
| SCCInt_BChng_MouseV - Mouse vertical quadrature handler
| Mouse vertical tracking: SCC channel B DCD transitions = Y1 quadrature.
| Y2 comes from VIA PortB bit 5. Direction = Y1 XOR Y2.
SCCInt_BChng_MouseV:
        MOVE.B  (VIA_Base).l,D1                 | read VIA PortB, PB5 = MouseY2
        ADD     D0,D0                           | Shift RR0 bit 3 (Y1) into bit 4
        ADD     D0,D0                           | Shift again into bit 5 position
        EOR     D0,D1                           | D1 = X^Y in bit 5 position
        BTST    #0x5,D1                         | Test quadrature direction bit
        BEQ.B   MOUSE_MOVE_DOWN                 | Y1^Y2=0: move down
        SUBQ.W  #0x1,(MTemp_v).w                | Y1^Y2 = 1, move up
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | Signal cursor update needed
        RTS                                     | return from SCCInt_BChng_MouseV
MOUSE_MOVE_DOWN:
        ADDQ.W  #0x1,(MTemp_v).w                | Y1^Y2 = 0, move down
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | Signal cursor update needed
CRSVBL_RETURN:                                  | shared RTS
        RTS                                     | return from CRSVBL_RETURN
CrsrVBLTask:
        TST.B   (CrsrNew).w                     | non-zero if mouse position has changed
        BEQ.B   CRSVBL_RETURN                   | no mouse motion: return early
        TST.B   (CrsrBusy).w                    | semaphore
        BNE.B   CRSVBL_RETURN                   | busy: retry next VBL
        TST.B   (CrsrCouple).w                  | if 0, we redraw but don't move
        BEQ.B   CRSVBL_REDRAW                   | Uncoupled: skip position update, just redraw
        MOVE    (MTemp_v).w,D0                  | new vertical mouse position
        SUB     (RawMouse_v).w,D0               | D0 = vertical delta (signed)
        MOVE    D0,D2                           | D2 = vertical delta
        BGE.B   CRSVBL_HORIZ_DELTA              | Delta >= 0: already positive
        NEG     D2                              | Delta negative: D2 = |vertical delta|
CRSVBL_HORIZ_DELTA:
        MOVE    (MTemp_h).w,D1                  | D1 = new horizontal mouse position
        SUB     (RawMouse_h).w,D1               | D1 = horizontal delta (signed)
        BGE.B   CRSVBL_ADD_HDELTA               | Delta >= 0: add absolute value to D2
        SUB     D1,D2                           | Negative: subtract (= add abs value)
        BRA.B   CRSVBL_ACCEL                    | Skip positive-path ADD
CRSVBL_ADD_HDELTA:
        ADD     D1,D2                           | Positive: add to manhattan distance
CRSVBL_ACCEL:
        TST.B   (CrsrScale).w                   | acceleration scaling enabled?
        BEQ.B   CRSVBL_APPLY_DELTA              | Scaling disabled: use raw deltas
        CMP     (CrsrThresh).w,D2               | Compare distance with acceleration threshold
        BLT.B   CRSVBL_APPLY_DELTA              | Below threshold: no acceleration
        ADD     D1,D1                           | Double horizontal delta (mouse acceleration)
        ADD     D0,D0                           | Double vertical delta too
CRSVBL_APPLY_DELTA:
        ADD     D1,(RawMouse_h).w               | Apply horizontal delta to raw mouse position
        ADD     D0,(RawMouse_v).w               | Apply vertical delta to raw mouse position
        LEA.L     (CrsrPin).w,A0                | A0 = cursor pinning rectangle
        MOVE.L  (RawMouse_v).w,D0               | D0 = raw mouse position (v:h packed)
        BSR.B   PIN_POINT_TO_RECT               | constrain to CrsrPin rectangle
        MOVE.L  D0,(RawMouse_v).w               | Store constrained raw position
        MOVE.L  D0,(MTemp_v).w                  | Sync MTemp with constrained position
        AND.L   (MouseMask).w,D0                | mask the mouse location
        MOVE.L  (MouseOffset).w,D1              | Load mouse coordinate offset
        BEQ.B   CRSVBL_UPDATE_POS               | No offset: skip add+constrain
        ADD.L   D1,D0                           | Apply offset to masked position
        BSR.B   PIN_POINT_TO_RECT               | constrain the offset position too
CRSVBL_UPDATE_POS:
        MOVE.L  D0,(Mouse).w                    | Store final cursor position (Mouse = lowmem $830)
CRSVBL_REDRAW:
        TST.B   (CrsrObscure).w                 | Is cursor currently obscured?
        BNE.B   CRSVBL_CLEAR_FLAGS              | Yes: skip HideCursor (already hidden)
        BSR.W   P_HideCursor                    | Erase cursor at old position
CRSVBL_CLEAR_FLAGS:
        CLR.B   (CrsrNew).w                     | Clear "mouse moved" flag
        CLR.B   (CrsrObscure).w                 | Clear "cursor obscured" flag
        BSR.W   P_ShowCursor                    | Redraw cursor at new position
        RTS                                     | return from cursor VBL update

| PIN_POINT_TO_RECT - constrain point D0.L (v:h) to rectangle at (A0)
| D0 in = v:h point; A0 = PinRect top/left/bottom/right (4 words)
PIN_POINT_TO_RECT:
        CMP     2(A0),D0                        | D0.h vs PinRect.left
        BGE.B   PIN_CHECK_RIGHT                 | H >= left: OK
        MOVE    2(A0),D0                        | clamp H to left
PIN_CHECK_RIGHT:
        CMP     6(A0),D0                        | D0.h vs PinRect.right
        BLE.B   PIN_CHECK_TOP                   | H <= right: OK
        MOVE    6(A0),D0                        | clamp H to right
        SUBQ.W  #0x1,D0                         | back off 1 pixel (exclusive)
PIN_CHECK_TOP:
        SWAP    D0                              | switch to vertical word
        CMP     (A0),D0                         | D0.v vs PinRect.top
        BGE.B   PIN_CHECK_BOTTOM                | V >= top: OK
        MOVE    (A0),D0                         | clamp V to top
PIN_CHECK_BOTTOM:
        CMP     4(A0),D0                        | D0.v vs PinRect.bottom
        BLE.B   PIN_DONE                        | V <= bottom: OK
        MOVE    4(A0),D0                        | clamp V to bottom
        SUBQ.W  #0x1,D0                         | back off 1 pixel
PIN_DONE:
        SWAP    D0                              | Restore point to v:h packed format
        RTS                                     | return from PIN_DONE

| ----------------------------------------------------------
| PinRect -- _PinRect trap implementation. Wrapper around
| PIN_POINT_TO_RECT that pulls the point + pin-rect pointer off the
| stack, calls the helper, and pushes the constrained point back as
| the return value. Stack on entry (Pascal calling convention):
| 0(SP) = return address
| 4(SP) = point to pin (v:h packed long)
| 8(SP) = pointer to pin rectangle
PinRect:
        MOVE.L  4(SP),D0                        | D0 = point to pin (v:h packed)
        MOVE.L  8(SP),A0                        | A0 = pointer to pin rectangle
        BSR.B   PIN_POINT_TO_RECT               | Constrain point to rectangle
        MOVE.L  (SP)+,A0                        | A0 = return address
        ADDQ.W  #0x8,SP                         | Remove 8 bytes of parameters
        MOVE.L  D0,(SP)                         | Store result (pinned point) on stack
        JMP     (A0)                            | Return to caller
