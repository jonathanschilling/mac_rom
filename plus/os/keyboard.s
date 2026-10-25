| Keyboard driver -- InitKeyboard, keyboard interrupt, KybdTask
|
| Apple module KBDMNGR (the SE has the ADB Manager in its place). Talks to
| the keyboard through the VIA shift register: Model/Inquiry commands,
| key transition bytes (bit 7 = key up, $79 = keypad prefix), KeyMap
| update, key translation through Key1Trans/Key2Trans, keyDown/keyUp/
| autoKey events via _PostEvent, and KybdTask, the VBL task that polls the
| keyboard.
|
| References: Inside Macintosh Vol III, Ch 2: keyboard protocol;
| Inside Macintosh Vol I, Ch 8: keyboard events

| ----------------------------------------------------------
|
| InitKeyboard - Initialize keyboard subsystem
|
| Called during boot.
| Mac Plus keyboard uses Intel 8021 microcontroller, communicating via
| VIA shift register (SR). Mac sends command bytes, keyboard responds
| with key data. VIA ACR bits [4:2] control SR mode.
| Commands: $10=Inquiry (poll for key), $14=Instant (read immediately),
| $16=Model (get keyboard type), $36=Test (self-test).
InitKeyboard:
        CLR.B   (KbdType).w                     | clear keyboard model number
        CLR.L   (KbdVers).w                     | clear KbdVers + KbdVars_1
        BSR     ZERO_KEYMAP                     | zero the 18-byte KeyMap bitmap
        ST.B    (KbdVers).w                     | mark keyboard version as "needs query"
        LEA.L   VIAInt_KeyDataReady(PC),A0      | A0 = VIA SR interrupt handler
        MOVE.L  A0,(Lvl1DT_2).w                 | install VIA SR interrupt handler in Lvl1DT[2]
        CLR.L   (Key1Trans).w                   | clear primary key translation procedure ptr
        CLR.L   (Key2Trans).w                   | clear secondary key translation (keypad) ptr
        LEA.L   KybdTask(PC),A0                 | A0 = keyboard VBL task
        MOVE.L  A0,(JKybdTask).w                | install keyboard VBL polling task vector
| GetKeyboardModelNumber -- re-send Model command to detect keyboard.
GetKeyboardModelNumber:
        MOVE.L  (VIA).w,A1                      | A1 = VIA base address
        CLR.B   0x1800(A1)                      | PCR = 0: CB2 input mode (keyboard data in)
        MOVE.B  #0x87,0x1C00(A1)                | IER: enable SR interrupt + Timer 1 interrupt
        MOVEQ.L #0x16,D0                        | D0 = $16 = Model command (get keyboard type)
        ST.B    (KbdLast).w                     | flag: next SR byte is model number response

| Send command byte D0 to keyboard via VIA shift register
| Protocol: disable SR -> send sync pulse (0x00) -> load command byte
| VIA ACR bits [4:2]: 000=disabled, 011=shift out under ext CB1 clock,
| 111=shift out under internal Timer 2 clock
| Called during boot.
KBD_SEND_CMD:
        MOVE.L  (VIA).w,A1                      | A1 = VIA base address
        MOVE    SR,-(SP)                        | save processor status (interrupt mask)
        ORI     #0x300,SR                       | disable all interrupts during SR manipulation
        MOVE.B  0x1600(A1),D1                   | D1 = current ACR value
        ANDI.B  #0xE3,D1                        | clear SR control bits [4:2] = 000 (SR disabled)
        MOVE    D1,-(SP)                        | save ACR-with-SR-disabled on stack
        MOVE.B  D1,0x1600(A1)                   | write ACR: SR disabled
        CLR.B   0x1400(A1)                      | clear SR data register (preparation)
        ORI.B   #0x18,D1                        | set bits [4:3] = 11: shift out under ext clock
        MOVE.B  D1,0x1600(A1)                   | write ACR: begin shift out mode
        CLR.B   0x1400(A1)                      | load SR=0, clocks out sync/attention pulse
        NOP                                     | brief delay for keyboard to recognize sync
        MOVE    (SP)+,D1                        | restore ACR-with-SR-disabled
        MOVE.B  D1,0x1600(A1)                   | write ACR: SR disabled again (end sync pulse)
        ORI.B   #0x1C,D1                        | set bits [4:2] = 111: shift out under T2 clock
        MOVE.B  D1,0x1600(A1)                   | write ACR: shift out under internal clock
        MOVE.B  D0,0x1400(A1)                   | load command byte into SR; clocked to keyboard
        MOVE    (SP)+,SR                        | restore processor interrupt state
        RTS                                     | return from KBD_SEND_CMD

