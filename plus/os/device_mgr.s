| Device Manager
|
| Handles communication between applications and device drivers.
| High-level: OpenDriver, CloseDriver, FSRead, FSWrite, Control, Status, KillIO
| Low-level: PBOpen, PBClose, PBRead, PBWrite, PBControl, PBStatus, PBKillIO
| All low-level calls take A0 = ParmBlkPtr, async flag in trap word bit 10.
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
|
| Device Manager I/O routine dispatch table
|
| Three word offsets from the driver header base: these index into
| the driver entry-point table for the FS I/O dispatch.
| Entries: Open ($06), IODone ($4A), unknown ($52)
DT_mFSIODNETbl:
  .byte 0x00,0x06,0x00,0x4A,0x00,0x52

| ----------------------------------------------------------
|
| Fetch - read a byte from the driver's I/O buffer
|
| Called via JFetch vector ($08F4). Used by serial drivers and
| others to read one byte from the active I/O request's buffer.
| A1 = DCE pointer. Returns byte in D0.
| Bit 15 of D0 is set on return if buffer is exhausted.
Fetch:
        BCLR    #0xF,D0                         | clear "buffer exhausted" flag; enter read mode
FETCH_STASH_COMMON:
        MOVEM.L D1/A2-A3,-(SP)                  | save working registers
        MOVE.L  0x8(A1),D1                      | D1 = dCtlQHead: first queued I/O request
        BEQ.B   IO_CORE_ERR                     | no active request: fatal error (dsIOCoreErr)
        MOVE.L  D1,A3                           | A3 = pointer to active IOParam block
        MOVE.L  FILLPAT(A3),D1                  | D1 = current buffer position (ioActCount, offset $28)
        MOVE.L  BKPAT(A3),A2                    | A2 = buffer base pointer (ioBuffer, offset $20)
        BCLR    #0xF,D0                         | test+clear bit 15: 0=Fetch (read), 1=Stash (write)
        BNE.B   FETCH_STASH_WRITE               | branch if Stash (write byte to buffer)
        MOVE.B  0x0(A2,D1.L),D0                 | Fetch: read byte from buffer[position] into D0
        BRA.B   FETCH_STASH_ADVANCE             | advance position

| ----------------------------------------------------------
|
| Stash continuation - write byte to buffer
|
FETCH_STASH_WRITE:
        MOVE.B  D0,0x0(A2,D1.L)                 | Stash: write D0 byte into buffer[position]
FETCH_STASH_ADVANCE:
        ADDQ.L  #0x1,D1                         | advance buffer position
        MOVE.L  D1,FILLPAT(A3)                  | update current position (ioActCount, offset $28)
        CMP.L   0x24(A3),D1                     | compare position to requested count (ioReqCount)
        BLT.B   FETCH_STASH_EXIT                | not yet exhausted: return normally
        BSET    #0xF,D0                         | set bit 15: buffer exhausted
FETCH_STASH_EXIT:
        EXT.L   D0                              | sign-extend byte result to long
        MOVEM.L (SP)+,D1/A2-A3                  | restore working registers
        RTS                                     | return from Fetch/Stash

| ----------------------------------------------------------
|
| No active I/O request - fatal system error
|
IO_CORE_ERR:
        MOVEQ.L #0xE,D0                         | dsIOCoreErr: I/O system error (ID=14)
        _SysError                               | halt system with fatal I/O error

| ----------------------------------------------------------
|
| Stash - write a byte to the driver's I/O buffer
|
| Called via JStash vector ($08F8). Writes byte in D0.B to the
| active I/O request's buffer. A1 = DCE pointer.
| Bit 15 of D0 set on return if buffer is full.
Stash:
        BSET    #0xF,D0                         | set bit 15 to indicate write (Stash) mode
        BRA.B   FETCH_STASH_COMMON              | share common Fetch/Stash logic

| ----------------------------------------------------------
|
| Device Manager I/O completion - noErr path
|
IODONE_NOERR:
        MOVEQ.L #0x0,D0                         | result = noErr

| ----------------------------------------------------------
|
| IODone - complete an asynchronous I/O request
|
| Called via JIODone vector ($08FC) when a driver finishes an I/O
| operation. A1 = DCE pointer, D0 = result code.
| Dequeues the completed request, calls its completion routine,
| and starts the next queued request if any.
IODone:
        MOVE.L  0x8(A1),D1                      | D1 = dCtlQHead: current I/O request
        BEQ.B   UNLOCK_DRV_CHECK                | no request queued: just clear busy flag
        MOVE    SR,-(SP)                        | save status register
        MOVE    SR,D1                           | D1 = current SR (for restoring IPL later)
        ORI     #0x300,SR                       | raise IPL to 3: block device interrupts
        BSR.B   CLEAR_DRV_BUSY                  | clear driver busy flag and resource lock bits
        BSR.B   DEQUEUE_IOREQ                   | dequeue request, store result, call completion
        ORI     #0x300,SR                       | re-raise IPL (completion routine may have lowered it)
        TST.L   0x8(A1)                         | another request waiting in queue?
        BNE.B   DISPATCH_NEXT_REQ               | yes: dispatch next request
        MOVE    (SP)+,SR                        | no more requests: restore SR
        RTS                                     | return from IODone

| ----------------------------------------------------------
|
| CLEAR_DRV_BUSY - Clear driver busy flag and unlock driver resource
|
| A1 = DCE pointer. Clears the "busy" bit (bit 7) of dCtlFlags+1
| and, for RAM-based drivers, unlocks the driver handle in both
| the handle master pointer and the zone header.
CLEAR_DRV_BUSY:
        BCLR    #0x7,0x5(A1)                    | clear dCtlFlags bit 7 (driver busy)
UNLOCK_DRV_CHECK:
        BTst    #0x6,0x4(A1)                    | test dCtlFlags bit 6 (dNeedLock / dRAMBased)
        BNE.B   UNLOCK_DRV_DONE                 | ROM-based driver: nothing to unlock
        MOVE.L  (A1),A0                         | A0 = dCtlDriver (handle to driver code)
        BCLR    #0x7,(A0)                       | unlock master pointer (clear lock bit)
        MOVE.L  (SysZone).w,A0                  | A0 = system heap zone header
        ADDA.L  -0x4(A1),A0                     | add relative handle to get zone block header
        BCLR    #0x7,(A0)                       | unlock block in zone (clear lock bit)
UNLOCK_DRV_DONE:
        RTS                                     | return from unlock

| ----------------------------------------------------------
|
| DEQUEUE_IOREQ - Dequeue completed request and call completion routine
|
| A1 = DCE pointer, D0 = result code, D1 = saved SR.
| Removes the head of the driver's I/O queue (dCtlQHead),
| stores the result in ioResult, and calls ioCompletion if set.
DEQUEUE_IOREQ:
        MOVE.L  0x8(A1),A0                      | A0 = dCtlQHead (completed IOParam block)
        CMPI    #0x2,0x4(A0)                    | verify qType = ioQType (2 = I/O queue element)
        BNE.B   IO_CORE_ERR                     | wrong type: fatal dsIOCoreErr
        MOVE.L  (A0),0x8(A1)                    | dCtlQHead = qLink (advance to next request)
        BNE.B   DEQUEUE_RESTORE_SR              | if next request exists, keep tail pointer
        CLR.L   0xC(A1)                         | queue now empty: clear dCtlQTail
