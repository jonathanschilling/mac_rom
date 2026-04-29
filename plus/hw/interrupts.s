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
        MOVEM.L D0-D3/A0-A3,-(SP)               | Save registers for interrupt context
        TST.B   (HWCfgFlags).w                  | Check hardware config (SCSI present?)
| --- ROM-variant difference @ $1A4A ---
| v1: BEQ.B VIA_DISPATCH -- branched only when HWCfgFlags was zero,
| leaving the SCSI_INT_CHECK path dead if
| the flag was set.
| v2/v3: BRA.B VIA_DISPATCH -- unconditional branch; SCSI_INT_CHECK is
| reached only via its explicit label.
| Reason: v1 had a condition-code bug here. v2 fixed it by widening to
| an unconditional branch so the intended control flow (VIA
| dispatch unless code falls through to SCSI_INT_CHECK from
| elsewhere) holds regardless of HWCfgFlags.
.if ROM_TARGET == MAC_PLUS_V1
        BEQ.B   VIA_DISPATCH                    | Plus v1: conditional (buggy)
.else
        BRA.B   VIA_DISPATCH                    | Plus v2/v3: always branch to VIA dispatch
.endif

| ----------------------------------------------------------
|
| SCSI_INT_CHECK
| SCSI pseudo-DMA interrupt check (Mac Plus only).
| If NCR 5380 has a pending interrupt, acknowledge it
| and return from the level-1 handler without VIA dispatch.
|
SCSI_INT_CHECK:
        MOVE.L  #SCSI_Base,A0                   | NCR 5380 SCSI controller
        BTST    #0x4,0x50(A0)                   | Check SCSI interrupt pending (bus/phase)
        BEQ.B   VIA_DISPATCH                    | Not SCSI, check VIA
        TST.B   0x70(A0)                        | Acknowledge SCSI interrupt
        BRA.B   LVL1_RETURN                     | Return from interrupt

| ----------------------------------------------------------
|
| VIA_DISPATCH - VIA interrupt source identification and dispatch
|
| Reads IFR ANDed with IER to find which VIA interrupt fired.
| Scans bits 0-6 (Timer2, Timer1, CB1/keyboard, CB2, SR, CA1/1sec, CA2/VBL)
| via LSR loop, then jumps through Lvl1DT dispatch table.
|
| Called during boot.
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
|
| Level 2 Interrupt: SCC (vector $68)
|
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
Spurious_IntVIAandSCC:
        RTE                                     | Return from level-2 interrupt

| ----------------------------------------------------------
|
| ExtBInt_StatusChngSCC - SCC channel B external/status change
|
| Handles DCD transitions on channel B (mouse Y1 quadrature).
| Compares old vs new RR0 to detect which ext/status bit changed,
| then dispatches via ExtStsDT table.
|
ExtBInt_StatusChngSCC:
        MOVE.B  (A0),D0                         | get channel B RR0
        LEA.L   (SCCBSts).w,A3                  | A3 = saved channel B status byte
        LEA.L   (ExtStsDT).w,A2                 | A2 = channel B ext/status dispatch table
        BRA.B   EXTSTATUS_DISPATCH              | Merge with channel A handler

| ----------------------------------------------------------
|
| ExtAInt_StatusChngSCC - SCC channel A external/status change
|
| Handles DCD transitions on channel A (mouse X1 quadrature).
|
ExtAInt_StatusChngSCC:
        MOVE.B  (A0),D0                         | get channel A RR0. Bit 3 = X1 or Y1.
        LEA.L   (SCCASts).w,A3                  | A3 = saved channel A status byte
        LEA.L   (ExtStsDT_A).w,A2               | A2 = channel A ext/status dispatch table

| ----------------------------------------------------------
|
| EXTSTATUS_DISPATCH - Common ext/status dispatch for both SCC channels
|
| Reads WR15 (ext/status interrupt enable mask), XORs old and new
| RR0 to find changed bits, ANDs with WR15 to isolate enabled changes.
| Bit 3 (DCD) change dispatches through ExtStsDT[0] or [1].
|
EXTSTATUS_DISPATCH:
        MOVE.B  #0xF,(A1)                       | select register $F
        MOVE.B  (A3),D1                         | get previous status
        MOVE.B  D0,(A3)                         | save new status
        EOR.B   D0,D1                           | XOR old and new status
        AND.B   (A0),D1                         | AND with register F, reset register to 0
        CMPI.B  #0x8,D1                         | Test if DCD changed (bit 3)
        BNE.B   EXTSTATUS_RESET                 | Not DCD - use first ExtStsDT slot
        ADDQ.W  #0x4,A2                         | DCD changed - use second ExtStsDT slot