| ----------------------------------------------------------
|
| VIAInt_KeyDataReady - VIA SR interrupt: keyboard sent response data
| Called when VIA shift register completes a byte transfer.
| If Mac was transmitting (ACR bit 4 set), this is command-done;
| wait for keyboard to prepare response, then switch SR to input mode.
| If Mac was receiving (ACR bit 4 clear), read the response byte.
|
| Called during boot.
VIAInt_KeyDataReady:
        BTST    #0x4,0x1600(A1)                 | ACR bit 4: SR shifting out? (command phase)
        BEQ.B   KBD_DATA_RECEIVED               | no -> receiving phase, go read response byte
| Command byte just finished transmitting; wait ~330us for keyboard to prepare
        MOVE.B  #0x4,0x1A00(A1)                 | IFR: clear SR interrupt flag
        MOVE    #0xC8,D0                        | D0 = 200 (loop count for ~330us delay on 68000)
        TST.B   (CPUFlag).w                     | 68000 or 68020?
        BEQ.B   KBD_SEND_DELAY                  | 68000 -> use base count
        LSL     #0x3,D0                         | 68020: multiply by 8 (faster CPU needs more loops)
KBD_SEND_DELAY:
        DBF     D0,KBD_SEND_DELAY               | spin-wait delay loop
        BCLR    #0x4,0x1600(A1)                 | clear ACR bit 4: switch SR to input (shift in)
        MOVE.B  0x1400(A1),D0                   | dummy read of SR to start receiving keyboard data
        RTS                                     | return from KBD_SEND_DELAY

| ----------------------------------------------------------
|
| KBD_DATA_RECEIVED - Keyboard response byte received via VIA SR input
| Processes the raw byte: model number, keypad prefix, or key transition.
| Key encoding: bit 7 = transition (0=down, 1=up), bits [6:1] = key code,
| bit 0 = which key of pair (keyboards have 2-key rollover).
|
| Called during boot.
KBD_DATA_RECEIVED:
        ST.B    (KbdVers).w                     | mark that keyboard responded (version valid)
        MOVE.B  0x1400(A1),D0                   | D0 = raw byte from keyboard shift register
        MOVE.B  D0,D3                           | D3 = save raw byte (bit 7 = key up/down)
        CMPI.B  #0x7B,D0                        | $7B = null response (no key pressed)
        BEQ.B   KBD_SEND_INQUIRY                | no key -> send next Inquiry command
        TST.B   (KbdLast).w                     | expecting model number response?
        BEQ.B   KBD_CHK_KEYPAD                  | no -> check for keypad prefix
        MOVE.B  D0,(KbdType).w                  | store keyboard model number (e.g. 3=M0110A)
        CLR.B   (KbdLast).w                     | clear "awaiting model" flag
        BRA.B   KBD_SEND_INQUIRY                | send Inquiry to start polling for keys

| ----------------------------------------------------------
|
| KBD_CHK_KEYPAD - check if byte is keypad prefix ($79)
| Mac Plus keyboard sends $79 before each numeric keypad key code.
|
KBD_CHK_KEYPAD:
        CMPI.B  #0x79,D0                        | $79 = keypad prefix byte
        BNE.B   KBD_PROCESS_KEY                 | not keypad prefix -> process as key transition
        ST.B    (KbdVars_1).w                   | flag: next key byte is from numeric keypad
        MOVEQ.L #0x14,D0                        | D0 = $14 = Instant command (get next byte now)
        BRA.B   KBD_SEND_CMD_JMP                | send Instant to immediately read keypad key code

| ----------------------------------------------------------
|
| KBD_SEND_INQUIRY - send Inquiry command to poll keyboard for next key event
|
| Called during boot.
KBD_SEND_INQUIRY:
        MOVEQ.L #0x10,D0                        | D0 = $10 = Inquiry command (poll for key)
KBD_SEND_CMD_JMP:
        BRA     KBD_SEND_CMD                    | send command byte D0 to keyboard

| ----------------------------------------------------------
|
| KBD_PROCESS_KEY - Process a key transition byte from keyboard
| Raw byte format: bit 7=transition (0=down,1=up), bits[6:1]=keyCode, bit 0=pair
| Extracts 7-bit virtual key code, applies keypad offset, translates via KCHR,
| then posts key-down (event 3) or key-up (event 4) to the event queue.
|
KBD_PROCESS_KEY:
        MOVEQ.L #0x7F,D2                        | D2 = mask for bits [6:0]
        AND.B   D0,D2                           | strip transition bit (bit 7)
        LSR.B   #0x1,D2                         | D2 = raw key code (bits [6:1] >> 1)
        TST.B   (KbdVars_1).w                   | was keypad prefix ($79) received?
        BEQ.B   KBD_CHK_KEY_UP                  | no -> main keyboard key code
        ADDI    #0x40,D2                        | keypad keys: add $40 offset to key code