DEQUEUE_RESTORE_SR:
        MOVE    D1,SR                           | restore SR (lower IPL for completion routine)
        MOVE    D0,0x10(A0)                     | store result code in ioResult
        BLE.B   DEQUEUE_CHK_COMPL               | if result <= 0 (error or noErr), keep it
        CLR     0x10(A0)                        | positive D0 is not an error: clear ioResult
DEQUEUE_CHK_COMPL:
        MOVE.L  0xC(A0),D1                      | D1 = ioCompletion routine address
        BEQ.B   DEQUEUE_DONE                    | no completion routine: return
        MOVE.L  A1,-(SP)                        | save DCE pointer
        MOVE.L  D1,A1                           | A1 = completion routine address
        EXT.L   D0                              | sign-extend result code to long
        JSR     (A1)                            | call completion routine (A0=IOParam, D0=result)
        MOVE.L  (SP)+,A1                        | restore DCE pointer
DEQUEUE_DONE:
        RTS                                     | return from dequeue and completion call

| ----------------------------------------------------------
|
| ENQUEUE_IOREQ - Enqueue an I/O request into a driver's queue
|
| A1 = DCE pointer, A0 = IOParam block to enqueue.
| Enqueues the request at dCtlQueue (offset 6 in DCE),
| then attempts to start it if driver is not busy.
ENQUEUE_IOREQ:
        MOVE.L  A1,D1                           | save DCE pointer in D1
        LEA.L   0x6(A1),A1                      | A1 = &dCtlQueue (queue header at DCE+6)
        MOVE    SR,-(SP)                        | save SR for IPL restore
        ORI     #0x300,SR                       | raise IPL to 3: protect queue manipulation
        JSR     Enqueue(PC)                     | enqueue IOParam block (A0) into driver queue
        MOVE.L  D1,A1                           | restore A1 = DCE pointer
DISPATCH_NEXT_REQ:
        BSet    #0x7,0x5(A1)                    | test+set driver busy flag (dCtlFlags bit 7)
        BEQ.B   START_HEAD_REQ                  | was not busy: start processing this request
        MOVEQ.L #0x0,D0                         | already busy: request is queued, return noErr
        MOVE    (SP)+,SR                        | restore SR
        RTS                                     | return from enqueue

| ----------------------------------------------------------
|
| START_HEAD_REQ - Start processing the head I/O request
|
| Driver was not busy. Determine which driver entry point to call
| based on the ioTrap field of the IOParam block: _Control (4),
| _Status (5), or _Read/_Write (prime).
START_HEAD_REQ:
        MOVE    (SP)+,SR                        | restore SR
        MOVE.L  0x8(A1),A0                      | A0 = dCtlQHead (IOParam at head of queue)
START_HEAD_IOPARAM:
        MOVEQ.L #0xC,D1                         | D1 = drvrCtl offset ($0C in driver header)
        CMPI.B  #0x4,0x7(A0)                    | ioTrap low byte = 4? (_Control)
        BEQ.B   CALL_DRV_ENTRY                  | dispatch to driver's Control entry
        MOVEQ.L #0xE,D1                         | D1 = drvrStatus offset ($0E in driver header)
        CMPI.B  #0x5,0x7(A0)                    | ioTrap low byte = 5? (_Status)
        BEQ.B   CALL_DRV_ENTRY                  | dispatch to driver's Status entry
        TST.L   0x24(A0)                        | ioReqCount = 0? (no data to transfer)
        BEQ     IODONE_NOERR                    | zero-length request: complete with noErr
        MOVE    0x2C(A0),D0                     | D0 = ioPosMode (positioning mode + flags)
        MOVE.L  0x2E(A0),D1                     | D1 = ioPosOffset (requested file position)
        ROXR.B  #0x2,D0                         | shift positioning mode bits into carry+sign
        BPL.B   IO_PRIME_ENTRY                  | mode = fsAtMark (0): don't update position
        BCC.B   IO_SET_POSITION                 | mode = fsFromStart (1): use offset directly
        ADD.L   0x10(A1),D1                     | mode = fsFromMark (3): offset relative to dCtlPosition
IO_SET_POSITION:
        MOVE.L  D1,0x10(A1)                     | update dCtlPosition to new file position
IO_PRIME_ENTRY:
        MOVEQ.L #0xA,D1                         | D1 = drvrPrime offset ($0A in driver header)

| ----------------------------------------------------------
|
| CALL_DRV_ENTRY - Call driver entry point
|
| A1 = DCE pointer, A0 = IOParam block, D1 = entry point offset
| in driver header (drvrOpen=$08, drvrPrime=$0A, drvrCtl=$0C,
| drvrStatus=$0E). Loads and locks RAM-based drivers as needed.
CALL_DRV_ENTRY:
        MOVE.L  (A1),D0                         | D0 = dCtlDriver (handle or pointer to driver)
        BNE.B   CALL_DRV_LOCK                   | driver exists: proceed to call it
        MOVEQ.L #-0x16,D0                       | dsMBarNFnd / unitEmptyErr (-22): no driver
        MOVE    D0,0x10(A0)                     | store error in ioResult
        RTS                                     | return error to caller

| ----------------------------------------------------------
|
| CALL_DRV_LOCK - Lock driver resource and dispatch to entry point
|
| For RAM-based drivers (dRAMBased=1), lock the resource handle
| and load it if purged. Then call the driver entry point.
CALL_DRV_LOCK:
        MOVEM.L D3-D7/A1-A6,-(SP)               | save all registers (driver may use any)
        MOVE.L  D0,A2                           | A2 = driver handle (or pointer if ROM-based)
        BTST    #0x6,0x5(A1)                    | test dCtlFlags bit 6 (dRAMBased in high byte)
        BEQ.B   CALL_DRV_EXEC                   | ROM-based: A2 is already a direct pointer
        MOVE.L  (SysZone).w,A3                  | A3 = system heap zone header
        ADDA.L  -0x4(A1),A3                     | offset to block header in zone
        BSET    #0x7,(A3)                       | lock driver block in heap (set lock bit)
        TST.L   (A2)                            | dereference handle: master pointer nil?
        BNE.B   CALL_DRV_LOCK_HDL               | not purged: proceed
        MOVE.L  A2,-(SP)                        | push handle for _LoadResource
        _LoadResource                           | reload purged driver resource
        MOVE    (ResErr).w,D0                   | check for Resource Manager error
        BNE.B   CALL_DRV_LOADFAIL               | load failed: report error
CALL_DRV_LOCK_HDL:
        BSet    #0x7,(A2)                       | lock handle master pointer (set hi bit)
        MOVE.L  (A2),-(SP)                      | push dereferenced pointer
        CLR.B   (SP)                            | clear the high byte (strip lock/flag bits)
        MOVE.L  (SP)+,A2                        | A2 = clean pointer to driver code
CALL_DRV_EXEC:
        MOVE    0x0(A2,D1.W),D1                 | D1 = entry point offset from driver header
        MOVEQ.L #0x0,D0                         | clear D0 before calling driver
        JSR     0x0(A2,D1.W)                    | call driver entry point (A0=IOParam, A1=DCE)
        BRA.B   CALL_DRV_EXIT                   | return from driver call

