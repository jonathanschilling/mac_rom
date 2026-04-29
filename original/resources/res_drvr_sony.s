| ========================================================================
| DRVR 4 -- .Sony 3.5" floppy disk driver
| ========================================================================
| resource : 'DRVR' 4 '.Sony'
|
| Sony 3.5" floppy disk driver for 400K/800K GCR disks.
| Written by Larry Kenyon, Apple Computer, 1984-1986.
|
| Handles internal and external floppy drives via the IWM (Integrated
| Woz Machine) chip at base address $DFE1FF. Drive control lines
| CA0/CA1/CA2/SEL select among 16 sense/control functions. IWM
| registers are selected by Q6/Q7 lines:
| Q6=0 Q7=0: data read Q6=1 Q7=0: read status/sense
| Q6=0 Q7=1: handshake Q6=1 Q7=1: mode/data write
|
| GCR 6-and-2 encoding stores 6 data bits per disk byte (high bit
| always set). Five speed zones accommodate variable sectors/track:
| tracks 0-15: 12 sectors tracks 16-31: 11 sectors
| tracks 32-47: 10 sectors tracks 48-63: 9 sectors
| tracks 64-79: 8 sectors
|
| Also includes HD20 (DCD -- Direct Connect Device) hard disk support
| via the floppy port using a serial protocol.
|
| Classic note: the 64K ROM has no resource fork, so this driver is
| stored inline. The layout still mirrors the standard DRVR header
| so the Device Manager can dispatch through it.
|
| DRVR header -- Device Manager driver resource header
DRVR_Sony:                                      | start of .Sony DRVR header
        .short  0x4F00                          | drvrFlags: dNeedLock+dNeedTime+dNeedGoodBye+rdwrCS
        .short  0x0000                          | drvrDelay: no periodic action
        .short  0x0000                          | drvrEMask: no event mask
        .short  0x0000                          | drvrMenu: no menu
        .short  0x0050                          | drvrOpen: offset to E_Sony_Open (= $16E0)
        .short  0x018C                          | drvrPrime: offset to E_Sony_Prime (= $181C)
        .short  0x00DA                          | drvrCtl: offset to E_Sony_Control(= $176A)
        .short  0x0144                          | drvrStatus: offset to E_Sony_Status (= $17D4)
        .short  0x00B4                          | drvrClose: offset to E_Sony_Close (= $1744)
        .byte   0x05                            | drvrName length = 5
        .ascii  ".Sony"                         | drvrName: ".Sony"

| InitDskTbl -- 12 word offsets from SETSPEED to disk-routine entry points:
| FigTrkSpd, DiskPrime, RdAddr, RdData, WrData, Seek,
| SetUpPoll, Recal, Control, WakeUp, ReSeek, MakeSpdTbl
| Each offset is added to the SETSPEED base ($16A8) to compute the
| absolute routine address.
SETSPEED:
        .byte   0x08,0x70,0x01,0x7A             | FigTrkSpd=$1F18, DiskPrime=$1822
        .byte   0x0A,0x0C,0x0A,0xC8             | RdAddr=$20B4, RdData=$2170
        .byte   0x0D,0x20,0x05,0xEC             | WrData=$23C8, Seek=$1C94
        .byte   0x09,0xD4,0x06,0xDC             | SetUpPoll=$207C, Recal=$1D84
        .byte   0x00,0xC8,0x06,0x5A             | Control=$1770, WakeUp=$1D02
        .byte   0x02,0xB4,0x07,0xDA             | ReSeek=$195C, MakeSpdTbl=$1E82

| InitParams -- tuneable drive constants (32 bytes), copied into SonyVars at boot:
| ReadErrInit, RecalInit, WrgSectInit, BadSpdInit (8 bytes -- retry counters)
| Command, HeadSettle (4 bytes)
| SpdChgTime=1500, PwrOnTime=4000, PwrOffTime=5 (6 bytes -- power timing)
| SeekTime=120, SectTime=100, DskVBLTime=30 (6 bytes -- seek/sector timing)
| EjectTime=7500, CkDelta=14400 (8 bytes -- eject timing)
| EjectWait, pad (2 bytes)
INITPARAMS:
        .byte   0x08,0x00,0x02,0x00             | ReadErr=8, RecalInit=2
        .byte   0x40,0x00,0x08,0x00             | WrgSect=64, BadSpd=8
        .byte   0x00,0x00,0x01,0x2C             | Command=0, HeadSettle=300
        .byte   0x05,0xDC,0x0F,0xA0             | SpdChgTime=1500, PwrOnTime=4000
        .byte   0x00,0x05,0x00,0x78             | PwrOffTime=5, SeekTime=120
        .byte   0x00,0x64,0x00,0x1E             | SectTime=100, DskVBLTime=30
        .byte   0x1D,0x4C,0x00,0x00             | EjectTime=7500, CkDelta hi=0
        .byte   0x38,0x40,0xFC,0x00             | CkDelta lo=14400, EjectWait=-4, pad
| ----------------------------------------------------------
| E_Sony_Open -- .Sony driver open routine
| Allocates SonyVars (250 bytes), initializes the disk-routine jump
| table and tuneable drive constants, then installs internal/external
| drive queue entries and the disk-poll VBL task. E_Sony_Close (just
| RTS) shares the trailing RTS with E_Sony_Open's exit at $1744.
| Entry: A1 = DCE pointer
E_Sony_Open:
        MOVEQ.L #0x7D,D0                        | DiskVarLth: size of SonyVars
        ADD.L   D0,D0                           | D0 = 250 = sizeof(SonyVars) (64K version)
        _NewPtrSysClear                         | allocate cleared block in system heap
        MOVE.L  A0,(SonyVars).w                 | save SonyVars ptr in low memory
        MOVE.L  A0,A2                           | A2 = SonyVars (working ptr)
        MOVE.L  A1,(A0)                         | DiskUnitPtr: save DCE ptr at SonyVars[0]
        MOVE    dCtlRefNum(A1),D2               | D2 = dCtlRefNum (driver refNum, for AddDrive)
        LEA.L   (DrvQHdr_Flags).w,A1            | A1 = drive queue header
        JSR     InitQueue(PC)                   | initialize empty drive queue
        MOVEQ.L #0x4A,D0                        | D0 = $4A (offset to internal-drive DQE)
        LEA.L   6(A2,D0.W),A0                   | A0 = &SonyVars[$50] = internal-drive DQE
        MOVEQ.L #0x1,D0                         | D0 = 1 (drvNum for internal drive)
        BSR.B   SONY_ADD_DRIVE                  | enqueue internal drive (drvNum=1)
        ADDA.W  #0x42,A0                        | A0 += $42 = address of external-drive DQE
        MOVEQ.L #0x2,D0                         | D0 = 2 (drvNum for external drive)
        BSR.B   SONY_ADD_DRIVE                  | enqueue external drive (drvNum=2)
        LEA     SETSPEED(PC),A0                 | A0 = base of InitDskTbl offset table
        LEA.L   (DiskVars_JFigTrkSpd).w,A1      | A1 = first jump-table slot in low mem
        MOVEQ.L #0xB,D1                         | D1 = 11 (DBF count: 12 entries)
        JSR     JmpTblInit(PC)                  | convert offsets to absolute jump addresses
        ST      24(A2)                          | OneToOne(A2) = -1 (legacy 1:1 sector flag)
        LEA.L   0x2A(A2),A1                     | A1 = &SonyVars[$2A] = ReadErrInit slot
        LEA     INITPARAMS(PC),A0               | A0 = source: tuneable drive constants
        MOVEQ.L #0x20,D0                        | D0 = 32 bytes to copy
        _BlockMove                              | copy InitParams into SonyVars[$2A..$49]
        LEA     4(A2),A0                        | A0 = &SonyVars[4] = VBL task QElem
        MOVE    #vType,qType(A0)                | qType = vType (1) for VBL task element
        LEA     Sony_CheckForNewDisks(PC),A1    | A1 = address of disk-poll VBL task
        MOVE.L  A1,vblAddr(A0)                  | vblAddr: install task entry point
        MOVE    #0x1E,vblCount(A0)              | vblCount = 30 ticks (~0.5s)
        _VInstall                               | install VBL task
        RTS                                     | return (also serves as E_Sony_Close)
| ----------------------------------------------------------
| SONY_ADD_DRIVE -- enqueue a drive entry on the drive queue
| In: A0 = DQE ptr, D0.low = drvNum, D2 = driver refNum
| Builds drvNum:refNum word (D0 swapped + D2 in low half), stores at DQE+6,
| then JMPs to Enqueue. Tail-call returns to E_Sony_Open's caller.
SONY_ADD_DRIVE:
        SWAP    D0                              | move drvNum into high half of D0
        MOVE    D2,D0                           | D0.low = D2 = refNum (D0 = drvNum:refNum)
        MOVE.L  D0,dQDrive(A0)                  | DQE+6: store drvNum:refNum (4 bytes)
        LEA.L   (DrvQHdr_Flags).w,A1            | A1 = drive queue header
        JMP     Enqueue(PC)                     | tail-call enqueue
| ----------------------------------------------------------
| Sony_ReturnResult -- common exit path for .Sony driver routines
| Stores D0 in DskErr lowmem, then continues into SONY_RETURNRESULT_CONT
| (in res_drvr_sony.s) which clears Active and dispatches via JIODone.
Sony_ReturnResult:
        MOVE    D0,(DskErr).w                   | store driver result code in DskErr lowmem
| ----------------------------------------------------------
| SONY_RETURNRESULT_CONT -- tail of Sony_ReturnResult
| Called from device_mgr.s Sony_ReturnResult ($1756), which stores D0
| (driver result code) in DskErr lowmem and falls through here. Clears
| the Active flag, reloads the DCE ptr, and dispatches through JIODone
| to complete the I/O request.
SONY_RETURNRESULT_CONT:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars pointer
        CLR.B   0x19(A1)                        | Active = false (re-enable VBL task)
        MOVE.L  (A1),A1                         | A1 = DCE pointer (DiskUnitPtr)
        MOVE.L  (JIODone).w,-(SP)               | push JIODone vector
        RTS                                     | dispatch to IODone

| ----------------------------------------------------------
| E_Sony_Control -- .Sony driver Control trap entry (drvrCtl = $00DA)
| Pushes JControl vector (pointing to Sony_Control below) and RTSes to it.
E_Sony_Control:
        MOVE.L  (DiskVars_JControl).w,-(SP)     | push Sony_Control vector
        RTS                                     | dispatch via jtControl

| ----------------------------------------------------------
| Sony_Control -- .Sony driver control-call dispatcher
| Entry: A0 = paramBlock (CntrlParam), A1 = DCE, A2 = SonyVars.
| Dispatches by csCode (at ioMisc+2, offset 26 in paramBlock).
| csCode 1 = KillIO (legacy: stops motor, masks SIR, returns via RTE)
| csCode 7 = Eject
| csCode 8 = Set tag buffer pointer
| csCode 9+ = dispatch via CODES table
Sony_Control:
        MOVE    csCode(A0),D0                   | D0 = csCode
        SUBQ.W  #0x1,D0                         | csCode == 1 (KillIO)?
        BNE.B   SONY_CONTROL_NO                 | no: try other codes
        MOVE    SR,-(SP)                        | save SR for RTE
        ORI     #0x100,SR                       | raise IPL=1 (mask level-1 interrupts)
        BSR.W   Sony_MotorOff                   | stop drive motor
        MOVE.B  #0x20,vIER(A2)                  | VIA IER: mask sound-IRQ bit
        CLR.B   25(A1)                          | clear per-drive Active flag
        RTE                                     | return from interrupt (restores SR)
SONY_CONTROL_NO:
        SUBQ.W  #0x6,D0                         | csCode == 7 (Eject)? (D0 now = csCode-7)
        BEQ.B   Sony_EjectOrSwitchDisk          | yes: go eject disk
        SUBQ.W  #0x1,D0                         | csCode == 8 (set tag buf ptr)? (= csCode-8)
        BNE.B   Sony_ReturnErrUnimplementedControl | no: return controlErr
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  28(A0),0xF4(A1)                 | TagBufPtr(A1) = CSParam (ptr or nil)
        BRA.B   SONY_CONTROL_DONE               | return noErr
Sony_ReturnErrUnimplementedControl:             | unimplemented csCode
        MOVEQ.L #-0x11,D0                       | controlErr (-17)
        BRA.B   Sony_ReturnResult               | store in DskErr, dispatch IODone
| ----------------------------------------------------------
| Sony_EjectOrSwitchDisk -- csCode 7 (eject disk) handler
| Selects the target drive, stops motor, seeks head, ejects disk.
Sony_EjectOrSwitchDisk:
        BSR.B   Sony_ChooseDriveFromPB          | invalidate track cache for this drive
        BNE.B   Sony_ReturnResult               | bad drive -> return nsDrvErr
        BSR.W   Sony_MotorOn1                   | spin up drive motor before eject
        MOVEQ.L #0xD,D0                         | D0 = $D = EJECT register address
        BSR.W   Sony_AdrDisk                    | select EJECT phase line
        TST.B   0xE00(A0)                       | LSTRB on: latch eject strobe
        MOVE    0x42(A1),D0                     | D0 = EjectTime delay for solenoid travel
        BSR.W   E_Sony_WakeUp                   | wait via Time Manager for solenoid
        MOVE.B  0x48(A1),3(A1,D1.W)             | DiskInPlace = EjectWait sentinel ($FC..$FF)
        TST.B   0xC00(A0)                       | LSTRB off: release eject strobe
        MOVEQ.L #0x0,D0                         | D0 = 0: immediate motor power-off
        BSR.W   Sony_MotorOff                   | stop drive motor (no delay)
SONY_CONTROL_DONE:                              | common noErr exit
        MOVEQ.L #0x0,D0                         | D0 = 0 (noErr)
        BRA.B   Sony_ReturnResult               | store+dispatch IODone

| ----------------------------------------------------------
| E_Sony_Status -- .Sony driver Status trap entry (drvrStatus = $0144)
| Entry: A0 = paramBlock (CntrlParam), A1 = DCE.
| Only csCode 8 (drvStsCC = return drive status) is supported -- returns
| 22 bytes of per-drive status words copied into CSParam[0..10].
| All other csCodes return statusErr (-18).
E_Sony_Status:
        MOVEQ.L #-0x12,D0                       | D0 = -18 = statusErr (default)
        CMPI    #0x8,26(A0)                     | csCode == 8 (drvStsCC)?
        BNE.W   Sony_ReturnResult               | no: return statusErr
        BSR.B   Sony_ChooseDriveFromPB          | A1 = SonyVars, D1 = drive offset
        BNE.W   Sony_ReturnResult               | bad drive: return nsDrvErr
        LEA.L   28(A0),A0                       | A0 = CSParam (destination)
        MOVEQ.L #0xB,D0                         | 11 words = 22 bytes of drive status
        ADDA.W  D1,A1                           | A1 += drive offset (per-drive vars)
E_SONY_STATUS_LOOP:
        MOVE    (A1)+,(A0)+                     | copy one word of status
        SUBQ.W  #0x1,D0                         | decrement word counter
        BGT.B   E_SONY_STATUS_LOOP              | loop for all 11 words
        BRA.W   Sony_ReturnResult               | return noErr

| ----------------------------------------------------------
| Sony_ChooseDriveFromPB -- select drive by paramBlock ioVRefNum
| Reads ioVRefNum (offset 22) and validates it's in [1..2]. Stores the
| drive number in SonyVars' selected-drive slot, sets Active=-1, and
| computes the per-drive variable offset into D1 via Sony_SetupSonyVars.
| Returns: Z=1, D0=0 on valid drive; Z=0, D0=-56 (nsDrvErr) on invalid.
Sony_ChooseDriveFromPB:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        ST      25(A1)                          | Active = -1 (suspend VBL task)
        MOVE    ioVRefNum(A0),D0                | D0 = ioVRefNum (drive number)
        BEQ.B   SONY_CHOOSEDRIVEFROMPB_ERR      | 0: invalid
        CMPI    #0x2,D0                         | > 2?
        BGT.B   SONY_CHOOSEDRIVEFROMPB_ERR      | yes: only drives 1-2 exist
        MOVE    D0,TwoSideFmt(A1)               | store drive# in "selected drive" slot
        BSR.W   Sony_SetupSonyVars              | D1 = per-drive offset into SonyVars
        MOVEQ.L #0x0,D0                         | D0 = 0 (success, Z=1)
        RTS                                     | return success: D0=0, Z=1
