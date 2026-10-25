| Device Manager
|
| Apple source: DeviceMgr.a (MacSEROM.lst module IOCORE): the jump offsets
| FSIODNETBL (JFetch, JStash, JIODone), FETCH, STASH, IODONE, the
| request queueing and the traps Open ... KillIO, DrvrInstall, DrvrRemove,
| AddDrive.
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

| FSIODNETBL - Device Manager I/O parameter block template
| 6 bytes: ioTrap offsets for Open/Close/Read/Write/Control/Status
| Apple source module: IOCORE
FSIODNETBL:
    .long	0x0006004A                            | Open/Close entry offsets
    .short	0x0052                               | Read/Write entry offset
| FETCH - read next byte from serial input buffer (SCC driver)
|
| Entry: D0 bit 15 = 0 (fetch mode)
| A1 = DCE pointer -> dCtlQHead -> serial buffer
| Exit: D0 = byte read (bit 15 set if buffer exhausted)
FETCH:
    BCLR	#0xF,D0                                | clear bit 15 (fetch mode indicator)
FETCH_STASH_COMMON:
    MOVEM.L	D1/A2-A3,-(A7)                      | save work registers
    MOVE.L	0x8(A1),D1                           | D1 = dCtlQHead (I/O request)
    BEQ.B	IO_CORE_ERR                           | no request: fatal error
    MOVEA.L	D1,A3                               | A3 = I/O param block
    MOVE.L	0x28(A3),D1                          | D1 = buffer position index
    MOVEA.L	0x20(A3),A2                         | A2 = buffer base address
    BCLR	#0xF,D0                                | write mode? (bit 15 was set)
    BNE.B	FETCH_STASH_WRITE                     | yes: write byte to buffer
    MOVE.B	0x0(A2,D1.L),D0                      | D0 = read byte from buffer[index]
    BRA.B	FETCH_STASH_ADVANCE                   | advance index
| FETCH_STASH_WRITE - write byte to buffer (Stash path)
FETCH_STASH_WRITE:
    MOVE.B	D0,0x0(A2,D1.L)                      | buffer[index] = D0
FETCH_STASH_ADVANCE:
    ADDQ.L	#0x1,D1                              | advance buffer index
    MOVE.L	D1,0x28(A3)                          | store updated index
    CMP.L	0x24(A3),D1                           | index >= buffer size?
    BLT.B	FETCH_STASH_EXIT                      | no: more room
    BSET	#0xF,D0                                | yes: set buffer-exhausted flag
FETCH_STASH_EXIT:
    EXT.L	D0                                    | sign-extend result to long
    MOVEM.L	(A7)+,D1/A2-A3                      | restore work registers
    RTS                                         | return from Fetch/Stash
IO_CORE_ERR:
    MOVEQ.L	#0xE,D0                             | dsBadDrvrRef: bad driver reference
    _SysError                                   | fatal: system error 14
| STASH - write byte to serial output buffer
|
| Entry: D0 = byte to write (bit 15 will be set as write indicator)
STASH:
    BSET	#0xF,D0                                | set bit 15 (write/stash mode)
    BRA.B	FETCH_STASH_COMMON                    | use common Fetch/Stash path
| IODONE wrapper - call IODone preserving D0
IODONE_WRAPPER:
    MOVEQ.L	#0x0,D0                             | D0 = noErr
IODONE:
    MOVE.W	D0,-(A7)                             | save result code
    BSR.B	IODone                                | process I/O completion
    MOVE.W	(A7)+,D0                             | restore result code
    RTS                                         | return from IODone wrapper
| ----------------------------------------------------------
|
| IODone - complete an asynchronous I/O request
|
| Called via JIODone vector ($08FC) when a driver finishes an I/O
| operation. A1 = DCE pointer, D0 = result code.
| Dequeues the completed request, calls its completion routine,
| and starts the next queued request if any.
IODone:
    MOVE.L	0x8(A1),D1                           | D1 = dCtlQHead: current I/O request
    BEQ.B	UNLOCK_DRV_CHECK                      | no request queued: just clear busy flag
    MOVE.W	SR,-(A7)                             | save SR for later restore
    MOVE.W	SR,D1                                | D1 = save SR for completion routine
    ORI.W	#0x300,SR                             | raise IPL to 3 (block interrupts)
    BSR.B	CLEAR_DRV_BUSY                        | clear driver busy flag + unlock
    BSR.B	DEQUEUE_IOREQ                         | dequeue request, call completion
    ORI.W	#0x300,SR                             | re-raise IPL after completion
    TST.L	0x8(A1)                               | more requests in driver queue?
    BNE.B	DISPATCH_NEXT_REQ                     | yes: start next request
    MOVE.W	(A7)+,SR                             | no: restore SR and return
    RTS                                         | return from IODone
| ----------------------------------------------------------
|
| CLEAR_DRV_BUSY - Clear driver busy flag and unlock driver resource
|
| A1 = DCE pointer. Clears the "busy" bit (bit 7) of dCtlFlags+1
| and, unless dNeedLock is set, unlocks the driver handle in both
| the handle master pointer and the zone header.
CLEAR_DRV_BUSY:
    BCLR	#0x7,0x5(A1)                           | clear drvrActive (bit 7 of the low flag byte)
UNLOCK_DRV_CHECK:
    BTST	#0x6,0x4(A1)                           | dNeedLock (bit 6 of the high flag byte)?
    BNE.B	UNLOCK_DRV_DONE                       | yes: leave the driver locked
    MOVEA.L	(A1),A0                             | A0 = driver handle master pointer
    BCLR	#0x7,(A0)                              | clear lock bit on handle
    MOVEA.L	(SysZone).W,A0                      | A0 = system zone header
    ADDA.L	-0x4(A1),A0                          | add DCE offset to get zone entry
    BCLR	#0x7,(A0)                              | clear lock bit in zone
