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
| Installed at boot via _DrvrInstall (see jump table at $05FC).
| ----------------------------------------------------------
DRVR_Sound:                                     | start of .Sound DRVR header
        .short  0x4E00                          | drvrFlags: ctl/status/read/write
        .short  0x0000                          | drvrDelay
        .short  0x0000                          | drvrEMask
        .short  0x0000                          | drvrMenu
        .short  0x001A                          | drvrOpen -> E_Sound_Open @ $34C8
        .short  0x00C6                          | drvrPrime -> E_Sound_Prime @ $3574
        .short  0x00A6                          | drvrCtl -> E_Sound_Ctl @ $3554
        .short  0x00BA                          | drvrStatus -> E_Sound_Status @ $3568
        .short  0x0030                          | drvrClose -> SND_KILL_SOUND @ $34DE
        .byte   0x06                            | drvrName length
        .ascii  ".Sound"                        | drvrName text
        .byte   0x20                            | pad to even boundary

| ----------------------------------------------------------
| .Sound Open: initialize sound driver
| VIA Timer 1 generates square-wave sound via Port B bit 7 (vSndEnb);
| volume controlled by VIA Port A bits 0-2.
| ----------------------------------------------------------
E_Sound_Open:
        MOVE.L  A1,(SoundDCE).w                 | save DCE pointer
        BSR.B   SND_RELEASE_T1                  | disable VBL sound task + release Timer 1
        MOVE.B  (SPVolCtl).w,D0                 | D0 = saved speaker volume (PRAM)
        BSR.W   SetSndVol                       | set volume via VIA Port A bits 0-2
        CLR.B   (SoundActive).w                 | mark sound inactive
SND_RETURN_NOERR:
        MOVEQ.L #0x0,D0                         | D0 = 0 (noErr)
        RTS                                     | return from .Sound Open / Close

| ----------------------------------------------------------
| SND_KILL_SOUND / .Sound Close: stop sound + release Timer 1
| ----------------------------------------------------------
SND_KILL_SOUND:                                 | @ $34DE (drvrClose target)
        BSR.B   SND_REMOVE_VBL                  | remove VBL sound task
        BSR.B   SND_RELEASE_T1                  | release VIA Timer 1 to system
        BSET    #0x7,(0xEFE1FE).l               | set bit 7 at absolute (VIA handshake)
        BRA.B   SND_RETURN_NOERR                | -> noErr
SND_RELEASE_T1:
        MOVEQ.L #-0x1,D0                        | D0 = -1 = full-amplitude silence level
        BSR.B   SND_FILL_BUF                    | silence sound buffer with -1 fill
SND_T1_RELEASED:                                | @ $34F0 (skip-fill entry)
        MOVE.L  (VIA).w,A0                      | A0 = VIA base
        ANDI.B  #0x3F,vACR(A0)                  | VIA_ACR &= 0x3F (T1 one-shot, PB7 off)
        RTS                                     | return after Timer 1 released

| ----------------------------------------------------------
| SND_REMOVE_VBL: remove VBL sound task if active
SND_REMOVE_VBL:
        TST.B   (SoundActive).w                 | sound VBL task running?
        BEQ.B   SND_VBL_REMOVED                 | no ->
        LEA.L     (SoundVBL_qLink).w,A0         | VBL task record
        _VRemove                                | remove from VBL queue
        CLR.B   (SoundActive).w                 | mark inactive
SND_VBL_REMOVED:
        RTS                                     | return from VBL task removal
| SND_FILL_SetLevel - fill entire sound buffer with constant level D0
SND_FILL_BUF:
        MOVE.B  D0,(SoundLevel).w               | save requested level in lowmem
        MOVE.L  (SoundBase).w,A0                | A0 = sound buffer base
        MOVEQ.L #0x49,D1                        | D1 = 74 samples (370 bytes / 5)
