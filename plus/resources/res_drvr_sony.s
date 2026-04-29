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
| DRVR header -- Device Manager driver resource header
  .short 0x4F00                                 | drvrFlags: dNeedLock+dNeedTime+dNeedGoodBye+dStatEnable+dCtlEnable+dWritEnable+dReadEnable
  .short 0x0000                                 | drvrDelay: no periodic action
  .short 0x0000                                 | drvrEMask: no event mask
  .short 0x0000                                 | drvrMenu: no menu
  .short 0x006E                                 | drvrOpen: offset to E_Sony_Open
  .short 0x033A                                 | drvrPrime: offset to E_Sony_Prime
  .short 0x01E2                                 | drvrCtl: offset to E_Sony_Control
  .short 0x02EC                                 | drvrStatus: offset to E_Sony_Status
  .short 0x0018                                 | drvrClose: offset to E_Sony_Close
  .byte 0x05                                    | drvrName length = 5

| Name
  .ascii ".Sony"                                | drvrName: driver name string

| end of Name
| -------------------------------------------------------
| DiskClose -- close routine (returns closErr, not closable)
| Called during boot.
E_Sony_Close:
        MOVEQ.L #-0x18,D0                       | closErr: driver not closeable
        RTS                                     | return error to Device Manager

| InitDskTbl -- offset table for jump vector initialization
| Each word is a PC-relative offset from SETSPEED to a routine entry point.
| 15 vectors: FigTrkSpd, DiskPrime, RdAddr, RdData, WrData, Seek,
| SetUpPoll, Recal, Control, WakeUp, ReSeek, MakeSpdTbl, AdrDisk,
| SetSpeed (RTS = no PWM), NiblTbl
| Called during boot.
SETSPEED:
  .byte  0x0D,0x44,0x03,0x24,0x0E,0xD6          | FigTrkSpd, DiskPrime, RdAddr offsets
  .byte 0x0F,0x9C,0x11,0xF4,0x09,0xDA           | RdData, WrData, Seek offsets
  .byte 0x0E,0x9E,0x0B,0x0C,0x01,0xCC           | SetUpPoll, Recal, Control offsets
  .byte 0x0A,0x8E,0x05,0x96,0x0C,0x9E           | WakeUp, ReSeek, MakeSpdTbl offsets
  .byte 0x08,0x78,0x09,0x00,0x13,0x3E           | AdrDisk, SetSpeed, NiblTbl offsets

| InitDsk2 -- 3 more vectors: DiskSel, SendCmd, DCDReset
  .byte 0x0B,0xE8,0x19,0x66,0x1F,0x20           | DiskSel, SendCmd, DCDReset offsets
| InitParams -- tuneable drive constants (32 bytes)
| ReadErrInit/Cnt, RecalInit/Cnt, WrgSectInit/Cnt, BadSpdInit/Cnt,
| Command, HeadSettle, SpdChgTime, PwrOnTime, PwrOffTime, SeekTime,
| SectTime, DskVBLTime, EjectTime, CkDelta, EjectWait
INITPARAMS:
  .byte  0x08,0x00,0x02,0x00,0x40,0x00          | ReadErr=8, RecalInit=2, WrgSect=64
  .byte 0x08,0x00,0x00,0x00,0x01,0x2C           | BadSpd=8, Command=0, HeadSettle=300
  .byte 0x05,0xDC,0x0F,0xA0,0x00,0x05           | SpdChgTime=1500, PwrOnTime=4000, PwrOff=5
  .byte 0x00,0x78,0x00,0x64,0x00,0x1E           | SeekTime=120, SectTime=100, DskVBLTime=30
  .byte 0x1D,0x4C,0x00,0x00,0x38,0x40           | EjectTime=7500, CkDelta=0x3840 (14400)
  .byte 0xFC,0x00                               | EjectWait=-4 ($FC), pad byte
| -------------------------------------------------------
| DispSetUp -- convert word offsets to absolute addresses
| A0: pointer to word offset table (advanced)
| A1: pointer to jump vector destination (advanced)
| D0: base address of offset table
| D1: number of entries minus 1
DISPSETUP:
        MOVEQ.L #0x0,D2                         | clear high word for 32-bit add
        MOVE    (A0)+,D2                        | get next word offset from table
        ADD.L   D0,D2                           | compute absolute address = base + offset
        MOVE.L  D2,(A1)+                        | store vector in jump table
        DBF     D1,DISPSETUP                    | loop for all entries
        RTS                                     | return to caller

| ========================================================================
|
| DiskOpen -- Sony driver initialization
|
| Allocates SonyVars ($310 bytes), initializes all disk I/O jump
| vectors, tuneable drive constants, VBL task for power-down and
| disk-in-place sensing, Time Manager queue element, and probes
| for connected drives. Installs drive queue entries via _AddDrive.
|
| Called during boot with A1 = pointer to DCE (device control entry).
| ========================================================================
E_Sony_Open:
        MOVE.L  #0x310,D0                       | DiskVarLth: size of SonyVars
        _NewPtrSysClear                         | allocate zeroed system heap block
        MOVE.L  A0,(SonyVars).w                 | store SonyVars ptr in low memory
        MOVE.L  A1,(A0)                         | DiskUnitPtr: save DCE ptr at offset 0
        MOVE.L  (UTableBase).w,A2               | unit table base
        MOVE.L  0x10(A2),0x4(A2)                | copy unit 4 entry to unit 1 (alias .Sony)
        MOVE.B  #0x1,0x7(A1)                    | set driver version = 1 in DCE
        ST.B    0x19(A0)                        | Active: mark driver active (exclude VBL)
        MOVE.L  A0,A2                           | A2 = SonyVars for later use
| initialize the disk routine jump table (15 vectors)
        LEA.L   SETSPEED(PC),A0                 | point to InitDskTbl offset table
        LEA.L   (DiskVars_JFigTrkSpd).w,A1      | first jump table entry
        MOVEQ.L #0xE,D1                         | 15 vectors (0..14)
        MOVE.L  A0,D0                           | base address for offset computation
        BSR.B   DISPSETUP                       | DispSetUp: convert to absolute addrs
        LEA.L   (JDiskSel).w,A1                 | second table: DiskSel, SendCmd, DCDReset
        MOVEQ.L #0x2,D1                         | 3 more vectors
        BSR.B   DISPSETUP                       | install them
        ST.B    0x18(A2)                        | OneToOne: set 1:1 flag (legacy, unused)
| copy tuneable drive constants (32 bytes) into SonyVars
        LEA.L   0x2A(A2),A1                     | dest: ReadErrInit(A2)
        LEA.L   INITPARAMS(PC),A0               | source: InitParams table
        MOVEQ.L #0x20,D0                        | 32 bytes to copy
        _BlockMove                              | copy drive constants
| allocate VBL task for power-down and disk-in-place sensing
        LEA.L   0x4(A2),A0                      | DiskQVE(A2): VBL task control block
        MOVE    #0x1,0x4(A0)                    | QType = VType (VBL task)
        LEA.L   Sony_CheckForNewDisks(PC),A1    | address of VBL task routine
        MOVE.L  A1,0x6(A0)                      | VBLAddr: set task entry point
        MOVE    #0x1E,0xA(A0)                   | VBLCount = 30 ticks (~0.5 sec)
        _VInstall                               | install into vertical retrace queue
| install Time Manager queue element for wakeup timing
        LEA.L   0x118(A2),A0                    | TimeQEl(A2): time queue element
        _InsTime                                | register with Time Manager
| check pass-thru on external connector (DCD detection)
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        MOVE    #0x7,TwoSideFmt(A1)             | Drive = 7: probe ext chain limit
        BSR     Sony_JumpDiskSel                | select interface for drive 7
        BSR     SONY_WRITEDRIVEREG_CONT         | check if DCD responds on ext port
        SPL.B   0xFC(A1)                        | PassThru: 0=works, $FF=no pass-thru
| probe drives 1..6, install drive queue entries
        MOVEQ.L #0x1,D2                         | D2 = physical drive number, start at 1
E_SONY_OPEN_LOOP:
        MOVE    D2,TwoSideFmt(A1)               | Drive: set current drive number
        BSR     Sony_SetupRegs                  | set up IWM/VIA base addrs, get D1
        ST.B    0x4(A1,D1.W)                    | Installed = $FF (assume not installed)
        CMPI    #0x3,D2                         | drives 1-2 = floppy, 3+ = DCD
        BLE.B   E_SONY_OPEN_CONT                | floppy probe for drives 1-2
        TST.B   0xFC(A1)                        | PassThru: can we see external DCD?
        BMI.B   E_SONY_OPEN_SKIP                | no pass-thru: skip this DCD drive
E_SONY_OPEN_CONT:
        BSR     Sony_JumpDiskSel                | select the drive interface
        CMPI    #0x3,D2                         | DCD drive (3+)?
        BLT.B   CHKCONNECT                      | branch to floppy sense for drives 1-2
        BSR     SONY_WRITEDRIVEREG_CONT         | probe DCD: check exist/sides
        BMI.B   E_SONY_OPEN_SKIP                | not connected, skip
        MOVE    #0x1,0xA(A1,D1.W)               | SpdAdjCnt: mark DCD present
        MOVEQ.L #-0x2,D3                        | refnum -2 for DCD driver
        BRA.B   E_SONY_OPEN_CONT_2              | go install drive queue entry

| -------------------------------------------------------
| ChkConnect (floppy) -- sense floppy drive attributes
| Called during boot.
CHKCONNECT:
        MOVEQ.L #0xD,D0                         | DrvExstAdr: check drive-exists sense
        BSR     Sony_ReadDriveRegAdr            | sense=0 when drive is connected
        BMI.B   E_SONY_OPEN_SKIP                | not connected, skip this drive
        MOVEQ.L #0x9,D0                         | SidesAdr: sense number of sides
        BSR     Sony_ReadDriveRegAdr            | 0=single-sided, 1=double-sided
        SMI.B   0x5(A1,D1.W)                    | Sides: $FF=two-sided drive
        MOVEQ.L #0xF,D0                         | NewIntfAdr: check new interface
        BSR     Sony_ReadDriveRegAdr            | 1=new interface (ready handshake)
        SMI.B   0x13(A1,D1.W)                   | NewIntf: $FF=new interface
        MOVEQ.L #-0x5,D3                        | SonyRfN: refnum -5 for Sony driver
E_SONY_OPEN_CONT_2:
        MOVE.B  #0x1,0x4(A1,D1.W)               | Installed = 1 (drive is installed)
        MOVE    D2,D0                           | physical drive number in high word
        SWAP    D0                              | D0.hi = drive number
        MOVE    D3,D0                           | D0.lo = driver refnum
        LEA.L   0x6(A1,D1.W),A0                 | DQEL: drive queue element for this drive
        _AddDrive                               | add to system drive queue
E_SONY_OPEN_SKIP:
        ADDQ.W  #0x1,D2                         | next physical drive number
        CMPI    #0x6,D2                         | max 6 drives (2 floppy + 4 DCD)
        BLE.B   E_SONY_OPEN_LOOP                | loop for all drives
| install grow zone procedure to free track cache if memory runs low
        MOVE.L  (SysZone).w,A2                  | get system zone pointer
        LEA.L   E_SONY_OPEN_CONT_3(PC),A0       | our GZ proc address
        MOVE.L  0x10(A2),0x124(A1)              | NextGZProc: save old GZ proc
        MOVE.L  A0,0x10(A2)                     | install our GZ proc in zone header
        CLR.B   0x19(A1)                        | Active: clear driver active flag
        MOVEQ.L #0x0,D0                         | return noErr
        RTS                                     | return to Device Manager

| -------------------------------------------------------
| Grow zone procedure -- frees track cache buffer when
| Memory Manager needs space in system zone.
| Chains to previous GZ proc if one existed.
E_SONY_OPEN_CONT_3:
        MOVE.L  (SonyVars).w,A1                 | get SonyVars pointer
        BSR.B   E_SONY_OPEN_CONT_4              | TCdispose: free track cache buffer
        BNE.B   E_SONY_OPEN_EXIT                | freed memory, return size
        MOVE.L  0x124(A1),D1                    | NextGZProc: chain to old GZ proc
        BEQ.B   E_SONY_OPEN_EXIT                | no previous proc, return 0
        MOVE.L  D1,A0                           | load previous GZ proc address
        JMP     (A0)                            | tail-call previous GZ proc

| GZ proc return -- delivers freed size to Memory Manager
E_SONY_OPEN_EXIT:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x4,SP                         | discard GZ proc parameter
        MOVE.L  D0,(SP)                         | return freed size to caller
        JMP     (A0)                            | return to Memory Manager

| -------------------------------------------------------
| TCdispose -- dispose track cache buffer
| Returns freed size in D0 (0 if no buffer existed).
E_SONY_OPEN_CONT_4:
        CLR.L   -(SP)                           | push 0: assume no space freed
        MOVE.L  0x10A(A1),D0                    | TCBuffer: get track cache ptr
        BEQ.B   E_SONY_OPEN_EXIT_2              | no buffer allocated, return 0
        MOVE.L  D0,A0                           | A0 = buffer pointer for _GetPtrSize
        _GetPtrSize                             | D0 = size of track cache buffer
        MOVE.L  D0,(SP)                         | save freed size on stack
        _DisposePtr                             | free the buffer
        CLR.L   0x10A(A1)                       | TCBuffer = nil
        CLR.B   0x101(A1)                       | TCInstalled = false
E_SONY_OPEN_EXIT_2:
        MOVE.L  (SP)+,D0                        | D0 = space freed (or 0)
        RTS                                     | return to GZ proc or TCdispose caller

| -------------------------------------------------------
| DiskCtlErr/DiskDone -- I/O completion
|
| Stores error code in DskErr for debugging, clears Active
| flag, reloads DCE pointer, and dispatches through JIODone.
| D0: result code (0 = success)
E_SONY_OPEN_CONT_5:
        CLR.B   0x3(A1,D1.W)                    | DiskInPlace = 0 (no disk)
Sony_ReturnErrUnimplementedControl:
        MOVEQ.L #-0x11,D0                       | controlErr: unsupported control call
| Called by: SONY_CONTROL_NO_2, SONY_EJECTORSWITCHDISK_EXIT_2, E_SONY_STATUS_LOOP, SONY_DISKPRIME_ERR_4, DT_SONY_NIBLTBL_ERR_13
Sony_ReturnResult:
        TST     D0                              | error?
        BEQ.B   SONY_RETURNRESULT_CONT          | branch if noErr
        MOVE    D0,(DskErr).w                   | save last error for debugging
SONY_RETURNRESULT_CONT:
        MOVE.L  (SonyVars).w,A1                 | get SonyVars pointer
        CLR.B   0x19(A1)                        | Active = false (allow VBL task)
        MOVE.L  (A1),A1                         | A1 = DCE pointer (DiskUnitPtr)
        MOVE.L  (JIODone).w,-(SP)               | push JIODone vector
        RTS                                     | dispatch to IODone

| -------------------------------------------------------
| Control/status dispatch table
| Each entry: csCode word, status handler offset, control handler offset
| relative to CODES. Terminated by 0x0000.
| Codes: 7=Eject, 6=Format, 5=Verify, 21=PhysIcon
CODES:
  .byte  0x00,0x07,0xFF,0xE2,0x00,0xC6          | csCode 7 (Eject): status=-30, ctl=+198
  .byte 0x00,0x06,0x1D,0xF8,0x11,0xEE           | csCode 6 (Format): status=+7672, ctl=+4590
  .byte 0x00,0x05,0x1D,0xF4,0x14,0xD6           | csCode 5 (Verify): status=+7668, ctl=+5334
  .byte 0x00,0x15,0x1D,0xDE,0xFF,0xE6           | csCode 21 (PhysIcon): status=+7646, ctl=-26
  .byte 0x00,0x00                               | terminator: end of dispatch table

| -------------------------------------------------------
| DiskControl -- dispatch through JControl vector
E_Sony_Control:
        MOVE.L  (DiskVars_JControl).w,-(SP)     | push control vector
        RTS                                     | dispatch to jtControl

| -------------------------------------------------------
| jtControl -- control call dispatcher
|
| Dispatches control calls by csCode. Pre-checks drive
| number validity. A0 = parameter block from caller.
| csCode 1: KillIO (returns -1, not supported)
| csCode 5: Verify csCode 6: Format
| csCode 7: Eject csCode 8: Set tag buffer
| csCode 9: Track cache control
| csCode 21: Get physical drive icon
Sony_Control:
        MOVE    0x1A(A0),D0                     | CSCode: get the control opcode
        CMPI    #0x1,D0                         | KillIO?
        BNE.B   SONY_CONTROL_NO                 | no, check other opcodes
        MOVEQ.L #-0x1,D0                        | KillIO not supported, return -1
        RTS                                     | return error to caller

| ctlTagBuf -- set tag buffer pointer (csCode 8)
| No drive number required.
SONY_CONTROL_NO:
        MOVE.L  (SonyVars).w,A1                 | get SonyVars pointer
        CMPI    #0x8,D0                         | tagBufCC: set tag buffer?
        BNE.B   SONY_CONTROL_NEXT               | no, try next opcode
        MOVE.L  0x1C(A0),0xF4(A1)               | TagBufPtr = CSParam (ptr or 0)
        BRA     SONY_EJECTORSWITCHDISK_EXIT_2   | return noErr

| ----------------------------------------------------------
|
| SONY_CONTROL_NEXT
|
| ctlTCCtrl -- track cache control (csCode 9)
| CSParam byte 0: enable/disable flag, byte 1: allocate/dispose
SONY_CONTROL_NEXT:
        CMPI    #0x9,D0                         | trackCacheCC: track cache control?
        BNE.B   SONY_CONTROL_NO_2               | no, try dispatch table
        ADDA    #0x1C,A0                        | A0 -> CSParam in param block
        MOVE.B  (A0)+,D1                        | D1 = enable/disable flag
        MOVE.B  (A0)+,D0                        | D0 = allocate(+)/dispose(-)/query(0)
        BEQ.B   SONY_CONTROL_ERR                | zero: just update TCInstalled flag
        BPL.B   SONY_CONTROL_CONT               | positive: allocate track cache
        BSR     E_SONY_OPEN_CONT_4              | negative: dispose track cache
        BRA.B   SONY_CONTROL_ERR                | update TCInstalled flag

| ctlTCAlloc -- allocate track cache buffer if not present
SONY_CONTROL_CONT:
        TST.L   0x10A(A1)                       | TCBuffer: already allocated?
        BNE.B   SONY_CONTROL_ERR                | yes, skip allocation
        CMPI    #0x2,(MemTop).w                 | enough memory? (at least 128K)
        BLE.B   SONY_CONTROL_ERR                | too little RAM, skip
        MOVE.L  #0x1890,D0                      | $1890 = 6288 bytes (12 sectors * 524)
        _NewPtrSysClear                         | allocate zeroed track cache
        BNE.B   SONY_CONTROL_ERR                | allocation failed, skip
        MOVE.L  A0,0x10A(A1)                    | TCBuffer: store buffer pointer
        CLR     0x102(A1)                       | TCDrive: clear cached drive number
SONY_CONTROL_ERR:
        TST.L   0x10A(A1)                       | TCBuffer: cache allocated?
        SNE.B   0x101(A1)                       | TCInstalled: $FF if buffer exists
        BEQ.B   SONY_CONTROL_DONE               | no buffer, done
        TST.B   D1                              | caller wants cache enabled?
        SNE.B   0x101(A1)                       | TCInstalled: $FF=enabled, 0=disabled
SONY_CONTROL_DONE:
        BRA     SONY_EJECTORSWITCHDISK_EXIT_2   | return noErr

| ctlOther -- remaining control codes (5/6/7/21) via dispatch table
SONY_CONTROL_NO_2:
        MOVE    D0,D2                           | D2 = control code for table lookup
        BSR     Sony_ChooseDriveFromPB          | select drive, set up SonyVars
        BNE     Sony_ReturnResult               | invalid drive -> return error
        TST.B   0x4(A1,D1.W)                    | Installed: drive connected?
        BPL.B   SONY_CONTROL_OK                 | yes -> dispatch via table
        MOVEQ.L #-0x40,D0                       | noDrvErr: drive isn't connected
        BRA     Sony_ReturnResult               | return error

| ctlDispatch -- scan control/status table for matching csCode
SONY_CONTROL_OK:
        LEA.L   CODES(PC),A3                    | A3 = base of dispatch table
        MOVE.L  A3,A4                           | A4 = scan pointer
SONY_CONTROL_NEXT_2:
        MOVE    (A4)+,D4                        | D4 = csCode from table entry
        BEQ     Sony_ReturnErrUnimplementedControl | end of table: unimplemented
        CMP     D4,D2                           | matches requested csCode?
        BEQ.B   SONY_CONTROL_OK_2               | yes -> dispatch
        ADDQ.W  #0x4,A4                         | skip status/control offset pair
        BRA.B   SONY_CONTROL_NEXT_2             | check next entry

| ctlJump -- choose floppy or DCD handler offset
SONY_CONTROL_OK_2:
        CMPI    #0x2,TwoSideFmt(A1)             | drive number: floppy (1-2)?
        BGT.B   SONY_CONTROL_CONT_2             | DCD drive -> use status offset
        ADDQ.W  #0x2,A4                         | floppy -> skip to control offset
SONY_CONTROL_CONT_2:
        ADDA    (A4),A3                         | A3 = handler address (base + offset)
        JMP     (A3)                            | jump to control handler

| ----------------------------------------------------------
|
| Sony EjectOrSwitchDisk
|
Sony_EjectOrSwitchDisk:
        BSR     Sony_CheckDriveNumber           | invalidate track cache for this drive
        MOVEQ.L #0x0,D0                         | immediate power-off (no delay)
        BSR     Sony_MotorOff                   | stop drive motor
        BSR     Sony_JumpDiskSel                | select this drive's interface
        MOVE    #0x7D0,D0                       | wait 200ms for motor spin-down
        BSR     E_Sony_WakeUp                   | continue below after timer delay
        MOVEQ.L #0xD,D0                         | EJECT register address
        BSR     Sony_AdrDisk                    | write EJECT: pulse eject solenoid
        TST.B   0xE00(A0)                       | LSTRB on: latch eject strobe
        TST.B   0x13(A1,D1.W)                   | NewIntf: new-style interface?
        BMI.B   SONY_EJECTORSWITCHDISK_OK       | yes -> wait for disk replacement
        MOVE    0x42(A1),D0                     | EjectTime: delay for solenoid travel
        BSR     E_Sony_WakeUp                   | continue below after timer delay
        TST.B   0xC00(A0)                       | LSTRB off: release eject strobe
SONY_EJECTORSWITCHDISK_EXIT:
        MOVE.B  0x48(A1),0x3(A1,D1.W)           | DiskInPlace = EjectWait sentinel
SONY_EJECTORSWITCHDISK_EXIT_2:
        MOVEQ.L #0x0,D0                         | noErr
        BRA     Sony_ReturnResult               | return success

| SONY_EJECTORSWITCHDISK_OK -- new interface eject: wait for disk replacement
SONY_EJECTORSWITCHDISK_OK:
        TST.B   0xC00(A0)                       | LSTRB off: release eject strobe
        MOVEQ.L #0xF,D3                         | D3 = retry count (16 attempts)
SONY_EJECTORSWITCHDISK_LOOP:
        MOVE    #0x3E8,D0                       | wait 100ms between polls
        BSR     E_Sony_WakeUp                   | delay via Time Manager
        MOVEQ.L #0x2,D0                         | CSTIN sense register
        BSR     Sony_ReadDriveRegAdr            | read CSTIN, 0 = disk inserted
        DBMI    D3,SONY_EJECTORSWITCHDISK_LOOP  | loop until disk inserted or timeout
        MOVEQ.L #0xA,D0                         | 1ms settling delay
        BSR     E_Sony_WakeUp                   | wait for disk to seat
        BRA.B   SONY_EJECTORSWITCHDISK_EXIT     | set DiskInPlace and return noErr

| -------------------------------------------------------
| DiskStatus -- return drive status (csCode 8 only)
| Copies 22 bytes of per-drive status into CSParam area.
E_Sony_Status:
        MOVEQ.L #-0x12,D0                       | statusErr: assume unsupported
        CMPI    #0x8,0x1A(A0)                   | csCode == 8 (drvStsCC)?
        BNE     Sony_ReturnResult               | no -> return statusErr
        BSR.B   Sony_ChooseDriveFromPB          | select drive from ioVRefNum
        BNE     Sony_ReturnResult               | bad drive -> return error
        LEA.L   0x1C(A0),A0                     | A0 -> CSParam (destination)
        MOVEQ.L #0xB,D0                         | 11 words = 22 bytes of drive status
        ADDA    D1,A1                           | A1 -> per-drive vars in SonyVars
E_SONY_STATUS_LOOP:
        MOVE    (A1)+,(A0)+                     | copy one word of status
        SUBQ.W  #0x1,D0                         | decrement word counter
        BGT.B   E_SONY_STATUS_LOOP              | loop for all 11 words
        BRA     Sony_ReturnResult               | return noErr

| -------------------------------------------------------
| ChooseDriveFromPB -- select drive from parameter block
| Reads ioVRefNum (PB+$16), validates 1..6, saves previous
| drive number, sets Active flag to exclude VBL task.
Sony_ChooseDriveFromPB:
        MOVE.L  (SonyVars).w,A1                 | load SonyVars pointer
        ST.B    0x19(A1)                        | Active = $FF: lock out VBL task
        MOVE    0x16(A0),D0                     | D0 = ioVRefNum (drive number)
        BEQ.B   SONY_CHOOSEDRIVEFROMPB_ERR      | zero is invalid
        CMPI    #0x6,D0                         | max 6 drives supported
        BGT.B   SONY_CHOOSEDRIVEFROMPB_ERR      | out of range -> error
        MOVE    TwoSideFmt(A1),0x112(A1)        | save previous Drive number
        MOVE    D0,TwoSideFmt(A1)               | set current Drive number
        BSR     Sony_SetupSonyVars              | compute drive vars offset in D1
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return success to caller

SONY_CHOOSEDRIVEFROMPB_ERR:
        MOVEQ.L #-0x38,D0                       | nsDrvErr (-56): no such drive
        RTS                                     | return error to caller

| ----------------------------------------------------------
|
| E_Sony_Prime
|
| E_Sony_Prime: entry point for Read/Write - dispatches via vector
E_Sony_Prime:
        MOVE.L  (DiskVars_JDiskPrime).w,-(SP)   | push DiskPrime vector
        RTS                                     | jump to implementation

| Sony_DiskPrime: main Read/Write handler
| A0 = IOParam block, ioTrap 2=Read, 3=Write
| Validates drive, checks disk inserted, seeks to target track,
| then reads or writes sectors in a loop
Sony_DiskPrime:
        ORI     #0x100,SR                       | raise IPL to prevent interrupts
        MOVE    0x6(A0),D3                      | D3 = ioTrap (2=read, 3=write)
        BTST    #0x6,0x2D(A0)                   | verify mode? (ioPosMode bit 6)
        SNE.B   (DskVerify).w                   | set verify flag if so
        BSR.B   Sony_ChooseDriveFromPB          | select drive from ioVRefNum
        BNE     SONY_DISKPRIME_ERR_4            | error -> return
        MOVE    D3,TwoSided(A1)                 | save I/O command type
| check drive is installed
        MOVEQ.L #-0x40,D0                       | assume nsDrvErr (-64)
        TST.B   0x4(A1,D1.W)                    | drive installed?
        BMI.B   SONY_DISKPRIME_ERR_4            | no ->
        BSR     Sony_JumpDiskSel                | select this drive's interface
| check drive type and disk insertion
        CMPI    #0x2,TwoSideFmt(A1)             | valid drive number?
        BGT     DT_SONY_NIBLTBL_CONT_20         | external/DCD drive ->
        MOVEQ.L #0x2,D0                         | disk register: CSTIN
        BSR     Sony_ReadDriveRegAdr            | read disk-inserted status
        BPL.B   SONY_DISKPRIME_CONT             | disk present ->
| no disk in drive
        CLR.B   0x3(A1,D1.W)                    | clear disk-in-place flag
        TST.B   0x1000(A0)                      | async call?
        MOVEQ.L #-0x41,D0                       | offLinErr (-65): no disk
        BRA.B   SONY_DISKPRIME_ERR_4            | return

| SONY_DISKPRIME_CONT -- disk is present, initialize if first access
SONY_DISKPRIME_CONT:
        CMPI.B  #0x2,0x3(A1,D1.W)               | DiskInPlace==2: already initialized?
        BEQ.B   SONY_DISKPRIME_OK               | yes -> proceed to I/O
        BSR     Sony_MotorOn1                   | spin up motor (no delay)
        BSR     E_Sony_Recal                    | recalibrate head to track 0
        BMI.B   SONY_DISKPRIME_ERR_2            | recal failed -> error exit
        BSR     E_Sony_MakeSpdTbl               | build speed correction table
        BNE.B   SONY_DISKPRIME_ERR_2            | speed cal failed -> error exit
        MOVEQ.L #0x6,D0                         | WRTPRT sense register
        BSR     Sony_ReadDriveRegAdr            | read WRTPRT, 0 = locked
        SPL.B   0x2(A1,D1.W)                    | WrProt: $FF if write-protected
        MOVE.B  #0x2,0x3(A1,D1.W)               | DiskInPlace = 2: MacOS initialized
        CLR.B   0x12(A1,D1.W)                   | DiskFormat = 0: assume single-sided
SONY_DISKPRIME_OK:
        BSR     SONY_RESEEK_OK_3                | test ioTrap: read or write?
        BEQ.B   SONY_DISKPRIME_SKIP             | read -> skip write-protect check
        MOVE    (BufTgFBkNum).w,0x26(A1)        | save tag file block number
        TST.B   0x2(A1,D1.W)                    | WrProt: disk write-protected?
        BPL.B   SONY_DISKPRIME_SKIP             | not protected -> proceed
        MOVEQ.L #-0x2C,D0                       | wPrErr (-44): disk is write-protected
SONY_DISKPRIME_ERR:
        MOVE    PwrOffTime(A1),D2               | D2 = motor power-off delay
        BRA.B   SONY_DISKPRIME_ERR_3            | turn off motor and return error