UNLOCK_DRV_DONE:
    RTS                                         | return from unlock check
| DEQUEUE_IOREQ - dequeue completed I/O request and call completion
|
| Unlinks the head IOParam from driver queue, sets ioResult,
| calls ioCompletion routine if non-nil, restores SR.
| A1 = DCE, D0 = result code, D1 = saved SR for restore
DEQUEUE_IOREQ:
    MOVEA.L	0x8(A1),A0                          | A0 = dCtlQHead (completed request)
    CMPI.W	#0x2,0x4(A0)                         | qType == ioQType (2)?
    BNE.B	IO_CORE_ERR                           | bad type: fatal error
    MOVE.L	(A0),0x8(A1)                         | dCtlQHead = next request in chain
    BNE.B	DEQUEUE_RESTORE_SR                    | queue not empty: skip tail clear
    CLR.L	0xC(A1)                               | queue empty: clear dCtlQTail
DEQUEUE_RESTORE_SR:
    MOVE.W	D1,SR                                | restore SR (re-enable interrupts)
    MOVE.W	D0,0x10(A0)                          | ioResult = D0 (result code)
    BLE.B	DEQUEUE_CHK_COMPL                     | negative or zero: keep result
    CLR.W	0x10(A0)                              | positive result: clear to noErr
DEQUEUE_CHK_COMPL:
    MOVE.L	0xC(A0),D1                           | D1 = ioCompletion routine
    BEQ.B	DEQUEUE_DONE                          | nil: no completion routine
    MOVE.L	A1,-(A7)                             | save DCE pointer
    MOVEA.L	D1,A1                               | A1 = completion routine address
    EXT.L	D0                                    | sign-extend result for completion
    JSR	(A1)                                    | call ioCompletion(A0=IOParam, D0=result)
    MOVEA.L	(A7)+,A1                            | restore DCE pointer
DEQUEUE_DONE:
    RTS                                         | return from dequeue/completion
| ENQUEUE_IOREQ - enqueue I/O request into driver queue
|
| Adds IOParam block (A0) to driver's I/O queue (A1+6),
| then dispatches if driver is not busy.
| A0 = IOParam, A1 = DCE
ENQUEUE_IOREQ:
    MOVE.L	A1,D1                                | save DCE pointer in D1
    LEA.L	0x6(A1),A1                            | A1 = driver I/O queue header
    MOVE.W	SR,-(A7)                             | save SR
    ORI.W	#0x300,SR                             | raise IPL (atomic enqueue)
    JSR	ENQUEUE(PC)                             | enqueue IOParam into driver queue
    MOVEA.L	D1,A1                               | restore DCE pointer
| DISPATCH_NEXT_REQ - try to start next I/O request
DISPATCH_NEXT_REQ:
    BSET	#0x7,0x5(A1)                           | set driver busy flag (dCtlFlags bit 7)
    BEQ.B	START_HEAD_REQ                        | was clear: driver free, start request
    MOVEQ.L	#0x0,D0                             | D0 = noErr (already busy, queued OK)
    MOVE.W	(A7)+,SR                             | restore SR
    RTS                                         | return (request will run later)
| ----------------------------------------------------------
|
| START_HEAD_REQ - Start processing the head I/O request
|
| Driver was not busy. Determine which driver entry point to call
| based on the ioTrap field of the IOParam block: _Control (4),
| _Status (5), or _Read/_Write (prime).
START_HEAD_REQ:
    MOVE.W	(A7)+,SR                             | restore SR
    MOVEA.L	0x8(A1),A0                          | A0 = head IOParam from dCtlQHead
START_HEAD_IOPARAM:
    MOVEQ.L	#0xC,D1                             | D1 = 12 (Control entry offset)
    CMPI.B	#0x4,0x7(A0)                         | ioTrap low byte = 4 (_Control)?
    BEQ.B	CALL_DRV_ENTRY                        | yes: call Control entry
    MOVEQ.L	#0xE,D1                             | D1 = 14 (Status entry offset)
    CMPI.B	#0x5,0x7(A0)                         | ioTrap low byte = 5 (_Status)?
    BEQ.B	CALL_DRV_ENTRY                        | yes: call Status entry
| Read/Write Prime path: set file position before calling driver
    TST.L	0x24(A0)                              | ioReqCount = 0? (no data to transfer)
    BEQ.W	IODONE_WRAPPER                        | yes: no data to transfer, done
    MOVE.W	0x2C(A0),D0                          | D0 = ioPosMode (positioning mode)
    MOVE.L	0x2E(A0),D1                          | D1 = ioPosOffset (position value)
    ROXR.B	#0x2,D0                              | shift mode bits: bit1->X, bit0->bit7
    BPL.B	IO_PRIME_ENTRY                        | mode 0: no position change
    BCC.B	IO_SET_POSITION                       | mode 1: absolute position
    ADD.L	0x10(A1),D1                           | mode 3: relative (add current pos)
IO_SET_POSITION:
    MOVE.L	D1,0x10(A1)                          | update dCtlPosition
IO_PRIME_ENTRY:
    MOVEQ.L	#0xA,D1                             | D1 = 10 (Prime entry offset in driver)
| ----------------------------------------------------------
|
| CALL_DRV_ENTRY - Call driver entry point
|
| A1 = DCE pointer, A0 = IOParam block, D1 = entry point offset
| in driver header (drvrOpen=$08, drvrPrime=$0A, drvrCtl=$0C,
| drvrStatus=$0E). Loads and locks RAM-based drivers as needed.
| Called by: START_HEAD_IOPARAM, OPEN_CALL_DRIVER, CLOSE_WAIT_BUSY, KILLIO
CALL_DRV_ENTRY:
    MOVE.L	(A1),D0                              | D0 = dCtlDriver (handle or ROM ptr)
    BNE.B	CALL_DRV_LOCK                         | valid: proceed
    MOVEQ.L	#-0x16,D0                           | dsBadDrvrRef (-22): no driver loaded
    MOVE.W	D0,0x10(A0)                          | ioResult = error
    RTS                                         | return error