EXTSTATUS_RESET:
        MOVE.B  #0x10,(A1)                      | SCC cmd: reset ext/status interrupts
        MOVE.L  (A2),A2                         | Load handler address from ExtStsDT
        JMP     (A2)                            | Tail-call the mouse quadrature handler

| ----------------------------------------------------------
|
| OneSecInt_VIA - One-second interrupt handler
|
| Called during boot.
| Triggered by VIA CA1 every second. Increments global time counter
| (seconds since 1/1/1904), clears the one-second IFR flag, and
| checks the alarm clock against the current time.
OneSecInt_VIA:
        ADDQ.L  #0x1,(Time).w                   | Increment seconds since 1/1/1904
        MOVE.B  #0x1,0x1A00(A1)                 | Clear T2 interrupt flag in IFR
        BCLR    #0x5,(AlarmState).w             | Clear "alarm checked" flag
        TST.B   (SPVolCtl).w                    | Test sign bit: negative = alarm enabled
        BPL.B   ONESEC_DONE                     | Alarm disabled, return
        MOVE.L  (SPAlarm).w,D0                  | Load alarm time (secs since 1/1/1904)
        BEQ.B   ONESEC_DONE                     | No alarm set, return
        CMP.L   (Time).w,D0                     | Compare alarm time vs current time
        BHI.B   ONESEC_DONE                     | Alarm time still in the future, return
        BCLR    #0x1,(AlarmState).w             | Alarm has fired: clear "alarm pending" bit
ONESEC_DONE:
        RTS                                     | Return

| ----------------------------------------------------------
|
| VBLInt_VIA - Vertical blanking interrupt handler (60.15 Hz)
|
| Called during boot.
| VIA Timer 1 fires at 60.15 Hz (every vertical blank interval).
| Increments Ticks, processes mouse button via VIA PortB bit 3,
| runs cursor task, posts mouse-down/up events, runs VBL task queue.
VBLInt_VIA:
        ADDQ.L  #0x1,(Ticks).w                  | Increment 60 Hz tick counter
        MOVE.B  #0x2,0x1A00(A1)                 | Clear T1 interrupt flag in IFR
        MOVE    #0x2000,SR                      | Lower IPL to allow level-2 (SCC) interrupts
        BSET    #0x6,(VBLQueueHdr_Flags).w      | Mark VBL processing in progress
        BNE.B   ONESEC_DONE                     | Already in VBL processing, return (reentrance guard)
        MOVE.L  (StackLowPoint).w,D0            | Load stack low-water mark
        BEQ.B   VBL_CURSOR_TASK                 | No low-water tracking, skip check
        CMPA.L  D0,SP                           | Compare current SP with recorded low point
        BCC     VBL_CHECK_HEAP                  | SP >= low point, skip update
        MOVE.L  A7,(StackLowPoint).w            | Record new stack low-water mark
VBL_CHECK_HEAP:
        MOVE.L  (ApplZone).w,A1                 | A1 = application heap zone header
        CMPA.L  (A1),SP                         | Compare SP against heap zone start
        BCC     VBL_CURSOR_TASK                 | SP above heap, stack OK
        MOVEQ.L #0x1C,D0                        | dsStknHeap: stack has grown into heap
        _SysError                               | Fatal system error
VBL_CURSOR_TASK:
        MOVE.L  (JCrsrTask).w,A0                | Load cursor VBL task vector
        JSR     (A0)                            | Execute cursor update (CrsrVBLTask)
        BTST    #0x0,(Ticks_LoByte).w           | Test bit 0 of tick counter (odd/even)
        BNE.B   VBL_TASK_QUEUE                  | Odd tick: skip mouse button processing
        MOVEQ.L #0x1,D0                         | D0 = mouseUp event code (default)
        MOVE.B  (VIA_Base).l,D2                 | Read VIA PortB: PB3=mouse button
        ASL.B   #0x4,D2                         | Shift PB3 into sign bit (N flag)
        BPL.B   VBL_CHECK_BTN_CHG               | PB3=1 (button up): post mouseUp event (D0=1)
        MOVEQ.L #0x2,D0                         | PB3=0 (button down): D0 = mouseDown event code