SONY_CHOOSEDRIVEFROMPB_ERR:
        MOVEQ.L #-0x38,D0                       | D0 = -56 (nsDrvErr: no such drive)
        RTS                                     | Z=0 (error)

| ----------------------------------------------------------
| E_Sony_Prime -- .Sony driver Prime trap entry (drvrPrime = $018C)
| Pushes JDiskPrime vector (= Sony_DiskPrime below) and RTSes to it.
E_Sony_Prime:
        MOVE.L  (DiskVars_JDiskPrime).w,-(SP)   | push Sony_DiskPrime vector
        RTS                                     | dispatch via jtDiskPrime

| ----------------------------------------------------------
| Sony_DiskPrime -- read or write one sector (drvrPrime = read/write)
| Entry: A0 = paramBlock (IOParam), A1 = DCE.
| Selects drive from ioVRefNum, checks disk present, initializes disk if
| first access (seek track 0, build speed table, read WRTPRT), checks
| write-protect for write requests, then dispatches to sector read/write.
Sony_DiskPrime:
        ORI     #0x100,SR                       | raise IPL=1 (mask level-1 interrupts)
        MOVE    ioTrap(A0),D3                   | D3 = ioTrap (for Read/Write discrimination)
        BTST    #0x6,(ioPosMode+1)(A0)          | ioPosMode bit 6: fsVerify?
        SNE     (DskVerify).w                   | DskVerify = $FF if verify requested
        BSR.B   Sony_ChooseDriveFromPB          | A1 = SonyVars, D1 = drive offset
        BNE.B   SONY_DISKPRIME_ERR_4            | bad drive: exit with nsDrvErr
        MOVE    D3,0x32(A1)                     | save ioTrap in SonyVars (for Recal)
        BSR.W   Sony_JumpDiskSel                | set PWM speed for this track's zone
        BSR.W   SONY_CHECKFORNEWDISKS_CONT_4_OK | ensure motor running (with delay)
        BMI.B   SONY_DISKPRIME_ERR_4            | motor error: exit
        MOVEQ.L #0x2,D0                         | D0 = 2 (DiskIn sense register)
        BSR.W   Sony_ReadDriveRegAdr            | poll DiskIn: disk-in-place?
        BPL.B   SONY_DISKPRIME_CONT             | disk present: proceed to init/IO
        CLR.B   3(A1,D1.W)                      | DiskInPlace = 0 (no disk)
        MOVEQ.L #-0x41,D0                       | D0 = -65 = offLinErr (drive off line)
        BRA.B   SONY_DISKPRIME_ERR_4            | exit with error

| ----------------------------------------------------------
| SONY_DISKPRIME_CONT -- disk is present, initialize if first access
SONY_DISKPRIME_CONT:
        CMPI.B  #0x2,3(A1,D1.W)                 | DiskInPlace == 2: already initialized?
        BEQ.B   SONY_DISKPRIME_OK               | yes -> proceed to I/O
        BSR.W   Sony_MotorOn1                   | spin up motor (no delay)
        BSR.W   SONY_SEEK_CONT_2_CONT_9         | recalibrate head to track 0
        BMI.B   SONY_DISKPRIME_ERR_2            | recal failed -> error exit
        BSR.W   E_Sony_MakeSpdTbl               | build speed correction table
        BNE.B   SONY_DISKPRIME_ERR_2            | speed cal failed -> error exit
        MOVEQ.L #0x6,D0                         | D0 = 6 (WRTPRT sense register)
        BSR.W   Sony_ReadDriveRegAdr            | read WRTPRT (0 = locked)
        SPL.B   2(A1,D1.W)                      | WrProt = $FF if write-enabled (N=0)
        MOVE.B  #0x2,3(A1,D1.W)                 | DiskInPlace = 2 (disk initialized)
        CLR.B   0x12(A1,D1.W)                   | clear byte at offset $12 (per-drive slot)
SONY_DISKPRIME_OK:
        BSR.W   SONY_RESEEK_OK_3                | test ioTrap: read or write?
        BEQ.B   SONY_DISKPRIME_SKIP             | read -> skip write-protect check
        MOVE    (BufTgFBkNum).w,0x26(A1)        | save tag file block number
        TST.B   2(A1,D1.W)                      | WrProt: disk write-protected?
        BPL.B   SONY_DISKPRIME_SKIP             | not protected -> proceed
        MOVEQ.L #-0x2C,D0                       | wPrErr (-44): disk is write-protected
SONY_DISKPRIME_ERR:
        MOVE    0x3A(A1),D2                     | D2 = motor power-off delay
        BRA.B   SONY_DISKPRIME_ERR_3            | turn off motor and return error
SONY_DISKPRIME_ERR_2:
        MOVEQ.L #0x0,D2                         | D2 = 0: immediate motor power-off delay
SONY_DISKPRIME_ERR_3:
        MOVE    D0,-(SP)                        | save error code
        MOVE    D2,D0                           | D0 = power-off delay for MotorOff
        BSR.W   Sony_MotorOff                   | schedule motor power-off
        MOVE    (SP)+,D0                        | restore error code
SONY_DISKPRIME_ERR_4:
        ANDI    #-0x701,SR                      | restore IPL to 0
        BRA.W   Sony_ReturnResult               | return result in D0
SONY_DISKPRIME_SKIP:
        MOVE    0(A1,D1.W),D6                   | D6 = DriveType(A1,D1.W)
        BSR.W   Sony_SetSpeed                   | validate sector number against drive geometry
        BSR.W   Sony_MotorOn2                   | prepare drive for I/O (seek head)
        ST.B    0x13(A1,D1.W)                   | set byte at offset $13 = -1 (side marker)
UPDATE:
        MOVE.L  (A1),A2                         | A2 = DCE pointer
        MOVE.L  8(A2),A0                        | A0 = IOParam block (dCtlQHdr+8)
        MOVE.L  16(A2),D0                       | D0 = dCtlPosition byte offset
        LSR.L   #0x8,D0                         | D0 >>= 8 (start of /512 shift)
        LSR.L   #0x1,D0                         | D0 /= 2 (@ $18CC)
        MOVEQ.L #0x0,D2                         | D2 = 0: running sector count
        MOVEQ.L #0x0,D3                         | D3 = 0: track/side descriptor
        MOVEQ.L #0x4,D7                         | D7 = 4: outer-loop zone counter (5 zones)
        MOVEQ.L #0xD,D4                         | D4 = 13: sectors-per-track (zone 0 + 1)
UPDATE_LOOP:
        MOVEQ.L #0xF,D5                         | D4 = 0: accumulated result
        SUBQ.W  #0x1,D4                         | D4-- = sectors/track for this zone
UPDATE_LOOP_2:
        MOVEQ.L #0x0,D6                         | D6 = 0: side flag (0 = side 0)
UPDATE_DONE:
        ADD     D4,D2                           | D2 += sectors-per-track
        CMP     D0,D2                           | reached target sector?
        BGT.B   SONY_DISKPRIME_OK_2             | yes -> compute side/track
        TST.B   D6                              | already on side 1?
        BNE.B   UPDATE_CONT                     | yes -> next track
        MOVE.B  0x12(A1,D1.W),D6                | D6 = FmtByte for this side
        BNE.B   UPDATE_DONE                     | matching format found -> done
UPDATE_CONT:
        ADDQ.W  #0x1,D3                         | D3++ = track number
        DBRA    D5,UPDATE_LOOP_2                | next track in this zone (16 tracks/zone)
        DBRA    D7,UPDATE_LOOP                  | next zone (5 zones, decrementing sectors)
UPDATE_CONT_2:
        MOVEQ.L #-0x32,D0                       | CMnotempty: not supported on TFS
        BRA.B   SONY_DISKPRIME_ERR              | ->
SONY_DISKPRIME_OK_2:
        TST.B   D6                              | accessing side 1?
        BEQ.B   SONY_DISKPRIME_OK_2_NO          | no -> side 0, proceed
        BSET    #0xB,D3                         | set side bit in track descriptor
        TST.B   5(A1,D1.W)                      | Sides: drive double-sided?
        BNE.B   SONY_DISKPRIME_OK_2_NO          | yes -> OK
        MOVEQ.L #-0x4E,D0                       | sideErr (-78): single-sided drive
        BRA.B   SONY_DISKPRIME_ERR              | return error