| ----------------------------------------------------------
|
| CALL_DRV_LOADFAIL - _LoadResource failed for RAM-based driver
|
CALL_DRV_LOADFAIL:
        MOVE    D0,0x10(A0)                     | store Resource Manager error in ioResult
CALL_DRV_EXIT:
        EXT.L   D0                              | sign-extend result to long
        MOVEM.L (SP)+,D3-D7/A1-A6               | restore all registers
        RTS                                     | return from driver entry point call

| ----------------------------------------------------------
|
| LOOKUP_UNIT - Look up a driver in the unit table
|
| D2 = driver refNum (negated unit number - 1). Converts to unit
| number, bounds-checks, and returns DCE pointer in A1.
| On failure, branches to UNIT_EMPTY_ERR (unitEmptyErr).
| Called by: OPEN_INIT_DCE, CLOSE_DEVICE, DEVIO_COMMON, STATUS_GET_DCE, KillIO
LOOKUP_UNIT:
        NOT     D2                              | convert refNum to unit number (~refNum)
        BMI.B   UNIT_EMPTY_ERR                  | negative unit number: invalid
        CMP     (UnitTableEntryCount).w,D2      | unit number >= table size?
        BGE.B   UNIT_EMPTY_ERR                  | out of range: error
        ASL     #0x2,D2                         | unit number * 4 = table offset
        MOVE.L  (UTableBase).w,A1               | A1 = base of unit table
        MOVE.L  0x0(A1,D2.W),D2                 | D2 = DCE handle from unit table
        BEQ.B   UNIT_EMPTY_ERR                  | nil handle: no driver installed
        MOVE.L  D2,A2                           | A2 = DCE handle
        MOVE.L  (A2),D2                         | D2 = dereference DCE handle to pointer
        BEQ     IO_CORE_ERR                     | nil pointer (purged DCE): fatal dsIOCoreErr
        MOVE.L  D2,A1                           | A1 = DCE pointer (for caller)
        RTS                                     | return with DCE pointer in A1

| ----------------------------------------------------------
|
| UNIT_EMPTY_ERR - Driver not found error
|
| Returns unitEmptyErr (-21) in ioResult.
UNIT_EMPTY_ERR:
        MOVE.L  D5,A0                           | A0 = saved IOParam pointer
        MOVEM.L (SP)+,D0/D3-D5/A2-A3            | restore caller's registers
        MOVEQ.L #-0x15,D0                       | unitEmptyErr (-21): no driver in unit table
        MOVE    D0,0x10(A0)                     | store error in ioResult
        RTS                                     | return error to caller

| ----------------------------------------------------------
|
| DEVMGR_OPEN_DISP - Device Manager Open dispatch
|
| After looking up the driver, decides whether this is a file open
| (goes to File Manager) or a device open (returns badUnitErr).
DEVMGR_OPEN_DISP:
        MOVE.L  D5,A0                           | A0 = saved IOParam pointer
        MOVE    0x6(A0),D1                      | D1 = ioTrap word from IOParam block
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore caller's registers
        CMPI.B  #0x40,0x1B(A0)                  | ioPermssn = $40? (driver-specific open flag)
        BEQ.B   BAD_UNIT_ERR                    | yes: return badUnitErr (driver already open)
        JMP     P_mFileOpen(PC)                 | no: forward to File Manager's FileOpen

| ----------------------------------------------------------
|
| BAD_UNIT_ERR - Return badUnitErr for re-opened device
|
BAD_UNIT_ERR:
        MOVEQ.L #-0x17,D0                       | badUnitErr (-23): driver already open
        BRA     OPEN_STORE_RESULT               | branch to common exit to return error

|
| _Open ($A000)
| A0 = paramBlock (IOParam) -> D0 = error
| Opens a driver by name: searches unit table, then tries 'DRVR' resource.
| refNum = -(unitNum+1), returned in ioRefNum of the paramBlock.
|
| Called during boot.
Open:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE.L  A0,D5                           | D5 = saved paramBlock ptr
        MOVE    D1,0x6(A0)                      | save trap word in ioTrap
        MOVE    0x1A(A0),D2                     | D2 = ioFileType (driver type hint)
        MOVE.L  ioFileName(A0),A0               | A0 = pointer to driver name (Pascal string)
        MOVEQ.L #0x0,D1                         | clear D1 for length byte
        MOVE.B  (A0)+,D1                        | D1 = name length; A0 past length byte
        CMPI.B  #0x40,D2                        | ioFileType $40 = open by name (skip '.' check)
        BEQ.B   OPEN_SEARCH_BY_NAME             | if match (ioFileType $40), search by name
        CMPI.B  #0x2E,(A0)                      | driver names start with '.' (e.g. ".Sony")
        BNE.B   DEVMGR_OPEN_DISP                | not a driver name -> forward to File Manager
OPEN_SEARCH_BY_NAME:
| Search unit table for an installed driver matching the requested name
        MOVE.L  (UTableBase).w,A3               | A3 = base of unit table (array of DCE handles)
        MOVE    (UnitTableEntryCount).w,D2      | D2 = number of unit table entries
        MOVEQ.L #-0x1,D4                        | D4 = refNum counter, starts at -1 (unit 0)
OPEN_SCAN_UNIT_TBL:
        MOVE.L  (A3)+,D0                        | D0 = next DCE handle from unit table
        BEQ.B   OPEN_SCAN_NEXT                  | nil handle = empty slot, skip
        MOVE.L  D0,A2                           | A2 = DCE handle
        MOVE.L  (A2),D0                         | D0 = DCE pointer (deref handle)
        BEQ.B   OPEN_SCAN_NEXT                  | nil DCE pointer, skip
        MOVE.L  D0,A1                           | A1 = DCE pointer
        BTST    #0x6,dCtlFlags+1(A1)            | test dRAMBased bit: RAM driver = handle
        MOVE.L  (A1),A1                         | A1 = dCtlDriver (handle or ptr to DRVR header)
        BEQ.B   OPEN_CHECK_DRVR_PTR             | ROM driver: dCtlDriver is direct ptr
        MOVE.L  A1,D0                           | RAM driver: dCtlDriver is a handle
        BEQ.B   OPEN_SCAN_NEXT                  | nil driver handle, skip
        MOVE.L  (A1),A1                         | deref handle -> A1 = DRVR header ptr
OPEN_CHECK_DRVR_PTR:
        MOVE.L  A1,D0                           | test if DRVR header ptr is valid
        BEQ.B   OPEN_SCAN_NEXT                  | nil -> skip this entry
        LEA.L   0x12(A1),A1                     | A1 = drvrName field (offset 18 in DRVR header)
        MOVE.L  D1,D0                           | D0.hi = 0, D0.lo = requested name length
        SWAP    D0                              | D0.hi = requested length (for _CmpString)
        MOVE.B  (A1)+,D0                        | D0.lo = driver name length from DRVR
        CMP.B   D0,D1                           | compare name lengths first
        BNE.B   OPEN_SCAN_NEXT                  | lengths differ, no match
        _CmpString                              | compare A0 (requested) vs A1 (driver), D0 lengths
        BEQ     OPEN_LOCK_DRIVER                | match found -> finish opening this driver