SND_FILL_LOOP:                                  | fill 6 samples per iteration
        MOVE.B  D0,(A0)                         | write sample to even byte
        ADDQ.W  #0x2,A0                         | skip odd byte (video timing)
        MOVE.B  D0,(A0)                         | write sample 2 of 5
        ADDQ.W  #0x2,A0                         | advance to next even byte
        MOVE.B  D0,(A0)                         | write sample 3 of 5
        ADDQ.W  #0x2,A0                         | advance to next even byte
        MOVE.B  D0,(A0)                         | write sample 4 of 5
        ADDQ.W  #0x2,A0                         | advance to next even byte
        MOVE.B  D0,(A0)                         | write sample 5 of 5
        ADDQ.W  #0x2,A0                         | advance to next even byte
        DBF     D1,SND_FILL_LOOP                | loop for all 74 samples
        RTS                                     | return after buffer filled
| SetSndVol - apply D0 to VIA Port A volume bits 0-2 (SPVolCtl)
SetSndVol:
        MOVE    SR,-(SP)                        | save interrupt mask
        ORI     #0x300,SR                       | disable interrupts (IPL 3)
        MOVE.B  (0xEFFFFE).l,D1                 | D1 = VIA Port A (volume + overlay)
        ANDI    #0xF8,D1                        | clear volume bits 0-2
        ANDI    #0x7,D0                         | mask volume to 3 bits
        MOVE.B  D0,(SdVolume).w                 | store in low-memory global
        OR      D0,D1                           | merge volume bits into Port A image
        MOVE.B  D1,(0xEFFFFE).l                 | write back to VIA Port A
        RTE                                     | restore SR from stack (pushed above) + return
        MOVE    csCode(A0),D0                   | D0 = csCode
        BEQ.B   E_Sound_Status                  | csCode 0: status ->
        SUBQ.W  #0x2,D0                         | test for csCode 2 or 3
        BEQ.B   SND_CTL_VOLUME                  | csCode 2: set volume ->
        BLT.W   SND_KILL_SOUND                  | csCode 1: killIO (stop sound) ->
        MOVE    csParam(A0),D0                  | D0 = fill value from csParam
        BSR.B   SND_FILL_BUF                    | csCode 3: fill buffer with constant
E_Sound_Status:
        BRA.W   SND_IODONE_NOERR                | return noErr via IODone
SND_CTL_VOLUME:
        MOVE    28(A0),D0                       | D0 = csParam (new volume 0-7)
        BSR.B   SetSndVol                       | set VIA Port A bits 0-2 = volume
        BRA.B   E_Sound_Status                  | finish control call (noErr)
        BCLR    #0x7,(0xEFE1FE).l               | clear vSndEnb (enable sound) in VIA Port B
        MOVE.L  ioBuffer(A0),A1                 | A1 = ioBuffer (sound command list)
        TST     (A1)+                           | check command type
        BEQ.W   SND_FREEFORM_ENTRY              | 0 = end of list ->
        BPL.W   SND_4TONE_ENTRY                 | >0 = four-tone synthesizer ->
SND_SQWAVE_NEXT:                                | read next square-wave cmd
        MOVEM   (A1)+,D0-D2                     | D0=freq D1=amplitude D2=duration
        TST     D2                              | duration zero?
        BEQ.W   SND_SQWAVE_END                  | D2=0: end/silence ->
        MOVE.L  A0,-(SP)                        | save IOParam ptr
        MOVE.L  (VIA).w,A0                      | A0 = VIA base
        ORI.B   #0xC0,vACR(A0)                  | VIA_ACR |= 0xC0 (T1 PB7-output + free-run)
        CMP     (CurPitch).w,D0                 | same frequency as last note?
        BEQ.B   SND_T1_READY                    | yes -> skip Timer 1 reload
        MOVE    D0,(CurPitch).w                 | save current pitch
        MOVE.B  D0,vT1C(A0)                     | write T1 counter low (triggers latch)
        LSR     #0x8,D0                         | get high byte of frequency
        MOVE.B  D0,vT1CH(A0)                    | write T1 counter high (starts timer)
