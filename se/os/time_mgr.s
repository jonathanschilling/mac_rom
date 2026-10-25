| Time Manager
|
| Manages asynchronous timer tasks using VIA Timer 2.
| Provides the _InsTime ($A058), _RmvTime ($A059), _PrimeTime ($A05A) traps.
|
| Timer 2 runs in one-shot mode. When a timer fires, VIAInt5_Timer2
| is called as a VIA level-1 interrupt handler. It processes the
| expired timer and reprograms T2 for the next pending timeout.
|
| Conversion: 1 millisecond = 0x30C VIA clock cycles (at ~783 kHz).
| Maximum single-shot delay: 84 ms (0x54 ms * 0x30C = ~65000 cycles).
|
| TimeVars block layout (18 bytes, allocated by _NewPtrSysClear):
| +0x00 (long): last T2 interval actually programmed, in ms
| +0x04 (long): pointer to soonest-expiring TMTask (or nil)
| +0x08 (word): queue header flags
| +0x0A (long): queue header head - first TMTask in linked list
| +0x0E (long): queue header tail
|
| TMTask record layout (passed in A0 to traps):
| +0x00 (long): qLink - next task in queue
| +0x06 (long): tmAddr - completion routine pointer
| +0x0A (long): tmCount - delay remaining in milliseconds
|
| References:
| Inside Macintosh Vol IV, Ch 6: Time Manager
|
| ----------------------------------------------------------
|
| _InsTime ($A058): add a task to the Time Manager queue
| Pascal: PROCEDURE InsTime(tmTaskPtr: QElemPtr);
| Entry: A0 = ptr to TMTask (qLink, qType, tmAddr, tmCount)
| Exit:  D0 = noErr
| Enqueues the task at the queue header TimeVars+8 (_Enqueue). tmCount
| and Timer 2 are not touched: _PrimeTime schedules the task, and
| SCAN_TIMER_QUEUE ignores queued tasks whose tmCount is 0.
|
| Called during boot.