| SONY_DISKPRIME_ERR_2 -- error during disk init: immediate motor-off
SONY_DISKPRIME_ERR_2:
        MOVEQ.L #0x0,D2                         | D2 = 0: immediate power-off
SONY_DISKPRIME_ERR_3:
        MOVE    D0,-(SP)                        | save error code
        MOVE    D2,D0                           | D0 = power-off delay for MotorOff
        BSR     Sony_MotorOff                   | schedule motor power-off
        MOVE    (SP)+,D0                        | restore error code
SONY_DISKPRIME_ERR_4:
        ANDI    #-0x701,SR                      | restore IPL to 0 (enable interrupts)
        BRA     Sony_ReturnResult               | return result in D0

| SONY_DISKPRIME_SKIP -- set motor speed and begin sector I/O loop
SONY_DISKPRIME_SKIP:
        MOVE    0x0(A1,D1.W),D6                 | D6 = current head track position
        BSR     Sony_SetSpeed                   | set PWM speed for this track's zone
        BSR     Sony_MotorOn2                   | ensure motor is running with delay
| SONY_DISKPRIME_NEXT -- main I/O loop: compute logical sector from byte offset
SONY_DISKPRIME_NEXT:
        MOVE.L  (A1),A2                         | A2 = DCE pointer
        MOVE.L  0x8(A2),A0                      | A0 = IOParam block
        MOVE.L  0x10(A2),D0                     | D0 = dCtlPosition (byte offset)
        MOVEQ.L #0x9,D7                         | D7 = 9 (shift count for /512)
        LSR.L   D7,D0                           | D0 = logical sector number
        MOVEQ.L #0x0,D4                         | D4 = side shift (0=single-sided)
        TST.B   0x12(A1,D1.W)                   | DiskFormat: double-sided?
        BEQ.B   SONY_DISKPRIME_CONT_2           | single-sided -> D4=0
        MOVEQ.L #0x1,D4                         | double-sided -> D4=1
SONY_DISKPRIME_CONT_2:
        MOVEQ.L #0x64,D2                        | D2 = 100
        LSL     #0x3,D2                         | D2 = 800 sectors (400K disk)
        LSL     D4,D2                           | D2 = 1600 if double-sided
        CMP.L   D2,D0                           | sector beyond end of disk?
        BLT.B   SONY_DISKPRIME_NO               | no -> compute track/sector
SONY_DISKPRIME_EMPTY:
        MOVEQ.L #-0x32,D0                       | paramErr (-50): invalid position
SONY_DISKPRIME_ERR_5:
        BRA.B   SONY_DISKPRIME_ERR              | motor off and return error

| determine which of the five speed zones the desired sector is in
SONY_DISKPRIME_NO:
        MOVEQ.L #0x7,D3                         | D3 = 7
        LSL     #0x4,D3                         | D3 = 112 (sectors in zone 0, ss)
        LSL     D4,D3                           | D3 = 224 if double-sided
        MOVEQ.L #0x10,D5                        | D5 = 16 (decrement per zone, ss)
        LSL     D4,D5                           | D5 = 32 if double-sided
SONY_DISKPRIME_NEXT_2:
        ADD     D5,D3                           | D3 += sectors-per-zone increment
        SUB.L   D3,D2                           | D2 -= sectors in this zone
        CMP.L   D2,D0                           | target sector in remaining range?
        BLT.B   SONY_DISKPRIME_NEXT_2           | no -> try next zone inward
        LSR     #0x4,D3                         | D3 = sectors per track (this zone)
        MOVEQ.L #-0x1,D5                        | D5 = -1 (track counter, pre-inc)
SONY_DISKPRIME_NEXT_3:
        ADD     D3,D2                           | restore sector count for one track
        ADDQ.W  #0x1,D5                         | D5 = track within zone
        CMP     D2,D0                           | past this track?
        BGE.B   SONY_DISKPRIME_NEXT_3           | yes -> next track
        LSR     D4,D3                           | single-side sectors per track
        MOVEQ.L #0xC,D6                         | 12 = max sectors/track (zone 0)
        SUB     D3,D6                           | D6 = zone index * implicit
        LSL     #0x4,D6                         | D6 = zone * 16 (track base)
        ADD     D6,D5                           | D5 = absolute track number
        MOVE.L  D4,D6                           | D6 = side number: 0 for 400K, 1 for 800K
        SUB     D3,D2                           | D2 = starting sector number for side 1 of track
        CMP.L   D2,D0                           | target sector in side 1 range?
        BGE.B   SONY_DISKPRIME_OK_2             | yes -> accessing side 1
        SUB     D3,D2                           | D2 = starting sector number for side 0 of track
        MOVEQ.L #0x0,D6                         | D6 = side 0
SONY_DISKPRIME_OK_2:
        TST.B   D6                              | accessing side 1?
        BEQ.B   SONY_DISKPRIME_NO_2             | no -> side 0, proceed
        BSET    #0xB,D5                         | set side bit in track descriptor
        TST.B   0x5(A1,D1.W)                    | Sides: drive double-sided?
        BNE.B   SONY_DISKPRIME_NO_2             | yes -> OK
        MOVEQ.L #-0x4E,D0                       | sideErr (-78): single-sided drive
        BRA.B   SONY_DISKPRIME_ERR_5            | return error

| SONY_DISKPRIME_NO_2 -- set up sector loop variables
SONY_DISKPRIME_NO_2:
        MOVE    D5,DriveType(A1)                | save track/side descriptor
        SUB     D2,D0                           | D0 = sector offset within this side
        SUB     D0,D3                           | D3 = remaining sectors on this track
        MOVE    D0,SectCnt(A1)                  | save starting sector offset
        MOVE.L  0x24(A0),D5                     | D5 = ioReqCount (requested bytes)
        MOVE.L  0x28(A0),D2                     | D2 = ioActCount (bytes done so far)
        SUB.L   D2,D5                           | D5 = remaining bytes
        LSR.L   D7,D5                           | D5 = remaining sectors needed
        BEQ.B   SONY_DISKPRIME_EMPTY            | zero sectors: paramErr
        CMP     D5,D3                           | more sectors on track than needed?
        SLT.B   D6                              | D6 = $FF if more tracks follow
        BLE.B   SONY_DISKPRIME_CONT_3           | D3 <= D5: use all remaining
        MOVE    D5,D3                           | D3 = min(available, needed)
SONY_DISKPRIME_CONT_3:
        MOVEQ.L #0x0,D5                         | clear sector bitmask
        MOVE    D0,D4                           | D4 = first sector number
        MOVE    D3,-(SP)                        | save sector count
SONY_DISKPRIME_LOOP:
        BSet    D0,D5                           | set bit for each desired sector
        ADDQ.W  #0x1,D0                         | next sector
        SUBQ.W  #0x1,D3                         | decrement count
        BNE.B   SONY_DISKPRIME_LOOP             | loop until all bits set
        MOVE    (SP)+,D3                        | restore sector count
        MOVE.L  D5,SectMapSave(A1)              | store the bitmask of desired sectors
        MOVE.L  0x20(A0),A3                     | A3 = pointer to data buffer
        ADDA.L  D2,A3                           | offset by actual number of bytes processed so far
        MOVE.L  A3,0x1C(A1)                     | store pointer to data buffer
        LSR.L   D7,D2                           | divide by 512
        MOVE    D2,FBlksDone(A1)                | store actual number of sectors processed so far
        MOVE.B  RecalInit(A1),RecalCnt(A1)      | reset recal retry counter
        CLR.B   0x100(A1)                       | TCReady: clear track cache valid flag
        BSR     SONY_RESEEK_OK_3                | test ioTrap: read(0) or write(1)?
        BEQ.B   SONY_DISKPRIME_CONT_4           | read -> check track cache
        BSR     SONY_DISKPRIME_OK_4             | write: is track cache valid for this drive/track?
        BNE.B   SONY_DISKPRIME_SKIP_2           | no -> go seek and write
        MOVE.L  D5,D0                           | D0 = desired sector bitmask
        NOT.L   D0                              | invert: bits to invalidate
        AND.L   D0,0x106(A1)                    | TCValid: clear cached sectors being overwritten
        BSR     SONY_DISKPRIME_CONT_6           | update TCReady flag
SONY_DISKPRIME_SKIP_2:
        BRA     E_Sony_ReSeek                   | seek to target track and do I/O

| SONY_DISKPRIME_CONT_4 -- read path: try track cache first
SONY_DISKPRIME_CONT_4:
        TST.B   (DskVerify).w                   | verify-after-write mode?
        BNE.B   SONY_DISKPRIME_SKIP_2           | yes -> skip cache, do raw read
        BSR     SONY_DISKPRIME_OK_4             | is track cache valid for this drive/track?
        BNE     SONY_DISKPRIME_NO_4             | no -> seek and read from disk
        MOVE.L  D5,D2                           | D2 = bitmask of desired sectors
        AND.L   0x106(A1),D2                    | mask: keep only sectors that ARE cached
        BEQ.B   SONY_DISKPRIME_EMPTY_2          | none cached -> must read from disk
        MOVEQ.L #0x2,D7                         | D7 = 2
        ASL.L   #0x8,D7                         | D7 = $200 = 512 bytes per sector
        MOVE    D4,D0                           | D0 = first sector in track
        MULU    #0x20C,D0                       | * 524: offset into track cache (12 tag + 512 data)
        MOVE.L  0x10A(A1),A4                    | A4 = TCBuffer base
        ADDA    D0,A4                           | A4 -> cached sector data
SONY_DISKPRIME_LOOP_2:
        BTst    D4,D2                           | is this sector in the cache valid?
        BEQ.B   SONY_DISKPRIME_SKIP_3           | no -> skip to next sector
        BCLR    D4,D5                           | mark sector as satisfied
        MOVEM.L A0-A1,-(SP)                     | save IOParam and SonyVars
        TST.L   0xF4(A1)                        | TagBufPtr: caller provided tag buffer?
        BEQ.B   SONY_DISKPRIME_NO_3             | no -> use system tag globals
        MOVE    D4,D0                           | compute tag buffer offset for this sector
        SUB     SectCnt(A1),D0                  | relative to starting sector
        ADD     FBlksDone(A1),D0                | plus sectors already done
        MULU    #0xC,D0                         | * 12 bytes per tag
        MOVE.L  0xF4(A1),A1                     | A1 = caller's tag buffer
        ADDA.L  D0,A1                           | offset to this sector's tags
        BRA.B   SONY_DISKPRIME_CONT_5           | copy tags

| SONY_DISKPRIME_NO_3 -- no external tag buffer: use system globals
SONY_DISKPRIME_NO_3:
        LEA.L   (BufTgFNum).w,A1                | A1 -> system tag buffer
SONY_DISKPRIME_CONT_5:
        MOVE.L  A4,A0                           | A0 = source (track cache entry)
        MOVE.L  (A0)+,(A1)+                     | copy 12 bytes of tag data (words 1-2)
        MOVE.L  (A0)+,(A1)+                     | tag data words 3-4
        MOVE.L  (A0)+,(A1)+                     | tag data words 5-6
        MOVE.L  A3,A1                           | A1 = user's data buffer
        MOVE.L  D7,D0                           | D0 = 512 bytes
        _BlockMove                              | copy 512 bytes from cache to user buffer
        MOVEM.L (SP)+,A0-A1                     | restore IOParam and SonyVars
        ADDQ.W  #0x1,0x110(A1)                  | TCHits: increment cache hit count
        ADD.L   D7,0x10(A2)                     | advance dCtlPosition by 512
        ADD.L   D7,0x28(A0)                     | advance ioActCount by 512
SONY_DISKPRIME_SKIP_3:
        ADDA.L  D7,A3                           | advance user buffer pointer
        ADDA.L  D7,A4                           | advance cache pointer past data
        ADDA    #0xC,A4                         | skip 12-byte tag area
        ADDQ.W  #0x1,D4                         | next sector number
        SUBQ.W  #0x1,D3                         | decrement sector count
        BNE.B   SONY_DISKPRIME_LOOP_2           | loop for remaining sectors
        MOVE.L  D5,SectMapSave(A1)              | save sector mask
        BNE.B   SONY_DISKPRIME_EMPTY_2          | must wrap around?
        MOVE.L  0x28(A0),D0                     | get actual number of bytes
        CMP.L   0x24(A0),D0                     | compared to desired number of bytes
        BLT     SONY_DISKPRIME_NEXT             | process the remaining tracks?
        MOVEQ.L #0x0,D0                         | success!
        BRA     SONY_DISKPRIME_ERR              | turn off drive motor, and return the result

| SONY_DISKPRIME_EMPTY_2 -- not all sectors satisfied from cache: do disk I/O
SONY_DISKPRIME_EMPTY_2:
        BSR.B   SONY_DISKPRIME_CONT_6           | update TCReady from remaining mask
        BRA.B   E_Sony_ReSeek                   | seek and read remaining sectors

| SONY_DISKPRIME_NO_4 -- cache miss: prepare fresh cache, then read from disk
SONY_DISKPRIME_NO_4:
        BSR.B   SONY_DISKPRIME_CONT_6           | update TCReady flag
        BNE.B   E_Sony_ReSeek                   | cache not usable -> just seek/read
        MOVE    TwoSideFmt(A1),0x102(A1)        | TCDrive: tag cache for this drive
        MOVE    DriveType(A1),0x104(A1)         | TCTrack: tag cache for this track/side
        CLR.L   0x106(A1)                       | TCValid: clear all sector valid bits
        BRA.B   E_Sony_ReSeek                   | seek and read from disk

| SONY_DISKPRIME_CONT_6 -- TCReadyCheck: update TCReady flag based on cache state
| Sets TCReady=$FF if track cache is installed and covers
| remaining sectors (or if verify-write needs all sectors)
SONY_DISKPRIME_CONT_6:
        TST.B   0x101(A1)                       | TCInstalled: cache enabled?
        BEQ.B   SONY_DISKPRIME_NO_5             | no -> force D6=1 (more tracks)
        BTST    #0xA,TwoSided(A1)               | write operation bit set?
        BNE.B   SONY_DISKPRIME_OK_3             | write -> use D6 as-is
        TST.B   D6                              | D6=0 means all sectors on one track
SONY_DISKPRIME_OK_3:
        SEQ.B   0x100(A1)                       | TCReady: $FF if all on one track
        RTS                                     | return to caller

| SONY_DISKPRIME_NO_5 -- cache not installed: set D6=1 to skip caching
SONY_DISKPRIME_NO_5:
        MOVEQ.L #0x1,D6                         | force "more tracks follow" flag
        BRA.B   SONY_DISKPRIME_OK_3             | set TCReady=0

| SONY_DISKPRIME_OK_4 -- TCMatch: check if track cache matches current drive/track
| Returns D0=0 if cache is valid for this drive and track/side
SONY_DISKPRIME_OK_4:
        TST.B   0x101(A1)                       | TCInstalled: cache enabled?
        BEQ.B   SONY_DISKPRIME_NO_6             | no -> mismatch
        MOVE    0x102(A1),D0                    | TCDrive: cached drive number
        BEQ.B   SONY_DISKPRIME_NO_6             | no drive cached -> mismatch
        CMP     TwoSideFmt(A1),D0               | same drive as current?
        BNE.B   SONY_DISKPRIME_NO_6             | different drive -> mismatch
        MOVE    DriveType(A1),D0                | current track/side descriptor
        SUB     0x104(A1),D0                    | subtract TCTrack
        BEQ.B   SONY_DISKPRIME_EXIT             | match -> return 0
SONY_DISKPRIME_NO_6:
        MOVEQ.L #-0x1,D0                        | mismatch -> return -1
SONY_DISKPRIME_EXIT:
        RTS                                     | Z=1 if match, Z=0 if mismatch

| ----------------------------------------------------------
|
| E_Sony_Re Seek
|
E_Sony_ReSeek:
        MOVE.L  (DiskVars_JReSeek).w,-(SP)      | push ReSeek vector address
        RTS                                     | dispatch to Sony_ReSeek

| -------------------------------------------------------
| Sony_ReSeek -- seek to target track, adjust speed if needed
| Retries with speed correction until BadSpdCnt exhausted.
Sony_ReSeek:
        MOVE.B  InvalidResp(A1),0x31(A1)        | BadSpdCnt: init speed retry counter
SONY_RESEEK_RETRY:
        MOVE    DriveType(A1),D6                | D6 = target track/side descriptor
        BSR     E_Sony_Seek                     | seek head to target track
        BMI.B   SONY_RESEEK_ERR                 | seek failed -> error exit
        MOVE.B  0x2A(A1),0x2B(A1)               | ReadErrCnt = ReadErrInit
        LSR     #0x4,D6                         | extract zone from track number
        LSL     #0x3,D6                         | *8: index into per-zone speed table
        LEA.L   0x1A(A1,D1.W),A2                | A2 -> per-drive speed adjustment table
        LEA.L   0x4(A2,D6.W),A2                 | A2 -> timestamp for this zone
        MOVE.L  (Ticks).w,D2                    | D2 = current tick count
        MOVE.L  (A2),D0                         | last speed measurement timestamp
        BEQ.B   SONY_RESEEK_CONT                | never measured -> measure now
        SUB.L   D2,D0                           | elapsed = current - last
        NEG.L   D0                              | make positive
        CMP.L   0x44(A1),D0                     | SectTime threshold exceeded?
        BLT.B   SONY_RESEEK_SKIP                | recent enough -> skip speed check
SONY_RESEEK_CONT:
        MOVE.L  D2,(A2)                         | update timestamp
        LEA.L   SONY_RESEEK_CONT_2(PC),A3       | A3 = speed check callback
        BRA     SONY_MAKESPDTBL_CONT_6          | measure disk speed via FigTrkSpd

| SONY_RESEEK_CONT_2 -- callback after speed measurement
SONY_RESEEK_CONT_2:
        BMI.B   SONY_RESEEK_ERR                 | measurement failed -> error
        MOVE    -(A2),D0                        | D0 = current speed adjustment value
        LEA.L   DT_Sony_SpeedCheckTbl(PC),A0    | A0 = acceptable RPM range table
        LSR     #0x1,D6                         | zone index for word table
        ADDA    D6,A0                           | index into speed table
        CMP     (A0)+,D4                        | measured speed > upper limit?
        BGT.B   SONY_RESEEK_OK                  | yes -> speed too fast, adjust
        NEG     D0                              | try negative correction
        CMP     (A0),D4                         | measured speed > lower limit?
        BGT.B   SONY_RESEEK_SKIP                | within range -> proceed to I/O
SONY_RESEEK_OK:
        TST.B   0x13(A1,D1.W)                   | NewIntf: 800K interface?
        BMI.B   SONY_RESEEK_NO                  | new intf -> no PWM adjustment
        SUB     D0,-(A2)                        | apply speed correction to adjustment
        CLR.L   0x4(A2)                         | clear timestamp to force remeasure
SONY_RESEEK_NO:
        ADDQ.W  #0x1,0x18(A1,D1.W)              | SpdAdjCnt: increment adjustment count
        SUBQ.B  #0x1,0x31(A1)                   | decrement BadSpdCnt
        BPL.B   SONY_RESEEK_RETRY               | retry if attempts remain
        MOVEQ.L #-0x4F,D0                       | spdAdjErr (-79): can't adjust speed
SONY_RESEEK_ERR:
        BRA     SONY_RESEEK_ERR_6               | recal and retry or return error

| SONY_RESEEK_SKIP -- sector scan loop: read address marks, find desired sectors
SONY_RESEEK_SKIP:
        MOVE.B  WrgSectInit(A1),WrgSectCnt(A1)  | reset wrong-sector retry counter
SONY_RESEEK_RETRY_2:
        MOVE    D1,D6                           | save drive vars offset
        BSR     SONY_SETUPPOLL_CONT             | read address field (RdAddr)
        BMI     SONY_RESEEK_ERR_4               | read error -> retry path
        CMP     DriveType(A1),D1                | on correct track/side?
        BNE     SONY_RESEEK_ERR_5               | wrong track -> seek error
        MOVE    D2,0xFE(A1)                     | CurSect: save current sector number
        MOVE    D2,(TagData).w                  | copy sector number to low-mem tag
        MOVE.L  SectMapSave(A1),D0              | D0 = desired sector bitmask
        BTST    D2,D0                           | is this a sector we want?
        BNE     SONY_RESEEK_OK_2                | yes -> read/write this sector
| sector not needed: try caching it if track cache enabled
        TST.B   0x100(A1)                       | TCReady: track cache active?
        BEQ     SONY_RESEEK_SKIP_3              | no -> wait for next sector
        MOVE.L  0x106(A1),D0                    | TCValid: sector cache bitmap
        BTST    D2,D0                           | already cached?
        BNE     SONY_RESEEK_SKIP_3              | yes -> skip, wait for next
        LEA.L   Sony_RdData(PC),A0              | check if RdData is patched
        CMPA.L  (DiskVars_JRdData).w,A0         | standard RdData vector?
        SNE.B   0x100(A1)                       | if patched, disable cache read-ahead
        BNE     SONY_RESEEK_SKIP_3              | patched -> skip cache fill
        MOVE    D2,D1                           | D1 = sector number
        MULU    #0x20C,D2                       | D2 = offset into cache (524*sector)
        MOVE.L  0x10A(A1),A0                    | A0 = TCBuffer base
        ADDA.L  D2,A0                           | offset to this sector's cache slot
        ADDA    #0xC,A0                         | skip 12-byte tag area -> data
        BSR     E_Sony_RdData                   | read sector data into cache
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars (trashed by RdData)
        SPL.B   0x100(A1)                       | TCReady: clear if read failed
        BMI.B   SONY_RESEEK_ERR_2               | error -> skip tag copy
        ADDQ.W  #0x1,0x10E(A1)                  | TCCacheCnt: count sectors cached
        MOVE    0xFE(A1),D2                     | D2 = sector just read
        MOVE.L  0x10A(A1),A0                    | A0 = TCBuffer
        MOVE    D2,D1                           | D1 = sector number
        MULU    #0x20C,D1                       | offset to sector's tag area
        ADDA.L  D1,A0                           | A0 -> tag area in cache
        LEA.L   (BufTgFNum).w,A2                | A2 = system tag buffer
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 1-4 into cache
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 5-8
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 9-12
        MOVE.L  0x106(A1),D4                    | D4 = TCValid bitmask
        BSET    D2,D4                           | mark this sector as cached
        MOVE.L  D4,0x106(A1)                    | update TCValid
SONY_RESEEK_ERR_2:
        BSet    #0x7,(IntFlag).w                | test and set deferred interrupt flag
        BNE.B   SONY_RESEEK_CONT_3              | already set -> just poll
        MOVE    SectTime(A1),D0                 | inter-sector timing delay
        BSR     SONY_WAKEUP_CONT                | subtract from motor countdown
        BSR     SONY_RESEEK_CONT_8              | call PollProc (deferred tasks)
        BSR     SONY_WAKEUP_EXIT                | return to WakeUp continuation
        BRA.B   SONY_RESEEK_CONT_4              | resume sector scan

| SONY_RESEEK_CONT_3 -- deferred interrupt already pending: quick poll
SONY_RESEEK_CONT_3:
        BSR     SONY_RESEEK_CONT_8              | call PollProc
        ANDI    #-0x701,SR                      | restore IPL to 0
SONY_RESEEK_CONT_4:
        BRA     SONY_RESEEK_SKIP                | resume sector scan loop

| SONY_RESEEK_OK_2 -- found desired sector: set up for read or write
SONY_RESEEK_OK_2:
        CMPI.B  #0x1F,D3                        | format byte > $1F means double-sided
        SGT.B   0x12(A1,D6.W)                   | DiskFormat: $FF if double-sided
        SUB     SectCnt(A1),D2                  | D2 = sector offset relative to start
        MOVE    D2,D1                           | D1 = relative sector offset
        ASL.L   #0x8,D1                         | D1 = offset * 256
        ADD.L   D1,D1                           | D1 = offset * 512 (byte offset)
        ADD.L   0x1C(A1),D1                     | D1 = data buffer + byte offset
        MOVE.L  D1,A0                           | A0 -> user data buffer for this sector
        MOVE    FBlksDone(A1),D1                | D1 = sectors already completed
        ADD     D2,D1                           | D1 = absolute sector index
        MOVE    D1,D0                           | D0 = sector index for tag calc
        ADD     D1,D1                           | D1 = index * 2
        ADD     D0,D1                           | D1 = index * 3
        ASL     #0x2,D1                         | D1 = index * 12 (tag offset)
        MOVE    D1,0xF8(A1)                     | TagOffset: save for tag buffer copy
        BSR     SONY_RESEEK_OK_3                | test ioTrap: read(0) or write(1)?
        BEQ.B   SONY_RESEEK_CONT_6              | read -> go to RdData
| write path: prepare tag data then write sector
        MOVE.L  0xF4(A1),D3                     | TagBufPtr: external tag buffer?
        BEQ.B   SONY_RESEEK_NO_2                | no -> compute default tags
        MOVE.L  D3,A1                           | A1 = external tag buffer
        ADDA    D1,A1                           | offset to this sector's tags
        LEA.L   (BufTgFNum).w,A2                | A2 = system tag globals
        MOVE.L  (A1)+,(A2)+                     | copy tags from user buffer to globals
        MOVE.L  (A1)+,(A2)+                     | tag bytes 5-8
        MOVE.L  (A1)+,(A2)+                     | tag bytes 9-12
        BRA.B   SONY_RESEEK_CONT_5              | write sector

| SONY_RESEEK_NO_2 -- no external tag buffer: compute file block number tag
SONY_RESEEK_NO_2:
        ADD     0x26(A1),D0                     | add base block number
        MOVE    D0,(BufTgFBkNum).w              | set tag file block number
SONY_RESEEK_CONT_5:
        BSR     E_Sony_WrData                   | write sector data to disk
        BMI     SONY_RESEEK_ERR_4               | write error -> retry path
        BRA.B   SONY_RESEEK_SKIP_2              | success -> update bookkeeping

| SONY_RESEEK_CONT_6 -- read path: read sector from disk
SONY_RESEEK_CONT_6:
        BSR     E_Sony_RdData                   | read sector data from disk
        BMI     SONY_RESEEK_ERR_4               | read error -> retry path
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        MOVE.L  0xF4(A1),D0                     | TagBufPtr: external tag buffer?
        BEQ.B   SONY_RESEEK_SKIP_2              | no -> skip tag copy
        MOVE.L  D0,A0                           | A0 = external tag buffer
        ADDA    0xF8(A1),A0                     | offset to this sector's tags
        LEA.L   (BufTgFNum).w,A2                | A2 = system tag globals
        MOVE.L  (A2)+,(A0)+                     | copy tags to user buffer
        MOVE.L  (A2)+,(A0)+                     | tag bytes 5-8
        MOVE.L  (A2)+,(A0)+                     | tag bytes 9-12
| SONY_RESEEK_SKIP_2 -- sector I/O complete: update bookkeeping, check if done
SONY_RESEEK_SKIP_2:
        BSR     Sony_SetupSonyVars              | reload SonyVars and drive offset
        MOVE.L  SectMapSave(A1),D4              | D4 = remaining sector bitmask
        MOVE    0xFE(A1),D2                     | D2 = sector just processed
        BCLR    D2,D4                           | clear this sector's bit
        MOVE.L  D4,SectMapSave(A1)              | save updated bitmask
        MOVE.L  (A1),A2                         | A2 = DCE pointer
        MOVE.L  0x8(A2),A0                      | A0 = IOParam block
        MOVEQ.L #0x2,D3                         | D3 = 2
        ASL.L   #0x8,D3                         | D3 = $200 = 512 bytes
        ADD.L   D3,0x10(A2)                     | advance dCtlPosition by 512
        ADD.L   D3,0x28(A0)                     | advance ioActCount by 512
        MOVE.L  0x24(A0),D3                     | D3 = ioReqCount (total requested)
        SUB.L   0x28(A0),D3                     | D3 = remaining bytes
        BSET    #0x7,(IntFlag).w                | test and set deferred interrupt flag
        BEQ.B   SONY_RESEEK_NO_3                | not set -> do deferred processing
        BSR.B   SONY_RESEEK_OK_3                | read or write?
        BEQ.B   SONY_RESEEK_CONT_7              | read -> quick poll
        TST.L   D4                              | more sectors on this track?
        BNE.B   SONY_RESEEK_NO_3                | yes -> do deferred processing
        BSR     SONY_RESEEK_CONT_8              | call PollProc
        MOVEQ.L #0x7,D0                         | 0.7ms delay
        BSR     E_Sony_WakeUp                   | brief pause for write settling
        BRA.B   SONY_RESEEK_DONE                | check if transfer complete

| SONY_RESEEK_NO_3 -- inter-sector deferred processing
SONY_RESEEK_NO_3:
        MOVE    SectTime(A1),D0                 | D0 = inter-sector timing value
        BSR     SONY_WAKEUP_CONT                | subtract from motor countdown
        BSR     SONY_RESEEK_CONT_8              | call PollProc (deferred tasks)
        BSR     SONY_WAKEUP_EXIT                | return to WakeUp continuation
        BRA.B   SONY_RESEEK_DONE                | check if transfer complete

| SONY_RESEEK_CONT_7 -- interrupt already pending: quick poll only
SONY_RESEEK_CONT_7:
        BSR     SONY_RESEEK_CONT_8              | call PollProc
        ANDI    #-0x701,SR                      | restore IPL to 0
| SONY_RESEEK_DONE -- check if all sectors done, or more tracks needed
SONY_RESEEK_DONE:
        MOVE.L  D4,D0                           | more sectors on this track?
        BNE     SONY_RESEEK_SKIP                | yes -> scan for next sector
        TST.L   D3                              | more bytes remaining?
        BGT     SONY_DISKPRIME_NEXT             | yes -> compute next track
        TST.B   0x12(A1,D1.W)                   | DiskFormat: double-sided disk?
        BEQ.B   SONY_RESEEK_ERR_3               | single-sided -> done
        TST.B   0x5(A1,D1.W)                    | Sides: drive double-sided?
        BNE.B   SONY_RESEEK_ERR_3               | yes -> done
        MOVEQ.L #-0x4E,D0                       | sideErr (-78): single-sided drive