SND_T1_READY:
        MOVE    D1,D0                           | D0 = amplitude
        BSR.W   SND_FILL_BUF                    | fill buffer at amplitude D0
        MOVE    D2,D0                           | D0 = duration (ticks)
        LEA     SoundVBL_taskSquareWave(PC),A1  | A1 = square-wave VBL proc
        BSR.B   SND_VBL_INSTALL                 | install VBL with D0 ticks delay
        MOVE.L  (SP)+,A0                        | restore IOParam ptr
        ADDQ.L  #0x6,ioActCount(A0)             | ioActCount += 6 (size of square-wave cmd)
SND_PRIME_DONE:
        MOVEQ.L #0x0,D0                         | D0 = 0 (noErr)
        RTS                                     | return from .Sound Prime
SND_VBL_IMMEDIATE:
        MOVEQ.L #0x1,D0                         | D0 = 1 tick (run immediately)
SND_VBL_INSTALL:
        LEA.L     (SoundVBL_qLink).w,A0         | A0 = SoundVBL task record
        MOVE.L  A0,D1                           | DCE for IODone
        CLR.L   (A0)+                           | qLink = nil
        MOVE    #0x1,(A0)+                      | qType = vType (VBL task)
        MOVE.L  A1,(A0)+                        | jump via A0
        MOVE    D0,(A0)+                        | vblCount = ticks until callback
        TST.B   (SoundActive).w                 | VBL task already installed?
        BNE.B   SND_VBL_INSTALLED               | yes -> count was just refreshed
        ST      (SoundActive).w                 | (SoundActive).w := -1 (true)
        MOVE.L  D1,A0                           | A0 = VBL task ptr for VInstall
        _VInstall                               | install task in VBL queue
SND_VBL_INSTALLED:
        RTS                                     | return from VBL install

| ----------------------------------------------------------
| VBL callback: square wave note duration expired
| Advances to next sound command or completes I/O
SoundVBL_taskSquareWave:
        MOVE.L  (SoundDCE).w,A1                 | A1 = Sound DCE
        MOVE.L  8(A1),A0                        | A0 = current IOParam
        MOVE.L  ioActCount(A0),D0               | D0 = position in sound data (ioActCount)
        MOVE.L  ioBuffer(A0),A1                 | A1 = sound command buffer (ioBuffer)
        ADDA.L  D0,A1                           | advance to current command
        ADDQ.L  #0x2,A1                         | skip command header
        ADDQ.W  #0x4,D0                         | advance position
        CMP.L   ioReqCount(A0),D0               | past end of buffer (ioReqCount)?
        BLT.B   SND_SQWAVE_NEXT                 | not yet -> read next command
SND_SQWAVE_END:                                 | @ $360A (D2=0 end/silence)
        BSR.W   SND_T1_RELEASED                 | stop Timer 1 + clear VIA_ACR bits 6-7
        CLR     (CurPitch).w                    | clear current pitch
SND_STOP_AND_DONE:
        BSR.W   SND_REMOVE_VBL                  | remove VBL sound task
        MOVEQ.L #-0x1,D0                        | D0 = -1 silence level
        BSR.W   SND_FILL_BUF                    | silence the sound buffer
        BSET    #0x7,(0xEFE1FE).l               | set bit at absolute
SND_IODONE_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
        MOVE.L  (SoundDCE).w,A1                 | DCE for IODone
        MOVE.L  (JIODone).w,A0                  | IODone vector
        JMP     (A0)                            | -> complete I/O
SND_4TONE_ENTRY:
        MOVE.L  (A1)+,(SoundPtr).w              | SoundPtr = 4-tone parameter block ptr
        LEA     SoundVBL_task4Tone(PC),A1       | A1 = 4-tone mixer VBL proc
SND_INSTALL_VBL_IMM:
        BSR.B   SND_VBL_IMMEDIATE               | install VBL (1-tick immediate)
        BRA.B   SND_PRIME_DONE                  | return noErr
SND_4TONE_DONE:
        MOVEM.L (SP)+,D0-A6                     | restore all regs saved in mixer
        BRA.B   SND_STOP_AND_DONE               | stop sound + IODone
