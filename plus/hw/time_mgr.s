| Time Manager
|
| Manages asynchronous timer tasks using VIA Timer 2.
| Provides InsXTime, _RmvTime ($A059), and _PrimeTime ($A05A) traps.
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
| Ins X Time
|
| Called during boot.
InsXTime:
        MOVE.L  (TimeVars).w,A1                 | A1 = TimeVars block pointer
        LEA.L   0x8(A1),A1                      | A1 = timer queue header (TimeVars+8)
        _Enqueue                                | insert TMTask (A0) into timer queue
        MOVEQ.L #0x0,D0                         | return noErr
        RTS                                     | exit InsXTime, task added to Time Manager queue

| RmvTime -- trap handler for _RmvTime ($A059).
| ----------------------------------------------------------
|
| _RmvTime ($A059)
|
RmvTime:
        MOVE.L  (TimeVars).w,A1                 | A1 = TimeVars block pointer
        LEA.L   0x8(A1),A1                      | A1 = timer queue header (TimeVars+8)
        _Dequeue                                | remove TMTask (A0) from timer queue
        MOVE.L  (TimeVars).w,A1                 | reload TimeVars pointer
        MOVE.L  0x4(A1),D0                      | D0 = soonest-expiring task ptr
        CMP.L   A0,D0                           | was removed task the soonest?
        BNE.B   RMVTIME_DONE                    | no -- nothing to reschedule
        BSR.B   SCAN_TIMER_QUEUE                | yes -- rescan queue for new soonest task
RMVTIME_DONE:
        RTS                                     | exit _RmvTime, queue and T2 updated if needed

| PrimeTime -- trap handler for _PrimeTime ($A05A).
| ----------------------------------------------------------
|
| _PrimeTime ($A05A)
|
PrimeTime:
        MOVE.L  D0,0xA(A0)                      | store requested delay (ms) in tmCount
        MOVE.L  (TimeVars).w,A0                 | A0 = TimeVars block pointer
        MOVE    SR,-(SP)                        | save status register
        MOVE    #0x2700,SR                      | disable all interrupts (IPL=7)
        MOVE.L  0x4(A0),D1                      | D1 = current soonest task ptr
        BEQ.B   PRIME_NO_ACTIVE                 | no active task -- just schedule new one
        MOVE.L  D1,A1                           | A1 = current soonest TMTask
        CMP.L   0xA(A1),D0                      | new delay vs soonest task's tmCount?
        BGE.B   PRIME_RESTORE_SR                | new task not sooner -- keep current T2
        MOVEQ.L #0x0,D1                         | D1 = 0, will accumulate T2 counter
        MOVE.L  (VIA).w,A1                      | A1 = VIA base address
        MOVE.B  0x1200(A1),D1                   | read T2 counter high byte (T2CH)
        ROR     #0x8,D1                         | shift high byte to bits 15-8
        MOVE.B  D1,0x1000(A1)                   | latch+read T2 counter low byte (T2CL)
        DIVU    #0x30C,D1                       | convert remaining T2 cycles to ms
        EXT.L   D1                              | discard remainder, keep ms quotient
        SUB.L   D1,(A0)                         | reduce last-programmed interval by elapsed ms
        BSR     VIAInt5_Timer2                  | force T2 interrupt: expire current, reschedule
        BRA.B   PRIME_RESTORE_SR                | done -- exit with interrupts restored

| ----------------------------------------------------------
|
| PRIME_NO_ACTIVE -- no task was active; scan queue and start T2
|
PRIME_NO_ACTIVE:
        BSR.B   SCAN_TIMER_QUEUE                | scan queue for soonest task and start T2
PRIME_RESTORE_SR:
        MOVE    (SP)+,SR                        | restore saved interrupt level
        RTS                                     | exit _PrimeTime, task primed and T2 running

| SCAN_TIMER_QUEUE -- Scan timer queue, find soonest task, program VIA Timer 2
|
| Walks the linked list of TMTasks starting from the queue head.
| Finds the task with the smallest positive tmCount, stores it as
| the soonest task (TimeVars+4), then calls PROGRAM_T2 to program T2.
SCAN_TIMER_QUEUE:
        MOVE.L  (VIA).w,A1                      | A1 = VIA base address
        MOVE.B  #0x20,0x1C00(A1)                | clear T2 interrupt enable (IER bit 5)
        MOVE.L  D2,-(SP)                        | save D2 (used as min-delay tracker)
        MOVEQ.L #-0x1,D2                        | D2 = 0xFFFFFFFF (initial min = max positive)
        BCLR    #0x1F,D2                        | D2 = 0x7FFFFFFF (largest positive long)
        MOVEQ.L #0x0,D1                         | D1 = nil (no soonest task found yet)
        MOVE.L  (TimeVars).w,A1                 | A1 = TimeVars block pointer
        MOVE.L  0xA(A1),D0                      | D0 = queue head (first TMTask ptr)
        BEQ.B   SCAN_DONE                       | empty queue -- skip scan
