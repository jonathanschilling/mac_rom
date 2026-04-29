| Interrupt Handlers (VIA, SCC, Keyboard, Mouse)
|
| 68000 auto-vector interrupts:
| Level 1 (VIA): timer 1 (sound/VBL), timer 2, keyboard shift register,
| one-second tick, VBL (via timer 1)
| Level 2 (SCC): serial port A/B receive/transmit/status change,
| mouse quadrature via DCD transitions on SCC channels
|
| VIA interrupt dispatch reads IFR & IER to find source, then jumps
| through Lvl1DT vector table (at low-memory address KeyThresh+4*n).
| SCC interrupt dispatch reads RR2B (modified vector) bits [3:1] to
| identify source, then jumps through Lvl2DT vector table.
|
| Hardware registers accessed:
| VIA IFR (0xEFFBFE) - interrupt flag register, read to identify source
| VIA IER (0xEFFDFE) - interrupt enable register, mask active interrupts
| VIA SR (0xEFF5FE) - shift register, keyboard byte transfer
| VIA PortB (0xEFE1FE) - mouse button, RTC, screen beam position
| SCC read base (0x9FFFF8) - RR0/RR2 status, RR8 receive data
| SCC write base (0xBFFFF9) - WR0 command, WR2 vector, WR1 enables
|
| References:
| Inside Macintosh Vol II, Ch 6: Device Manager - Interrupts (pp 195-201)
| Inside Macintosh Vol III, Ch 2: VIA, SCC hardware details

| ----------------------------------------------------------
|
| Level 1 Interrupt: VIA (vector $64)
| Dispatches: Timer 1/2, keyboard, VBL, one-second
|
Lvl1Int_VIA:
        MOVEM.L D0-D3/A0-A3,-(SP)               | save caller-saved regs for ISR context
VIA_DISPATCH:
        LEA.L   (KeyThresh).w,A0                | A0 = Lvl1DT base (KeyThresh = slot 0)
        MOVE.L  (VIA).w,A1                      | A1 = VIA base register
        MOVE.B  vIFR(A1),D0                     | D0 = VIA IFR (interrupt flag register)
        AND.B   vIER(A1),D0                     | D0 &= IER: active enabled sources
        BSET    #0x7,D0                         | set sentinel bit (force loop termination)
VIA_SCAN_NEXT:
        ADDQ.L  #0x4,A0                         | advance to next Lvl1DT vector slot
        LSR.B   #0x1,D0                         | shift out lowest IFR bit into carry
        BCC.B   VIA_SCAN_NEXT                   | no interrupt from this source: try next
        MOVE.L  (A0),A0                         | load handler address from Lvl1DT slot
        JSR     (A0)                            | call VIA interrupt sub-handler
LVL1_RETURN:
        MOVEM.L (SP)+,D0-D3/A0-A3               | restore caller-saved regs
        RTE                                     | return from interrupt

| ----------------------------------------------------------
| Level 2 Interrupt: SCC (vector $68)
| SCC interrupt flags = SCCBControl[3:1]
| Reads RR2B to identify interrupt source, dispatches via Lvl2DT.
| RR2B modified vector bits [3:1] encode the source:
| 0x0=Ch B Tx empty, 0x2=Ch B ext/status, 0x4=Ch B Rx ready,
| 0x6=Ch B special, 0x8=Ch A Tx empty, 0xA=Ch A ext/status,
| 0xC=Ch A Rx ready, 0xE=Ch A special
| SCCBControl[3]: 0=channel B, 1=channel A
Lvl2Int_SCC:
        MOVEM.L D0-D3/A0-A3,-(SP)               | Save registers for interrupt context
        MOVE.L  (SCCRd).w,A0                    | A0 = SCC read base (channel B control)
        MOVE.B  (A0),D0                         | read from SCC B control into D0- this gets thrown away, but side effect is to select SCC register index 0
        MOVE.L  (SCCWr).w,A1                    | A1 = SCC write base (channel B control)
        MOVE.B  #0x2,(A1)                       | write $2 to SCC B control| selects RR2B
        LEA.L   (Lvl2DT).w,A2                   | A2 = level-2 dispatch table base
        MOVEQ.L #0xE,D0                         | Mask for bits [3:1] of RR2B
        AND.B   (A0),D0                         | get and mask interrupt flag bits from RR2B, reset register index to 0
        CMPI.B  #0x8,D0                         | Bit 3 set = channel A source
        BLT.B   SCC_DISPATCH_JMP                | Channel B: keep A0/A1 pointing to B
        ADDQ.W  #0x2,A0                         | Advance SCC read ptr to channel A
        ADDQ.W  #0x2,A1                         | point to channel A instead of B
