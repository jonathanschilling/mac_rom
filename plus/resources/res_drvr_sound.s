| DRVR 3 -- .Sound driver
|
| resource : 'DRVR' 3 '.Sound'
|
| Plays back sound via VIA Timer 1 free-run PWM and the sound buffer
| at $6A100. Handles both the four-voice square-wave synthesizer
| (csCode = 2 = SetSndVol-era) and the free-form sample player.
|
| Driver control fields, then Pascal name ".Sound", then the five
| driver entry points (Open/Prime/Ctl/Status/Close).
|
| Installed at boot via _DrvrInstall (classic: via jump table at
| $05FC; Plus: via _Open(".Sound") in InitIOMgr).

| ----------------------------------------------------------
| DRVR 3 - .Sound driver header
| 18 bytes of driver-control fields + Pascal name ".Sound".
| ----------------------------------------------------------
  .short 0x4E00                                 | drvrFlags
  .short 0x0000                                 | drvrDelay
  .short 0x0000                                 | drvrEMask
  .short 0x0000                                 | drvrMenu
  .short 0x001A                                 | drvrOpen
  .short 0x00DA                                 | drvrPrime
  .short 0x00BA                                 | drvrCtl
  .short 0x00CE                                 | drvrStatus
  .short 0x0034                                 | drvrClose
  .byte 0x06                                    | drvrName length

| Name
  .ascii ".Sound"                               | drvrName: sound driver name

| end of Name
  .byte 0x20                                    | align to word

| .Sound Open: initialize sound driver
| VIA Timer 1 generates square-wave sound via Port B bit 7 (vSndEnb)
| Volume controlled by VIA Port A bits 0-2
E_Sound_Open:
        MOVE.L  A1,(SoundDCE).w                 | save DCE pointer
        BSR.B   SND_RELEASE_T1                  | disable VBL sound task + release Timer 1
        MOVE.B  (SPVolCtl).w,D0                 | D0 = saved speaker volume (PRAM)
        BSR     SND_SET_VOLUME                  | set volume via VIA Port A bits 0-2
        CLR.B   (SoundActive).w                 | mark sound inactive
SND_RETURN_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from open/close call

| ----------------------------------------------------------
|
| .Sound Close: stop sound and release Timer 1
|
SND_KILL_SOUND:
        CLR     (CurPitch).w                    | clear current pitch
E_Sound_Close:
        BSR.B   SND_REMOVE_VBL                  | remove VBL sound task
        BSR.B   SND_RELEASE_T1                  | release Timer 1 to system
        BRA.B   SND_RETURN_NOERR                | -> noErr

| ----------------------------------------------------------
|
| SND_RELEASE_T1: release VIA Timer 1 + disable VBL task
| Disables VBL task and sets Timer 1 to free-run mode
|
SND_RELEASE_T1:
        BSR.B   SND_SILENCE_BUF                 | remove VBL sound task if installed
| SND_RELEASE_T1_ONLY -- release Timer 1.
SND_RELEASE_T1_ONLY:
        MOVE.L  (VIA).w,A0                      | A0 = VIA base
        TST.B   (T1Arbitrate).w                 | Timer 1 already free?
        BNE.B   SND_T1_RELEASED                 | yes ->
        ANDI.B  #0x3F,0x1600(A0)                | VIA ACR: clear Timer 1 mode bits (free-run)
        ST.B    (T1Arbitrate).w                 | mark Timer 1 as released
SND_T1_RELEASED:
        RTS                                     | return from Timer 1 release

| ----------------------------------------------------------
|
| SND_REMOVE_VBL: remove VBL sound task if active
|
SND_REMOVE_VBL:
        TST.B   (SoundActive).w                 | sound VBL task running?
        BEQ.B   SND_VBL_REMOVED                 | no ->
        LEA.L   (SoundVBL_qLink).w,A0           | VBL task record
        _VRemove                                | remove from VBL queue
        CLR.B   (SoundActive).w                 | mark inactive