| ----------------------------------------------------------
| Time Manager (SE FDHD)
| Asynchronous timer service using VIA Timer 2 (one-shot mode).
| Provides _InsTime ($A058), _RmvTime ($A059), _PrimeTime ($A05A).
| The SE FDHD variant differs from the Plus by using 0x30F clocks
| per millisecond (vs 0x30C on Plus, reflecting the slightly higher
| VIA clock derived from the SE's faster overall timing budget) and
| extends the ISR to support nested re-entry by deferring expired-
| task callbacks onto the supervisor stack until interrupts are
| restored.
| TimeVars block layout (18 bytes, allocated by _NewPtrSysClear):
|   +0x00 (long): last T2 interval actually programmed (ms)
|   +0x04 (long): pointer to soonest-expiring TMTask (or nil)
|   +0x08 (word): queue header flags
|   +0x0A (long): qHead - first TMTask in linked list
|   +0x0E (long): qTail
| TMTask record (passed in A0):
|   +0x00 long qLink, +0x06 long tmAddr, +0x0A long tmCount(ms)
| _InsTime ($A058) - enqueue TMTask (A0) into timer queue
| Apple source module: TIMEMGR
INSTIME:
    MOVEA.L     (TimeVars).W,A1                 | A1 -> TimeVars
    LEA.L       0x8(A1),A1                      | A1 -> queue header (TimeVars+8)
    _Enqueue                                    | insert TMTask via OS Queue
    MOVEQ.L     #0x0,D0                         | return noErr
    RTS                                         | return from _InsTime
| ----------------------------------------------------------
| _RmvTime ($A059) - dequeue TMTask (A0) and reschedule if needed
RMVTIME:
    MOVEA.L     (TimeVars).W,A1                 | A1 -> TimeVars
    LEA.L       0x8(A1),A1                      | A1 -> queue header
    _Dequeue                                    | remove TMTask from queue
    MOVEA.L     (TimeVars).W,A1                 | reload TimeVars ptr
    MOVE.L      0x4(A1),D0                      | D0 = current soonest task
    CMP.L       A0,D0                           | was removed task the soonest?
    BNE.B       RMVTIME_DONE                    | no -> nothing to reschedule
    BSR.B       SCAN_TIMER_QUEUE                | yes -> rescan + reprogram T2
RMVTIME_DONE:
    RTS                                         | return from _RmvTime
| ----------------------------------------------------------
| _PrimeTime ($A05A) - set tmCount on a TMTask and start T2
| Inputs: A0 -> TMTask, D0.L = delay in milliseconds.
PRIMETIME:
    MOVE.W      SR,-(A7)                        | save status register
    MOVE.W      #0x2700,SR                      | IPL = 7 (mask all interrupts)
    MOVE.L      D0,0xA(A0)                      | tmCount = requested delay
    MOVE.L      A0,-(A7)                        | save TMTask ptr across call
    MOVEA.L     (TimeVars).W,A0                 | A0 -> TimeVars
    MOVE.L      0x4(A0),D1                      | D1 = current soonest task
    BEQ.B       PRIME_NO_ACTIVE                 | no active task -> just schedule
    MOVEA.L     D1,A1                           | A1 = current soonest TMTask
    CMP.L       0xA(A1),D0                      | new delay >= soonest's tmCount?
    BGE.B       PRIME_PEEL                      | yes -> keep current T2 (drop our ptr)
    MOVEQ.L     #0x0,D1                         | clear D1 (will accumulate T2)
    MOVEA.L     (VIA).W,A1                      | A1 = VIA base
    MOVE.B      0x1200(A1),D1                   | T2CH high byte (T2 latched read)
    ROR.W       #0x8,D1                         | shift to bits 15..8
    MOVE.B      0x1000(A1),D1                   | T2CL low byte
    DIVU.W      #0x30F,D1                       | T2 cycles -> ms (SE: 0x30F/ms)
    EXT.L       D1                              | sign-extend ms quotient
    SUB.L       D1,(A0)                         | adjust last-programmed by elapsed
    MOVE.L      (A0),D1                         | D1 = adjusted last-interval
    MOVEA.L     (A7)+,A0                        | restore TMTask ptr
    ADD.L       D1,0xA(A0)                      | tmCount += adjusted-elapsed
    BSR.W       P_VIAint5_Timer2                | force T2-fire to expire current
    BRA.B       PRIME_RESTORE_SR                | -> restore SR
PRIME_NO_ACTIVE:
    BSR.B       SCAN_TIMER_QUEUE                | scan queue + program T2
PRIME_PEEL:
    MOVEA.L     (A7)+,A0                        | drop saved TMTask ptr
PRIME_RESTORE_SR:
    MOVE.W      (A7)+,SR                        | restore interrupt level
    RTS                                         | return from _PrimeTime
| ----------------------------------------------------------
| SCAN_TIMER_QUEUE - find soonest TMTask, program VIA Timer 2
| Walks the queue starting at TimeVars+0xA, finds the smallest
| positive tmCount, stores its ptr in TimeVars+4, then calls
| PROGRAM_T2 to (re-)arm T2 for the chosen delay.
SCAN_TIMER_QUEUE:
    MOVEA.L     (VIA).W,A1                      | A1 = VIA base
    MOVE.B      #0x20,0x1C00(A1)                | IER bit 5 = clear T2 interrupt
    MOVE.L      D2,-(A7)                        | save D2 (min-delay tracker)
    MOVEQ.L     #-0x1,D2                        | D2 = 0xFFFFFFFF
    BCLR        #0x1F,D2                        | D2 = 0x7FFFFFFF (max positive long)
    MOVEQ.L     #0x0,D1                         | D1 = nil (no soonest yet)
    MOVEA.L     (TimeVars).W,A1                 | A1 -> TimeVars
    MOVE.L      0xA(A1),D0                      | D0 = qHead (first TMTask)
    BEQ.B       SCAN_DONE                       | empty queue
SCAN_NEXT_TASK:
    MOVEA.L     D0,A0                           | A0 = current TMTask
    TST.L       0xA(A0)                         | tmCount == 0 (unprimed)?
    BEQ.B       SCAN_SKIP_TASK                  | yes -> skip
    CMP.L       0xA(A0),D2                      | min vs this tmCount?
    BLT.B       SCAN_SKIP_TASK                  | min smaller -> keep
    MOVE.L      0xA(A0),D2                      | new min delay
    MOVE.L      A0,D1                           | D1 = new soonest task ptr
SCAN_SKIP_TASK:
    MOVE.L      (A0),D0                         | qLink -> next TMTask
    BNE.B       SCAN_NEXT_TASK                  | continue
SCAN_DONE:
    MOVE.L      D1,0x4(A1)                      | TimeVars+4 = soonest task
    MOVE.L      (A7)+,D2                        | restore D2
    BSR.B       PROGRAM_T2                      | program T2 for soonest
    RTS                                         | return from SCAN_TIMER_QUEUE
| ----------------------------------------------------------
| PROGRAM_T2 - program VIA T2 for soonest TMTask's delay
| D1 = soonest TMTask ptr (or nil). Clamps tmCount to 83 ms max
| (T2 is 16-bit: 83 * 0x30F = 0xFEAD < 65536). Writes T2CL/T2CH and
| enables T2 interrupt via IER. The 0x53 ms cap differs from Plus's
| 0x54 due to SE's faster clock.
PROGRAM_T2:
    TST.L       D1                              | any soonest task?
    BEQ.B       T2_NO_TASK                      | no -> leave T2 disabled
    MOVEA.L     D1,A1                           | A1 = soonest TMTask
    MOVE.L      0xA(A1),D1                      | D1 = tmCount (ms)
    MOVEQ.L     #0x53,D0                        | 83 ms max for SE FDHD T2
    CMP.L       D0,D1                           | delay <= 83 ms?
    BLE.B       T2_DELAY_OK                     | yes -> use actual
    MOVE.L      D0,D1                           | clamp to 83 ms
T2_DELAY_OK:
    MOVEA.L     (TimeVars).W,A1                 | A1 -> TimeVars
    MOVE.L      D1,(A1)                         | record actual programmed (ms)
    MULU.W      #0x30F,D1                       | ms -> VIA T2 cycles (SE: 0x30F/ms)
    MOVEA.L     (VIA).W,A1                      | A1 = VIA base
    MOVE.B      D1,0x1000(A1)                   | write T2CL low byte
    ROR.W       #0x8,D1                         | bring high byte to position
    MOVE.B      D1,0x1200(A1)                   | write T2CH high byte (starts countdown)
    MOVE.B      #0xA0,0x1C00(A1)                | IER: enable T2 interrupt (bit 5)
    LEA.L       P_VIAint5_Timer2(PC),A0         | A0 -> T2 interrupt handler
    MOVE.L      A0,(Lvl1DT_5).W                 | install T2 handler in lvl-1 dispatch
T2_NO_TASK:
    RTS                                         | return from PROGRAM_T2
| ----------------------------------------------------------
| P_VIAint5_Timer2 - VIA Timer 2 interrupt handler
| Called when T2 counts down to 0. Subtracts last-programmed ms
| from every primed task's tmCount, queues expired-task callbacks
| onto the supervisor stack, rescans the queue to reprogram T2,
| then dispatches the queued callbacks with interrupts re-enabled.
P_VIAint5_Timer2:
    MOVEM.L     D0-D2/A0-A2,-(A7)               | save working regs for ISR
    MOVE.W      SR,D2                           | D2 = saved SR (entry IPL)
    ORI.W       #0x300,SR                       | IPL = 7 during queue walk
    MOVEA.L     (TimeVars).W,A1                 | A1 -> TimeVars
    MOVE.L      0xA(A1),D0                      | D0 = qHead (first TMTask)
    BEQ.B       T2ISR_RESTORE                   | empty queue
    MOVE.L      (A1),D1                         | D1 = last programmed interval (ms)
    MOVEA.L     A7,A2                           | A2 = saved SP (callback queue base)
T2ISR_NEXT_TASK:
    MOVEA.L     D0,A0                           | A0 = current TMTask
    TST.L       0xA(A0)                         | tmCount == 0 (unprimed)?
    BEQ.B       T2ISR_SKIP_TASK                 | yes -> skip
    SUB.L       D1,0xA(A0)                      | tmCount -= elapsed ms
    BGT.B       T2ISR_SKIP_TASK                 | still positive -> not expired
    CLR.L       0xA(A0)                         | reached 0 or below: mark complete
    MOVE.L      0x6(A0),-(A7)                   | push tmAddr for deferred dispatch
T2ISR_SKIP_TASK:
    MOVE.L      (A0),D0                         | qLink -> next TMTask
    BNE.B       T2ISR_NEXT_TASK                 | continue queue walk
    BSR.W       SCAN_TIMER_QUEUE                | reprogram T2 for next soonest
    MOVE.W      D2,SR                           | restore caller's IPL (allow nesting)
T2ISR_DISPATCH:
    CMPA.L      A2,A7                           | callback queue empty?
    BEQ.B       T2ISR_DONE                      | yes -> done
    MOVEA.L     (A7)+,A0                        | A0 = next deferred tmAddr
    MOVEM.L     D2/A2,-(A7)                     | save D2/A2 across callback
    JSR         (A0)                            | call task completion routine
    MOVEM.L     (A7)+,D2/A2                     | restore
    BRA.B       T2ISR_DISPATCH                  | next callback
T2ISR_RESTORE:
    MOVE.W      D2,SR                           | restore caller's IPL
T2ISR_DONE:
    MOVEM.L     (A7)+,D0-D2/A0-A2               | restore working regs
    RTS                                         | exit T2 ISR