OPEN_SCAN_NEXT:
        SUBQ.W  #0x1,D4                         | decrement refNum (next = -2, -3, ...)
        SUBQ.W  #0x1,D2                         | decrement unit table loop counter
        BGT.B   OPEN_SCAN_UNIT_TBL              | more entries to check
| Driver not found in unit table -- try loading as 'DRVR' resource by name
        SUBQ.W  #0x4,SP                         | space for GetNamedResource result handle
        MOVE.L  #0x44525652,-(SP)               | push resource type 'DRVR'
        MOVE.L  D5,A0                           | restore paramBlock ptr
        MOVE.L  ioFileName(A0),-(SP)            | push driver name pointer
        MOVE    #-0x1,(ROMMapInsert).w          | search ROM resource map first
        _GetNamedResource                       | -> handle on stack
        MOVE.L  (SP)+,D3                        | D3 = DRVR resource handle (or nil)
        BNE.B   OPEN_GOT_RESOURCE               | got handle -> install the driver
        MOVE    (ResErr).w,D0                   | no handle; check why
        BEQ     DEVMGR_OPEN_DISP                | resNotFound -> forward to File Manager
        CMPI    #-0xC0,D0                       | -192 = resNotFound
        BEQ     DEVMGR_OPEN_DISP                | forward to File Manager
        BRA     OPEN_EXIT                       | other resource error -> return it

| ----------------------------------------------------------
|
| OPEN_GOT_RESOURCE - DRVR resource found, get its resource ID to derive unit number
|
| Called during boot.
OPEN_GOT_RESOURCE:
        CLR     -(SP)                           | space for resource ID (word)
        MOVE.L  A7,D0                           | D0 = pointer to ID result on stack
        MOVE.L  D3,-(SP)                        | push DRVR resource handle
        MOVE.L  D0,-(SP)                        | push pointer to receive resource ID
        CLR.L   -(SP)                           | push nil (type ptr, not needed)
        CLR.L   -(SP)                           | push nil (name ptr, not needed)
        MOVE    #-0x1,(ROMMapInsert).w          | search ROM map first
        _GetResInfo                             | get resource ID of the DRVR
        MOVE    (SP)+,D4                        | D4 = DRVR resource ID (= unit number)
        NOT     D4                              | D4 = refNum = ~unitNum
        MOVE    D4,D0                           | D0 = refNum for lookup
        BSR     LOOKUP_UNIT_SLOT                | look up unit table slot for this refNum
        BMI     OPEN_EXIT                       | invalid refNum -> error
        BNE.B   OPEN_INIT_DCE                   | DCE already exists -> skip install
| No DCE at this unit number -- install a new one
        MOVE    D4,D0                           | D0 = refNum for DrvrInstall
        MOVE.L  D3,A0                           | A0 = DRVR resource handle
        MOVE.L  (A0),A0                         | A0 = DRVR header ptr (deref handle)
        BTST    #0x6,(A0)                       | test dNeedLock flag in drvrFlags
        BEQ.B   OPEN_STD_INSTALL                | not locked -> standard install
        _DrvrInstallResrvMem                    | allocate DCE in reserved memory
        BRA.B   OPEN_CHK_INSTALL                | skip standard install

| ----------------------------------------------------------
|
| OPEN_STD_INSTALL - standard driver install (no reserved memory needed)
|
OPEN_STD_INSTALL:
        _DrvrInstall                            | allocate DCE at D0=refNum, A0=handle
OPEN_CHK_INSTALL:
        BNE     OPEN_EXIT                       | install failed -> return error
OPEN_INIT_DCE:
| DCE exists (or just created); initialize it from DRVR header fields
        MOVE    D4,D2                           | D2 = refNum for LOOKUP_UNIT
        BSR     LOOKUP_UNIT                     | A1=DCE ptr, A2=DCE handle from unit table
        BSET    #0x5,dCtlFlags+1(A1)            | set dOpened bit in DCE runtime flags
        BNE.B   OPEN_LOCK_DRIVER                | already open -> skip init, go to permission check
        MOVEQ.L #0x40,D0                        | D0 = $40 (dRAMBased flag for dCtlFlags+1)
        MOVE.L  D3,(A1)                         | dCtlDriver = DRVR resource handle
        MOVE.L  D3,A0                           | A0 = DRVR resource handle
        MOVE.L  (A0),D3                         | D3 = deref'd DRVR ptr (may have hi bits set)
        AND.L   (Lo3Bytes).w,D3                 | mask to 24-bit address
        CMP.L   (ROMBase).w,D3                  | is DRVR in ROM?
        BLT.B   OPEN_COPY_DRVR_HDR              | no (in RAM) -> keep handle in dCtlDriver
        MOVE.L  D3,(A1)                         | ROM driver: store direct ptr in dCtlDriver
        MOVEQ.L #0x0,D0                         | D0 = 0 (ROM-based, clear dRAMBased flag)
OPEN_COPY_DRVR_HDR:
| Copy DRVR header fields into DCE
        MOVE.L  D3,A0                           | A0 = DRVR header ptr
        MOVE    (A0)+,dCtlFlags(A1)             | copy drvrFlags -> dCtlFlags
        MOVE.B  D0,dCtlFlags+1(A1)              | set runtime flags (dRAMBased or 0)
        MOVE.L  (A0)+,dCtlDelay(A1)             | copy drvrDelay+drvrEMask -> dCtlDelay+dCtlEMask
        MOVE    (A0)+,dCtlMenu(A1)              | copy drvrMenu -> dCtlMenu
OPEN_LOCK_DRIVER:
| Lock driver in memory if dNeedLock set and RAM-based
        MOVE.L  (A2),A1                         | A1 = DCE ptr (re-deref in case heap moved)
        BTST    #0x6,dCtlFlags(A1)              | test dNeedLock: driver needs locking?
        BEQ.B   OPEN_CHK_PERM                   | no -> skip locking
        MOVE.L  (A1),A0                         | A0 = dCtlDriver (handle or ptr)
        BTST    #0x6,dCtlFlags+1(A1)            | test dRAMBased
        BEQ.B   OPEN_LOCK_DCE                   | ROM-based -> skip handle lock
        BSET    #0x7,(A0)                       | lock the DRVR handle's master pointer
OPEN_LOCK_DCE:
        BSet    #0x7,(A2)                       | lock the DCE handle's master pointer
OPEN_CHK_PERM:
| Check read/write permission compatibility
        MOVE.L  D5,A0                           | A0 = paramBlock ptr
        MOVE    D4,ioRefNum(A0)                 | return refNum to caller in paramBlock
        MOVEQ.L #-0x17,D0                       | D0 = -23 (openErr: driver already open)
        MOVE.B  dCtlFlags(A1),D1                | D1 = driver capability flags (read/write enable)
        MOVE    D1,D2                           | D2 = save original flags
        OR.B    ioPermssn(A0),D1                | combine requested permission with capabilities
        EOR.B   D2,D1                           | isolate bits set in request but not in driver
        ANDI.B  #0x3,D1                         | mask read+write enable bits
        BNE.B   OPEN_EXIT                       | requested unsupported permission -> openErr
        BSET    #0x5,dCtlFlags+1(A1)            | set dOpened bit
        BEQ.B   OPEN_CALL_DRIVER                | was not previously open -> call open routine
        CMPI.B  #0x40,ioPermssn(A0)             | ioPermssn=$40 means "force reopen"
        BNE.B   OPEN_RET_NOERR                  | already open, no force -> return noErr
