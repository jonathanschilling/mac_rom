| Interrupt handlers (VIA, SCC)
|
| Apple source: InterruptHandlers.a (MacSEROM.lst module INTHND): LVL1INT
| (VIA: one-second interrupt, VBL, the ADB shift register, timer 2 of the
| Time Manager, ... dispatched through Lvl1DT), LVL2INT (SCC, dispatched
| through Lvl2DT; the mouse is on ADB, not on the SCC as in the Mac Plus),
| SPURIOUS, EXTBINT/EXTAINT (SCC external/status interrupts), ONESECINT
| and VBLINT (runs the VBL task queue every tick; the queue itself is
| kept by os/vbl_mgr.s).
|
| References: Inside Macintosh Vol II, Ch 6 (interrupts); Inside
| Macintosh Vol V, Ch 3 (SE hardware).

| LVL1INT - Level 1 interrupt handler (VIA)
|
| 68000 auto-vector level 1 (vector $64). Reads VIA IFR ANDed with
| IER to identify active interrupt source. Scans bits 0-6 via LSR,
| then dispatches through Lvl1DT vector table (low memory at KeyThresh).
| Sources: Timer2, Timer1, keyboard SR, CB2, shift reg, 1-sec, VBL
INTHND:                                         | Apple source module (MacSEROM.lst)
LVL1INT:
    MOVEM.L     D0-D3/A0-A3,-(A7)               | save registers for interrupt context
    LEA.L       (KeyThresh).W,A0                | A0 = Lvl1DT dispatch base
    MOVEA.L     (VIA).W,A1                      | A1 = VIA base register
    MOVE.B      0x1A00(A1),D0                   | D0 = VIA IFR (interrupt flag register)
    AND.B       0x1C00(A1),D0                   | D0 &= IER: active enabled sources only
    BSET        #0x7,D0                         | set sentinel bit (force loop termination)
VIA_SCAN_NEXT:
    ADDQ.L      #0x4,A0                         | advance to next dispatch vector
    LSR.B       #0x1,D0                         | shift next source bit into carry
    BCC.B       VIA_SCAN_NEXT                   | carry clear: skip this source
    MOVEA.L     (A0),A0                         | A0 = handler address from Lvl1DT
    JSR         (A0)                            | call VIA interrupt handler
    MOVEM.L     (A7)+,D0-D3/A0-A3               | restore registers
    .byte 0x4E,0x73                             | RTE (return from exception)
| LVL2INT - Level 2 interrupt handler (SCC)
|
| 68000 auto-vector level 2 (vector $68). Reads SCC RR2B modified
| vector to identify source (bits [3:1] = interrupt type).
| Channel A sources use offsets >= 8, channel B < 8.
| Dispatches through Lvl2DT vector table in low memory.
LVL2INT:
    MOVEM.L     D0-D3/A0-A3,-(A7)               | save registers for interrupt context
    MOVEA.L     (SCCRd).W,A0                    | A0 = SCC read base (channel B)
    MOVE.B      (A0),D0                         | D0 = RR0 (status, unused here)
    MOVEA.L     (SCCWr).W,A1                    | A1 = SCC write base (channel B)
    MOVE.B      #0x2,(A1)                       | WR0: select register 2
    LEA.L       (Lvl2DT).W,A2                   | A2 = SCC dispatch table base
    MOVEQ.L     #0xE,D0                         | D0 = 0x0E (mask bits [3:1])
    AND.B       (A0),D0                         | D0 = RR2B modified vector & 0x0E
    CMPI.B      #0x8,D0                         | channel A? (vector >= 8)
    BLT.B       SCC_DISPATCH_JMP                | no: channel B, dispatch directly
    ADDQ.W      #0x2,A0                         | adjust to channel A read regs
    ADDQ.W      #0x2,A1                         | adjust to channel A write regs
SCC_DISPATCH_JMP:
    ADD.W       D0,D0                           | D0 *= 2 (longword index)
    MOVEA.L     0x0(A2,D0.W),A2                 | A2 = handler from Lvl2DT
    JSR         (A2)                            | call SCC interrupt handler
    MOVEM.L     (A7)+,D0-D3/A0-A3               | restore registers
SPURIOUS:
    .byte 0x4E,0x73                             | RTE (return from exception)
| EXTBINT - SCC channel B external/status change interrupt
|
| Reads RR0, compares with saved status to detect DCD transitions
| (used for mouse quadrature input via SCC DCD pins).
EXTBINT:
    MOVE.B      (A0),D0                         | D0 = RR0 channel B (current status)
    LEA.L       (SCCBSts).W,A3                  | A3 = saved channel B status
    LEA.L       (ExtStsDT).W,A2                 | A2 = channel B ext/status dispatch
    BRA.B       EXTSTATUS_DISPATCH              | common dispatch
| EXTAINT - SCC channel A external/status change interrupt
EXTAINT:
    MOVE.B      (A0),D0                         | D0 = RR0 channel A (current status)
    LEA.L       (SCCASts).W,A3                  | A3 = saved channel A status
    LEA.L       (ExtStsDT_A).W,A2               | A2 = channel A ext/status dispatch