SND_VBL_REMOVED:
        RTS                                     | return from VBL task removal

| ----------------------------------------------------------
|
| SND_SILENCE_BUF: fill buffer with silence (current level)
| Reads first byte of sound buffer, replicates to all 370 words
|
SND_SILENCE_BUF:
        MOVE.L  (SoundBase).w,A0                | A0 = sound buffer base
        MOVE.B  (A0),D0                         | D0 = current sample level
| SND_FILL_BUF: fill entire sound buffer with constant sample value D0
SND_FILL_BUF:
        MOVE.B  D0,(SoundLevel).w               | save current level
| replicate byte D0 into all 4 bytes of D0 (for MOVEP.L fill)
        MOVE.B  D0,D1                           | save copy of sample byte
        LSL     #0x8,D0                         | shift to bits 15-8
        MOVE.B  D1,D0                           | D0.W = D0:D0
        MOVE    D0,D1                           | copy word to D1
        SWAP    D0                              | move word to high half
        MOVE    D1,D0                           | D0.L = D0:D0:D0:D0
| fill 370 words: 46 iterations * 8 bytes + 2 bytes = 370
        MOVE.L  (SoundBase).w,A0                | A0 = sound buffer
        MOVEQ.L #0x2D,D1                        | 45 iterations (46-1)
SND_FILL_LOOP:
        MOVEP.L D0,0x0(A0)                      | write 4 even bytes (8 byte stride)
        MOVEP.L D0,0x8(A0)                      | write 4 more even bytes
        ADDA    #0x10,A0                        | advance 16 bytes
        DBF     D1,SND_FILL_LOOP                | loop until buffer filled
        MOVEP   D0,0x0(A0)                      | write final 2 bytes
        RTS                                     | return from buffer fill

| ----------------------------------------------------------
|
| SND_SET_VOLUME: set speaker volume via VIA Port A bits 0-2
| D0 = volume (0-7, where 0=loudest, 7=softest)
|
SND_SET_VOLUME:
        MOVE    SR,-(SP)                        | save interrupt mask
        ORI     #0x300,SR                       | disable interrupts (IPL 3)
        MOVE.B  (VIA_PortA2).l,D1               | read VIA Port A
        ANDI    #0xF8,D1                        | clear volume bits 0-2
        ANDI    #0x7,D0                         | mask volume to 3 bits
        MOVE.B  D0,(SdVolume).w                 | store in low-memory global
        OR      D0,D1                           | merge volume into Port A
        MOVE.B  D1,(VIA_PortA2).l               | write VIA Port A
        MOVE    (SP)+,SR                        | restore interrupts
        RTS                                     | return from volume set

| ----------------------------------------------------------
|
| E_Sound_Control
|
| .Sound Control: dispatch on csCode
| csCode 0 = status, 1 = killIO, 2 = set volume, 3 = fill buffer
E_Sound_Control:
        MOVE    0x1A(A0),D0                     | D0 = csCode
        BEQ.B   E_Sound_Status                  | csCode 0: status ->
        SUBQ.W  #0x2,D0                         | test for csCode 2 or 3
        BEQ.B   SND_CTL_VOLUME                  | csCode 2: set volume ->
        BLT     SND_KILL_SOUND                  | csCode 1: killIO (stop sound) ->
| csCode 3: fill sound buffer with constant value
        MOVE    0x1C(A0),D0                     | D0 = fill value from csParam
        BSR.B   SND_FILL_BUF                    | fill buffer with constant sample
| .Sound Status: return noErr
E_Sound_Status:
        BRA     SND_IODONE_NOERR                | -> noErr + IODone

| ----------------------------------------------------------
|
| csCode 2: set speaker volume from csParam
|
SND_CTL_VOLUME:
        MOVE    0x1C(A0),D0                     | D0 = new volume (0-7)
        BSR.B   SND_SET_VOLUME                  | set VIA Port A bits 0-2
        BRA.B   E_Sound_Status                  | -> noErr

