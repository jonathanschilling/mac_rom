| =========================================================================
| DRVR 3 .Sound -- the Sound Driver: square-wave, four-tone and free-form
| synthesizers
| =========================================================================
| ROM offsets $179B8..$17D27: the 8-byte header of the ROM resource at
| $179B8, then the driver, $368 bytes from $179C0 (_DRVR_3_.Sound in
| MacPlusROM.lst) on; type DRVR, ID 3, name ".Sound", attributes $58
| (resSysHeap, resLocked, resProtected). The same in all three Plus ROMs.
| InitIOMgr opens it at startup by name (DT_SOUND_NAME); unit 3, refNum -4.
|
| The driver (Inside Macintosh II-221..II-236) plays the synthesizer buffer
| of a Write call -- StartSound(synthRec, numBytes, completion) is a Write
| with ioBuffer = synthRec and ioReqCount = numBytes. The first word of the
| buffer selects the synthesizer (Prime: TST.W, then BEQ / BPL):
|   swMode -1  square wave (SWSynthRec): tone triplets count, amplitude,
|              duration (ticks), ended by a zero duration or by
|              ioReqCount. VIA Timer 1 in free-running mode inverts PB7
|              (vSndEnb, the sound enable) each time it has counted down
|              the count (VIA clock 783.36 kHz; IM II-225: frequency =
|              783360/count); the sound buffer holds the constant
|              amplitude. CurPitch = count. ioActCount counts the bytes of
|              the triplets played.
|   ftMode  1  four-tone (FTSynthRec): the next long points to an
|              FTSoundRec (kept in SoundPtr): duration (word), then rate
|              (Fixed) and phase (Fixed: byte offset into the waveform)
|              of tones 1-4, then the four WavePtrs (256-byte waveforms).
|              Every tick the VBL task mixes 370 samples, the average of
|              the four tones, and decrements the duration.
|   ffMode  0  free-form (FFSynthRec): count (Fixed: source bytes per
|              sample) and the waveform bytes. Every tick the VBL task
|              resamples the next part of the waveform into the buffer,
|              until ioActCount (source bytes used) reaches ioReqCount.
| A synthesizer runs from the VBL task SoundVBL (vblAddr is set to the
| synthesizer's routine); the request stays at the head of the driver's
| I/O queue until the task completes it through jIODone. (A Write with
| ioReqCount 0 never reaches Prime: the Device Manager completes it.)
|
| The sound buffer (SoundBase, 740 bytes; IM II-233, III-21): the video
| hardware fetches one word of it per horizontal line (every 44.93 us,
| 370 words per frame) and sends the high byte -- the even bytes are the
| samples -- to the sound DAC; the low bytes are the disk-speed PWM
| values and are never touched here. $80 is the middle level, 0 and $FF
| are the extremes; a constant level is silence, a jump between levels
| clicks.
|
| Entry points (Device Manager: A0 = parameter block, A1 = DCE):
|   Open     E_Sound_Open: SoundDCE := the DCE; the buffer holds the level
|            of its first byte; Timer 1 released; speaker volume from
|            parameter RAM (SPVolCtl).
|   Prime    E_Sound_Prime: Write only (drvrFlags: no Read); switches the
|            sound output on (vSndEnb := 0), starts the synthesizer named
|            by the mode word and returns noErr.
|   Control  E_Sound_Control, csCode in the parameter block:
|              1 (or negative)  KillIO: stop the sound (E_Sound_KillIO)
|              2                set the speaker volume, csParam = 0..7
|              3 and up         amplitude: fill the buffer with the low
|                               byte of csParam (square wave, IM II-234)
|              0                nothing
|            then jIODone with noErr -- for an immediate call too, which
|            completes the Write being played (IM II-234 warns of its
|            completion routine).
|            KillIO returns with RTS, as it must (IM II-194); the Device
|            Manager then aborts the queued requests (abortErr).
|   Status   E_Sound_Status: no status codes; jIODone with noErr.
|   Close    E_Sound_Close: stop the sound, let the buffer hold the level
|            of its first byte, release Timer 1.
|
| Low-memory globals: SdVolume ($260) speaker volume; SoundPtr ($262) the
| FTSoundRec; SoundBase ($266) the sound buffer; SoundVBL ($26A, 16 bytes,
| of which the 14-byte VBL element is used) the VBL task; SoundDCE ($27A);
| SoundActive ($27E) nonzero while SoundVBL is installed (_SysBeep flashes
| the menu bar instead of beeping while it is set); SoundLevel ($27F) the
| level of the last fill (IM II-234: "the amplitude placed in the 740-byte
| buffer"; written here, never read); CurPitch ($280) the square-wave
| count; T1Arbitrate ($B3F) $FF = VIA Timer 1 free, 0 = owned by the Sound
| Driver; SPVolCtl ($208) the volume byte of parameter RAM; VIA ($1D4);
| JIODone ($8FC). DCE fields: dCtlQHead (the request being played),
| dCtlPosition (free-form: fraction of the source position).
|
| Changes against the 64K ROM's driver (src/original/drivers/sound.s,
| $2CE bytes; this one is $368):
|   - VIA Timer 1 is shared through T1Arbitrate: a square wave claims it
|     (and leaves it alone when someone else owns it); Close and the end
|     of a square wave release it only if the driver owns it.
|   - KillIO has its own entry, which clears CurPitch first; the 64K
|     driver's KillIO was Close and left CurPitch (IM II-232 tells
|     assembly-language programmers to clear it themselves).
|   - Open, Close, KillIO and the end of a sound let the buffer hold the
|     level of its first byte and leave the sound output on; the 64K
|     driver filled it with $FF and switched the output off (vSndEnb := 1)
|     at Close, KillIO and the end of every sound.
|   - SND_FILL_BUF writes four samples per MOVEP.L (the 64K driver: one
|     MOVE.B per sample). SND_SET_VOLUME returns with MOVE (SP)+,SR and
|     RTS instead of RTE: that trick only works on the 68000 (the 68010
|     and later expect a format word in the frame), and the Plus ROM also
|     runs on a 68020 (see INSTALL_ATRAP).
|   - SND_VBL_INSTALL also clears vblPhase.
|   - Four-tone: a faster loop when tones 2-4 stand still (rates 0).
|   - Free-form: the task checks for an empty queue, and it completes a
|     request at the end of the tick that used up the source (the 64K
|     driver: at the top of the next tick) -- filling the buffer with the
|     level of its first byte at once, so most of the last frame of every
|     free-form sound is never played.
| Changed later in the SE driver ($390 bytes): Open, Close and KillIO fill
| the buffer with $80; the mixers keep SoundLevel at the last sample they
| wrote, and the end of a sound holds that level; the free-form task
| completes a request without the fill and stays installed, so the last
| frame is played and a queued free-form request follows without a gap.
|
| Suspected bugs (no code changes; see the comments there):
|   - SND_VBL_INSTALL rewrites the whole VBL element, qLink included, also
|     while it is in the VBL queue: for every square-wave triplet after
|     the first (from P_SoundVBL_taskSquareWave), and for a request that
|     jIODone starts while the task is installed (after an immediate
|     Control or Status call). The VBL Manager reads qLink after the task
|     returns: the tasks queued behind the sound task are cut off, and the
|     queue's qTail keeps pointing at them (also in the 64K and SE).
|   - The free-form silence fill writes one sample too many: on word 32,
|     the frame's first sample, or on SoundBase+740, the byte after the
|     buffer (also in the 64K and SE).
|   - The free-form task fills over the last frame of a sound (above).
| Timing quirk: the first tone of a square-wave sound lasts D to 2D-1
| ticks instead of D: this ROM's _VInstall phase-aligns vblCount even for
| vblPhase 0 (see SND_VBL_INSTALL).
| Not in this driver: the SE's four-tone SoundLevel slip (-2(A2) for
| -2(A6)) and its free-form loop that skips the mode-word check -- these
| mixers do not touch SoundLevel, and the free-form task returns after it
| has completed a request.
|
| Sources: Inside Macintosh II-221..II-236 (The Sound Driver), II-187..
| II-196 (driver structure, KillIO, IODone), II-350 (VBL tasks), III-21
| (sound hardware); the 64K driver (src/original/drivers/sound.s) and the
| SE driver (src/se/resources/res_drvr_sound.s) for the comparison.
| =========================================================================

