| Vertical Retrace Manager -- _VInstall / _VRemove
|
| Apple source: VerticalRetraceMgr.a (MacSEROM.lst module VBLCORE). The
| VBL interrupt handler itself, which runs the VBL task queue every tick,
| is VBLINT in hw/interrupts.s; these two traps only maintain the
| queue (VBLQueue).
|
| VBLTask (Inside Macintosh II-350): +0 qLink, +4 qType (vType = 1),
| +6 vblAddr (task routine), +10 vblCount (ticks until the next call,
| 0 = inactive), +12 vblPhase (phase offset against the other tasks).
|
| References: Inside Macintosh Vol II, Ch 11: The Vertical Retrace Manager
| CORESTUB (an RTS) ends the module.

| VINSTALL - _VInstall trap: install a VBL task
|
| Entry: A0 = VBLTask record pointer
| VBLTask.qType must be 1 (vType). If vblCount and vblPhase are
| both non-zero, computes the phase-aligned first-fire count.
| Returns D0 = 0 (success) or D0 = -2 (bad qType).
| Apple source module: VBLCORE
VINSTALL:
    CMPI.W	#0x1,0x4(A0)                         | qType == vType (1)?
    BEQ.B	VINSTALL_SYNC                         | yes: install task
VINSTALL_TYPERR:
    MOVEQ.L	#-0x2,D0                            | D0 = -2 (qErr: bad queue type)
    RTS                                         | return error
VINSTALL_SYNC:
    MOVE.W	0xA(A0),D1                           | D1 = vblCount (interval)
    BEQ.B	VINSTALL_ENQUEUE                      | zero: install without phase align
    TST.W	0xC(A0)                               | vblPhase set?
    BEQ.B	VINSTALL_ENQUEUE                      | no: install without phase align
| Phase-align first fire: compute (Ticks mod vblCount) offset
    MOVE.W	SR,-(A7)                             | save SR
    ORI.W	#0x100,SR                             | raise IPL to 1 (block VBL)
    MOVE.L	(Ticks).W,D0                         | D0 = current tick count
    SWAP.W	D0                                   | position for 32-bit modulo
    MOVEQ.L	#0x0,D2                             | clear D2 for division
    MOVE.W	D0,D2                                | D2 = high word of Ticks
    DIVU.W	D1,D2                                | D2 = high / interval (rem in high)
    SWAP.W	D2                                   | D2 = remainder
    MOVE.W	D2,D0                                | merge remainder into D0
    SWAP.W	D0                                   | reassemble for low-word divide
    DIVU.W	D1,D0                                | D0 = full Ticks / interval
    SWAP.W	D0                                   | D0 = Ticks mod interval
    SUB.W	0xC(A0),D0                            | subtract vblPhase
    NEG.W	D0                                    | D0 = phase - (Ticks mod interval)
    BPL.B	VINSTALL_PHASE_OK                     | positive: use as first-fire delay
    ADD.W	D1,D0                                 | negative: add interval to wrap
VINSTALL_PHASE_OK:
    ADD.W	D0,0xA(A0)                            | adjust vblCount for phase alignment
    MOVE.W	(A7)+,SR                             | restore SR
VINSTALL_ENQUEUE:
    LEA.L	(VBLQueueHdr_Flags).W,A1              | A1 = VBL queue header
    JSR	ENQUEUE(PC)                             | enqueue VBL task
    MOVEQ.L	#0x0,D0                             | D0 = 0 (noErr)
    RTS                                         | return from VInstall
| VREMOVE - _VRemove trap: remove a VBL task from the queue
|
| Entry: A0 = VBLTask record pointer
| Returns D0 = 0 (success) or D0 = -2 (bad qType)
VREMOVE:
    CMPI.W	#0x1,0x4(A0)                         | qType == vType (1)?
    BNE.B	VINSTALL_TYPERR                       | no: return qErr
    MOVE.L	A1,-(A7)                             | save A1
    LEA.L	(VBLQueueHdr_Flags).W,A1              | A1 = VBL queue header
    JSR	DEQUEUE(PC)                             | remove task from VBL queue
    MOVEA.L	(A7)+,A1                            | restore A1
CORESTUB:
    RTS                                         | return from VRemove