SCC_DISPATCH_JMP:
        ADD     D0,D0                           | D0*2 = longword index into Lvl2DT
        MOVE.L  0x0(A2,D0.W),A2                 | Load handler address from Lvl2DT
        JSR     (A2)                            | Call SCC interrupt sub-handler
        MOVEM.L (SP)+,D0-D3/A0-A3               | Restore registers saved at entry
| Spurious_IntVIAandSCC -- installed as Vector $6C (spurious interrupt).
| Any SCC/VIA interrupt with no active source lands here and just RTEs.
Spurious_IntVIAandSCC:
        RTE                                     | return immediately (nothing to do)

| ----------------------------------------------------------
| ExtBInt_StatusChngSCC - SCC channel-B external-status interrupt handler
| (installed as Lvl2DT[1] = slot for channel B ext/status)
ExtBInt_StatusChngSCC:
        LEA.L   (SCCBSts).w,A3                  | A3 = saved SCC ch B status low-mem
        LEA.L   (ExtStsDT).w,A2                 | A2 = ext-status dispatch table (ch B)
        BRA.B   EXTSTATUS_DISPATCH              | jump to shared decode path

| ExtAInt_StatusChngSCC - SCC channel-A external-status interrupt handler
ExtAInt_StatusChngSCC:
        LEA.L     (SCCASts).w,A3                | A3 = saved SCC ch A status low-mem
        LEA.L     (ExtStsDT_A).w,A2             | A2 = ext-status dispatch table (ch A)
EXTSTATUS_DISPATCH:
        MOVE.B  (A0),D0                         | D0 = current ext-status byte
        MOVE.B  (A3),D1                         | D1 = previous ext-status byte
        EOR.B   D0,D1                           | D1 = changed bits since last time
        MOVE.B  D0,(A3)                         | save new status byte
        MOVE.B  #0x10,(A1)                      | WR0 = 0x10 (reset ext/status)
        CMPI.B  #0x8,D1                         | did the DCD bit (bit 3) change?
        BNE.B   EXTSTATUS_RESET                 | no: keep slot index = 0
        ADDQ.W  #0x4,A2                         | yes: advance to DCD-change slot
EXTSTATUS_RESET:
        MOVE.L  (A2),A2                         | A2 = dispatch handler
        JMP     (A2)                            | tail-call handler

| OneSecInt_VIA - VIA Timer 2 / one-second interrupt handler
OneSecInt_VIA:
        ADDQ.L  #0x1,(Time).w                   | increment seconds-since-boot counter
        MOVE.B  #0x1,vIFR(A1)                   | clear CA1 interrupt flag (write to IFR)
ONESEC_DONE:
        RTS                                     | return to Lvl1Int_VIA dispatch

