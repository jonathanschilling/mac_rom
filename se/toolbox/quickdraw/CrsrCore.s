| Cursor core -- cursor drawing, ScrnAddress/ScrnSize/ScrnBitMap, CrsrVBLTask, PinRect
|
| Apple source: CrsrCore.a (System 7.1: QuickDraw/Classic/CrsrCore.a; the
| SE link map calls the module CRSRCORE). The low-level cursor support
| behind the QuickDraw cursor traps in LCursor.s: those traps jump through
| the J-vectors (JHideCursor, JShowCursor, JShieldCursor, JSetCrsr,
| JInitCrsr, JCrsrObscure, JScrnAddr, JScrnSize) that InitCrsr's table
| DT_mCRSRCore installs. CrsrVBLTask, run by the VBL interrupt, moves
| the cursor with the mouse (mouse acceleration from MTemp/RawMouse),
| and PinRect keeps a point inside a rectangle. In the SE ROM this file
| follows the rest of QuickDraw (the Mac Plus links it near the
| interrupt handlers).
|
| References: Inside Macintosh Vol I, Ch 6: QuickDraw (cursor handling);
| Inside Macintosh Vol III: hardware (screen buffer, mouse)

| ====================================================================
|
| Cursor Manager (CRSRCORE) -- SE-era, software-rendered cursor
|
| The Plus draws a hardware-overlapping cursor via the VIA Timer 1
| ISR. The SE/SE FDHD draws a software cursor by saving and
| restoring the framebuffer pixels under a 16x16 cursor rectangle,
| then XORing data through the mask onto screen.
|
| Low-memory state used:
|   CrsrBusy      flag while we are mid-draw/erase
|   CrsrVis       1 if cursor is currently rendered
|   CrsrState     hide-depth counter (0=visible, <0=hidden)
|   CrsrObscure   1 if cursor was hidden by ObscureCursor
|   CrsrRect      bounding rect on screen (4 words)
|   CrsrAddr      framebuffer addr of CrsrRect.topLeft
|   CrsrSave      saved background longwords (4*16 = 64 bytes)
|   TheCrsr       data, mask, and hotspot
|   Mouse         current mouse position
|
| ====================================================================

| Cursor jump table (CRSRCORE) -- 4 longwords used by the trap
| dispatcher to fan _HideCursor / _ShowCursor / _ShieldCursor /
| _ObscureCursor / _SetCursor to the routines below.
CRSRCORE:                                       | Apple source module (MacSEROM.lst)
INITCRTABLE:
    .long       0x001E0070                      | jump table entries
    .long       0x013E01D0                      | (relative offsets)
    .long       0x01D80062                      | for cursor traps
    .long       0x01800010                      | (4 entries, 16 bytes)
| ----------------------------------------------------------
|
| P_CrsrObscure - Hide cursor and mark as obscured
|
| Called by _ObscureCursor trap. Sets the CrsrObscure flag so the
| cursor stays hidden until the next mouse movement.
|
P_CrsrObscure:
    MOVE.B      #0x1,(CrsrBusy).W               | flag mid-erase
    BSET        #0x0,(CrsrObscure)              | set obscure flag (was it set ?)
    BNE.B       CRSR_CLEAR_BUSY                 | already obscured, just exit
| Fall through into P_HideCursor to actually erase the cursor.
| ----------------------------------------------------------
|
| P_HideCursor - Erase cursor from screen, decrement CrsrState
|
| Restores saved background pixels under the cursor rectangle,
| clears CrsrVis, and decrements CrsrState (hide depth counter).
|
P_HideCursor:
    MOVE.B      #0x1,(CrsrBusy).W               | flag mid-erase
    TST.B       (CrsrVis).W                     | is cursor visible ?
    BEQ.B       HIDE_DEC_STATE                  | no, just dec depth
    MOVEM.L     D0-D1/A0-A1,-(A7)               | save regs
    LEA.L       (CrsrRect).W,A1                 | A1 -> CrsrRect
    MOVE.W      (A1),D1                         | D1 = top
    CLR.L       (A1)+                           | clear top,left
    SUB.W       (A1),D1                         | D1 = top - bottom
    CLR.L       (A1)                            | clear bottom,right
    NEG.W       D1                              | D1 = height in rows
    BEQ.B       HIDE_CLEAR_VIS                  | empty rect, skip restore
    MOVEA.L     (CrsrAddr).W,A1                 | A1 = framebuffer addr
    LEA.L       (CrsrSave).W,A0                 | A0 = saved bg pixels
    MOVEQ.L     #0x40,D0                        | D0 = rowBytes (64)