SONY_RESEEK_ERR_3:
        BRA     SONY_DISKPRIME_ERR              | motor off and return result

| SONY_RESEEK_OK_3 -- IsWrite: test if current operation is write
| Returns Z=1 for read (ioTrap==2), Z=0 for write (ioTrap==3)
| Called by: SONY_DISKPRIME_OK, SONY_DISKPRIME_LOOP, SONY_RESEEK_OK_2, SONY_RESEEK_SKIP_2, SONY_RESEEK_ERR_4 (and 1 more)
SONY_RESEEK_OK_3:
        CMPI.B  #0x2,0x33(A1)                   | TwoSided: ioTrap saved at +$33
        RTS                                     | Z=1 if read, Z=0 if write

| -------------------------------------------------------
| SONY_RESEEK_CONT_8 -- CallPollProc: invoke deferred task (PollProc)
| Saves volatile registers, calls PollProc, restores state.
| If PollProc is nil, switches to PollStack and returns.
| Called by: SONY_RESEEK_ERR_2, SONY_RESEEK_CONT_3, SONY_RESEEK_SKIP_2, SONY_RESEEK_NO_3, SONY_RESEEK_CONT_7 (and 5 more)
SONY_RESEEK_CONT_8:
        MOVE.L  (SP)+,A4                        | A4 = return address
        PEA.L   SONY_RESEEK_CONT_9(PC)          | push resume address after PollProc
        MOVE.L  (PollProc).w,-(SP)              | push PollProc address
        BEQ.B   SONY_RESEEK_EMPTY               | nil -> use PollStack shortcut
        MOVE.L  (SonyVars).w,A1                 | save volatile regs in SonyVars
        MOVEM.L D0/D2-D3/A0/A4,0xD0(A1)         | save D0,D2,D3,A0,A4 at +$D0
        RTS                                     | "call" PollProc

| SONY_RESEEK_CONT_9 -- PollProc resume point: restore registers
SONY_RESEEK_CONT_9:
        BSR     Sony_SetupSonyVars              | reload SonyVars and drive offset
        MOVEM.L 0xD0(A1),D0/D2-D3/A0/A4         | restore saved registers
        JMP     (A4)                            | return to caller of SONY_RESEEK_CONT_8

| SONY_RESEEK_EMPTY -- no PollProc: switch to PollStack and return
SONY_RESEEK_EMPTY:
        MOVE.L  (PollStack).w,SP                | switch to reserved poll stack
        BSR     Sony_SetupSonyVars              | reload SonyVars
        JMP     (A4)                            | return to caller of SONY_RESEEK_CONT_8

| SONY_RESEEK_ERR_4 -- sector I/O error: retry with decremented counters
SONY_RESEEK_ERR_4:
        BSR.B   SONY_RESEEK_CONT_8              | call PollProc
        ANDI    #-0x701,SR                      | restore IPL to 0
        ADDQ.W  #0x1,0xFA(A1)                   | ErrCnt: increment global error count
        ADDQ.W  #0x1,0x14(A1,D1.W)              | increment per-drive error count
        TST.B   RecalCnt(A1)                    | recal retries remaining?
        BEQ.B   SONY_RESEEK_RETRY_3             | none -> try read retry only
        BSR.B   SONY_RESEEK_OK_3                | is this a write operation?
        BNE.B   SONY_RESEEK_ERR_6               | write -> go to recal/retry
SONY_RESEEK_RETRY_3:
        SUBQ.B  #0x1,0x2B(A1)                   | ReadErrCnt: decrement read retry
        BPL     SONY_RESEEK_SKIP                | retries remain -> rescan sectors
        BRA.B   SONY_RESEEK_ERR_6               | exhausted -> recal and retry

| SONY_RESEEK_SKIP_3 -- wrong sector found: wait and retry
SONY_RESEEK_SKIP_3:
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        MOVE    SectTime(A1),D0                 | inter-sector timing
        BSR     SONY_WAKEUP_CONT                | subtract from motor countdown
        BSR.B   SONY_RESEEK_CONT_8              | call PollProc
        BSR     SONY_WAKEUP_EXIT                | return to WakeUp continuation
        ADDQ.L  #0x1,(RndSeed).w                | perturb random seed (timing jitter)
        MOVEQ.L #-0x51,D0                       | sectNFErr (-81): can't find sector
        SUBQ.B  #0x1,WrgSectCnt(A1)             | decrement wrong-sector retry count
        BMI.B   SONY_RESEEK_ERR_6               | exhausted -> recal and retry
        BRA     SONY_RESEEK_RETRY_2             | try scanning again

| SONY_RESEEK_ERR_5 -- address mark shows wrong track: seek error
SONY_RESEEK_ERR_5:
        BSR.B   SONY_RESEEK_CONT_8              | call PollProc
        MOVEQ.L #-0x50,D0                       | seekErr (-80): drive seek error
| SONY_RESEEK_ERR_6 -- fatal error path: try recal then retry
SONY_RESEEK_ERR_6:
        ANDI    #-0x701,SR                      | restore IPL to 0
        SUBQ.B  #0x1,RecalCnt(A1)               | decrement recal retry counter
        BLE.B   SONY_RESEEK_ERR_7               | exhausted -> return error
        BSR     E_Sony_Recal                    | recalibrate to track 0
        BMI.B   SONY_RESEEK_ERR_7               | recal failed -> return error
        BSR     E_Sony_MakeSpdTbl               | rebuild speed table
        BPL     E_Sony_ReSeek                   | success -> re-seek and retry I/O
SONY_RESEEK_ERR_7:
        BRA     SONY_RESEEK_ERR_3               | return last error to caller
.equ SPEEDZONE_TBL, .-0x2                       | base addr for speed zone offset table

  .byte 0x00,0x4A,0x00,0x8C,0x01,0x28           | speed zone offsets: zone 0=74, 1=140, 2=296
  .byte 0x01,0x44,0x01,0x60,0x01,0x7C           | zone 3=324, zone 4=352, zone 5=380
  .byte 0x01,0x7C                               | zone 5 repeated (sentinel)
| Sony_SetupRegs -- set up A0=IWM, A2=VIA, A1=SonyVars.
| Called by: E_SONY_OPEN_LOOP, Sony_AdrDisk, SONY_WAKEUP_CONT_3, Sony_Recal, Sony_CheckForDiskInserted (and 1 more)
Sony_SetupRegs:
        MOVE.L  (IWM).w,A0                      | A0 = IWM chip base ($DFE1FF)
        MOVE.L  (VIA).w,A2                      | A2 = VIA chip base ($EFE1FE)
| Sony_SetupSonyVars -- reload SonyVars and drive offset.
| Called by: Sony_ChooseDriveFromPB, SONY_RESEEK_SKIP_2, SONY_RESEEK_CONT_9, SONY_RESEEK_EMPTY, Sony_SetSpeed (and 13 more)
Sony_SetupSonyVars:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars pointer
        MOVE    TwoSideFmt(A1),D1               | D1 = current drive number
        ADD     D1,D1                           | D1 = drive * 2 (word index)
        MOVE    SPEEDZONE_TBL(PC,D1.W),D1       | D1 = per-drive vars offset in SonyVars
        RTS                                     | return with A1=SonyVars, D1=offset

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
        LSR.B   #0x1,D0                         | test CA2 bit
        BCC.B   SONY_ADRDISK_CONT               | CA2 = 0 ->
        TST.B   0xA00(A0)                       | CA2 on
        BRA.B   SONY_ADRDISK_CONT_2             | ->

| ----------------------------------------------------------
|
| SONY_ADRDISK_CONT
|
SONY_ADRDISK_CONT:
        TST.B   0x800(A0)                       | CA2 off
SONY_ADRDISK_CONT_2:
        LSR.B   #0x1,D0                         | test SEL bit (bit 1 of register addr)
        BCC.B   SONY_ADRDISK_CONT_3             | SEL=0 -> clear SEL line
        BSET    #0x5,0x1E00(A2)                 | SEL on: set VIA Port A bit 5
        BRA.B   SONY_ADRDISK_SKIP               | skip SEL-off path

| ----------------------------------------------------------
|
| SONY_ADRDISK_CONT_3
|
SONY_ADRDISK_CONT_3:
        BClr    #0x5,0x1E00(A2)                 | SEL off: clear VIA Port A bit 5
SONY_ADRDISK_SKIP:
        LSR.B   #0x1,D0                         | test CA0 bit (bit 2 of register addr)
        BCS.B   SONY_ADRDISK_CONT_4             | CA0=1 -> leave CA0 on (already set)
        TST.B   (A0)                            | CA0 off: deassert phase 0
SONY_ADRDISK_CONT_4:
        LSR.B   #0x1,D0                         | test CA1 bit (bit 3 of register addr)
        BCS.B   SONY_ADRDISK_CONT_5             | CA1=1 -> leave CA1 on (already set)
        TST.B   0x400(A0)                       | CA1 off: deassert phase 1
SONY_ADRDISK_CONT_5:
        RTS                                     | drive register now addressed

| read the drive register whose address is in D0
Sony_ReadDriveRegAdr:
        BSR.B   Sony_AdrDisk                    | address register D0 via phase lines
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

| write to a drive register
| register address is in D0[3:1]
| value to write is in D0[0]
Sony_WriteDriveRegAdr:
        BSR.B   Sony_AdrDisk                    | address register D0 via phase lines
| Sony_WriteDriveReg -- write STEP: execute one step pulse.
Sony_WriteDriveReg:
        MOVE    SR,-(SP)                        | save SR (preserve IPL)
        ORI     #0x300,SR                       | raise IPL to 3 (mask SCC ints)
        TST.B   0xE00(A0)                       | LSTRB on: latch strobe high
        NOP                                     | hold time for drive to register strobe
        NOP                                     | additional hold time
        TST.B   0xC00(A0)                       | LSTRB off: complete write pulse
        MOVE    (SP)+,SR                        | restore previous IPL
        RTS                                     | drive register written

| special handler for drive numbers 3 and above
SONY_WRITEDRIVEREG_CONT:
        MOVEQ.L #0xD,D0                         | DrvExstAdr: check DCD exists
        BSR.B   Sony_ReadDriveRegAdr            | read INSTALLED, 0 = yes
        BPL.B   SONY_WRITEDRIVEREG_EXIT         | sense=0: not connected -> return -1
        TST.B   (A0)                            | CA0 off: address SIDES register
        BSR.B   Sony_ReadDriveReg               | read SIDES, 0 = single, 1 = double
        BPL.B   SONY_WRITEDRIVEREG_EXIT         | single-sided: no DCD -> return -1
        TST.B   0x200(A0)                       | CA0 on: address disk-switched register
        TST.B   0x400(A0)                       | CA1 off: complete register select
        BSR.B   Sony_ReadDriveReg               | read disk-switched status
        BRA.B   SONY_WRITEDRIVEREG_EXIT_2       | return with disk-switched in D0

| ----------------------------------------------------------
|
| SONY_WRITEDRIVEREG_EXIT
|
SONY_WRITEDRIVEREG_EXIT:
        MOVEQ.L #-0x1,D0                        | return -1: DCD not present
SONY_WRITEDRIVEREG_EXIT_2:
        RTS                                     | return to caller

| -------------------------------------------------------
| Sony_SetSpeed -- set PWM disk speed for target track zone
| D6 = target track number. Looks up per-zone speed adjustment,
| clamps to [0, $1B8], computes settling delay, programs PWM.
Sony_SetSpeed:
        BSR     Sony_SetupSonyVars              | A1=SonyVars, D1=drive offset
        MOVE    D6,D2                           | D2 = target track
        LSR     #0x4,D2                         | zone index (track / 16)
        LSL     #0x3,D2                         | zone * 8 (table stride)
        ADD     D1,D2                           | per-drive zone table offset
        MOVE    0x1A(A1,D2.W),D2                | D2 = calibrated speed for zone
        TST.B   0x13(A1,D1.W)                   | NewIntf: 800K interface?
        BMI.B   SONY_SETSPEED_NO                | new intf -> no PWM, use 0
        TST     D2                              | speed value negative?
        BPL.B   SONY_SETSPEED_OK                | no -> use as-is
SONY_SETSPEED_NO:
        MOVEQ.L #0x0,D2                         | clamp minimum to 0
SONY_SETSPEED_OK:
        CMPI    #0x1B8,D2                       | exceeds max PWM value ($1B8=440)?
        BLE.B   SONY_SETSPEED_OK_2              | no -> use as-is
        MOVE    #0x1B8,D2                       | clamp to max
SONY_SETSPEED_OK_2:
        MOVE    (PWMValue).w,D0                 | D0 = current PWM setting
        BPL.B   SONY_SETSPEED_CONT              | motor running -> compute delay
        MOVE    PwrOnTime(A1),D0                | motor off -> full power-on delay
        BRA.B   SONY_SETSPEED_NO_2              | apply delay

| SONY_SETSPEED_CONT -- compute spin-up/down settling delay
SONY_SETSPEED_CONT:
        SUB     D2,D0                           | D0 = magnitude of speed change
        BEQ     Sony_SetupSonyVars              | no change -> return
        BPL.B   SONY_SETSPEED_CONT_2            | positive -> slowing down
        NEG     D0                              | make positive
SONY_SETSPEED_CONT_2:
        LSL     #0x5,D0                         | scale by 32 for delay estimate
        CMP     SpdChgTime(A1),D0               | below minimum speed change time?
        BGT.B   SONY_SETSPEED_NO_2              | no -> use computed delay
        MOVE    SpdChgTime(A1),D0               | enforce minimum delay
SONY_SETSPEED_NO_2:
        ADD     iconIDCC(A1),D0                 | add accumulated motor-on time
        CMP     PwrOnTime(A1),D0                | exceeds max delay?
        BLT.B   SONY_SETSPEED_NO_3              | no -> use sum
        MOVE    PwrOnTime(A1),D0                | clamp to max
SONY_SETSPEED_NO_3:
        MOVE    D0,iconIDCC(A1)                 | save motor settling countdown
| SONY_SETSPEED_CONT_3 -- ProgramPWM: generate PWM waveform buffers for disk speed
| D2 = target PWM value. Computes LFSR duty cycle values and fills
| both double-buffered PWM buffers (370 bytes each at even addresses).
SONY_SETSPEED_CONT_3:
        MOVE    D2,(PWMValue).w                 | store new PWM setting
        MOVEM.L D3-D6/A2,-(SP)                  | save registers
        SUBI    #0x1B8,D2                       | D2 = $1B8 - speed (invert)
        NEG     D2                              | D2 = inverted PWM count
        EXT.L   D2                              | sign-extend for DIVU
        DIVU    #0xA,D2                         | D2.w = quotient, D2.hi = remainder
        MOVEQ.L #0x1E,D0                        | D0 = LFSR seed (6-bit)
SONY_SETSPEED_LOOP:
        MOVE.B  D0,D1                           | D1 = previous LFSR value
        MOVE.B  D0,D3                           | D3 = feedback calculation
        LSR.B   #0x1,D0                         | shift LFSR right
        EOR.B   D0,D3                           | XOR for feedback tap
        LSR.B   #0x1,D3                         | isolate feedback bit
        BCC.B   SONY_SETSPEED_SKIP              | no feedback -> skip
        BSET    #0x5,D0                         | inject feedback into bit 5
SONY_SETSPEED_SKIP:
        DBF     D2,SONY_SETSPEED_LOOP           | iterate LFSR D2 times
        SWAP    D2                              | D2 = remainder (0-9)
        MOVE.B  SONY_SETSPEED_CONT_6(PC,D2.W),D5 | D5.hi = dither pattern MSB
        ASL     #0x8,D5                         | shift to high byte
        MOVE.B  SONY_SETSPEED_CONT_7(PC,D2.W),D5 | D5.lo = dither pattern LSB
        MOVEQ.L #0x24,D3                        | D3 = 36 (outer loop: 37 groups)
        MOVE.L  (PWMBuf1).w,A0                  | A0 = PWM buffer 1
        MOVE.L  (PWMBuf2).w,A2                  | A2 = PWM buffer 2
SONY_SETSPEED_LOOP_2:
        MOVEQ.L #0x9,D2                         | D2 = 9 (inner loop: 10 samples)
        MOVE    D5,D4                           | D4 = dither pattern for this group
SONY_SETSPEED_LOOP_3:
        LSL     #0x1,D4                         | shift dither bit into carry
        BCC.B   SONY_SETSPEED_CONT_4            | bit=0 -> use D1 (lower value)
        MOVE.B  D0,D6                           | bit=1 -> use D0 (higher value)
        BRA.B   SONY_SETSPEED_CONT_5            | write sample

| SONY_SETSPEED_CONT_4 -- dither bit is 0: use lower PWM value
SONY_SETSPEED_CONT_4:
        MOVE.B  D1,D6                           | use lower LFSR value
SONY_SETSPEED_CONT_5:
        MOVE.B  D6,(A0)                         | write to PWM buffer 1
        MOVE.B  D6,(A2)                         | write to PWM buffer 2
        ADDQ.W  #0x2,A0                         | advance by 2 (even addresses only)
        ADDQ.W  #0x2,A2                         | advance buffer 2 likewise
        DBF     D2,SONY_SETSPEED_LOOP_3         | inner loop: 10 samples per group
        DBF     D3,SONY_SETSPEED_LOOP_2         | outer loop: 37 groups = 370 samples
        MOVEM.L (SP)+,D3-D6/A2                  | restore registers
        BRA     Sony_SetupSonyVars              | reload SonyVars and return

| ----------------------------------------------------------
|
| SONY_SETSPEED_CONT_6
|
SONY_SETSPEED_CONT_6:
  .byte  0x00                                   | PWM dither pattern MSB (11 entries)
SONY_SETSPEED_CONT_7:
  .byte  0x20,0x21,0x24,0x94,0xAA,0xB5          | PWM dither pattern LSB, entries 0-5
  .byte 0xB7,0x7B,0xFF,0x40,0x00                | PWM dither pattern LSB, entries 6-10

| E_Sony_Seek -- seek head to target track.
E_Sony_Seek:
        BCLR    #0xB,D6                         | clear side bit, keep track only
        BSR     Sony_SetSpeed                   | program PWM speed for target zone
        MOVE.L  (DiskVars_JSeek).w,-(SP)        | push Seek vector address
        RTS                                     | dispatch to Sony_Seek

| ----------------------------------------------------------
|
| Sony Seek
|
| Sony_Seek: move head to target track D6
| Steps the stepper motor one track at a time via IWM phase lines.
| If current track unknown (negative), recalibrates first.
Sony_Seek:
        MOVE.L  (SP)+,A6                        | save return address
        BSR     Sony_SetupSonyVars              | set up SonyVars (A1) and drive vars
        MOVE    0x0(A1,D1.W),D7                 | D7 = current track number
        BPL.B   SEEK_2                          | known track ->
| track unknown: recalibrate first
        BSR     E_Sony_Recal                    | recal to track 0
        MOVE    D0,D7                           | D7 = 0 (after recal)
        BRA.B   SONY_SEEK_ERR                   | -> check if at target

| ----------------------------------------------------------
|
| Seek: step loop
|
SEEK_2:
        CMP     D6,D7                           | at target track?
        BEQ.B   SONY_SEEK_DONE                  | yes, done ->
| set up step direction
SONY_SEEK_CONT:
        MOVEQ.L #0x0,D0                         | D0 = 0: DIRTN toward track 0
        MOVEQ.L #0x1,D1                         | D1 = +1: step increment
        MOVE    D7,D2                           | D2 = current track
        SUB     D6,D2                           | D2 = current - target
        BEQ.B   SONY_SEEK_ERR                   | at target -> store and settle
        BMI.B   SONY_SEEK_CONT_2                | current < target -> step outward
        MOVEQ.L #0x1,D0                         | D0 = 1: DIRTN toward track 0
        MOVEQ.L #-0x1,D1                        | D1 = -1: step inward
SONY_SEEK_CONT_2:
        ADD     D1,D7                           | advance track count by step delta
        BSR     Sony_WriteDriveRegAdr           | write DIRTN: set step direction
        MOVE    D7,0x0(A1,D1.W)                 | update current track position
        MOVEQ.L #0x4,D0                         | STEP sense register
        BSR     Sony_ReadDriveRegAdr            | read STEP: 1=stepper can step
        BMI.B   SONY_SEEK_CONT_3                | stepper ready -> perform step
        MOVEQ.L #-0x4B,D7                       | cantStepErr (-75): stepper jammed
        BRA.B   SONY_SEEK_ERR                   | store error as track position

| ----------------------------------------------------------
|
| SONY_SEEK_CONT_3
|
SONY_SEEK_CONT_3:
        BSR     Sony_WriteDriveReg              | write STEP: execute one step pulse
        BSR.B   SONY_SEEK_CONT_4                | WaitStep: delay for step settling
        BRA.B   SONY_SEEK_CONT                  | check if at target track

| ----------------------------------------------------------
|
| SONY_SEEK_ERR
|
| SONY_SEEK_ERR -- store final track, wait for head settle and motor ready
SONY_SEEK_ERR:
        BSR     Sony_SetupSonyVars              | reload SonyVars and drive offset
        MOVE    D7,0x0(A1,D1.W)                 | save final track position
        MOVE    HeadSettle(A1),D0               | D0 = head settle delay
        MOVEQ.L #0x5,D2                         | D2 = max READY poll attempts
        BSR     SONY_SEEK_CONT_7                | wait for head settle + READY
SONY_SEEK_DONE:
        MOVE    iconIDCC(A1),D0                 | D0 = remaining motor settle time
        MOVEQ.L #0x0,D2                         | D2 = 0 (no initial delay)
        BSR     SONY_SEEK_CONT_7                | wait for motor READY
        MOVE    D7,D0                           | D0 = current track (return value)
        JMP     (A6)                            | return to caller

| -------------------------------------------------------
| SONY_SEEK_CONT_4 -- WaitStep: delay for seek time, poll STEP completion
| Used by 400K drives that need explicit step timing.
SONY_SEEK_CONT_4:
        MOVE    SeekTime(A1),D0                 | D0 = inter-step delay (12ms)
        BSR.B   SONY_SEEK_CONT_5                | 400K: sleep D0; 800K: continue
        MOVEQ.L #0x50,D5                        | D5 = 80 polls for step complete
SONY_SEEK_LOOP:
        MOVEQ.L #0x4,D0                         | STEP sense register
        BSR     Sony_ReadDriveRegAdr            | read STEP, 1 = step done
        DBMI    D5,SONY_SEEK_LOOP               | poll until step complete or timeout
        RTS                                     | return to seek loop

| -------------------------------------------------------
| SONY_SEEK_CONT_5 -- Delay400K: if 400K drive, pop return and sleep D0 ticks
| 800K drives handle step timing in hardware, so this is a no-op.
SONY_SEEK_CONT_5:
        TST.B   0x13(A1,D1.W)                   | NewIntf: 800K interface?
        BPL.B   SONY_SEEK_CONT_6                | 400K -> need explicit delay
        RTS                                     | 800K -> return (hw handles timing)

| SONY_SEEK_CONT_6 -- 400K drive: pop caller's return, sleep D0 ticks
SONY_SEEK_CONT_6:
        ADDQ.W  #0x4,SP                         | discard SONY_SEEK_CONT_4/SONY_SEEK_CONT_7 return address
        TST     D0                              | delay = 0?
        BEQ.B   SONY_SEEK_OK                    | yes -> no delay needed
        BRA.B   E_Sony_WakeUp                   | sleep D0 tenths-of-ms via Timer

| SONY_SEEK_OK -- no delay needed
SONY_SEEK_OK:
        RTS                                     | return to caller

| -------------------------------------------------------
| SONY_SEEK_CONT_7 -- WaitReady: initial delay, then poll READY sense line
| D0 = initial delay (tenths-of-ms), D2 = initial wait count
SONY_SEEK_CONT_7:
        BSR.B   SONY_SEEK_CONT_5                | delay if 400K drive
        MOVE.L  (SP)+,A4                        | A4 = return address
        MOVE    #0x3E8,D5                       | D5 = 1000 READY poll attempts
        MOVE    D2,D0                           | D0 = initial wait delay
        BEQ.B   SONY_SEEK_SKIP                  | zero -> skip initial delay
SONY_SEEK_LOOP_2:
        BSR.B   E_Sony_WakeUp                   | sleep D0 via Time Manager
SONY_SEEK_SKIP:
        MOVEQ.L #0xB,D0                         | READY sense register
        BSR     Sony_ReadDriveRegAdr            | read READY, 0 = ready
        BPL.B   SONY_SEEK_DONE_2                | ready -> done
        MOVEQ.L #0xA,D0                         | D0 = 1ms retry delay
        DBF     D5,SONY_SEEK_LOOP_2             | retry until READY or timeout
SONY_SEEK_DONE_2:
        CLR     iconIDCC(A1)                    | clear motor settling countdown
        JMP     (A4)                            | return to caller

| E_Sony_WakeUp -- branch to subroutine.
| ----------------------------------------------------------
|
| E_Sony_Wake Up
|
| Called by: Sony_EjectOrSwitchDisk, SONY_EJECTORSWITCHDISK_LOOP, Sony_DCDReset, SONY_RESEEK_SKIP_2, SONY_SEEK_CONT_6 (and 6 more)
E_Sony_WakeUp:
        MOVE.L  (DiskVars_JWakeUp).w,-(SP)      | push WakeUp vector address
        RTS                                     | dispatch to Sony_WakeUp

| ----------------------------------------------------------
|
| Sony WakeUp
|
Sony_WakeUp:
        BSR.B   SONY_WAKEUP_CONT                | schedule timer for D0 delay
| SONY_WAKEUP_EXIT -- return to WakeUp continuation.
SONY_WAKEUP_EXIT:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return addr as continuation
        MOVEQ.L #0x0,D0                         | clear D0 for timer callback
        MOVEM.L D3-D7/A3-A6,0xD0(A1)            | save volatile regs in SonyVars
        ANDI    #-0x701,SR                      | restore IPL to 0 (enable interrupts)
        RTS                                     | return; timer callback resumes later

| -------------------------------------------------------
| SONY_WAKEUP_CONT -- StartTimer: subtract delay from motor countdown,
| set up Time Manager callback to resume after D0 tenths-of-ms.
SONY_WAKEUP_CONT:
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        SUB     D0,iconIDCC(A1)                 | subtract delay from motor countdown
        BGT.B   SONY_WAKEUP_CONT_2              | still positive -> keep value
        CLR     iconIDCC(A1)                    | clamp countdown at 0
SONY_WAKEUP_CONT_2:
        LEA.L   0x118(A1),A0                    | A0 = Time Manager queue element
        LEA.L   SONY_WAKEUP_CONT_3(PC),A1       | A1 = timer completion routine
        MOVE.L  A1,0x6(A0)                      | tmAddr = completion routine
        ANDI.L  #0xFFFF,D0                      | mask to 16-bit delay
        CMPI    #0xA,D0                         | minimum 1ms (10 tenths)?
        BCC.B   SONY_WAKEUP_OK                  | >= 10 -> use as-is
        MOVEQ.L #0xA,D0                         | enforce 1ms minimum
SONY_WAKEUP_OK:
        DIVU    #0xA,D0                         | convert tenths-of-ms to ms
        EXT.L   D0                              | sign-extend for _PrimeTime
        MOVE.L  (0x568).w,A1                    | A1 = _PrimeTime trap address
        JSR     (A1)                            | schedule timer callback
        BSR     Sony_SetupSonyVars              | reload SonyVars and drive offset
        RTS                                     | return to SONY_WAKEUP_EXIT (suspends operation)

| SONY_WAKEUP_CONT_3 -- timer completion routine: restore saved context
| Called by Time Manager when delay expires. Resumes the
| suspended disk operation from where SONY_WAKEUP_EXIT saved state.
SONY_WAKEUP_CONT_3:
        MOVEM.L D0-D7/A0-A6,-(SP)               | save all regs (timer context)
        BSR     Sony_SetupRegs                  | set up IWM/VIA/SonyVars
        MOVEM.L 0xD0(A1),D3-D7/A3-A6            | restore saved disk routine regs
        MOVEQ.L #0x0,D0                         | D0 = noErr
        BSR     SONY_FIGTRKSPD_EXIT             | push DskRtnAdr and return to it
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore timer context regs
        RTS                                     | return to Time Manager

| -------------------------------------------------------
| Sony_CheckDriveNumber -- invalidate track cache if drive matches
| If TCDrive matches current drive, clear it to force cache refill.
Sony_CheckDriveNumber:
        MOVE    0x102(A1),D0                    | D0 = TCDrive (cached drive number)
        CMP     TwoSideFmt(A1),D0               | matches current drive?
        BNE.B   SONY_CHECKDRIVENUMBER_NO        | no -> cache belongs to other drive
        CLR     0x102(A1)                       | invalidate cache for this drive
SONY_CHECKDRIVENUMBER_NO:
        RTS                                     | return to caller

| E_Sony_Recal -- recalibrate head to track 0.
| ----------------------------------------------------------
|
| E_Sony_Recal
|
E_Sony_Recal:
        MOVE.L  (DiskVars_JRecal).w,-(SP)       | push Recal vector address
        RTS                                     | dispatch to Sony_Recal

| ----------------------------------------------------------
|
| Sony Recal
|
| Sony_Recal -- recalibrate: move head to track 0
| Initializes IWM if needed, then steps toward track 0 until TK0 sense.
Sony_Recal:
        MOVE.L  (SP)+,A5                        | save return address in A5
        BSR     Sony_SetupRegs                  | set up A0=IWM, A2=VIA, A1=SonyVars
        BSR.B   Sony_CheckDriveNumber           | invalidate track cache
        MOVEQ.L #0x3F,D1                        | D1 = $3F: IWM mode register mask
        TST.B   0x1A00(A0)                      | Q6 on: enter status read mode
        MOVE.B  0x1C00(A0),D0                   | read IWM status register
        TST.B   0x1800(A0)                      | Q6 off: back to data mode
        AND.B   D1,D0                           | mask to mode bits
        CMP.B   D1,D0                           | mode = $3F (properly initialized)?
        BEQ.B   SONY_RECAL_SKIP                 | yes -> skip IWM init
| IWM not initialized: write mode register
        MOVEQ.L #0x2,D2                         | D2 = 0x20000 (128K retries)
        SWAP    D2                              | D2.hi = 2 -> D2 = $20000