OPEN_CALL_DRIVER:
| Call the driver's open routine (offset 8 in DRVR header)
        MOVEQ.L #0x8,D1                         | D1 = drvrOpen offset in DRVR header
        BSR     CALL_DRV_ENTRY                  | call driver routine at DRVR+D1
        BPL.B   OPEN_CHK_NEEDLOCK               | open succeeded -> check if we need cleanup
| Open failed -- clean up
        MOVE.L  D5,A0                           | A0 = paramBlock
        CLR     ioRefNum(A0)                    | clear refNum (driver not open)
        BCLR    #0x5,dCtlFlags+1(A1)            | clear dOpened bit
        BRA.B   OPEN_UNLOCK_RAM                 | go unlock driver if RAM-based

| ----------------------------------------------------------
|
| OPEN_CHK_NEEDLOCK - open succeeded; check if driver needs GoodBye kiss
|
| Called during boot.
OPEN_CHK_NEEDLOCK:
        BTst    #0x6,dCtlFlags(A1)              | test dNeedLock flag
        BNE.B   OPEN_EXIT                       | locked driver -> done, return result
OPEN_UNLOCK_RAM:
| Unlock RAM-based driver if it was locked during open
        MOVE.L  (A1),A0                         | A0 = dCtlDriver (handle or ptr)
        BTST    #0x6,dCtlFlags+1(A1)            | test dRAMBased
        BEQ.B   OPEN_EXIT                       | ROM-based -> nothing to unlock
        BCLR    #0x7,(A0)                       | unlock DRVR handle's master pointer
        BTST    #0x6,dCtlFlags(A1)              | test dNeedLock again
        BNE.B   OPEN_EXIT                       | locked -> don't unlock DCE
        BCLR    #0x7,(A2)                       | unlock DCE handle's master pointer
OPEN_EXIT:
| Common exit: restore regs, store result, return
        MOVE.L  D5,A0                           | A0 = paramBlock
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore registers
OPEN_STORE_RESULT:
        MOVE    D0,ioResult(A0)                 | store error code in paramBlock
        RTS                                     | return

| ----------------------------------------------------------
|
| OPEN_RET_NOERR - return noErr (driver already open, no action needed)
|
OPEN_RET_NOERR:
        MOVEQ.L #0x0,D0                         | D0 = noErr
        BRA.B   OPEN_EXIT                       | branch to exit

| ----------------------------------------------------------
|
| _Close ($A001)
| A0 = paramBlock -> D0 = error
| Positive ioRefNum -> file close (File Manager); negative -> device close.
|
| Called during boot.
Close:
        MOVE    ioRefNum(A0),D2                 | D2 = ioRefNum from paramBlock
        BMI.B   CLOSE_DEVICE                    | negative refNum = device driver
        JMP     FileClose(PC)                   | positive refNum -> File Manager close

| ----------------------------------------------------------
|
| CLOSE_DEVICE - device driver close path
|
CLOSE_DEVICE:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE.L  A0,D5                           | D5 = saved paramBlock ptr
        BSR     LOOKUP_UNIT                     | A1=DCE ptr, A2=DCE handle for refNum in D2
        BTST    #0x5,dCtlFlags+1(A1)            | test dOpened bit: is driver open?
        BEQ.B   OPEN_RET_NOERR                  | not open -> return noErr
CLOSE_WAIT_BUSY:
        BTst    #0x7,dCtlFlags+1(A1)            | test drvrActive bit: driver busy?
        BNE.B   CLOSE_WAIT_BUSY                 | spin-wait until driver finishes current I/O
        MOVEQ.L #0x10,D1                        | D1 = drvrClose offset in DRVR header
        BSR     CALL_DRV_ENTRY                  | call driver's close routine
        CMPI    #-0x18,D0                       | -24 = closErr (driver can't be closed)
        BEQ.B   OPEN_CHK_NEEDLOCK               | closErr -> leave driver open, unlock if needed
        BCLR    #0x5,dCtlFlags+1(A1)            | clear dOpened bit (driver is now closed)
        BRA.B   OPEN_UNLOCK_RAM                 | go unlock RAM driver resources

| ----------------------------------------------------------
|
| _Read ($A002)
| A0 = paramBlock -> D0 = error; reads ioReqCount bytes
| Positive ioRefNum -> file read; negative -> device driver read.
|
| Called during boot.
Read:
        MOVE    ioRefNum(A0),D2                 | D2 = ioRefNum
        BMI.B   READ_DEVICE                     | negative = device driver
        JMP     L_mFileRead(PC)                 | positive = File Manager read

| ----------------------------------------------------------
|
| READ_DEVICE - device driver read path
| D0 = -19 (readErr default), D4 = 0 (dReadEnable bit position)
|
| Called during boot.
READ_DEVICE:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVEQ.L #-0x13,D0                       | D0 = -19 (readErr)
        MOVEQ.L #0x0,D4                         | D4 = 0 = dReadEnable bit position
DEVIO_COMMON:
| Common entry for Read/Write/Control - D0=default error, D4=enable bit
        MOVE.L  A0,D5                           | D5 = saved paramBlock ptr
        BSR     LOOKUP_UNIT                     | A1=DCE ptr, A2=DCE handle for refNum in D2
        CMPI.B  #0x3,D1                         | trap <= Control? (Read=2, Write=3)
        BGT.B   DEVIO_SET_INPROGRESS            | Status/KillIO -> skip clearing ioActCount
        CLR.L   0x28(A0)                        | ioActCount = 0 (reset bytes transferred)
DEVIO_SET_INPROGRESS:
        MOVE    #0x1,ioResult(A0)               | ioResult = 1 (in progress, not yet complete)
        MOVE    D1,0x6(A0)                      | save trap word in ioTrap
        MOVE    #0x2,0x4(A0)                    | qType = ioQType (2) for I/O queue
        BTST    D4,dCtlFlags(A1)                | test enable bit (read/write/ctl/stat)
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore registers
        BEQ.B   DEVIO_STORE_RESULT              | operation not enabled -> return default error
        MOVEQ.L #-0x1C,D0                       | D0 = -28 (notOpenErr: driver not open)
        BTST    #0x5,dCtlFlags+1(A1)            | test dOpened bit
        BEQ.B   DEVIO_STORE_RESULT              | not open -> notOpenErr
        BTST    #0x9,D1                         | trap word bit 9 = immediate flag
        BNE     START_HEAD_IOPARAM              | immediate -> bypass queue, call driver directly
        BTST    #0xA,D1                         | trap word bit 10 = async flag
        BNE     ENQUEUE_IOREQ                   | async -> enqueue and return immediately
        CLR.L   ioCompletion(A0)                | synchronous: no completion routine
        MOVE.L  A0,-(SP)                        | save paramBlock ptr on stack
        BSR     ENQUEUE_IOREQ                   | enqueue the I/O request
        MOVE.L  (SP)+,A0                        | restore paramBlock ptr