| -------------------------------------------------------------------------
| ROM resource header: a Memory Manager style block header (tag $C0 and
| the physical size, then a relative-handle field) in front of the
| resource data, as for every ROM resource.
| -------------------------------------------------------------------------
        .long   0xC0000370                      | ROM resource header: tag $C0, physical size $370 (8 + $368)
        .long   0x00000058                      | relative handle: master pointer at ROM zone + $58

| -------------------------------------------------------------------------
| Driver header (IM II-188): flags, delay, event mask, menu, the offsets
| of the five routines and the driver name.
| -------------------------------------------------------------------------
_DRVR_3_.Sound:
        .short  0x4E00                          | drvrFlags: dNeedLock, dStatEnable, dCtlEnable, dWritEnable
        .short  0x0000                          | drvrDelay: no periodic action
        .short  0x0000                          | drvrEMask: no desk accessory events
        .short  0x0000                          | drvrMenu: no menu
        .short  E_Sound_Open-_DRVR_3_.Sound     | drvrOpen ($1A)
        .short  E_Sound_Prime-_DRVR_3_.Sound    | drvrPrime ($DA)
        .short  E_Sound_Control-_DRVR_3_.Sound  | drvrCtl ($BA)
        .short  E_Sound_Status-_DRVR_3_.Sound   | drvrStatus ($CE)
        .short  E_Sound_Close-_DRVR_3_.Sound    | drvrClose ($34)
        .byte   0x06                            | drvrName: length 6
        .ascii  ".Sound"                        | the driver name
        .byte   0x20                            | pad byte to the word boundary

| -------------------------------------------------------------------------
| E_Sound_Open -- Open: remember the DCE, let the buffer hold the level of
| its first byte, release Timer 1 and set the speaker volume from
| parameter RAM.
| Entry: A1 = DCE.  Exit: D0 = noErr.
| -------------------------------------------------------------------------
E_Sound_Open:
        MOVE.L  A1,(SoundDCE).w                 | SoundDCE := the driver's DCE
        BSR.B   SND_SILENCE_AND_RELEASE         | buffer := level of its first byte, release VIA Timer 1
        MOVE.B  (SPVolCtl).w,D0                 | D0 = PRAM volume byte (low 3 bits = volume)
        BSR.W   SND_SET_VOLUME                  | set the speaker volume (and SdVolume)
        CLR.B   (SoundActive).w                 | SoundVBL is not installed
SND_OPEN_OK:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return to the Device Manager (Open, Close, KillIO)

| -------------------------------------------------------------------------
| E_Sound_KillIO -- Control csCode 1 (KillIO): CurPitch := 0, then as
| Close; returns with RTS, not through jIODone (IM II-194). New in the
| Plus: the 64K driver's KillIO was Close and left CurPitch.
| E_Sound_Close -- Close: remove the VBL task, let the buffer hold the
| level of its first byte and release Timer 1.  Exit: D0 = noErr.
| -------------------------------------------------------------------------
E_Sound_KillIO:
        CLR.W   (CurPitch).w                    | no square-wave pitch any more (IM II-232)
