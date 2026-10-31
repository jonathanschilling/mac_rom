| Apple Desktop Bus Manager and keyboard
|
| Apple source: ADBMgr.a (MacSEROM.lst module KBDMNGR; System 7.1:
| OS/ADBMgr/ADBMgr.a). The SE talks to the keyboard and the mouse over
| ADB through the VIA shift register and port B (ST0/ST1 state lines):
| INITADB (bus reset, device table), FDBSHIFTINT (the shift-register
| interrupt that runs the ADB transaction state machine), ADBOP ($A07C),
| ADBREINIT ($A07B), INITADBDRVR, COUNTADBS ($A077), GETINDADB ($A078),
| GETADBINFO ($A079), SETADBINFO ($A07A), the keyboard and mouse
| handlers, and KEYTRANS ($A9C3: key code -> character through the KCHR).
|
| References: Inside Macintosh Vol V, Ch 20 (The Apple Desktop Bus);
| Mac Plus tree: os/keyboard.s (the Plus keyboard driver).

| INITADB - Keyboard/ADB Manager initialization
|
| Initializes the ADB-based keyboard driver for the SE. Sets up
| the JKybdTask vector, configures VIA shift register for ADB
| communication, and initiates the ADB device scan.
KBDMNGR:                                        | Apple source module (MacSEROM.lst)
INITADB:
    CLR.B       (KbdType).W                     | clear keyboard type (unknown)
    BSR.W       ZERO_KEYMAP                     | init ADB hardware state
    MOVEA.L     (ADBBase).W,A3                  | A3 = ADB manager globals base
    LEA.L       P_KybdTask(PC),A0               | A0 = keyboard VBL task handler
    MOVE.L      A0,(JKybdTask).W                | install keyboard task vector
    MOVEA.L     (VIA).W,A1                      | A1 = VIA base
    CLR.B       0x1800(A1)                      | vSR = 0: clear shift register
    MOVE.B      #0x84,0x1C00(A1)                | vACR: SR out under ext clock (ADB)
    MOVE.B      0x400(A1),D0                    | D0 = VIA data direction reg A
    ORI.B       #0x30,D0                        | set bits 4-5: ADB state output
    MOVE.B      D0,0x400(A1)                    | write back DDRA
| ADB_BUS_SCAN - ADB bus scan and device initialization
ADB_BUS_SCAN:
    BSET        #0x2,0x15D(A3)                  | set ADB state: scan in progress
    LEA.L       0xC0(A3),A0                     | A0 = ADB device table base
    MOVE.L      A0,0x13C(A3)                    | init ADB completion handler ptr
    MOVE.L      A0,0x144(A3)                    | init ADB response buffer ptr
    MOVE.L      A0,0x148(A3)                    | init ADB device list ptr
    LEA.L       0x130(A3),A0                    | A0 = ADB command block base
    MOVE.L      A0,0x140(A3)                    | init ADB command buffer ptr
    BSET        #0x5,0x15D(A3)                  | set ADB state: init pending
    BSR.B       ADB_SCAN_DEVICE                 | start ADB device scan
    ANDI.W      #0xF8FF,SR                      | lower IPL to 0 (enable interrupts)
ADB_INIT_WAIT:
    BTST        #0x5,0x15D(A3)                  | ADB init still pending?
    BNE.B       ADB_INIT_WAIT                   | yes: spin until complete
    JSR         ADB_ENSURE_MOUSE(PC)            | identify ADB keyboard type
    JSR         INSTALL_KCHR_KMAP(PC)           | configure key repeat parameters
    RTS                                         | return from INITADB
| ADB_SCAN_DEVICE - start ADB bus scan (Talk Reg 0 to all 16 addresses)
|
| Initializes the ADB command block and begins scanning all 16 ADB
| addresses with Talk Register 0 commands. The PIC microcontroller
| handles the actual ADB bus timing; the 68000 drives the protocol
| via VIA PB4/PB5 (ST0/ST1 state bits) and shift register (CB1/CB2).
|
| ADB globals layout at (A3) = ADBBase:
|   +$C0:  device table (12 bytes/entry: handler_id, orig_addr, cur_addr, pad, handler_ptr)
|   +$130: command data block pointer
|   +$134: completion callback pointer
|   +$13C-$148: buffer/list pointers
|   +$14C: device present bitmap (16 bits for addresses 0-15)
|   +$15C: ADB command/state byte (bits 2-3 = cmd type, 4-5 = ST state)
|   +$15D: ADB flags (bit 0=active, bit 2=scanning, bit 5=init pending)
|   +$15E: phase/control flags (bit 1=error/timeout)
|   +$161: device table write offset
|   +$162: retry counter
|   +$163: frame length (max response bytes)
|   +$164+: ADB command/data buffer
|   +$165: first response byte
|   +$16C: current ADB address being scanned (0-15)
ADB_SCAN_DEVICE:
    LEA.L       0x164(A3),A0                    | A0 = ADB command data buffer
    MOVE.L      A0,0x130(A3)                    | set command block pointer
    LEA.L       ADB_NEXT_ADDRESS(PC),A0         | A0 = scan callback
    MOVE.L      A0,0x134(A3)                    | set completion callback
    CLR.B       D0                              | D0 = 0 (Talk Reg 0, address 0)
    MOVE.B      D0,0x15C(A3)                    | ADB command = Talk Reg 0 to addr 0
    MOVE.B      #0x8,0x163(A3)                  | max frame length = 8 bytes
    MOVE.B      #0x30,0x15E(A3)                 | phase flags = 0x30 (ST1:ST0 = 11)
    BSR.W       ADB_KICK_PIC                    | set VIA state bits for ADB
    BSR.W       ADB_STATE0_IDLE                 | start ADB transaction via PIC
    RTS                                         | return (scan continues via callbacks)
| ADB_NEXT_ADDRESS - ADB scan callback: issue Talk Reg 0 to next address
|
| Called by the VIA shift interrupt after PIC completes a Talk command.
| Advances to next ADB address, issues Talk Reg 0 via ADB_TALK_REG3.
ADB_NEXT_ADDRESS:
    LEA.L       ADB_RECORD_DEVICE(PC),A0        | A0 = response handler callback
    MOVE.B      0x16C(A3),D0                    | D0 = current ADB address
    BSR.W       ADB_TALK_REG3                   | issue Talk Reg 0 to address D0
    RTS                                         | return (response via ADB_RECORD_DEVICE)
| ADB_RECORD_DEVICE - process Talk Reg 0 response during scan
|
| If device responded (no error), records it in the device table:
| handler_id, original address, current address, and installs the
| appropriate handler (keyboard=addr 2, mouse=addr 3).
ADB_RECORD_DEVICE:
    BTST        #0x1,0x15E(A3)                  | ADB error/timeout? (no response)
    BNE.B       ADB_SCAN_NEXT_ADDR              | yes: skip to next address
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.B      0x161(A3),D1                    | D1 = device table write offset
    MOVE.B      0x165(A3),D0                    | D0 = first response byte (handler ID)
    MOVE.B      D0,0x0(A3,D1.W)                 | devtbl[n].handler_id = handler ID
    MOVE.B      0x16C(A3),D0                    | D0 = device ADB address
    MOVE.B      D0,0x1(A3,D1.W)                 | devtbl[n].orig_addr = address
    MOVE.B      D0,0x2(A3,D1.W)                 | devtbl[n].cur_addr = address
    CMPI.B      #0x2,D0                         | keyboard (default address 2)?
    BNE.B       ADB_RECORD_NOT_KBD              | no: check mouse
    LEA.L       ADB_HANDLER_KBD(PC),A0          | A0 = keyboard handler routine
    MOVE.L      A0,0x4(A3,D1.W)                 | devtbl[n].handler = keyboard handler
ADB_RECORD_NOT_KBD:
    CMPI.B      #0x3,D0                         | mouse (default address 3)?
    BNE.B       ADB_RECORD_AFTER_HANDLER        | no: use default handler
    LEA.L       ADB_HANDLER_MOUSE(PC),A0        | A0 = mouse handler routine
    MOVE.L      A0,0x4(A3,D1.W)                 | devtbl[n].handler = mouse handler
ADB_RECORD_AFTER_HANDLER:
    ADDI.W      #0xC,D1                         | advance to next device table entry
    MOVE.B      D1,0x161(A3)                    | update device table write offset
    MOVE.W      0x14C(A3),D2                    | D2 = device present bitmap
    BSET        D0,D2                           | set bit for this ADB address
    MOVE.W      D2,0x14C(A3)                    | update device present bitmap
| Advance to next ADB address (0 through 15)
ADB_SCAN_NEXT_ADDR:
    MOVE.B      0x16C(A3),D0                    | D0 = current address
    ADDQ.W      #0x1,D0                         | advance to next address
    MOVE.B      D0,0x16C(A3)                    | store updated address
    CMPI.B      #0x10,D0                        | scanned all 16 addresses?
    BNE.B       ADB_NEXT_ADDRESS                | no: scan next address
| All addresses scanned: begin address conflict resolution
    MOVE.W      0x14C(A3),D0                    | D0 = device present bitmap
    BEQ.B       ADB_SCAN_DONE                   | no devices found: finish scan
    MOVE.W      D0,0x14E(A3)                    | save bitmap for resolution
| Address conflict resolution: move colliding devices to free addresses
ADB_RESOLVE_CONFLICTS:
    ST.B        0x16C(A3)                       | set address to 0xFF (pre-increment)
ADB_RESOLVE_LOOP:
    ADDQ.B      #0x1,0x16C(A3)                  | advance to next candidate address
    BSR.W       ADB_FIND_FREE_FWD               | find next free ADB address
    BPL.B       ADB_RESOLVE_DO_MOVE             | found free address: relocate device
    MOVE.B      0x162(A3),D0                    | D0 = retry counter
    ADDQ.W      #0x1,D0                         | increment retries
    MOVE.B      D0,0x162(A3)                    | update retry counter
    CMPI.B      #0x32,D0                        | tried 50 times?
    BNE.B       ADB_RESOLVE_CONFLICTS           | no: retry
    BRA.B       ADB_SCAN_DONE                   | give up: finish scan
ADB_RESOLVE_DO_MOVE:
    BSR.W       ADB_FIND_OCCUPIED_REV           | find device at conflicting address
    BMI.B       ADB_SCAN_DONE                   | no device: finish scan
    LEA.L       ADB_MOVE_COMPLETE(PC),A0        | A0 = move-completion callback
    MOVE.B      D0,0x16D(A3)                    | target address for device move
    MOVE.B      D0,D1                           | D1 = target address
    MOVE.B      0x16C(A3),D0                    | D0 = source address
    BSR.W       ADB_LISTEN_REG3                 | issue ADB Move command (src -> target)
    RTS                                         | return (move continues via callback)
| ADB_SCAN_DONE - scan complete: set up idle polling
ADB_SCAN_DONE:
    MOVE.B      #0x3C,0x15C(A3)                 | ADB cmd = Talk Reg 0, addr 15 (idle poll)
    LEA.L       ADB_HANDLER_MOUSE(PC),A0        | A0 = default polling handler
    MOVE.L      A0,0x134(A3)                    | set idle polling callback
    JSR         ADB_EXEC_COMMAND(PC)            | start idle ADB polling loop
    BCLR        #0x5,0x15D(A3)                  | clear init-pending flag
    RTS                                         | return (ADB scan complete)
