| =========================================================================
| DRVR 3 .Sound -- the Sound Driver: square-wave, four-tone and free-form
| synthesizers
| =========================================================================
| ROM offsets +0x36C88..+0x3701F: the 8-byte header of the ROM resource at
| +0x36C88, then the driver, $390 bytes from +0x36C90 (_DRVR_3_.Sound in
| MacSEROM.lst) on; type DRVR, ID 3, name ".Sound", attributes $58
| (resSysHeap, resLocked, resProtected). The same in both SE ROMs.
| InitIOMgr opens it at startup; refNum -4.
|
| The driver (Inside Macintosh II-221..II-236) plays the synthesizer buffer
| of a Write call -- StartSound(synthRec, numBytes, completion) is a Write
| with ioBuffer = synthRec and ioReqCount = numBytes. The first word of the
| buffer selects the synthesizer (Prime: TST.W, then BEQ / BPL):
|   swMode -1  square wave (SWSynthRec): tone triplets count, amplitude,
|              duration (ticks), ended by a zero duration or by
|              ioReqCount. VIA Timer 1 in free-running mode toggles PB7
|              (vSndEnb, the sound enable) at 783360/count Hz; the sound
|              buffer holds the constant amplitude. CurPitch = count.
|              ioActCount counts the bytes of the triplets played.
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
| I/O queue until the task completes it through jIODone.
|
| The sound buffer (SoundBase, 740 bytes; IM II-233, III-21): the video
| hardware fetches one word of it per horizontal line (every 44.93 us,
| 370 words per frame) and sends the high byte -- the even bytes are the
| samples -- to the sound DAC; the low bytes are the disk-speed PWM
| values and are never touched here. $80 is the middle level (silence);
| 0 and $FF are the extremes.
|
| Entry points (Device Manager: A0 = parameter block, A1 = DCE):
|   Open     E_Sound_Open: SoundDCE := the DCE; buffer := $80; Timer 1
|            released; speaker volume from parameter RAM (SPVolCtl).
|   Prime    E_Sound_Prime: Write only (drvrFlags: no Read); starts the
|            synthesizer named by the mode word and returns noErr.
|   Control  E_Sound_Control, csCode in the parameter block:
|              1 (or negative)  KillIO: stop the sound (E_Sound_KillIO)
|              2                set the speaker volume, csParam = 0..7
|              3 and up         amplitude: fill the buffer with the low
|                               byte of csParam (square wave, IM II-234)
|              0                nothing
|            then jIODone with noErr -- for an immediate call too, which
|            completes the Write being played (IM II-234 warns of its
|            completion routine).
|            KillIO returns with RTS, as it must (IM II-194).
|   Status   E_Sound_Status: no status codes; jIODone with noErr.
|   Close    E_Sound_Close: stop the sound, buffer := $80, release Timer 1.
|
| Low-memory globals: SdVolume ($260) speaker volume; SoundPtr ($262) the
| FTSoundRec; SoundBase ($266) the sound buffer; SoundVBL ($26A, 14 bytes)
| the VBL task; SoundDCE ($27A); SoundActive ($27E) nonzero while SoundVBL
| is installed; SoundLevel ($27F) the sample level the buffer is to hold
| when no synthesizer writes it; CurPitch ($280) the square-wave count;
| T1Arbitrate ($B3F) $FF = VIA Timer 1 free, 0 = owned by the Sound
| Driver. DCE fields: dCtlQHead (the request being played), dCtlPosition
| (free-form: fractional source position, 16.16).
|
| Changes against the Mac Plus driver ($368 bytes; this one is $390):
|   - Open, Close and KillIO fill the buffer with $80; the Plus refills it
|     with the level of its first byte.
|   - SoundLevel is kept current: the four-tone and free-form mixers store
|     the last sample they wrote, and when a sound ends the buffer is
|     filled with that level (SND_FILL_FROM_LOWMEM); the Plus again uses
|     the first byte of the buffer, which can click.
|   - Free-form: when a request is done the VBL task completes it through
|     jIODone without filling the buffer and stays installed, so the last
|     frame is played; the next tick it plays the next queued request
|     without a gap, or removes itself when there is none. The Plus
|     removed the task with every request and filled over the last frame
|     at once. A request found finished at the top of the task is
|     completed with the task removed, and the task goes on at once with
|     the next one.
|
| Suspected bugs (no code changes; see the comments there):
|   - P_SoundVBL_task4Tone records -2(A2) as SoundLevel: A2 is tone 1's
|     waveform there, not the buffer pointer (A6) as in the free-form
|     code it was copied from; a byte in front of the waveform becomes
|     the level the buffer holds after the sound.
|   - The free-form task loops back to its start after jIODone has
|     started the next queued request, without checking that request's
|     mode word: a square-wave or four-tone request queued behind a
|     free-form one is resampled as free-form data for a tick and can be
|     completed early. Latent: only a request that is already finished at
|     the top of a tick takes this path (a negative ioReqCount; zero-length
|     Writes never reach Prime), as the end-of-tick check completes the
|     others.
|   - SND_VBL_INSTALL rewrites the whole VBL element, qLink included, also
|     while it is in the VBL queue -- for the next square-wave triplet and
|     for a request that an immediate Control or Status call's jIODone
|     starts (as in the Plus and 64K drivers) and, new in the SE, for any
|     request that the free-form task's end-of-tick jIODone starts: VBL
|     tasks installed after the sound task are cut off the queue (the VBL
|     Manager reads qLink after the task returns; qTail keeps pointing at
|     the cut-off tasks).
|   - The free-form silence fill writes one sample too many (on word 32,
|     or on SoundBase+740; as in the Plus and 64K drivers).
|
| Sources: Inside Macintosh II-221..II-236 (The Sound Driver), II-187..
| II-196 (driver structure, KillIO, IODone), II-350 (VBL tasks), III-21
| (sound hardware); the Mac Plus driver (src/plus/resources/
| res_drvr_sound.s) for the shared code.
| =========================================================================