VBL_CHECK_BTN_CHG:
        MOVE.B  (MBState).w,D1                  | Load previous mouse button state (bit 7)
        EOR.B   D2,D1                           | XOR with current state: sign bit=1 if changed
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

| ----------------------------------------------------------
|
| VBL task queue processing
|
| Walks the VBL queue (linked list at VBLQueueHdr). For each task,
| decrements vblCount. When count reaches zero, calls the task's
| vblAddr routine. If vblCount is still zero after the call (task
| did not reschedule itself), the task is dequeued.
|
VBL_TASK_QUEUE:
        MOVE.L  (VBLQueueHdr_Head).w,D0         | D0 = first VBL task in queue (or nil)
        BEQ.B   VBL_TASKS_DONE                  | Queue empty, done
VBL_TASK_LOOP:
        MOVE.L  D0,A0                           | A0 = current VBL task element
        SUBQ.W  #0x1,0xA(A0)                    | Decrement vblCount (offset 0xA)
        BNE.B   VBL_TASK_NEXT                   | Count not zero yet, skip to next task
        MOVE.L  A0,-(SP)                        | Save task pointer across call
        MOVE.L  0x6(A0),A1                      | A1 = vblAddr (task service routine)
        JSR     (A1)                            | Call VBL task service routine
        MOVE.L  (SP)+,A0                        | Restore task pointer
        TST     0xA(A0)                         | Did task reschedule itself (set vblCount>0)?
        BNE.B   VBL_TASK_NEXT                   | Yes, keep in queue
        LEA.L   (VBLQueueHdr_Flags).w,A1        | A1 = VBL queue header
        JSR     Dequeue(PC)                     | Remove completed task from queue
VBL_TASK_NEXT:
        MOVE.L  (A0),D0                         | D0 = qLink: next task in queue
        BNE.B   VBL_TASK_LOOP                   | More tasks, continue loop
VBL_TASKS_DONE:
        BClr    #0x6,(VBLQueueHdr_Flags).w      | Clear "VBL in progress" flag
        RTS                                     | Return

| ----------------------------------------------------------
|
| Mouse quadrature interrupt handlers
|
| on entry, D0 = newest channel A/B RR0 value. Bit 3 = X1 or Y1.
| Mouse horizontal tracking: SCC channel A DCD transitions = X1 quadrature.
| X2 comes from VIA PortB bit 4. Direction = X1 XOR X2.
SCCInt_AChng_MouseH:
        MOVE.B  (VIA_Base).l,D1                 | read VIA PortB, PB4 = MouseX2
        ADD     D0,D0                           | Shift RR0 bit 3 (X1) into bit 4 position
        EOR     D0,D1                           | XOR X1 with PortB to isolate X1^X2 in bit 4
        BTST    #0x4,D1                         | Test quadrature direction bit
        BEQ.B   MOUSE_MOVE_LEFT                 | X1^X2=0: move left
        ADDQ.W  #0x1,(MTemp_h).w                | X1^X2 = 1, move right
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | Signal cursor update needed
        RTS                                     | Return

| ----------------------------------------------------------
|
| MOUSE_MOVE_LEFT - Mouse move left
|
MOUSE_MOVE_LEFT:
        SUBQ.W  #0x1,(MTemp_h).w                | X1^X2 = 0, move left
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | Signal cursor update needed
        RTS                                     | Return

| ----------------------------------------------------------
|
| SCCInt_BChng_MouseV - Mouse vertical quadrature handler
|
| Mouse vertical tracking: SCC channel B DCD transitions = Y1 quadrature.
| Y2 comes from VIA PortB bit 5. Direction = Y1 XOR Y2.
SCCInt_BChng_MouseV:
        MOVE.B  (VIA_Base).l,D1                 | read VIA PortB, PB5 = MouseY2
        ADD     D0,D0                           | Shift RR0 bit 3 (Y1) into bit 4
        ADD     D0,D0                           | Shift again into bit 5 position
        EOR     D0,D1                           | XOR Y1 with PortB to isolate Y1^Y2 in bit 5
        BTST    #0x5,D1                         | Test quadrature direction bit
        BEQ.B   MOUSE_MOVE_DOWN                 | Y1^Y2=0: move down
        SUBQ.W  #0x1,(MTemp_v).w                | Y1^Y2 = 1, move up
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | Signal cursor update needed
        RTS                                     | Return