KBD_CHK_KEY_UP:
| If key-up and matches last key-down, clear auto-repeat state
        TST.B   D3                              | test bit 7 of raw byte (key transition)
        BPL.B   KBD_TRANSLATE                   | bit 7 clear = key down -> skip
        MOVE    (KeyLast).w,D1                  | D1 = last key-down event message
        LSR     #0x8,D1                         | D1 = virtual key code of last key down
        CMP.B   D1,D2                           | same key being released?
        BNE.B   KBD_TRANSLATE                   | different key -> don't clear repeat
        CLR     (KeyLast).w                     | clear auto-repeat tracking (key released)
KBD_TRANSLATE:
| Translate raw key code through Key1Trans/Key2Trans procedure
        MOVE.L  D2,-(SP)                        | save raw key code
        BSR.B   UPDATE_KEYMAP                   | update KeyMap bitmap, call key translation proc
        MOVE.L  (SP)+,D2                        | D2 = raw key code (restored)
        LSL     #0x8,D2                         | shift key code to high byte of event message
        MOVE.B  D0,D2                           | D2 = (keyCode<<8) | ASCII character from trans
        BNE.B   KBD_POST_EVENT                  | got a character -> post event
| Translation returned 0: check screen dump (Cmd-Shift-3) state
        MOVE.B  (ScrDmpType).w,D0               | screen dump enable flag
        BMI.B   KBD_SEND_INQUIRY                | $FF = dump already in progress -> ignore
        ST.B    (ScrDmpType).w                  | mark dump in progress
        MOVE.B  D0,D2                           | D2 = previous ScrDmpType value as event msg
KBD_POST_EVENT:
| Post the key event
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

| ----------------------------------------------------------
|
| UPDATE_KEYMAP - Update KeyMap bitmap and call key translation procedure
| In: D2 = virtual key code (0-127), D3 = raw byte (bit 7 = up/down)
| Out: D0 = translated ASCII character (0 if no translation proc)
| KeyMap is a 16-byte (128-bit) bitmap of currently-pressed keys.
| Key1Trans = main keyboard translation proc, Key2Trans = keypad proc.
|
UPDATE_KEYMAP:
        LEA.L   (KeyMap).w,A0                   | A0 = base of KeyMap bitmap
        MOVE    D2,D1                           | D1 = key code
        LSR     #0x3,D1                         | D1 = byte offset in KeyMap (key code / 8)
        ADDA    D1,A0                           | A0 = byte containing this key's bit
        BSET    D2,(A0)                         | set bit (key down); D2 mod 8 selects bit
        TST.B   D3                              | check transition direction
        BPL.B   KEYMAP_CHK_DIRECTION            | key down -> leave bit set
        BCLR    D2,(A0)                         | key up -> clear bit in KeyMap
KEYMAP_CHK_DIRECTION:
| Select translation procedure: Key2Trans for keypad, Key1Trans for main kbd
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
        RTS                                     | returns to translation proc or to caller

| ----------------------------------------------------------
|
| KybdTask - Keyboard VBL polling task
| Called every VBL (~16.6ms). If keyboard hasn't responded since last poll
| (KbdVers=0), assumes keyboard was disconnected: re-queries model number
| and resets KeyMap. Each successful keyboard response sets KbdVers=$FF;
| this task clears it to detect timeout on next VBL.
|
| Called during boot.
KybdTask:
        TST.B   (KbdVers).w                     | keyboard responded since last VBL?
        BNE.B   KYBDTASK_CLEAR_FLAG             | yes -> just clear flag and return
| Keyboard timeout -- re-initialize and re-query model number
        CLR.B   (KbdType).w                     | clear stale keyboard model
        BSR     GetKeyboardModelNumber          | re-send Model command to detect keyboard
| ZERO_KEYMAP -- zero the 18-byte KeyMap bitmap.
ZERO_KEYMAP:
| Zero the 18-byte KeyMap bitmap (9 words = 128 key bits + padding)
        LEA.L   (KeyMap).w,A0                   | A0 = KeyMap base
        MOVEQ.L #0x8,D0                         | D0 = 8 (DBF loop count for 9 words)
KEYMAP_ZERO_LOOP:
        CLR     (A0)+                           | clear 2 bytes of KeyMap
        DBF     D0,KEYMAP_ZERO_LOOP             | loop 9 times (18 bytes)
KYBDTASK_CLEAR_FLAG:
        CLR.B   (KbdVers).w                     | reset response flag for next VBL timeout check
        RTS                                     | return from KYBDTASK_CLEAR_FLAG

