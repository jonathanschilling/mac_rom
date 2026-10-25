| Vertical Retrace Manager -- _VInstall / _VRemove
|
| Apple source: VerticalRetraceMgr.a (MacSEROM.lst module VBLCORE). The
| VBL interrupt handler, which runs the VBL task queue every tick, is
| VBLInt_VIA in hw/interrupts.s; these two traps only maintain the queue
| (VBLQueue).
|
| VBLTask (Inside Macintosh II-350): +0 qLink, +4 qType (vType = 1),
| +6 vblAddr (task routine), +10 vblCount (ticks until the next call,
| 0 = inactive), +12 vblPhase (phase offset against the other tasks).
|
| References: Inside Macintosh Vol II, Ch 11: The Vertical Retrace Manager

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
        RTS                                     | return from VINSTALL_TYPERR
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
        RTS                                     | return from VINSTALL_ENQUEUE

| VRemove - remove VBL task A0 from VBL queue
| D0 = 0 on success, -2 on invalid vblType.
VRemove:
        CMPI    #vType,qType(A0)                | Check vblType = vType (1)
        BNE.B   VINSTALL_TYPERR                 | not a vType task: return paramErr
        MOVE.L  A1,-(SP)                        | Save A1 (caller may need it)
        LEA.L   (VBLQueueHdr_Flags).w,A1        | A1 = VBL queue header
        JSR     Dequeue(PC)                     | remove from VBL queue
        MOVE.L  (SP)+,A1                        | Restore A1
        RTS                                     | return from VRemove