E_Sound_Close:
        BSR.B   SND_REMOVE_VBL                  | stop the synthesizer: remove SoundVBL
        BSR.B   SND_SILENCE_AND_RELEASE         | buffer := level of its first byte, release VIA Timer 1
        BRA.B   SND_OPEN_OK                     | -> noErr

| -------------------------------------------------------------------------
| SND_SILENCE_AND_RELEASE -- let the sound buffer hold the level of its
| first byte (SND_SILENCE_BUF), then release VIA Timer 1
| (SND_RELEASE_T1_ONLY). The 64K driver filled the buffer with $FF here,
| the SE fills it with $80.
| Called by: E_Sound_Open, E_Sound_Close.  Uses D0, D1, A0.
| -------------------------------------------------------------------------
SND_SILENCE_AND_RELEASE:
        BSR.B   SND_SILENCE_BUF                 | fill the 370 samples with the level of the first one
| SND_RELEASE_T1_ONLY -- release VIA Timer 1 if the Sound Driver owns it
| (T1Arbitrate = 0): stop the PB7 square-wave output and mark the timer
| free ($FF).
| Called by: SND_SQWAVE_FINISH (and SND_SILENCE_AND_RELEASE).  Uses A0.
SND_RELEASE_T1_ONLY:
        MOVEA.L (VIA).w,A0                      | A0 = VIA base
        TST.B   (T1Arbitrate).w                 | Timer 1 owned by the Sound Driver (0)?
        BNE.B   SND_T1_RELEASED                 | no: free or someone else's ->
        ANDI.B  #0x3F,vACR(A0)                  | vACR bits 7-6 := 00: Timer 1 one-shot, PB7 output off
        ST.B    (T1Arbitrate).w                 | T1Arbitrate := $FF: Timer 1 free
SND_T1_RELEASED:
        RTS                                     | return

| -------------------------------------------------------------------------
| SND_REMOVE_VBL -- remove the sound VBL task if it is installed.
| Called by: E_Sound_Close, SND_REMOVE_AND_IODONE.  Uses A0, D0 (_VRemove).
| -------------------------------------------------------------------------
SND_REMOVE_VBL:
        TST.B   (SoundActive).w                 | SoundVBL installed?
        BEQ.B   SND_REMOVE_VBL_NOT_ACTIVE       | no ->
        LEA.L   (SoundVBL_qLink).w,A0           | A0 = SoundVBL, the VBL task
        _VRemove                                | take it out of the VBL queue
        CLR.B   (SoundActive).w                 | no longer installed
SND_REMOVE_VBL_NOT_ACTIVE:
        RTS                                     | return

| -------------------------------------------------------------------------
| SND_SILENCE_BUF -- let the sound buffer hold one level, that of its
| first byte (sample word 0), so that the sound stops without a jump.
| Word 0 is not the last sample a synthesizer wrote, though (four-tone:
| the first of the second pass; free-form: the first of the words 0..31
| or a 0 of the silence fill), so the end can still click. The SE
| replaced it with SND_FILL_FROM_LOWMEM (the level in SoundLevel, which
| its mixers keep at the last sample).
| SND_FILL_BUF -- fill the sound buffer with the level D0.B (and store it
| in SoundLevel, IM II-234): the 370 even bytes of the 740-byte buffer,
| four at a time with MOVEP.L; the odd bytes (disk-speed PWM) are not
| touched.
| Called by: SND_SILENCE_AND_RELEASE, SND_REMOVE_AND_IODONE (SND_SILENCE_BUF);
| E_Sound_Control (csCode 3), E_Sound_Prime (square wave) (SND_FILL_BUF).
| Uses D0, D1, A0.
| -------------------------------------------------------------------------
SND_SILENCE_BUF:
        MOVEA.L (SoundBase).w,A0                | A0 = the sound buffer
        MOVE.B  (A0),D0                         | D0 = level of sample word 0
SND_FILL_BUF:
        MOVE.B  D0,(SoundLevel).w               | SoundLevel := the level the buffer holds
        MOVE.B  D0,D1                           | replicate the level into all four bytes of D0:
        LSL.W   #0x8,D0                         | level into bits 15-8
        MOVE.B  D1,D0                           | D0.W = level:level
        MOVE.W  D0,D1                           | D1.W = level:level
        SWAP    D0                              | into the high word
        MOVE.W  D1,D0                           | D0.L = level x 4
        MOVEA.L (SoundBase).w,A0                | A0 = the sound buffer
        MOVEQ.L #0x2D,D1                        | 46 passes of 8 samples (368), then 2 more
SND_FILL_LOOP:
        MOVEP.L D0,0x0(A0)                      | samples at +0, +2, +4, +6
        MOVEP.L D0,0x8(A0)                      | samples at +8, +10, +12, +14
        ADDA.W  #0x10,A0                        | next 8 sample words
        DBF     D1,SND_FILL_LOOP                | 46 times
        MOVEP.W D0,0x0(A0)                      | the last 2 samples (words 368, 369)
        RTS                                     | return