HIDE_RESTORE_ROW:
    MOVE.L      (A0)+,(A1)                      | restore one longword
    ADDA.W      D0,A1                           | next scanline
    SUBQ.W      #0x1,D1                         | dec row counter
    BGT.B       HIDE_RESTORE_ROW                | loop until done
HIDE_CLEAR_VIS:
    CLR.B       (CrsrVis).W                     | mark cursor erased
    MOVEM.L     (A7)+,D0-D1/A0-A1               | restore regs
HIDE_DEC_STATE:
    SUBQ.W      #0x1,(CrsrState).W              | dec hide-depth counter
CRSR_CLEAR_BUSY:
    CLR.B       (CrsrBusy).W                    | release busy flag
    RTS                                         | return from cursor op
| ----------------------------------------------------------
|
| P_InitCrsr - Initialize cursor state at boot
|
| Sets CrsrObscure and CrsrState to 0, leaves CrsrBusy set so
| the next ShowCursor can come up safely.
|
P_InitCrsr:
    MOVE.B      #0x1,(CrsrBusy).W               | flag mid-init
    CLR.B       (CrsrObscure).W                 | not obscured
    CLR.W       (CrsrState).W                   | hide depth = 0
| Fall through to P_ShowCursor.
| ----------------------------------------------------------
|
| P_ShowCursor - Draw cursor on screen, increment CrsrState
|
| Computes cursor screen position from Mouse and hotspot,
| clips to screen bounds, saves background pixels, then XORs
| cursor data with mask onto the framebuffer.
|
P_ShowCursor:
    MOVE.B      #0x1,(CrsrBusy).W               | flag mid-show
    ADDQ.W      #0x1,(CrsrState).W              | inc hide-depth counter
    BLT.B       CRSR_CLEAR_BUSY                 | still hidden, just exit
    CLR.W       (CrsrState).W                   | clamp >= 0
    TST.B       (CrsrVis).W                     | already drawn ?
    BNE.B       CRSR_CLEAR_BUSY                 | yes, just exit
    MOVEM.L     D0-D5/A0-A3,-(A7)               | save regs
    MOVEQ.L     #0x10,D5                        | D5 = cursor height (16)
    LEA.L       (CrsrSave).W,A0                 | A0 -> bg save buffer
    LEA.L       (TheCrsr_data).W,A2             | A2 -> cursor data
    LEA.L       (TheCrsr_mask).W,A3             | A3 -> cursor mask
    MOVE.W      (Mouse_h).W,D0                  | D0 = mouse h
    SUB.W       (TheCrsr_hotspot_h).W,D0        | bias by hotspot.h
    MOVEQ.L     #0xF,D2                         | D2 = mask = 15
    AND.W       D0,D2                           | D2 = bit offset within longword
    NEG.W       D2                              | flip sign for ROL
    ADD.W       D5,D2                           | D2 = 16 - bitOffset
    MOVEQ.L     #0x0,D3                         | D3 = 0
    SUBQ.W      #0x1,D3                         | D3 = -1 = 0xFFFFFFFF
    LSL.L       D2,D3                           | D3 = mask shifted by D2
    ANDI.W      #0xFFF0,D0                      | D0 = longword-aligned x
    BGE.B       SHOW_CLIP_RIGHT                 | within left edge
    MOVEQ.L     #0x0,D0                         | clamp x to 0
    SWAP.W      D3                              | clear hi half of mask
    SUB.W       D3,D3                           | (D3.lo = 0)
    ADD.W       D5,D2                           | bump shift count
SHOW_CLIP_RIGHT:
    CMPI.W      #0x1E0,D0                       | x past 480 ?
    BLE.B       SHOW_CLIP_VERT                  | no, within right edge
    MOVE.W      #0x1E0,D0                       | clamp x to 480
    SUB.W       D3,D3                           | clear lo half of mask
    SWAP.W      D3                              | (D3.hi = 0)
    ADD.W       D5,D2                           | bump shift count