CALL_DRV_LOCK:
    MOVEM.L	D3-D7/A1-A6,-(A7)                   | save all registers for driver call
    MOVEA.L	D0,A2                               | A2 = driver handle/pointer
    BTST	#0x6,0x5(A1)                           | dCtlFlags bit 6: ROM-based driver?
    BEQ.B	CALL_DRV_EXEC                         | yes (0): driver in ROM, skip load
| RAM-based driver: lock handle and load if purged
    MOVEA.L	(SysZone).W,A3                      | A3 = system zone header
    ADDA.L	-0x4(A1),A3                          | add DCE offset to find zone entry
    BSET	#0x7,(A3)                              | lock driver handle in zone
    TST.L	(A2)                                  | handle master pointer nil? (purged?)
    BNE.B	OPEN_LOCK_DRVR                        | not nil: already loaded
    MOVE.L	A2,-(A7)                             | push handle for _LoadResource
    _LoadResource                               | reload purged driver resource
    MOVE.W	(ResErr).W,D0                        | D0 = resource error
    BNE.B	CALL_DRV_LOADFAIL                     | load failed: return error
OPEN_LOCK_DRVR:
    EXG	A0,A2                                   | A0 = handle (for _HLock)
    _HLock                                      | lock driver handle in memory
    EXG	A0,A2                                   | restore A0 = IOParam, A2 = handle
    MOVE.L	(A2),-(A7)                           | dereference handle -> pointer
    CLR.B	(A7)                                  | clear high byte (24-bit clean)
    MOVEA.L	(A7)+,A2                            | A2 = driver code pointer
| Execute driver entry point
CALL_DRV_EXEC:
    MOVE.W	0x0(A2,D1.W),D1                      | D1 = entry point offset from header
    MOVEQ.L	#0x0,D0                             | D0 = noErr (default result)
    JSR	0x0(A2,D1.W)                            | call driver entry point
    BRA.B	CALL_DRV_EXIT                         | clean up and return
| CALL_DRV_LOADFAIL - resource load failed
CALL_DRV_LOADFAIL:
    MOVE.W	D0,0x10(A0)                          | ioResult = resource error
CALL_DRV_EXIT:
    EXT.L	D0                                    | sign-extend result to long
    MOVEM.L	(A7)+,D3-D7/A1-A6                   | restore all registers
    RTS                                         | return from driver call