| -------------------------------------------------------------------------
| ROM resource header: a Memory Manager style block header (tag $C0 and
| the physical size, then a relative-handle field) in front of the
| resource data, as for every ROM resource.
| -------------------------------------------------------------------------
Resource_DRVR_0003_DotSound:
Resource_DRVR_0003_DotSound_Header:
    ROM_RESOURCE DRVR_3                         | 8-byte resource header (include/romrsrc.inc)

| -------------------------------------------------------------------------
| Driver header (IM II-188): flags, delay, event mask, menu, the offsets
| of the five routines and the driver name.
| -------------------------------------------------------------------------
Driver_Sound:
_DRVR_3_.Sound:
        .short  0x4E00                          | drvrFlags: dNeedLock, dStatEnable, dCtlEnable, dWritEnable
        .short  0x0000                          | drvrDelay: no periodic action
        .short  0x0000                          | drvrEMask: no desk accessory events
        .short  0x0000                          | drvrMenu: no menu
        .short  E_Sound_Open-_DRVR_3_.Sound     | drvrOpen ($1A)
        .short  E_Sound_Prime-_DRVR_3_.Sound    | drvrPrime ($DC)
        .short  E_Sound_Control-_DRVR_3_.Sound  | drvrCtl ($BC)
        .short  E_Sound_Status-_DRVR_3_.Sound   | drvrStatus ($D0)
        .short  E_Sound_Close-_DRVR_3_.Sound    | drvrClose ($34)
        .byte   0x06                            | drvrName: length 6
        .ascii  ".Sound"                        | the driver name
        .byte   0x20                            | pad byte to the word boundary