| ADB_MOVE_COMPLETE - ADB Move command completion: verify move succeeded
|
| After moving a device to a new address, Talk the new address to
| confirm the device responds there. If successful, update device table.
ADB_MOVE_COMPLETE:
    LEA.L       ADB_MOVE_TALK_NEW(PC),A0        | A0 = verify-response callback
    MOVE.B      0x16C(A3),D0                    | D0 = source address
    BRA.W       ADB_TALK_REG3                   | Talk Reg 0 at source (should be empty)
ADB_MOVE_TALK_NEW:
    BTST        #0x1,0x15E(A3)                  | move succeeded? (no error = device gone)
    BNE.B       ADB_MOVE_RETRY                  | error: device still at old address, retry
    BSR.B       ADB_UPDATE_DEVTBL               | update device table with new address
    MOVE.B      0x165(A3),0x0(A3,D1.W)          | store new handler ID in device table
    BRA.B       ADB_RESOLVE_LOOP                | continue scanning for more conflicts
| Move failed: retry with different target address
ADB_MOVE_RETRY:
    LEA.L       ADB_MOVE_NEXT_ADDR(PC),A0       | A0 = retry callback
    MOVE.B      0x16C(A3),D1                    | D1 = current address (data byte)
    MOVE.B      0x16D(A3),D0                    | D0 = target address
    BRA.W       ADB_LISTEN_REG3                 | issue Listen Reg 3 (ADB Move cmd)
ADB_MOVE_NEXT_ADDR:
    LEA.L       ADB_MOVE_RESCAN(PC),A0          | A0 = verify callback after retry
    MOVE.B      0x16D(A3),D0                    | D0 = target address
    BRA.B       ADB_TALK_REG3                   | Talk Reg 0 to verify move
ADB_MOVE_RESCAN:
    BTST        #0x1,0x15E(A3)                  | verify succeeded?
    BNE.B       ADB_MOVE_RESCAN_RTS             | no: give up on this device
    BSR.B       ADB_UPDATE_DEVTBL               | update device table
    MOVE.B      0x165(A3),-0xC(A3,D2.W)         | store handler ID in prev entry
ADB_MOVE_RESCAN_RTS:
    BRA.W       ADB_RESOLVE_LOOP                | continue conflict resolution
| ADB_UPDATE_DEVTBL - update device table after successful ADB Move
|
| Marks new address as present in bitmap, finds device entry by
| source address, copies entry to new slot, updates current address.
ADB_UPDATE_DEVTBL:
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.B      0x16D(A3),D0                    | D0 = new (target) address
    MOVE.W      0x14E(A3),D1                    | D1 = device present bitmap
    BSET        D0,D1                           | mark new address as present
    MOVE.W      D1,0x14E(A3)                    | update bitmap
    MOVEQ.L     #0x0,D1                         | D1 = 0 (device table scan offset)
    MOVE.B      0x16C(A3),D0                    | D0 = source address
| Search device table for entry with matching current address
ADB_FIND_DEVICE_LOOP:
    CMP.B       0x2(A3,D1.W),D0                 | devtbl[n].cur_addr == source?
    BEQ.B       ADB_FIND_DEVICE_FOUND           | found: copy entry
    ADDI.W      #0xC,D1                         | advance to next entry (12 bytes)
    BRA.B       ADB_FIND_DEVICE_LOOP            | keep searching
ADB_FIND_DEVICE_FOUND:
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.B      0x161(A3),D2                    | D2 = device table write offset (new slot)
    MOVE.L      0x0(A3,D1.W),D3                 | copy handler_id + addresses
    MOVE.L      D3,0x0(A3,D2.W)                 | to new slot
    MOVE.L      0x4(A3,D1.W),D3                 | copy handler ptr
    MOVE.L      D3,0x4(A3,D2.W)                 | to new slot
    MOVE.B      0x16D(A3),D0                    | D0 = new address
    MOVE.B      D0,0x2(A3,D2.W)                 | update cur_addr in new slot
    ADDI.W      #0xC,D2                         | advance write offset past new entry
    MOVE.B      D2,0x161(A3)                    | store updated write offset
    RTS                                         | return from ADB_UPDATE_DEVTBL
| ADB_TALK_REG3 - issue ADB Talk Register 0 command
|
| Builds Talk Reg 0 command byte (addr << 4 | 0x0F = Talk Reg 3),
| sets up completion callback, and initiates ADB transaction via PIC.
| Entry: D0 = ADB device address (0-15), A0 = completion callback
| ADB command byte: [addr:4][11:2][reg:2] = addr<<4 | 0x0F = Talk Reg 3
| (Note: 0x0F = Talk Reg 3; Talk Reg 0 would be 0x0C)
ADB_TALK_REG3:
    MOVE.L      A0,0x134(A3)                    | set completion callback
    LSL.B       #0x4,D0                         | D0 = address << 4
    ORI.B       #0xF,D0                         | D0 |= 0x0F (Talk Reg 3)
    MOVE.B      D0,0x15C(A3)                    | set ADB command byte
    MOVE.B      #0x8,0x163(A3)                  | max response = 8 bytes
    MOVE.B      #0x30,0x15E(A3)                 | phase flags = 0x30 (ST1:ST0 = 11)
    BSR.W       ADB_KICK_PIC                    | set VIA state bits
    BSR.W       ADB_STATE0_IDLE                 | start ADB transaction via PIC
    RTS                                         | return (response via callback)
| ADB_LISTEN_REG3 - issue ADB Listen Register 3 command (Move device)
|
| Sends Listen Reg 3 with 2-byte data (new_addr, 0xFE) to relocate
| an ADB device from its current address to a new one.
| Entry: D0 = device address, D1 = new address data, A0 = callback
| ADB command byte: addr<<4 | 0x0B = Listen Reg 3
ADB_LISTEN_REG3:
    MOVE.L      A0,0x134(A3)                    | set completion callback
    MOVE.B      D1,0x164(A3)                    | data byte 0 = new address
    MOVE.B      #0xFE,0x165(A3)                 | data byte 1 = 0xFE (move command)
    LSL.B       #0x4,D0                         | D0 = address << 4
    ORI.W       #0xB,D0                         | D0 |= 0x0B (Listen Reg 3)
    MOVE.B      D0,0x15C(A3)                    | set ADB command byte
    MOVE.B      #0x8,0x163(A3)                  | max response = 8 bytes
    MOVE.B      #0x30,0x15E(A3)                 | phase flags = 0x30
    BSR.W       ADB_KICK_PIC                    | set VIA state bits
    BSR.W       ADB_STATE0_IDLE                 | start ADB transaction via PIC
    RTS                                         | return (response via callback)
| ADB_FIND_FREE_FWD - find next free ADB address for device relocation
|
| Scans the device present bitmap for an address that's not yet used.
| Returns: D0 = free address (N clear), or N set if none free
ADB_FIND_FREE_FWD:
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.B      0x16C(A3),D0                    | D0 = current scan address
    MOVE.W      0x14E(A3),D1                    | D1 = device present bitmap
| Scan bitmap starting from current address
ADB_FIND_FREE_FWD_LOOP:
    BTST        D0,D1                           | address D0 in use? (bit set)
    BNE.B       ADB_FIND_FREE_FWD_RTS           | yes (occupied): this is free target
    ADDQ.W      #0x1,D0                         | try next address
    CMPI.W      #0x10,D0                        | past address 15?
    BLT.B       ADB_FIND_FREE_FWD_LOOP          | no: keep scanning
    MOVEQ.L     #-0x1,D0                        | no free address found (N set)
    RTS                                         | return with N set
ADB_FIND_FREE_FWD_RTS:
    MOVE.B      D0,0x16C(A3)                    | store free address for move target
    RTS                                         | return with N clear
| ADB_FIND_OCCUPIED_REV - find highest occupied ADB address (for conflict scan)
|
| Scans bitmap from address 15 downward to find the first occupied slot.
| Returns: D0 = address (N clear if found), N set if none
ADB_FIND_OCCUPIED_REV:
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVEQ.L     #0xF,D0                         | D0 = 15 (start from highest)
    MOVE.W      0x14E(A3),D1                    | D1 = device present bitmap
ADB_FIND_OCCUPIED_REV_LOOP:
    BTST        D0,D1                           | address D0 occupied?
    BEQ.B       ADB_FIND_OCCUPIED_REV_RTS       | yes (bit clear): found conflicting
    SUBQ.W      #0x1,D0                         | try next lower address
    BPL.B       ADB_FIND_OCCUPIED_REV_LOOP      | more addresses: keep scanning
ADB_FIND_OCCUPIED_REV_RTS:
    RTS                                         | return D0 = address or N set
| P_KybdTask - keyboard VBL task (stub, actual processing via ADB)
P_KybdTask:
    RTS                                         | return (no-op on SE)
| FDBSHIFTINT - VIA shift register interrupt handler (ADB protocol)
|
| Called when the PIC microcontroller clocks a byte via CB1/CB2.
| This is the core ADB state machine that manages byte-level
| transactions between the 68000 and the PIC ADB controller.
|
| The PIC uses CB1 (SCLK) rising edges to shift data through CB2 (DIO).
| VIA port B bits 4-5 (ST0/ST1) tell the PIC what state to enter:
|   ST1:ST0 = 00: receive command byte from VIA
|   ST1:ST0 = 01: PIC sends byte + error status
|   ST1:ST0 = 10: PIC sends byte + SRQ status
|   ST1:ST0 = 11: null state (idle)
|
| ADB command byte ($15C) bits 2-3 select the transaction type:
|   0x08/0x0C = send command (PIC->ADB bus)
|   0x04/0x00 = receive response (ADB bus->PIC->VIA)
FDBSHIFTINT:
    MOVE.B      #0x4,0x1A00(A1)                 | clear VIA IFR bit 2 (SR interrupt)
    MOVEA.L     (ADBBase).W,A3                  | A3 = ADB globals base
    MOVE.B      0x15C(A3),D0                    | D0 = ADB command/state byte
    ANDI.B      #0xC,D0                         | extract bits 2-3 (command type)
    CMPI.B      #0x8,D0                         | command type = send (0x08)?
    BEQ.B       ADB_SEND_BYTE                   | yes: handle send path
    CMPI.B      #0xC,D0                         | command type = send (0x0C)?
    BEQ.B       ADB_SEND_BYTE                   | yes: handle send path
| Receive path: PIC is sending data to 68000 via VIA SR
    BTST        #0x0,0x15F(A3)                  | transaction in progress?
    BNE.B       ADB_RECV_VIA_SR                 | yes: receive next byte
    BTST        #0x5,0x15D(A3)                  | init/scan pending?
    BNE.W       ADB_CALL_COMPLETION_DO          | yes: handle scan response
    BRA.W       ADB_NEXT_POLL                   | no: handle normal response
| Send path: 68000 sends command/data byte to PIC via VIA SR
ADB_SEND_BYTE:
    BTST        #0x0,0x15F(A3)                  | transaction in progress?
    BEQ.W       ADB_BEGIN_SEND                  | no: start new transaction
    BTST        #0x3,(A1)                       | VIA port A bit 3: PIC INT asserted?
    BNE.B       ADB_RECV_BYTE                   | yes: PIC has response/status
| PIC not ready: send next command byte
    BSET        #0x0,0x15E(A3)                  | set command-phase flag
    BSR.W       ADB_QUEUE_PREEMPT               | load next data byte into VIA SR
    BSR.W       ADB_QUEUE_RESTORE               | set ST0/ST1 to advance PIC state
    BCLR        #0x7,0x15E(A3)                  | clear response-pending flag
    BRA.B       ADB_PHASE_DISPATCH              | continue
