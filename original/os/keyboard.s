| Keyboard driver -- InitKeyboard, keyboard interrupt, KybdTask
|
| Apple module KBDMNGR (as in the Mac Plus). Talks to the keyboard through
| the VIA shift register: Model/Inquiry commands, key transition bytes
| (bit 7 = key up, $79 = keypad prefix), KeyMap update, key translation
| through Key1Trans/Key2Trans, keyDown/keyUp/autoKey events via _PostEvent,
| and KybdTask, the VBL task that polls the keyboard.
|
| References: Inside Macintosh Vol III, Ch 2: keyboard protocol;
| Inside Macintosh Vol I, Ch 8: keyboard events

| ----------------------------------------------------------
| InitKeyboard -- initialize keyboard subsystem (called during boot)
| Mac keyboard is an Intel 8021 microcontroller communicating via VIA
| shift register (SR). Mac sends command bytes; keyboard responds with
| key data. VIA ACR bits [4:2] control SR mode.
| Commands: $10=Inquiry (poll for key), $14=Instant (read immediately),
| $16=Model (get keyboard type), $36=Test (self-test).
| Installs:
| Lvl1DT[2] -> VIAInt_KeyDataReady (VIA SR interrupt handler)
| JKybdTask -> KybdTask (VBL keyboard timeout poller)
| Clears Key1Trans / Key2Trans (no translation procs until OS loaded).
| Sets KbdVers=$FF (forces a model query on first VBL).
InitKeyboard:
        CLR.B   (KbdType).w                     | clear keyboard model number
        CLR.L   (KbdVers).w                     | clear KbdVers + KbdVars_1
        BSR.W   ZERO_KEYMAP                     | zero the 18-byte KeyMap bitmap
        ST      (KbdVers).w                     | KbdVers = $FF: forces model query at first VBL
        LEA     VIAInt_KeyDataReady(PC),A0      | A0 = VIA SR interrupt handler
        MOVE.L  A0,(Lvl1DT_2).w                 | install in VIA Lvl1DT[2] (SR-shift-done slot)
        CLR.L   (Key1Trans).w                   | clear primary key translation procedure ptr
        CLR.L   (Key2Trans).w                   | clear secondary (keypad) translation ptr
        LEA     KybdTask(PC),A0                 | A0 = keyboard VBL polling task
        MOVE.L  A0,(JKybdTask).w                | install in JKybdTask vector

| ----------------------------------------------------------
| GetKeyboardModelNumber -- re-query keyboard for its model number.
| Sets KbdLast=1 (next SR byte is model response), then falls into
| KBD_SEND_CMD with D0 = $16 (Model command).
GetKeyboardModelNumber:
        MOVE.L  (VIA).w,A1                      | A1 = VIA base address
        CLR.B   vPCR(A1)                        | PCR = 0: CB2 input mode (keyboard data in)
        MOVE.B  #0x87,vIER(A1)                  | IER: enable SR + Timer 1 + CA1 interrupts
        MOVEQ.L #0x16,D0                        | D0 = $16 = Model command (get keyboard type)
        ST.B    (KbdLast).w                     | flag: next SR byte is model number response
| ----------------------------------------------------------
| KBD_SEND_CMD -- send command byte D0 to keyboard via VIA shift register.
| Protocol: disable SR -> send sync pulse (0x00 with bit-banged clock) ->
| load command byte. ACR bits [4:2]: 000=SR disabled, 011=shift out under
| ext CB1 clock, 111=shift out under internal Timer 2 clock.
| Returns via RTE -- assumes the caller is the VIA SR interrupt handler;
| RTE pops the SR + PC pushed by the original interrupt entry.
KBD_SEND_CMD:
        MOVE.L  (VIA).w,A1                      | A1 = VIA base address
        MOVE    SR,-(SP)                        | save processor SR
        ORI     #0x300,SR                       | mask all interrupts during SR manipulation
        MOVE.B  vACR(A1),D1                     | D1 = current ACR value
        ANDI.B  #0xE3,D1                        | clear SR control bits [4:2] = 000 (SR disabled)
        MOVE    D1,-(SP)                        | save ACR-with-SR-disabled on stack
        MOVE.B  D1,vACR(A1)                     | write ACR: SR disabled
        CLR.B   vSR(A1)                         | clear SR data register
        ORI.B   #0x18,D1                        | set bits [4:3] = 11: shift out under ext clock
        MOVE.B  D1,vACR(A1)                     | write ACR: begin shift out mode
        CLR.B   vSR(A1)                         | load SR=0, clock out sync/attention pulse
        NOP                                     | brief delay for keyboard to recognize sync
        MOVE    (SP)+,D1                        | restore ACR-with-SR-disabled
        MOVE.B  D1,vACR(A1)                     | write ACR: SR disabled again (end sync pulse)
        ORI.B   #0x1C,D1                        | set bits [4:2] = 111: shift out under T2 clock
        MOVE.B  D1,vACR(A1)                     | write ACR: shift out under internal clock
        MOVE.B  D0,vSR(A1)                      | load command byte into SR; clocks to keyboard
        RTE                                     | return from VIA SR interrupt