| ----------------------------------------------------------
|
| .Sound Prime (Read/Write): play sound data
| A0 = IOParam, ioBuffer -> sound command list
| Sound commands: -1=square wave (freq, amp, dur), 0=end, >0=4-tone
|
E_Sound_Prime:
        BCLR    #0x7,(VIA_Base).l               | enable sound (clear vSndEnb in Port B)

        MOVE.L  0x20(A0),A1                     | A1 = ioBuffer (sound command list)
        TST     (A1)+                           | check command type
        BEQ     SND_FREEFORM_ENTRY              | 0 = end of list ->
        BPL     SND_4TONE_ENTRY                 | >0 = four-tone synthesizer ->
| square-wave synthesizer: command is (count, freq, amplitude, duration)
SND_SQWAVE_NEXT:
        MOVEM   (A1)+,D0-D2                     | D0=freq, D1=amplitude, D2=duration
        TST     D2                              | duration = 0?
        BEQ     SND_SQWAVE_END                  | yes, end of this waveform ->
| acquire VIA Timer 1 for square-wave generation
        MOVE.L  A0,-(SP)                        | save IOParam
        TST.B   (T1Arbitrate).w                 | Timer 1 available?
        BEQ.B   SND_CLAIM_T1                    | no, take it ->
        BCLR    #0x7,(T1Arbitrate).w            | test and claim Timer 1
        BEQ.B   SND_T1_READY                    | already claimed ->
        CLR.B   (T1Arbitrate).w                 | release claim flag
SND_CLAIM_T1:
        MOVE.L  (VIA).w,A0                      | A0 = VIA base
        ORI.B   #0xC0,0x1600(A0)                | VIA ACR: Timer 1 = square-wave output mode
| program VIA Timer 1 for square wave at frequency D0
        CMP     (CurPitch).w,D0                 | same frequency?
        BEQ.B   SND_T1_READY                    | yes, skip ->
        MOVE.B  D0,0x800(A0)                    | T1CL: timer 1 counter low byte
        ROR     #0x8,D0                         | get high byte
        MOVE.B  D0,0xA00(A0)                    | T1CH: timer 1 counter high (starts timer)
        ROR     #0x8,D0                         | restore D0
SND_T1_READY:
        MOVE    D0,(CurPitch).w                 | save current pitch
        MOVE    D1,D0                           | D0 = amplitude
        BSR     SND_FILL_BUF                    | fill sound buffer with amplitude
        MOVE    D2,D0                           | D0 = duration (ticks)
        LEA.L   SoundVBL_taskSquareWave(PC),A1  | VBL proc for square wave timing
        BSR.B   SND_VBL_INSTALL                 | install VBL task with D0 ticks
        MOVE.L  (SP)+,A0                        | restore IOParam
        ADDQ.L  #0x6,0x28(A0)                   | advance to next sound command (+6 bytes)
SND_PRIME_DONE:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from driver prime

| ----------------------------------------------------------
|
| SND_VBL_IMMEDIATE/SND_VBL_INSTALL: install VBL task for sound duration timing
| SND_VBL_IMMEDIATE: 1-tick delay, SND_VBL_INSTALL: D0-tick delay, A1 = VBL proc
|
SND_VBL_IMMEDIATE:
        MOVEQ.L #0x1,D0                         | 1 tick (immediate)
| SND_VBL_INSTALL -- install VBL task with D0 ticks.
SND_VBL_INSTALL:
        LEA.L   (SoundVBL_qLink).w,A0           | VBL task record
        MOVE.L  A0,D1                           | save for VInstall
        CLR.L   (A0)+                           | qLink = nil
        MOVE    #0x1,(A0)+                      | qType = vType
        MOVE.L  A1,(A0)+                        | vblAddr = proc
        MOVE    D0,(A0)+                        | vblCount = ticks until callback
        CLR     (A0)                            | vblPhase = 0
        TST.B   (SoundActive).w                 | already installed?
        BNE.B   SND_VBL_INSTALLED               | yes, count updated ->
        ST.B    (SoundActive).w                 | mark active
        MOVE.L  D1,A0                           | A0 = VBL task
        _VInstall                               | install in VBL queue