| -------------------------------------------------------------------------
| SND_SET_VOLUME -- set the speaker volume: D0 = 0..7 (0 = silent,
| 7 = loudest, IM II-232) into SdVolume and into the sound-volume bits 0-2
| of VIA port A (vBufA), with interrupts masked to level 3 because other
| port A bits change at interrupt time. (The 64K driver returned with
| RTE; see the banner.)
| Called by: E_Sound_Open, SND_CTL_VOLUME.  Uses D0, D1.
| -------------------------------------------------------------------------
SND_SET_VOLUME:
        MOVE.W  SR,-(SP)                        | save the interrupt mask
        ORI.W   #0x300,SR                       | mask interrupts up to level 3
        MOVE.B  (VIA_PortA2).l,D1               | D1 = vBufA
        ANDI.W  #0xF8,D1                        | clear the volume bits 0-2
        ANDI.W  #0x7,D0                         | D0 = volume 0..7
        MOVE.B  D0,(SdVolume).w                 | SdVolume := volume
        OR.W    D0,D1                           | merge it into the port A value
        MOVE.B  D1,(VIA_PortA2).l               | vBufA := new value
        MOVE.W  (SP)+,SR                        | restore the interrupt mask
        RTS                                     | return

| -------------------------------------------------------------------------
| E_Sound_Control -- Control. Entry: A0 = parameter block, A1 = DCE.
| csCode 0 -> noErr; 1 or negative -> KillIO; 2 -> volume; 3 and up ->
| amplitude (fill the buffer with the low byte of csParam).
| -------------------------------------------------------------------------
E_Sound_Control:
        MOVE.W  csCode(A0),D0                   | D0 = csCode
        BEQ.B   E_Sound_Status                  | 0: nothing to do ->
        SUBQ.W  #0x2,D0                         | csCode - 2
        BEQ.B   SND_CTL_VOLUME                  | 2: set the speaker volume ->
        BLT.W   E_Sound_KillIO                  | 1 (killCode) or negative: stop the sound ->
        MOVE.W  csParam(A0),D0                  | 3 and up: D0.B = new amplitude (low byte of csParam)
        BSR.B   SND_FILL_BUF                    | fill the buffer with it: changes a square wave's amplitude
| E_Sound_Status -- Status (and the end of Control): noErr through
| jIODone; for an immediate Control call this completes the Write that is
| playing (IM II-234).
E_Sound_Status:
        BRA.W   SND_IODONE_NOERR                | -> jIODone with noErr

| csCode 2: speaker volume := csParam (0..7).
SND_CTL_VOLUME:
        MOVE.W  csParam(A0),D0                  | D0 = new volume
        BSR.B   SND_SET_VOLUME                  | set SdVolume and VIA port A bits 0-2
        BRA.B   E_Sound_Status                  | -> noErr

| -------------------------------------------------------------------------
| E_Sound_Prime -- Write (StartSound). Entry: A0 = parameter block, A1 =
| DCE. Enables the sound output, then starts the synthesizer that the
| first word of the buffer (ioBuffer) names; returns noErr at once (the
| VBL task completes the request). Square wave: plays the first triplet
| here, without a look at ioReqCount (also entered from
| P_SoundVBL_taskSquareWave for the next one: SND_SQWAVE_NEXT, A1 = the
| triplet). New in the Plus: Timer 1 is claimed through T1Arbitrate.
| -------------------------------------------------------------------------
E_Sound_Prime:
        BCLR    #0x7,(VIA_Base).l               | vBufB bit 7 (vSndEnb) := 0: sound output on
        MOVEA.L ioBuffer(A0),A1                 | A1 = the synthesizer buffer
        TST.W   (A1)+                           | mode word: ffMode 0, ftMode 1, swMode -1
        BEQ.W   SND_FREEFORM_ENTRY              | 0: free-form synthesizer ->
        BPL.W   SND_4TONE_ENTRY                 | 1: four-tone synthesizer ->
| swMode: A1 -> the next tone triplet.
SND_SQWAVE_NEXT:
        MOVEM.W (A1)+,D0-D2                     | D0 = count (pitch), D1 = amplitude, D2 = duration (ticks)
        TST.W   D2                              | duration 0: the end of the triplets?
        BEQ.W   SND_SQWAVE_FINISH               | yes: stop and complete the request ->
        MOVE.L  A0,-(SP)                        | save the parameter block
        TST.B   (T1Arbitrate).w                 | Timer 1 already ours (0)?
        BEQ.B   SND_CLAIM_T1                    | yes: (re)program it ->
        BCLR    #0x7,(T1Arbitrate).w            | free ($FF)? claim it: clear bit 7
        BEQ.B   SND_T1_READY                    | bit 7 was 0: someone else owns it, leave it ->
        CLR.B   (T1Arbitrate).w                 | T1Arbitrate := 0: owned by the Sound Driver
SND_CLAIM_T1:
        MOVEA.L (VIA).w,A0                      | A0 = VIA base
        ORI.B   #0xC0,vACR(A0)                  | vACR bits 7-6 := 11: Timer 1 free-running, square wave on PB7
        CMP.W   (CurPitch).w,D0                 | same count as the tone playing?
        BEQ.B   SND_T1_READY                    | yes: leave the timer running ->
        MOVE.B  D0,vT1C(A0)                     | low byte of the count into the T1 low latch
        ROR.W   #0x8,D0                         | D0.B = high byte
        MOVE.B  D0,vT1CH(A0)                    | T1 high counter: loads the count and starts the timer
        ROR.W   #0x8,D0                         | D0 = count again