| -------------------------------------------------------------------------
| E_Sound_Open -- Open: remember the DCE, silence the buffer, release
| Timer 1 and set the speaker volume from parameter RAM.
| Entry: A1 = DCE.  Exit: D0 = noErr.
| -------------------------------------------------------------------------
E_Sound_Open:
        MOVE.L  A1,(SoundDCE).W                 | SoundDCE := the driver's DCE
        BSR.B   SND_SILENCE_AND_RELEASE         | buffer := $80, release VIA Timer 1
        MOVE.B  (SPVolCtl).W,D0                 | D0 = PRAM volume byte (low 3 bits = volume)
        BSR.W   SND_SET_VOLUME                  | set the speaker volume (and SdVolume)
        CLR.B   (SoundActive).W                 | SoundVBL is not installed
SND_OPEN_OK:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return to the Device Manager (Open, Close, KillIO)

| -------------------------------------------------------------------------
| E_Sound_KillIO -- Control csCode 1 (KillIO): CurPitch := 0, then as
| Close; returns with RTS, not through jIODone (IM II-194).
| E_Sound_Close -- Close: remove the VBL task, silence the buffer and
| release Timer 1.  Exit: D0 = noErr.
| -------------------------------------------------------------------------
E_Sound_KillIO:
        CLR.W   (CurPitch).W                    | no square-wave pitch any more (IM II-232)
E_Sound_Close:
        BSR.B   SND_REMOVE_VBL                  | stop the synthesizer: remove SoundVBL
        BSR.B   SND_SILENCE_AND_RELEASE         | buffer := $80, release VIA Timer 1
        BRA.B   SND_OPEN_OK                     | -> noErr

| -------------------------------------------------------------------------
| SND_SILENCE_AND_RELEASE -- fill the sound buffer with $80, the middle
| level, then release VIA Timer 1 (SND_RELEASE_T1_ONLY).
| SE: the Plus driver refilled the buffer with the level of its first
| byte instead of $80.
| Called by: E_Sound_Open, E_Sound_Close.  Uses D0, D1, A0.
| -------------------------------------------------------------------------
SND_SILENCE_AND_RELEASE:
        MOVE.B  #0x80,D0                        | level $80: the middle of the DAC range
        BSR.B   SND_FILL_BUF                    | fill the 370 samples (and SoundLevel) with it
| SND_RELEASE_T1_ONLY -- release VIA Timer 1 if the Sound Driver owns it
| (T1Arbitrate = 0): stop the PB7 square-wave output and mark the timer
| free ($FF).  Uses A0.
SND_RELEASE_T1_ONLY:
        MOVEA.L (VIA).W,A0                      | A0 = VIA base
        TST.B   (T1Arbitrate).W                 | Timer 1 owned by the Sound Driver (0)?
        BNE.B   SND_T1_RELEASED                 | no: free or someone else's ->
        ANDI.B  #0x3F,vACR(A0)                  | vACR bits 7-6 := 00: Timer 1 one-shot, PB7 output off
        ST.B    (T1Arbitrate).W                 | T1Arbitrate := $FF: Timer 1 free
SND_T1_RELEASED:
        RTS                                     | return

| -------------------------------------------------------------------------
| SND_REMOVE_VBL -- remove the sound VBL task if it is installed.
| Called by: E_Sound_Close, SND_REMOVE_AND_IODONE, P_SoundVBL_taskFreeForm.
| Uses A0, D0 (_VRemove).
| -------------------------------------------------------------------------
SND_REMOVE_VBL:
        TST.B   (SoundActive).W                 | SoundVBL installed?
        BEQ.B   SND_REMOVE_VBL_NOT_ACTIVE       | no ->
        LEA.L   (SoundVBL_qLink).W,A0           | A0 = SoundVBL, the VBL task
        _VRemove                                | take it out of the VBL queue
        CLR.B   (SoundActive).W                 | no longer installed
SND_REMOVE_VBL_NOT_ACTIVE:
        RTS                                     | return