SND_VBL_INSTALLED:
        RTS                                     | return from VBL task install

| ----------------------------------------------------------
|
| VBL callback: square wave note duration expired
| Advances to next sound command or completes I/O
|
SoundVBL_taskSquareWave:
        MOVE.L  (SoundDCE).w,A1                 | A1 = Sound DCE
        MOVE.L  0x8(A1),A0                      | A0 = current IOParam
        MOVE.L  0x28(A0),D0                     | D0 = position in sound data
        MOVE.L  0x20(A0),A1                     | A1 = sound command buffer
        ADDA.L  D0,A1                           | advance to current command
        ADDQ.L  #0x2,A1                         | skip command header
        ADDQ.W  #0x4,D0                         | advance position
        CMP.L   0x24(A0),D0                     | past end of buffer?
        BLT     SND_SQWAVE_NEXT                 | no, play next note ->
| all notes played: release Timer 1 and complete I/O
SND_SQWAVE_END:
        BSR     SND_RELEASE_T1_ONLY             | release Timer 1
        CLR     (CurPitch).w                    | clear pitch
| SND_STOP_AND_DONE -- yes: remove VBL, silence, IODone.
SND_STOP_AND_DONE:
        BSR     SND_REMOVE_VBL                  | remove VBL task
        BSR     SND_SILENCE_BUF                 | fill buffer with silence
SND_IODONE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
        MOVE.L  (SoundDCE).w,A1                 | DCE for IODone
        MOVE.L  (JIODone).w,A0                  | IODone vector
        JMP     (A0)                            | -> complete I/O

| ----------------------------------------------------------
|
| SND_4TONE_ENTRY: four-tone synthesizer entry
| : save data pointer, install VBL mixer
SND_4TONE_ENTRY:
        MOVE.L  (A1)+,(SoundPtr).w              | save 4-tone parameter block ptr
        LEA.L   SoundVBL_task4Tone(PC),A1       | VBL = 4-tone mixer callback
SND_INSTALL_VBL_IMM:
        BSR.B   SND_VBL_IMMEDIATE               | install VBL (1-tick immediate)
        BRA.B   SND_PRIME_DONE                  | -> noErr
| 4-tone done: restore regs and clean up
SND_4TONE_DONE:
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore all regs
        BRA.B   SND_STOP_AND_DONE               | -> remove VBL, silence, IODone

| ----------------------------------------------------------
|
| 4-tone VBL callback: mix 4 sine wave voices into sound buffer
| Called every tick (60 Hz) to synthesize 370 samples
| Each voice: phase accumulator + amplitude + waveform table ptr
|
SoundVBL_task4Tone:
        MOVEM.L D0-D7/A0-A6,-(SP)               | save all regs (restored at SND_4TONE_DONE)
        MOVE.L  (SoundPtr).w,A6                 | A6 = 4-tone parameter block
        TST     (A6)                            | duration count zero?
        BEQ.B   SND_4TONE_DONE                  | yes, done ->
        MOVE    #0x1,(SoundVBL_Count).w         | reschedule for next tick
        SUBQ.W  #0x1,(A6)+                      | decrement duration
        MOVEM.L (A6),D2-D7/A0-A5                | load 4 voices' freq, phase, and waveform ptrs
| set up for 4-voice waveform mixing
        MOVE.L  (SoundBase).w,A6                | A6 = sound buffer base
        MOVE.L  #0xFF0000,D1                    | D1 = phase mask (high byte)
| check if any voices are active (nonzero frequency)
        MOVE.L  A0,D0                           | voice 4 frequency
        BNE.B   SND_4TONE_MIX_START             | active ->
        MOVE.L  D6,D0                           | voice 3 frequency
        BNE.B   SND_4TONE_MIX_START             | active ->
        MOVE.L  D4,D0                           | voice 2 frequency
        BEQ.B   SND_SOLO_VOICE1                 | all silent ->