| PIC asserted INT: read response byte from VIA SR
ADB_RECV_BYTE:
    BTST        #0x7,0x15E(A3)                  | expecting response byte?
    BEQ.B       ADB_PHASE_DISPATCH              | no: skip read
    BCLR        #0x4,0x1600(A1)                 | clear VIA ACR bit 4 (SR input mode)
    MOVE.B      0x1400(A1),D0                   | D0 = byte from VIA SR (PIC data)
    BSR.W       ADB_STATE3_NULL                 | store byte in ADB response buffer
    BCLR        #0x0,0x15D(A3)                  | clear transaction-active flag
    MOVE.B      #0x30,0x15E(A3)                 | reset phase to ST1:ST0 = 11 (idle)
    CLR.B       0x160(A3)                       | clear byte counter
    BCLR        #0x0,0x15D(A3)                  | clear active (redundant)
    RTS                                         | return from shift interrupt
| ADB_PHASE_DISPATCH - send phase: write or read VIA SR based on cmd direction
ADB_PHASE_DISPATCH:
    BTST        #0x2,0x15C(A3)                  | cmd bit 2: send direction? (Talk=read)
    BEQ.B       ADB_SEND_VIA_SR                 | bit clear: write cmd byte to PIC
| Read byte from PIC via VIA SR (Talk response)
ADB_RECV_VIA_SR:
    BCLR        #0x4,0x1600(A1)                 | VIA ACR bit 4: set SR to input mode
    MOVE.B      0x1400(A1),D0                   | D0 = byte from VIA SR
    CLR.B       0x160(A3)                       | clear byte counter
    BRA.B       ADB_SEND_VIA_SR_GO              | advance state
| Write command/data byte to PIC via VIA SR
ADB_SEND_VIA_SR:
    MOVEA.L     0x130(A3),A0                    | A0 = command data block pointer
    MOVE.B      (A0),0x1400(A1)                 | write byte to VIA SR -> PIC
    MOVE.B      #0x1,0x160(A3)                  | set byte counter = 1 (sent)
ADB_SEND_VIA_SR_GO:
    BSR.W       ADB_STATE1_BUSY                 | set VIA ACR for next SR direction
    BSET        #0x4,0x15E(A3)                  | set phase flag: byte transferred
    BSET        #0x5,0x15E(A3)                  | set phase flag: SR active
    RTS                                         | return from shift interrupt
| ADB_BEGIN_SEND - start new send transaction (no prior state)
ADB_BEGIN_SEND:
    BTST        #0x1,0x15F(A3)                  | send pending? (from prior cmd)
    BEQ.B       ADB_RECV_PATH                   | no: check receive path
    BTST        #0x3,(A1)                       | PIC INT asserted? (PB3)
    BNE.B       ADB_AFTER_SEND                  | yes: PIC ready for next byte
    BTST        #0x4,0x15E(A3)                  | byte already transferred?
    BEQ.W       VIAInt_KeyDataReady             | no: spurious interrupt
    BSET        #0x1,0x15E(A3)                  | set error/timeout flag
    BTST        #0x5,0x15D(A3)                  | init/scan pending?
    BNE.B       ADB_CALL_COMPLETION_DO          | yes: call scan callback
| ADB_AFTER_SEND - PIC INT received: process response after send
ADB_AFTER_SEND:
    BCLR        #0x4,0x15E(A3)                  | clear byte-transferred flag
    BSR.W       ADB_NEXT_BYTE                   | read response + check for more data
    BEQ.W       ADB_NEXT_POLL                   | no more data: start idle poll
    BSR.W       ADB_STATE2_RECV                 | more data: continue transaction
    RTS                                         | return from ADB_AFTER_SEND
| ADB_CALL_COMPLETION/03686 - call completion callback
ADB_CALL_COMPLETION:
    BSR.W       ADB_NEXT_BYTE                   | process final response byte
ADB_CALL_COMPLETION_DO:
    MOVEA.L     0x134(A3),A0                    | A0 = completion callback
    JMP         (A0)                            | tail-call completion handler
| ADB_RECV_PATH - receive path: PIC sending data to 68000
ADB_RECV_PATH:
    BTST        #0x2,0x15F(A3)                  | receive transaction pending?
    BEQ.B       ADB_BEGIN_TXN                   | no: start fresh ADB transaction
    BTST        #0x5,0x15D(A3)                  | init/scan pending?
    BNE.B       ADB_CALL_COMPLETION             | yes: process and callback
    BTST        #0x3,(A1)                       | PIC INT asserted?
    BNE.B       ADB_RECV_DO_READ                | yes: PIC has data
    BTST        #0x5,0x15E(A3)                  | SR active?
    BEQ.B       VIAInt_KeyDataReady             | no: spurious interrupt
    BSET        #0x2,0x15E(A3)                  | set SRQ detected flag
    BSET        #0x3,0x15D(A3)                  | set SRQ-pending flag
| PIC has data: read and process
ADB_RECV_DO_READ:
    BCLR        #0x5,0x15E(A3)                  | clear SR-active flag
    BSR.W       ADB_NEXT_BYTE                   | read response byte
    BEQ.B       ADB_NEXT_POLL                   | no data: idle poll
    BTST        #0x1,0x15E(A3)                  | error/timeout?
    BEQ.B       ADB_RECV_DONE                   | no: continue receiving
    BTST        #0x6,0x15E(A3)                  | auto-poll active?
    BNE.B       ADB_POLL_DEVICES                | yes: walk device table
    BRA.B       ADB_CHK_SRQ                     | no: check SRQ
ADB_RECV_DONE:
    BSR.W       ADB_STATE1_BUSY                 | set VIA SR for next byte
    RTS                                         | return (wait for next SR interrupt)
| ADB_BEGIN_TXN - start fresh ADB transaction
ADB_BEGIN_TXN:
    BSET        #0x0,0x15D(A3)                  | set transaction-active flag
    BTST        #0x3,0x15F(A3)                  | auto-start?
    BNE.W       ADB_PHASE_DISPATCH              | yes: send command byte
    MOVE.B      0x1400(A1),D0                   | D0 = dummy read (clear VIA SR)
    BSR.W       ADB_EXEC_COMMAND                | start ADB poll cycle
    RTS                                         | return from ADB_BEGIN_TXN
| VIAInt_KeyDataReady - spurious SR interrupt: drain VIA SR and continue
VIAInt_KeyDataReady:
    BTST        #0x4,0x1600(A1)                 | VIA ACR bit 4: SR output mode?
    BNE.B       ADB_NEXT_POLL                   | yes: no data to read
    MOVE.B      0x1400(A1),D0                   | drain VIA SR (discard byte)
| ADB_NEXT_POLL - start next ADB idle poll
ADB_NEXT_POLL:
    BSR.W       ADBOP_TRAP                      | prepare for next poll cycle
    BCLR        #0x6,0x15E(A3)                  | clear auto-poll flag
| ADB_CHK_SRQ - check for SRQ or scan-in-progress
ADB_CHK_SRQ:
    BTST        #0x3,0x15D(A3)                  | SRQ pending?
    BNE.B       ADB_POLL_KBD                    | yes: handle SRQ
    BTST        #0x2,0x15D(A3)                  | scan/init pending?
    BEQ.W       ADB_IDLE                        | no: auto-poll next device
    BSR.W       ADB_EXEC_COMMAND                | yes: continue scan
    RTS                                         | return from ADB_CHK_SRQ
| ADB_POLL_DEVICES - ADB auto-poll: walk device table, poll next device
|
| Iterates through the device table (12 bytes/entry at +$C0) and
| issues Talk Reg 0 to each registered device's current address.
| Uses the device's stored handler and data pointers.
ADB_POLL_DEVICES:
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.B      0x161(A3),D1                    | D1 = device table offset
    CMPI.W      #0xC0,D1                        | past end of device table?
    BGE.B       ADB_POLL_DEVICES_RTS            | yes: end of auto-poll cycle
    MOVE.B      0x2(A3,D1.W),D0                 | D0 = devtbl[n].cur_addr
    BEQ.B       ADB_POLL_DEVICES_RTS            | empty entry: end of cycle
    LSL.B       #0x4,D0                         | D0 = address << 4
    ORI.W       #0xC,D0                         | D0 |= 0x0C (Talk Reg 0)
    MOVE.B      #0x70,0x15E(A3)                 | phase = 0x70 (auto-poll active)
    MOVE.B      D0,0x15C(A3)                    | set ADB command byte
    MOVE.B      #0x8,0x163(A3)                  | max response = 8 bytes
    LEA.L       0x164(A3),A0                    | A0 = command data buffer
    MOVE.L      A0,0x130(A3)                    | set command block pointer
    MOVE.L      0x4(A3,D1.W),0x134(A3)          | set completion = devtbl[n].handler
    MOVE.L      0x8(A3,D1.W),0x138(A3)          | set data ptr = devtbl[n].data
    BSR.W       ADB_KICK_PIC                    | set VIA state bits
    BSR.W       ADB_STATE0_IDLE                 | start ADB transaction
    ADDI.W      #0xC,D1                         | advance to next device entry
    MOVE.B      D1,0x161(A3)                    | store updated table offset
    RTS                                         | return (response via handler)
ADB_POLL_DEVICES_RTS:
    BCLR        #0x6,0x15E(A3)                  | clear auto-poll flag
    BRA.B       ADB_CHK_SRQ                     | check SRQ / continue
| ADB_POLL_KBD - handle Service Request (SRQ) from ADB device
|
| An ADB device asserted SRQ during the last transaction.
| Poll the first device in the table (keyboard at address 2)
| to service the request. SRQ indicates the device has data.
ADB_POLL_KBD:
    BCLR        #0x3,0x15D(A3)                  | clear SRQ-pending flag
    MOVE.B      #0x70,0x15E(A3)                 | phase = 0x70 (auto-poll)
    MOVE.B      0x2(A3),D0                      | D0 = devtbl[0].cur_addr (keyboard)
    LSL.B       #0x4,D0                         | D0 = address << 4
    ORI.W       #0xC,D0                         | D0 |= 0x0C (Talk Reg 0)
    MOVE.B      D0,0x15C(A3)                    | set ADB command byte
    LEA.L       0x164(A3),A0                    | A0 = command data buffer
    MOVE.L      A0,0x130(A3)                    | set command block pointer
    MOVE.B      #0x8,0x163(A3)                  | max response = 8 bytes
    MOVE.L      0x4(A3),0x134(A3)               | completion = devtbl[0].handler
    MOVE.L      0x8(A3),0x138(A3)               | data ptr = devtbl[0].data
    MOVE.B      #0xC,0x161(A3)                  | reset table offset to entry 1
    BSR.W       ADB_KICK_PIC                    | set VIA state bits
    BSR.W       ADB_STATE0_IDLE                 | start ADB transaction
    RTS                                         | return (keyboard data via handler)
| ADB_IDLE - idle: no pending ADB work, run explicit command if any
ADB_IDLE:
    MOVE.B      #0x30,0x15E(A3)                 | phase = 0x30 (ST1:ST0 = 11, idle)
    BCLR        #0x0,0x15D(A3)                  | clear transaction-active flag
    BSR.W       ADB_QUEUE_POP                   | check for queued explicit ADB cmd
    BSR.W       ADB_INTERNAL_DISPATCH           | start next ADB poll if needed
    RTS                                         | return from FDBSHIFTINT