| ----------------------------------------------------------
| VIAInt_KeyDataReady -- VIA SR interrupt: keyboard sent response data
| Called when VIA shift register completes a byte transfer.
| If Mac was transmitting (ACR bit 4 set), this is command-done; wait
| ~330us for keyboard to prepare response, then switch SR to input mode.
| If Mac was receiving (ACR bit 4 clear), branch into KBD_DATA_RECEIVED.
VIAInt_KeyDataReady:
        BTST    #0x4,vACR(A1)                   | ACR bit 4: SR shifting out? (command phase)
        BEQ.B   KBD_DATA_RECEIVED               | no: receiving phase, go read response byte
        MOVE.B  #0x4,vIFR(A1)                   | IFR: clear SR interrupt flag
        MOVE    #0x96,D0                        | D0 = 150 (DBF count for ~330us delay on 68000)
KBD_SEND_DELAY:
        DBF     D0,KBD_SEND_DELAY               | spin-wait delay loop
        BCLR    #0x4,vACR(A1)                   | clear ACR bit 4: switch SR to input (shift in)
        MOVE.B  vSR(A1),D0                      | dummy read of SR to start receiving response
        RTS                                     | return from VIA SR interrupt

| ----------------------------------------------------------
| KBD_DATA_RECEIVED - Keyboard response byte received via VIA SR input
| Processes the raw byte: model number, keypad prefix, or key transition.
| Key encoding: bit 7 = transition (0=down, 1=up), bits [6:1] = key code,
| bit 0 = which key of pair (keyboards have 2-key rollover).
| Called during boot.
KBD_DATA_RECEIVED:
        ST      (KbdVers).w                     | mark that keyboard responded (version valid)
        MOVE.B  vSR(A1),D0                      | D0 = raw byte from keyboard shift register
        MOVE.B  D0,D3                           | D3 = save raw byte (bit 7 = key up/down)
        CMPI.B  #0x7B,D0                        | $7B = null response (no key pressed)
        BEQ.B   KBD_SEND_INQUIRY                | no key -> send next Inquiry command
        TST.B   (KbdLast).w                     | expecting model number response?
        BEQ.B   KBD_CHK_KEYPAD                  | no -> check for keypad prefix
        MOVE.B  D0,(KbdType).w                  | store keyboard model number (e.g. 3=M0110A)
        CLR.B   (KbdLast).w                     | clear "awaiting model" flag
        BRA.B   KBD_SEND_INQUIRY                | send Inquiry to start polling for keys
| ----------------------------------------------------------
| KBD_CHK_KEYPAD -- check if received byte is keypad prefix ($79)
| Mac keyboard sends $79 before each numeric keypad key code.
KBD_CHK_KEYPAD:
        CMPI.B  #0x79,D0                        | $79 = keypad prefix byte
        BNE.B   KBD_PROCESS_KEY                 | not keypad prefix: process as key transition
        ST      (KbdVars_1).w                   | flag: next key byte is from numeric keypad
        MOVEQ.L #0x14,D0                        | D0 = $14 = Instant command (get next byte now)
        BRA.B   KBD_SEND_CMD_JMP                | skip past Inquiry, send Instant via SR
| ----------------------------------------------------------
| KBD_SEND_INQUIRY -- load Inquiry command, then fall through to send.
| Inquiry asks the keyboard "what's next?" -- keyboard responds with
| either $7B (no key) or a key transition byte.
KBD_SEND_INQUIRY:
        MOVEQ.L #0x10,D0                        | D0 = $10 = Inquiry command (poll for next key)
KBD_SEND_CMD_JMP:                               | common send-via-SR
        BRA.W   KBD_SEND_CMD                    | branch to KBD_SEND_CMD ($155E)
KBD_PROCESS_KEY:
        MOVEQ.L #0x7F,D2                        | D2 = mask for bits [6:0]
        AND.B   D0,D2                           | strip transition bit (bit 7)
        LSR.B   #0x1,D2                         | D2 = raw key code (bits [6:1] >> 1)
        TST.B   (KbdVars_1).w                   | was keypad prefix ($79) received?
        BEQ.B   KBD_CHK_KEY_UP                  | no -> main keyboard key code
        ADDI    #0x40,D2                        | keypad keys: add $40 offset to key code