| at least one voice active: mix 370 samples (2 passes of 185)
SND_4TONE_MIX_START:
        ADDA    #0x172,A6                       | start at end of buffer (fill backwards)
        MOVE    #0x2,-(SP)                      | outer loop: 2 passes
        MOVE    #0xB9,-(SP)                     | inner loop: 185 samples per pass
| inner loop: generate one sample by mixing 4 voices
| Each voice: phase += freq, sample = waveform[phase >> 16]
SND_MIX_SAMPLE:
        CLR     D1                              | clear accumulator
        ADD.L   D2,D3                           | voice 1: advance phase
        ADD.L   D4,D5                           | voice 2: advance phase
        ADD.L   D6,D7                           | voice 3: advance phase
        ADDA.L  A0,A1                           | voice 4: advance phase
| look up waveform samples and sum
        MOVE.L  D3,D0                           | voice 1 phase
        AND.L   D1,D0                           | mask to table index
        SWAP    D0                              | index in low word
        MOVE.B  0x0(A2,D0.W),D1                 | D1 = voice 1 sample from waveform table
        MOVE.L  D5,D0                           | voice 2 phase
        AND.L   D1,D0                           | mask to wave table size
        SWAP    D0                              | index in low word
        MOVE.B  0x0(A3,D0.W),D0                 | voice 2 sample
        ADD     D0,D1                           | accumulate
        MOVE.L  D7,D0                           | voice 3 phase
        AND.L   D1,D0                           | mask to wave table size
        SWAP    D0                              | index in low word
        MOVE.B  0x0(A4,D0.W),D0                 | voice 3 sample
        ADD     D0,D1                           | accumulate
        MOVE.L  A1,D0                           | voice 4 phase
        AND.L   D1,D0                           | mask to wave table size
        SWAP    D0                              | index in low word
        MOVE.B  0x0(A5,D0.W),D0                 | voice 4 sample
        ADD     D0,D1                           | accumulate all 4 voices
        LSR     #0x2,D1                         | divide by 4 (average)
        MOVE.B  D1,(A6)                         | store sample in sound buffer
        ADDQ.W  #0x2,A6                         | advance buffer (even bytes only)
        SUBQ.W  #0x1,(SP)                       | inner loop count
        BNE.B   SND_MIX_SAMPLE                  | more samples ->
| second pass: wrap around to start of buffer
        MOVE.L  (SoundBase).w,A6                | reset to buffer start
        MOVE    #0xB9,(SP)                      | reset inner count (185)
        SUBQ.W  #0x1,0x2(SP)                    | outer loop count
        BNE.B   SND_MIX_SAMPLE                  | second pass ->
        BRA.B   SND_SAVE_VOICES                 | -> save voice state and return

| ----------------------------------------------------------
|
| SND_SOLO_VOICE1: optimized single-voice path
|
| optimized path: only voice 1 active, voices 2-4 are constant
| Pre-compute voices 2+3+4 sum, then only iterate voice 1
SND_SOLO_VOICE1:
        ADDA    #0x8C,A6                        | offset into buffer
        MOVE    #0x2,-(SP)                      | outer: 2 passes
        MOVE    #0x12C,-(SP)                    | inner: 300 samples
| pre-compute constant contribution from voices 2-4
        MOVE.L  D5,D0                           | voice 2 phase
        AND.L   D1,D0                           | mask to wave table size
        SWAP    D0                              | index in low word
        MOVE.B  0x0(A3,D0.W),D0                 | voice 2 sample
        MOVE    D0,-(SP)                        | push partial sum
        MOVE.L  D7,D0                           | voice 3 phase
        AND.L   D1,D0                           | mask to wave table size
        SWAP    D0                              | index in low word
        MOVE.B  0x0(A4,D0.W),D0                 | voice 3 sample
        ADD     D0,(SP)                         | accumulate
        MOVE.L  A1,D0                           | voice 4 phase
        AND.L   D1,D0                           | mask to wave table size
        SWAP    D0                              | index in low word
        MOVE.B  0x0(A5,D0.W),D0                 | voice 4 sample
        ADD     D0,(SP)                         | (SP) = voices 2+3+4 constant sum