SoundVBL_task4Tone:
        MOVEM.L D0-A6,-(SP)                     | save all regs (restored at SND_4TONE_DONE)
        MOVE.L  (SoundPtr).w,A6                 | A6 = 4-tone parameter block
        TST     (A6)                            | duration count zero?
        BEQ.B   SND_4TONE_DONE                  | yes -> done playing
        MOVE.W   #0x1,0x274                     | SoundVBL_Count=1 (run next tick)
        SUBQ.W   #0x1,(FP)+                     | decrement duration in-place
        MOVEM.L  (FP),D2-A5                     | load 4 voices: freq/phase/wave ptrs
        MOVE.L  (SoundBase).w,A6                | A6 = sound buffer base
        ADDA.W  #0x172,A6                       | advance to end of buffer (fill back)
        MOVE.L  #0xFF0000,D1                    | D1 = phase mask (high byte select)
        MOVE    #0x2,-(SP)                      | outer loop count = 2 passes
        MOVE.W   #0xB9,-(SP)                    | inner loop count = 185 samples

| inner loop: generate one sample by mixing 4 voices
| Each voice: phase += freq, sample = waveform[phase >> 16]
SND_MIX_SAMPLE:
        CLR     D1                              | clear accumulator
        ADD.L   D2,D3                           | voice 1: advance phase
        ADD.L   D4,D5                           | voice 2: advance phase
        ADD.L   D6,D7                           | voice 3: advance phase
        ADDA.L  A0,A1                           | voice 4: advance phase
        MOVE.L  D3,D0                           | voice 1 phase
        AND.L   D1,D0                           | mask to table index
        SWAP    D0                              | index in low word
        MOVE.B  0(A2,D0.W),D1                   | D1 = voice 1 sample from waveform table
        MOVE.L  D5,D0                           | voice 2 phase
        AND.L   D1,D0                           | mask to wave table size
        SWAP    D0                              | index in low word
        MOVE.B  0(A3,D0.W),D0                   | voice 2 sample
        ADD     D0,D1                           | accumulate
        MOVE.L  D7,D0                           | voice 3 phase
        AND.L   D1,D0                           | mask to wave table size
        SWAP    D0                              | index in low word
        MOVE.B  0(A4,D0.W),D0                   | voice 3 sample
        ADD     D0,D1                           | accumulate
        MOVE.L  A1,D0                           | voice 4 phase
        AND.L   D1,D0                           | mask to wave table size
        SWAP    D0                              | index in low word
        MOVE.B  0(A5,D0.W),D0                   | voice 4 sample
        ADD     D0,D1                           | accumulate all 4 voices
        LSR     #0x2,D1                         | divide by 4 (average)
        MOVE.B  D1,(A6)                         | store sample in sound buffer
        ADDQ.W  #0x2,A6                         | advance buffer (even bytes only)
        SUBQ.W  #0x1,(SP)                       | inner loop count
        BNE.B   SND_MIX_SAMPLE                  | more samples ->
        MOVE.L  (SoundBase).w,A6                | reset to buffer start
        MOVE    #0xB9,(SP)                      | reset inner count (185)
        SUBQ.W  #0x1,2(SP)                      | outer loop count
        BNE.B   SND_MIX_SAMPLE                  | second pass ->

| save updated voice state back to parameter block
SND_SAVE_VOICES:
        ADDQ.W  #0x4,SP                         | pop loop counters
        MOVE.L  (SoundPtr).w,A6                 | A6 = parameter block
        ADDQ.W  #0x2,A6                         | skip duration word
        MOVEM.L D2-D7/A0-A1,(A6)                | save updated phase accumulators
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore all regs
        RTS                                     | return from 4-tone VBL callback
SND_FREEFORM_ENTRY:
        MOVE.L  (SoundDCE).w,A1                 | A1 = Sound DCE
        CLR.L   16(A1)                          | clear position counter
        LEA     SoundVBL_taskFreeForm(PC),A1    | VBL proc = free-form player
        BRA.W   SND_INSTALL_VBL_IMM             | install VBL