| -------------------------------------------------------------------------
| SND_FILL_FROM_LOWMEM -- fill the sound buffer with SoundLevel, the last
| level a synthesizer wrote, so that the end of a sound does not click.
| SE: replaces the Plus driver's SND_SILENCE_BUF, which took the level
| from the first byte of the buffer.
| SND_FILL_BUF -- fill the sound buffer with the level D0.B (and store it
| in SoundLevel): the 370 even bytes of the 740-byte buffer, four at a
| time with MOVEP.L; the odd bytes (disk-speed PWM) are not touched.
| Called by: SND_SILENCE_AND_RELEASE, E_Sound_Control (csCode 3), E_Sound_Prime
| (square wave), SND_REMOVE_AND_IODONE, P_SoundVBL_taskFreeForm.
| Uses D0, D1, A0.
| -------------------------------------------------------------------------
SND_FILL_FROM_LOWMEM:
        MOVE.B  (SoundLevel).W,D0               | D0 = level of the last sample written
SND_FILL_BUF:
        MOVE.B  D0,(SoundLevel).W               | SoundLevel := the level the buffer holds
        MOVE.B  D0,D1                           | replicate the level into all four bytes of D0:
        LSL.W   #0x8,D0                         | level into bits 15-8
        MOVE.B  D1,D0                           | D0.W = level:level
        MOVE.W  D0,D1                           | D1.W = level:level
        SWAP.W  D0                              | into the high word
        MOVE.W  D1,D0                           | D0.L = level x 4
        MOVEA.L (SoundBase).W,A0                | A0 = the sound buffer
        MOVEQ.L #0x2D,D1                        | 46 passes of 8 samples (368), then 2 more
SND_FILL_LOOP:
        MOVEP.L D0,0x0(A0)                      | samples at +0, +2, +4, +6
        MOVEP.L D0,0x8(A0)                      | samples at +8, +10, +12, +14
        ADDA.W  #0x10,A0                        | next 8 sample words
        DBF.W   D1,SND_FILL_LOOP                | 46 times
        MOVEP.W D0,0x0(A0)                      | the last 2 samples (words 368, 369)
        RTS                                     | return

| -------------------------------------------------------------------------
| SND_SET_VOLUME -- set the speaker volume: D0 = 0..7 (0 = softest,
| 7 = loudest, IM II-232) into SdVolume and into the sound-volume bits 0-2
| of VIA port A (vBufA), with interrupts masked to level 3 because other
| port A bits change at interrupt time.
| Called by: E_Sound_Open, SND_CTL_VOLUME.  Uses D0, D1.
| -------------------------------------------------------------------------
SND_SET_VOLUME:
        MOVE.W  SR,-(SP)                        | save the interrupt mask
        ORI.W   #0x300,SR                       | mask interrupts up to level 3
        MOVE.B  (VIA_PortA2).L,D1               | D1 = vBufA
        ANDI.W  #0xF8,D1                        | clear the volume bits 0-2
        ANDI.W  #0x7,D0                         | D0 = volume 0..7
        MOVE.B  D0,(SdVolume).W                 | SdVolume := volume
        OR.W    D0,D1                           | merge it into the port A value
        MOVE.B  D1,(VIA_PortA2).L               | vBufA := new value
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
| here (also entered from P_SoundVBL_taskSquareWave for the next one:
| SND_SQWAVE_NEXT, A1 = the triplet).
| -------------------------------------------------------------------------
E_Sound_Prime:
        BCLR    #0x7,(VIA_Base).L               | vBufB bit 7 (vSndEnb) := 0: sound output on
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
        TST.B   (T1Arbitrate).W                 | Timer 1 already ours (0)?
        BEQ.B   SND_CLAIM_T1                    | yes: (re)program it ->
        BCLR    #0x7,(T1Arbitrate).W            | free ($FF)? claim it: clear bit 7
        BEQ.B   SND_T1_READY                    | bit 7 was 0: someone else owns it, leave it ->
        CLR.B   (T1Arbitrate).W                 | T1Arbitrate := 0: owned by the Sound Driver