SONY_RECAL_RETRY:
        MOVEQ.L #0x1F,D1                        | mode value: $1F
        MOVEQ.L #-0x4D,D0                       | initIWMErr (-77): assume failure
        SUBQ.L  #0x1,D2                         | decrement retry counter
        BMI.B   SONY_RECAL_ERR_2                | retries exhausted -> error
        TST.B   0x1000(A0)                      | ENABLE off (reset IWM state)
        TST.B   0x1A00(A0)                      | Q6 on: enter status mode
        MOVE.B  0x1C00(A0),D0                   | read IWM status register
        BTST    #0x5,D0                         | IWM in write mode?
        BNE.B   SONY_RECAL_RETRY                | yes -> retry
        AND.B   D1,D0                           | mask mode bits
        CMP.B   D1,D0                           | mode register correct now?
        BEQ.B   SONY_RECAL_OK                   | yes -> IWM initialized
        MOVE.B  D1,0x1E00(A0)                   | write IWM mode register = $1F
        TST.B   0x1C00(A0)                      | latch mode write
        BRA.B   SONY_RECAL_RETRY                | verify by re-reading

| SONY_RECAL_OK -- IWM initialized: start motor and begin recal
SONY_RECAL_OK:
        TST.B   0x1800(A0)                      | Q6 off: return to data mode
        BSR.B   Sony_MotorOn2                   | spin up motor with power-on delay
| SONY_RECAL_SKIP -- step loop: step toward track 0, polling TK0
SONY_RECAL_SKIP:
        MOVEQ.L #0x50,D7                        | D7 = 80 max steps (beyond track count)
SONY_RECAL_CONT:
        MOVE    SeekTime(A1),D0                 | D0 = inter-step delay
        TST.B   0x13(A1,D1.W)                   | NewIntf: 800K interface?
        BPL.B   SONY_RECAL_CONT_2               | 400K -> use full delay
        LSR     #0x1,D0                         | 800K -> half delay (hw assist)
SONY_RECAL_CONT_2:
        BSR     E_Sony_WakeUp                   | wait for step settling
        MOVEQ.L #0xA,D0                         | TK0 sense register
        BSR     Sony_ReadDriveRegAdr            | read TK0, 0 = at track 0
        BPL.B   SONY_RECAL_DONE                 | at track 0 -> done
        MOVEQ.L #0x1,D0                         | DIRTN=1: step toward track 0
        BSR     Sony_WriteDriveRegAdr           | write DIRTN
        MOVEQ.L #0x4,D0                         | STEP sense register
        BSR     Sony_ReadDriveRegAdr            | read STEP, 1 = step done
        BPL.B   SONY_RECAL_ERR                  | step not possible -> error
        MOVEQ.L #-0x4C,D0                       | tk0BadErr (-76): can't find track 0
        SUBQ.W  #0x1,D7                         | decrement step counter
        BEQ.B   SONY_RECAL_ERR_2                | 80 steps done -> return error
        BSR     Sony_WriteDriveReg              | write STEP: execute one step
        BRA.B   SONY_RECAL_CONT                 | continue stepping

| SONY_RECAL_DONE -- reached track 0 successfully
SONY_RECAL_DONE:
        MOVEQ.L #0x0,D0                         | noErr
        BRA.B   SONY_RECAL_ERR_2                | save track and return

| ----------------------------------------------------------
|
| SONY_RECAL_ERR
|
SONY_RECAL_ERR:
        MOVEQ.L #-0x4B,D0                       | error -75, can't step error
SONY_RECAL_ERR_2:
        MOVE    D0,0x0(A1,D1.W)                 | save result as track (0 or error)
        JMP     (A5)                            | return to recal caller via saved A5

| ----------------------------------------------------------
|
| Sony MotorOff -- schedule or execute motor power-down
| D0 = delay in VBL ticks (0 = immediate off)
Sony_MotorOff:
        BSR     Sony_SetupSonyVars              | set up SonyVars and drive offset
        MOVE    D0,TrkSpeedTbl(A1)              | PwrOffDelay: set VBL countdown
        BEQ.B   SONY_MOTOROFF_EMPTY             | zero -> immediate power-off
        MOVE    TwoSideFmt(A1),0x116(A1)        | PwrOffDrive: remember which drive
        RTS                                     | VBL task will power off later

| SONY_MOTOROFF_EMPTY -- immediate motor off
SONY_MOTOROFF_EMPTY:
        MOVEQ.L #0x9,D0                         | MOTOROFF register address
        BSR     Sony_WriteDriveRegAdr           | write MOTOROFF: stop motor
        TST.B   0x1000(A0)                      | ENABLE off: deselect drive
        RTS                                     | return to caller

| -------------------------------------------------------
| Sony_MotorOn1 -- turn on motor with no settling delay
Sony_MotorOn1:
        MOVEQ.L #0x0,D0                         | D0 = 0: no settling delay
        BRA.B   SONY_MOTORON2_CONT              | common motor-on path

| -------------------------------------------------------
| Sony_MotorOn2 -- turn on motor with full power-on delay
Sony_MotorOn2:
        MOVE    PwrOnTime(A1),D0                | D0 = configured power-on delay
SONY_MOTORON2_CONT:
        MOVE    D0,D2                           | D2 = settling delay for SONY_SEEK_CONT_7
        BSR.B   Sony_JumpDiskSel                | select drive interface
        MOVEQ.L #0x8,D0                         | MOTORON sense register
        BSR     Sony_ReadDriveRegAdr            | read MOTORON, 0 = already on
        BPL.B   SONY_MOTORON2_EXIT              | already running -> return
        BSR     Sony_WriteDriveReg              | write MOTORON: start motor
        MOVE    D2,D0                           | D0 = settling delay
        MOVE    #0x2EE,D2                       | D2 = 750 READY poll attempts
        BRA     SONY_SEEK_CONT_7                | wait for settle + READY

| SONY_MOTORON2_EXIT -- motor already on
SONY_MOTORON2_EXIT:
        RTS                                     | motor running, return immediately

| Sony_JumpDiskSel -- select this drive's interface.
| ----------------------------------------------------------
|
| Sony JumpDiskSel
|
Sony_JumpDiskSel:
        BSR     Sony_SetupRegs                  | set up A0=IWM, A2=VIA, A1=SonyVars
| E_Sony_DiskSel -- select drive interface.
E_Sony_DiskSel:
        MOVE.L  (JDiskSel).w,-(SP)              | push DiskSel vector address
        RTS                                     | dispatch to Sony_DiskSel

| ----------------------------------------------------------
|
| Sony DiskSel
|
| Sony_DiskSel -- select and enable the correct drive interface
| Handles internal (drive 1), external (drive 2), and DCD (3+)
| drive selection via IWM phase lines and VIA port A.
Sony_DiskSel:
        TST     TrkSpeedTbl(A1)                 | PwrOffDelay: motor-off pending?
        BEQ.B   SONY_DISKSEL_SKIP               | no -> skip
        MOVE    0x116(A1),D0                    | PwrOffDrive: which drive?
        CMP     TwoSideFmt(A1),D0               | same as current drive?
        BEQ.B   SONY_DISKSEL_SKIP               | yes -> don't power off yet
        MOVEQ.L #0x0,D0                         | immediate power-off
        BSR.B   Sony_MotorOff                   | stop other drive's motor
SONY_DISKSEL_SKIP:
        CLR     TrkSpeedTbl(A1)                 | clear pending power-off timer
        CMPI    #0x4A,D1                        | drive 1 (internal)?
        BNE.B   SONY_DISKSEL_NO                 | no -> external/DCD path
        TST.B   0x1400(A0)                      | INTDRV: select internal drive
        TST.B   0x1200(A0)                      | ENABLE: activate drive
        RTS                                     | return

| SONY_DISKSEL_NO -- external drive path: set all phase lines for ext select
SONY_DISKSEL_NO:
        TST.B   0xA00(A0)                       | CA2 on
        TST.B   0x600(A0)                       | CA1 on
        TST.B   0x200(A0)                       | CA0 on
        BCLR    #0x5,0x1E00(A2)                 | SEL off (VIA Port A bit 5)
        TST.B   0x1600(A0)                      | EXTDRV: select external drive
        TST.B   0xFC(A1)                        | PassThru: ext chain supported?
        BEQ.B   SONY_DISKSEL_OK                 | yes -> DCD chain selection
        TST.B   0x1200(A0)                      | ENABLE: activate drive
        RTS                                     | no pass-thru: simple ext select

| SONY_DISKSEL_OK -- DCD chain: select drive by toggling phase lines
SONY_DISKSEL_OK:
        CMPI    #0x8C,D1                        | drive 2 (external floppy)?
        BNE.B   SONY_DISKSEL_NO_2               | no -> DCD drive (3+)
        TST.B   0x1200(A0)                      | ENABLE: activate drive 2
        MOVEQ.L #0x4,D0                         | D0 = 5 poll attempts
SONY_DISKSEL_CONT:
        MOVE    SR,-(SP)                        | save SR
        ORI     #0x300,SR                       | raise IPL to mask interrupts
        TST.B   0x1A00(A0)                      | Q6 on: enter status mode
SONY_DISKSEL_CONT_2:
        TST.B   0x1C00(A0)                      | read IWM status: drive ready?
        DBPL    D0,SONY_DISKSEL_LOOP            | poll until ready or timeout
        TST.B   0x1800(A0)                      | Q6 off: return to data mode
        MOVE    (SP)+,SR                        | restore SR
        RTS                                     | return

| SONY_DISKSEL_LOOP -- DCD handshake: toggle LSTRB and phase lines for sync
SONY_DISKSEL_LOOP:
        TST.B   0xE00(A0)                       | LSTRB on: clock pulse high
        MOVE.L  (SP),(SP)                       | delay (4 bus cycles)
        TST.B   0xC00(A0)                       | LSTRB off: clock pulse low
        MOVE.L  (SP),(SP)                       | delay
        TST.B   0x400(A0)                       | CA1 off: toggle phase
        MOVE.L  (SP),(SP)                       | delay
        TST.B   0x600(A0)                       | CA1 on: toggle phase
        MOVE.L  (SP),(SP)                       | delay
        BRA.B   SONY_DISKSEL_CONT_2             | continue polling

| SONY_DISKSEL_NO_2 -- DCD drive (3+): disable previous, enable new drive
SONY_DISKSEL_NO_2:
        TST.B   0x1000(A0)                      | ENABLE off: deselect previous
        MOVE    TwoSideFmt(A1),D0               | current drive number
        MOVE.L  (SP),(SP)                       | delay for drive deselect settling
        TST.B   0x1200(A0)                      | ENABLE on: select new drive
        SUBQ.W  #0x3,D0                         | D0 = DCD chain position (0-based)
        BRA.B   SONY_DISKSEL_CONT               | handshake with selected DCD

| acceptable disk RPM speed ranges
DT_Sony_SpeedCheckTbl:
  .byte 0x11,0xE9,0x11,0x35,0x13,0x8A           | zone 0: hi=0x11E9, lo=0x1135; zone 1 hi=0x138A
  .byte 0x12,0xC6,0x15,0x7F,0x14,0xA7           | zone 1 lo=0x12C6; zone 2: hi=0x157F, lo=0x14A7
  .byte 0x17,0xE2,0x16,0xF2,0x1A,0xDE           | zone 3: hi=0x17E2, lo=0x16F2; zone 4 hi=0x1ADE
  .byte 0x19,0xD0                               | zone 4 lo=0x19D0

| E_Sony_MakeSpdTbl -- build speed correction table.
E_Sony_MakeSpdTbl:
        MOVE.L  (DiskVars_JMakeSpdTbl).w,-(SP)  | push MakeSpdTbl vector address
        RTS                                     | dispatch to Sony_MakeSpdTbl

| ----------------------------------------------------------
|
| Sony MakeSpdTbl
|
| Sony_MakeSpdTbl -- build speed calibration table for all zones
| For 800K drives (new interface), just delays $1F40 (800ms).
| For 400K drives, measures RPM at two PWM values and interpolates.
Sony_MakeSpdTbl:
        TST.B   0x13(A1,D1.W)                   | NewIntf: 800K interface?
        BPL.B   SONY_MAKESPDTBL_CONT            | 400K -> calibrate via TACH
        MOVE    #0x1F40,D0                      | 800ms settling delay for 800K
        BRA     E_Sony_WakeUp                   | just wait, no PWM calibration

| ----------------------------------------------------------
|
| SONY_MAKESPDTBL_CONT
|
| SONY_MAKESPDTBL_CONT -- 400K drive: calibrate speed by measuring at two PWM values
| Measures RPM at PWM=$80 and PWM=$100, interpolates for each zone.
SONY_MAKESPDTBL_CONT:
        MOVE.L  (SP)+,A4                        | A4 = return address
        MOVE    #0x80,D2                        | first calibration PWM = $80
        BSR.B   SONY_MAKESPDTBL_CONT_5          | measure speed -> D4
        BMI.B   SONY_MAKESPDTBL_ERR             | measurement failed -> abort
        MOVE.L  D4,D3                           | D3 = speed at PWM $80
        MOVE    #0x100,D2                       | second calibration PWM = $100
        BSR.B   SONY_MAKESPDTBL_CONT_5          | measure speed -> D4
        BMI.B   SONY_MAKESPDTBL_ERR             | measurement failed -> abort
        MOVE.L  D4,D5                           | D5 = speed at PWM $100
        SUB.L   D3,D5                           | D5 = speed difference (slope)
        BGT.B   SONY_MAKESPDTBL_CONT_2          | positive -> valid slope
        MOVEQ.L #0x1,D5                         | clamp minimum to avoid div-by-zero
SONY_MAKESPDTBL_CONT_2:
        LSL.L   #0x1,D3                         | D3 = 2 * speed_low (interpolation)
        MOVEQ.L #0x4,D6                         | D6 = 4 (5 speed zones, 0-based)
        LEA.L   DT_Sony_SpeedCheckTbl(PC),A5    | A5 -> target RPM range table
        BSR     Sony_SetupSonyVars              | reload drive offset
        LEA.L   0x1A(A1,D1.W),A3                | A3 -> per-drive speed table
| SONY_MAKESPDTBL_LOOP -- compute PWM values for each zone pair
SONY_MAKESPDTBL_LOOP:
        MOVEQ.L #0x0,D2                         | clear for word load
        MOVE    (A5)+,D2                        | D2 = upper RPM limit for zone
        MOVE.L  D2,D7                           | D7 = save upper limit
        ADD     (A5)+,D2                        | D2 += lower RPM limit
        LSR     #0x1,D2                         | D2 = midpoint RPM for zone
SONY_MAKESPDTBL_CONT_3:
        ADD.L   D4,D2                           | offset by measured speed
        SUB.L   D3,D2                           | subtract 2*speed_low
        LSL.L   #0x7,D2                         | scale up for integer division
        BGT.B   SONY_MAKESPDTBL_CONT_4          | positive -> valid
        MOVEQ.L #0x1,D2                         | clamp to minimum 1
SONY_MAKESPDTBL_CONT_4:
        DIVU    D5,D2                           | D2 = interpolated PWM value
        ADDQ.W  #0x1,D2                         | round up
        CMPI    #0x18F,D2                       | exceeds max PWM ($18F)?
        BLE.B   SONY_MAKESPDTBL_OK              | no -> use as-is
        MOVE    #0x18F,D2                       | clamp to max
SONY_MAKESPDTBL_OK:
        MOVE    D2,(A3)+                        | store PWM for this zone limit
        EXG     D7,D2                           | swap: second limit of zone pair
        NOT     D0                              | toggle upper/lower limit flag
        BNE.B   SONY_MAKESPDTBL_CONT_3          | do second limit
        SUBQ.W  #0x4,A3                         | back up to compute delta
        SUB     (A3)+,D7                        | D7 = upper - lower PWM
        MOVE    D7,(A3)+                        | store delta for speed adjustment
        CLR.L   (A3)+                           | clear timestamp for this zone
        DBF     D6,SONY_MAKESPDTBL_LOOP         | next zone
SONY_MAKESPDTBL_ERR:
        TST     D0                              | set condition codes for caller
        JMP     (A4)                            | return

| -------------------------------------------------------
| SONY_MAKESPDTBL_CONT_5 -- MeasureSpeed: set PWM to D2, wait for spin-up,
| then average 4 TACH measurements to get drive speed.
| Returns speed value in D4, or negative D0 on error.
SONY_MAKESPDTBL_CONT_5:
        MOVE.L  (SP)+,A3                        | A3 = return address
        BSR     SONY_SETSPEED_CONT_3            | program PWM to value D2
        MOVE    PwrOnTime(A1),D0                | D0 = spin-up settling delay
        BSR     E_Sony_WakeUp                   | wait for motor to reach speed
| SONY_MAKESPDTBL_CONT_6 -- average 4 TACH period measurements
SONY_MAKESPDTBL_CONT_6:
        MOVEQ.L #0x0,D4                         | D4 = accumulated TACH time
        MOVEQ.L #0x3,D5                         | D5 = 3 (4 measurements, 0-based)
SONY_MAKESPDTBL_LOOP_2:
        BSR.B   E_Sony_FigTrkSpd                | measure time for 15 TACH edges
        BMI.B   SONY_MAKESPDTBL_ERR_2           | error -> abort
        ADD.L   D0,D4                           | accumulate TACH time
        DBF     D5,SONY_MAKESPDTBL_LOOP_2       | repeat 4 times
        LSR.L   #0x3,D4                         | D4 = average (sum/8, not sum/4)
        MOVE.L  #0x4000000,D0                   | D0 = constant for speed conversion
        DIVU    D4,D0                           | D0 = speed = $4000000 / avg_time
        MOVE    D0,D4                           | D4 = speed value
        MOVEQ.L #0x0,D0                         | D0 = noErr
SONY_MAKESPDTBL_ERR_2:
        JMP     (A3)                            | return to caller

| E_Sony_FigTrkSpd -- measure time for 15 TACH edges.
| ----------------------------------------------------------
|
| E_Sony_Fig Trk Spd
|
E_Sony_FigTrkSpd:
        MOVE.L  (DiskVars_JFigTrkSpd).w,-(SP)   | push FigTrkSpd vector address
        RTS                                     | dispatch to Sony_FigTrkSpd

| ----------------------------------------------------------
|
| Sony FigTrkSpd
|
| Sony_FigTrkSpd -- measure time for 15 TACH pulses
| Uses VIA Timer 2 as a free-running counter. Measures the
| time for 15 TACH edges via IWM status register bit 7.
| Returns elapsed time in D0 (positive), or -64 on error.
Sony_FigTrkSpd:
        MOVE    SR,-(SP)                        | save SR
        MOVEM.L D1-D7/A0-A6,-(SP)               | save all registers
        MOVEQ.L #0x4,D0                         | reserve 4 bytes on poll stack
        BSR     E_Sony_SetUpPoll                | set up SCC/VIA for polling
        MOVEQ.L #0xE,D0                         | TACH sense register address
        BSR     Sony_AdrDisk                    | address TACH via phase lines
        LEA.L   (IWM_Base).l,A0                 | A0 = IWM base (absolute)
        TST.B   0x1A00(A0)                      | Q6 on: enter status read mode
        MOVEQ.L #-0x1,D1                        | D1 = $FFFF: T2 max count
        MOVEQ.L #0x5,D3                         | D3 = 5: VIA IFR bit for T2 timeout
        MOVE.L  (VIA).w,A2                      | A2 = VIA base
        LEA.L   0x1A00(A2),A3                   | A3 = VIA IFR register
        LEA.L   0x1C00(A0),A1                   | A1 = IWM Q7L address (status read)
        BSR.B   SONY_FIGTRKSPD_CONT             | start VIA T2 free-run timer
        BSR.B   SONY_FIGTRKSPD_NEXT             | sync: wait for first TACH edge
        BEQ.B   SONY_FIGTRKSPD_CONT_2           | synchronized -> begin measurement
SONY_FIGTRKSPD_ERR:
        TST.B   0x1800(A0)                      | Q6 off: return to data mode
        BSR     SONY_RESEEK_CONT_8              | call PollProc
        MOVEM.L (SP)+,D1-D7/A0-A6               | restore all registers
        MOVE    (SP)+,SR                        | restore SR
        TST.L   D0                              | set condition codes on result
        RTS                                     | return

| -------------------------------------------------------
| SONY_FIGTRKSPD_CONT -- StartT2: load VIA Timer 2 with $FFFF and start counting
SONY_FIGTRKSPD_CONT:
        MOVE.B  D1,0x1000(A2)                   | T2L-L = $FF
        MOVE.B  D1,0x1200(A2)                   | T2C-H = $FF: starts countdown
        RTS                                     | return

| SONY_FIGTRKSPD_CONT_2 -- TACH synchronized: restart T2 and count 15 edges
SONY_FIGTRKSPD_CONT_2:
        BSR.B   SONY_FIGTRKSPD_CONT             | restart T2 at $FFFF
        MOVEQ.L #0xE,D2                         | D2 = 14 (15 edges, 0-based)
SONY_FIGTRKSPD_LOOP:
        BSR.B   SONY_FIGTRKSPD_NEXT             | wait for next TACH edge
        BNE.B   SONY_FIGTRKSPD_ERR              | timeout -> error exit
        DBF     D2,SONY_FIGTRKSPD_LOOP          | count 15 TACH edges
| read T2 counter value (elapsed = $FFFF - T2)
        MOVE.B  0x1200(A2),D2                   | read T2C-H (high byte)
        MOVE.B  0x1000(A2),D1                   | read T2C-L (low byte)
        CMP.B   0x1200(A2),D2                   | T2C-H changed during read?
        BEQ.B   SONY_FIGTRKSPD_OK               | no -> reading is consistent
        MOVEQ.L #0x0,D1                         | yes -> clear low byte (ambiguous)
SONY_FIGTRKSPD_OK:
        BTst    D3,(A3)                         | IFR bit 5: T2 timed out?
        BNE.B   SONY_FIGTRKSPD_ERR              | yes -> measurement invalid
        LSL     #0x8,D2                         | D2 = high byte << 8
        OR.B    D1,D2                           | D2 = 16-bit T2 remaining
        NOT     D2                              | D2 = $FFFF - remaining = elapsed
        MOVEQ.L #0x0,D0                         | clear high word
        MOVE    D2,D0                           | D0 = elapsed time for 15 TACH edges
        BRA.B   SONY_FIGTRKSPD_ERR              | return with D0 = time

| -------------------------------------------------------
| SONY_FIGTRKSPD_NEXT -- WaitTACH: detect a TACH rising edge (0->1 transition)
| Looks for two consecutive 0s then two consecutive 1s on TACH.
| Services SCC data during wait. Returns Z=1 if edge found,
| Z=0 (D0=-64) if T2 timeout or drive disconnected.
SONY_FIGTRKSPD_NEXT:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
| scan for TACH=0 (low phase)
SONY_FIGTRKSPD_NO:
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_FIGTRKSPD_SKIP             | busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_FIGTRKSPD_SKIP:
        TST.B   (A1)                            | read IWM status (TACH in bit 7)
        BMI.B   SONY_FIGTRKSPD_NO_2             | TACH=1 -> not low yet
        TST.B   (A1)                            | confirm second consecutive 0
        BPL.B   SONY_FIGTRKSPD_FOUND            | two 0s found -> scan for 1s
SONY_FIGTRKSPD_NO_2:
        BTst    D3,(A3)                         | VIA IFR bit 5: T2 timed out?
        BEQ.B   SONY_FIGTRKSPD_NO               | no -> keep scanning
SONY_FIGTRKSPD_ERR_2:
        MOVEQ.L #-0x40,D0                       | nsDrvErr (-64): timeout/disconnected
| SONY_FIGTRKSPD_EXIT -- resume continuation: push saved return and dispatch
SONY_FIGTRKSPD_EXIT:
        MOVE.L  (DskRtnAdr).w,-(SP)             | push saved continuation address
        TST     D0                              | set condition codes on result
        RTS                                     | return to continuation

| SONY_FIGTRKSPD_FOUND -- TACH went low: now scan for rising edge (two 1s)
SONY_FIGTRKSPD_FOUND:
        TST.B   (A5)                            | SCC wait/request?
        BMI.B   SONY_FIGTRKSPD_SKIP_2           | busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_FIGTRKSPD_SKIP_2:
        BTst    D3,(A3)                         | T2 timed out?
        BNE.B   SONY_FIGTRKSPD_ERR_2            | yes -> error
        TST.B   (A1)                            | read TACH
        BPL.B   SONY_FIGTRKSPD_FOUND            | still 0 -> keep waiting
        TST.B   (A1)                            | confirm second consecutive 1
        BPL.B   SONY_FIGTRKSPD_FOUND            | false alarm -> keep waiting
        MOVEQ.L #0x0,D0                         | noErr: rising edge detected
        BRA.B   SONY_FIGTRKSPD_EXIT             | return success

| ----------------------------------------------------------
|
| Sony CheckForNewDisks
|
| -------------------------------------------------------
| Sony_CheckForNewDisks -- VBL task: poll drives for inserted disks
| Called every ~0.5 sec by Vertical Retrace Manager.
| Also handles deferred motor power-off countdown.
Sony_CheckForNewDisks:
        MOVE    SR,-(SP)                        | save interrupt state
        ORI     #0x100,SR                       | raise IPL to 1 (mask level-1 ints)
        MOVE.L  (SonyVars).w,A1                 | load SonyVars
        MOVE    0x40(A1),0xA(A0)                | DskVBLTime: reload VBLCount
        TST.B   0x19(A1)                        | Active: driver busy?
        BNE.B   SONY_CHECKFORNEWDISKS_EXIT      | yes -> skip polling
        TST     TrkSpeedTbl(A1)                 | PwrOffDelay: motor-off pending?
        BEQ.B   SONY_CHECKFORNEWDISKS_NO        | no -> poll drives
        SUBQ.W  #0x1,TrkSpeedTbl(A1)            | decrement motor-off countdown
        BNE.B   SONY_CHECKFORNEWDISKS_EXIT      | not yet -> return
        MOVEQ.L #0x9,D0                         | MOTOROFF register
        BSR     Sony_WriteDriveRegAdr           | power off motor
SONY_CHECKFORNEWDISKS_NO:
        MOVEQ.L #0x1,D3                         | D3 = first drive to poll
SONY_CHECKFORNEWDISKS_OK:
        BSR.B   Sony_CheckForDiskInserted       | check this drive for disk
        ADDQ.W  #0x1,D3                         | next drive number
        CMPI    #0x6,D3                         | past max drive count?
        BGT.B   SONY_CHECKFORNEWDISKS_DONE      | yes -> done
        TST.B   0xFC(A1)                        | PassThru: ext chain available?
        BEQ.B   SONY_CHECKFORNEWDISKS_OK        | yes -> check all drives
        CMPI    #0x3,D3                         | past floppy drives?
        BLE.B   SONY_CHECKFORNEWDISKS_OK        | no -> keep checking floppies
SONY_CHECKFORNEWDISKS_DONE:
        TST.B   0x1000(A0)                      | ENABLE off: deselect all drives
SONY_CHECKFORNEWDISKS_EXIT:
        MOVE    (SP)+,SR                        | restore interrupt state
        RTS                                     | return

| ----------------------------------------------------------
|
| Sony CheckForDiskInserted
|
| -------------------------------------------------------
| Sony_CheckForDiskInserted -- poll one drive for new disk
| D3 = drive number. Posts diskInsertEvt if disk detected.
Sony_CheckForDiskInserted:
        MOVE    D3,TwoSideFmt(A1)               | set current drive number
        BSR     Sony_SetupRegs                  | set up IWM/VIA/drive vars
        TST.B   0x4(A1,D1.W)                    | Installed: drive present?
        BMI.B   SONY_CHECKFORDISKINSERTED_SKIP_2 | not installed -> skip
        TST.B   0x3(A1,D1.W)                    | DiskInPlace: disk present?
        BGT.B   SONY_CHECKFORDISKINSERTED_SKIP_2 | disk already known -> skip
        BEQ.B   SONY_CHECKFORDISKINSERTED_NO    | no disk -> check sense line
        ADDQ.B  #0x1,0x3(A1,D1.W)               | eject sentinel: advance toward 0
        BMI.B   SONY_CHECKFORDISKINSERTED_SKIP  | still negative -> not ready yet
SONY_CHECKFORDISKINSERTED_NO:
        BSR     E_Sony_DiskSel                  | select drive interface
        CMPI    #0x2,TwoSideFmt(A1)             | floppy drive (1-2)?
        BLE.B   SONY_CHECKFORDISKINSERTED_OK    | yes -> floppy sense
| DCD drive: read disk-present sense directly
        TST.B   (A0)                            | CA0 off
        TST.B   0x800(A0)                       | CA2 off
        BSR     Sony_ReadDriveReg               | read DCD disk-present status
        BMI.B   SONY_CHECKFORDISKINSERTED_CONT  | DCD present -> post event
        BRA.B   SONY_CHECKFORDISKINSERTED_SKIP  | not present -> mark track unknown

| SONY_CHECKFORDISKINSERTED_OK -- floppy: read CSTIN sense line
SONY_CHECKFORDISKINSERTED_OK:
        MOVEQ.L #0x2,D0                         | CSTIN sense register
        BSR     Sony_ReadDriveRegAdr            | read CSTIN, 0 = disk inserted
        BMI.B   SONY_CHECKFORDISKINSERTED_SKIP  | no disk -> mark track unknown
SONY_CHECKFORDISKINSERTED_CONT:
        MOVE    #0x7,A0                         | A0 = diskInsertEvt event code (7)
        MOVE.L  D3,D0                           | D0 = drive number (event message)
        _PostEvent                              | post disk-inserted event
        BNE.B   SONY_CHECKFORDISKINSERTED_SKIP  | event queue full -> skip
        ADDQ.B  #0x1,0x3(A1,D1.W)               | DiskInPlace = 1: disk inserted
SONY_CHECKFORDISKINSERTED_SKIP:
        ST.B    0x0(A1,D1.W)                    | Track = $FF: track unknown
        MOVE.L  (IWM).w,A0                      | reload IWM base for caller
SONY_CHECKFORDISKINSERTED_SKIP_2:
        RTS                                     | return

