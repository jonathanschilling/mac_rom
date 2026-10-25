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
        RTS                                     | return from ONESEC_DONE

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
        RTS                                     | return from VBL_TASKS_DONE

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
        RTS                                     | return from SCCInt_AChng_MouseH

| ----------------------------------------------------------
|
| MOUSE_MOVE_LEFT - Mouse move left
|
MOUSE_MOVE_LEFT:
        SUBQ.W  #0x1,(MTemp_h).w                | X1^X2 = 0, move left
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | Signal cursor update needed
        RTS                                     | return from MOUSE_MOVE_LEFT

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
        RTS                                     | return from SCCInt_BChng_MouseV

| ----------------------------------------------------------
|
| MOUSE_MOVE_DOWN - Mouse move down
|
MOUSE_MOVE_DOWN:
        ADDQ.W  #0x1,(MTemp_v).w                | Y1^Y2 = 0, move down
        MOVE.B  (CrsrCouple).w,(CrsrNew).w      | Signal cursor update needed
        RTS                                     | return from MOUSE_MOVE_DOWN