SHOW_CLIP_VERT:
    MOVE.W      D5,D4                           | D4 = row count
    MOVE.W      (Mouse_v).W,D1                  | D1 = mouse v
    SUB.W       (TheCrsr_hotspot_v).W,D1        | bias by hotspot.v
    BGE.B       SHOW_CLIP_BOTTOM                | within top edge
    ADD.W       D1,D4                           | clip rows from top
    ADD.W       D1,D1                           | D1 *= 2 (word -> byte)
    SUBA.W      D1,A2                           | adjust data ptr
    SUBA.W      D1,A3                           | adjust mask ptr
    MOVEQ.L     #0x0,D1                         | clamp y to 0
SHOW_CLIP_BOTTOM:
    CMPI.W      #0x146,D1                       | y past 326 ?
    BLE.B       SHOW_SET_RECT                   | no, within bottom edge
    MOVE.W      #0x156,D4                       | else max y = 342
    SUB.W       D1,D4                           | clip rows from bottom
SHOW_SET_RECT:
    LEA.L       (CrsrRect).W,A1                 | A1 -> CrsrRect
    MOVE.W      D1,(A1)+                        | top := y
    MOVE.W      D0,(A1)+                        | left := x
    MOVE.W      D1,(A1)                         | bottom := y +
    ADD.W       D4,(A1)+                        | + height
    MOVE.W      D0,(A1)                         | right := x +
    ADDI.W      #0x20,(A1)                      | + 32 (longword width)
    MOVEA.L     (ScrnBase).W,A1                 | A1 = framebuffer base
    LSR.W       #0x3,D0                         | x / 8 = byte offset
    ADDA.W      D0,A1                           | A1 += byte offset
    MOVEQ.L     #0x40,D5                        | D5 = rowBytes (64)
    MULU.W      D5,D1                           | D1 = y * rowBytes
    ADDA.L      D1,A1                           | A1 = framebuffer addr
    MOVE.L      A1,(CrsrAddr).W                 | save in CrsrAddr
    BRA.B       SHOW_DRAW_TEST                  | enter draw loop
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
    MOVE.W      (A2)+,D0                        | D0.lo = cursor data word
    ROL.L       D2,D0                           | shift to bit-aligned position
    AND.L       D3,D0                           | mask to clipped width
    MOVE.W      (A3)+,D1                        | D1.lo = cursor mask word
    ROL.L       D2,D1                           | shift to bit-aligned position
    AND.L       D3,D1                           | mask to clipped width
    NOT.L       D1                              | invert mask
    MOVE.L      (A1),(A0)+                      | save bg longword
    AND.L       D1,(A1)                         | clear bg under cursor mask
    EOR.L       D0,(A1)                         | XOR cursor data into screen
    ADDA.W      D5,A1                           | next scanline
SHOW_DRAW_TEST:
    DBF.W       D4,SHOW_DRAW_ROW                | loop until all rows drawn
    MOVE.B      #0x1,(CrsrVis).W                | mark cursor visible
    MOVEM.L     (A7)+,D0-D5/A0-A3               | restore regs
    CLR.B       (CrsrBusy).W                    | release busy flag
    RTS                                         | return from P_ShowCursor
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
    MOVEM.L     D0/A0,-(A7)                     | save regs
    LEA.L       (CrsrRect).W,A0                 | A0 -> CrsrRect
    MOVE.W      0xC(A7),D0                      | D0 = shield.bottom
    CMP.W       (A0)+,D0                        | shield.bottom < cursor.top ?
    BLT.B       SHIELD_NO_OVERLAP               | yes, no overlap
    CMPI.W      #0x1F0,(A0)                     | cursor.left >= 0x1F0 ?
    BGE.B       SHIELD_DO_HIDE                  | yes, hide cursor (off-screen)
    MOVE.W      0xE(A7),D0                      | D0 = shield.left
    CMP.W       (A0)+,D0                        | shield.left <= cursor.left ?
    BLE.B       SHIELD_NO_OVERLAP               | yes, no overlap
    MOVE.W      0x10(A7),D0                     | D0 = shield.top
    CMP.W       (A0)+,D0                        | shield.top >= cursor.bottom ?
    BGE.B       SHIELD_NO_OVERLAP               | yes, no overlap
    MOVE.W      0x12(A7),D0                     | D0 = shield.right
    CMP.W       (A0),D0                         | shield.right >= cursor.right ?
    BGE.B       SHIELD_NO_OVERLAP               | yes, no overlap
SHIELD_DO_HIDE:
    BSR.W       P_HideCursor                    | overlap, hide cursor
    BRA.B       SHIELD_RETURN                   | and return