| header and trailer for sector address block
DT_Sony_SectorAdrTbl:
  .byte 0xD5,0xAA,0x96,0xDE,0xAA,0xFF           | header $D5AA96, trailer $DEAAFF

| E_Sony_SetUpPoll -- set up SCC/VIA for polling.
E_Sony_SetUpPoll:
        MOVE.L  (DiskVars_JSetUpPoll).w,-(SP)   | push SetUpPoll vector address
        RTS                                     | dispatch to Sony_SetUpPoll

| ----------------------------------------------------------
|
| Sony SetUpPoll
|
| -------------------------------------------------------
| Sony_SetUpPoll -- prepare SCC/VIA addresses for polling during I/O
| Sets A5=VIA Port A (for SCC wait/request check), A6=SCC data read.
| Saves PollStack for non-PollProc fallback.
| D0 = stack offset to reserve for polling.
Sony_SetUpPoll:
        LEA.L   (SCC_RdDataA).l,A6              | A6 = SCC channel A data read
        LEA.L   (VIA_PortA2).l,A5               | A5 = VIA port A (SCC wait/request)
        ORI     #0x300,SR                       | raise IPL to mask interrupts
        MOVE.L  A7,(PollStack).w                | save current SP as poll stack base
        ADD.L   D0,(PollStack).w                | reserve D0 bytes on poll stack
        RTS                                     | return

| -------------------------------------------------------
| SONY_SETUPPOLL_CONT -- ReadSectorAddr: set up polling, select head side,
| then call RdAddr to read sector address mark.
| Returns D1=track/side, D2=sector, D3=format byte.
SONY_SETUPPOLL_CONT:
        MOVEQ.L #0x8,D0                         | reserve 8 bytes on poll stack
        BSR.B   E_Sony_SetUpPoll                | set up A5/A6 and PollStack
        MOVEQ.L #0x1,D0                         | D0 = 1: head on side 0
        BTST    #0x3,DriveType(A1)              | side 1 requested?
        BEQ.B   SONY_SETUPPOLL_NO               | no -> side 0
        MOVEQ.L #0x3,D0                         | D0 = 3: head on side 1
SONY_SETUPPOLL_NO:
        BSR     Sony_AdrDisk                    | select head side via phase lines
| E_Sony_RdAddr -- read sector address field.
E_Sony_RdAddr:
        LEA.L   DT_Sony_SectorAdrTbl(PC),A2     | A2 = address of address marks table
        MOVE.L  (DiskVars_JRdAddr).w,-(SP)      | push JRdAddr vector
        RTS                                     | return

| ----------------------------------------------------------
|
| Sony RdAddr
|
| Sony_RdAddr: read sector address field from disk
| Scans for address mark ($D5 $AA $96), decodes track/sector/side/checksum
| Uses IWM data register (Q6=off, Q7=off) via A4 pointer
| Returns: track in D4, sector in D5, side in D6
Sony_RdAddr:
        MOVEQ.L #0x3,D3                         | D3 = address mark byte count (3)
        MOVEQ.L #0x7F,D2                        | D2 = timeout counter (128 bytes)
        MOVEQ.L #0x0,D5                         | D5 = disk data accumulator
        MOVE.L  #IWM_Q6L,A4                     | A4 = IWM data register (Q6L)
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
| scan for address mark sync bytes
SONY_RDADDR_SKIP:
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDADDR_CONT                | SCC busy ->
        MOVE.B  (A6),-(SP)                      | service SCC if needed
SONY_RDADDR_CONT:
        MOVE.B  (A4),D5                         | read byte from IWM data register
        DBF     D2,SONY_RDADDR_LOOP             | decrement timeout
        MOVEQ.L #-0x42,D0                       | noDtaMkErr (-66): no address mark found
        BRA     SONY_RDADDR_ERR                 | -> error exit

| ----------------------------------------------------------
|
| SONY_RDADDR_LOOP
|
SONY_RDADDR_LOOP:
        BPL.B   SONY_RDADDR_SKIP                | bit 7 clear: not a valid disk byte
        SUBQ.W  #0x1,D3                         | decrement sync byte counter
        BNE.B   SONY_RDADDR_SKIP                | need 3 consecutive valid bytes
        MOVE    #0x5DC,D0                       | D0 = 1500: scan timeout for 400K
        TST.B   0x13(A1,D1.W)                   | NewIntf: 800K interface?
        BEQ.B   SONY_RDADDR_CONT_2              | 400K -> use $5DC timeout
        MOVE    #0x5BC,D0                       | 800K -> slightly shorter timeout
SONY_RDADDR_CONT_2:
        LEA.L   DECODE_TBL(PC),A3               | A3 = GCR nibble decode table
SONY_RDADDR_CONT_3:
        MOVE.L  A2,A0                           | A0 -> address mark pattern $D5 $AA $96
        MOVEQ.L #0x3,D1                         | D1 = 3 header bytes to match
SONY_RDADDR_NEXT:
        MOVE.B  (A4),D5                         | read byte from IWM data register
        BPL.B   SONY_RDADDR_NEXT                | bit 7 clear: not valid, keep polling
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDADDR_SKIP_2              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDADDR_SKIP_2:
        DBF     D0,SONY_RDADDR_LOOP_2           | decrement scan timeout
        MOVEQ.L #-0x43,D0                       | badMkErr (-67): address mark not found
        BRA.B   SONY_RDADDR_ERR                 | return error

| ----------------------------------------------------------
|
| SONY_RDADDR_LOOP_2
|
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
        MOVE.B  0x0(A3,D5.W),D1                 | GCR decode: side + upper track bits
        EOR.B   D1,D4                           | accumulate into checksum
        ROL     #0x6,D1                         | D1 = full track/side descriptor
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDADDR_SKIP_3              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDADDR_SKIP_3:
        MOVE.B  (A4),D5                         | read 4th addr field byte
        BPL.B   SONY_RDADDR_SKIP_3              | poll until valid
        MOVE.B  0x0(A3,D5.W),D3                 | GCR decode: format byte
        EOR.B   D3,D4                           | accumulate into checksum
SONY_RDADDR_CONT_7:
        MOVE.B  (A4),D5                         | read 5th addr field byte (checksum)
        BPL.B   SONY_RDADDR_CONT_7              | poll until valid
        MOVE.B  0x0(A3,D5.W),D5                 | GCR decode: expected checksum
        EOR.B   D5,D4                           | XOR with accumulated: should be 0
        BNE.B   SONY_RDADDR_ERR_2               | nonzero -> checksum failed
        MOVEQ.L #0x1,D4                         | D4 = 1: expect 2 trailer bytes
SONY_RDADDR_LOOP_3:
        MOVE.B  (A4),D5                         | read trailer byte from disk
        BPL.B   SONY_RDADDR_LOOP_3              | poll until valid
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDADDR_SKIP_4              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDADDR_SKIP_4:
        CMP.B   (A0)+,D5                        | compare trailer against $DE, $AA
        BNE.B   SONY_RDADDR_ERR_3               | mismatch -> bad bit-slip error
        DBF     D4,SONY_RDADDR_LOOP_3           | read next trailer byte
SONY_RDADDR_ERR:
        BRA     SONY_FIGTRKSPD_EXIT             | done

| ----------------------------------------------------------
|
| SONY_RDADDR_ERR_2
|
SONY_RDADDR_ERR_2:
        MOVEQ.L #-0x45,D0                       | error -69, bad checksum error - bad address mark
        BRA.B   SONY_RDADDR_ERR                 | abort and return error

| ----------------------------------------------------------
|
| SONY_RDADDR_ERR_3
|
SONY_RDADDR_ERR_3:
        MOVEQ.L #-0x46,D0                       | error -70, bad BtSlp error - bad address mark
        BRA.B   SONY_RDADDR_ERR                 | abort and return error

| ----------------------------------------------------------
|
| DEADDRESS_TBL
|
| Data mark sync pattern: $D5 $AA $AD (data field header)
| Deaddress mark: $DE $AA $FF (data field trailer)
DEADDRESS_TBL:
  .byte  0xD5,0xAA,0xAD,0xDE,0xAA,0xFF          | data mark $D5AAAD, deaddress $DEAAFF
| RdData entry: set up data mark table and dispatch via vector
E_Sony_RdData:
        LEA.L   DEADDRESS_TBL(PC),A1            | A1 = data mark sync/deaddress table
        MOVE.L  (DiskVars_JRdData).w,-(SP)      | push RdData vector
        RTS                                     | jump to RdData implementation

| ----------------------------------------------------------
|
| Sony_RdData: read one sector of data from disk
| Scans for data mark ($D5 $AA $AD), reads 524 bytes of GCR-encoded data
| (512 data + 12 tag bytes), decodes 6-and-2 nibbles, verifies checksum
|
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
        MOVE.L  A1,A2                           | put header/trailer table pointer into A2
        MOVEQ.L #0x3,D1                         | D1 = 3 (sync bytes to match)
SONY_RDDATA_LOOP:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_LOOP                | wait for data ready (sign bit clear)
        TST.B   (A5)                            | _PollSCC: poll SCC modem port to avoid overruns
        BMI.B   SONY_RDDATA_SKIP                | _PollSCC: skip if no data
        MOVE.B  (A6),-(SP)                      | _PollSCC: push SCC data to poll stack
SONY_RDDATA_SKIP:
        DBF     D2,SONY_RDDATA_LOOP_2           | decrement timeout and loop
        MOVEQ.L #-0x47,D0                       | error -71, can't find data mark
        BRA.B   SONY_RDADDR_ERR                 | abort and return error

| ----------------------------------------------------------
|
| SONY_RDDATA_LOOP_2
|
SONY_RDDATA_LOOP_2:
        CMP.B   (A2)+,D3                        | compare the disk byte against the expected header
        BNE.B   SONY_RDDATA_CONT                | header mismatch, restart scan
        SUBQ.W  #0x1,D1                         | decrement remaining sync bytes count
        BNE.B   SONY_RDDATA_LOOP                | loop if more sync bytes to match
SONY_RDDATA_CONT_2:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_CONT_2              | wait for data ready (sign bit clear)
        LEA.L   (TagData_1).w,A1                | A1 = pointer to tag data buffer
        MOVE.B  0x0(A3,D3.W),(A1)+              | convert a byte of tags. Assuming A3 is a pointer to the nibble decode table
SONY_RDDATA_CONT_3:
        TST.B   (A5)                            | _PollSCC: poll SCC modem port to avoid overruns
        BMI.B   SONY_RDDATA_SKIP_2              | _PollSCC: skip if no data
        MOVE.B  (A6),-(SP)                      | _PollSCC: push SCC data to poll stack
SONY_RDDATA_SKIP_2:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_CONT_3              | wait for data ready (sign bit clear)
        MOVE.B  0x0(A3,D3.W),D1                 | GCR decode: 6-bit nibble with 2+2+2 extra bits
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
        OR.B    0x0(A3,D3.W),D1                 | combine decoded low 6 with high 2
        EOR.B   D6,D1                           | decrypt: XOR with checksum D6
        MOVE.B  D1,(A1)+                        | store decoded byte C
        ADDX.B  D1,D7                           | accumulate checksum C into D7
        SUBQ.W  #0x3,D4                         | decrement count of remaining bytes
        BPL.B   SONY_RDDATA_CONT_3              | branch if more bytes remain
        SWAP    D4                              | done with tag bytes
        TST.B   (DskVerify).w                   | verify-after-write mode?
        BEQ.B   SONY_RDDATA_SKIP_4              | no -> read data normally
        BRA.B   SONY_RDDATA_SKIP_6              | yes -> verify (compare) instead

| ----------------------------------------------------------
|
| SONY_RDDATA_LOOP_3
|
SONY_RDDATA_LOOP_3:
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDDATA_SKIP_4              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_4:
        MOVE.B  (A4),D3                         | read GCR nibble byte from disk
        BPL.B   SONY_RDDATA_LOOP_3              | poll until valid disk byte
        MOVE.B  0x0(A3,D3.W),D1                 | GCR decode: nibble with 3x2 extra bits
        ROL.B   #0x2,D1                         | rotate first 2 extra bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits
SONY_RDDATA_CONT_6:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_6              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine low 6 with high 2
        MOVE.B  D7,D3                           | D3 = checksum C
        ADD.B   D7,D3                           | D3 = 2*C (carry for ROL feedback)
        ROL.B   #0x1,D7                         | rotate checksum C left with carry
        EOR.B   D7,D2                           | decrypt byte A via XOR
        MOVE.B  D2,(A0)+                        | store decoded data byte A
        ADDX.B  D2,D5                           | accumulate into checksum D5
        ROL.B   #0x2,D1                         | rotate next 2 extra bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits
SONY_RDDATA_CONT_7:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_7              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine low 6 with high 2
        EOR.B   D5,D2                           | decrypt byte B via XOR
        MOVE.B  D2,(A0)+                        | store decoded data byte B
        ADDX.B  D2,D6                           | accumulate into checksum D6
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
        OR.B    0x0(A3,D3.W),D1                 | combine low 6 with high 2
        EOR.B   D6,D1                           | decrypt byte C via XOR
        MOVE.B  D1,(A0)+                        | store decoded data byte C
        ADDX.B  D1,D7                           | accumulate into checksum D7
        SUBQ.W  #0x3,D4                         | 3 bytes decoded per group
        BRA.B   SONY_RDDATA_LOOP_3              | loop for remaining data bytes

| ----------------------------------------------------------
|
| SONY_RDDATA_LOOP_4
|
SONY_RDDATA_LOOP_4:
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDDATA_SKIP_6              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_6:
        MOVE.B  (A4),D3                         | read GCR nibble from disk (verify)
        BPL.B   SONY_RDDATA_LOOP_4              | poll until valid
        MOVE.B  0x0(A3,D3.W),D1                 | GCR decode: nibble with 3x2 extra bits
        ROL.B   #0x2,D1                         | rotate first 2 extra bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits
SONY_RDDATA_CONT_8:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_8              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine low 6 with high 2
        MOVE.B  D7,D3                           | D3 = checksum C
        ADD.B   D7,D3                           | D3 = 2*C (carry for ROL)
        ROL.B   #0x1,D7                         | rotate checksum C left with carry
        EOR.B   D7,D2                           | decrypt byte A via XOR
        CMP.B   (A0)+,D2                        | compare decoded byte A with buffer
        BNE.B   SONY_RDDATA_ERR                 | mismatch -> verify error
        ADDX.B  D2,D5                           | accumulate checksum A
        ROL.B   #0x2,D1                         | rotate next 2 extra bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits
SONY_RDDATA_CONT_9:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_CONT_9              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine low 6 with high 2
        EOR.B   D5,D2                           | decrypt byte B via XOR
        CMP.B   (A0)+,D2                        | compare decoded byte B with buffer
        BNE.B   SONY_RDDATA_ERR_3               | mismatch -> read-verify error
        ADDX.B  D2,D6                           | accumulate checksum B
        TST     D4                              | bytes remaining?
        BEQ.B   SONY_RDDATA_DONE                | zero -> done, check checksum
        ROL.B   #0x2,D1                         | rotate last 2 extra bits
        AND.B   D0,D1                           | mask high 2 bits
DECODE_TBL:
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDDATA_SKIP_7              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_7:
        MOVE.B  (A4),D3                         | read next GCR byte (verify C)
        BPL.B   SONY_RDDATA_SKIP_7              | poll until valid
        OR.B    0x0(A3,D3.W),D1                 | combine low 6 with high 2
        EOR.B   D6,D1                           | decrypt byte C via XOR
        CMP.B   (A0)+,D1                        | compare decoded byte C with buffer
SONY_RDDATA_ERR:
        BNE.B   SONY_RDDATA_ERR_3               | mismatch -> read-verify error
        ADDX.B  D1,D7                           | accumulate checksum C
        SUBQ.W  #0x3,D4                         | 3 bytes verified per group
        BRA.B   SONY_RDDATA_LOOP_4              | loop for remaining verify bytes

| ----------------------------------------------------------
|
| SONY_RDDATA_DONE
|
SONY_RDDATA_DONE:
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDDATA_SKIP_8              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_8:
        MOVE.B  (A4),D3                         | read GCR checksum nibble byte
        BPL.B   SONY_RDDATA_SKIP_8              | poll until valid
        MOVE.B  0x0(A3,D3.W),D1                 | GCR decode: nibble with 4x2 cksum bits
        BMI.B   SONY_RDDATA_ERR_2               | $FF = invalid GCR byte
        ROL.B   #0x2,D1                         | rotate first 2 checksum bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits of checksum A
SONY_RDDATA_CONT_10:
        MOVE.B  (A4),D3                         | read checksum byte for D5
        BPL.B   SONY_RDDATA_CONT_10             | poll until valid
        MOVE.B  0x0(A3,D3.W),D3                 | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_ERR_2               | invalid GCR byte -> error
        OR.B    D3,D2                           | D2 = full 8-bit checksum A
        CMP.B   D2,D5                           | compare with accumulated D5
        BNE.B   SONY_RDDATA_ERR_2               | mismatch -> checksum error
        ROL.B   #0x2,D1                         | rotate next 2 checksum bits
        MOVE.B  D1,D2                           | copy for masking
        AND.B   D0,D2                           | mask high 2 bits of checksum B
SONY_RDDATA_CONT_11:
        MOVE.B  (A4),D3                         | read checksum byte for D6
        BPL.B   SONY_RDDATA_CONT_11             | poll until valid
        MOVE.B  0x0(A3,D3.W),D3                 | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_ERR_2               | invalid GCR byte -> error
        OR.B    D3,D2                           | D2 = full 8-bit checksum B
        CMP.B   D2,D6                           | compare with accumulated D6
        BNE.B   SONY_RDDATA_ERR_2               | mismatch -> checksum error
        ROL.B   #0x2,D1                         | rotate last 2 checksum bits
        AND.B   D0,D1                           | mask high 2 bits of checksum C
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDDATA_SKIP_9              | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_9:
        MOVE.B  (A4),D3                         | read checksum byte for D7
        BPL.B   SONY_RDDATA_SKIP_9              | poll until valid
        MOVE.B  0x0(A3,D3.W),D3                 | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_ERR_2               | invalid GCR byte -> error
        OR.B    D3,D1                           | D1 = full 8-bit checksum C
        CMP.B   D1,D7                           | compare with accumulated D7
        BEQ.B   SONY_RDDATA_CONT_12             | test the checksum
SONY_RDDATA_ERR_2:
        MOVEQ.L #-0x48,D0                       | error -72, bad data checksum, bad data mark
        BRA.B   SONY_RDDATA_CONT_13             | branch

| ----------------------------------------------------------
|
| SONY_RDDATA_ERR_3
|
SONY_RDDATA_ERR_3:
        MOVEQ.L #-0x44,D0                       | error -68, read-verify failed
        BRA.B   SONY_RDDATA_CONT_13             | branch

| ----------------------------------------------------------
|
| SONY_RDDATA_CONT_12
|
SONY_RDDATA_CONT_12:
        MOVEQ.L #0x1,D4                         | D4 = 1: expect 2 trailer bytes ($DE $AA)
SONY_RDDATA_LOOP_5:
        MOVE.B  (A4),D3                         | read trailer byte from disk
        BPL.B   SONY_RDDATA_LOOP_5              | poll until valid
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_RDDATA_SKIP_10             | SCC busy -> skip service
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_RDDATA_SKIP_10:
        CMP.B   (A2)+,D3                        | compare trailer against $DE, $AA
        BNE.B   SONY_RDDATA_ERR_4               | mismatch -> bad data bit-slip
        DBF     D4,SONY_RDDATA_LOOP_5           | read next trailer byte
        MOVEQ.L #0x0,D0                         | noErr: data read successful
SONY_RDDATA_CONT_13:
        BRA     SONY_FIGTRKSPD_EXIT             | branch

| ----------------------------------------------------------
|
| SONY_RDDATA_ERR_4
|
SONY_RDDATA_ERR_4:
        MOVEQ.L #-0x49,D0                       | error -73, bad DBtSlp, bad data mark
        BRA.B   SONY_RDDATA_CONT_13             | branch

| GCR decode table begins here, starting with disk byte $96
  .byte 0x00,0x01,0xFF,0xFF,0x02,0x03           | disk $96-$9B -> 6-bit values 0-3
  .byte 0xFF,0x04,0x05,0x06,0xFF,0xFF           | disk $9D-$9F -> values 4-6
  .byte 0xFF,0xFF,0xFF,0xFF,0x07,0x08           | disk $A6-$A7 -> values 7-8
  .byte 0xFF,0xFF,0xFF,0x09,0x0A,0x0B           | disk $AB-$AD -> values 9-11
  .byte 0x0C,0x0D,0xFF,0xFF,0x0E,0x0F           | disk $AE-$AF, $B2-$B3 -> values 12-15
  .byte 0x10,0x11,0x12,0x13,0xFF,0x14           | disk $B4-$B7 -> values 16-20
  .byte 0x15,0x16,0x17,0x18,0x19,0x1A           | disk $B9-$BE -> values 21-26
  .byte 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF           | disk $BF-$CA: invalid (0xFF)
  .byte 0xFF,0xFF,0xFF,0xFF,0xFF,0x1B           | disk $CB -> value 27
  .byte 0xFF,0x1C,0x1D,0x1E,0xFF,0xFF           | disk $CD-$CF -> values 28-30
  .byte 0xFF,0x1F,0xFF,0xFF,0x20,0x21           | disk $D3, $D6-$D7 -> values 31-33
  .byte 0xFF,0x22,0x23,0x24,0x25,0x26           | disk $D9-$DD -> values 34-38
  .byte 0x27,0x28,0xFF,0xFF,0xFF,0xFF           | disk $DE-$DF -> values 39-40
  .byte 0xFF,0x29,0x2A,0x2B,0xFF,0x2C           | disk $E5-$E7, $E9 -> values 41-44
  .byte 0x2D,0x2E,0x2F,0x30,0x31,0x32           | disk $EA-$EF -> values 45-50
  .byte 0xFF,0xFF,0x33,0x34,0x35,0x36           | disk $F2-$F5 -> values 51-54
  .byte 0x37,0x38,0xFF,0x39,0x3A,0x3B           | disk $F6-$F7, $F9-$FB -> values 55-59
  .byte 0x3C,0x3D,0x3E,0x3F                     | disk $FC-$FF -> values 60-63
SONY_RDDATA_CONT_14:
  .byte  0xFF,0x3F,0xCF,0xF3,0xFC,0xFF          | self-sync $FF, gap nibbles, self-sync
  .byte 0xD5,0xAA                               | data mark header $D5 $AA (+ $AD follows)

| E_Sony_WrData -- write sector data to disk.
E_Sony_WrData:
        LEA.L   SONY_RDDATA_CONT_14(PC),A2      | load effective address
        MOVE.L  (DiskVars_JWrData).w,-(SP)      | push address/value
        RTS                                     | return

| ----------------------------------------------------------
|
| Sony WrData
|
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
        MOVE.B  (A2)+,D1                        | load next header byte from template
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
        LEA.L   DT_Sony_NiblTbl(PC),A2          | A2 = GCR encode table (64 entries)
SONY_WRDATA_NO_2:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_2                | no -> wait
        MOVE.B  D1,(A3)                         | write $AA data mark to disk
        MOVEQ.L #0xB,D1                         | D1 = $0B: initial nibble value
        MOVE.B  (A1)+,D2                        | D2 = first tag byte
        BRA.B   SONY_WRDATA_LOOP_2              | enter GCR encode loop

| ----------------------------------------------------------
|
| SONY_WRDATA_CONT
|
SONY_WRDATA_CONT:
        MOVE.L  A0,A1                           | switch source from tags to data buffer
SONY_WRDATA_NEXT:
        ADDX.B  D2,D7                           | accumulate byte C into checksum D7
        EOR.B   D6,D2                           | encrypt byte C: XOR with checksum D6
        MOVE.B  D2,D3                           | D3 = encrypted byte C
        LSR     #0x6,D3                         | extract high 2 bits into D3
SONY_WRDATA_NO_3:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_3                | no -> wait
        MOVE.B  0x0(A2,D3.W),(A3)               | GCR encode high 2 bits of C
        SUBQ.W  #0x3,D4                         | 3 bytes encoded per group
        MOVE.B  D7,D3                           | D3 = checksum C
        ADD.B   D7,D3                           | D3 = 2*C (carry for ROL)
        ROL.B   #0x1,D7                         | rotate checksum C left with carry
        ANDI.B  #0x3F,D0                        | mask byte A to low 6 bits
SONY_WRDATA_NO_4:
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_WRDATA_SKIP_2              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_WRDATA_SKIP_2:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_4                | no -> wait (polls SCC while waiting)
        MOVE.B  0x0(A2,D0.W),(A3)               | GCR encode low 6 bits of byte A
SONY_WRDATA_LOOP_2:
        MOVE.B  (A1)+,D0                        | D0 = next source byte (A)
        ADDX.B  D0,D5                           | accumulate byte A into checksum D5
        EOR.B   D7,D0                           | encrypt byte A: XOR with checksum D7
        MOVE.B  D0,D3                           | save encrypted A for high bits
        ROL     #0x2,D3                         | rotate 2 high bits into D3
        ANDI.B  #0x3F,D1                        | mask byte B to low 6 bits
SONY_WRDATA_NO_5:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_5                | no -> wait
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
        BPL.B   SONY_WRDATA_SKIP_3              | no -> wait
        MOVE.B  0x0(A2,D2.W),(A3)               | GCR encode low 6 bits of byte C
        MOVE.B  (A1)+,D2                        | D2 = next source byte (C)
        TST     D4                              | bytes remaining in segment?
        BNE.B   SONY_WRDATA_NEXT                | yes -> encode next group
        SWAP    D4                              | swap: switch from tags to data count
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
        BPL.B   SONY_WRDATA_NO_7                | no -> wait
        MOVE.B  0x0(A2,D0.W),(A3)               | GCR encode checksum A low 6
        ANDI.B  #0x3F,D1                        | mask checksum B low 6 bits
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_WRDATA_SKIP_4              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_WRDATA_SKIP_4:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_SKIP_4              | no -> wait
        MOVE.B  0x0(A2,D1.W),(A3)               | GCR encode checksum B low 6
        MOVE.B  D7,D3                           | D3 = checksum C
        LSR     #0x6,D3                         | extract high 2 bits of checksum C
SONY_WRDATA_NO_8:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_8                | no -> wait
        MOVE.B  0x0(A2,D3.W),(A3)               | GCR encode checksum nibble
        ANDI.B  #0x3F,D5                        | mask checksum D5 low 6 bits
SONY_WRDATA_NO_9:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_9                | no -> wait
        MOVE.B  0x0(A2,D5.W),(A3)               | GCR encode checksum D5 low 6
        ANDI.B  #0x3F,D6                        | mask checksum D6 low 6 bits
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_WRDATA_SKIP_5              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_WRDATA_SKIP_5:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_SKIP_5              | no -> wait
        MOVE.B  0x0(A2,D6.W),(A3)               | GCR encode checksum D6 low 6
        ANDI.B  #0x3F,D7                        | mask checksum D7 low 6 bits
SONY_WRDATA_NO_10:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_10               | no -> wait
        MOVE.B  0x0(A2,D7.W),(A3)               | GCR encode checksum D7 low 6
        LEA.L   SONY_WRDATA_CONT_2(PC),A2       | A2 = data field trailer ($DE $AA $FF $FF)
        MOVEQ.L #0x3,D2                         | D2 = 3: write 4 trailer bytes
SONY_WRDATA_LOOP_3:
        MOVE.B  (A4),D1                         | read IWM handshake for write timing
        BPL.B   SONY_WRDATA_LOOP_3              | poll until ready
        MOVE.B  (A2)+,(A3)                      | write next trailer byte to disk
        TST.B   (A5)                            | check SCC wait/request
        BMI.B   SONY_WRDATA_SKIP_6              | SCC busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC receive data
SONY_WRDATA_SKIP_6:
        DBF     D2,SONY_WRDATA_LOOP_3           | loop for all 4 trailer bytes
        MOVEQ.L #0x0,D0                         | assume noErr
        BTST    #0x6,D1                         | IWM bit 6: write completed OK?
        BNE.B   SONY_WRDATA_OK                  | yes -> success
        MOVEQ.L #-0x4A,D0                       | wrUnderrun (-74): write underrun
SONY_WRDATA_OK:
        TST.B   (IWM_Q7L).l                     | Q7 off: exit write mode
        BRA     SONY_FIGTRKSPD_EXIT             | return via continuation

| ----------------------------------------------------------
|
| SONY_WRDATA_CONT_2
|
SONY_WRDATA_CONT_2:
  .byte  0xDE,0xAA,0xFF,0xFF                    | deaddress mark $DEAA, pad $FF $FF
DT_Sony_NiblTbl:
  .byte 0x96,0x97,0x9A,0x9B,0x9D,0x9E           | GCR encode: values 0-5
  .byte 0x9F,0xA6,0xA7,0xAB,0xAC,0xAD           | GCR encode: values 6-11
  .byte 0xAE,0xAF,0xB2,0xB3,0xB4,0xB5           | GCR encode: values 12-17
  .byte 0xB6,0xB7,0xB9,0xBA,0xBB,0xBC           | GCR encode: values 18-23
  .byte 0xBD,0xBE,0xBF,0xCB,0xCD,0xCE           | GCR encode: values 24-29
  .byte 0xCF,0xD3,0xD6,0xD7,0xD9,0xDA           | GCR encode: values 30-35
  .byte 0xDB,0xDC,0xDD,0xDE,0xDF,0xE5           | GCR encode: values 36-41
  .byte 0xE6,0xE7,0xE9,0xEA,0xEB,0xEC           | GCR encode: values 42-47
  .byte 0xED,0xEE,0xEF,0xF2,0xF3,0xF4           | GCR encode: values 48-53
  .byte 0xF5,0xF6,0xF7,0xF9,0xFA,0xFB           | GCR encode: values 54-59
  .byte 0xFC,0xFD,0xFE,0xFF                     | GCR encode: values 60-63