DEVIO_POLL_RESULT:
        MOVE    ioResult(A0),D0                 | poll ioResult
        BGT.B   DEVIO_POLL_RESULT               | >0 means still in progress; spin-wait
        EXT.L   D0                              | sign-extend result to long
DEVIO_STORE_RESULT:
        MOVE    D0,ioResult(A0)                 | store final result in paramBlock
        RTS                                     | return

| ----------------------------------------------------------
|
| _Write ($A003)
| A0 = paramBlock -> D0 = error; writes ioReqCount bytes
| Positive ioRefNum -> file write; negative -> device driver write.
|
| Called during boot.
Write:
        MOVE    ioRefNum(A0),D2                 | D2 = ioRefNum
        BMI.B   WRITE_DEVICE                    | negative = device driver
        JMP     FileWrite(PC)                   | positive = File Manager write

| ----------------------------------------------------------
|
| WRITE_DEVICE - device driver write path
| D0 = -20 (writErr default), D4 = 1 (dWritEnable bit position)
|
| Called during boot.
WRITE_DEVICE:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVEQ.L #-0x14,D0                       | D0 = -20 (writErr)
        MOVEQ.L #0x1,D4                         | D4 = 1 = dWritEnable bit position
        BRA.B   DEVIO_COMMON                    | join common Read/Write/Control path

| ----------------------------------------------------------
|
| _Control ($A004)
| A0 = paramBlock (CntrlParam) -> D0 = error
| D0 = -17 (controlErr default), D4 = 2 (dCtlEnable bit position)
|
| Called during boot.
Control:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE    ioRefNum(A0),D2                 | D2 = driver refNum
        MOVEQ.L #-0x11,D0                       | D0 = -17 (controlErr)
        MOVEQ.L #0x2,D4                         | D4 = 2 = dCtlEnable bit position
  .short 0x6080                                 | BRA.B DEVIO_COMMON (hand-assembled forward branch)

| ----------------------------------------------------------
|
| _Status ($A005)
| A0 = paramBlock (CntrlParam) -> D0 = error
| csCode=1 is special: returns DCE handle in ioMisc without calling driver.
|
Status:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE    ioRefNum(A0),D2                 | D2 = driver refNum
        MOVE.L  A0,D5                           | D5 = saved paramBlock ptr
        CMPI    #0x1,0x1A(A0)                   | csCode == 1? (get DCE handle)
        BEQ.B   STATUS_GET_DCE                  | yes -> return DCE handle directly
        MOVEQ.L #-0x12,D0                       | D0 = -18 (statusErr)
        MOVEQ.L #0x3,D4                         | D4 = 3 = dStatEnable bit position
        BRA     DEVIO_COMMON                    | join common dispatch path

| ----------------------------------------------------------
|
| STATUS_GET_DCE - Status csCode=1: return DCE handle in ioMisc
|
STATUS_GET_DCE:
        BSR     LOOKUP_UNIT                     | A1=DCE ptr, A2=DCE handle
        MOVE.L  A2,0x1C(A0)                     | store DCE handle in ioMisc field
        BRA     OPEN_RET_NOERR                  | return noErr

| ----------------------------------------------------------
|
| _KillIO ($A006)
| A0 = paramBlock -> D0 = error; aborts pending I/O
| Sends killCode control call, then dequeues and aborts all pending requests.
|
KillIO:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE    ioRefNum(A0),D2                 | D2 = driver refNum
        MOVE.L  A0,D5                           | D5 = saved paramBlock ptr
        BSR     LOOKUP_UNIT                     | A1=DCE ptr, A2=DCE handle
        MOVE    #0x1,0x1A(A0)                   | csCode = killCode (1)
        MOVE    SR,-(SP)                        | save interrupt state
        ORI     #0x300,SR                       | disable interrupts (critical section)
        MOVEQ.L #0xC,D1                         | D1 = drvrCtl offset in DRVR header
        MOVEQ.L #-0x11,D0                       | D0 = -17 (controlErr default)
        MOVEQ.L #0x2,D4                         | D4 = 2 = dCtlEnable bit position
        BTST    D4,dCtlFlags(A1)                | driver supports control calls?
        BEQ.B   KILLIO_RESTORE_SR               | no -> return controlErr
        MOVEQ.L #-0x1C,D0                       | D0 = -28 (notOpenErr)
        BTST    #0x5,dCtlFlags+1(A1)            | driver open?
        BEQ.B   KILLIO_RESTORE_SR               | not open -> notOpenErr
        BSR     CALL_DRV_ENTRY                  | call driver's control routine with killCode
        BNE.B   KILLIO_RESTORE_SR               | driver returned error -> done
KILLIO_DRAIN_QUEUE:
| Drain the driver's I/O queue: dequeue and abort each pending request
        TST.L   0x8(A1)                         | dCtlQHead: any queued requests?
        BEQ.B   KILLIO_DONE                     | queue empty -> done
        MOVEQ.L #-0x1B,D0                       | D0 = -27 (abortErr) for aborted requests
        MOVE    #0x2300,D1                      | D1 = SR value: supervisor, IPL=3 (ints masked)
        BSR     DEQUEUE_IOREQ                   | dequeue head, set ioResult, call completion
        BRA.B   KILLIO_DRAIN_QUEUE              | loop until queue drained

| ----------------------------------------------------------
|
| KILLIO_DONE - queue drained, clear drvrActive, return noErr
|
KILLIO_DONE:
        BSR     CLEAR_DRV_BUSY                  | clear drvrActive bit, unlock driver if RAM-based
        MOVEQ.L #0x0,D0                         | D0 = noErr
KILLIO_RESTORE_SR:
        MOVE    (SP)+,SR                        | restore interrupt state
        BRA     OPEN_EXIT                       | return through common exit

| ----------------------------------------------------------
|
| _DrvrInstall ($A03D)
| D0 = refNum -> D0 = error
| Allocates a 40-byte DCE in the system heap and installs it in the unit table.
| Trap word bit 10 (_DrvrInstallResrvMem variant) reserves memory first.
|
| Called during boot.
DrvrInstall:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        MOVE.L  A0,A3                           | A3 = saved driver handle (not used here)
        MOVE.L  D0,D3                           | D3 = saved refNum
        BSR.B   LOOKUP_UNIT_SLOT                | look up unit table slot; A2=slot ptr
        BMI.B   DRVRINST_EXIT                   | invalid refNum -> return unitEmptyErr
        BNE.B   DRVRINST_ZERO_DCE               | DCE already exists -> skip allocation
        BTST    #0xA,D1                         | trap word bit 10 = ResrvMem variant?
        BEQ.B   DRVRINST_ALLOC_NORM             | no -> allocate normally
        MOVEQ.L #0x28,D0                        | D0 = 40 = dCtlEntrySize
        _ResrvMemSys                            | reserve 40 bytes in system heap first
DRVRINST_ALLOC_NORM:
        MOVEQ.L #0x28,D0                        | D0 = 40 = dCtlEntrySize
        _NewHandleSys                           | allocate relocatable block in system heap
        BNE.B   DRVRINST_EXIT                   | allocation failed -> return MemErr
