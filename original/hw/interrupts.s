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