| VBLInt_VIA - VIA Timer 1 / VBL interrupt handler
VBLInt_VIA:
        ADDQ.L  #0x1,(Ticks).w                  | Increment 60 Hz tick counter
        MOVE.B  #0x2,vIFR(A1)                   | Clear T1 interrupt flag in IFR
        MOVE    #0x2000,SR                      | Lower IPL to allow level-2 (SCC) interrupts
        BSET    #0x6,(VBLQueueHdr_Flags).w      | Mark VBL processing in progress
        BNE.B   ONESEC_DONE                     | Already in VBL processing: re-entrance guard
        MOVE.L  (StackLowPoint).w,D0            | Load stack low-water mark
        BEQ.B   VBL_CURSOR_TASK                 | 0 = no low-water tracking, skip check
        CMPA.L  D0,SP                           | compare SP to low-water
        BCC.W   VBL_CHECK_HEAP                  | SP >= low point: skip update
        MOVE.L  SP,(StackLowPoint).w            | Record new stack low-water mark
VBL_CHECK_HEAP:
        MOVE.L  (ApplZone).w,A1                 | A1 = application heap zone header
        CMPA.L  (A1),SP                         | SP vs heap top?
        BCC.W   VBL_CURSOR_TASK                 | SP above heap, stack OK
        MOVEQ.L #0x1C,D0                        | dsStknHeap: stack has grown into heap
        _SysError                               | Fatal system error
VBL_CURSOR_TASK:
        MOVE.L  (JCrsrTask).w,A0                | Load cursor VBL task vector
        JSR     (A0)                            | run cursor VBL task
        BTST    #0x0,(Ticks_LoByte).w           | Test bit 0 of tick counter (odd/even)
        BNE.B   VBL_TASK_QUEUE                  | Odd tick: skip mouse button processing
        MOVEQ.L #0x1,D0                         | D0 = mouseUp event code (default)
        MOVE.B  (0xEFE1FE).l,D2                 | D2 = VIA PortB (PB3 = mouse button)
        ASL.B   #0x4,D2                         | shift PB3 into sign bit
        BPL.B   VBL_CHECK_BTN_CHG               | PB3=1 (button up): post mouseUp event
        MOVEQ.L #0x2,D0                         | PB3=0 (button down): D0 = mouseDown event code
VBL_CHECK_BTN_CHG:
        MOVE.B  (MBState).w,D1                  | Load previous mouse button state (bit 7)
        EOR.B   D2,D1                           | bitwise XOR: D1 = changed bits
        BPL.B   VBL_BTN_DONE                    | No state change, skip event posting
        MOVE.L  (Ticks).w,D1                    | Load current tick count
        SUB.L   (MBTicks).w,D1                  | Ticks since last button state change
        CMPI.L  #0x3,D1                         | Debounce: require 3+ ticks (~50ms)
        BLT.B   VBL_BTN_DONE                    | Too soon, ignore this transition
        ADD.L   D1,(RndSeed).w                  | Mix elapsed time into random seed
        MOVE.L  (Ticks).w,(MBTicks).w           | Record tick of this button transition
        ANDI.B  #0x80,D2                        | Isolate sign bit (button state)
        MOVE.B  D2,(MBState).w                  | Store new button state (0x80=up, 0x00=down)
        MOVE.L  D0,A0                           | A0 = event code (1=mouseUp, 2=mouseDown)
        MOVEQ.L #0x0,D0                         | D0 = event message (none for mouse events)
        _PostEvent                              | Post mouse button event to OS event queue
VBL_BTN_DONE:
        MOVE.B  (Ticks_LoByte).w,D0             | Load low byte of tick counter
        ANDI.B  #0x1F,D0                        | Mask to 5 bits: fires every 32 ticks (~0.5s)
        BNE.B   VBL_TASK_QUEUE                  | Not time yet, skip keyboard task
        MOVE.L  (JKybdTask).w,D0                | Load keyboard periodic task vector
        BEQ.B   VBL_TASK_QUEUE                  | No keyboard task installed, skip
        MOVE.L  D0,A0                           | A0 = keyboard task address
        JSR     (A0)                            | Execute keyboard periodic task (auto-repeat)