DT_SONY_NIBLTBL_CONT:
  .byte  0xFF,0x3F,0xCF,0xF3,0xFC,0xFF          | format template: self-sync, gap nibbles
  .byte 0xD5,0xAA,0x96,0x00,0x00,0x00           | addr mark $D5AA96, trk/sect/side=0
  .byte 0x00,0x00,0xDE,0xAA,0xFF,0xFF           | format/chksum=0, deaddr $DEAAFF
  .byte 0x3F,0xCF,0xF3,0xFC,0xFF,0xD5           | gap nibbles, self-sync, data mark $D5
  .byte 0xAA,0xAD,0x00,0x00                     | data mark $AAAD, pad bytes

| -------------------------------------------------------
| DT_SONY_NIBLTBL_CONT_2 -- Format: low-level format a floppy disk
| Allocates 512-byte stack buffer, writes all 80 tracks.
DT_SONY_NIBLTBL_CONT_2:
        SUBA    #0x200,SP                       | allocate 512-byte sector buffer on stack
        MOVE.L  A7,0x1C(A1)                     | store buffer pointer in SonyVars
        TST.B   0x5(A1,D1.W)                    | Sides: drive double-sided?
        SMI.B   TwoSided(A1)                    | $FF if double-sided drive
        BPL.B   DT_SONY_NIBLTBL_SKIP            | single-sided -> skip override
        CMPI    #0x1,0x1C(A0)                   | CSParam: force single-sided?
        BNE.B   DT_SONY_NIBLTBL_SKIP            | no -> keep double-sided
        CLR.B   TwoSided(A1)                    | force single-sided format
DT_SONY_NIBLTBL_SKIP:
        TST.B   TwoSided(A1)                    | which format mode?
        SNE.B   0x12(A1,D1.W)                   | DiskFormat: $FF=double-sided
        MOVE    #0x7,SectMapSave(A1)            | initial speed adjustment retries
        BSR     DT_SONY_NIBLTBL_CONT_19         | spin up motor via async path
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        MOVE.L  0x1C(A1),A0                     | A0 = format data buffer
        LEA.L   DT_SONY_NIBLTBL_CONT(PC),A1     | A1 = sector template (sync+addr+data)
        MOVEQ.L #0xB,D0                         | 12 sectors per track (max, 0-based)
DT_SONY_NIBLTBL_LOOP:
        MOVEQ.L #0x1A,D1                        | 27 bytes per sector template entry
        MOVE.L  A1,A2                           | A2 = template source pointer
DT_SONY_NIBLTBL_LOOP_2:
        MOVE.B  (A2)+,(A0)+                     | copy one template byte
        DBF     D1,DT_SONY_NIBLTBL_LOOP_2       | copy 27 bytes
        DBF     D0,DT_SONY_NIBLTBL_LOOP         | repeat for 12 sectors
        BSR     Sony_SetupSonyVars              | reload drive vars
        CLR     DriveType(A1)                   | start at track 0, side 0
DT_SONY_NIBLTBL_NEXT:
        BSR.B   DT_SONY_NIBLTBL_CONT_3          | seek + adjust speed for track
        BNE.B   DT_SONY_NIBLTBL_ERR             | error -> abort format
        BSR     DT_SONY_NIBLTBL_EMPTY           | write and verify this track
        BNE.B   DT_SONY_NIBLTBL_ERR             | error -> abort format
        BSR     Sony_SetupSonyVars              | reload drive vars
        BCLR    #0x3,DriveType(A1)              | clear side bit
        ADDQ.W  #0x1,DriveType(A1)              | advance to next track
        CMPI    #0x50,DriveType(A1)             | past track 79?
        BLT.B   DT_SONY_NIBLTBL_NEXT            | no -> format next track
        MOVEQ.L #0x0,D0                         | format complete: noErr
DT_SONY_NIBLTBL_ERR:
        MOVE    PwrOffTime(A1),D2               | motor-off delay
        ADDA    #0x200,SP                       | free sector buffer from stack
        BRA     SONY_DISKPRIME_ERR_3            | power off motor and return

| ----------------------------------------------------------
|
| RANGE_TBL
|
| format speed range table (tighter tolerances than normal I/O)
RANGE_TBL:
  .byte  0x11,0xBC,0x11,0x62,0x13,0x59          | zone 0: hi=0x11BC, lo=0x1162; zone 1 hi=0x1359
  .byte 0x12,0xF7,0x15,0x49,0x14,0xDD           | zone 1 lo=0x12F7; zone 2: hi=0x1549, lo=0x14DD
  .byte 0x17,0xA6,0x17,0x2E,0x1A,0x9A           | zone 3: hi=0x17A6, lo=0x172E; zone 4 hi=0x1A9A
  .byte 0x1A,0x14                               | zone 4 lo=0x1A14
| -------------------------------------------------------
| DT_SONY_NIBLTBL_CONT_3 -- FormatSeekAndAdjust: seek to format track, adjust speed
| Seeks to target track via async path, then measures and adjusts
| speed for 400K drives. Retries up to BadSpdCnt times.
DT_SONY_NIBLTBL_CONT_3:
        MOVE.B  InvalidResp(A1),0x31(A1)        | BadSpdCnt: init speed retry counter
DT_SONY_NIBLTBL_RETRY:
        MOVE    DriveType(A1),D6                | D6 = target track/side
        BSR     DT_SONY_NIBLTBL_CONT_16         | async seek to track D6
        BSR     Sony_SetupSonyVars              | reload drive vars
        MOVE    0x0(A1,D1.W),D6                 | D6 = actual track reached
        BMI.B   DT_SONY_NIBLTBL_ERR_3           | seek error -> return
        TST.B   0x13(A1,D1.W)                   | NewIntf: 800K interface?
        BMI.B   DT_SONY_NIBLTBL_SKIP_2          | yes -> no speed adjustment needed
        MOVEQ.L #0xF,D0                         | check if at zone boundary
        AND.B   D6,D0                           | track mod 16
        BNE.B   DT_SONY_NIBLTBL_SKIP_2          | not at boundary -> skip speed check
        LSR     #0x4,D6                         | zone index
        LSL     #0x3,D6                         | zone * 8 (table stride)
        LEA.L   0x1A(A1,D1.W),A2                | A2 -> per-drive speed table
        LEA.L   0x4(A2,D6.W),A2                 | A2 -> zone timestamp
        MOVE.L  (Ticks).w,D2                    | current tick count
        MOVE.L  D2,(A2)                         | update timestamp
        LEA.L   DT_SONY_NIBLTBL_CONT_4(PC),A3   | A3 = speed check callback
        BRA     SONY_MAKESPDTBL_CONT_6          | measure speed via FigTrkSpd

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_4
|
| DT_SONY_NIBLTBL_CONT_4 -- speed check callback for format (tighter tolerances)
DT_SONY_NIBLTBL_CONT_4:
        BMI.B   DT_SONY_NIBLTBL_ERR_2           | measurement failed -> error
        MOVE    -(A2),D0                        | D0 = speed adjustment delta
        LSR     #0x1,D0                         | halve correction (gentler)
        LEA.L   RANGE_TBL(PC),A0                | A0 -> format RPM range table
        LSR     #0x1,D6                         | zone word index
        ADDA    D6,A0                           | index into table
        CMP     (A0)+,D4                        | measured > upper limit?
        BGT.B   DT_SONY_NIBLTBL_OK              | yes -> speed too fast
        NEG     D0                              | try negative correction
        CMP     (A0),D4                         | measured > lower limit?
        BGT.B   DT_SONY_NIBLTBL_SKIP_2          | within range -> success
DT_SONY_NIBLTBL_OK:
        SUB     D0,-(A2)                        | apply speed correction
        CLR.L   0x4(A2)                         | clear timestamp to force remeasure
        SUBQ.B  #0x1,0x31(A1)                   | decrement BadSpdCnt
        BPL.B   DT_SONY_NIBLTBL_RETRY           | retries remain -> try again
DT_SONY_NIBLTBL_ERR_2:
        MOVEQ.L #-0x4F,D0                       | spdAdjErr (-79): speed adjust failed
        BRA.B   DT_SONY_NIBLTBL_ERR_3           | return error

| DT_SONY_NIBLTBL_SKIP_2 -- speed OK (or 800K drive)
DT_SONY_NIBLTBL_SKIP_2:
        MOVEQ.L #0x0,D0                         | noErr
DT_SONY_NIBLTBL_ERR_3:
        RTS                                     | return

| -------------------------------------------------------
| DT_SONY_NIBLTBL_EMPTY -- FormatWriteVerify: write all sectors on current track,
| then verify by reading address marks and comparing sector data.
DT_SONY_NIBLTBL_EMPTY:
        BSR     Sony_SetupSonyVars              | reload drive vars
        MOVE    DriveType(A1),D6                | D6 = track/side descriptor
        MOVE    D6,D1                           | D1 = copy for zone calc
        BCLR    #0xB,D1                         | clear side bit
        LSR     #0x4,D1                         | D1 = zone index (track / 16)
        MOVEQ.L #0xC,D0                         | 12 = max sectors/track (zone 0)
        SUB     D1,D0                           | D0 = sectors/track for this zone
        MOVE    D0,SectCnt(A1)                  | save sector count
        BSR     DT_SONY_NIBLTBL_CONT_9          | encode address fields for all sectors
| DT_SONY_NIBLTBL_CONT_5 -- write raw track then verify
DT_SONY_NIBLTBL_CONT_5:
        BSR     DT_SONY_NIBLTBL_CONT_8          | write formatted track to disk
        BEQ.B   DT_SONY_NIBLTBL_CONT_6          | success -> verify
        BSR     DT_SONY_NIBLTBL_ERR_10          | write failed: save error, poll
        ANDI    #-0x701,SR                      | restore interrupts
        BRA     DT_SONY_NIBLTBL_ERR_5           | return error

| DT_SONY_NIBLTBL_CONT_6 -- verify: read address mark after format write
DT_SONY_NIBLTBL_CONT_6:
        BSR     E_Sony_RdAddr                   | read sector address field
        BMI.B   DT_SONY_NIBLTBL_ERR_4           | read failed -> save error
        TST.B   D2                              | sector number = 0?
        BEQ.B   DT_SONY_NIBLTBL_ERR_4           | yes -> skip (expected first sector)
        MOVEQ.L #-0x52,D0                       | noDtaMkErr (-82): wrong sector found
DT_SONY_NIBLTBL_ERR_4:
        BSR     DT_SONY_NIBLTBL_ERR_10          | save error code, call PollProc
        ANDI    #-0x701,SR                      | restore interrupts
        LEA.L   SectMapSave(A1),A0              | A0 -> interleave offset
        MOVE    (DskErr).w,D0                   | D0 = last error
        BMI.B   DT_SONY_NIBLTBL_ERR_6           | fatal error -> decrement retries
        MOVE.L  #0x5E0,D2                       | $5E0 = 1504 total possible
        SUB     D0,D2                           | D2 = remaining after read error count
        DIVU    #0x5,D2                         | divide by 5 for sector timing
        MOVE    #-0x53,(DskErr).w               | fmtVerErr (-83): verify failed
        SUB     (A0),D2                         | subtract current interleave offset
        BMI.B   DT_SONY_NIBLTBL_CONT_7          | negative -> too many errors
        EXT.L   D2                              | sign-extend for division
        DIVU    SectCnt(A1),D2                  | D2 = revolutions of slippage
        BEQ.B   DT_SONY_NIBLTBL_EMPTY_2         | zero -> good interleave
        SUBQ.W  #0x1,D2                         | one revolution slip acceptable
        BEQ.B   DT_SONY_NIBLTBL_EMPTY_2         | -> good enough
        ADDQ.W  #0x1,(A0)                       | adjust interleave offset up
DT_SONY_NIBLTBL_EMPTY_2:
        BSR     Sony_SetupSonyVars              | branch to subroutine
        BSET    #0x3,DriveType(A1)              | set bit
        BNE.B   DT_SONY_NIBLTBL_NO              | branch if not equal
        TST.B   TwoSided(A1)                    | test status bit
        BNE     DT_SONY_NIBLTBL_EMPTY           | branch if not zero
DT_SONY_NIBLTBL_NO:
        CLR     (DskErr).w                      | clear value
DT_SONY_NIBLTBL_ERR_5:
        MOVE    (DskErr).w,D0                   | move word
        RTS                                     | return

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_7
|
| DT_SONY_NIBLTBL_CONT_7 -- borderline: one revolution slip is marginal
DT_SONY_NIBLTBL_CONT_7:
        ADDQ.W  #0x1,D2                         | D2 was -1? -> exactly on boundary
        BEQ.B   DT_SONY_NIBLTBL_EMPTY_2         | yes -> accept
DT_SONY_NIBLTBL_ERR_6:
        SUBQ.W  #0x1,(A0)                       | adjust interleave offset down
        CMPI    #0x4,(A0)                       | exceeded maximum retries?
        BLT.B   DT_SONY_NIBLTBL_ERR_5           | yes -> return with error
  .short 0x6080                                 | Bra.B DT_SONY_NIBLTBL_CONT_5: retry format write

| -------------------------------------------------------
| DT_SONY_NIBLTBL_CONT_8 -- FormatWriteTrack: write raw formatted track data
| Selects head side, enters write mode, writes self-sync,
| address fields, and gap bytes for all sectors on track.
DT_SONY_NIBLTBL_CONT_8:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
        MOVEQ.L #0x1,D0                         | D0 = 1: head side 0
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        TST.B   TwoSided(A1)                    | double-sided format?
        BEQ.B   DT_SONY_NIBLTBL_NO_2            | no -> side 0
        BTST    #0xB,D6                         | side 1 requested?
        BEQ.B   DT_SONY_NIBLTBL_NO_2            | no -> side 0
        MOVEQ.L #0x3,D0                         | D0 = 3: head side 1
DT_SONY_NIBLTBL_NO_2:
        BSR     Sony_AdrDisk                    | select head side
        MOVEQ.L #0x4,D0                         | reserve 4 bytes on poll stack
        BSR     E_Sony_SetUpPoll                | set up SCC/VIA polling
        MOVE.L  #IWM_Q6H,A3                     | A3 = IWM write data register
        MOVE.L  #IWM_Q6L,A4                     | A4 = IWM handshake register
        MOVE.L  0x1C(A1),A0                     | A0 = format data buffer
        MOVE    SectCnt(A1),D0                  | D0 = sectors per track
        MOVE    SectMapSave(A1),D1              | D1 = interleave offset
        SUBQ.W  #0x2,D1                         | adjust for loop counter
        LEA.L   DT_SONY_NIBLTBL_CONT(PC),A1     | A1 = sync/gap pattern template
        MOVE    #0xC7,D3                        | D3 = 199: initial sync byte count
        TST.B   (A3)                            | Q6 on: enter write mode setup
        MOVE.B  D3,(IWM_Q7H).l                  | Q7 on + first write: enable write mode
| DT_SONY_NIBLTBL_LOOP_3 -- write initial self-sync ($FF) bytes, D3+1 groups of 6 bytes
DT_SONY_NIBLTBL_LOOP_3:
        MOVE.L  A1,A2                           | A2 = sync pattern source
        MOVEQ.L #0x2,D2                         | 3 pairs of sync bytes
DT_SONY_NIBLTBL_LOOP_4:
        MOVE.B  (A2)+,D4                        | load next sync byte
DT_SONY_NIBLTBL_NO_3:
        TST.B   (A4)                            | IWM handshake: ready to write?
        BPL.B   DT_SONY_NIBLTBL_NO_3            | no -> wait
        MOVE.B  D4,(A3)                         | write sync byte to IWM
        MOVE.B  (A2)+,D4                        | load next sync byte
        TST.B   (A5)                            | SCC wait/request check
        BMI.B   DT_SONY_NIBLTBL_ERR_7           | branch if minus (error)
        MOVE.B  (A6),-(SP)                      | _PollSCC: push SCC data to poll stack
DT_SONY_NIBLTBL_ERR_7:
        TST.B   (A4)                            | test status bit
        BPL.B   DT_SONY_NIBLTBL_ERR_7           | wait for data ready (sign bit clear)
        MOVE.B  D4,(A3)                         | store byte to buffer
        DBF     D2,DT_SONY_NIBLTBL_LOOP_4       | repeat 3 pairs
        DBF     D3,DT_SONY_NIBLTBL_LOOP_3       | repeat D3+1 groups (200 total)
| DT_SONY_NIBLTBL_NEXT_2 -- per-sector loop: write inter-sector sync, address, gap, data
DT_SONY_NIBLTBL_NEXT_2:
        MOVE    D1,D3                           | D3 = interleave gap count
DT_SONY_NIBLTBL_LOOP_5:
        MOVE.L  A1,A2                           | A2 = sync pattern source
        MOVEQ.L #0x5,D2                         | write 6 self-sync bytes
DT_SONY_NIBLTBL_LOOP_6:
        TST.B   (A4)                            | IWM ready?
        BPL.B   DT_SONY_NIBLTBL_LOOP_6          | wait
        MOVE.B  (A2)+,(A3)                      | write sync byte
        TST.B   (A5)                            | SCC service check
        BMI.B   DT_SONY_NIBLTBL_SKIP_3          | busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC data
DT_SONY_NIBLTBL_SKIP_3:
        DBF     D2,DT_SONY_NIBLTBL_LOOP_6       | 6 sync bytes
        DBF     D3,DT_SONY_NIBLTBL_LOOP_5       | repeat for inter-sector gap
| write 27 bytes of address+data from format buffer
        MOVEQ.L #0x1A,D2                        | 27 bytes (0-based: $1A = 26)
DT_SONY_NIBLTBL_LOOP_7:
        TST.B   (A4)                            | IWM ready?
        BPL.B   DT_SONY_NIBLTBL_LOOP_7          | wait
        MOVE.B  (A0)+,(A3)                      | write format buffer byte to disk
        TST.B   (A5)                            | SCC service check
        BMI.B   DT_SONY_NIBLTBL_SKIP_4          | busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC data
DT_SONY_NIBLTBL_SKIP_4:
        DBF     D2,DT_SONY_NIBLTBL_LOOP_7       | repeat for 27 bytes
| write data gap: $2BF (703) bytes of $96
        MOVE    #0x2BE,D2                       | 703 gap bytes (0-based)
DT_SONY_NIBLTBL_LOOP_8:
        TST.B   (A4)                            | IWM ready?
        BPL.B   DT_SONY_NIBLTBL_LOOP_8          | wait
        MOVE.B  #0x96,(A3)                      | write gap byte ($96)
        TST.B   (A5)                            | SCC service check
        BMI.B   DT_SONY_NIBLTBL_SKIP_5          | busy -> skip
        MOVE.B  (A6),-(SP)                      | service SCC data
DT_SONY_NIBLTBL_SKIP_5:
        DBF     D2,DT_SONY_NIBLTBL_LOOP_8       | repeat for all gap bytes
| write 4 bytes of deaddress mark from template
        MOVEQ.L #0x3,D2                         | 4 bytes
        ADDQ.W  #0x8,A2                         | skip to deaddress mark in template
DT_SONY_NIBLTBL_LOOP_9:
        TST.B   (A4)                            | IWM ready?
        BPL.B   DT_SONY_NIBLTBL_LOOP_9          | wait
        MOVE.B  (A2)+,(A3)                      | write deaddress byte
        DBF     D2,DT_SONY_NIBLTBL_LOOP_9       | repeat for 4 bytes
        SUBQ.W  #0x1,D0                         | decrement sector count
        BGT.B   DT_SONY_NIBLTBL_NEXT_2          | more sectors -> next sector
| check write completion status
        MOVE.B  (A4),D0                         | read IWM handshake register
        MOVEQ.L #0x0,D2                         | clear D2
        BTST    #0x6,D0                         | write underrun bit set?
        BNE.B   DT_SONY_NIBLTBL_NO_4            | no -> success
        MOVEQ.L #-0x4A,D0                       | wrUnderrun (-74): write underrun
        BRA.B   DT_SONY_NIBLTBL_EXIT            | exit write mode

| DT_SONY_NIBLTBL_NO_4 -- write completed successfully
DT_SONY_NIBLTBL_NO_4:
        MOVEQ.L #0x0,D0                         | noErr
DT_SONY_NIBLTBL_EXIT:
        TST.B   (IWM_Q7L).l                     | Q7 off: exit write mode
        MOVE.L  (DskRtnAdr).w,-(SP)             | push continuation address
        TST     D0                              | set condition codes
        RTS                                     | return to continuation

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_9
|
DT_SONY_NIBLTBL_CONT_9:
        MOVEM.L D0-D7/A0-A1,-(SP)               | save all registers
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  0x1C(A1),A0                     | A0 = format data buffer
        MOVEQ.L #0x2,D3                         | D3 = $02: single-sided format byte
        TST.B   TwoSided(A1)                    | double-sided format?
        BEQ.B   DT_SONY_NIBLTBL_NO_5            | no -> use $02
        MOVEQ.L #0x22,D3                        | D3 = $22: double-sided format byte
DT_SONY_NIBLTBL_NO_5:
        MOVE.L  (DiskVars_NiblTbl).w,A1         | A1 = GCR encode table
        MOVE.B  0x0(A1,D3.W),D7                 | D7 = GCR-encoded format byte
        MOVE.B  D3,D5                           | D5 = format byte (for checksum seed)
        MOVEQ.L #0x3F,D3                        | mask for low 6 bits of track
        AND.B   D6,D3                           | D3 = track number (low 6 bits)
        MOVE.B  0x0(A1,D3.W),D2                 | D2 = GCR-encoded track low bits
        EOR.B   D3,D5                           | accumulate track into checksum seed
        LSR     #0x6,D6                         | D6 = side/track upper bits
        EOR.B   D6,D5                           | accumulate side into checksum seed
        MOVE.B  0x0(A1,D6.W),D6                 | D6 = GCR-encoded side/upper track
        MOVE    D0,D1                           | D1 = sectors per track
        SUBQ.W  #0x1,D1                         | D1 = sectors - 1
        LSR     #0x1,D1                         | D1 = (sectors-1)/2 (interleave start)
        ADDQ.W  #0x1,D1                         | D1 = interleave offset
        SWAP    D1                              | D1.hi = interleave, D1.lo for sector
        CLR     D1                              | D1.lo = 0: starting sector number
DT_SONY_NIBLTBL_CONT_10:
        MOVE.B  0x0(A1,D1.W),D3                 | D3 = GCR-encoded sector number
        MOVEQ.L #0x0,D4                         | clear checksum accumulator
        MOVE.B  D5,D4                           | D4 = checksum seed
        EOR.B   D1,D4                           | XOR sector number into checksum
        ADDA    #0x9,A0                         | skip 9 bytes (sync pattern) in buffer
        MOVE.B  D2,(A0)+                        | write GCR track low bits
        MOVE.B  D3,(A0)+                        | write GCR sector number
        MOVE.B  D6,(A0)+                        | write GCR side/upper track
        MOVE.B  D7,(A0)+                        | write GCR format byte
        MOVE.B  0x0(A1,D4.W),(A0)+              | write GCR checksum byte
        ADDA    #0xC,A0                         | skip 12 bytes (trailer + data gap)
        MOVE.B  D3,(A0)+                        | write sector number again (data mark)
        ADDQ.W  #0x1,D1                         | next sector (interleaved)
        SWAP    D1                              | swap interleave counter
        SUBQ.W  #0x1,D0                         | decrement sectors remaining
        BNE.B   DT_SONY_NIBLTBL_CONT_10         | more sectors -> continue
        MOVEM.L (SP)+,D0-D7/A0-A1               | restore all registers
        RTS                                     | return to format caller

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_11
|
DT_SONY_NIBLTBL_CONT_11:
        SUBA    #0x200,SP                       | allocate 512-byte verify buffer on stack
        MOVE.L  A7,0x1C(A1)                     | store buffer pointer in SonyVars
        BSR     DT_SONY_NIBLTBL_CONT_19         | spin up motor via async path
        MOVEQ.L #0x4,D2                         | D2 = 4: 5 speed zones (0-based)
        MOVE    #0x7F,D4                        | D4 = $7F: sector bitmap seed
        MOVEQ.L #0x4F,D6                        | D6 = 79: start at track 79
DT_SONY_NIBLTBL_LOOP_10:
        LSL     #0x1,D4                         | expand sector bitmap for zone
        ADDQ.W  #0x1,D4                         | set lowest bit (adds one sector)
        MOVEQ.L #0xF,D3                         | D3 = 15: 16 tracks per zone
DT_SONY_NIBLTBL_LOOP_11:
        MOVEM.L D2-D6,-(SP)                     | save zone/track state
        BSR     DT_SONY_NIBLTBL_CONT_16         | async seek to track D6
        MOVEM.L (SP)+,D2-D6                     | restore zone/track state
        BSR     Sony_SetupSonyVars              | reload SonyVars and drive offset
        MOVE    0x0(A1,D1.W),D0                 | D0 = actual track reached
        BMI.B   DT_SONY_NIBLTBL_ERR_8           | seek error -> abort verify
        BSR.B   DT_SONY_NIBLTBL_CONT_12         | verify all sectors on this track
        BNE.B   DT_SONY_NIBLTBL_ERR_8           | verify error -> abort
        SUBQ.W  #0x1,D6                         | next track (working backward)
        DBF     D3,DT_SONY_NIBLTBL_LOOP_11      | repeat for all tracks in zone
        DBF     D2,DT_SONY_NIBLTBL_LOOP_10      | repeat for all 5 zones
DT_SONY_NIBLTBL_ERR_8:
        BRA     DT_SONY_NIBLTBL_ERR             | free buffer and return result

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_12
|
DT_SONY_NIBLTBL_CONT_12:
        MOVEM.L D2-D6,-(SP)                     | save caller's registers
        ORI     #0x300,SR                       | raise IPL to mask interrupts
        LEA.L   SectMapSave(A1),A0              | A0 -> sector bitmap area
        MOVE    D4,(A0)                         | store sector bitmap for this zone
        MOVEQ.L #0xC,D3                         | 12 = max sectors (zone 0)
        SUB     D2,D3                           | D3 = sectors/track for this zone
        LSL     #0x2,D3                         | D3 *= 4: scan timeout multiplier
        MOVE    D3,0x2(A0)                      | store timeout count
        MOVE.L  (A0)+,(A0)+                     | copy bitmap/timeout to working area
        BCLR    #0x3,DriveType(A1)              | clear side bit: start with side 0
DT_SONY_NIBLTBL_NEXT_3:
        MOVE.L  D1,D6                           | D6 = drive vars offset (for SONY_SETUPPOLL_CONT)
        BSR     SONY_SETUPPOLL_CONT             | read sector address field
        BPL.B   DT_SONY_NIBLTBL_CONT_13         | success -> check sector
        BSR.B   DT_SONY_NIBLTBL_ERR_10          | save error, call PollProc
        ANDI    #-0x701,SR                      | restore IPL to 0
        BRA.B   DT_SONY_NIBLTBL_ERR_9           | return error

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_13
|
DT_SONY_NIBLTBL_CONT_13:
        LEA.L   SectCnt(A1),A0                  | A0 -> sector counter area
        MOVE    D2,(A0)+                        | store current sector number
        MOVE    (A0)+,D0                        | D0 = remaining sector bitmap
        BCLR    D2,D0                           | clear bit for this sector
        BNE.B   DT_SONY_NIBLTBL_OK_2            | bit was set -> verify this sector
        BSR.B   DT_SONY_NIBLTBL_ERR_10          | unexpected sector: save error, poll
        ANDI    #-0x701,SR                      | restore IPL to 0
        LEA.L   0x24(A1),A0                     | A0 -> timeout counter
        BRA.B   DT_SONY_NIBLTBL_CONT_14         | decrement timeout

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_OK_2
|
DT_SONY_NIBLTBL_OK_2:
        CMPI.B  #0x1F,D3                        | format byte > $1F means double-sided
        SGT.B   0x12(A1,D6.W)                   | DiskFormat: $FF if double-sided
        MOVE.L  0x1C(A1),A0                     | A0 = verify data buffer
        CLR.B   (DskVerify).w                   | clear verify flag (normal read mode)
        BSR     E_Sony_RdData                   | read sector data into buffer
        BSR.B   DT_SONY_NIBLTBL_ERR_10          | save error, call PollProc
        TST     D0                              | read error?
        BNE.B   DT_SONY_NIBLTBL_ERR_9           | yes -> return error
        LEA.L   SectCnt(A1),A0                  | A0 -> sector counter area
        MOVE    (A0)+,D2                        | D2 = sector number just read
        MOVE    (A0),D0                         | D0 = remaining sector bitmap
        BCLR    D2,D0                           | clear bit for verified sector
        MOVE    D0,(A0)+                        | update bitmap
        BEQ.B   DT_SONY_NIBLTBL_CONT_15         | all sectors verified -> check sides
DT_SONY_NIBLTBL_CONT_14:
        SUBQ.W  #0x1,(A0)                       | decrement scan timeout counter
        BNE.B   DT_SONY_NIBLTBL_NEXT_3          | retries remain -> read next address
        MOVEQ.L #-0x54,D0                       | firstDskErr (-84): format verify failed
        BRA.B   DT_SONY_NIBLTBL_ERR_9           | return error

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_15
|
DT_SONY_NIBLTBL_CONT_15:
        BSR     Sony_SetupSonyVars              | reload SonyVars and drive offset
        TST.B   0x12(A1,D1.W)                   | DiskFormat: double-sided disk?
        BEQ.B   DT_SONY_NIBLTBL_DONE            | single-sided -> done with track
        BSET    #0x3,DriveType(A1)              | set side 1 bit
        BNE.B   DT_SONY_NIBLTBL_DONE            | already set -> both sides done
        ADDQ.W  #0x2,A0                         | point past bitmap to timeout
        MOVE.L  (A0),-(A0)                      | copy timeout/bitmap for side 1
        BRA.B   DT_SONY_NIBLTBL_NEXT_3          | verify side 1 sectors

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_DONE
|
DT_SONY_NIBLTBL_DONE:
        MOVEQ.L #0x0,D0                         | noErr: track verified successfully