SONY_DISKPRIME_OK_2_NO:
        MOVE    D3,DriveType(A1)                | save track/side descriptor in DriveType
        SUB     D2,D0                           | D0 = sector offset within this track
        ADD     D0,D4                           | D4 += offset (final sector # on track)
        NEG     D0                              | D0 = -offset (sectors remaining on track)
        MOVE    D4,0x20(A1)                     | save first-sector # for this transfer
        MOVE.L  ioReqCount(A0),D5               | D5 = total bytes requested
        MOVE.L  ioActCount(A0),D2               | D2 = bytes transferred so far
        SUB.L   D2,D5                           | D5 = remaining bytes to transfer
        LSR.L   #0x8,D5                         | D5 >>= 8 (start of /512 shift)
        LSR.L   #0x1,D5                         | D5 /= 2 = remaining sectors needed
        BEQ.B   UPDATE_CONT_2                   | zero sectors -> CMnotempty error
        CMP     D5,D0                           | more sectors on track than needed?
        BLE.B   SONY_DISKPRIME_OK_2_NO_CONT     | D0 <= D5: use all remaining
        MOVE    D5,D0                           | D0 = min(available, needed)
SONY_DISKPRIME_OK_2_NO_CONT:
        MOVEQ.L #0x0,D3                         | D3 = 0: clear sector bitmask
SONY_DISKPRIME_OK_2_NO_NO:
        BSET    D4,D3                           | set bit for this sector in bitmask
        ADDQ.W  #0x1,D4                         | next sector number
        SUBQ.W  #0x1,D0                         | decrement sector count
        BNE.B   SONY_DISKPRIME_OK_2_NO_NO       | loop until all sector bits set
        MOVE.L  D3,0x22(A1)                     | save bit-cell window timer
        MOVE.L  ioBuffer(A0),D3                 | D3 = user buffer pointer
        ADD.L   D2,D3                           | D3 += bytes already done (next byte to write)
        MOVE.L  D3,0x1C(A1)                     | save accumulated bit-cell count
        LSR.L   #0x8,D2                         | D2 >>= 8: sectors in upper byte
        LSR.L   #0x1,D2                         | D2 /= 2 = sectors already done
        MOVE    D2,0x28(A1)                     | save FBlksDone (sectors completed)
        MOVE.B  0x2C(A1),0x2D(A1)               | RecalCnt = RecalInit (reset retry)
SONY_DISKPRIME_OK_2_NO_RETRY:
        MOVE.L  (DiskVars_JReSeek).w,-(SP)      | push JReSeek vector
        RTS                                     | dispatch to Sony_ReSeek
| ----------------------------------------------------------
| Sony_ReSeek -- table-driven entry: init speed-retry counter
| Retries with speed correction until BadSpdCnt exhausted.
Sony_ReSeek:
        MOVE.B  InvalidResp(A1),0x31(A1)        | BadSpdCnt: init speed retry counter
SONY_RESEEK_RETRY:
        MOVE    DriveType(A1),D6                | D6 = target track/side descriptor
        BSR.W   E_Sony_Seek                     | seek head to target track
        BMI.B   SONY_RESEEK_ERR                 | seek error -> exit via error chain
        MOVE.B  0x2A(A1),0x2B(A1)               | ReadErrCnt = ReadErrInit
        LSR     #0x4,D6                         | extract zone from track number
        LSL     #0x3,D6                         | *8: index into per-zone speed table
        LEA.L     0x1A(A1,D1.W),A2              | A2 -> per-drive speed adjustment table
        LEA.L     4(A2,D6.W),A2                 | A2 -> timestamp for this zone
        MOVE.L  (Ticks).w,D2                    | D2 = current tick count
        MOVE.L  (A2),D0                         | last speed measurement timestamp
        BEQ.B   SONY_RESEEK_CONT                | never measured -> measure now
        SUB.L   D2,D0                           | elapsed = current - last
        NEG.L   D0                              | make positive
        CMP.L   0x44(A1),D0                     | SectTime threshold exceeded?
        BLT.B   SONY_RESEEK_SKIP                | below threshold -> skip speed remeasure
SONY_RESEEK_CONT:
        MOVE.L  D2,(A2)                         | update timestamp
        LEA     SONY_RESEEK_CONT_2(PC),A3       | A3 = speed check callback
        BRA.W   SONY_MAKESPDTBL_CONT_6          | measure disk speed via FigTrkSpd

| SONY_RESEEK_CONT_2 -- callback after speed measurement
SONY_RESEEK_CONT_2:
        BMI.B   SONY_RESEEK_ERR                 | measurement failed -> error
        MOVE    -(A2),D0                        | D0 = current speed adjustment value
        LEA     DT_Sony_SpeedCheckTbl(PC),A0    | A0 = acceptable RPM range table
        LSR     #0x1,D6                         | zone index for word table
        ADDA.W  D6,A0                           | index into speed table
        CMP     (A0)+,D4                        | measured speed > upper limit?
        BGT.B   SONY_RESEEK_OK                  | yes -> speed too fast, adjust
        NEG     D0                              | try negative correction
        CMP     (A0),D4                         | measured speed > lower limit?
        BGT.B   SONY_RESEEK_SKIP                | within limits -> skip speed adjust
SONY_RESEEK_OK:
        SUB     D0,-(A2)                        | -(A2) -= D0
        CLR.L   4(A2)                           | clear last-measure timestamp (force remeasure)
        ADDQ.W  #0x1,0x18(A1,D1.W)              | SpdAdjCnt++: track adjustment count
        SUBQ.B  #0x1,0x31(A1)                   | decrement BadSpdCnt
        BPL.B   SONY_RESEEK_RETRY               | retries left -> retry seek/IO
        MOVEQ.L #-0x4F,D0                       | spdAdjErr (-79): can't adjust speed
SONY_RESEEK_ERR:
        BRA.W   SONY_RESEEK_ERR_6               | jump to recal/retry error path

| ----------------------------------------------------------
| SONY_RESEEK_SKIP -- sector address-field search and per-sector I/O
| Reads address fields one by one until a desired sector is found,
| then dispatches to ReadData or WriteData. WrgSectCnt limits retries
| before giving up and recalibrating.
| ----------------------------------------------------------
SONY_RESEEK_SKIP:
        MOVE.B  0x2E(A1),0x2F(A1)               | WrgSectCnt = WrgSectInit (reset wrong-sector retry)
SONY_RESEEK_RETRY_2:
        MOVE.L  D1,D6                           | D6 = drive offset (preserve across SetUpPoll)
        BSR.W   SONY_SETUPPOLL_CONT             | set up address-field polling, read header
        BPL.B   DT_SONY_NIBLTBL_NEXT_3_CONT_2   | header found OK -> validate
DT_SONY_NIBLTBL_NEXT_3_CONT:                    | drive-select failed
        PEA.L   SONY_SEEK_ERR_LOG(PC)           | push retry-log entry on stack
        BRA.B   DT_SONY_NIBLTBL_NEXT_3_CONT_3   | chain to common error-return
DT_SONY_NIBLTBL_NEXT_3_CONT_2:
        CMP     DriveType(A1),D1                | header track == target track?
        BEQ.B   DT_SONY_NIBLTBL_NEXT_3_CONT_4   | yes -> check sector
        MOVEQ.L #-0x50,D0                       | D0 = -80 = seekErr (wrong track)
        PEA.L   SONY_RESEEK_ERR_6(PC)           | push recal/retry exit
DT_SONY_NIBLTBL_NEXT_3_CONT_3:
        BRA.W   SONY_RESEEK_CONT_8              | dispatch via PollProc/PollStack
DT_SONY_NIBLTBL_NEXT_3_CONT_4:
        MOVE.L  0x22(A1),D0                     | D0 = SectMapSave (desired-sector bitmask)
        BTST    D2,D0                           | test bit D2 of D0
        BNE.B   DT_SONY_NIBLTBL_NEXT_3_CONT_5   | this sector wanted -> process
        ADDQ.L  #0x1,(RndSeed).w                | stir RndSeed (ignored sector pseudoentropy)
        MOVEQ.L #-0x51,D0                       | D0 = -81 = sectNFErr (sector not found)
        PEA.L   SONY_RESEEK_ERR_6_CONT(PC)      | push WrgSectCnt retry exit
        BRA.B   DT_SONY_NIBLTBL_NEXT_3_CONT_3   | dispatch via PollProc
DT_SONY_NIBLTBL_NEXT_3_CONT_5:
        MOVE    D2,(TagData).w                  | save sector # in TagData lowmem
        CMPI.B  #0x1F,D3                        | format byte > $1F means double-sided
        SGT.B   0x12(A1,D6.W)                   | side-selected byte = $FF if GT (double-sided)
        SUB.W   0x20(A1),D2                     | D2 -= TrkCnt(A1) (sectors-done base)
        MOVE    D2,D1                           | D1 = offset into sector buffer
        ASL.L   #0x8,D1                         | D1 <<= 8: sector# * 256
        ADD.L   D1,D1                           | D1 *= 2: sector# * 512 (bytes per sector)
        ADD.L   0x1C(A1),D1                     | D1 += buffer base (= user byte ptr)
        MOVE.L  D1,A0                           | A0 = user data buffer for this sector
        MOVE    0x28(A1),D1                     | D1 = sectors already completed
        ADD     D2,D1                           | D1 = absolute sector index
        MOVE    D1,D0                           | D0 = sector index for tag calc
        ADD     D1,D1                           | D1 = D1 + D1
        ADD     D0,D1                           | D1 = sector index * 2 + sector
        ASL     #0x2,D1                         | D1 = (index * 2 + sector) * 4
        MOVE    D1,0xF8(A1)                     | TagOffset: save for tag buffer copy
        BSR.W   SONY_RESEEK_OK_3                | test ioTrap: read(0) or write(1)?
        BEQ.B   SONY_IO_TAG_DONE_CONT_2         | read -> dispatch ReadData
        MOVE.L  0xF4(A1),D3                     | TagBufPtr: external tag buffer?
        BEQ.B   SONY_IO_TAG_DONE                | no external buffer -> skip copy
SONY_IO_TAG_COPY:
        MOVE.L  D3,A1                           | A1 = external tag buffer
        ADDA.W  D1,A1                           | offset to this sector's tags
        LEA.L     (BufTgFNum).w,A2              | A2 = system tag globals
        MOVE.L  (A1)+,(A2)+                     | copy tags from user buffer to globals
        MOVE.L  (A1)+,(A2)+                     | tag bytes 5-8
        MOVE.L  (A1)+,(A2)+                     | tag bytes 9-12
        BRA.B   SONY_IO_TAG_DONE_CONT           | skip default tag setup
SONY_IO_TAG_DONE:
        ADD     0x26(A1),D0                     | D0 += FileTagBase (BufTgFBkNum offset)
        MOVE    D0,(BufTgFBkNum).w              | BufTgFBkNum = computed file block #
        MOVE.L  (Time).w,(BufTgDate).w          | BufTgDate = current Time (timestamp)
SONY_IO_TAG_DONE_CONT:
        BSR.W   SONY_RDDATA_CONT_14_CONT        | dispatch JWrData (write sector + tags)
        BNE.W   DT_SONY_NIBLTBL_NEXT_3_CONT     | write error -> retry via SeekErrLog
        BRA.B   SONY_IO_TAG_DONE_CONT_3         | success -> continue post-IO
SONY_IO_TAG_DONE_CONT_2:
        BSR.W   SONY_RDADDR_CONT_7_LOOP_CONT_3  | dispatch JRdData (read sector + tags)
        BNE.W   DT_SONY_NIBLTBL_NEXT_3_CONT     | read error -> retry via SeekErrLog
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars (reload after read)
        MOVE.L  0xF4(A1),D0                     | D0 = TagBufPtr (caller's tag buffer)
        BEQ.B   SONY_IO_TAG_DONE_CONT_3         | no buffer -> skip tag copy
        MOVE.L  D0,A0                           | A0 = caller's tag buffer base
        ADDA.W  0xF8(A1),A0                     | A0 += TagOffset (this sector's slot)
        LEA.L     (BufTgFNum).w,A2              | A2 = system tag globals (BufTgFNum)
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 1-4 to caller buffer
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 5-8 to caller buffer
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 9-12 to caller buffer
SONY_IO_TAG_DONE_CONT_3:
        PEA.L   SONY_RESEEK_CONT_8_CONT_3(PC)   | push post-IO continuation

| -------------------------------------------------------
| SONY_RESEEK_CONT_8 -- CallPollProc: invoke deferred task (PollProc)
| Saves volatile registers, calls PollProc, restores state.
| If PollProc is nil, switches to PollStack and returns.
SONY_RESEEK_CONT_8:
        MOVE.L  (SP)+,A4                        | A4 = return address
        PEA.L   SONY_RESEEK_CONT_9(PC)          | push resume address after PollProc
        MOVE.L  (PollProc).w,-(SP)              | push PollProc address
        BEQ.B   SONY_RESEEK_EMPTY               | nil -> use PollStack shortcut
        MOVE.L  (SonyVars).w,A1                 | save volatile regs in SonyVars
        MOVEM.L D0/D2-D3/A0/A4,0xD0(A1)         | save D0,D2,D3,A0,A4 at +$D0
        RTS                                     | "call" PollProc
SONY_RESEEK_CONT_9:                             | branch target @ ROM $1A9E -- PollProc resume
        BSR.W   Sony_SetupSonyVars              | reload SonyVars and drive offset
        MOVEM.L 0xD0(A1),D0/D2-D3/A0/A4         | restore saved registers
        JMP     (A4)                            | return to caller of SONY_RESEEK_CONT_8
SONY_RESEEK_EMPTY:
        MOVE.L  (PollStack).w,SP                | switch to reserved poll stack
        BSR.W   Sony_SetupSonyVars              | reload SonyVars
        JMP     (A4)                            | return to caller of SONY_RESEEK_CONT_8
SONY_RESEEK_OK_3:
        CMPI.B  #0x2,0x33(A1)                   | compare ioTrap LSB to 2 (write trap?)
        RTS                                     | return Z=1 if read, Z=0 if write
SONY_RESEEK_CONT_8_CONT_3:
        TST.B   24(A1)                          | OneToOne flag set?
        BNE.B   SONY_RESEEK_CONT_8_NO           | yes -> keep IPL raised
        ANDI    #-0x701,SR                      | SR &= -0x701
SONY_RESEEK_CONT_8_NO:
        BSR.B   SONY_RESEEK_OK_3                | test ioTrap: read or write?
        BEQ.B   SONY_RESEEK_CONT_8_CONT_4       | read -> skip cache update
        TST.B   (CPUFlag).w                     | CPU type 68000 only?
        BNE.B   SONY_RESEEK_CONT_8_CONT_4       | newer CPU -> skip
        BSR.W   SONY_SEEK_CONT_2_CONT_4         | post-write head settle
SONY_RESEEK_CONT_8_CONT_4:
        MOVE.L  (A1),A2                         | A2 = DCE pointer
        MOVE.L  8(A2),A0                        | A0 = IOParam block
        MOVEQ.L #0x2,D0                         | D0 = 2 (high byte of 512)
        ASL.L   #0x8,D0                         | D0 = $200 = 512 (sector size)
        ADD.L   D0,16(A2)                       | 16(A2) += D0
        ADD.L   D0,ioActCount(A0)               | ioActCount += 512 (one sector transferred)
        MOVE.L  0x22(A1),D0                     | D0 = SectMapSave (sector bitmask)
        MOVE    (TagData).w,D2                  | D2 = sector # just transferred
        BCLR    D2,D0                           | clear sector bit (mark satisfied)
        MOVE.L  D0,0x22(A1)                     | save updated sector bitmask
        BNE.W   SONY_RESEEK_SKIP                | more sectors to process: loop
        MOVE.L  ioActCount(A0),D0               | D0 = ioActCount (bytes done)
        CMP.L   ioReqCount(A0),D0               | hit ioReqCount (all bytes transferred)?
        BLT.W   UPDATE                          | no: re-run format-decision loop
        MOVEQ.L #0x0,D0                         | D0 = noErr (success)
SONY_RESEEK_ERR_3:                              | also target from SONY_RESEEK_ERR_7
        BRA.W   SONY_DISKPRIME_ERR              | return via error-exit chain (D0 = result)
| ----------------------------------------------------------
| SONY_SEEK_ERR_LOG -- log a read/write error, retry if count remains
| Bumps error-log counter at offset $14 in per-drive SonyVars, then
| decrements ReadErrCnt (0x2B). If retries remain (N=0), loops back
| to SONY_RESEEK_SKIP; else falls through to SONY_RESEEK_ERR_6 for recal.
SONY_SEEK_ERR_LOG:
        ADDQ.W  #0x1,0x14(A1,D1.W)              | per-drive error counter++
        SUBQ.B  #0x1,0x2B(A1)                   | ReadErrCnt--
        BPL.W   SONY_RESEEK_SKIP                | retries left: loop

| SONY_RESEEK_ERR_6 -- fatal error path: try recal then retry
SONY_RESEEK_ERR_6:
        ANDI    #-0x701,SR                      | restore IPL to 0
        SUBQ.B  #0x1,0x2D(A1)                   | decrement recal retry counter
        BLE.B   SONY_RESEEK_ERR_7               | exhausted -> return error
        BSR.W   SONY_SEEK_CONT_2_CONT_9         | recalibrate to track 0
        BMI.B   SONY_RESEEK_ERR_7               | recal failed -> return error
        BSR.W   E_Sony_MakeSpdTbl               | rebuild speed table
        BPL.W   SONY_DISKPRIME_OK_2_NO_RETRY    | success -> re-seek and retry I/O
SONY_RESEEK_ERR_7:
        BRA.B   SONY_RESEEK_ERR_3               | jump to error-exit (preserves D0)
SONY_RESEEK_ERR_6_CONT:
        SUBQ.B  #0x1,0x2F(A1)                   | decrement WrgSectCnt (wrong-sector retry)
        BMI.B   SONY_RESEEK_ERR_6               | exhausted -> recal/retry path
        BSR.W   SONY_SEEK_CONT_2_CONT_4         | settle head after wrong sector
        BRA.W   SONY_RESEEK_RETRY_2             | retry sector address-field search
Sony_SetupRegs:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address (low memory)
        MOVE.L  (VIA).w,A2                      | A2 = VIA base address (low memory)
Sony_SetupSonyVars:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars base
        CMPI    #0x1,TwoSideFmt(A1)             | selected drive == 1 (internal)?
        BEQ.B   SONY_RESEEK_ERR_6_CONT_2        | yes -> use internal-drive offset
        MOVE    #0x8C,D1                        | D1 = $8C: external-drive offset
        RTS                                     | return D1 = per-drive var offset
SONY_RESEEK_ERR_6_CONT_2:
        MOVEQ.L #0x4A,D1                        | D1 = $4A: internal-drive offset
        RTS                                     | return D1 = per-drive var offset

| disk register to select in D0
| {CA1,CA0,SEL,CA2} <= D0
| Sony_AdrDisk: address a disk register via CA0/CA1/CA2/SEL lines
| D0 = register number (4 bits: CA0, CA1, CA2, SEL)
| The IWM phase lines select one of 16 drive status/control registers.
| CA0/CA1/CA2 are controlled by IWM phase line registers at offsets
| $200/$400/$600/$800/$A00 from IWM base. SEL is VIA Port A bit 5.
Sony_AdrDisk:
        BSR.B   Sony_SetupRegs                  | set up A0=IWM, A2=VIA
        TST.B   0x200(A0)                       | CA0 on
        TST.B   0x600(A0)                       | CA1 on
        TST.B   0x800(A0)                       | CA2 off (default state)
        LSR.B   #0x1,D0                         | test CA2 bit (bit 0 of register #)
        BCC.B   SONY_ADRDISK_CONT_6             | CA2 = 0 -> skip CA2-on
        TST.B   0xA00(A0)                       | CA2 on (assert phase 5)
SONY_ADRDISK_CONT_6:
        BCLR    #0x5,vBufA(A2)                  | SEL off: clear VIA Port A bit 5
        LSR.B   #0x1,D0                         | test SEL bit (bit 1 of register addr)
        BCC.B   SONY_ADRDISK_CONT_7             | SEL = 0 -> skip SEL-on
        BSET    #0x5,vBufA(A2)                  | SEL on: set VIA Port A bit 5
SONY_ADRDISK_CONT_7:
        LSR.B   #0x1,D0                         | test CA0 bit (bit 2 of register addr)
        BCS.B   SONY_ADRDISK_CONT_8             | CA0=1 -> leave CA0 on (already set)
        TST.B   (A0)                            | CA0 off: deassert phase 0
SONY_ADRDISK_CONT_8:
        LSR.B   #0x1,D0                         | test CA1 bit (bit 3 of register #)
        BCS.B   SONY_ADRDISK_CONT_9             | CA1 = 1 -> leave CA1 asserted
        TST.B   0x400(A0)                       | CA1 off (deassert phase 1)
SONY_ADRDISK_CONT_9:
        RTS                                     | drive register now addressed
Sony_ReadDriveRegAdr:
        BSR.B   Sony_AdrDisk                    | address drive register D0

| Sony_ReadDriveReg -- read SIDES, 0 = single, 1 = double.
Sony_ReadDriveReg:
        MOVE    SR,-(SP)                        | save SR (preserve IPL)
        ORI     #0x300,SR                       | raise IPL to 3 (mask SCC ints)
        TST.B   0x1A00(A0)                      | Q6 on: enter status read mode
        MOVE.B  0x1C00(A0),D0                   | Q7 off: read IWM status, sense data in bit 7
        TST.B   0x1800(A0)                      | Q6 off: return to data mode
        MOVE    (SP)+,SR                        | restore previous IPL
        TST.B   D0                              | set N flag from sense bit 7
        RTS                                     | N=1 means sense=1, N=0 means sense=0
Sony_WriteDriveRegAdr:
        BSR.B   Sony_AdrDisk                    | address drive register D0
Sony_WriteDriveReg:
        MOVE    SR,-(SP)                        | save SR (preserve IPL)
        ORI     #0x300,SR                       | raise IPL to 3 (mask SCC ints)
        TST.B   0xE00(A0)                       | LSTRB on: pulse strobe high
        TST.B   0xC00(A0)                       | LSTRB off: complete strobe pulse
        RTE                                     | restore SR (RTE used as RTS+SR-restore)
Sony_SetSpeed:
        BSR.B   Sony_SetupSonyVars              | A1 = SonyVars, D1 = drive offset
        MOVE    D6,D2                           | D2 = track number
        LSR     #0x4,D2                         | D2 = track / 16 (zone index)
        LSL     #0x3,D2                         | D2 = zone * 8 (PWM table index)
        ADD     D1,D2                           | D2 += drive offset
        MOVE    0x1A(A1,D2.W),D2                | D2 = per-drive PWM seed
        ADD     0x16(A1,D1.W),D2                | D2 += per-drive PWM trim
        BPL.B   SONY_SETSPEED_OK                | D2 >= 0 -> use as-is
        MOVEQ.L #0x0,D2                         | D2 < 0 -> clamp to 0
SONY_SETSPEED_OK:
        CMPI    #0x18F,D2                       | D2 > 0x18F (max PWM)?
        BLE.B   SONY_SETSPEED_OK_2              | within range -> use as-is
        MOVE    #0x18F,D2                       | motor off -> full power-on delay
SONY_SETSPEED_OK_2:
        MOVE    (PWMValue).w,D0                 | D0 = current PWM setting
        BPL.B   SONY_SETSPEED_CONT              | motor running -> compute delay
        MOVE    0x38(A1),D0                     | motor off -> full power-on delay
        BRA.B   SONY_SETSPEED_NO_2              | apply delay
SONY_SETSPEED_CONT:
        SUB     D2,D0                           | D0 = magnitude of speed change
        BEQ.W   Sony_SetupSonyVars              | no change -> return
        BPL.B   SONY_SETSPEED_CONT_2            | positive -> slowing down
        NEG     D0                              | make positive
SONY_SETSPEED_CONT_2:
        LSL     #0x5,D0                         | scale by 32 for delay estimate
        CMP     0x36(A1),D0                     | below minimum speed change time?
        BGT.B   SONY_SETSPEED_NO_2              | no -> use computed delay
        MOVE    0x36(A1),D0                     | enforce minimum delay
SONY_SETSPEED_NO_2:
        ADD     iconIDCC(A1),D0                 | add accumulated motor-on time
        CMP     0x38(A1),D0                     | exceeds max delay?
        BLT.B   SONY_SETSPEED_NO_3              | no -> use sum
        MOVE    0x38(A1),D0                     | clamp to max
SONY_SETSPEED_NO_3:
        MOVE    D0,iconIDCC(A1)                 | save clamped motor-on delay

| SONY_SETSPEED_CONT_3 -- ProgramPWM: generate PWM waveform buffers for disk speed
| D2 = target PWM value. Computes LFSR duty cycle values and fills
| both double-buffered PWM buffers (370 bytes each at even addresses).
SONY_SETSPEED_CONT_3:
        MOVE    D2,(PWMValue).w                 | store new PWM setting
        MOVEM.L D3-D6/A2,-(SP)                  | save registers
        SUBI    #0x18F,D2                       | D2 = $1B8 - speed (invert)
        NEG     D2                              | D2 = inverted PWM count
        EXT.L    D2                             | sign-extend D2 word -> long for DIVU
        DIVU    #0xA,D2                         | D2 = D2 /u #0xA
        MOVEQ.L #0xB,D0                         | D0 = 11 (LFSR seed)
SONY_SETSPEED_LOOP:
        MOVE.B  D0,D1                           | D1 = previous LFSR value
        MOVE.B  D0,D3                           | D3 = feedback calculation
        LSR.B   #0x1,D0                         | shift LFSR right
        EOR.B   D0,D3                           | D3 ^= D0 (compute feedback bit)
        LSR.B   #0x1,D3                         | isolate feedback bit
        BCC.B   SONY_SETSPEED_SKIP              | no feedback -> skip
        BSET    #0x5,D0                         | inject feedback into bit 5
SONY_SETSPEED_SKIP:
        DBRA    D2,SONY_SETSPEED_LOOP           | iterate LFSR D2 times
        SWAP    D2                              | D2 = remainder (0-9)
        MOVE.B  SONY_SETSPEED_CONT_6(PC,D2.W),D5 | D5.hi = dither pattern MSB
        ASL     #0x8,D5                         | shift to high byte
        MOVE.B  SONY_SETSPEED_CONT_7(PC,D2.W),D5 | D5.lo = dither pattern LSB
        MOVEQ.L #0x24,D3                        | D3 = 36 (outer loop: 37 groups)
        LEA.L   (0x7FD01).l,A0                  | LEA abs-long -> addr reg
        MOVE.L  (PWMBuf2).w,A2                  | A2 = PWMBuf2 (alternate PWM buffer)
SONY_SETSPEED_LOOP_2:
        MOVEQ.L #0x9,D2                         | D2 = 9 (inner loop: 10 samples per group)
        MOVE    D5,D4                           | bit=1 -> use D0 (higher value)
SONY_SETSPEED_LOOP_3:
        LSL     #0x1,D4                         | shift dither bit into carry
        BCC.B   SONY_SETSPEED_CONT_4            | bit=0 -> use D1 (lower value)
        MOVE.B  D0,D6                           | bit=1 -> use D0 (higher value)
        BRA.B   SONY_SETSPEED_CONT_5            | write sample
SONY_SETSPEED_CONT_4:
        MOVE.B  D1,D6                           | bit=0 -> D6 = D1 (lower sample)
SONY_SETSPEED_CONT_5:
        MOVE.B  D6,(A0)                         | write to PWM buffer 1
        MOVE.B  D6,(A2)                         | write to PWM buffer 2
        ADDQ.W  #0x2,A0                         | advance by 2 (even addresses only)
        ADDQ.W  #0x2,A2                         | advance buffer 2 likewise
        DBRA    D2,SONY_SETSPEED_LOOP_3         | inner loop: 10 samples per group
        DBRA    D3,SONY_SETSPEED_LOOP_2         | outer loop: 37 groups = 370 samples
        MOVEM.L (SP)+,D3-D6/A2                  | restore registers
        BRA.W   Sony_SetupSonyVars              | reload SonyVars and return

| ----------------------------------------------------------
| Dither pattern tables (12 bytes) -- for PWM speed-control
| DAC dither-pattern lookup. MSB and LSB tables overlap by one
| byte (the $00 at $1C7A serves as MSB[0] for the primary table
| and as LSB[11] / terminator for the secondary series).
SONY_SETSPEED_CONT_6:                           | dither MSB table
        .byte   0x00                            | MSB[0] = 0
SONY_SETSPEED_CONT_7:                           | dither LSB table (11 bytes)
        .byte   0x20, 0x21, 0x24, 0x94          | LSB[0..3]
        .byte   0xAA, 0xB5, 0xB7, 0x7B          | LSB[4..7]
        .byte   0xFF, 0x40, 0x00                | LSB[8..10] (last byte = 0 pad)
E_Sony_Seek:
        BCLR    #0xB,D6                         | clear side bit, keep track only
        BSR.W   Sony_SetSpeed                   | program PWM speed for target zone
        MOVE.L  (DiskVars_JSeek).w,-(SP)        | push Seek vector address
        RTS                                     | dispatch to Sony_Seek
| ----------------------------------------------------------
| Sony Seek
| Sony_Seek: move head to target track D6
| Steps the stepper motor one track at a time via IWM phase lines.
| If current track unknown (negative), recalibrates first.
Sony_Seek:
        MOVE.L  (SP)+,A6                        | save return address
        BSR.W   Sony_SetupSonyVars              | set up SonyVars (A1) and drive vars
        MOVE    0(A1,D1.W),D7                   | D7 = current track number
        BPL.B   SEEK_2                          | known track ->
        BSR.W   SONY_SEEK_CONT_2_CONT_9         | recal to track 0
        MOVE    D0,D7                           | D7 = 0 (after recal)
| --- ROM-variant difference @ $1CA6 ---
| MAC_128K: 0x66, 0x4E (bnes $1cf6 -- branch to 1cf6)
| MAC_512K: 0x60, 0x36 (bras $1cde -- unconditional, different target)
| Reason: control-flow change in the 400K Sony disk driver's sector-read
| retry path between the 1984-01 (128K) and 1984-10 (512K) revisions.
.if ROM_TARGET == MAC_128K
        BNE.B   SONY_STEP_VIA_A6                | 128K: if recal-reached-0, return via A6
.else
        BRA.B   SONY_SEEK_CONT_2_CONT_2         | 512K: always go reload vars + settle
.endif
SEEK_2:
        CMP     D6,D7                           | current track == target?
        BEQ.B   SONY_SEEK_CONT_2_SKIP           | yes -> skip step, go verify

| set up step direction
SONY_SEEK_CONT:
        MOVEQ.L #0x0,D0                         | D0 = 0: DIRTN toward track 0
        MOVEQ.L #0x1,D1                         | D1 = +1: step increment
        MOVE    D7,D2                           | D2 = current track
        SUB     D6,D2                           | D2 = current - target
        BEQ.B   SONY_SEEK_CONT_2_CONT_2         | at target -> store and settle
        BMI.B   SONY_SEEK_CONT_2                | current < target -> step outward
        MOVEQ.L #0x1,D0                         | D0 = 1: DIRTN toward track 0
        MOVEQ.L #-0x1,D1                        | D1 = -1: step inward
SONY_SEEK_CONT_2:
        ADD     D1,D7                           | advance track count by step delta
        BSR.W   Sony_WriteDriveRegAdr           | write DIRTN: set step direction
        MOVE    D7,0(A1,D1.W)                   | update current track position
        MOVEQ.L #0x4,D0                         | STEP sense register
        BSR.W   Sony_ReadDriveRegAdr            | read STEP: 1=stepper can step
        BMI.B   SONY_SEEK_CONT_2_CONT           | stepper ready -> perform step
        MOVEQ.L #-0x4B,D7                       | cantStepErr (-75): stepper jammed
        BRA.B   SONY_SEEK_CONT_2_CONT_2         | step error -> store track and settle
SONY_SEEK_CONT_2_CONT:
        BSR.W   Sony_WriteDriveReg              | pulse STEP: advance head one track
        MOVE    0x3C(A1),D0                     | D0 = SeekTime (per-step delay)
        BSR.B   E_Sony_WakeUp                   | wait for stepper settle via WakeUp
        BRA.B   SONY_SEEK_CONT                  | loop: step toward target
SONY_SEEK_CONT_2_CONT_2:
        BSR.W   Sony_SetupSonyVars              | reload A1=SonyVars, D1=drive offset
        MOVE    D7,0(A1,D1.W)                   | CurTrack = D7 (final track or err)
        MOVE    0x34(A1),D0                     | D0 = HeadSettle delay
        BSR.B   E_Sony_WakeUp                   | wait for head to settle
SONY_SEEK_CONT_2_SKIP:
        MOVE    iconIDCC(A1),D0                 | D0 = MotorOnDelay (residual spin-up)
        BEQ.B   SONY_SEEK_CONT_2_CONT_3         | zero -> motor at speed already
        BSR.B   E_Sony_WakeUp                   | wait remaining motor-on delay
SONY_SEEK_CONT_2_CONT_3:
        MOVE    D7,D0                           | D0 = D7 (error code from seek)
SONY_STEP_VIA_A6:                               | 128K variant BNE.B target
        JMP     (A6)                            | return via A6 (saved caller PC)
SONY_SEEK_CONT_2_CONT_4:
        MOVE    0x3E(A1),D0                     | D0 = SectTime (post-write head delay)
E_Sony_WakeUp:
        MOVE.L  (DiskVars_JWakeUp).w,-(SP)      | push JWakeUp vector
        RTS                                     | dispatch to Sony_WakeUp
        BSR.W   Sony_SetupRegs                  | A0 = IWM, A2 = VIA
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return PC in DskRtnAdr lowmem
        ORI     #0x100,SR                       | raise IPL=1 (mask level-1 interrupts)
        SUB     D0,iconIDCC(A1)                 | 20(A1) -= D0
        BGT.B   SONY_SEEK_CONT_2_CONT_5         | positive remainder -> use as-is
        CLR     iconIDCC(A1)                    | 20(A1) := 0
SONY_SEEK_CONT_2_CONT_5:
        MOVEQ.L #0x4E,D1                        | D1 = $4E = 78 (timer scale: 100us/tick)
        MULU    D0,D1                           | D1 = D0 * 78 (T2 count for D0 100us)
        BCLR    #0x5,vACR(A2)                   | clear VIA T2 interrupt enable
        LEA     SONY_SEEK_CONT_2_CONT_6(PC),A0  | A0 = T2 interrupt service routine
        MOVE.L  A0,(Lvl1DT_5).w                 | install T2 ISR in Lvl1DT[5] vector
        MOVE.B  D1,vT2C(A2)                     | write T2 counter low
        ROR     #0x8,D1                         | rotate D1 to access high byte
        MOVE.B  D1,vT2CH(A2)                    | write T2 counter high (starts timer)
        MOVE.B  #0xA0,vIER(A2)                  | enable T2 interrupt (VIA IER: IE+T2)
        SWAP    D1                              | restore high word of D1
        MOVE    D1,0xCE(A1)                     | save high word of T2 reload count
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        MOVEM.L D3-D7/A3-A6,0xD0(A1)            | D3-D7/A3-A6 -> 0xD0(A1)
        ANDI    #-0x701,SR                      | SR &= -0x701
        RTS                                     | return to caller (will resume on T2 IRQ)
SONY_SEEK_CONT_2_CONT_6:
        MOVE.B  0x1200(A1),0x1200(A1)           | ack VIA T2 interrupt (read-modify-write)
        BSR.W   Sony_SetupRegs                  | reload A0=IWM, A2=VIA after IRQ
        SUBQ.W  #0x1,0xCE(A1)                   | decrement remaining T2 wraparound count
        BMI.B   SONY_SEEK_CONT_2_CONT_7         | count exhausted -> resume caller
        RTS                                     | more wraps needed -> return from IRQ
SONY_SEEK_CONT_2_CONT_7:
        MOVE.B  #0x20,0x1C00(A2)                | VIA IER: disable T2 interrupt
        MOVEM.L D4-D7/A4-A6,-(SP)               | save IRQ-frame regs to stack
        MOVEM.L 0xD0(A1),D3-D7/A3-A6            | 0xD0(A1) -> D3-D7/A3-A6
        PEA.L   SONY_SEEK_CONT_2_CONT_8(PC)     | push restore-stub return address
        BRA.W   SONY_FIGTRKSPD_EXIT             | jump to caller's saved PC (DskRtnAdr)
SONY_SEEK_CONT_2_CONT_8:
        MOVEM.L (SP)+,D4-D7/A4-A6               | restore IRQ-frame regs
        RTS                                     | return from T2 wakeup ISR
SONY_SEEK_CONT_2_CONT_9:
        MOVE.L  (DiskVars_JRecal).w,-(SP)       | push JRecal vector
        RTS                                     | dispatch to Sony_Recal
        MOVE.L  (SP)+,A5                        | A5 = caller return address
        BSR.W   Sony_SetupRegs                  | A0 = IWM, A2 = VIA
| --- ROM-variant difference @ $1D8A (MOVEQ immediate) ---
| MAC_128K: MOVEQ.L #31,D1 -- mask value 0x1F
| MAC_512K: MOVEQ.L #63,D1 -- mask value 0x3F (larger set of valid bits)
| Reason: 1984-10 revision widened the status-register bit mask used to
| validate IWM register contents in the sector-scan retry loop.
.if ROM_TARGET == MAC_128K
        MOVEQ.L #0x1F,D1                        | 128K: mask 0x1F
.else
        MOVEQ.L #0x3F,D1                        | 512K: mask 0x3F
.endif
        TST.B   0x1A00(A0)                      | Q6 on: enter status read mode
        MOVE.B  0x1C00(A0),D0                   | Q7 off: read IWM status byte
        TST.B   0x1800(A0)                      | Q6 off: return to data mode
        AND.B   D1,D0                           | D0 &= valid-bits mask
        CMP.B   D1,D0                           | all valid bits high (idle state)?
| --- ROM-variant difference @ $1D9C (branch displacement) ---
| MAC_128K: BEQ.B +0x32 -- target $1DD0 (below, current layout)
| MAC_512K: BEQ.B +0x34 -- target $1DD2 (shifted +2 bytes by insertion below)
| Reason: the 512K revision adds a 2-byte MOVEQ at $1DA2, which pushes
| every address below that point down by 2; this branch's displacement
| is adjusted to still land on the revised `SONY_SEEK_CONT_2_CONT_11`-equivalent label.
.if ROM_TARGET == MAC_128K
        BEQ.B   SONY_SEEK_CONT_2_CONT_11        | 128K: disp +0x32 -> $1DD0
.else
        BEQ.B   SONY_SEEK_CONT_2_CONT_11        | 512K: disp +0x34 -> $1DD2 (same label, shifted addr)
.endif
        MOVEQ.L #0x2,D2                         | D2.lo = 2 (low word seed)
        SWAP    D2                              | D2 = $00020000 = 131072 retry count
| --- ROM-variant difference @ $1DA2..$1DD5 ---
| MAC_128K (52 B): original sector-scan body, BEQ target at $1DD0.
| MAC_512K (52 B): identical logic but prefixed with an extra
| MOVEQ.L #31,D1 (re-asserting the mask after the loop entry) and
| with the trailing sector-index constants shifted (MOVEQ #0x52->#0x50,
| BRA.B +0x12 replaced by NOP to keep byte-count parity).
| Reason: the 1984-10 revision hardens the Sony scan retry by re-
| loading the valid-bits mask on every iteration, then adjusts the
| subsequent initialization constants to preserve the original dispatch
| offsets downstream. Keep both branches byte-equal so surrounding
| addresses don't shift.
.if ROM_TARGET == MAC_128K
| SONY_SEEK_CONT_2_NO - 128K seek-retry path (no extra IWM mask reload)
SONY_SEEK_CONT_2_NO:
        MOVEQ.L #-0x4D,D0                       | D0 = -77 (error placeholder)
        SUBQ.L  #0x1,D2                         | decrement IWM-status retry count
        BMI.B   SONY_SEEK_CONT_2_ERR_2          | no retries left: error
        TST.B   0x1000(A0)                      | IWM $1000: PH0/CA0 strobe
        TST.B   0x1A00(A0)                      | IWM $1A00: PH2/CA2 strobe
        MOVE.B  0x1C00(A0),D0                   | D0 = IWM $1C00 (Q6 status)
        BTST    #0x5,D0                         | valid-bits bit 5 set?
        BNE.B   SONY_SEEK_CONT_2_NO             | no: retry
        AND.B   D1,D0                           | mask to valid bits (D1 = 31)
        CMP.B   D1,D0                           | bits all set?
        BEQ.B   SONY_SEEK_CONT_2_CONT_10        | yes: OK
        MOVE.B  D1,0x1E00(A0)                   | no: pulse IWM register
        TST.B   0x1C00(A0)                      | re-read status
        BRA.B   SONY_SEEK_CONT_2_NO             | loop
SONY_SEEK_CONT_2_CONT_10:
        TST.B   0x1800(A0)                      | IWM $1800: PH1/CA1
        BSR.B   Sony_MotorOn2                   | finalize drive state
SONY_SEEK_CONT_2_CONT_11:
        MOVEQ.L #0x52,D7                        | D7 = $52 (sector index)
        MOVEQ.L #0x0,D0                         | D0 = noErr
        BRA.B   SONY_SEEK_CONT_2_CONT_13        | continue seek
.else
| 512K variant: same logic, prefixed with `MOVEQ #31,D1` at entry and
| trailing MOVEQ #0x52 replaced by MOVEQ #0x50 + NOP. The BNE/BRA
| loop bodies jump back to the MOVEQ #-77 (not to the mask re-load),
| preserving the single-shot semantics of the mask initialization.
SONY_SEEK_CONT_2_NO:                            | @ $1DA2 (512K entry)
        MOVEQ.L #0x1F,D1                        | D1 = 31 = valid-bits mask (entry only)
SONY_SEEK_CONT_2_NO_LOOP:                       | @ $1DA4 (512K loop head)
        MOVEQ.L #-0x4D,D0                       | D0 = -77 (error placeholder)
        SUBQ.L  #0x1,D2                         | decrement IWM-status retry count
        BMI.B   SONY_SEEK_CONT_2_ERR_2          | no retries left: error
        TST.B   0x1000(A0)                      | IWM $1000: PH0/CA0 strobe
        TST.B   0x1A00(A0)                      | IWM $1A00: PH2/CA2 strobe
        MOVE.B  0x1C00(A0),D0                   | D0 = IWM $1C00 (Q6 status)
        BTST    #0x5,D0                         | valid-bits bit 5 set?
        BNE.B   SONY_SEEK_CONT_2_NO_LOOP        | no: retry (keep mask)
        AND.B   D1,D0                           | mask to valid bits
        CMP.B   D1,D0                           | bits all set?
        BEQ.B   SONY_SEEK_CONT_2_CONT_10        | yes: OK
        MOVE.B  D1,0x1E00(A0)                   | no: pulse IWM register
        TST.B   0x1C00(A0)                      | re-read status
        BRA.B   SONY_SEEK_CONT_2_NO_LOOP        | loop
SONY_SEEK_CONT_2_CONT_10:                       | @ $1DCC (512K)
        TST.B   0x1800(A0)                      | IWM $1800: PH1/CA1
        BSR.B   Sony_MotorOn2                   | finalize drive state
SONY_SEEK_CONT_2_CONT_11:                       | @ $1DD2 (512K)
        MOVEQ.L #0x50,D7                        | D7 = $50 (adjusted for shifted layout)
        NOP                                     | padding (replaces BRA in 128K)
.endif
| SONY_SEEK_CONT_2_CONT_12 - common seek-step entry: read TK0 sense, wake drive
SONY_SEEK_CONT_2_CONT_12:
        MOVE    0x3C(A1),D0                     | D0 = SeekTime (per-step delay)
        BSR.W   E_Sony_WakeUp                   | wait for step settling
        MOVEQ.L #0xA,D0                         | TK0 sense register
        BSR.W   Sony_ReadDriveRegAdr            | read TK0, 0 = at track 0
        BPL.B   SONY_SEEK_CONT_2_DONE           | at track 0 -> done
        MOVEQ.L #0x1,D0                         | DIRTN=1: step toward track 0
SONY_SEEK_CONT_2_CONT_13:
        BSR.W   Sony_WriteDriveRegAdr           | write DIRTN
        MOVEQ.L #0x4,D0                         | STEP sense register
        BSR.W   Sony_ReadDriveRegAdr            | read STEP, 1 = step done
        BPL.B   SONY_SEEK_CONT_2_ERR            | step not possible -> error
        MOVEQ.L #-0x4C,D0                       | tk0BadErr (-76): can't find track 0
        SUBQ.W  #0x1,D7                         | decrement step counter
        BEQ.B   SONY_SEEK_CONT_2_ERR_2          | 80 steps done -> return error
        BSR.W   Sony_WriteDriveReg              | write STEP: execute one step
        BRA.B   SONY_SEEK_CONT_2_CONT_12        | loop: poll TK0 until at track 0
SONY_SEEK_CONT_2_DONE:
        MOVEQ.L #0x0,D0                         | D0 = noErr (track 0 reached)
        BRA.B   SONY_SEEK_CONT_2_ERR_2          | store CurTrack and return
SONY_SEEK_CONT_2_ERR:
        MOVEQ.L #-0x4B,D0                       | D0 = -75 = cantStepErr
SONY_SEEK_CONT_2_ERR_2:
        MOVE    D0,0(A1,D1.W)                   | CurTrack = D0 (0 = track 0, neg = err)
        JMP     (A5)                            | jump via A5
| ----------------------------------------------------------
| Sony MotorOff -- schedule or execute motor power-down
| D0 = delay in VBL ticks (0 = immediate off)
Sony_MotorOff:
        BSR.W   Sony_SetupSonyVars              | A1 = SonyVars, D1 = drive offset
        MOVE    D0,TrkSpeedTbl(A1)              | save delay (0 = immediate, n = VBL count)
        BEQ.B   SONY_MOTOROFF_EMPTY             | zero -> stop motor now
        RTS                                     | return to caller (@ $1E16)
SONY_MOTOROFF_EMPTY:
        MOVEQ.L #0x9,D0                         | MOTOROFF register address
        BSR.W   Sony_WriteDriveRegAdr           | write MOTOROFF: stop motor
        TST.B   0x1000(A0)                      | ENABLE off: deselect drive
        RTS                                     | return: motor stopped
Sony_MotorOn1:
        MOVEQ.L #0x0,D0                         | D0 = 0: no spin-up wait
        BRA.B   SONY_MOTORON2_CONT              | enter common motor-on path
Sony_MotorOn2:
        MOVE    0x38(A1),D0                     | D0 = PwrOnTime (full spin-up wait)
SONY_MOTORON2_CONT:
        MOVE    D0,D2                           | D2 = saved spin-up delay
        BSR.W   Sony_SetupSonyVars              | A1 = SonyVars, D1 = drive offset
        CLR     TrkSpeedTbl(A1)                 | 26(A1) := 0
        BSR.B   Sony_JumpDiskSel                | select drive (ENABLE this drive)
        MOVEQ.L #0x8,D0                         | D0 = 8 (MOTORON sense register)
        BSR.W   Sony_ReadDriveRegAdr            | read MOTORON: motor running?
        BPL.B   SONY_MOTORON2_EXIT              | already running -> skip
        BSR.W   Sony_WriteDriveReg              | pulse MOTORON: start motor
        MOVE    D2,D0                           | D0 = saved spin-up delay
        BNE.W   E_Sony_WakeUp                   | nonzero -> wait via WakeUp
SONY_MOTORON2_EXIT:
        RTS                                     | return: motor on
Sony_JumpDiskSel:
        BSR.W   Sony_SetupRegs                  | A0=IWM, A2=VIA
SONY_MOTOROFF_CONT_6:
        MOVE    #0x1400,D0                      | D0 = $1400 (ENABLE1: drive 1)
        CMPI    #0x4A,D1                        | drive offset == $4A (internal)?
        BEQ.B   SONY_MOTOROFF_CONT_7            | yes -> use ENABLE1
        MOVE    #0x1600,D0                      | no -> $1600 (ENABLE2: drive 2)
SONY_MOTOROFF_CONT_7:
        TST.B   0(A0,D0.W)                      | assert ENABLE for selected drive
        TST.B   0x1200(A0)                      | disable drive register-read mode
        RTS                                     | return: drive selected
| Speed zone RPM-limit table: 5 zones x (upper, lower) RPM thresholds

| ----------------------------------------------------------
| DT_Sony_SpeedCheckTbl -- acceptable disk RPM ranges per speed zone
| 5 zones x 2 words = 20 bytes of (upper, lower) RPM-scaled thresholds.
| Used by SONY_MAKESPDTBL to verify the PWM speed falls within tolerance.
DT_Sony_SpeedCheckTbl:
        .short  0x11E9, 0x1135                  | zone 0: upper 4585, lower 4405 RPM-scaled
        .short  0x138A, 0x12C6                  | zone 1: upper 5002, lower 4806 RPM-scaled
        .short  0x157F, 0x14A7                  | zone 2: upper 5503, lower 5287 RPM-scaled
        .short  0x17E2, 0x16F2                  | zone 3: upper 6114, lower 5874 RPM-scaled
        .short  0x1ADE, 0x19D0                  | zone 4: upper 6878, lower 6608 RPM-scaled
E_Sony_MakeSpdTbl:
        MOVE.L  (DiskVars_JMakeSpdTbl).w,-(SP)  | push JMakeSpdTbl patch-vector
        RTS                                     | dispatch via JMakeSpdTbl
| ----------------------------------------------------------
| Sony MakeSpdTbl
| Sony_MakeSpdTbl: build speed correction table by measuring RPM
| at two PWM values and interpolating per-zone PWM values.
| Classic 1984 is 400K-only; Plus 1986 added 800K early-out (not in classic).
Sony_MakeSpdTbl:
        MOVE.L  (SP)+,A4                        | A4 = return address
        MOVE    #0x80,D2                        | first calibration PWM = $80
        BSR.B   SONY_MAKESPDTBL_CONT_5          | program PWM, measure speed -> D4
        BMI.B   SONY_MAKESPDTBL_ERR             | measurement failed -> exit
        MOVE.L  D4,D3                           | D3 = speed at PWM $80
        MOVE    #0x100,D2                       | second calibration PWM = $100
        BSR.B   SONY_MAKESPDTBL_CONT_5          | program PWM, measure speed -> D4
        BMI.B   SONY_MAKESPDTBL_ERR             | measurement failed -> exit
        MOVE.L  D4,D5                           | D5 = speed at PWM $100
        SUB.L   D3,D5                           | D5 = speed difference (slope)
        LSL.L   #0x1,D3                         | D3 = 2 * speed_low (interpolation)
        MOVEQ.L #0x4,D6                         | D6 = 4 (5 speed zones, 0-based)
        LEA     DT_Sony_SpeedCheckTbl(PC),A5    | A5 -> target RPM range table
        BSR.W   Sony_SetupSonyVars              | reload drive offset
        LEA.L     0x1A(A1,D1.W),A3              | A3 -> per-drive speed table

| SONY_MAKESPDTBL_LOOP -- compute PWM values for each zone pair
SONY_MAKESPDTBL_LOOP:
        MOVEQ.L #0x0,D2                         | clear for word load
        MOVE    (A5)+,D2                        | D2 = upper RPM limit for zone
        MOVE.L  D2,D7                           | D7 = save upper limit
        ADD     (A5)+,D2                        | D2 += lower RPM limit
        LSR     #0x1,D2                         | D2 = midpoint RPM for zone
SONY_MAKESPDTBL_LOOP_CONT:
        ADD.L   D4,D2                           | D2 += measured high speed
        SUB.L   D3,D2                           | D2 -= measured low speed (numerator)
        BPL.B   SONY_MAKESPDTBL_LOOP_CONT_2     | positive -> use as-is
        MOVEQ.L #0x0,D2                         | negative -> clamp to 0
SONY_MAKESPDTBL_LOOP_CONT_2:
        LSL.L   #0x7,D2                         | D2 <<= 7 (scale for fixed-point divide)
        BEQ.B   SONY_MAKESPDTBL_LOOP_CONT_3     | zero -> skip divide
        DIVU    D5,D2                           | D2 = (numerator * 128) / slope
SONY_MAKESPDTBL_LOOP_CONT_3:
        ADDQ.W  #0x1,D2                         | round up
        CMPI    #0x18F,D2                       | exceeds max PWM ($18F)?
        BLE.B   SONY_MAKESPDTBL_OK              | no -> use as-is
        MOVE    #0x18F,D2                       | clamp to max
SONY_MAKESPDTBL_OK:
        MOVE    D2,(A3)+                        | store PWM for this zone limit
        EXG     D7,D2                           | swap: D2 = upper limit, D7 = computed PWM
        NOT     D0                              | toggle pass flag (first/second iteration)
        BNE.B   SONY_MAKESPDTBL_LOOP_CONT       | do second limit
        SUBQ.W  #0x4,A3                         | back up to compute delta
        SUB     (A3)+,D7                        | D7 = upper - lower PWM
        MOVE    D7,(A3)+                        | store delta for speed adjustment
        CLR.L   (A3)+                           | clear timestamp for this zone
        DBRA    D6,SONY_MAKESPDTBL_LOOP         | next zone
SONY_MAKESPDTBL_ERR:
        TST     D0                              | test error flags in D0
        JMP     (A4)                            | return via saved A4 vector
SONY_MAKESPDTBL_CONT_5:
        MOVE.L  (SP)+,A3                        | A3 = return address
        BSR.W   SONY_SETSPEED_CONT_3            | program PWM to value D2
        MOVE    0x38(A1),D0                     | D0 = spin-up settling delay
        BSR.W   E_Sony_WakeUp                   | wait for motor to reach speed
SONY_MAKESPDTBL_CONT_6:
        MOVEQ.L #0x0,D4                         | clear speed accumulator
        MOVEQ.L #0x3,D5                         | 4 samples to average (0..3)
SONY_MAKESPDTBL_LOOP_2:
        BSR.B   E_Sony_FigTrkSpd                | measure time for 15 TACH edges
        BMI.B   SONY_MAKESPDTBL_ERR_2           | measurement error -> exit via A3
        ADD.L   D0,D4                           | accumulate TACH time
        DBRA    D5,SONY_MAKESPDTBL_LOOP_2       | repeat 4 times
        LSR.L   #0x3,D4                         | D4 = average (sum/8, not sum/4)
        MOVE.L  #0x04000000,D0                  | D0 = 67108864: RPM conversion constant
        DIVU    D4,D0                           | D0 = constant / average TACH time = RPM scale
        MOVE    D0,D4                           | D4 = speed value
        MOVEQ.L #0x0,D0                         | D0 = noErr
SONY_MAKESPDTBL_ERR_2:
        JMP     (A3)                            | return via A3 (saved caller PC)
E_Sony_FigTrkSpd:
        MOVE.L  (DiskVars_JFigTrkSpd).w,-(SP)   | push FigTrkSpd vector address
        RTS                                     | dispatch to Sony_FigTrkSpd
| ----------------------------------------------------------
| Sony FigTrkSpd
| Sony_FigTrkSpd: measure time for 15 TACH pulses
| Uses VIA Timer 2 as a free-running counter. Returns elapsed time
| in D0 (positive), or -64 on error.
Sony_FigTrkSpd:
        MOVE    SR,-(SP)                        | save SR
        MOVEM.L D1-A6,-(SP)                     | save all registers
        MOVEQ.L #0x4,D0                         | reserve 4 bytes on poll stack
        BSR.W   SONY_CHECKFORNEWDISKS_CONT_6    | set up SCC/VIA for polling
        MOVEQ.L #0xE,D0                         | TACH sense register address
        BSR.W   Sony_AdrDisk                    | address TACH via phase lines
        LEA.L   0xDFE1FF.l,A0                   | A0 = IWM base address
        TST.B   0x1A00(A0)                      | Q6 on: enter status read mode
        MOVEQ.L #-0x1,D1                        | D1 = $FFFF: T2 max count
        MOVEQ.L #0x5,D3                         | D3 = 5: VIA IFR bit for T2 timeout
        MOVE.L  (VIA).w,A2                      | A2 = VIA base
        LEA.L     0x1A00(A2),A3                 | A3 = VIA IFR register
        LEA.L     0x1C00(A0),A1                 | A1 = IWM Q7L address (status read)
        BSR.B   SONY_FIGTRKSPD_CONT             | start VIA T2 free-run timer
        BSR.B   SONY_FIGTRKSPD_NEXT             | sync: wait for first TACH edge
        BEQ.B   SONY_FIGTRKSPD_CONT_2           | synchronized -> begin measurement
SONY_FIGTRKSPD_ERR:
        TST.B   0x1800(A0)                      | Q6 off: return to data mode
        BSR.W   SONY_RESEEK_CONT_8              | call PollProc
        MOVEM.L (SP)+,D1-A6                     | restore all registers
        MOVE    (SP)+,SR                        | restore SR
        TST.L   D0                              | set condition codes on result
        RTS                                     | return: D0 = elapsed time or error
| -------------------------------------------------------
| SONY_FIGTRKSPD_CONT -- StartT2: load VIA Timer 2 with $FFFF and start counting
SONY_FIGTRKSPD_CONT:
        MOVE.B  D1,vT2C(A2)                     | T2L-L = $FF
        MOVE.B  D1,vT2CH(A2)                    | T2C-H = $FF: starts countdown
        RTS                                     | return: T2 timer running
SONY_FIGTRKSPD_CONT_2:
        BSR.B   SONY_FIGTRKSPD_CONT             | start VIA T2 countdown
        MOVEQ.L #0xE,D2                         | 15 TACH edges (0..14)
SONY_FIGTRKSPD_LOOP:
        BSR.B   SONY_FIGTRKSPD_NEXT             | wait for next TACH edge
        BNE.B   SONY_FIGTRKSPD_ERR              | timeout -> error exit
        DBRA    D2,SONY_FIGTRKSPD_LOOP          | count 15 TACH edges
        MOVE.B  vT2CH(A2),D2                    | read T2C-H (high byte)
        MOVE.B  vT2C(A2),D1                     | read T2C-L (low byte)
        CMP.B   vT2CH(A2),D2                    | T2C-H changed during read?
        BEQ.B   SONY_FIGTRKSPD_OK               | no -> reading is consistent
        MOVEQ.L #0x0,D1                         | yes -> clear low byte (ambiguous)
SONY_FIGTRKSPD_OK:
        BTST    D3,(A3)                         | IFR bit 5: T2 timed out?
        BNE.B   SONY_FIGTRKSPD_ERR              | yes -> measurement invalid
        LSL     #0x8,D2                         | D2 = high byte << 8
        OR.B    D1,D2                           | D2 |= low byte (full 16-bit count)
        NOT     D2                              | invert: D2 = $FFFF - count = elapsed
        MOVEQ.L #0x0,D0                         | clear high word
        MOVE    D2,D0                           | D0 = elapsed time for 15 TACH edges
        BRA.B   SONY_FIGTRKSPD_ERR              | return with D0 = time
SONY_FIGTRKSPD_NEXT:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save caller return PC in DskRtnAdr lowmem
SONY_FIGTRKSPD_NO:
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_FIGTRKSPD_SKIP             | SCC busy -> skip RX service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_FIGTRKSPD_SKIP:
        TST.B   (A1)                            | read IWM status (TACH in bit 7)
        BMI.B   SONY_FIGTRKSPD_NO_2             | TACH=1 -> not low yet
        TST.B   (A1)                            | confirm second consecutive 0
        BPL.B   SONY_FIGTRKSPD_FOUND            | two 0s found -> scan for 1s
SONY_FIGTRKSPD_NO_2:
        BTST    D3,(A3)                         | T2 timed out?
        BEQ.B   SONY_FIGTRKSPD_NO               | still counting -> retry
SONY_FIGTRKSPD_ERR_2:
        MOVEQ.L #-0x40,D0                       | timeout error (-0x40 = noDriveErr)

| SONY_FIGTRKSPD_EXIT -- resume continuation: push saved return and dispatch
SONY_FIGTRKSPD_EXIT:
        MOVE.L  (DskRtnAdr).w,-(SP)             | push saved continuation address
        TST     D0                              | set condition codes on result
        RTS                                     | return to continuation
SONY_FIGTRKSPD_FOUND:
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_FIGTRKSPD_SKIP_2           | busy -> skip SCC service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_FIGTRKSPD_SKIP_2:
        BTST    D3,(A3)                         | T2 timed out?
        BNE.B   SONY_FIGTRKSPD_ERR_2            | yes -> return noDriveErr
        TST.B   (A1)                            | read TACH
        BPL.B   SONY_FIGTRKSPD_FOUND            | still 0 -> keep waiting
        TST.B   (A1)                            | confirm second consecutive 1
        BPL.B   SONY_FIGTRKSPD_FOUND            | false alarm -> keep waiting
        MOVEQ.L #0x0,D0                         | noErr: rising edge detected
        BRA.B   SONY_FIGTRKSPD_EXIT             | return success

| ----------------------------------------------------------
| Sony CheckForNewDisks
| -------------------------------------------------------
| Sony_CheckForNewDisks -- VBL task: poll drives for inserted disks
| Called every ~0.5 sec by Vertical Retrace Manager.
| Also handles deferred motor power-off countdown.
Sony_CheckForNewDisks:
        MOVE    SR,-(SP)                        | save interrupt state
        ORI     #0x100,SR                       | raise IPL to 1 (mask level-1 ints)
        MOVE.L  (SonyVars).w,A1                 | load SonyVars
        MOVE    0x40(A1),10(A0)                 | DskVBLTime: reload VBLCount
        TST.B   25(A1)                          | Active: driver busy?
        BNE.B   SONY_CHECKFORNEWDISKS_CONT_2    | driver active -> skip poll, RTE
        TST     TrkSpeedTbl(A1)                 | PwrOffDelay: motor-off pending?
        BEQ.B   SONY_CHECKFORNEWDISKS_CONT      | no countdown -> go scan drives
        SUBQ.W  #0x1,TrkSpeedTbl(A1)            | decrement motor-off countdown
        BNE.B   SONY_CHECKFORNEWDISKS_CONT_2    | still counting down -> RTE
        MOVEQ.L #0x9,D0                         | MOTOROFF register
        BSR.W   Sony_WriteDriveRegAdr           | power off motor
        TST.B   0x1000(A0)                      | ENABLE off: deselect drive
SONY_CHECKFORNEWDISKS_CONT:
        MOVEQ.L #0x2,D3                         | D3 = 2 (drive #2 = external)
        BSR.B   SONY_CHECKFORNEWDISKS_CONT_3    | poll external drive
        MOVEQ.L #0x1,D3                         | D3 = 1 (drive #1 = internal)
        BSR.B   SONY_CHECKFORNEWDISKS_CONT_3    | poll internal drive
SONY_CHECKFORNEWDISKS_CONT_2:
        RTE                                     | return from VBL task
SONY_CHECKFORNEWDISKS_CONT_3:
        MOVE    D3,TwoSideFmt(A1)               | select this drive in SonyVars
        BSR.W   Sony_SetupRegs                  | A0=IWM, A2=VIA, D1=drive offset
        BSR.B   SONY_CHECKFORNEWDISKS_CONT_4_OK | test if drive present + read DIRTN
        BMI.B   SONY_CHECKFORNEWDISKS_CONT_4_CONT_2 | drive absent -> return
        BSR.W   SONY_MOTOROFF_CONT_6            | select drive (ENABLE this drive)
        TST.B   3(A1,D1.W)                      | DiskInPlace state byte
        BGT.B   SONY_CHECKFORNEWDISKS_CONT_4_CONT_2 | disk already detected -> skip
        BEQ.B   SONY_CHECKFORNEWDISKS_CONT_4    | zero -> check disk insert
        ADDQ.B  #0x1,3(A1,D1.W)                 | 3(A1,D1.W) += 0x1
        BMI.B   SONY_CHECKFORNEWDISKS_CONT_4_CONT | EjectWait still active -> skip insert
SONY_CHECKFORNEWDISKS_CONT_4:
        MOVEQ.L #0x2,D0                         | D0 = 2 (DiskIn sense register)
        BSR.W   Sony_ReadDriveRegAdr            | read DiskIn (0 = inserted)
        BMI.B   SONY_CHECKFORNEWDISKS_CONT_4_CONT | no disk -> skip postEvent
        ADDQ.B  #0x1,3(A1,D1.W)                 | 3(A1,D1.W) += 0x1
        MOVE    #0x7,A0                         | A0 = 7 (diskEvt event code)
        MOVE.L  D3,D0                           | D0 = drive number (event message)
        _PostEvent                              | post diskEvt to event queue
SONY_CHECKFORNEWDISKS_CONT_4_CONT:
        ST      0(A1,D1.W)                      | 0(A1,D1.W) := -1 (true)
SONY_CHECKFORNEWDISKS_CONT_4_CONT_2:
        RTS                                     | return from per-drive poll
SONY_CHECKFORNEWDISKS_CONT_4_OK:
        MOVE.B  4(A1,D1.W),D2                   | D2 = DriveStatus byte
        BNE.B   SONY_CHECKFORNEWDISKS_CONT_4_NO | already known -> skip detection
        BSR.W   SONY_MOTOROFF_CONT_6            | select drive (ENABLE this drive)
        MOVEQ.L #0xD,D0                         | D0 = $D = INSTALLED (drive present?)
        MOVEQ.L #-0x1,D2                        | D2 = -1 (assume drive present)
        BSR.W   Sony_ReadDriveRegAdr            | read INSTALLED (0 = present)
        BMI.B   SONY_CHECKFORNEWDISKS_CONT_4_NO_CONT | absent -> remove from queue
        MOVEQ.L #0x1,D2                         | D2 = 1 (drive present marker)
        MOVEQ.L #0x9,D0                         | D0 = 9 (SIDES sense register)
        BSR.W   Sony_ReadDriveRegAdr            | read SIDES (1 = double-sided)
        SMI     5(A1,D1.W)                      | 5(A1,D1.W) := (N == 1)
SONY_CHECKFORNEWDISKS_CONT_4_NO:
        MOVEQ.L #-0x40,D0                       | D0 = -0x40 (sets N for return)
        MOVE.B  D2,4(A1,D1.W)                   | DriveStatus = D2
        RTS                                     | return from drive-detection
SONY_CHECKFORNEWDISKS_CONT_4_NO_CONT:
        LEA.L     6(A1,D1.W),A0                 | A0 = DQE for absent drive
        LEA.L     (DrvQHdr_Flags).w,A1          | A1 = drive queue header
        JSR     Dequeue(PC)                     | remove drive from queue
        BSR.W   Sony_SetupSonyVars              | reload A1=SonyVars, D1=drive offset
        BRA.B   SONY_CHECKFORNEWDISKS_CONT_4_NO | set DriveStatus=-1 and return
SONY_CHECKFORNEWDISKS_CONT_5:
        ADD.L   D2,-0x6922(A2)                  | -0x6922(A2) += D2
        .short  0xAAFF                          | A-line trap $AAFF (no macro in traps.inc)
| SONY_CHECKFORNEWDISKS_CONT_6 - tail: dispatch to JSetUpPoll vector via RTS
SONY_CHECKFORNEWDISKS_CONT_6:
        MOVE.L  (DiskVars_JSetUpPoll).w,-(SP)   | push JSetUpPoll vector
        RTS                                     | dispatch to Sony_SetUpPoll
| -------------------------------------------------------
| Sony_SetUpPoll -- table-driven entry: set up polling state.
| A6 = SCC channel A data read; A5 = VIA port A; SP saved as
| PollStack base; D0 reserves bytes on poll stack; IPL raised.
Sony_SetUpPoll:
        LEA.L   (0x9FFFFE).l,A6                 | A6 = SCC channel A data read
        LEA.L   (0xEFFFFE).l,A5                 | A5 = VIA port A (SCC wait/request)
        MOVE.L  SP,(PollStack).w                | save current SP as poll stack base
        ADD.L   D0,(PollStack).w                | reserve D0 bytes on poll stack
        ORI     #0x300,SR                       | raise IPL to mask interrupts
        RTS                                     | return

| -------------------------------------------------------
| SONY_SETUPPOLL_CONT -- ReadSectorAddr: set up polling, select head side,
| then call RdAddr to read sector address mark.
| Returns D1=track/side, D2=sector, D3=format byte.
SONY_SETUPPOLL_CONT:
        MOVEQ.L #0x8,D0                         | reserve 8 bytes on poll stack
        BSR.B   SONY_CHECKFORNEWDISKS_CONT_6    | set up A5/A6 and PollStack
        MOVEQ.L #0x1,D0                         | D0 = 1: head on side 0
        BTST    #0x3,DriveType(A1)              | side 1 requested?
        BEQ.B   SONY_SETUPPOLL_NO               | no -> side 0
        MOVEQ.L #0x3,D0                         | D0 = 3: head on side 1
SONY_SETUPPOLL_NO:
        BSR.W   Sony_AdrDisk                    | select head side (0 or 1)
| E_Sony_RdAddr -- read sector address field.
E_Sony_RdAddr:
        LEA     SONY_CHECKFORNEWDISKS_CONT_5(PC),A2 | A2 = address of address marks table
        MOVE.L  (DiskVars_JRdAddr).w,-(SP)      | push JRdAddr vector
        RTS                                     | dispatch to Sony_RdAddr
| ----------------------------------------------------------
| Sony_RdAddr: read sector address field from disk
| Scans for address mark ($D5 $AA $96), decodes track/sector/side/checksum
| Uses IWM data register (Q6=off, Q7=off) via A4 pointer
| Returns: track in D4, sector in D5, side in D6
Sony_RdAddr:
        MOVEQ.L #0x3,D3                         | D3 = address mark byte count (3)
        MOVEQ.L #0x30,D2                        | D2 = timeout counter (48 bytes)
        MOVEQ.L #0x0,D5                         | D5 = disk data accumulator
        MOVE.L  #0xDFF9FF,A4                    | A4 = IWM data register (Q6L)
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
SONY_RDADDR_SKIP:
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_RDADDR_CONT                | busy -> skip SCC service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDADDR_CONT:
        MOVE.B  (A4),D5                         | read byte from IWM data register
        DBRA    D2,SONY_RDADDR_LOOP             | decrement timeout
        MOVEQ.L #-0x42,D0                       | noDtaMkErr (-66): no address mark found
        BRA.W   SONY_RDADDR_ERR                 | -> error exit
SONY_RDADDR_LOOP:
        BPL.B   SONY_RDADDR_SKIP                | invalid byte (bit 7 = 0) -> retry
        SUBQ.W  #0x1,D3                         | decrement byte-match counter
        BNE.B   SONY_RDADDR_SKIP                | more bytes needed -> read next
        MOVE    #0x5DC,D0                       | D0 = 1500 (post-sync byte budget)
        LEA     SONY_RDDATA_CONT_9_CONT(PC),A3  | A3 = nibble-decode table base
SONY_RDADDR_CONT_3:
        MOVE.L  A2,A0                           | A0 = sync mark pattern table
        MOVEQ.L #0x3,D1                         | D1 = 3 (3-byte sync mark)
SONY_RDADDR_NEXT:
        MOVE.B  (A4),D5                         | read byte from IWM data register
        BPL.B   SONY_RDADDR_NEXT                | bit 7 clear: not valid, keep polling
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDADDR_SKIP_2              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDADDR_SKIP_2:
        DBRA    D0,SONY_RDADDR_LOOP_2           | loop within byte budget for sync mark
        MOVEQ.L #-0x43,D0                       | D0 = -67 = noAdrMkErr (sync timeout)
        BRA.B   SONY_RDADDR_ERR                 | error exit via SONY_FIGTRKSPD_EXIT
SONY_RDADDR_LOOP_2:
        CMP.B   (A0)+,D5                        | does disk byte match expected sync?
        BNE.B   SONY_RDADDR_CONT_3              | mismatch -> restart pattern scan
        SUBQ.W  #0x1,D1                         | decrement bytes remaining in pattern
        BNE.B   SONY_RDADDR_NEXT                | more bytes needed -> read next
SONY_RDADDR_CONT_4:
        MOVE.B  (A4),D5                         | read 1st addr field byte from disk
        BPL.B   SONY_RDADDR_CONT_4              | poll until valid disk byte
        MOVE.B  0x0(A3,D5.W),D1                 | GCR decode: low 6 bits of track
        MOVE.B  D1,D4                           | D4 = running checksum XOR
        ROR     #0x6,D1                         | shift track bits to high byte for later
SONY_RDADDR_CONT_5:
        MOVE.B  (A4),D5                         | read 2nd addr field byte
        BPL.B   SONY_RDADDR_CONT_5              | poll until valid
        MOVE.B  0x0(A3,D5.W),D2                 | GCR decode: sector number
        EOR.B   D2,D4                           | accumulate into checksum
SONY_RDADDR_CONT_6:
        MOVE.B  (A4),D5                         | read 3rd addr field byte
        BPL.B   SONY_RDADDR_CONT_6              | poll until valid
        MOVE.B  0(A3,D5.W),D1                   | GCR decode: side + upper track bits
        EOR.B   D1,D4                           | D4 ^= side byte (running XOR checksum)
        ROL     #0x6,D1                         | D1 = full track/side descriptor
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDADDR_SKIP_3              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDADDR_SKIP_3:
        MOVE.B  (A4),D5                         | read 4th addr byte (format byte)
        BPL.B   SONY_RDADDR_SKIP_3              | poll until valid GCR byte
        MOVE.B  0(A3,D5.W),D3                   | D3 = decoded format byte
        EOR.B   D3,D4                           | D4 ^= format byte (running checksum)
SONY_RDADDR_CONT_7:
        MOVE.B  (A4),D5                         | read 5th addr field byte (checksum)
        BPL.B   SONY_RDADDR_CONT_7              | poll until valid
        MOVE.B  0(A3,D5.W),D5                   | GCR decode: expected checksum
        EOR.B   D5,D4                           | D4 ^= expected checksum (must = 0)
        BNE.B   SONY_RDADDR_ERR_2               | nonzero -> checksum failed
        MOVEQ.L #0x1,D4                         | D4 = 1: expect 2 trailer bytes
SONY_RDADDR_LOOP_3:
        MOVE.B  (A4),D5                         | read trailer byte from disk
        BPL.B   SONY_RDADDR_LOOP_3              | poll until valid GCR byte
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_RDADDR_SKIP_4              | SCC busy -> skip RX service
        MOVE.B  (A6),-(SP)                      | service SCC RX byte
SONY_RDADDR_SKIP_4:
        CMP.B   (A0)+,D5                        | compare trailer against $DE, $AA
        BNE.B   SONY_RDADDR_ERR_3               | mismatch -> bad bit-slip error
        DBRA    D4,SONY_RDADDR_LOOP_3           | read next trailer byte
SONY_RDADDR_ERR:
        BRA.W   SONY_FIGTRKSPD_EXIT             | return via DskRtnAdr (D0 = result)
SONY_RDADDR_ERR_2:
        MOVEQ.L #-0x45,D0                       | D0 = -69 = badCksmErr (addr cksum)
        BRA.B   SONY_RDADDR_ERR                 | return error
SONY_RDADDR_ERR_3:
        MOVEQ.L #-0x46,D0                       | D0 = -70 = badBtSlpErr (bad bit slip)
        BRA.B   SONY_RDADDR_ERR                 | return error
SONY_RDADDR_CONT_7_LOOP_CONT_2:
        ADD.L   D2,-0x5222(A2)                  | -0x5222(A2) += D2
        .short  0xAAFF                          | A-line trap $AAFF (no macro in traps.inc)
| SONY_RDADDR_CONT_7_LOOP_CONT_3 - re-enter sector-address read loop via JRdData vector
SONY_RDADDR_CONT_7_LOOP_CONT_3:
        LEA     SONY_RDADDR_CONT_7_LOOP_CONT_2(PC),A1 | A1 = post-RdData continuation
        MOVE.L  (DiskVars_JRdData).w,-(SP)      | push JRdData vector
        RTS                                     | dispatch to Sony_RdData

| ----------------------------------------------------------
| Sony_RdData: read one sector of data from disk
| Scans for data mark ($D5 $AA $AD), reads 524 bytes of GCR-encoded data
| (512 data + 12 tag bytes), decodes 6-and-2 nibbles, verifies checksum
Sony_RdData:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
        MOVEQ.L #0x30,D2                        | D2 = timeout (48 byte times)
        MOVEQ.L #0x0,D3                         | D3 = accumulator
        MOVEQ.L #-0x40,D0                       | assume nsDrvErr (-64)
        MOVE.L  #0x1FE000A,D4                   | $1FE.000A = 510 bytes data, 10 bytes tags
        MOVEQ.L #0x0,D5                         | init CkSumA
        MOVEQ.L #0x0,D6                         | init CkSumB
        MOVEQ.L #0x0,D7                         | init CkSumC
SONY_RDDATA_CONT:
        MOVE.L  A1,A2                           | A2 = data sync mark pattern table
        MOVEQ.L #0x3,D1                         | D1 = 3 (3-byte sync mark)
SONY_RDDATA_LOOP:
        MOVE.B  (A4),D3                         | D3 = previous checksum byte C
        BPL.B   SONY_RDDATA_LOOP                | invalid GCR byte -> retry
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_RDDATA_SKIP                | SCC busy -> skip RX service
        MOVE.B  (A6),-(SP)                      | store decoded tag/data byte A
SONY_RDDATA_SKIP:
        DBRA    D2,SONY_RDDATA_LOOP_2           | loop within byte budget for sync
        MOVEQ.L #-0x47,D0                       | D0 = -71 = noDtaMkErr (no data mark)
        BRA.B   SONY_RDADDR_ERR                 | error exit via FIGTRKSPD_EXIT
SONY_RDDATA_LOOP_2:
        CMP.B   (A2)+,D3                        | compare disk byte to expected sync
        BNE.B   SONY_RDDATA_CONT                | mismatch -> restart pattern scan
        SUBQ.W  #0x1,D1                         | decrement bytes remaining in pattern
        BNE.B   SONY_RDDATA_LOOP                | more bytes needed -> read next
SONY_RDDATA_CONT_2:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_CONT_2              | wait for data ready (sign bit clear)
        LEA.L   (TagData_1).w,A1                | A1 = pointer to tag data buffer
        MOVE.B  0x0(A3,D3.W),(A1)+              | convert a byte of tags. Assuming A3 is a pointer to the nibble decode table
SONY_RDDATA_CONT_3:
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_RDDATA_SKIP_2              | busy -> skip SCC service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_2:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_CONT_3              | wait for data ready (sign bit clear)
        MOVE.B  0(A3,D3.W),D1                   | GCR decode: 6-bit nibble with 2+2+2 extra bits
        ROL.B   #0x2,D1                         | rotate extra bits into position
        MOVE.B  D1,D2                           | D2 = copy for masking low bits
        AND.B   D0,D2                           | mask to low 2 bits (D0=$A=00001010)
SONY_RDDATA_CONT_4:
        MOVE.B  (A4),D3                         | read next GCR byte from disk
        BPL.B   SONY_RDDATA_CONT_4              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine decoded low 6 bits with high 2
        MOVE.B  D7,D3                           | D3 = previous checksum byte C
        ADD.B   D7,D3                           | D3 = 2*C (carry tracks overflow)
        ROL.B   #0x1,D7                         | rotate C left with carry feedback
        EOR.B   D7,D2                           | decrypt: XOR with running checksum
        MOVE.B  D2,(A1)+                        | store decoded tag/data byte A
        ADDX.B  D2,D5                           | accumulate checksum A into D5
        ROL.B   #0x2,D1                         | rotate next 2 extra bits into position
        MOVE.B  D1,D2                           | D2 = copy for masking
        AND.B   D0,D2                           | mask to low 2 bits
SONY_RDDATA_CONT_5:
        MOVE.B  (A4),D3                         | read next GCR byte from disk
        BPL.B   SONY_RDDATA_CONT_5              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine decoded low 6 with high 2
        EOR.B   D5,D2                           | decrypt: XOR with checksum D5
        MOVE.B  D2,(A1)+                        | store decoded byte B
        ADDX.B  D2,D6                           | accumulate checksum B into D6
        ROL.B   #0x2,D1                         | rotate last 2 extra bits into position
        AND.B   D0,D1                           | mask to low 2 bits
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDDATA_SKIP_3              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_3:
        MOVE.B  (A4),D3                         | read next GCR byte from disk
        BPL.B   SONY_RDDATA_SKIP_3              | poll until valid
        OR.B    0(A3,D3.W),D1                   | D1 |= 0(A3,D3.W)
        EOR.B   D6,D1                           | decrypt: XOR with checksum D6
        MOVE.B  D1,(A1)+                        | store decoded byte C
        ADDX.B  D1,D7                           | D7 += D1 (with X bit)
        SUBQ.W  #0x3,D4                         | decrement count of remaining bytes
        BPL.B   SONY_RDDATA_CONT_3              | branch if more bytes remain
        SWAP    D4                              | done with tag bytes
        TST.B   (DskVerify).w                   | verify-after-write mode?
        BEQ.B   SONY_RDDATA_SKIP_4              | no -> read data normally
        BRA.B   SONY_RDDATA_SKIP_6              | yes -> verify (compare) instead
SONY_RDDATA_LOOP_3:
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_RDDATA_SKIP_4              | SCC busy -> skip RX service
        MOVE.B  (A6),-(SP)                      | read next GCR byte
SONY_RDDATA_SKIP_4:
        MOVE.B  (A4),D3                         | read GCR byte from IWM
        BPL.B   SONY_RDDATA_LOOP_3              | invalid (bit 7 = 0) -> retry
        MOVE.B  0(A3,D3.W),D1                   | D1 = decoded 6-bit nibble
        ROL.B   #0x2,D1                         | rotate extra bits into position
        MOVE.B  D1,D2                           | D2 = copy for masking
        AND.B   D0,D2                           | D2 = high 2 bits (mask = $A=00001010)
SONY_RDDATA_CONT_6:
        MOVE.B  (A4),D3                         | read next GCR byte from IWM
        BPL.B   SONY_RDDATA_CONT_6              | poll until valid
        OR.B    0(A3,D3.W),D2                   | D2 |= 0(A3,D3.W)
        MOVE.B  D7,D3                           | D3 = previous checksum byte C
        ADD.B   D7,D3                           | compute carry from 2*C
        ROL.B   #0x1,D7                         | rotate C left with carry feedback
        EOR.B   D7,D2                           | decrypt: XOR with checksum C
        MOVE.B  D2,(A0)+                        | store decoded data byte A
        ADDX.B  D2,D5                           | D5 += D2 (with X bit)
        ROL.B   #0x2,D1                         | rotate next 2 extra bits in
        MOVE.B  D1,D2                           | D2 = copy for masking
        AND.B   D0,D2                           | D2 = high 2 bits
SONY_RDDATA_CONT_7:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_7              | poll until valid
        OR.B    0(A3,D3.W),D2                   | D2 |= 0(A3,D3.W)
        EOR.B   D5,D2                           | decrypt: XOR with checksum D5
        MOVE.B  D2,(A0)+                        | store decoded data byte B
        ADDX.B  D2,D6                           | D6 += D2 (with X bit)
        TST     D4                              | bytes remaining in sector?
        BEQ.B   SONY_RDDATA_DONE                | zero -> sector complete, check checksum
        ROL.B   #0x2,D1                         | rotate last 2 extra bits
        AND.B   D0,D1                           | mask high 2 bits
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDDATA_SKIP_5              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_5:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_SKIP_5              | poll until valid
        OR.B    0(A3,D3.W),D1                   | D1 |= 0(A3,D3.W)
        EOR.B   D6,D1                           | decrypt: XOR with checksum D6
        MOVE.B  D1,(A0)+                        | store decoded data byte C
        ADDX.B  D1,D7                           | D7 += D1 (with X bit)
        SUBQ.W  #0x3,D4                         | 3 bytes decoded per group
        BRA.B   SONY_RDDATA_LOOP_3              | loop for remaining data bytes
SONY_RDDATA_LOOP_4:
        TST.B   (A5)                            | SCC wait/request? (verify path)
        BMI.B   SONY_RDDATA_SKIP_6              | SCC busy -> skip RX service
        MOVE.B  (A6),-(SP)                      | service SCC RX byte
SONY_RDDATA_SKIP_6:
        MOVE.B  (A4),D3                         | service SCC receive data
        BPL.B   SONY_RDDATA_LOOP_4              | invalid GCR byte -> retry
        MOVE.B  0(A3,D3.W),D1                   | D1 = decoded 6-bit nibble
        ROL.B   #0x2,D1                         | rotate extra bits into position
        MOVE.B  D1,D2                           | D2 = copy for masking
        AND.B   D0,D2                           | D2 = high 2 bits (mask)
SONY_RDDATA_CONT_8:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_8              | poll until valid
        OR.B    0(A3,D3.W),D2                   | D2 |= 0(A3,D3.W)
        MOVE.B  D7,D3                           | D3 = checksum C
        ADD.B   D7,D3                           | D3 = 2*C (carry for ROL)
        ROL.B   #0x1,D7                         | rotate checksum C left with carry
        EOR.B   D7,D2                           | decrypt: XOR with checksum C
        CMP.B   (A0)+,D2                        | compare decoded byte A with buffer
        BNE.B   SONY_RDDATA_ERR                 | mismatch -> verify error
        ADDX.B  D2,D5                           | D5 += D2 (with X bit)
        ROL.B   #0x2,D1                         | rotate next 2 extra bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits
SONY_RDDATA_CONT_9:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_9              | poll until valid
        OR.B    0(A3,D3.W),D2                   | D2 |= 0(A3,D3.W)
        EOR.B   D5,D2                           | decrypt: XOR with checksum D5
        CMP.B   (A0)+,D2                        | compare decoded byte B with buffer
        BNE.B   SONY_RDDATA_SKIP_9_ERR_ERR      | mismatch -> read-verify error
        ADDX.B  D2,D6                           | D6 += D2 (with X bit)
        TST     D4                              | bytes remaining?
        BEQ.B   SONY_RDDATA_DONE                | zero -> done, check checksum
        ROL.B   #0x2,D1                         | rotate last 2 extra bits
        AND.B   D0,D1                           | mask high 2 bits
SONY_RDDATA_CONT_9_CONT:
        TST.B   (A5)                            | SCC wait/request? (verify path)
        BMI.B   SONY_RDDATA_SKIP_7              | SCC busy -> skip RX service
        MOVE.B  (A6),-(SP)                      | service SCC RX byte
SONY_RDDATA_SKIP_7:
        MOVE.B  (A4),D3                         | read checksum byte for D6
        BPL.B   SONY_RDDATA_SKIP_7              | poll until valid
        OR.B    0(A3,D3.W),D1                   | D1 |= 0(A3,D3.W)
        EOR.B   D6,D1                           | decrypt: XOR with checksum D6
        CMP.B   (A0)+,D1                        | compare verify byte C against buffer
SONY_RDDATA_ERR:
        BNE.B   SONY_RDDATA_SKIP_9_ERR_ERR      | mismatch -> read-verify error
        ADDX.B  D1,D7                           | D7 += D1 (with X bit)
        SUBQ.W  #0x3,D4                         | 3 bytes verified per group
        BRA.B   SONY_RDDATA_LOOP_4              | loop for remaining verify bytes
SONY_RDDATA_DONE:
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_RDDATA_SKIP_8              | busy -> skip SCC service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_8:
        MOVE.B  (A4),D3                         | read GCR checksum nibble byte
        BPL.B   SONY_RDDATA_SKIP_8              | poll until valid
        MOVE.B  0(A3,D3.W),D1                   | GCR decode: nibble with 4x2 cksum bits
        BMI.B   SONY_RDDATA_SKIP_9_ERR          | $FF = invalid GCR byte
        ROL.B   #0x2,D1                         | rotate first 2 checksum bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits of checksum A
SONY_RDDATA_CONT_10:
        MOVE.B  (A4),D3                         | read checksum byte for D5
        BPL.B   SONY_RDDATA_CONT_10             | poll until valid
        MOVE.B  0(A3,D3.W),D3                   | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_SKIP_9_ERR          | invalid GCR byte -> error
        OR.B    D3,D2                           | D2 |= low 6 bits (full byte)
        CMP.B   D2,D5                           | compare with accumulated D5
        BNE.B   SONY_RDDATA_SKIP_9_ERR          | mismatch -> checksum error
        ROL.B   #0x2,D1                         | rotate next 2 checksum bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits of checksum B

SONY_RDDATA_CONT_11:
        MOVE.B  (A4),D3                         | read checksum byte for D6
        BPL.B   SONY_RDDATA_CONT_11             | poll until valid
        MOVE.B  0(A3,D3.W),D3                   | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_SKIP_9_ERR          | invalid GCR byte -> error
        OR.B    D3,D2                           | D2 |= low 6 bits (full byte)
        CMP.B   D2,D6                           | compare with accumulated D6
        BNE.B   SONY_RDDATA_SKIP_9_ERR          | mismatch -> checksum error
        ROL.B   #0x2,D1                         | rotate last 2 checksum bits
        AND.B   D0,D1                           | mask high 2 bits of checksum C
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDDATA_SKIP_9              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_9:
        MOVE.B  (A4),D3                         | read checksum byte for D7
        BPL.B   SONY_RDDATA_SKIP_9              | poll until valid
        MOVE.B  0(A3,D3.W),D3                   | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_SKIP_9_ERR          | invalid GCR byte -> error
        OR.B    D3,D1                           | D1 |= low 6 bits (full byte)
        CMP.B   D1,D7                           | compare with accumulated D7
        BEQ.B   SONY_RDDATA_SKIP_9_ERR_CONT     | test the checksum
SONY_RDDATA_SKIP_9_ERR:
        MOVEQ.L #-0x48,D0                       | D0 = -72 = badCksmErr (data cksum)
        BRA.B   SONY_RDDATA_SKIP_9_ERR_CONT_2   | return error via FIGTRKSPD_EXIT
SONY_RDDATA_SKIP_9_ERR_ERR:
        MOVEQ.L #-0x44,D0                       | D0 = -68 = readVerifyErr
        BRA.B   SONY_RDDATA_SKIP_9_ERR_CONT_2   | return error via FIGTRKSPD_EXIT
SONY_RDDATA_SKIP_9_ERR_CONT:
        MOVEQ.L #0x1,D4                         | D4 = 1 (expect 2 trailer bytes)
SONY_RDDATA_SKIP_9_ERR_CONT_LOOP:
        MOVE.B  (A4),D3                         | read trailer byte from disk
        BPL.B   SONY_RDDATA_SKIP_9_ERR_CONT_LOOP | invalid GCR byte -> retry
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_RDDATA_SKIP_9_ERR_CONT_LOOP_CONT | SCC busy -> skip RX service
        MOVE.B  (A6),-(SP)                      | service SCC RX byte
SONY_RDDATA_SKIP_9_ERR_CONT_LOOP_CONT:
        CMP.B   (A2)+,D3                        | compare trailer against $DE, $AA
        BNE.B   SONY_RDDATA_ERR_4               | mismatch -> bad data bit-slip
        DBRA    D4,SONY_RDDATA_SKIP_9_ERR_CONT_LOOP | read next trailer byte
        MOVEQ.L #0x0,D0                         | noErr: data read successful
SONY_RDDATA_SKIP_9_ERR_CONT_2:
        BRA.W   SONY_FIGTRKSPD_EXIT             | return via DskRtnAdr (D0=result)

| ----------------------------------------------------------
| SONY_RDDATA_ERR_4
SONY_RDDATA_ERR_4:
        MOVEQ.L #-0x49,D0                       | error -73, bad DBtSlp, bad data mark
        BRA.B   SONY_RDDATA_SKIP_9_ERR_CONT_2   | branch
| ----------------------------------------------------------
| GCR 6-and-2 decode table (106 bytes) -- ROM $234C
| Maps each valid GCR disk byte ($96-$FF) back to its encoded 6-bit
| value (0..63). $FF entries mark invalid disk-byte values. Indexed
| by (disk_byte - $96). Only 64 of the 106 entries are valid nibble
| mappings; the rest are invalid-byte sentinels.
        .byte   0x00, 0x01, 0xFF, 0xFF, 0x02, 0x03, 0xFF, 0x04 | disk $96-$9D -> 0,1,-,-,2,3,-,4
        .byte   0x05, 0x06, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF | disk $9E-$A5 -> 5,6,-,-,-,-,-,-
        .byte   0x07, 0x08, 0xFF, 0xFF, 0xFF, 0x09, 0x0A, 0x0B | disk $A6-$AD -> 7,8,-,-,-,9,10,11
        .byte   0x0C, 0x0D, 0xFF, 0xFF, 0x0E, 0x0F, 0x10, 0x11 | disk $AE-$B5 -> 12,13,-,-,14-17
        .byte   0x12, 0x13, 0xFF, 0x14, 0x15, 0x16, 0x17, 0x18 | disk $B6-$BD -> 18,19,-,20-24
        .byte   0x19, 0x1A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF | disk $BE-$C5 -> 25,26,-,-,-,-,-,-
        .byte   0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x1B, 0xFF, 0x1C | disk $C6-$CD -> -,-,-,-,-,27,-,28
        .byte   0x1D, 0x1E, 0xFF, 0xFF, 0xFF, 0x1F, 0xFF, 0xFF | disk $CE-$D5 -> 29,30,-,-,-,31,-,-
        .byte   0x20, 0x21, 0xFF, 0x22, 0x23, 0x24, 0x25, 0x26 | disk $D6-$DD -> 32-34,-,35-38
        .byte   0x27, 0x28, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x29 | disk $DE-$E5 -> 39,40,-,-,-,-,-,41
        .byte   0x2A, 0x2B, 0xFF, 0x2C, 0x2D, 0x2E, 0x2F, 0x30 | disk $E6-$ED -> 42,43,-,44-48
        .byte   0x31, 0x32, 0xFF, 0xFF, 0x33, 0x34, 0x35, 0x36 | disk $EE-$F5 -> 49,50,-,-,51-54
        .byte   0x37, 0x38, 0xFF, 0x39, 0x3A, 0x3B, 0x3C, 0x3D | disk $F6-$FD -> 55,56,-,57-61
        .byte   0x3E, 0x3F                      | disk $FE-$FF -> 62,63
| ----------------------------------------------------------
| Disk self-sync + data mark prefix (8 bytes) -- ROM $23B6
| Written ahead of each sector: 4 sync-gap bytes ($FF $3F $CF $F3 $FC $FF)
| then the 2-byte data-address-mark prefix ($D5 $AA). The third mark byte
| ($AD for data, $96 for address) is written by the caller.
SONY_RDDATA_CONT_14:
        .byte   0xFF, 0x3F, 0xCF, 0xF3          | self-sync FF + gap nibbles
        .byte   0xFC, 0xFF                      | gap nibble + self-sync FF
        .byte   0xD5, 0xAA                      | data-mark header (D5 AA)
| SONY_RDDATA_CONT_14_CONT - resume data-write phase: dispatch to JWrData vector
SONY_RDDATA_CONT_14_CONT:
        LEA     SONY_RDDATA_CONT_14(PC),A2      | A2 = sync+data-mark prefix table
        MOVE.L  (DiskVars_JWrData).w,-(SP)      | push JWrData vector
        RTS                                     | dispatch to Sony_WrData

| ----------------------------------------------------------
| Sony WrData
Sony_WrData:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address as continuation
        LEA.L   (TagData_1).w,A1                | A1 = source: 12-byte tag data
        MOVE.L  #0x2010009,D4                   | D4.hi=$201 (513 data), D4.lo=9 (+3=12 tag bytes)
        MOVEQ.L #0x0,D2                         | clear checksum/data register B
        MOVEQ.L #0x0,D3                         | clear nibble accumulator
        MOVE.L  #IWM_Q6H,A3                     | A3 = IWM Q6H (write data register)
        TST.B   (A3)                            | Q6 on: prepare for write mode
        MOVEQ.L #0x6,D0                         | D0 = 6: write 7 sync/header bytes
        MOVEQ.L #0x0,D5                         | clear checksum register A
        MOVE.B  (A2)+,(IWM_Q7H).l               | Q7 on + write $FF: enter write mode
        MOVEQ.L #0x0,D6                         | clear checksum register B
        MOVEQ.L #0x0,D7                         | clear checksum register C
SONY_WRDATA_LOOP:
        MOVE.B  (A2)+,D1                        | D1 = next sync/header byte
SONY_WRDATA_NO:
        TST.B   (A4)                            | IWM handshake: ready for next byte?
        BPL.B   SONY_WRDATA_NO                  | no -> wait for IWM
        MOVE.B  D1,(A3)                         | write sync/header byte to disk
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_WRDATA_SKIP                | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_WRDATA_SKIP:
        SUBQ.W  #0x1,D0                         | decrement header byte counter
        BNE.B   SONY_WRDATA_LOOP                | more header bytes -> loop
        MOVE.B  (A2)+,D1                        | D1 = $AA: data mark byte
        LEA     DT_Sony_NiblTbl(PC),A2          | A2 = GCR encode table (64 entries)
SONY_WRDATA_NO_2:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_2                | IWM not ready -> wait
        MOVE.B  D1,(A3)                         | write $AA data mark to disk
        MOVEQ.L #0xB,D1                         | D1 = $0B: initial nibble value
        MOVE.B  (A1)+,D2                        | D2 = first tag byte
        BRA.B   SONY_WRDATA_LOOP_2              | enter GCR encode loop
SONY_WRDATA_CONT:
        MOVE.L  A0,A1                           | A1 = data buffer pointer for GCR encode
SONY_WRDATA_NEXT:
        ADDX.B  D2,D7                           | accumulate byte C into checksum D7
        EOR.B   D6,D2                           | encrypt byte C: XOR with checksum D6
        MOVE.B  D2,D3                           | D3 = encrypted byte C
        LSR     #0x6,D3                         | extract high 2 bits into D3
SONY_WRDATA_NO_3:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_3                | IWM not ready -> wait
        MOVE.B  0x0(A2,D3.W),(A3)               | GCR encode high 2 bits of C
        SUBQ.W  #0x3,D4                         | 3 bytes encoded per group
        MOVE.B  D7,D3                           | D3 = checksum C
        ADD.B   D7,D3                           | D3 = 2*C (carry for ROL)
        ROL.B   #0x1,D7                         | rotate checksum C left with carry
        ANDI.B  #0x3F,D0                        | mask byte A to low 6 bits
SONY_WRDATA_NO_4:
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_WRDATA_SKIP_2              | SCC busy -> skip RX service
        MOVE.B  (A6),-(SP)                      | service SCC RX byte
SONY_WRDATA_SKIP_2:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_4                | no -> wait
        MOVE.B  0(A2,D0.W),(A3)                 | GCR encode final high-bits nibble
SONY_WRDATA_LOOP_2:
        MOVE.B  (A1)+,D0                        | D0 = next source byte (A)
        ADDX.B  D0,D5                           | accumulate byte A into checksum D5
        EOR.B   D7,D0                           | encrypt byte A: XOR with checksum D7
        MOVE.B  D0,D3                           | save encrypted A for high bits
        ROL     #0x2,D3                         | rotate 2 high bits into D3
        ANDI.B  #0x3F,D1                        | mask byte B to low 6 bits
SONY_WRDATA_NO_5:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_5                | IWM not ready -> wait
        MOVE.B  0x0(A2,D1.W),(A3)               | GCR encode low 6 bits of byte B
        MOVE.B  (A1)+,D1                        | D1 = next source byte (B)
        ADDX.B  D1,D6                           | accumulate byte B into checksum D6
        EOR.B   D5,D1                           | encrypt byte B: XOR with checksum D5
        MOVE.B  D1,D3                           | save encrypted B for high bits
        ROL     #0x2,D3                         | rotate 2 more high bits into D3
        ANDI.B  #0x3F,D2                        | mask byte C to low 6 bits
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_WRDATA_SKIP_3              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_WRDATA_SKIP_3:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_SKIP_3              | IWM not ready -> wait
        MOVE.B  0(A2,D2.W),(A3)                 | GCR encode low 6 bits of byte C
        MOVE.B  (A1)+,D2                        | D2 = next source byte (C)
        TST     D4                              | bytes remaining in segment?
        BNE.B   SONY_WRDATA_NEXT                | yes -> encode next group
        SWAP    D4                              | swap halves of switch from tags to data count
        BNE.B   SONY_WRDATA_CONT                | nonzero -> start data section
        CLR.B   D3                              | clear D3 low byte for final nibble
        LSR     #0x6,D3                         | extract last high 2 bits
SONY_WRDATA_NO_6:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_6                | no -> wait
        MOVE.B  0x0(A2,D3.W),(A3)               | GCR encode final high-bits nibble
        MOVE.B  D5,D3                           | build checksum nibble: D5 high 2 bits
        ROL     #0x2,D3                         | rotate D5 bits into position
        MOVE.B  D6,D3                           | OR in D6 high 2 bits
        ROL     #0x2,D3                         | D3 = {D5[7:6], D6[7:6], D7[7:6]}
        ANDI.B  #0x3F,D0                        | mask checksum A low 6 bits
SONY_WRDATA_NO_7:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_7                | IWM not ready -> wait
        MOVE.B  0x0(A2,D0.W),(A3)               | GCR encode checksum A low 6
        ANDI.B  #0x3F,D1                        | mask checksum B low 6 bits
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_WRDATA_SKIP_4              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_WRDATA_SKIP_4:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_SKIP_4              | IWM not ready -> wait
        MOVE.B  0x0(A2,D1.W),(A3)               | GCR encode checksum B low 6
        MOVE.B  D7,D3                           | D3 = checksum C
        LSR     #0x6,D3                         | extract high 2 bits of checksum C
SONY_WRDATA_NO_8:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_8                | IWM not ready -> wait
        MOVE.B  0(A2,D3.W),(A3)                 | GCR encode high 2 bits of cksums
        ANDI.B  #0x3F,D5                        | mask checksum A to low 6 bits
SONY_WRDATA_NO_9:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_9                | IWM not ready -> wait
        MOVE.B  0(A2,D5.W),(A3)                 | GCR encode checksum A low 6
        ANDI.B  #0x3F,D6                        | mask checksum B to low 6 bits
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_WRDATA_SKIP_5              | SCC busy -> skip RX service
        MOVE.B  (A6),-(SP)                      | service SCC RX byte
SONY_WRDATA_SKIP_5:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_SKIP_5              | IWM not ready -> wait
        MOVE.B  0(A2,D6.W),(A3)                 | GCR encode checksum B low 6
        ANDI.B  #0x3F,D7                        | mask checksum C to low 6 bits
SONY_WRDATA_NO_10:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_10               | IWM not ready -> wait
        MOVE.B  0(A2,D7.W),(A3)                 | GCR encode checksum D7 low 6
        LEA     SONY_WRDATA_CONT_2(PC),A2       | A2 = data field trailer ($DE $AA $FF $FF)
        MOVEQ.L #0x3,D2                         | D2 = 3: write 4 trailer bytes
SONY_WRDATA_LOOP_3:
        MOVE.B  (A4),D1                         | read IWM handshake for write timing
        BPL.B   SONY_WRDATA_LOOP_3              | poll until ready
        MOVE.B  (A2)+,(A3)                      | write next trailer byte to disk
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_WRDATA_SKIP_6              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_WRDATA_SKIP_6:
        DBRA    D2,SONY_WRDATA_LOOP_3           | loop for all 4 trailer bytes
        MOVEQ.L #0x0,D0                         | assume noErr
        BTST    #0x6,D1                         | IWM bit 6: write completed OK?
        BNE.B   SONY_WRDATA_OK                  | bit 6 set -> write OK
        MOVEQ.L #-0x4A,D0                       | wrUnderrun (-74): write underrun
SONY_WRDATA_OK:
        TST.B  (0xDFFDFF).l                     | test byte at absolute
        BRA.W   SONY_FIGTRKSPD_EXIT             | return via DskRtnAdr (D0=result)
SONY_WRDATA_CONT_2:
        ADD.L   -1(A2),D7                       | fall-through pad data: $DEAA $FFFF
| ----------------------------------------------------------
| DT_Sony_NiblTbl -- GCR 6-and-2 encode table (64 bytes) @ ROM $2512
| Maps each 6-bit data value (0..63) to its disk byte ($96..$FF).
| Inverse of the decode table at $234C. Only 64 of the 106 byte values
| in the $96..$FF range are valid encodings; unused values (like $98,
| $99, $A0..$A5) are skipped. Indexed by 6-bit data value.
DT_Sony_NiblTbl:
        .byte   0x96, 0x97, 0x9A, 0x9B          | values 0-3
        .byte   0x9D, 0x9E, 0x9F, 0xA6          | values 4-7
        .byte   0xA7, 0xAB, 0xAC, 0xAD          | values 8-11
        .byte   0xAE, 0xAF, 0xB2, 0xB3          | values 12-15
        .byte   0xB4, 0xB5, 0xB6, 0xB7          | values 16-19
        .byte   0xB9, 0xBA, 0xBB, 0xBC          | values 20-23
        .byte   0xBD, 0xBE, 0xBF, 0xCB          | values 24-27
        .byte   0xCD, 0xCE, 0xCF, 0xD3          | values 28-31
        .byte   0xD6, 0xD7, 0xD9, 0xDA          | values 32-35
        .byte   0xDB, 0xDC, 0xDD, 0xDE          | values 36-39
        .byte   0xDF, 0xE5, 0xE6, 0xE7          | values 40-43
        .byte   0xE9, 0xEA, 0xEB, 0xEC          | values 44-47
        .byte   0xED, 0xEE, 0xEF, 0xF2          | values 48-51
        .byte   0xF3, 0xF4, 0xF5, 0xF6          | values 52-55
        .byte   0xF7, 0xF9, 0xFA, 0xFB          | values 56-59
        .byte   0xFC, 0xFD, 0xFE, 0xFF          | values 60-63