| ----------------------------------------------------------
|
| MOUSE_MOVE_DOWN - Mouse move down
|
MOUSE_MOVE_DOWN:
        ADDQ.W  #0x1,(MTemp_v).w                | Y1^Y2 = 0, move down
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | Signal cursor update needed
        RTS                                     | Return

| ----------------------------------------------------------
|
| _VInstall ($A033) - Install a VBL task into the VBL queue
|
| A0 = pointer to VBL task element (vType must be 1).
| Synchronizes the task's vblCount with the current tick count
| modulo its vblPhase, so tasks fire in the correct phase slot.
| Returns D0 = 0 on success, -2 (vTypErr) on invalid type.
|
| Called during boot.
VInstall:
        CMPI    #0x1,0x4(A0)                    | Check vblType = vType (1)
        BEQ.B   VINSTALL_SYNC                   | Valid VBL type, proceed
VINSTALL_TYPERR:
        MOVEQ.L #-0x2,D0                        | vTypErr: invalid queue element type
        RTS                                     | Return

| ----------------------------------------------------------
|
| VINSTALL_SYNC - VInstall phase synchronization and enqueue
|
| Called during boot.
VINSTALL_SYNC:
        MOVE    0xA(A0),D1                      | D1 = vblCount (initial tick interval)
        BEQ.B   VINSTALL_ENQUEUE                | Count=0: no phase sync needed, just enqueue
        MOVE    SR,-(SP)                        | Save SR and raise IPL
        ORI     #0x100,SR                       | Disable VIA (level-1) interrupts during sync
        MOVE.L  (Ticks).w,D0                    | D0 = current 32-bit tick count
        SWAP    D0                              | D0.W = high word of Ticks
        MOVEQ.L #0x0,D2                         | Clear D2 for 32-bit divide setup
        MOVE    D0,D2                           | D2 = high word of Ticks
        DIVU    D1,D2                           | D2 = (Ticks_hi % vblCount) in upper word
        SWAP    D2                              | D2.W = remainder from high-word divide
        MOVE    D2,D0                           | Prepend remainder to low word of Ticks
        SWAP    D0                              | D0 = (remainder:Ticks_lo) for second divide
        DIVU    D1,D0                           | D0 upper = Ticks mod vblCount
        SWAP    D0                              | D0.W = Ticks mod vblCount
        SUB     0xC(A0),D0                      | Subtract vblPhase from (Ticks mod vblCount)
        NEG     D0                              | D0 = phase offset ticks until first fire
        BPL.B   VINSTALL_PHASE_OK               | Positive: fire in D0 ticks
        ADD     D1,D0                           | Negative: wrap around by adding vblCount
VINSTALL_PHASE_OK:
        ADD     D0,0xA(A0)                      | Adjust vblCount to synchronize phase
        MOVE    (SP)+,SR                        | Restore interrupt level
VINSTALL_ENQUEUE:
        LEA.L   (VBLQueueHdr_Flags).w,A1        | A1 = VBL queue header
        JSR     Enqueue(PC)                     | Insert task into VBL queue
        MOVEQ.L #0x0,D0                         | Return noErr
        RTS                                     | Return

| ----------------------------------------------------------
|
| _VRemove ($A034) - Remove a VBL task from the VBL queue
|
| A0 = pointer to VBL task element.
| Returns D0 from Dequeue (0=success, qErr if not found).
|
VRemove:
        CMPI    #0x1,0x4(A0)                    | Check vblType = vType (1)
        BNE.B   VINSTALL_TYPERR                 | Invalid type, return vTypErr
        MOVE.L  A1,-(SP)                        | Save A1 (caller may need it)
        LEA.L   (VBLQueueHdr_Flags).w,A1        | A1 = VBL queue header
        JSR     Dequeue(PC)                     | Remove task from VBL queue
        MOVE.L  (SP)+,A1                        | Restore A1
        RTS                                     | Return

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
        RTS                                     | Return

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
        RTS                                     | Return

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
        RTS                                     | Return

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
| Color2Index - Return screen bitmap info (base, rowBytes, bounds)
|
| On Mac Plus (1-bit display), returns a bitmap descriptor:
| ScrnBase, ScreenRow (64), bounds rect (0,0,342,512).
| Re-uses STORE_SCRN_WIDTH to store the width as the last step.
|
| Called during boot.
Color2Index:
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
        RTS                                     | Return

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
        RTS                                     | Return

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