| ----------------------------------------------------------
|
| SHIELD_NO_OVERLAP - No overlap: just decrement CrsrState
|
| Called during boot.
SHIELD_NO_OVERLAP:
    SUBQ.W      #0x1,(CrsrState).W              | dec hide-depth (no actual hide)
SHIELD_RETURN:
    MOVEM.L     (A7)+,D0/A0                     | restore regs
    MOVE.L      (A7)+,(A7)                      | strip shield rect (4 bytes)
    MOVE.L      (A7)+,(A7)                      | strip shield rect (4 more bytes)
    RTS                                         | return from P_ShieldCursor
| ----------------------------------------------------------
|
| P_SetCrsr - Install a new cursor (data + mask + hotspot)
|
| Compares each longword of the new cursor with the installed
| TheCrsr; if any differ, increment change counter and copy.
| Clamps hotspot to 16x16. If anything changed, hide+show to
| force redraw with new bits.
|
P_SetCrsr:
    MOVEA.L     0x8(A7),A0                      | A0 = new Cursor
    LEA.L       (TheCrsr_data).W,A1             | A1 = installed TheCrsr
    MOVEQ.L     #0xF,D2                         | 16 longs (data+mask = 64 bytes)
    MOVEQ.L     #0x0,D1                         | D1 = change counter
SETCRSR_CMP_LOOP:
    MOVE.L      (A0)+,D0                        | D0 = next new long
    CMP.L       (A1),D0                         | same as installed ?
    BEQ.B       SETCRSR_STORE                   | yes, no change
    ADDQ.W      #0x1,D1                         | no, count change
SETCRSR_STORE:
    MOVE.L      D0,(A1)+                        | install new long
    DBF.W       D2,SETCRSR_CMP_LOOP             | loop 16 longs
    MOVE.L      0xE(A7),D0                      | D0 = new hotspot (v,h)
    MOVEQ.L     #0x10,D2                        | D2 = clamp = 16
    CMP.W       D2,D0                           | hotspot.h > 16 ?
    BLS.B       SETCRSR_CLAMP_V                 | no, ok
    MOVE.W      D2,D0                           | yes, clamp to 16
SETCRSR_CLAMP_V:
    SWAP.W      D0                              | swap to look at hotspot.v
    CMP.W       D2,D0                           | hotspot.v > 16 ?
    BLS.B       SETCRSR_CHECK_CHG               | no, ok
    MOVE.W      D2,D0                           | yes, clamp to 16
SETCRSR_CHECK_CHG:
    SWAP.W      D0                              | swap back
    CMP.L       (TheCrsr_hotspot_v).W,D0        | new hotspot == old ?
    BEQ.B       SETCRSR_REDRAW                  | yes, no change
    ADDQ.W      #0x1,D1                         | no, count change
    MOVE.L      D0,(TheCrsr_hotspot_v).W        | install new hotspot
SETCRSR_REDRAW:
    TST.W       D1                              | any changes ?
    BEQ.B       SETCRSR_RETURN                  | no, just return
    BSR.W       P_HideCursor                    | yes, erase old cursor
    BSR.W       P_ShowCursor                    | and draw new cursor
SETCRSR_RETURN:
    MOVEA.L     (A7)+,A0                        | pop return addr
    ADDA.W      #0xE,A7                         | strip params
    JMP         (A0)                            | tail-call back
| ----------------------------------------------------------
|
| ScreenAddress / ScreenSize / ScreenBitmap - SE Toolbox-only
| screen-info accessors.  Hardcoded for SE 512x342, rowBytes = 64.
|
SCRNADDRESS:
    MOVE.L      (ScrnBase).W,0x4(A7)            | return ScrnBase on stack
    RTS                                         | return from ScrnAddress
SCRNSIZE:
    MOVEA.L     (A7)+,A1                        | pop return addr
    MOVEA.L     (A7)+,A0                        | pop addr of v
    MOVE.W      #0x156,(A0)                     | *v := 342
    MOVEA.L     (A7)+,A0                        | pop addr of h
STORE_SCRN_WIDTH:
    MOVE.W      #0x200,(A0)                     | *h := 512
    JMP         (A1)                            | tail-call back