DRVRINST_ZERO_DCE:
| Zero-fill the 40-byte DCE and install it in the unit table
        MOVEQ.L #0x27,D0                        | D0 = 39 (DBF loop count for 40 bytes)
        MOVE.L  (A0),A1                         | A1 = deref'd DCE pointer
DRVRINST_ZERO_LOOP:
        CLR.B   (A1)+                           | zero one byte of DCE
        DBF     D0,DRVRINST_ZERO_LOOP           | loop 40 times
        MOVE.L  A0,(A2)                         | store DCE handle in unit table slot
        MOVE.L  (A0),A3                         | A3 = DCE pointer (deref'd)
        BSET    #0x6,dCtlFlags+1(A3)            | set dRAMBased (new DCE is always RAM-based)
        MOVE    D3,VISRGN(A3)                   | store refNum in dCtlRefNum (offset $18)
DRVRINST_RET_NOERR:
        MOVEQ.L #0x0,D0                         | D0 = noErr
DRVRINST_EXIT:
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore registers
        RTS                                     | return

| ----------------------------------------------------------
|
| LOOKUP_UNIT_SLOT - Look up unit table slot by refNum
| In: D0 = refNum (negative), D1 = trap word
| Out: A2 = pointer to unit table slot, A0 = DCE handle (may be nil)
| D0 = DCE handle (masked 24-bit), Z set if slot is empty
| Returns with N set (BMI) on invalid refNum (unitEmptyErr)
|
| Called during boot.
LOOKUP_UNIT_SLOT:
        NOT     D0                              | D0 = unitNum = ~refNum
        BMI.B   DRVRINST_BAD_REFNUM             | negative unitNum = invalid refNum
        CMP     (UnitTableEntryCount).w,D0      | unitNum >= table size?
        BGE.B   DRVRINST_BAD_REFNUM             | out of range -> error
        ASL     #0x2,D0                         | D0 = byte offset (unitNum * 4)
        MOVE.L  (UTableBase).w,A2               | A2 = unit table base
        ADDA    D0,A2                           | A2 = pointer to this unit's slot
        MOVE.L  (A2),A0                         | A0 = DCE handle from slot (may be nil)
        MOVE.L  A0,D0                           | return DCE handle in D0
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit; sets Z if nil
        RTS                                     | return

| ----------------------------------------------------------
|
| DRVRINST_BAD_REFNUM - invalid refNum: return unitEmptyErr (-21)
|
DRVRINST_BAD_REFNUM:
        MOVEQ.L #-0x15,D0                       | D0 = -21 (unitEmptyErr)
        RTS                                     | return

| ----------------------------------------------------------
|
| _DrvrRemove ($A03E)
| D0 = refNum -> D0 = error
| Removes a closed driver from the unit table and frees its DCE.
| Cannot remove an open driver (returns dRemovErr -25).
|
DrvrRemove:
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers
        BSR.B   LOOKUP_UNIT_SLOT                | look up unit table slot; A2=slot ptr, A0=DCE handle
        BMI.B   DRVRINST_EXIT                   | invalid refNum -> error
        BEQ.B   DRVRINST_RET_NOERR              | empty slot -> return noErr (nothing to remove)
        MOVE.L  A2,A3                           | A3 = unit table slot pointer (to clear later)
        MOVE.L  D0,A2                           | A2 = DCE handle (24-bit from LOOKUP_UNIT_SLOT)
        MOVE.L  (A2),A1                         | A1 = DCE pointer
        BTST    #0x5,dCtlFlags+1(A1)            | test dOpened: is driver still open?
        BNE.B   DRVRREMOVE_STILL_OPEN           | open -> can't remove, return dRemovErr
        BTST    #0x6,dCtlFlags+1(A1)            | test dRAMBased
        BEQ.B   DRVRREMOVE_FREE_DCE             | ROM-based -> skip resource release
        MOVE.L  (A1),-(SP)                      | push dCtlDriver (DRVR resource handle)
        _ReleaseResource                        | release the DRVR resource
DRVRREMOVE_FREE_DCE:
        MOVE.L  A2,A0                           | A0 = DCE handle
        _DisposeHandle                          | free the DCE memory
        CLR.L   (A3)                            | clear unit table slot (nil handle)
        BRA.B   DRVRINST_RET_NOERR              | return noErr

| ----------------------------------------------------------
|
| DRVRREMOVE_STILL_OPEN - driver is still open, cannot remove
|
DRVRREMOVE_STILL_OPEN:
        MOVEQ.L #-0x19,D0                       | D0 = -25 (dRemovErr)
        BRA.B   DRVRINST_EXIT                   | branch to exit

| ----------------------------------------------------------
|
| _AddDrive ($A04E)
| D0 = drvNum, D1 = refNum, A0 = DQE (drive queue element) -> D0 = noErr
| Stores drive number and driver refNum in the DQE, then enqueues it
| on the system drive queue (DrvQHdr) for File Manager volume mounting.
|
| Called during boot.
AddDrive:
        MOVE.L  D0,0x6(A0)                      | store drvNum (word) + refNum (word) at DQE+6
        LEA.L   (DrvQHdr_Flags).w,A1            | A1 = drive queue header
        JSR     Enqueue(PC)                     | add DQE to drive queue
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | return

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
        RTS                                     | return

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
        RTS                                     | return

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
        RTS                                     | return

| ----------------------------------------------------------
|
| _PostEvent ($A02F)
| A0 = event number (0-15), D0 = event message -> D0 = error
| Posts an event to the system event queue if the event type is
| enabled in SysEvtMask. Returns evtNotEnb (1) if event masked out.
|
| Called during boot.
PostEvent:
        MOVE    (SysEvtMask).w,D2               | D2 = system event mask (bit per event type)
        MOVE    A0,D1                           | D1 = event number
        BTST    D1,D2                           | is this event type enabled?
        BNE.B   POSTEVENT_ENABLED               | yes -> post it
        MOVEQ.L #0x1,D0                         | D0 = 1 (evtNotEnb: event not enabled)
        RTS                                     | return

| ----------------------------------------------------------
|
| POSTEVENT_ENABLED - event is enabled, find a free event record and enqueue it
| Event records are in a circular buffer (SysEvtBuf). Each record is
| 22 bytes: 6-byte queue header + 16-byte event data (evtNum, evtMessage,
| evtTicks, evtMouse, evtMeta, evtMBut).
| Searches for a "free" record (evtNum = -1). If none free, steals the
| oldest event from queue head.
|
| Called during boot.
POSTEVENT_ENABLED:
        MOVE    SR,-(SP)                        | save interrupt state
        MOVE.L  D0,-(SP)                        | save event message on stack
        MOVE    A0,-(SP)                        | save event number on stack
        MOVE.L  (SysEvtBuf).w,A0                | A0 = event buffer base
        ADDQ.L  #0x6,A0                         | skip queue header to first evtNum field
        MOVEQ.L #0x16,D0                        | D0 = 22 = event record size
        MOVEQ.L #-0x1,D1                        | D1 = -1 (marker for free event record)
        SUBA    D0,A0                           | pre-decrement for loop (ADDA first in loop)
        MOVE    (EvtBufCnt).w,D2                | D2 = number of event buffer slots
        ORI     #0x100,SR                       | disable interrupts during queue manipulation
POSTEVENT_SCAN_LOOP:
        ADDA    D0,A0                           | advance to next event record's evtNum
        CMP     (A0),D1                         | evtNum == -1? (free slot)
        DBEQ    D2,POSTEVENT_SCAN_LOOP          | loop until free slot found or all checked
        LEA.L   (EventQueue).w,A1               | A1 = event queue header
        BEQ.B   POSTEVENT_FILL                  | found free slot -> use it
| No free slot: steal oldest event from queue head
        MOVE.L  0x2(A1),A0                      | A0 = queue head element (oldest event)
        MOVE.L  (A0),0x2(A1)                    | dequeue: head = head->qLink
        ADDQ.L  #0x6,A0                         | A0 past queue header to evtNum field
POSTEVENT_FILL:
| Fill in the event record
        MOVE    (SP)+,(A0)                      | store evtNum (event number)
        MOVE.L  (SP)+,0x2(A0)                   | store evtMessage
        BSR.B   FILL_EVENT_FIELDS               | fill evtTicks, evtMouse, evtMeta, evtMBut
        SUBQ.L  #0x6,A0                         | back up to queue element header
        MOVE    #0x4,0x4(A0)                    | qType = evType (4)
        JSR     Enqueue(PC)                     | add to EventQueue (at tail)
        MOVE    (SP)+,SR                        | restore interrupt state
        MOVEQ.L #0x0,D0                         | D0 = noErr
        RTS                                     | return

| ----------------------------------------------------------
|
| FILL_EVENT_FIELDS - Fill event record timestamp and modifier fields
| A0 points to evtNum field (event record + 6 bytes past queue header).
| Fills evtTicks, evtMouse (v,h), evtMeta (modifier keys), evtMBut.
|
| Called during boot (32,478 times in 30s trace).
FILL_EVENT_FIELDS:
        MOVE.L  (Ticks).w,0x6(A0)               | evtTicks = current tick count
        MOVE.L  (Mouse_v).w,0xA(A0)             | evtMouse = mouse position (v,h)
        MOVE    (KeyMap_6).w,D1                 | D1 = modifier key bits from KeyMap byte 12-13
        ROL     #0x1,D1                         | rotate: align modifier bits for evtMeta format
        MOVE.B  D1,0xE(A0)                      | evtMeta = modifier key state byte
        MOVE.B  (MBState).w,0xF(A0)             | evtMBut = mouse button state
        RTS                                     | return

| ----------------------------------------------------------
|
| _OSEventAvail ($A030)
| D0 = event mask (bit per event type), A0 = event record buffer ->
| D0 = 0 if event found (copied to buffer), D0 = -1 if no matching event.
| Peeks at the event queue without dequeuing. Also generates auto-key
| repeat events (autoKeyEvt=5) when a key is held past KeyThresh ticks.
|
| Called during boot (32,478 times in 30s trace).
OSEventAvail:
        LEA.L   (EventQueue).w,A1               | A1 = event queue header
        MOVE    SR,-(SP)                        | save interrupt state
        ORI     #0x100,SR                       | disable interrupts during queue scan
        MOVE.L  0x2(A1),D1                      | D1 = queue head (first event element)
        BEQ.B   OSEVTAVAIL_CHK_AUTOKEY          | queue empty -> check auto-key repeat
OSEVTAVAIL_WALK:
| Walk the event queue looking for an event matching the caller's mask
        MOVE.L  D1,A1                           | A1 = current queue element
        MOVE    dCtlQueue(A1),D1                | D1 = evtNum (at offset 6 in queue element)
        BTST    D1,D0                           | is this event type in caller's mask?
        BNE.B   OSEVTAVAIL_FOUND                | yes -> return this event
        MOVE.L  (A1),D1                         | D1 = qLink (next element)
        BNE.B   OSEVTAVAIL_WALK                 | more elements -> keep searching
OSEVTAVAIL_CHK_AUTOKEY:
| No matching event found; check if auto-key repeat should fire
        AND     (SysEvtMask).w,D0               | mask with system event mask
        TST     (KeyLast).w                     | any key held down?
        BEQ.B   OSEVTAVAIL_NO_EVENT             | no -> return "no event"
        BTST    #0x5,D0                         | bit 5 = autoKeyEvt enabled in mask?
        BEQ.B   OSEVTAVAIL_NO_EVENT             | auto-key not requested -> no event
        MOVE.L  (Ticks).w,D1                    | D1 = current tick count
        MOVE.L  D1,D2                           | D2 = copy for repeat threshold check
        SUB.L   (KeyTime).w,D1                  | D1 = ticks since initial key-down
        CMP     (KeyThresh).w,D1                | past initial repeat delay?
        BLT.B   OSEVTAVAIL_NO_EVENT             | not yet -> no auto-key event
        SUB.L   (KeyRepTime).w,D2               | D2 = ticks since last repeat event
        CMP     (KeyRepThresh).w,D2             | past repeat interval?
        BLT.B   OSEVTAVAIL_NO_EVENT             | not yet -> no auto-key event
| Generate auto-key repeat event
        MOVE.L  (Ticks).w,(KeyRepTime).w        | reset repeat timer
        MOVE.L  A0,-(SP)                        | save caller's event record buffer
        MOVE    #0x5,A0                         | A0 = autoKeyEvt (event code 5)
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (KeyLast).w,D0                  | D0 = last key-down message (keyCode|charCode)
        BSR     PostEvent                       | post autoKeyEvt to event queue
        MOVE.L  A0,A1                           | A1 = the just-posted event element
        MOVE.L  (SP)+,A0                        | restore caller's event record buffer
OSEVTAVAIL_FOUND:
| Found (or generated) a matching event; copy 16-byte event record to buffer
        MOVE    (SP)+,SR                        | restore interrupt state
        MOVEQ.L #0x4,D0                         | D0 = 4 (loop count: 4 longs = 16 bytes)
        MOVEM.L A0-A1,-(SP)                     | save buffer and element pointers
        ADDQ.L  #0x6,A1                         | skip queue header to evtNum field
OSEVTAVAIL_COPY_LOOP:
        MOVE.L  (A1)+,(A0)+                     | copy 4 bytes of event record
        SUBQ.W  #0x1,D0                         | decrement loop counter
        BNE.B   OSEVTAVAIL_COPY_LOOP            | loop 4 times (16 bytes total)
        MOVEM.L (SP)+,A0-A1                     | restore pointers
        RTS                                     | D0 = 0 (event found)

| ----------------------------------------------------------
|
| OSEVTAVAIL_NO_EVENT - no matching event: fill buffer with null event, return -1
|
| Called during boot (32,476 times in 30s trace).
OSEVTAVAIL_NO_EVENT:
        BSR     FILL_EVENT_FIELDS               | fill null event with current timestamp/modifiers
        MOVE    (SP)+,SR                        | restore interrupt state
        CLR     (A0)                            | evtNum = 0 (nullEvt)
        CLR.L   0x2(A0)                         | evtMessage = 0
        MOVEQ.L #-0x1,D0                        | D0 = -1 (no event found)
        RTS                                     | return

