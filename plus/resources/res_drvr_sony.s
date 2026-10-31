| ========================================================================
| DRVR 4 -- .Sony disk driver (Mac Plus: 400K/800K floppy drives, HD20)
| ========================================================================
| resource : 'DRVR' 4 '.Sony'
|
| Apple's Sony disk driver (Larry Kenyon, 1982-86; a later version of the
| same code is in the System 7.1 sources, Drivers/Sony/Sony*.a, whose
| routine names are used here). It runs the IWM floppy disk controller
| for the internal drive (drive 1) and a drive on the external port
| (drive 2): 400K one-sided drives (old interface; the Mac sets their
| speed through the PWM line) and 800K two-sided drives (new interface:
| ready handshake, own speed control). Hard Disk 20 drives ("DCD",
| direct connect device; drive numbers 3-6, driver refNum -2) on the
| external port use the same interface lines with a serial protocol.
| Register conventions (Apple: GetDrive): A1 = SonyVars, D1 = offset of
| the current drive's variables in SonyVars, A0 = IWM base, A2 = VIA
| base; during transfers A4 = IWM register, A5 = VIA port A (SCC W/REQ
| in bit 7) and A6 = SCC channel A data (SCC polling, see SetUpPoll).
|
| IWM (IWM Design Spec; hwregs.inc; offsets ph0L..q7H in sysequ.inc):
| each access to one of its 16 locations, $200 apart from DBase =
| $DFE1FF, sets ("H") or clears ("L") one state bit: PH0-PH3 (the
| drive's CA0, CA1, CA2, LSTRB lines), Motor-On (drive enable /ENBLx),
| Drive-Sel (intDrive: /ENBL1, internal; extDrive: /ENBL2, external),
| L6, L7. L7 and L6 select the register (registers are read at "L" and
| written at "H" locations):
|   L7 L6  0 0  read data (all ones while Motor-On = 0)
|          0 1  read status: bit 7 SENSE, bit 5 a drive enable is
|               active, bits 0-4 mode register
|          1 0  read write handshake: bit 7 = 1 buffer empty, bit 6 = 0
|               after a write underrun
|          1 1  write the mode register (Motor-On = 0) or data (= 1)
| Mode $1F (set by Recal): latch mode, asynchronous handshake, 1-second
| motor-off timer disabled, fast mode, 8 MHz clock: 2 us bit cells
| (Apple's SonyHdr.a: "16 us/nybble").
|
| Drive registers: CA1, CA0, SEL (VIA port A bit 5) and CA2 address 16
| sense and control registers; D0 holds such an address as CA1-CA0-SEL-
| CA2 in bits 3-0 (table in include/sonyequ.inc). Sense reads the
| addressed sense line as status bit 7; Pulse strobes LSTRB (PH3), and
| the drive sets the control register addressed by CA1, CA0, SEL to CA2.
|
| GCR disk format (SWIM Chip User's Ref, "GCR Track Format"; Inside
| Macintosh II-211): 80 tracks per side in five speed zones of 16 tracks
| with 12, 11, 10, 9 and 8 sectors per track (track 0 is the outermost).
| Each sector has
|   an address field: self-sync bytes, mark $D5 $AA $96, track, sector,
|     side, format byte, checksum (XOR of the four), slip marks $DE $AA
|   a data field: self-sync bytes, mark $D5 $AA $AD, sector number, 699
|     nibbles of 12 tag and 512 data bytes (6-and-2 encoded with three
|     running checksums), 4 checksum nibbles, slip marks $DE $AA
| The address field bytes are 6-bit values: the side byte holds the side
| in bit 5 and track bits 6-10; the format byte is $02 (one-sided) or
| $22 (two-sided), 2:1 interleave. A disk byte ("nibble") has bit 7 set
| and no more than two 0 bits in a row; 64 of these encode the 6-bit
| values (NiblTbl), $D5 and $AA are reserved for the marks.
|
| Disk speed: a 400K drive gets one speed code per zone (TrkSpeedTbl in
| its drive variables, measured by MakeSpdTbl with the tachometer and
| rechecked by ReSeek every 4 minutes); SetSpeed writes it as PWM values
| into the low bytes of the sound buffer words. 800K drives get code 0.
|
| SonyVars: include/sonyequ.inc has this layout (MPW 1.0 SonyEqu.a,
| DiskVarLth = $310): driver variables $00-$49, drive 1 variables $4A,
| drive 2 $8C (66 bytes each), WakeTimeCnt $CE, SaveRegs $D0, TagBufPtr
| $F4, TagBufOS $F8, DiskErrs $FA, PassThru $FC, CurSector $FE, track
| cache $100-$111, LastDrive $112, TimeOutDrive $116, TimeQEl $118,
| NextGZProc $124, HD20 drive variables $128, $144, $160, $17C (28 bytes
| each), HD20 command and status block from StsRtnAddr ($198) on.
|
| DRVR header (Inside Macintosh II-188)

| resource header
    ROM_RESOURCE DRVR_4                         | 8-byte resource header (include/romrsrc.inc)
_DRVR_4_.Sony:
  .short 0x4F00                                 | drvrFlags: dNeedLock+dStatEnable+dCtlEnable+dWritEnable+dReadEnable
  .short 0x0000                                 | drvrDelay: no periodic action
  .short 0x0000                                 | drvrEMask: no event mask
  .short 0x0000                                 | drvrMenu: no menu
  .short E_Sony_Open-_DRVR_4_.Sony              | drvrOpen: $006E
  .short E_Sony_Prime-_DRVR_4_.Sony             | drvrPrime: $033A
  .short E_Sony_Control-_DRVR_4_.Sony           | drvrCtl: $01E2
  .short E_Sony_Status-_DRVR_4_.Sony            | drvrStatus: $02EC
  .short E_Sony_Close-_DRVR_4_.Sony             | drvrClose: $0018
  .byte 0x05                                    | drvrName length = 5
  .ascii ".Sony"                                | drvrName: driver name string
| -------------------------------------------------------
| DiskClose -- the driver cannot be closed: return closErr.
E_Sony_Close:
        MOVEQ.L #closErr,D0                     | closErr: driver not closeable
        RTS                                     | return error to Device Manager

| InitDskTbl -- word offsets (relative to INITDSKTBL) of the disk routines
| whose addresses DiskOpen stores in the 15 jump vectors of DiskVars
| (JFigTrkSpd..NiblTbl, $222-$25A). Patches can redirect a routine by
| changing its vector. SetSpeed is the PWM speed routine (the 7.1 driver,
| without 400K drive support, has an RTS there).
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
        .short  Sony_AdrDisk-INITDSKTBL         | JAdrDisk ($252)
        .short  Sony_SetSpeed-INITDSKTBL        | JSetSpeed ($256)
        .short  DT_Sony_NiblTbl-INITDSKTBL      | NiblTbl ($25A): GCR nibble table (data)
| InitDsk2 -- three more vectors, stored from JDiskSel ($B40) on
INITDSK2:
        .short  Sony_jtDiskSel-INITDSKTBL       | JDiskSel ($B40)
        .short  Sony_SendCmd-INITDSKTBL         | JSendCmd ($B44)
        .short  Sony_DCDReset-INITDSKTBL        | JDCDReset ($B48)
| InitParams -- tuneable drive constants, copied into SonyVars from
| ReadErrInit (+$2A) on (32 bytes; the values of sonyequ.inc, section
| "Floppy drive constants")
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
| -------------------------------------------------------
| DispSetUp -- convert word offsets into absolute jump vectors.
|   A0 (in/out) -- next offset in the table
|   A1 (in/out) -- next jump vector
|   D0 (in)     -- base address the offsets are relative to
|   D1 (in)     -- number of vectors - 1
DISPSETUP:
        MOVEQ.L #0x0,D2                         | clear high word for 32-bit add
        MOVE    (A0)+,D2                        | get next word offset from table
        ADD.L   D0,D2                           | compute absolute address = base + offset
        MOVE.L  D2,(A1)+                        | store vector in jump table
        DBF     D1,DISPSETUP                    | loop for all entries
        RTS                                     | return from DISPSETUP

| ========================================================================
|
| DiskOpen -- driver initialization (called once at boot, A1 = DCE)
|
| Allocates the $310-byte SonyVars block, sets up the disk routine
| vectors and the tuneable constants, installs the VBL task (disk-in-
| place polling and motor power-down) and the Time Manager element used
| by WakeUp, checks whether an HD20 on the external port passes requests
| through (PassThru), looks for connected drives (1 internal floppy, 2
| external floppy, 3-6 HD20) and gives each a drive queue element
| (_AddDrive). Finally it installs the grow-zone procedure that frees the
| track cache buffer when the system heap runs out of memory.
E_Sony_Open:
        MOVE.L  #DiskVarLth,D0                  | DiskVarLth: $310 bytes of driver variables
        _NewPtrSysClear                         | allocate zeroed system heap block
        MOVE.L  A0,(SonyVars).w                 | store SonyVars ptr in low memory
        MOVE.L  A1,(A0)                         | DiskUnitPtr: save DCE ptr at offset 0
        MOVE.L  (UTableBase).w,A2               | unit table base
        MOVE.L  0x10(A2),0x4(A2)                | unit 1 (refNum -2, HD20 drives) shares the .Sony DCE (unit 4)
        MOVE.B  #0x1,dCtlQueue+1(A1)            | driver version 1 (DCtlQueue+1)
        ST.B    Active(A0)                      | Active: mark driver active (exclude VBL)
        MOVE.L  A0,A2                           | A2 = SonyVars for later use
| initialize the disk routine jump table (15 vectors)
        LEA.L   INITDSKTBL(PC),A0               | point to InitDskTbl offset table
        LEA.L   (DiskVars_JFigTrkSpd).w,A1      | first jump table entry
        MOVEQ.L #0xE,D1                         | 15 vectors (0..14)
        MOVE.L  A0,D0                           | base address for offset computation
        BSR.B   DISPSETUP                       | DispSetUp: convert to absolute addrs
        LEA.L   (JDiskSel).w,A1                 | second table: DiskSel, SendCmd, DCDReset
        MOVEQ.L #0x2,D1                         | 3 more vectors
        BSR.B   DISPSETUP                       | install them
        ST.B    OneToOne(A2)                    | OneToOne: set 1:1 flag (legacy, unused)
| copy tuneable drive constants (32 bytes) into SonyVars
        LEA.L   ReadErrInit(A2),A1              | dest: ReadErrInit(A2)
        LEA.L   INITPARAMS(PC),A0               | source: InitParams table
        MOVEQ.L #0x20,D0                        | 32 bytes to copy
        _BlockMove                              | copy drive constants
| install the VBL task for power-down and disk-in-place sensing
        LEA.L   DiskQVE(A2),A0                  | DiskQVE(A2): VBL task control block
        MOVE    #vType,qType(A0)                | qType = vType (VBL task)
        LEA.L   Sony_DiskVBLTask(PC),A1         | address of VBL task routine
        MOVE.L  A1,vblAddr(A0)                  | vblAddr: set task entry point
        MOVE    #KDskVBLTime,vblCount(A0)       | vblCount = 30 ticks (0.5 s)
        _VInstall                               | install into vertical retrace queue
| install the Time Manager queue element used by WakeUp
        LEA.L   TimeQEl(A2),A0                  | TimeQEl(A2): time queue element
        _InsTime                                | register with Time Manager
| Check whether pass-thru works on the external connector: an HD20
| without pass-thru would make it look as if an endless chain of HD20s
| were connected. Drive 7 (beyond the last HD20) is selected through the
| daisy chain; if an HD20 answers there, pass-thru does not work.
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        MOVE    #0x7,Drive(A1)                  | Drive = 7: one more than the last HD20 (DrvVarOS has 7 entries)
        BSR     Sony_DiskSelect                 | DiskSelect: select it through the chain
        BSR     Sony_CkDCDExist                 | CkDCDExist: does an HD20 answer (PL)?
        SPL.B   PassThru(A1)                    | PassThru: 0 = pass-thru works, $FF = it does not
| look for drives 1-6, install drive queue entries
        MOVEQ.L #0x1,D2                         | D2 = physical drive number, start at 1
E_SONY_OPEN_LOOP:
        MOVE    D2,Drive(A1)                    | Drive = physical drive number being probed
        BSR     Sony_GetDrive                   | GetDrive: A0=IWM, A2=VIA, D1 = this drive's vars offset
        ST.B    Installed(A1,D1.W)              | Installed = $FF: assume not connected
        CMPI    #0x3,D2                         | drives 1-3: probe them
        BLE.B   E_SONY_OPEN_CONT                | (3 = the first HD20, no pass-thru needed)
        TST.B   PassThru(A1)                    | PassThru: does pass-thru work?
        BMI.B   E_SONY_OPEN_SKIP                | no -> no further HD20 (drives 4-6)
E_SONY_OPEN_CONT:
        BSR     Sony_DiskSelect                 | DiskSelect: select the drive
        CMPI    #0x3,D2                         | HD20 (drive 3-6)?
        BLT.B   CHKCONNECT                      | no -> floppy drive 1 or 2
        BSR     Sony_CkDCDExist                 | CkDCDExist: HD20 connected at this position?
        BMI.B   E_SONY_OPEN_SKIP                | no -> skip
        MOVE    #0x1,DriveQVers(A1,D1.W)        | DriveQVers (+$0A, the drive queue element's qType) = 1: dQDrvSz2 holds the high word of the HD20 size
        MOVEQ.L #-0x2,D3                        | DCDRfN: refNum -2 for HD20 drives
        BRA.B   E_SONY_OPEN_CONT_2              | install the drive queue element

| -------------------------------------------------------
| ChkConnect -- floppy drive: connected? number of sides, interface
CHKCONNECT:
        MOVEQ.L #DrvExstAdr,D0                  | DrvExstAdr: drive-exists sense (0 = connected)
        BSR     Sony_AdrAndSense                | AdrAndSense
        BMI.B   E_SONY_OPEN_SKIP                | not connected, skip this drive
        MOVEQ.L #SidesAdr,D0                    | SidesAdr: number-of-sides sense
        BSR     Sony_AdrAndSense                | sense = 1 for a two-sided drive
        SMI.B   Sides(A1,D1.W)                  | Sides = $FF: two-sided drive
        MOVEQ.L #NewIntfAdr,D0                  | NewIntfAdr: new-interface sense
        BSR     Sony_AdrAndSense                | sense = 1: drive implements the ready handshake (800K drive)
        SMI.B   NewIntf(A1,D1.W)                | NewIntf = $FF: new interface
        MOVEQ.L #-0x5,D3                        | SonyRfN: refNum -5 for floppy drives
E_SONY_OPEN_CONT_2:
        MOVE.B  #0x1,Installed(A1,D1.W)         | Installed = 1 (drive is installed)
        MOVE    D2,D0                           | physical drive number in high word
        SWAP    D0                              | move it to the high word
        MOVE    D3,D0                           | D0.lo = driver refNum (-5 floppy, -2 HD20)
        LEA.L   DQEl(A1,D1.W),A0                | A0 -> drive queue element in the drive vars (+6)
        _AddDrive                               | add the drive to the drive queue
E_SONY_OPEN_SKIP:
        ADDQ.W  #0x1,D2                         | next physical drive number
        CMPI    #0x6,D2                         | up to drive 6 (2 floppy + 4 HD20)
        BLE.B   E_SONY_OPEN_LOOP                | loop for all drives
| install the grow-zone procedure that frees the track cache buffer
        MOVE.L  (SysZone).w,A2                  | get system zone pointer
        LEA.L   SONY_GZPROC(PC),A0              | our grow-zone procedure
        MOVE.L  gzProc(A2),NextGZProc(A1)       | NextGZProc = the zone's previous grow-zone procedure
        MOVE.L  A0,gzProc(A2)                   | install ours in the zone header (gzProc)
        CLR.B   Active(A1)                      | Active = 0: driver idle
        MOVEQ.L #0x0,D0                         | return noErr
        RTS                                     | return to Device Manager

| -------------------------------------------------------
| Grow-zone procedure of the system heap: frees the track cache buffer
| (TCdispose) when the Memory Manager needs space; if there was none,
| it calls the previous grow-zone procedure. (Removed in the SE driver.)
SONY_GZPROC:
        MOVE.L  (SonyVars).w,A1                 | get SonyVars pointer
        BSR.B   SONY_TCDISPOSE                  | TCdispose: free track cache buffer
        BNE.B   SONY_GZPROC_RET                 | freed memory, return size
        MOVE.L  NextGZProc(A1),D1               | NextGZProc: chain to old GZ proc
        BEQ.B   SONY_GZPROC_RET                 | no previous proc, return 0
        MOVE.L  D1,A0                           | load previous GZ proc address
        JMP     (A0)                            | tail-call previous GZ proc

| GZ proc return -- delivers freed size to Memory Manager
SONY_GZPROC_RET:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.W  #0x4,SP                         | discard GZ proc parameter
        MOVE.L  D0,(SP)                         | return freed size to caller
        JMP     (A0)                            | return to Memory Manager

| -------------------------------------------------------
| TCdispose -- release the track cache buffer
|   D0 (out) -- number of bytes freed (0 if there was no buffer)
SONY_TCDISPOSE:
        CLR.L   -(SP)                           | push 0: assume no space freed
        MOVE.L  TCBuffer(A1),D0                 | TCBuffer: get track cache ptr
        BEQ.B   SONY_TCDISPOSE_DONE             | no buffer allocated, return 0
        MOVE.L  D0,A0                           | A0 = buffer pointer for _GetPtrSize
        _GetPtrSize                             | D0 = size of track cache buffer
        MOVE.L  D0,(SP)                         | save freed size on stack
        _DisposePtr                             | free the buffer
        CLR.L   TCBuffer(A1)                    | TCBuffer = nil
        CLR.B   TCInstalled(A1)                 | TCInstalled = false
SONY_TCDISPOSE_DONE:
        MOVE.L  (SP)+,D0                        | D0 = space freed (or 0)
        RTS                                     | return to GZ proc or ctlTrkCache

| -------------------------------------------------------
| DiskCtlErr / DiskDone -- I/O completion
|   D0 (in) -- result code
| Saves a non-zero result in DskErr, clears Active and completes the
| request through the IODone vector (JIODone). SONY_DCD_CTLEJECT is the
| HD20 eject (csCode 7): an HD20 is not ejected; DiskInPlace = 0 makes the
| VBL task (Check4Disk) post a disk-inserted event, so the volume is
| mounted again (MTN #272). This ROM returns controlErr for it.
SONY_DCD_CTLEJECT:
        CLR.B   DiskInPlace(A1,D1.W)            | DiskInPlace = 0 (the VBL task reposts the disk)
Sony_DiskCtlErr:
        MOVEQ.L #controlErr,D0                  | controlErr: unsupported control call
| Called by: SONY_CONTROL_NO_2, SONY_CTL_NOERR, E_SONY_STATUS_LOOP, SONY_DISKPRIME_ERR_4, SONY_DCDEXIT
Sony_DiskDone:
        TST     D0                              | error?
        BEQ.B   SONY_DISKDONE_1                 | no -> skip
        MOVE    D0,(DskErr).w                   | save the last error for debugging
SONY_DISKDONE_1:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        CLR.B   Active(A1)                      | Active = 0: allow the VBL task to run
        MOVE.L  (A1),A1                         | A1 = DCE pointer (DiskUnitPtr)
        MOVE.L  (JIODone).w,-(SP)               | push the IODone vector
        RTS                                     | and jump to IODone

| -------------------------------------------------------
| CtlTbl -- control call dispatch table: csCode, offset of the handler
| for HD20 drives (3-6), offset of the handler for floppy drives (1-2),
| both relative to CODES; a zero word ends the table. KillIO (1), the tag
| buffer (8) and the track cache (9) calls are tested in code.
CODES:
        .short  7                               | csCode 7: ejectCode: eject disk
        .short  SONY_DCD_CTLEJECT-CODES         | HD20 drives 3-6
        .short  SONY_CTL_EJECT-CODES            | floppy drives 1-2
        .short  6                               | csCode 6: formatCC: format disk
        .short  SONY_DCD_FORMAT-CODES           | HD20 drives 3-6
        .short  Sony_CtlFormat-CODES            | floppy drives 1-2
        .short  5                               | csCode 5: verifyCC: verify disk
        .short  SONY_DCD_VERIFY-CODES           | HD20 drives 3-6
        .short  Sony_CtlVerify-CODES            | floppy drives 1-2
        .short  21                              | csCode 21: iconCC: get drive icon
        .short  SONY_DCD_ICON-CODES             | HD20 drives 3-6 (icon from the HD20)
        .short  Sony_DiskCtlErr-CODES           | floppy drives 1-2: controlErr (no floppy icon in this ROM)
        .short  0                               | end of table

| -------------------------------------------------------
| DiskControl -- driver control entry: jump through the JControl vector.
E_Sony_Control:
        MOVE.L  (DiskVars_JControl).w,-(SP)     | push control vector
        RTS                                     | dispatch to jtControl

| -------------------------------------------------------
| jtControl -- control call dispatcher (JControl vector)
|   A0 (in) -- control parameter block
| KillIO (csCode 1), the tag buffer (8) and track cache (9) calls are
| handled first, without a drive number; the others need a valid,
| connected drive and go through CtlTbl (CODES): 5 Verify, 6 Format,
| 7 Eject, 21 drive icon (HD20 only). Calls that the Device Manager
| queues complete through DiskDone (IODone); KillIO is an immediate
| call and returns with RTS (not supported: result -1, MTN #272).
Sony_Control:
        MOVE    csCode(A0),D0                   | D0 = csCode
        CMPI    #killCode,D0                    | KillIO (csCode 1)?
        BNE.B   SONY_CTL_TAGBUF                 | no -> other calls
        MOVEQ.L #-0x1,D0                        | KillIO not supported: return -1
        RTS                                     | immediate call: return to the Device Manager

| ctlTagBuf (csCode 8) -- set (CSParam <> 0) or clear the separate tag
| buffer; drive number not needed.
SONY_CTL_TAGBUF:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        CMPI    #tgBuffCode,D0                  | csCode 8: set tag buffer?
        BNE.B   SONY_CTL_TRKCACHE               | no -> next
        MOVE.L  csParam(A0),TagBufPtr(A1)       | TagBufPtr = CSParam (pointer or 0)
        BRA     SONY_CTL_NOERR                  | always noErr

| ctlTrkCache (csCode 9) -- track cache control; drive number not needed.
|   CSParam+0: non-zero = enable, zero = disable the cache
|   CSParam+1: >0 = install (allocate), <0 = remove, 0 = neither
SONY_CTL_TRKCACHE:
        CMPI    #TCacheCC,D0                    | csCode 9: track cache control?
        BNE.B   SONY_CONTROL_NO_2               | no -> calls that need a drive
        ADDA    #csParam,A0                     | A0 -> CSParam
        MOVE.B  (A0)+,D1                        | D1 = enable flag
        MOVE.B  (A0)+,D0                        | D0 = install/remove flag
        BEQ.B   SONY_CONTROL_ERR                | neither -> just enable/disable
        BPL.B   SONY_CONTROL_CONT               | positive -> install a cache buffer
        BSR     SONY_TCDISPOSE                  | negative -> TCdispose: remove the buffer
        BRA.B   SONY_CONTROL_ERR                | and disable the cache

| ctlTCInst -- allocate the cache buffer unless there is one
SONY_CONTROL_CONT:
        TST.L   TCBuffer(A1)                    | TCBuffer: buffer already allocated?
        BNE.B   SONY_CONTROL_ERR                | yes -> keep it
        CMPI    #0x2,(MemTop).w                 | MemTop high word <= 2: RAM below 192K (128K Mac)?
        BLE.B   SONY_CONTROL_ERR                | yes -> no cache
        MOVE.L  #0x1890,D0                      | $1890 = 12 sectors * (12 + 512) bytes
        _NewPtrSysClear                         | allocate it in the system heap
        BNE.B   SONY_CONTROL_ERR                | no memory -> no cache
        MOVE.L  A0,TCBuffer(A1)                 | TCBuffer = new buffer
        CLR     TCDrive(A1)                     | TCDrive = 0: cache contents invalid
| ctlTCEnb -- TCInstalled = $FF if there is a buffer and enabling was asked
SONY_CONTROL_ERR:
        TST.L   TCBuffer(A1)                    | TCBuffer: any buffer?
        SNE.B   TCInstalled(A1)                 | TCInstalled = 0 if there is none
        BEQ.B   SONY_CONTROL_DONE               | no buffer -> done
        TST.B   D1                              | enable requested?
        SNE.B   TCInstalled(A1)                 | TCInstalled = $FF (on) or 0 (off)
SONY_CONTROL_DONE:
        BRA     SONY_CTL_NOERR                  | always noErr

| csCodes 5, 6, 7, 21 and unknown codes: check the drive number, then
| look the csCode up in CtlTbl
SONY_CONTROL_NO_2:
        MOVE    D0,D2                           | D2 = csCode
        BSR     Sony_CkDrvNum                   | CkDrvNum: check the drive number, set up A1/D1
        BNE     Sony_DiskDone                   | bad drive number -> return nsDrvErr
        TST.B   Installed(A1,D1.W)              | drive connected (Installed = 1)?
        BPL.B   SONY_CONTROL_OK                 | yes -> look the csCode up
        MOVEQ.L #noDriveErr,D0                  | noDriveErr: drive not connected
        BRA     Sony_DiskDone                   | complete the request

| scan CtlTbl for the csCode
SONY_CONTROL_OK:
        LEA.L   CODES(PC),A3                    | A3 = table base (offsets are relative to it)
        MOVE.L  A3,A4                           | A4 = scan pointer
SONY_CONTROL_NEXT_2:
        MOVE    (A4)+,D4                        | D4 = csCode of this entry
        BEQ     Sony_DiskCtlErr                 | end of table -> controlErr
        CMP     D4,D2                           | csCode of the request?
        BEQ.B   SONY_CONTROL_OK_2               | yes -> dispatch
        ADDQ.W  #0x4,A4                         | skip both handler offsets
        BRA.B   SONY_CONTROL_NEXT_2             | check the next entry

| use the HD20 offset (first) or the floppy offset (second)
SONY_CONTROL_OK_2:
        CMPI    #0x2,Drive(A1)                  | floppy drive (1-2)?
        BGT.B   SONY_CONTROL_CONT_2             | no, HD20 -> first offset
        ADDQ.W  #0x2,A4                         | floppy -> second offset
SONY_CONTROL_CONT_2:
        ADDA    (A4),A3                         | A3 = handler address (table base + offset)
        JMP     (A3)                            | go to the handler

| ctlSonyEjc (csCode 7, floppy) -- eject the disk. The drive is powered
| down at once; the interface stays selected for the eject pulse
| (Apple: "IODone is jumped to when the eject has been completed").
SONY_CTL_EJECT:
        BSR     SONY_INVALTRKCACHE              | InvalTrkCache: forget cached sectors of this drive
        MOVEQ.L #0x0,D0                         | immediate power-off
        BSR     Sony_PowerDown                  | PowerDown
        BSR     Sony_DiskSelect                 | DiskSelect: keep the interface enabled
        MOVE    #0x7D0,D0                       | wait 200 ms (2000 * 100 us)
        BSR     E_Sony_WakeUp                   | WakeUp (returns after the delay)
        MOVEQ.L #EjectHAdr,D0                   | EjectHAdr: control address CA1 = CA0 = 1, SEL = 0, CA2 = 1: eject
        BSR     Sony_AdrDisk                    | AdrDisk: address it
        TST.B   ph3H(A0)                        | LSTRB high: start the eject pulse
        TST.B   NewIntf(A1,D1.W)                | new-interface (800K) drive?
        BMI.B   SONY_NEWDRVEJECT                | yes -> short pulse, then wait for the disk to leave
        MOVE    EjectTime(A1),D0                | EjectTime: 0.75 s pulse for old (400K) drives
        BSR     E_Sony_WakeUp                   | WakeUp
        TST.B   ph3L(A0)                        | LSTRB low: end of the pulse
| CtlEjtOK -- ignore disk-in-place for the next EjectWait VBL calls
SONY_CTL_EJECTDONE:
        MOVE.B  EjectWait(A1),DiskInPlace(A1,D1.W) | DiskInPlace = EjectWait ($FC): counts up to 0 in the VBL task
SONY_CTL_NOERR:
        MOVEQ.L #0x0,D0                         | noErr
        BRA     Sony_DiskDone                   | complete the request

| NewDrvEject -- an 800K drive only needs a short LSTRB pulse, but its
| enable must stay asserted until 150 us after the disk has left the
| drive (Apple: "new drive needs /enb asserted until 150usec after
| /cstin goes away"; /CSTIN is the disk-in-place sense, DIPAdr).
SONY_NEWDRVEJECT:
        TST.B   ph3L(A0)                        | LSTRB low (Apple: "1us < assert LSTRB < 300ms")
        MOVEQ.L #0xF,D3                         | wait at most 16 * 100 ms
SONY_NEWDRVEJECT_LOOP:
        MOVE    #0x3E8,D0                       | 100 ms
        BSR     E_Sony_WakeUp                   | WakeUp
        MOVEQ.L #DIPAdr,D0                      | DIPAdr: disk-in-place sense (/CSTIN)
        BSR     Sony_AdrAndSense                | sense = 1 once the disk has left the drive
        DBMI    D3,SONY_NEWDRVEJECT_LOOP        | until the disk is out or the time is up
        MOVEQ.L #0xA,D0                         | 1 ms more
        BSR     E_Sony_WakeUp                   | WakeUp
        BRA.B   SONY_CTL_EJECTDONE              | DiskInPlace = EjectWait, noErr

| -------------------------------------------------------
| DiskStatus -- status entry; only csCode 8 (drive status) is supported:
| copies the first 22 bytes of the drive variables (track, write-protect,
| disk-in-place, installed, sides, drive queue element, two-sided format,
| new interface, soft error count) to CSParam (MTN #272, IM II-215).
E_Sony_Status:
        MOVEQ.L #statusErr,D0                   | statusErr: assume an unsupported csCode
        CMPI    #drvStsCode,csCode(A0)          | csCode 8 (drive status)?
        BNE     Sony_DiskDone                   | no -> return statusErr
        BSR.B   Sony_CkDrvNum                   | CkDrvNum: check the drive number
        BNE     Sony_DiskDone                   | bad drive number -> return the error
        LEA.L   csParam(A0),A0                  | A0 -> CSParam
        MOVEQ.L #0xB,D0                         | 11 words
        ADDA    D1,A1                           | A1 -> this drive's variables
E_SONY_STATUS_LOOP:
        MOVE    (A1)+,(A0)+                     | copy a word
        SUBQ.W  #0x1,D0                         | count it
        BGT.B   E_SONY_STATUS_LOOP              | until all 11 words are copied (D0 = 0 = noErr)
        BRA     Sony_DiskDone                   | complete the request

| -------------------------------------------------------
| CkDrvNum -- check the drive number of a request and set up for it
|   A0 (in) -- parameter block; ioVRefNum = drive number 1-6
|   D0 (out), CCR -- 0 (BEQ) or nsDrvErr (BNE); A1 = SonyVars, D1 = drive
| vars offset. Sets Active (keeps the VBL task out), saves the previous
| Drive in LastDrive and sets Drive.
Sony_CkDrvNum:
        MOVE.L  (SonyVars).w,A1                 | load SonyVars pointer
        ST.B    Active(A1)                      | Active = $FF: exclude the VBL task
        MOVE    ioVRefNum(A0),D0                | D0 = ioVRefNum = drive number
        BEQ.B   SONY_CKDRVNUM_ERR               | 0 -> nsDrvErr
        CMPI    #0x6,D0                         | above drive 6?
        BGT.B   SONY_CKDRVNUM_ERR               | yes -> nsDrvErr
        MOVE    Drive(A1),LastDrive(A1)         | LastDrive = previous Drive
        MOVE    D0,Drive(A1)                    | Drive = requested drive
        BSR     Sony_GetDrv1                    | GetDrv1: D1 = drive vars offset
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return (BEQ)

SONY_CKDRVNUM_ERR:
        MOVEQ.L #nsDrvErr,D0                    | nsDrvErr (-56): no such drive
        RTS                                     | return (BNE)

| DiskPrime -- driver prime entry: jump through the JDiskPrime vector.
E_Sony_Prime:
        MOVE.L  (DiskVars_JDiskPrime).w,-(SP)   | push DiskPrime vector
        RTS                                     | jump to implementation

| jtDiskPrime -- read or write (JDiskPrime vector)
|   A0 (in) -- I/O parameter block (ioTrap: $A002 read, $A003 write;
|              ioPosMode bit 6 = read-verify), A1 (in) -- DCE
| Checks the drive and the disk; at the first access to a disk it
| recalibrates, builds the speed table and reads the write protection.
| The blocks are then read or written track by track (GetTrack,
| CheckCache, ReSeek, OnTrack in Apple's SonyRWT.a).
Sony_DiskPrime:
        ORI     #0x100,SR                       | exclude VBL interrupts (IPL 1)
        MOVE    ioTrap(A0),D3                   | D3 = ioTrap ($A002 read, $A003 write)
        BTST    #0x6,(ioPosMode+1)(A0)          | read-verify mode? (ioPosMode bit 6, rdVerify)
        SNE.B   (DskVerify).w                   | note it in DskVerify
        BSR.B   Sony_CkDrvNum                   | CkDrvNum: check the drive number
        BNE     SONY_DISKPRIME_ERR_4            | bad drive number -> return the error
        MOVE    D3,Command(A1)                  | Command = I/O command (ioTrap)
| a connected drive?
        MOVEQ.L #noDriveErr,D0                  | noDriveErr (-64): assume no drive
        TST.B   Installed(A1,D1.W)              | Installed: 1 = connected, $FF = not
        BMI.B   SONY_DISKPRIME_ERR_4            | not connected -> return the error
        BSR     Sony_DiskSelect                 | DiskSelect: select the drive
| HD20 or floppy; for a floppy check disk-in-place (may have been ejected manually)
        CMPI    #0x2,Drive(A1)                  | HD20 (drive 3-6)?
        BGT     Sony_DCDPrime                   | yes -> HD20 read/write
        MOVEQ.L #DIPAdr,D0                      | DIPAdr: disk-in-place sense
        BSR     Sony_AdrAndSense                | sense = 0 when a disk is in place
        BPL.B   SONY_DISKPRIME_CONT             | disk in place ->
| no disk in the drive
        CLR.B   DiskInPlace(A1,D1.W)            | DiskInPlace = 0: no disk here
        TST.B   mtrOff(A0)                      | IWM motor off: cut /ENBL so the drive does not tick
        MOVEQ.L #offLinErr,D0                   | offLinErr (-65): no disk in the drive
        BRA.B   SONY_DISKPRIME_ERR_4            | return the error

| first access to this disk: power up, recalibrate, measure the speed
SONY_DISKPRIME_CONT:
        CMPI.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2: already clamped and recalibrated?
        BEQ.B   SONY_DISKPRIME_OK               | yes -> check write protection
        BSR     Sony_FastPower                  | FastPower: motor on (waits only for /READY of an 800K drive)
        BSR     E_Sony_Recal                    | Recal: seek to track 0 (also sets the IWM mode)
        BMI.B   SONY_DISKPRIME_ERR_2            | error -> immediate power-down
        BSR     E_Sony_MakeSpdTbl               | MakeSpdTbl: speed codes of the zones (400K drive)
        BNE.B   SONY_DISKPRIME_ERR_2            | error -> immediate power-down
        MOVEQ.L #WrProtAdr,D0                   | WrProtAdr: write-protect sense
        BSR     Sony_AdrAndSense                | sense = 0 when write-protected
        SPL.B   WriteProt(A1,D1.W)              | WriteProt = $FF for a write-protected disk
        MOVE.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2: recalibrated
        CLR.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt = 0: assume a one-sided format
| CkWrProt -- a write to a write-protected disk?
SONY_DISKPRIME_OK:
        BSR     Sony_CheckRead                  | CheckRead: is it a read?
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
| POffExit -- shared with the format and verify calls
SONY_DISKPRIME_POFFEXIT:
        MOVE    D0,-(SP)                        | save the result code
        MOVE    D2,D0                           | D0 = power-off delay
        BSR     Sony_PowerDown                  | PowerDown
        MOVE    (SP)+,D0                        | restore the result code
| DiskErr -- open interrupts and complete the request
SONY_DISKPRIME_ERR_4:
        ANDI    #-0x701,SR                      | open interrupts again (IPL 0)
        BRA     Sony_DiskDone                   | complete the request

| RWPower -- set the speed for the current track and power up
SONY_DISKPRIME_SKIP:
        MOVE    Track(A1,D1.W),D6               | D6 = current track
        BSR     Sony_SetSpeed                   | SetSpeed for it (400K drive)
        BSR     Sony_RWPowerUp                  | RWPowerUp: power up and wait
| GetTrack -- the next track to do: side/track, first sector, sector map
SONY_DISKPRIME_NEXT:
        MOVE.L  (A1),A2                         | A2 = DCE
        MOVE.L  dCtlQHead(A2),A0                | A0 = current request (dCtlQHead)
        MOVE.L  dCtlPosition(A2),D0             | D0 = dCtlPosition (byte position)
        MOVEQ.L #0x9,D7                         | 2^9 = 512 bytes per block
        LSR.L   D7,D0                           | D0 = block number on the disk
        MOVEQ.L #0x0,D4                         | D4 = 0: one-sided format
        TST.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt: two-sided disk?
        BEQ.B   SONY_DISKPRIME_SIDES            | no ->
        MOVEQ.L #0x1,D4                         | D4 = 1: two-sided format
SONY_DISKPRIME_SIDES:
        MOVEQ.L #0x64,D2                        | 100
        LSL     #0x3,D2                         | * 8 = 800 blocks
        LSL     D4,D2                           | 1600 blocks if two-sided
        CMP.L   D2,D0                           | block beyond the end of the disk?
        BLT.B   SONY_DISKPRIME_NO               | no -> find its speed zone
SONY_DISKPRIME_EMPTY:
        MOVEQ.L #paramErr,D0                    | paramErr (-50): bad position
SONY_DISKPRIME_ERR_5:
        BRA.B   SONY_DISKPRIME_ERR              | power down and return the error

| NxtClass -- find the speed zone of the block (D2 = first block of it)
SONY_DISKPRIME_NO:
        MOVEQ.L #0x7,D3                         | 7
        LSL     #0x4,D3                         | * 16 = 112 (the loop adds 16 first: 128 in zone 4)
        LSL     D4,D3                           | doubled for two-sided disks
        MOVEQ.L #0x10,D5                        | 16 more blocks per side in each lower zone
        LSL     D4,D5                           | doubled for two-sided disks
SONY_DISKPRIME_NEXT_2:
        ADD     D5,D3                           | D3 = blocks in this zone
        SUB.L   D3,D2                           | D2 = first block of this zone
        CMP.L   D2,D0                           | block in a lower zone?
        BLT.B   SONY_DISKPRIME_NEXT_2           | yes -> next zone outward
| NxtTrack -- find the track (cylinder) within the zone
        LSR     #0x4,D3                         | D3 = blocks per cylinder in this zone
        MOVEQ.L #-0x1,D5                        | D5 = track within the zone - 1
SONY_DISKPRIME_NEXT_3:
        ADD     D3,D2                           | D2 = first block of the next track
        ADDQ.W  #0x1,D5                         | next track
        CMP     D2,D0                           | block beyond this track?
        BGE.B   SONY_DISKPRIME_NEXT_3           | yes -> keep counting
        LSR     D4,D3                           | D3 = sectors per track in this zone
        MOVEQ.L #0xC,D6                         | 12
        SUB     D3,D6                           | - sectors per track = zone number
        LSL     #0x4,D6                         | * 16 = first track of this zone
        ADD     D6,D5                           | D5 = track number
        MOVE.L  D4,D6                           | D6 = side (1 for a two-sided disk)
        SUB     D3,D2                           | D2 = first block of side 1 of this cylinder
        CMP.L   D2,D0                           | block on side 1?
        BGE.B   SONY_DISKPRIME_OK_2             | yes ->
        SUB     D3,D2                           | D2 = first block of side 0
        MOVEQ.L #0x0,D6                         | side 0
SONY_DISKPRIME_OK_2:
        TST.B   D6                              | side 1?
        BEQ.B   SONY_DISKPRIME_NO_2             | no ->
        BSET    #0xB,D5                         | bit 11 of the side/track word = side 1
        TST.B   Sides(A1,D1.W)                  | Sides: two-sided drive?
        BNE.B   SONY_DISKPRIME_NO_2             | yes -> fine
        MOVEQ.L #twoSideErr,D0                  | twoSideErr (-78): two-sided disk in a one-sided drive
        BRA.B   SONY_DISKPRIME_ERR_5            | power down and return the error

| the sectors wanted on this track: first sector, count, bitmap
SONY_DISKPRIME_NO_2:
        MOVE    D5,SideTrack(A1)                | SideTrack = side/track wanted
        SUB     D2,D0                           | D0 = first sector wanted on this track
        SUB     D0,D3                           | D3 = sectors left on this track
        MOVE    D0,FirstSect(A1)                | FirstSect = first sector wanted
        MOVE.L  ioReqCount(A0),D5               | D5 = ioReqCount
        MOVE.L  ioActCount(A0),D2               | D2 = ioActCount (bytes done so far)
        SUB.L   D2,D5                           | bytes still to transfer
        LSR.L   D7,D5                           | / 512 = blocks still to transfer
        BEQ.B   SONY_DISKPRIME_EMPTY            | less than one block -> paramErr
        CMP     D5,D3                           | more blocks wanted than left on this track?
        SLT.B   D6                              | D6 = $00 if this is the last track to do
        BLE.B   SONY_DISKPRIME_CONT_3           | yes -> take the rest of the track
        MOVE    D5,D3                           | else only the blocks wanted
SONY_DISKPRIME_CONT_3:
        MOVEQ.L #0x0,D5                         | D5 = sector bitmap
        MOVE    D0,D4                           | D4 = first sector
        MOVE    D3,-(SP)                        | save the sector count
SONY_DISKPRIME_LOOP:
        BSet    D0,D5                           | one bit per sector wanted
        ADDQ.W  #0x1,D0                         | next sector
        SUBQ.W  #0x1,D3                         | count it
        BNE.B   SONY_DISKPRIME_LOOP             | until all sectors are marked
        MOVE    (SP)+,D3                        | restore the sector count
        MOVE.L  D5,SectMap(A1)                  | SectMap = sectors wanted on this track
        MOVE.L  ioBuffer(A0),A3                 | A3 = ioBuffer
        ADDA.L  D2,A3                           | + bytes already done
        MOVE.L  A3,DiskBuffer(A1)               | DiskBuffer = buffer address for the first sector
        LSR.L   D7,D2                           | blocks done so far
        MOVE    D2,FBlksDone(A1)                | FBlksDone (for the file tags)
        MOVE.B  RecalInit(A1),RecalCnt(A1)      | RecalCnt = RecalInit: recals allowed on this track
| CheckCache -- use the track cache: reads take cached sectors, writes
| invalidate the cached copies of the sectors written; reading into the
| cache (TCRdEnable) only for a synchronous call on its last track.
        CLR.B   TCRdEnable(A1)                  | TCRdEnable = 0: assume no reading into the cache
        BSR     Sony_CheckRead                  | CheckRead: is it a read?
        BEQ.B   SONY_DISKPRIME_CONT_4           | yes -> read through the cache
        BSR     Sony_CacheValid                 | CacheValid: cache valid for this drive/side/track?
        BNE.B   SONY_DISKPRIME_SKIP_2           | no -> go do the I/O
        MOVE.L  D5,D0                           | bitmap of the sectors being written
        NOT.L   D0                              | = sectors not being written
        AND.L   D0,TCSectMap(A1)                | TCSectMap: invalidate the sectors written
        BSR     Sony_TCRdEnbChk                 | TCRdEnbChk (the 7.1 driver no longer calls it here)
SONY_DISKPRIME_SKIP_2:
        BRA     E_Sony_ReSeek                   | go do the I/O

| readCache -- copy the wanted sectors that are in the cache
SONY_DISKPRIME_CONT_4:
        TST.B   (DskVerify).w                   | read-verify?
        BNE.B   SONY_DISKPRIME_SKIP_2           | yes -> never from the cache
        BSR     Sony_CacheValid                 | CacheValid?
        BNE     SONY_DISKPRIME_NO_4             | no -> set the cache up for this track
        MOVE.L  D5,D2                           | sectors wanted
        AND.L   TCSectMap(A1),D2                | and cached (TCSectMap)
        BEQ.B   SONY_DISKPRIME_EMPTY_2          | none -> go do the I/O
        MOVEQ.L #0x2,D7                         | 2
        ASL.L   #0x8,D7                         | * 256 = 512 bytes per sector
        MOVE    D4,D0                           | first sector wanted
        MULU    #0x20C,D0                       | * 524 = offset of its entry in the cache
        MOVE.L  TCBuffer(A1),A4                 | A4 = TCBuffer: track cache
        ADDA    D0,A4                           | A4 -> cache entry of the first sector
SONY_DISKPRIME_LOOP_2:
        BTst    D4,D2                           | sector wanted and cached?
        BEQ.B   SONY_DISKPRIME_SKIP_3           | no -> next sector
        BCLR    D4,D5                           | remove it from the sectors wanted
        MOVEM.L A0-A1,-(SP)                     | preserve A0/A1 over _BlockMove
        TST.L   TagBufPtr(A1)                   | TagBufPtr: separate tag buffer?
        BEQ.B   SONY_DISKPRIME_NO_3             | no -> tags go to TagData
        MOVE    D4,D0                           | current sector
        SUB     FirstSect(A1),D0                | - FirstSect = sector index on this track
        ADD     FBlksDone(A1),D0                | + FBlksDone = block index in the request
        MULU    #0xC,D0                         | * 12 = offset into the tag buffer
        MOVE.L  TagBufPtr(A1),A1                | A1 = tag buffer
        ADDA.L  D0,A1                           | A1 -> tags of this block
        BRA.B   SONY_DISKPRIME_CONT_5           | copy the tags

| no separate tag buffer: tags go to the file tags buffer in low memory
SONY_DISKPRIME_NO_3:
        LEA.L   (BufTgFNum).w,A1                | A1 -> TagData+2 (file tags in low memory)
SONY_DISKPRIME_CONT_5:
        MOVE.L  A4,A0                           | A0 -> cache entry: 12 tag bytes, 512 data bytes
        MOVE.L  (A0)+,(A1)+                     | copy the 12 tag bytes
        MOVE.L  (A0)+,(A1)+                     | tag bytes 5-8
        MOVE.L  (A0)+,(A1)+                     | tag bytes 9-12
        MOVE.L  A3,A1                           | A1 = user buffer
        MOVE.L  D7,D0                           | 512 bytes
        _BlockMove                              | copy the data
        MOVEM.L (SP)+,A0-A1                     | restore A0/A1
        ADDQ.W  #0x1,TCNumUsed(A1)              | TCNumUsed: count sectors taken from the cache
        ADD.L   D7,dCtlPosition(A2)             | dCtlPosition += 512
        ADD.L   D7,ioActCount(A0)               | ioActCount += 512
SONY_DISKPRIME_SKIP_3:
        ADDA.L  D7,A3                           | next block in the user buffer
        ADDA.L  D7,A4                           | next cache entry
        ADDA    #0xC,A4                         | (12 tag bytes per entry)
        ADDQ.W  #0x1,D4                         | next sector
        SUBQ.W  #0x1,D3                         | count it
        BNE.B   SONY_DISKPRIME_LOOP_2           | until all sectors of this track are checked
        MOVE.L  D5,SectMap(A1)                  | SectMap = sectors still wanted
        BNE.B   SONY_DISKPRIME_EMPTY_2          | some left -> read them
        MOVE.L  ioActCount(A0),D0               | ioActCount
        CMP.L   ioReqCount(A0),D0               | compared with ioReqCount
        BLT     SONY_DISKPRIME_NEXT             | more to do -> next track
        MOVEQ.L #0x0,D0                         | noErr
        BRA     SONY_DISKPRIME_ERR              | power down and return

| rc_Cont -- some sectors still to read from the disk
SONY_DISKPRIME_EMPTY_2:
        BSR.B   Sony_TCRdEnbChk                 | TCRdEnbChk
        BRA.B   E_Sony_ReSeek                   | go do the I/O

| rdCacheNV -- cache not valid: if reads into the cache are enabled, set
| it up for this drive and side/track
SONY_DISKPRIME_NO_4:
        BSR.B   Sony_TCRdEnbChk                 | TCRdEnbChk: reads into the cache enabled?
        BNE.B   E_Sony_ReSeek                   | no -> go do the I/O
        MOVE    Drive(A1),TCDrive(A1)           | TCDrive = this drive
        MOVE    SideTrack(A1),TCSideTrack(A1)   | TCSideTrack = this side/track
        CLR.L   TCSectMap(A1)                   | TCSectMap = 0: no sectors cached yet
        BRA.B   E_Sony_ReSeek                   | go do the I/O

| TCRdEnbChk -- TCRdEnable = $FF (BEQ) if the cache is installed and on,
| the call is synchronous and no sectors are needed on another track
| (D6 = 0); else TCRdEnable = 0 (BNE).
Sony_TCRdEnbChk:
        TST.B   TCInstalled(A1)                 | TCInstalled: cache installed and on?
        BEQ.B   SONY_TCRDENBCHK_OFF             | no ->
        BTST    #asyncTrpBit,Command(A1)        | asynchronous call (ioTrap bit 10)?
        BNE.B   SONY_TCRDENBCHK_SET             | yes -> no caching (NE)
        TST.B   D6                              | last track of the request?
SONY_TCRDENBCHK_SET:
        SEQ.B   TCRdEnable(A1)                  | TCRdEnable = $FF if so
        RTS                                     | return (BEQ = read into the cache)

| cache not installed
SONY_TCRDENBCHK_OFF:
        MOVEQ.L #0x1,D6                         | force NE
        BRA.B   SONY_TCRDENBCHK_SET             | TCRdEnable = 0

| CacheValid -- does the cache hold this drive and side/track?
|   D0 (out), CCR -- 0 (BEQ) if valid, -1 (BNE) if not
Sony_CacheValid:
        TST.B   TCInstalled(A1)                 | TCInstalled: cache installed and on?
        BEQ.B   SONY_CACHEVALID_NO              | no -> not valid
        MOVE    TCDrive(A1),D0                  | TCDrive
        BEQ.B   SONY_CACHEVALID_NO              | 0 -> not valid
        CMP     Drive(A1),D0                    | same drive?
        BNE.B   SONY_CACHEVALID_NO              | no -> not valid
        MOVE    SideTrack(A1),D0                | current side/track
        SUB     TCSideTrack(A1),D0              | - TCSideTrack
        BEQ.B   SONY_CACHEVALID_EXIT            | same -> valid (D0 = 0)
SONY_CACHEVALID_NO:
        MOVEQ.L #-0x1,D0                        | not valid
SONY_CACHEVALID_EXIT:
        RTS                                     | return

| ReSeek -- jump through the JReSeek vector (DiskPrime part III).
E_Sony_ReSeek:
        MOVE.L  (DiskVars_JReSeek).w,-(SP)      | push ReSeek vector address
        RTS                                     | dispatch to Sony_ReSeek

| -------------------------------------------------------
| jtReSeek -- seek to the track wanted (SideTrack); for a 400K drive check
| the zone's speed if CkDelta (4 min) has passed since the last check and
| correct the speed code by the 2% delta (at most BadSpdInit times).
Sony_ReSeek:
        MOVE.B  BadSpdInit(A1),BadSpdCnt(A1)    | BadSpdCnt = BadSpdInit: speed adjustments allowed
SONY_RESEEK_RETRY:
        MOVE    SideTrack(A1),D6                | D6 = side/track wanted
        BSR     E_Sony_Seek                     | Seek (sets the zone's speed)
        BMI.B   SONY_RESEEK_ERR                 | error -> recal
        MOVE.B  ReadErrInit(A1),ReadErrCnt(A1)  | ReadErrCnt = ReadErrInit
        LSR     #0x4,D6                         | D6 = zone (16 tracks per zone)
        LSL     #0x3,D6                         | * 8 = offset of the zone entry
        LEA.L   TrkSpeedTbl(A1,D1.W),A2         | A2 -> TrkSpeedTbl in the drive vars (+$1A)
        LEA.L   TSTblTicks(A2,D6.W),A2          | A2 -> TSTblTicks: time of the last check of this zone
        MOVE.L  (Ticks).w,D2                    | D2 = Ticks
        MOVE.L  (A2),D0                         | last check
        BEQ.B   SONY_RESEEK_CONT                | never checked -> check now
        SUB.L   D2,D0                           | last - now
        NEG.L   D0                              | = ticks since the last check
        CMP.L   CkDelta(A1),D0                  | CkDelta (+$44): time for a recheck?
        BLT.B   SONY_RESEEK_SKIP                | no -> on to the sectors
SONY_RESEEK_CONT:
        MOVE.L  D2,(A2)                         | remember the time of this check
        LEA.L   SONY_RESEEK_CONT_2(PC),A3       | A3 = return address for the measurement
        BRA     SONY_GETFREQ1                   | GetFreq1: measure the speed value (D4)

| D4 = speed value (11.4 * rpm); compare with the zone's limits
SONY_RESEEK_CONT_2:
        BMI.B   SONY_RESEEK_ERR                 | measurement failed -> recal
        MOVE    -(A2),D0                        | D0 = TSTblDelta: speed code change for 2% speed
        LEA.L   DT_Sony_SpeedCheckTbl(PC),A0    | A0 -> speed limits table
        LSR     #0x1,D6                         | zone * 4
        ADDA    D6,A0                           | A0 -> limits for this zone
        CMP     (A0)+,D4                        | too fast (speed value above the upper limit)?
        BGT.B   SONY_RESEEK_ADJUST              | yes -> lower the speed code by the delta
        NEG     D0                              | else D0 = -delta
        CMP     (A0),D4                         | too slow (at or below the lower limit)?
        BGT.B   SONY_RESEEK_SKIP                | no -> speed is fine
SONY_RESEEK_ADJUST:
        TST.B   NewIntf(A1,D1.W)                | new-interface (800K) drive?
        BMI.B   SONY_RESEEK_NO                  | yes -> it sets its own speed: no code change
        SUB     D0,-(A2)                        | TSTblCode -= delta (too fast) or += delta (too slow)
        CLR.L   TSTblTicks(A2)                  | force a recheck next time
SONY_RESEEK_NO:
        ADDQ.W  #0x1,SpdAdjCnt(A1,D1.W)         | SpdAdjCnt: count speed adjustments
        SUBQ.B  #0x1,BadSpdCnt(A1)              | BadSpdCnt: adjustments left?
        BPL.B   SONY_RESEEK_RETRY               | yes -> seek (sets the new speed) and check again
        MOVEQ.L #spdAdjErr,D0                   | spdAdjErr (-79): speed cannot be adjusted
SONY_RESEEK_ERR:
        BRA     SONY_RESEEK_ERR_6               | DoRecal: recal or give up

| OnTrack -- read the address fields passing by; read or write the sectors
| wanted, read the others into the track cache if enabled. RdAddr leaves
| interrupts off (IPL 3) and SCC bytes on the stack (poll data).
SONY_RESEEK_SKIP:
        MOVE.B  WrgSectInit(A1),WrgSectCnt(A1)  | WrgSectCnt = WrgSectInit: wrong sectors tolerated
SONY_RESEEK_RETRY_2:
        MOVE    D1,D6                           | OnTrack1: D6 = drive vars offset
        BSR     Sony_RdAddrSetup                | RdAddrSetup: read the next address field
        BMI     SONY_RESEEK_ERR_4               | error -> AdrDtaErr
        CMP     SideTrack(A1),D1                | right side and track?
        BNE     SONY_RESEEK_ERR_5               | no -> WrgSideTrk
        MOVE    D2,CurSector(A1)                | CurSector = sector number
        MOVE    D2,(TagData).w                  | TagData+1 = sector number (low byte; written by WrData)
        MOVE.L  SectMap(A1),D0                  | sectors wanted on this track
        BTST    D2,D0                           | is this one of them?
        BNE     SONY_RESEEK_OK_2                | yes -> read or write it
| not wanted: read it into the track cache if reads into the cache are enabled
        TST.B   TCRdEnable(A1)                  | TCRdEnable: reading into the cache?
        BEQ     SONY_RESEEK_SKIP_3              | no -> WrgSectAdr
        MOVE.L  TCSectMap(A1),D0                | TCSectMap: sectors already cached
        BTST    D2,D0                           | this one?
        BNE     SONY_RESEEK_SKIP_3              | yes -> WrgSectAdr
        LEA.L   Sony_RdData(PC),A0              | the driver's own RdData
        CMPA.L  (DiskVars_JRdData).w,A0         | still in the JRdData vector?
        SNE.B   TCRdEnable(A1)                  | no (patched, e.g. copy protection): no caching
        BNE     SONY_RESEEK_SKIP_3              | patched -> WrgSectAdr
        MOVE    D2,D1                           | D1 = sector number
        MULU    #0x20C,D2                       | * 524 = cache entry offset
        MOVE.L  TCBuffer(A1),A0                 | A0 = TCBuffer
        ADDA.L  D2,A0                           | A0 -> cache entry
        ADDA    #0xC,A0                         | A0 -> data part (after the 12 tag bytes)
        BSR     E_Sony_RdData                   | RdData into the cache
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        SPL.B   TCRdEnable(A1)                  | error: stop caching this track
        BMI.B   SONY_RESEEK_ERR_2               | error -> ignore it (may be a copy-protected sector)
        ADDQ.W  #0x1,TCNumCached(A1)            | TCNumCached: count sectors read into the cache
        MOVE    CurSector(A1),D2                | D2 = sector just read
        MOVE.L  TCBuffer(A1),A0                 | A0 = TCBuffer
        MOVE    D2,D1                           | sector number
        MULU    #0x20C,D1                       | * 524
        ADDA.L  D1,A0                           | A0 -> cache entry
        LEA.L   (BufTgFNum).w,A2                | A2 -> TagData+2: tags just read
        MOVE.L  (A2)+,(A0)+                     | copy the 12 tag bytes
        MOVE.L  (A2)+,(A0)+                     | tag bytes 5-8
        MOVE.L  (A2)+,(A0)+                     | tag bytes 9-12
        MOVE.L  TCSectMap(A1),D4                | TCSectMap
        BSET    D2,D4                           | + this sector
        MOVE.L  D4,TCSectMap(A1)                | update it
SONY_RESEEK_ERR_2:
        BSet    #0x7,(IntFlag).w                | interrupts to be opened for AppleTalk (bit 7 was 0)?
        BNE.B   SONY_RESEEK_POLLONLY            | no -> just poll data
        MOVE    SectTime(A1),D0                 | one sector time
        BSR     SONY_WAKESETUP                  | WakeSetUp: prime the timer
        BSR     Sony_EmptyPD                    | EmptyPD: process the poll data
        BSR     SONY_WAKEGO                     | WakeGo: wait, interrupts open
        BRA.B   SONY_RESEEK_CONT_4              | continue on the track

| no AppleTalk request: pass the poll data on and open interrupts
SONY_RESEEK_POLLONLY:
        BSR     Sony_EmptyPD                    | EmptyPD
        ANDI    #-0x701,SR                      | open interrupts
SONY_RESEEK_CONT_4:
        BRA     SONY_RESEEK_SKIP                | try for the sectors we want

| OTSetUp -- a sector wanted: note the format, set up buffer and tags
SONY_RESEEK_OK_2:
        CMPI.B  #0x1F,D3                        | format byte > $1F (bit 5, $20, set): two-sided format
        SGT.B   TwoSideFmt(A1,D6.W)             | TwoSideFmt (drive var +$12) = $FF for two-sided
        SUB     FirstSect(A1),D2                | - FirstSect = relative sector number
        MOVE    D2,D1                           | D1 = relative sector number
        ASL.L   #0x8,D1                         | * 256
        ADD.L   D1,D1                           | * 512
        ADD.L   DiskBuffer(A1),D1               | + DiskBuffer
        MOVE.L  D1,A0                           | A0 -> data buffer for this sector
        MOVE    FBlksDone(A1),D1                | blocks done so far
        ADD     D2,D1                           | + relative sector = relative block number
        MOVE    D1,D0                           | (keep it for writes)
        ADD     D1,D1                           | * 2
        ADD     D0,D1                           | * 3
        ASL     #0x2,D1                         | * 12 = offset in the tag buffer
        MOVE    D1,TagBufOS(A1)                 | TagBufOS: kept for a read
        BSR     Sony_CheckRead                  | CheckRead: read?
        BEQ.B   SONY_RESEEK_CONT_6              | yes -> OTRead
| OTWrite -- tags from the separate tag buffer, or the file block number
        MOVE.L  TagBufPtr(A1),D3                | TagBufPtr: separate tag buffer?
        BEQ.B   SONY_RESEEK_NO_2                | no -> file block number tag only
        MOVE.L  D3,A1                           | A1 = tag buffer
        ADDA    D1,A1                           | A1 -> tags of this block
        LEA.L   (BufTgFNum).w,A2                | A2 -> TagData+2
        MOVE.L  (A1)+,(A2)+                     | copy its 12 tag bytes
        MOVE.L  (A1)+,(A2)+                     | tag bytes 5-8
        MOVE.L  (A1)+,(A2)+                     | tag bytes 9-12
        BRA.B   SONY_RESEEK_CONT_5              | write the sector

| no separate tag buffer: only the file block number is set
SONY_RESEEK_NO_2:
        ADD     FirstFSeq(A1),D0                | + FirstFSeq = file block number
        MOVE    D0,(BufTgFBkNum).w              | TagData+8 = file block number
SONY_RESEEK_CONT_5:
        BSR     E_Sony_WrData                   | WrData
        BMI     SONY_RESEEK_ERR_4               | error -> AdrDtaErr
        BRA.B   SONY_RESEEK_SKIP_2              | sector done

| OTRead -- read the data field, copy the tags to the separate buffer
SONY_RESEEK_CONT_6:
        BSR     E_Sony_RdData                   | RdData
        BMI     SONY_RESEEK_ERR_4               | error -> AdrDtaErr
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  TagBufPtr(A1),D0                | TagBufPtr: separate tag buffer?
        BEQ.B   SONY_RESEEK_SKIP_2              | no -> done
        MOVE.L  D0,A0                           | A0 = tag buffer
        ADDA    TagBufOS(A1),A0                 | + TagBufOS
        LEA.L   (BufTgFNum).w,A2                | A2 -> TagData+2: tags just read
        MOVE.L  (A2)+,(A0)+                     | copy the 12 tag bytes
        MOVE.L  (A2)+,(A0)+                     | tag bytes 5-8
        MOVE.L  (A2)+,(A0)+                     | tag bytes 9-12
| GotSect -- sector done: update the map, position and byte count
SONY_RESEEK_SKIP_2:
        BSR     Sony_GetDrv1                    | GetDrv1: A1, D1
        MOVE.L  SectMap(A1),D4                  | sector map
        MOVE    CurSector(A1),D2                | D2 = sector just done
        BCLR    D2,D4                           | this sector is done
        MOVE.L  D4,SectMap(A1)                  | update the map
        MOVE.L  (A1),A2                         | A2 = DCE
        MOVE.L  dCtlQHead(A2),A0                | A0 = request (dCtlQHead)
        MOVEQ.L #0x2,D3                         | 2
        ASL.L   #0x8,D3                         | * 256 = 512
        ADD.L   D3,dCtlPosition(A2)             | dCtlPosition += 512
        ADD.L   D3,ioActCount(A0)               | ioActCount += 512
        MOVE.L  ioReqCount(A0),D3               | ioReqCount
        SUB.L   ioActCount(A0),D3               | D3 = 0 when the request is done
        BSET    #0x7,(IntFlag).w                | interrupts to be opened for AppleTalk?
        BEQ.B   SONY_RESEEK_NO_3                | yes -> wait a sector time with interrupts open
        BSR.B   Sony_CheckRead                  | CheckRead: read?
        BEQ.B   SONY_RESEEK_CONT_7              | yes -> continue (1-1 possible)
        TST.L   D4                              | last sector on this track?
        BNE.B   SONY_RESEEK_NO_3                | no -> wait a sector time (1-1 writes not possible)
        BSR     Sony_EmptyPD                    | EmptyPD
        MOVEQ.L #0x7,D0                         | 700 us
        BSR     E_Sony_WakeUp                   | WakeUp: let the erase head turn off after the last write
        BRA.B   SONY_RESEEK_DONE                | continue

| one sector time with interrupts open
SONY_RESEEK_NO_3:
        MOVE    SectTime(A1),D0                 | one sector time
        BSR     SONY_WAKESETUP                  | WakeSetUp
        BSR     Sony_EmptyPD                    | EmptyPD
        BSR     SONY_WAKEGO                     | WakeGo: wait, interrupts open
        BRA.B   SONY_RESEEK_DONE                | continue

| no wait: pass the poll data on and open interrupts
SONY_RESEEK_CONT_7:
        BSR     Sony_EmptyPD                    | EmptyPD
        ANDI    #-0x701,SR                      | open interrupts
| more sectors on this track, more tracks, or done
SONY_RESEEK_DONE:
        MOVE.L  D4,D0                           | sectors left on this track?
        BNE     SONY_RESEEK_SKIP                | yes -> OnTrack
        TST.L   D3                              | bytes left?
        BGT     SONY_DISKPRIME_NEXT             | yes -> GetTrack: next track
        TST.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt: two-sided disk?
        BEQ.B   SONY_RESEEK_ERR_3               | no -> done
        TST.B   Sides(A1,D1.W)                  | Sides: two-sided drive?
        BNE.B   SONY_RESEEK_ERR_3               | yes -> done
        MOVEQ.L #twoSideErr,D0                  | twoSideErr (-78): early warning
SONY_RESEEK_ERR_3:
        BRA     SONY_DISKPRIME_ERR              | DskRWOff: power down and complete

| CheckRead -- BEQ if the request is a read (low byte of Command =
| aRdCmd, from ioTrap $A002), BNE for a write
| Called by: SONY_DISKPRIME_OK, SONY_DISKPRIME_LOOP, SONY_RESEEK_OK_2, SONY_RESEEK_SKIP_2, SONY_RESEEK_ERR_4 (and 1 more)
Sony_CheckRead:
        CMPI.B  #aRdCmd,(Command+1)(A1)         | low byte of Command: aRdCmd (read)?
        RTS                                     | return

| -------------------------------------------------------
| EmptyPD -- pass the SCC bytes that the polling code pushed on the stack
| (poll data) to PollProc (the serial driver), or discard them if there
| is none, and return to the caller with the stack reset (PollStack).
| Preserves D0, D2-D3, A0 in SaveRegs; returns with A1 = SonyVars, D1.
Sony_EmptyPD:
        MOVE.L  (SP)+,A4                        | A4 = return address
        PEA.L   SONY_EMPTYPD_RESUME(PC)         | PollProc returns to SONY_EMPTYPD_RESUME
        MOVE.L  (PollProc).w,-(SP)              | PollProc installed?
        BEQ.B   SONY_EMPTYPD_NOPROC             | no -> throw the data away
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVEM.L D0/D2-D3/A0/A4,SaveRegs(A1)     | save D0, D2, D3, A0 and the return address
        RTS                                     | go to PollProc

| back from PollProc
SONY_EMPTYPD_RESUME:
        BSR     Sony_GetDrv1                    | GetDrv1
        MOVEM.L SaveRegs(A1),D0/D2-D3/A0/A4     | restore the registers
        JMP     (A4)                            | return

| no PollProc: discard the poll data
SONY_EMPTYPD_NOPROC:
        MOVE.L  (PollStack).w,SP                | reset the stack (discard poll data)
        BSR     Sony_GetDrv1                    | GetDrv1
        JMP     (A4)                            | return

| AdrDtaErr -- address or data field error: retry on this track (reads),
| recal (writes, they may be slightly off track) while recals are left
SONY_RESEEK_ERR_4:
        BSR.B   Sony_EmptyPD                    | EmptyPD
        ANDI    #-0x701,SR                      | open interrupts
        ADDQ.W  #0x1,DiskErrs(A1)               | DiskErrs: global soft error count
        ADDQ.W  #0x1,DriveErrs(A1,D1.W)         | DriveErrs (drive var +$14): drive soft error count
        TST.B   RecalCnt(A1)                    | last recal?
        BEQ.B   SONY_RESEEK_RETRY_3             | yes -> retry rather than fail
        BSR.B   Sony_CheckRead                  | CheckRead: write?
        BNE.B   SONY_RESEEK_ERR_6               | yes -> recal (may be slightly off track)
SONY_RESEEK_RETRY_3:
        SUBQ.B  #0x1,ReadErrCnt(A1)             | ReadErrCnt: errors left?
        BPL     SONY_RESEEK_SKIP                | yes -> try another
        BRA.B   SONY_RESEEK_ERR_6               | no -> recal

| WrgSectAdr -- not a sector we want: give one sector time back to the
| system (interrupts open) and look again
SONY_RESEEK_SKIP_3:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE    SectTime(A1),D0                 | one sector time
        BSR     SONY_WAKESETUP                  | WakeSetUp
        BSR.B   Sony_EmptyPD                    | EmptyPD
        BSR     SONY_WAKEGO                     | WakeGo
        ADDQ.L  #0x1,(RndSeed).w                | bump the random seed
        MOVEQ.L #sectNFErr,D0                   | sectNFErr (-81) in case we run out of recals
        SUBQ.B  #0x1,WrgSectCnt(A1)             | WrgSectCnt: enough wrong sectors?
        BMI.B   SONY_RESEEK_ERR_6               | yes -> recal
        BRA     SONY_RESEEK_RETRY_2             | OnTrack1: keep looking

| WrgSideTrk -- address field of another side or track
SONY_RESEEK_ERR_5:
        BSR.B   Sony_EmptyPD                    | EmptyPD
        MOVEQ.L #seekErr,D0                     | seekErr (-80) in case we run out of recals
| DoRecal -- recal to track 0, remeasure the speeds and seek again
SONY_RESEEK_ERR_6:
        ANDI    #-0x701,SR                      | open interrupts
        SUBQ.B  #0x1,RecalCnt(A1)               | RecalCnt: recal done already?
        BLE.B   SONY_RESEEK_ERR_7               | yes -> give up
        BSR     E_Sony_Recal                    | Recal
        BMI.B   SONY_RESEEK_ERR_7               | error -> give up
        BSR     E_Sony_MakeSpdTbl               | MakeSpdTbl
        BPL     E_Sony_ReSeek                   | ok -> seek again
SONY_RESEEK_ERR_7:
        BRA     SONY_RESEEK_ERR_3               | power down and return the error
| -------------------------------------------------------------------------
| DrvVarOS -- offset of each drive's variables in SonyVars, indexed with
| drive number * 2 (hence DRVVAROFS-2 in GetDrv1). The seventh entry
| serves the pass-thru probe in DiskOpen, which selects drive 7.
| -------------------------------------------------------------------------
DRVVAROFS:
        .short  Drive1                          | drive 1: internal floppy
        .short  Drive2                          | drive 2: external floppy
        .short  Drive3                          | drive 3: first HD20
        .short  Drive4                          | drive 4: second HD20
        .short  Drive5                          | drive 5: third HD20
        .short  Drive6                          | drive 6: fourth HD20
        .short  Drive6                          | drive 7 (pass-thru probe): drive 6's variables
| GetDrive, GetDrv1 -- set up the much-used registers
|   A0 (out) -- IWM base (GetDrive), A2 (out) -- VIA base (GetDrive)
|   A1 (out) -- SonyVars, D1 (out) -- offset of the current drive's vars
| Called by: E_SONY_OPEN_LOOP, Sony_AdrDisk, SONY_GOWAKEIT, Sony_Recal, Sony_Check4Disk (and 1 more)
Sony_GetDrive:
        MOVE.L  (IWM).w,A0                      | GetDrive: A0 = IWM base ($DFE1FF)
        MOVE.L  (VIA).w,A2                      | A2 = VIA base ($EFE1FE)
| GetDrv1 -- A1 = SonyVars, D1 = DrvVarOS entry of Drive
| Called by: Sony_CkDrvNum, SONY_RESEEK_SKIP_2, SONY_EMPTYPD_RESUME, SONY_EMPTYPD_NOPROC, Sony_SetSpeed (and 13 more)
Sony_GetDrv1:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE    Drive(A1),D1                    | D1 = Drive (1-7)
        ADD     D1,D1                           | * 2
        MOVE    DRVVAROFS-2(PC,D1.W),D1         | D1 = drive vars offset
        RTS                                     | return

| -------------------------------------------------------------------------
| AdrDisk -- address one of the 16 drive registers
|   D0 (in) -- register address, bits 0-3 = CA2, SEL, CA0, CA1 (Apple's
|              order CA1-CA0-SEL-CA2, bit 3 to bit 0)
| CA0-CA2 are the IWM phase lines PH0-PH2, SEL is VIA port A bit 5
| (vHeadSel). CA0 = CA1 = 1 must be true while SEL changes from 1 to 0
| (Apple's comment), hence both are set first.
Sony_AdrDisk:
        BSR.B   Sony_GetDrive                   | GetDrive: A0 = IWM, A2 = VIA, A1, D1
        TST.B   ph0H(A0)                        | CA0 high (ph0H)
        TST.B   ph1H(A0)                        | CA1 high (ph1H)
        LSR.B   #0x1,D0                         | bit 0: CA2
        BCC.B   SONY_ADRDISK_CONT               | 0 ->
        TST.B   ph2H(A0)                        | CA2 high (ph2H)
        BRA.B   SONY_ADRDISK_CONT_2             | ->

SONY_ADRDISK_CONT:
        TST.B   ph2L(A0)                        | CA2 low (ph2L)
SONY_ADRDISK_CONT_2:
        LSR.B   #0x1,D0                         | bit 1: SEL
        BCC.B   SONY_ADRDISK_CONT_3             | 0 ->
        BSET    #vHeadSel,vBufD(A2)             | SEL high: VIA port A bit 5
        BRA.B   SONY_ADRDISK_SKIP               | ->

SONY_ADRDISK_CONT_3:
        BCLR    #vHeadSel,vBufD(A2)             | SEL low
SONY_ADRDISK_SKIP:
        LSR.B   #0x1,D0                         | bit 2: CA0
        BCS.B   SONY_ADRDISK_CONT_4             | 1 -> leave it high
        TST.B   (A0)                            | CA0 low (ph0L)
SONY_ADRDISK_CONT_4:
        LSR.B   #0x1,D0                         | bit 3: CA1
        BCS.B   SONY_ADRDISK_CONT_5             | 1 -> leave it high
        TST.B   ph1L(A0)                        | CA1 low (ph1L)
SONY_ADRDISK_CONT_5:
        RTS                                     | return

| AdrAndSense / Sense -- read the sense line of a drive register
|   D0 (in)  -- register address (AdrAndSense only)
|   D0 (out) -- IWM status register: bit 7 = SENSE input (BMI = 1), bit 5
|               = a drive enable is active, bits 0-4 = mode register
| The status register is read with L7 = 0, L6 = 1 (Q6H, then Q7L).
Sony_AdrAndSense:
        BSR.B   Sony_AdrDisk                    | AdrAndSense: address the register
Sony_Sense:
        MOVE    SR,-(SP)                        | Sense: save the interrupt level
        ORI     #0x300,SR                       | no interrupts
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVE.B  q7L(A0),D0                      | Q7L (L7 = 0): read the status register (bit 7 = SENSE)
        TST.B   q6L(A0)                         | Q6L: L6 = 0, back to read mode (data register)
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST.B   D0                              | N = sense line
        RTS                                     | return

| AdrAndStrb / Pulse -- pulse LSTRB (phase line PH3) to perform a drive
| control function: the drive takes CA2 as the value for the control
| register addressed by CA1, CA0 and SEL
|   D0 (in) -- control register address (AdrAndStrb only)
Sony_AdrAndStrb:
        BSR.B   Sony_AdrDisk                    | AdrAndStrb: address the register
Sony_Pulse:
        MOVE    SR,-(SP)                        | Pulse: save the interrupt level
        ORI     #0x300,SR                       | no interrupts
        TST.B   ph3H(A0)                        | ph3H: LSTRB high
        NOP                                     | (pulse width)
        NOP                                     | (pulse width)
        TST.B   ph3L(A0)                        | ph3L: LSTRB low
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return

| CkDCDExist -- is an HD20 connected at the selected position?
| An HD20 shows /DrvExst = 1 and Sides = 1 (unlike a floppy drive) and
| asserts its /Exist line (register address 5, dcdExist).
|   D0 (out) -- MI: no HD20; PL: HD20 present (D0 = status byte)
Sony_CkDCDExist:
        MOVEQ.L #DrvExstAdr,D0                  | DrvExstAdr (13)
        BSR.B   Sony_AdrAndSense                | sense = 0: a floppy drive is connected
        BPL.B   SONY_CKDCDEXIST_NONE            | floppy (or nothing) -> no HD20
        TST.B   (A0)                            | CA0 low: register 9 (SidesAdr)
        BSR.B   Sony_Sense                      | sense
        BPL.B   SONY_CKDCDEXIST_NONE            | sense = 0 -> no HD20
        TST.B   ph0H(A0)                        | CA0 high,
        TST.B   ph1L(A0)                        | CA1 low: register 5 (dcdExist)
        BSR.B   Sony_Sense                      | sense: 0 = HD20 present
        BRA.B   SONY_CKDCDEXIST_EXIT            | return its status

SONY_CKDCDEXIST_NONE:
        MOVEQ.L #-0x1,D0                        | no HD20: D0 = -1 (MI)
SONY_CKDCDEXIST_EXIT:
        RTS                                     | return

| -------------------------------------------------------
| SetSpeed -- set the speed for a track (400K drives: speed code through
| the PWM bytes of the sound buffer; new-interface drives regulate their
| speed themselves and get code 0)
|   D6 (in) -- track number
| Looks up the zone's speed code in TrkSpeedTbl, clamps it to [0, $1B8],
| adds the time the speed change takes to Wait and programs the PWM
| bytes (SONY_SETSPEED_CONT_3).
Sony_SetSpeed:
        BSR     Sony_GetDrv1                    | A1=SonyVars, D1=drive offset
        MOVE    D6,D2                           | D2 = target track
        LSR     #0x4,D2                         | zone index (track / 16)
        LSL     #0x3,D2                         | zone * 8 (table stride)
        ADD     D1,D2                           | per-drive zone table offset
        MOVE    TrkSpeedTbl(A1,D2.W),D2         | D2 = TSTblCode: speed code of the zone
        TST.B   NewIntf(A1,D1.W)                | NewIntf: new-interface (800K) drive?
        BMI.B   SONY_SETSPEED_NO                | yes -> speed code 0 (the drive sets its own speed)
        TST     D2                              | negative?
        BPL.B   SONY_SETSPEED_OK                | no ->
SONY_SETSPEED_NO:
        MOVEQ.L #0x0,D2                         | clamp to 0
SONY_SETSPEED_OK:
        CMPI    #0x1B8,D2                       | above the highest speed code $1B8?
        BLE.B   SONY_SETSPEED_OK_2              | no ->
        MOVE    #0x1B8,D2                       | clamp to $1B8
SONY_SETSPEED_OK_2:
        MOVE    (PWMValue).w,D0                 | D0 = current speed code
        BPL.B   SONY_SETSPEED_CONT              | valid -> delay from the size of the change
        MOVE    PwrOnTime(A1),D0                | none yet (PWMValue = $FFFF from boot): power-on time
        BRA.B   SONY_SETSPEED_NO_2              | ->

| delay = |change| * 32 * 100 us, at least SpdChgTime (150 ms)
SONY_SETSPEED_CONT:
        SUB     D2,D0                           | D0 = old - new code
        BEQ     Sony_GetDrv1                    | no change -> return
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
| SONY_SETSPEED_CONT_3 -- store the speed code D2 in PWMValue and fill the
| 370 PWM bytes of the sound buffer at PWMBuf1 and at PWMBuf2 (MPW
| SysEqu.a: "PWM buffer 1 (or 2 if sound)") -- every second byte, the PWM
| bytes being the low bytes of the sound buffer words (HardwareEqu.a:
| "PWM bytes are low bytes"). The values are states of a 6-bit linear
| feedback shift register: q = ($1B8 - code) / 10 steps from $1E give two
| neighbouring states, and of each group of 10 bytes, r (the remainder)
| get the later state and the others the earlier one; so the speed
| hardware evidently counts in that register sequence (an inference: no
| document here describes the PWM counter). Called with a given code by
| GetFreq too (Apple's SonyUtil.a lists SetSpeed and SetASpeed).
SONY_SETSPEED_CONT_3:
        MOVE    D2,(PWMValue).w                 | PWMValue = new speed code
        MOVEM.L D3-D6/A2,-(SP)                  | save registers
        SUBI    #0x1B8,D2                       | code - $1B8
        NEG     D2                              | D2 = $1B8 - code (0-440)
        EXT.L   D2                              | (high word 0 for DIVU)
        DIVU    #0xA,D2                         | D2.w = q = / 10, D2.hi = r = remainder
        MOVEQ.L #0x1E,D0                        | D0 = $1E: start state
SONY_SETSPEED_LFSR:
        MOVE.B  D0,D1                           | D1 = state before this step
        MOVE.B  D0,D3                           | D3 = feedback calculation
        LSR.B   #0x1,D0                         | shift right
        EOR.B   D0,D3                           | bit 0 = old bit 0 XOR old bit 1
        LSR.B   #0x1,D3                         | into the carry
        BCC.B   SONY_SETSPEED_SKIP              | 0 ->
        BSET    #0x5,D0                         | 1 -> into bit 5
SONY_SETSPEED_SKIP:
        DBF     D2,SONY_SETSPEED_LFSR           | q + 1 steps: D1 = state q, D0 = state q + 1
        SWAP    D2                              | D2 = r (0-9)
        MOVE.B  SONY_SETSPEED_CONT_6(PC,D2.W),D5 | D5 = pattern word for r: table bytes r and r + 1
        ASL     #0x8,D5                         | (high byte)
        MOVE.B  SONY_SETSPEED_CONT_7(PC,D2.W),D5 | (low byte)
        MOVEQ.L #0x24,D3                        | 37 groups of 10 bytes = 370
        MOVE.L  (PWMBuf1).w,A0                  | A0 = PWM bytes of buffer 1
        MOVE.L  (PWMBuf2).w,A2                  | A2 = PWM bytes of buffer 2
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
        DBF     D2,SONY_SETSPEED_LOOP_3         | 10 bytes of the group
        DBF     D3,SONY_SETSPEED_LOOP_2         | 37 groups = 370 bytes
        MOVEM.L (SP)+,D3-D6/A2                  | restore registers
        BRA     Sony_GetDrv1                    | GetDrv1 and return

| Pattern words, read at byte offset r (0-9) as (byte r, byte r + 1): the
| top 10 bits hold r one bits, spread out (r = 1: $2021, 5: $AAB5, 9: $FF40)
SONY_SETSPEED_CONT_6:
        .byte   0x00                            | byte 0
SONY_SETSPEED_CONT_7:
        .byte   0x20,0x21,0x24,0x94,0xAA,0xB5   | bytes 1-6
        .byte   0xB7,0x7B,0xFF,0x40,0x00        | bytes 7-11 (r = 9 uses bytes 9, 10)

| -------------------------------------------------------------------------
| Seek -- seek to a track
|   D6.W (in) -- track (bit 11 = side 1; cleared here)
|   D0 (out)  -- result: track number, or a negative error code
| Sets the speed for the target zone first. Returns to one level above
| the caller while waiting (A6 = return address).
| -------------------------------------------------------------------------
E_Sony_Seek:
        BCLR    #0xB,D6                         | clear the side bit
        BSR     Sony_SetSpeed                   | SetSpeed for the target zone
        MOVE.L  (DiskVars_JSeek).w,-(SP)        | Seek1: push the JSeek vector
        RTS                                     | and jump through it

| jtSeek (JSeek vector): one step at a time, each with its direction set
| and the /STEP handshake checked; an unknown track (negative Track)
| means a recal first.
Sony_Seek:
        MOVE.L  (SP)+,A6                        | A6 = return address
        BSR     Sony_GetDrv1                    | GetDrv1
        MOVE    Track(A1,D1.W),D7               | D7 = current track
        BPL.B   SEEK_2                          | valid ->
| track unknown: recal first
        BSR     E_Sony_Recal                    | Recal
        MOVE    D0,D7                           | D7 = result (track 0 or error)
        BRA.B   SONY_SEEKEND                    | SeekEnd (no further step after a recal)

SEEK_2:
        CMP     D6,D7                           | already on the target track?
        BEQ.B   SONY_SEEKEND1                   | yes -> just wait out any speed change
| SeekLp -- set the direction for one step
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
        BSR     Sony_AdrAndStrb                 | set the step direction (restores D1 = drive vars offset)
        MOVE    D7,Track(A1,D1.W)               | Track = new track
        MOVEQ.L #StepLAdr,D0                    | StepLAdr: /STEP sense
        BSR     Sony_AdrAndSense                | /STEP high (1) = no step in progress
        BMI.B   SONY_SEEK_CONT_3                | ready -> step
        MOVEQ.L #cantStepErr,D7                 | cantStepErr (-75): drive will not step
        BRA.B   SONY_SEEKEND                    | store it as the track

SONY_SEEK_CONT_3:
        BSR     Sony_Pulse                      | LSTRB pulse at StepLAdr (CA2 = 0): step, /STEP goes low
        BSR.B   SONY_WAIT100                    | Wait100: wait for the step to finish
        BRA.B   SONY_SEEK_CONT                  | next step

| SeekEnd -- store the track; head settle time (400K) or /READY (800K)
SONY_SEEKEND:
        BSR     Sony_GetDrv1                    | GetDrv1: A1, D1
        MOVE    D7,Track(A1,D1.W)               | Track = result
        MOVE    HeadSettle(A1),D0               | HeadSettle: 30 ms head settle time (400K drive)
        MOVEQ.L #0x5,D2                         | first wait 500 us (new drives)
        BSR     SONY_WAITREADY                  | waitReady
| SeekEnd1 -- wait out any speed change (Wait; /READY for 800K drives)
SONY_SEEKEND1:
        MOVE    Wait(A1),D0                     | Wait: speed change or power-on time still to go
        MOVEQ.L #0x0,D2                         | no first wait
        BSR     SONY_WAITREADY                  | waitReady
        MOVE    D7,D0                           | D0 = result
        JMP     (A6)                            | return

| -------------------------------------------------------
| Wait100 -- after a step pulse: old drives wait SeekTime (12 ms), new
| drives poll /STEP until it is high again (at most 81 times)
SONY_WAIT100:
        MOVE    SeekTime(A1),D0                 | SeekTime: 12 ms
        BSR.B   SONY_CHECKNEW                   | CheckNew: old drive -> WakeUp for D0 and return
        MOVEQ.L #0x50,D5                        | poll count
SONY_WAIT100_LOOP:
        MOVEQ.L #StepLAdr,D0                    | StepLAdr
        BSR     Sony_AdrAndSense                | sense
        DBMI    D5,SONY_WAIT100_LOOP            | until /STEP is high again
        RTS                                     | return

| -------------------------------------------------------
| CheckNew -- for a new-interface drive return; for an old drive return to
| the caller's caller after waiting D0 * 100 us (WakeUp)
SONY_CHECKNEW:
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BPL.B   SONY_CHECKNEW_WAIT              | no -> wait
        RTS                                     | yes: return

| old drive: drop our caller's return address and wait
SONY_CHECKNEW_WAIT:
        ADDQ.W  #0x4,SP                         | drop our caller's return address
        TST     D0                              | any time to wait?
        BEQ.B   SONY_CHECKNEW_EXIT              | no -> return
        BRA.B   E_Sony_WakeUp                   | WakeUp

| no wait
SONY_CHECKNEW_EXIT:
        RTS                                     | return

| -------------------------------------------------------
| waitReady -- old drive: wait D0 (CheckNew); new drive: wait D2 * 100 us,
| then poll /READY every 1 ms, for at most 1 s; clears Wait
SONY_WAITREADY:
        BSR.B   SONY_CHECKNEW                   | CheckNew: old drive -> just wait D0
        MOVE.L  (SP)+,A4                        | A4 = return address
        MOVE    #0x3E8,D5                       | at most 1000 * 1 ms
        MOVE    D2,D0                           | first wait
        BEQ.B   SONY_WAITREADY_SENSE            | none -> check at once
SONY_WAITREADY_LOOP:
        BSR.B   E_Sony_WakeUp                   | WakeUp
SONY_WAITREADY_SENSE:
        MOVEQ.L #ReadyAdr,D0                    | ReadyAdr: /READY sense
        BSR     Sony_AdrAndSense                | sense = 0 when ready
        BPL.B   SONY_WAITREADY_DONE             | ready ->
        MOVEQ.L #0xA,D0                         | then check every 1 ms
        DBF     D5,SONY_WAITREADY_LOOP          | (on timeout go on anyway)
SONY_WAITREADY_DONE:
        CLR     Wait(A1)                        | Wait = 0: no extra wait time
        JMP     (A4)                            | return

| WakeUp -- jump through the JWakeUp vector
| Called by: SONY_CTL_EJECT, SONY_NEWDRVEJECT_LOOP, Sony_DCDReset, SONY_RESEEK_SKIP_2, SONY_CHECKNEW_WAIT (and 6 more)
E_Sony_WakeUp:
        MOVE.L  (DiskVars_JWakeUp).w,-(SP)      | push the JWakeUp vector
        RTS                                     | and jump through it

| -------------------------------------------------------------------------
| jtWakeUp -- wait D0 * 100 us (Time Manager), then continue at the caller's
| return address; meanwhile the caller's caller gets control back with
| D0 = 0 (the driver is asynchronous). Wait is reduced by D0 (WakeSetUp).
|   D0 (in) -- number of 100-us intervals (< 65536); D3-D7, A3-A6 are
|              preserved (SaveRegs)
| In this version the timer is primed first (WakeSetUp) and the caller's
| state saved afterwards (WakeGo); Apple's C97 (1986) reversed this.
Sony_WakeUp:
        BSR.B   SONY_WAKESETUP                  | WakeSetUp: prime the Time Manager element
| WakeGo -- save the continuation, open interrupts, return to the caller's caller
SONY_WAKEGO:
        MOVE.L  (SP)+,(DskRtnAdr).w             | DskRtnAdr = continuation (our caller)
        MOVEQ.L #0x0,D0                         | D0 = 0: noErr for the caller's caller
        MOVEM.L D3-D7/A3-A6,SaveRegs(A1)        | save the caller's registers in SaveRegs
        ANDI    #-0x701,SR                      | open VIA interrupts
        RTS                                     | return to the caller's caller

| -------------------------------------------------------------------------
| WakeSetUp -- Wait -= D0 (pinned at 0); prime the Time Manager element
| TimeQEl for D0 * 100 us (at least 1 ms) with GoWakeIt as its routine
SONY_WAKESETUP:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        SUB     D0,Wait(A1)                     | Wait -= D0
        BGT.B   SONY_WAKESETUP_1                | still positive ->
        CLR     Wait(A1)                        | pin it at 0
SONY_WAKESETUP_1:
        LEA.L   TimeQEl(A1),A0                  | A0 -> TimeQEl
        LEA.L   SONY_GOWAKEIT(PC),A1            | GoWakeIt
        MOVE.L  A1,0x6(A0)                      | tmAddr = GoWakeIt
        ANDI.L  #0xFFFF,D0                      | clear the high word of D0
        CMPI    #0xA,D0                         | at least 10 * 100 us?
        BCC.B   SONY_WAKESETUP_2                | yes ->
        MOVEQ.L #0xA,D0                         | else 1 ms
SONY_WAKESETUP_2:
        DIVU    #0xA,D0                         | / 10 = milliseconds
        EXT.L   D0                              | PrimeTime takes a long count
        MOVE.L  (0x568).w,A1                    | A1 = jPrimeTime vector
        JSR     (A1)                            | PrimeTime (A0 = TimeQEl)
        BSR     Sony_GetDrv1                    | GetDrv1: restore A1, D1
        RTS                                     | return

| GoWakeIt -- Time Manager routine of TimeQEl: restore the saved registers
| and call the continuation (DskRtn) with D0 = 0
| (Apple: "D0 = for RWT-MakeSpdTbl new intf path")
SONY_GOWAKEIT:
        MOVEM.L D0-D7/A0-A6,-(SP)               | save all registers
        BSR     Sony_GetDrive                   | GetDrive
        MOVEM.L SaveRegs(A1),D3-D7/A3-A6        | the registers saved by WakeGo
        MOVEQ.L #0x0,D0                         | D0 = 0
        BSR     SONY_DSKRTN                     | DskRtn: call the routine at DskRtnAdr
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore the registers
        RTS                                     | return to the Time Manager

| -------------------------------------------------------
| InvalTrkCache -- invalidate the track cache if it holds data of the
| current drive (TCDrive = Drive)
SONY_INVALTRKCACHE:
        MOVE    TCDrive(A1),D0                  | D0 = TCDrive
        CMP     Drive(A1),D0                    | this drive?
        BNE.B   SONY_INVALTRKCACHE_EXIT         | no ->
        CLR     TCDrive(A1)                     | TCDrive = 0: cache invalid
SONY_INVALTRKCACHE_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
E_Sony_Recal:
        MOVE.L  (DiskVars_JRecal).w,-(SP)       | Recal: push the JRecal vector
        RTS                                     | and jump through it

| jtRecal -- set the IWM mode if needed (Apple later split this out as
| SetIWMMode), power up, step out to track 0. Track = 0 or the error.
| Returns one level above the caller while waiting (A5 = return address).
Sony_Recal:
        MOVE.L  (SP)+,A5                        | A5 = return address
        BSR     Sony_GetDrive                   | GetDrive
        BSR.B   SONY_INVALTRKCACHE              | InvalTrkCache
        MOVEQ.L #0x3F,D1                        | status bits 0-5: mode bits and "enable active"
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVE.B  q7L(A0),D0                      | Q7L: read the status register
        TST.B   q6L(A0)                         | Q6L: back to read mode
        AND.B   D1,D0                           | bits 0-5
        CMP.B   D1,D0                           | mode $1F and a drive enabled?
        BEQ.B   SONY_RECAL_SKIP                 | yes -> IWM set up and drive powered: step
| SetIWMMode: the mode register is written with Motor-On = 0 and read back
| in the status register; give up after about a second (the timeout exit
| stores initIWMErr with D1 = $1F as drive offset: odd address, address error)
        MOVEQ.L #0x2,D2                         | 2
        SWAP    D2                              | D2 = $20000 loops, about one second (OneSecConst)
SONY_RECAL_RETRY:
        MOVEQ.L #0x1F,D1                        | mode $1F: latch, async, no timer, fast, 8 MHz
        MOVEQ.L #initIWMErr,D0                  | initIWMErr (-77): assume a timeout
        SUBQ.L  #0x1,D2                         | count the loop
        BMI.B   SONY_RECAL_ERR_2                | timeout -> error
        TST.B   mtrOff(A0)                      | mtrOff: Motor-On = 0 (needed to write the mode)
        TST.B   q6H(A0)                         | Q6H: L6 = 1 (sense state)
        MOVE.B  q7L(A0),D0                      | Q7L: read the status register
        BTST    #0x5,D0                         | a drive enable still active (status bit 5)?
        BNE.B   SONY_RECAL_RETRY                | yes -> wait for it to go off
        AND.B   D1,D0                           | mode bits 0-4
        CMP.B   D1,D0                           | mode $1F set?
        BEQ.B   SONY_RECAL_OK                   | yes -> done
        MOVE.B  D1,q7H(A0)                      | Q7H (L7 = L6 = 1, motor off): write the mode register = $1F
        TST.B   q7L(A0)                         | Q7L: back to the sense state (status register)
        BRA.B   SONY_RECAL_RETRY                | read it back

| mode set: back to read mode, power the drive up again
SONY_RECAL_OK:
        TST.B   q6L(A0)                         | Q6L: back to read mode
        BSR.B   Sony_RWPowerUp                  | RWPowerUp: re-enable and power up the drive
| step out until /TK0, at most 80 steps (12 ms each, 6 ms for 800K drives)
SONY_RECAL_SKIP:
        MOVEQ.L #0x50,D7                        | at most 80 steps
SONY_RECAL_CONT:
        MOVE    SeekTime(A1),D0                 | SeekTime: 12 ms
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BPL.B   SONY_RECAL_CONT_2               | no -> full time
        LSR     #0x1,D0                         | yes -> 6 ms
SONY_RECAL_CONT_2:
        BSR     E_Sony_WakeUp                   | WakeUp
        MOVEQ.L #Tk0Adr,D0                      | Tk0Adr: track 0 sense
        BSR     Sony_AdrAndSense                | sense = 0 at track 0
        BPL.B   SONY_RECAL_DONE                 | there -> done
        MOVEQ.L #DirHAdr,D0                     | DirHAdr: direction control, CA2 = 1: out (toward track 0)
        BSR     Sony_AdrAndStrb                 | set the direction
        MOVEQ.L #StepLAdr,D0                    | StepLAdr: /STEP sense
        BSR     Sony_AdrAndSense                | /STEP high (1) = ready to step
        BPL.B   SONY_RECAL_ERR                  | not ready -> cantStepErr
        MOVEQ.L #tk0BadErr,D0                   | tk0BadErr (-76) if we run out of steps
        SUBQ.W  #0x1,D7                         | count the step
        BEQ.B   SONY_RECAL_ERR_2                | 80 steps without track 0 -> error
        BSR     Sony_Pulse                      | LSTRB pulse at StepLAdr: step
        BRA.B   SONY_RECAL_CONT                 | again

| at track 0
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
| -------------------------------------------------------------------------
Sony_PowerDown:
        BSR     Sony_GetDrv1                    | GetDrv1
        MOVE    D0,TimeOut(A1)                  | TimeOut = D0
        BEQ.B   SONY_POWERDOWN_NOW              | 0 -> power down now
        MOVE    Drive(A1),TimeOutDrive(A1)      | TimeOutDrive = this drive
        RTS                                     | return

| power down now
SONY_POWERDOWN_NOW:
        MOVEQ.L #MtrOffAdr,D0                   | MtrOffAdr: motor control, CA2 = 1: motor off
        BSR     Sony_AdrAndStrb                 | AdrAndStrb
        TST.B   mtrOff(A0)                      | mtrOff: also cut the drive enable /ENBLx
        RTS                                     | return

| -------------------------------------------------------
| FastPower -- power up without waiting (400K: MakeSpdTbl waits anyway)
Sony_FastPower:
        MOVEQ.L #0x0,D0                         | no extra wait
        BRA.B   Sony_PowerUp                    | common path

| -------------------------------------------------------
| RWPowerUp -- power up and wait PwrOnTime (400 ms)
Sony_RWPowerUp:
        MOVE    PwrOnTime(A1),D0                | RWPowerUp: PwrOnTime (400 ms)
| PowerUp -- select the drive, motor on unless already on, then wait:
| old drive D0 * 100 us, new drive 75 ms and then until /READY (waitReady)
Sony_PowerUp:
        MOVE    D0,D2                           | PowerUp: D2 = wait time
        BSR.B   Sony_DiskSelect                 | DiskSelect
        MOVEQ.L #MtrOnAdr,D0                    | MtrOnAdr: motor-on sense
        BSR     Sony_AdrAndSense                | sense = 0 when the motor is on
        BPL.B   SONY_POWERUP_EXIT               | already on -> return
        BSR     Sony_Pulse                      | LSTRB pulse at MtrOnAdr (CA2 = 0): motor on
        MOVE    D2,D0                           | D0 = wait time
        MOVE    #0x2EE,D2                       | first wait 75 ms (750 * 100 us)
        BRA     SONY_WAITREADY                  | waitReady

| motor already on
SONY_POWERUP_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| DiskSelect -- enable the interface of the current drive (Drive); a
| floppy drive powers down whenever its enable is cut (Apple)
Sony_DiskSelect:
        BSR     Sony_GetDrive                   | DiskSelect: GetDrive
| DiskSel1 -- quick entry (Check4Disk): jump through the JDiskSel vector
Sony_DiskSel1:
        MOVE.L  (JDiskSel).w,-(SP)              | DiskSel1: push the JDiskSel vector
        RTS                                     | and jump through it

| jtDiskSel (JDiskSel vector): power down another drive with a pending
| power-down, then select drive 1 (/ENBL1), or the external port (/ENBL2)
| with the daisy chain clocked to the drive wanted when pass-thru works
Sony_jtDiskSel:
        TST     TimeOut(A1)                     | TimeOut: power-down pending?
        BEQ.B   SONY_DISKSEL_SKIP               | no ->
        MOVE    TimeOutDrive(A1),D0             | TimeOutDrive
        CMP     Drive(A1),D0                    | the current drive?
        BEQ.B   SONY_DISKSEL_SKIP               | yes -> nothing to do
        MOVEQ.L #0x0,D0                         | another drive: power it down now
        BSR.B   Sony_PowerDown                  | PowerDown (it stays selected)
SONY_DISKSEL_SKIP:
        CLR     TimeOut(A1)                     | no power-down pending any more
        CMPI    #Drive1,D1                      | drive 1 (internal)?
        BNE.B   SONY_DISKSEL_NO                 | no -> external port
        TST.B   intDrive(A0)                    | intDrive: Drive-Sel = 0, /ENBL1 (internal drive)
        TST.B   mtrOn(A0)                       | mtrOn: Motor-On = 1, /ENBL1 low
        RTS                                     | return

| external port: go to state 7 (PH0 = PH1 = PH2 = 1) safely ("we may
| already be enabled in state 2, so go safely thru 6", Apple), SEL low
SONY_DISKSEL_NO:
        TST.B   ph2H(A0)                        | CA2 high
        TST.B   ph1H(A0)                        | CA1 high
        TST.B   ph0H(A0)                        | CA0 high
        BCLR    #vHeadSel,vBufD(A2)             | SEL low: address $D, DrvExstAdr (/Exist for an HD20)
        TST.B   extDrive(A0)                    | extDrive: Drive-Sel = 1, /ENBL2 (external port)
        TST.B   PassThru(A1)                    | PassThru = 0: pass-thru works?
        BEQ.B   SONY_DISKSEL_OK                 | yes -> daisy-chain selection
        TST.B   mtrOn(A0)                       | mtrOn: /ENBL2 low
        RTS                                     | return

| pass-thru works: drive 2 = the external floppy, 3-6 = HD20s in the chain
SONY_DISKSEL_OK:
        CMPI    #Drive2,D1                      | drive 2 (external floppy)?
        BNE.B   SONY_DISKSEL_HD20               | no -> HD20
        TST.B   mtrOn(A0)                       | mtrOn: /ENBL2 low
        MOVEQ.L #0x4,D0                         | at most 5 checks, 4 clocks
| clock the chain (LSTRB pulse, CA1 low-high) while the sense line at
| address $D is high, at most D0 times
SONY_DISKSEL_CONT:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | no interrupts
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
SONY_DISKSEL_CONT_2:
        TST.B   q7L(A0)                         | Q7L: status, bit 7 = sense at address $D
        DBPL    D0,SONY_DISKSEL_LOOP            | sense low, or the count is out -> done
        TST.B   q6L(A0)                         | Q6L: back to read mode
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return

| one clock of the daisy chain
SONY_DISKSEL_LOOP:
        TST.B   ph3H(A0)                        | ph3H: LSTRB high
        MOVE.L  (SP),(SP)                       | (delay)
        TST.B   ph3L(A0)                        | ph3L: LSTRB low
        MOVE.L  (SP),(SP)                       | (delay)
        TST.B   ph1L(A0)                        | CA1 low
        MOVE.L  (SP),(SP)                       | (delay)
        TST.B   ph1H(A0)                        | CA1 high
        MOVE.L  (SP),(SP)                       | (delay)
        BRA.B   SONY_DISKSEL_CONT_2             | sense again

| HD20 (drive 3-6): enable cut and reasserted, then Drive - 3 clocks at most
SONY_DISKSEL_HD20:
        TST.B   mtrOff(A0)                      | mtrOff: /ENBL2 off
        MOVE    Drive(A1),D0                    | drive number
        MOVE.L  (SP),(SP)                       | (delay)
        TST.B   mtrOn(A0)                       | mtrOn: /ENBL2 low again
        SUBQ.W  #0x3,D0                         | D0 = drive - 3: position in the chain
        BRA.B   SONY_DISKSEL_CONT               | clock the chain

| SpeedCheckTbl -- speed value limits of the five zones (upper, lower;
| +-2% around the zone's speed). A speed value is 2^29 / (VIA timer
| counts per revolution) = 11.42 * rpm (VIA timer at 783.36 kHz); GetFreq1
| measures it. ReSeek corrects the speed code when a measurement is
| outside these limits, MakeSpdTbl aims at their midpoints.
DT_Sony_SpeedCheckTbl:
        .short  0x11E9,0x1135                   | zone 0 (tracks 0-15): about 394 rpm
        .short  0x138A,0x12C6                   | zone 1 (tracks 16-31): about 429 rpm
        .short  0x157F,0x14A7                   | zone 2 (tracks 32-47): about 472 rpm
        .short  0x17E2,0x16F2                   | zone 3 (tracks 48-63): about 525 rpm
        .short  0x1ADE,0x19D0                   | zone 4 (tracks 64-79): about 590 rpm

| -------------------------------------------------------------------------
| MakeSpdTbl -- the speed codes of the five zones (TrkSpeedTbl) of a 400K
| drive; a new-interface drive only gets 800 ms to seat the disk.
|   D0 (out) -- 0 or an error (-1 / noDriveErr: no tachometer pulses)
| -------------------------------------------------------------------------
E_Sony_MakeSpdTbl:
        MOVE.L  (DiskVars_JMakeSpdTbl).w,-(SP)  | MakeSpdTbl: push the JMakeSpdTbl vector
        RTS                                     | and jump through it

| jtMakeSpdTbl: measure the speed values f128 and f256 at speed codes $80
| and $100 and, assuming them linear in the code, compute for each zone
| the code of the limits' midpoint t, code = 128 * (t + f256 - 2 * f128) /
| (f256 - f128) + 1 (at most $18F), and the code change for 2% speed.
Sony_MakeSpdTbl:
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BPL.B   SONY_MAKESPDTBL_CONT            | no -> calibrate
        MOVE    #0x1F40,D0                      | 800 ms (Apple: "to seat diskette correctly")
        BRA     E_Sony_WakeUp                   | WakeUp: just wait

| 400K drive: f128, f256 at codes $80 and $100; for each zone the code of
| the midpoint (TSTblCode), the 2% delta (TSTblDelta), TSTblTicks = 0
SONY_MAKESPDTBL_CONT:
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
        BGT.B   SONY_MAKESPDTBL_CONT_2          | positive ->
        MOVEQ.L #0x1,D5                         | else 1 (no division by 0)
SONY_MAKESPDTBL_CONT_2:
        LSL.L   #0x1,D3                         | D3 = 2 * f128
        MOVEQ.L #0x4,D6                         | five zones
        LEA.L   DT_Sony_SpeedCheckTbl(PC),A5    | A5 -> SpeedCheckTbl (speed value limits)
        BSR     Sony_GetDrv1                    | GetDrv1
        LEA.L   TrkSpeedTbl(A1,D1.W),A3         | A3 -> TrkSpeedTbl of this drive
| per zone: pass 1 code of the midpoint t, pass 2 code of the upper limit
SONY_MAKESPDTBL_LOOP:
        MOVEQ.L #0x0,D2                         | (high word 0)
        MOVE    (A5)+,D2                        | D2 = upper limit of the zone
        MOVE.L  D2,D7                           | D7 = upper limit (for pass 2)
        ADD     (A5)+,D2                        | + lower limit
        LSR     #0x1,D2                         | D2 = t: the midpoint (target speed value)
SONY_MAKESPDTBL_CONT_3:
        ADD.L   D4,D2                           | t + f256
        SUB.L   D3,D2                           | t + f256 - 2 * f128
        LSL.L   #0x7,D2                         | * 128
        BGT.B   SONY_MAKESPDTBL_CONT_4          | positive ->
        MOVEQ.L #0x1,D2                         | else 1
SONY_MAKESPDTBL_CONT_4:
        DIVU    D5,D2                           | / (f256 - f128) = speed code for t
        ADDQ.W  #0x1,D2                         | + 1 (rounds up)
        CMPI    #0x18F,D2                       | above $18F?
        BLE.B   SONY_MAKESPDTBL_OK              | no ->
        MOVE    #0x18F,D2                       | clamp to $18F
SONY_MAKESPDTBL_OK:
        MOVE    D2,(A3)+                        | pass 1: TSTblCode; pass 2: code(upper), replaced below
        EXG     D7,D2                           | D2 = upper limit for pass 2, D7 = this code
        NOT     D0                              | toggle the pass flag (D0 = 0 from GetFreq)
        BNE.B   SONY_MAKESPDTBL_CONT_3          | -> pass 2
        SUBQ.W  #0x4,A3                         | A3 -> TSTblCode
        SUB     (A3)+,D7                        | D7 = code(upper) - code(midpoint): the 2% delta
        MOVE    D7,(A3)+                        | TSTblDelta
        CLR.L   (A3)+                           | TSTblTicks = 0: check the zone at its first use
        DBF     D6,SONY_MAKESPDTBL_LOOP         | next zone
SONY_MAKESPDTBL_ERR:
        TST     D0                              | CCR = result
        JMP     (A4)                            | return

| -------------------------------------------------------
| GetFreq -- set speed code D2 (SetASpeed), wait PwrOnTime, then GetFreq1
| GetFreq1 -- D4 = speed value: 4 FigTrkSpd measurements of 1/4
| revolution each, sum / 8, $4000000 / that = 2^29 / counts per revolution
|   D0 (out) -- 0 or noDriveErr (no tachometer pulses); return via JMP (A3)
SONY_GETFREQ:
        MOVE.L  (SP)+,A3                        | A3 = return address
        BSR     SONY_SETSPEED_CONT_3            | program speed code D2
        MOVE    PwrOnTime(A1),D0                | PwrOnTime: 400 ms for the speed change
        BSR     E_Sony_WakeUp                   | WakeUp
| SONY_GETFREQ1 -- average 4 TACH period measurements
SONY_GETFREQ1:
        MOVEQ.L #0x0,D4                         | sum of the measurements
        MOVEQ.L #0x3,D5                         | four measurements
SONY_GETFREQ1_LOOP:
        BSR.B   E_Sony_FigTrkSpd                | VIA timer counts for 15 tach pulses (1/4 revolution)
        BMI.B   SONY_GETFREQ1_EXIT              | error -> return it
        ADD.L   D0,D4                           | add up
        DBF     D5,SONY_GETFREQ1_LOOP           | four times: one revolution
        LSR.L   #0x3,D4                         | counts per revolution / 8
        MOVE.L  #0x4000000,D0                   | 2^26
        DIVU    D4,D0                           | D0 = speed value (11.42 * rpm)
        MOVE    D0,D4                           | D4 = speed value
        MOVEQ.L #0x0,D0                         | noErr
SONY_GETFREQ1_EXIT:
        JMP     (A3)                            | return

| -------------------------------------------------------------------------
E_Sony_FigTrkSpd:
        MOVE.L  (DiskVars_JFigTrkSpd).w,-(SP)   | FigTrkSpeed: push the JFigTrkSpd vector
        RTS                                     | and jump through it

| jtFigTrkSpd -- VIA timer 2 counts for 15 tachometer pulses (1/4
| revolution; TACH gives 60 pulses per revolution). The TACH sense is read
| as status bit 7 while VIA timer 2 counts down from $FFFF (783.36 kHz);
| if it runs out (VIA IFR bit 5) no pulses are coming: noDriveErr.
|   D0 (out) -- counts (PL) or noDriveErr (MI)
| Timer 2 is also the Time Manager's timer; the SE driver re-arms it
| afterwards (Apple's A302, 1986), this one does not.
Sony_FigTrkSpd:
        MOVE    SR,-(SP)                        | save the interrupt level
        MOVEM.L D1-D7/A0-A6,-(SP)               | save registers
        MOVEQ.L #0x4,D0                         | PollStack = SP + 4 (one return address)
        BSR     E_Sony_SetUpPoll                | SetUpPoll: A5, A6, interrupts off
        MOVEQ.L #TachAdr,D0                     | TachAdr: tachometer sense
        BSR     Sony_AdrDisk                    | address it
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
        BSR     Sony_EmptyPD                    | EmptyPD
        MOVEM.L (SP)+,D1-D7/A0-A6               | restore registers
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST.L   D0                              | CCR = result
        RTS                                     | return

| -------------------------------------------------------
| StartT2 -- timer 2 = $FFFF: the low byte goes to the latch, writing the
| high byte loads the counter, starts it and clears IFR bit 5
SONY_STARTT2:
        MOVE.B  D1,vT2C(A2)                     | timer 2 low byte (latch)
        MOVE.B  D1,vT2CH(A2)                    | timer 2 high byte: start
        RTS                                     | return

| synchronized: restart the timer, count 15 more pulses
SONY_FIGTRKSPD_CONT_2:
        BSR.B   SONY_STARTT2                    | StartT2
        MOVEQ.L #0xE,D2                         | 15 pulses
SONY_FIGTRKSPD_LOOP:
        BSR.B   SONY_WAITTACH                   | WaitTach
        BNE.B   SONY_FIGTRKSPD_EXIT             | timeout -> error
        DBF     D2,SONY_FIGTRKSPD_LOOP          | next pulse
| counts = $FFFF - timer (high byte read twice: if it changed, low = 0)
        MOVE.B  vT2CH(A2),D2                    | timer 2 high byte
        MOVE.B  vT2C(A2),D1                     | timer 2 low byte
        CMP.B   vT2CH(A2),D2                    | high byte changed meanwhile?
        BEQ.B   SONY_FIGTRKSPD_OK               | no ->
        MOVEQ.L #0x0,D1                         | yes: low byte = 0
SONY_FIGTRKSPD_OK:
        BTst    D3,(A3)                         | timer 2 ran out (IFR bit 5)?
        BNE.B   SONY_FIGTRKSPD_EXIT             | yes -> error (D0 = noDriveErr)
        LSL     #0x8,D2                         | high byte
        OR.B    D1,D2                           | | low byte = timer value
        NOT     D2                              | $FFFF - timer = counts
        MOVEQ.L #0x0,D0                         | (high word 0)
        MOVE    D2,D0                           | D0 = counts for 15 pulses
        BRA.B   SONY_FIGTRKSPD_EXIT             | return them

| -------------------------------------------------------
| WaitTach -- wait for a rising edge of TACH (sensed 0 twice, then 1 twice),
| pushing SCC bytes meanwhile. D0 = 0 (BEQ), or noDriveErr (BNE) when
| timer 2 runs out (Apple: "probably no drive"). Returns via DskRtnAdr
| (the caller's poll data stay on the stack).
SONY_WAITTACH:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
| wait for TACH low
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
        BTst    D3,(A3)                         | timer 2 run out?
        BEQ.B   SONY_WAITTACH_LOW               | no -> keep waiting
SONY_WAITTACH_TIMEOUT:
        MOVEQ.L #noDriveErr,D0                  | noDriveErr (-64): timeout or no drive
| DskRtn -- return to the continuation in DskRtnAdr with CCR = D0
SONY_DSKRTN:
        MOVE.L  (DskRtnAdr).w,-(SP)             | push the continuation address
        TST     D0                              | CCR = result
        RTS                                     | go there

| TACH low: wait for high
SONY_WAITTACH_HIGH:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WAITTACH_HIGH_2            | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WAITTACH_HIGH_2:
        BTst    D3,(A3)                         | timer 2 run out?
        BNE.B   SONY_WAITTACH_TIMEOUT           | yes -> error
        TST.B   (A1)                            | TACH
        BPL.B   SONY_WAITTACH_HIGH              | low -> keep waiting
        TST.B   (A1)                            | high twice?
        BPL.B   SONY_WAITTACH_HIGH              | no -> keep waiting
        MOVEQ.L #0x0,D0                         | noErr: rising edge seen
        BRA.B   SONY_DSKRTN                     | return

|
| -------------------------------------------------------------------------
| DiskVBLTask -- VBL task, every DskVBLTime (30 ticks = 0.5 s): counts
| down a pending power-down (TimeOut) and looks for inserted disks; not
| while a request is active. Runs at IPL 1 (the SE driver: 3, A216).
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
        BSR     Sony_AdrAndStrb                 | AdrAndStrb (the enable is cut below)
SONY_DISKVBLTASK_POLL:
        MOVEQ.L #0x1,D3                         | start with drive 1
SONY_DISKVBLTASK_LOOP:
        BSR.B   Sony_Check4Disk                 | Check4Disk
        ADDQ.W  #0x1,D3                         | next drive
        CMPI    #0x6,D3                         | all six done?
        BGT.B   SONY_DISKVBLTASK_DONE           | yes ->
        TST.B   PassThru(A1)                    | pass-thru works?
        BEQ.B   SONY_DISKVBLTASK_LOOP           | yes -> drives 1-6
        CMPI    #0x3,D3                         | else only drives 1-3
        BLE.B   SONY_DISKVBLTASK_LOOP           | next drive
SONY_DISKVBLTASK_DONE:
        TST.B   mtrOff(A0)                      | mtrOff: cut the drive enable (Apple: "new drive fix")
SONY_DISKVBLTASK_EXIT:
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return

|
| -------------------------------------------------------------------------
| Check4Disk -- check drive D3: after an eject count DiskInPlace up to 0;
| with no disk, look for one and post a disk-inserted event (message =
| drive number; Inside Macintosh II-212). DiskInPlace 1 or 2: nothing to
| do (no eject-button polling before the SE).
Sony_Check4Disk:
        MOVE    D3,Drive(A1)                    | Drive = D3
        BSR     Sony_GetDrive                   | GetDrive: A0, A1, A2, D1
        TST.B   Installed(A1,D1.W)              | drive connected?
        BMI.B   SONY_CKEXIT                     | no -> exit
        TST.B   DiskInPlace(A1,D1.W)            | DiskInPlace: disk in place (1 or 2)?
        BGT.B   SONY_CKEXIT                     | yes -> exit
        BEQ.B   SONY_CKDIP                      | none -> CkDIP
        ADDQ.B  #0x1,DiskInPlace(A1,D1.W)       | just ejected ($FC-$FF): count up towards 0
        BMI.B   SONY_CKINVAL                    | still waiting -> CkInval
| CkDIP -- is a disk in place (floppy) or the HD20 ready?
SONY_CKDIP:
        BSR     Sony_DiskSel1                   | DiskSel1: select the drive
        CMPI    #0x2,Drive(A1)                  | floppy drive (1-2)?
        BLE.B   SONY_CKDIP_SENSE                | yes ->
| HD20: address 8 (CA1 = 1, CA0 = SEL = CA2 = 0) after DiskSelect
        TST.B   (A0)                            | HD20: CA0 low (ph0L)
        TST.B   ph2L(A0)                        | CA2 low
        BSR     Sony_Sense                      | sense HSHK
        BMI.B   SONY_CKDIP_POST                 | high -> post a disk-inserted event
        BRA.B   SONY_CKINVAL                    | else exit

| floppy: disk-in-place sense
SONY_CKDIP_SENSE:
        MOVEQ.L #DIPAdr,D0                      | DIPAdr: disk-in-place sense
        BSR     Sony_AdrAndSense                | sense = 0 when a disk is in place
        BMI.B   SONY_CKINVAL                    | no disk -> exit
SONY_CKDIP_POST:
        MOVE    #diskInsertEvt,A0               | diskInsertEvt (7)
        MOVE.L  D3,D0                           | message = drive number (high word 0)
        _PostEvent                              | post the event
        BNE.B   SONY_CKINVAL                    | not posted (probably boot time) -> CkInval
        ADDQ.B  #0x1,DiskInPlace(A1,D1.W)       | DiskInPlace = 1: disk in place, not clamped
| CkInval -- the current track is unknown
SONY_CKINVAL:
        ST.B    Track(A1,D1.W)                  | CkInval: Track = $FFxx: current track invalid
        MOVE.L  (IWM).w,A0                      | A0 = IWM base again
SONY_CKEXIT:
        RTS                                     | return

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
| PollStack = SP + D0, i.e. the stack level of the caller's caller, to
| which EmptyPD resets the stack (SCC bytes are pushed meanwhile)
Sony_SetUpPoll:
        LEA.L   (SCC_RdDataA).l,A6              | A6 = SCC channel A data (read)
        LEA.L   (VIA_PortA2).l,A5               | A5 = VIA port A (vBufD: SCC W/REQ in bit 7)
        ORI     #0x300,SR                       | no interrupts from now on
        MOVE.L  SP,(PollStack).w                | PollStack = SP
        ADD.L   D0,(PollStack).w                | + D0 (the return addresses)
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
        BSR     Sony_AdrDisk                    | address it: that head's data on the RD line
| RdAddr -- address mark table in A2, jump through the JRdAddr vector
E_Sony_RdAddr:
        LEA.L   DT_Sony_SectorAdrTbl(PC),A2     | A2 -> AdrMks: address mark table
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
| stack.
Sony_RdAddr:
        MOVEQ.L #0x3,D3                         | D3 = 3: find 3 nibbles first (Apple: "try for 3 bytes")
        MOVEQ.L #0x7F,D2                        | D2: within at most 128 reads of the data register
        MOVEQ.L #0x0,D5                         | D5 = 0: nibbles are used as a word index
        MOVE.L  #IWM_Q6L,A4                     | A4 = q6L: the data register (absolute address, DiskQ6L)
        MOVE.L  (SP)+,(DskRtnAdr).w             | save the return address
| any nibbles at all (a blank track gives none)?
SONY_RDADDR_SKIP:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_CONT                | no SCC byte waiting ->
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_CONT:
        MOVE.B  (A4),D5                         | read the data register
        DBF     D2,SONY_RDADDR_LOOP             | count the read
        MOVEQ.L #noNybErr,D0                    | noNybErr (-66): fewer than 3 nibbles in 128 reads
        BRA     SONY_RDADDR_ERR                 | return the error

SONY_RDADDR_LOOP:
        BPL.B   SONY_RDADDR_SKIP                | bit 7 clear: no nibble yet
        SUBQ.W  #0x1,D3                         | one more nibble
        BNE.B   SONY_RDADDR_SKIP                | until 3 were seen (not necessarily in a row)
        MOVE    #0x5DC,D0                       | MustFindCt: find the mark within 1500 nibbles
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BEQ.B   SONY_RDADDR_CONT_2              | no ->
        MOVE    #0x5BC,D0                       | new-interface drive: MustFindCt - 32
SONY_RDADDR_CONT_2:
        LEA.L   SONY_DENIBLTBL-0x96(PC),A3      | A3 -> denibblize table - $96 (indexed by disk byte)
| look for the address mark $D5 $AA $96
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
        DBF     D0,SONY_RDADDR_LOOP_2           | count the nibble
        MOVEQ.L #noAdrMkErr,D0                  | noAdrMkErr (-67): no address mark within the count
        BRA.B   SONY_RDADDR_ERR                 | return the error

SONY_RDADDR_LOOP_2:
        CMP.B   (A0)+,D5                        | next mark byte?
        BNE.B   SONY_RDADDR_CONT_3              | no -> start over
        SUBQ.W  #0x1,D1                         | one more matched
        BNE.B   SONY_RDADDR_NEXT                | until all three (D1 = 0 afterwards)
| the five address field nibbles, each a 6-bit value; checksum = XOR
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
        MOVE.B  0x0(A3,D5.W),D1                 | denibblize: side (bit 5) and track bits 6-10
        EOR.B   D1,D4                           | checksum
        ROL     #0x6,D1                         | D1 bits 0-11: side (bit 11) and track
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_3              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_3:
        MOVE.B  (A4),D5                         | format nibble ("volume" in Apple's code)
        BPL.B   SONY_RDADDR_SKIP_3              | wait for it
        MOVE.B  0x0(A3,D5.W),D3                 | denibblize: format byte ($20 = two-sided)
        EOR.B   D3,D4                           | checksum
SONY_RDADDR_CONT_7:
        MOVE.B  (A4),D5                         | checksum nibble
        BPL.B   SONY_RDADDR_CONT_7              | wait for it
        MOVE.B  0x0(A3,D5.W),D5                 | denibblize
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
        DBF     D4,SONY_RDADDR_LOOP_3           | next slip mark
SONY_RDADDR_ERR:
        BRA     SONY_DSKRTN                     | DskRtn: return with D0 (PL for ok)

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
        LEA.L   SONY_DTAMKS(PC),A1              | A1 -> DtaMks: data mark table
        MOVE.L  (DiskVars_JRdData).w,-(SP)      | push the JRdData vector
        RTS                                     | and jump through it

| -------------------------------------------------------------------------
| jtRdData -- read the data field after the address field just read: the
| sector number to TagData+1, the 12 tag bytes to TagData+2, the 512 data
| bytes to (A0); with DskVerify set, compare the data with (A0) instead
| (read-verify). The 699 data nibbles are denibblized and checksummed on
| the fly (one-to-one reading possible): each group of four nibbles holds
| the top bits of three bytes (A7 A6 B7 B6 C7 C6) and their low 6 bits;
| the bytes are XORed with the running checksums C, A, B (C rotated left
| first, its old bit 7 carried into the ADDX). Four nibbles of checksum
| and the slip marks follow (WrData has the encoder).
|   A0 (in) -- buffer, A1 -- DtaMks, A3, A4, A5, A6 as RdAddr left them
|   D0 (out) -- 0, noDtaMkErr, badDCksum, dataVerErr, badDBtSlp
|
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
        DBF     D2,SONY_RDDATA_LOOP_2           | count the nibble
        MOVEQ.L #noDtaMkErr,D0                  | noDtaMkErr (-71): no data mark within 48 nibbles
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
| groups of three bytes: first the 12 tag bytes (to TagData+2), then the
| data (RdData3 below)
SONY_RDDATA_CONT_3:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_2              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_2:
        MOVE.B  (A4),D3                         | top-bits nibble
        BPL.B   SONY_RDDATA_CONT_3              | no nibble yet -> read again
        MOVE.B  0x0(A3,D3.W),D1                 | D1 = [0][0][A7][A6][B7][B6][C7][C6]
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
        OR.B    0x0(A3,D3.W),D1                 | D1 = ByteC'
        EOR.B   D6,D1                           | ByteC = ByteC' XOR CkSumB
        MOVE.B  D1,(A1)+                        | store byte C
        ADDX.B  D1,D7                           | CkSumC += ByteC + X
        SUBQ.W  #0x3,D4                         | 3 bytes done
        BPL.B   SONY_RDDATA_CONT_3              | more bytes in this buffer -> next group
        SWAP    D4                              | tags done: D4 = 510, buffer (A0)
        TST.B   (DskVerify).w                   | read-verify (ioPosMode bit 6, DskVerify)?
        BEQ.B   SONY_RDDATA_SKIP_4              | no -> RdData3: store the data
        BRA.B   SONY_RDDATA_SKIP_6              | yes -> RdVer1: compare instead

| RdData3 -- the 512 data bytes to (A0); the last group has only A and B
SONY_RDDATA_LOOP_3:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_4              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_4:
        MOVE.B  (A4),D3                         | top-bits nibble
        BPL.B   SONY_RDDATA_LOOP_3              | no nibble yet -> read again
        MOVE.B  0x0(A3,D3.W),D1                 | D1 = [0][0][A7][A6][B7][B6][C7][C6]
        ROL.B   #0x2,D1                         | D1 = [A7][A6][B7][B6][C7][C6][0][0]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [A7][A6][0][0][0][0][0][0]
SONY_RDDATA_CONT_6:
        MOVE.B  (A4),D3                         | byte A nibble
        BPL.B   SONY_RDDATA_CONT_6              | wait for it
        OR.B    0x0(A3,D3.W),D2                 | D2 = ByteA'
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
        OR.B    0x0(A3,D3.W),D2                 | D2 = ByteB'
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
        OR.B    0x0(A3,D3.W),D1                 | D1 = ByteC'
        EOR.B   D6,D1                           | ByteC = ByteC' XOR CkSumB
        MOVE.B  D1,(A0)+                        | store byte C
        ADDX.B  D1,D7                           | CkSumC += ByteC + X
        SUBQ.W  #0x3,D4                         | 3 bytes done
        BRA.B   SONY_RDDATA_LOOP_3              | next group

| RdVer1 -- read-verify: compare the decoded data with (A0)
SONY_RDDATA_LOOP_4:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_6              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_6:
        MOVE.B  (A4),D3                         | top-bits nibble
        BPL.B   SONY_RDDATA_LOOP_4              | no nibble yet -> read again
        MOVE.B  0x0(A3,D3.W),D1                 | D1 = [0][0][A7][A6][B7][B6][C7][C6]
        ROL.B   #0x2,D1                         | D1 = [A7][A6][B7][B6][C7][C6][0][0]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [A7][A6][0][0][0][0][0][0]
SONY_RDDATA_CONT_8:
        MOVE.B  (A4),D3                         | byte A nibble
        BPL.B   SONY_RDDATA_CONT_8              | wait for it
        OR.B    0x0(A3,D3.W),D2                 | D2 = ByteA'
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
        OR.B    0x0(A3,D3.W),D2                 | D2 = ByteB'
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
        OR.B    0x0(A3,D3.W),D1                 | D1 = ByteC'
        EOR.B   D6,D1                           | ByteC = ByteC' XOR CkSumB
        CMP.B   (A0)+,D1                        | same as in the buffer?
SONY_RDDATA_ERR:
        BNE.B   SONY_RDDATA_ERR_3               | no -> dataVerErr
        ADDX.B  D1,D7                           | CkSumC += ByteC + X
        SUBQ.W  #0x3,D4                         | 3 bytes done
        BRA.B   SONY_RDDATA_LOOP_4              | next group

| RdCkSum -- the four checksum nibbles (each checked for an invalid nibble)
SONY_RDDATA_DONE:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_8              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_8:
        MOVE.B  (A4),D3                         | top-bits nibble of the checksums
        BPL.B   SONY_RDDATA_SKIP_8              | wait for it
        MOVE.B  0x0(A3,D3.W),D1                 | D1 = [0][0][A7][A6][B7][B6][C7][C6]
        BMI.B   SONY_RDDATA_ERR_2               | $FF: invalid nibble -> badDCksum
        ROL.B   #0x2,D1                         | D1 = [A7][A6][B7][B6][C7][C6][0][0]
        MOVE.B  D1,D2                           | D2 = D1
        AND.B   D0,D2                           | D2 = [A7][A6][0][0][0][0][0][0]
SONY_RDDATA_CONT_10:
        MOVE.B  (A4),D3                         | CkSumA nibble
        BPL.B   SONY_RDDATA_CONT_10             | wait for it
        MOVE.B  0x0(A3,D3.W),D3                 | D3 = [0][0][A5][A4][A3][A2][A1][A0]
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
        MOVE.B  0x0(A3,D3.W),D3                 | D3 = [0][0][B5][B4][B3][B2][B1][B0]
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
        MOVE.B  0x0(A3,D3.W),D3                 | D3 = [0][0][C5][C4][C3][C2][C1][C0]
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

| RdSlip -- the slip marks $DE $AA
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
        DBF     D4,SONY_RDDATA_LOOP_5           | next slip mark
        MOVEQ.L #0x0,D0                         | noErr
SONY_RDDATA_CONT_13:
        BRA     SONY_DSKRTN                     | return through DskRtn

SONY_RDDATA_ERR_4:
        MOVEQ.L #badDBtSlp,D0                   | badDBtSlp (-73): data field slip marks wrong
        BRA.B   SONY_RDDATA_CONT_13             | return the error

| GCR decode table (denibblize, Apple: DNib): disk nibble $96..$FF ->
| 6-bit value, $FF for the other nibbles (among them the mark bytes $AA
| and $D5); RdAddr/RdData index it with the disk byte (base
| SONY_DENIBLTBL-$96). Only the checksum nibbles are checked for $FF.
SONY_DENIBLTBL:
        .byte   0x00,0x01,0xFF,0xFF,0x02,0x03   | disk $96-$97, $9A-$9B -> values 0-3
        .byte   0xFF,0x04,0x05,0x06,0xFF,0xFF   | disk $9D-$9F -> values 4-6
        .byte   0xFF,0xFF,0xFF,0xFF,0x07,0x08   | disk $A6-$A7 -> values 7-8
        .byte   0xFF,0xFF,0xFF,0x09,0x0A,0x0B   | disk $AB-$AD -> values 9-11 ($AA invalid)
        .byte   0x0C,0x0D,0xFF,0xFF,0x0E,0x0F   | disk $AE-$AF, $B2-$B3 -> values 12-15
        .byte   0x10,0x11,0x12,0x13,0xFF,0x14   | disk $B4-$B7, $B9 -> values 16-20
        .byte   0x15,0x16,0x17,0x18,0x19,0x1A   | disk $BA-$BF -> values 21-26
        .byte   0xFF,0xFF,0xFF,0xFF,0xFF,0xFF   | disk $C0-$C5: invalid ($FF)
        .byte   0xFF,0xFF,0xFF,0xFF,0xFF,0x1B   | disk $CB -> value 27
        .byte   0xFF,0x1C,0x1D,0x1E,0xFF,0xFF   | disk $CD-$CF -> values 28-30
        .byte   0xFF,0x1F,0xFF,0xFF,0x20,0x21   | disk $D3, $D6-$D7 -> values 31-33 ($D5 invalid)
        .byte   0xFF,0x22,0x23,0x24,0x25,0x26   | disk $D9-$DD -> values 34-38
        .byte   0x27,0x28,0xFF,0xFF,0xFF,0xFF   | disk $DE-$DF -> values 39-40
        .byte   0xFF,0x29,0x2A,0x2B,0xFF,0x2C   | disk $E5-$E7, $E9 -> values 41-44
        .byte   0x2D,0x2E,0x2F,0x30,0x31,0x32   | disk $EA-$EF -> values 45-50
        .byte   0xFF,0xFF,0x33,0x34,0x35,0x36   | disk $F2-$F5 -> values 51-54
        .byte   0x37,0x38,0xFF,0x39,0x3A,0x3B   | disk $F6-$F7, $F9-$FB -> values 55-59
        .byte   0x3C,0x3D,0x3E,0x3F             | disk $FC-$FF -> values 60-63
| MarkTbl (Apple) -- the six self-sync bytes and the first two bytes of
| the data mark. As a bit stream the self-sync bytes are 11111111 00
| 11111111 00 11111111 00 11111111 00 11111111: four 10-bit self-sync
| bytes ("eight bits of 1 and two bits of 0", Software control of IWM)
| and eight 1s; they put the IWM on the byte boundary whatever came
| before (SWIM Chip User's Ref, "GCR Track Format").
SONY_WRDATAMKS:
        .byte   0xFF,0x3F,0xCF,0xF3,0xFC,0xFF   | the six self-sync bytes
        .byte   0xD5,0xAA                       | data mark $D5 $AA ($AD is written by the loop)

| WrData -- MarkTbl in A2, jump through the JWrData vector
E_Sony_WrData:
        LEA.L   SONY_WRDATAMKS(PC),A2           | A2 -> MarkTbl: self-sync bytes and data mark
        MOVE.L  (DiskVars_JWrData).w,-(SP)      | push the JWrData vector
        RTS                                     | and jump through it

| -------------------------------------------------------------------------
| jtWrData -- write the data field of the sector whose address field was
| just read (Larry Kenyon): six self-sync bytes, $D5 $AA $AD, the sector
| number (TagData+1), the 12 tag bytes (TagData+2..) and the 512 bytes at
| (A0), encoded 6-and-2 with three running checksums as RdData decodes
| them, then the checksum nibbles and $DE $AA $FF $FF.
|   A0 (in) -- data buffer; A2 -- MarkTbl; A4 = Q6L, A5/A6 (SetUpPoll)
|   D0 (out) -- 0 or wrUnderrun
| IWM access: Q6H (L6 = 1, sense state), then the first byte to Q7H: the
| change to L7 = 1 with L6 = 1 starts the write state ("a transition from
| the write protect sense state to the write load state", IWM Design
| Spec) and the byte goes to the write buffer. Each further byte: wait
| for handshake bit 7 (buffer empty), read at Q6L (L7 = 1, L6 = 0: write
| handshake register), then write the byte to Q6H (L6 = 1: data). Q7L
| ends the write state.
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
        LEA.L   DT_Sony_NiblTbl(PC),A2          | A2 -> NiblTbl: 6-bit value -> disk nibble
SONY_WRDATA_NO_2:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_2                | no -> wait
        MOVE.B  D1,(A3)                         | write $AA
        MOVEQ.L #0xB,D1                         | NiblTbl[$0B] = $AD: the loop writes it as "byte B"
        MOVE.B  (A1)+,D2                        | D2 = sector number (TagData+1): "byte C", not checksummed
        BRA.B   SONY_WRDATA_LOOP_2              | into the loop

| WrDataSw -- after the tags, continue with the data buffer
SONY_WRDATA_CONT:
        MOVE.L  A0,A1                           | A1 = user buffer
| WrData1 -- finish byte C, write the top-bits nibble and the low bits of A
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
        MOVE.B  0x0(A2,D0.W),(A3)               | write low A
| WrData2 -- next byte A, low bits of B, next byte B, low bits of C, next C
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
        MOVE.B  0x0(A2,D2.W),(A3)               | write low C
        MOVE.B  (A1)+,D2                        | D2 = next ByteC (after the last group: unused)
        TST     D4                              | end of this buffer?
        BNE.B   SONY_WRDATA_NEXT                | no -> WrData1
        SWAP    D4                              | tags done (lo was 9): D4 = 513 for the data
        BNE.B   SONY_WRDATA_CONT                | -> WrDataSw; data done (0): last group
| WrLast2 -- the last group has only bytes 511 and 512 (C = 0); then the
| checksums as one top-bits nibble and three low-bits nibbles
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
        MOVE.B  0x0(A2,D3.W),(A3)               | write the checksum top-bits nibble
        ANDI.B  #0x3F,D5                        | low 6 bits of CkSumA
SONY_WRDATA_NO_9:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_9                | no -> wait
        MOVE.B  0x0(A2,D5.W),(A3)               | write CkSumA
        ANDI.B  #0x3F,D6                        | low 6 bits of CkSumB
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_5              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_5:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_SKIP_5              | no -> wait
        MOVE.B  0x0(A2,D6.W),(A3)               | write CkSumB
        ANDI.B  #0x3F,D7                        | low 6 bits of CkSumC
SONY_WRDATA_NO_10:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_WRDATA_NO_10               | no -> wait
        MOVE.B  0x0(A2,D7.W),(A3)               | write CkSumC
        LEA.L   SONY_SLIPMKS(PC),A2             | A2 -> $DE $AA $FF $FF
        MOVEQ.L #0x3,D2                         | four bytes
SONY_WRDATA_LOOP_3:
        MOVE.B  (A4),D1                         | handshake register: bit 7 empty, bit 6 write state
        BPL.B   SONY_WRDATA_LOOP_3              | wait for the buffer
        MOVE.B  (A2)+,(A3)                      | write the next byte
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_6              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_6:
        DBF     D2,SONY_WRDATA_LOOP_3           | all four
        MOVEQ.L #0x0,D0                         | assume no underrun
        BTST    #0x6,D1                         | handshake bit 6 still 1 (cleared by an underrun)?
        BNE.B   SONY_WRDATA_OK                  | yes -> noErr
        MOVEQ.L #wrUnderrun,D0                  | wrUnderrun (-74): the buffer ran empty
SONY_WRDATA_OK:
        TST.B   (IWM_Q7L).l                     | Q7L: L7 = 0, leave the write state (DiskQ7L)
        BRA     SONY_DSKRTN                     | return through DskRtn

| TrailMks -- slip marks $DE $AA and two $FF that let the last byte reach
| the disk before the write state ends
SONY_SLIPMKS:
        .byte   0xDE,0xAA,0xFF,0xFF             | slip marks $DE $AA, then $FF $FF
| Nibl -- 6-bit value -> disk nibble: the 64 bytes with bit 7 set, no
| more than one pair of adjacent 0 bits and two adjacent 1 bits in bits
| 0-6 (the SWIM Chip User's Ref, "GCR Encoding", states only the 0-bit
| rules, which 72 bytes pass); DNib above is the inverse. DiskOpen
| exports its address as NiblTbl.
DT_Sony_NiblTbl:
        .byte   0x96,0x97,0x9A,0x9B,0x9D,0x9E   | values 0-5
        .byte   0x9F,0xA6,0xA7,0xAB,0xAC,0xAD   | values 6-11
        .byte   0xAE,0xAF,0xB2,0xB3,0xB4,0xB5   | values 12-17
        .byte   0xB6,0xB7,0xB9,0xBA,0xBB,0xBC   | values 18-23
        .byte   0xBD,0xBE,0xBF,0xCB,0xCD,0xCE   | values 24-29
        .byte   0xCF,0xD3,0xD6,0xD7,0xD9,0xDA   | values 30-35
        .byte   0xDB,0xDC,0xDD,0xDE,0xDF,0xE5   | values 36-41
        .byte   0xE6,0xE7,0xE9,0xEA,0xEB,0xEC   | values 42-47
        .byte   0xED,0xEE,0xEF,0xF2,0xF3,0xF4   | values 48-53
        .byte   0xF5,0xF6,0xF7,0xF9,0xFA,0xFB   | values 54-59
        .byte   0xFC,0xFD,0xFE,0xFF             | values 60-63
| AdrMkTbl (SyncTbl) -- template of the 27 bytes in front of each sector's
| data, copied 12 times into the format buffer; FillInMarks puts in the
| track, sector, side, format and checksum nibbles (offsets 9-13) and the
| data field's sector nibble (offset 26). DoFormat writes the 703 data
| nibbles ($96 = value 0) and $DE $AA $FF $FF after each.
SONY_ADRMKTBL:
        .byte   0xFF,0x3F,0xCF,0xF3,0xFC,0xFF   | 0-5: self-sync bytes
        .byte   0xD5,0xAA,0x96,0x00,0x00,0x00   | 6-8: address mark; 9-11: track, sector, side
        .byte   0x00,0x00,0xDE,0xAA,0xFF,0xFF   | 12, 13: format, checksum; 14-16: $DE $AA $FF; 17: self-sync
        .byte   0x3F,0xCF,0xF3,0xFC,0xFF,0xD5   | 18-22: self-sync; 23: data mark $D5
        .byte   0xAA,0xAD,0x00,0x00             | 24, 25: $AA $AD; 26: sector; 27: (pad)

| -------------------------------------------------------------------------
| CtlFormat (csCode 6) -- format a floppy disk: both sides on a two-sided
| drive (csParam = 1: one side only), one side on a one-sided drive
| ("putting a $0001 at csParam creates a single-sided disk", Technical
| Note #272). Every track is written in one pass (DoFormat): 200 sync
| groups, then its sectors in 2:1 interleave (12 to 8 per track, one less
| per 16-track zone), each with GapSync sync groups in front, an address
| field and a data field of 703 $96 nibbles (all zeroes); then RdAddr
| must find sector 0 (FormatTrack). 400K drives get their speed checked
| at the first track of each zone (SpdSeek). There is no write-protect
| check (Apple added one, returning wPrErr, in November 1987).
|   A0 (in) -- parameter block; A1 = SonyVars, D1 = drive offset
|   D0 (out) -- result code
Sony_CtlFormat:
        SUBA    #0x200,SP                       | 512 bytes on the stack: the mark buffer (12 * 27 bytes)
        MOVE.L  SP,DiskBuffer(A1)               | DiskBuffer -> the stack buffer
        TST.B   Sides(A1,D1.W)                  | Sides: two-sided drive?
        SMI.B   TwoSided(A1)                    | TwoSided = $FF (both sides) for a two-sided drive
        BPL.B   SONY_CTLFORMAT_SIDES            | one-sided drive -> one-sided format
        CMPI    #0x1,csParam(A0)                | csParam = 1: one-sided format anyway?
        BNE.B   SONY_CTLFORMAT_SIDES            | no -> two-sided format
        CLR.B   TwoSided(A1)                    | TwoSided = 0: one side only
SONY_CTLFORMAT_SIDES:
        TST.B   TwoSided(A1)                    | one or two sides?
        SNE.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt of the drive = the format we write
        MOVE    #0x7,GapSync(A1)                | GapSync = 7 sync groups per sector to start with (8 since 1989)
        BSR     SONY_FVPOWERUP                  | FVPowerUp: power up (synchronously)
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  DiskBuffer(A1),A0               | A0 -> mark buffer
        LEA.L   SONY_ADRMKTBL(PC),A1            | A1 -> AdrMkTbl: the 27-byte template
        MOVEQ.L #0xB,D0                         | 12 sectors (the most on a track)
SONY_CTLFORMAT_MARKS:
        MOVEQ.L #0x1A,D1                        | 27 bytes each
        MOVE.L  A1,A2                           | A2 -> template
SONY_CTLFORMAT_MARKS_2:
        MOVE.B  (A2)+,(A0)+                     | copy a byte
        DBF     D1,SONY_CTLFORMAT_MARKS_2       | 27 bytes
        DBF     D0,SONY_CTLFORMAT_MARKS         | 12 times
        BSR     Sony_GetDrv1                    | GetDrv1: A1 = SonyVars, D1 = drive offset
        CLR     SideTrack(A1)                   | SideTrack = 0: track 0, side 0 first
| TrackLoop -- seek (checking the speed), format the track (both sides)
SONY_CTLFORMAT_TRACKLOOP:
        BSR.B   SONY_SPDSEEK                    | SpdSeek: seek, check the speed
        BNE.B   SONY_FMTVEREXIT                 | error -> exit
        BSR     SONY_FORMATTRACK                | FormatTrack: write the track, check the gap
        BNE.B   SONY_FMTVEREXIT                 | error -> exit
        BSR     Sony_GetDrv1                    | GetDrv1
        BCLR    #0x3,SideTrack(A1)              | side 0 (bit 11 of SideTrack)
        ADDQ.W  #0x1,SideTrack(A1)              | next track
        CMPI    #0x50,SideTrack(A1)             | all 80 tracks done?
        BLT.B   SONY_CTLFORMAT_TRACKLOOP        | no -> next track
        MOVEQ.L #0x0,D0                         | FmtVerOK: noErr
| FmtVerExit -- release the stack buffer, power down after the normal
| delay and complete the request (also the exit of CtlVerify)
SONY_FMTVEREXIT:
        MOVE    PwrOffTime(A1),D2               | D2 = normal power-off delay (PwrOffTime)
        ADDA    #0x200,SP                       | release the stack buffer
        BRA     SONY_DISKPRIME_POFFEXIT         | POffExit: power down, complete the request

| FmtSpdTbl -- speed limits for formatting with a 400K drive: upper and
| lower speed value per zone, +-1% around the zone's speed (the limits for
| reading and writing, SpeedCheckTbl, allow +-2%). Speed value = 11.42 *
| rpm (see SpeedCheckTbl).
SONY_FMTSPEEDTBL:
        .short  0x11BC,0x1162                   | zone 0 (tracks 0-15): about 394 rpm
        .short  0x1359,0x12F7                   | zone 1 (tracks 16-31): about 429 rpm
        .short  0x1549,0x14DD                   | zone 2 (tracks 32-47): about 472 rpm
        .short  0x17A6,0x172E                   | zone 3 (tracks 48-63): about 525 rpm
        .short  0x1A9A,0x1A14                   | zone 4 (tracks 64-79): about 590 rpm
| -------------------------------------------------------------------------
| SpdSeek -- seek to SideTrack (synchronously); with a 400K drive measure
| the speed at the first track of each zone (0, 16, 32, 48, 64) and move
| the zone's speed code by half its 2% delta until the speed is within
| the format limits (FmtSpdTbl), at most BadSpdInit + 1 times. (Apple's
| later SpdSeek only seeks.)
|   D0 (out) -- 0 or spdAdjErr; MI with Track < 0 after a seek error
SONY_SPDSEEK:
        MOVE.B  BadSpdInit(A1),BadSpdCnt(A1)    | BadSpdCnt = BadSpdInit: adjustments allowed
| CkDrift -- seek, then check the speed
SONY_SPDSEEK_CKDRIFT:
        MOVE    SideTrack(A1),D6                | D6 = side/track wanted
        BSR     SONY_FMTVERSEEK                 | FmtVerSeek: seek synchronously
        BSR     Sony_GetDrv1                    | GetDrv1
        MOVE    Track(A1,D1.W),D6               | D6 = current track (negative after a seek error)
        BMI.B   SONY_SPDSEEK_EXIT               | seek error -> return
        TST.B   NewIntf(A1,D1.W)                | NewIntf: 800K drive (it regulates its speed)?
        BMI.B   SONY_SPDSEEK_OK                 | yes -> no speed check
        MOVEQ.L #0xF,D0                         | mask: track mod 16
        AND.B   D6,D0                           | D0 = track mod 16
        BNE.B   SONY_SPDSEEK_OK                 | not the first track of a zone -> done
        LSR     #0x4,D6                         | zone
        LSL     #0x3,D6                         | * 8: offset of its TrkSpeedTbl entry
        LEA.L   TrkSpeedTbl(A1,D1.W),A2         | A2 -> TrkSpeedTbl of this drive
        LEA.L   TSTblTicks(A2,D6.W),A2          | A2 -> TSTblTicks: time of the zone's last check
        MOVE.L  (Ticks).w,D2                    | D2 = Ticks
        MOVE.L  D2,(A2)                         | note the time of this check
        LEA.L   SONY_SPDSEEK_CHECK(PC),A3       | A3 = return address for the measurement
        BRA     SONY_GETFREQ1                   | GetFreq1: D4 = speed value now

| back from GetFreq1: D4 = speed value (MI: no tachometer pulses)
SONY_SPDSEEK_CHECK:
        BMI.B   SONY_SPDSEEK_ERR                | measurement failed -> spdAdjErr
        MOVE    -(A2),D0                        | D0 = TSTblDelta: 2% of the zone's speed code
        LSR     #0x1,D0                         | half of it
        LEA.L   SONY_FMTSPEEDTBL(PC),A0         | A0 -> FmtSpdTbl
        LSR     #0x1,D6                         | zone * 4
        ADDA    D6,A0                           | A0 -> limits of this zone
        CMP     (A0)+,D4                        | above the upper limit (too fast)?
        BGT.B   SONY_SPDSEEK_ADJUST             | yes -> code - delta/2
        NEG     D0                              | D0 = -delta/2
        CMP     (A0),D4                         | above the lower limit?
        BGT.B   SONY_SPDSEEK_OK                 | yes -> speed within the limits
| too fast or too slow: correct the speed code, check again
SONY_SPDSEEK_ADJUST:
        SUB     D0,-(A2)                        | TSTblCode -= delta/2 (too fast) or += delta/2 (too slow)
        CLR.L   TSTblTicks(A2)                  | TSTblTicks = 0: check the zone again at its next use
        SUBQ.B  #0x1,BadSpdCnt(A1)              | BadSpdCnt: adjustments left?
        BPL.B   SONY_SPDSEEK_CKDRIFT            | yes -> seek and check again
SONY_SPDSEEK_ERR:
        MOVEQ.L #spdAdjErr,D0                   | spdAdjErr (-79): speed cannot be adjusted
        BRA.B   SONY_SPDSEEK_EXIT               | return it

| SpdSeekOK -- speed within the limits, or an 800K drive
SONY_SPDSEEK_OK:
        MOVEQ.L #0x0,D0                         | noErr
SONY_SPDSEEK_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| FormatTrack -- format the current track (and side 1 of it for a two-
| sided format): FillInMarks, DoFormat, then RdAddr right behind the write
| must find sector 0 (fmt1Err otherwise); the nibbles read before it
| measure the sync left between the last sector and sector 0. Too little:
| GapSync - 1 (not below minSync) and the track is written again; two or
| more groups per sector to spare: GapSync + 1 for the following tracks.
|   D0 (out) -- 0 or the error (DskErr)
SONY_FORMATTRACK:
        BSR     Sony_GetDrv1                    | GetDrv1
        MOVE    SideTrack(A1),D6                | D6 = side/track
        MOVE    D6,D1                           | D1 = side/track
        BCLR    #0xB,D1                         | without the side bit (bit 11)
        LSR     #0x4,D1                         | D1 = zone (track / 16)
        MOVEQ.L #0xC,D0                         | 12 sectors in zone 0,
        SUB     D1,D0                           | one less per zone inward
        MOVE    D0,SectCnt(A1)                  | SectCnt = sectors on this track
        BSR     SONY_FILLINMARKS                | FillInMarks: address fields of this side/track
| FmtTrk1 -- write the track, then look for sector 0
SONY_FORMATTRACK_1:
        BSR     SONY_DOFORMAT                   | DoFormat: write the track (interrupts stay off)
        BEQ.B   SONY_FORMATTRACK_CHECK          | ok -> check the gap
        BSR     SONY_TOEMPTYPD                  | toEmptyPD: DskErr = error, empty the poll data
        ANDI    #-0x701,SR                      | open interrupts
        BRA     SONY_FORMATTRACK_EXIT           | exit with the write error (wrUnderrun)

| the poll data stays on the stack: RdAddr reads the next address field
SONY_FORMATTRACK_CHECK:
        BSR     E_Sony_RdAddr                   | RdAddr: the next address field
        BMI.B   SONY_FORMATTRACK_GAP            | error ->
        TST.B   D2                              | sector 0?
        BEQ.B   SONY_FORMATTRACK_GAP            | yes ->
        MOVEQ.L #fmt1Err,D0                     | fmt1Err (-82): not sector 0
SONY_FORMATTRACK_GAP:
        BSR     SONY_TOEMPTYPD                  | toEmptyPD (DskErr = D0)
        ANDI    #-0x701,SR                      | open interrupts
        LEA.L   GapSync(A1),A0                  | A0 -> GapSync
        MOVE    (DskErr).w,D0                   | D0 = RdAddr result: count left, or an error
        BMI.B   SONY_FORMATTRACK_DECRSN1        | error -> one sync group less, write again
        MOVE.L  #MustFindCt+4,D2                | MustFindCt + 4 = 1504 (Apple: "adjusted")
        SUB     D0,D2                           | - count left = nibbles read before sector 0
        DIVU    #0x5,D2                         | / 5: a sync group reads as five $FF nibbles
        MOVE    #fmt2Err,(DskErr).w             | assume fmt2Err (-83): not enough sync
        SUB     (A0),D2                         | - GapSync = groups more than standard
        BMI.B   SONY_FORMATTRACK_DECRSYNC       | too few -> DecrSync
        EXT.L   D2                              | drop the remainder (high word) for DIVU
        DIVU    SectCnt(A1),D2                  | / sectors = extra groups per sector
        BEQ.B   SONY_FORMATTRACK_OK             | none -> ok
        SUBQ.W  #0x1,D2                         | just one ->
        BEQ.B   SONY_FORMATTRACK_OK             | leave GapSync alone
        ADDQ.W  #0x1,(A0)                       | else GapSync + 1 (for the next tracks)
| FTExitOK -- side 0 done: format side 1 of a two-sided format
SONY_FORMATTRACK_OK:
        BSR     Sony_GetDrv1                    | GetDrv1
        BSET    #0x3,SideTrack(A1)              | side 1 (bit 11); done it already?
        BNE.B   SONY_FORMATTRACK_DONE           | yes ->
        TST.B   TwoSided(A1)                    | two-sided format?
        BNE     SONY_FORMATTRACK                | yes -> format side 1
SONY_FORMATTRACK_DONE:
        CLR     (DskErr).w                      | success: DskErr = 0
SONY_FORMATTRACK_EXIT:
        MOVE    (DskErr).w,D0                   | FTExit: D0 = DskErr
        RTS                                     | return

| DecrSync -- too little sync: accept the track if only one group short
SONY_FORMATTRACK_DECRSYNC:
        ADDQ.W  #0x1,D2                         | only one group too few?
        BEQ.B   SONY_FORMATTRACK_OK             | yes -> accept
| DecrSn1 -- one sync group less per sector, write the track again
SONY_FORMATTRACK_DECRSN1:
        SUBQ.W  #0x1,(A0)                       | GapSync - 1
        CMPI    #minSync,(A0)                   | below minSync (4)?
        BLT.B   SONY_FORMATTRACK_EXIT           | yes -> give up (DskErr: fmt2Err or the RdAddr error)
        BRA.B   SONY_FORMATTRACK_1              | FmtTrk1: write the track again

| -------------------------------------------------------------------------
| DoFormat -- write the current track in one pass; the drive is up to
| speed and on the track. 200 sync groups, then per sector (FillInMarks
| order) GapSync - 1 sync groups, its 27 bytes from the mark buffer (sync
| group, address field, sync group, data mark and sector nibble), 703 $96
| nibbles and the slip marks $DE $AA $FF $FF. Interrupts stay off and the
| poll data on the stack (the return address is kept in DskRtnAdr); the
| caller empties it (toEmptyPD).
|   D6 (in) -- side/track; D0 (out) -- 0 or wrUnderrun
| IWM: Q6H (sense state), then the first byte to Q7H starts the write
| state; per byte wait for handshake bit 7 (buffer empty) at Q6L, write
| the byte to Q6H; Q7L ends the write state (see WrData).
| Registers: A0 -> mark buffer, A1 -> SyncTbl, A2 -> template, A3 = Q6H,
| A4 = Q6L, A5/A6 = VIA port A / SCC data (SetUpPoll), D0 = sectors left,
| D1 = GapSync - 2, D2/D3 = loop counts, D4 = next byte.
SONY_DOFORMAT:
        MOVE.L  (SP)+,(DskRtnAdr).w             | DskRtnAdr = return address (SCC bytes get pushed)
        MOVEQ.L #RdDtaAdr,D0                    | RdDtaAdr: side 0 head
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        TST.B   TwoSided(A1)                    | two-sided format?
        BEQ.B   SONY_DOFORMAT_SIDE              | no -> side 0
        BTST    #0xB,D6                         | side 1 (bit 11)?
        BEQ.B   SONY_DOFORMAT_SIDE              | no -> side 0
        MOVEQ.L #RdDta1Adr,D0                   | RdDta1Adr: side 1 head
SONY_DOFORMAT_SIDE:
        BSR     Sony_AdrDisk                    | address it: selects the head that writes
        MOVEQ.L #0x4,D0                         | PollStack = SP + 4 (one return address)
        BSR     E_Sony_SetUpPoll                | SetUpPoll: A5, A6, interrupts off
        MOVE.L  #IWM_Q6H,A3                     | A3 = q6H: write data register (absolute, DiskQ6H)
        MOVE.L  #IWM_Q6L,A4                     | A4 = q6L: write handshake register (absolute, DiskQ6L)
        MOVE.L  DiskBuffer(A1),A0               | A0 -> mark buffer
        MOVE    SectCnt(A1),D0                  | D0 = sectors on this track
        MOVE    GapSync(A1),D1                  | D1 = GapSync
        SUBQ.W  #0x2,D1                         | - 2: for DBF and the sync group in the marks
        LEA.L   SONY_ADRMKTBL(PC),A1            | A1 -> SyncTbl: a sync group (AdrMkTbl bytes 0-5)
        MOVE    #0xC7,D3                        | D3 = 200 - 1: 200 sync groups (strtSync)
        TST.B   (A3)                            | Q6H: L6 = 1 (sense state)
        MOVE.B  D3,(IWM_Q7H).l                  | a garbage byte to Q7H: L7 = 1 starts the write state
| WrStrtSync -- 200 sync groups, two bytes per pass
SONY_DOFORMAT_STRTSYNC:
        MOVE.L  A1,A2                           | A2 -> sync group
        MOVEQ.L #0x2,D2                         | 3 pairs of bytes
SONY_DOFORMAT_WSS1:
        MOVE.B  (A2)+,D4                        | WSS1: prefetch
SONY_DOFORMAT_WSS1_HSHK:
        TST.B   (A4)                            | Q6L: handshake bit 7 = 1: buffer empty?
        BPL.B   SONY_DOFORMAT_WSS1_HSHK         | no -> wait
        MOVE.B  D4,(A3)                         | write the byte (Q6H)
        MOVE.B  (A2)+,D4                        | prefetch
        TST.B   (A5)                            | _PollSCC: VIA port A bit 7 (SCC W/REQ) = 0: byte waiting?
        BMI.B   SONY_DOFORMAT_WSS1_HSHK2        | no ->
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_DOFORMAT_WSS1_HSHK2:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_DOFORMAT_WSS1_HSHK2        | no -> wait
        MOVE.B  D4,(A3)                         | write the byte
        DBF     D2,SONY_DOFORMAT_WSS1           | 3 pairs: one sync group
        DBF     D3,SONY_DOFORMAT_STRTSYNC       | 200 sync groups
| WrNxtSect -- a sector: GapSync - 1 sync groups ...
SONY_DOFORMAT_NXTSECT:
        MOVE    D1,D3                           | D3 = GapSync - 2
SONY_DOFORMAT_GAP:
        MOVE.L  A1,A2                           | A2 -> sync group
        MOVEQ.L #0x5,D2                         | 6 bytes
SONY_DOFORMAT_GAP_2:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_DOFORMAT_GAP_2             | no -> wait
        MOVE.B  (A2)+,(A3)                      | write a byte of the sync group
        TST.B   (A5)                            | _PollSCC: SCC byte waiting?
        BMI.B   SONY_DOFORMAT_GAP_3             | no ->
        MOVE.B  (A6),-(SP)                      | push it
SONY_DOFORMAT_GAP_3:
        DBF     D2,SONY_DOFORMAT_GAP_2          | 6 bytes
        DBF     D3,SONY_DOFORMAT_GAP            | GapSync - 1 sync groups
| ... the sector's 27 bytes from the mark buffer ...
        MOVEQ.L #0x1A,D2                        | 27 bytes
SONY_DOFORMAT_ADRMK:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_DOFORMAT_ADRMK             | no -> wait
        MOVE.B  (A0)+,(A3)                      | write a byte of the marks
        TST.B   (A5)                            | _PollSCC: SCC byte waiting?
        BMI.B   SONY_DOFORMAT_ADRMK_2           | no ->
        MOVE.B  (A6),-(SP)                      | push it
SONY_DOFORMAT_ADRMK_2:
        DBF     D2,SONY_DOFORMAT_ADRMK          | 27 bytes
| ... 703 $96 nibbles: tags, data and checksums of a sector of zeroes ...
        MOVE    #0x2BE,D2                       | 703 nibbles
SONY_DOFORMAT_DATA:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_DOFORMAT_DATA              | no -> wait
        MOVE.B  #0x96,(A3)                      | write $96 (value 0)
        TST.B   (A5)                            | _PollSCC: SCC byte waiting?
        BMI.B   SONY_DOFORMAT_DATA_2            | no ->
        MOVE.B  (A6),-(SP)                      | push it
SONY_DOFORMAT_DATA_2:
        DBF     D2,SONY_DOFORMAT_DATA           | 703 nibbles
| ... and the slip marks $DE $AA $FF $FF (AdrMkTbl bytes 14-17)
        MOVEQ.L #0x3,D2                         | 4 bytes
        ADDQ.W  #0x8,A2                         | A2 = SyncTbl + 6 + 8: AdrMkTbl byte 14
SONY_DOFORMAT_SLIP:
        TST.B   (A4)                            | buffer empty?
        BPL.B   SONY_DOFORMAT_SLIP              | no -> wait
        MOVE.B  (A2)+,(A3)                      | write a slip mark byte
        DBF     D2,SONY_DOFORMAT_SLIP           | 4 bytes
        SUBQ.W  #0x1,D0                         | sectors left?
        BGT.B   SONY_DOFORMAT_NXTSECT           | yes -> next sector
| underrun? (write handshake bit 6 = 0)
        MOVE.B  (A4),D0                         | D0 = write handshake register
        MOVEQ.L #0x0,D2                         | (D2 = 0; Apple: "assume no underrun")
        BTST    #0x6,D0                         | bit 6 = 0: underrun?
        BNE.B   SONY_DOFORMAT_OK                | no ->
        MOVEQ.L #wrUnderrun,D0                  | wrUnderrun (-74)
        BRA.B   SONY_DOFORMAT_EXIT              | exit

| no underrun
SONY_DOFORMAT_OK:
        MOVEQ.L #0x0,D0                         | noErr
SONY_DOFORMAT_EXIT:
        TST.B   (IWM_Q7L).l                     | Q7L: L7 = 0 ends the write state (in the last $FF)
        MOVE.L  (DskRtnAdr).w,-(SP)             | push the return address
        TST     D0                              | CCR = result
        RTS                                     | return (interrupts off, poll data on the stack)

| -------------------------------------------------------------------------
| FillInMarks -- put the address fields of the track's sectors into the
| mark buffer, in 2:1 interleave order 0, k, 1, k+1, ... (k = (n-1)/2 + 1;
| 12 sectors: 0 6 1 7 2 8 3 9 4 10 5 11): track bits 0-5, sector, side
| (bit 5) with track bits 6-10, format byte and checksum (XOR of the
| four), each as a disk nibble (NiblTbl); and the sector nibble behind
| the data mark.
|   D0 (in) -- sector count; D6 (in) -- side/track; registers preserved
SONY_FILLINMARKS:
        MOVEM.L D0-D7/A0-A1,-(SP)               | save registers
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  DiskBuffer(A1),A0               | A0 -> mark buffer
        MOVEQ.L #FmtByte,D3                     | FmtByte $02: 2:1 interleave, one-sided
        TST.B   TwoSided(A1)                    | two-sided format?
        BEQ.B   SONY_FILLINMARKS_1              | no ->
        MOVEQ.L #Fmt2Byte,D3                    | Fmt2Byte $22: 2:1 interleave, two-sided (bit 5)
SONY_FILLINMARKS_1:
        MOVE.L  (DiskVars_NiblTbl).w,A1         | A1 -> NiblTbl (6-bit value -> disk nibble)
        MOVE.B  0x0(A1,D3.W),D7                 | D7 = format byte nibble
        MOVE.B  D3,D5                           | D5 = checksum: the format byte
        MOVEQ.L #0x3F,D3                        | 6-bit mask
        AND.B   D6,D3                           | D3 = track bits 0-5
        MOVE.B  0x0(A1,D3.W),D2                 | D2 = track nibble
        EOR.B   D3,D5                           | into the checksum
        LSR     #0x6,D6                         | D6 = side (bit 5), track bits 6-10 (bits 0-4)
        EOR.B   D6,D5                           | into the checksum
        MOVE.B  0x0(A1,D6.W),D6                 | D6 = side nibble
        MOVE    D0,D1                           | D1 = sector count
        SUBQ.W  #0x1,D1                         | - 1
        LSR     #0x1,D1                         | / 2
        ADDQ.W  #0x1,D1                         | + 1 = k: the second sector written
        SWAP    D1                              | (high word)
        CLR     D1                              | the first sector is always 0
SONY_FILLINMARKS_LOOP:
        MOVE.B  0x0(A1,D1.W),D3                 | D3 = sector nibble
        MOVEQ.L #0x0,D4                         | (high bytes 0 for the index)
        MOVE.B  D5,D4                           | checksum without the sector
        EOR.B   D1,D4                           | plus the sector
        ADDA    #0x9,A0                         | skip sync group, $D5 $AA $96 (bytes 0-8)
        MOVE.B  D2,(A0)+                        | 9: track nibble
        MOVE.B  D3,(A0)+                        | 10: sector nibble
        MOVE.B  D6,(A0)+                        | 11: side nibble
        MOVE.B  D7,(A0)+                        | 12: format byte nibble
        MOVE.B  0x0(A1,D4.W),(A0)+              | 13: checksum nibble
        ADDA    #0xC,A0                         | skip bytes 14-25 (slip marks, sync group, $D5 $AA $AD)
        MOVE.B  D3,(A0)+                        | 26: sector nibble of the data mark
        ADDQ.W  #0x1,D1                         | next sector of this half
        SWAP    D1                              | alternate between the two halves
        SUBQ.W  #0x1,D0                         | sectors left?
        BNE.B   SONY_FILLINMARKS_LOOP           | yes ->
        MOVEM.L (SP)+,D0-D7/A0-A1               | restore registers
        RTS                                     | return

| -------------------------------------------------------------------------
| CtlVerify (csCode 5) -- read every sector of the disk, track 79 down to
| track 0 (both sides of a two-sided format), into a stack buffer; a read
| error aborts the call ("If any sector is found to be bad, it aborts
| immediately", Technical Note #272).
|   A0 (in) -- parameter block; A1 = SonyVars, D1 = drive offset
|   D0 (out) -- result code
Sony_CtlVerify:
        SUBA    #0x200,SP                       | 512-byte buffer on the stack
        MOVE.L  SP,DiskBuffer(A1)               | DiskBuffer -> the stack buffer
        BSR     SONY_FVPOWERUP                  | FVPowerUp: power up (synchronously)
        MOVEQ.L #0x4,D2                         | D2 = zone, 4 down to 0
        MOVE    #0x7F,D4                        | sector map of track 79 (almost): 7 bits
        MOVEQ.L #0x4F,D6                        | D6 = track 79 first
| NxtVClass -- next zone inward: one more sector per track
SONY_CTLVERIFY_CLASS:
        LSL     #0x1,D4                         | one more bit in the sector map
        ADDQ.W  #0x1,D4                         | (zone 4: 8 sectors ... zone 0: 12)
        MOVEQ.L #0xF,D3                         | 16 tracks per zone
| NxtVTrk -- seek to track D6, verify it
SONY_CTLVERIFY_TRACK:
        MOVEM.L D2-D6,-(SP)                     | save the loop registers
        BSR     SONY_FMTVERSEEK                 | FmtVerSeek: seek to D6 (synchronously)
        MOVEM.L (SP)+,D2-D6                     | restore them
        BSR     Sony_GetDrv1                    | GetDrv1
        MOVE    Track(A1,D1.W),D0               | D0 = current track (negative: the seek error)
        BMI.B   SONY_CTLVERIFY_EXIT             | seek error -> exit with it
        BSR.B   SONY_VERTRACK                   | VerTrack: read all sectors of the track
        BNE.B   SONY_CTLVERIFY_EXIT             | error -> exit
        SUBQ.W  #0x1,D6                         | next track
        DBF     D3,SONY_CTLVERIFY_TRACK         | 16 tracks of the zone
        DBF     D2,SONY_CTLVERIFY_CLASS         | 5 zones
SONY_CTLVERIFY_EXIT:
        BRA     SONY_FMTVEREXIT                 | FmtVerExit: release the buffer, power down

| -------------------------------------------------------------------------
| VerTrack -- read every sector of the current track (side 0, then side 1
| of a two-sided format) with interrupts off. SectMapSave holds [sector
| map][tries] for side 0 and a copy for side 1; tries = 4 * sectors
| (address fields read: 1:1 reads may fail); verErr when they run out.
|   D2 (in) -- zone; D4 (in) -- sector map; D0 (out) -- 0 or the error
SONY_VERTRACK:
        MOVEM.L D2-D6,-(SP)                     | save registers
        ORI     #HiIntMask,SR                   | no interrupts
        LEA.L   SectMapSave(A1),A0              | A0 -> SectMapSave
        MOVE    D4,(A0)                         | sector map of this track
        MOVEQ.L #0xC,D3                         | 12
        SUB     D2,D3                           | - zone = sectors on this track
        LSL     #0x2,D3                         | * 4: tries (allow some slop, may not get 1-1)
        MOVE    D3,0x2(A0)                      | tries
        MOVE.L  (A0)+,(A0)+                     | duplicate for side 1
        BCLR    #0x3,SideTrack(A1)              | side 0 first
| VTLoop -- next address field
SONY_VERTRACK_LOOP:
        MOVE.L  D1,D6                           | D6 = drive offset (RdAddr returns D1 = side/track)
        BSR     Sony_RdAddrSetup                | RdAddrSetup: D2 = sector, D3 = format byte
        BPL.B   SONY_VERTRACK_1                 | ok ->
        BSR.B   SONY_TOEMPTYPD                  | toEmptyPD
        ANDI    #-0x701,SR                      | open interrupts
        BRA.B   SONY_VERTRACK_EXIT              | exit with the error

| sector D2 still wanted?
SONY_VERTRACK_1:
        LEA.L   SectSave(A1),A0                 | A0 -> SectSave
        MOVE    D2,(A0)+                        | SectSave = sector number
        MOVE    (A0)+,D0                        | D0 = sector map
        BCLR    D2,D0                           | sector still wanted?
        BNE.B   SONY_VERTRACK_2                 | yes -> read it
        BSR.B   SONY_TOEMPTYPD                  | toEmptyPD (a sector we have already)
        ANDI    #-0x701,SR                      | open interrupts
        LEA.L   SectMapSave+2(A1),A0            | A0 -> tries
        BRA.B   SONY_VERTRACK_3                 | count the try

| read the sector's data field
SONY_VERTRACK_2:
        CMPI.B  #0x1F,D3                        | format byte above $1F (bit 5: two-sided)?
        SGT.B   TwoSideFmt(A1,D6.W)             | TwoSideFmt = $FF for a two-sided disk
        MOVE.L  DiskBuffer(A1),A0               | A0 -> buffer
        CLR.B   (DskVerify).w                   | DskVerify = 0: never read-verify here
        BSR     E_Sony_RdData                   | RdData: read the data field
        BSR.B   SONY_TOEMPTYPD                  | toEmptyPD
        TST     D0                              | read ok?
        BNE.B   SONY_VERTRACK_EXIT              | no -> exit with the error
        LEA.L   SectSave(A1),A0                 | A0 -> SectSave
        MOVE    (A0)+,D2                        | D2 = sector just read
        MOVE    (A0),D0                         | D0 = sector map
        BCLR    D2,D0                           | mark it read
        MOVE    D0,(A0)+                        | store the map
        BEQ.B   SONY_VERTRACK_OK                | all read -> side 1 or done
SONY_VERTRACK_3:
        SUBQ.W  #0x1,(A0)                       | count the try
        BNE.B   SONY_VERTRACK_LOOP              | tries left -> next address field
        MOVEQ.L #verErr,D0                      | verErr (-84): sectors missing after all tries
        BRA.B   SONY_VERTRACK_EXIT              | exit

| VTExitOK -- side 0 done: side 1 of a two-sided disk
SONY_VERTRACK_OK:
        BSR     Sony_GetDrv1                    | GetDrv1
        TST.B   TwoSideFmt(A1,D1.W)             | two-sided format?
        BEQ.B   SONY_VERTRACK_DONE              | no -> done
        BSET    #0x3,SideTrack(A1)              | side 1 (bit 11); done already?
        BNE.B   SONY_VERTRACK_DONE              | yes -> done
        ADDQ.W  #0x2,A0                         | A0 -> the side 1 copy (SectMapSave+4)
        MOVE.L  (A0),-(A0)                      | copy map and tries back
        BRA.B   SONY_VERTRACK_LOOP              | read side 1

| track verified
SONY_VERTRACK_DONE:
        MOVEQ.L #0x0,D0                         | noErr
SONY_VERTRACK_EXIT:
        ANDI    #-0x701,SR                      | VTExit: open interrupts
        MOVEM.L (SP)+,D2-D6                     | restore registers
        TST     D0                              | CCR = result
        RTS                                     | return

| toEmptyPD -- DskErr = D0, then EmptyPD (poll data to PollProc, stack reset)
| Called by: SONY_FORMATTRACK_1, SONY_FORMATTRACK_GAP, SONY_VERTRACK_LOOP, SONY_VERTRACK_1, SONY_VERTRACK_2
SONY_TOEMPTYPD:
        MOVE    D0,(DskErr).w                   | DskErr = result
        BRA     Sony_EmptyPD                    | EmptyPD

| -------------------------------------------------------------------------
| FmtVerSeek -- seek to D6 synchronously (SyncCall with Seek)
SONY_FMTVERSEEK:
        LEA.L   E_Sony_Seek(PC),A0              | A0 -> Seek (through the JSeek vector)
| SyncCall -- call the routine at A0 and wait until it has finished: when
| it has to wait (WakeUp) it returns to its caller's caller, the wait loop
| here, and goes on from the Time Manager. The high byte of DskErr is the
| "done" flag (Apple replaced it by Active in 1990: "used DskErr as a
| completion flag", SonyFormat.a).
SONY_SYNCCALL:
        CLR.B   (DskErr).w                      | DskErr high byte = 0: not done
        BSR.B   SONY_SYNCCALL_CALL              | call it
SONY_SYNCCALL_WAIT:
        TST.B   (DskErr).w                      | done?
        BEQ.B   SONY_SYNCCALL_WAIT              | no -> wait
        RTS                                     | return

| SyncCall's call: the routine returns here when it has finished
SONY_SYNCCALL_CALL:
        JSR     (A0)                            | call the routine
        ST.B    (DskErr).w                      | DskErr high byte = $FF: done
        RTS                                     | return (to the wait loop, or to GoWakeIt)

| FVPowerUp -- power up synchronously (SyncCall with RWPowerUp)
SONY_FVPOWERUP:
        LEA.L   Sony_RWPowerUp(PC),A0           | A0 -> RWPowerUp
        BRA.B   SONY_SYNCCALL                   | SyncCall

| -------------------------------------------------------------------------
| DCDPrime -- read or write on an HD20 (drives 3-6, from jtDiskPrime).
| The first access (DiskInPlace < 2) issues a status command to learn
| the drive's size and characteristics. Then the blocks are transferred,
| at most 255 per command: DCDSetupCmd, SendCmd (for a write also the
| data of each block), then per block DCDWaitHSHK and DCDRcvResponse; up
| to four tries per command, with one hard reset (DCDReset).
| HD20 lines: the IWM phase lines CA0-CA2 and the drive's HSHK, read as
| the sense line (status bit 7); /ENBL2 (mtrOn) selects the chain.
Sony_DCDPrime:
        ANDI    #-0x701,SR                      | open interrupts (IPL 0)
        MOVE    LastDrive(A1),D0                | D0 = LastDrive: the drive of the previous call
        CMP     Drive(A1),D0                    | the same drive?
        BEQ.B   SONY_DCDPRIME_SELECT            | yes ->
        MOVEQ.L #0xA,D0                         | else wait 1 ms first
        BSR     E_Sony_WakeUp                   | WakeUp
SONY_DCDPRIME_SELECT:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base
        TST.B   (A0)                            | ph0L: CA0 low
        TST.B   ph2L(A0)                        | CA2 low (CA1 high, SEL low: the sense line is the HD20's HSHK)
        CMPI.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace >= 2: status known (2 or 8)?
        BGE.B   SONY_DCDPRIME_GO                | yes -> transfer
        LEA.L   SONY_DCDPRIME_STATUS(PC),A0     | continue at DCDPRIME_STATUS after the status command
        MOVE.L  A0,StsRtnAddr(A1)               | StsRtnAddr
        BRA     Sony_DCDStatus                  | DCDStatus: send the status command

| back from the status command (CCR = result): note the drive's status
SONY_DCDPRIME_STATUS:
        BNE     SONY_DCDEXIT                    | status command failed -> complete with the error
        BSR     Sony_GetDrive                   | GetDrive: A1 = SonyVars, D1 = drive offset
        MOVE.B  #0x8,DiskInPlace(A1,D1.W)       | DiskInPlace = 8: non-ejectable disk in place (MTN #272)
        MOVE.L  DevType(A1),DriveType(A1,D1.W)  | DriveType, DriveManf = device type and manufacturer
        MOVE.L  DevChar(A1),D0                  | D0 = characteristics byte, 3-byte block count (DevBlks)
        SWAP    D0                              | block count low word to the high word
        MOVE.L  D0,DriveSize(A1,D1.W)           | DriveSize = low word of the block count,
        CLR.B   DriveS1(A1,D1.W)                | DriveS1 = high word (bits 16-23)
        LSR     #0x8,D0                         | D0 = characteristics byte
        MOVE.B  D0,DriveChar(A1,D1.W)           | DriveChar
        BTST    #DevChWP,D0                     | DevChWP (bit 3): write-protected?
        SNE.B   WriteProt(A1,D1.W)              | WriteProt = $FF if so
        BTST    #DevChEject,D0                  | DevChEject (bit 4): removable medium?
        BEQ.B   SONY_DCDPRIME_GO                | no -> DiskInPlace stays 8
        MOVE.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2 (ejectable, like a floppy)
| GO -- check the request; a read-verify is not done on an HD20
SONY_DCDPRIME_GO:
        MOVE.L  (A1),A2                         | A2 = DCE (DiskUnitPtr)
        MOVE.L  dCtlPosition(A2),D5             | D5 = dCtlPosition (byte offset)
        MOVEQ.L #0x9,D1                         | / 512
        LSR.L   D1,D5                           | D5 = first block number
        MOVE.L  dCtlQHead(A2),A0                | A0 = the request (dCtlQHead)
        MOVE.L  TagBufPtr(A1),A5                | A5 = TagBufPtr (0: tags in the system tag buffer)
        MOVE.L  ioBuffer(A0),A4                 | A4 = ioBuffer
        MOVE.L  ioReqCount(A0),D3               | D3 = ioReqCount
        MOVEQ.L #paramErr,D0                    | paramErr (-50) unless
        ANDI    #0x1FF,D3                       | the count is a multiple of 512
        BNE     SONY_DCDEXIT                    | no -> complete with paramErr
        MOVE.L  ioReqCount(A0),D3               | D3 = ioReqCount
        TST.B   (DskVerify).w                   | read-verify (DskVerify)?
        BEQ.B   SONY_DCDPRIME_CMD               | no -> transfer
        BSR     Sony_CheckRead                  | CheckRead: a read?
        BNE.B   SONY_DCDPRIME_CMD               | no (write) -> transfer
        MOVE.L  D3,ioActCount(A0)               | read-verify: ioActCount = ioReqCount,
        ADD.L   D3,dCtlPosition(A2)             | dCtlPosition advanced,
        MOVEQ.L #0x0,D0                         | noErr, nothing read
        BRA     SONY_DCDEXIT                    | complete the request

| CMD -- HD20 command 0 (read) or 1 (write)
SONY_DCDPRIME_CMD:
        MOVE.B  Command+1(A1),DCDCmd(A1)        | DCDCmd = low byte of Command (aRdCmd 2, aWrCmd 3)
        SUBQ.B  #0x2,DCDCmd(A1)                 | - 2: 0 = read, 1 = write
| NEXT -- the next command: D3 = bytes left
SONY_DCDPRIME_NEXT:
        MOVEQ.L #0x9,D1                         | / 512
        LSR.L   D1,D3                           | D3 = blocks left
        MOVEQ.L #0x0,D0                         | D0 = 0,
        SUBQ.B  #0x1,D0                         | - 1 in the low byte: D0 = 255
        CMP.L   D0,D3                           | more than 255 blocks?
        BLT.B   SONY_DCDPRIME_COUNT             | no ->
        MOVE.L  D0,D3                           | at most 255 blocks per command
SONY_DCDPRIME_COUNT:
        MOVE    D3,D2                           | D3 = this command's block count
        SWAP    D3                              | in the high word (blocks of the command)
        MOVE    D2,D3                           | and in the low word (blocks left, counted down)
        MOVE.B  #maxTries-1,RecalCnt(A1)        | RecalCnt = 3: four tries (maxTries)
        CLR.B   DCDFlags(A1)                    | DCDFlags = 0: no reset yet
| RETRY -- (re)send the command
SONY_DCDPRIME_RETRY:
        BSR     SONY_DCDSETUPCMD                | DCDSetupCmd: build the command block
        BSR     E_Sony_SendCmd                  | SendCmd: send it (with a block of data for a write)
        BNE.B   SONY_DCDPRIME_ERR               | error ->
| WAIT -- wait for the response to the command or block
SONY_DCDPRIME_WAIT:
        BSR     SONY_DCDWAITHSHK                | DCDWaitHSHK: wait until HSHK goes low
        BPL.B   SONY_DCDPRIME_RCV               | it did -> receive the response
        MOVE.B  #comErr,LastResult(A1)          | timeout: LastResult = comErr,
        CLR.L   LastStatus(A1)                  | LastStatus =
        MOVE.B  #NoResp,LastStatus(A1)          | NoResp ($40): no response packet received
        BRA.B   SONY_DCDPRIME_ERR               | -> retry

| RCV -- receive and check the response (for a write the next block is
| sent from there)
SONY_DCDPRIME_RCV:
        BSR     Sony_DCDRcvResponse             | DCDRcvResponse
        BEQ.B   SONY_DCDPRIME_WAIT              | more blocks -> wait for the next response
        ADD.L   D4,D5                           | D5 = next block: + blocks done (D4)
        TST     D0                              | error?
        BEQ.B   SONY_DCDPRIME_DONE              | no -> account for the command
| ERR -- retry: after a communication error that is no checksum error
| first reset the HD20 (once); the last try always follows a reset
SONY_DCDPRIME_ERR:
        SUBQ.B  #0x1,RecalCnt(A1)               | tries left?
        BLT.B   SONY_DCDPRIME_FAIL              | no -> fail
        BEQ.B   SONY_DCDPRIME_RESET             | last one -> reset first
        CMPI.B  #comErr,LastResult(A1)          | communication error (comErr)?
        BNE.B   SONY_DCDPRIME_AGAIN             | no (the HD20 reported an error) -> retry
        BTST    #bChksum,LastStatus(A1)         | bChksum (bit 30 = bit 6 of the first LastStatus byte)?
        BNE.B   SONY_DCDPRIME_AGAIN             | set -> retry without a reset
        TST.B   DCDFlags(A1)                    | reset done already?
        BEQ.B   SONY_DCDPRIME_RESET             | no -> reset
        CLR.B   RecalCnt(A1)                    | yes: make this the last try
SONY_DCDPRIME_RESET:
        BSR     E_Sony_DCDReset                 | DCDReset: hard reset of the HD20
        BNE.B   SONY_DCDPRIME_FAIL              | failed -> fail
        ST.B    DCDFlags(A1)                    | DCDFlags = $FF: reset done
SONY_DCDPRIME_AGAIN:
        BRA.B   SONY_DCDPRIME_RETRY             | send the command again

| FAIL -- out of tries: readErr or writErr
SONY_DCDPRIME_FAIL:
        MOVEQ.L #readErr,D0                     | readErr (-19)
        CMPI.B  #aRdCmd,Command+1(A1)           | a read?
        BEQ.B   SONY_DCDPRIME_FAILEXIT          | yes ->
        MOVEQ.L #writErr,D0                     | else writErr (-20)
SONY_DCDPRIME_FAILEXIT:
        BRA.B   SONY_DCDEXIT                    | complete the request

| DONE -- command done: update the tags, the position and the count
SONY_DCDPRIME_DONE:
        MOVEQ.L #0x9,D1                         | * 512
        CLR     D3                              | D3 = the command's block count
        SWAP    D3                              | (from the high word)
        CMPI.B  #aRdCmd,Command+1(A1)           | a read?
        BEQ.B   SONY_DCDPRIME_UPDATE            | yes ->
        ADD.L   D3,(BufTgFFlg).w                | write: file block number in the tags (BufTgFBkNum) + blocks
SONY_DCDPRIME_UPDATE:
        LSL.L   D1,D3                           | D3 = bytes done
        MOVE.L  (A1),A3                         | A3 = DCE
        ADD.L   D3,dCtlPosition(A3)             | dCtlPosition + bytes
        MOVE.L  dCtlQHead(A3),A0                | A0 = the request
        ADD.L   D3,ioActCount(A0)               | ioActCount + bytes
        MOVE.L  ioReqCount(A0),D3               | D3 = ioReqCount
        SUB.L   ioActCount(A0),D3               | - ioActCount = bytes left
        BGT     SONY_DCDPRIME_NEXT              | more -> next command
        MOVEQ.L #0x0,D0                         | noErr
| DCD exit -- deselect the HD20, open interrupts, complete the request
SONY_DCDEXIT:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base
        TST.B   mtrOff(A0)                      | mtrOff: /ENBL2 off, deselect the HD20
        ANDI    #-0x701,SR                      | open interrupts
        BRA     Sony_DiskDone                   | DiskDone: complete the request

| -------------------------------------------------------------------------
| DCDWaitHSHK -- wait until the HD20 pulls HSHK low (status bit 7 = 0:
| it has a response to send): 100 polls, then every ChkTime (100-us
| units, WakeUp: the caller's caller gets control meanwhile) for at most
| MaxTime more checks. Returns through A3: PL = ready, MI = timeout.
SONY_DCDWAITHSHK:
        MOVE.L  (SP)+,A3                        | A3 = return address
SONY_DCDWAITHSHK_1:
        MOVEQ.L #0x64,D0                        | 100 polls
SONY_DCDWAITHSHK_2:
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        TST.B   q7L(A0)                         | Q7L: read status, HSHK in bit 7
        DBPL    D0,SONY_DCDWAITHSHK_2           | poll until HSHK is low or the count is done
        BPL.B   SONY_DCDWAITHSHK_EXIT           | HSHK low -> ready
        SUBQ.W  #0x1,MaxTime(A1)                | MaxTime: checks left?
        BMI.B   SONY_DCDWAITHSHK_EXIT           | no -> timeout (MI)
        MOVE    ChkTime(A1),D0                  | D0 = ChkTime
        BSR     E_Sony_WakeUp                   | WakeUp: wait that long
        BRA.B   SONY_DCDWAITHSHK_1              | poll again

| return with the N flag of the last status read (or of MaxTime)
SONY_DCDWAITHSHK_EXIT:
        JMP     (A3)                            | return

| -------------------------------------------------------------------------
| DCDSetupCmd -- set up a read or write command for D3 blocks from block
| D5: StartBlock (3 bytes, DriveOut = 0), SeqNum = block count, ChkTime
| and MaxTime for the first response, D6/D7 = data bytes to send and to
| receive per block (512 one way, 0 the other). The read/write test comes
| before flag bits 6-7 of DCDCmd are cleared (the SE driver clears them
| first).
SONY_DCDSETUPCMD:
        MOVE.L  D5,D0                           | D0 = first block number
        LSL.L   #0x8,D0                         | 3-byte block number, then DriveOut = 0
        MOVE.L  D0,StartBlock(A1)               | StartBlock, DriveOut
        MOVE.B  D3,SeqNum(A1)                   | SeqNum = number of blocks
        MOVE    #tSeekChk,ChkTime(A1)           | ChkTime = tSeekChk: check every 1 ms
        MOVE    #tSeekMax,MaxTime(A1)           | MaxTime = tSeekMax: 10000 checks = 10 s
        MOVE.L  #0x200,D6                       | D6 = 512 bytes to send
        MOVEQ.L #0x0,D7                         | D7 = 0 bytes to receive
        TST.B   DCDCmd(A1)                      | DCDCmd: read (0)?
        BNE.B   SONY_DCDSETUPCMD_EXIT           | no (write) ->
        EXG     D6,D7                           | read: send 0, receive 512
SONY_DCDSETUPCMD_EXIT:
        ANDI.B  #0x3F,DCDCmd(A1)                | DCDCmd: clear flag bits 6-7
        RTS                                     | return

| SendCmd -- jump through the JSendCmd vector
E_Sony_SendCmd:
        MOVE.L  (JSendCmd).w,-(SP)              | push SendCmd vector address
        RTS                                     | dispatch to Sony_SendCmd

| -------------------------------------------------------------------------
| jtSendCmd (JSendCmd vector) -- send the command block (DCDSendPacket);
| for a write it carries the 20 tag bytes and 512 data bytes of the
| first block, the others follow from DCDRcvResponse (SONY_SENDCMD_NEXT).
| Group counts: 6 header bytes + data = 7 * full groups + the remainder
| (high word), which the last group carries with the checksum.
|   D6/D7 (in) -- data bytes to send / receive per block; D3 -- blocks
|   A4 (in) -- data buffer; A5 -- tag buffer or 0
|   D0 (out), CCR -- 0 (EQ) or 1 (NE, LastStatus/LastResult set)
Sony_SendCmd:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address
        LEA.L   q6L(A0),A3                      | A3 = q6L: write handshake register (in the write state)
        MOVE.L  D6,BufSize(A1)                  | BufSize = data bytes per block,
        ADD.L   D7,BufSize(A1)                  | sent or received
        MOVE.B  DCDCmd(A1),D1                   | D1 = command
        CMPI.B  #0x3,D1                         | status, format or verify (3 and up)?
        BGE.B   SONY_SENDCMD_SKIP               | yes -> no tags
        TST.B   D1                              | read (0)?
        BNE.B   SONY_SENDCMD_NO                 | no (write) ->
        ADDI    #TagSize,D7                     | read: 20 tag bytes more to receive
        BRA.B   SONY_SENDCMD_SKIP               | ->

| write: 20 tag bytes more to send; without a tag buffer they come from
| the system tag buffer (TagData)
SONY_SENDCMD_NO:
        ADDI    #TagSize,D6                     | 20 tag bytes more to send
        MOVE.L  A5,D0                           | tag buffer (TagBufPtr)?
        BNE.B   SONY_SENDCMD_SKIP               | yes -> copied per block below
        ADDA    #TagBytes,A1                    | A1 -> TagBytes
        MOVE.L  (BufTgFNum).w,(A1)+             | file number
        MOVE.L  (BufTgFFlg).w,(A1)+             | flags and file block number
        MOVE.L  (BufTgDate).w,(A1)+             | date
        MOVE.L  (BufTgHD20).w,(A1)+             | 8 more tag bytes of the HD20
        MOVE.L  (BufTgHD20_1).w,(A1)+           | (TagData+14..21)
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
SONY_SENDCMD_SKIP:
        ADDQ.W  #0x6,D6                         | + 6 header bytes
        DIVU    #0x7,D6                         | / 7: full groups to send (remainder in the high word)
        ANDI    #0x7F,D6                        | (7 bits)
        ADDQ.W  #0x6,D7                         | + 6 header bytes
        DIVU    #0x7,D7                         | / 7: full groups to receive (remainder in the high word)
        ANDI    #0x7F,D7                        | (7 bits)
        MOVEQ.L #0x0,D4                         | D4 = 0 blocks done
        BRA.B   SONY_SENDCMD_LOOP               | send the command

| NEXT -- from DCDRcvResponse: write the next block (a read just waits)
SONY_SENDCMD_NEXT:
        TST.B   D1                              | read?
        BEQ.B   SONY_SENDCMD_EXIT               | yes -> return (EQ: more blocks)
        ORI.B   #0x40,DCDCmd(A1)                | DCDCmd bit 6: next block of the write
        MOVE.B  D3,SeqNum(A1)                   | SeqNum = blocks left
        ADDQ.L  #0x1,TagBytes+4(A1)             | next file block number in the tags (low word of TagBytes+4)
        MOVE    #tNextChk,ChkTime(A1)           | ChkTime = tNextChk: check every 700 us
        MOVE    #tNextMax,MaxTime(A1)           | MaxTime = tNextMax: 10000 checks = 7 s
SONY_SENDCMD_LOOP:
        CMPI.B  #0x3,D1                         | status, format or verify?
        BGE.B   SONY_SENDCMD_OK                 | yes -> no tags
        TST.B   D1                              | read?
        BEQ.B   SONY_SENDCMD_OK                 | yes -> no tags to send
        MOVE.L  A5,D0                           | tag buffer?
        BEQ.B   SONY_SENDCMD_OK                 | no -> TagBytes as set up
        ADDA    #TagBytes,A1                    | A1 -> TagBytes
        MOVE.L  (A5)+,(A1)+                     | 12 tag bytes of this block
        MOVE.L  (A5)+,(A1)+                     | from the tag buffer
        MOVE.L  (A5)+,(A1)+                     | (TagBufPtr)
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
SONY_SENDCMD_OK:
        BSR     Sony_DCDSendPacket              | DCDSendPacket: send the packet
        BNE     SONY_SENDCMD_ERR                | error -> comErr
SONY_SENDCMD_EXIT:
        RTS                                     | return (EQ)

| -------------------------------------------------------------------------
| DCDRcvResponse -- receive the HD20's response packet (DCDRcvPacket)
| and check it: response byte = command + $80, SeqNum = blocks left,
| status; store the tags of a read block and count the block; for a
| write send the next block (SendCmd). EQ: more blocks follow; NE: done
| (D0 = 0) or error (D0 = 1, LastStatus and LastResult set).
Sony_DCDRcvResponse:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address
        LEA.L   q6L(A0),A3                      | A3 = q6L: the read data register (L7 = 0)
        MOVE.B  DCDCmd(A1),D1                   | D1 = command
        ANDI.B  #0x3F,D1                        | without flag bits 6-7
        BSR     Sony_DCDRcvPacket               | DCDRcvPacket: header to Response.., data to A4
        BNE     SONY_SENDCMD_ERR                | error -> comErr
        MOVE.L  Response(A1),D0                 | D0 = response, SeqNum, 2 status bytes
        MOVE.B  #InvalidResp,D0                 | (low byte: InvalidResp)
        SUBI.B  #0x80,Response(A1)              | Response - $80
        CMP.B   Response(A1),D1                 | = command?
        BNE.B   SONY_SENDCMD_ERR                | no -> InvalidResp
        CMPI.B  #0x3,D1                         | status, format or verify?
        BGE.B   SONY_SENDCMD_CHKSTATUS          | yes -> no sequence number
        MOVE.B  #SqncNumErr,D0                  | (SqncNumErr)
        CMP.B   SeqNum(A1),D3                   | SeqNum = blocks left?
        BEQ.B   SONY_SENDCMD_OK_2               | yes ->
        SWAP    D0                              | else LastStatus =
        MOVE.B  D3,D0                           | SqncNumErr, response,
        SWAP    D0                              | expected and received
        ROR.L   #0x8,D0                         | sequence number
        MOVE.B  SeqNum(A1),D0                   | (SONY_SENDCMD_ERR moves
        ROL.L   #0x8,D0                         | the error code to the top)
        BRA.B   SONY_SENDCMD_ERR                | -> comErr

| a read block: its tags to the tag buffer and the system tag buffer
SONY_SENDCMD_OK_2:
        TST.B   D1                              | read?
        BNE.B   SONY_SENDCMD_CHKSTATUS          | no ->
        MOVE.L  A5,D0                           | tag buffer?
        BEQ.B   SONY_SENDCMD_NO_2               | no ->
        ADDA    #TagBytes,A1                    | A1 -> TagBytes
        MOVE.L  (A1)+,(A5)+                     | 12 tag bytes
        MOVE.L  (A1)+,(A5)+                     | to the tag buffer
        MOVE.L  (A1)+,(A5)+                     | (TagBufPtr)
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
SONY_SENDCMD_NO_2:
        ADDA    #TagBytes,A1                    | A1 -> TagBytes
        MOVE.L  (A1)+,(BufTgFNum).w             | file number
        MOVE.L  (A1)+,(BufTgFFlg).w             | flags and file block number
        MOVE.L  (A1)+,(BufTgDate).w             | date
        MOVE.L  (A1)+,(BufTgHD20).w             | 8 more tag bytes of the HD20
        MOVE.L  (A1)+,(BufTgHD20_1).w           | (TagData+14..21)
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
| the HD20's status: bit 0 of the first byte (opFailed) or a first byte
| of $0A is an error (nonZerStat)
SONY_SENDCMD_CHKSTATUS:
        MOVEQ.L #nonZerStat,D2                  | D2 = nonZerStat
        MOVE.L  SeqNum+1(A1),D0                 | D0 = the 4 status bytes (Status; that name is the _Status label here)
        BTST    #opFailed,D0                    | opFailed (bit 24)?
        BNE.B   SONY_SENDCMD_ERR_2              | yes -> error
        CMPI.B  #0xA,SeqNum+1(A1)               | first status byte $0A?
        BEQ.B   SONY_SENDCMD_ERR_2              | yes -> error
        ADDA.L  BufSize(A1),A4                  | A4 -> next block's data
        ADDQ.L  #0x1,D4                         | one more block done
        SUBQ.B  #0x1,D3                         | blocks left?
        BNE     SONY_SENDCMD_NEXT               | yes -> next block
        MOVEQ.L #0x0,D0                         | noErr: all done
SONY_SENDCMD_RET:
        ADDQ.W  #0x1,D3                         | D3 + 1 (not in the SE driver: a retry then asks for one block more than is left)
        ANDI    #-0x5,SR                        | clear Z: NE = finished
        RTS                                     | return

| comErr: LastStatus = error code (top byte) and context, LastResult
SONY_SENDCMD_ERR:
        MOVEQ.L #comErr,D2                      | D2 = comErr
        ROR.L   #0x8,D0                         | error code to the top byte
SONY_SENDCMD_ERR_2:
        MOVE.L  D0,LastStatus(A1)               | LastStatus
        MOVE.B  D2,LastResult(A1)               | LastResult = comErr or nonZerStat
        MOVEQ.L #0x1,D0                         | D0 = 1: error
        BRA.B   SONY_SENDCMD_RET                | return (NE)

| -------------------------------------------------------------------------
| DCDRcvPacket -- receive a packet from the HD20: $AA, then groups of 8
| bytes: 7 data bytes (bits 7-1 in bits 6-0, bit 7 set) and a byte with
| their bits 0 (bit 0 for the first byte). D7 = full groups, its high
| word the data bytes of the last group, whose 7th byte is the checksum
| (all decoded bytes add up to 0). The first 26 bytes go to Response..
| (6 header bytes, TagBytes), the rest to A4. Groups are decoded while
| the next one arrives. A first byte $BF (response $7E/$7F) announces a
| 6-byte packet. With an SCC interrupt pending, CA0 low asks the HD20 to
| hold off after the group it is sending; interrupts are opened briefly,
| then CA0 high and the HD20 goes on with a new $AA.
|   A0 = IWM, A3 = q6L (read data register), A4 -> data, D7 (in)
|   D0 (out), CCR -- 0 (EQ) or RdHsHi, RdSyncTO, RdGroupTO, RdHoffSyncTO,
|   RdHsHiTO, RdChksumErr
| IWM read data register (L7 = 0, L6 = 0): bit 7 is set when a byte is
| complete; "in asynchronous mode the data register ... will be cleared
| ... about 2 uS after a valid data read" (IWM Design Spec).
Sony_DCDRcvPacket:
        MOVE    SR,-(SP)                        | save the interrupt level
        MOVEM.L D1-D7/A1/A4-A6,-(SP)            | save registers
        ADDA    #Response,A1                    | A1 -> Response: header, then TagBytes
        MOVEQ.L #0x0,D5                         | D5 = checksum
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVEQ.L #RdHsHi,D0                      | RdHsHi ($20): HSHK must be low (response ready)
        TST.B   q7L(A0)                         | Q7L: read status, HSHK in bit 7
        BMI     SONY_RCVPKT_EXIT                | high -> error
        MOVEM.L (SCCRd).w,A5-A6                 | A5 = SCCRd, A6 = SCCWr
        ADDQ.W  #0x2,A5                         | A5 -> SCC channel A control (read)
        ADDQ.W  #0x2,A6                         | A6 -> SCC channel A control (write)
        ORI     #0x700,SR                       | no interrupts
        TST.B   ph0H(A0)                        | CA0 high,
        TST.B   ph1L(A0)                        | CA1 low: ready to receive
        TST.B   (A3)                            | q6L: L6 = 0, read data; discard a stale byte
        MOVEQ.L #RdSyncTO,D0                    | RdSyncTO ($21): no $AA
        MOVEQ.L #0x1,D6                         | D6 = $10000 reads
        SWAP    D6                              | for the $AA
| wait for the sync byte $AA
SONY_RCVPKT_SYNC:
        SUBQ.L  #0x1,D6                         | count
        BEQ     SONY_RCVPKT_EXIT                | timeout -> RdSyncTO
        CMPI.B  #SyncByte,(A3)                  | $AA?
        BNE.B   SONY_RCVPKT_SYNC                | no -> read again
        MOVE    #0x50,D6                        | 80 reads for a group
| the first group: D1 = bytes 1/2 (low/high word), D2 = 3/4, D3 = 5/6,
| D4 = byte 7 (high word) and the bit-0 byte (low word)
SONY_RCVPKT_GET1:
        MOVE.B  (A3),D1                         | byte 1
        DBMI    D6,SONY_RCVPKT_GET1             | until one is there (bit 7 set)
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> RdGroupTO
        CMPI.B  #0xBF,D1                        | $BF: response $7E/$7F?
        BNE.B   SONY_RCVPKT_NOTSHORT            | no ->
        MOVEQ.L #0x6,D7                         | yes: no full group,
        SWAP    D7                              | 6 bytes in the last one
SONY_RCVPKT_NOTSHORT:
        SWAP    D1                              | (keep it)
SONY_RCVPKT_GET2:
        MOVE.B  (A3),D1                         | byte 2
        DBMI    D6,SONY_RCVPKT_GET2             | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D1                              | D1.lo = byte 1, D1.hi = byte 2
SONY_RCVPKT_GET3:
        MOVE.B  (A3),D2                         | byte 3
        DBMI    D6,SONY_RCVPKT_GET3             | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D2                              | (keep it)
SONY_RCVPKT_GET4:
        MOVE.B  (A3),D2                         | byte 4
        DBMI    D6,SONY_RCVPKT_GET4             | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D2                              | D2.lo = byte 3, D2.hi = byte 4
SONY_RCVPKT_GET5:
        MOVE.B  (A3),D3                         | byte 5
        DBMI    D6,SONY_RCVPKT_GET5             | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D3                              | (keep it)
SONY_RCVPKT_GET6:
        MOVE.B  (A3),D3                         | byte 6
        DBMI    D6,SONY_RCVPKT_GET6             | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D3                              | D3.lo = byte 5, D3.hi = byte 6
SONY_RCVPKT_GET7:
        MOVE.B  (A3),D4                         | byte 7
        DBMI    D6,SONY_RCVPKT_GET7             | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D4                              | (high word)
SONY_RCVPKT_GET8:
        MOVE.B  (A3),D4                         | byte 8: bits 0 of bytes 1-7
        DBMI    D6,SONY_RCVPKT_GET8             | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        DBF     D7,SONY_RCVPKT_DECODE           | full groups -> decode them
        BRA     SONY_RCVPKT_LAST                | else this is the last group

| RdGroupTO -- a byte did not come
SONY_RCVPKT_GROUPTO:
        MOVEQ.L #RdGroupTO,D0                   | RdGroupTO ($22)
        BRA     SONY_RCVPKT_EXIT                | exit

| DECODE -- decode a full group (to A1) while reading the next one
SONY_RCVPKT_DECODE:
        MOVEQ.L #0x3,D6                         | D6.hi = 3: A1 switches to A4 after 26 bytes
        SWAP    D6                              | (3 groups and 5 bytes)
        MOVE    #0x50,D6                        | D6.lo = 80 reads per group
SONY_RCVPKT_GROUP:
        LSR.B   #0x1,D4                         | its bit 0 -> X
        ADDX.B  D1,D1                           | data byte 1 = byte << 1 + X
        ADD.B   D1,D5                           | checksum
        MOVE.B  D1,(A1)+                        | store it
SONY_RCVPKT_NEXT1:
        MOVE.B  (A3),D1                         | next group: byte 1
        DBMI    D6,SONY_RCVPKT_NEXT1            | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D1                              | D1.lo = byte 2
        MOVE.B  #0x3,(A6)                       | SCC channel A: select RR3 (interrupt pending)
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D1,D1                           | data byte 2
        ADD.B   D1,D5                           | checksum
        MOVE.B  D1,(A1)+                        | store it
SONY_RCVPKT_NEXT2:
        MOVE.B  (A3),D1                         | next group: byte 2
        DBMI    D6,SONY_RCVPKT_NEXT2            | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D1                              | D1 = next bytes 1/2
        TST     D7                              | the group coming in is the last one?
        BEQ.B   SONY_RCVPKT_HOLDCHK             | yes -> no hold-off (D0 = 0)
        TST.B   (A5)                            | read RR3: SCC interrupt pending?
SONY_RCVPKT_HOLDCHK:
        SNE.B   D0                              | D0 = $FF: hold off after this group
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D2,D2                           | data byte 3
        ADD.B   D2,D5                           | checksum
        MOVE.B  D2,(A1)+                        | store it
SONY_RCVPKT_NEXT3:
        MOVE.B  (A3),D2                         | next group: byte 3
        DBMI    D6,SONY_RCVPKT_NEXT3            | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D2                              | D2.lo = byte 4
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D2,D2                           | data byte 4
        ADD.B   D2,D5                           | checksum
        MOVE.B  D2,(A1)+                        | store it
SONY_RCVPKT_NEXT4:
        MOVE.B  (A3),D2                         | next group: byte 4
        DBMI    D6,SONY_RCVPKT_NEXT4            | until there
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D2                              | D2 = next bytes 3/4
        TST.B   D0                              | hold off?
        BEQ.B   SONY_RCVPKT_BYTE5               | no ->
        TST.B   (A0)                            | ph0L: CA0 low: HD20, hold off after this group
SONY_RCVPKT_BYTE5:
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D3,D3                           | data byte 5
        ADD.B   D3,D5                           | checksum
        MOVE.B  D3,(A1)+                        | store it
SONY_RCVPKT_NEXT5:
        MOVE.B  (A3),D3                         | next group: byte 5
        DBMI    D6,SONY_RCVPKT_NEXT5            | until there
SONY_RCVPKT_GROUPTO2:
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout ->
        SWAP    D3                              | D3.lo = byte 6
        SWAP    D6                              | D6.lo = header count
        DBF     D6,SONY_RCVPKT_BYTE6            | header not done ->
        MOVE.L  A4,A1                           | 26 bytes done: the rest to the data buffer
SONY_RCVPKT_BYTE6:
        SWAP    D6                              | D6.lo = read count again
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D3,D3                           | data byte 6
        ADD.B   D3,D5                           | checksum
        MOVE.B  D3,(A1)+                        | store it
SONY_RCVPKT_NEXT6:
        MOVE.B  (A3),D3                         | next group: byte 6
        DBMI    D6,SONY_RCVPKT_NEXT6            | until there
        BPL.B   SONY_RCVPKT_GROUPTO2            | timeout ->
        SWAP    D3                              | D3 = next bytes 5/6
        LSR.B   #0x1,D4                         | bit 0 -> X
        SWAP    D4                              | D4.lo = byte 7
        ADDX.B  D4,D4                           | data byte 7
        ADD.B   D4,D5                           | checksum
        MOVE.B  D4,(A1)+                        | store it
SONY_RCVPKT_NEXT7:
        MOVE.B  (A3),D4                         | next group: byte 7
        DBMI    D6,SONY_RCVPKT_NEXT7            | until there
        BPL.B   SONY_RCVPKT_GROUPTO2            | timeout ->
        SWAP    D4                              | (high word)
        MOVE    #0x50,D6                        | 80 reads for the next group
SONY_RCVPKT_NEXT8:
        MOVE.B  (A3),D4                         | next group: byte 8 (bits 0)
        DBMI    D6,SONY_RCVPKT_NEXT8            | until there
        BPL.B   SONY_RCVPKT_GROUPTO2            | timeout ->
        TST.B   D0                              | hold off?
        DBNE    D7,SONY_RCVPKT_GROUP            | no: full groups left -> decode the next one
        BEQ.B   SONY_RCVPKT_LAST                | no: it is the last group -> decode it
        TST.B   (A5)                            | hold off: read the SCC (register pointer to 0)
        ANDI    #-0x701,SR                      | open interrupts: the SCC is serviced
        SUBQ.W  #0x1,D7                         | count the group (DBNE did not)
        MOVEQ.L #0x10,D0                        | short delay
SONY_RCVPKT_HOLDDELAY:
        DBF     D0,SONY_RCVPKT_HOLDDELAY        | (17 loops)
        ORI     #0x700,SR                       | no interrupts
        TST.B   ph0H(A0)                        | CA0 high: HD20, go on
        TST.B   (A3)                            | discard a stale byte
        CLR     D0                              | D0 = 0: 65536 reads for the $AA
| after a hold-off: wait for $AA again
SONY_RCVPKT_RESYNC:
        SUBQ.W  #0x1,D0                         | count
        BEQ.B   SONY_RCVPKT_HOFFTO              | timeout -> RdHoffSyncTO
        CMPI.B  #SyncByte,(A3)                  | $AA?
        BNE.B   SONY_RCVPKT_RESYNC              | no -> read again
        BRA     SONY_RCVPKT_GROUP               | yes -> decode the group read before

| RdHoffSyncTO -- no $AA after a hold-off
SONY_RCVPKT_HOFFTO:
        MOVEQ.L #RdHoffSyncTO,D0                | RdHoffSyncTO ($24)
        BRA.B   SONY_RCVPKT_EXIT                | exit

| LAST -- the last group: store its data bytes (D7.hi of them), add its
| 7th byte (the checksum) to the sum; then HSHK must be high again
SONY_RCVPKT_LAST:
        SWAP    D7                              | D7 = data bytes in the last group
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D1,D1                           | data byte 1
        ADD.B   D1,D5                           | checksum
        SUBQ.W  #0x1,D7                         | a data byte?
        BMI.B   SONY_RCVPKT_LAST2               | no ->
        MOVE.B  D1,(A1)+                        | store it
SONY_RCVPKT_LAST2:
        SWAP    D1                              | D1.lo = byte 2
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D1,D1                           | data byte 2
        ADD.B   D1,D5                           | checksum
        SUBQ.W  #0x1,D7                         | a data byte?
        BMI.B   SONY_RCVPKT_LAST3               | no ->
        MOVE.B  D1,(A1)+                        | store it
SONY_RCVPKT_LAST3:
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D2,D2                           | data byte 3
        ADD.B   D2,D5                           | checksum
        SUBQ.W  #0x1,D7                         | a data byte?
        BMI.B   SONY_RCVPKT_LAST4               | no ->
        MOVE.B  D2,(A1)+                        | store it
SONY_RCVPKT_LAST4:
        SWAP    D2                              | D2.lo = byte 4
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D2,D2                           | data byte 4
        ADD.B   D2,D5                           | checksum
        SUBQ.W  #0x1,D7                         | a data byte?
        BMI.B   SONY_RCVPKT_LAST5               | no ->
        MOVE.B  D2,(A1)+                        | store it
SONY_RCVPKT_LAST5:
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D3,D3                           | data byte 5
        ADD.B   D3,D5                           | checksum
        SUBQ.W  #0x1,D7                         | a data byte?
        BMI.B   SONY_RCVPKT_LAST6               | no ->
        MOVE.B  D3,(A1)+                        | store it
SONY_RCVPKT_LAST6:
        SWAP    D3                              | D3.lo = byte 6
        LSR.B   #0x1,D4                         | bit 0 -> X
        ADDX.B  D3,D3                           | data byte 6
        ADD.B   D3,D5                           | checksum
        SUBQ.W  #0x1,D7                         | a data byte?
        BMI.B   SONY_RCVPKT_LAST7               | no ->
        MOVE.B  D3,(A1)+                        | store it
SONY_RCVPKT_LAST7:
        LSR.B   #0x1,D4                         | bit 0 -> X
        SWAP    D4                              | D4.lo = byte 7
        ADDX.B  D4,D4                           | the checksum byte
        ADD.B   D4,D5                           | sum = 0 if all is well
        TST.B   ph1H(A0)                        | CA1 high: end of the packet
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVEQ.L #RdHsHiTO,D0                    | RdHsHiTO ($25): HSHK did not go high
        TST.B   q7L(A0)                         | Q7L: HSHK (status bit 7) high again?
        BPL.B   SONY_RCVPKT_EXIT                | no -> RdHsHiTO
        MOVE.B  D5,D0                           | D0 = checksum sum
        BEQ.B   SONY_RCVPKT_EXIT                | 0 -> noErr
        MOVEQ.L #RdChksumErr,D0                 | else RdChksumErr ($26)
| exit: SCC register pointer back to 0, CA1 high, CA0 low
SONY_RCVPKT_EXIT:
        TST.B   (A5)                            | read the SCC (register pointer to 0)
        TST.B   ph1H(A0)                        | CA1 high
        TST.B   (A0)                            | ph0L: CA0 low
        MOVEM.L (SP)+,D1-D7/A1/A4-A6            | restore registers
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST.B   D0                              | CCR = result
        RTS                                     | return (EQ = ok)

| -------------------------------------------------------------------------
| DCDSendPacket -- send a packet to the HD20: $AA, $80 + groups to send,
| $80 + groups to receive (counting the last ones), then groups of 8
| bytes: a byte with the bits 0 of the 7 data bytes (bit 0 for the first
| byte, bit 7 set), then the 7 bytes shifted right with bit 7 set (the
| HD20's own packets put the bit-0 byte last, see DCDRcvPacket). The
| last group carries the remaining bytes and the checksum (minus the sum
| of all bytes) as its 7th byte; two $00 bytes end the packet. The first
| 26 bytes come from DCDCmd.. (6-byte command block, TagBytes), the rest
| from A4. With an SCC interrupt pending the Mac holds off after a group:
| CA0 low, a $00 byte, write state off, interrupts open briefly, then
| CA0 high and the write goes on with a new $AA.
|   A0 = IWM, A3 = q6L (write handshake), A4 -> data; D1 = command;
|   D6/D7 = full groups to send / receive (SendCmd)
|   D0 (out), CCR -- 0 (EQ) or WrtHsLw, WrtHSLwTO, WrtHSHighTO
| Handshake: HSHK high (idle); CA0 high: request; the HD20 pulls HSHK
| low; CA1 low; the packet; CA1 high; the HD20 lets HSHK go high again.
Sony_DCDSendPacket:
        MOVE    SR,-(SP)                        | save the interrupt level
        MOVEM.L D1-D7/A1/A4-A6,-(SP)            | save registers
        ADDA    #DCDCmd,A1                      | A1 -> DCDCmd: command block, then TagBytes
        MOVEM.L (SCCRd).w,A5-A6                 | A5 = SCCRd, A6 = SCCWr
        ADDQ.W  #0x2,A5                         | A5 -> SCC channel A control (read)
        ADDQ.W  #0x2,A6                         | A6 -> SCC channel A control (write)
        MOVE.B  D1,D4                           | command
        SWAP    D4                              | (in the high word)
        SWAP    D6                              | D6.hi = groups to send for now,
        MOVE    D7,D6                           | D6.lo = groups to receive,
        SWAP    D6                              | swapped: D6.hi = receive, D6.lo = send
        MOVEQ.L #0x0,D5                         | checksum = 0
        ST.B    D4                              | D4.lo = $FF: the bit-0 byte of the first group
| the first 6 bytes (the command block): D1 = 1/2 (low/high word),
| D2 = 3/4, D3 = 5/6, each shifted right with bit 7 set
        MOVE.B  (A1)+,D1                        | byte 1 (DCDCmd)
        ADD.B   D1,D5                           | checksum
        ROXR.B  #0x1,D1                         | bit 0 -> X, shifted right
        ORI.B   #0x80,D1                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0 in D4
        SWAP    D1                              | (keep it)
        MOVE.B  (A1)+,D1                        | byte 2 (SeqNum)
        ADD.B   D1,D5                           | checksum
        ROXR.B  #0x1,D1                         | bit 0 -> X
        ORI.B   #0x80,D1                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D1                              | D1.lo = byte 1, D1.hi = byte 2
        MOVE.B  (A1)+,D2                        | byte 3 (StartBlock)
        ADD.B   D2,D5                           | checksum
        ROXR.B  #0x1,D2                         | bit 0 -> X
        ORI.B   #0x80,D2                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D2                              | (keep it)
        MOVE.B  (A1)+,D2                        | byte 4
        ADD.B   D2,D5                           | checksum
        ROXR.B  #0x1,D2                         | bit 0 -> X
        ORI.B   #0x80,D2                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D2                              | D2.lo = byte 3, D2.hi = byte 4
        MOVE.B  (A1)+,D3                        | byte 5
        ADD.B   D3,D5                           | checksum
        ROXR.B  #0x1,D3                         | bit 0 -> X
        ORI.B   #0x80,D3                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D3                              | (keep it)
        MOVE.B  (A1)+,D3                        | byte 6 (DriveOut)
        ADD.B   D3,D5                           | checksum
        ROXR.B  #0x1,D3                         | bit 0 -> X
        ORI.B   #0x80,D3                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D3                              | D3.lo = byte 5, D3.hi = byte 6
        SWAP    D4                              | D4.lo = command, D4.hi = bit-0 byte
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVEQ.L #WrtHsLw,D0                     | WrtHsLw ($10): HSHK must be high before we start
        TST.B   q7L(A0)                         | Q7L: read status, HSHK in bit 7
        BPL     SONY_SENDPKT_EXIT               | low -> error
        TST.B   ph0H(A0)                        | CA0 high: request to send
        MOVEQ.L #WrtHSLwTO,D0                   | WrtHSLwTO ($11): HSHK did not go low
        MOVEQ.L #0x14,D7                        | D7 = $140000
        SWAP    D7                              | status reads at most
| wait until the HD20 pulls HSHK low
SONY_SENDPKT_WAITLOW:
        SUBQ.L  #0x1,D7                         | count
        BEQ     SONY_SENDPKT_EXIT               | timeout -> error
        TST.B   q7L(A0)                         | HSHK (status bit 7)
        BMI.B   SONY_SENDPKT_WAITLOW            | still high -> wait
        TST.B   ph1L(A0)                        | CA1 low
        LEA.L   q6H(A0),A0                      | A0 -> IWM q6H: write data register (until the end)
        ORI     #0x700,SR                       | no interrupts
        MOVEQ.L #0x2,D7                         | D7 = 2: after 2 more groups and 5 bytes from
        CMPI.B  #0x4,D4                         | DCDCmd.. (26 bytes) continue at A4, for
        BLT.B   SONY_SENDPKT_SETUP              | commands 0-3 (read, write, status);
        MOVEQ.L #-0x1,D7                        | other commands: everything after the
        MOVE.L  A4,A1                           | command block from A4
SONY_SENDPKT_SETUP:
        MOVEQ.L #0x4,D0                         | short delay
SONY_SENDPKT_DELAY:
        DBF     D0,SONY_SENDPKT_DELAY           | (5 loops)
        MOVE.L  D6,D0                           | D0 = receive/send counts
        ADDI.L  #0x810081,D0                    | + $81 each: groups (with the last) + $80
        MOVE.B  #SyncByte,q7H-q6H(A0)           | Q7H: L7 = 1, write state; first byte $AA
SONY_SENDPKT_COUNT1:
        TST.B   (A3)                            | handshake bit 7: buffer empty?
        BPL.B   SONY_SENDPKT_COUNT1             | no -> wait
        MOVE.B  D0,(A0)                         | send $80 + groups to send
        SWAP    D0                              | D0.lo = $81 + groups to receive
SONY_SENDPKT_COUNT2:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_COUNT2             | no -> wait
        MOVE.B  D0,(A0)                         | send $80 + groups to receive
        MOVEQ.L #-0x80,D0                       | D0 = $80: bit 7 of every encoded byte
        BRA     SONY_SENDPKT_NEXT               | start the group loop

| GROUP -- send a full group (bytes 1-6 in D1-D3), fetching the next one
SONY_SENDPKT_GROUP:
        MOVE.B  (A1)+,D4                        | byte 7
        ADD.B   D4,D5                           | checksum
        ROXR.B  #0x1,D4                         | bit 0 -> X
        OR.B    D0,D4                           | bit 7 set
        SWAP    D4                              | D4.lo = the bit-0 byte, D4.hi = byte 7
        ROXR.B  #0x2,D4                         | collect bit 0 of byte 7, bit 7 = 1
SONY_SENDPKT_PUT0:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PUT0               | no -> wait
        MOVE.B  D4,(A0)                         | send the bit-0 byte
        ST.B    D4                              | start the next bit-0 byte
        MOVE.B  #0x3,(A6)                       | SCC channel A: select RR3 (interrupt pending)
SONY_SENDPKT_PUT1:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PUT1               | no -> wait
        MOVE.B  D1,(A0)                         | send byte 1
        MOVE.B  (A1)+,D1                        | next group: byte 1
        ADD.B   D1,D5                           | checksum
        ROXR.B  #0x1,D1                         | bit 0 -> X
        OR.B    D0,D1                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D1                              | D1.lo = byte 2
        TST.B   (A5)                            | read RR3: SCC interrupt pending?
        BEQ.B   SONY_SENDPKT_PUT2               | no ->
        BSET    #0x1F,D6                        | yes: D6 bit 31 = hold off after this group
SONY_SENDPKT_PUT2:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PUT2               | no -> wait
        MOVE.B  D1,(A0)                         | send byte 2
        MOVE.B  (A1)+,D1                        | next group: byte 2
        ADD.B   D1,D5                           | checksum
        ROXR.B  #0x1,D1                         | bit 0 -> X
        OR.B    D0,D1                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D1                              | D1 = next bytes 1/2
        TST     D6                              | full groups left after this one?
        BNE.B   SONY_SENDPKT_PUT3               | yes ->
        BCLR    #0x1F,D6                        | no: no hold-off before the last group
SONY_SENDPKT_PUT3:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PUT3               | no -> wait
        MOVE.B  D2,(A0)                         | send byte 3
        MOVE.B  (A1)+,D2                        | next group: byte 3
        ADD.B   D2,D5                           | checksum
        ROXR.B  #0x1,D2                         | bit 0 -> X
        OR.B    D0,D2                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D2                              | D2.lo = byte 4
        BTST    #0x1F,D6                        | hold off?
        BEQ.B   SONY_SENDPKT_PUT4               | no ->
        TST.B   ph0L-q6H(A0)                    | CA0 low: HD20, we hold off after this group
SONY_SENDPKT_PUT4:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PUT4               | no -> wait
        MOVE.B  D2,(A0)                         | send byte 4
        MOVE.B  (A1)+,D2                        | next group: byte 4
        ADD.B   D2,D5                           | checksum
        ROXR.B  #0x1,D2                         | bit 0 -> X
        OR.B    D0,D2                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D2                              | D2 = next bytes 3/4
SONY_SENDPKT_PUT5:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PUT5               | no -> wait
        MOVE.B  D3,(A0)                         | send byte 5
        MOVE.B  (A1)+,D3                        | next group: byte 5
        ADD.B   D3,D5                           | checksum
        ROXR.B  #0x1,D3                         | bit 0 -> X
        OR.B    D0,D3                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D3                              | D3.lo = byte 6
        DBF     D7,SONY_SENDPKT_PUT6            | command block and tags not done ->
        MOVE.L  A4,A1                           | done: continue with the data
SONY_SENDPKT_PUT6:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PUT6               | no -> wait
        MOVE.B  D3,(A0)                         | send byte 6
        MOVE.B  (A1)+,D3                        | next group: byte 6
        ADD.B   D3,D5                           | checksum
        ROXR.B  #0x1,D3                         | bit 0 -> X
        OR.B    D0,D3                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect bit 0
        SWAP    D3                              | D3 = next bytes 5/6
        SWAP    D4                              | D4.lo = byte 7
SONY_SENDPKT_PUT7:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PUT7               | no -> wait
        MOVE.B  D4,(A0)                         | send byte 7
        BCLR    #0x1F,D6                        | hold off?
        BNE.B   SONY_SENDPKT_HOLDOFF            | yes ->
SONY_SENDPKT_NEXT:
        DBF     D6,SONY_SENDPKT_GROUP           | full groups left -> next group
        BRA.B   SONY_SENDPKT_LAST               | else the last group

| HOLDOFF -- a $00 byte, write state off, interrupts open briefly (the
| SCC is serviced), CA0 high, then the write state again with $AA
SONY_SENDPKT_HOLDOFF:
        CLR.B   D0                              | D0 = $00
SONY_SENDPKT_HOLD0:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_HOLD0              | no -> wait
        MOVE.B  D0,(A0)                         | send $00
        ANDI    #-0x701,SR                      | open interrupts
        MOVE    #0x10,D0                        | short delay
SONY_SENDPKT_HOLDDELAY1:
        DBF     D0,SONY_SENDPKT_HOLDDELAY1      | (17 loops)
        SUBQ.W  #0x1,D6                         | count this group (its DBF is skipped)
        TST.B   q7L-q6H(A0)                     | Q7L: L7 = 0, write state off
        TST.B   q6L-q6H(A0)                     | Q6L: L6 = 0
        TST.B   (A0)                            | Q6H (A0 = q6H): L6 = 1, status register selected
        TST.B   ph0H-q6H(A0)                    | CA0 high: HD20, go on
        MOVE    #0x10,D0                        | short delay
SONY_SENDPKT_HOLDDELAY2:
        DBF     D0,SONY_SENDPKT_HOLDDELAY2      | (17 loops)
        MOVEQ.L #-0x80,D0                       | D0 = $80 again
        ORI     #0x700,SR                       | no interrupts
        MOVE.B  #SyncByte,q7H-q6H(A0)           | Q7H: write state again, $AA
        BRA     SONY_SENDPKT_GROUP              | send the next group

| LAST -- the last group: bytes 1-6 (D1-D3), the checksum as byte 7,
| then two $00; wait for HSHK high (the HD20 has the packet)
SONY_SENDPKT_LAST:
        NEG.B   D5                              | checksum = -sum
        ROXR.B  #0x1,D5                         | bit 0 -> X
        OR.B    D0,D5                           | bit 7 set
        SWAP    D4                              | D4.lo = the bit-0 byte
        ROXR.B  #0x2,D4                         | collect the checksum's bit 0, bit 7 = 1
SONY_SENDPKT_LPUT0:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_LPUT0              | no -> wait
        MOVE.B  D4,(A0)                         | send the bit-0 byte
SONY_SENDPKT_LPUT1:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_LPUT1              | no -> wait
        MOVE.B  D1,(A0)                         | send byte 1
        SWAP    D1                              | bytes 2, 4, 6 are in the high words
SONY_SENDPKT_LPUT2:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_LPUT2              | no -> wait
        MOVE.B  D1,(A0)                         | send byte 2
SONY_SENDPKT_LPUT3:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_LPUT3              | no -> wait
        MOVE.B  D2,(A0)                         | send byte 3
        SWAP    D2                              | next
SONY_SENDPKT_LPUT4:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_LPUT4              | no -> wait
        MOVE.B  D2,(A0)                         | send byte 4
SONY_SENDPKT_LPUT5:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_LPUT5              | no -> wait
        MOVE.B  D3,(A0)                         | send byte 5
        SWAP    D3                              | next
SONY_SENDPKT_LPUT6:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_LPUT6              | no -> wait
        MOVE.B  D3,(A0)                         | send byte 6
SONY_SENDPKT_CKSUM:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_CKSUM              | no -> wait
        MOVE.B  D5,(A0)                         | send the checksum
SONY_SENDPKT_PAD1:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PAD1               | no -> wait
        MOVEQ.L #0x0,D0                         | then two $00 bytes
        MOVE.B  D0,(A0)                         | send $00
SONY_SENDPKT_PAD2:
        TST.B   (A3)                            | empty?
        BPL.B   SONY_SENDPKT_PAD2               | no -> wait
        MOVE.B  D0,(A0)                         | send $00
        MOVE.L  (IWM).w,A0                      | A0 = IWM base
        TST.B   ph1H(A0)                        | CA1 high: end of the packet
        MOVEQ.L #WrtHSHighTO,D0                 | WrtHSHighTO ($13): HSHK did not go high
        MOVEQ.L #-0x1,D7                        | 65535 reads at most
SONY_SENDPKT_WAITHIGH:
        SUBQ.W  #0x1,D7                         | count
        BEQ.B   SONY_SENDPKT_EXIT               | timeout -> error
        TST.B   q7L(A0)                         | Q7L: ends the write state; L6 = 1: status, HSHK in bit 7
        BPL.B   SONY_SENDPKT_WAITHIGH           | still low -> wait
        MOVEQ.L #0x0,D0                         | noErr
| exit: CA1 high, CA0 low
SONY_SENDPKT_EXIT:
        TST.B   ph1H(A0)                        | CA1 high
        TST.B   (A0)                            | ph0L: CA0 low
        MOVEM.L (SP)+,D1-D7/A1/A4-A6            | restore registers
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST.B   D0                              | CCR = result
        RTS                                     | return (EQ = ok)

| DCDReset -- jump through the JDCDReset vector
E_Sony_DCDReset:
        MOVE.L  (JDCDReset).w,-(SP)             | push the JDCDReset vector
        RTS                                     | and jump through it

| -------------------------------------------------------------------------
| jtDCDReset (JDCDReset vector) -- hard reset of the HD20: select it,
| address register 1 (dcdReset: CA1, CA0 low, CA2 high) for tRstAssert
| (100 ms), release it, wait tRstSettle (2 s), then until the HD20 lets
| HSHK go high (every tRstChk, 10 ms, for at most tRstMax, 16 s).
| Returns through A3 (WakeUp: the caller's caller runs meanwhile).
|   D0 (out), CCR -- 0 or -1 (timeout)
Sony_DCDReset:
        MOVE.L  (SP)+,A3                        | A3 = return address
        BSR     Sony_DiskSelect                 | DiskSelect: select the HD20 (A0 = IWM)
        TST.B   ph2H(A0)                        | CA2 high
        TST.B   ph1L(A0)                        | CA1 low
        TST.B   (A0)                            | ph0L: CA0 low: address 1 = dcdReset
        MOVE    #tRstAssert,D0                  | tRstAssert: 1000 * 100 us = 100 ms
        BSR     E_Sony_WakeUp                   | WakeUp
        TST.B   ph1H(A0)                        | CA1 high
        TST.B   ph2L(A0)                        | CA2 low: reset released; sense = HSHK
        MOVE    #tRstSettle,D0                  | tRstSettle: 20000 * 100 us = 2 s
        BSR     E_Sony_WakeUp                   | WakeUp
        MOVE    #tRstChk,ChkTime(A1)            | ChkTime = tRstChk: check every 10 ms
        MOVE    #tRstMax,MaxTime(A1)            | MaxTime = tRstMax: 1600 checks = 16 s
| wait until HSHK is high (the HD20 is ready)
SONY_DCDRESET_CONT:
        BSR     Sony_Sense                      | Sense: HSHK (status bit 7)
        BMI.B   SONY_DCDRESET_SKIP              | high -> ready
        SUBQ.W  #0x1,MaxTime(A1)                | checks left?
        BMI.B   SONY_DCDRESET_SKIP_2            | no -> timeout
        MOVE    ChkTime(A1),D0                  | D0 = ChkTime
        BSR     E_Sony_WakeUp                   | WakeUp
        BRA.B   SONY_DCDRESET_CONT              | check again

| ready
SONY_DCDRESET_SKIP:
        MOVEQ.L #0x0,D0                         | noErr
        JMP     (A3)                            | return

| timeout
SONY_DCDRESET_SKIP_2:
        TST.B   q6L(A0)                         | Q6L: L6 = 0, back to read mode
        MOVEQ.L #-0x1,D0                        | D0 = -1
        JMP     (A3)                            | return

| ICONDONE -- back from the status command of an icon call: return a
| pointer to the icon (DevIcon, part of the HD20's status data)
SONY_DCD_ICONDONE:
        BNE.B   SONY_DCD_ICONEXIT               | status command failed -> return the error
        LEA.L   DevIcon(A1),A2                  | A2 -> DevIcon (StsBuffer + 44)
        MOVE.L  (A1),A0                         | A0 = DCE
        MOVE.L  dCtlQHead(A0),A0                | A0 = the request (dCtlQHead)
        MOVE.L  A2,csParam(A0)                  | csParam = pointer to the icon
SONY_DCD_ICONEXIT:
        BRA     SONY_DCDEXIT                    | complete the request (DCD exit)

| -------------------------------------------------------------------------
| HD20 icon call (csCode 21, drives 3-6): only if the HD20 has an icon
| (DevChIcon in its characteristics byte); the icon comes with the status
| data, so a status command is sent first ("The Hard Disk 20 icon is in
| the drive's ROM", Technical Note #272).
SONY_DCD_ICON:
        BTST    #DevChIcon,DriveChar(A1,D1.W)   | DriveChar bit 2 (DevChIcon): icon available?
        BEQ     Sony_DiskCtlErr                 | no -> controlErr
        LEA.L   SONY_DCD_ICONDONE(PC),A0        | continue at ICONDONE after the status command
        MOVE.L  A0,StsRtnAddr(A1)               | StsRtnAddr
| -------------------------------------------------------------------------
| DCDStatus, HD20 verify (csCode 5) and format (csCode 6) -- send a one-
| block HD20 command (3 = status, $1A = verify, $19 = format) and wait
| for the response, with a retry and a hard reset. After a status
| command continue at StsRtnAddr with D0/CCR = result, after the others
| complete the request. (Technical Note #272: format "initializes the
| data of each sector to all zeroes"; a failed format or verify returns
| controlErr.)
Sony_DCDStatus:
        MOVEQ.L #0x3,D3                         | HD20 command 3: status
        BRA.B   SONY_DCD_COMMAND                | send it

| HD20 verify (csCode 5)
SONY_DCD_VERIFY:
        MOVEQ.L #0x1A,D3                        | HD20 command $1A: verify
        BRA.B   SONY_DCD_COMMAND                | send it

| HD20 format (csCode 6)
SONY_DCD_FORMAT:
        MOVEQ.L #0x19,D3                        | HD20 command $19: format
SONY_DCD_COMMAND:
        BSR     Sony_DiskSelect                 | DiskSelect: select the HD20
        TST.B   (A0)                            | ph0L: CA0 low
        TST.B   ph2L(A0)                        | CA2 low
        CLR.B   DCDFlags(A1)                    | DCDFlags = 0: no retry or reset yet
        MOVE.B  D3,DCDCmd(A1)                   | DCDCmd = command
SONY_DCD_COMMAND_RETRY:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        ANDI.B  #0x3F,DCDCmd(A1)                | DCDCmd: clear flag bits 6-7
        SUBA.L  A4,A4                           | A4 = 0: no data buffer
        SUBA.L  A5,A5                           | A5 = 0: no tag buffer
        MOVEQ.L #0x1,D3                         | one block
        MOVEQ.L #0x0,D6                         | nothing to send
        MOVEQ.L #0x0,D7                         | nothing to receive
        MOVE    #tFVChk,ChkTime(A1)             | ChkTime = tFVChk: check every 10 ms
        MOVE    #tFVMax,MaxTime(A1)             | MaxTime = tFVMax: 18000 checks = 3 minutes
        CMPI.B  #0x3,DCDCmd(A1)                 | status command?
        BNE.B   SONY_DCD_COMMAND_SEND           | no ->
        MOVE.L  #0x14C,D7                       | receive 332 bytes of status (20 to DevType.., the rest to A4)
        MOVE    #tStsChk,ChkTime(A1)            | ChkTime = tStsChk: check every 1 ms
        MOVE    #tStsMax,MaxTime(A1)            | MaxTime = tStsMax: 10000 checks = 10 s
        LEA.L   StsBuffer(A1),A4                | A4 -> StsBuffer
SONY_DCD_COMMAND_SEND:
        BSR     E_Sony_SendCmd                  | SendCmd: send the command
        BEQ.B   SONY_DCD_COMMAND_WAIT           | sent -> wait for the response
| error: reset (only once: then give up) if the first LastStatus byte is
| 2 or bChksum is clear; with bChksum set the first error resets too
| (BSET of retryonce falls through), later ones just retry. (DCDPrime
| tests LastResult = comErr where this tests the first LastStatus byte.)
SONY_DCD_COMMAND_ERR:
        CMPI.B  #0x2,LastStatus(A1)             | first byte of LastStatus = 2?
        BEQ.B   SONY_DCD_COMMAND_RESET          | yes -> reset
        BTST    #bChksum,LastStatus(A1)         | bChksum (bit 6 of the first LastStatus byte)?
        BEQ.B   SONY_DCD_COMMAND_RESET          | no -> reset
        BSET    #retryonce,DCDFlags(A1)         | retryonce set before?
        BNE.B   SONY_DCD_COMMAND_RETRY          | yes -> send the command again
SONY_DCD_COMMAND_RESET:
        BSET    #resetonce,DCDFlags(A1)         | resetonce set before?
        BNE.B   SONY_DCD_COMMAND_FAIL           | yes -> give up
        BSR     E_Sony_DCDReset                 | DCDReset
        BNE.B   SONY_DCD_COMMAND_FAIL           | failed -> give up
        BRA.B   SONY_DCD_COMMAND_RETRY          | send the command again

| wait for the response and receive it
SONY_DCD_COMMAND_WAIT:
        BSR     SONY_DCDWAITHSHK                | DCDWaitHSHK (ChkTime/MaxTime)
        BMI.B   SONY_DCD_COMMAND_ERR            | timeout -> error handling
        BSR     Sony_DCDRcvResponse             | DCDRcvResponse
        TST     D0                              | error?
        BNE.B   SONY_DCD_COMMAND_ERR            | yes -> error handling
        MOVEQ.L #0x0,D0                         | noErr
        BRA.B   SONY_DCD_COMMAND_END            | done

| failed (after a reset)
SONY_DCD_COMMAND_FAIL:
        MOVEQ.L #controlErr,D0                  | controlErr (-17)
SONY_DCD_COMMAND_END:
        CMPI.B  #0x3,DCDCmd(A1)                 | status command?
        BEQ.B   SONY_DCD_COMMAND_STS            | yes -> continue at StsRtnAddr
        BRA     SONY_DCDEXIT                    | else complete the request (DCD exit)

| status command done: continue at StsRtnAddr
SONY_DCD_COMMAND_STS:
        MOVE.L  StsRtnAddr(A1),A0               | A0 = StsRtnAddr
        TST     D0                              | CCR = result
        JMP     (A0)                            | continue there
    ROM_RESOURCE_END DRVR_4                     | end of the data: pads to even, sets the sizes

| end of resource : 'DRVR' 4 '.Sony'