VBL_TASK_QUEUE:                                 | walk VBL task queue
        MOVE.L  (VBLQueueHdr_Head).w,D0         | D0 = queue head pointer
        BEQ.B   VBL_TASKS_DONE                  | empty queue: done
VBL_TASK_LOOP:
        MOVE.L  D0,A0                           | A0 = current VBL task element
        SUBQ.W  #0x1,vblCount(A0)               | Decrement vblCount (offset 0xA)
        BNE.B   VBL_TASK_NEXT                   | Count not zero yet, skip dispatch
        MOVE.L  A0,-(SP)                        | Save task pointer across call
        MOVE.L  vblAddr(A0),A1                  | A1 = vblAddr (task service routine)
        JSR     (A1)                            | call VBL task service routine
        MOVE.L  (SP)+,A0                        | Restore task pointer
        TST     vblCount(A0)                    | Did task reschedule itself (set vblCount>0)?
        BNE.B   VBL_TASK_NEXT                   | Yes, keep in queue
        LEA.L     (VBLQueueHdr_Flags).w,A1      | A1 = VBL queue header
        JSR     Dequeue(PC)                     | Remove completed task from queue
VBL_TASK_NEXT:
        MOVE.L  (A0),D0                         | D0 = next task (qLink)
        BNE.B   VBL_TASK_LOOP                   | more tasks: loop
VBL_TASKS_DONE:
        BCLR    #0x6,(VBLQueueHdr_Flags).w      | clear "VBL in progress" flag
        RTS                                     | return (back to Lvl1Int_VIA)
| VInstall - insert VBL task A0 into VBL queue
| D0 = 0 on success, -2 on invalid vblType.

| ----------------------------------------------------------
| _VInstall ($A033) - Install a VBL task into the VBL queue
| A0 = pointer to VBL task element (vType must be 1).
| Synchronizes the task's vblCount with the current tick count
| modulo its vblPhase, so tasks fire in the correct phase slot.
| Returns D0 = 0 on success, -2 (vTypErr) on invalid type.
| Called during boot.
VInstall:
        CMPI    #vType,qType(A0)                | vblType must be 1 (vType)
        BEQ.B   VINSTALL_SYNC                   | ok: continue
VINSTALL_TYPERR:
        MOVEQ.L #-0x2,D0                        | paramErr
        RTS                                     | Return
VINSTALL_SYNC:
        MOVE    vblCount(A0),D1                 | D1 = vblCount
        BEQ.B   VINSTALL_ENQUEUE                | 0 = never fire; just insert
        MOVE.L  (Ticks).w,D0                    | D0 = current tick count
        DIVU    D1,D0                           | D0 high = Ticks % vblCount
        SWAP    D0                              | D0 = remainder (phase offset)
        MOVE    vblPhase(A0),D1                 | D1 = vblPhase (desired phase)
        BEQ.B   VINSTALL_ENQUEUE                | phase 0: no phase adjust
        SUB     D1,D0                           | D0 = (Ticks%count) - phase
        ADDQ.W  #0x1,D0                         | bias by +1 (next tick)
        BPL.B   VINSTALL_PHASE_OK               | positive: use as-is
        NEG     D0                              | negative: take absolute value
VINSTALL_PHASE_OK:
        ADD     D0,vblCount(A0)                 | first-fire vblCount = adjusted delta
VINSTALL_ENQUEUE:
        LEA.L   (VBLQueueHdr_Flags).w,A1        | A1 = VBL queue header
        JSR     Enqueue(PC)                     | insert into VBL queue
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | Return