SCAN_NEXT_TASK:
        MOVE.L  D0,A0                           | A0 = current TMTask being examined
        TST.L   0xA(A0)                         | is tmCount zero (task not primed)?
        BEQ.B   SCAN_SKIP_TASK                  | yes -- skip unprimed task
        CMP.L   0xA(A0),D2                      | current min vs this task's tmCount?
        BLT.B   SCAN_SKIP_TASK                  | current min is smaller -- skip
        MOVE.L  0xA(A0),D2                      | D2 = new minimum delay (this tmCount)
        MOVE.L  A0,D1                           | D1 = pointer to soonest task so far
SCAN_SKIP_TASK:
        MOVE.L  (A0),D0                         | D0 = qLink -- next TMTask in queue
        BNE.B   SCAN_NEXT_TASK                  | more tasks -- continue scanning
SCAN_DONE:
        MOVE.L  D1,0x4(A1)                      | store soonest task ptr in TimeVars+4
        MOVE.L  (SP)+,D2                        | restore saved D2
        BSR.B   PROGRAM_T2                      | program T2 for soonest task's delay
        RTS                                     | exit queue scan, T2 programmed with new soonest task

| PROGRAM_T2 -- Program VIA Timer 2 for soonest task
|
| D1 = pointer to soonest TMTask (or nil if none).
| Clamps delay to 84 ms max (T2 is 16-bit: 84*780 < 65536).
| Writes T2CL/T2CH and enables T2 interrupt via IER.
PROGRAM_T2:
        TST.L   D1                              | any soonest task to schedule?
        BEQ.B   T2_NO_TASK                      | no task -- leave T2 disabled
        MOVE.L  D1,A1                           | A1 = soonest TMTask
        MOVE.L  0xA(A1),D1                      | D1 = tmCount (delay in ms)
        MOVEQ.L #0x54,D0                        | D0 = 84 ms max single-shot limit
        CMP.L   D0,D1                           | delay <= 84 ms?
        BLE.B   T2_DELAY_OK                     | yes -- use actual delay
        MOVE.L  D0,D1                           | no -- clamp to 84 ms max
T2_DELAY_OK:
        MOVE.L  (TimeVars).w,A1                 | A1 = TimeVars block pointer
        MOVE.L  D1,(A1)                         | store actual programmed interval (ms)
        MULU    #0x30C,D1                       | convert ms to VIA T2 cycles (780 cyc/ms)
        MOVE.L  (VIA).w,A1                      | A1 = VIA base address
        ROR     #0x8,D1                         | move high byte into low position
        MOVE.B  D1,0x1200(A1)                   | write T2CH -- timer high byte
        ROR     #0x8,D1                         | move low byte into position
        MOVE.B  D1,0x1000(A1)                   | write T2CL -- starts countdown
        MOVE.B  #0xA0,0x1C00(A1)                | IER: set bit 5 = enable T2 interrupt
        LEA.L   VIAInt5_Timer2(PC),A0           | A0 = T2 interrupt handler address
        MOVE.L  A0,(Lvl1DT_5).w                 | install T2 handler in level-1 dispatch table
T2_NO_TASK:
        RTS                                     | exit T2 programming, interrupt armed

| ----------------------------------------------------------
|
| VIAInt5_Timer2 -- Timer 2 interrupt handler
|
| Called when T2 counts down to zero. Subtracts the elapsed interval
| from every primed task's tmCount, then fires the soonest task if
| its tmCount has reached zero or gone negative.
|
VIAInt5_Timer2:
        MOVEM.L D0-D1/A0-A1,-(SP)               | save working registers for ISR
        MOVE.L  (TimeVars).w,A1                 | A1 = TimeVars block pointer
        MOVE.L  0xA(A1),D0                      | D0 = queue head (first TMTask)
        BEQ.B   T2ISR_DONE                      | empty queue -- nothing to process
        MOVE.L  (A1),D1                         | D1 = last programmed T2 interval (ms)
T2ISR_NEXT_TASK:
        MOVE.L  D0,A0                           | A0 = current TMTask
        TST.L   0xA(A0)                         | is tmCount zero (unprimed)?
        BEQ.B   T2ISR_SKIP_TASK                 | yes -- skip, don't subtract from unprimed
        SUB.L   D1,0xA(A0)                      | tmCount -= elapsed ms
T2ISR_SKIP_TASK:
        MOVE.L  (A0),D0                         | D0 = qLink -- next TMTask in queue
        BNE.B   T2ISR_NEXT_TASK                 | more tasks -- continue loop
        MOVE.L  0x4(A1),A0                      | A0 = soonest task (just expired)
        MOVE.L  A0,-(SP)                        | save soonest task ptr across SCAN_TIMER_QUEUE call
        BSR     SCAN_TIMER_QUEUE                | rescan queue for next soonest, reprogram T2
        MOVE.L  (SP)+,A0                        | restore expired task ptr
        TST.L   0xA(A0)                         | did tmCount reach zero or go negative?
        BGT.B   T2ISR_DONE                      | still positive -- not yet expired
        CLR.L   0xA(A0)                         | zero tmCount: mark task as completed
        MOVE.L  0x6(A0),A0                      | A0 = tmAddr -- task completion routine
        JSR     (A0)                            | call the Time Manager task callback
T2ISR_DONE:
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore working registers for VIAInt5_Timer2
        RTS                                     | exit VIAInt5_Timer2 ISR, wait for next T2 interrupt
