| Device Manager
|
| Apple source: the I/O core (MacSEROM.lst module IOCORE). It starts with
| the offset table INSTDISP_TAIL_PADDING, from which startup sets the jump
| vectors JFetch, JStash and JIODone, followed by Fetch/Stash
| (FETCH_STASH_COMMON: next byte of a driver's I/O buffer) and IODone, the
| request queueing and dispatch, and the traps Open, Close, Read, Write,
| Control, Status, KillIO, DrvrInstall and DrvrRemove. For a file
| reference number Open/Close/Read/Write go on to the File Manager.
|
| Driver resource header (Inside Macintosh: Devices, Fig 1-6):
| Offset 0: drvrFlags INTEGER driver flags
| Offset 2: drvrDelay INTEGER ticks between periodic actions
| Offset 4: drvrEMask INTEGER desk accessory event mask
| Offset 6: drvrMenu INTEGER desk accessory menu ID
| Offset 8: drvrOpen INTEGER offset to open routine
| Offset 10: drvrPrime INTEGER offset to prime (read/write) routine
| Offset 12: drvrCtl INTEGER offset to control routine
| Offset 14: drvrStatus INTEGER offset to status routine
| Offset 16: drvrClose INTEGER offset to close routine
| Offset 18: drvrName STRING Pascal string (length byte + name)
|
| DCtlEntry - Device Control Entry (40 bytes, MPW 1.0 Devices.h):
| Offset 0: dCtlDriver Ptr ROM driver ptr or RAM handle
| Offset 4: dCtlFlags INTEGER driver flags
| Offset 6: dCtlQHdr QHdr driver I/O queue (10 bytes)
| Offset 16: dCtlPosition LongInt byte position for Read/Write
| Offset 20: dCtlStorage Handle driver's private storage
| Offset 24: dCtlRefNum INTEGER reference number (-1 to -32)
| Offset 26: dCtlCurTicks LongInt ticks at last periodic call
| Offset 30: dCtlWindow GrafPtr driver's window (desk accessories)
| Offset 34: dCtlDelay INTEGER ticks between periodic actions
| Offset 36: dCtlEMask INTEGER event mask (desk accessories)
| Offset 38: dCtlMenu INTEGER menu ID (desk accessories)
|
| IOParam - I/O parameter block (50 bytes, MPW 1.0 Files.h):
| Offset 0: qLink Ptr next queue entry
| Offset 4: qType INTEGER queue type
| Offset 6: ioTrap INTEGER trap word
| Offset 8: ioCmdAddr Ptr address of routine
| Offset 12: ioCompletion ProcPtr completion routine
| Offset 16: ioResult OSErr result code
| Offset 18: ioNamePtr StringPtr driver/volume name
| Offset 22: ioVRefNum INTEGER volume reference number
| Offset 24: ioRefNum INTEGER driver reference number
| Offset 26: ioVersNum BYTE version number
| Offset 27: ioPermssn BYTE permission (fsCurPerm=0,fsRdPerm=1,fsWrPerm=2)
| Offset 28: ioMisc LongInt misc (varies by call)
| Offset 32: ioBuffer Ptr data buffer
| Offset 36: ioReqCount LongInt requested byte count
| Offset 40: ioActCount LongInt actual byte count
| Offset 44: ioPosMode INTEGER positioning mode (fsAtMark=0,fsFromStart=1)
| Offset 46: ioPosOffset LongInt positioning offset
|
| CntrlParam - Control/Status parameter block (50 bytes, MPW 1.0 Devices.h):
| Offset 0-22: same as IOParam header
| Offset 24: ioCRefNum INTEGER driver reference number
| Offset 26: csCode INTEGER control/status code
| Offset 28: csParam[11] 22 bytes control/status parameters
|
| References:
| MPW 1.0 Devices.h, Apple Computer Inc. 1985-1986
| Inside Macintosh: Devices, Ch 1: Device Manager (pp 1-3 to 1-58)
| Inside Macintosh Vol II, Ch 6: The Device Manager (pp 173-208)

| ----------------------------------------------------------
| INSTDISP_TAIL_PADDING ($10C4) -- not padding: the 3-word offset table
| from which INIT_MEMORY_MAP (via JmpTblInit) sets JFetch, JStash and
| JIODone; offsets are relative to $10C4: $0006 -> $10CA Fetch (the
| BCLR #15,D0 hidden in the next two lines, falling into
| FETCH_STASH_COMMON), $004A -> $110E Stash (after IO_CORE_ERR),
| $0052 -> $1116 (IODone + 2). The bytes are kept as the two ORI
| instructions FDisasm decoded them as.
INSTDISP_TAIL_PADDING:
        ORI.B   #0x4A,D6                        | data: $0006 (JFetch), $004A (JStash)
        ORI     #0x880,(A2)                     | data: $0052 (JIODone); $10CA: $0880 = BCLR
        .short  0x000F                          | BCLR #15,D0: the Fetch entry (JFetch)

| ----------------------------------------------------------
| FETCH_STASH_COMMON -- driver helper used by char-mode drivers (.AIn,
| .Sound etc.) for next-byte read/write through a circular buffer
| on a DCE (Device Control Entry).
| Entry: A1 = DCE ptr, D0 = byte (.W or .B); bit 0xF of D0 = "write"
| On entry, 8(A1) = QHdr ptr (queue of pending requests).
| Exit: CCR.Z=1 if buffer space exhausted (D0 bit 0xF set).
FETCH_STASH_COMMON:
        MOVEM.L D1/A2-A3,-(SP)                  | save work regs
        MOVE.L  8(A1),D1                        | D1 = current request ptr
        BEQ.B   IO_CORE_ERR                     | nil request: fatal dsIOCoreErr
        MOVE.L  D1,A3                           | A3 = request ptr (mutable)
        MOVE.L  ioActCount(A3),D1               | D1 = byte index (ioActCount)
        MOVE.L  ioBuffer(A3),A2                 | A2 = buffer base (ioBuffer)
        BCLR    #0xF,D0                         | test+clear write-mode bit in D0
        BNE.B   FETCH_STASH_WRITE               | bit set: write D0 byte to buffer
        MOVE.B  0(A2,D1.L),D0                   | read: D0 = buffer[D1]
        BRA.B   FETCH_STASH_ADVANCE             | bump index + check end
FETCH_STASH_WRITE:
        MOVE.B   D0,0(A2,D1.L)                  | buffer[D1] = D0
FETCH_STASH_ADVANCE:
        ADDQ.L  #0x1,D1                         | byte index += 1
        MOVE.L  D1,ioActCount(A3)               | store updated ioActCount
        CMP.L   ioReqCount(A3),D1               | compare with ioReqCount (limit)
        BLT.B   FETCH_STASH_EXIT                | not yet at limit: return
        BSET    #0xF,D0                         | set bit 0xF: signal "buffer full"
FETCH_STASH_EXIT:
        TST     D0                              | set CCR for caller
        MOVEM.L (SP)+,D1/A2-A3                  | restore work regs
        RTS                                     | return to caller with Z flag reflecting status
| ----------------------------------------------------------
| IO_CORE_ERR -- fatal I/O core error (no active request, bad qType, etc.)
| Reached when the I/O queue or DCE is in an inconsistent state.
| Calls _SysError with dsIOCoreErr (id 14) and never returns. The
| BSET/BRA after it is the separate Stash entry ($110E, the JStash
| vector, see INSTDISP_TAIL_PADDING): D0 bit 15 set = write.
IO_CORE_ERR:                                    | fatal dsIOCoreErr
        MOVEQ.L #0xE,D0                         | D0 = 14 = dsIOCoreErr
        _SysError                               | halt system with fatal I/O error
        BSET    #0xF,D0                         | Stash entry ($110E, via JStash): write
        BRA.B   FETCH_STASH_COMMON              | store D0.B in the request's buffer

| ----------------------------------------------------------
| IODone -- complete the current I/O request of a driver. JIODone
| points 2 bytes in ($1116, D0 = result code); entering at IODone
| itself ($1114) completes the request with noErr.
| Walks the I/O queue at A1 (= DCE), removes the just-completed
| request from the queue head, runs ioCompletion if installed,
| then returns to the next pending request (or RTE if none).
| Entry: A1 = DCE ptr, D0 = result code
IODone:                                         | noErr entry ($1114)
        MOVEQ.L #0x0,D0                         | D0 = noErr; JIODone enters at the next line
        MOVE.L  8(A1),A0                        | A0 = head of pending IO queue
        BTST    #0x1,6(A0)                      | bit 1 of dCtlFlags: I/O active?
        BNE.B   UNLOCK_DRV_CHECK                | yes: skip lock-release (we own it)
        MOVE    SR,-(SP)                        | save SR (interrupt state)
        MOVE    SR,D1                           | D1 = saved SR (for restore later)
        ORI     #0x300,SR                       | mask interrupts (IPL=3)
        BSR.B   CLEAR_DRV_BUSY                  | clear dCtlFlags bit 7 (locked)
        BSR.B   DEQUEUE_IOREQ                   | pop completed request, run completion
        TST.L   8(A1)                           | another request still queued?
        BNE.B   DISPATCH_NEXT_REQ               | yes: continue dispatch
        RTE                                     | done: return from interrupt
CLEAR_DRV_BUSY:
        BCLR    #0x7,5(A1)                      | clear drvrActive (bit 7 of the low flag byte)
UNLOCK_DRV_CHECK:
        BTST    #0x6,4(A1)                      | dNeedLock (bit 6 of the high flag byte)?
        BNE.B   UNLOCK_DRV_DONE                 | yes: leave the driver locked
        MOVE.L  (A1),A0                         | A0 = handle to driver (qLink slot)
        BCLR    #0x7,(A0)                       | release lock-byte in master ptr
        MOVE.L  (SysZone).w,A0                  | A0 = system zone header
        ADDA.L  -4(A1),A0                       | A0 += offset (zone-relative back-ptr)
        BCLR    #0x7,(A0)                       | release lock-byte on heap block
UNLOCK_DRV_DONE:
        RTS                                     | return from unlock
DEQUEUE_IOREQ:
        MOVE.L  8(A1),A0                        | A0 = head request (the one completing)
        CMPI    #0x2,4(A0)                      | qType field == 2 (IOQType)?
        BNE.B   IO_CORE_ERR                     | wrong qType: fatal dsIOCoreErr
        MOVE.L  (A0),8(A1)                      | dequeue: head = old.qLink
        BNE.B   DEQUEUE_RESTORE_SR              | more queued: keep tail intact
        CLR.L   12(A1)                          | empty queue: tail = nil
DEQUEUE_RESTORE_SR:
        MOVE    D1,SR                           | restore SR (re-enable interrupts)
        MOVE    D0,16(A0)                       | store result in ioResult field
        BLE.B   DEQUEUE_CHK_COMPL               | result <= 0 (ok or err): keep sign
        NEG     16(A0)                          | result > 0: negate (force noErr/-)
DEQUEUE_CHK_COMPL:
        MOVE.L  12(A0),D1                       | D1 = ioCompletion proc ptr
        BEQ.B   DEQUEUE_DONE                    | nil: no callback, return
        MOVE.L  A1,-(SP)                        | save A1 (the DCE ptr)
        MOVE.L  D1,A1                           | A1 = completion proc
        TST     D0                              | set CCR from result code (handler arg)
        JSR     (A1)                            | call ioCompletion(D0=result, A0=IOParam)
        MOVE.L  (SP)+,A1                        | restore DCE ptr
DEQUEUE_DONE:                                   | common return from IODone
        RTS                                     | return from _IODone trap

| ----------------------------------------------------------
| ENQUEUE_IOREQ -- enqueue an I/O request and dispatch if driver idle
| Common entry from the OS-trap dispatcher for _Read / _Write / _Control
| / _Status. Adds the IOParam (A0) to the driver's dCtlQueue, then if
| the driver was not already busy, kicks off the head request.
| Entry: A0 = IOParam, A1 = DCE pointer
ENQUEUE_IOREQ:                                  | common queue+dispatch
        MOVE.L  A1,D1                           | save DCE pointer in D1
        LEA.L   dCtlQueue(A1),A1                | A1 = &dCtlQueue (queue header at DCE+6)
        JSR     Enqueue(PC)                     | enqueue IOParam (A0) into driver queue
        MOVE.L  D1,A1                           | restore A1 = DCE pointer
        MOVE    SR,-(SP)                        | save SR for IPL restore
        ORI     #0x300,SR                       | raise IPL=3 (protect queue manipulation)
DISPATCH_NEXT_REQ:                              | kick the head request if idle
        BSET    #0x7,5(A1)                      | test+set busy bit (dCtlFlags bit 7)
        BEQ.B   START_HEAD_REQ                  | was not busy: start head request
        MOVEQ.L #0x0,D0                         | already busy: queued, return noErr
        RTE                                     | restore SR and return to trap caller
START_HEAD_REQ:                                 | driver was idle, dispatch head
        MOVE    (SP)+,SR                        | restore SR (lower IPL)
        MOVE.L  dCtlQHead(A1),A0                | A0 = dCtlQHead (head IOParam in queue)
START_HEAD_IOPARAM:                             | dispatch by ioTrap low byte
        MOVEQ.L #drvrCtl,D1                     | D1 = drvrCtl offset ($0C)
        CMPI.B  #0x4,ioTrap+1(A0)               | ioTrap low byte = 4? (_Control)
        BEQ.B   CALL_DRV_ENTRY                  | yes: dispatch to driver Control entry
        MOVEQ.L #drvrStatus,D1                  | D1 = drvrStatus offset ($0E)
        CMPI.B  #0x5,ioTrap+1(A0)               | ioTrap low byte = 5? (_Status)
        BEQ.B   CALL_DRV_ENTRY                  | yes: dispatch to driver Status entry
        TST.L   ioReqCount(A0)                  | ioReqCount = 0? (no data to transfer)
        BEQ.W   IODone                          | zero-length: complete with noErr
        MOVE    ioPosMode(A0),D0                | D0 = ioPosMode (positioning mode + flags)
        MOVE.L  ioPosOffset(A0),D1              | D1 = ioPosOffset (requested file position)
        ROXR.B  #0x2,D0                         | shift positioning bits into carry+sign
        BPL.B   IO_PRIME_ENTRY                  | mode = fsAtMark (0): don't update position
        BCC.B   IO_SET_POSITION                 | mode = fsFromStart (1): use offset directly
        ADD.L   dCtlPosition(A1),D1             | mode = fsFromMark (3): offset relative to dCtlPosition
IO_SET_POSITION:
        MOVE.L  D1,dCtlPosition(A1)             | update dCtlPosition to new file position
IO_PRIME_ENTRY:                                 | fall through to CALL_DRV_ENTRY
        MOVEQ.L #drvrPrime,D1                   | D1 = drvrPrime offset ($0A)

| ----------------------------------------------------------
| CALL_DRV_ENTRY -- call a driver entry point (Open/Prime/Ctl/Status)
| A1 = DCE pointer, A0 = IOParam block, D1 = entry-point offset within
| driver header (drvrOpen=$08, drvrPrime=$0A, drvrCtl=$0C, drvrStatus=$0E).
| For RAM-based drivers, loads and locks the driver resource handle, then
| dispatches via JSR through the entry-point offset.
CALL_DRV_ENTRY:                                 | common driver call
        MOVE.L  (A1),D0                         | D0 = dCtlDriver (handle or pointer to driver)
        BNE.B   CALL_DRV_LOCK                   | driver exists: proceed to call it
        MOVEQ.L #-0x16,D0                       | unitEmptyErr (-22): no driver installed
        MOVE    D0,ioResult(A0)                 | store error in IOParam.ioResult
        RTS                                     | return error to caller
CALL_DRV_LOCK:                                  | lock RAM driver before call
        MOVEM.L D3-D7/A1-A6,-(SP)               | save all registers (driver may use any)
        MOVE.L  (A1),A2                         | A2 = handle (RAM) or pointer (ROM) to driver
        BTST    #0x6,5(A1)                      | dCtlFlags bit 6: dRAMBased?
        BEQ.B   CALL_DRV_EXEC                   | ROM-based: A2 is direct pointer, skip locking
        MOVE.L  (SysZone).w,A3                  | A3 = system heap zone header
        ADDA.L  -4(A1),A3                       | A3 += relative-handle offset to block header
        BSET    #0x7,(A3)                       | lock driver block in heap
        TST.L   (A2)                            | dereference handle: master pointer nil?
        BNE.B   CALL_DRV_LOCK_HDL               | not purged: proceed
        MOVE.L  A2,-(SP)                        | push handle for _LoadResource
        _LoadResource                           | reload purged driver resource
        MOVE    (ResErr).w,D0                   | D0 = Resource Manager error
        BNE.B   CALL_DRV_LOADFAIL               | load failed: store error and exit
CALL_DRV_LOCK_HDL:                              | lock handle's master pointer
        BSET    #0x7,(A2)                       | set lock-bit in master pointer
        MOVE.L  (A2),-(SP)                      | push dereferenced master pointer
        CLR.B   (SP)                            | strip lock/flag bits from high byte
        MOVE.L  (SP)+,A2                        | A2 = clean driver code pointer
CALL_DRV_EXEC:                                  | JSR into driver entry
        MOVE    0(A2,D1.W),D1                   | D1 = entry-point offset from driver header
        MOVEQ.L #0x0,D0                         | clear D0 before driver call
        JSR     0(A2,D1.W)                      | call driver entry (A0=IOParam, A1=DCE)
        BRA.B   CALL_DRV_EXIT                   | restore and return
CALL_DRV_LOADFAIL:                              | _LoadResource failure path
        MOVE    D0,ioResult(A0)                 | store ResErr result in IOParam.ioResult
CALL_DRV_EXIT:                                  | restore and return
        MOVEM.L (SP)+,D3-D7/A1-A6               | restore all work registers
        RTS                                     | return from driver call
| ----------------------------------------------------------
| LOOKUP_UNIT -- look up a driver in the unit table by refNum
| D2 = driver refNum (negated unit number - 1). Converts to the unit
| number, bounds-checks against UnitTableEntryCount, dereferences the
| DCE handle from the unit table slot. On success, A1 = DCE pointer;
| A2 = DCE handle. On any failure, branches to UNIT_EMPTY_ERR which
| returns unitEmptyErr (-21) to the caller.
LOOKUP_UNIT:
        NOT     D2                              | refNum -> unit number (~refNum)
        BMI.B   UNIT_EMPTY_ERR                  | negative unit number: invalid refNum
        CMP     (UnitTableEntryCount).w,D2      | unit number >= table size?
        BGE.B   UNIT_EMPTY_ERR                  | out of range: error
        ASL     #0x2,D2                         | unit number * 4 = table-byte offset
        MOVE.L  (UTableBase).w,A1               | A1 = base of unit table
        MOVE.L  0(A1,D2.W),D2                   | D2 = DCE handle from slot
        BEQ.B   UNIT_EMPTY_ERR                  | nil handle: no driver installed
        MOVE.L  D2,A2                           | A2 = DCE handle (for caller)
        MOVE.L  (A2),D2                         | D2 = dereferenced DCE pointer
        BEQ.W   IO_CORE_ERR                     | nil pointer (purged DCE): fatal dsIOCoreErr
        MOVE.L  D2,A1                           | A1 = DCE pointer (for caller)
        RTS                                     | return with DCE handle/pointer
| ----------------------------------------------------------
| UNIT_EMPTY_ERR -- failure path for LOOKUP_UNIT (driver not found)
UNIT_EMPTY_ERR:
        MOVEM.L (SP)+,D0/D3-D5/A2-A3            | restore caller's saved registers
        MOVEQ.L #-0x15,D0                       | unitEmptyErr (-21): no driver in slot
        RTS                                     | return error to OS-trap caller
| ----------------------------------------------------------
| Open ($A000) -- open a driver by name (or fall through to File Manager)
| A0 = paramBlock (IOParam), D1 = trap word.
| Searches first by 'DRVR' resource ID (if SysMap is loaded), then falls
| back to a unit-table scan-by-name. refNum = -(unitNum+1) is returned
| in ioRefNum of paramBlock. Called during boot.
Open:                                           | _Open trap entry
        MOVEM.L D3-D5/A2-A3,-(SP)               | save work registers
        MOVE.L  A0,D5                           | D5 = saved paramBlock ptr
        MOVE    D1,ioTrap(A0)                   | save trap word in ioTrap
        TST     (SysMap).w                      | resource map loaded yet?
        BMI.B   OPEN_SCAN_UNIT_TBL              | no SysMap (boot): skip resource lookup
        SUBQ.W  #0x4,SP                         | space for _GetNamedResource handle
        MOVE.L  #0x44525652,-(SP)               | push resource type 'DRVR'
        MOVE.L  ioFileName(A0),A3               | A3 = pointer to driver name (Pascal string)
        MOVE.L  A3,-(SP)                        | push name pointer
        _GetNamedResource                       | -> handle on stack (or 0 + ResErr)
        MOVE.L  (SP)+,D3                        | D3 = DRVR resource handle (or nil)
        BEQ.B   OPEN_SCAN_UNIT_TBL              | nil handle: fall back to unit-table scan
        MOVE    (ResErr).w,D0                   | check for Resource Manager error
        BNE.B   OPEN_CHK_INSTALL                | non-zero error: skip install
        LINK    A6,#-0x10E                      | local frame for _GetResInfo (270 bytes name buf)
        MOVE.L  D3,-(SP)                        | push DRVR handle
        PEA.L   -4(A6)                          | push &resID (word slot)
        PEA.L   -8(A6)                          | push &type slot
        PEA.L   -0x10E(A6)                      | push &name slot (255-byte Pascal string)
        _GetResInfo                             | fetch DRVR's resource ID
        MOVE    -4(A6),D4                       | D4 = DRVR resource ID (= unit number)
        NOT     D4                              | D4 = refNum = ~unitNum
        UNLK    A6                              | tear down local frame
        MOVE    D4,D0                           | D0 = refNum for slot lookup
        BSR.W   LOOKUP_UNIT_SLOT                | A2 = unit-table slot for this refNum
        BNE.B   OPEN_INIT_DCE                   | DCE already exists: skip _DrvrInstall
        MOVE    D4,D0                           | D0 = refNum for _DrvrInstall
        _DrvrInstall                            | allocate fresh DCE in slot D0
OPEN_CHK_INSTALL:                               | after install / lookup
        BNE.W   OPEN_EXIT                       | install failed: bail with D0=err
OPEN_INIT_DCE:                                  | initialize DCE from DRVR header
        MOVE    D4,D2                           | D2 = refNum for LOOKUP_UNIT
        BSR.W   LOOKUP_UNIT                     | A1 = DCE ptr, A2 = DCE handle
        MOVE.L  D3,(A1)                         | dCtlDriver = DRVR resource handle
        MOVE.L  D3,A0                           | A0 = DRVR resource handle
        MOVE.L  (A0),A0                         | A0 = deref'd DRVR header ptr
        MOVE    (A0)+,dCtlFlags(A1)             | copy drvrFlags -> dCtlFlags
        MOVE.L  (A0)+,dCtlDelay(A1)             | copy drvrDelay+drvrEMask
        MOVE    (A0)+,dCtlMenu(A1)              | copy drvrMenu
        BCLR    #0x7,5(A1)                      | clear runtime "busy" bit
        BSET    #0x6,5(A1)                      | set dRAMBased bit (loaded via Resource Mgr)
        BRA.B   OPEN_LOCK_DRIVER                | go lock + check perms
| ----------------------------------------------------------
| OPEN_SCAN_UNIT_TBL -- fallback: scan unit table for DCE matching name
| Walks 10 unit-table entries (D2=9 down to 0) checking each DCE's
| dCtlDriver name field against ioFileName. Used during boot when
| SysMap is not yet loaded, or when GetNamedResource returns nil.
OPEN_SCAN_UNIT_TBL:
        MOVE.L  D5,A0                           | A0 = paramBlock ptr
        MOVE.L  (UTableBase).w,A3               | A3 = base of unit table
        MOVEQ.L #0x9,D2                         | D2 = 9 (loop count: 10 slots)
        MOVEQ.L #-0x1,D4                        | D4 = refNum counter, starts at -1
OPEN_SCAN_NEXT_ENTRY:                           | iteration body
        MOVE.L  (A3)+,D0                        | D0 = next DCE handle
        BEQ.B   OPEN_SCAN_NEXT                  | nil handle: skip
        MOVE.L  D0,A2                           | A2 = DCE handle
        MOVE.L  (A2),D0                         | D0 = dereferenced DCE pointer
        BEQ.B   OPEN_SCAN_NEXT                  | nil pointer: skip
        MOVE.L  D0,A1                           | A1 = DCE pointer
        BTST    #0x6,5(A1)                      | dCtlFlags+1 bit 6: dRAMBased?
        BNE.B   OPEN_SCAN_NEXT                  | RAM driver: skip (only ROM scanned)
        MOVEM.L A0-A1,-(SP)                     | save A0/A1 across _CmpString
        MOVE.L  ioFileName(A0),A0               | A0 = requested driver name
        MOVE.L  (A1),A1                         | A1 = dCtlDriver pointer
        LEA.L   18(A1),A1                       | A1 = drvrName (offset 18 in DRVR header)
        MOVEQ.L #0x0,D0                         | clear D0 for length-byte assembly
        MOVE.B  (A0)+,D0                        | D0.lo = requested name length
        SWAP    D0                              | D0.hi = requested length (for _CmpString)
        MOVE.B  (A1)+,D0                        | D0.lo = driver name length
        _CmpString                              | compare strings; CCR.Z set on match
        MOVEM.L (SP)+,A0-A1                     | restore A0/A1
        BEQ.B   OPEN_LOCK_DRIVER                | match: go lock + permission check
OPEN_SCAN_NEXT:                                 | advance to next slot
        SUBQ.W  #0x1,D4                         | refNum--
        SUBQ.W  #0x1,D2                         | loop count--
        BGT.B   OPEN_SCAN_NEXT_ENTRY            | more slots: continue
        MOVE    ioTrap(A0),D1                   | restore trap word
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore registers
        JMP     FileOpen(PC)                    | not found: forward to File Manager Open
| ----------------------------------------------------------
| OPEN_LOCK_DRIVER -- driver located, lock memory and check permissions
| A1 = DCE pointer, A2 = DCE handle, D4 = refNum, D5 = paramBlock ptr.
OPEN_LOCK_DRIVER:
        BTST    #0x6,dCtlFlags(A1)              | drvrFlags bit 6: dNeedLock?
        BEQ.B   OPEN_CHK_PERM                   | not needed: skip lock
        MOVEQ.L #0x8,D0                         | D0 high = 8 (CompactMem requested size hi)
        SWAP    D0                              | shift into high half: $00080000 bytes
        _CompactMem                             | compact heap to make room for locked driver
        MOVE.L  (A1),A0                         | A0 = dCtlDriver handle
        BSET    #0x7,(A0)                       | lock DRVR handle's master pointer
        BSET    #0x7,(A2)                       | lock DCE handle's master pointer
| ----------------------------------------------------------
| OPEN_CHK_PERM -- check requested permission against driver capabilities
OPEN_CHK_PERM:
        MOVE.L  D5,A0                           | A0 = paramBlock ptr
        MOVE    D4,ioRefNum(A0)                 | return refNum to caller in paramBlock
        MOVEQ.L #-0x17,D0                       | D0 = -23 (openErr: incompatible permission)
        MOVE.B  dCtlFlags(A1),D1                | D1 = driver capability flags (rd/wr/ctl/stat)
        MOVE    D1,D2                           | D2 = save original capability bits
        OR.B    ioPermssn(A0),D1                | combine requested perm with capabilities
        EOR.B   D2,D1                           | isolate bits set in request but not in driver
        ANDI.B  #0x3,D1                         | mask read+write enable bits
        BNE.B   OPEN_EXIT                       | requested unsupported permission: openErr
        BSET    #0x5,5(A1)                      | set dOpened bit (driver is now open)
        BNE.B   OPEN_RET_NOERR                  | was already open: return noErr
        MOVEQ   #drvrOpen,D1                    | D1 = drvrOpen offset in DRVR header
        BSR.W   CALL_DRV_ENTRY                  | call driver's open entry point
        BTST    #0x6,dCtlFlags(A1)              | drvrFlags bit 6: dNeedLock?
        BNE.B   OPEN_RET_NOERR                  | locked driver: keep locks, return D0
        MOVEQ.L #0x0,D0                         | clear D0 (force noErr below)
| ----------------------------------------------------------
| OPEN_UNLOCK_RAM -- fall-through unlock path for non-locked RAM drivers
OPEN_UNLOCK_RAM:
        MOVE.L  (A1),A0                         | A0 = dCtlDriver handle
        BCLR    #0x7,(A0)                       | unlock DRVR handle's master pointer
        BCLR    #0x7,(A2)                       | unlock DCE handle's master pointer
OPEN_EXIT:                                      | common exit (D0 holds result)
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore work registers
        RTS                                     | return to trap dispatcher
OPEN_RET_NOERR:                                 | set D0=0, fall to OPEN_EXIT
        MOVEQ.L #0x0,D0                         | D0 = 0 (noErr)
        BRA.B   OPEN_EXIT                       | restore + return
| ----------------------------------------------------------
| Close ($A001) -- close a driver by refNum (or fall through to File Manager)
| A0 = paramBlock, D0 = error. Positive ioRefNum -> file close (FileMgr);
| negative -> CLOSE_DEVICE.
Close:                                          | _Close trap entry
        MOVE    ioRefNum(A0),D2                 | D2 = ioRefNum
        BMI.B   CLOSE_DEVICE                    | negative: device driver close
        JMP     FileClose(PC)                   | positive: File Manager close
| ----------------------------------------------------------
| CLOSE_DEVICE -- device driver close path
| Spin-waits while driver is busy, calls drvrClose, clears dOpened.
CLOSE_DEVICE:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        BSR.W   LOOKUP_UNIT                     | A1 = DCE ptr, A2 = DCE handle
        BTST    #0x5,5(A1)                      | dOpened bit set?
        BEQ.B   OPEN_RET_NOERR                  | not open: return noErr
CLOSE_WAIT_BUSY:                                | spin until driver idle
        BTST    #0x7,5(A1)                      | drvrActive bit (busy)?
        BNE.B   CLOSE_WAIT_BUSY                 | yes: keep spinning
        MOVEQ.L #drvrClose,D1                   | D1 = drvrClose offset ($10) in DRVR header
        BSR.W   CALL_DRV_ENTRY                  | call driver's close routine
        BCLR    #0x5,5(A1)                      | clear dOpened bit
        BRA.B   OPEN_UNLOCK_RAM                 | unlock + restore + return
| ----------------------------------------------------------
| Read ($A002) -- read bytes from a driver (or fall through to File Manager)
| A0 = paramBlock, D0 = error. Positive ioRefNum -> file read; negative
| -> READ_DEVICE.
Read:                                           | _Read trap entry
        MOVE    ioRefNum(A0),D2                 | D2 = ioRefNum
        BMI.B   READ_DEVICE                     | negative: device read
        JMP     L_mFileRead(PC)                 | positive: File Manager read
| ----------------------------------------------------------
| READ_DEVICE -- device driver read path (D0=-19=readErr, D4=0=dReadEnable)
READ_DEVICE:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVEQ.L #-0x13,D0                       | D0 = -19 (readErr default)
        MOVEQ.L #0x0,D4                         | D4 = 0 = dReadEnable bit position
| ----------------------------------------------------------
| DEVIO_COMMON -- shared Read/Write/Control entry path
| D0 = default error, D2 = refNum, D4 = enable-bit position.
DEVIO_COMMON:
        BSR.W   LOOKUP_UNIT                     | A1 = DCE ptr, A2 = DCE handle
        CMPI.B  #0x3,D1                         | trap low byte <= 3? (Read=2, Write=3)
        BGT.B   DEVIO_SET_INPROGRESS            | Status/KillIO: skip ioActCount reset
        CLR.L   ioActCount(A0)                  | ioActCount = 0 (no bytes transferred yet)
DEVIO_SET_INPROGRESS:
        MOVE    #0x1,ioResult(A0)               | ioResult = 1 (in progress, not yet complete)
        MOVE    D1,ioTrap(A0)                   | save trap word in ioTrap
        MOVE    #ioQType,qType(A0)              | qType = ioQType (2) for I/O queue
        BTST    D4,dCtlFlags(A1)                | enable bit set in driver capabilities?
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore work registers
        BEQ.B   DEVIO_STORE_RESULT              | not enabled: return default error in D0
        MOVEQ.L #-0x1C,D0                       | D0 = -28 (notOpenErr: driver not open)
        BTST    #0x5,5(A1)                      | dOpened bit set?
        BEQ.B   DEVIO_STORE_RESULT              | not open: notOpenErr
        BTST    #0x9,D1                         | trap word bit 9 = immediate flag
        BNE.W   START_HEAD_IOPARAM              | immediate: bypass queue, call driver directly
        BTST    #0xA,D1                         | trap word bit 10 = async flag
        BNE.W   ENQUEUE_IOREQ                   | async: enqueue and return immediately
        CLR.L   ioCompletion(A0)                | synchronous: no completion routine
        MOVE.L  A0,-(SP)                        | save paramBlock ptr across BSR
        BSR.W   ENQUEUE_IOREQ                   | enqueue + dispatch the I/O request
        MOVE.L  (SP)+,A0                        | restore paramBlock ptr
DEVIO_POLL_RESULT:                              | synchronous poll loop
        MOVE    ioResult(A0),D0                 | D0 = current ioResult
        BGT.B   DEVIO_POLL_RESULT               | > 0 (in progress): keep polling
DEVIO_STORE_RESULT:                             | RTS (D0 already in ioResult)
        RTS                                     | return to trap dispatcher
| ----------------------------------------------------------
| Write ($A003) -- write bytes to a driver (or fall through to File Manager)
Write:                                          | _Write trap entry
        MOVE    ioRefNum(A0),D2                 | D2 = ioRefNum
        BMI.B   WRITE_DEVICE                    | negative: device write
        JMP     FileWrite(PC)                   | positive: File Manager write
| ----------------------------------------------------------
| WRITE_DEVICE -- device driver write path (D0=-20=writErr, D4=1=dWritEnable)
WRITE_DEVICE:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVEQ.L #-0x14,D0                       | D0 = -20 (writErr default)
        MOVEQ.L #0x1,D4                         | D4 = 1 = dWritEnable bit position
        BRA.B   DEVIO_COMMON                    | join shared dispatch
| ----------------------------------------------------------
| Control ($A004) -- driver control call (no file-side equivalent)
| D0 = -17 (controlErr default), D4 = 2 (dCtlEnable bit position).
Control:                                        | _Control trap entry
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE    ioRefNum(A0),D2                 | D2 = driver refNum
        MOVEQ.L #-0x11,D0                       | D0 = -17 (controlErr default)
        MOVEQ.L #0x2,D4                         | D4 = 2 = dCtlEnable bit position
        BRA.B   DEVIO_COMMON                    | join shared dispatch
| ----------------------------------------------------------
| Status ($A005) -- driver status query (no file-side equivalent)
| csCode == 1 is special: returns DCE handle in ioMisc without calling driver.
Status:                                         | _Status trap entry
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE    ioRefNum(A0),D2                 | D2 = driver refNum
        CMPI    #0x1,26(A0)                     | csCode == 1? (return DCE handle)
        BEQ.B   STATUS_GET_DCE                  | yes: short-circuit, return handle
        MOVEQ.L #-0x12,D0                       | D0 = -18 (statusErr default)
        MOVEQ.L #0x3,D4                         | D4 = 3 = dStatEnable bit position
        BRA.W   DEVIO_COMMON                    | join shared dispatch
| ----------------------------------------------------------
| STATUS_GET_DCE -- Status csCode=1: return DCE handle in ioMisc
STATUS_GET_DCE:
        BSR.W   LOOKUP_UNIT                     | A1 = DCE ptr, A2 = DCE handle
        MOVE.L  A2,28(A0)                       | store DCE handle in ioMisc (offset 28)
        BRA.W   OPEN_RET_NOERR                  | return noErr through OPEN_EXIT
| ----------------------------------------------------------
| KillIO ($A006) -- abort all queued I/O on a driver
| Sends killCode (csCode=1) to driver, then dequeues+aborts each pending
| request with abortErr (-27). Returns through OPEN_EXIT.
KillIO:                                         | _KillIO trap entry
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE    ioRefNum(A0),D2                 | D2 = driver refNum
        BSR.W   LOOKUP_UNIT                     | A1 = DCE ptr, A2 = DCE handle
        MOVE    #0x1,26(A0)                     | csCode = killCode (1)
        MOVE    SR,-(SP)                        | save interrupt state
        ORI     #0x300,SR                       | mask interrupts (IPL=3, critical section)
        MOVEQ.L #drvrCtl,D1                     | D1 = drvrCtl offset ($0C) in DRVR header
        BSR.W   CALL_DRV_ENTRY                  | call driver's control with killCode
        BNE.B   KILLIO_RESTORE_SR               | driver returned error: skip drain
KILLIO_DRAIN_QUEUE:                             | drain pending requests
        TST.L   dCtlQHead(A1)                   | dCtlQHead: any queued requests?
        BEQ.B   KILLIO_DONE                     | queue empty: clear busy + return
        MOVEQ.L #-0x1B,D0                       | D0 = -27 (abortErr) for each request
        MOVE    #0x2300,D1                      | D1 = SR value (supervisor, IPL=3)
        BSR.W   DEQUEUE_IOREQ                   | dequeue head, set ioResult, call completion
        BRA.B   KILLIO_DRAIN_QUEUE              | loop until queue drained
KILLIO_DONE:                                    | queue drained
        BSR.W   CLEAR_DRV_BUSY                  | clear drvrActive bit, unlock RAM driver
        MOVEQ.L #0x0,D0                         | D0 = 0 (noErr)
KILLIO_RESTORE_SR:                              | common exit
        MOVE    (SP)+,SR                        | restore interrupt state
        BRA.W   OPEN_EXIT                       | restore + return D0
| ----------------------------------------------------------
| DrvrInstall ($A03D) -- install a driver into the unit table
| D0 = refNum (negative), A0 = driver handle.
| Allocates a 40-byte DCE in the system heap, zero-fills it, stores it
| in the unit-table slot, marks the DCE as RAM-based. Returns noErr or
| a memory/refNum error. Called during boot.
DrvrInstall:                                    | _DrvrInstall trap entry
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE.L  A0,A3                           | A3 = driver handle (preserved across alloc)
        MOVE.L  D0,D3                           | D3 = saved refNum
        BSR.B   LOOKUP_UNIT_SLOT                | A2 = unit table slot, A0 = existing DCE handle
        BNE.B   DRVRINST_ZERO_DCE               | DCE already exists: skip allocation
        MOVEQ.L #dCtlEntrySize,D0               | D0 = 40 = DCE size
        _NewHandleSys                           | allocate 40-byte block in system heap
        BNE.B   DRVRINST_EXIT                   | allocation failed: bail with MemErr
DRVRINST_ZERO_DCE:                              | A0 = DCE handle (new or existing)
        MOVEQ.L #dCtlEntrySize-1,D0             | D0 = 39 (DBF count for 40 bytes)
        MOVE.L  (A0),A1                         | A1 = dereferenced DCE pointer
DRVRINST_ZERO_LOOP:
        CLR.B   (A1)+                           | zero one byte of DCE
        DBRA    D0,DRVRINST_ZERO_LOOP           | loop 40 times
        MOVE.L  A0,(A2)                         | store DCE handle in unit-table slot
        MOVE.L  (A0),A3                         | A3 = DCE pointer (deref'd)
        BSET    #0x6,5(A3)                      | set dRAMBased (new DCE is always RAM-based)
        MOVE    D3,dCtlRefNum(A3)               | store refNum in dCtlRefNum (offset $18)
DRVRINST_RET_NOERR:
        MOVEQ.L #0x0,D0                         | D0 = noErr
DRVRINST_EXIT:                                  | common exit (D0 holds result)
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore registers
        RTS                                     | return to trap dispatcher

| ----------------------------------------------------------
| LOOKUP_UNIT_SLOT -- look up unit-table slot by refNum
| In: D0 = refNum (negative)
| Out: A2 = pointer to unit-table slot, A0 = DCE handle from slot
| D0 = DCE handle, Z set if slot is empty
| Branches to DRVRINST_BAD_REFNUM (BMI) on invalid refNum
LOOKUP_UNIT_SLOT:
        NOT     D0                              | D0 = unitNum = ~refNum
        BMI.B   DRVRINST_BAD_REFNUM             | negative unitNum: invalid refNum
        CMP     (UnitTableEntryCount).w,D0      | unitNum >= table size?
        BGE.B   DRVRINST_BAD_REFNUM             | out of range: error
        ASL     #0x2,D0                         | D0 = byte offset (unitNum * 4)
        MOVE.L  (UTableBase).w,A2               | A2 = unit-table base
        ADDA.W  D0,A2                           | A2 = pointer to this unit's slot
        MOVE.L  (A2),A0                         | A0 = DCE handle from slot (may be nil)
        MOVE.L  A0,D0                           | D0 = handle (sets Z if nil)
        RTS                                     | return from LOOKUP_UNIT_SLOT (Z set if slot empty)
| ----------------------------------------------------------
| DRVRINST_BAD_REFNUM -- invalid refNum: return unitEmptyErr through caller
DRVRINST_BAD_REFNUM:
        BRA.W   UNIT_EMPTY_ERR                  | restore caller's regs + return -21

| ----------------------------------------------------------
| DrvrRemove ($A03E) -- remove a driver from the unit table
| D0 = refNum. Frees the DCE; for RAM-based drivers, also releases the
| DRVR resource handle. Returns dRemovErr (-25) if driver still open.
DrvrRemove:                                     | _DrvrRemove trap entry
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        BSR.B   LOOKUP_UNIT_SLOT                | A2 = slot, A0 = DCE handle
        BEQ.B   DRVRINST_RET_NOERR              | empty slot: nothing to remove, return noErr
        MOVE.L  A2,A3                           | A3 = unit-table slot ptr (to clear later)
        MOVE.L  D0,A2                           | A2 = DCE handle
        MOVE.L  (A2),A1                         | A1 = DCE pointer
        BTST    #0x5,5(A1)                      | dOpened bit set?
        BNE.B   DRVRREMOVE_STILL_OPEN           | yes: can't remove, return dRemovErr
        BTST    #0x6,5(A1)                      | dRAMBased?
        BEQ.B   DRVRREMOVE_FREE_DCE             | ROM-based: skip resource release
        MOVE.L  (A1),-(SP)                      | push dCtlDriver (DRVR resource handle)
        _ReleaseResource                        | release the DRVR resource
DRVRREMOVE_FREE_DCE:
        MOVE.L  A2,A0                           | A0 = DCE handle
        _DisposeHandle                          | free the DCE memory
        CLR.L   (A3)                            | clear unit-table slot (nil handle)
        BRA.B   DRVRINST_RET_NOERR              | return noErr
| ----------------------------------------------------------
| DRVRREMOVE_STILL_OPEN -- driver still open: return dRemovErr (-25)
DRVRREMOVE_STILL_OPEN:
        MOVEQ   #-0x19,D0                       | D0 = -25 (dRemovErr)
        BRA.B   DRVRINST_EXIT                   | restore + return error