SND_T1_READY:
        MOVE.W  D0,(CurPitch).w                 | CurPitch := count
        MOVE.W  D1,D0                           | D0.B = amplitude
        BSR.W   SND_FILL_BUF                    | the buffer holds the amplitude level
        MOVE.W  D2,D0                           | D0 = duration in ticks
        LEA.L   P_SoundVBL_taskSquareWave(PC),A1 | the task that starts the next triplet
        BSR.B   SND_VBL_INSTALL                 | run it after D0 ticks
        MOVEA.L (SP)+,A0                        | A0 = the parameter block
        ADDQ.L  #0x6,ioActCount(A0)             | ioActCount += 6: one triplet played
SND_PRIME_DONE:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return; the request stays queued

| -------------------------------------------------------------------------
| SND_VBL_IMMEDIATE -- set up SoundVBL to run the routine A1 next tick.
| SND_VBL_INSTALL -- set up SoundVBL to run the routine A1 after D0
| ticks, and install it unless it is installed already (SoundActive).
| Notes: the element is rewritten in either case, qLink included; while
| it is in the VBL queue that cuts off the tasks queued behind it (see
| the banner). And this ROM's _VInstall phase-aligns vblCount even for
| vblPhase 0 (the 64K and SE versions skip phase 0): it adds (-Ticks mod
| D) to vblCount = D, so a sound's first square-wave tone lasts D to
| 2D-1 ticks; the next ones, rewritten while installed, last D.
| Called by: E_Sound_Prime (square wave), SND_INSTALL_VBL_IMM.
| Uses A0, D0, D1 (_VInstall: also D2 and A1).
| -------------------------------------------------------------------------
SND_VBL_IMMEDIATE:
        MOVEQ.L #0x1,D0                         | after 1 tick
SND_VBL_INSTALL:
        LEA.L   (SoundVBL_qLink).w,A0           | A0 = SoundVBL
        MOVE.L  A0,D1                           | D1 = SoundVBL, for _VInstall
        CLR.L   (A0)+                           | qLink := nil (also while queued: see above)
        MOVE.W  #0x1,(A0)+                      | qType := vType
        MOVE.L  A1,(A0)+                        | vblAddr := the synthesizer routine
        MOVE.W  D0,(A0)+                        | vblCount := ticks until it runs
        CLR.W   (A0)                            | vblPhase := 0 (new in the Plus)
        TST.B   (SoundActive).w                 | already installed?
        BNE.B   SND_VBL_INSTALLED               | yes: the new count and routine apply ->
        ST.B    (SoundActive).w                 | SoundActive := installed
        MOVEA.L D1,A0                           | A0 = SoundVBL
        _VInstall                               | install it in the VBL queue
SND_VBL_INSTALLED:
        RTS                                     | return

| -------------------------------------------------------------------------
| P_SoundVBL_taskSquareWave -- VBL task (vblAddr) of the square-wave
| synthesizer: the current tone's duration is over; play the next triplet
| if the buffer has one, else stop and complete the request.
| ioActCount = bytes of triplets played, so the next triplet is at
| ioBuffer + 2 + ioActCount.
| dCtlQHead is not tested for nil (in no version): after an immediate
| Control call has completed the Write through jIODone (IM II-234), the
| queue can be empty when the tone ends; the request fields are then
| read from the exception vectors at $20..$2B, and with the ROM's vectors
| (the Line 1010 handler above the trace handler) the comparison ends
| the sound.
| -------------------------------------------------------------------------
P_SoundVBL_taskSquareWave:
        MOVEA.L (SoundDCE).w,A1                 | A1 = the driver's DCE
        MOVEA.L dCtlQHead(A1),A0                | A0 = the request being played
        MOVE.L  ioActCount(A0),D0               | D0 = triplet bytes played
        MOVEA.L ioBuffer(A0),A1                 | A1 = the SWSynthRec
        ADDA.L  D0,A1                           | + bytes played
        ADDQ.L  #0x2,A1                         | + the mode word: A1 -> next triplet
        ADDQ.W  #0x4,D0                         | ioActCount + 4 still below ioReqCount:
        CMP.L   ioReqCount(A0),D0               | another triplet in the buffer?
        BLT.W   SND_SQWAVE_NEXT                 | yes: play it ->
| End of the square wave (zero duration or end of the buffer).
SND_SQWAVE_FINISH:
        BSR.W   SND_RELEASE_T1_ONLY             | stop the PB7 square wave, release Timer 1
        CLR.W   (CurPitch).w                    | no pitch
| SND_REMOVE_AND_IODONE -- end of a sound: remove the VBL task, let the
| buffer hold the level of its first byte (SE: SoundLevel), complete the
| request.
| Called by: SND_CHECK_ACTIVE_IO; reached from SND_SQWAVE_FINISH and
| SND_4TONE_DONE.
SND_REMOVE_AND_IODONE:
        BSR.W   SND_REMOVE_VBL                  | remove SoundVBL
        BSR.W   SND_SILENCE_BUF                 | buffer := level of its first byte
| SND_IODONE_NOERR -- complete the current request with noErr: jIODone
| (which also starts the next queued request, calling Prime).
| Reached from E_Sound_Status, SND_REMOVE_AND_IODONE.
SND_IODONE_NOERR:
        MOVEQ.L #0x0,D0                         | result noErr
        MOVEA.L (SoundDCE).w,A1                 | A1 = the driver's DCE, for IODone
        MOVEA.L (JIODone).w,A0                  | A0 = jIODone vector (IODone)
        JMP     (A0)                            | -> IODone; returns to our caller

| -------------------------------------------------------------------------
| SND_4TONE_ENTRY -- Prime, ftMode: A1 -> the sndRec field. SoundPtr :=
| the FTSoundRec; the four-tone task runs from the next tick on.
| -------------------------------------------------------------------------
SND_4TONE_ENTRY:
        MOVE.L  (A1)+,(SoundPtr).w              | SoundPtr := sndRec, the FTSoundRec
        LEA.L   P_SoundVBL_task4Tone(PC),A1     | the four-tone mixer