| ----------------------------------------------------------
|
| LOOKUP_UNIT - Look up a driver in the unit table
|
| D2 = driver refNum (negated unit number - 1). Converts to unit
| number, bounds-checks, and returns DCE pointer in A1.
| On failure, branches to UNIT_EMPTY_ERR (unitEmptyErr).
| Called by: OPEN_INIT_DCE, CLOSE_DEVICE, DEVIO_COMMON, STATUS_DEVICE, KILLIO
LOOKUP_UNIT:
    NOT.W	D2                                    | D2 = ~refNum (convert to unit #)
    BMI.B	OPEN_LOOKUP_RTS                       | negative unit #: invalid
    CMP.W	(UnitTableEntryCount).W,D2            | unit # >= table size?
    BGE.B	OPEN_LOOKUP_RTS                       | out of range: invalid
    ASL.W	#0x2,D2                               | D2 *= 4 (longword index)
    MOVEA.L	(UTableBase).W,A1                   | A1 = unit table base
    MOVE.L	0x0(A1,D2.W),D2                      | D2 = DCE handle for this unit
    BEQ.B	OPEN_LOOKUP_RTS                       | nil: unit not installed
    MOVEA.L	D2,A2                               | A2 = DCE handle
    MOVE.L	(A2),D2                              | D2 = DCE pointer (deref handle)
    BEQ.W	IO_CORE_ERR                           | nil: DCE purged, fatal error
    MOVEA.L	D2,A1                               | A1 = DCE record
    RTS                                         | return from LOOKUP_UNIT
OPEN_LOOKUP_RTS:
    MOVEA.L	D5,A0                               | A0 = restore IOParam
    MOVEM.L	(A7)+,D0/D3-D5/A2-A4                | restore registers
    MOVEQ.L	#-0x15,D0                           | unitEmptyErr (-21): unit not installed
    MOVE.W	D0,0x10(A0)                          | ioResult = error
    RTS                                         | return from LOOKUP_UNIT
| DEVMGR_OPEN_DISP - Open by refNum: driver found, check for file open
DEVMGR_OPEN_DISP:
    MOVEA.L	D5,A0                               | A0 = restore IOParam pointer
    MOVE.W	0x6(A0),D1                           | D1 = saved trap word
    MOVEM.L	(A7)+,D3-D5/A2-A4                   | restore registers
    CMPI.B	#0x40,0x1B(A0)                       | ioPermssn = fsRdPerm (file open)?
    BEQ.B	BAD_UNIT_ERR                          | yes: return permission error
    JMP	FILEOPEN(PC)                            | no: dispatch to File Manager _Open
BAD_UNIT_ERR:
    MOVEQ.L	#-0x17,D0                           | permErr (-23): permission error
    BRA.W	OPEN_STORE_RESULT                     | store result and return
| OPEN - _Open trap: open a device driver by name or refNum
|
| Entry: A0 = IOParam, D1 = trap word
| IOParam.ioNamePtr (+0x12) = driver name (Pascal string)
| IOParam.ioPermssn (+0x1B) = permission
| Exit: D0 = result, IOParam.ioRefNum (+0x18) = driver refNum
OPEN:
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save work registers
    MOVE.L	A0,D5                                | D5 = save IOParam pointer
    MOVE.W	D1,0x6(A0)                           | ioTrap = trap word
    MOVE.W	0x1A(A0),D2                          | D2 = ioRefNum (or ioPermssn high)
    MOVEA.L	0x12(A0),A0                         | A0 = ioNamePtr (driver name string)
    MOVEQ.L	#0x0,D1                             | clear D1 high bytes
    MOVE.B	(A0)+,D1                             | D1 = name length, A0 -> name chars
    CMPI.B	#0x40,D2                             | open by name? (refNum = 0x40)
    BEQ.W	OPEN_SEARCH_BY_NAME                   | yes: search unit table by name
    CMPI.B	#0x2E,(A0)                           | name starts with '.'? (device name)
    BNE.B	DEVMGR_OPEN_DISP                      | no: open by refNum (file open path)
| Search unit table for a driver matching the given name
OPEN_SEARCH_BY_NAME:
    MOVEA.L	(UTableBase).W,A3                   | A3 = unit table base
    MOVE.W	(UnitTableEntryCount).W,D2           | D2 = number of unit table entries
    MOVEQ.L	#-0x1,D4                            | D4 = -1 (unit number counter, pre-inc)
OPEN_SCAN_UNIT_TBL:
    MOVE.L	(A3)+,D0                             | D0 = next DCE handle from unit table
    BEQ.B	OPEN_SCAN_NEXT                        | nil: slot empty, skip
    MOVEA.L	D0,A2                               | A2 = DCE handle
    MOVE.L	(A2),D0                              | D0 = DCE pointer (deref handle)
    BEQ.B	OPEN_SCAN_NEXT                        | nil: DCE purged, skip
    MOVEA.L	D0,A1                               | A1 = DCE record
    BTST	#0x6,0x5(A1)                           | dCtlFlags bit 6: ROM-based?
    MOVEA.L	(A1),A1                             | A1 = dCtlDriver (handle or ptr)
    BEQ.B	OPEN_CHECK_DRVR_PTR                   | ROM: A1 is direct pointer
    MOVE.L	A1,D0                                | RAM: A1 is handle
    BEQ.B	OPEN_SCAN_NEXT                        | nil handle: skip
    MOVEA.L	(A1),A1                             | deref handle to get driver pointer
OPEN_CHECK_DRVR_PTR:
    MOVE.L	A1,D0                                | D0 = driver code pointer
    BEQ.B	OPEN_SCAN_NEXT                        | nil: driver not loaded, skip
    LEA.L	0x12(A1),A1                           | A1 = driver name (offset 0x12 in header)
    MOVE.L	D1,D0                                | D0 = search name length
    SWAP.W	D0                                   | position for _CmpString
    MOVE.B	(A1)+,D0                             | D0 low = driver name length
    CMP.B	D0,D1                                 | same length?
    BNE.B	OPEN_SCAN_NEXT                        | no: names can't match
    _CmpString                                  | compare names (A0 vs A1, D0 lengths)
    BEQ.W	OPEN_LOCK_DRIVER                      | match: found driver, proceed to open
| Called by: OPEN_SCAN_UNIT_TBL, OPEN_CHECK_DRVR_PTR
OPEN_SCAN_NEXT:
    SUBQ.W	#0x1,D4                              | decrement unit number counter
    SUBQ.W	#0x1,D2                              | decrement remaining entries
    BGT.B	OPEN_SCAN_UNIT_TBL                    | more entries: keep searching
| Not found in unit table: try loading DRVR resource by name
    SUBQ.W	#0x4,A7                              | make room for result handle
    MOVE.L	#0x44525652,-(A7)                    | push 'DRVR' resource type
    MOVEA.L	D5,A0                               | A0 = IOParam (for ioNamePtr)
    MOVE.L	0x12(A0),-(A7)                       | push ioNamePtr (driver name)
    MOVE.W	#0xFFFF,(ROMMapInsert).W             | search ROM resource map first
    _GetNamedResource                           | load 'DRVR' resource by name
    MOVE.L	(A7)+,D3                             | D3 = resource handle (0 if not found)
    BNE.B	OPEN_GOT_RESOURCE                     | found: install and open driver
    MOVE.W	(ResErr).W,D0                        | D0 = resource error
    BEQ.W	DEVMGR_OPEN_DISP                      | resNotFound: try file open path
    CMPI.W	#0xFF40,D0                           | mapReadErr (-192)?
    BEQ.W	DEVMGR_OPEN_DISP                      | yes: try file open path
    BRA.W	OPEN_CLOSE_EXIT                       | other error: fail
| ----------------------------------------------------------
|
| OPEN_GOT_RESOURCE - DRVR resource found, get its resource ID to derive unit number
|
| Called during boot.
| OPEN_GOT_RESOURCE - DRVR resource loaded, get its ID for unit number
OPEN_GOT_RESOURCE:
    CLR.W	-(A7)                                 | make room for resource ID result
    MOVE.L	A7,D0                                | D0 = pointer to ID result
    MOVE.L	D3,-(A7)                             | push resource handle
    MOVE.L	D0,-(A7)                             | push @ID result
    CLR.L	-(A7)                                 | push nil (type result, unused)
    CLR.L	-(A7)                                 | push nil (name result, unused)
    MOVE.W	#0xFFFF,(ROMMapInsert).W             | search ROM map
    _GetResInfo                                 | get resource ID -> stack
    MOVE.W	(A7)+,D4                             | D4 = resource ID
    NOT.W	D4                                    | D4 = ~ID = refNum (unit number)
    MOVE.W	D4,D0                                | D0 = refNum for install
    BSR.W	LOOKUP_UNIT_SLOT                      | check if unit slot exists
    BMI.W	OPEN_CLOSE_EXIT                       | error: fail
    BNE.B	OPEN_INIT_DCE                         | slot exists: use it
| Slot empty: install new DCE
    MOVE.W	D4,D0                                | D0 = refNum
    MOVEA.L	D3,A0                               | A0 = DRVR resource handle
    MOVEA.L	(A0),A0                             | A0 = DRVR pointer (deref)
    BTST	#0x6,(A0)                              | driver needs locked memory? (bit 6)
    BEQ.B	OPEN_STD_INSTALL                      | no: standard install
    _DrvrInstallResrvMem                        | yes: install with reserved memory
    BRA.B	OPEN_AFTER_INSTALL                    | check result
OPEN_STD_INSTALL:
    _DrvrInstall                                | standard driver install
OPEN_AFTER_INSTALL:
    BNE.W	OPEN_CLOSE_EXIT                       | install failed: return error
| OPEN_INIT_DCE - DCE slot allocated, set up driver header fields
OPEN_INIT_DCE:
    MOVE.W	D4,D2                                | D2 = refNum for LOOKUP_UNIT
    BSR.W	LOOKUP_UNIT                           | get DCE pointer -> A1, handle -> A2
    BSET	#0x5,0x5(A1)                           | set dCtlFlags bit 5: driver open
    BNE.W	OPEN_LOCK_DRIVER                      | already open: skip init
    MOVEQ.L	#0x40,D0                            | D0 = 0x40 (RAM driver flag for dCtlFlags)
    MOVE.L	D3,(A1)                              | dCtlDriver = resource handle
    MOVEA.L	D3,A0                               | A0 = resource handle
    MOVE.L	(A0),D3                              | D3 = dereferenced pointer
    AND.L	(Lo3Bytes).W,D3                       | mask to 24-bit address
    MOVE.L	(ROMBase).W,-(A7)                    | push ROMBase
    CLR.B	(A7)                                  | mask to 24-bit
    CMP.L	(A7)+,D3                              | driver in ROM? (below ROMBase)
    BCS.B	OPEN_COPY_DRVR_HDR                    | yes: RAM driver, keep handle
    MOVE.L	D3,(A1)                              | ROM: store direct pointer
    MOVEQ.L	#0x0,D0                             | D0 = 0 (ROM driver flag)
| Copy driver header fields to DCE
OPEN_COPY_DRVR_HDR:
    MOVEA.L	D3,A0                               | A0 = driver code pointer
    MOVE.W	(A0)+,0x4(A1)                        | dCtlFlags = drvrFlags
    MOVE.B	D0,0x5(A1)                           | dCtlFlags low = RAM/ROM indicator
    MOVE.L	(A0)+,0x22(A1)                       | dCtlMenu = drvrMenu (menu ID + tick)
    MOVE.W	(A0)+,0x26(A1)                       | dCtlDelay = drvrDelay
| OPEN_LOCK_DRIVER - driver found (already installed), prepare to call Open
OPEN_LOCK_DRIVER:
    MOVEA.L	(A2),A1                             | A1 = DCE record (deref DCE handle)
    BTST	#0x6,0x4(A1)                           | dCtlFlags bit 6: needs locking?
    BEQ.B	OPEN_CHK_PERM                         | no: skip lock
    MOVEA.L	(A1),A0                             | A0 = dCtlDriver (handle)
    BTST	#0x6,0x5(A1)                           | ROM-based? (bit 6)
    BEQ.B	OPEN_LOCK_DCE                         | yes: don't lock ROM pointer
    _HLock                                      | lock driver handle in memory
OPEN_LOCK_DCE:
    MOVEA.L	A2,A0                               | A0 = DCE handle
    _HLock                                      | lock DCE handle
| Check open permission compatibility
OPEN_CHK_PERM:
    MOVEA.L	D5,A0                               | A0 = IOParam block
    MOVE.W	D4,0x18(A0)                          | ioRefNum = driver refNum
    MOVEQ.L	#-0x17,D0                           | D0 = permErr (-23) (default)
    MOVE.B	0x4(A1),D1                           | D1 = dCtlFlags (read/write perms)
    MOVE.W	D1,D2                                | D2 = save flags
    OR.B	0x1B(A0),D1                            | merge requested permission
    EOR.B	D2,D1                                 | D1 = requested bits NOT in flags
    ANDI.B	#0x3,D1                              | mask read/write permission bits
    BNE.W	OPEN_CLOSE_EXIT                       | mismatch: permission error
    BSET	#0x5,0x5(A1)                           | set dCtlFlags bit 5: driver open
    BEQ.B	OPEN_CALL_DRIVER                      | was clear: first open, call drvrOpen
    CMPI.B	#0x40,0x1B(A0)                       | permission = fsRdPerm only?
    BNE.B	OPEN_RET_NOERR                        | no: already open, return success
| Call drvrOpen entry point (offset 8 in driver header)
OPEN_CALL_DRIVER:
    MOVEQ.L	#0x8,D1                             | D1 = 8 (drvrOpen entry offset)
    BSR.W	CALL_DRV_ENTRY                        | call driver Open entry
    BPL.B	OPEN_DCE_FAIL                         | success (D0 >= 0): open complete
    MOVEA.L	D5,A0                               | A0 = IOParam (restore)
    CLR.W	0x18(A0)                              | clear ioRefNum (open failed)
    BCLR	#0x5,0x5(A1)                           | clear dCtlFlags bit 5 (not open)
    BRA.B	OPEN_UNLOCK_RAM                       | unlock and return error
OPEN_DCE_FAIL:
    NOP                                         | (alignment pad)
| OPEN_CHK_LOCK - check if driver needs unlocking after close/open
OPEN_CHK_LOCK:
    BTST	#0x6,0x4(A1)                           | dCtlFlags bit 6: needs locking?
    BNE.B	OPEN_CLOSE_EXIT                       | no lock needed: skip to exit
| OPEN_UNLOCK_RAM - unlock RAM driver and DCE handles
OPEN_UNLOCK_RAM:
    MOVEA.L	(A1),A0                             | A0 = dCtlDriver handle
    BTST	#0x6,0x5(A1)                           | ROM-based driver? (bit 6)
    BEQ.B	OPEN_CLOSE_EXIT                       | ROM: no unlock needed
    EXG	D0,D3                                   | save result across _HUnlock
    _HUnlock                                    | unlock driver handle
    EXG	D0,D3                                   | restore result
    BTST	#0x6,0x4(A1)                           | needs DCE unlock too?
    BNE.B	OPEN_CLOSE_EXIT                       | no: done
    MOVEA.L	A2,A0                               | A0 = DCE handle
    EXG	D0,D3                                   | save result
    _HUnlock                                    | unlock DCE handle
    EXG	D0,D3                                   | restore result
| OPEN_CLOSE_EXIT - Open/Close common exit: restore regs, set ioResult
| Called by: OPEN_UNLOCK_RAM, OPEN_SCAN_NEXT, OPEN_GOT_RESOURCE, OPEN_AFTER_INSTALL, OPEN_CHK_PERM (and 3 more)
OPEN_CLOSE_EXIT:
    MOVEA.L	D5,A0                               | A0 = restore IOParam
    MOVEM.L	(A7)+,D3-D5/A2-A4                   | restore work registers
OPEN_STORE_RESULT:
    MOVE.W	D0,0x10(A0)                          | ioResult = D0
    RTS                                         | return from Open/Close
OPEN_RET_NOERR:
    MOVEQ.L	#0x0,D0                             | D0 = noErr
    BRA.B	OPEN_CLOSE_EXIT                       | return success
| CLOSE - _Close trap: close a device driver
|
| Entry: A0 = IOParam, ioRefNum (+0x18) identifies driver
| Negative refNum = device driver; positive = file (dispatch to FS)
CLOSE:
    MOVE.W	0x18(A0),D2                          | D2 = ioRefNum
    BMI.B	CLOSE_DEVICE                          | negative: device driver close
    JMP	FILECLOSE(PC)                           | positive: File Manager _Close
CLOSE_DEVICE:
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save work registers
    MOVE.L	A0,D5                                | D5 = save IOParam
    BSR.W	LOOKUP_UNIT                           | look up DCE from refNum
    BTST	#0x5,0x5(A1)                           | dCtlFlags bit 5: driver open?
    BEQ.B	OPEN_RET_NOERR                        | not open: return noErr
CLOSE_WAIT_BUSY:
    BTST	#0x7,0x5(A1)                           | dCtlFlags bit 7: driver busy?
    BNE.B	CLOSE_WAIT_BUSY                       | yes: spin until not busy
    MOVEQ.L	#0x10,D1                            | D1 = 16 (drvrClose entry offset)
    BSR.W	CALL_DRV_ENTRY                        | call driver Close entry
    CMPI.W	#0xFFE8,D0                           | closErr (-24): close failed?
    BEQ.B	OPEN_CHK_LOCK                         | yes: unlock only (don't clear open)
    BCLR	#0x5,0x5(A1)                           | clear dCtlFlags bit 5 (driver closed)
    BRA.B	OPEN_UNLOCK_RAM                       | unlock handles and return
| READ - _Read trap: read from device or file
|
| Negative ioRefNum = device, positive = file.
| D4 = 0 = dCtlFlags bit to test for read permission (bit 0).
READ:
    MOVE.W	0x18(A0),D2                          | D2 = ioRefNum
    BMI.B	READ_DEVICE                           | negative: device read
    JMP	FILEREAD(PC)                            | positive: File Manager _Read
READ_DEVICE:
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save work registers
    MOVEQ.L	#-0x13,D0                           | D0 = readErr (-19) (default error)
    MOVEQ.L	#0x0,D4                             | D4 = 0 (test bit 0: read permission)
| DEVIO_COMMON - common Read/Write/Control/Status dispatch
|
| D0 = default error code, D4 = permission bit to test
DEVIO_COMMON:
    MOVE.L	A0,D5                                | D5 = save IOParam
    BSR.W	LOOKUP_UNIT                           | look up DCE from ioRefNum (D2)
    CMPI.B	#0x3,D1                              | trap word <= 3? (Read/Write)
    BGT.B	DEVIO_SET_INPROGRESS                  | Control/Status: skip position clear
    CLR.L	0x28(A0)                              | clear ioActCount (for Read/Write)
DEVIO_SET_INPROGRESS:
    MOVE.W	#0x1,0x10(A0)                        | ioResult = 1 (in progress)
    MOVE.W	D1,0x6(A0)                           | ioTrap = trap word
    MOVE.W	#0x2,0x4(A0)                         | qType = ioQType (2)
    BTST	D4,0x4(A1)                             | check permission bit in dCtlFlags
    MOVEM.L	(A7)+,D3-D5/A2-A4                   | restore work registers
    BEQ.B	DEVIO_STORE_RESULT                    | permission denied: return error
    MOVEQ.L	#-0x1C,D0                           | dsBadDrvrRef (-28): not open
    BTST	#0x5,0x5(A1)                           | dCtlFlags bit 5: driver open?
    BEQ.B	DEVIO_STORE_RESULT                    | not open: return error
| Dispatch based on trap word bits 9-10
    BTST	#0x9,D1                                | bit 9: immediate (no queue)?
    BNE.W	START_HEAD_IOPARAM                    | yes: call driver directly
    BTST	#0xA,D1                                | bit 10: async?
    BNE.W	ENQUEUE_IOREQ                         | yes: enqueue and return
| Synchronous I/O: enqueue, then poll ioResult until complete
    CLR.L	0xC(A0)                               | clear ioCompletion (sync: no callback)
    MOVE.L	A0,-(A7)                             | save IOParam
    BSR.W	ENQUEUE_IOREQ                         | enqueue and start
    MOVEA.L	(A7)+,A0                            | restore IOParam
DEVIO_POLL_RESULT:
    MOVE.W	0x10(A0),D0                          | D0 = ioResult
    BGT.B	DEVIO_POLL_RESULT                     | > 0 (in progress): keep polling
    EXT.L	D0                                    | sign-extend result
DEVIO_STORE_RESULT:
    MOVE.W	D0,0x10(A0)                          | ioResult = D0
    RTS                                         | return from Read/Write/Control/Status
| WRITE - _Write trap: write to device or file
WRITE:
    MOVE.W	0x18(A0),D2                          | D2 = ioRefNum
    BMI.B	WRITE_DEVICE                          | negative: device write
    JMP	FILEWRITE(PC)                           | positive: File Manager _Write
WRITE_DEVICE:
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save work registers
    MOVEQ.L	#-0x14,D0                           | D0 = writErr (-20) (default)
    MOVEQ.L	#0x1,D4                             | D4 = 1 (test bit 1: write permission)
    BRA.B	DEVIO_COMMON                          | join common dispatch
| P_tControl - _Control trap handler
P_tControl:
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save work registers
    MOVE.W	0x18(A0),D2                          | D2 = ioRefNum
    MOVEQ.L	#-0x11,D0                           | D0 = controlErr (-17) (default)
    MOVEQ.L	#0x2,D4                             | D4 = 2 (test bit 2: control perm)
    BRA.B	DEVIO_COMMON                          | join common dispatch
| P_tStatus - _Status trap handler
|
| Special case: csCode = 1 returns DCE handle in csParam.
P_tStatus:
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save work registers
    MOVE.W	0x18(A0),D2                          | D2 = ioRefNum
    MOVE.L	A0,D5                                | D5 = save IOParam
    CMPI.W	#0x1,0x1A(A0)                        | csCode = 1? (return DCE handle)
    BEQ.B	STATUS_DEVICE                         | yes: return handle directly
    MOVEQ.L	#-0x12,D0                           | D0 = statusErr (-18) (default)
    MOVEQ.L	#0x3,D4                             | D4 = 3 (test bit 3: status perm)
    BRA.W	DEVIO_COMMON                          | join common dispatch
STATUS_DEVICE:
    BSR.W	LOOKUP_UNIT                           | look up DCE
    MOVE.L	A2,0x1C(A0)                          | csParam = DCE handle
    BRA.W	OPEN_RET_NOERR                        | return noErr
| KILLIO - _KillIO trap: abort pending I/O on a driver
|
| Sends a Control call (csCode=1) to kill pending requests,
| then drains the driver's I/O queue by completing each with abortErr.
KILLIO:
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save work registers
    MOVE.W	0x18(A0),D2                          | D2 = ioRefNum
    MOVE.L	A0,D5                                | D5 = save IOParam
    BSR.W	LOOKUP_UNIT                           | look up DCE
    MOVE.W	#0x1,0x1A(A0)                        | csCode = 1 (killIO)
    MOVE.W	SR,-(A7)                             | save SR
    ORI.W	#0x300,SR                             | raise IPL (atomic queue access)
    MOVEQ.L	#0xC,D1                             | D1 = 12 (Control entry offset)
    MOVEQ.L	#-0x11,D0                           | D0 = controlErr (-17)
    MOVEQ.L	#0x2,D4                             | D4 = 2 (control permission bit)
    BTST	D4,0x4(A1)                             | driver supports Control?
    BEQ.B	KILLIO_RESTORE_SR                     | no: skip, drain queue only
    MOVEQ.L	#-0x1C,D0                           | D0 = notOpenErr (-28)
    BTST	#0x5,0x5(A1)                           | driver open?
    BEQ.B	KILLIO_RESTORE_SR                     | no: skip
    BSR.W	CALL_DRV_ENTRY                        | call driver Control (kill request)
    BNE.B	KILLIO_RESTORE_SR                     | error: skip queue drain
| KillIO queue drain: complete all pending requests with abortErr
KILLIO_DRAIN_QUEUE:
    TST.L	0x8(A1)                               | more requests in driver queue?
    BEQ.B	KILLIO_DONE                           | empty: done draining
    MOVEQ.L	#-0x1B,D0                           | D0 = abortErr (-27)
    MOVE.W	#0x2300,D1                           | D1 = SR value for completion
    BSR.W	DEQUEUE_IOREQ                         | dequeue + complete with abortErr
    BRA.B	KILLIO_DRAIN_QUEUE                    | drain next request
KILLIO_DONE:
    BSR.W	CLEAR_DRV_BUSY                        | clear driver busy flag + unlock
    MOVEQ.L	#0x0,D0                             | D0 = noErr
KILLIO_RESTORE_SR:
    MOVE.W	(A7)+,SR                             | restore SR
    BRA.W	OPEN_CLOSE_EXIT                       | return through Open/Close exit
| DRVRINSTALL - _DrvrInstall trap: allocate DCE for a driver
|
| Entry: D0 = refNum, A0 = driver handle (unused for slot alloc)
| Allocates a 50-byte (0x32) DCE handle in system heap,
| zeros it, installs in unit table, sets refNum and flags.
DRVRINSTALL:
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save work registers
    MOVEA.L	A0,A3                               | A3 = save driver handle
    MOVE.L	D0,D3                                | D3 = save refNum
    BSR.B	LOOKUP_UNIT_SLOT                      | find/validate unit table slot
    BMI.B	DRVRINSTALL_RTS                       | invalid refNum: return error
    BNE.B	DRVRINSTALL_ZERO_DCE                  | slot exists: reuse DCE
| Slot empty: allocate new DCE handle (50 bytes)
    BTST	#0xA,D1                                | _DrvrInstallResrvMem? (bit 10)
    BEQ.B	DRVRINSTALL_DO_ALLOC                  | no: standard alloc
    MOVEQ.L	#0x32,D0                            | D0 = 50 bytes (DCE size)
    _ResrvMemSys                                | reserve system heap space first
DRVRINSTALL_DO_ALLOC:
    MOVEQ.L	#0x32,D0                            | D0 = 50 bytes
    _NewHandleSys                               | allocate DCE handle in sys heap
    BNE.B	DRVRINSTALL_RTS                       | alloc failed: return error
| Zero-fill DCE and install in unit table
DRVRINSTALL_ZERO_DCE:
    MOVEQ.L	#0x31,D0                            | D0 = 49 (50 bytes - 1 for DBF)
    MOVEA.L	(A0),A1                             | A1 = DCE pointer (deref handle)
DRVRINST_ZERO_LOOP:
    CLR.B	(A1)+                                 | zero next byte
    DBF.W	D0,DRVRINST_ZERO_LOOP                 | loop 50 bytes
    MOVE.L	A0,(A2)                              | install DCE handle in unit table
    MOVEA.L	(A0),A3                             | A3 = DCE pointer
    BSET	#0x6,0x5(A3)                           | set dCtlFlags bit 6: RAM-based driver
    MOVE.W	D3,0x18(A3)                          | dCtlRefNum = refNum
DRVRINSTALL_OK:
    MOVEQ.L	#0x0,D0                             | D0 = noErr
DRVRINSTALL_RTS:
    MOVEM.L	(A7)+,D3-D5/A2-A4                   | restore work registers
    RTS                                         | return from DrvrInstall
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
    NOT.W	D0                                    | D0 = ~refNum (convert to unit number)
    BMI.B	DRVRINST_BAD_REFNUM                   | negative: invalid refNum
    CMP.W	(UnitTableEntryCount).W,D0            | unit # >= table size?
    BGE.B	DRVRINST_BAD_REFNUM                   | out of range: invalid
    ASL.W	#0x2,D0                               | D0 *= 4 (longword index)
    MOVEA.L	(UTableBase).W,A2                   | A2 = unit table base
    ADDA.W	D0,A2                                | A2 = pointer to unit table slot
    MOVEA.L	(A2),A0                             | A0 = DCE handle from slot
    MOVE.L	A0,D0                                | D0 = DCE handle
    AND.L	(Lo3Bytes).W,D0                       | mask to 24-bit (Z set if nil)
    RTS                                         | return (N=0, Z reflects slot state)
DRVRINST_BAD_REFNUM:
    MOVEQ.L	#-0x15,D0                           | unitEmptyErr (-21): invalid refNum
    RTS                                         | return with N set (BMI)
| DRVRREMOVE - _DrvrRemove trap: remove a driver from unit table
|
| Entry: D0 = refNum
| Releases driver resource if RAM-based, disposes DCE handle,
| clears unit table slot. Returns error if driver is still open.
DRVRREMOVE:
    MOVEM.L	D3-D5/A2-A4,-(A7)                   | save work registers
    BSR.B	LOOKUP_UNIT_SLOT                      | find unit table slot
    BMI.B	DRVRINSTALL_RTS                       | invalid refNum: return error
    BEQ.B	DRVRINSTALL_OK                        | slot empty: return noErr
    MOVEA.L	A2,A3                               | A3 = save unit table slot pointer
    MOVEA.L	D0,A2                               | A2 = DCE handle (24-bit)
    MOVEA.L	(A2),A1                             | A1 = DCE record (deref)
    BTST	#0x5,0x5(A1)                           | dCtlFlags bit 5: driver open?
    BNE.B	DRVRREMOVE_STILL_OPEN                 | yes: can't remove while open
    BTST	#0x6,0x5(A1)                           | dCtlFlags bit 6: RAM-based?
    BEQ.B	DRVRREMOVE_DISPOSE                    | ROM: skip resource release
    MOVE.L	(A1),-(A7)                           | push dCtlDriver (resource handle)
    _ReleaseResource                            | release DRVR resource
DRVRREMOVE_DISPOSE:
    MOVEA.L	A2,A0                               | A0 = DCE handle
    .short	0xA423                               | _DisposeHandle (modified trap)
    CLR.L	(A3)                                  | clear unit table slot (uninstall)
    BRA.B	DRVRINSTALL_OK                        | return noErr
DRVRREMOVE_STILL_OPEN:
    MOVEQ.L	#-0x19,D0                           | dRemovErr (-25): driver still open
    BRA.B	DRVRINSTALL_RTS                       | return error
| ADDDRIVE - _AddDrive trap: add a drive to the drive queue
|
| Entry: A0 = drive queue element, D0 = driver refNum
| Stores refNum at element+6, enqueues in DrvQHdr.
ADDDRIVE:
    MOVE.L	D0,0x6(A0)                           | store driver refNum in queue element
    LEA.L	(DrvQHdr_Flags).W,A1                  | A1 = drive queue header
    JSR	ENQUEUE(PC)                             | enqueue drive element
    MOVEQ.L	#0x0,D0                             | D0 = noErr
    RTS                                         | return from AddDrive