| fast inner loop: only voice 1 varies
SND_SOLO_LOOP:
        CLR     D1                              | clear accumulator
        ADD.L   D2,D3                           | voice 1: advance phase
        MOVE.L  D3,D0                           | voice 1 phase
        AND.L   D1,D0                           | mask to index
        SWAP    D0                              | index in low word
        MOVE.B  0x0(A2,D0.W),D1                 | voice 1 sample
        ADD     (SP),D1                         | + constant voices 2+3+4
        LSR     #0x2,D1                         | average of 4
        MOVE.B  D1,(A6)                         | store in sound buffer
        ADDQ.W  #0x2,A6                         | next even byte
        SUBQ.W  #0x1,0x2(SP)                    | inner count
        BNE.B   SND_SOLO_LOOP                   | more ->
| second pass
        MOVE.L  (SoundBase).w,A6                | reset to start
        MOVE    #0x46,0x2(SP)                   | 70 samples for second pass
        SUBQ.W  #0x1,0x4(SP)                    | outer count
        BNE.B   SND_SOLO_LOOP                   | ->
        ADDQ.W  #0x2,SP                         | pop constant sum
| save updated voice state back to parameter block
SND_SAVE_VOICES:
        ADDQ.W  #0x4,SP                         | pop loop counters
        MOVE.L  (SoundPtr).w,A6                 | A6 = parameter block
        ADDQ.W  #0x2,A6                         | skip duration word
        MOVEM.L D2-D7/A0-A1,(A6)                | save updated phase accumulators
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore all regs
SND_VBL_RTS:
        RTS                                     | return from VBL callback

| ----------------------------------------------------------
|
| Free-form synthesizer entry: play arbitrary waveform data
|
SND_FREEFORM_ENTRY:
        MOVE.L  (SoundDCE).w,A1                 | A1 = Sound DCE
        CLR.L   0x10(A1)                        | clear position counter
        LEA.L   SoundVBL_taskFreeForm(PC),A1    | VBL proc = free-form player
        BRA     SND_INSTALL_VBL_IMM             | install VBL

| ----------------------------------------------------------
|
| VBL callback: play free-form (sampled) sound data
| Copies 370 bytes of waveform data to sound buffer each tick
|
SoundVBL_taskFreeForm:
        BSR.B   SND_CHECK_ACTIVE_IO             | set up IOParam -> A0, DCE -> A1
        BEQ.B   SND_VBL_RTS                     | no active I/O ->
        MOVE.L  0x10(A1),D3                     | D3 = current byte position
        MOVE    #0x1,(SoundVBL_Count).w         | reschedule for next tick
| set up free-form playback: read sample rate and source data
        MOVE.L  A4,-(SP)                        | save A4
        MOVE.L  0x20(A0),A1                     | A1 = ioBuffer
        ADDQ.W  #0x2,A1                         | skip header word
        MOVE.L  (A1)+,D1                        | D1 = sample rate (fixed-point)
        MOVE.L  A1,A3                           | A3 = start of sample data
        ADDA.L  0x24(A0),A3                     | A3 = end of sample data (+ ioReqCount)
        ADDA.L  D0,A1                           | A1 = current position in sample data
| set up sound buffer pointers
        MOVE.L  (SoundBase).w,A2                | A2 = sound buffer
        ADDA    #0x40,A2                        | offset past PWM area
        LEA.L   0x2A4(A2),A4                    | A4 = end of sound buffer
        CLR     -(SP)                           | loop-around flag
        MOVE    #0x151,D2                       | 337 samples to generate
