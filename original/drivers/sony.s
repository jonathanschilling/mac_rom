| ========================================================================
| DRVR 4 -- .Sony disk driver (Mac 128K / 512K: 400K floppy drives)
| ========================================================================
| (In the 64K ROM a driver in ROM code, not a 'DRVR' resource: InitIOMgr
| installs it from DRVR_INSTALL_TABLE.)
|
| Apple's 1984 Sony disk driver (Larry Kenyon), the ancestor of the Mac
| Plus driver (src/plus/resources/res_drvr_sony.s, whose banner describes
| the IWM, the drive registers and the GCR format; the routine names are
| those of Apple's System 7.1 Sony sources). It runs the IWM for the
| internal drive (drive 1) and an external drive (drive 2): 400K one-
| sided drives, whose spindle speed the Mac sets for each zone of 16
| tracks through the PWM bytes of the sound buffer (SetSpeed). Unlike the
| Plus driver it has no HD20 support, no track cache, no Format or Verify
| call and no new-interface (800K) drive support; WakeUp times the waits
| with VIA timer 2 itself (the Plus uses the Time Manager). The block-to-
| track computation and the side bit already allow two-sided disks
| (TwoSideFmt from the format byte, twoSideErr).
| Register conventions (Apple: GetDrive): A1 = SonyVars, D1 = offset of
| the current drive's variables in SonyVars, A0 = IWM base, A2 = VIA
| base; during transfers A4 = IWM data register, A5 = VIA port A (SCC
| W/REQ in bit 7), A6 = SCC channel A data (SCC polling, see SetUpPoll).
| IWM mode $1F (set by Recal): latch mode, asynchronous handshake,
| 1-second timer off, fast mode (2-us bit cells), 8 MHz clock.
|
| Disk speed: one speed code (0-$18F) per zone in TrkSpeedTbl of the drive
| variables, measured by MakeSpdTbl with the tachometer and rechecked by
| ReSeek every CkDelta (4 minutes), plus the drive's OffSpeed (+22);
| "the Sound Driver and disk speed-control circuitry share a special
| 740-byte buffer" (Inside Macintosh II-233): the high bytes of its 370
| words are sound samples, the low bytes the PWM values SetSpeed writes.
|
| SonyVars: 250 bytes ($FA, DiskVarLth of this version): the layout of
| include/sonyequ.inc up to TagBufOS: driver variables $00-$49, drive 1
| variables $4A, drive 2 $8C (66 bytes each), WakeTimeCnt $CE (timer 2
| wraps left), SaveRegs $D0, TagBufPtr $F4, TagBufOS $F8.
|
| DRVR header (Inside Macintosh II-188; the 64K ROM has no resource fork)
DRVR_Sony:                                      | start of .Sony DRVR header
        .short  0x4F00                          | drvrFlags: dNeedLock+dStatEnable+dCtlEnable+dWritEnable+dReadEnable
        .short  0x0000                          | drvrDelay: no periodic action
        .short  0x0000                          | drvrEMask: no event mask
        .short  0x0000                          | drvrMenu: no menu
        .short  E_Sony_Open-DRVR_Sony           | drvrOpen: $0050
        .short  E_Sony_Prime-DRVR_Sony          | drvrPrime: $018C
        .short  E_Sony_Control-DRVR_Sony        | drvrCtl: $00DA
        .short  E_Sony_Status-DRVR_Sony         | drvrStatus: $0144
        .short  E_Sony_Close-DRVR_Sony          | drvrClose: $00B4 (an RTS)
        .byte   0x05                            | drvrName length = 5
        .ascii  ".Sony"                         | drvrName: ".Sony"

| InitDskTbl -- word offsets (relative to INITDSKTBL) of the disk routines
| whose addresses DiskOpen stores in the 12 jump vectors of DiskVars
| (JFigTrkSpd..JMakeSpdTbl, $222-$24E; JmpTblInit). Patches can redirect
| a routine by changing its vector. (The Plus has 3 more: JAdrDisk,
| JSetSpeed and the NiblTbl address.)
INITDSKTBL:
        .short  Sony_FigTrkSpd-INITDSKTBL       | JFigTrkSpd ($222)
        .short  Sony_DiskPrime-INITDSKTBL       | JDiskPrime ($226)
        .short  Sony_RdAddr-INITDSKTBL          | JRdAddr ($22A)
        .short  Sony_RdData-INITDSKTBL          | JRdData ($22E)
        .short  Sony_WrData-INITDSKTBL          | JWrData ($232)
        .short  Sony_Seek-INITDSKTBL            | JSeek ($236)
        .short  Sony_SetUpPoll-INITDSKTBL       | JSetUpPoll ($23A)
        .short  Sony_Recal-INITDSKTBL           | JRecal ($23E)
        .short  Sony_Control-INITDSKTBL         | JControl ($242)
        .short  Sony_WakeUp-INITDSKTBL          | JWakeUp ($246)
        .short  Sony_ReSeek-INITDSKTBL          | JReSeek ($24A)
        .short  Sony_MakeSpdTbl-INITDSKTBL      | JMakeSpdTbl ($24E)

| InitParams -- tuneable drive constants, copied into SonyVars from
| ReadErrInit (+$2A) on (32 bytes; the same values as in the Plus
| driver, sonyequ.inc section "Floppy drive constants")
INITPARAMS:
        .byte   8,0                             | ReadErrInit: 8 soft errors per recal/track
        .byte   2,0                             | RecalInit: 2 recals per track
        .byte   64,0                            | WrgSectInit: 64 wrong sectors per sector
        .byte   8,0                             | BadSpdInit: 8 wrong speeds per track
        .short  0                               | Command: no I/O command
        .short  KHdSetTime                      | HeadSettle: 300 = 30 ms head settle time
        .short  KSpdChgTime                     | SpdChgTime: 1500 = 150 ms speed change
        .short  KPowerOn                        | PwrOnTime: 4000 = 400 ms power-on time
        .short  KRWPOff                         | PwrOffTime: 5 = 2-2.5 s power-off delay
        .short  KSeekTime                       | SeekTime: 120 = 12 ms track-to-track
        .short  KSectTime                       | SectTime: 100 = 10 ms sector time
        .short  KDskVBLTime                     | DskVBLTime: 30 ticks = 0.5 s VBL task period
        .short  KEjectTime                      | EjectTime: 7500 = 0.75 s eject pulse
        .long   KCkDelta                        | CkDelta: 14400 ticks = 4 min speed recheck
        .byte   KEjectWait,0                    | EjectWait: -4 VBL calls before DIP check
| ----------------------------------------------------------
| DiskOpen -- driver initialization (called once at boot, A1 = DCE):
| allocates the 250 SonyVars bytes, sets the disk routine vectors and the
| tuneable constants, gives drives 1 and 2 a drive queue element each
| (whether they are connected is found out at their first use, see
| CkInstalled) and installs the VBL task. DiskClose is the final RTS.
E_Sony_Open:
        MOVEQ.L #0x7D,D0                        | 125
        ADD.L   D0,D0                           | * 2 = 250 = $FA: SonyVars of this version
        _NewPtrSysClear                         | allocate cleared block in system heap
        MOVE.L  A0,(SonyVars).w                 | store SonyVars ptr in low memory
        MOVE.L  A0,A2                           | A2 = SonyVars
        MOVE.L  A1,(A0)                         | DiskUnitPtr: save DCE ptr at offset 0
        MOVE    dCtlRefNum(A1),D2               | D2 = driver refNum (for AddDrive)
        LEA.L   (DrvQHdr_Flags).w,A1            | A1 = drive queue header
        JSR     InitQueuePrim(PC)               | the drive queue starts empty
        MOVEQ.L #Drive1,D0                      | D0 = Drive1: offset of drive 1's variables
        LEA.L   DQEl(A2,D0.W),A0                | A0 -> drive 1's drive queue element (DQEl)
        MOVEQ.L #0x1,D0                         | drive number 1 (internal)
        BSR.B   SONY_ADD_DRIVE                  | add it to the drive queue
        ADDA.W  #DrvLclLth,A0                   | A0 -> drive 2's element (+66)
        MOVEQ.L #0x2,D0                         | drive number 2 (external)
        BSR.B   SONY_ADD_DRIVE                  | add it to the drive queue
        LEA     INITDSKTBL(PC),A0               | A0 -> InitDskTbl
        LEA.L   (DiskVars_JFigTrkSpd).w,A1      | A1 -> first jump vector (JFigTrkSpd)
        MOVEQ.L #0xB,D1                         | 12 vectors (DBF count 11)
        JSR     JmpTblInit(PC)                  | JmpTblInit: offsets -> addresses
        ST      OneToOne(A2)                    | OneToOne = $FF: interrupts stay off between sectors (AfterIO)
        LEA.L   ReadErrInit(A2),A1              | dest: ReadErrInit(A2)
        LEA     INITPARAMS(PC),A0               | source: InitParams table
        MOVEQ.L #0x20,D0                        | 32 bytes to copy
        _BlockMove                              | copy drive constants
        LEA     DiskQVE(A2),A0                  | DiskQVE(A2): VBL task control block
        MOVE    #vType,qType(A0)                | qType = vType (VBL task)
        LEA     Sony_DiskVBLTask(PC),A1         | address of VBL task routine
        MOVE.L  A1,vblAddr(A0)                  | vblAddr: set task entry point
        MOVE    #0x1E,vblCount(A0)              | vblCount = 30 ticks (0.5 s)
        _VInstall                               | install into vertical retrace queue
| DiskClose -- nothing to do (D0 = noErr from the Device Manager)
E_Sony_Close:
        RTS                                     | return
| ----------------------------------------------------------
| SONY_ADD_DRIVE -- D0 = drive number in the high word, D2 = refNum in
| the low word, then into AddDrive (whose JMP to Enqueue returns to
| DiskOpen)
SONY_ADD_DRIVE:
        SWAP    D0                              | move drvNum into high half of D0
        MOVE    D2,D0                           | D0.low = D2 = refNum (D0 = drvNum:refNum)
|
| _AddDrive ($A04E): add a drive queue element to the drive queue
| Pascal: PROCEDURE AddDrive(drvrRefNum: INTEGER; drvNum: INTEGER;
|                            qEl: DrvQElPtr);
| Entry: A0 = drive queue element, D0 = drvNum (high word) and
|        drvrRefNum (low word)
| Stores D0 at dQDrive/dQRefNum (+6/+8) and enqueues the element itself
| at the tail of the drive queue (DrvQHdr). D0 is not set to a result
| code.
AddDrive:
        MOVE.L  D0,dQDrive(A0)                  | DQE+6: store drvNum:refNum (4 bytes)
        LEA.L   (DrvQHdr_Flags).w,A1            | A1 = drive queue header
        JMP     Enqueue(PC)                     | tail-call enqueue
| ----------------------------------------------------------
| DiskDone -- complete the request: DskErr = D0 (the last result, kept
| for debugging), Active = 0, IODone (the Plus version stores only
| errors in DskErr)
Sony_DiskDone:
        MOVE    D0,(DskErr).w                   | save the last error for debugging
SONY_DISKDONE_1:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        CLR.B   Active(A1)                      | Active = 0: allow the VBL task to run
        MOVE.L  (A1),A1                         | A1 = DCE pointer (DiskUnitPtr)
        MOVE.L  (JIODone).w,-(SP)               | push the IODone vector
        RTS                                     | and jump to IODone

| ----------------------------------------------------------
| DiskControl -- jump through the JControl vector
E_Sony_Control:
        MOVE.L  (DiskVars_JControl).w,-(SP)     | push Sony_Control vector
        RTS                                     | dispatch via jtControl

| ----------------------------------------------------------
| jtControl -- control call dispatcher (JControl vector); A0 = parameter
| block. csCode 1 KillIO (immediate call: powers the drive down at once,
| cancels a pending WakeUp, returns noErr with RTE), 7 Eject, 8 set the
| tag buffer (TagBufPtr); others: controlErr.
Sony_Control:
        MOVE    csCode(A0),D0                   | D0 = csCode
        SUBQ.W  #0x1,D0                         | csCode 1 (KillIO)?
        BNE.B   SONY_CTL_OTHER                  | no ->
        MOVE    SR,-(SP)                        | save the interrupt level (for the RTE)
        ORI     #0x100,SR                       | no VIA interrupts (IPL 1)
        BSR.W   Sony_PowerDown                  | PowerDown with D0 = 0: motor off now (GetDrive: A1, A2)
        MOVE.B  #0x20,vIER(A2)                  | VIA IER: disable the timer 2 interrupt (no WakeUp)
        CLR.B   Active(A1)                      | Active = 0
        RTE                                     | restore the interrupt level, return (D0 = 0)
SONY_CTL_OTHER:
        SUBQ.W  #0x6,D0                         | csCode 7 (eject)?
        BEQ.B   SONY_CTL_EJECT                  | yes ->
        SUBQ.W  #0x1,D0                         | csCode 8 (set tag buffer)?
        BNE.B   Sony_DiskCtlErr                 | no -> controlErr
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  csParam(A0),TagBufPtr(A1)       | TagBufPtr = csParam (pointer or 0)
        BRA.B   SONY_CTL_NOERR                  | noErr
| other csCodes
Sony_DiskCtlErr:                                | unimplemented csCode
        MOVEQ.L #controlErr,D0                  | controlErr (-17): unsupported call
        BRA.B   Sony_DiskDone                   | complete the request
| ----------------------------------------------------------
| ctlEject (csCode 7) -- power the drive up, pulse LSTRB at EjectHAdr for
| EjectTime (0.75 s), then power it down at once
SONY_CTL_EJECT:
        BSR.B   Sony_CkDrvNum                   | CkDrvNum: drive number ok? (A1, D1)
        BNE.B   Sony_DiskDone                   | no -> nsDrvErr
        BSR.W   Sony_FastPower                  | FastPower: drive enabled, motor on (no wait)
        MOVEQ.L #EjectHAdr,D0                   | EjectHAdr: control address CA1 = CA0 = 1, SEL = 0, CA2 = 1: eject
        BSR.W   Sony_AdrDisk                    | AdrDisk: address it
        TST.B   ph3H(A0)                        | LSTRB high: start the eject pulse
        MOVE    EjectTime(A1),D0                | EjectTime: 0.75 s pulse
        BSR.W   E_Sony_WakeUp                   | WakeUp (A0, A1, D1 set again afterwards)
        MOVE.B  EjectWait(A1),DiskInPlace(A1,D1.W) | DiskInPlace = EjectWait ($FC): counts up to 0 in the VBL task
        TST.B   ph3L(A0)                        | LSTRB low: end of the pulse
        MOVEQ.L #0x0,D0                         | D0 = 0: immediate power-down
        BSR.W   Sony_PowerDown                  | PowerDown
SONY_CTL_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
        BRA.B   Sony_DiskDone                   | complete the request

| ----------------------------------------------------------
| DiskStatus -- only csCode 8 (drive status): the first 22 bytes of the
| drive's variables (Track .. DriveErrs) to csParam; other csCodes:
| statusErr. (Inside Macintosh II-215; Technical Note #272)
E_Sony_Status:
        MOVEQ.L #statusErr,D0                   | statusErr: assume an unsupported csCode
        CMPI    #drvStsCode,csCode(A0)          | csCode 8 (drive status)?
        BNE.W   Sony_DiskDone                   | no -> return statusErr
        BSR.B   Sony_CkDrvNum                   | CkDrvNum: check the drive number
        BNE.W   Sony_DiskDone                   | bad drive number -> return the error
        LEA.L   csParam(A0),A0                  | A0 -> csParam
        MOVEQ.L #0xB,D0                         | 11 words
        ADDA.W  D1,A1                           | A1 -> this drive's variables
E_SONY_STATUS_LOOP:
        MOVE    (A1)+,(A0)+                     | copy a word
        SUBQ.W  #0x1,D0                         | count it
        BGT.B   E_SONY_STATUS_LOOP              | until all 11 words are copied (D0 = 0 = noErr)
        BRA.W   Sony_DiskDone                   | complete the request

| ----------------------------------------------------------
| CkDrvNum -- check the drive number (ioVRefNum = 1 or 2): Active = $FF
| (keeps the VBL task out until DiskDone), Drive = drive number, D1 =
| its variables' offset (GetDrv1). EQ, D0 = 0: ok; NE: nsDrvErr.
Sony_CkDrvNum:
        MOVE.L  (SonyVars).w,A1                 | load SonyVars pointer
        ST      Active(A1)                      | Active = $FF: exclude the VBL task
        MOVE    ioVRefNum(A0),D0                | D0 = ioVRefNum = drive number
        BEQ.B   SONY_CKDRVNUM_ERR               | 0 -> nsDrvErr
        CMPI    #0x2,D0                         | > 2?
        BGT.B   SONY_CKDRVNUM_ERR               | yes -> only drives 1-2
        MOVE    D0,Drive(A1)                    | Drive = requested drive
        BSR.W   Sony_GetDrv1                    | GetDrv1: D1 = drive vars offset
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return (BEQ)
SONY_CKDRVNUM_ERR:
        MOVEQ.L #nsDrvErr,D0                    | nsDrvErr (-56): no such drive
        RTS                                     | return (BNE)

| ----------------------------------------------------------
| DiskPrime -- jump through the JDiskPrime vector
E_Sony_Prime:
        MOVE.L  (DiskVars_JDiskPrime).w,-(SP)   | push DiskPrime vector
        RTS                                     | jump to implementation

| ----------------------------------------------------------
| jtDiskPrime (JDiskPrime vector) -- read or write (A0 = parameter block):
| check the drive (connected, disk in place), clamp and recalibrate a new
| disk (Recal, MakeSpdTbl, write protection), refuse writes to a write-
| protected disk, then work through the request track by track
| (GetTrack, ReSeek).
Sony_DiskPrime:
        ORI     #0x100,SR                       | exclude VBL interrupts (IPL 1)
        MOVE    ioTrap(A0),D3                   | D3 = ioTrap ($A002 read, $A003 write)
        BTST    #0x6,(ioPosMode+1)(A0)          | read-verify mode? (ioPosMode bit 6, rdVerify)
        SNE     (DskVerify).w                   | note it in DskVerify
        BSR.B   Sony_CkDrvNum                   | CkDrvNum: check the drive number
        BNE.B   SONY_DISKPRIME_ERR_4            | bad drive: exit with nsDrvErr
        MOVE    D3,Command(A1)                  | Command = ioTrap (low byte: aRdCmd 2, aWrCmd 3)
        BSR.W   Sony_DiskSelect                 | DiskSelect: select and enable the drive
        BSR.W   SONY_CKINSTALLED                | CkInstalled: drive connected?
        BMI.B   SONY_DISKPRIME_ERR_4            | no -> noDriveErr
        MOVEQ.L #DIPAdr,D0                      | DIPAdr: disk-in-place sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when a disk is in place
        BPL.B   SONY_DISKPRIME_CONT             | disk in place ->
        CLR.B   DiskInPlace(A1,D1.W)            | DiskInPlace = 0: no disk here
        MOVEQ.L #offLinErr,D0                   | offLinErr (-65): no disk in the drive
        BRA.B   SONY_DISKPRIME_ERR_4            | return the error

| a new disk (DiskInPlace = 1): power up, recal, speed table, write protection
SONY_DISKPRIME_CONT:
        CMPI.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2: already clamped and recalibrated?
        BEQ.B   SONY_DISKPRIME_OK               | yes -> check write protection
        BSR.W   Sony_FastPower                  | FastPower: motor on (no wait)
        BSR.W   E_Sony_Recal                    | Recal: seek to track 0 (also sets the IWM mode)
        BMI.B   SONY_DISKPRIME_ERR_2            | error -> immediate power-down
        BSR.W   E_Sony_MakeSpdTbl               | MakeSpdTbl: speed codes of the zones (400K drive)
        BNE.B   SONY_DISKPRIME_ERR_2            | error -> immediate power-down
        MOVEQ.L #WrProtAdr,D0                   | WrProtAdr: write-protect sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when write-protected
        SPL.B   WriteProt(A1,D1.W)              | WriteProt = $FF for a write-protected disk
        MOVE.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2: recalibrated
        CLR.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt = 0: assume a one-sided format
| CkWrProt -- a write to a write-protected disk?
SONY_DISKPRIME_OK:
        BSR.W   Sony_CheckRead                  | CheckRead: is it a read?
        BEQ.B   SONY_DISKPRIME_SKIP             | yes -> power up and go
        MOVE    (BufTgFBkNum).w,FirstFSeq(A1)   | FirstFSeq = file block number of the first tag (TagData+8)
        TST.B   WriteProt(A1,D1.W)              | WriteProt: disk write-protected?
        BPL.B   SONY_DISKPRIME_SKIP             | no -> power up and go
        MOVEQ.L #wPrErr,D0                      | wPrErr (-44): disk is write-protected
| DskRWOff -- power down after the normal delay (exit with D0 = result)
SONY_DISKPRIME_ERR:
        MOVE    PwrOffTime(A1),D2               | D2 = normal power-off delay (PwrOffTime, 2-2.5 s)
        BRA.B   SONY_DISKPRIME_POFFEXIT         | power down with that delay
| DskImmOff -- immediate power-down (errors at the first access)
SONY_DISKPRIME_ERR_2:
        MOVEQ.L #0x0,D2                         | D2 = 0: immediate power-down
| POffExit
SONY_DISKPRIME_POFFEXIT:
        MOVE    D0,-(SP)                        | save the result code
        MOVE    D2,D0                           | D0 = power-off delay
        BSR.W   Sony_PowerDown                  | PowerDown
        MOVE    (SP)+,D0                        | restore the result code
| DiskErr -- open interrupts and complete the request
SONY_DISKPRIME_ERR_4:
        ANDI    #-0x701,SR                      | open interrupts again (IPL 0)
        BRA.W   Sony_DiskDone                   | complete the request
| RWPower -- set the speed for the current track and power up
SONY_DISKPRIME_SKIP:
        MOVE    Track(A1,D1.W),D6               | D6 = current track
        BSR.W   Sony_SetSpeed                   | SetSpeed for its zone
        BSR.W   Sony_RWPowerUp                  | RWPowerUp: power up and wait
        ST.B    0x13(A1,D1.W)                   | drive var +19 = $FF (never read here; later NewIntf)
| GetTrack -- the side/track of the next block (dCtlPosition / 512): walk
| the zones (12 down to 8 sectors per track, 16 tracks each), counting
| side 1 too when TwoSideFmt is set; then the map of the sectors wanted
| on that track (up to its end or the end of the request)
SONY_DISKPRIME_NEXT:
        MOVE.L  (A1),A2                         | A2 = DCE
        MOVE.L  dCtlQHead(A2),A0                | A0 = current request (dCtlQHead)
        MOVE.L  dCtlPosition(A2),D0             | D0 = dCtlPosition (byte position)
        LSR.L   #0x8,D0                         | / 256
        LSR.L   #0x1,D0                         | / 2: D0 = block number
        MOVEQ.L #0x0,D2                         | D2 = first block of the next track (side)
        MOVEQ.L #0x0,D3                         | D3 = track
        MOVEQ.L #0x4,D7                         | 5 zones
        MOVEQ.L #0xD,D4                         | D4 = 13: sectors per track + 1 (zone 0)
SONY_GETTRACK_ZONE:
        MOVEQ.L #0xF,D5                         | 16 tracks per zone
        SUBQ.W  #0x1,D4                         | D4 = sectors per track in this zone
SONY_GETTRACK_TRACK:
        MOVEQ.L #0x0,D6                         | D6 = 0: side 0
SONY_GETTRACK_SIDE:
        ADD     D4,D2                           | + the sectors of this side
        CMP     D0,D2                           | past the block wanted?
        BGT.B   SONY_GETTRACK_FOUND             | yes -> it is on this side/track
        TST.B   D6                              | side 1 done?
        BNE.B   SONY_GETTRACK_NEXTTRK           | yes -> next track
        MOVE.B  TwoSideFmt(A1,D1.W),D6          | D6 = TwoSideFmt: two-sided format?
        BNE.B   SONY_GETTRACK_SIDE              | yes -> count side 1 of this track
SONY_GETTRACK_NEXTTRK:
        ADDQ.W  #0x1,D3                         | next track
        DBRA    D5,SONY_GETTRACK_TRACK          | 16 tracks per zone
        DBRA    D7,SONY_GETTRACK_ZONE           | 5 zones
SONY_GETTRACK_PARAMERR:
        MOVEQ.L #paramErr,D0                    | paramErr (-50): beyond the end of the disk, or < 512 bytes
        BRA.B   SONY_DISKPRIME_ERR              | power down and return the error
SONY_GETTRACK_FOUND:
        TST.B   D6                              | on side 1?
        BEQ.B   SONY_GETTRACK_SECTORS           | no ->
        BSET    #0xB,D3                         | side bit (bit 11)
        TST.B   Sides(A1,D1.W)                  | Sides: two-sided drive?
        BNE.B   SONY_GETTRACK_SECTORS           | yes -> fine
        MOVEQ.L #twoSideErr,D0                  | twoSideErr (-78): two-sided disk in a one-sided drive
        BRA.B   SONY_DISKPRIME_ERR              | power down and return the error
SONY_GETTRACK_SECTORS:
        MOVE    D3,SideTrack(A1)                | SideTrack = side/track of the block
        SUB     D2,D0                           | D0 = -(blocks from it to the end of the track)
        ADD     D0,D4                           | D4 = its sector number
        NEG     D0                              | D0 = sectors from it to the end of the track
        MOVE    D4,FirstSect(A1)                | FirstSect = first sector wanted
        MOVE.L  ioReqCount(A0),D5               | D5 = ioReqCount
        MOVE.L  ioActCount(A0),D2               | D2 = ioActCount (bytes done so far)
        SUB.L   D2,D5                           | bytes still to transfer
        LSR.L   #0x8,D5                         | / 256
        LSR.L   #0x1,D5                         | / 2: blocks still to transfer
        BEQ.B   SONY_GETTRACK_PARAMERR          | none (< 512 bytes) -> paramErr
        CMP     D5,D0                           | more on this track than needed?
        BLE.B   SONY_GETTRACK_MAP               | no ->
        MOVE    D5,D0                           | D0 = sectors to do on this track
SONY_GETTRACK_MAP:
        MOVEQ.L #0x0,D3                         | D3 = sector map
SONY_GETTRACK_MAPLOOP:
        BSET    D4,D3                           | sector D4 wanted
        ADDQ.W  #0x1,D4                         | next sector
        SUBQ.W  #0x1,D0                         | count it
        BNE.B   SONY_GETTRACK_MAPLOOP           | all of them
        MOVE.L  D3,SectMap(A1)                  | SectMap = sectors wanted on this track
        MOVE.L  ioBuffer(A0),D3                 | D3 = ioBuffer
        ADD.L   D2,D3                           | + ioActCount
        MOVE.L  D3,DiskBuffer(A1)               | DiskBuffer = buffer address of FirstSect
        LSR.L   #0x8,D2                         | / 256
        LSR.L   #0x1,D2                         | / 2 = blocks done
        MOVE    D2,FBlksDone(A1)                | FBlksDone = blocks done before this track
        MOVE.B  RecalInit(A1),RecalCnt(A1)      | RecalCnt = RecalInit
| ReSeek -- jump through the JReSeek vector
E_Sony_ReSeek:
        MOVE.L  (DiskVars_JReSeek).w,-(SP)      | push the JReSeek vector
        RTS                                     | and jump through it
| ----------------------------------------------------------
| jtReSeek (JReSeek vector) -- seek to SideTrack, recheck the zone's speed
| after CkDelta, then OnTrack: read address fields until the wanted
| sectors are done
Sony_ReSeek:
        MOVE.B  BadSpdInit(A1),BadSpdCnt(A1)    | BadSpdCnt = BadSpdInit: speed adjustments allowed
SONY_RESEEK_RETRY:
        MOVE    SideTrack(A1),D6                | D6 = side/track wanted
        BSR.W   E_Sony_Seek                     | Seek (sets the zone's speed)
        BMI.B   SONY_RESEEK_ERR                 | error -> recal
        MOVE.B  ReadErrInit(A1),ReadErrCnt(A1)  | ReadErrCnt = ReadErrInit: soft errors tolerated
        LSR     #0x4,D6                         | D6 = zone (16 tracks per zone)
        LSL     #0x3,D6                         | * 8 = offset of the zone entry
        LEA.L   TrkSpeedTbl(A1,D1.W),A2         | A2 -> TrkSpeedTbl in the drive vars (+$1A)
        LEA.L   TSTblTicks(A2,D6.W),A2          | A2 -> TSTblTicks: time of the last check of this zone
        MOVE.L  (Ticks).w,D2                    | D2 = Ticks
        MOVE.L  (A2),D0                         | last check
        BEQ.B   SONY_RESEEK_CONT                | never checked -> check now
        SUB.L   D2,D0                           | last - now
        NEG.L   D0                              | = ticks since the last check
        CMP.L   CkDelta(A1),D0                  | CkDelta (4 min): time for a recheck?
        BLT.B   SONY_RESEEK_SKIP                | no -> on to the sectors
SONY_RESEEK_CONT:
        MOVE.L  D2,(A2)                         | remember the time of this check
        LEA     SONY_RESEEK_CONT_2(PC),A3       | A3 = return address for the measurement
        BRA.W   SONY_GETFREQ1                   | GetFreq1: measure the speed value (D4)
| back from GetFreq1 (D4 = speed value): within SpeedCheckTbl's limits?
SONY_RESEEK_CONT_2:
        BMI.B   SONY_RESEEK_ERR                 | measurement failed -> recal
        MOVE    -(A2),D0                        | D0 = TSTblDelta: speed code change for 2% speed
        LEA     DT_Sony_SpeedCheckTbl(PC),A0    | A0 -> speed limits table
        LSR     #0x1,D6                         | zone * 4
        ADDA.W  D6,A0                           | A0 -> limits for this zone
        CMP     (A0)+,D4                        | too fast (speed value above the upper limit)?
        BGT.B   SONY_RESEEK_ADJUST              | yes -> lower the speed code by the delta
        NEG     D0                              | else D0 = -delta
        CMP     (A0),D4                         | too slow (at or below the lower limit)?
        BGT.B   SONY_RESEEK_SKIP                | no -> speed is fine
SONY_RESEEK_ADJUST:
        SUB     D0,-(A2)                        | TSTblCode -= delta (too fast) or += delta (too slow)
        CLR.L   TSTblTicks(A2)                  | force a recheck next time
        ADDQ.W  #0x1,SpdAdjCnt(A1,D1.W)         | SpdAdjCnt: count speed adjustments
        SUBQ.B  #0x1,BadSpdCnt(A1)              | BadSpdCnt: adjustments left?
        BPL.B   SONY_RESEEK_RETRY               | yes -> seek (sets the new speed) and check again
        MOVEQ.L #spdAdjErr,D0                   | spdAdjErr (-79): speed cannot be adjusted
SONY_RESEEK_ERR:
        BRA.W   SONY_RESEEK_ERR_6               | DoRecal: recal or give up

| OnTrack -- read address fields until all wanted sectors of the track
| (SectMap) are done: wrong track -> seekErr, recal; unwanted sector ->
| WrgSectCnt; read/write errors -> ReadErrCnt (soft errors), recal.
| Interrupts are off from RdAddrSetup until AfterIO (OneToOne).
SONY_RESEEK_SKIP:
        MOVE.B  WrgSectInit(A1),WrgSectCnt(A1)  | WrgSectCnt = WrgSectInit: wrong sectors tolerated
SONY_RESEEK_RETRY_2:
        MOVE.L  D1,D6                           | D6 = drive offset (RdAddr returns D1 = side/track)
        BSR.W   Sony_RdAddrSetup                | RdAddrSetup: next address field (D1, D2 = sector, D3 = format)
        BPL.B   SONY_RESEEK_GOTADR              | ok ->
| RdAddr error: EmptyPD, then SoftErr
SONY_RESEEK_RDERR:
        PEA.L   SONY_RESEEK_SOFTERR(PC)         | continue at SoftErr
        BRA.B   SONY_RESEEK_TOEMPTYPD           | after EmptyPD
| on the right track?
SONY_RESEEK_GOTADR:
        CMP     SideTrack(A1),D1                | side/track of the field = SideTrack?
        BEQ.B   SONY_RESEEK_ONTRACK             | yes ->
        MOVEQ.L #seekErr,D0                     | seekErr (-80): wrong track
        PEA.L   SONY_RESEEK_ERR_6(PC)           | continue at DoRecal
SONY_RESEEK_TOEMPTYPD:
        BRA.W   Sony_EmptyPD                    | EmptyPD first
| a sector we want?
SONY_RESEEK_ONTRACK:
        MOVE.L  SectMap(A1),D0                  | D0 = SectMap: sectors still wanted
        BTST    D2,D0                           | this one?
        BNE.B   SONY_RESEEK_GOTSECT             | yes -> GotSect
        ADDQ.L  #0x1,(RndSeed).w                | RndSeed + 1 (each unwanted sector stirs the random seed)
        MOVEQ.L #sectNFErr,D0                   | sectNFErr (-81) if they run out
        PEA.L   SONY_RESEEK_WRGSECT(PC)         | continue at WrgSect
        BRA.B   SONY_RESEEK_TOEMPTYPD           | after EmptyPD
| GotSect -- the buffer address and tag offset of the sector, then read or write it
SONY_RESEEK_GOTSECT:
        MOVE    D2,(TagData).w                  | TagData = sector number (for AfterIO)
        CMPI.B  #0x1F,D3                        | format byte > $1F (bit 5, $20, set): two-sided format
        SGT.B   TwoSideFmt(A1,D6.W)             | TwoSideFmt (drive var +$12) = $FF for two-sided
        SUB.W   FirstSect(A1),D2                | - FirstSect = relative sector number
        MOVE    D2,D1                           | D1 = relative sector number
        ASL.L   #0x8,D1                         | * 256
        ADD.L   D1,D1                           | * 512
        ADD.L   DiskBuffer(A1),D1               | + DiskBuffer
        MOVE.L  D1,A0                           | A0 -> data buffer for this sector
        MOVE    FBlksDone(A1),D1                | blocks done before this track
        ADD     D2,D1                           | + relative sector = relative block number
        MOVE    D1,D0                           | (keep it for writes)
        ADD     D1,D1                           | * 2
        ADD     D0,D1                           | * 3
        ASL     #0x2,D1                         | * 12 = offset in the tag buffer
        MOVE    D1,TagBufOS(A1)                 | TagBufOS: kept for a read
        BSR.W   Sony_CheckRead                  | CheckRead: read?
        BEQ.B   SONY_RESEEK_OTREAD              | yes -> OTRead
        MOVE.L  TagBufPtr(A1),D3                | TagBufPtr: separate tag buffer?
        BEQ.B   SONY_RESEEK_FILETAG             | no -> file block number tag only
| OTWrite with a tag buffer: its 12 bytes for this block to TagData+2
SONY_RESEEK_WRTAGS:
        MOVE.L  D3,A1                           | A1 = tag buffer
        ADDA.W  D1,A1                           | A1 -> tags of this block
        LEA.L     (BufTgFNum).w,A2              | A2 -> TagData+2
        MOVE.L  (A1)+,(A2)+                     | copy its 12 tag bytes
        MOVE.L  (A1)+,(A2)+                     | tag bytes 5-8
        MOVE.L  (A1)+,(A2)+                     | tag bytes 9-12
        BRA.B   SONY_RESEEK_OTWRITE             | write the sector
| no tag buffer: the file block number and the date
SONY_RESEEK_FILETAG:
        ADD     FirstFSeq(A1),D0                | + FirstFSeq = file block number
        MOVE    D0,(BufTgFBkNum).w              | TagData+8 = file block number
        MOVE.L  (Time).w,(BufTgDate).w          | date tag = Time (this driver sets it)
| OTWrite
SONY_RESEEK_OTWRITE:
        BSR.W   E_Sony_WrData                   | WrData: write the data field
        BNE.W   SONY_RESEEK_RDERR               | error -> EmptyPD, SoftErr
        BRA.B   SONY_RESEEK_SECTDONE            | ok -> AfterIO
| OTRead
SONY_RESEEK_OTREAD:
        BSR.W   E_Sony_RdData                   | RdData: read the data field
        BNE.W   SONY_RESEEK_RDERR               | error -> EmptyPD, SoftErr
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  TagBufPtr(A1),D0                | TagBufPtr: separate tag buffer?
        BEQ.B   SONY_RESEEK_SECTDONE            | no -> done
        MOVE.L  D0,A0                           | A0 = tag buffer
        ADDA.W  TagBufOS(A1),A0                 | + TagBufOS
        LEA.L     (BufTgFNum).w,A2              | A2 -> TagData+2: tags just read
        MOVE.L  (A2)+,(A0)+                     | copy the 12 tag bytes
        MOVE.L  (A2)+,(A0)+                     | tag bytes 5-8
        MOVE.L  (A2)+,(A0)+                     | tag bytes 9-12
SONY_RESEEK_SECTDONE:
        PEA.L   SONY_RESEEK_AFTERIO(PC)         | continue at AfterIO after EmptyPD

| EmptyPD -- pass the SCC bytes that the polling code pushed on the stack
| (poll data) to PollProc (the serial driver), or discard them, and
| return with the stack reset (PollStack); preserves D0, D2-D3, A0
Sony_EmptyPD:
        MOVE.L  (SP)+,A4                        | A4 = return address
        PEA.L   SONY_EMPTYPD_RESUME(PC)         | PollProc returns to SONY_EMPTYPD_RESUME
        MOVE.L  (PollProc).w,-(SP)              | PollProc installed?
        BEQ.B   SONY_EMPTYPD_NOPROC             | no -> throw the data away
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVEM.L D0/D2-D3/A0/A4,SaveRegs(A1)     | save D0, D2, D3, A0 and the return address
        RTS                                     | go to PollProc
SONY_EMPTYPD_RESUME:
        BSR.W   Sony_GetDrv1                    | GetDrv1
        MOVEM.L SaveRegs(A1),D0/D2-D3/A0/A4     | restore the registers
        JMP     (A4)                            | return
SONY_EMPTYPD_NOPROC:
        MOVE.L  (PollStack).w,SP                | reset the stack (discard poll data)
        BSR.W   Sony_GetDrv1                    | GetDrv1
        JMP     (A4)                            | return
| CheckRead -- EQ for a read (low byte of Command = aRdCmd)
Sony_CheckRead:
        CMPI.B  #aRdCmd,(Command+1)(A1)         | low byte of Command: aRdCmd (read)?
        RTS                                     | return
| AfterIO -- a sector is done: open interrupts unless OneToOne; after a
| write wait SectTime (10 ms) unless DskWr11 ("try 1-1 disk writes"); count
| it (dCtlPosition, ioActCount), clear it from SectMap; next sector,
| next track (GetTrack) or done
SONY_RESEEK_AFTERIO:
        TST.B   OneToOne(A1)                    | OneToOne (set by DiskOpen)?
        BNE.B   SONY_RESEEK_CKWRITE             | yes -> interrupts stay off
        ANDI    #-0x701,SR                      | else open them
SONY_RESEEK_CKWRITE:
        BSR.B   Sony_CheckRead                  | CheckRead: a read?
        BEQ.B   SONY_RESEEK_COUNT               | yes ->
        TST.B   (CPUFlag).w                     | DskWr11 ($12F; later CPUFlag): 1:1 writes?
        BNE.B   SONY_RESEEK_COUNT               | yes -> no wait
        BSR.W   SONY_WAITSECT                   | WaitSect: WakeUp for SectTime (interrupts open meanwhile)
SONY_RESEEK_COUNT:
        MOVE.L  (A1),A2                         | A2 = DCE
        MOVE.L  dCtlQHead(A2),A0                | A0 = the request
        MOVEQ.L #0x2,D0                         | 2
        ASL.L   #0x8,D0                         | * 256 = 512 bytes
        ADD.L   D0,dCtlPosition(A2)             | dCtlPosition + 512
        ADD.L   D0,ioActCount(A0)               | ioActCount + 512
        MOVE.L  SectMap(A1),D0                  | D0 = SectMap
        MOVE    (TagData).w,D2                  | D2 = the sector just done
        BCLR    D2,D0                           | no longer wanted
        MOVE.L  D0,SectMap(A1)                  | SectMap
        BNE.W   SONY_RESEEK_SKIP                | more on this track -> OnTrack
        MOVE.L  ioActCount(A0),D0               | D0 = ioActCount
        CMP.L   ioReqCount(A0),D0               | all done?
        BLT.W   SONY_DISKPRIME_NEXT             | no -> GetTrack: next track
        MOVEQ.L #0x0,D0                         | noErr
SONY_RESEEK_ERR_3:
        BRA.W   SONY_DISKPRIME_ERR              | DskRWOff: power down after the normal delay
| ----------------------------------------------------------
| SoftErr -- a read or write error: count it (DriveErrs), retry while
| ReadErrCnt lasts, then DoRecal
SONY_RESEEK_SOFTERR:
        ADDQ.W  #0x1,DriveErrs(A1,D1.W)         | DriveErrs (drive var +$14): drive soft error count
        SUBQ.B  #0x1,ReadErrCnt(A1)             | ReadErrCnt: errors left?
        BPL.W   SONY_RESEEK_SKIP                | yes -> OnTrack again

| DoRecal -- recal (while RecalCnt lasts), new speed table, seek again
SONY_RESEEK_ERR_6:
        ANDI    #-0x701,SR                      | open interrupts
        SUBQ.B  #0x1,RecalCnt(A1)               | RecalCnt: recal done already?
        BLE.B   SONY_RESEEK_ERR_7               | yes -> give up
        BSR.W   E_Sony_Recal                    | Recal
        BMI.B   SONY_RESEEK_ERR_7               | error -> give up
        BSR.W   E_Sony_MakeSpdTbl               | MakeSpdTbl
        BPL.W   E_Sony_ReSeek                   | ok -> ReSeek
SONY_RESEEK_ERR_7:
        BRA.B   SONY_RESEEK_ERR_3               | give up: return D0
| WrgSect -- an unwanted sector: wait SectTime and look again, while
| WrgSectCnt lasts (then DoRecal)
SONY_RESEEK_WRGSECT:
        SUBQ.B  #0x1,WrgSectCnt(A1)             | WrgSectCnt: wrong sectors left?
        BMI.B   SONY_RESEEK_ERR_6               | no -> DoRecal
        BSR.W   SONY_WAITSECT                   | WaitSect: WakeUp for SectTime
        BRA.W   SONY_RESEEK_RETRY_2             | OnTrack again
| GetDrive -- A0 = IWM, A2 = VIA, then GetDrv1: A1 = SonyVars, D1 =
| offset of the current drive's variables (Drive1 or Drive2)
Sony_GetDrive:
        MOVE.L  (IWM).w,A0                      | GetDrive: A0 = IWM base ($DFE1FF)
        MOVE.L  (VIA).w,A2                      | A2 = VIA base ($EFE1FE)
Sony_GetDrv1:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        CMPI    #0x1,Drive(A1)                  | Drive = 1 (internal)?
        BEQ.B   SONY_GETDRV1_INT                | yes ->
        MOVE    #Drive2,D1                      | D1 = Drive2 ($8C): external drive
        RTS                                     | return
SONY_GETDRV1_INT:
        MOVEQ.L #Drive1,D1                      | D1 = Drive1 ($4A): internal drive
        RTS                                     | return

| AdrDisk -- address drive register D0 (CA1-CA0-SEL-CA2 in bits 3-0):
| CA0, CA1 high and CA2 low first, then CA2, SEL (VIA port A bit 5),
| CA0 and CA1 as given. GetDrive first (A0 = IWM, A2 = VIA, A1, D1).
Sony_AdrDisk:
        BSR.B   Sony_GetDrive                   | GetDrive: A0 = IWM, A2 = VIA, A1, D1
        TST.B   ph0H(A0)                        | CA0 high
        TST.B   ph1H(A0)                        | CA1 high
        TST.B   ph2L(A0)                        | CA2 low
        LSR.B   #0x1,D0                         | bit 0: CA2
        BCC.B   SONY_ADRDISK_SEL                | 0 -> leave it low
        TST.B   ph2H(A0)                        | CA2 high
SONY_ADRDISK_SEL:
        BCLR    #vHeadSel,vBufA(A2)             | SEL low (VIA port A bit 5)
        LSR.B   #0x1,D0                         | bit 1: SEL
        BCC.B   SONY_ADRDISK_CA0                | 0 -> leave it low
        BSET    #vHeadSel,vBufA(A2)             | SEL high
SONY_ADRDISK_CA0:
        LSR.B   #0x1,D0                         | bit 2: CA0
        BCS.B   SONY_ADRDISK_CA1                | 1 -> leave it high
        TST.B   (A0)                            | ph0L: CA0 low
SONY_ADRDISK_CA1:
        LSR.B   #0x1,D0                         | bit 3: CA1
        BCS.B   SONY_ADRDISK_DONE               | 1 -> leave it high
        TST.B   ph1L(A0)                        | CA1 low
SONY_ADRDISK_DONE:
        RTS                                     | return
| AdrAndSense -- AdrDisk, then Sense
Sony_AdrAndSense:
        BSR.B   Sony_AdrDisk                    | address the register
| Sense -- read the addressed sense line: N = 1 for a high level (IWM
| status bit 7), interrupts off meanwhile
Sony_Sense:
        MOVE    SR,-(SP)                        | Sense: save the interrupt level
        ORI     #0x300,SR                       | no interrupts
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVE.B  q7L(A0),D0                      | Q7L (L7 = 0): read the status register (bit 7 = SENSE)
        TST.B   q6L(A0)                         | Q6L: L6 = 0, back to read mode (data register)
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST.B   D0                              | N = sense line
        RTS                                     | return
| AdrAndStrb -- AdrDisk, then Pulse
Sony_AdrAndStrb:
        BSR.B   Sony_AdrDisk                    | address the register
| Pulse -- strobe LSTRB: the drive sets the addressed control register
| to CA2 (interrupts off meanwhile)
Sony_Pulse:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | no interrupts
        TST.B   ph3H(A0)                        | LSTRB high
        TST.B   ph3L(A0)                        | LSTRB low
        RTE                                     | restore the interrupt level and return
| -------------------------------------------------------------------------
| SetSpeed -- set the speed for track D6: the zone's speed code
| (TrkSpeedTbl) plus the drive's OffSpeed, clamped to [0, $18F]; adds
| the time the change takes to Wait and programs the PWM bytes of the
| sound buffers (SONY_SETSPEED_CONT_3)
Sony_SetSpeed:
        BSR.B   Sony_GetDrv1                    | GetDrv1: A1, D1
        MOVE    D6,D2                           | D2 = target track
        LSR     #0x4,D2                         | zone index (track / 16)
        LSL     #0x3,D2                         | zone * 8 (table stride)
        ADD     D1,D2                           | per-drive zone table offset
        MOVE    TrkSpeedTbl(A1,D2.W),D2         | D2 = TSTblCode: speed code of the zone
        ADD     0x16(A1,D1.W),D2                | + OffSpeed (drive var +22; MPW 1.0: "old OffSpeed")
        BPL.B   SONY_SETSPEED_OK                | not negative ->
        MOVEQ.L #0x0,D2                         | else 0
SONY_SETSPEED_OK:
        CMPI    #0x18F,D2                       | above $18F, the highest code here?
        BLE.B   SONY_SETSPEED_OK_2              | no ->
        MOVE    #0x18F,D2                       | clamp to $18F
SONY_SETSPEED_OK_2:
        MOVE    (PWMValue).w,D0                 | D0 = current speed code
        BPL.B   SONY_SETSPEED_CONT              | valid -> delay from the size of the change
        MOVE    PwrOnTime(A1),D0                | none yet (PWMValue = $FFFF from boot): power-on time
        BRA.B   SONY_SETSPEED_NO_2              | ->
| delay = |change| * 32 * 100 us, at least SpdChgTime (150 ms)
SONY_SETSPEED_CONT:
        SUB     D2,D0                           | D0 = old - new code
        BEQ.W   Sony_GetDrv1                    | no change -> return
        BPL.B   SONY_SETSPEED_CONT_2            | ->
        NEG     D0                              | |change|
SONY_SETSPEED_CONT_2:
        LSL     #0x5,D0                         | * 32 (100-us units)
        CMP     SpdChgTime(A1),D0               | more than SpdChgTime?
        BGT.B   SONY_SETSPEED_NO_2              | yes -> keep it
        MOVE    SpdChgTime(A1),D0               | else SpdChgTime
SONY_SETSPEED_NO_2:
        ADD     Wait(A1),D0                     | + Wait still pending
        CMP     PwrOnTime(A1),D0                | at most PwrOnTime (400 ms)
        BLT.B   SONY_SETSPEED_NO_3              | ->
        MOVE    PwrOnTime(A1),D0                | clamp
SONY_SETSPEED_NO_3:
        MOVE    D0,Wait(A1)                     | Wait = time to wait for the speed change (SeekEnd)
| SONY_SETSPEED_CONT_3 -- store the speed code D2 in PWMValue and fill
| the 370 PWM bytes (the low bytes of the sound buffer words) of the main
| buffer ($7FD01) and of the buffer at PWMBuf2 with states of a 6-bit
| shift register: q = ($18F - code) / 10 steps from $0B give two states,
| and of each 10 bytes r (the remainder) get the later one (the Plus
| driver: codes up to $1B8, start state $1E; see its notes). Also called
| by GetFreq with a given code.
SONY_SETSPEED_CONT_3:
        MOVE    D2,(PWMValue).w                 | PWMValue = new speed code
        MOVEM.L D3-D6/A2,-(SP)                  | save registers
        SUBI    #0x18F,D2                       | code - $18F
        NEG     D2                              | D2 = $18F - code (0-399)
        EXT.L    D2                             | (high word 0 for DIVU)
        DIVU    #0xA,D2                         | D2.w = q = / 10, D2.hi = r = remainder
        MOVEQ.L #0xB,D0                         | D0 = $0B: start state
SONY_SETSPEED_LFSR:
        MOVE.B  D0,D1                           | D1 = state before this step
        MOVE.B  D0,D3                           | D3 = feedback calculation
        LSR.B   #0x1,D0                         | shift right
        EOR.B   D0,D3                           | bit 0 = old bit 0 XOR old bit 1
        LSR.B   #0x1,D3                         | into the carry
        BCC.B   SONY_SETSPEED_SKIP              | 0 ->
        BSET    #0x5,D0                         | 1 -> into bit 5
SONY_SETSPEED_SKIP:
        DBRA    D2,SONY_SETSPEED_LFSR           | q + 1 steps: D1 = state q, D0 = state q + 1
        SWAP    D2                              | D2 = r (0-9)
        MOVE.B  SONY_SETSPEED_PATTERNS(PC,D2.W),D5 | D5 = pattern word for r: table bytes r and r + 1
        ASL     #0x8,D5                         | (high byte)
        MOVE.B  SONY_SETSPEED_PATTERNS1(PC,D2.W),D5 | (low byte)
        MOVEQ.L #0x24,D3                        | 37 groups of 10 bytes = 370
        LEA.L   (0x7FD01).l,A0                  | A0 = PWM bytes of the main sound buffer ($7FD00: also the 128K's $1FD00)
        MOVE.L  (PWMBuf2).w,A2                  | A2 = PWMBuf2 (MPW SysEqu.a: "PWM buffer 1 (or 2 if sound)")
SONY_SETSPEED_LOOP_2:
        MOVEQ.L #0x9,D2                         | 10 bytes per group
        MOVE    D5,D4                           | D4 = pattern: r one bits in bits 15-6
SONY_SETSPEED_LOOP_3:
        LSL     #0x1,D4                         | next pattern bit
        BCC.B   SONY_SETSPEED_CONT_4            | 0 -> state q
        MOVE.B  D0,D6                           | 1 -> state q + 1
        BRA.B   SONY_SETSPEED_CONT_5            | ->
| pattern bit 0: the earlier state
SONY_SETSPEED_CONT_4:
        MOVE.B  D1,D6                           | state q
SONY_SETSPEED_CONT_5:
        MOVE.B  D6,(A0)                         | PWM byte of buffer 1
        MOVE.B  D6,(A2)                         | PWM byte of buffer 2
        ADDQ.W  #0x2,A0                         | next PWM byte (every second byte)
        ADDQ.W  #0x2,A2                         | next PWM byte
        DBRA    D2,SONY_SETSPEED_LOOP_3         | 10 bytes of the group
        DBRA    D3,SONY_SETSPEED_LOOP_2         | 37 groups = 370 bytes
        MOVEM.L (SP)+,D3-D6/A2                  | restore registers
        BRA.W   Sony_GetDrv1                    | GetDrv1 and return

| Pattern words, read at byte offset r (0-9) as (byte r, byte r + 1): the
| top 10 bits hold r one bits, spread out (r = 1: $2021, 5: $AAB5, 9: $FF40)
SONY_SETSPEED_PATTERNS:
        .byte   0x00                            | byte 0
SONY_SETSPEED_PATTERNS1:
        .byte   0x20, 0x21, 0x24, 0x94          | bytes 1-4
        .byte   0xAA, 0xB5, 0xB7, 0x7B          | bytes 5-8
        .byte   0xFF, 0x40, 0x00                | bytes 9-11 (r = 9 uses bytes 9, 10)
| -------------------------------------------------------------------------
| Seek -- seek to track D6 (bit 11, the side, is cleared); D0 (out) =
| track or a negative error. Sets the zone's speed first. Returns to one
| level above the caller while waiting (A6 = return address).
E_Sony_Seek:
        BCLR    #0xB,D6                         | clear the side bit
        BSR.W   Sony_SetSpeed                   | SetSpeed for the target zone
        MOVE.L  (DiskVars_JSeek).w,-(SP)        | Seek1: push the JSeek vector
        RTS                                     | and jump through it
| jtSeek (JSeek vector): one step at a time, each with its direction set
| and the /STEP handshake checked; an unknown track (negative Track)
| means a recal first.
Sony_Seek:
        MOVE.L  (SP)+,A6                        | A6 = return address
        BSR.W   Sony_GetDrv1                    | GetDrv1
        MOVE    Track(A1,D1.W),D7               | D7 = current track
        BPL.B   SEEK_2                          | known ->
        BSR.W   E_Sony_Recal                    | Recal
        MOVE    D0,D7                           | D7 = result (track 0 or error)
| --- ROM-variant difference @ $1CA6 ---
| MAC_128K: BNE.B SONY_SEEK_RET ($66 $4E): after a recal return only if
|           it failed, else step from track 0 on to the target
| MAC_512K: BRA.B SONY_SEEKEND ($60 $36): end the seek at track 0
| Reason: (branch after the recal of an unknown track) the 512K seek
| returns at once (Track = 0 or the error); ReSeek's address check then
| fails (seekErr): DoRecal recalibrates again, MakeSpdTbl, then seeks from
| track 0. Apple's reason for the change is not documented.
.if ROM_TARGET == MAC_128K
        BNE.B   SONY_SEEK_RET                   | 128K: Recal failed -> return the error
.else
        BRA.B   SONY_SEEKEND                    | 512K: SeekEnd (Track = D7)
.endif
SEEK_2:
        CMP     D6,D7                           | already on the target track?
        BEQ.B   SONY_SEEKEND_WAIT               | yes -> just wait out any speed change

| step towards the target: direction, then /STEP handshake and pulse
SONY_SEEK_CONT:
        MOVEQ.L #DirLAdr,D0                     | DirLAdr: step in (toward higher tracks)
        MOVEQ.L #0x1,D1                         | D1 = +1
        MOVE    D7,D2                           | current track
        SUB     D6,D2                           | - target track
        BEQ.B   SONY_SEEKEND                    | there -> SeekEnd
        BMI.B   SONY_SEEK_CONT_2                | below the target -> step in
        MOVEQ.L #DirHAdr,D0                     | DirHAdr: step out (toward track 0)
        MOVEQ.L #-0x1,D1                        | D1 = -1
SONY_SEEK_CONT_2:
        ADD     D1,D7                           | next track number
        BSR.W   Sony_AdrAndStrb                 | set the step direction (restores D1 = drive vars offset)
        MOVE    D7,Track(A1,D1.W)               | Track = new track
        MOVEQ.L #StepLAdr,D0                    | StepLAdr: /STEP sense
        BSR.W   Sony_AdrAndSense                | /STEP high (1) = no step in progress
        BMI.B   SONY_SEEK_CONT_3                | ready -> step
        MOVEQ.L #cantStepErr,D7                 | cantStepErr (-75): drive will not step
        BRA.B   SONY_SEEKEND                    | store it as the track
SONY_SEEK_CONT_3:
        BSR.W   Sony_Pulse                      | LSTRB pulse at StepLAdr (CA2 = 0): step, /STEP goes low
        MOVE    SeekTime(A1),D0                 | SeekTime: 12 ms per step
        BSR.B   E_Sony_WakeUp                   | WakeUp: wait for the step
        BRA.B   SONY_SEEK_CONT                  | next step
| SeekEnd -- Track = D7, wait HeadSettle and any speed change (Wait)
SONY_SEEKEND:
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1
        MOVE    D7,Track(A1,D1.W)               | Track = result
        MOVE    HeadSettle(A1),D0               | HeadSettle: 30 ms head settle time
        BSR.B   E_Sony_WakeUp                   | WakeUp
SONY_SEEKEND_WAIT:
        MOVE    Wait(A1),D0                     | D0 = Wait: speed change time still to wait
        BEQ.B   SONY_SEEKEND_RET                | none ->
        BSR.B   E_Sony_WakeUp                   | WakeUp
SONY_SEEKEND_RET:
        MOVE    D7,D0                           | D0 = track or error
SONY_SEEK_RET:
        JMP     (A6)                            | return
| WaitSect -- WakeUp for SectTime (10 ms)
SONY_WAITSECT:
        MOVE    SectTime(A1),D0                 | D0 = SectTime
| WakeUp -- jump through the JWakeUp vector
E_Sony_WakeUp:
        MOVE.L  (DiskVars_JWakeUp).w,-(SP)      | push the JWakeUp vector
        RTS                                     | and jump through it
| -------------------------------------------------------------------------
| jtWakeUp -- wait D0 * 100 us, then continue at the caller's return
| address; meanwhile the caller's caller gets control with D0 = 0. VIA
| timer 2 counts D0 * 78 (TicksPr100) cycles: the low word in one go,
| then WakeTimeCnt more runs of about 65280 cycles; its interrupt
| (Lvl1DT entry 5) then restores D3-D7/A3-A6 (SaveRegs) and calls the
| continuation (DskRtn) with A0, A1, A2, D1 set by GetDrive. Wait is
| reduced by D0.
Sony_WakeUp:
        BSR.W   Sony_GetDrive                   | GetDrive: A0 = IWM, A2 = VIA, A1, D1
        MOVE.L  (SP)+,(DskRtnAdr).w             | DskRtnAdr = continuation (our caller)
        ORI     #0x100,SR                       | no VIA interrupts
        SUB     D0,Wait(A1)                     | Wait -= D0
        BGT.B   SONY_WAKEUP_T2                  | still positive ->
        CLR     Wait(A1)                        | pin it at 0
SONY_WAKEUP_T2:
        MOVEQ.L #TicksPr100,D1                  | 78 timer cycles per 100 us (783.36 kHz)
        MULU    D0,D1                           | D1 = D0 * 78
        BCLR    #0x5,vACR(A2)                   | ACR bit 5 = 0: timer 2 in one-shot (timed interrupt) mode
        LEA     SONY_WAKEUP_T2INT(PC),A0        | timer 2 interrupt routine
        MOVE.L  A0,(Lvl1DT_5).w                 | into Lvl1DT entry 5 (VIA timer 2)
        MOVE.B  D1,vT2C(A2)                     | timer 2 low byte (latch)
        ROR     #0x8,D1                         | high byte
        MOVE.B  D1,vT2CH(A2)                    | timer 2 high byte: starts it
        MOVE.B  #0xA0,vIER(A2)                  | VIA IER: enable the timer 2 interrupt
        SWAP    D1                              | D1 = high word of the count
        MOVE    D1,WakeTimeCnt(A1)              | WakeTimeCnt = further runs of the timer
        MOVEQ.L #0x0,D0                         | D0 = 0: noErr for the caller's caller
        MOVEM.L D3-D7/A3-A6,SaveRegs(A1)        | save the caller's registers in SaveRegs
        ANDI    #-0x701,SR                      | open VIA interrupts
        RTS                                     | return to the caller's caller
| timer 2 interrupt (A1 = VIA): rerun the timer or resume the continuation
SONY_WAKEUP_T2INT:
        MOVE.B  vT2CH(A1),vT2CH(A1)             | rewrite timer 2's high byte ($FF): another run, flag cleared
        BSR.W   Sony_GetDrive                   | GetDrive: A0 = IWM, A1 = SonyVars, A2 = VIA, D1
        SUBQ.W  #0x1,WakeTimeCnt(A1)            | WakeTimeCnt: more runs?
        BMI.B   SONY_WAKEUP_GO                  | no -> resume
        RTS                                     | yes -> return from the interrupt
SONY_WAKEUP_GO:
        MOVE.B  #0x20,vIER(A2)                  | VIA IER: disable the timer 2 interrupt
        MOVEM.L D4-D7/A4-A6,-(SP)               | save registers the interrupt handler does not
        MOVEM.L SaveRegs(A1),D3-D7/A3-A6        | the registers saved by WakeUp
        PEA.L   SONY_WAKEUP_DONE(PC)            | return here afterwards
        BRA.W   SONY_DSKRTN                     | DskRtn: call the continuation (DskRtnAdr)
SONY_WAKEUP_DONE:
        MOVEM.L (SP)+,D4-D7/A4-A6               | restore registers
        RTS                                     | return from the interrupt
| Recal -- jump through the JRecal vector
E_Sony_Recal:
        MOVE.L  (DiskVars_JRecal).w,-(SP)       | Recal: push the JRecal vector
        RTS                                     | and jump through it
| -------------------------------------------------------------------------
| jtRecal (JRecal vector) -- set the IWM mode if needed (SetIWMMode),
| power up, step out to track 0: Track = 0 or the error. Returns one
| level above the caller while waiting (A5 = return address).
Sony_Recal:
        MOVE.L  (SP)+,A5                        | A5 = return address
        BSR.W   Sony_GetDrive                   | GetDrive
| --- ROM-variant difference @ $1D8A ---
| MAC_128K: MOVEQ.L #$1F,D1: the IWM is ready if status bits 0-4 (mode) = $1F
| MAC_512K: MOVEQ.L #$3F,D1: and a drive enable is active (status bit 5)
| Reason: the 512K also sets the mode and powers the drive up again
|         (SetIWMMode, RWPowerUp) when no drive is enabled
.if ROM_TARGET == MAC_128K
        MOVEQ.L #0x1F,D1                        | 128K: status bits 0-4: mode
.else
        MOVEQ.L #0x3F,D1                        | 512K: bits 0-5: mode and "enable active"
.endif
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVE.B  q7L(A0),D0                      | Q7L: read the status register
        TST.B   q6L(A0)                         | Q6L: back to read mode
        AND.B   D1,D0                           | the bits of D1
        CMP.B   D1,D0                           | all set: mode $1F (512K: and a drive enabled)?
| --- ROM-variant difference @ $1D9C ---
| MAC_128K: BEQ.B +$32 to SONY_RECAL_STEPS ($1DD0)
| MAC_512K: BEQ.B +$34 to SONY_RECAL_STEPS ($1DD2)
| Reason: the 512K's extra MOVEQ #$1F,D1 at $1DA2 moves the code
|         behind it by 2 bytes (up to $1DD5, where both agree again)
.if ROM_TARGET == MAC_128K
        BEQ.B   SONY_RECAL_STEPS                | 128K: yes -> step
.else
        BEQ.B   SONY_RECAL_STEPS                | 512K: yes -> step
.endif
        MOVEQ.L #0x2,D2                         | 2
        SWAP    D2                              | D2 = $20000 loops, about one second (OneSecConst)
| --- ROM-variant difference @ $1DA2..$1DD5 ---
| MAC_128K: SetIWMMode loop with D1 = $1F; then at most 82 ($52) steps,
|           the first one inward (D0 = DirLAdr = 0, BRA.B to the step)
| MAC_512K: MOVEQ #$1F,D1 first (D1 was $3F), the same loop; then at
|           most 80 ($50) steps, all outward (NOP instead of the
|           MOVEQ #0,D0 / BRA.B)
| Reason: follows from $1D8A (the loop needs D1 = $1F); the 512K also
|         drops the first step away from track 0. Both are 52 bytes.
.if ROM_TARGET == MAC_128K
| SetIWMMode -- wait (at most about a second) until no drive enable is
| active, write mode $1F (only possible with Motor-On = 0) until it reads
| back (status bits 0-4). On a timeout the exit stores initIWMErr with
| D1 = $1F as the drive offset: an odd address (address error).
SONY_RECAL_SETMODE:
        MOVEQ.L #initIWMErr,D0                  | initIWMErr (-77): assume a timeout
        SUBQ.L  #0x1,D2                         | count the loop
        BMI.B   SONY_RECAL_ERR_2                | timeout -> error
        TST.B   mtrOff(A0)                      | mtrOff: Motor-On = 0 (needed to write the mode)
        TST.B   q6H(A0)                         | Q6H: L6 = 1 (sense state)
        MOVE.B  q7L(A0),D0                      | Q7L: read the status register
        BTST    #0x5,D0                         | a drive enable still active (status bit 5)?
        BNE.B   SONY_RECAL_SETMODE              | yes -> wait for it to go off
        AND.B   D1,D0                           | mode bits 0-4
        CMP.B   D1,D0                           | mode $1F set?
        BEQ.B   SONY_RECAL_OK                   | yes -> done
        MOVE.B  D1,q7H(A0)                      | Q7H (L7 = L6 = 1, motor off): write the mode register = $1F
        TST.B   q7L(A0)                         | Q7L: back to the sense state (status register)
        BRA.B   SONY_RECAL_SETMODE              | read it back
SONY_RECAL_OK:
        TST.B   q6L(A0)                         | Q6L: back to read mode
        BSR.B   Sony_RWPowerUp                  | RWPowerUp: re-enable and power up the drive
SONY_RECAL_STEPS:
        MOVEQ.L #0x52,D7                        | at most 82 steps
        MOVEQ.L #DirLAdr,D0                     | DirLAdr: the first step goes inward
        BRA.B   SONY_RECAL_STEP                 | -> step
.else
| 512K: MOVEQ #$1F,D1 for the mode loop; the loop branches back to its
| second instruction (SONY_RECAL_SETMODE_LOOP)
SONY_RECAL_SETMODE:
        MOVEQ.L #0x1F,D1                        | mode $1F: latch, async, no timer, fast, 8 MHz
SONY_RECAL_SETMODE_LOOP:
        MOVEQ.L #initIWMErr,D0                  | initIWMErr (-77): assume a timeout
        SUBQ.L  #0x1,D2                         | count the loop
        BMI.B   SONY_RECAL_ERR_2                | timeout -> error
        TST.B   mtrOff(A0)                      | mtrOff: Motor-On = 0 (needed to write the mode)
        TST.B   q6H(A0)                         | Q6H: L6 = 1 (sense state)
        MOVE.B  q7L(A0),D0                      | Q7L: read the status register
        BTST    #0x5,D0                         | a drive enable still active (status bit 5)?
        BNE.B   SONY_RECAL_SETMODE_LOOP         | yes -> wait for it to go off
        AND.B   D1,D0                           | mode bits 0-4
        CMP.B   D1,D0                           | mode $1F set?
        BEQ.B   SONY_RECAL_OK                   | yes -> done
        MOVE.B  D1,q7H(A0)                      | Q7H (L7 = L6 = 1, motor off): write the mode register = $1F
        TST.B   q7L(A0)                         | Q7L: back to the sense state (status register)
        BRA.B   SONY_RECAL_SETMODE_LOOP         | read it back
SONY_RECAL_OK:
        TST.B   q6L(A0)                         | Q6L: back to read mode
        BSR.B   Sony_RWPowerUp                  | RWPowerUp: re-enable and power up the drive
SONY_RECAL_STEPS:
        MOVEQ.L #0x50,D7                        | at most 80 steps
        NOP                                     | (the 128K's MOVEQ #0,D0 / BRA.B)
.endif
| step out until /TK0 (12 ms per step)
SONY_RECAL_LOOP:
        MOVE    SeekTime(A1),D0                 | SeekTime: 12 ms
        BSR.W   E_Sony_WakeUp                   | WakeUp
        MOVEQ.L #Tk0Adr,D0                      | Tk0Adr: track 0 sense
        BSR.W   Sony_AdrAndSense                | sense = 0 at track 0
        BPL.B   SONY_RECAL_DONE                 | there -> done
        MOVEQ.L #DirHAdr,D0                     | DirHAdr: direction control, CA2 = 1: out (toward track 0)
SONY_RECAL_STEP:
        BSR.W   Sony_AdrAndStrb                 | set the direction
        MOVEQ.L #StepLAdr,D0                    | StepLAdr: /STEP sense
        BSR.W   Sony_AdrAndSense                | /STEP high (1) = ready to step
        BPL.B   SONY_RECAL_ERR                  | not ready -> cantStepErr
        MOVEQ.L #tk0BadErr,D0                   | tk0BadErr (-76) if we run out of steps
        SUBQ.W  #0x1,D7                         | count the step
        BEQ.B   SONY_RECAL_ERR_2                | out of steps without track 0 -> error
        BSR.W   Sony_Pulse                      | LSTRB pulse at StepLAdr: step
        BRA.B   SONY_RECAL_LOOP                 | again
SONY_RECAL_DONE:
        MOVEQ.L #0x0,D0                         | track 0
        BRA.B   SONY_RECAL_ERR_2                | store and return
SONY_RECAL_ERR:
        MOVEQ.L #cantStepErr,D0                 | cantStepErr (-75): drive will not step
SONY_RECAL_ERR_2:
        MOVE    D0,Track(A1,D1.W)               | Track = 0 or error code
        JMP     (A5)                            | return
| -------------------------------------------------------------------------
| PowerDown -- power-down after D0 VBL task calls (TimeOut, 0.5 s each;
| the VBL task does it), or at once if D0 = 0: motor off control
| (MtrOffAdr) and the drive enable cut (mtrOff)
Sony_PowerDown:
        BSR.W   Sony_GetDrv1                    | GetDrv1
        MOVE    D0,TimeOut(A1)                  | TimeOut = D0
        BEQ.B   SONY_POWERDOWN_NOW              | 0 -> power down now
        RTS                                     | return
SONY_POWERDOWN_NOW:
        MOVEQ.L #MtrOffAdr,D0                   | MtrOffAdr: motor control, CA2 = 1: motor off
        BSR.W   Sony_AdrAndStrb                 | AdrAndStrb
        TST.B   mtrOff(A0)                      | mtrOff: also cut the drive enable /ENBLx
        RTS                                     | return
| FastPower -- power up without waiting
Sony_FastPower:
        MOVEQ.L #0x0,D0                         | no wait
        BRA.B   Sony_PowerUp                    | common path
| RWPowerUp -- power up and wait PwrOnTime (400 ms)
Sony_RWPowerUp:
        MOVE    PwrOnTime(A1),D0                | PwrOnTime (400 ms)
| PowerUp -- cancel a pending power-down (TimeOut = 0), select and enable
| the drive; if its motor is off: motor on and wait D0 (WakeUp)
Sony_PowerUp:
        MOVE    D0,D2                           | D2 = wait time
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1
        CLR     TimeOut(A1)                     | TimeOut = 0: no power-down pending
        BSR.B   Sony_DiskSelect                 | DiskSelect
        MOVEQ.L #MtrOnAdr,D0                    | MtrOnAdr: motor-on sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when the motor is on
        BPL.B   SONY_POWERUP_EXIT               | already on -> return
        BSR.W   Sony_Pulse                      | LSTRB pulse at MtrOnAdr (CA2 = 0): motor on
        MOVE    D2,D0                           | D0 = wait time
        BNE.W   E_Sony_WakeUp                   | wait time -> WakeUp
SONY_POWERUP_EXIT:
        RTS                                     | return
| DiskSelect -- select the drive (Drive-Sel: intDrive for drive 1,
| extDrive for drive 2) and assert its enable (mtrOn: Motor-On = 1)
Sony_DiskSelect:
        BSR.W   Sony_GetDrive                   | GetDrive: A0 = IWM, A2 = VIA, A1, D1
SONY_DISKSELECT_1:
        MOVE    #intDrive,D0                    | intDrive: drive 1 (/ENBL1)
        CMPI    #Drive1,D1                      | drive 1's variables?
        BEQ.B   SONY_DISKSELECT_SET             | yes ->
        MOVE    #extDrive,D0                    | extDrive: drive 2 (/ENBL2)
SONY_DISKSELECT_SET:
        TST.B   0(A0,D0.W)                      | Drive-Sel state bit
        TST.B   mtrOn(A0)                       | mtrOn: Motor-On = 1, the selected /ENBL goes low
        RTS                                     | return
| -------------------------------------------------------------------------
| SpeedCheckTbl -- speed value limits of the five zones (upper, lower;
| +-2% around the zone's speed; speed value = 2^29 / VIA timer counts
| per revolution = 11.42 * rpm). ReSeek checks against them, MakeSpdTbl
| aims at their midpoints.
DT_Sony_SpeedCheckTbl:
        .short  0x11E9,0x1135                   | zone 0 (tracks 0-15): about 394 rpm
        .short  0x138A,0x12C6                   | zone 1 (tracks 16-31): about 429 rpm
        .short  0x157F,0x14A7                   | zone 2 (tracks 32-47): about 472 rpm
        .short  0x17E2,0x16F2                   | zone 3 (tracks 48-63): about 525 rpm
        .short  0x1ADE,0x19D0                   | zone 4 (tracks 64-79): about 590 rpm
| MakeSpdTbl -- jump through the JMakeSpdTbl vector
E_Sony_MakeSpdTbl:
        MOVE.L  (DiskVars_JMakeSpdTbl).w,-(SP)  | MakeSpdTbl: push the JMakeSpdTbl vector
        RTS                                     | and jump through it
| -------------------------------------------------------------------------
| jtMakeSpdTbl -- the speed codes of the five zones (TrkSpeedTbl): speed
| values at codes $80 and $100 (GetFreq), then per zone the code for the
| midpoint of its limits and the delta to the upper limit (2%). Unlike
| the Plus version there is no guard against f256 <= f128 (DIVU by 0).
|   D0 (out) -- 0 or noDriveErr (no tachometer pulses)
Sony_MakeSpdTbl:
        MOVE.L  (SP)+,A4                        | A4 = return address
        MOVE    #0x80,D2                        | speed code $80
        BSR.B   SONY_GETFREQ                    | GetFreq: D4 = speed value at that code
        BMI.B   SONY_MAKESPDTBL_ERR             | error -> return it
        MOVE.L  D4,D3                           | D3 = f128: speed value at code $80
        MOVE    #0x100,D2                       | speed code $100
        BSR.B   SONY_GETFREQ                    | GetFreq
        BMI.B   SONY_MAKESPDTBL_ERR             | error -> return it
        MOVE.L  D4,D5                           | D5 = D4 = f256: speed value at code $100
        SUB.L   D3,D5                           | D5 = f256 - f128: change per 128 code steps
        LSL.L   #0x1,D3                         | D3 = 2 * f128
        MOVEQ.L #0x4,D6                         | five zones
        LEA     DT_Sony_SpeedCheckTbl(PC),A5    | A5 -> SpeedCheckTbl (speed value limits)
        BSR.W   Sony_GetDrv1                    | GetDrv1
        LEA.L   TrkSpeedTbl(A1,D1.W),A3         | A3 -> TrkSpeedTbl of this drive
| per zone: pass 1 code of the midpoint t, pass 2 code of the upper limit
SONY_MAKESPDTBL_LOOP:
        MOVEQ.L #0x0,D2                         | (high word 0)
        MOVE    (A5)+,D2                        | D2 = upper limit of the zone
        MOVE.L  D2,D7                           | D7 = upper limit (for pass 2)
        ADD     (A5)+,D2                        | + lower limit
        LSR     #0x1,D2                         | D2 = t: the midpoint (target speed value)
SONY_MAKESPDTBL_CODE:
        ADD.L   D4,D2                           | t + f256
        SUB.L   D3,D2                           | t + f256 - 2 * f128
        BPL.B   SONY_MAKESPDTBL_SCALE           | not negative ->
        MOVEQ.L #0x0,D2                         | else 0
SONY_MAKESPDTBL_SCALE:
        LSL.L   #0x7,D2                         | * 128
        BEQ.B   SONY_MAKESPDTBL_ROUND           | 0 -> code 1
        DIVU    D5,D2                           | / (f256 - f128) = speed code for t
SONY_MAKESPDTBL_ROUND:
        ADDQ.W  #0x1,D2                         | + 1 (rounds up)
        CMPI    #0x18F,D2                       | above $18F?
        BLE.B   SONY_MAKESPDTBL_OK              | no ->
        MOVE    #0x18F,D2                       | clamp to $18F
SONY_MAKESPDTBL_OK:
        MOVE    D2,(A3)+                        | pass 1: TSTblCode; pass 2: code(upper), replaced below
        EXG     D7,D2                           | D2 = upper limit for pass 2, D7 = this code
        NOT     D0                              | toggle the pass flag (D0 = 0 from GetFreq)
        BNE.B   SONY_MAKESPDTBL_CODE            | -> pass 2
        SUBQ.W  #0x4,A3                         | A3 -> TSTblCode
        SUB     (A3)+,D7                        | D7 = code(upper) - code(midpoint): the 2% delta
        MOVE    D7,(A3)+                        | TSTblDelta
        CLR.L   (A3)+                           | TSTblTicks = 0: check the zone at its first use
        DBRA    D6,SONY_MAKESPDTBL_LOOP         | next zone
SONY_MAKESPDTBL_ERR:
        TST     D0                              | CCR = result
        JMP     (A4)                            | return
| GetFreq -- set speed code D2, wait PwrOnTime, then GetFreq1
| GetFreq1 -- D4 = speed value: 4 FigTrkSpd measurements of 1/4
| revolution each, sum / 8, $4000000 / that = 2^29 / counts per revolution
|   D0 (out) -- 0 or noDriveErr; return via JMP (A3)
SONY_GETFREQ:
        MOVE.L  (SP)+,A3                        | A3 = return address
        BSR.W   SONY_SETSPEED_CONT_3            | program speed code D2
        MOVE    PwrOnTime(A1),D0                | PwrOnTime: 400 ms for the speed change
        BSR.W   E_Sony_WakeUp                   | WakeUp
SONY_GETFREQ1:
        MOVEQ.L #0x0,D4                         | sum of the measurements
        MOVEQ.L #0x3,D5                         | four measurements
SONY_GETFREQ1_LOOP:
        BSR.B   E_Sony_FigTrkSpd                | VIA timer counts for 15 tach pulses (1/4 revolution)
        BMI.B   SONY_GETFREQ1_EXIT              | error -> return it
        ADD.L   D0,D4                           | add up
        DBRA    D5,SONY_GETFREQ1_LOOP           | four times: one revolution
        LSR.L   #0x3,D4                         | counts per revolution / 8
        MOVE.L  #0x04000000,D0                  | 2^26
        DIVU    D4,D0                           | D0 = speed value (11.42 * rpm)
        MOVE    D0,D4                           | D4 = speed value
        MOVEQ.L #0x0,D0                         | noErr
SONY_GETFREQ1_EXIT:
        JMP     (A3)                            | return
| FigTrkSpeed -- jump through the JFigTrkSpd vector
E_Sony_FigTrkSpd:
        MOVE.L  (DiskVars_JFigTrkSpd).w,-(SP)   | FigTrkSpeed: push the JFigTrkSpd vector
        RTS                                     | and jump through it
| -------------------------------------------------------------------------
| jtFigTrkSpd -- VIA timer 2 counts for 15 tachometer pulses (1/4
| revolution; TACH gives 60 pulses per revolution). The TACH sense is read
| as status bit 7 while timer 2 counts down from $FFFF (783.36 kHz); if it
| runs out (VIA IFR bit 5) no pulses come: noDriveErr.
|   D0 (out) -- counts (PL) or noDriveErr (MI)
Sony_FigTrkSpd:
        MOVE    SR,-(SP)                        | save the interrupt level
        MOVEM.L D1-A6,-(SP)                     | save registers
        MOVEQ.L #0x4,D0                         | PollStack = SP + 4 (one return address)
        BSR.W   E_Sony_SetUpPoll                | SetUpPoll: A5, A6, interrupts off
        MOVEQ.L #TachAdr,D0                     | TachAdr: tachometer sense
        BSR.W   Sony_AdrDisk                    | address it
        LEA.L   (IWM_Base).l,A0                 | A0 = IWM base, absolute (DBase = $DFE1FF)
        TST.B   q6H(A0)                         | Q6H: L6 = 1, the status register is read at Q7L
        MOVEQ.L #-0x1,D1                        | D1 = $FF: timer bytes
        MOVEQ.L #0x5,D3                         | D3 = 5: VIA IFR bit of timer 2 (ifT2)
        MOVE.L  (VIA).w,A2                      | A2 = VIA base
        LEA.L   vIFR(A2),A3                     | A3 -> VIA interrupt flag register
        LEA.L   q7L(A0),A1                      | A1 -> Q7L: status register (bit 7 = TACH)
        BSR.B   SONY_STARTT2                    | StartT2: timeout for the first pulse
        BSR.B   SONY_WAITTACH                   | WaitTach: synchronize with a pulse
        BEQ.B   SONY_FIGTRKSPD_CONT_2           | found -> measure
SONY_FIGTRKSPD_EXIT:
        TST.B   q6L(A0)                         | Q6L: L6 = 0, back to read mode
        BSR.W   Sony_EmptyPD                    | EmptyPD
        MOVEM.L (SP)+,D1-A6                     | restore registers
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST.L   D0                              | CCR = result
        RTS                                     | return
| -------------------------------------------------------
| StartT2 -- timer 2 = $FFFF, counting down
SONY_STARTT2:
        MOVE.B  D1,vT2C(A2)                     | timer 2 low byte (latch)
        MOVE.B  D1,vT2CH(A2)                    | timer 2 high byte: start
        RTS                                     | return
| measure: 15 pulses
SONY_FIGTRKSPD_CONT_2:
        BSR.B   SONY_STARTT2                    | StartT2
        MOVEQ.L #0xE,D2                         | 15 pulses
SONY_FIGTRKSPD_LOOP:
        BSR.B   SONY_WAITTACH                   | WaitTach
        BNE.B   SONY_FIGTRKSPD_EXIT             | timeout -> error
        DBRA    D2,SONY_FIGTRKSPD_LOOP          | 15 pulses
        MOVE.B  vT2CH(A2),D2                    | timer 2 high byte
        MOVE.B  vT2C(A2),D1                     | timer 2 low byte
        CMP.B   vT2CH(A2),D2                    | high byte changed meanwhile?
        BEQ.B   SONY_FIGTRKSPD_OK               | no ->
        MOVEQ.L #0x0,D1                         | yes: low byte = 0
SONY_FIGTRKSPD_OK:
        BTST    D3,(A3)                         | timer 2 ran out (IFR bit 5)?
        BNE.B   SONY_FIGTRKSPD_EXIT             | yes -> error (D0 = noDriveErr)
        LSL     #0x8,D2                         | high byte
        OR.B    D1,D2                           | | low byte = timer value
        NOT     D2                              | $FFFF - timer = counts
        MOVEQ.L #0x0,D0                         | (high word 0)
        MOVE    D2,D0                           | D0 = counts for 15 pulses
        BRA.B   SONY_FIGTRKSPD_EXIT             | return them
| WaitTach -- wait for a rising TACH edge (each level read twice),
| polling the SCC; returns through DskRtn: EQ ok, MI noDriveErr
SONY_WAITTACH:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
SONY_WAITTACH_LOW:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WAITTACH_LOW_2             | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WAITTACH_LOW_2:
        TST.B   (A1)                            | status: TACH in bit 7
        BMI.B   SONY_WAITTACH_LOW_3             | high ->
        TST.B   (A1)                            | low twice?
        BPL.B   SONY_WAITTACH_HIGH              | yes -> wait for high
SONY_WAITTACH_LOW_3:
        BTST    D3,(A3)                         | timer 2 run out?
        BEQ.B   SONY_WAITTACH_LOW               | no -> keep waiting
SONY_WAITTACH_TIMEOUT:
        MOVEQ.L #noDriveErr,D0                  | noDriveErr (-64): timeout or no drive
| DskRtn -- continue at DskRtnAdr with CCR = D0
SONY_DSKRTN:
        MOVE.L  (DskRtnAdr).w,-(SP)             | push the continuation address
        TST     D0                              | CCR = result
        RTS                                     | go there
SONY_WAITTACH_HIGH:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WAITTACH_HIGH_2            | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WAITTACH_HIGH_2:
        BTST    D3,(A3)                         | timer 2 run out?
        BNE.B   SONY_WAITTACH_TIMEOUT           | yes -> error
        TST.B   (A1)                            | TACH
        BPL.B   SONY_WAITTACH_HIGH              | low -> keep waiting
        TST.B   (A1)                            | high twice?
        BPL.B   SONY_WAITTACH_HIGH              | no -> keep waiting
        MOVEQ.L #0x0,D0                         | noErr: rising edge seen
        BRA.B   SONY_DSKRTN                     | return

| -------------------------------------------------------------------------
| DiskVBLTask -- VBL task, every DskVBLTime (30 ticks = 0.5 s): counts
| down a pending power-down (TimeOut) and looks for inserted disks in
| drives 2 and 1; not while a request is active. Runs at IPL 1.
|   A0 (in) -- the VBL task element (DiskQVE)
Sony_DiskVBLTask:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x100,SR                       | no VBL interrupts (IPL 1)
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE    DskVBLTime(A1),vblCount(A0)     | vblCount = DskVBLTime: run again in 0.5 s
        TST.B   Active(A1)                      | Active: request in progress?
        BNE.B   SONY_DISKVBLTASK_EXIT           | yes -> leave the drives alone
        TST     TimeOut(A1)                     | TimeOut: power-down pending?
        BEQ.B   SONY_DISKVBLTASK_POLL           | no -> poll the drives
        SUBQ.W  #0x1,TimeOut(A1)                | count it down
        BNE.B   SONY_DISKVBLTASK_EXIT           | not yet -> a drive is still powered: exit
        MOVEQ.L #MtrOffAdr,D0                   | MtrOffAdr: time is up, motor off
        BSR.W   Sony_AdrAndStrb                 | AdrAndStrb (the enable is cut below)
        TST.B   mtrOff(A0)                      | mtrOff: cut the drive enable
SONY_DISKVBLTASK_POLL:
        MOVEQ.L #0x2,D3                         | drive 2 (external)
        BSR.B   Sony_Check4Disk                 | Check4Disk
        MOVEQ.L #0x1,D3                         | drive 1 (internal)
        BSR.B   Sony_Check4Disk                 | Check4Disk
SONY_DISKVBLTASK_EXIT:
        RTE                                     | restore the interrupt level, return
| Check4Disk -- drive D3: if it is connected (CkInstalled), count
| DiskInPlace up to 0 after an eject; with no disk look for one, then
| DiskInPlace = 1 and post a disk-inserted event (message = drive
| number; Inside Macintosh II-212). Without a disk the current track
| becomes unknown (CkInval).
Sony_Check4Disk:
        MOVE    D3,Drive(A1)                    | Drive = D3
        BSR.W   Sony_GetDrive                   | GetDrive: A0, A1, A2, D1
        BSR.B   SONY_CKINSTALLED                | CkInstalled: drive connected?
        BMI.B   SONY_CKEXIT                     | no -> exit
        BSR.W   SONY_DISKSELECT_1               | DiskSelect: select and enable the drive
        TST.B   DiskInPlace(A1,D1.W)            | DiskInPlace: disk in place (1 or 2)?
        BGT.B   SONY_CKEXIT                     | yes -> exit
        BEQ.B   SONY_CKDIP_SENSE                | none -> CkDIP
        ADDQ.B  #0x1,DiskInPlace(A1,D1.W)       | just ejected ($FC-$FF): count up towards 0
        BMI.B   SONY_CKINVAL                    | still waiting -> CkInval
| CkDIP -- disk-in-place sense
SONY_CKDIP_SENSE:
        MOVEQ.L #DIPAdr,D0                      | DIPAdr: disk-in-place sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when a disk is in place
        BMI.B   SONY_CKINVAL                    | no disk -> exit
        ADDQ.B  #0x1,DiskInPlace(A1,D1.W)       | DiskInPlace = 1: disk in place, not clamped
        MOVE    #diskInsertEvt,A0               | diskInsertEvt (7)
        MOVE.L  D3,D0                           | message = drive number (high word 0)
        _PostEvent                              | post the event (the result is not checked)
| CkInval -- the current track is unknown
SONY_CKINVAL:
        ST      Track(A1,D1.W)                  | Track = $FFxx: current track invalid
SONY_CKEXIT:
        RTS                                     | return
| CkInstalled -- is the drive connected? Installed is 0 until it is
| known: then /DRVIN (DrvExstAdr, 0 = connected) and SIDES are sensed once;
| a drive that is not there loses its drive queue element.
|   D0 (out) = noDriveErr, N set if the drive is not connected
SONY_CKINSTALLED:
        MOVE.B  Installed(A1,D1.W),D2           | D2 = Installed (1 yes, $FF no, 0 unknown)
        BNE.B   SONY_CKINSTALLED_SET            | known ->
        BSR.W   SONY_DISKSELECT_1               | DiskSelect: select and enable the drive
        MOVEQ.L #DrvExstAdr,D0                  | DrvExstAdr: /DRVIN sense (0 = drive connected)
        MOVEQ.L #-0x1,D2                        | D2 = $FF: assume not connected
        BSR.W   Sony_AdrAndSense                | sense
        BMI.B   SONY_CKINSTALLED_NONE           | high -> no drive
        MOVEQ.L #0x1,D2                         | D2 = 1: connected
        MOVEQ.L #SidesAdr,D0                    | SidesAdr: number of sides sense
        BSR.W   Sony_AdrAndSense                | 1 = two-sided drive
        SMI     Sides(A1,D1.W)                  | Sides = $FF for a two-sided drive
SONY_CKINSTALLED_SET:
        MOVEQ.L #noDriveErr,D0                  | D0 = noDriveErr (for the callers)
        MOVE.B  D2,Installed(A1,D1.W)           | Installed = D2 (N set if not connected)
        RTS                                     | return
| no drive: take its drive queue element out of the queue
SONY_CKINSTALLED_NONE:
        LEA.L   DQEl(A1,D1.W),A0                | A0 -> the drive's queue element
        LEA.L   (DrvQHdr_Flags).w,A1            | A1 = drive queue header
        JSR     Dequeue(PC)                     | Dequeue it
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1 again
        BRA.B   SONY_CKINSTALLED_SET            | Installed = $FF
| AdrMks -- address mark $D5 $AA $96, slip marks $DE $AA, then $FF
DT_Sony_SectorAdrTbl:
        .byte   0xD5,0xAA,0x96,0xDE,0xAA,0xFF   | $D5 $AA $96 $DE $AA $FF
| SetUpPoll -- jump through the JSetUpPoll vector
E_Sony_SetUpPoll:
        MOVE.L  (DiskVars_JSetUpPoll).w,-(SP)   | push the JSetUpPoll vector
        RTS                                     | and jump through it
| -------------------------------------------------------------------------
| jtSetUpPoll -- prepare the SCC polling of the disk routines: A6 = SCC
| channel A data, A5 = VIA port A (SCC W/REQ in bit 7), interrupts off;
| PollStack = SP + D0 (the stack level of the caller's caller)
Sony_SetUpPoll:
        LEA.L   (SCC_RdDataA).l,A6              | A6 = SCC channel A data (read)
        LEA.L   (VIA_PortA2).l,A5               | A5 = VIA port A (vBufD: SCC W/REQ in bit 7)
        MOVE.L  SP,(PollStack).w                | PollStack = SP
        ADD.L   D0,(PollStack).w                | + D0 (the return addresses)
        ORI     #0x300,SR                       | no interrupts from now on
        RTS                                     | return

| -------------------------------------------------------
| RdAddrSetup -- set up polling, address the read data of the head for the
| side in SideTrack, then RdAddr: D1 = side/track, D2 = sector, D3 =
| format byte of the next address field
Sony_RdAddrSetup:
        MOVEQ.L #0x8,D0                         | PollStack = SP + 8 (two return addresses)
        BSR.B   E_Sony_SetUpPoll                | SetUpPoll
        MOVEQ.L #RdDtaAdr,D0                    | RdDtaAdr: read data of the side 0 head
        BTST    #0x3,SideTrack(A1)              | side 1 (bit 11 of SideTrack)?
        BEQ.B   SONY_RDADDRSETUP_SIDE           | no ->
        MOVEQ.L #RdDta1Adr,D0                   | RdDta1Adr: read data of the side 1 head
SONY_RDADDRSETUP_SIDE:
        BSR.W   Sony_AdrDisk                    | address it: that head's data on the RD line
| RdAddr -- address mark table in A2, jump through the JRdAddr vector
E_Sony_RdAddr:
        LEA     DT_Sony_SectorAdrTbl(PC),A2     | A2 -> AdrMks: address mark table
        MOVE.L  (DiskVars_JRdAddr).w,-(SP)      | push the JRdAddr vector
        RTS                                     | and jump through it
| -------------------------------------------------------------------------
| jtRdAddr -- read the next address field that passes the head
|   A2 (in)  -- AdrMks; A5/A6 (in) -- VIA port A / SCC data (SetUpPoll)
|   D0 (out) -- MustFindCt minus the nibbles read before the mark (>= 0),
|               or noNybErr, noAdrMkErr, badCksmErr, badBtSlpErr
|   D1 (out) -- side/track (bit 11 side, bits 0-10 track), D2 -- sector,
|               D3 -- format byte; A3 -> denibblize table - $96, A4 = Q6L
| The IWM is in the read state (L7 = L6 = 0, motor on): reading Q6L gives
| the data register, bit 7 set when a whole nibble has been shifted in.
| Returns through DskRtn (DskRtnAdr), interrupts off, poll data on the
| stack. (The Plus version allows 128 reads for the first nibbles.)
Sony_RdAddr:
        MOVEQ.L #0x3,D3                         | D3 = 3: find 3 nibbles first (Apple: "try for 3 bytes")
        MOVEQ.L #0x30,D2                        | D2: within at most 49 reads of the data register
        MOVEQ.L #0x0,D5                         | D5 = 0: nibbles are used as a word index
        MOVE.L  #IWM_Q6L,A4                     | A4 = q6L: the data register (absolute address, DiskQ6L)
        MOVE.L  (SP)+,(DskRtnAdr).w             | save the return address
SONY_RDADDR_SKIP:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_CONT                | no SCC byte waiting ->
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_CONT:
        MOVE.B  (A4),D5                         | read the data register
        DBRA    D2,SONY_RDADDR_LOOP             | count the read
        MOVEQ.L #noNybErr,D0                    | noNybErr (-66): fewer than 3 nibbles in 49 reads
        BRA.W   SONY_RDADDR_ERR                 | return the error
SONY_RDADDR_LOOP:
        BPL.B   SONY_RDADDR_SKIP                | bit 7 clear: no nibble yet
        SUBQ.W  #0x1,D3                         | one more nibble
        BNE.B   SONY_RDADDR_SKIP                | until 3 were seen (not necessarily in a row)
        MOVE    #MustFindCt,D0                  | MustFindCt: find the mark within 1500 nibbles
        LEA     SONY_DENIBLTBL-0x96(PC),A3      | A3 -> denibblize table - $96 (indexed by disk byte)
SONY_RDADDR_CONT_3:
        MOVE.L  A2,A0                           | A0 -> AdrMks
        MOVEQ.L #0x3,D1                         | 3 mark bytes
SONY_RDADDR_NEXT:
        MOVE.B  (A4),D5                         | read the data register
        BPL.B   SONY_RDADDR_NEXT                | wait for a nibble
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_2              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_2:
        DBRA    D0,SONY_RDADDR_LOOP_2           | count the nibble
        MOVEQ.L #noAdrMkErr,D0                  | noAdrMkErr (-67): no address mark within the count
        BRA.B   SONY_RDADDR_ERR                 | return the error
SONY_RDADDR_LOOP_2:
        CMP.B   (A0)+,D5                        | next mark byte?
        BNE.B   SONY_RDADDR_CONT_3              | no -> start over
        SUBQ.W  #0x1,D1                         | one more matched
        BNE.B   SONY_RDADDR_NEXT                | until all three (D1 = 0 afterwards)
SONY_RDADDR_CONT_4:
        MOVE.B  (A4),D5                         | track nibble
        BPL.B   SONY_RDADDR_CONT_4              | wait for it
        MOVE.B  0x0(A3,D5.W),D1                 | denibblize: track bits 0-5
        MOVE.B  D1,D4                           | start the checksum
        ROR     #0x6,D1                         | park them in bits 10-15 (room for the side byte)
SONY_RDADDR_CONT_5:
        MOVE.B  (A4),D5                         | sector nibble
        BPL.B   SONY_RDADDR_CONT_5              | wait for it
        MOVE.B  0x0(A3,D5.W),D2                 | denibblize: sector number
        EOR.B   D2,D4                           | checksum
SONY_RDADDR_CONT_6:
        MOVE.B  (A4),D5                         | side nibble
        BPL.B   SONY_RDADDR_CONT_6              | wait for it
        MOVE.B  0(A3,D5.W),D1                   | denibblize: side (bit 5) and track bits 6-10
        EOR.B   D1,D4                           | checksum
        ROL     #0x6,D1                         | D1 bits 0-11: side (bit 11) and track
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_3              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_3:
        MOVE.B  (A4),D5                         | format nibble ("volume" in Apple's code)
        BPL.B   SONY_RDADDR_SKIP_3              | wait for it
        MOVE.B  0(A3,D5.W),D3                   | denibblize: format byte ($20 = two-sided)
        EOR.B   D3,D4                           | checksum
SONY_RDADDR_CONT_7:
        MOVE.B  (A4),D5                         | checksum nibble
        BPL.B   SONY_RDADDR_CONT_7              | wait for it
        MOVE.B  0(A3,D5.W),D5                   | denibblize
        EOR.B   D5,D4                           | XOR of all five must be 0
        BNE.B   SONY_RDADDR_ERR_2               | no -> badCksmErr
        MOVEQ.L #0x1,D4                         | 2 slip marks
SONY_RDADDR_LOOP_3:
        MOVE.B  (A4),D5                         | next nibble
        BPL.B   SONY_RDADDR_LOOP_3              | wait for it
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_4              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_4:
        CMP.B   (A0)+,D5                        | slip mark $DE, $AA?
        BNE.B   SONY_RDADDR_ERR_3               | no -> badBtSlpErr
        DBRA    D4,SONY_RDADDR_LOOP_3           | both
SONY_RDADDR_ERR:
        BRA.W   SONY_DSKRTN                     | DskRtn: return with D0 (PL for ok)
SONY_RDADDR_ERR_2:
        MOVEQ.L #badCksmErr,D0                  | badCksmErr (-69): address field checksum wrong
        BRA.B   SONY_RDADDR_ERR                 | return the error
SONY_RDADDR_ERR_3:
        MOVEQ.L #badBtSlpErr,D0                 | badBtSlpErr (-70): address field slip marks wrong
        BRA.B   SONY_RDADDR_ERR                 | return the error
| DtaMks -- data mark $D5 $AA $AD, slip marks $DE $AA, then $FF
SONY_DTAMKS:
        .byte   0xD5,0xAA,0xAD,0xDE,0xAA,0xFF   | $D5 $AA $AD $DE $AA $FF
| RdData -- data mark table in A1, jump through the JRdData vector
E_Sony_RdData:
        LEA     SONY_DTAMKS(PC),A1              | A1 -> DtaMks: data mark table
        MOVE.L  (DiskVars_JRdData).w,-(SP)      | push the JRdData vector
        RTS                                     | and jump through it

| -------------------------------------------------------------------------
| jtRdData -- read the data field after the address field just read: the
| sector number to TagData+1, the 12 tag bytes to TagData+2, the 512 data
| bytes to (A0); with DskVerify set compare them with (A0) instead. The
| nibbles are denibblized and checksummed on the fly as in the Plus
| driver (whose comments describe the bit layout).
|   A0 (in) -- buffer, A1 -- DtaMks, A3, A4, A5, A6 as RdAddr left them
|   D0 (out) -- 0, noDtaMkErr, badDCksum, dataVerErr, badDBtSlp
Sony_RdData:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address here
        MOVEQ.L #0x30,D2                        | D2 = 48: find the data mark within 48 nibbles
        MOVEQ.L #0x0,D3                         | D3 = 0: nibbles are used as a word index
        MOVEQ.L #-0x40,D0                       | D0 = $C0: mask for bits 7-6 (MOVEQ #-64)
        MOVE.L  #0x1FE000A,D4                   | counts: lo 10 -> 4 groups (12 tags), hi 510 -> 170 groups + 2
        MOVEQ.L #0x0,D5                         | CkSumA = 0
        MOVEQ.L #0x0,D6                         | CkSumB = 0
        MOVEQ.L #0x0,D7                         | CkSumC = 0
SONY_RDDATA_CONT:
        MOVE.L  A1,A2                           | A2 -> DtaMks
        MOVEQ.L #0x3,D1                         | D1 = 3 data mark bytes to match ($D5 $AA $AD)
SONY_RDDATA_LOOP:
        MOVE.B  (A4),D3                         | read the data register
        BPL.B   SONY_RDDATA_LOOP                | no nibble yet -> read again
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP                | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP:
        DBRA    D2,SONY_RDDATA_LOOP_2           | count the nibble
        MOVEQ.L #noDtaMkErr,D0                  | noDtaMkErr (-71): no data mark within 49 nibbles
        BRA.B   SONY_RDADDR_ERR                 | return the error
SONY_RDDATA_LOOP_2:
        CMP.B   (A2)+,D3                        | next mark byte?
        BNE.B   SONY_RDDATA_CONT                | no -> start over
        SUBQ.W  #0x1,D1                         | one more mark byte matched
        BNE.B   SONY_RDDATA_LOOP                | loop if more mark bytes to match
SONY_RDDATA_CONT_2:
        MOVE.B  (A4),D3                         | sector number nibble
        BPL.B   SONY_RDDATA_CONT_2              | no nibble yet -> read again
        LEA.L   (TagData_1).w,A1                | A1 -> TagData+1
        MOVE.B  0x0(A3,D3.W),(A1)+              | sector number of the data mark -> TagData+1
SONY_RDDATA_CONT_3:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_2              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_2:
        MOVE.B  (A4),D3                         | top-bits nibble
        BPL.B   SONY_RDDATA_CONT_3              | no nibble yet -> read again
        MOVE.B  0(A3,D3.W),D1                   | D1 = [0][0][A7][A6][B7][B6][C7][C6]
        ROL.B   #0x2,D1                         | D1 = [A7][A6][B7][B6][C7][C6][0][0]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [A7][A6][0][0][0][0][0][0]
SONY_RDDATA_CONT_4:
        MOVE.B  (A4),D3                         | byte A nibble
        BPL.B   SONY_RDDATA_CONT_4              | wait for it
        OR.B    0x0(A3,D3.W),D2                 | D2 = ByteA' (no time to check for bad nibbles)
        MOVE.B  D7,D3                           | CkSumC
        ADD.B   D7,D3                           | X = CkSumC bit 7
        ROL.B   #0x1,D7                         | CkSumC' = CkSumC rotated left
        EOR.B   D7,D2                           | ByteA = ByteA' XOR CkSumC'
        MOVE.B  D2,(A1)+                        | store byte A
        ADDX.B  D2,D5                           | CkSumA += ByteA + X
        ROL.B   #0x2,D1                         | D1 = [B7][B6][C7][C6][0][0][A7][A6]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [B7][B6][0][0][0][0][0][0]
SONY_RDDATA_CONT_5:
        MOVE.B  (A4),D3                         | byte B nibble
        BPL.B   SONY_RDDATA_CONT_5              | wait for it
        OR.B    0x0(A3,D3.W),D2                 | D2 = ByteB'
        EOR.B   D5,D2                           | ByteB = ByteB' XOR CkSumA
        MOVE.B  D2,(A1)+                        | store byte B
        ADDX.B  D2,D6                           | CkSumB += ByteB + X
        ROL.B   #0x2,D1                         | D1 = [C7][C6][0][0][A7][A6][B7][B6]
        AND.B   D0,D1                           | D1 = [C7][C6][0][0][0][0][0][0]
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_3              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_3:
        MOVE.B  (A4),D3                         | byte C nibble
        BPL.B   SONY_RDDATA_SKIP_3              | wait for it
        OR.B    0(A3,D3.W),D1                   | D1 = ByteC'
        EOR.B   D6,D1                           | ByteC = ByteC' XOR CkSumB
        MOVE.B  D1,(A1)+                        | store byte C
        ADDX.B  D1,D7                           | CkSumC += ByteC + X
        SUBQ.W  #0x3,D4                         | 3 bytes done
        BPL.B   SONY_RDDATA_CONT_3              | more bytes in this buffer -> next group
        SWAP    D4                              | tags done: D4 = 510, buffer (A0)
        TST.B   (DskVerify).w                   | read-verify (ioPosMode bit 6, DskVerify)?
        BEQ.B   SONY_RDDATA_SKIP_4              | no -> RdData3: store the data
        BRA.B   SONY_RDDATA_SKIP_6              | yes -> RdVer1: compare instead
SONY_RDDATA_LOOP_3:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_4              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_4:
        MOVE.B  (A4),D3                         | top-bits nibble
        BPL.B   SONY_RDDATA_LOOP_3              | no nibble yet -> read again
        MOVE.B  0(A3,D3.W),D1                   | D1 = [0][0][A7][A6][B7][B6][C7][C6]
        ROL.B   #0x2,D1                         | D1 = [A7][A6][B7][B6][C7][C6][0][0]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [A7][A6][0][0][0][0][0][0]
SONY_RDDATA_CONT_6:
        MOVE.B  (A4),D3                         | byte A nibble
        BPL.B   SONY_RDDATA_CONT_6              | wait for it
        OR.B    0(A3,D3.W),D2                   | D2 = ByteA'
        MOVE.B  D7,D3                           | CkSumC
        ADD.B   D7,D3                           | X = CkSumC bit 7
        ROL.B   #0x1,D7                         | CkSumC' = CkSumC rotated left
        EOR.B   D7,D2                           | ByteA = ByteA' XOR CkSumC'
        MOVE.B  D2,(A0)+                        | store byte A
        ADDX.B  D2,D5                           | CkSumA += ByteA + X
        ROL.B   #0x2,D1                         | D1 = [B7][B6][C7][C6][0][0][A7][A6]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [B7][B6][0][0][0][0][0][0]
SONY_RDDATA_CONT_7:
        MOVE.B  (A4),D3                         | byte B nibble
        BPL.B   SONY_RDDATA_CONT_7              | wait for it
        OR.B    0(A3,D3.W),D2                   | D2 = ByteB'
        EOR.B   D5,D2                           | ByteB = ByteB' XOR CkSumA
        MOVE.B  D2,(A0)+                        | store byte B
        ADDX.B  D2,D6                           | CkSumB += ByteB + X
        TST     D4                              | counter 0: bytes 511 and 512 done?
        BEQ.B   SONY_RDDATA_DONE                | yes -> RdCkSum
        ROL.B   #0x2,D1                         | D1 = [C7][C6][0][0][A7][A6][B7][B6]
        AND.B   D0,D1                           | D1 = [C7][C6][0][0][0][0][0][0]
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_5              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_5:
        MOVE.B  (A4),D3                         | byte C nibble
        BPL.B   SONY_RDDATA_SKIP_5              | wait for it
        OR.B    0(A3,D3.W),D1                   | D1 = ByteC'
        EOR.B   D6,D1                           | ByteC = ByteC' XOR CkSumB
        MOVE.B  D1,(A0)+                        | store byte C
        ADDX.B  D1,D7                           | CkSumC += ByteC + X
        SUBQ.W  #0x3,D4                         | 3 bytes done
        BRA.B   SONY_RDDATA_LOOP_3              | next group
SONY_RDDATA_LOOP_4:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_6              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_6:
        MOVE.B  (A4),D3                         | top-bits nibble
        BPL.B   SONY_RDDATA_LOOP_4              | no nibble yet -> read again
        MOVE.B  0(A3,D3.W),D1                   | D1 = [0][0][A7][A6][B7][B6][C7][C6]
        ROL.B   #0x2,D1                         | D1 = [A7][A6][B7][B6][C7][C6][0][0]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [A7][A6][0][0][0][0][0][0]
SONY_RDDATA_CONT_8:
        MOVE.B  (A4),D3                         | byte A nibble
        BPL.B   SONY_RDDATA_CONT_8              | wait for it
        OR.B    0(A3,D3.W),D2                   | D2 = ByteA'
        MOVE.B  D7,D3                           | CkSumC
        ADD.B   D7,D3                           | X = CkSumC bit 7
        ROL.B   #0x1,D7                         | CkSumC' = CkSumC rotated left
        EOR.B   D7,D2                           | ByteA = ByteA' XOR CkSumC'
        CMP.B   (A0)+,D2                        | same as in the buffer?
        BNE.B   SONY_RDDATA_ERR                 | no -> dataVerErr
        ADDX.B  D2,D5                           | CkSumA += ByteA + X
        ROL.B   #0x2,D1                         | D1 = [B7][B6][C7][C6][0][0][A7][A6]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [B7][B6][0][0][0][0][0][0]
SONY_RDDATA_CONT_9:
        MOVE.B  (A4),D3                         | byte B nibble
        BPL.B   SONY_RDDATA_CONT_9              | wait for it
        OR.B    0(A3,D3.W),D2                   | D2 = ByteB'
        EOR.B   D5,D2                           | ByteB = ByteB' XOR CkSumA
        CMP.B   (A0)+,D2                        | same as in the buffer?
        BNE.B   SONY_RDDATA_ERR_3               | no -> dataVerErr
        ADDX.B  D2,D6                           | CkSumB += ByteB + X
        TST     D4                              | counter 0: last group done?
        BEQ.B   SONY_RDDATA_DONE                | yes -> RdCkSum
        ROL.B   #0x2,D1                         | D1 = [C7][C6][0][0][A7][A6][B7][B6]
        AND.B   D0,D1                           | D1 = [C7][C6][0][0][0][0][0][0]
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_7              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_7:
        MOVE.B  (A4),D3                         | byte C nibble
        BPL.B   SONY_RDDATA_SKIP_7              | wait for it
        OR.B    0(A3,D3.W),D1                   | D1 = ByteC'
        EOR.B   D6,D1                           | ByteC = ByteC' XOR CkSumB
        CMP.B   (A0)+,D1                        | same as in the buffer?
SONY_RDDATA_ERR:
        BNE.B   SONY_RDDATA_ERR_3               | no -> dataVerErr
        ADDX.B  D1,D7                           | CkSumC += ByteC + X
        SUBQ.W  #0x3,D4                         | 3 bytes done
        BRA.B   SONY_RDDATA_LOOP_4              | next group
SONY_RDDATA_DONE:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_8              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_8:
        MOVE.B  (A4),D3                         | top-bits nibble of the checksums
        BPL.B   SONY_RDDATA_SKIP_8              | wait for it
        MOVE.B  0(A3,D3.W),D1                   | D1 = [0][0][A7][A6][B7][B6][C7][C6]
        BMI.B   SONY_RDDATA_ERR_2               | $FF: invalid nibble -> badDCksum
        ROL.B   #0x2,D1                         | D1 = [A7][A6][B7][B6][C7][C6][0][0]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [A7][A6][0][0][0][0][0][0]
SONY_RDDATA_CONT_10:
        MOVE.B  (A4),D3                         | CkSumA nibble
        BPL.B   SONY_RDDATA_CONT_10             | wait for it
        MOVE.B  0(A3,D3.W),D3                   | D3 = [0][0][A5][A4][A3][A2][A1][A0]
        BMI.B   SONY_RDDATA_ERR_2               | invalid nibble -> badDCksum
        OR.B    D3,D2                           | D2 = CkSumA as written
        CMP.B   D2,D5                           | = the computed CkSumA?
        BNE.B   SONY_RDDATA_ERR_2               | no -> badDCksum
        ROL.B   #0x2,D1                         | D1 = [B7][B6][C7][C6][0][0][A7][A6]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [B7][B6][0][0][0][0][0][0]

SONY_RDDATA_CONT_11:
        MOVE.B  (A4),D3                         | CkSumB nibble
        BPL.B   SONY_RDDATA_CONT_11             | wait for it
        MOVE.B  0(A3,D3.W),D3                   | D3 = [0][0][B5][B4][B3][B2][B1][B0]
        BMI.B   SONY_RDDATA_ERR_2               | invalid nibble -> badDCksum
        OR.B    D3,D2                           | D2 = CkSumB as written
        CMP.B   D2,D6                           | = the computed CkSumB?
        BNE.B   SONY_RDDATA_ERR_2               | no -> badDCksum
        ROL.B   #0x2,D1                         | D1 = [C7][C6][0][0][A7][A6][B7][B6]
        AND.B   D0,D1                           | D1 = [C7][C6][0][0][0][0][0][0]
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_9              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_9:
        MOVE.B  (A4),D3                         | CkSumC nibble
        BPL.B   SONY_RDDATA_SKIP_9              | wait for it
        MOVE.B  0(A3,D3.W),D3                   | D3 = [0][0][C5][C4][C3][C2][C1][C0]
        BMI.B   SONY_RDDATA_ERR_2               | invalid nibble -> badDCksum
        OR.B    D3,D1                           | D1 = CkSumC as written
        CMP.B   D1,D7                           | = the computed CkSumC?
        BEQ.B   SONY_RDDATA_CONT_12             | yes -> RdSlip
SONY_RDDATA_ERR_2:
        MOVEQ.L #badDCksum,D0                   | badDCksum (-72): data checksum wrong or invalid nibble
        BRA.B   SONY_RDDATA_CONT_13             | return the error
SONY_RDDATA_ERR_3:
        MOVEQ.L #dataVerErr,D0                  | dataVerErr (-68): read-verify compare failed
        BRA.B   SONY_RDDATA_CONT_13             | return the error
SONY_RDDATA_CONT_12:
        MOVEQ.L #0x1,D4                         | 2 slip marks
SONY_RDDATA_LOOP_5:
        MOVE.B  (A4),D3                         | next nibble
        BPL.B   SONY_RDDATA_LOOP_5              | wait for it
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_10             | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_10:
        CMP.B   (A2)+,D3                        | slip mark $DE, $AA?
        BNE.B   SONY_RDDATA_ERR_4               | no -> badDBtSlp
        DBRA    D4,SONY_RDDATA_LOOP_5           | both
        MOVEQ.L #0x0,D0                         | noErr
SONY_RDDATA_CONT_13:
        BRA.W   SONY_DSKRTN                     | return through DskRtn

| badDBtSlp: data field slip marks wrong
SONY_RDDATA_ERR_4:
        MOVEQ.L #badDBtSlp,D0                   | badDBtSlp (-73): data field slip marks wrong
        BRA.B   SONY_RDDATA_CONT_13             | return the error
| -------------------------------------------------------------------------
| DNib -- denibblize table, indexed by disk nibble - $96 (A3 = SONY_DENIBLTBL
| - $96): the 6-bit value of each of the 64 valid nibbles, $FF for the 42
| other bytes from $96 to $FF; the inverse of NiblTbl. Only the checksum
| nibbles are checked for $FF.
SONY_DENIBLTBL:
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
| -------------------------------------------------------------------------
| MarkTbl -- the six self-sync bytes and the data mark $D5 $AA in front of
| each data field written by WrData; $AD (NiblTbl[$0B]) follows from the
| loop
SONY_WRDATAMKS:
        .byte   0xFF,0x3F,0xCF,0xF3,0xFC,0xFF   | the six self-sync bytes
        .byte   0xD5,0xAA                       | data mark $D5 $AA
| WrData -- MarkTbl in A2, jump through the JWrData vector
E_Sony_WrData:
        LEA     SONY_WRDATAMKS(PC),A2           | A2 -> MarkTbl: self-sync bytes and data mark
        MOVE.L  (DiskVars_JWrData).w,-(SP)      | push the JWrData vector
        RTS                                     | and jump through it

| -------------------------------------------------------------------------
| jtWrData -- write the data field of the sector whose address field was
| just read: six self-sync bytes, $D5 $AA $AD, the sector number
| (TagData+1), the 12 tag bytes (TagData+2..) and the 512 bytes at (A0),
| 6-and-2 encoded with three running checksums, then the checksum
| nibbles and $DE $AA $FF $FF (see the Plus driver for the IWM write
| sequence: Q6H, first byte to Q7H, handshake bit 7 at Q6L, data to Q6H).
|   A0 (in) -- data buffer; A2 -- MarkTbl; A4 = Q6L, A5/A6 (SetUpPoll)
|   D0 (out) -- 0 or wrUnderrun
Sony_WrData:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address as continuation
        LEA.L   (TagData_1).w,A1                | A1 -> TagData+1: sector number and tags first
        MOVE.L  #0x2010009,D4                   | counts: lo 9 = 12 tags - 1st group; hi 513 = last tag group + 170 data groups
        MOVEQ.L #0x0,D2                         | D2 = 0: high byte clear for indexing
        MOVEQ.L #0x0,D3                         | D3 = 0
        MOVE.L  #IWM_Q6H,A3                     | A3 = q6H: write data register (absolute, DiskQ6H)
        TST.B   (A3)                            | Q6H: L6 = 1 (sense state)
        MOVEQ.L #0x6,D0                         | the loop writes the next 6 bytes ($3F..$D5)
        MOVEQ.L #0x0,D5                         | CkSumA = 0
        MOVE.B  (A2)+,(IWM_Q7H).l               | first byte $FF to Q7H: L7 = 1, write state
        MOVEQ.L #0x0,D6                         | CkSumB = 0
        MOVEQ.L #0x0,D7                         | CkSumC = 0
SONY_WRDATA_LOOP:
        MOVE.B  (A2)+,D1                        | next byte of MarkTbl
SONY_WRDATA_NO:
        TST.B   (A4)                            | handshake register (q6L): bit 7 = buffer empty?
        BPL.B   SONY_WRDATA_NO                  | no -> wait
        MOVE.B  D1,(A3)                         | write it (q6H)
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP                | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP:
        SUBQ.W  #0x1,D0                         | count it
        BNE.B   SONY_WRDATA_LOOP                | next
        MOVE.B  (A2)+,D1                        | $AA, the second data mark byte
        LEA     DT_Sony_NiblTbl(PC),A2          | A2 -> NiblTbl: 6-bit value -> disk nibble
SONY_WRDATA_NO_2:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_2                | no -> wait
        MOVE.B  D1,(A3)                         | write $AA
        MOVEQ.L #0xB,D1                         | NiblTbl[$0B] = $AD: the loop writes it as "byte B"
        MOVE.B  (A1)+,D2                        | D2 = sector number (TagData+1): "byte C", not checksummed
        BRA.B   SONY_WRDATA_LOOP_2              | into the loop
SONY_WRDATA_CONT:
        MOVE.L  A0,A1                           | A1 = user buffer
SONY_WRDATA_NEXT:
        ADDX.B  D2,D7                           | CkSumC += ByteC + X
        EOR.B   D6,D2                           | ByteC' = ByteC XOR CkSumB
        MOVE.B  D2,D3                           | low byte of D3 = ByteC' (A', B' top bits above it)
        LSR     #0x6,D3                         | D3 = A7 A6 B7 B6 C7 C6: the top bits of the group
SONY_WRDATA_NO_3:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_3                | no -> wait
        MOVE.B  0x0(A2,D3.W),(A3)               | write them as one nibble
        SUBQ.W  #0x3,D4                         | 3 more bytes (clears X)
        MOVE.B  D7,D3                           | CkSumC
        ADD.B   D7,D3                           | X = bit 7 of checksum C
        ROL.B   #0x1,D7                         | CkSumC rotated left (not through X)
        ANDI.B  #0x3F,D0                        | low 6 bits of byte A'
SONY_WRDATA_NO_4:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_2              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_2:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_4                | no -> wait (polling the SCC)
        MOVE.B  0(A2,D0.W),(A3)                 | write low A
SONY_WRDATA_LOOP_2:
        MOVE.B  (A1)+,D0                        | D0 = next ByteA
        ADDX.B  D0,D5                           | CkSumA += ByteA + X
        EOR.B   D7,D0                           | ByteA' = ByteA XOR CkSumC
        MOVE.B  D0,D3                           | top bits of A'
        ROL     #0x2,D3                         | into D3
        ANDI.B  #0x3F,D1                        | low 6 bits of byte B' (first time: $0B)
SONY_WRDATA_NO_5:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_5                | no -> wait
        MOVE.B  0x0(A2,D1.W),(A3)               | write low B (first time: $AD)
        MOVE.B  (A1)+,D1                        | D1 = next ByteB
        ADDX.B  D1,D6                           | CkSumB += ByteB + X
        EOR.B   D5,D1                           | ByteB' = ByteB XOR CkSumA
        MOVE.B  D1,D3                           | top bits of B'
        ROL     #0x2,D3                         | into D3
        ANDI.B  #0x3F,D2                        | low 6 bits of byte C' (first time: sector number)
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_3              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_3:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_SKIP_3              | no -> wait
        MOVE.B  0(A2,D2.W),(A3)                 | write low C
        MOVE.B  (A1)+,D2                        | D2 = next ByteC (after the last group: unused)
        TST     D4                              | end of this buffer?
        BNE.B   SONY_WRDATA_NEXT                | no -> WrData1
        SWAP    D4                              | tags done (lo was 9): D4 = 513 for the data
        BNE.B   SONY_WRDATA_CONT                | -> WrDataSw; data done (0): last group
        CLR.B   D3                              | last group: only bytes 511 and 512, C = 0
        LSR     #0x6,D3                         | D3 = A7 A6 B7 B6 0 0
SONY_WRDATA_NO_6:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_6                | no -> wait
        MOVE.B  0x0(A2,D3.W),(A3)               | write the top-bits nibble of the last group
        MOVE.B  D5,D3                           | start the checksum top-bits nibble:
        ROL     #0x2,D3                         | checksum A bits 7-6,
        MOVE.B  D6,D3                           | then checksum B
        ROL     #0x2,D3                         | (bits 7-6 of A and B now in D3 bits 8-11)
        ANDI.B  #0x3F,D0                        | low 6 bits of byte A (data byte 511)
SONY_WRDATA_NO_7:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_7                | no -> wait
        MOVE.B  0x0(A2,D0.W),(A3)               | write it
        ANDI.B  #0x3F,D1                        | low 6 bits of byte B (data byte 512)
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_4              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_4:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_SKIP_4              | no -> wait
        MOVE.B  0x0(A2,D1.W),(A3)               | write it
        MOVE.B  D7,D3                           | add checksum C:
        LSR     #0x6,D3                         | D3 = top bits of checksums A, B, C
SONY_WRDATA_NO_8:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_8                | no -> wait
        MOVE.B  0(A2,D3.W),(A3)                 | write the checksum top-bits nibble
        ANDI.B  #0x3F,D5                        | low 6 bits of CkSumA
SONY_WRDATA_NO_9:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_9                | no -> wait
        MOVE.B  0(A2,D5.W),(A3)                 | write CkSumA
        ANDI.B  #0x3F,D6                        | low 6 bits of CkSumB
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_5              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_5:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_SKIP_5              | no -> wait
        MOVE.B  0(A2,D6.W),(A3)                 | write CkSumB
        ANDI.B  #0x3F,D7                        | low 6 bits of CkSumC
SONY_WRDATA_NO_10:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_10               | no -> wait
        MOVE.B  0(A2,D7.W),(A3)                 | write CkSumC
        LEA     SONY_SLIPMKS(PC),A2             | A2 -> $DE $AA $FF $FF
        MOVEQ.L #0x3,D2                         | four bytes
SONY_WRDATA_LOOP_3:
        MOVE.B  (A4),D1                         | handshake register: bit 7 empty, bit 6 write state
        BPL.B   SONY_WRDATA_LOOP_3              | wait for the buffer
        MOVE.B  (A2)+,(A3)                      | write the next byte
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_6              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_6:
        DBRA    D2,SONY_WRDATA_LOOP_3           | four bytes
        MOVEQ.L #0x0,D0                         | assume no underrun
        BTST    #0x6,D1                         | handshake bit 6 still 1 (cleared by an underrun)?
        BNE.B   SONY_WRDATA_OK                  | yes -> noErr
        MOVEQ.L #wrUnderrun,D0                  | wrUnderrun (-74): the buffer ran empty
SONY_WRDATA_OK:
        TST.B   (IWM_Q7L).l                     | Q7L: L7 = 0, leave the write state (DiskQ7L)
        BRA.W   SONY_DSKRTN                     | return through DskRtn
| TrailMks -- slip marks $DE $AA and two $FF that let the last byte reach
| the disk before the write state ends
SONY_SLIPMKS:
        .byte   0xDE,0xAA,0xFF,0xFF             | slip marks $DE $AA, then $FF $FF
| -------------------------------------------------------------------------
| Nibl -- 6-bit value -> disk nibble: the 64 bytes with bit 7 set, no
| more than one pair of adjacent 0 bits and two adjacent 1 bits in bits
| 0-6 (the SWIM Chip User's Ref, "GCR Encoding", states only the 0-bit
| rules, which 72 bytes pass); DNib above is the inverse
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