SCRNBITMAP:
    MOVEA.L     (A7)+,A1                        | pop return addr
    MOVEA.L     (A7)+,A0                        | pop addr of dest BitMap
    MOVE.L      (ScrnBase).W,(A0)+              | bitMap.baseAddr = ScrnBase
    MOVE.W      (ScreenRow).W,(A0)+             | bitMap.rowBytes = ScreenRow
    CLR.L       (A0)+                           | bitMap.bounds.tl = (0,0)
    MOVE.W      #0x156,(A0)+                    | bitMap.bounds.bottom = 342
    BRA.B       STORE_SCRN_WIDTH                | bitMap.bounds.right = 512
| ====================================================================
|
| CrsrVBLTask -- per-VBL cursor + mouse acceleration tick
|
| Runs from the VBL ISR. If CrsrNew is set (mouse moved), reads
| the latest raw mouse delta from MTemp - RawMouse, accumulates
| mickey samples in a sliding window, computes an acceleration
| factor from the average, and updates RawMouse + Mouse with the
| accelerated delta. Then erases (if visible) and redraws the
| cursor at the new position.
|
| MickeyBytes record layout:
|   +0  W  current sample-count (1..8, sliding)
|   +2  W  max samples = 8
|   +4..+10 W*7 ring buffer of past mickey magnitudes
|   +12 W  scratch (sample sum / fractional remainder)
|   +18 W  fractional remainder
|   +20.. B[8] threshold table for accel curve
|
| ====================================================================
CRSRVBLTASK:
    TST.B       (CrsrNew).W                     | mouse moved since last task ?
    BEQ.W       CRSVBL_RESET_AND_RTS            | no, reset window and exit
    TST.B       (CrsrBusy).W                    | cursor mid-show/hide ?
    BNE.W       CRSVBL_RESET_AND_RTS            | yes, skip this VBL
    TST.B       (CrsrCouple).W                  | mouse coupled to cursor ?
    BEQ.W       CRSVBL_RESET_AND_REDRAW         | no, just redraw at MTemp
    MOVE.W      (MTemp_h).W,D0                  | D0 = MTemp.h
    SUB.W       (RawMouse_h).W,D0               | D0 = mouse delta h
    MOVE.W      (MTemp_v).W,D1                  | D1 = MTemp.v
    SUB.W       (RawMouse_v).W,D1               | D1 = mouse delta v
    MOVE.W      D0,D2                           | D2 = |D0|
    BGE.B       CRSVBL_ABS_DV                   | (already positive)
    NEG.W       D2                              | (negate)
CRSVBL_ABS_DV:
    MOVE.W      D1,D3                           | D3 = |D1|
    BGE.B       CRSVBL_PICK_MAX                 | (already positive)
    NEG.W       D3                              | (negate)
CRSVBL_PICK_MAX:
    CMP.W       D2,D3                           | |dv| <= |dh| ?
    BLS.B       CRSVBL_COMPUTE_MICKEY           | yes, D2 = max
    EXG         D2,D3                           | else swap so D2 = max
CRSVBL_COMPUTE_MICKEY:
    ASR.W       #0x1,D3                         | mickey = max + min/2
    ADD.W       D2,D3                           | (Manhattan-like distance)
    BEQ.W       CRSVBL_RESET_AND_REDRAW         | zero magnitude, no accel
    MOVEA.L     (MickeyBytes).W,A0              | A0 -> MickeyBytes record
    MOVEM.L     D4-D5,-(A7)                     | save D4,D5
    MOVE.W      (A0),D4                         | D4 = current sample count
    CMP.W       0x2(A0),D4                      | at max samples ?
    BGE.B       CRSVBL_RING_DISPATCH            | yes, ring buf is full
    ADDQ.W      #0x1,(A0)                       | else inc sample count
CRSVBL_RING_DISPATCH:
    MOVE.W      D3,D5                           | D5 = new mickey
    MOVE.W      D4,D2                           | D2 = sample count
    SUBQ.W      #0x1,D2                         | -1 for table index
    ASL.W       #0x1,D2                         | *2 for word offset
    JMP         CRSVBL_RING_TBL(PC,D2.W)        | dispatch on sample count (1..8)
| Fan-in summer dispatch table -- compute D5 = sum of latest N
| mickeys stored in the ring buffer at A0+4..A0+16. Each entry
| shifts older samples down by one slot to make room for the new
| sample (which is later stored at slot 6 in CRSVBL_STORE_NEW).
| Entries are 2-byte BRAs except the n=8 case which falls into
| CRSVBL_SUM_SLOT1 so the dispatch table doubles as the n=8 head.
CRSVBL_RING_TBL:
    BRA.B       CRSVBL_STORE_NEW                | n=1: just save new sample