SoundVBL_taskFreeForm:
        MOVE.L  (SoundDCE).w,A1                 | A1 = Sound DCE
        MOVE.L  8(A1),A0                        | A0 = current IOParam (DCE+8)
        MOVE.L  16(A1),D3                       | D3 = saved fractional phase
        MOVE.L  ioActCount(A0),D0               | D0 = position in free-form sample stream
        CMP.L   ioReqCount(A0),D0               | past end of buffer (ioReqCount)?
        BGE.W   SND_STOP_AND_DONE               | yes -> wind down sound VBL
        MOVE    #0x1,(SoundVBL_Count).w         | next VBL: run on every tick
        MOVE.L  A4,-(SP)                        | save A4
        MOVE.L  ioBuffer(A0),A1                 | A1 = ioBuffer (free-form sample list)
        ADDQ.W  #0x2,A1                         | skip cmd word
        MOVE.L  (A1)+,D1                        | D1 = rate (samples per tick, 16.16)
        MOVE.L  A1,A3                           | A3 = start of sample data
        ADDA.L  ioReqCount(A0),A3               | A3 = end-of-buffer pointer
        ADDA.L  D0,A1                           | advance source by ioActCount
        MOVE.L  (SoundBase).w,A2                | A2 = sound buffer base
        ADDA.W  #0x40,A2                        | skip past first 32 samples
        LEA.L     0x2A4(A2),A4                  | A4 = end of usable buffer (676)
        CLR     -(SP)                           | wrap-flag = 0 (no wrap yet)
        MOVE    #0x151,D2                       | D2 = 337 sample slots
SND_FREEFORM_LOOP:
        MOVEQ.L #0x0,D0                         | D0 = 0 byte-consumed counter
SND_RESAMPLE_INNER:
        MOVE.B  (A1),(A2)                       | copy sample to sound buffer
        ADDQ.W  #0x2,A2                         | advance buffer (even bytes)
        ADD.L   D1,D3                           | advance fractional position
        SWAP    D3                              | integer part in low word
        ADDA.W  D3,A1                           | advance source by integer samples
        ADD     D3,D0                           | count bytes consumed
        CLR     D3                              | clear integer part
        SWAP    D3                              | fraction back in low word
        CMPA.L  A1,A3                           | reached end of source data?
        DBLE    D2,SND_RESAMPLE_INNER           | no, and more buffer space ->
        ADD.L   D0,ioActCount(A0)               | ioActCount += bytes consumed
        TST     (SP)+                           | did we wrap around?
        BEQ.B   SND_FF_NO_WRAP                  | no wrap -> check buffer remaining
        TST     D2                              | any buffer left to fill?
        BMI.B   SND_FF_SAVE_POS                 | no ->
SND_RESAMPLE_INNER_CONT:
        MOVEQ.L #0x0,D0                         | D0 = 0 (@ $3748)
SND_SILENCE_LOOP:
        MOVE.B  D0,(A2)                         | write silence
        ADDQ.W  #0x2,A2                         | next even byte
        CMPA.L  A2,A4                           | past end of buffer?
        BGT.B   SND_SILENCE_WRAP                | no ->
        MOVE.L  (SoundBase).w,A2                | wrap to start
SND_SILENCE_WRAP:
        DBRA    D2,SND_SILENCE_LOOP             | loop until buffer fully silenced
SND_FF_SAVE_POS:
        MOVE.L  (SoundDCE).w,A1                 | A1 = Sound DCE
        MOVE.L  D3,16(A1)                       | save fractional phase in DCE+16
        MOVE.L  (SP)+,A4                        | restore A4 from stack
        RTS                                     | return from free-form VBL
SND_FF_NO_WRAP:
        TST     D2                              | any buffer left?
        BMI.B   SND_FF_WRAP                     | no ->
        ADDI    #0x20,D2                        | reload silence-loop count = 32
        BRA.B   SND_RESAMPLE_INNER_CONT         | emit silence for buffer tail
SND_FF_WRAP:
        MOVE.W   #0x1,-(SP)                     | push wrap-flag = 1
        MOVE.L  (SoundBase).w,A2                | reset A2 to buffer start
        MOVEQ.L #0x1F,D2                        | D2 = 31 (wrapped sample count)
        BRA.B   SND_FREEFORM_LOOP               | restart resample at buffer head