SND_CLAIM_T1:
        MOVEA.L (VIA).W,A0                      | A0 = VIA base
        ORI.B   #0xC0,vACR(A0)                  | vACR bits 7-6 := 11: Timer 1 free-running, square wave on PB7
        CMP.W   (CurPitch).W,D0                 | same count as the tone playing?
        BEQ.B   SND_T1_READY                    | yes: leave the timer running ->
        MOVE.B  D0,vT1C(A0)                     | low byte of the count into the T1 low latch
        ROR.W   #0x8,D0                         | D0.B = high byte
        MOVE.B  D0,vT1CH(A0)                    | T1 high counter: loads the count and starts the timer
        ROR.W   #0x8,D0                         | D0 = count again
SND_T1_READY:
        MOVE.W  D0,(CurPitch).W                 | CurPitch := count
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
| Note: the element is rewritten in either case, qLink included; while it
| is in the VBL queue that cuts off the tasks queued behind it (see the
| banner).
| Called by: E_Sound_Prime (square wave), SND_INSTALL_VBL_IMM.
| Uses A0, D0, D1 (_VInstall).
| -------------------------------------------------------------------------
SND_VBL_IMMEDIATE:
        MOVEQ.L #0x1,D0                         | after 1 tick
SND_VBL_INSTALL:
        LEA.L   (SoundVBL_qLink).W,A0           | A0 = SoundVBL
        MOVE.L  A0,D1                           | D1 = SoundVBL, for _VInstall
        CLR.L   (A0)+                           | qLink := nil
        MOVE.W  #0x1,(A0)+                      | qType := vType
        MOVE.L  A1,(A0)+                        | vblAddr := the synthesizer routine
        MOVE.W  D0,(A0)+                        | vblCount := ticks until it runs
        CLR.W   (A0)                            | vblPhase := 0
        TST.B   (SoundActive).W                 | already installed?
        BNE.B   SND_VBL_INSTALLED               | yes: the new count and routine apply ->
        ST.B    (SoundActive).W                 | SoundActive := installed
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
| -------------------------------------------------------------------------
P_SoundVBL_taskSquareWave:
        MOVEA.L (SoundDCE).W,A1                 | A1 = the driver's DCE
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
        CLR.W   (CurPitch).W                    | no pitch
| SND_REMOVE_AND_IODONE -- end of a sound: remove the VBL task, let the
| buffer hold SoundLevel, complete the request.
SND_REMOVE_AND_IODONE:
        BSR.W   SND_REMOVE_VBL                  | remove SoundVBL
        BSR.W   SND_FILL_FROM_LOWMEM            | buffer := SoundLevel (no click)
| SND_IODONE_NOERR -- complete the current request with noErr: jIODone
| (which also starts the next queued request, calling Prime).
| Reached from E_Sound_Status, SND_REMOVE_AND_IODONE, SND_FREEFORM_DONE.
SND_IODONE_NOERR:
        MOVEQ.L #0x0,D0                         | result noErr
        MOVEA.L (SoundDCE).W,A1                 | A1 = the driver's DCE, for IODone
        MOVEA.L (JIODone).W,A0                  | A0 = jIODone vector (IODone)
        JMP     (A0)                            | -> IODone; returns to our caller

| -------------------------------------------------------------------------
| SND_4TONE_ENTRY -- Prime, ftMode: A1 -> the sndRec field. SoundPtr :=
| the FTSoundRec; the four-tone task runs from the next tick on.
| -------------------------------------------------------------------------
SND_4TONE_ENTRY:
        MOVE.L  (A1)+,(SoundPtr).W              | SoundPtr := sndRec, the FTSoundRec
        LEA.L   P_SoundVBL_task4Tone(PC),A1     | the four-tone mixer
SND_INSTALL_VBL_IMM:
        BSR.B   SND_VBL_IMMEDIATE               | run A1 from the next tick on
        BRA.B   SND_PRIME_DONE                  | -> noErr