| VRemove - remove VBL task A0 from VBL queue
| D0 = 0 on success, -2 on invalid vblType.
VRemove:
        CMPI    #vType,qType(A0)                | Check vblType = vType (1)
        BNE.B   VINSTALL_TYPERR                 | not a vType task: return paramErr
        MOVE.L  A1,-(SP)                        | Save A1 (caller may need it)
        LEA.L   (VBLQueueHdr_Flags).w,A1        | A1 = VBL queue header
        JSR     Dequeue(PC)                     | remove from VBL queue
        MOVE.L  (SP)+,A1                        | Restore A1
        RTS                                     | Return
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
        RTS                                     | Return

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
        RTS                                     | Return

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
| ScrnAddress -- _ScrnAddress trap implementation.
| Returns the screen base address in the longword on the stack at +4
| (the caller's reserved result slot). Trivial: just copies (ScrnBase).w.
ScrnAddress:
        MOVE.L  (ScrnBase).w,4(SP)              | result = ScrnBase
        RTS                                     | Return

| ----------------------------------------------------------
| ScrnSize -- _ScrnSize trap implementation.
| Returns the framebuffer dimensions (width x height) via two pointers
| pushed on the stack. Mac 128K/512K screen = 512 x 342 mono pixels.
ScrnSize:
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
        RTS                                     | Return
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
        RTS                                     | Return
MOUSE_MOVE_DOWN:
        ADDQ.W  #0x1,(MTemp_v).w                | Y1^Y2 = 0, move down
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | Signal cursor update needed
CRSVBL_RETURN:                                  | shared RTS
        RTS                                     | Return
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
        RTS                                     | Return

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
| ----------------------------------------------------------
| EMT1010_TrapDispatch -- 68000 Line 1010 Emulator (A-trap dispatcher)
| Installed as the line-1010 exception vector ($28). Every A-line
| instruction ($Axxx) traps here. The 68000 frame is SR (word) +
| PC (long). The trap word $Axxx is fetched from the saved PC; we
| then split into OS-trap path (D2 < $A800) and Toolbox path
| (D2 >= $A800). For Toolbox traps, bit 10 = "auto-pop" (caller
| pre-popped its own return address; we collapse the stack).
| Layout matches Plus's src/plus/os/trap_dispatch.s but classic
| has no 68020 frame-fixup (Mac 128K/512K never shipped with
| anything but a 68000).
EMT1010_TrapDispatch:                           | A-trap dispatch entry
        SUBQ.L  #0x2,SP                         | reserve a stack slot for handler addr
        MOVEM.L D1-D2/A2,-(SP)                  | save dispatcher's working regs
        MOVE.L  16(SP),A2                       | A2 = saved PC from exception frame
        MOVE    (A2)+,D2                        | D2 = trap word ($Axxx); advance PC
        MOVE.L  A2,16(SP)                       | store updated return PC back to frame
        MOVE    D2,D1                           | D1 = copy of trap word (for OS handler)
        CMPI    #-0x5800,D2                     | test bit 11: $A800 unsigned (-0x5800 sign)
        BCS.B   TRAP_OS_PATH                    | bit 11 = 0: OS trap (-> $1064)
        BSR.B   TRAP_RESOLVE_HANDLER            | Toolbox: resolve handler addr
        MOVE.L  D2,12(SP)                       | store handler addr in reserved slot
        CMPI    #-0x5400,D1                     | test bit 10: $AC00 unsigned (auto-pop)
        MOVEM.L (SP)+,D1-D2/A2                  | restore work regs
        BCS.B   TRAP_TBOX_DISPATCH              | bit 10 = 0: normal Toolbox dispatch
        MOVE.L  (SP)+,(SP)                      | auto-pop: discard glue retaddr
TRAP_TBOX_DISPATCH:
        RTS                                     | jump to handler via stack slot
| ----------------------------------------------------------
| TRAP_RESOLVE_HANDLER -- convert 9-bit trap index in D2 to absolute
| handler address. Looks up DispatchTab[D2*2], unpacks the compressed
| ROM-relative or RAM-relative offset, returns absolute addr in D2.
TRAP_RESOLVE_HANDLER:
        ANDI    #0x1FF,D2                       | mask to 9-bit trap number
        EXT.L    D2                             | sign-extend to 32 bits
        ADD     D2,D2                           | *2 (word index into DispatchTab)
        LEA.L     (DispatchTab).w,A2            | A2 = dispatch table base
        MOVE    0(A2,D2.W),D2                   | D2 = packed offset entry
        ADD     D2,D2                           | shift LSB to carry: 0=ROM, 1=RAM
        BCS.B   TRAP_RESOLVE_RAM                | RAM-resident handler -> rebase
        ADD.L   (ROMBase).w,D2                  | ROM handler: D2 = ROMBase + offset
        RTS                                     | return with absolute ROM handler in D2
TRAP_RESOLVE_RAM:
        ADD.L   (RAMBase).w,D2                  | RAM handler: D2 = RAMBase + offset
        RTS                                     | return with absolute RAM handler in D2

| ----------------------------------------------------------
| TRAP_OS_PATH -- OS trap (low 256 entries of dispatch table).
| Bit 8 of trap word: 0 = save+restore A0 across handler call,
| 1 = handler returns result in A0 (no save).
TRAP_OS_PATH:
        BCLR    #0x8,D2                         | test+clear bit 8 (save-A0 flag)
        BNE.B   TRAP_OS_NOSAVEREG               | bit 8 was set: don't save A0
        BSR.B   TRAP_RESOLVE_HANDLER            | resolve OS handler addr
        MOVE.L  D2,A2                           | A2 = handler entry
        MOVEM.L A0-A1,-(SP)                     | save A0+A1 (A0 will be restored)
        JSR     (A2)                            | call OS handler
        MOVEM.L (SP)+,A0-A1                     | restore A0+A1 (A0 preserved)
TRAP_OS_RETURN:                                 | shared epilogue
        MOVEM.L (SP)+,D1-D2/A2                  | restore dispatcher work regs
        ADDQ.W  #0x4,SP                         | discard the reserved handler-addr slot
        TST     D0                              | set CCR from handler's result code
        RTS                                     | return past the trap word
TRAP_OS_NOSAVEREG:                              | bit 8 = 1 path (A0 = result)
        BSR.B   TRAP_RESOLVE_HANDLER            | resolve handler addr
        MOVE.L  D2,A2                           | A2 = handler entry
        MOVE.L  A1,-(SP)                        | save A1 only (A0 carries result back)
        JSR     (A2)                            | call OS handler
        MOVE.L  (SP)+,A1                        | restore A1
        BRA.B   TRAP_OS_RETURN                  | rejoin common epilogue
| ----------------------------------------------------------
| GetTrapAddress -- returns dispatch handler addr for trap word in D0.
| Used by patches to chain into the original implementation. Calls
| TRAP_RESOLVE_HANDLER and returns the resolved address in A0.
GetTrapAddress:
        MOVE.L  A2,-(SP)                        | save A2
        MOVE    D0,D2                           | D2 = trap word from caller
        BSR.B   TRAP_RESOLVE_HANDLER            | resolve to absolute addr
        MOVE.L  D2,A0                           | A0 = resolved handler
        MOVE.L  (SP)+,A2                        | restore A2
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | return from GetTrapAddress (A0 = handler)
| InstallDispatch - install A-trap handler at D0 -> A0 into DispatchTab
| D0 = A-trap index (0..511), A0 = handler address (ROM or RAM)
| Stores compressed offset: ROM addresses use offset from ROMBase,
| RAM addresses use offset from RAMBase with LSB=1 as the tag.
InstallDispatch:
        MOVE.L  A0,D1                           | D1 = handler address
        CMP.L   (ROMBase).w,D1                  | address >= ROMBase?
        BLT.B   INSTDISP_RamPath                | no: use RAM-base offset
        SUB.L   (ROMBase).w,D1                  | yes: D1 = offset from ROMBase
INSTDISP_Store:
        ROR     #0x1,D1                         | shift bit 0 to MSB (ROM=0, RAM=1)
        ANDI    #0x1FF,D0                       | D0 = trap idx in low 9 bits
        ADD     D0,D0                           | D0 *= 2 (word index into DispatchTab)
        LEA.L   (DispatchTab).w,A0              | A0 = dispatch table base
        MOVE    D1,0(A0,D0.W)                   | DispatchTab[D0] = offset tag
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | return from InstallDispatch (D0 = noErr)
INSTDISP_RamPath:
        SUB.L   (RAMBase).w,D1                  | D1 = offset from RAMBase
        ADDQ.W  #0x1,D1                         | +1 so ROR gives MSB=1 (RAM tag)
        BRA.B   INSTDISP_Store                  | back to shared store path
| ----------------------------------------------------------
| Trailing 4 bytes of InstallDispatch ($10C4..$10C7) -- looks like a
| 2-instruction inline pad. Probably an unused entry point or
| alignment leftover from an earlier code revision.
INSTDISP_TAIL_PADDING:
        ORI.B   #0x4A,D6                        | D6 |= 0x4A (4-byte ORI sequence,
        ORI     #0x880,(A2)                     | never reached at runtime)
        .short  0x000F                          | 2-byte alignment pad leftover from rev

| ----------------------------------------------------------
| FETCH_STASH_COMMON -- driver helper used by char-mode drivers (.AIn,
| .Sound etc.) for next-byte read/write through a circular buffer
| on a DCE (Device Control Entry).
| Entry: A1 = DCE ptr, D0 = byte (.W or .B); bit 0xF of D0 = "write"
| On entry, 8(A1) = QHdr ptr (queue of pending requests).
| Exit: CCR.Z=1 if buffer space exhausted (D0 bit 0xF set).
FETCH_STASH_COMMON:
        MOVEM.L D1/A2-A3,-(SP)                  | save work regs
        MOVE.L  8(A1),D1                        | D1 = current request ptr
        BEQ.B   IO_CORE_ERR                     | nil request: fatal dsIOCoreErr
        MOVE.L  D1,A3                           | A3 = request ptr (mutable)
        MOVE.L  ioActCount(A3),D1               | D1 = byte index (ioActCount)
        MOVE.L  ioBuffer(A3),A2                 | A2 = buffer base (ioBuffer)
        BCLR    #0xF,D0                         | test+clear write-mode bit in D0
        BNE.B   FETCH_STASH_WRITE               | bit set: write D0 byte to buffer
        MOVE.B  0(A2,D1.L),D0                   | read: D0 = buffer[D1]
        BRA.B   FETCH_STASH_ADVANCE             | bump index + check end
FETCH_STASH_WRITE:
        MOVE.B   D0,0(A2,D1.L)                  | buffer[D1] = D0
FETCH_STASH_ADVANCE:
        ADDQ.L  #0x1,D1                         | byte index += 1
        MOVE.L  D1,ioActCount(A3)               | store updated ioActCount
        CMP.L   ioReqCount(A3),D1               | compare with ioReqCount (limit)
        BLT.B   FETCH_STASH_EXIT                | not yet at limit: return
        BSET    #0xF,D0                         | set bit 0xF: signal "buffer full"
FETCH_STASH_EXIT:
        TST     D0                              | set CCR for caller
        MOVEM.L (SP)+,D1/A2-A3                  | restore work regs
        RTS                                     | return to caller with Z flag reflecting status
| ----------------------------------------------------------
| IO_CORE_ERR -- fatal I/O core error (no active request, bad qType, etc.)
| Reached when the I/O queue or DCE is in an inconsistent state.
| Calls _SysError with dsIOCoreErr (id 14) and never returns; the trailing
| BSET/BRA bytes are never executed (would loop back into FETCH_STASH_COMMON
| if _SysError ever returned).
IO_CORE_ERR:                                    | fatal dsIOCoreErr
        MOVEQ.L #0xE,D0                         | D0 = 14 = dsIOCoreErr
        _SysError                               | halt system with fatal I/O error
        BSET    #0xF,D0                         | (unreachable: _SysError never returns)
        BRA.B   FETCH_STASH_COMMON              | (unreachable)

| ----------------------------------------------------------
| IODone -- driver-completion trap entry (called via _IODone).
| Walks the I/O queue at A1 (= DCE), removes the just-completed
| request from the queue head, runs ioCompletion if installed,
| then returns to the next pending request (or RTE if none).
| Entry: A1 = DCE ptr, D0 = result code
IODone:                                         | _IODone trap entry
        MOVEQ.L #0x0,D0                         | (D0 will hold result on entry)
        MOVE.L  8(A1),A0                        | A0 = head of pending IO queue
        BTST    #0x1,6(A0)                      | bit 1 of dCtlFlags: I/O active?
        BNE.B   UNLOCK_DRV_CHECK                | yes: skip lock-release (we own it)
        MOVE    SR,-(SP)                        | save SR (interrupt state)
        MOVE    SR,D1                           | D1 = saved SR (for restore later)
        ORI     #0x300,SR                       | mask interrupts (IPL=3)
        BSR.B   CLEAR_DRV_BUSY                  | clear dCtlFlags bit 7 (locked)
        BSR.B   DEQUEUE_IOREQ                   | pop completed request, run completion
        TST.L   8(A1)                           | another request still queued?
        BNE.B   DISPATCH_NEXT_REQ               | yes: continue dispatch
        RTE                                     | done: return from interrupt
CLEAR_DRV_BUSY:
        BCLR    #0x7,5(A1)                      | dCtlFlags &= ~0x80 (release lock)
UNLOCK_DRV_CHECK:
        BTST    #0x6,4(A1)                      | dCtlFlags bit 6: still in dispatch?
        BNE.B   UNLOCK_DRV_DONE                 | yes: skip handle-cleanup
        MOVE.L  (A1),A0                         | A0 = handle to driver (qLink slot)
        BCLR    #0x7,(A0)                       | release lock-byte in master ptr
        MOVE.L  (SysZone).w,A0                  | A0 = system zone header
        ADDA.L  -4(A1),A0                       | A0 += offset (zone-relative back-ptr)
        BCLR    #0x7,(A0)                       | release lock-byte on heap block
UNLOCK_DRV_DONE:
        RTS                                     | return from unlock
DEQUEUE_IOREQ:
        MOVE.L  8(A1),A0                        | A0 = head request (the one completing)
        CMPI    #0x2,4(A0)                      | qType field == 2 (IOQType)?
        BNE.B   IO_CORE_ERR                     | wrong qType: fatal dsIOCoreErr
        MOVE.L  (A0),8(A1)                      | dequeue: head = old.qLink
        BNE.B   DEQUEUE_RESTORE_SR              | more queued: keep tail intact
        CLR.L   12(A1)                          | empty queue: tail = nil
DEQUEUE_RESTORE_SR:
        MOVE    D1,SR                           | restore SR (re-enable interrupts)
        MOVE    D0,16(A0)                       | store result in ioResult field
        BLE.B   DEQUEUE_CHK_COMPL               | result <= 0 (ok or err): keep sign
        NEG     16(A0)                          | result > 0: negate (force noErr/-)
DEQUEUE_CHK_COMPL:
        MOVE.L  12(A0),D1                       | D1 = ioCompletion proc ptr
        BEQ.B   DEQUEUE_DONE                    | nil: no callback, return
        MOVE.L  A1,-(SP)                        | save A1 (the DCE ptr)
        MOVE.L  D1,A1                           | A1 = completion proc
        TST     D0                              | set CCR from result code (handler arg)
        JSR     (A1)                            | call ioCompletion(D0=result, A0=IOParam)
        MOVE.L  (SP)+,A1                        | restore DCE ptr
DEQUEUE_DONE:                                   | common return from IODone
        RTS                                     | return from _IODone trap