| ADB_EXEC_COMMAND - set up ADB poll/command cycle
|
| Prepares for an ADB Talk command by looking up the device's handler
| and data pointers in the device table, building the command byte,
| and initiating the transaction through the PIC.
| Uses ADB_FIND_DEVICE to find device entry by address.
ADB_EXEC_COMMAND:
    MOVE.B      #0xB0,0x15E(A3)                 | phase = 0xB0 (poll setup)
    LEA.L       0x164(A3),A0                    | A0 = command data buffer
    MOVE.L      A0,0x158(A3)                    | save buffer base
    MOVE.L      A0,0x130(A3)                    | set command block pointer
    MOVE.B      0x163(A3),0x16F(A3)             | save max frame length
    MOVE.B      0x15C(A3),D0                    | D0 = ADB command byte
    ANDI.B      #0xF0,D0                        | extract address field (bits 4-7)
    LSR.B       #0x4,D0                         | D0 = device address
    JSR         ADB_FIND_DEVICE(PC)             | look up device in table -> A1
    BEQ.B       ADB_EXEC_FALLBACK               | found: use its handler
| Device not found at this address: fall back to address 3 (mouse)
    MOVE.B      #0x3,D0                         | D0 = 3 (default mouse address)
    MOVE.B      #0x3C,0x15C(A3)                 | cmd = Talk Reg 0, addr 3
    JSR         ADB_FIND_DEVICE(PC)             | look up mouse device
ADB_EXEC_FALLBACK:
    MOVEA.L     0x4(A1),A0                      | A0 = device handler routine
    MOVE.L      A0,0x150(A3)                    | save handler (for restore)
    MOVE.L      A0,0x134(A3)                    | set completion callback
    MOVEA.L     0x8(A1),A0                      | A0 = device data pointer
    MOVE.L      A0,0x154(A3)                    | save data ptr (for restore)
    MOVE.L      A0,0x138(A3)                    | set data pointer
    MOVE.B      0x15C(A3),D0                    | D0 = command byte
    ANDI.B      #0xF0,D0                        | keep address field
    ORI.B       #0xC,D0                         | add Talk Reg 0 (0x0C)
    MOVE.B      D0,0x15C(A3)                    | set final command byte
    MOVE.B      D0,0x16E(A3)                    | save for polling loop
    BSR.W       ADB_KICK_PIC                    | set VIA state bits (ST0/ST1)
    BSR.W       ADB_STATE0_IDLE                 | start ADB transaction via PIC
    RTS                                         | return (response via handler)
| ADB_NEXT_BYTE - read ADB response byte from VIA SR into buffer
|
| Reads the byte from VIA shift register (if in input mode) and
| stores it at the current buffer position. Advances the byte counter.
| Returns Z set if no more bytes expected.
ADB_NEXT_BYTE:
    MOVEA.L     0x130(A3),A0                    | A0 = response buffer pointer
    MOVE.B      0x160(A3),D0                    | D0 = byte counter (position)
    EXT.W       D0                              | sign-extend for indexing
    BTST        #0x4,0x1600(A1)                 | VIA ACR bit 4: SR output mode?
    BNE.B       ADB_NEXT_BYTE_OUT               | yes: no byte to read
    MOVE.B      0x1400(A1),0x0(A0,D0.W)         | buf[pos] = byte from VIA SR
    ADDQ.W      #0x1,D0                         | advance byte counter
    MOVE.B      D0,0x160(A3)                    | update byte counter
    BRA.B       ADB_NEXT_BYTE_IN                | check if buffer full
| SR output mode: write next data byte to PIC via VIA SR
ADB_NEXT_BYTE_OUT:
    CMP.B       0x163(A3),D0                    | past max frame length?
    BGT.B       ADB_NEXT_BYTE_RTS               | yes: no more data to send
    MOVE.B      0x0(A0,D0.W),0x1400(A1)         | write buf[pos] to VIA SR -> PIC
    ADDQ.W      #0x1,D0                         | advance byte counter
    MOVE.B      D0,0x160(A3)                    | update counter
ADB_NEXT_BYTE_IN:
    CMPI.B      #0x8,D0                         | 8 bytes transferred? (max ADB frame)
    RTS                                         | return (Z set if at max)
ADB_NEXT_BYTE_RTS:
    SUBQ.W      #0x1,D0                         | back up counter (end of data)
    MOVE.B      D0,0x160(A3)                    | store final counter
    MOVEQ.L     #0x0,D0                         | D0 = 0 (Z set: no more data)
    RTS                                         | return from ADB_NEXT_BYTE_RTS
| ADBOP - _ADBOp trap handler (Inside Mac: Devices, Ch 5)
|
| Sends an explicit ADB command. Entry via trap or internal call.
| Entry (trap): A0 = param block: +0 = data ptr, +4 = completion, +8 = refCon
|               D0 = ADB command byte
| Per Inside Mac, queues the command if ADB is busy.
ADBOP:
    MOVEM.L     A0-A4,-(A7)                     | save registers
    MOVEA.L     0x4(A0),A1                      | A1 = completion routine
    MOVEA.L     0x8(A0),A2                      | A2 = refCon (user data)
    MOVEA.L     (A0),A0                         | A0 = data buffer pointer
    BRA.B       ADB_INTERNAL_DISPATCH_BUSY      | join common path
| ADB_INTERNAL_DISPATCH - internal ADB command dispatch (registers pre-loaded)
ADB_INTERNAL_DISPATCH:
    MOVEM.L     A0-A4,-(A7)                     | save registers
ADB_INTERNAL_DISPATCH_BUSY:
    MOVEA.L     (ADBBase).W,A3                  | A3 = ADB globals
    BCLR        #0x4,0x15D(A3)                  | clear PIC-busy flag
    BTST        #0x3,0x15F(A3)                  | auto-start mode?
    BEQ.B       ADB_INTERNAL_DISPATCH_PEND      | no: skip PIC check
    MOVEA.L     (VIA).W,A4                      | A4 = VIA base
    BTST        #0x3,(A4)                       | PIC INT asserted? (PB3)
    BNE.B       ADB_INTERNAL_DISPATCH_PEND      | yes: PIC ready
    BSET        #0x4,0x15D(A3)                  | PIC not ready: set busy flag
ADB_INTERNAL_DISPATCH_PEND:
    BSET        #0x0,0x15D(A3)                  | set transaction-active flag
    BNE.B       ADB_INTERNAL_DISPATCH_QUEUE     | already active: queue command
    BTST        #0x4,0x15D(A3)                  | PIC busy?
    BEQ.B       ADB_EXEC_NOW                    | no: execute immediately