SND_INSTALL_VBL_IMM:
        BSR.B   SND_VBL_IMMEDIATE               | run A1 from the next tick on
        BRA.B   SND_PRIME_DONE                  | -> noErr

| End of the four-tone sound (duration 0): restore the registers, stop.
SND_4TONE_DONE:
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore the registers saved by the task
        BRA.B   SND_REMOVE_AND_IODONE           | -> remove the task, hold the first byte's level, jIODone

| -------------------------------------------------------------------------
| P_SoundVBL_task4Tone -- VBL task of the four-tone synthesizer: while
| the FTSoundRec's duration is not 0, decrement it and mix the 370
| samples of the next frame. Each tone: phase += rate (16.16), sample =
| wave[integer part of the phase AND $FF]; the buffer gets the average
| of the four tones. Registers in the mixer: D2/D3 rate and phase of
| tone 1, D4/D5 tone 2, D6/D7 tone 3, A0/A1 tone 4, A2..A5 the four
| waveforms, A6 the buffer pointer, D1 = $00FF0000 (index mask in the
| high word, sum in the low word).
| The samples are written from the middle of the buffer (word 185) to
| its end, then words 0..184 (the loop for tone 1 alone starts at word
| 70), presumably to stay ahead of the word the hardware is fetching.
| New in the Plus: that faster loop (the 64K driver always mixed all four
| tones). The mixer does not touch SoundLevel (the SE's records the last
| sample there, from the wrong register).
| -------------------------------------------------------------------------
P_SoundVBL_task4Tone:
        MOVEM.L D0-D7/A0-A6,-(SP)               | save the registers (restored at SND_SAVE_VOICES/SND_4TONE_DONE)
        MOVEA.L (SoundPtr).w,A6                 | A6 = the FTSoundRec
        TST.W   (A6)                            | duration left?
        BEQ.B   SND_4TONE_DONE                  | 0: the sound is over ->
        MOVE.W  #0x1,(SoundVBL_Count).w         | vblCount := 1: run again next tick
        SUBQ.W  #0x1,(A6)+                      | duration - 1; A6 -> sound1Rate
        MOVEM.L (A6),D2-D7/A0-A5                | rates and phases of tones 1-4, then the four WavePtrs
        MOVEA.L (SoundBase).w,A6                | A6 = the sound buffer
        MOVE.L  #0xFF0000,D1                    | D1 = mask of the phase's integer byte (bits 16-23)
        MOVE.L  A0,D0                           | tone 4 rate
        BNE.B   SND_4TONE_MIX_START             | not 0: mix all four ->
        MOVE.L  D6,D0                           | tone 3 rate
        BNE.B   SND_4TONE_MIX_START             | not 0: mix all four ->
        MOVE.L  D4,D0                           | tone 2 rate
        BEQ.B   SND_SOLO_VOICE1                 | tones 2-4 stand still: only tone 1 changes ->
SND_4TONE_MIX_START:
        ADDA.W  #0x172,A6                       | start at word 185, the middle of the buffer
        MOVE.W  #0x2,-(SP)                      | 2 passes: words 185..369, then 0..184
        MOVE.W  #0xB9,-(SP)                     | 185 samples per pass
SND_MIX_SAMPLE:
        CLR.W   D1                              | sum := 0 (low word of D1)
        ADD.L   D2,D3                           | tone 1: phase += rate
        ADD.L   D4,D5                           | tone 2: phase += rate
        ADD.L   D6,D7                           | tone 3: phase += rate
        ADDA.L  A0,A1                           | tone 4: phase += rate
        MOVE.L  D3,D0                           | tone 1 phase
        AND.L   D1,D0                           | integer byte only
        SWAP    D0                              | D0.W = waveform index 0..255
        MOVE.B  0x0(A2,D0.W),D1                 | sum := tone 1 sample
        MOVE.L  D5,D0                           | tone 2 phase
        AND.L   D1,D0                           | integer byte only (D0.W: high byte 0)
        SWAP    D0                              | D0.W = waveform index
        MOVE.B  0x0(A3,D0.W),D0                 | D0.W = tone 2 sample
        ADD.W   D0,D1                           | sum += tone 2
        MOVE.L  D7,D0                           | tone 3 phase
        AND.L   D1,D0                           | integer byte only
        SWAP    D0                              | D0.W = waveform index
        MOVE.B  0x0(A4,D0.W),D0                 | D0.W = tone 3 sample
        ADD.W   D0,D1                           | sum += tone 3
        MOVE.L  A1,D0                           | tone 4 phase
        AND.L   D1,D0                           | integer byte only
        SWAP    D0                              | D0.W = waveform index
        MOVE.B  0x0(A5,D0.W),D0                 | D0.W = tone 4 sample
        ADD.W   D0,D1                           | sum += tone 4
        LSR.W   #0x2,D1                         | average of the four tones
        MOVE.B  D1,(A6)                         | sample into the buffer
        ADDQ.W  #0x2,A6                         | next buffer word
        SUBQ.W  #0x1,(SP)                       | samples left in this pass
        BNE.B   SND_MIX_SAMPLE                  | more ->
        MOVEA.L (SoundBase).w,A6                | second pass: from word 0 (the SE records SoundLevel first)
        MOVE.W  #0xB9,(SP)                      | 185 samples
        SUBQ.W  #0x1,0x2(SP)                    | passes left
        BNE.B   SND_MIX_SAMPLE                  | second pass ->
        BRA.B   SND_SAVE_VOICES                 | -> store the phases and return