| End of the four-tone sound (duration 0): restore the registers, stop.
SND_4TONE_DONE:
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore the registers saved by the task
        BRA.B   SND_REMOVE_AND_IODONE           | -> remove the task, hold SoundLevel, jIODone

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
| its end, then words 0..184 (the faster loops start at word 70 or 32),
| presumably to stay ahead of the word the hardware is fetching. SE:
| after each pass the last sample is to be kept in SoundLevel (see the
| note there).
| -------------------------------------------------------------------------
P_SoundVBL_task4Tone:
        MOVEM.L D0-D7/A0-A6,-(SP)               | save the registers (restored at SND_SAVE_VOICES/SND_4TONE_DONE)
        MOVEA.L (SoundPtr).W,A6                 | A6 = the FTSoundRec
        TST.W   (A6)                            | duration left?
        BEQ.B   SND_4TONE_DONE                  | 0: the sound is over ->
        MOVE.W  #0x1,(SoundVBL_Count).W         | vblCount := 1: run again next tick
        SUBQ.W  #0x1,(A6)+                      | duration - 1; A6 -> sound1Rate
        MOVEM.L (A6),D2-D7/A0-A5                | rates and phases of tones 1-4, then the four WavePtrs
        MOVEA.L (SoundBase).W,A6                | A6 = the sound buffer
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
        SWAP.W  D0                              | D0.W = waveform index 0..255
        MOVE.B  0x0(A2,D0.W),D1                 | sum := tone 1 sample
        MOVE.L  D5,D0                           | tone 2 phase
        AND.L   D1,D0                           | integer byte only (D0.W: high byte 0)
        SWAP.W  D0                              | D0.W = waveform index
        MOVE.B  0x0(A3,D0.W),D0                 | D0.W = tone 2 sample
        ADD.W   D0,D1                           | sum += tone 2
        MOVE.L  D7,D0                           | tone 3 phase
        AND.L   D1,D0                           | integer byte only
        SWAP.W  D0                              | D0.W = waveform index
        MOVE.B  0x0(A4,D0.W),D0                 | D0.W = tone 3 sample
        ADD.W   D0,D1                           | sum += tone 3
        MOVE.L  A1,D0                           | tone 4 phase
        AND.L   D1,D0                           | integer byte only
        SWAP.W  D0                              | D0.W = waveform index
        MOVE.B  0x0(A5,D0.W),D0                 | D0.W = tone 4 sample
        ADD.W   D0,D1                           | sum += tone 4
        LSR.W   #0x2,D1                         | average of the four tones
        MOVE.B  D1,(A6)                         | sample into the buffer
        ADDQ.W  #0x2,A6                         | next buffer word
        SUBQ.W  #0x1,(SP)                       | samples left in this pass
        BNE.B   SND_MIX_SAMPLE                  | more ->
        MOVE.B  -0x2(A2),(SoundLevel).W         | SE: SoundLevel := ... -2(A2), a byte in front of tone 1's waveform -- meant -2(A6), the last sample (suspected bug)
        MOVEA.L (SoundBase).W,A6                | second pass: from word 0
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
        SWAP.W  D0                              | D0.W = waveform index
        MOVE.B  0x0(A3,D0.W),D0                 | D0.W = tone 2 sample
        MOVE.W  D0,-(SP)                        | (SP) = constant part of the sum
        MOVE.L  D7,D0                           | tone 3 phase
        AND.L   D1,D0                           | integer byte only
        SWAP.W  D0                              | D0.W = waveform index
        MOVE.B  0x0(A4,D0.W),D0                 | D0.W = tone 3 sample
        ADD.W   D0,(SP)                         | (SP) += tone 3
        MOVE.L  A1,D0                           | tone 4 phase
        AND.L   D1,D0                           | integer byte only
        SWAP.W  D0                              | D0.W = waveform index
        MOVE.B  0x0(A5,D0.W),D0                 | D0.W = tone 4 sample
        ADD.W   D0,(SP)                         | (SP) = tone 2 + tone 3 + tone 4
