| Vertical Retrace Manager -- _VInstall / _VRemove
|
| Apple source: VerticalRetraceMgr.a (MacSEROM.lst module VBLCORE). The
| VBL interrupt handler itself, which runs the VBL task queue every tick,
| is VBLInt_VIA in hw/interrupts.s; these two traps only maintain the
| queue (VBLQueue).
|
| VBLTask (Inside Macintosh II-350): +0 qLink, +4 qType (vType = 1),
| +6 vblAddr (task routine), +10 vblCount (ticks until the next call,
| 0 = inactive), +12 vblPhase (phase offset against the other tasks).
|
| References: Inside Macintosh Vol II, Ch 11: The Vertical Retrace Manager

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
        RTS                                     | return from VINSTALL_TYPERR

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
        RTS                                     | return from VINSTALL_ENQUEUE

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
        RTS                                     | return from VRemove