| sample rate conversion loop: resample source at playback rate
SND_RESAMPLE_OUTER:
        MOVEQ.L #0x0,D0                         | clear byte counter
SND_RESAMPLE_INNER:
        MOVE.B  (A1),(A2)                       | copy sample to sound buffer
        ADDQ.W  #0x2,A2                         | advance buffer (even bytes)
        ADD.L   D1,D3                           | advance fractional position
        SWAP    D3                              | integer part in low word
        ADDA    D3,A1                           | advance source by integer samples
        ADD     D3,D0                           | count bytes consumed
        CLR     D3                              | clear integer part
        SWAP    D3                              | fraction back in low word
        CMPA.L  A1,A3                           | past end of source?
        DBLE    D2,SND_RESAMPLE_INNER           | no, and more buffer space ->
| update I/O position
        ADD.L   D0,0x28(A0)                     | ioActCount += bytes consumed
        TST     (SP)+                           | did we wrap around?
        BEQ.B   SND_FF_NO_WRAP                  | no ->
        TST     D2                              | any buffer left to fill?
        BMI.B   SND_FF_SAVE_POS                 | no ->
| fill remaining buffer with silence
SND_FILL_SILENCE:
        MOVEQ.L #0x0,D0                         | silence = 0
SND_SILENCE_LOOP:
        MOVE.B  D0,(A2)                         | write silence
        ADDQ.W  #0x2,A2                         | next even byte
        CMPA.L  A2,A4                           | past end of buffer?
        BGT.B   SND_SILENCE_WRAP                | no ->
        MOVE.L  (SoundBase).w,A2                | wrap to start
SND_SILENCE_WRAP:
        DBF     D2,SND_SILENCE_LOOP             | fill rest with silence
| save position and return
SND_FF_SAVE_POS:
        MOVE.L  (SoundDCE).w,A1                 | DCE
        MOVE.L  D3,0x10(A1)                     | save fractional position
        MOVE.L  (SP)+,A4                        | restore A4
| SND_CHECK_ACTIVE_IO: check if free-form I/O is still active
| Returns: A0 = IOParam, A1 = DCE, NE if active
SND_CHECK_ACTIVE_IO:
        MOVE.L  (SoundDCE).w,A1                 | A1 = Sound DCE
        MOVE.L  0x8(A1),D0                      | D0 = active IOParam (from DCE queue)
        BEQ.B   SND_FF_INACTIVE                 | no active I/O ->
        MOVE.L  D0,A0                           | A0 = IOParam
        MOVE.L  0x28(A0),D0                     | D0 = ioActCount (bytes played)
        CMP.L   0x24(A0),D0                     | >= ioReqCount?
        BLT.B   SND_FF_CHECK_RTS                | no, still playing ->
        BSR     SND_STOP_AND_DONE               | yes: remove VBL, silence, IODone
SND_FF_INACTIVE:
        MOVEQ.L #0x0,D0                         | return EQ (inactive)
SND_FF_CHECK_RTS:
        RTS                                     | return from active I/O check
| free-form: end of source reached, fill remaining with silence
SND_FF_NO_WRAP:
        TST     D2                              | any buffer left?
        BMI.B   SND_FF_WRAP                     | no ->
        ADDI    #0x20,D2                        | adjust count for wrap
        BRA.B   SND_FILL_SILENCE                | -> fill with silence

| ----------------------------------------------------------
|
| SND_FF_WRAP: wrap around to start of source data
|
| wrap around: continue from start of source data
SND_FF_WRAP:
        MOVE    #0x1,-(SP)                      | set wrap flag
        MOVE.L  (SoundBase).w,A2                | reset buffer to start
        MOVEQ.L #0x1F,D2                        | 32 more samples
        BRA.B   SND_RESAMPLE_OUTER              | continue resampling

| end of resource : 'DRVR' 3 '.Sound'

| resource header
  .long 0xC0002070                              | Length
  .long 0x0000005C                              | ?