CRSVBL_RING_N2:
    BRA.B       CRSVBL_SUM_SLOT6                | n=2: 1 ring slot
CRSVBL_RING_N3:
    BRA.B       CRSVBL_SUM_SLOT5                | n=3: 2 ring slots
CRSVBL_RING_N4:
    BRA.B       CRSVBL_SUM_SLOT4                | n=4: 3 ring slots
CRSVBL_RING_N5:
    BRA.B       CRSVBL_SUM_SLOT3                | n=5: 4 ring slots
CRSVBL_RING_N6:
    BRA.B       CRSVBL_SUM_SLOT2                | n=6: 5 ring slots
CRSVBL_RING_N7:
    BRA.B       CRSVBL_SUM_SLOT1                | n=7: 6 ring slots
CRSVBL_RING_N8:
    ADD.W       0x4(A0),D5                      | n=8: add slot 0 (oldest)
CRSVBL_SUM_SLOT1:
    ADD.W       0x6(A0),D5                      | add slot 1
    MOVE.W      0x6(A0),0x4(A0)                 | shift slot 1 -> slot 0
CRSVBL_SUM_SLOT2:
    ADD.W       0x8(A0),D5                      | add slot 2
    MOVE.W      0x8(A0),0x6(A0)                 | shift slot 2 -> slot 1
CRSVBL_SUM_SLOT3:
    ADD.W       0xA(A0),D5                      | add slot 3
    MOVE.W      0xA(A0),0x8(A0)                 | shift slot 3 -> slot 2
CRSVBL_SUM_SLOT4:
    ADD.W       0xC(A0),D5                      | add slot 4
    MOVE.W      0xC(A0),0xA(A0)                 | shift slot 4 -> slot 3
CRSVBL_SUM_SLOT5:
    ADD.W       0xE(A0),D5                      | add slot 5
    MOVE.W      0xE(A0),0xC(A0)                 | shift slot 5 -> slot 4
CRSVBL_SUM_SLOT6:
    ADD.W       0x10(A0),D5                     | add slot 6 (newest before this tick)
    MOVE.W      0x10(A0),0xE(A0)                | shift slot 6 -> slot 5
CRSVBL_STORE_NEW:
    MOVE.W      D3,0x10(A0)                     | store new mickey in slot 6
    MOVE.W      D4,D2                           | D2 = sample count
    ASR.W       #0x1,D2                         | /2 for rounding
    ADD.W       D2,D5                           | D5 = sum + N/2
    EXT.L       D5                              | make 32-bit
    DIVU.W      D4,D5                           | D5 = sum / N (avg mickey)
    MOVE.W      D3,D4                           | D4 = new mickey
    SUB.W       D5,D3                           | D3 = new - avg (delta)
    ADD.W       0x12(A0),D3                     | + fractional remainder
    CMPI.W      #0xFFFF,D3                      | did D3 wrap to -1 ?
    BNE.B       CRSVBL_DELTA_OK                 | no
    CLR.W       D3                              | yes, clamp to 0
CRSVBL_DELTA_OK:
    ASR.W       #0x1,D3                         | div by 2 for accel scale
    MOVE.W      D3,0x12(A0)                     | save remainder for next time
    ADD.W       D5,D3                           | D3 = avg + scaled delta
    CMPI.W      #0xFF,D5                        | avg > 255 ?
    BLS.B       CRSVBL_AVG_OK                   | no
    MOVE.B      #0xFF,D5                        | yes, clamp to 255
CRSVBL_AVG_OK:
    MOVEA.L     (MickeyBytes).W,A0              | A0 -> MickeyBytes
    ADDA.W      #0x14,A0                        | A0 -> threshold table at +20
    CLR.W       D2                              | D2 = accel multiplier