SND_SOLO_LOOP:
        CLR.W   D1                              | sum := 0
        ADD.L   D2,D3                           | tone 1: phase += rate
        MOVE.L  D3,D0                           | tone 1 phase
        AND.L   D1,D0                           | integer byte only
        SWAP.W  D0                              | D0.W = waveform index
        MOVE.B  0x0(A2,D0.W),D1                 | sum := tone 1 sample
        ADD.W   (SP),D1                         | + the constant tones 2-4
        LSR.W   #0x2,D1                         | average of the four tones
        MOVE.B  D1,(A6)                         | sample into the buffer
        ADDQ.W  #0x2,A6                         | next buffer word
        SUBQ.W  #0x1,0x2(SP)                    | samples left in this pass
        BNE.B   SND_SOLO_LOOP                   | more ->
        MOVE.B  -0x2(A2),(SoundLevel).W         | SE: as above, -2(A2) instead of the last sample -2(A6)
        MOVEA.L (SoundBase).W,A6                | second pass: from word 0
        MOVE.W  #0x46,0x2(SP)                   | 70 samples (words 0..69)
        SUBQ.W  #0x1,0x4(SP)                    | passes left
        BNE.B   SND_SOLO_LOOP                   | second pass ->
        ADDQ.W  #0x2,SP                         | drop the constant sum
SND_SAVE_VOICES:
        ADDQ.W  #0x4,SP                         | drop the two loop counters
        MOVEA.L (SoundPtr).W,A6                 | A6 = the FTSoundRec
        ADDQ.W  #0x2,A6                         | skip the duration
        MOVEM.L D2-D7/A0-A1,(A6)                | store the rates and the advanced phases
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore the registers
        RTS                                     | return to the VBL Manager

| -------------------------------------------------------------------------
| SND_FREEFORM_ENTRY -- Prime, ffMode: source position := 0
| (dCtlPosition holds its fraction); the free-form task runs from the
| next tick on.
| -------------------------------------------------------------------------
SND_FREEFORM_ENTRY:
        MOVEA.L (SoundDCE).W,A1                 | A1 = the driver's DCE
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
| SE (not in the Plus driver): with no request left the task removes
| itself and lets the buffer hold SoundLevel; a request that runs out in
| this tick is completed at its end with the task still installed and
| the buffer untouched (SND_FREEFORM_DONE), so its last frame is played.
| A request already finished at the top of a tick is completed with the
| task removed, and the task goes on with the next request in the same
| tick -- without checking that the request jIODone started is a
| free-form one (suspected bug, latent: a square-wave or four-tone
| request queued behind would be resampled as free-form data).
| -------------------------------------------------------------------------
P_SoundVBL_taskFreeForm:
        MOVEA.L (SoundDCE).W,A1                 | A1 = the driver's DCE
        MOVE.L  dCtlQHead(A1),D0                | D0 = the request at the head of the queue
        BNE.B   SND_FREEFORM_CHECK_DONE         | there is one ->
        BSR.W   SND_REMOVE_VBL                  | none left: remove the task
        BSR.W   SND_FILL_FROM_LOWMEM            | and let the buffer hold the last level
        RTS                                     | return to the VBL Manager
SND_FREEFORM_CHECK_DONE:
        MOVEA.L D0,A0                           | A0 = the request
        MOVE.L  ioActCount(A0),D0               | D0 = source bytes used
        CMP.L   ioReqCount(A0),D0               | all of them?
        BLT.B   SND_FREEFORM_RESAMPLE_INIT      | no: play on ->
        BSR.W   SND_REMOVE_AND_IODONE           | yes: remove the task, hold the level, jIODone (starts the next request)
        BRA.B   P_SoundVBL_taskFreeForm         | and look at the next request