KBD_CHK_KEY_UP:
        TST.B   D3                              | test bit 7 of raw byte (key transition)
        BPL.B   KBD_TRANSLATE                   | bit 7 clear = key down -> skip
        MOVE    (KeyLast).w,D1                  | D1 = last key-down event message
        LSR     #0x8,D1                         | D1 = virtual key code of last key down
        CMP.B   D1,D2                           | same key being released?
        BNE.B   KBD_TRANSLATE                   | different key -> don't clear repeat
        CLR     (KeyLast).w                     | clear auto-repeat tracking (key released)
KBD_TRANSLATE:
        MOVE.L  D2,-(SP)                        | save raw key code
        BSR.B   UPDATE_KEYMAP                   | update KeyMap bitmap, call key translation proc
        MOVE.L  (SP)+,D2                        | D2 = raw key code (restored)
        LSL     #0x8,D2                         | shift key code to high byte of event message
        MOVE.B  D0,D2                           | D2 = (keyCode<<8) | ASCII character from trans
        BEQ.B   KBD_SEND_INQUIRY                | translation returned 0: no event, poll next key
        MOVEQ.L #0x4,D0                         | D0 = keyUpEvt (event code 4)
        TST.B   D3                              | check transition bit again
        BMI.B   KBD_DO_POST                     | bit 7 set = key up -> use keyUpEvt
        MOVEQ.L #0x3,D0                         | D0 = keyDwnEvt (event code 3)
        MOVE.L  (Ticks).w,(KeyTime).w           | record time of key-down for auto-repeat
        MOVE.L  (Ticks).w,(KeyRepTime).w        | initialize repeat timer
        MOVE    D2,(KeyLast).w                  | save event message for auto-repeat generation
KBD_DO_POST:
        MOVE.L  D0,A0                           | A0 = event code (used as mask by PostEvent)
        MOVE.L  D2,D0                           | D0 = event message (keyCode | charCode)
        _PostEvent                              | post keyDown/keyUp event
        BRA.B   KBD_SEND_INQUIRY                | send next Inquiry command to keyboard
UPDATE_KEYMAP:
        LEA.L     (KeyMap).w,A0                 | A0 = base of KeyMap bitmap
        MOVE    D2,D1                           | D1 = key code
        LSR     #0x3,D1                         | D1 = byte offset in KeyMap (key code / 8)
        ADDA.W  D1,A0                           | A0 = byte containing this key's bit
        BSET    D2,(A0)                         | set bit (key down); D2 mod 8 selects bit
        TST.B   D3                              | check transition direction
        BPL.B   KEYMAP_CHK_DIRECTION            | key down -> leave bit set
        BCLR    D2,(A0)                         | key up -> clear bit in KeyMap
KEYMAP_CHK_DIRECTION:
        MOVE.L  (Key1Trans).w,-(SP)             | push main keyboard translation proc
        TST.B   (KbdVars_1).w                   | keypad key?
        BEQ.B   KEYMAP_SEL_TRANS                | no -> use Key1Trans
        MOVE.L  (Key2Trans).w,(SP)              | replace with keypad translation proc
        CLR.B   (KbdVars_1).w                   | clear keypad flag (consumed)
KEYMAP_SEL_TRANS:
        MOVE    (KeyMap_6).w,D1                 | D1 = modifier key state word from KeyMap
        TST.L   (SP)                            | is translation proc installed?
        BNE.B   KEYMAP_CALL_TRANS               | yes -> call it (RTS pops to proc address)
        MOVE.L  (SP)+,D0                        | no proc -> D0 = 0 (nil), pop stack
KEYMAP_CALL_TRANS:
        RTS                                     | return to caller (@ $166E)
KybdTask:
        TST.B   (KbdVers).w                     | keyboard responded since last VBL?
        BNE.B   KYBDTASK_CLEAR_FLAG             | yes -> just clear flag and return
        CLR.B   (KbdType).w                     | clear stale keyboard model
        BSR.W   GetKeyboardModelNumber          | re-send Model command to detect keyboard
ZERO_KEYMAP:
        LEA.L     (KeyMap).w,A0                 | A0 = KeyMap base
        MOVEQ.L #0x8,D0                         | D0 = 8 (DBF loop count for 9 words)
KEYMAP_ZERO_LOOP:
        CLR     (A0)+                           | clear 2 bytes of KeyMap
        DBRA    D0,KEYMAP_ZERO_LOOP             | loop 9 times (18 bytes)
KYBDTASK_CLEAR_FLAG:
        CLR.B   (KbdVers).w                     | reset response flag for next VBL timeout check
        RTS                                     | return from VBL task