| EXTSTATUS_DISPATCH - common ext/status handler for both channels
|
| Reads WR15 mask, XORs old and new RR0 to find changed bits.
| Bit 3 (DCD) change selects handler from ExtStsDT[0] or [1].
| Mouse quadrature is detected via DCD transitions on SCC channels.
EXTSTATUS_DISPATCH:
    MOVE.B      #0xF,(A1)                       | WR0: select register 15 (WR15)
    MOVE.B      (A3),D1                         | D1 = previous RR0 (saved status)
    MOVE.B      D0,(A3)                         | save current RR0 as new status
    EOR.B       D0,D1                           | D1 = changed bits (old XOR new)
    AND.B       (A0),D1                         | D1 &= WR15 (enabled changes only)
    CMPI.B      #0x8,D1                         | DCD changed? (bit 3)
    BNE.B       EXTSTATUS_RESET                 | no: use first handler (non-DCD)
    ADDQ.W      #0x4,A2                         | yes: use second handler (DCD)
EXTSTATUS_RESET:
    MOVE.B      #0x10,(A1)                      | WR0 cmd: reset ext/status interrupts
    MOVEA.L     (A2),A2                         | A2 = handler address from dispatch
    JMP         (A2)                            | jump to ext/status handler
| ONESECINT - one-second interrupt handler (VIA CA1)
|
| Increments the system clock (Time global), checks alarm state.
| If alarm time has passed, signals the alarm by clearing AlarmState bit 1.
ONESECINT:
    ADDQ.L      #0x1,(Time).W                   | increment system clock (seconds)
    MOVE.B      #0x1,0x1A00(A1)                 | clear VIA IFR bit 0 (CA1 = 1-sec)
    BCLR        #0x5,(AlarmState)               | clear alarm-checked flag
    TST.B       (SPVolCtl).W                    | alarm enabled? (bit 7 = parm RAM)
    BPL.B       LVL2RTS                         | no: return
    MOVE.L      (SPAlarm).W,D0                  | D0 = alarm time (seconds)
    BEQ.B       LVL2RTS                         | no alarm set: return
    CMP.L       (Time).W,D0                     | alarm time > current time?
    BHI.B       LVL2RTS                         | not yet: return
    BCLR        #0x1,(AlarmState)               | alarm fired: clear pending flag
LVL1RTS:                                        | MacSEROM.lst: second name of this address
LVL2RTS:
    RTS                                         | return from interrupt handler
| VBLINT - vertical blanking interrupt handler (VIA Timer 1)
|
| Called 60.15 times per second. Increments Ticks, processes the VBL
| task queue, checks stack overflow, and calls the cursor task.
VBLINT:
    ADDQ.L      #0x1,(Ticks).W                  | increment VBL tick counter
    MOVE.B      #0x2,0x1A00(A1)                 | clear VIA IFR bit 1 (Timer 1 = VBL)
    MOVE.W      #0x2000,SR                      | lower IPL to 0 (allow nesting)
    BSET        #0x6,(VBLQueueHdr_Flags)        | set VBL-busy flag (reentrancy guard)
    BNE.B       LVL2RTS                         | already processing: return (avoid recursion)
| Stack overflow detection
    MOVE.L      (StackLowPoint).W,D0            | D0 = lowest stack seen so far
    BEQ.B       VBL_CURSOR_TASK                 | not tracking: skip
    CMPA.L      D0,A7                           | current SP below previous low?
    BCC.B       VBL_CHECK_HEAP                  | no: check zone boundary
    MOVE.L      A7,(StackLowPoint).W            | yes: update low-water mark
VBL_CHECK_HEAP:
    MOVEA.L     (ApplZone).W,A1                 | A1 = application zone header
    CMPA.L      (A1),A7                         | stack below zone start?
    BCC.B       VBL_CURSOR_TASK                 | no: safe
    MOVEQ.L     #0x1C,D0                        | dsStknHeap: stack/heap collision
    _SysError                                   | fatal: system error 28
| Cursor task and VBL task queue processing
VBL_CURSOR_TASK:
    MOVE.L      (JCrsrTask).W,D0                | D0 = cursor update task address
    BEQ.B       VBL_TASK_QUEUE                  | no cursor task: skip to VBL queue
    MOVEA.L     D0,A0                           | A0 = cursor task
    JSR         (A0)                            | call cursor update task
| VBL_TASK_QUEUE - walk and fire VBL tasks
|
| Each VBLTask: +0 = qLink, +4 = qType, +6 = vblAddr, +A = vblCount,
| +C = vblPhase. Decrements vblCount; when zero, calls vblAddr.
| If vblCount is still zero after call (task didn't reschedule), dequeue.
VBL_TASK_QUEUE:
    MOVE.L      (VBLQueueHdr_Head).W,D0         | D0 = first VBL task (qHead)
    BEQ.B       VBL_TASKS_DONE                  | empty queue: done
VBL_TASK_LOOP:
    MOVEA.L     D0,A0                           | A0 = current VBL task
    SUBQ.W      #0x1,0xA(A0)                    | decrement vblCount
    BNE.B       VBL_TASK_NEXT                   | not zero: skip this task
    MOVE.L      A0,-(A7)                        | save task pointer across call
    MOVEA.L     0x6(A0),A1                      | A1 = vblAddr (task routine)
    JSR         (A1)                            | call VBL task routine
    MOVEA.L     (A7)+,A0                        | restore task pointer
    TST.W       0xA(A0)                         | task rescheduled? (vblCount != 0)
    BNE.B       VBL_TASK_NEXT                   | yes: keep in queue
    LEA.L       (VBLQueueHdr_Flags).W,A1        | A1 = VBL queue header
    JSR         DEQUEUE(PC)                     | remove one-shot task from queue
VBL_TASK_NEXT:
    MOVE.L      (A0),D0                         | D0 = qLink (next task)
    BNE.B       VBL_TASK_LOOP                   | more tasks: continue
VBL_TASKS_DONE:
    BCLR        #0x6,(VBLQueueHdr_Flags)        | clear VBL-busy flag
    RTS                                         | return from VBL processing