| SND_SOLO_VOICE1 -- the rates of tones 2-4 are 0: their samples are
| constant, so add them up once and mix only tone 1 (faster); starts at
| word 70: 300 samples to the end of the buffer, then words 0..69.
SND_SOLO_VOICE1:
        ADDA.W  #0x8C,A6                        | start at word 70
        MOVE.W  #0x2,-(SP)                      | 2 passes
        MOVE.W  #0x12C,-(SP)                    | 300 samples in the first pass
        MOVE.L  D5,D0                           | tone 2 phase
        AND.L   D1,D0                           | integer byte only
        SWAP    D0                              | D0.W = waveform index
        MOVE.B  0x0(A3,D0.W),D0                 | D0.W = tone 2 sample
        MOVE.W  D0,-(SP)                        | (SP) = constant part of the sum
        MOVE.L  D7,D0                           | tone 3 phase
        AND.L   D1,D0                           | integer byte only
        SWAP    D0                              | D0.W = waveform index
        MOVE.B  0x0(A4,D0.W),D0                 | D0.W = tone 3 sample
        ADD.W   D0,(SP)                         | (SP) += tone 3
        MOVE.L  A1,D0                           | tone 4 phase
        AND.L   D1,D0                           | integer byte only
        SWAP    D0                              | D0.W = waveform index
        MOVE.B  0x0(A5,D0.W),D0                 | D0.W = tone 4 sample
        ADD.W   D0,(SP)                         | (SP) = tone 2 + tone 3 + tone 4
SND_SOLO_LOOP:
        CLR.W   D1                              | sum := 0
        ADD.L   D2,D3                           | tone 1: phase += rate
        MOVE.L  D3,D0                           | tone 1 phase
        AND.L   D1,D0                           | integer byte only
        SWAP    D0                              | D0.W = waveform index
        MOVE.B  0x0(A2,D0.W),D1                 | sum := tone 1 sample
        ADD.W   (SP),D1                         | + the constant tones 2-4
        LSR.W   #0x2,D1                         | average of the four tones
        MOVE.B  D1,(A6)                         | sample into the buffer
        ADDQ.W  #0x2,A6                         | next buffer word
        SUBQ.W  #0x1,0x2(SP)                    | samples left in this pass
        BNE.B   SND_SOLO_LOOP                   | more ->
        MOVEA.L (SoundBase).w,A6                | second pass: from word 0
        MOVE.W  #0x46,0x2(SP)                   | 70 samples (words 0..69)
        SUBQ.W  #0x1,0x4(SP)                    | passes left
        BNE.B   SND_SOLO_LOOP                   | second pass ->
        ADDQ.W  #0x2,SP                         | drop the constant sum