DT_SONY_NIBLTBL_ERR_9:
        ANDI    #-0x701,SR                      | restore IPL to 0 (enable interrupts)
        MOVEM.L (SP)+,D2-D6                     | restore caller's registers
        TST     D0                              | set condition codes on result
        RTS                                     | return Z=1 if success

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_ERR_10
|
| Called by: DT_SONY_NIBLTBL_CONT_5, DT_SONY_NIBLTBL_ERR_4, DT_SONY_NIBLTBL_NEXT_3, DT_SONY_NIBLTBL_CONT_13, DT_SONY_NIBLTBL_OK_2
DT_SONY_NIBLTBL_ERR_10:
        MOVE    D0,(DskErr).w                   | save error code for format/verify
        BRA     SONY_RESEEK_CONT_8              | call PollProc (deferred tasks)

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_16
|
DT_SONY_NIBLTBL_CONT_16:
        LEA.L   E_Sony_Seek(PC),A0              | A0 = seek routine address
DT_SONY_NIBLTBL_CONT_17:
        CLR.B   (DskErr).w                      | clear error flag (async completion)
        BSR.B   DT_SONY_NIBLTBL_CONT_18         | invoke async routine via A0
DT_SONY_NIBLTBL_NO_6:
        TST.B   (DskErr).w                      | async operation complete?
        BEQ.B   DT_SONY_NIBLTBL_NO_6            | no -> spin-wait for completion
        RTS                                     | return when timer callback sets flag

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_18
|
DT_SONY_NIBLTBL_CONT_18:
        JSR     (A0)                            | call async routine (seek or motor-on)
        ST.B    (DskErr).w                      | set completion flag = $FF
        RTS                                     | return to DT_SONY_NIBLTBL_CONT_17

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_19
|
DT_SONY_NIBLTBL_CONT_19:
        LEA.L   Sony_MotorOn2(PC),A0            | A0 = motor-on routine address
        BRA.B   DT_SONY_NIBLTBL_CONT_17         | invoke as async operation

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_20
|
DT_SONY_NIBLTBL_CONT_20:
        ANDI    #-0x701,SR                      | restore IPL to 0 (DCD path)
        MOVE    0x112(A1),D0                    | D0 = previous drive (LastDrive)
        CMP     TwoSideFmt(A1),D0               | same as current DCD drive?
        BEQ.B   DT_SONY_NIBLTBL_SKIP_6          | yes -> skip settling delay
        MOVEQ.L #0xA,D0                         | 1ms drive-switch settling delay
        BSR     E_Sony_WakeUp                   | wait for drive to stabilize
DT_SONY_NIBLTBL_SKIP_6:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address
        TST.B   (A0)                            | CA0 off: set up DCD register select
        TST.B   0x800(A0)                       | CA2 off: complete register select
        CMPI.B  #0x2,0x3(A1,D1.W)               | DiskInPlace >= 2 (already mounted)?
        BGE.B   DT_SONY_NIBLTBL_SKIP_7          | yes -> skip DCD status query
        LEA.L   DT_SONY_NIBLTBL_CONT_21(PC),A0  | A0 = DCD status completion callback
        MOVE.L  A0,0x198(A1)                    | StsRtnAddr: save callback address
        BRA     SONY_DCDRESET_CONT_4            | go issue DCD status command

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_21
|
DT_SONY_NIBLTBL_CONT_21:
        BNE     DT_SONY_NIBLTBL_ERR_13          | DCD status error -> return
        BSR     Sony_SetupRegs                  | reload IWM/VIA/SonyVars
        MOVE.B  #0x8,0x3(A1,D1.W)               | DiskInPlace = 8: DCD disk present
        MOVE.L  0x1A2(A1),0x16(A1,D1.W)         | copy DCD block count to drive size
        MOVE.L  0x1A6(A1),D0                    | D0 = DCD device characteristics
        SWAP    D0                              | swap for byte-order alignment
        MOVE.L  D0,0x12(A1,D1.W)                | store DCD type/manufacturer info
        CLR.B   0x14(A1,D1.W)                   | DriveErrs: clear error count
        LSR     #0x8,D0                         | D0 = device characteristics byte
        MOVE.B  D0,0x1A(A1,D1.W)                | DriveMisc: store characteristics
        BTST    #0x3,D0                         | DevChWP: write-protected?
        SNE.B   0x2(A1,D1.W)                    | WrProt: $FF if write-protected
        BTST    #0x4,D0                         | media ready bit set?
        BEQ.B   DT_SONY_NIBLTBL_SKIP_7          | no -> keep DiskInPlace = 8
        MOVE.B  #0x2,0x3(A1,D1.W)               | DiskInPlace = 2: DCD ready for I/O
DT_SONY_NIBLTBL_SKIP_7:
        MOVE.L  (A1),A2                         | A2 = DCE pointer
        MOVE.L  0x10(A2),D5                     | D5 = dCtlPosition (byte offset)
        MOVEQ.L #0x9,D1                         | shift count for /512
        LSR.L   D1,D5                           | D5 = starting block number
        MOVE.L  0x8(A2),A0                      | A0 = IOParam block
        MOVE.L  0xF4(A1),A5                     | A5 = TagBufPtr (or nil)
        MOVE.L  0x20(A0),A4                     | A4 = ioBuffer pointer
        MOVE.L  0x24(A0),D3                     | D3 = ioReqCount (total bytes)
        MOVEQ.L #-0x32,D0                       | paramErr (-50): assume bad position
        ANDI    #0x1FF,D3                       | check alignment (must be 512 multiple)
        BNE     DT_SONY_NIBLTBL_ERR_13          | not aligned -> return paramErr
        MOVE.L  0x24(A0),D3                     | D3 = ioReqCount (reload)
        TST.B   (DskVerify).w                   | verify-after-write mode?
        BEQ.B   DT_SONY_NIBLTBL_NO_7            | no -> proceed with I/O
        BSR     SONY_RESEEK_OK_3                | check if read operation
        BNE.B   DT_SONY_NIBLTBL_NO_7            | write -> proceed with I/O
        MOVE.L  D3,0x28(A0)                     | verify read: set ioActCount = full
        ADD.L   D3,0x10(A2)                     | advance dCtlPosition by full count
        MOVEQ.L #0x0,D0                         | noErr: verify read is a no-op for DCD
        BRA     DT_SONY_NIBLTBL_ERR_13          | return success

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_NO_7
|
DT_SONY_NIBLTBL_NO_7:
        MOVE.B  0x33(A1),0x19C(A1)              | DCDCmd = ioTrap (2=read, 3=write)
        SUBQ.B  #0x2,0x19C(A1)                  | convert: 0=read, 1=write
DT_SONY_NIBLTBL_NEXT_4:
        MOVEQ.L #0x9,D1                         | shift count for /512
        LSR.L   D1,D3                           | D3 = blocks remaining
        MOVEQ.L #0x0,D0                         | D0 = $000000FF (max blocks per cmd)
        SUBQ.B  #0x1,D0                         | D0 = 255
        CMP.L   D0,D3                           | more than 255 blocks?
        BLT.B   DT_SONY_NIBLTBL_NO_8            | no -> use actual count
        MOVE.L  D0,D3                           | clamp to 255 blocks per command
DT_SONY_NIBLTBL_NO_8:
        MOVE    D3,D2                           | D2 = block count (low word copy)
        SWAP    D3                              | D3.hi = block count for sequence
        MOVE    D2,D3                           | D3 = {count, count} for tracking
        MOVE.B  #0x3,RecalCnt(A1)               | retry count = 3 attempts
        CLR.B   0x1BF(A1)                       | DCDFlags: clear reset/retry flags
DT_SONY_NIBLTBL_RETRY_2:
        BSR     DT_SONY_NIBLTBL_CONT_26         | build DCD command packet
        BSR     E_Sony_SendCmd                  | send command to DCD
        BNE.B   DT_SONY_NIBLTBL_ERR_11          | send failed -> retry/error
DT_SONY_NIBLTBL_CONT_22:
        BSR     DT_SONY_NIBLTBL_CONT_25         | wait for DCD ready (poll HSHK)
        BPL.B   DT_SONY_NIBLTBL_CONT_23         | ready -> receive response
        MOVE.B  #0x2,0x1BE(A1)                  | LastResult = comErr (comm failure)
        CLR.L   0x1BA(A1)                       | clear LastStatus
        MOVE.B  #0x40,0x1BA(A1)                 | LastStatus = NoResp ($40)
        BRA.B   DT_SONY_NIBLTBL_ERR_11          | go to retry path

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_23
|
DT_SONY_NIBLTBL_CONT_23:
        BSR     SONY_SENDCMD_CONT               | receive DCD response packet
        BEQ.B   DT_SONY_NIBLTBL_CONT_22         | more blocks -> continue transfer
        ADD.L   D4,D5                           | accumulate blocks transferred
        TST     D0                              | transfer error?
        BEQ.B   DT_SONY_NIBLTBL_CONT_24         | noErr -> update position
DT_SONY_NIBLTBL_ERR_11:
        SUBQ.B  #0x1,RecalCnt(A1)               | decrement retry counter
        BLT.B   DT_SONY_NIBLTBL_ERR_12          | retries exhausted -> fatal error
        BEQ.B   DT_SONY_NIBLTBL_RETRY_3         | last retry -> try DCD reset
        CMPI.B  #0x2,0x1BE(A1)                  | LastResult == comErr?
        BNE.B   DT_SONY_NIBLTBL_RETRY_4         | no -> retry without reset
        BTST    #0x1E,0x1BA(A1)                 | bChksum: checksum error in status?
        BNE.B   DT_SONY_NIBLTBL_RETRY_4         | yes -> retry without reset
        TST.B   0x1BF(A1)                       | DCDFlags: already tried reset?
        BEQ.B   DT_SONY_NIBLTBL_RETRY_3         | no -> try DCD reset
        CLR.B   RecalCnt(A1)                    | force last attempt
DT_SONY_NIBLTBL_RETRY_3:
        BSR     E_Sony_DCDReset                 | hard-reset the DCD controller
        BNE.B   DT_SONY_NIBLTBL_ERR_12          | reset failed -> fatal error
        ST.B    0x1BF(A1)                       | DCDFlags: mark reset attempted
DT_SONY_NIBLTBL_RETRY_4:
        BRA.B   DT_SONY_NIBLTBL_RETRY_2         | retry the DCD command

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_ERR_12
|
DT_SONY_NIBLTBL_ERR_12:
        MOVEQ.L #-0x13,D0                       | readErr (-19): DCD read failed
        CMPI.B  #0x2,0x33(A1)                   | was this a read operation?
        BEQ.B   DT_SONY_NIBLTBL_EXIT_2          | yes -> return readErr
        MOVEQ.L #-0x14,D0                       | writErr (-20): DCD write failed
DT_SONY_NIBLTBL_EXIT_2:
        BRA.B   DT_SONY_NIBLTBL_ERR_13          | return error

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_24
|
DT_SONY_NIBLTBL_CONT_24:
        MOVEQ.L #0x9,D1                         | shift count for *512
        CLR     D3                              | clear low word of D3
        SWAP    D3                              | D3 = blocks transferred this round
        CMPI.B  #0x2,0x33(A1)                   | read operation?
        BEQ.B   DT_SONY_NIBLTBL_SKIP_8          | yes -> skip tag update
        ADD.L   D3,(BufTgFFlg).w                | write: advance tag file block number
DT_SONY_NIBLTBL_SKIP_8:
        LSL.L   D1,D3                           | D3 = bytes transferred (* 512)
        MOVE.L  (A1),A3                         | A3 = DCE pointer
        ADD.L   D3,PORTRECT(A3)                 | advance dCtlPosition by bytes done
        MOVE.L  PORTBOUNDS(A3),A0               | A0 = IOParam block
        ADD.L   D3,0x28(A0)                     | advance ioActCount by bytes done
        MOVE.L  0x24(A0),D3                     | D3 = ioReqCount (total requested)
        SUB.L   0x28(A0),D3                     | D3 = remaining bytes
        BGT     DT_SONY_NIBLTBL_NEXT_4          | more data -> issue next DCD command
        MOVEQ.L #0x0,D0                         | noErr: DCD transfer complete
DT_SONY_NIBLTBL_ERR_13:
        MOVE.L  (IWM).w,A0                      | reload IWM base
        TST.B   0x1000(A0)                      | ENABLE off: deselect drive
        ANDI    #-0x701,SR                      | restore IPL to 0
        BRA     Sony_ReturnResult               | return result to caller

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_25
|
DT_SONY_NIBLTBL_CONT_25:
        MOVE.L  (SP)+,A3                        | A3 = return address
DT_SONY_NIBLTBL_RETRY_5:
        MOVEQ.L #0x64,D0                        | D0 = 100: quick poll attempts
DT_SONY_NIBLTBL_LOOP_12:
        TST.B   0x1A00(A0)                      | Q6 on: enter status read mode
        TST.B   0x1C00(A0)                      | read IWM status: HSHK in bit 7
        DBPL    D0,DT_SONY_NIBLTBL_LOOP_12      | poll until HSHK high or timeout
        BPL.B   DT_SONY_NIBLTBL_EXIT_3          | HSHK high -> DCD ready
        SUBQ.W  #0x1,0x1C2(A1)                  | decrement MaxTime counter
        BMI.B   DT_SONY_NIBLTBL_EXIT_3          | timeout expired -> return not ready
        MOVE    0x1C0(A1),D0                    | D0 = ChkTime (inter-poll delay)
        BSR     E_Sony_WakeUp                   | delay between poll cycles
        BRA.B   DT_SONY_NIBLTBL_RETRY_5         | retry polling

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_EXIT_3
|
DT_SONY_NIBLTBL_EXIT_3:
        JMP     (A3)                            | return to caller (N flag = result)

| ----------------------------------------------------------
|
| DT_SONY_NIBLTBL_CONT_26
|
DT_SONY_NIBLTBL_CONT_26:
        MOVE.L  D5,D0                           | D0 = starting block number
        LSL.L   #0x8,D0                         | shift block# left 8 for packet format
        MOVE.L  D0,0x19E(A1)                    | StartBlock: store in command packet
        MOVE.B  D3,0x19D(A1)                    | SeqNum: store block count as seq#
        MOVE    #0xA,0x1C0(A1)                  | ChkTime = 10 (1ms poll interval)
        MOVE    #0x2710,0x1C2(A1)               | MaxTime = 10000 (10 sec timeout)
        MOVE.L  #0x200,D6                       | D6 = 512: data size per block
        MOVEQ.L #0x0,D7                         | D7 = 0: no tag data initially
        TST.B   0x19C(A1)                       | DCDCmd: read (0) or write (1+)?
        BNE.B   DT_SONY_NIBLTBL_CONT_27         | write -> D6=data, D7=0
        EXG     D6,D7                           | read -> D6=0 (send), D7=512 (recv)
DT_SONY_NIBLTBL_CONT_27:
        ANDI.B  #0x3F,0x19C(A1)                 | mask command to 6 bits
        RTS                                     | return with command packet ready

| E_Sony_SendCmd -- send command to DCD.
| ----------------------------------------------------------
|
| E_Sony_Send Cmd
|
E_Sony_SendCmd:
        MOVE.L  (JSendCmd).w,-(SP)              | push SendCmd vector address
        RTS                                     | dispatch to Sony_SendCmd

| ----------------------------------------------------------
|
| Sony SendCmd
|
Sony_SendCmd:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address
        LEA.L   0x1800(A0),A3                   | A3 = IWM Q6L (handshake register)
        MOVE.L  D6,0x1B6(A1)                    | BufSize: set send data size
        ADD.L   D7,0x1B6(A1)                    | add receive data size to total
        MOVE.B  0x19C(A1),D1                    | D1 = DCD command byte
        CMPI.B  #0x3,D1                         | status command (3+)?
        BGE.B   SONY_SENDCMD_SKIP               | yes -> no tag adjustment needed
        TST.B   D1                              | read command (0)?
        BNE.B   SONY_SENDCMD_NO                 | no (write) -> add tags to send size
        ADDI    #0x14,D7                        | read: add 20 tag bytes to receive
        BRA.B   SONY_SENDCMD_SKIP               | skip write path

| ----------------------------------------------------------
|
| SONY_SENDCMD_NO
|
SONY_SENDCMD_NO:
        ADDI    #0x14,D6                        | write: add 20 tag bytes to send size
        MOVE.L  A5,D0                           | TagBufPtr: external tag buffer?
        BNE.B   SONY_SENDCMD_SKIP               | yes -> tags already in user buffer
        ADDA    #0x1A2,A1                       | point to DCD tag buffer area
        MOVE.L  (BufTgFNum).w,(A1)+             | copy tag data from system globals
        MOVE.L  (BufTgFFlg).w,(A1)+             | file flags
        MOVE.L  (BufTgDate).w,(A1)+             | date
        MOVE.L  (BufTgHD20).w,(A1)+             | HD20 tag extension bytes
        MOVE.L  (BufTgHD20_1).w,(A1)+           | HD20 tag extension bytes (cont)
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_SKIP:
        ADDQ.W  #0x6,D6                         | add 6 overhead bytes to send count
        DIVU    #0x7,D6                         | convert bytes to 7-bit groups
        ANDI    #0x7F,D6                        | mask to 7 bits
        ADDQ.W  #0x6,D7                         | add 6 overhead bytes to receive count
        DIVU    #0x7,D7                         | convert bytes to 7-bit groups
        ANDI    #0x7F,D7                        | mask to 7 bits
        MOVEQ.L #0x0,D4                         | D4 = 0: total blocks transferred
        BRA.B   SONY_SENDCMD_LOOP               | enter command send loop

| ----------------------------------------------------------
|
| SONY_SENDCMD_NEXT
|
SONY_SENDCMD_NEXT:
        TST.B   D1                              | read command?
        BEQ.B   SONY_SENDCMD_EXIT               | yes -> all blocks done, return
        ORI.B   #0x40,0x19C(A1)                 | set continuation bit in command
        MOVE.B  D3,0x19D(A1)                    | SeqNum: store remaining block count
        ADDQ.L  #0x1,0x1A6(A1)                  | increment DCD sequence number
        MOVE    #0x7,0x1C0(A1)                  | ChkTime = 7 (700us next-block poll)
        MOVE    #0x2710,0x1C2(A1)               | MaxTime = 10000 (10 sec timeout)
SONY_SENDCMD_LOOP:
        CMPI.B  #0x3,D1                         | status command?
        BGE.B   SONY_SENDCMD_OK                 | yes -> no tag copy needed
        TST.B   D1                              | read command?
        BEQ.B   SONY_SENDCMD_OK                 | yes -> no tag copy (tags in recv)
        MOVE.L  A5,D0                           | TagBufPtr: external tag buffer?
        BEQ.B   SONY_SENDCMD_OK                 | no -> use default tags
        ADDA    #0x1A2,A1                       | point to DCD tag buffer area
        MOVE.L  (A5)+,(A1)+                     | copy 12 tag bytes from user buffer
        MOVE.L  (A5)+,(A1)+                     | tag bytes 5-8
        MOVE.L  (A5)+,(A1)+                     | tag bytes 9-12
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_OK:
        BSR     SONY_SENDCMD_CONT_3             | send DCD packet (serialize + transmit)
        BNE     SONY_SENDCMD_ERR                | send error -> set error status
SONY_SENDCMD_EXIT:
        RTS                                     | return to caller

| SONY_SENDCMD_CONT -- receive DCD response packet.
| ----------------------------------------------------------
|
| SONY_SENDCMD_CONT
|
SONY_SENDCMD_CONT:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address
        LEA.L   0x1800(A0),A3                   | A3 = IWM Q6L (handshake register)
        MOVE.B  0x19C(A1),D1                    | D1 = DCD command byte
        ANDI.B  #0x3F,D1                        | mask to base command (strip flags)
        BSR     SONY_SENDCMD_CONT_2             | receive response packet from DCD
        BNE     SONY_SENDCMD_ERR                | receive error -> set error status
        MOVE.L  0x19C(A1),D0                    | D0 = command + response bytes
        MOVE.B  #0x30,D0                        | D0.lo = InvalidResp error code
        SUBI.B  #0x80,0x19C(A1)                 | subtract $80: check Response = Cmd+$80
        CMP.B   0x19C(A1),D1                    | response matches expected?
        BNE.B   SONY_SENDCMD_ERR                | no -> invalid response error
        CMPI.B  #0x3,D1                         | status command?
        BGE.B   SONY_SENDCMD_SKIP_2             | yes -> skip sequence check
        MOVE.B  #0x31,D0                        | D0 = SqncNumErr error code
        CMP.B   0x19D(A1),D3                    | sequence number matches?
        BEQ.B   SONY_SENDCMD_OK_2               | yes -> response validated
        SWAP    D0                              | pack error info into D0.hi
        MOVE.B  D3,D0                           | store expected seq# in D0.lo
        SWAP    D0                              | restore: D0.hi = {err, expected}
        ROR.L   #0x8,D0                         | rotate to pack received seq#
        MOVE.B  0x19D(A1),D0                    | insert actual seq# received
        ROL.L   #0x8,D0                         | restore byte order
        BRA.B   SONY_SENDCMD_ERR                | sequence mismatch -> error

| ----------------------------------------------------------
|
| SONY_SENDCMD_OK_2
|
SONY_SENDCMD_OK_2:
        TST.B   D1                              | read command?
        BNE.B   SONY_SENDCMD_SKIP_2             | no -> skip tag extraction
        MOVE.L  A5,D0                           | TagBufPtr: external tag buffer?
        BEQ.B   SONY_SENDCMD_NO_2               | no -> copy to system globals
        ADDA    #0x1A2,A1                       | point to DCD tag buffer
        MOVE.L  (A1)+,(A5)+                     | copy 12 received tag bytes to user
        MOVE.L  (A1)+,(A5)+                     | tag bytes 5-8
        MOVE.L  (A1)+,(A5)+                     | tag bytes 9-12
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_NO_2:
        ADDA    #0x1A2,A1                       | point to DCD tag buffer
        MOVE.L  (A1)+,(BufTgFNum).w             | copy tag: file number
        MOVE.L  (A1)+,(BufTgFFlg).w             | copy tag: file flags
        MOVE.L  (A1)+,(BufTgDate).w             | copy tag: date
        MOVE.L  (A1)+,(BufTgHD20).w             | copy tag: HD20 extension
        MOVE.L  (A1)+,(BufTgHD20_1).w           | copy tag: HD20 extension (cont)
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_SKIP_2:
        MOVEQ.L #0x1,D2                         | D2 = 1: nonZerStat result type
        MOVE.L  0x19E(A1),D0                    | D0 = DCD status from response
        BTST    #0x18,D0                        | opFailed bit set?
        BNE.B   SONY_SENDCMD_ERR_2              | yes -> operation failed
        CMPI.B  #0xA,0x19E(A1)                  | status = $0A (disk changed)?
        BEQ.B   SONY_SENDCMD_ERR_2              | yes -> report as error
        ADDA.L  0x1B6(A1),A4                    | advance data buffer by BufSize
        ADDQ.L  #0x1,D4                         | count blocks transferred
        SUBQ.B  #0x1,D3                         | decrement blocks remaining
        BNE     SONY_SENDCMD_NEXT               | more blocks -> send next command
        MOVEQ.L #0x0,D0                         | noErr: all blocks transferred
SONY_SENDCMD_EXIT_2:
        ADDQ.W  #0x1,D3                         | restore D3 (was decremented to 0)
        ANDI    #-0x5,SR                        | clear carry and extend flags
        RTS                                     | return with D0 = result

| ----------------------------------------------------------
|
| SONY_SENDCMD_ERR
|
SONY_SENDCMD_ERR:
        MOVEQ.L #0x2,D2                         | D2 = 2: comErr result type
        ROR.L   #0x8,D0                         | pack error code into status word
SONY_SENDCMD_ERR_2:
        MOVE.L  D0,0x1BA(A1)                    | LastStatus: save DCD error status
        MOVE.B  D2,0x1BE(A1)                    | LastResult: save result type
        MOVEQ.L #0x1,D0                         | D0 = 1: indicate error
        BRA.B   SONY_SENDCMD_EXIT_2             | return via common exit

| SONY_SENDCMD_CONT_2 -- receive response packet from DCD.
| ----------------------------------------------------------
|
| SONY_SENDCMD_CONT_2
|
SONY_SENDCMD_CONT_2:
        MOVE    SR,-(SP)                        | save SR
        MOVEM.L D1-D7/A1/A4-A6,-(SP)            | save all registers
        ADDA    #0x19C,A1                       | A1 -> DCD command area in SonyVars
        MOVEQ.L #0x0,D5                         | D5 = running checksum
        TST.B   0x1A00(A0)                      | Q6 on: enter status read mode
        MOVEQ.L #0x20,D0                        | D0 = RdHsHi error code
        TST.B   0x1C00(A0)                      | read IWM status: check HSHK
        BMI     SONY_SENDCMD_ERR_6              | HSHK high -> error (should be low)
        MOVEM.L (SCCRd).w,A5-A6                 | load SCC read base addresses
        ADDQ.W  #0x2,A5                         | A5 = SCC channel A control
        ADDQ.W  #0x2,A6                         | A6 = SCC channel A data
        ORI     #0x700,SR                       | raise IPL to 7 (disable all ints)
        TST.B   0x200(A0)                       | CA0 on: prepare DCD handshake
        TST.B   0x400(A0)                       | CA1 off: set receive mode
        TST.B   (A3)                            | clear IWM handshake latch
        MOVEQ.L #0x21,D0                        | D0 = RdSyncTO error code
        MOVEQ.L #0x1,D6                         | D6 = $10000: sync timeout counter
        SWAP    D6                              | D6.hi = 1 -> D6 = $10000
SONY_SENDCMD_NO_3:
        SUBQ.L  #0x1,D6                         | decrement sync search timeout
        BEQ     SONY_SENDCMD_ERR_6              | timeout -> RdSyncTO error
        CMPI.B  #0xAA,(A3)                      | received sync byte ($AA)?
        BNE.B   SONY_SENDCMD_NO_3               | no -> keep searching
        MOVE    #0x50,D6                        | D6 = 80: group receive timeout
SONY_SENDCMD_LOOP_2:
        MOVE.B  (A3),D1                         | read first byte of group (cmd byte)
        DBMI    D6,SONY_SENDCMD_LOOP_2          | poll until valid (bit 7 set)
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> RdGroupTO error
        CMPI.B  #0xBF,D1                        | holdoff marker byte?
        BNE.B   SONY_SENDCMD_NO_4               | no -> normal data group
        MOVEQ.L #0x6,D7                         | D7 = 6: holdoff groups counter
        SWAP    D7                              | save in D7.hi
SONY_SENDCMD_NO_4:
        SWAP    D1                              | save D1 in high word
SONY_SENDCMD_LOOP_3:
        MOVE.B  (A3),D1                         | read byte 2 of group
        DBMI    D6,SONY_SENDCMD_LOOP_3          | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D1                              | restore: D1 = {byte1, byte2}
SONY_SENDCMD_LOOP_4:
        MOVE.B  (A3),D2                         | read byte 3 of group
        DBMI    D6,SONY_SENDCMD_LOOP_4          | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D2                              | save in high word
SONY_SENDCMD_LOOP_5:
        MOVE.B  (A3),D2                         | read byte 4 of group
        DBMI    D6,SONY_SENDCMD_LOOP_5          | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D2                              | D2 = {byte3, byte4}
SONY_SENDCMD_LOOP_6:
        MOVE.B  (A3),D3                         | read byte 5 of group
        DBMI    D6,SONY_SENDCMD_LOOP_6          | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D3                              | save in high word
SONY_SENDCMD_LOOP_7:
        MOVE.B  (A3),D3                         | read byte 6 of group
        DBMI    D6,SONY_SENDCMD_LOOP_7          | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D3                              | D3 = {byte5, byte6}
SONY_SENDCMD_LOOP_8:
        MOVE.B  (A3),D4                         | read byte 7 of group (parity)
        DBMI    D6,SONY_SENDCMD_LOOP_8          | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D4                              | save in high word
SONY_SENDCMD_LOOP_9:
        MOVE.B  (A3),D4                         | read byte 8 of group
        DBMI    D6,SONY_SENDCMD_LOOP_9          | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        DBF     D7,SONY_SENDCMD_LOOP_10         | decrement group counter, decode
        BRA     SONY_SENDCMD_DONE               | last group -> decode final bytes

| ----------------------------------------------------------
|
| SONY_SENDCMD_ERR_3
|
SONY_SENDCMD_ERR_3:
        MOVEQ.L #0x22,D0                        | RdGroupTO: group receive timeout
        BRA     SONY_SENDCMD_ERR_6              | exit with error

| ----------------------------------------------------------
|
| SONY_SENDCMD_LOOP_10
|
SONY_SENDCMD_LOOP_10:
        MOVEQ.L #0x3,D6                         | D6.hi = 3: switch to data after 3 groups
        SWAP    D6                              | save in high word
        MOVE    #0x50,D6                        | D6.lo = 80: byte receive timeout
SONY_SENDCMD_LOOP_11:
        LSR.B   #0x1,D4                         | shift parity bit into extend
        ADDX.B  D1,D1                           | reconstruct byte 1 with parity bit
        ADD.B   D1,D5                           | accumulate into checksum
        MOVE.B  D1,(A1)+                        | store decoded byte 1
SONY_SENDCMD_LOOP_12:
        MOVE.B  (A3),D1                         | read next group byte 1
        DBMI    D6,SONY_SENDCMD_LOOP_12         | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D1                              | save in high word
        MOVE.B  #0x3,(A6)                       | reset SCC channel A (wr reg 3)
        LSR.B   #0x1,D4                         | shift next parity bit
        ADDX.B  D1,D1                           | reconstruct byte 2 with parity
        ADD.B   D1,D5                           | accumulate checksum
        MOVE.B  D1,(A1)+                        | store decoded byte 2
SONY_SENDCMD_LOOP_13:
        MOVE.B  (A3),D1                         | read next group byte 2
        DBMI    D6,SONY_SENDCMD_LOOP_13         | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D1                              | save in high word
        TST     D7                              | holdoff groups remaining?
        BEQ.B   SONY_SENDCMD_SKIP_3             | no -> skip SCC check
        TST.B   (A5)                            | check SCC channel A status
SONY_SENDCMD_SKIP_3:
        SNE.B   D0                              | D0 = $FF if SCC needs service
        LSR.B   #0x1,D4                         | shift next parity bit
        ADDX.B  D2,D2                           | reconstruct byte 3 with parity
        ADD.B   D2,D5                           | accumulate checksum
        MOVE.B  D2,(A1)+                        | store decoded byte 3