ADB_INTERNAL_DISPATCH_QUEUE:
    BTST        #0x1,0x15D(A3)                  | queue full/error?
    BEQ.B       ADB_INTERNAL_DISPATCH_PUSH      | no: queue command
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (error: can't queue)
    BRA.B       ADB_EXEC_NOW_RTS                | return error
ADB_INTERNAL_DISPATCH_PUSH:
    BSR.W       ADB_QUEUE_PUSH                  | queue command for later execution
    MOVEQ.L     #0x0,D0                         | D0 = noErr (queued OK)
    BRA.B       ADB_EXEC_NOW_RTS                | return
| Execute ADB command immediately
ADB_EXEC_NOW:
    BSR.B       ADB_STATE0_IDLE                 | set VIA ST0/ST1 = 00 (receive cmd)
    MOVE.B      (A0)+,0x163(A3)                 | frame length from data buffer
    MOVE.L      A0,0x130(A3)                    | command data pointer
    MOVE.B      D0,0x15C(A3)                    | ADB command byte
    MOVE.L      A1,0x134(A3)                    | completion routine
    MOVE.L      A2,0x138(A3)                    | refCon / data pointer
    BSR.W       ADB_KICK_PIC                    | initiate ADB transaction
    MOVEQ.L     #0x0,D0                         | D0 = noErr
ADB_EXEC_NOW_RTS:
    MOVEM.L     (A7)+,A0-A4                     | restore registers
    RTS                                         | return from _ADBOp
| ADBOP_TRAP - call ADB completion routine after transaction
|
| Prepares the response buffer header (byte count at buf[-1]),
| then calls the completion routine with D0 = command, A0 = buffer,
| A2 = refCon. Per Inside Mac ADB Manager convention.
ADBOP_TRAP:
    MOVEM.L     D0/A0-A3,-(A7)                  | save registers
    MOVEA.L     (ADBBase).W,A3                  | A3 = ADB globals
    MOVE.L      0x134(A3),D0                    | D0 = completion routine
    BEQ.B       ADBOP_RTS                       | nil: no completion, skip
    MOVEA.L     D0,A1                           | A1 = completion routine
    MOVEA.L     0x130(A3),A0                    | A0 = response buffer
    MOVE.B      -(A0),D0                        | back up to length byte position
    MOVE.B      0x160(A3),D0                    | D0 = byte count received
    MOVE.B      D0,(A0)                         | store count at buf[-1] (length)
    MOVE.B      0x15C(A3),D0                    | D0 = ADB command byte
    MOVEA.L     0x138(A3),A2                    | A2 = refCon / data
    JSR         (A1)                            | call completion(D0=cmd, A0=buf, A2=ref)
ADBOP_RTS:
    MOVEM.L     (A7)+,D0/A0-A3                  | restore registers
    RTS                                         | return from ADBOP_RTS
| ADB_STATE0_IDLE/03930/03938/03940 - set VIA port B ST0/ST1 state bits
|
| These four entry points set the 2-bit state code (ST1:ST0) on
| VIA port B bits 4-5, which tells the PIC ADB controller what
| phase to enter next. State is also recorded in $15F for tracking.
|   ADB_STATE0_IDLE: state 0 (00) - PIC receives command from VIA
|   ADB_STATE1_BUSY: state 1 (01) - PIC sends byte + error status
|   ADB_STATE2_RECV: state 2 (10) - PIC sends byte + SRQ status
|   ADB_STATE3_NULL: state 3 (11) - null/idle state
| Called by: ADB_SCAN_DEVICE, ADB_TALK_REG3, ADB_LISTEN_REG3, ADB_POLL_DEVICES, ADB_POLL_KBD (and 2 more)
ADB_STATE0_IDLE:
    MOVEM.L     D0-D1/A1,-(A7)                  | save registers
    MOVEQ.L     #0x0,D0                         | D0 = state 0 (ST1:ST0 = 00)
    BRA.B       KBD_SEND_CMD                    | set state
ADB_STATE1_BUSY:
    MOVEM.L     D0-D1/A1,-(A7)                  | save registers
    MOVEQ.L     #0x1,D0                         | D0 = state 1 (ST1:ST0 = 01)
    BRA.B       KBD_SEND_CMD                    | set state
ADB_STATE2_RECV:
    MOVEM.L     D0-D1/A1,-(A7)                  | save registers
    MOVEQ.L     #0x2,D0                         | D0 = state 2 (ST1:ST0 = 10)
    BRA.B       KBD_SEND_CMD                    | set state
ADB_STATE3_NULL:
    MOVEM.L     D0-D1/A1,-(A7)                  | save registers
    MOVEQ.L     #0x3,D0                         | D0 = state 3 (ST1:ST0 = 11)
KBD_SEND_CMD:
    MOVEA.L     (VIA).W,A1                      | A1 = VIA base
    MOVE.W      SR,-(A7)                        | save SR (atomic update)
    ORI.W       #0x300,SR                       | raise IPL
    CLR.B       0x15F(A3)                       | clear state tracking byte
    BSET        D0,0x15F(A3)                    | record which state we're setting
    LSL.B       #0x4,D0                         | shift state to PB4-PB5 position
    MOVE.B      (A1),D1                         | D1 = current VIA port B
    ANDI.B      #0xCF,D1                        | clear PB4-PB5 (ST0/ST1)
    OR.B        D0,D1                           | merge new state bits
    MOVE.B      D1,(A1)                         | write to VIA port B
    MOVE.W      (A7)+,SR                        | restore SR
    MOVEM.L     (A7)+,D0-D1/A1                  | restore registers
    RTS                                         | return from KBD_SEND_CMD
| ADB_KICK_PIC - initiate ADB transaction: set active flag + trigger PIC
| Called by: ADB_SCAN_DEVICE, ADB_TALK_REG3, ADB_LISTEN_REG3, ADB_POLL_DEVICES, ADB_POLL_KBD (and 2 more)
ADB_KICK_PIC:
    BSET        #0x0,0x15D(A3)                  | set transaction-active flag
    MOVEA.L     (VIA).W,A1                      | A1 = VIA base
    MOVE.W      SR,-(A7)                        | save SR (atomic VIA update)
    ORI.W       #0x300,SR                       | raise IPL
    ANDI.B      #0xE3,0x1600(A1)                | clear VIA ACR bits 2-4 (SR mode)
    MOVE.L      (A7),(A7)                       | bus delay (VIA register settle)
    ORI.B       #0x1C,0x1600(A1)                | set ACR bits 2-4: SR out, ext clock
    MOVE.L      (A7),(A7)                       | bus delay
    MOVE.B      D0,0x1400(A1)                   | write command byte to VIA SR
    MOVE.W      (A7)+,SR                        | restore SR
    RTS                                         | return (PIC will clock out byte)
| ADB_QUEUE_PREEMPT - save current ADB state and queue for later
|
| Saves the current command/completion/data to the ADB queue
| so the current transaction can be preempted by a higher-priority one.
ADB_QUEUE_PREEMPT:
    MOVEM.L     A1-A2,-(A7)                     | save registers
    MOVEA.L     0x130(A3),A0                    | A0 = command data pointer
    MOVE.B      -(A0),D0                        | back up to length byte
    MOVE.B      0x15C(A3),D0                    | D0 = ADB command byte
    MOVEA.L     0x134(A3),A1                    | A1 = completion routine
    MOVEA.L     0x138(A3),A2                    | A2 = refCon
    BSR.B       ADB_QUEUE_PUSH                  | queue command for later
    MOVEM.L     (A7)+,A1-A2                     | restore registers
    RTS                                         | return from ADB_QUEUE_PREEMPT
| ADB_QUEUE_RESTORE - restore saved ADB poll state after preemption
|
| Restores command, length, buffer, completion, and data pointers
| from the saved poll state ($16E-$16F, $158, $150, $154).
ADB_QUEUE_RESTORE:
    MOVE.B      0x16E(A3),0x15C(A3)             | restore ADB command byte
    MOVE.B      0x16F(A3),0x163(A3)             | restore frame length
    MOVE.L      0x158(A3),0x130(A3)             | restore command data pointer
    MOVE.L      0x150(A3),0x134(A3)             | restore completion routine
    MOVE.L      0x154(A3),0x138(A3)             | restore refCon/data pointer
    RTS                                         | return from ADB_QUEUE_RESTORE
| ADB_QUEUE_PUSH - enqueue ADB command into circular buffer
|
| ADB command queue is a circular buffer of 14-byte entries at +$C0.
| Each entry: +0 = cmd byte, +2 = data ptr, +6 = completion, +A = refCon.
| +$148 = write pointer, +$144 = read pointer, +$13C/+$140 = base/limit.
| Sets bit 1 of +$15D (queue full) when write catches read.
ADB_QUEUE_PUSH:
    MOVE.L      A4,-(A7)                        | save A4
    BTST        #0x1,0x15D(A3)                  | queue full? (bit 1)
    BNE.B       ADB_QUEUE_PUSH_RTS              | yes: discard command
    BCLR        #0x2,0x15D(A3)                  | clear queue-empty flag
    MOVEA.L     0x148(A3),A4                    | A4 = queue write pointer
    MOVE.B      D0,(A4)                         | entry.cmd = ADB command byte
    MOVE.L      A0,0x2(A4)                      | entry.data = data buffer
    MOVE.L      A1,0x6(A4)                      | entry.completion = callback
    MOVE.L      A2,0xA(A4)                      | entry.refCon = user data
    ADDA.W      #0xE,A4                         | advance write ptr by 14 bytes
    CMPA.L      0x140(A3),A4                    | past queue limit?
    BLT.B       E_1056_LOOP_LOOP_3              | no: write pointer OK
    MOVEA.L     0x13C(A3),A4                    | wrap to queue base
E_1056_LOOP_LOOP_3:
    CMPA.L      0x144(A3),A4                    | write caught read? (queue full)
    BNE.B       ADB_QUEUE_PUSH_FULL             | no: room remaining
    BSET        #0x1,0x15D(A3)                  | set queue-full flag
ADB_QUEUE_PUSH_FULL:
    MOVE.L      A4,0x148(A3)                    | update write pointer
ADB_QUEUE_PUSH_RTS:
    MOVEA.L     (A7)+,A4                        | restore A4
    RTS                                         | return from ADB_QUEUE_PUSH_RTS
| ADB_QUEUE_POP - dequeue ADB command from circular buffer
|
| Reads next pending command from the queue into registers.
| Returns with D0 = cmd, A0 = data, A1 = completion, A2 = refCon.
| Sets bit 2 of +$15D (queue empty) when read catches write.
ADB_QUEUE_POP:
    MOVE.L      A4,-(A7)                        | save A4
    BTST        #0x2,0x15D(A3)                  | queue empty? (bit 2)
    BNE.B       ADB_QUEUE_POP_HAVE              | yes: nothing to dequeue
    MOVEA.L     0x144(A3),A4                    | A4 = queue read pointer
    MOVE.B      (A4),D0                         | D0 = entry.cmd
    MOVEA.L     0x2(A4),A0                      | A0 = entry.data
    MOVEA.L     0x6(A4),A1                      | A1 = entry.completion
    MOVEA.L     0xA(A4),A2                      | A2 = entry.refCon
    ADDA.W      #0xE,A4                         | advance read ptr by 14 bytes
    CMPA.L      0x140(A3),A4                    | past queue limit?
    BLT.B       ADB_QUEUE_POP_EMPTY             | no: read pointer OK
    MOVEA.L     0x13C(A3),A4                    | wrap to queue base
ADB_QUEUE_POP_EMPTY:
    CMPA.L      0x148(A3),A4                    | read caught write? (queue empty)
    BNE.B       ADB_QUEUE_POP_RTS               | no: more entries
    BSET        #0x2,0x15D(A3)                  | set queue-empty flag
ADB_QUEUE_POP_RTS:
    MOVE.L      A4,0x144(A3)                    | update read pointer
ADB_QUEUE_POP_HAVE:
    MOVEA.L     (A7)+,A4                        | restore A4
    RTS                                         | return from ADB_QUEUE_POP_HAVE
| ADB_HANDLER_MOUSE - ADB mouse handler (device address 3)
|
| Processes mouse data from ADB Talk Reg 0 response.
| ADB mouse register 0: byte 0 = button + Y delta, byte 1 = X delta.
| Bit 7 of byte 0: button state (0 = pressed, 1 = released).
| Bits 6-0: signed 7-bit Y delta. Byte 1 bits 6-0: signed X delta.
| Posts mouseDown/mouseUp events on button state changes.
| Updates MTemp (raw mouse position) for cursor tracking.
ADB_HANDLER_MOUSE:
    MOVEQ.L     #0x1,D0                         | D0 = 1 (mouseDown event code)
    MOVE.B      0x164(A3),D2                    | D2 = ADB response byte 0 (btn+Y)
    BPL.B       VBL_CHECK_BTN_CHG               | bit 7 clear: button pressed
    MOVEQ.L     #0x2,D0                         | D0 = 2 (mouseUp event code)
VBL_CHECK_BTN_CHG:
    MOVE.B      (MBState).W,D1                  | D1 = previous button state
    EOR.B       D2,D1                           | D1 = changed bits
    BPL.B       MOUSE_PROCESS_Y                 | bit 7 same: no button change
| Button state changed: post mouse event
    MOVE.L      (Ticks).W,D1                    | D1 = current tick count
    SUB.L       (MBTicks).W,D1                  | D1 = ticks since last button event
    CMPI.L      #0x1,D1                         | debounce: at least 1 tick elapsed?
    BLT.B       MOUSE_PROCESS_Y                 | too soon: ignore (debounce)
    ADD.L       D1,(RndSeed).W                  | mix timing into random seed
    MOVE.L      (Ticks).W,(MBTicks).W           | update last button event time
    ANDI.B      #0x80,D2                        | extract button bit only
    MOVE.B      D2,(MBState).W                  | update button state global
    MOVEA.L     D0,A0                           | A0 = event code (1 or 2)
    MOVEQ.L     #0x0,D0                         | D0 = 0 (event message = nil)
    _PostEvent                                  | post mouseDown or mouseUp event
| Process Y delta (vertical mouse movement)
MOUSE_PROCESS_Y:
    MOVEQ.L     #0x7F,D0                        | D0 = 0x7F (7-bit mask)
    AND.B       0x164(A3),D0                    | D0 = Y delta (unsigned 7-bit)
    ADD.B       D0,D0                           | shift bit 6 to bit 7 (sign extend)
    ASR.B       #0x1,D0                         | arithmetic shift: signed 7-bit
    EXT.W       D0                              | sign-extend to word
    BEQ.B       MOUSE_PROCESS_X                 | zero: no vertical movement
    ADD.W       D0,(MTemp_v).W                  | update raw mouse Y position
    MOVE.B      (CrsrCouple).W,(CrsrNew).W      | signal cursor needs update
| Process X delta (horizontal mouse movement)
MOUSE_PROCESS_X:
    MOVEQ.L     #0x7F,D0                        | D0 = 0x7F (7-bit mask)
    AND.B       0x165(A3),D0                    | D0 = X delta (response byte 1)
    ADD.B       D0,D0                           | sign-extend trick
    ASR.B       #0x1,D0                         | signed 7-bit delta
    EXT.W       D0                              | sign-extend to word
    BEQ.B       MOUSE_PROCESS_RTS               | zero: no horizontal movement
    ADD.W       D0,(MTemp_h).W                  | update raw mouse X position
    MOVE.B      (CrsrCouple).W,(CrsrNew).W      | signal cursor needs update
MOUSE_PROCESS_RTS:
    RTS                                         | return from mouse handler
| ADB_HANDLER_KBD - ADB keyboard handler (device address 2)
|
| Processes keyboard data from ADB Talk Reg 0 response.
| ADB keyboard register 0: 2 bytes, each containing a keycode.
| Bit 7 = key state (0 = down, 1 = up), bits 6-0 = keycode.
| 0xFF = no key (no event). Uses _GetADBInfo to identify keyboard
| type for proper keycode-to-event translation.
| Posts keyDown(3)/keyUp(4)/autoKey(5) events via _PostEvent.
ADB_HANDLER_KBD:
    MOVE.L      A2,D3                           | D3 = refCon (handler data ptr)
    BEQ.W       KBD_COMPLETION_NORMAL           | nil: no handler, skip
    MOVEA.L     A0,A1                           | A1 = response data buffer
    LSR.W       #0x4,D0                         | shift command byte to get address
    MOVEQ.L     #0xF,D1                         | D1 = 0xF (address mask)
    AND.L       D1,D0                           | D0 = ADB device address
    MOVE.L      D0,D3                           | D3 = save address for later
| Call _GetADBInfo to get device type/handler info
    LEA.L       -0xA(A7),A7                     | allocate 10 bytes on stack for info
    MOVEA.L     A7,A0                           | A0 = ADBDataBlock on stack
    _GetADBInfo                                 | get device info for address D0
    ROR.L       #0x8,D3                         | position address in D3 high
    MOVE.W      (A7)+,D3                        | D3 low = device type/handler ID
    ADDQ.L      #0x8,A7                         | deallocate stack space
    SWAP.W      D3                              | D3 = address:handler combined
| Process two key bytes from ADB response
    MOVE.B      0x1(A1),D0                      | D0 = key byte 1
    MOVE.B      0x2(A1),-(A7)                   | save key byte 2 on stack
    BSR.B       KBD_POST_EVENT                  | process key byte 1
    MOVE.B      (A7)+,D0                        | D0 = key byte 2
| KBD_POST_EVENT - process one ADB key byte
|
| D0 = key byte: bit 7 = up/down, bits 6-0 = keycode.
| 0xFF = no key event (skip). Posts keyDown/keyUp/autoKey event.
KBD_POST_EVENT:
    CMPI.B      #0xFF,D0                        | key = 0xFF (no key)?
    BEQ.W       KBD_COMPLETION_NORMAL           | yes: skip
    CLR.L       (KbdVers).W                     | clear keyboard version cache
    MOVEQ.L     #0x7F,D1                        | D1 = keycode mask
    AND.B       D0,D1                           | D1 = keycode (bits 6-0)
| Look up keycode in KCHR key-code-to-modifier mapping table
    MOVEA.L     (A2),A1                         | A1 = KCHR resource pointer
    MOVE.B      0x4(A1,D1.W),D3                 | D3 = modifier table entry for key
    BPL.B       KBD_UPDATE_KEYMAP               | bit 7 clear: normal key, skip special
    BCLR        #0x7,D3                         | clear special-key flag
    LEA.L       0x84(A1),A0                     | A0 = special key mapping table
    MOVE.W      (A0)+,D2                        | D2 = number of special key entries
    BEQ.B       KBD_UPDATE_KEYMAP               | empty: treat as normal key
    SUBQ.W      #0x1,D2                         | adjust for DBF
KBD_POST_NOT_FF:
    CMP.B       (A0)+,D0                        | match key byte in special table?
    BEQ.W       KBD_SPECIAL_KEY                 | yes: handle special key
    MOVE.B      0x1(A0),D1                      | D1 = entry data length
    LEA.L       0x2(A0,D1.W),A0                 | skip to next entry
    DBF.W       D2,KBD_POST_NOT_FF              | loop special key entries
| KBD_UPDATE_KEYMAP - update key map and post keyboard event
KBD_UPDATE_KEYMAP:
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.B      D3,D2                           | D2 = keycode index
    LSR.W       #0x3,D2                         | D2 = byte offset in key map
    TST.B       D0                              | key down? (bit 7 = 0)
    BMI.B       KBD_KEYUP_AUTO                  | bit 7 set: key up
    BSET        D3,0x4(A2,D2.W)                 | set bit in key map (key down)
    BRA.B       KBD_BUILD_MESSAGE               | continue
KBD_KEYUP_AUTO:
    BCLR        D3,0x4(A2,D2.W)                 | clear bit in key map (key up)
    BSET        #0x7,D3                         | set key-up flag in D3
KBD_BUILD_MESSAGE:
    MOVEM.L     0x4(A2),D0-D2/A0                | load 16-byte key map from handler data
    MOVEM.L     D0-D2/A0,(KeyMap)               | copy to KeyMap low-memory global
    MOVE.L      D3,D0                           | D0 = keycode + flags
    LSR.L       #0x8,D0                         | extract ADB address field
    MOVE.B      D0,(KeyLast).W                  | KeyLast = last keycode
    SWAP.W      D0                              | get keyboard type
    MOVE.B      D0,(KbdType).W                  | KbdType = ADB handler ID
| Call _KeyTranslate to convert keycode to character
    MOVE.W      0xA(A2),D0                      | D0 = modifier state from handler
    ROL.W       #0x1,D0                         | align modifiers for _KeyTranslate
    SUBQ.L      #0x4,A7                         | make room for 2 result words
    MOVE.L      0x14(A2),-(A7)                  | push dead-key state
    MOVE.W      D3,-(A7)                        | push keycode + up/down
    MOVE.B      D0,(A7)                         | merge modifiers into keycode byte
    PEA.L       0x18(A2)                        | push KCHR resource pointer
    _KeyTranslate                               | translate keycode -> character(s)
    MOVE.W      (A7)+,D0                        | D0 = first translated character
    BEQ.B       KBD_POST_EVENT_RTS              | zero: no character, check second
    BSR.B       KBD_COMPLETION                  | post event for first character
KBD_POST_EVENT_RTS:
    MOVE.W      (A7)+,D0                        | D0 = second translated character
    BEQ.B       KBD_COMPLETION_NORMAL           | zero: no second character
| KBD_COMPLETION - build and post keyboard event
|
| D0 = translated character, D3 = keycode + up/down flag
| Builds event message: char in bits 0-7, keycode in bits 8-15,
| ADB address in bits 16-23. Posts keyDown(3) or keyUp(4).
KBD_COMPLETION:
    ROR.W       #0x8,D0                         | position char in high byte
    SWAP.W      D0                              | move to bits 16-31
    MOVE.W      D3,D0                           | D0 low = keycode + flags
    ROL.L       #0x8,D0                         | assemble event message
    TST.B       D3                              | key up? (bit 7 set)
    BMI.B       KBD_POST_KEYUP                  | yes: post keyUp event
| Key down: record timing and post keyDown event
    MOVE.L      (Ticks).W,D1                    | D1 = current tick count
    MOVE.L      D1,(KeyTime).W                  | KeyTime = time of this key-down
    MOVE.L      D1,(KeyRepTime).W               | KeyRepTime = reset repeat timer
    MOVE.L      D0,(KbdVers).W                  | save event message for auto-key
    MOVEA.W     #0x3,A0                         | A0 = 3 (keyDown event code)
    _PostEvent                                  | post keyDown event
KBD_COMPLETION_NORMAL:
    RTS                                         | return from keyboard handler
| Post keyUp event
KBD_POST_KEYUP:
    MOVEA.W     #0x4,A0                         | A0 = 4 (keyUp event code)
    BCLR        #0xF,D0                         | clear bit 15 (key-up flag in msg)
    _PostEvent                                  | post keyUp event
    RTS                                         | return from keyboard handler
| KBD_SPECIAL_KEY - special key table match: check key state and dispatch
KBD_SPECIAL_KEY:
    MOVE.B      (A0)+,D1                        | D1 = special key flags/action byte
    BPL.B       KBD_COMPLETION_NEXT             | bit 7 clear: no toggle check needed
| Toggle key: check if currently down in key map
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.B      D3,D2                           | D2 = keycode index
    LSR.W       #0x3,D2                         | D2 = byte offset in key map
    BTST        D3,0x4(A2,D2.W)                 | key currently down in map?
    SEQ.B       D0                              | D0 = 0xFF if down, 0x00 if up
KBD_COMPLETION_NEXT:
    MOVEQ.L     #0xF,D2                         | D2 = 0xF (action type mask)
    AND.B       D1,D2                           | D2 = action type (bits 0-3)
    BEQ.B       KBD_COMPLETION_NORMAL           | no match: no action
    TST.B       0x1C(A2)                        | pending special key operation?
    BNE.W       KBD_UPDATE_KEYMAP               | yes: just update key map
| Special key processing: modifier keys, LED control, etc.
| D2 = special key type, A0 = special key data table entry
    MOVEM.L     D0/A1,-(A7)                     | save key byte and buffer ptr
    MOVE.L      A0,-(A7)                        | save special key data ptr
    CMPI.B      #0xC,D2                         | LED control key? (type >= 12)
    BGE.B       KBD_LED_PATH                    | yes: use LED update path
    PEA.L       ADB_DONE_CLR_PENDING(PC)        | push simple completion handler
    BRA.B       KBD_QUEUE_LED_UPDATE            | join common send path
KBD_LED_PATH:
    PEA.L       KBD_SET_LED(PC)                 | push LED update completion handler
KBD_QUEUE_LED_UPDATE:
    LEA.L       0x1D(A2),A1                     | A1 = pending ADB ops table
    MOVE.B      (A1)+,D1                        | D1 = pending ops count
    BEQ.B       KBD_QUEUE_DRAIN_LOOP            | none: skip to cleanup
    SUBQ.W      #0x1,D1                         | adjust for DBF
KBD_QUEUE_FREE_SLOT:
    TST.B       (A1)+                           | slot in use? (non-zero)
    BEQ.B       KBD_QUEUE_FILL                  | empty slot: use it
    LEA.L       0x9(A1),A1                      | skip 10-byte entry
    DBF.W       D1,KBD_QUEUE_FREE_SLOT          | scan next slot
    BRA.B       KBD_QUEUE_DRAIN_LOOP            | no free slot: skip
| Found free slot: fill with ADB command data
KBD_QUEUE_FILL:
    MOVE.B      D0,-0x1(A1)                     | store key byte in slot flag
    BSET        #0x1,-0x1(A1)                   | mark slot as active
    MOVE.L      A1,-(A7)                        | save slot pointer for completion
    MOVE.B      (A0),D1                         | D1 = data length
    CMPI.B      #0x8,D1                         | clamp to max 8 bytes
    BLS.B       KBD_QUEUE_FULL                  | <= 8: use as-is
    MOVEQ.L     #0x8,D1                         | cap at 8 bytes
KBD_QUEUE_FULL:
    MOVE.B      (A0)+,(A1)+                     | copy data bytes to slot
    DBF.W       D1,KBD_QUEUE_FULL               | loop copy
    MOVE.W      D3,D0                           | D0 = keycode + flags
    CLR.B       D0                              | clear low byte
    LSR.W       #0x4,D0                         | extract ADB address
    OR.B        D2,D0                           | merge with register/cmd type
    MOVEA.L     A7,A0                           | A0 = ADBOp param block on stack
    _ADBOp                                      | send ADB command
    BNE.B       KBD_QUEUE_DRAIN_RTS             | error: clear slot and cleanup
    ADDQ.L      #0x4,A7                         | pop slot pointer (success)
KBD_QUEUE_DRAIN_LOOP:
    ADDQ.L      #0x8,A7                         | clean up stack frame
    MOVEM.L     (A7)+,D0/A1                     | restore key byte and buffer
    BRA.W       KBD_UPDATE_KEYMAP               | continue to key map update
KBD_QUEUE_DRAIN_RTS:
    MOVEA.L     (A7)+,A1                        | A1 = slot pointer
    CLR.B       -0x1(A1)                        | clear slot (ADB op failed)
    BRA.B       KBD_QUEUE_DRAIN_LOOP            | cleanup
| KBD_SET_LED - LED update completion: apply LED mask to key state
|
| Merges or clears LED bits in the keyboard register data based
| on key down/up state. Then sends a Listen command to update the
| keyboard's LED register.
KBD_SET_LED:
    MOVEA.L     A0,A1                           | A1 = ADB response data
    MOVEQ.L     #0x0,D1                         | clear D1
    MOVE.B      (A1)+,D1                        | D1 = response byte count
    MOVE.B      (A2)+,D2                        | D2 = mask byte count
    CMP.B       D2,D1                           | use shorter of the two
    BLS.B       KBD_SET_LED_CALC                | response shorter: use D1
    MOVE.B      D2,D1                           | mask shorter: use D2
KBD_SET_LED_CALC:
    TST.B       -0x1(A0)                        | key down? (flag byte negative)
    BPL.B       KBD_SET_LED_AFTER_CAPS          | key up: clear LED bits
    BRA.B       KBD_SET_LED_AFTER_NUM           | key down: set LED bits
KBD_SET_LED_NUMLOCK:
    MOVE.B      (A2)+,D2                        | D2 = mask byte
    OR.B        D2,(A1)+                        | set LED bits in response
KBD_SET_LED_AFTER_NUM:
    DBF.W       D1,KBD_SET_LED_NUMLOCK          | loop all mask bytes
    BRA.B       KBD_SET_LED_DO_LISTEN           | send updated data
KBD_SET_LED_CAPSLOCK:
    MOVE.B      (A2)+,D2                        | D2 = mask byte
    NOT.B       D2                              | invert mask
    AND.B       D2,(A1)+                        | clear LED bits in response
KBD_SET_LED_AFTER_CAPS:
    DBF.W       D1,KBD_SET_LED_CAPSLOCK         | loop all mask bytes
| Send updated LED state back to keyboard via Listen command
KBD_SET_LED_DO_LISTEN:
    CLR.L       -(A7)                           | push nil refCon
    PEA.L       ADB_DONE_CLR_PENDING(PC)        | push completion handler
    MOVE.L      A0,-(A7)                        | push data buffer
    MOVEA.L     A7,A0                           | A0 = ADBOp param block
    BCLR        #0x2,D0                         | change Talk to Listen (clear bit 2)
    _ADBOp                                      | send Listen command to keyboard
    BNE.B       KBD_SET_LED_RTS                 | error: skip
    MOVEA.L     (A7),A0                         | A0 = data buffer
    CLR.B       -0x1(A0)                        | clear pending flag
KBD_SET_LED_RTS:
    LEA.L       0xC(A7),A7                      | clean up stack (3 longs)
    RTS                                         | return from LED update
| ADB_DONE_CLR_PENDING - simple ADB completion: clear pending flag
ADB_DONE_CLR_PENDING:
    CLR.B       -0x1(A0)                        | clear pending op flag
    RTS                                         | return from ADB_DONE_CLR_PENDING
| ADBREINIT - reinitialize ADB subsystem (_ADBReInit trap)
|
| Clears all ADB globals, rescans the bus, and loads ADBS device
| driver resources for each discovered device.
ADBREINIT:
    MOVEM.L     D0-D4/A0-A3,-(A7)               | save all registers
    MOVEA.L     (ADBBase).W,A3                  | A3 = ADB globals base
    MOVE.W      #0x5B,D0                        | D0 = 91 longwords (368 bytes)
    MOVEA.L     A3,A0                           | A0 = start of ADB globals
ADB_DONE_RTS:
    CLR.L       (A0)+                           | zero next longword
    DBF.W       D0,ADB_DONE_RTS                 | clear all ADB globals
    BSR.W       ADB_BUS_SCAN                    | rescan ADB bus
    BSR.B       INITADBDRVR                     | load ADBS resources for devices
    MOVEM.L     (A7)+,D0-D4/A0-A3               | restore registers
    RTS                                         | return from ADBReInit
| INITADBDRVR - load ADBS (ADB Service) resources for each device
|
| For each ADB device found, looks up an 'ADBS' resource by handler
| ID. If found, calls its init routine (per Inside Mac: Devices).
INITADBDRVR:
    _CountADBs                                  | D0 = number of ADB devices
    MOVE.W      D0,D3                           | D3 = device count
    BEQ.B       ADB_INSTALL_LOOP                | none: return
    MOVEQ.L     #0x1,D4                         | D4 = 1 (first device index)
    LINK        A6,#-0xC                        | allocate 12-byte local frame
ADBINIT_BODY:
    LEA.L       -0xC(A6),A0                     | A0 = ADBDataBlock on stack
    MOVE.W      D4,D0                           | D0 = device index
    _GetIndADB                                  | get info for device #D0
    MOVE.B      D0,-0x2(A6)                     | save ADB address in local
    BMI.B       ADB_INSTALL_BODY                | error: skip this device
| Try to load 'ADBS' resource for this device's handler ID
    SUBQ.L      #0x4,A7                         | make room for result handle
    MOVE.L      #0x41444253,-(A7)               | push 'ADBS' resource type
    CLR.W       -(A7)                           | push resource ID = 0
    MOVE.B      -0xB(A6),0x1(A7)                | set ID low byte = handler ID
    _GetResource                                | load ADBS resource
    MOVE.L      (A7),D1                         | D1 = resource handle
    BNE.B       ADBREINIT_TAIL                  | found: install driver
    ADDQ.W      #0x4,A7                         | pop result handle (not found)
    BRA.B       ADB_INSTALL_BODY                | try next device
ADBREINIT_TAIL:
    _DetachResource                             | detach ADBS from resource chain
    MOVEA.L     D1,A0                           | A0 = ADBS handle
    MOVE.L      (A0),D0                         | D0 = deref handle -> pointer
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit address
    MOVEA.L     D0,A0                           | A0 = ADBS code pointer
    MOVE.B      -0x2(A6),D0                     | D0 = ADB device address
    MOVE.B      -0xC(A6),D1                     | D1 = original handler ID
    JSR         (A0)                            | call ADBS init routine
ADB_INSTALL_BODY:
    ADDQ.W      #0x1,D4                         | advance to next device
    CMP.W       D4,D3                           | more devices?
    BGE.B       ADBINIT_BODY                    | yes: process next
    UNLK        A6                              | deallocate local frame
ADB_INSTALL_LOOP:
    RTS                                         | return from INITADBDRVR
| COUNTADBS - _CountADBs trap: count ADB devices with non-zero address
COUNTADBS:
    MOVEQ.L     #0x10,D1                        | D1 = 16 (max device entries)
    MOVE.W      D1,D0                           | D0 = 16 (will subtract empty)
    MOVEA.L     (ADBBase).W,A1                  | A1 = device table base
    BRA.B       COUNTADBS_TEST                  | start scan
ADB_INSTALL_FOUND:
    ADDA.W      #0xC,A1                         | advance to next 12-byte entry
COUNTADBS_TEST:
    TST.B       0x2(A1)                         | cur_addr == 0? (empty entry)
    DBEQ.W      D1,ADB_INSTALL_FOUND            | loop until empty or end
    SUB.W       D1,D0                           | D0 = 16 - remaining = count
    RTS                                         | return D0 = device count
| GETINDADB - _GetIndADB trap: get Nth ADB device info
|
| Entry: D0 = index (1-based), A0 = ADBDataBlock pointer
| Exit: D0 = device address, ADBDataBlock filled
GETINDADB:
    TST.W       D0                              | index <= 0?
    BLE.B       ADB_FIND_DEVICE_RTS             | invalid: return -1
    CMPI.W      #0x10,D0                        | index > 16?
    BGT.B       ADB_FIND_DEVICE_RTS             | invalid: return -1
    MOVEA.L     (ADBBase).W,A1                  | A1 = device table base
    MULU.W      #0xC,D0                         | D0 *= 12 (entry size)
    LEA.L       -0xC(A1,D0.L),A1                | A1 = Nth device entry
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.B      0x2(A1),D0                      | D0 = device's current ADB address
| ADB_COPY_DEVTBL - copy device table entry to ADBDataBlock
ADB_COPY_DEVTBL:
    MOVE.B      (A1),(A0)+                      | ADBDataBlock.devType = handler_id
    MOVE.B      0x1(A1),(A0)+                   | ADBDataBlock.origAddr
    MOVE.L      0x4(A1),(A0)+                   | ADBDataBlock.dbServiceRtPtr
    MOVE.L      0x8(A1),(A0)                    | ADBDataBlock.dbDataAreaAddr
    RTS                                         | return D0 = address
| GETADBINFO - _GetADBInfo trap: get device info by address
|
| Entry: D0 = ADB address, A0 = ADBDataBlock pointer
| Exit: D0 = 0 if found, -1 if not
GETADBINFO:
    BSR.B       ADB_FIND_DEVICE                 | find device by address D0
    BEQ.B       ADB_COPY_DEVTBL                 | found: copy data to block
    RTS                                         | not found: return D0 = -1
| SETADBINFO - _SetADBInfo trap: set device handler and data
|
| Entry: D0 = ADB address, A0 = ADBSetInfoBlock (+0=handler, +4=data)
| Sets the device's service routine and data area pointers.
SETADBINFO:
    BSR.B       ADB_FIND_DEVICE                 | find device by address D0
    BNE.B       ADB_COPY_DEVTBL_RTS             | not found: return
    MOVE.L      (A0)+,0x4(A1)                   | devtbl[n].handler = new handler
    MOVE.L      (A0),0x8(A1)                    | devtbl[n].data = new data area
ADB_COPY_DEVTBL_RTS:
    RTS                                         | return from SetADBInfo
| ADB_FIND_DEVICE - find device table entry by ADB address
|
| Entry: D0 = ADB address to find
| Exit: A1 = device entry pointer, D0 = 0 if found, -1 if not
| Called by: ADB_EXEC_COMMAND, GETADBINFO, SETADBINFO, ADB_ENSURE_MOUSE, ADB_ENSURE_MOUSE_LOOP
ADB_FIND_DEVICE:
    MOVEQ.L     #0x10,D1                        | D1 = 16 (max entries)
    MOVEA.L     (ADBBase).W,A1                  | A1 = device table base
    BRA.B       ADB_FIND_DEVICE_NEXT            | start scan
ADB_FIND_DEVICE_LOOP2:
    ADDA.W      #0xC,A1                         | advance to next entry
ADB_FIND_DEVICE_NEXT:
    CMP.B       0x2(A1),D0                      | cur_addr matches target?
    BEQ.B       ADB_FIND_DEVICE_OK              | yes: found
    TST.B       0x2(A1)                         | end of table? (cur_addr = 0)
    DBEQ.W      D1,ADB_FIND_DEVICE_LOOP2        | loop until match or end
ADB_FIND_DEVICE_RTS:
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (not found)
    RTS                                         | return from ADB_FIND_DEVICE_RTS
ADB_FIND_DEVICE_OK:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (found, Z set)
    RTS                                         | return from ADB_FIND_DEVICE_OK
| ADB_ENSURE_MOUSE - ensure keyboard and mouse entries exist in device table
|
| If no device at address 2 (keyboard), creates a default entry.
| If no device at address 3 (mouse), creates a default entry.
| Used during ADB init to guarantee handlers for standard devices.
ADB_ENSURE_MOUSE:
    MOVEQ.L     #0x2,D0                         | D0 = 2 (keyboard address)
    BSR.B       ADB_FIND_DEVICE                 | find keyboard
    TST.B       D0                              | found?
    BEQ.B       ADB_ENSURE_MOUSE_LOOP           | yes: skip to mouse check
| No keyboard found: create default entry
    MOVE.B      #0x1,(A1)                       | handler_id = 1 (Apple keyboard)
    MOVE.B      #0x2,0x1(A1)                    | orig_addr = 2
    MOVE.B      #0x2,0x2(A1)                    | cur_addr = 2
    LEA.L       ADB_HANDLER_KBD(PC),A0          | A0 = keyboard handler routine
    MOVE.L      A0,0x4(A1)                      | set handler
ADB_ENSURE_MOUSE_LOOP:
    MOVEQ.L     #0x3,D0                         | D0 = 3 (mouse address)
    BSR.B       ADB_FIND_DEVICE                 | find mouse
    BEQ.B       ADB_ENSURE_MOUSE_RTS            | found: done
| No mouse found: create default entry
    MOVE.B      #0x1,(A1)                       | handler_id = 1 (Apple mouse)
    MOVE.B      #0x3,0x1(A1)                    | orig_addr = 3
    MOVE.B      #0x3,0x2(A1)                    | cur_addr = 3
    LEA.L       ADB_HANDLER_MOUSE(PC),A0        | A0 = mouse handler routine
    MOVE.L      A0,0x4(A1)                      | set handler
ADB_ENSURE_MOUSE_RTS:
    RTS                                         | return from ADB_ENSURE_MOUSE_RTS
| INSTALL_KCHR_KMAP - configure keyboard: load KCHR and KMAP resources
|
| For each keyboard device (orig_addr = 2), allocates a 50-byte
| key handler data block, loads 'KCHR' (key character mapping) and
| 'KMAP' (key layout mapping) resources from ROM, and installs them
| in the device table entry's data area pointer.
INSTALL_KCHR_KMAP:
    MOVEQ.L     #0x10,D1                        | D1 = 16 (max device entries)
    MOVEA.L     (ADBBase).W,A1                  | A1 = device table base
    BRA.B       INSTALL_KCHR_NEXT               | start scan
INSTALL_KCHR_LOOP:
    ADDA.W      #0xC,A1                         | advance to next entry
INSTALL_KCHR_NEXT:
    MOVEQ.L     #0x2,D0                         | D0 = 2 (keyboard orig_addr)
    CMP.B       0x1(A1),D0                      | is this a keyboard device?
    BNE.B       KEYTRANS_BODY                   | no: skip
| Allocate key handler data block (50 bytes, cleared)
    MOVEQ.L     #0x32,D0                        | D0 = 50 bytes
    _NewPtrSysClear                             | allocate zeroed sys heap block
    MOVEA.L     A0,A2                           | A2 = key handler data block
    MOVE.B      #0x2,0x1D(A2)                   | set pending ops count = 2
| Load 'KCHR' resource (key character mapping, ID 0)
    SUBQ.L      #0x4,A7                         | make room for result handle
    MOVE.L      #0x4B434852,-(A7)               | push 'KCHR' resource type
    CLR.W       -(A7)                           | push resource ID = 0
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | search ROM map first
    _GetResource                                | load KCHR resource
    MOVE.L      (A7)+,D0                        | D0 = KCHR handle
    BEQ.B       KEYTRANS_BODY                   | not found: skip keyboard
    MOVEA.L     D0,A0                           | A0 = KCHR handle
    MOVE.L      (A0),0x14(A2)                   | store KCHR pointer in data block
| Load 'KMAP' resource (key layout mapping, ID 0)
    SUBQ.L      #0x4,A7                         | make room for result handle
    MOVE.L      #0x4B4D4150,-(A7)               | push 'KMAP' resource type
    CLR.W       -(A7)                           | push resource ID = 0
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | search ROM map first
    _GetResource                                | load KMAP resource
    MOVE.L      (A7)+,D0                        | D0 = KMAP handle
    BEQ.B       KEYTRANS_BODY                   | not found: skip
    MOVEA.L     D0,A0                           | A0 = KMAP handle
    MOVE.L      (A0),(A2)                       | store KMAP pointer in data block
    MOVE.L      A2,0x8(A1)                      | devtbl[n].data = key handler block
    MOVE.B      (A1),(KbdType).W                | KbdType = handler ID
    MOVE.B      0x2(A1),(KeyLast).W             | KeyLast = current ADB address
KEYTRANS_BODY:
    DBF.W       D1,INSTALL_KCHR_LOOP            | next device entry
    RTS                                         | return from INSTALL_KCHR_KMAP
| KEYTRANS - _KeyTranslate trap: translate keycode to character(s)
|
| Per Inside Mac: Text, the KCHR resource defines a keycode-to-char
| mapping. This routine looks up the keycode in the KCHR tables,
| handles dead-key state, and returns up to 2 characters.
| Stack params: KCHR ptr, keycode+modifiers, dead-key state ptr
| Returns: 2 result words on stack (char1, char2)
KEYTRANS:
    MOVE.L      (A7)+,D0                        | D0 = return address
    MOVEA.L     (A7)+,A0                        | A0 = dead-key state pointer
    MOVE.W      (A7)+,D1                        | D1 = keycode + modifiers
    MOVEA.L     (A7)+,A1                        | A1 = KCHR resource pointer
    MOVE.L      D0,-(A7)                        | push return address back
    MOVEM.L     D3/A2,-(A7)                     | save work registers
| Look up modifier-to-table-number mapping
    MOVE.W      D1,D2                           | D2 = keycode + modifiers
    LSR.W       #0x8,D2                         | D2 = modifier byte (bits 8-15)
    MOVE.B      0x2(A1,D2.W),D2                 | D2 = table number from KCHR header
    MOVEQ.L     #0x7F,D0                        | D0 = 0x7F (keycode mask)
    AND.B       D1,D0                           | D0 = virtual keycode (0-127)
    EXT.W       D1                              | sign-extend keycode (for key up)
    EXT.L       D1                              | D1.L = signed keycode
    MOVE.B      D2,D1                           | D1.B = table number
    LSL.W       #0x8,D1                         | D1 = table<<8
    MOVE.B      D0,D1                           | D1 = table<<8 | keycode
    LSL.W       #0x7,D2                         | D2 = table * 128 (byte offset)
    OR.B        D1,D2                           | D2 = table*128 + keycode
    ADDA.W      #0x104,A1                       | A1 = KCHR char tables base (+260)
    MOVE.B      0x0(A1,D2.W),D0                 | D0 = character from table
    BEQ.B       KEYTRANS_DEAD_CHK               | zero: check dead-key sequence table
| Non-zero character: check for dead-key completion
    TST.L       D1                              | key up? (signed negative)
    BMI.B       KEYTRANS_RETURN                 | yes: return char as-is
    MOVE.L      (A0),D3                         | D3 = current dead-key state
    BEQ.B       KEYTRANS_RETURN                 | no dead-key: return char
    CLR.L       (A0)                            | clear dead-key state (consumed)
    LEA.L       0x0(A1,D3.L),A2                 | A2 = dead-key completion table
    MOVE.W      (A2)+,D2                        | D2 = number of completion entries
    BEQ.B       KEYTRANS_DEFAULT_CHAR           | empty: use default completion
    SUBQ.W      #0x1,D2                         | adjust for DBF
KEYTRANS_HAVE_DEAD:
    CMP.B       (A2)+,D0                        | match completion character?
    BEQ.B       KEYTRANS_NORMAL_CHAR            | yes: return completed char
    ADDQ.L      #0x1,A2                         | skip result byte
    DBF.W       D2,KEYTRANS_HAVE_DEAD           | try next entry
| Dead-key not matched: return default completion char
KEYTRANS_DEFAULT_CHAR:
    SWAP.W      D0                              | move char to high word (second result)
    MOVE.W      (A2),D0                         | D0 low = default completion char
    SWAP.W      D0                              | D0 = default:original (2 results)
    BRA.B       KEYTRANS_RETURN                 | return both characters
KEYTRANS_NORMAL_CHAR:
    MOVE.B      (A2),D0                         | D0 = matched completion character
    BRA.B       KEYTRANS_RETURN                 | return single character
| KEYTRANS_DEAD_CHK - zero char from table: check dead-key sequence table
KEYTRANS_DEAD_CHK:
    MOVE.W      -0x2(A1),D3                     | D3 = number of char tables
    LSL.W       #0x7,D3                         | D3 *= 128 (total table bytes)
    LEA.L       0x0(A1,D3.W),A2                 | A2 = dead-key sequence table
    MOVE.W      (A2)+,D2                        | D2 = number of dead-key seqs
    BEQ.B       KEYTRANS_RETURN                 | none: return zero
    SUBQ.W      #0x1,D2                         | adjust for DBF
KEYTRANS_DEAD_LOOKUP:
    CMP.W       (A2)+,D1                        | match table+keycode combo?
    BEQ.B       KEYTRANS_DEAD_MATCH             | yes: handle dead-key sequence
    MOVE.W      (A2)+,D3                        | skip sequence data
    LSL.W       #0x1,D3                         | D3 = entry size in bytes
    LEA.L       0x2(A2,D3.W),A2                 | advance past this entry
    DBF.W       D2,KEYTRANS_DEAD_LOOKUP         | try next sequence
| KEYTRANS_RETURN - KeyTranslate return: store result and return
| Called by: KEYTRANS, KEYTRANS_DEFAULT_CHAR, KEYTRANS_NORMAL_CHAR, KEYTRANS_DEAD_CHK, KEYTRANS_DEAD_DONE (and 2 more)
KEYTRANS_RETURN:
    MOVEM.L     (A7)+,D3/A2                     | restore work registers
    MOVE.L      D0,0x4(A7)                      | store 2 result chars on stack
    RTS                                         | return from _KeyTranslate
| KEYTRANS_DEAD_MATCH - dead-key sequence matched
KEYTRANS_DEAD_MATCH:
    TST.L       D1                              | key up? (signed negative)
    BMI.B       KEYTRANS_DEAD_NEXT              | yes: look up release char
    MOVE.L      (A0),D3                         | D3 = current dead-key state
    BEQ.B       KEYTRANS_DEAD_DONE              | no state: begin new dead-key
| Completing a dead-key sequence: look up completion char
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.W      0x0(A1,D3.L),D2                 | D2 = completion table entry count
    LSL.W       #0x1,D2                         | D2 *= 2 (byte size of entries)
    ADD.L       D2,D3                           | advance past entries
    MOVE.W      0x2(A1,D3.L),D0                 | D0 = completed character
KEYTRANS_DEAD_DONE:
    TST.W       (A2)                            | has completion entries?
    BEQ.B       KEYTRANS_DEAD_NOMATCH           | no: terminal dead-key
    MOVE.L      A2,D2                           | D2 = completion table ptr
    SUB.L       A1,D2                           | D2 = offset from KCHR base
    MOVE.L      D2,(A0)                         | save dead-key state
    BRA.B       KEYTRANS_RETURN                 | return (pending dead-key)
KEYTRANS_DEAD_NOMATCH:
    CLR.L       (A0)                            | clear dead-key state (sequence done)
    SWAP.W      D0                              | move first char to high
    MOVE.W      0x2(A2),D0                      | D0 low = final char
    BRA.B       KEYTRANS_RETURN                 | return both chars
KEYTRANS_DEAD_NEXT:
    MOVE.W      (A2)+,D3                        | D3 = sequence entry count
    LSL.W       #0x1,D3                         | D3 *= 2
    MOVE.W      0x0(A2,D3.W),D0                 | D0 = key-up char
    BRA.B       KEYTRANS_RETURN                 | return
| ZERO_KEYMAP - clear keyboard state (KeyMap + KbdVers)
|
| Called during ADB init to reset all key-down flags.
ZERO_KEYMAP:
    LEA.L       (KeyMap).W,A0                   | A0 = KeyMap (16 bytes + extras)
    MOVEQ.L     #0x8,D0                         | D0 = 8 words (18 bytes)
KBD_RESET_KEYMAP:
    CLR.W       (A0)+                           | clear next word
    DBF.W       D0,KBD_RESET_KEYMAP             | clear all keyboard state
    CLR.L       (KbdVers).W                     | clear auto-key message cache
    RTS                                         | return from KBD_RESET_KEYMAP