SND_SAVE_VOICES:
        ADDQ.W  #0x4,SP                         | drop the two loop counters
        MOVEA.L (SoundPtr).w,A6                 | A6 = the FTSoundRec
        ADDQ.W  #0x2,A6                         | skip the duration
        MOVEM.L D2-D7/A0-A1,(A6)                | store the rates and the advanced phases
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore the registers
SND_VBL_RTS:
        RTS                                     | return to the VBL Manager (also the free-form task's exit)

| -------------------------------------------------------------------------
| SND_FREEFORM_ENTRY -- Prime, ffMode: source position := 0
| (dCtlPosition holds its fraction); the free-form task runs from the
| next tick on.
| -------------------------------------------------------------------------
SND_FREEFORM_ENTRY:
        MOVEA.L (SoundDCE).w,A1                 | A1 = the driver's DCE
        CLR.L   dCtlPosition(A1)                | fraction of the source position := 0
        LEA.L   P_SoundVBL_taskFreeForm(PC),A1  | the free-form resampler
        BRA.W   SND_INSTALL_VBL_IMM             | run it from the next tick on; noErr

| -------------------------------------------------------------------------
| P_SoundVBL_taskFreeForm -- VBL task of the free-form synthesizer:
| resample the next 370 samples of the request at the head of the queue
| into the buffer, advancing the source by count (16.16) bytes per
| sample; ioActCount = source bytes used, the request is done when it
| reaches ioReqCount (the driver plays ioReqCount waveform bytes, IM
| II-232). The buffer is filled from word 32 to its end, then words
| 0..31; a source that ends early is followed by level 0.
| The request is checked (SND_CHECK_ACTIVE_IO) at the top of the tick --
| none: return; finished: complete it and return -- and again at the end
| of the tick, so it is completed in the tick that used up its source,
| through SND_REMOVE_AND_IODONE: the task is removed and the buffer is
| filled with the level of its first byte right away, which wipes out
| most of the frame just written before the hardware plays it. New in
| the Plus: the 64K driver tested only at the top of the next tick (and
| not for an empty queue); the SE completes the request without the fill
| and keeps the task installed.
| -------------------------------------------------------------------------
P_SoundVBL_taskFreeForm:
        BSR.B   SND_CHECK_ACTIVE_IO             | A1 = DCE; NE: A0 = the request, D0 = ioActCount
        BEQ.B   SND_VBL_RTS                     | none, or just completed: return to the VBL Manager
        MOVE.L  dCtlPosition(A1),D3             | D3.W = fraction of the source position
        MOVE.W  #0x1,(SoundVBL_Count).w         | vblCount := 1: run again next tick
        MOVE.L  A4,-(SP)                        | save A4 (the VBL interrupt saves only D0-D3/A0-A3)
        MOVEA.L ioBuffer(A0),A1                 | A1 = the FFSynthRec
        ADDQ.W  #0x2,A1                         | skip the mode word
        MOVE.L  (A1)+,D1                        | D1 = count: source bytes per sample (Fixed)
        MOVEA.L A1,A3                           | A3 = waveBytes
        ADDA.L  ioReqCount(A0),A3               | A3 = waveBytes + ioReqCount: end of the source
        ADDA.L  D0,A1                           | A1 = waveBytes + ioActCount: next source byte
        MOVEA.L (SoundBase).w,A2                | A2 = the sound buffer
        ADDA.W  #0x40,A2                        | start at word 32
        LEA.L   0x2A4(A2),A4                    | A4 = SoundBase + 740: end of the buffer
        CLR.W   -(SP)                           | flag 0: first part, words 32..369
        MOVE.W  #0x151,D2                       | at most 338 samples (DBLE count 337)
SND_RESAMPLE_OUTER:
        MOVEQ.L #0x0,D0                         | D0 = source bytes used in this part
SND_RESAMPLE_INNER:
        MOVE.B  (A1),(A2)                       | sample := the current source byte
        ADDQ.W  #0x2,A2                         | next buffer word
        ADD.L   D1,D3                           | position += count (16.16)
        SWAP    D3                              | D3.W = whole bytes to advance
        ADDA.W  D3,A1                           | advance the source
        ADD.W   D3,D0                           | count them
        CLR.W   D3                              | drop the whole bytes
        SWAP    D3                              | D3 = the fraction again
        CMPA.L  A1,A3                           | source used up (A1 >= A3)?
        DBLE    D2,SND_RESAMPLE_INNER           | no: next sample while D2 lasts
        ADD.L   D0,ioActCount(A0)               | ioActCount += source bytes used
        TST.W   (SP)+                           | which part was it?
        BEQ.B   SND_FREEFORM_NEXT_BUF           | the first ->
        TST.W   D2                              | second part: buffer complete (D2 = -1)?
        BMI.B   SND_FREEFORM_DONE               | yes ->
| The source ended before the end of the frame: fill the rest of the
| buffer with level 0, wrapping at its end. DBF writes D2 + 1 samples,
| one more than needed (suspected bug, also in the 64K and SE drivers):
| the last one lands on word 32, the frame's first sample -- or, when the
| source ended with the last sample of the first part (A2 = A4 here),
| the first one lands on SoundBase+740, the byte after the buffer.
SND_FILL_SILENCE:
        MOVEQ.L #0x0,D0                         | level 0
SND_SILENCE_LOOP:
        MOVE.B  D0,(A2)                         | sample := 0
        ADDQ.W  #0x2,A2                         | next buffer word
        CMPA.L  A2,A4                           | at the end of the buffer?
        BGT.B   SND_SILENCE_LOOP_INNER          | no ->
        MOVEA.L (SoundBase).w,A2                | yes: go on at word 0
SND_SILENCE_LOOP_INNER:
        DBF     D2,SND_SILENCE_LOOP             | D2 + 1 samples
| The frame is complete: save the position, then check the request.
SND_FREEFORM_DONE:
        MOVEA.L (SoundDCE).w,A1                 | A1 = the driver's DCE
        MOVE.L  D3,dCtlPosition(A1)             | keep the fraction for the next tick
        MOVEA.L (SP)+,A4                        | restore A4
| SND_CHECK_ACTIVE_IO -- look at the free-form request at the head of
| the queue: none -> EQ; source used up (ioActCount >= ioReqCount) ->
| complete it (SND_REMOVE_AND_IODONE: remove the task, fill the buffer
| with the level of its first byte, jIODone, which starts the next
| request) -> EQ; else NE, with A0 = the request, D0 = ioActCount and
| A1 = the DCE.
| Called by: P_SoundVBL_taskFreeForm (top of the tick); reached at the
| end of the tick from SND_FREEFORM_DONE (its RTS then returns to the
| VBL Manager).
SND_CHECK_ACTIVE_IO:
        MOVEA.L (SoundDCE).w,A1                 | A1 = the driver's DCE
        MOVE.L  dCtlQHead(A1),D0                | D0 = the request at the head of the queue
        BEQ.B   SND_FF_INACTIVE                 | none (new in the Plus) ->
        MOVEA.L D0,A0                           | A0 = the request
        MOVE.L  ioActCount(A0),D0               | D0 = source bytes used
        CMP.L   ioReqCount(A0),D0               | all of them?
        BLT.B   SND_FF_CHECK_RTS                | no: return NE (from the CMP) ->
        BSR.W   SND_REMOVE_AND_IODONE           | yes: remove the task, fill the buffer, jIODone
SND_FF_INACTIVE:
        MOVEQ.L #0x0,D0                         | EQ: nothing to play
SND_FF_CHECK_RTS:
        RTS                                     | return
| End of the first part (words 32..369).
SND_FREEFORM_NEXT_BUF:
        TST.W   D2                              | buffer end reached (D2 = -1)?
        BMI.B   SND_FREEFORM_WRAP               | yes: go on at word 0 ->
        ADDI.W  #0x20,D2                        | no, the source ended: the rest + words 0..31
        BRA.B   SND_FILL_SILENCE                | -> fill them with level 0
| Second part: words 0..31.
SND_FREEFORM_WRAP:
        MOVE.W  #0x1,-(SP)                      | flag 1: second part
        MOVEA.L (SoundBase).w,A2                | A2 = word 0 of the buffer
        MOVEQ.L #0x1F,D2                        | at most 32 samples
        BRA.B   SND_RESAMPLE_OUTER              | -> resample them

| end of resource : 'DRVR' 3 '.Sound'