SND_FREEFORM_RESAMPLE_INIT:
        MOVE.L  dCtlPosition(A1),D3             | D3.W = fraction of the source position
        MOVE.W  #0x1,(SoundVBL_Count).W         | vblCount := 1: run again next tick
        MOVE.L  A4,-(SP)                        | save A4
        MOVEA.L ioBuffer(A0),A1                 | A1 = the FFSynthRec
        ADDQ.W  #0x2,A1                         | skip the mode word
        MOVE.L  (A1)+,D1                        | D1 = count: source bytes per sample (Fixed)
        MOVEA.L A1,A3                           | A3 = waveBytes
        ADDA.L  ioReqCount(A0),A3               | A3 = waveBytes + ioReqCount: end of the source
        ADDA.L  D0,A1                           | A1 = waveBytes + ioActCount: next source byte
        MOVEA.L (SoundBase).W,A2                | A2 = the sound buffer
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
        SWAP.W  D3                              | D3.W = whole bytes to advance
        ADDA.W  D3,A1                           | advance the source
        ADD.W   D3,D0                           | count them
        CLR.W   D3                              | drop the whole bytes
        SWAP.W  D3                              | D3 = the fraction again
        CMPA.L  A1,A3                           | source used up (A1 >= A3)?
        DBLE.W  D2,SND_RESAMPLE_INNER           | no: next sample while D2 lasts
        ADD.L   D0,ioActCount(A0)               | ioActCount += source bytes used
        TST.W   (SP)+                           | which part was it?
        BEQ.B   SND_FREEFORM_NEXT_BUF           | the first ->
        TST.W   D2                              | second part: buffer complete (D2 = -1)?
        BMI.B   SND_FREEFORM_DONE               | yes ->
| The source ended before the end of the frame: fill the rest of the
| buffer with level 0, wrapping at its end. DBF writes D2 + 1 samples,
| one more than needed (also in the Plus and 64K drivers): the last one
| lands on word 32, the frame's first sample -- or, when the source
| ended with the last sample of the first part (A2 = A4 here), the
| first one lands on SoundBase+740, the byte after the buffer.
SND_FILL_SILENCE:
        MOVEQ.L #0x0,D0                         | level 0
SND_SILENCE_LOOP:
        MOVE.B  D0,(A2)                         | sample := 0
        ADDQ.W  #0x2,A2                         | next buffer word
        CMPA.L  A2,A4                           | at the end of the buffer?
        BGT.B   SND_SILENCE_LOOP_INNER          | no ->
        MOVEA.L (SoundBase).W,A2                | yes: go on at word 0
SND_SILENCE_LOOP_INNER:
        DBF.W   D2,SND_SILENCE_LOOP             | D2 + 1 samples
| The frame is complete: save the position, record the level.
SND_FREEFORM_DONE:
        MOVEA.L (SoundDCE).W,A1                 | A1 = the driver's DCE
        MOVE.L  D3,dCtlPosition(A1)             | keep the fraction for the next tick
        MOVE.B  -0x2(A2),(SoundLevel).W         | SE: SoundLevel := the last sample written
        MOVEA.L (SP)+,A4                        | restore A4
        MOVE.L  ioActCount(A0),D0               | D0 = source bytes used
        CMP.L   ioReqCount(A0),D0               | all of them?
        BLT.B   SND_FREEFORM_OK_EXIT            | no: go on next tick ->
        BSR.W   SND_IODONE_NOERR                | SE: complete it now, the task stays installed
SND_FREEFORM_OK_EXIT:
        RTS                                     | return to the VBL Manager
| End of the first part (words 32..369).
SND_FREEFORM_NEXT_BUF:
        TST.W   D2                              | buffer end reached (D2 = -1)?
        BMI.B   SND_FREEFORM_WRAP               | yes: go on at word 0 ->
        ADDI.W  #0x20,D2                        | no, the source ended: the rest + words 0..31
        BRA.B   SND_FILL_SILENCE                | -> fill them with level 0
| Second part: words 0..31.
SND_FREEFORM_WRAP:
        MOVE.W  #0x1,-(SP)                      | flag 1: second part
        MOVEA.L (SoundBase).W,A2                | A2 = word 0 of the buffer
        MOVEQ.L #0x1F,D2                        | at most 32 samples
        BRA.B   SND_RESAMPLE_OUTER              | -> resample them
    ROM_RESOURCE_END DRVR_3                     | end of the data: pads to even, sets the sizes