SONY_SENDCMD_LOOP_14:
        MOVE.B  (A3),D2                         | read next group byte 3
        DBMI    D6,SONY_SENDCMD_LOOP_14         | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D2                              | save in high word
        LSR.B   #0x1,D4                         | shift next parity bit
        ADDX.B  D2,D2                           | reconstruct byte 4 with parity
        ADD.B   D2,D5                           | accumulate checksum
        MOVE.B  D2,(A1)+                        | store decoded byte 4
SONY_SENDCMD_LOOP_15:
        MOVE.B  (A3),D2                         | read next group byte 4
        DBMI    D6,SONY_SENDCMD_LOOP_15         | poll until valid
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D2                              | save in high word
        TST.B   D0                              | SCC needs service?
        BEQ.B   SONY_SENDCMD_SKIP_4             | no -> skip
        TST.B   (A0)                            | service IWM (clears SCC flag)
SONY_SENDCMD_SKIP_4:
        LSR.B   #0x1,D4                         | shift next parity bit
        ADDX.B  D3,D3                           | reconstruct byte 5 with parity
        ADD.B   D3,D5                           | accumulate checksum
        MOVE.B  D3,(A1)+                        | store decoded byte 5
SONY_SENDCMD_LOOP_16:
        MOVE.B  (A3),D3                         | read next group byte 5
        DBMI    D6,SONY_SENDCMD_LOOP_16         | poll until valid
SONY_SENDCMD_ERR_4:
        BPL.B   SONY_SENDCMD_ERR_3              | timeout -> error
        SWAP    D3                              | save in high word
        SWAP    D6                              | check header/data group switch
        DBF     D6,SONY_SENDCMD_LOOP_17         | decrement: switch to data after 3
        MOVE.L  A4,A1                           | switch dest from cmd area to data buf
SONY_SENDCMD_LOOP_17:
        SWAP    D6                              | restore receive timeout
        LSR.B   #0x1,D4                         | shift next parity bit
        ADDX.B  D3,D3                           | reconstruct byte 6 with parity
        ADD.B   D3,D5                           | accumulate checksum
        MOVE.B  D3,(A1)+                        | store decoded byte 6
SONY_SENDCMD_LOOP_18:
        MOVE.B  (A3),D3                         | read next group byte 6
        DBMI    D6,SONY_SENDCMD_LOOP_18         | poll until valid
        BPL.B   SONY_SENDCMD_ERR_4              | timeout -> error
        SWAP    D3                              | save in high word
        LSR.B   #0x1,D4                         | shift last parity bit
        SWAP    D4                              | access parity byte in low word
        ADDX.B  D4,D4                           | reconstruct byte 7 with parity
        ADD.B   D4,D5                           | accumulate checksum
        MOVE.B  D4,(A1)+                        | store decoded byte 7
SONY_SENDCMD_LOOP_19:
        MOVE.B  (A3),D4                         | read next group parity byte
        DBMI    D6,SONY_SENDCMD_LOOP_19         | poll until valid
        BPL.B   SONY_SENDCMD_ERR_4              | timeout -> error
        SWAP    D4                              | D4 = {parity, next_parity}
        MOVE    #0x50,D6                        | reset receive timeout to 80
SONY_SENDCMD_LOOP_20:
        MOVE.B  (A3),D4                         | read group sync/marker byte
        DBMI    D6,SONY_SENDCMD_LOOP_20         | poll until valid
        BPL.B   SONY_SENDCMD_ERR_4              | timeout -> error
        TST.B   D0                              | SCC holdoff pending?
        DBNE    D7,SONY_SENDCMD_LOOP_11         | no -> decode next group
        BEQ.B   SONY_SENDCMD_DONE               | all groups done -> finalize
        TST.B   (A5)                            | service SCC channel A
        ANDI    #-0x701,SR                      | restore IPL (enable ints briefly)
        SUBQ.W  #0x1,D7                         | decrement holdoff group counter
        MOVEQ.L #0x10,D0                        | D0 = 16: brief delay loop
SONY_SENDCMD_LOOP_21:
        DBF     D0,SONY_SENDCMD_LOOP_21         | spin delay for SCC service
        ORI     #0x700,SR                       | raise IPL back to 7
        TST.B   0x200(A0)                       | CA0 on: re-enable DCD handshake
        TST.B   (A3)                            | clear IWM handshake latch
        CLR     D0                              | D0 = $10000: sync search counter
SONY_SENDCMD_NO_5:
        SUBQ.W  #0x1,D0                         | decrement sync timeout
        BEQ.B   SONY_SENDCMD_ERR_5              | timeout -> holdoff sync error
        CMPI.B  #0xAA,(A3)                      | re-sync: found $AA?
        BNE.B   SONY_SENDCMD_NO_5               | no -> keep searching
        BRA     SONY_SENDCMD_LOOP_11            | synced -> resume group receive

| ----------------------------------------------------------
|
| SONY_SENDCMD_ERR_5
|
SONY_SENDCMD_ERR_5:
        MOVEQ.L #0x24,D0                        | RdHoffSyncTO: holdoff re-sync timeout
        BRA.B   SONY_SENDCMD_ERR_6              | exit with error

| ----------------------------------------------------------
|
| SONY_SENDCMD_DONE
|
SONY_SENDCMD_DONE:
        SWAP    D7                              | D7 = remaining bytes in final group
        LSR.B   #0x1,D4                         | shift parity bit for byte 1
        ADDX.B  D1,D1                           | reconstruct byte 1
        ADD.B   D1,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | one fewer byte remaining
        BMI.B   SONY_SENDCMD_NO_6               | negative -> no more bytes to store
        MOVE.B  D1,(A1)+                        | store decoded byte 1
SONY_SENDCMD_NO_6:
        SWAP    D1                              | access byte 2 from high word
        LSR.B   #0x1,D4                         | shift parity bit for byte 2
        ADDX.B  D1,D1                           | reconstruct byte 2
        ADD.B   D1,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_SENDCMD_SKIP_5             | no more -> skip store
        MOVE.B  D1,(A1)+                        | store decoded byte 2
SONY_SENDCMD_SKIP_5:
        LSR.B   #0x1,D4                         | shift parity bit for byte 3
        ADDX.B  D2,D2                           | reconstruct byte 3
        ADD.B   D2,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_SENDCMD_SKIP_6             | no more -> skip store
        MOVE.B  D2,(A1)+                        | store decoded byte 3
SONY_SENDCMD_SKIP_6:
        SWAP    D2                              | access byte 4 from high word
        LSR.B   #0x1,D4                         | shift parity bit for byte 4
        ADDX.B  D2,D2                           | reconstruct byte 4
        ADD.B   D2,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_SENDCMD_SKIP_7             | no more -> skip store
        MOVE.B  D2,(A1)+                        | store decoded byte 4
SONY_SENDCMD_SKIP_7:
        LSR.B   #0x1,D4                         | shift parity bit for byte 5
        ADDX.B  D3,D3                           | reconstruct byte 5
        ADD.B   D3,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_SENDCMD_SKIP_8             | no more -> skip store
        MOVE.B  D3,(A1)+                        | store decoded byte 5
SONY_SENDCMD_SKIP_8:
        SWAP    D3                              | access byte 6 from high word
        LSR.B   #0x1,D4                         | shift parity bit for byte 6
        ADDX.B  D3,D3                           | reconstruct byte 6
        ADD.B   D3,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_SENDCMD_SKIP_9             | no more -> skip store
        MOVE.B  D3,(A1)+                        | store decoded byte 6
SONY_SENDCMD_SKIP_9:
        LSR.B   #0x1,D4                         | shift last parity bit
        SWAP    D4                              | access byte 7
        ADDX.B  D4,D4                           | reconstruct byte 7
        ADD.B   D4,D5                           | accumulate final checksum byte
        TST.B   0x600(A0)                       | CA1 on: signal receive complete
        TST.B   0x1A00(A0)                      | Q6 on: read HSHK status
        MOVEQ.L #0x25,D0                        | D0 = RdHsHiTO: assume HSHK error
        TST.B   0x1C00(A0)                      | read IWM status: HSHK high?
        BPL.B   SONY_SENDCMD_ERR_6              | wait for data ready (sign bit clear)
        MOVE.B  D5,D0                           | move byte
        BEQ.B   SONY_SENDCMD_ERR_6              | branch if zero
        MOVEQ.L #0x26,D0                        | set value
SONY_SENDCMD_ERR_6:
        TST.B   (A5)                            | _PollSCC: poll SCC modem port to avoid overruns
        TST.B   0x600(A0)                       | test status bit
        TST.B   (A0)                            | test status bit
        MOVEM.L (SP)+,D1-D7/A1/A4-A6            | restore registers
        MOVE    (SP)+,SR                        | restore SR
        TST.B   D0                              | test result code
        RTS                                     | return

| SONY_SENDCMD_CONT_3 -- send DCD packet (serialize + transmit).
| ----------------------------------------------------------
|
| SONY_SENDCMD_CONT_3
|
SONY_SENDCMD_CONT_3:
        MOVE    SR,-(SP)                        | save SR
        MOVEM.L D1-D7/A1/A4-A6,-(SP)            | save registers
        ADDA    #0x19C,A1                       | add to address register
        MOVEM.L (SCCRd).w,A5-A6                 | A5, A6 = SCC Read ports
        ADDQ.W  #0x2,A5                         | point to channel A data
        ADDQ.W  #0x2,A6                         | point to channel A data
        MOVE.B  D1,D4                           | move byte
        SWAP    D4                              | swap counters/buffers
        SWAP    D6                              | swap counters/buffers
        MOVE    D7,D6                           | move word
        SWAP    D6                              | swap counters/buffers
        MOVEQ.L #0x0,D5                         | init CkSumA
        ST.B    D4                              | set flag byte
        MOVE.B  (A1)+,D1                        | store decoded byte
        ADD.B   D1,D5                           | add byte to checksum
        ROXR.B  #0x1,D1                         | rotate right with extend
        ORI.B   #0x80,D1                        | set high bit
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D1                              | swap counters/buffers
        MOVE.B  (A1)+,D1                        | store decoded byte
        ADD.B   D1,D5                           | add byte to checksum
        ROXR.B  #0x1,D1                         | rotate right with extend
        ORI.B   #0x80,D1                        | set high bit
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D1                              | swap counters/buffers
        MOVE.B  (A1)+,D2                        | store decoded byte
        ADD.B   D2,D5                           | add byte to checksum
        ROXR.B  #0x1,D2                         | rotate right with extend
        ORI.B   #0x80,D2                        | set high bit
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D2                              | swap counters/buffers
        MOVE.B  (A1)+,D2                        | store decoded byte
        ADD.B   D2,D5                           | add byte to checksum
        ROXR.B  #0x1,D2                         | rotate right with extend
        ORI.B   #0x80,D2                        | set high bit
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D2                              | swap counters/buffers
        MOVE.B  (A1)+,D3                        | store decoded byte
        ADD.B   D3,D5                           | add byte to checksum
        ROXR.B  #0x1,D3                         | rotate right with extend
        ORI.B   #0x80,D3                        | set high bit
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D3                              | swap counters/buffers
        MOVE.B  (A1)+,D3                        | store decoded byte
        ADD.B   D3,D5                           | add byte to checksum
        ROXR.B  #0x1,D3                         | rotate right with extend
        ORI.B   #0x80,D3                        | set high bit
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D3                              | swap counters/buffers
        SWAP    D4                              | swap counters/buffers
        TST.B   0x1A00(A0)                      | test status bit
        MOVEQ.L #0x10,D0                        | set value
        TST.B   0x1C00(A0)                      | test status bit
        BPL     SONY_SENDCMD_EMPTY_3            | branch if positive
        TST.B   0x200(A0)                       | test status bit
        MOVEQ.L #0x11,D0                        | set value
        MOVEQ.L #0x14,D7                        | set value
        SWAP    D7                              | swap counters/buffers
SONY_SENDCMD_SKIP_10:
        SUBQ.L  #0x1,D7                         | decrement long counter
        BEQ     SONY_SENDCMD_EMPTY_3            | branch if zero
        TST.B   0x1C00(A0)                      | test status bit
        BMI.B   SONY_SENDCMD_SKIP_10            | _PollSCC: skip if no data
        TST.B   0x400(A0)                       | test status bit
        LEA.L   0x1A00(A0),A0                   | load effective address
        ORI     #0x700,SR                       | disable interrupts
        MOVEQ.L #0x2,D7                         | set value
        CMPI.B  #0x4,D4                         | compare immediate byte
        BLT.B   SONY_SENDCMD_CONT_4             | branch if less than
        MOVEQ.L #-0x1,D7                        | set error/timeout code
        MOVE.L  A4,A1                           | move long
SONY_SENDCMD_CONT_4:
        MOVEQ.L #0x4,D0                         | set value
SONY_SENDCMD_LOOP_22:
        DBF     D0,SONY_SENDCMD_LOOP_22         | decrement timeout and loop
        MOVE.L  D6,D0                           | move long
        ADDI.L  #0x810081,D0                    | add immediate long
        MOVE.B  #0xAA,0x400(A0)                 | store byte to buffer
SONY_SENDCMD_CONT_5:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_5             | wait for data ready (sign bit clear)
        MOVE.B  D0,(A0)                         | store byte to buffer
        SWAP    D0                              | swap counters/buffers
SONY_SENDCMD_CONT_6:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_6             | wait for data ready (sign bit clear)
        MOVE.B  D0,(A0)                         | store byte to buffer
        MOVEQ.L #-0x80,D0                       | set error/timeout code
        BRA     SONY_SENDCMD_CONT_11            | branch

| ----------------------------------------------------------
|
| SONY_SENDCMD_LOOP_23
|
SONY_SENDCMD_LOOP_23:
        MOVE.B  (A1)+,D4                        | store decoded byte
        ADD.B   D4,D5                           | add byte to checksum
        ROXR.B  #0x1,D4                         | rotate right with extend
        OR.B    D0,D4                           | OR decoded nibble
        SWAP    D4                              | swap counters/buffers
        ROXR.B  #0x2,D4                         | rotate right with extend
SONY_SENDCMD_CONT_7:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_7             | wait for data ready (sign bit clear)
        MOVE.B  D4,(A0)                         | store byte to buffer
        ST.B    D4                              | set flag byte
        MOVE.B  #0x3,(A6)                       | move byte
SONY_SENDCMD_CONT_8:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_8             | wait for data ready (sign bit clear)
        MOVE.B  D1,(A0)                         | store byte to buffer
        MOVE.B  (A1)+,D1                        | store decoded byte
        ADD.B   D1,D5                           | add byte to checksum
        ROXR.B  #0x1,D1                         | rotate right with extend
        OR.B    D0,D1                           | OR decoded nibble
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D1                              | swap counters/buffers
        TST.B   (A5)                            | _PollSCC: poll SCC modem port to avoid overruns
        BEQ.B   SONY_SENDCMD_EMPTY              | branch if zero
        BSET    #0x1F,D6                        | set bit
SONY_SENDCMD_EMPTY:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_EMPTY              | wait for data ready (sign bit clear)
        MOVE.B  D1,(A0)                         | store byte to buffer
        MOVE.B  (A1)+,D1                        | store decoded byte
        ADD.B   D1,D5                           | add byte to checksum
        ROXR.B  #0x1,D1                         | rotate right with extend
        OR.B    D0,D1                           | OR decoded nibble
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D1                              | swap counters/buffers
        TST     D6                              | test word
        BNE.B   SONY_SENDCMD_NO_7               | branch if not equal
        BCLR    #0x1F,D6                        | clear bit
SONY_SENDCMD_NO_7:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_NO_7               | wait for data ready (sign bit clear)
        MOVE.B  D2,(A0)                         | store byte to buffer
        MOVE.B  (A1)+,D2                        | store decoded byte
        ADD.B   D2,D5                           | add byte to checksum
        ROXR.B  #0x1,D2                         | rotate right with extend
        OR.B    D0,D2                           | OR decoded nibble
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D2                              | swap counters/buffers
        BTST    #0x1F,D6                        | test bit
        BEQ.B   SONY_SENDCMD_EMPTY_2            | branch if zero
        TST.B   -0x1A00(A0)                     | test status bit
SONY_SENDCMD_EMPTY_2:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_EMPTY_2            | wait for data ready (sign bit clear)
        MOVE.B  D2,(A0)                         | store byte to buffer
        MOVE.B  (A1)+,D2                        | store decoded byte
        ADD.B   D2,D5                           | add byte to checksum
        ROXR.B  #0x1,D2                         | rotate right with extend
        OR.B    D0,D2                           | OR decoded nibble
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D2                              | swap counters/buffers
SONY_SENDCMD_CONT_9:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_9             | wait for data ready (sign bit clear)
        MOVE.B  D3,(A0)                         | store byte to buffer
        MOVE.B  (A1)+,D3                        | store decoded byte
        ADD.B   D3,D5                           | add byte to checksum
        ROXR.B  #0x1,D3                         | rotate right with extend
        OR.B    D0,D3                           | OR decoded nibble
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D3                              | swap counters/buffers
        DBF     D7,SONY_SENDCMD_LOOP_24         | decrement timeout and loop
        MOVE.L  A4,A1                           | move long
SONY_SENDCMD_LOOP_24:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_LOOP_24            | wait for data ready (sign bit clear)
        MOVE.B  D3,(A0)                         | store byte to buffer
        MOVE.B  (A1)+,D3                        | store decoded byte
        ADD.B   D3,D5                           | add byte to checksum
        ROXR.B  #0x1,D3                         | rotate right with extend
        OR.B    D0,D3                           | OR decoded nibble
        ROXR.B  #0x1,D4                         | rotate right with extend
        SWAP    D3                              | swap counters/buffers
        SWAP    D4                              | swap counters/buffers
SONY_SENDCMD_CONT_10:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_10            | wait for data ready (sign bit clear)
        MOVE.B  D4,(A0)                         | store byte to buffer
        BCLR    #0x1F,D6                        | clear bit
        BNE.B   SONY_SENDCMD_NO_8               | branch if not equal
SONY_SENDCMD_CONT_11:
        DBF     D6,SONY_SENDCMD_LOOP_23         | decrement timeout and loop
        BRA.B   SONY_SENDCMD_CONT_13            | branch

| ----------------------------------------------------------
|
| SONY_SENDCMD_NO_8
|
SONY_SENDCMD_NO_8:
        CLR.B   D0                              | clear value
SONY_SENDCMD_CONT_12:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_12            | wait for data ready (sign bit clear)
        MOVE.B  D0,(A0)                         | store byte to buffer
        ANDI    #-0x701,SR                      | and immediate
        MOVE    #0x10,D0                        | move word
SONY_SENDCMD_LOOP_25:
        DBF     D0,SONY_SENDCMD_LOOP_25         | decrement timeout and loop
        SUBQ.W  #0x1,D6                         | decrement word counter
        TST.B   0x200(A0)                       | test status bit
        TST.B   -0x200(A0)                      | test status bit
        TST.B   (A0)                            | test status bit
        TST.B   -0x1800(A0)                     | test status bit
        MOVE    #0x10,D0                        | move word
SONY_SENDCMD_LOOP_26:
        DBF     D0,SONY_SENDCMD_LOOP_26         | decrement timeout and loop
        MOVEQ.L #-0x80,D0                       | set error/timeout code
        ORI     #0x700,SR                       | disable interrupts
        MOVE.B  #0xAA,0x400(A0)                 | store byte to buffer
        BRA     SONY_SENDCMD_LOOP_23            | branch

| ----------------------------------------------------------
|
| SONY_SENDCMD_CONT_13
|
SONY_SENDCMD_CONT_13:
        NEG.B   D5                              | negate byte
        ROXR.B  #0x1,D5                         | rotate right with extend
        OR.B    D0,D5                           | OR decoded nibble
        SWAP    D4                              | swap counters/buffers
        ROXR.B  #0x2,D4                         | rotate right with extend
SONY_SENDCMD_CONT_14:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_14            | wait for data ready (sign bit clear)
        MOVE.B  D4,(A0)                         | store byte to buffer
SONY_SENDCMD_CONT_15:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_15            | wait for data ready (sign bit clear)
        MOVE.B  D1,(A0)                         | store byte to buffer
        SWAP    D1                              | swap counters/buffers
SONY_SENDCMD_CONT_16:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_16            | wait for data ready (sign bit clear)
        MOVE.B  D1,(A0)                         | store byte to buffer
SONY_SENDCMD_CONT_17:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_17            | wait for data ready (sign bit clear)
        MOVE.B  D2,(A0)                         | store byte to buffer
        SWAP    D2                              | swap counters/buffers
SONY_SENDCMD_CONT_18:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_18            | wait for data ready (sign bit clear)
        MOVE.B  D2,(A0)                         | store byte to buffer
SONY_SENDCMD_CONT_19:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_19            | wait for data ready (sign bit clear)
        MOVE.B  D3,(A0)                         | store byte to buffer
        SWAP    D3                              | swap counters/buffers
SONY_SENDCMD_CONT_20:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_20            | wait for data ready (sign bit clear)
        MOVE.B  D3,(A0)                         | store byte to buffer
SONY_SENDCMD_CONT_21:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_21            | wait for data ready (sign bit clear)
        MOVE.B  D5,(A0)                         | store byte to buffer
SONY_SENDCMD_CONT_22:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_22            | wait for data ready (sign bit clear)
        MOVEQ.L #0x0,D0                         | set value
        MOVE.B  D0,(A0)                         | store byte to buffer
SONY_SENDCMD_CONT_23:
        TST.B   (A3)                            | test status bit
        BPL.B   SONY_SENDCMD_CONT_23            | wait for data ready (sign bit clear)
        MOVE.B  D0,(A0)                         | store byte to buffer
        MOVE.L  (IWM).w,A0                      | move long
        TST.B   0x600(A0)                       | test status bit
        MOVEQ.L #0x13,D0                        | set value
        MOVEQ.L #-0x1,D7                        | set error/timeout code
SONY_SENDCMD_CONT_24:
        SUBQ.W  #0x1,D7                         | decrement word counter
        BEQ.B   SONY_SENDCMD_EMPTY_3            | branch if zero
        TST.B   0x1C00(A0)                      | test status bit
        BPL.B   SONY_SENDCMD_CONT_24            | wait for data ready (sign bit clear)
        MOVEQ.L #0x0,D0                         | set value
SONY_SENDCMD_EMPTY_3:
        TST.B   0x600(A0)                       | test status bit
        TST.B   (A0)                            | test status bit
        MOVEM.L (SP)+,D1-D7/A1/A4-A6            | restore registers
        MOVE    (SP)+,SR                        | restore SR
        TST.B   D0                              | test result code
        RTS                                     | return

| E_Sony_DCDReset -- hard-reset the DCD controller.
| ----------------------------------------------------------
|
| E_Sony_DCD Reset
|
E_Sony_DCDReset:
        MOVE.L  (JDCDReset).w,-(SP)             | push address/value
        RTS                                     | return

| ----------------------------------------------------------
|
| Sony DCDReset
|
Sony_DCDReset:
        MOVE.L  (SP)+,A3                        | pop address/value
        BSR     Sony_JumpDiskSel                | branch to subroutine
        TST.B   0xA00(A0)                       | CA2 on
        TST.B   0x400(A0)                       | CA1 off
        TST.B   (A0)                            | CA0 off
        MOVE    #0x3E8,D0                       | move word
        BSR     E_Sony_WakeUp                   | branch to subroutine
        TST.B   0x600(A0)                       | CA1 on
        TST.B   0x800(A0)                       | CA2 off
        MOVE    #0x4E20,D0                      | move word
        BSR     E_Sony_WakeUp                   | branch to subroutine
        MOVE    #0x64,0x1C0(A1)                 | move word
        MOVE    #0x640,0x1C2(A1)                | move word
SONY_DCDRESET_CONT:
        BSR     Sony_ReadDriveReg               | read ???
        BMI.B   SONY_DCDRESET_SKIP              | _PollSCC: skip if no data
        SUBQ.W  #0x1,0x1C2(A1)                  | decrement word counter
        BMI.B   SONY_DCDRESET_SKIP_2            | _PollSCC: skip if no data
        MOVE    0x1C0(A1),D0                    | move word
        BSR     E_Sony_WakeUp                   | branch to subroutine
        BRA.B   SONY_DCDRESET_CONT              | branch

| ----------------------------------------------------------
|
| SONY_DCDRESET_SKIP
|
SONY_DCDRESET_SKIP:
        MOVEQ.L #0x0,D0                         | set value
        JMP     (A3)                            | jump to routine

| ----------------------------------------------------------
|
| SONY_DCDRESET_SKIP_2
|
SONY_DCDRESET_SKIP_2:
        TST.B   0x1800(A0)                      | Q6 off
        MOVEQ.L #-0x1,D0                        | set error/timeout code
        JMP     (A3)                            | jump to routine

| ----------------------------------------------------------
|
| SONY_DCDRESET_CONT_2
|
SONY_DCDRESET_CONT_2:
        BNE.B   SONY_DCDRESET_NO                | branch if not equal
        LEA.L   0x1F0(A1),A2                    | load effective address
        MOVE.L  (A1),A0                         | move long
        MOVE.L  0x8(A0),A0                      | move long
        MOVE.L  A2,0x1C(A0)                     | move long
SONY_DCDRESET_NO:
        BRA     DT_SONY_NIBLTBL_ERR_13          | branch

| ----------------------------------------------------------
|
| SONY_DCDRESET_CONT_3
|
SONY_DCDRESET_CONT_3:
        BTST    #0x2,0x1A(A1,D1.W)              | test bit
        BEQ     Sony_ReturnErrUnimplementedControl | branch if zero
        LEA.L   SONY_DCDRESET_CONT_2(PC),A0     | load effective address
        MOVE.L  A0,0x198(A1)                    | move long
SONY_DCDRESET_CONT_4:
        MOVEQ.L #0x3,D3                         | set value
        BRA.B   SONY_DCDRESET_CONT_7            | branch

| ----------------------------------------------------------
|
| SONY_DCDRESET_CONT_5
|
SONY_DCDRESET_CONT_5:
        MOVEQ.L #0x1A,D3                        | set value
        BRA.B   SONY_DCDRESET_CONT_7            | branch

| ----------------------------------------------------------
|
| SONY_DCDRESET_CONT_6
|
SONY_DCDRESET_CONT_6:
        MOVEQ.L #0x19,D3                        | set value
SONY_DCDRESET_CONT_7:
        BSR     Sony_JumpDiskSel                | branch to subroutine
        TST.B   (A0)                            | test status bit
        TST.B   0x800(A0)                       | test status bit
        CLR.B   0x1BF(A1)                       | clear value
        MOVE.B  D3,0x19C(A1)                    | move byte
SONY_DCDRESET_NO_2:
        MOVE.L  (SonyVars).w,A1                 | move long
        ANDI.B  #0x3F,0x19C(A1)                 | and immediate
        SUBA.L  A4,A4                           | clear A4
        SUBA.L  A5,A5                           | clear A5
        MOVEQ.L #0x1,D3                         | set value
        MOVEQ.L #0x0,D6                         | init CkSumB
        MOVEQ.L #0x0,D7                         | init CkSumC
        MOVE    #0x64,0x1C0(A1)                 | move word
        MOVE    #0x4650,0x1C2(A1)               | move word
        CMPI.B  #0x3,0x19C(A1)                  | check for specific command
        BNE.B   SONY_DCDRESET_NO_3              | branch if not equal
        MOVE.L  #0x14C,D7                       | move long
        MOVE    #0xA,0x1C0(A1)                  | move word
        MOVE    #0x2710,0x1C2(A1)               | move word
        LEA.L   0x1C4(A1),A4                    | load effective address
SONY_DCDRESET_NO_3:
        BSR     E_Sony_SendCmd                  | branch to subroutine
        BEQ.B   SONY_DCDRESET_EMPTY_2           | branch if zero
SONY_DCDRESET_SKIP_3:
        CMPI.B  #0x2,0x1BA(A1)                  | compare immediate byte
        BEQ.B   SONY_DCDRESET_EMPTY             | branch if zero
        BTST    #0x1E,0x1BA(A1)                 | test bit
        BEQ.B   SONY_DCDRESET_EMPTY             | branch if zero
        BSET    #0x1,0x1BF(A1)                  | set bit
        BNE.B   SONY_DCDRESET_NO_2              | branch if not equal
SONY_DCDRESET_EMPTY:
        BSet    #0x0,0x1BF(A1)                  | set bit
        BNE.B   SONY_DCDRESET_NO_4              | branch if not equal
        BSR     E_Sony_DCDReset                 | branch to subroutine
        BNE.B   SONY_DCDRESET_NO_4              | branch if not equal
        BRA.B   SONY_DCDRESET_NO_2              | branch

| ----------------------------------------------------------
|
| SONY_DCDRESET_EMPTY_2
|
SONY_DCDRESET_EMPTY_2:
        BSR     DT_SONY_NIBLTBL_CONT_25         | branch to subroutine
        BMI.B   SONY_DCDRESET_SKIP_3            | _PollSCC: skip if no data
        BSR     SONY_SENDCMD_CONT               | branch to subroutine
        TST     D0                              | test word result
        BNE.B   SONY_DCDRESET_SKIP_3            | branch if not equal
        MOVEQ.L #0x0,D0                         | set value
        BRA.B   SONY_DCDRESET_CONT_8            | branch

| ----------------------------------------------------------
|
| SONY_DCDRESET_NO_4
|
SONY_DCDRESET_NO_4:
        MOVEQ.L #-0x11,D0                       | set error/timeout code
SONY_DCDRESET_CONT_8:
        CMPI.B  #0x3,0x19C(A1)                  | check for specific command
        BEQ.B   SONY_DCDRESET_EMPTY_3           | branch if zero
        BRA     DT_SONY_NIBLTBL_ERR_13          | branch

| ----------------------------------------------------------
|
| SONY_DCDRESET_EMPTY_3
|
SONY_DCDRESET_EMPTY_3:
        MOVE.L  0x198(A1),A0                    | move long
        TST     D0                              | test word result
        JMP     (A0)                            | jump to routine

| end of resource : 'DRVR' 4 '.Sony'

| resource header
  .long 0xC000095A                              | Length
  .long 0x00000060                              | ?