CRSVBL_THRESHOLD_LOOP:
    ADDQ.B      #0x1,D2                         | inc multiplier
    CMP.B       (A0)+,D5                        | avg > next threshold ?
    BHI.B       CRSVBL_THRESHOLD_LOOP           | yes, keep looking
    MULS.W      D2,D3                           | D3 = scaled mickey * multiplier
    MULS.W      D3,D0                           | apply to dh
    DIVS.W      D4,D0                           | / new mickey magnitude
    MULS.W      D3,D1                           | apply to dv
    DIVS.W      D4,D1                           | / new mickey magnitude
    MOVEM.L     (A7)+,D4-D5                     | restore D4,D5
    ADD.W       D0,(RawMouse_h).W               | add accelerated dh
    ADD.W       D1,(RawMouse_v).W               | add accelerated dv
    LEA.L       (CrsrPin).W,A0                  | A0 -> CrsrPin rect
    MOVE.L      (RawMouse_v).W,D0               | D0 = packed (v,h)
    BSR.B       PIN_POINT_TO_RECT               | clamp to CrsrPin
    MOVE.L      D0,(RawMouse_v).W               | save back to RawMouse
    MOVE.L      D0,(MTemp_v).W                  | sync MTemp
    AND.L       (MouseMask).W,D0                | apply mouse-region mask
    MOVE.L      (MouseOffset).W,D1              | + offset (for stagger)
    BEQ.B       CRSVBL_UPDATE_POS               | no offset configured
    ADD.L       D1,D0                           | add it
    BSR.B       PIN_POINT_TO_RECT               | re-clamp to CrsrPin
CRSVBL_UPDATE_POS:
    MOVE.L      D0,(Mouse_v).W                  | install in Mouse (visible pos)
CRSVBL_REDRAW:
    TST.B       (CrsrObscure).W                 | cursor obscured ?
    BNE.B       CRSVBL_CLEAR_FLAGS              | yes, skip hide
    _HideCursor                                 | erase old cursor
CRSVBL_CLEAR_FLAGS:
    CLR.B       (CrsrNew).W                     | clear "new mouse" flag
    CLR.B       (CrsrObscure).W                 | unobscure (mouse moved)
    _ShowCursor                                 | redraw cursor at new pos
    RTS                                         | return from CrsrVBLTask
| Mouse not moved (or busy): reset the mickey window and return.
CRSVBL_RESET_AND_RTS:
    MOVEA.L     (MickeyBytes).W,A0              | A0 -> MickeyBytes
    MOVE.W      #0x1,(A0)                       | reset sample count to 1
    CLR.W       0x12(A0)                        | clear fractional remainder
    RTS                                         | return from CrsrVBLTask
| Coupled but no mickey delta: reset window and redraw.
CRSVBL_RESET_AND_REDRAW:
    MOVEA.L     (MickeyBytes).W,A0              | A0 -> MickeyBytes
    MOVE.W      #0x1,(A0)                       | reset sample count to 1
    CLR.W       0x12(A0)                        | clear fractional remainder
    BRA.B       CRSVBL_REDRAW                   | redraw cursor at MTemp
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
    CMP.W       0x2(A0),D0                      | h >= rect.left ?
    BGE.B       PIN_CHECK_RIGHT                 | yes, check right
    MOVE.W      0x2(A0),D0                      | clamp h to rect.left
PIN_CHECK_RIGHT:
    CMP.W       0x6(A0),D0                      | h < rect.right ?
    BLT.B       PIN_CHECK_TOP                   | yes, check top
    MOVE.W      0x6(A0),D0                      | clamp h to rect.right - 1
    SUBQ.W      #0x1,D0                         | (-1)
PIN_CHECK_TOP:
    SWAP.W      D0                              | switch to v word
    CMP.W       (A0),D0                         | v >= rect.top ?
    BGE.B       PIN_CHECK_BOTTOM                | yes, check bottom
    MOVE.W      (A0),D0                         | clamp v to rect.top
PIN_CHECK_BOTTOM:
    CMP.W       0x4(A0),D0                      | v < rect.bottom ?
    BLT.B       PIN_DONE                        | yes, done
    MOVE.W      0x4(A0),D0                      | clamp v to rect.bottom - 1
    SUBQ.W      #0x1,D0                         | (-1)
PIN_DONE:
    SWAP.W      D0                              | switch back to h word
    RTS                                         | return from PinPoint
| ----------------------------------------------------------
|
| PinRect(pt: Point; r: Rect): Point -- public stack wrapper
| around PIN_POINT_TO_RECT.
|
PINRECT:
    MOVE.L      0x4(A7),D0                      | D0 = packed pt (v,h)
    MOVEA.L     0x8(A7),A0                      | A0 -> rect
    BSR.B       PIN_POINT_TO_RECT               | clamp pt to rect
    MOVEA.L     (A7)+,A0                        | pop return addr
    ADDQ.W      #0x8,A7                         | strip params
    MOVE.L      D0,(A7)                         | return pinned pt on stack
    JMP         (A0)                            | tail-call back
