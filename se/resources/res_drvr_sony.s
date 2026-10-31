| =========================================================================
| DRVR 4 .Sony -- the 800K disk driver of the Macintosh SE (1987)
| =========================================================================
| ROM offsets +0x34680..+0x36C87 (resource body, 9736 bytes) of the 1987
| Mac SE ROM ($B2E362A8). The 8-byte resource header at +0x34678 is in
| resources/res_drvr_sony_fdhd.s: the SE FDHD ROM (1989) replaced
| this driver by its SuperDrive (SWIM, MFM) .Sony driver in the same slot,
| so that file holds the SE FDHD driver and this one is assembled only for
| the MAC_SE target.
|
| The driver runs the IWM floppy disk controller for up to three 400K/800K
| GCR drives -- the SE has room for two internal drives -- and Hard Disk 20
| drives (HD20, "DCD" = direct connect device) daisy-chained on the
| external floppy port:
|   drive 1   lower internal floppy   (VIA port A bit 4 = 1, vDriveSel)
|   drive 2   upper internal floppy   (VIA port A bit 4 = 0)
|   drive 3   external floppy
|   drive 4,5 first and second HD20   (driver refNum -2, unit 1)
| These are physical drive numbers; DiskOpen hands out logical drive
| numbers 1, 2, ... to the floppy drives it finds, in this order, and the
| translation table at SonyVars+$16C maps them back (Inside Macintosh
| V-469). Register conventions: A1 = SonyVars, D1 = offset of the current
| drive's variables, A0 = IWM base, A2 = VIA base.
|
| The IWM (IWM Design Spec; SWIM Chip User's Ref, "Using the IWM
| Hardware") has 8 state bits; its address lines A3-A1 select one and A0
| is the value it gets, so an access to an "H" address sets the bit and
| an access to an "L" address clears it. IWM A0-A3 are CPU A9-A12, so the
| 16 addresses are $200 apart (equates ph0L..q7H in include/sysequ.inc):
|   ph0L-ph3H   phase lines PH0-PH3 = the drive's CA0, CA1, CA2, LSTRB
|   mtrOff/On   LMotor-On: drive enable /ENBLx low (a floppy drive powers
|               down when its enable is cut -- Apple's SonyUtil.a)
|   intDrive    Drive-Sel = 0: /ENBL1, internal drives
|   extDrive    Drive-Sel = 1: /ENBL2, external port
|   q6L-q7H     L6, L7
| L7, L6 and the motor-on state select the register: 0 0 (motor on) read
| data; 0 1 read status (bits 0-4 = mode register, bit 5 = an enable is
| active, bit 7 = SENSE input); 1 0 read the write handshake (bit 7 =
| buffer empty, bit 6 = 0 after an underrun); 1 1, motor off: write the
| mode register; 1 1, motor on: write data. Registers are read at "L"
| addresses (A0 = 0) and written at "H" addresses (A0 = 1; IWM undoco
| features: "Stores for writing to registers must always be done to bit
| setting locations"). A drive has 16 sense and control
| "registers" addressed by CA2, CA1, CA0 and SEL (VIA port A bit 5,
| vHeadSel); D0 holds such an address as CA1-CA0-SEL-CA2 in bits 3-0
| (SonyEqu.a). A sense register is read as status bit 7 (Sense); a
| control register is written by pulsing LSTRB, CA2 being the value
| written (AdrAndStrb). The registers this driver uses (address, Apple's
| SonyEqu.a name):
|   sense    2 DIPAdr     0 = disk in place    6 WrProtAdr 0 = write-protected
|            4 StepLAdr   0 = step under way   9 SidesAdr  1 = two-sided drive
|            8 MtrOnAdr   0 = motor on        10 Tk0Adr    0 = head on track 0
|           11 ReadyAdr   0 = ready           12 EjectLAdr 1 = eject button pressed
|           13 DrvExstAdr 0 = drive connected 14 TachAdr   tachometer, 60 pulses/turn
|           15 NewIntfAdr 1 = ready handshake (800K drive)
|   control  0/1 DirLAdr/DirHAdr: step direction in/out, 4 StepLAdr: step,
|            8 MtrOnAdr/9 MtrOffAdr: motor on/off, 13 EjectHAdr: eject
|   1/3 RdDtaAdr/RdDta1Adr select head 0/1 for reading; a strobe at
|   address 3 resets the eject button latch (CkEjSw). An HD20 answers at
|   5 (/Exist, CkDCDExist) and is reset through 1 (DCDReset).
|
| Relation to the Mac Plus driver (src/plus/resources/res_drvr_sony.s):
| both come from Apple's Sony driver sources (Larry Kenyon, 1983-86).
| 90% of the Mac Plus driver's bytes reappear here (77% of this driver),
| most of the code matches instruction for instruction, and the Mac Plus
| comments are carried over where it does. In terms of Apple's change
| history the SE driver includes A351 (5 Nov 1986: grow-zone procedure
| removed, SetIWMMode separated from Recal), but not C511 (12 Dec 1986:
| interrupts off in WakeUp -- System patch P014 adds this for this ROM)
| nor the SWIM/SuperDrive work (C437). Compared with the Mac Plus driver
| it adds or changes:
|   - support for the second internal drive: DiskSelect drives VIA PA4,
|     the third floppy's 66-byte variables are inserted at SonyVars+$CE,
|     so the driver variables from WakeTimeCnt to TimeQEl are $42 bytes
|     higher than in the Mac Plus driver, and the HD20 variables follow
|     the translation table; SonyVars is $344 bytes (Mac Plus: $310);
|     drive numbers go up to 5 (Mac Plus: 1-2 floppy, 3-6 HD20)
|   - the drive number translation table, GetDrive/GetDrv1 translate,
|     GetRDrive does not
|   - a rewritten control dispatcher with a table for all csCodes and
|     separate floppy/HD20 handlers; new csCodes 22 (media icon) and 23
|     (drive information), csCode 21 also for floppy drives, with DrvTbl
|     and four 32x32 icons (Apple's SonyIcon.a)
|   - the VBL task polls the eject button of drives with a disk and posts
|     an eject request; it runs at IPL 3 instead of 1
|   - no grow-zone procedure (TCdispose is only used by csCode 9)
|   - the read, write and format code reach the IWM through the low-memory
|     pointer IWM ($1E0) instead of absolute addresses (FigTrkSpd still
|     uses the absolute address, DBase = $DFE1FF); SetIWMMode is a
|     separate routine and sets IWM mode $17, slow mode (Mac Plus: $1F,
|     fast mode; see SetIWMMode)
|   - WakeUp saves the caller's state before priming the timer;
|     FigTrkSpd re-arms VIA timer 2 when it is done
|   - no speed check in ReSeek for drives with the new interface
|   - HD20: DCDReset selects the drive first, the command byte's flag
|     bits are cleared before it is tested
|
| Names: routines carry the names of Apple's Sony driver sources (System
| 7.1 Drivers/Sony: Sony.a, SonyRWT.a, SonyUtil.a, SonyFormat.a,
| SonyIcon.a -- a later version of the same code) where the code matches;
| the HD20 code, which is not in those sources, and local labels keep or
| extend the Mac Plus driver's names.
|
| Drive variables (include/sonyequ.inc, as in the Mac Plus driver),
| offsets from Drive1-Drive3 (66 bytes) or Drive4/Drive5 (HD20, 28
| bytes): Track (0, word; negative = unknown), WriteProt (2, bit 7 =
| write-protected), DiskInPlace (3: 0 no disk, 1 in place, 2 clamped, 8
| HD20 with a fixed medium; $FC-$FF just ejected, counting up to 0),
| Installed (4: 1 connected, $FF not connected, 0 unknown), Sides (5,
| $FF = two-sided drive), DQEl (6, the drive queue element), and for
| floppy drives TwoSideFmt (18), NewIntf (19), DriveErrs (20), SpdAdjCnt
| (24) and TrkSpeedTbl (26, 400K drives: 5 zones x TSTblCode, TSTblDelta,
| TSTblTicks), for HD20s DriveSize (18), DriveS1 (20), DriveType (22)
| and DriveChar (26).
|
| SonyVars layout of this driver (Apple's SonyEqu.a for onMacPP, the SE;
| include/sonyequ.inc has the Mac Plus layout, valid only below $CE; the
| variables from $CE on are defined as SE_ equates below):
|   $004A/$008C/$00CE  drive variables of drives 1/2/3 (66 bytes each)
|   $0110 WakeTimeCnt $0112 SaveRegs $0136 TagBufPtr  $013A TagBufOS
|   $013C DiskErrs   $013E PassThru   $0140 CurSector  $0142 TCRdEnable
|   $0143 TCInstalled $0144 TCDrive   $0146 TCSideTrack $0148 TCSectMap
|   $014C TCBuffer   $0150 TCNumCached $0152 TCNumUsed $0154 LastDrive
|   $0158 TimeOutDrive $015A TimeQEl  $0168 NextGZProc (not used)
|   $016C drive number translation table (6 words)
|   $0178/$0194      HD20 drive variables of drives 4/5 (28 bytes each;
|                    $01B0: a third HD20 slot, not used)
|   $01CC StsRtnAddr $01D0 DCDCmd     $01D1 SeqNum     $01D2 StartBlock
|   $01D6 TagBytes   $01EA BufSize    $01EE LastStatus $01F2 LastResult
|   $01F3 DCDFlags   $01F4 ChkTime    $01F6 MaxTime    $01F8 StsBuffer
|   $0224 DevIcon    $0344 end (DiskVarLth)
| =========================================================================
.if ROM_TARGET == MAC_SE
| -------------------------------------------------------------------------
| SonyVars of this driver from $CE on, after Apple's SonyEqu.a (layout for
| onMacPP = Macintosh SE; include/sonyequ.inc has the Mac Plus layout,
| whose equates from WakeTimeCnt on do not apply here), and three equates
| the include files lack.
| -------------------------------------------------------------------------
.set SE_Drive3, Drive2+DrvLclLth                | $0CE drive vars of drive 3, the external floppy
.set SE_WakeTimeCnt, SE_Drive3+DrvLclLth        | $110 WakeUp remainder count (not used)
.set SE_SaveRegs, SE_WakeTimeCnt+2              | $112 WakeUp/EmptyPD register save area (36 bytes)
.set SE_TagBufPtr, SE_SaveRegs+36               | $136 separate tag buffer (csCode 8), 0 = none
.set SE_TagBufOS, SE_TagBufPtr+4                | $13A offset of the current block's tags in it
.set SE_DiskErrs, SE_TagBufOS+2                 | $13C soft error count, all drives
.set SE_PassThru, SE_DiskErrs+2                 | $13E 0 if pass-thru works on the external port
.set SE_CurSector, SE_PassThru+2                | $140 sector being read/written ($13F unused)
.set SE_TCRdEnable, SE_CurSector+2              | $142 (byte) non-zero: read into the track cache
.set SE_TCInstalled, SE_TCRdEnable+1            | $143 (byte) non-zero: cache installed and on
.set SE_TCDrive, SE_TCInstalled+1               | $144 (word) drive of the cached track, 0 = invalid
.set SE_TCSideTrack, SE_TCDrive+2               | $146 (word) side/track of the cached track
.set SE_TCSectMap, SE_TCSideTrack+2             | $148 (long) bitmap of the cached sectors
.set SE_TCBuffer, SE_TCSectMap+4                | $14C (long) cache buffer, 12 * (12 + 512) bytes
.set SE_TCNumCached, SE_TCBuffer+4              | $150 (word) sectors read into the cache
.set SE_TCNumUsed, SE_TCNumCached+2             | $152 (word) sectors taken from the cache
.set SE_LastDrive, SE_TCNumUsed+2               | $154 (word) Drive before the last CkDrvNum
.set SE_TimeOutDrive, SE_LastDrive+4            | $158 (word) drive of a pending power-down (Apple: +4 "should have been +2")
.set SE_TimeQEl, SE_TimeOutDrive+2              | $15A Time Manager element of WakeUp (14 bytes)
.set SE_DriveXlat, SE_TimeQEl+0x0E+4            | $16C drive number translation table, 6 words ($168: NextGZProc, unused)
.set SE_Drive4, SE_DriveXlat+12                 | $178 drive vars of drive 4, first HD20 (28 bytes)
.set SE_Drive5, SE_Drive4+DCDLclLth             | $194 drive 5, second HD20 ($1B0: unused third slot)
.set SE_StsRtnAddr, SE_Drive5+2*DCDLclLth       | $1CC continuation after an HD20 status command
.set SE_DCDCmd, SE_StsRtnAddr+4                 | $1D0 HD20 command byte
.set SE_Response, SE_DCDCmd                     | $1D0 HD20 response byte (command + $80)
.set SE_SeqNum, SE_DCDCmd+1                     | $1D1 block count / sequence number
.set SE_Status, SE_SeqNum+1                     | $1D2 status bytes returned by the HD20
.set SE_StartBlock, SE_Status                   | $1D2 starting block number (commands)
.set SE_TagBytes, SE_Status+4                   | $1D6 20 tag bytes of a block
.set SE_DevType, SE_TagBytes                    | $1D6 status data: device type, manufacturer
.set SE_DevChar, SE_TagBytes+4                  | $1DA status data: characteristics, block count
.set SE_BufSize, SE_TagBytes+TagSize            | $1EA bytes per block (send + receive)
.set SE_LastStatus, SE_BufSize+4                | $1EE last status returned
.set SE_LastResult, SE_LastStatus+4             | $1F2 error type: nonZerStat or comErr
.set SE_DCDFlags, SE_LastResult+1               | $1F3 bit 0 resetonce, bit 1 retryonce
.set SE_ChkTime, SE_DCDFlags+1                  | $1F4 100-us units between handshake checks
.set SE_MaxTime, SE_ChkTime+2                   | $1F6 number of checks left
.set SE_StsBuffer, SE_MaxTime+2                 | $1F8 status data of the HD20 (332 bytes)
.set SE_DevIcon, SE_StsBuffer+44                | $224 HD20 icon (in the status data)
.set SE_DiskVarLth, SE_DevIcon+256+32           | $344 size of SonyVars
.set iwmMode, 0x17                              | IWM mode register value of the SE (SonyEqu.a)
| -------------------------------------------------------------------------
| DRVR header (Inside Macintosh II-188): flags, delay, event mask, menu,
| the offsets of the five entry points from the start of the header,
| and the driver name.
| -------------------------------------------------------------------------
Driver_Sony:
_DRVR_4_.Sony:
        .short  0x4F00                          | drvrFlags: dNeedLock+dStatEnable+dCtlEnable+dWritEnable+dReadEnable
        .short  0x0000                          | drvrDelay: no periodic action
        .short  0x0000                          | drvrEMask: no desk accessory events
        .short  0x0000                          | drvrMenu: no menu
        .short  E_Sony_Open-Driver_Sony         | drvrOpen: $006E
        .short  E_Sony_Prime-Driver_Sony        | drvrPrime: $038C
        .short  E_Sony_Control-Driver_Sony      | drvrCtl: $01F6
        .short  E_Sony_Status-Driver_Sony       | drvrStatus: $033E
        .short  E_Sony_Close-Driver_Sony        | drvrClose: $0018
        .byte   5                               | drvrName: length byte
        .ascii  ".Sony"                         | drvrName: driver name

| -------------------------------------------------------------------------
| DiskClose -- the driver cannot be closed: return closErr.
| -------------------------------------------------------------------------
E_Sony_Close:
        MOVEQ.L #-0x18,D0                       | closErr: driver not closeable
        RTS                                     | return error to Device Manager

| -------------------------------------------------------------------------
| InitDskTbl -- word offsets (relative to INITDSKTBL) of the disk routines
| whose addresses DiskOpen stores in the 15 jump vectors of DiskVars
| (JFigTrkSpd..NiblTbl, $222-$25A). Patches can redirect a routine by
| changing its vector.
| -------------------------------------------------------------------------
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
| ReadErrInit (+$2A) on; the same 32 bytes as in the Mac Plus driver
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

| -------------------------------------------------------------------------
| DispSetUp -- convert word offsets into absolute jump vectors.
|   A0 (in/out) -- next offset in the table
|   A1 (in/out) -- next jump vector
|   D0 (in)     -- base address the offsets are relative to
|   D1 (in)     -- number of vectors - 1
| -------------------------------------------------------------------------
DISPSETUP:
        MOVEQ.L #0x0,D2                         | clear high word for 32-bit add
        MOVE    (A0)+,D2                        | get next word offset from table
        ADD.L   D0,D2                           | compute absolute address = base + offset
        MOVE.L  D2,(A1)+                        | store vector in jump table
        DBF     D1,DISPSETUP                    | loop for all entries
        RTS                                     | return from DISPSETUP

| =========================================================================
| DiskOpen -- driver initialization (called once at boot, A1 = DCE)
|
| Allocates the $344-byte SonyVars block (Mac Plus: $310), sets up the
| drive number translation table, the disk routine vectors and the
| tuneable constants, installs the VBL task (disk-in-place polling and
| motor power-down) and the Time Manager element used by WakeUp, checks
| whether an HD20 on the external port passes requests through, and
| finally looks for connected drives:
|   drive 1   lower internal floppy  (VIA PA4 = 1)
|   drive 2   upper internal floppy  (VIA PA4 = 0, new on the SE)
|   drive 3   external floppy
|   drives 4,5 HD20 (DCD) on the external port
| Each connected drive gets a drive queue element (_AddDrive). Floppy
| drives are given consecutive logical drive numbers 1, 2, ... in the
| order found, and the translation table at SonyVars+$16C is updated so
| that logical drive number n selects the n-th connected floppy (see
| Inside Macintosh V-469: with one internal and one external drive the
| external drive becomes drive 2 instead of drive 3).
| Unlike the Mac Plus driver, no grow-zone procedure is installed.
| =========================================================================
E_Sony_Open:
        MOVE.L  #SE_DiskVarLth,D0               | DiskVarLth: $344 bytes of driver variables
        _NewPtrSysClear                         | allocate zeroed system heap block
        MOVE.L  A0,(SonyVars).w                 | store SonyVars ptr in low memory
        MOVE.L  A1,(A0)                         | DiskUnitPtr: save DCE ptr at offset 0
        MOVE.L  (UTableBase).w,A2               | unit table base
        MOVE.L  0x10(A2),0x4(A2)                | unit 1 (refNum -2, HD20 drives) shares the .Sony DCE
        MOVE.B  #0x1,dCtlQueue+1(A1)            | driver version 1 (DCtlQueue+1)
        ST.B    Active(A0)                      | Active: mark driver active (exclude VBL)
        LEA.L   SE_DriveXlat(A0),A2             | A2 -> drive number translation table (SonyVars+$16C)
        MOVEQ.L #0x0,D0                         | entry 0 = 0
SONY_OPEN_XLATINIT:
        MOVE.W  D0,(A2)+                        | entry n = n: identity mapping to start with
        ADDQ.W  #0x1,D0                         | next entry
        CMPI.W  #0x5,D0                         | entries 0-5 (drive numbers 0-5) done?
        BLE.B   SONY_OPEN_XLATINIT              | no -> continue
        MOVE.L  A0,A2                           | A2 = SonyVars for later use
| initialize the disk routine jump table (15 vectors)
        LEA.L   INITDSKTBL(PC),A0               | point to InitDskTbl offset table
        LEA.L   (DiskVars_JFigTrkSpd).w,A1      | first jump table entry
        MOVEQ.L #0xE,D1                         | 15 vectors (0..14)
        MOVE.L  A0,D0                           | base address for offset computation
        BSR.B   DISPSETUP                       | DispSetUp: convert to absolute addrs
        LEA.L   (JDiskSel).w,A1                 | JDiskSel ($B40): DiskSel, SendCmd, DCDReset
        MOVEQ.L #0x2,D1                         | 3 more vectors
        BSR.B   DISPSETUP                       | install them
        ST.B    OneToOne(A2)                    | OneToOne: set 1:1 flag (legacy, unused)
| copy tuneable drive constants (32 bytes) into SonyVars
        LEA.L   ReadErrInit(A2),A1              | dest: ReadErrInit(A2)
        LEA.L   INITPARAMS(PC),A0               | source: InitParams table
        MOVEQ.L #0x20,D0                        | 32 bytes to copy
        _BlockMove                              | copy drive constants
| allocate VBL task for power-down and disk-in-place sensing
        LEA.L   DiskQVE(A2),A0                  | DiskQVE(A2): VBL task control block
        MOVE    #vType,qType(A0)                | QType = VType (VBL task)
        LEA.L   Sony_DiskVBLTask(PC),A1         | address of VBL task routine
        MOVE.L  A1,vblAddr(A0)                  | VBLAddr: set task entry point
        MOVE    #KDskVBLTime,vblCount(A0)       | VBLCount = 30 ticks (~0.5 sec)
        _VInstall                               | install into vertical retrace queue
| install Time Manager queue element for wakeup timing
        LEA.L   SE_TimeQEl(A2),A0               | TimeQEl: Time Manager queue element (WakeUp)
        _InsTime                                | register with Time Manager
| check pass-thru on external connector (DCD detection)
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        MOVE.W  #0x6,Drive(A1)                  | Drive = 6, one above the last drive (Mac Plus: 7); GetDrive bounds it to 5
        BSR.W   Sony_DiskSelect                 | select the external interface for this drive number
        BSR.W   Sony_CkDCDExist                 | CkDCDExist: does an HD20 answer for drive 6?
        SPL.B   SE_PassThru(A1)                 | PassThru: $FF = HD20 answers for any number (no pass-thru)
| probe drives 1..5; D2 = physical drive number, D5 = next logical
| drive number to assign to a floppy drive
        MOVEQ.L #0x1,D2                         | start with physical drive 1
        MOVE.L  D2,D5                           | D5 = 1: first logical drive number
E_SONY_OPEN_LOOP:
        MOVE    D2,Drive(A1)                    | Drive = physical drive number being probed
        BSR.W   Sony_GetDrive                   | GetDrive: A0=IWM, A2=VIA, D1 = this drive's vars offset
        ST.B    Installed(A1,D1.W)              | Installed = $FF: assume not connected
        CMPI.W  #0x4,D2                         | drives 1-4 (floppies and first HD20)?
        BLE.B   E_SONY_OPEN_SELECT              | yes -> probe it unconditionally
        TST.B   SE_PassThru(A1)                 | PassThru: can a second HD20 be addressed?
        BMI.B   E_SONY_OPEN_SKIP                | no -> skip drive 5
E_SONY_OPEN_SELECT:
        TST.B   mtrOff(A0)                      | IWM motor off (drop /ENBL) before switching drives
E_SONY_OPEN_CONT:
        BSR.W   Sony_DiskSelect                 | DiskSelect: select this drive's interface
        CMPI.W  #0x4,D2                         | floppy drive (1-3)?
        BLT.B   CHKCONNECT                      | yes -> floppy sense
        MOVE.W  Drive(A1),D5                    | HD20: logical drive number = physical drive number
        BSR.W   Sony_CkDCDExist                 | CkDCDExist: HD20 connected at this position?
        BMI.B   E_SONY_OPEN_SKIP                | no -> skip
        MOVE    #0x1,DriveQVers(A1,D1.W)        | DriveQVers (+$0A, the drive queue element's qType) = 1: dQDrvSz2 holds the high word of the HD20 size
        MOVEQ.L #-0x2,D3                        | DCDRfN: refNum -2 for HD20 drives
        BRA.B   E_SONY_OPEN_XLAT                | install the drive queue element
| ChkConnect -- floppy drive: find out whether a drive is connected and
| how many sides it has.
CHKCONNECT:
        MOVEQ.L #DrvExstAdr,D0                  | DrvExstAdr: drive-exists sense (0 = connected)
        BSR.W   Sony_AdrAndSense                | sense=0 when drive is connected
        BMI.B   E_SONY_OPEN_SKIP                | not connected, skip this drive
        MOVEQ.L #SidesAdr,D0                    | SidesAdr: number-of-sides sense
        BSR.W   Sony_AdrAndSense                | sense = 1 for a double-sided drive
        SMI.B   Sides(A1,D1.W)                  | Sides: $FF=two-sided drive
        MOVEQ.L #NewIntfAdr,D0                  | NewIntfAdr: new-interface sense
        BSR.W   Sony_AdrAndSense                | sense = 1: drive implements the ready handshake (800K drive)
        SMI.B   NewIntf(A1,D1.W)                | NewIntf: $FF=new interface
        MOVEQ.L #-0x5,D3                        | SonyRfN: refNum -5 for floppy drives
| Swap translation table entries D2 (physical) and D5 (logical), so that
| logical drive D5 maps to this physical drive. For HD20 drives D5 = D2
| and the swap changes nothing.
E_SONY_OPEN_XLAT:
        LEA.L   SE_DriveXlat(A1),A1             | A1 -> drive number translation table
        LSL.W   #0x1,D5                         | D5 = logical drive number * 2 (word index)
        LSL.W   #0x1,D2                         | D2 = physical drive number * 2
        MOVE.W  0x0(A1,D2.W),D0                 | D0 = entry [physical]
        SWAP    D0                              | (keep it in the high word)
        MOVE.W  0x0(A1,D5.W),D0                 | D0.lo = entry [logical]
        MOVE.W  D0,0x0(A1,D2.W)                 | entry [physical] = old entry [logical]
        SWAP    D0                              | D0.lo = old entry [physical]
        MOVE.W  D0,0x0(A1,D5.W)                 | entry [logical] = old entry [physical]
        LSR.W   #0x1,D2                         | back to drive numbers
        LSR.W   #0x1,D5                         | (D5 too)
        MOVEA.L (SonyVars).w,A1                 | A1 = SonyVars again
E_SONY_OPEN_CONT_2:
        MOVE.B  #0x1,Installed(A1,D1.W)         | Installed = 1: drive connected
        MOVE.W  D5,D0                           | D0.hi = logical drive number (drive queue number)
        SWAP    D0                              | move it to the high word
        MOVE    D3,D0                           | D0.lo = driver refNum (-5 floppy, -2 HD20)
        LEA.L   DQEl(A1,D1.W),A0                | A0 -> drive queue element in the drive vars (+6)
        _AddDrive                               | add the drive to the drive queue
        ADDQ.W  #0x1,D5                         | next logical drive number
E_SONY_OPEN_SKIP:
        ADDQ.W  #0x1,D2                         | next physical drive
        CMPI.W  #0x5,D2                         | all 5 drives probed?
        BLE.W   E_SONY_OPEN_LOOP                | no -> next drive
        CLR.B   Active(A1)                      | Active = 0: driver idle
        MOVEQ.L #0x0,D0                         | return noErr
        RTS                                     | return to Device Manager

| -------------------------------------------------------------------------
| DiskCtlErr / DiskDone -- I/O completion
|   D0 (in) -- result code
| Saves a non-zero result in DskErr, clears Active and completes the
| request through the IODone vector (JIODone).
| -------------------------------------------------------------------------
Sony_DiskCtlErr:
        MOVEQ.L #-0x11,D0                       | controlErr: unsupported control call
| Called by: SONY_DCD_CTLEJECT, E_Sony_Status, SONY_CONTROL_BADCODE, SONY_CTL_KILLIO, SONY_CTL_FORMAT (and 11 more)
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

| -------------------------------------------------------------------------
| CtlTbl -- control call dispatch table. Each entry: csCode, offset of the
| handler for floppy drives (1-3), offset of the handler for HD20 drives
| (4-5), both relative to CODES; a zero word ends the table.
| The Mac Plus table had csCodes 5, 6, 7 and 21, with the HD20 offset
| first; KillIO (1), the tag buffer (8) and track cache (9) calls were
| tested in code. csCodes 22 and 23 are new.
| -------------------------------------------------------------------------
CODES:
        .short  1                               | csCode 1: KillIO
        .short  SONY_CTL_KILLIO-CODES           | floppy drives 1-3
        .short  SONY_CTL_KILLIO-CODES           | HD20 drives 4-5
        .short  5                               | csCode 5: verifyCC: verify disk
        .short  SONY_CTL_VERIFY-CODES           | floppy drives 1-3
        .short  SONY_DCD_CTLVERIFY-CODES        | HD20 drives 4-5
        .short  6                               | csCode 6: formatCC: format disk
        .short  SONY_CTL_FORMAT-CODES           | floppy drives 1-3
        .short  SONY_DCD_CTLFORMAT-CODES        | HD20 drives 4-5
        .short  7                               | csCode 7: ejectCode: eject disk
        .short  SONY_CTL_EJECT-CODES            | floppy drives 1-3
        .short  SONY_DCD_CTLEJECT-CODES         | HD20 drives 4-5
        .short  8                               | csCode 8: tagBufCC: set tag buffer
        .short  SONY_CTL_TAGBUF-CODES           | floppy drives 1-3
        .short  SONY_CTL_TAGBUF-CODES           | HD20 drives 4-5
        .short  9                               | csCode 9: TCacheCC: track cache control
        .short  SONY_CTL_TRKCACHE-CODES         | floppy drives 1-3
        .short  SONY_CTL_TRKCACHE-CODES         | HD20 drives 4-5
        .short  21                              | csCode 21: iconCC: get drive icon
        .short  SONY_CTL_DRIVEICON-CODES        | floppy drives 1-3
        .short  SONY_DCD_ICON-CODES             | HD20 drives 4-5
        .short  22                              | csCode 22: iconLogCC: get media icon
        .short  SONY_CTL_MEDIAICON-CODES        | floppy drives 1-3
        .short  SONY_DCD_ICON-CODES             | HD20 drives 4-5
        .short  23                              | csCode 23: infoCC: get drive info
        .short  SONY_CTL_DRVINFO-CODES          | floppy drives 1-3
        .short  SONY_CTL_DRVINFO-CODES          | HD20 drives 4-5
        .short  0                               | end of table

| -------------------------------------------------------------------------
| DiskControl -- driver control entry: jump through the JControl vector.
| -------------------------------------------------------------------------
E_Sony_Control:
        MOVE.L  (DiskVars_JControl).w,-(SP)     | push control vector
        RTS                                     | dispatch to jtControl

| -------------------------------------------------------------------------
| jtControl -- control call dispatcher (JControl vector)
|   A0 (in) -- control parameter block
| Checks the drive number first. Every handler is entered with
| A1 = SonyVars, D1 = drive vars offset and D0/CCR = result of the drive
| check (0 = valid drive, nsDrvErr = bad drive number, noDriveErr = drive
| not connected); calls that need a drive exit through DiskDone when
| CCR is NE. Rewritten for the SE: the Mac Plus driver handled KillIO,
| the tag buffer and track cache calls before checking the drive.
| -------------------------------------------------------------------------
Sony_Control:
        BSR.W   Sony_CkDrvNum                   | CkDrvNum: check the drive number, set up A1/D1
        BNE.W   SONY_CONTROL_DISPATCH           | bad drive number: dispatch with D0 = nsDrvErr
        TST.B   Installed(A1,D1.W)              | drive connected (Installed = 1)?
        BPL.B   SONY_CONTROL_DISPATCH           | yes -> D0 = 0
        MOVEQ.L #-0x40,D0                       | noDriveErr: drive not connected
SONY_CONTROL_DISPATCH:
        LEA.L   CODES(PC),A3                    | A3 -> dispatch table
        MOVEA.L A3,A4                           | A4 = table base for the handler offset
SONY_CONTROL_SCAN:
        MOVE.W  (A3),D2                         | csCode of this table entry
        BEQ.B   SONY_CONTROL_BADCODE            | end of table -> controlErr
        CMP.W   csCode(A0),D2                   | csCode of the request?
        BNE.B   SONY_CONTROL_NEXT               | no -> next entry
        ADDQ.W  #0x2,A3                         | A3 -> handler offset for floppy drives
        CMPI.W  #0x4,Drive(A1)                  | HD20 drive (drive number 4 or 5)?
        BLT.B   SONY_CONTROL_JUMP               | no -> use the floppy offset
        ADDQ.W  #0x2,A3                         | yes -> handler offset for HD20 drives
SONY_CONTROL_JUMP:
        ADDA.W  (A3),A4                         | A4 = handler address (table base + offset)
        TST.W   D0                              | CCR = result of the drive check
        JMP     (A4)                            | go to the handler
SONY_CONTROL_NEXT:
        ADDQ.W  #0x6,A3                         | skip csCode and both offsets
        BRA.B   SONY_CONTROL_SCAN               | check the next entry
SONY_CONTROL_BADCODE:
        MOVEQ.L #-0x11,D0                       | controlErr: csCode not in the table
        BRA.W   Sony_DiskDone                   | complete the request
| ctlKillIO (csCode 1) -- not supported (no way to abort an HD20
| request), drive number not checked.
SONY_CTL_KILLIO:
        MOVEQ.L #-0x1,D0                        | KillIO not supported: return -1
        BRA.W   Sony_DiskDone                   | complete the request
| ctlSonyFmt (csCode 6, floppy) -- format the disk in the drive.
SONY_CTL_FORMAT:
        BNE.W   Sony_DiskDone                   | bad or missing drive -> return the error
        BRA.W   Sony_CtlFormat                  | go format
| ctlSonyVer (csCode 5, floppy) -- verify the disk in the drive.
SONY_CTL_VERIFY:
        BNE.W   Sony_DiskDone                   | bad or missing drive -> return the error
        BRA.W   Sony_CtlVerify                  | go verify
| ctlTagBuf (csCode 8) -- set (CSParam <> 0) or clear the separate tag
| buffer; drive number not needed.
SONY_CTL_TAGBUF:
        MOVE.L  csParam(A0),SE_TagBufPtr(A1)    | TagBufPtr (+$136) = CSParam
        MOVEQ.L #0x0,D0                         | always noErr
        BRA.W   Sony_DiskDone                   | complete the request
| ctlTrkCache (csCode 9) -- track cache control; drive number not needed.
|   CSParam+0: non-zero = enable, zero = disable the cache
|   CSParam+1: >0 = install (allocate), <0 = remove, 0 = neither
| Always completes with noErr (MTN #272: "When the cache is removed,
| 680x0 register D0 contains the previous size of the cache"; TCdispose
| returns that size, but D0 is cleared before DiskDone).
SONY_CTL_TRKCACHE:
        ADDA.W  #csParam,A0                     | A0 -> CSParam
        MOVE.B  (A0)+,D1                        | D1 = enable flag
        MOVE.B  (A0)+,D0                        | D0 = install/remove flag
        BEQ.B   SONY_CTLTCENB                   | neither -> just enable/disable
        BPL.B   SONY_CTLTCINST                  | positive -> install a cache buffer
        BSR.W   SONY_TCDISPOSE                  | negative -> TCdispose: remove the buffer
        BRA.B   SONY_CTLTCENB                   | and disable the cache
SONY_CTLTCINST:
        TST.L   SE_TCBuffer(A1)                 | TCBuffer (+$14C): buffer already allocated?
        BNE.B   SONY_CTLTCENB                   | yes -> keep it
        CMPI.W  #0x2,(MemTop).w                 | MemTop high word <= 2: at most 128K of RAM?
        BLE.B   SONY_CTLTCENB                   | yes -> no cache
        MOVE.L  #0x1890,D0                      | $1890 = 12 sectors * 524 bytes
        _NewPtrSysClear                         | allocate it in the system heap
        BNE.B   SONY_CTLTCENB                   | no memory -> no cache
        MOVE.L  A0,SE_TCBuffer(A1)              | TCBuffer = new buffer
        CLR.W   SE_TCDrive(A1)                  | TCDrive (+$144) = 0: cache contents invalid
| Called by: SONY_CTLTCINST, SONY_CTL_TRKCACHE
SONY_CTLTCENB:
        TST.L   SE_TCBuffer(A1)                 | TCBuffer: any buffer?
        SNE.B   SE_TCInstalled(A1)              | TCInstalled (+$143) = 0 if there is none
        BEQ.B   SONY_CONTROL_DONE               | no buffer -> done
        TST.B   D1                              | enable requested?
        SNE.B   SE_TCInstalled(A1)              | TCInstalled = $FF (on) or 0 (off)
SONY_CONTROL_DONE:
        MOVEQ.L #0x0,D0                         | always noErr
        BRA.W   Sony_DiskDone                   | complete the request
| TCdispose -- release the track cache buffer
|   D0 (out) -- number of bytes freed (0 if there was no buffer)
| The Mac Plus driver also used this as its grow-zone procedure.
SONY_TCDISPOSE:
        CLR.L   -(SP)                           | assume nothing freed
        MOVE.L  SE_TCBuffer(A1),D0              | TCBuffer (+$14C): buffer allocated?
        BEQ.B   SONY_TCDISPOSE_DONE             | no -> return 0
        MOVEA.L D0,A0                           | A0 = buffer
        _GetPtrSize                             | D0 = its size
        MOVE.L  D0,(SP)                         | = number of bytes freed
        _DisposePtr                             | release it
        CLR.L   SE_TCBuffer(A1)                 | TCBuffer = nil
        CLR.B   SE_TCInstalled(A1)              | TCInstalled = 0
SONY_TCDISPOSE_DONE:
        MOVE.L  (SP)+,D0                        | D0 = bytes freed
        RTS                                     | return
| ctlSonyEjc (csCode 7, floppy) -- eject the disk. The drive is powered
| down at once; the interface stays selected for the eject pulse.
SONY_CTL_EJECT:
        BNE.W   Sony_DiskDone                   | bad or missing drive -> return the error
SONY_CTL_EJECT_GO:
        BSR.W   SONY_INVALTRKCACHE              | InvalTrkCache: forget cached sectors of this drive
        MOVEQ.L #0x0,D0                         | immediate power-off
        BSR.W   Sony_PowerDown                  | PowerDown
        BSR.W   Sony_DiskSelect                 | DiskSelect: keep the interface enabled
        MOVE    #0x7D0,D0                       | wait 200 ms
        BSR.W   E_Sony_WakeUp                   | WakeUp (returns after the delay)
        MOVEQ.L #EjectHAdr,D0                   | EjectHAdr: control address CA1 = CA0 = 1, SEL = 0, CA2 = 1: eject
        BSR.W   Sony_AdrDisk                    | address it
        TST.B   ph3H(A0)                        | LSTRB high: start the eject pulse
        TST.B   NewIntf(A1,D1.W)                | new-interface (800K) drive?
        BMI.B   SONY_NEWDRVEJECT                | yes -> a short pulse is enough
        MOVE    EjectTime(A1),D0                | EjectTime: 0.75 s pulse for old drives
        BSR.W   E_Sony_WakeUp                   | WakeUp
        TST.B   ph3L(A0)                        | LSTRB low: end of the pulse
        BRA.B   SONY_CTL_EJECTDONE              | done
| NewDrvEject -- an 800K drive only needs a short pulse, but /ENBL must
| stay asserted until 150 us after the disk has left the drive (Apple:
| "new drive needs /enb asserted until 150usec after /cstin goes away";
| /CSTIN is the disk-in-place sense, DIPAdr).
SONY_NEWDRVEJECT:
        TST.B   ph3L(A0)                        | LSTRB low (pulse > 1 us, < 300 ms)
        MOVEQ.L #0xF,D3                         | wait at most 16 * 100 ms
SONY_NEWDRVEJECT_LOOP:
        MOVE    #0x3E8,D0                       | 100 ms
        BSR.W   E_Sony_WakeUp                   | WakeUp
        MOVEQ.L #DIPAdr,D0                      | DIPAdr: disk-in-place sense
        BSR.W   Sony_AdrAndSense                | sense = 1 once the disk has left the drive
        DBMI    D3,SONY_NEWDRVEJECT_LOOP        | until the disk is out or the time is up
        MOVEQ.L #0xA,D0                         | 1 ms more
        BSR.W   E_Sony_WakeUp                   | WakeUp
| CtlEjtOK -- ignore disk-in-place for the next EjectWait VBL calls.
SONY_CTL_EJECTDONE:
        MOVE.B  EjectWait(A1),DiskInPlace(A1,D1.W) | DiskInPlace = EjectWait ($FC)
        MOVEQ.L #0x0,D0                         | noErr
        BRA.W   Sony_DiskDone                   | complete the request
| HD20 format, verify and eject (csCodes 6, 5, 7 for drives 4-5). An HD20
| is not ejected: DiskInPlace = 0 lets the VBL task (Check4Disk) post a
| disk-inserted event, so that the volume is mounted again (MTN #272:
| "if one is ejected, the driver posts a diskInserted event").
SONY_DCD_CTLFORMAT:
        BNE.W   Sony_DiskDone                   | bad or missing drive -> return the error
        BRA.W   SONY_DCD_FORMAT                 | HD20 format command
SONY_DCD_CTLVERIFY:
        BNE.W   Sony_DiskDone                   | bad or missing drive -> return the error
        BRA.W   SONY_DCD_VERIFY                 | HD20 verify command
SONY_DCD_CTLEJECT:
        BNE.W   Sony_DiskDone                   | bad or missing drive -> return the error
        CLR.B   DiskInPlace(A1,D1.W)            | DiskInPlace = 0: the VBL task senses the HD20 again and posts a disk-inserted event (remount)
        MOVEQ.L #0x0,D0                         | noErr
        BRA.W   Sony_DiskDone                   | complete the request

| -------------------------------------------------------------------------
| DiskStatus -- status entry; only csCode 8 (drive status) is supported:
| copies the first 22 bytes of the drive variables (track, write-protect,
| disk-in-place, installed, sides, drive queue element, two-sided format,
| new interface, soft error count) to CSParam.
| -------------------------------------------------------------------------
E_Sony_Status:
        MOVEQ.L #-0x12,D0                       | statusErr: assume an unsupported csCode
        CMPI    #0x8,csCode(A0)                 | csCode 8 (drive status)?
        BNE.W   Sony_DiskDone                   | no -> return statusErr
        BSR.B   Sony_CkDrvNum                   | CkDrvNum: check the drive number, set up A1/D1
        BNE.W   Sony_DiskDone                   | bad drive number -> return the error
        LEA.L   csParam(A0),A0                  | A0 -> CSParam
        MOVEQ.L #0xB,D0                         | 11 words
        ADDA    D1,A1                           | A1 -> this drive's variables
SONY_DRIVESTATUS_LOOP:
        MOVE    (A1)+,(A0)+                     | copy a word
        SUBQ.W  #0x1,D0                         | count it
        BGT.B   SONY_DRIVESTATUS_LOOP           | until all 11 words are copied (D0 = 0 = noErr)
        BRA.W   Sony_DiskDone                   | complete the request

| -------------------------------------------------------------------------
| CkDrvNum -- check the drive number of a request and set up registers
|   A0 (in)  -- parameter block (ioVRefNum = drive number)
|   A1 (out) -- SonyVars
|   D1 (out) -- offset of the drive's variables (through the translation
|               table)
|   D0 (out) -- 0, or nsDrvErr for a drive number outside 1..5 (BNE)
| Also sets Active (the VBL task stays away) and LastDrive.
| -------------------------------------------------------------------------
Sony_CkDrvNum:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        ST.B    Active(A1)                      | Active = $FF: exclude the VBL task
        MOVE    ioVRefNum(A0),D0                | D0 = ioVRefNum = drive number
        BEQ.B   SONY_CKDRVNUM_ERR               | 0 -> nsDrvErr
        CMPI.W  #0x5,D0                         | drive numbers 1-5 only
        BGT.B   SONY_CKDRVNUM_ERR               | above 5 -> nsDrvErr
        MOVE.W  Drive(A1),SE_LastDrive(A1)      | LastDrive (+$154) = previous Drive
        MOVE    D0,Drive(A1)                    | Drive = requested drive
        BSR.W   Sony_GetDrv1                    | GetDrv1: D1 = vars offset of the translated drive
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return (BEQ)

| CkDrvNum error exit: drive number 0 or above 5
SONY_CKDRVNUM_ERR:
        MOVEQ.L #-0x38,D0                       | nsDrvErr (-56): no such drive
        RTS                                     | return (BNE)

| -------------------------------------------------------------------------
| DiskPrime -- read/write entry: jump through the JDiskPrime vector.
| -------------------------------------------------------------------------
E_Sony_Prime:
        MOVE.L  (DiskVars_JDiskPrime).w,-(SP)   | push DiskPrime vector
        RTS                                     | jump to implementation

| -------------------------------------------------------------------------
| jtDiskPrime -- start a read or write (JDiskPrime vector)
|   A0 (in) -- parameter block (ioTrap: $A002 _Read, $A003 _Write)
| Checks the drive, selects it, checks for a disk; on the first access to
| a newly inserted disk the drive is recalibrated, the speed table built
| and the write protection noted (DiskInPlace = 2). HD20 drives
| (drive 4-5) go to the HD20 prime code instead.
| -------------------------------------------------------------------------
Sony_DiskPrime:
        ORI     #0x100,SR                       | exclude VBL interrupts (IPL 1)
        MOVE    ioTrap(A0),D3                   | D3 = ioTrap
        BTST    #0x6,ioPosMode+1(A0)            | read-verify mode? (ioPosMode bit 6)
        SNE.B   (DskVerify).w                   | note it in DskVerify
        BSR.B   Sony_CkDrvNum                   | CkDrvNum: check the drive number
        BNE.W   SONY_DISKERR                    | bad drive number -> return the error
        MOVE    D3,Command(A1)                  | Command (+$32) = I/O command (ioTrap)
| check drive is installed
        MOVEQ.L #-0x40,D0                       | noDriveErr (-64): assume no drive
        TST.B   Installed(A1,D1.W)              | Installed: 1 = connected, $FF = not
        BMI.B   SONY_DISKERR                    | not connected -> return the error
        BSR.W   Sony_DiskSelect                 | DiskSelect: select the drive
| check drive type and disk insertion
        CMPI.W  #0x4,Drive(A1)                  | HD20 drive (4 or 5)?
        BGE.W   Sony_DCDPrime                   | yes -> HD20 read/write
        MOVEQ.L #DIPAdr,D0                      | DIPAdr: disk-in-place sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when a disk is in place
        BPL.B   SONY_DISKPRIME_CONT             | disk in place ->
| no disk in drive
        CLR.B   DiskInPlace(A1,D1.W)            | DiskInPlace = 0: no disk here
        TST.B   mtrOff(A0)                      | IWM motor off: cut /ENBL so the drive does not tick
        MOVEQ.L #-0x41,D0                       | offLinErr (-65): no disk in the drive
        BRA.B   SONY_DISKERR                    | return the error
| first access to this disk: power up, recalibrate, measure speeds
SONY_DISKPRIME_CONT:
        CMPI.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2: already clamped and recalibrated?
        BEQ.B   SONY_CKWRPROT                   | yes -> check write protection
        BSR.W   Sony_FastPower                  | FastPower: motor on (waits only for /READY of an 800K drive)
        BSR.W   E_Sony_Recal                    | Recal: seek to track 0
        BMI.B   SONY_DSKIMMOFF                  | error -> immediate power-down
        BSR.W   E_Sony_MakeSpdTbl               | MakeSpdTbl: measure the speed of each zone
        BNE.B   SONY_DSKIMMOFF                  | error -> immediate power-down
        MOVEQ.L #WrProtAdr,D0                   | WrProtAdr: write-protect sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when write-protected
        SPL.B   WriteProt(A1,D1.W)              | WriteProt = $FF for a write-protected disk
        MOVE.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2: clamped (recalibrated)
        CLR.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt = 0: assume a one-sided format
| CkWrProt -- a write to a write-protected disk fails
SONY_CKWRPROT:
        BSR.W   Sony_CheckRead                  | CheckRead: is it a read?
        BEQ.B   SONY_RWPOWER                    | yes -> power up and go
        MOVE    (BufTgFBkNum).w,FirstFSeq(A1)   | FirstFSeq = file block number of the first tag (TagData+8)
        TST.B   WriteProt(A1,D1.W)              | WriteProt: disk write-protected?
        BPL.B   SONY_RWPOWER                    | no -> power up and go
        MOVEQ.L #-0x2C,D0                       | wPrErr (-44): disk is write-protected
| DskRWOff / DskImmOff / POffExit / DiskErr -- the exits of DiskPrime,
| after an error and after the last sector (format and verify exit
| through POffExit with D2 = PwrOffTime): start the power-down
| (DskRWOff: after PwrOffTime, DskImmOff: at once), open the interrupts,
| complete the request
SONY_DSKRWOFF:
        MOVE    PwrOffTime(A1),D2               | D2 = normal power-off delay
        BRA.B   SONY_POFFEXIT                   | power down with that delay
SONY_DSKIMMOFF:
        MOVEQ.L #0x0,D2                         | D2 = 0: immediate power-down
SONY_POFFEXIT:
        MOVE    D0,-(SP)                        | save the result code
        MOVE    D2,D0                           | D0 = power-off delay
        BSR.W   Sony_PowerDown                  | PowerDown
        MOVE    (SP)+,D0                        | restore the result code
SONY_DISKERR:
        ANDI    #-0x701,SR                      | open interrupts again
        BRA.W   Sony_DiskDone                   | complete the request
| RWPower -- set the speed for the current track and wait until the
| drive is powered up
SONY_RWPOWER:
        MOVE    Track(A1,D1.W),D6               | D6 = current track
        BSR.W   Sony_SetSpeed                   | SetSpeed for it
        BSR.W   Sony_RWPowerUp                  | RWPowerUp: power up and wait
| GetTrack -- convert the current byte position into side/track, first
| sector and sector bitmap for the next track to process
SONY_GETTRACK:
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
        BLT.B   SONY_NXTCLASS                   | no -> find its speed zone
SONY_DSKPARMERR:
        MOVEQ.L #-0x32,D0                       | paramErr (-50): bad position
SONY_TODRWOFF:
        BRA.B   SONY_DSKRWOFF                   | power down and return the error
| find the speed zone of the block (zones of 16 tracks, 12..8 sectors)
SONY_NXTCLASS:
        MOVEQ.L #0x7,D3                         | 7
        LSL     #0x4,D3                         | * 16 = 112 (the loop adds 16 first: 128 in zone 4)
        LSL     D4,D3                           | doubled for two-sided disks
        MOVEQ.L #0x10,D5                        | 16 more blocks per side in each lower zone
        LSL     D4,D5                           | doubled for two-sided disks
SONY_DISKPRIME_NEXT_2:
        ADD     D5,D3                           | blocks in this zone
        SUB.L   D3,D2                           | D2 = first block of this zone
        CMP.L   D2,D0                           | block in a lower zone?
        BLT.B   SONY_DISKPRIME_NEXT_2           | yes -> next zone outward
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
        BGE.B   SONY_GTRESUME                   | yes ->
        SUB     D3,D2                           | D2 = first block of side 0
        MOVEQ.L #0x0,D6                         | side 0
SONY_GTRESUME:
        TST.B   D6                              | side 1?
        BEQ.B   SONY_DISKPRIME_NO_2             | no ->
        BSET    #0xB,D5                         | bit 11 of the side/track word = side 1
        TST.B   Sides(A1,D1.W)                  | Sides: double-sided drive?
        BNE.B   SONY_DISKPRIME_NO_2             | yes -> fine
        MOVEQ.L #-0x4E,D0                       | twoSideErr (-78): two-sided disk in a one-sided drive
        BRA.B   SONY_TODRWOFF                   | power down and return the error

| SONY_DISKPRIME_NO_2 -- set up sector loop variables
SONY_DISKPRIME_NO_2:
        MOVE    D5,SideTrack(A1)                | SideTrack = side/track wanted
        SUB     D2,D0                           | D0 = first sector wanted on this track
        SUB     D0,D3                           | D3 = sectors left on this track
        MOVE    D0,FirstSect(A1)                | FirstSect = first sector wanted
        MOVE.L  ioReqCount(A0),D5               | D5 = ioReqCount
        MOVE.L  ioActCount(A0),D2               | D2 = ioActCount (bytes done so far)
        SUB.L   D2,D5                           | bytes still to transfer
        LSR.L   D7,D5                           | / 512 = blocks still to transfer
        BEQ.B   SONY_DSKPARMERR                 | less than one block -> paramErr
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
| CheckCache -- use the track cache when possible
        CLR.B   SE_TCRdEnable(A1)               | TCRdEnable (+$142) = 0: assume no reads into the cache
        BSR.W   Sony_CheckRead                  | CheckRead: is it a read?
        BEQ.B   SONY_READCACHE                  | yes -> read through the cache
        BSR.W   Sony_CacheValid                 | CacheValid: cache valid for this drive/side/track?
        BNE.B   SONY_TORESEEK                   | no -> go do the I/O
        MOVE.L  D5,D0                           | bitmap of the sectors being written
        NOT.L   D0                              | = sectors not being written
        AND.L   D0,SE_TCSectMap(A1)             | TCSectMap (+$148): drop the sectors we overwrite
SONY_TORESEEK:
        BRA.W   E_Sony_ReSeek                   | go do the I/O
| readCache -- take the sectors that are in the cache
SONY_READCACHE:
        TST.B   (DskVerify).w                   | read-verify?
        BNE.B   SONY_TORESEEK                   | yes -> never from the cache
        BSR.W   Sony_CacheValid                 | CacheValid?
        BNE.W   SONY_RDCACHENV                  | no -> set the cache up for this track
        MOVE.L  D5,D2                           | sectors wanted
        AND.L   SE_TCSectMap(A1),D2             | TCSectMap (+$148): and cached?
        BEQ.B   SONY_RC_CONT                    | none -> go do the I/O
        MOVEQ.L #0x2,D7                         | 2
        ASL.L   #0x8,D7                         | * 256 = 512 bytes per sector
        MOVE    D4,D0                           | first sector wanted
        MULU    #0x20C,D0                       | * 524 = offset of its entry in the cache
        MOVEA.L SE_TCBuffer(A1),A4              | A4 = TCBuffer (+$14C)
        ADDA    D0,A4                           | A4 -> cache entry of the first sector
SONY_RC_LOOP:
        BTst    D4,D2                           | sector wanted and cached?
        BEQ.B   SONY_DISKPRIME_SKIP_3           | no -> skip to next sector
        BCLR    D4,D5                           | remove it from the sectors wanted
        MOVEM.L A0-A1,-(SP)                     | preserve A0/A1 over _BlockMove
        TST.L   SE_TagBufPtr(A1)                | TagBufPtr (+$136): separate tag buffer?
        BEQ.B   SONY_DISKPRIME_NO_3             | no -> tags go to TagData
        MOVE    D4,D0                           | current sector
        SUB     FirstSect(A1),D0                | - FirstSect = sector index on this track
        ADD     FBlksDone(A1),D0                | + FBlksDone = block index in the request
        MULU    #0xC,D0                         | * 12 = offset into the tag buffer
        MOVEA.L SE_TagBufPtr(A1),A1             | A1 = tag buffer
        ADDA.L  D0,A1                           | A1 -> tags of this block
        BRA.B   SONY_DISKPRIME_CONT_5           | copy the tags

| SONY_DISKPRIME_NO_3 -- no external tag buffer: use system globals
SONY_DISKPRIME_NO_3:
        LEA.L   (BufTgFNum).w,A1                | A1 -> TagData+2 (file tags in low memory)
SONY_DISKPRIME_CONT_5:
        MOVE.L  A4,A0                           | A0 -> cache entry: 12 tag bytes, 512 data bytes
        MOVE.L  (A0)+,(A1)+                     | copy the 12 tag bytes
        MOVE.L  (A0)+,(A1)+                     | tag data words 3-4
        MOVE.L  (A0)+,(A1)+                     | tag data words 5-6
        MOVE.L  A3,A1                           | A1 = user buffer
        MOVE.L  D7,D0                           | 512 bytes
        _BlockMove                              | copy the data
        MOVEM.L (SP)+,A0-A1                     | restore A0/A1
        ADDQ.W  #0x1,SE_TCNumUsed(A1)           | TCNumUsed (+$152): count cache hits
        ADD.L   D7,dCtlPosition(A2)             | dCtlPosition += 512
        ADD.L   D7,ioActCount(A0)               | ioActCount += 512
SONY_DISKPRIME_SKIP_3:
        ADDA.L  D7,A3                           | next block in the user buffer
        ADDA.L  D7,A4                           | next cache entry
        ADDA    #0xC,A4                         | (12 tag bytes per entry)
        ADDQ.W  #0x1,D4                         | next sector
        SUBQ.W  #0x1,D3                         | count it
        BNE.B   SONY_RC_LOOP                    | until all sectors of this track are checked
        MOVE.L  D5,SectMap(A1)                  | SectMap = sectors still wanted
        BNE.B   SONY_RC_CONT                    | some left -> read them
        MOVE.L  ioActCount(A0),D0               | ioActCount
        CMP.L   ioReqCount(A0),D0               | compared with ioReqCount
        BLT.W   SONY_GETTRACK                   | more to do -> next track
        MOVEQ.L #0x0,D0                         | noErr
        BRA.W   SONY_DSKRWOFF                   | power down and return

| SONY_RC_CONT -- not all sectors satisfied from cache: do disk I/O
SONY_RC_CONT:
        BSR.B   Sony_TCRdEnbChk                 | TCRdEnbChk
        BRA.B   E_Sony_ReSeek                   | go do the I/O
| rdCacheNV -- cache not valid: start caching this track if possible
SONY_RDCACHENV:
        BSR.B   Sony_TCRdEnbChk                 | TCRdEnbChk: reads into the cache enabled?
        BNE.B   E_Sony_ReSeek                   | no -> go do the I/O
        MOVE.W  Drive(A1),SE_TCDrive(A1)        | TCDrive (+$144) = Drive
        MOVE.W  SideTrack(A1),SE_TCSideTrack(A1) | TCSideTrack (+$146) = SideTrack
        CLR.L   SE_TCSectMap(A1)                | TCSectMap (+$148) = 0: nothing cached yet
        BRA.B   E_Sony_ReSeek                   | go do the I/O
| TCRdEnbChk -- enable reads into the cache (TCRdEnable) for a
| synchronous call that needs no sectors on another track; BEQ if enabled
Sony_TCRdEnbChk:
        TST.B   SE_TCInstalled(A1)              | TCInstalled (+$143): cache installed and on?
        BEQ.B   SONY_TCRDENBCHK_OFF             | no ->
        BTST    #asyncTrpBit,Command(A1)        | asynchronous call (ioTrap bit 10)?
        BNE.B   SONY_TCRDENBCHK_SET             | yes -> no caching (NE)
        TST.B   D6                              | last track of the request?
SONY_TCRDENBCHK_SET:
        SEQ.B   SE_TCRdEnable(A1)               | TCRdEnable (+$142) = $FF if so
        RTS                                     | return

| SONY_TCRDENBCHK_OFF -- cache not installed: set D6=1 to skip caching
SONY_TCRDENBCHK_OFF:
        MOVEQ.L #0x1,D6                         | force NE
        BRA.B   SONY_TCRDENBCHK_SET             | TCRdEnable = 0
| CacheValid -- BEQ if the cache holds data of the current drive and
| side/track
Sony_CacheValid:
        TST.B   SE_TCInstalled(A1)              | TCInstalled (+$143): installed and on?
        BEQ.B   SONY_CACHEVALID_NO              | no -> not valid
        MOVE.W  SE_TCDrive(A1),D0               | TCDrive (+$144)
        BEQ.B   SONY_CACHEVALID_NO              | 0 -> not valid
        CMP     Drive(A1),D0                    | same drive?
        BNE.B   SONY_CACHEVALID_NO              | no -> not valid
        MOVE    SideTrack(A1),D0                | current side/track
        SUB.W   SE_TCSideTrack(A1),D0           | - TCSideTrack (+$146)
        BEQ.B   SONY_CACHEVALID_EXIT            | same -> valid (D0 = 0)
SONY_CACHEVALID_NO:
        MOVEQ.L #-0x1,D0                        | not valid
SONY_CACHEVALID_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| ReSeek -- jump through the JReSeek vector.
| -------------------------------------------------------------------------
| Called by: SONY_RDCACHENV, SONY_TORESEEK, SONY_RC_CONT, SONY_DORECAL
E_Sony_ReSeek:
        MOVE.L  (DiskVars_JReSeek).w,-(SP)      | push ReSeek vector address
        RTS                                     | dispatch to Sony_ReSeek

| -------------------------------------------------------------------------
| jtReSeek -- DiskPrime part III: seek to SideTrack; for a drive without
| the new interface (400K), check the zone speed when CkDelta ticks have
| passed since the last check and, if the speed value of GetFreq1 is
| outside the zone's limits in SpeedCheckTbl, change the zone's speed
| code by its 2% delta (at most BadSpdInit times).
| -------------------------------------------------------------------------
Sony_ReSeek:
        MOVE.B  BadSpdInit(A1),BadSpdCnt(A1)    | BadSpdCnt = BadSpdInit: speed adjustments allowed
SONY_RESEEK1:
        MOVE    SideTrack(A1),D6                | D6 = side/track wanted
        BSR.W   E_Sony_Seek                     | Seek
        BMI.B   SONY_TODORECAL                  | error -> recal
        MOVE.B  ReadErrInit(A1),ReadErrCnt(A1)  | ReadErrCnt = ReadErrInit
        TST.B   NewIntf(A1,D1.W)                | new-interface drive (regulates its own speed)?
        BMI.B   SONY_ONTRACK                    | yes -> no speed check (new on the SE)
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
        BLT.B   SONY_ONTRACK                    | no -> on to the sectors
SONY_RESEEK_CONT:
        MOVE.L  D2,(A2)                         | remember the time of this check
        LEA.L   SONY_RESEEK_CONT_2(PC),A3       | A3 = return address for the measurement
        BRA.W   SONY_GETFREQ1                   | measure the speed (GetFreq1 in MakeSpdTbl)

| SONY_RESEEK_CONT_2 -- callback after speed measurement
SONY_RESEEK_CONT_2:
        BMI.B   SONY_TODORECAL                  | measurement failed -> recal
        MOVE    -(A2),D0                        | D0 = TSTblDelta: speed code change for 2% speed
        LEA.L   DT_Sony_SpeedCheckTbl(PC),A0    | A0 -> speed limits table
        LSR     #0x1,D6                         | zone * 4
        ADDA    D6,A0                           | A0 -> limits for this zone
        CMP     (A0)+,D4                        | too fast (speed value D4 above the upper limit)?
        BGT.B   SONY_RESEEK_ADJUST              | yes -> lower the speed code by the delta
        NEG     D0                              | else D0 = -delta
        CMP     (A0),D4                         | too slow (D4 at or below the lower limit)?
        BGT.B   SONY_ONTRACK                    | no -> speed is fine
SONY_RESEEK_ADJUST:
        SUB     D0,-(A2)                        | TSTblCode -= delta (too fast) or += delta (too slow)
        CLR.L   TSTblTicks(A2)                  | force a recheck next time
SONY_RESEEK_NO:
        ADDQ.W  #0x1,SpdAdjCnt(A1,D1.W)         | SpdAdjCnt: count speed adjustments
        SUBQ.B  #0x1,BadSpdCnt(A1)              | BadSpdCnt: adjustments left?
        BPL.B   SONY_RESEEK1                    | yes -> seek (sets the new speed) and check again
        MOVEQ.L #-0x4F,D0                       | spdAdjErr (-79): speed cannot be adjusted
SONY_TODORECAL:
        BRA.W   SONY_DORECAL                    | recal or give up

| -------------------------------------------------------------------------
| OnTrack -- DiskPrime part IV: read each address mark passing under the
| head; read or write the sector when it is wanted, optionally read other
| sectors of the track into the track cache.
|   current file block = FirstFSeq + FBlksDone + (sector - FirstSect)
|   tag buffer offset  = [FBlksDone + (sector - FirstSect)] * 12
| -------------------------------------------------------------------------
| Called by: SONY_RESEEK1, SONY_RESEEK_CONT_2, SONY_RESEEK_CONT_4, SONY_RESEEK_DONE, SONY_RESEEK_RETRY_3
SONY_ONTRACK:
        MOVE.B  WrgSectInit(A1),WrgSectCnt(A1)  | WrgSectCnt = WrgSectInit: wrong sectors tolerated
SONY_ONTRACK1:
        MOVE    D1,D6                           | OnTrack1: D6 = drive vars offset
        BSR.W   Sony_RdAddrSetup                | RdAddrSetup: read the next address mark
        BMI.W   SONY_ADRDTAERR                  | error -> AdrDtaErr
        CMP     SideTrack(A1),D1                | right side and track?
        BNE.W   SONY_WRGSIDETRK                 | no -> WrgSideTrk
        MOVE.W  D2,SE_CurSector(A1)             | CurSector (+$140) = sector number
        MOVE    D2,(TagData).w                  | TagData+0 = sector number (for writes)
        MOVE.L  SectMap(A1),D0                  | sectors wanted on this track
        BTST    D2,D0                           | is this one of them?
        BNE.W   SONY_OTSETUP                    | yes -> read or write it
| not wanted: read it into the track cache if caching this track
        TST.B   SE_TCRdEnable(A1)               | TCRdEnable (+$142): reading into the cache?
        BEQ.W   SONY_WRGSECTADR                 | no -> WrgSectAdr
        MOVE.L  SE_TCSectMap(A1),D0             | TCSectMap (+$148)
        BTST    D2,D0                           | already cached?
        BNE.W   SONY_WRGSECTADR                 | yes -> WrgSectAdr
        LEA.L   Sony_RdData(PC),A0              | the driver's own RdData
        CMPA.L  (DiskVars_JRdData).w,A0         | still in the JRdData vector?
        SNE.B   SE_TCRdEnable(A1)               | TCRdEnable = 0 if RdData is patched (copy protection)
        BNE.W   SONY_WRGSECTADR                 | patched -> do not cache
        MOVE    D2,D1                           | D1 = sector number
        MULU    #0x20C,D2                       | * 524 = cache entry offset
        MOVEA.L SE_TCBuffer(A1),A0              | A0 = TCBuffer (+$14C)
        ADDA.L  D2,A0                           | A0 -> cache entry
        ADDA    #0xC,A0                         | A0 -> data part (after the 12 tag bytes)
        BSR.W   E_Sony_RdData                   | RdData into the cache
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        SPL.B   SE_TCRdEnable(A1)               | TCRdEnable = 0 after an error
        BMI.B   SONY_ONTRACK_CACHEDONE          | error -> ignore (may be a copy-protected sector)
        ADDQ.W  #0x1,SE_TCNumCached(A1)         | TCNumCached (+$150): count cached sectors
        MOVE.W  SE_CurSector(A1),D2             | D2 = CurSector (+$140)
        MOVEA.L SE_TCBuffer(A1),A0              | A0 = TCBuffer
        MOVE    D2,D1                           | sector number
        MULU    #0x20C,D1                       | * 524
        ADDA.L  D1,A0                           | A0 -> cache entry
        LEA.L   (BufTgFNum).w,A2                | A2 -> TagData+2: tags just read
        MOVE.L  (A2)+,(A0)+                     | copy the 12 tag bytes
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 5-8
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 9-12
        MOVE.L  SE_TCSectMap(A1),D4             | TCSectMap
        BSET    D2,D4                           | mark the sector as cached
        MOVE.L  D4,SE_TCSectMap(A1)             | update the map
SONY_ONTRACK_CACHEDONE:
        BSet    #0x7,(IntFlag).w                | interrupts to be opened for AppleTalk?
        BNE.B   SONY_RESEEK_POLLONLY            | no -> just poll data
        MOVE    SectTime(A1),D0                 | one sector time
        BSR.W   SONY_WAKESETUP                  | WakeSetUp: prime the timer
        BSR.W   Sony_EmptyPD                    | EmptyPD: process the poll data
        BSR.W   SONY_WAKEUP_GO                  | WakeGo: wait, interrupts open
        BRA.B   SONY_RESEEK_CONT_4              | continue on the track
| no interrupts for AppleTalk needed: just process the poll data
SONY_RESEEK_POLLONLY:
        BSR.W   Sony_EmptyPD                    | EmptyPD
        ANDI    #-0x701,SR                      | open interrupts
SONY_RESEEK_CONT_4:
        BRA.W   SONY_ONTRACK                    | try for the sectors we want
| OTSetUp -- a wanted sector: compute buffer and tag positions
SONY_OTSETUP:
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
        MOVE.W  D1,SE_TagBufOS(A1)              | TagBufOS (+$13A)
        BSR.W   Sony_CheckRead                  | CheckRead: a read?
        BEQ.B   SONY_OTREAD                     | yes -> OTRead
| OTWrite -- write the sector
        MOVE.L  SE_TagBufPtr(A1),D3             | TagBufPtr (+$136): separate tag buffer?
        BEQ.B   SONY_RESEEK_NO_2                | no -> file block number tag only
        MOVE.L  D3,A1                           | A1 = tag buffer
        ADDA    D1,A1                           | A1 -> tags of this block
        LEA.L   (BufTgFNum).w,A2                | A2 -> TagData+2
        MOVE.L  (A1)+,(A2)+                     | copy its 12 tag bytes
        MOVE.L  (A1)+,(A2)+                     | tag bytes 5-8
        MOVE.L  (A1)+,(A2)+                     | tag bytes 9-12
        BRA.B   SONY_RESEEK_CONT_5              | write the sector

| SONY_RESEEK_NO_2 -- no external tag buffer: compute file block number tag
SONY_RESEEK_NO_2:
        ADD     FirstFSeq(A1),D0                | + FirstFSeq = file block number
        MOVE    D0,(BufTgFBkNum).w              | TagData+8 = file block number
SONY_RESEEK_CONT_5:
        BSR.W   E_Sony_WrData                   | WrData: write the sector
        BMI.W   SONY_ADRDTAERR                  | error -> AdrDtaErr
        BRA.B   SONY_GOTSECT                    | sector done
| OTRead -- read the sector
SONY_OTREAD:
        BSR.W   E_Sony_RdData                   | RdData: read the sector
        BMI.W   SONY_ADRDTAERR                  | error -> AdrDtaErr
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  SE_TagBufPtr(A1),D0             | TagBufPtr (+$136): separate tag buffer?
        BEQ.B   SONY_GOTSECT                    | no -> done
        MOVE.L  D0,A0                           | A0 = tag buffer
        ADDA.W  SE_TagBufOS(A1),A0              | + TagBufOS (+$13A)
        LEA.L   (BufTgFNum).w,A2                | A2 -> TagData+2: tags just read
        MOVE.L  (A2)+,(A0)+                     | copy the 12 tag bytes
        MOVE.L  (A2)+,(A0)+                     | tag bytes 5-8
        MOVE.L  (A2)+,(A0)+                     | tag bytes 9-12
| GotSect -- mark the sector done, update position and byte count, then
| continue with the track (or the next track)
SONY_GOTSECT:
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1
        MOVE.L  SectMap(A1),D4                  | sector map
        MOVE.W  SE_CurSector(A1),D2             | CurSector (+$140)
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
        BSR.W   Sony_EmptyPD                    | EmptyPD
        MOVEQ.L #0x7,D0                         | 700 us
        BSR.W   E_Sony_WakeUp                   | WakeUp: let the erase head turn off after the last write
        BRA.B   SONY_RESEEK_DONE                | continue
| wait a sector time with interrupts open
SONY_RESEEK_NO_3:
        MOVE    SectTime(A1),D0                 | one sector time
        BSR.W   SONY_WAKESETUP                  | WakeSetUp
        BSR.W   Sony_EmptyPD                    | EmptyPD
        BSR.W   SONY_WAKEUP_GO                  | WakeGo: wait, interrupts open
        BRA.B   SONY_RESEEK_DONE                | continue
| a read: continue at once (1-1 reads are possible)
SONY_RESEEK_CONT_7:
        BSR.W   Sony_EmptyPD                    | EmptyPD
        ANDI    #-0x701,SR                      | open interrupts
| SONY_RESEEK_DONE -- check if all sectors done, or more tracks needed
SONY_RESEEK_DONE:
        MOVE.L  D4,D0                           | sectors left on this track?
        BNE.W   SONY_ONTRACK                    | yes -> OnTrack
        TST.L   D3                              | bytes left?
        BGT.W   SONY_GETTRACK                   | yes -> GetTrack: next track
        TST.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt: two-sided disk?
        BEQ.B   SONY_TODSKRWOFF                 | no -> done
        TST.B   Sides(A1,D1.W)                  | Sides: two-sided drive?
        BNE.B   SONY_TODSKRWOFF                 | yes -> done
        MOVEQ.L #-0x4E,D0                       | twoSideErr (-78): early warning
SONY_TODSKRWOFF:
        BRA.W   SONY_DSKRWOFF                   | power down and complete
| CheckRead -- BEQ if the request is a read (ioTrap low byte = 2)
| Called by: SONY_CKWRPROT, SONY_DISKPRIME_LOOP, SONY_OTSETUP, SONY_GOTSECT, SONY_ADRDTAERR (and 1 more)
Sony_CheckRead:
        CMPI.B  #aRdCmd,Command+1(A1)           | low byte of Command: ARdCmd?
        RTS                                     | return

| -------------------------------------------------------------------------
| EmptyPD -- call the poll data procedure (PollProc, set by the serial
| driver) to process serial data that was put on the stack while
| interrupts were off, or reset the stack to PollStack if there is none.
| -------------------------------------------------------------------------
| Called by: SONY_ONTRACK_CACHEDONE, SONY_RESEEK_POLLONLY, SONY_GOTSECT, SONY_RESEEK_NO_3, SONY_RESEEK_CONT_7 (and 4 more)
Sony_EmptyPD:
        MOVE.L  (SP)+,A4                        | A4 = return address
        PEA.L   SONY_EMPTYPD_RESUME(PC)         | PollProc returns to SONY_EMPTYPD_RESUME
        MOVE.L  (PollProc).w,-(SP)              | PollProc installed?
        BEQ.B   SONY_EMPTYPD_NOPROC             | no -> throw the data away
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVEM.L D0/D2-D3/A0/A4,SE_SaveRegs(A1)  | save D0/D2/D3/A0/A4 in SaveRegs (+$112)
        RTS                                     | go to PollProc

| SONY_EMPTYPD_RESUME -- PollProc resume point: restore registers
SONY_EMPTYPD_RESUME:
        BSR.W   Sony_GetDrv1                    | GetDrv1
        MOVEM.L SE_SaveRegs(A1),D0/D2-D3/A0/A4  | restore D0/D2/D3/A0/A4
        JMP     (A4)                            | return

| SONY_EMPTYPD_NOPROC -- no PollProc: switch to PollStack and return
SONY_EMPTYPD_NOPROC:
        MOVE.L  (PollStack).w,SP                | reset the stack (discard poll data)
        BSR.W   Sony_GetDrv1                    | GetDrv1
        JMP     (A4)                            | return
| AdrDtaErr -- address or data mark error
SONY_ADRDTAERR:
        BSR.B   Sony_EmptyPD                    | EmptyPD
        ANDI    #-0x701,SR                      | open interrupts
        ADDQ.W  #0x1,SE_DiskErrs(A1)            | DiskErrs (+$13C): global soft error count
        ADDQ.W  #0x1,DriveErrs(A1,D1.W)         | DriveErrs (drive var +$14): drive soft error count
        TST.B   RecalCnt(A1)                    | last recal?
        BEQ.B   SONY_RESEEK_RETRY_3             | yes -> retry rather than fail
        BSR.B   Sony_CheckRead                  | CheckRead: write?
        BNE.B   SONY_DORECAL                    | yes -> recal (may be slightly off track)
SONY_RESEEK_RETRY_3:
        SUBQ.B  #0x1,ReadErrCnt(A1)             | ReadErrCnt: errors left?
        BPL.W   SONY_ONTRACK                    | yes -> try another
        BRA.B   SONY_DORECAL                    | no -> recal
| WrgSectAdr -- a sector we do not need: wait about one sector time
SONY_WRGSECTADR:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE    SectTime(A1),D0                 | one sector time
        BSR.W   SONY_WAKESETUP                  | WakeSetUp
        BSR.B   Sony_EmptyPD                    | EmptyPD
        BSR.W   SONY_WAKEUP_GO                  | WakeGo
        ADDQ.L  #0x1,(RndSeed).w                | bump the random seed
        MOVEQ.L #-0x51,D0                       | sectNFErr (-81) in case we run out of recals
        SUBQ.B  #0x1,WrgSectCnt(A1)             | WrgSectCnt: enough wrong sectors?
        BMI.B   SONY_DORECAL                    | yes -> recal
        BRA.W   SONY_ONTRACK1                   | OnTrack1: keep looking
| WrgSideTrk -- wrong track or side under the head
SONY_WRGSIDETRK:
        BSR.B   Sony_EmptyPD                    | EmptyPD
        MOVEQ.L #-0x50,D0                       | seekErr (-80) in case we run out of recals
| DoRecal -- recalibrate to track 0, measure the speeds again and retry
SONY_DORECAL:
        ANDI    #-0x701,SR                      | open interrupts
        SUBQ.B  #0x1,RecalCnt(A1)               | RecalCnt: recal done already?
        BLE.B   SONY_RESEEK_ERR_7               | yes -> give up
        BSR.W   E_Sony_Recal                    | Recal
        BMI.B   SONY_RESEEK_ERR_7               | error -> give up
        BSR.W   E_Sony_MakeSpdTbl               | MakeSpdTbl
        BPL.W   E_Sony_ReSeek                   | ok -> seek again
SONY_RESEEK_ERR_7:
        BRA.W   SONY_TODSKRWOFF                 | power down and return the error

| -------------------------------------------------------------------------
| DrvVarOS -- offset of each drive's variables in SonyVars, for physical
| drive numbers 1-5 (indexed with drive*2, hence DRVVAROFS-2 below).
| The SE inserted the 66-byte variables of the third floppy at $CE, so
| all driver variables from WakeTimeCnt on are $42 bytes higher than in
| the Mac Plus driver; the HD20 variables follow the translation table.
| -------------------------------------------------------------------------
DRVVAROFS:
        .short  Drive1                          | drive 1: lower internal drive (Drive1 vars)
        .short  Drive2                          | drive 2: upper internal drive (Drive2 vars)
        .short  SE_Drive3                       | drive 3: external drive (new 3rd floppy vars)
        .short  SE_Drive4                       | drive 4: first HD20
        .short  SE_Drive5                       | drive 5: second HD20

| -------------------------------------------------------------------------
| GetRDrive, GetDrive, GetDrv1, GetDrv2 -- set up the much-used registers
|   A0 (out) -- IWM base (GetRDrive, GetDrive)
|   A2 (out) -- VIA base (GetRDrive, GetDrive)
|   A1 (out) -- SonyVars
|   D1 (out) -- offset of the current drive's variables
| GetDrive and GetDrv1 translate Drive (a logical drive number) through
| the table at SonyVars+$16C; GetRDrive does not translate (it is not
| called in this ROM). Mac Plus driver: no translation, Sony_SetupRegs
| (Mac Plus) = GetDrive, Sony_SetupSonyVars (Mac Plus) = GetDrv1.
| Drive numbers above 5 (the pass-thru probe in DiskOpen uses 6) are
| bounded to 5.
| -------------------------------------------------------------------------
Sony_GetRDrive:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base
        MOVE.L  (VIA).w,A2                      | A2 = VIA base
        BSR.B   Sony_GetDrv2                    | GetDrv2: A1, D1 = drive number * 2
        MOVE.W  DRVVAROFS-2(PC,D1.W),D1         | D1 = drive vars offset (untranslated)
        RTS                                     | return
| Called by: E_SONY_OPEN_LOOP, Sony_AdrDisk, SONY_GOWAKEIT, Sony_Recal, Sony_DiskSelect (and 2 more)
Sony_GetDrive:
        MOVEA.L (IWM).w,A0                      | GetDrive: A0 = IWM base
        MOVEA.L (VIA).w,A2                      | A2 = VIA base
| Called by: Sony_CkDrvNum, SONY_GOTSECT, SONY_EMPTYPD_RESUME, SONY_EMPTYPD_NOPROC, Sony_SetSpeed (and 13 more)
Sony_GetDrv1:
        BSR.B   Sony_GetDrv2                    | GetDrv1: A1 = SonyVars, D1 = logical drive * 2
        LEA.L   SE_DriveXlat(A1),A1             | A1 -> drive number translation table
        MOVE.W  0x0(A1,D1.W),D1                 | D1 = physical drive number
        ADD.W   D1,D1                           | * 2
        MOVE.W  DRVVAROFS-2(PC,D1.W),D1         | D1 = drive vars offset
        MOVEA.L (SonyVars).w,A1                 | A1 = SonyVars
        RTS                                     | return
| GetDrv2 -- A1 = SonyVars, D1 = Drive * 2 (Drive bounded to 5)
Sony_GetDrv2:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE    Drive(A1),D1                    | D1 = Drive
        CMPI.W  #0x5,D1                         | above the last drive number?
        BLE.B   SONY_GETDRV3                    | no ->
        MOVE.W  #0x5,D1                         | bound it to 5
SONY_GETDRV3:
        ADD     D1,D1                           | D1 = drive number * 2
        RTS                                     | return

| -------------------------------------------------------------------------
| AdrDisk -- address one of the 16 drive registers
|   D0 (in) -- register address, bits 0-3 = CA2, SEL, CA0, CA1 (Apple's
|              order CA1-CA0-SEL-CA2, bit 3 to bit 0)
| CA0-CA2 are the IWM phase lines PH0-PH2, SEL is VIA port A bit 5
| (vHeadSel). CA0 = CA1 = 1 must be true while SEL changes from 1 to 0
| (Apple's comment), hence both are set first.
| -------------------------------------------------------------------------
| Called by: SONY_CTL_EJECT_GO, Sony_AdrAndSense, Sony_AdrAndStrb, Sony_FigTrkSpd, SONY_RDADDRSETUP_SIDE (and 1 more)
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
| Called by: CHKCONNECT, SONY_NEWDRVEJECT_LOOP, Sony_DiskPrime, SONY_DISKPRIME_CONT, Sony_CkDCDExist (and 7 more)
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
| Called by: SONY_SEEK_CONT_2, SONY_RECAL_CONT_2, SONY_POWERDOWN_NOW, Sony_DiskVBLTask, SONY_CKEJSW
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
| An HD20 shows /DrvExst = 1 and /Sides = 1 (like no floppy drive) and
| asserts its /Exist line (register address 5).
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
| Sony_SetSpeed -- set the disk speed for a track (400K drives: speed
| code through the PWM bytes of the sound buffer; new-interface drives
| regulate their speed themselves and get code 0)
|   D6 (in) -- track number
| Looks up the zone's speed code in TrkSpeedTbl, clamps it to [0, $1B8],
| adds the time the speed change takes to Wait and programs the PWM
| bytes (SONY_SETSPEED_CONT_3).
Sony_SetSpeed:
        BSR.W   Sony_GetDrv1                    | A1=SonyVars, D1=drive offset
        MOVE    D6,D2                           | D2 = target track
        LSR     #0x4,D2                         | zone index (track / 16)
        LSL     #0x3,D2                         | zone * 8 (table stride)
        ADD     D1,D2                           | per-drive zone table offset
        MOVE    TrkSpeedTbl(A1,D2.W),D2         | D2 = TSTblCode: speed code of the zone
        TST.B   NewIntf(A1,D1.W)                | NewIntf: new-interface (800K) drive?
        BMI.B   SONY_SETSPEED_NO                | yes -> speed code 0 (the drive sets its own speed)
        TST     D2                              | speed value negative?
        BPL.B   SONY_SETSPEED_OK                | no -> use as-is
SONY_SETSPEED_NO:
        MOVEQ.L #0x0,D2                         | clamp minimum to 0
SONY_SETSPEED_OK:
        CMPI    #0x1B8,D2                       | exceeds max PWM value ($1B8=440)?
        BLE.B   SONY_SETSPEED_OK_2              | no -> use as-is
        MOVE    #0x1B8,D2                       | clamp to max
SONY_SETSPEED_OK_2:
        MOVE    (PWMValue).w,D0                 | D0 = current speed code
        BPL.B   SONY_SETSPEED_CONT              | valid -> delay from the size of the change
        MOVE    PwrOnTime(A1),D0                | none yet (PWMValue = $FFFF from boot): power-on time
        BRA.B   SONY_SETSPEED_NO_2              | apply delay

| SONY_SETSPEED_CONT -- compute spin-up/down settling delay
SONY_SETSPEED_CONT:
        SUB     D2,D0                           | D0 = magnitude of speed change
        BEQ.W   Sony_GetDrv1                    | no change -> return
        BPL.B   SONY_SETSPEED_CONT_2            | positive -> slowing down
        NEG     D0                              | make positive
SONY_SETSPEED_CONT_2:
        LSL     #0x5,D0                         | scale by 32 for delay estimate
        CMP     SpdChgTime(A1),D0               | below minimum speed change time?
        BGT.B   SONY_SETSPEED_NO_2              | no -> use computed delay
        MOVE    SpdChgTime(A1),D0               | enforce minimum delay
SONY_SETSPEED_NO_2:
        ADD     Wait(A1),D0                     | + Wait still pending
        CMP     PwrOnTime(A1),D0                | exceeds max delay?
        BLT.B   SONY_SETSPEED_NO_3              | no -> use sum
        MOVE    PwrOnTime(A1),D0                | clamp to max
SONY_SETSPEED_NO_3:
        MOVE    D0,Wait(A1)                     | Wait = time to wait for the speed change
| SONY_SETSPEED_CONT_3 -- ProgramPWM: store the speed code D2 in PWMValue
| and fill the 370 PWM bytes of the sound buffer at PWMBuf1 and at PWMBuf2
| (every second byte: the PWM bytes are the low bytes of the sound buffer
| words, Apple's HardwareEqu.a "PWM bytes are low bytes"; on the SE both
| pointers address the same buffer, MemTop-$2FF). The values are states
| of a 6-bit linear-feedback shift register: ($1B8 - code) / 10 steps
| from $1E give two neighbouring states, and of each group of 10 bytes
| (remainder) get the later and the rest the earlier one. (Apple's
| SonyUtil.a lists the routines SetSpeed and SetASpeed; this entry,
| called with a given code by GetFreq, is probably SetASpeed.)
SONY_SETSPEED_CONT_3:
        MOVE    D2,(PWMValue).w                 | PWMValue = new speed code
        MOVEM.L D3-D6/A2,-(SP)                  | save registers
        SUBI    #0x1B8,D2                       | D2 = $1B8 - speed (invert)
        NEG     D2                              | D2 = inverted PWM count
        EXT.L   D2                              | sign-extend for DIVU
        DIVU    #0xA,D2                         | D2.w = quotient, D2.hi = remainder
        MOVEQ.L #0x1E,D0                        | D0 = LFSR seed (6-bit)
SONY_SETSPEED_LFSR:
        MOVE.B  D0,D1                           | D1 = previous LFSR value
        MOVE.B  D0,D3                           | D3 = feedback calculation
        LSR.B   #0x1,D0                         | shift LFSR right
        EOR.B   D0,D3                           | XOR for feedback tap
        LSR.B   #0x1,D3                         | isolate feedback bit
        BCC.B   SONY_SETSPEED_SKIP              | no feedback -> skip
        BSET    #0x5,D0                         | inject feedback into bit 5
SONY_SETSPEED_SKIP:
        DBF     D2,SONY_SETSPEED_LFSR           | iterate LFSR D2 times
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
        ADDQ.W  #0x2,A0                         | next PWM byte (every second byte)
        ADDQ.W  #0x2,A2                         | advance buffer 2 likewise
        DBF     D2,SONY_SETSPEED_LOOP_3         | inner loop: 10 samples per group
        DBF     D3,SONY_SETSPEED_LOOP_2         | outer loop: 37 groups = 370 samples
        MOVEM.L (SP)+,D3-D6/A2                  | restore registers
        BRA.W   Sony_GetDrv1                    | reload SonyVars and return

| PWM dither patterns of SetSpeed: the word at SONY_SETSPEED_CONT_6 +
| remainder of ($1B8 - code) / 10 selects, bit by bit from bit 15, the
| bytes of a group of 10 that get the later LFSR state (as in the Mac
| Plus driver)
SONY_SETSPEED_CONT_6:
        .byte   0x00                            | PWM dither pattern MSB (11 entries)
SONY_SETSPEED_CONT_7:
        .byte   0x20,0x21,0x24,0x94,0xAA,0xB5   | PWM dither pattern LSB, entries 0-5
        .byte   0xB7,0x7B,0xFF,0x40,0x00        | PWM dither pattern LSB, entries 6-10

| -------------------------------------------------------------------------
| Seek -- seek to a track
|   D6.W (in) -- track (bit 11 = side 1; cleared here)
|   D0 (out)  -- result: track number, or a negative error code
| Sets the PWM speed for the target zone first. Returns to one level
| above the caller while waiting (A6 = return address).
| -------------------------------------------------------------------------
E_Sony_Seek:
        BCLR    #0xB,D6                         | clear side bit, keep track only
        BSR.W   Sony_SetSpeed                   | program PWM speed for target zone
        MOVE.L  (DiskVars_JSeek).w,-(SP)        | push Seek vector address
        RTS                                     | dispatch to Sony_Seek
| jtSeek (JSeek vector) -- step the head from Track to D6 one track at a
| time: for each step set the direction (AdrAndStrb), store the new
| Track, check that /STEP is high (cantStepErr if not), pulse it and wait
| (Wait100). (The SuperDrive driver of the SE FDHD rewrote this loop.)
Sony_Seek:
        MOVE.L  (SP)+,A6                        | save return address
        BSR.W   Sony_GetDrv1                    | set up SonyVars (A1) and drive vars
        MOVE    Track(A1,D1.W),D7               | D7 = current track
        BPL.B   SONY_SEEKLP                     | valid ->
| current track unknown: recalibrate
        BSR.W   E_Sony_Recal                    | Recal
        MOVE    D0,D7                           | D7 = result (track 0 or error)
        BRA.B   SONY_SEEKEND                    | SeekEnd with the Recal result (no seek)
| SeekLp -- the step loop: compare with the target track, then one step
| at a time
SONY_SEEKLP:
        CMP     D6,D7                           | already on the target track?
        BEQ.B   SONY_SEEKEND1                   | already there -> SeekEnd1: no head settle time, just wait out any speed change
| set up step direction
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
        MOVEQ.L #-0x4B,D7                       | cantStepErr (-75): drive will not step
        BRA.B   SONY_SEEKEND                    | store it as the track
SONY_SEEK_CONT_3:
        BSR.W   Sony_Pulse                      | LSTRB pulse at StepLAdr (CA2 = 0): step, /STEP goes low
        BSR.B   SONY_WAIT100                    | Wait100: wait for the step to finish
        BRA.B   SONY_SEEK_CONT                  | next step
| SeekEnd -- store the track, wait for the head to settle (or for /READY
| on a new-interface drive) and for any speed change
SONY_SEEKEND:
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1
        MOVE    D7,Track(A1,D1.W)               | Track = result
        MOVE    HeadSettle(A1),D0               | HeadSettle: 30 ms head settle time
        MOVEQ.L #0x5,D2                         | first wait 500 us (new drives)
        BSR.W   SONY_WAITREADY                  | waitReady
SONY_SEEKEND1:
        MOVE    Wait(A1),D0                     | Wait: speed change or power-on time still to go
        MOVEQ.L #0x0,D2                         | no first wait
        BSR.W   SONY_WAITREADY                  | waitReady
        MOVE    D7,D0                           | D0 = result
        JMP     (A6)                            | return
| Wait100 -- wait for a step: SeekTime for an old drive, else poll
| /STEP until it goes high again (at most 81 times)
SONY_WAIT100:
        MOVE    SeekTime(A1),D0                 | SeekTime: 12 ms
        BSR.B   SONY_CHECKNEW                   | CheckNew: old drive -> WakeUp for D0 and return
        MOVEQ.L #0x50,D5                        | poll count
SONY_WAIT100_LOOP:
        MOVEQ.L #StepLAdr,D0                    | StepLAdr
        BSR.W   Sony_AdrAndSense                | sense
        DBMI    D5,SONY_WAIT100_LOOP            | until /STEP is high again
        RTS                                     | return
| CheckNew -- for an old-interface (400K) drive, wait D0 with WakeUp and
| return to the caller's caller; return at once for a new drive
SONY_CHECKNEW:
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BPL.B   SONY_CHECKNEW_WAIT              | no -> wait
        RTS                                     | yes: return

| SONY_CHECKNEW_WAIT -- 400K drive: pop caller's return, wait D0 * 100 us
SONY_CHECKNEW_WAIT:
        ADDQ.W  #0x4,SP                         | drop our caller's return address
        TST     D0                              | any time to wait?
        BEQ.B   SONY_CHECKNEW_EXIT              | no -> return
        BRA.B   E_Sony_WakeUp                   | WakeUp

| SONY_CHECKNEW_EXIT -- no delay needed
SONY_CHECKNEW_EXIT:
        RTS                                     | return
| waitReady -- wait for /READY of a new-interface drive
|   D0 (in) -- wait time for an old drive (100 us units)
|   D2 (in) -- first wait before polling /READY (100 us units, 0 = none)
| /READY is polled every 1 ms; after about 1 s the drive is taken as
| ready anyway (Apple: "if we timeout, we must be ready??"). Returns to
| one level above the caller while waiting.
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
        BSR.W   Sony_AdrAndSense                | sense = 0 when ready
        BPL.B   SONY_WAITREADY_DONE             | ready ->
        MOVEQ.L #0xA,D0                         | then check every 1 ms
        DBF     D5,SONY_WAITREADY_LOOP          | until ready or 1 s has passed
SONY_WAITREADY_DONE:
        CLR     Wait(A1)                        | Wait = 0: no extra wait time
        JMP     (A4)                            | return

| -------------------------------------------------------------------------
| WakeUp, WakeSetUp, WakeGo -- wait in the background
|   D0 (in) -- number of 100 us intervals to wait (< 65536)
| The caller's registers D3-D7/A3-A6 go to SaveRegs (+$112) and its
| return address to DskRtnAdr; the driver returns to the caller's caller
| (normally the application, the request continues asynchronously) and
| GoWakeIt resumes the caller from a Time Manager task when the time is
| up. WakeSetUp only primes the timer; WakeGo saves the state and
| returns. jtWakeUp now saves the state before priming the timer (the
| Mac Plus driver primed it first and could be interrupted too early).
| -------------------------------------------------------------------------
| Called by: SONY_CTL_EJECT_GO, SONY_NEWDRVEJECT_LOOP, SONY_GOTSECT, SONY_WAITREADY_LOOP, SONY_RECAL_CONT_2 (and 5 more)
E_Sony_WakeUp:
        MOVE.L  (DiskVars_JWakeUp).w,-(SP)      | push the JWakeUp vector
        RTS                                     | and jump through it
| jtWakeUp (JWakeUp vector)
Sony_WakeUp:
        MOVEM.L D3-D7/A3-A6,SE_SaveRegs(A1)     | save the caller's registers first
        MOVE.L  (SP)+,(DskRtnAdr).w             | return address -> DskRtnAdr
        BSR.B   SONY_WAKESETUP                  | WakeSetUp: prime the timer
        BRA.B   SONY_WAKEUP_RET                 | return to the caller's caller
| WakeGo -- wait set up by WakeSetUp: save the state and return
SONY_WAKEUP_GO:
        MOVEM.L D3-D7/A3-A6,SE_SaveRegs(A1)     | WakeGo: save the caller's registers
| SONY_WAKEUP_EXIT -- return to WakeUp continuation.
SONY_WAKEUP_EXIT:
        MOVE.L  (SP)+,(DskRtnAdr).w             | return address -> DskRtnAdr
SONY_WAKEUP_RET:
        MOVEQ.L #0x0,D0                         | WakeRet: no error
        ANDI    #-0x701,SR                      | open VIA interrupts
        RTS                                     | return to the caller's caller
| WakeSetUp -- prime the Time Manager element (TimeQEl) for D0 * 100 us
SONY_WAKESETUP:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        SUB     D0,Wait(A1)                     | Wait -= D0
        BGT.B   SONY_WAKESETUP_1                | still positive ->
        CLR     Wait(A1)                        | pin it at 0
SONY_WAKESETUP_1:
        LEA.L   SE_TimeQEl(A1),A0               | A0 -> TimeQEl (+$15A)
        LEA.L   SONY_GOWAKEIT(PC),A1            | GoWakeIt
        MOVE.L  A1,0x6(A0)                      | tmAddr = GoWakeIt
        ANDI.L  #0xFFFF,D0                      | clear the high word of D0
        CMPI    #0xA,D0                         | at least 10 * 100 us
        BCC.B   SONY_WAKESETUP_2                | yes ->
        MOVEQ.L #0xA,D0                         | else 1 ms
SONY_WAKESETUP_2:
        DIVU    #0xA,D0                         | / 10 = milliseconds
        EXT.L   D0                              | PrimeTime takes a long count
        MOVE.L  (jPrimeTime).w,A1               | A1 = jPrimeTime vector
        JSR     (A1)                            | PrimeTime (A0 = TimeQEl)
        BSR.W   Sony_GetDrv1                    | GetDrv1: restore A1, D1
        RTS                                     | return
| GoWakeIt -- Time Manager task: resume the waiting caller
SONY_GOWAKEIT:
        MOVEM.L D0-D7/A0-A6,-(SP)               | save all registers
        BSR.W   Sony_GetDrive                   | GetDrive
        MOVEM.L SE_SaveRegs(A1),D3-D7/A3-A6     | restore the caller's D3-D7/A3-A6
        MOVEQ.L #0x0,D0                         | D0 = 0
        BSR.W   SONY_DSKRTN                     | DskRtn: call the routine at DskRtnAdr
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore the registers
SONY_GOWAKEIT_EXIT:
        RTS                                     | return to the Time Manager

| -------------------------------------------------------------------------
| Recal -- recalibrate: step out to track 0 (D7 = 80: at most 79 steps)
|   D0 (out) -- 0 or an error code, also stored as the current track
| Sets the IWM mode first. Returns to one level above the caller while
| waiting (A5 = return address).
| -------------------------------------------------------------------------
E_Sony_Recal:
        MOVE.L  (DiskVars_JRecal).w,-(SP)       | push Recal vector address
        RTS                                     | dispatch to Sony_Recal
| jtRecal (JRecal vector) -- set the IWM mode (SetIWMMode), then step out
| until track 0 is sensed
Sony_Recal:
        MOVE.L  (SP)+,A5                        | A5 = return address
        BSR.W   Sony_GetDrive                   | GetDrive
        BSR.W   SONY_INVALTRKCACHE              | InvalTrkCache
        BSR.B   SONY_SETIWMMODE                 | SetIWMMode (a subroutine on the SE)
        BNE.B   SONY_RECAL_ERR_2                | could not set the IWM mode -> return initIWMErr
SONY_RECAL_SKIP:
        MOVEQ.L #0x50,D7                        | D7 = 80: at most 79 steps
| SlowLoop -- one step per SeekTime (half of it for new-interface drives)
SONY_RECAL_CONT:
        MOVE    SeekTime(A1),D0                 | SeekTime: 12 ms
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BPL.B   SONY_RECAL_CONT_2               | no -> full time
        LSR     #0x1,D0                         | yes -> 6 ms
SONY_RECAL_CONT_2:
        BSR.W   E_Sony_WakeUp                   | WakeUp
        MOVEQ.L #Tk0Adr,D0                      | Tk0Adr: track 0 sense
        BSR.W   Sony_AdrAndSense                | sense = 0 at track 0
        BPL.B   SONY_RECAL_DONE                 | there -> done
        MOVEQ.L #DirHAdr,D0                     | DirHAdr: direction control, CA2 = 1: out (toward track 0)
        BSR.W   Sony_AdrAndStrb                 | set the direction
        MOVEQ.L #StepLAdr,D0                    | StepLAdr: /STEP sense
        BSR.W   Sony_AdrAndSense                | /STEP high (1) = ready to step
        BPL.B   SONY_RECALFAIL                  | not ready -> cantStepErr
        MOVEQ.L #-0x4C,D0                       | tk0BadErr (-76) if we run out of steps
        SUBQ.W  #0x1,D7                         | count the step
        BEQ.B   SONY_RECAL_ERR_2                | 79 steps without track 0 -> error
        BSR.W   Sony_Pulse                      | LSTRB pulse at StepLAdr: step
        BRA.B   SONY_RECAL_CONT                 | again

| SONY_RECAL_DONE -- reached track 0 successfully
SONY_RECAL_DONE:
        MOVEQ.L #0x0,D0                         | track 0
        BRA.B   SONY_RECAL_ERR_2                | store and return

| RecalFail -- the drive cannot step and is not at track 0
SONY_RECALFAIL:
        MOVEQ.L #-0x4B,D0                       | cantStepErr (-75): drive will not step
SONY_RECAL_ERR_2:
        MOVE    D0,Track(A1,D1.W)               | Track = 0 or error code
        JMP     (A5)                            | return

| -------------------------------------------------------------------------
| SetIWMMode -- make sure the IWM mode register holds iwmMode = $17;
| separated from Recal on the SE (A351, 5 Nov 1986).
|   D0 (out), CCR -- 0 (BEQ) or initIWMErr (BNE) after about a second
| $17 = mode register bits (IWM Design Spec): 0 latch mode (to be set in
| asynchronous mode), 1 asynchronous handshake, 2 1-second timer off
| (the enable drops as soon as LMotor-On is cleared), 3 = 0 slow mode,
| 4 8 MHz (FCLK divided by 8 for the internal 1 us). In 8 MHz slow mode
| a bit cell lasts 32 FCLK periods: 2.04 us with the SE's 15.6672 MHz
| FCLK (Apple's SonyMFM.a: "For a 15.6672MHz input clock (Mac SE, Mac
| II, etc)"; FCLK = C16M in Apple's Mac II wiring diagram), twice the
| Mac Plus's 7.8336 MHz: the 2 us GCR bit cell. Apple's SonyEqu.a
| has $17 for the SE: "changed for Brian Howard to set half speed"; the
| Mac Plus driver sets $1F (fast mode, 16 FCLK periods per cell). The
| status register echoes the mode in bits 0-4. The mode register is
| written with L7 = L6 = 1 while no drive is enabled; with the timer on
| it is not accessible until the timer has run down (SWIM Chip User's
| Ref, "Set Mode"), hence the wait for status bit 5 = 0. Unlike the boot
| code (INITIWM) this compares all five mode bits. If the mode had to be
| set, the drive is powered up again (RWPowerUp).
| -------------------------------------------------------------------------
SONY_SETIWMMODE:
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVE.B  q7L(A0),D0                      | Q7L: read the status register
        TST.B   q6L(A0)                         | Q6L: back to read mode
        ANDI.B  #0x1F,D0                        | mode bits (status bits 0-4)
        CMPI.B  #iwmMode,D0                     | mode $17 already set?
        BEQ.B   SONY_SETIWMMODE_EXIT            | yes -> return (BEQ)
        MOVEQ.L #0x2,D2                         | D2 = $20000: timeout of about a second
        SWAP    D2                              | (in the high word)
SONY_SETIWMMODE_LOOP:
        MOVEQ.L #-0x4D,D0                       | initIWMErr (-77): assume timeout
        SUBQ.L  #0x1,D2                         | count down
        BMI.B   SONY_SETIWMMODE_EXIT            | timeout -> return (BNE)
        TST.B   mtrOff(A0)                      | mtrOff: LMotor-On = 0 (with the 1-second timer on, the enable stays active until it runs out)
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVE.B  q7L(A0),D0                      | Q7L (L7 = 0): read the status register
        BTST    #0x5,D0                         | status bit 5: an enable /ENBLx still active?
        BNE.B   SONY_SETIWMMODE_LOOP            | yes -> keep waiting
        ANDI.B  #0x1F,D0                        | mode bits
        CMPI.B  #iwmMode,D0                     | already $17?
        BEQ.B   SONY_SETIWMMODE_DONE            | yes -> done
        MOVE.B  #iwmMode,q7H(A0)                | Q7H with L6 = 1, motor off: write the mode register = $17
        TST.B   q7L(A0)                         | Q7L: L7 = 0, status register again
        BRA.B   SONY_SETIWMMODE_LOOP            | check again
SONY_SETIWMMODE_DONE:
        TST.B   q6L(A0)                         | Q6L: L6 = 0, back to read mode
        BSR.B   Sony_RWPowerUp                  | RWPowerUp: re-enable the drive
        MOVEQ.L #0x0,D0                         | noErr
SONY_SETIWMMODE_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| PowerDown -- power down the current drive
|   D0 (in) -- 0: at once; else the VBL task powers it down after D0
|             VBL calls (TimeOut, TimeOutDrive)
| -------------------------------------------------------------------------
Sony_PowerDown:
        BSR.W   Sony_GetDrv1                    | GetDrv1
        MOVE    D0,TimeOut(A1)                  | TimeOut = D0
        BEQ.B   SONY_POWERDOWN_NOW              | 0 -> power down now
        MOVE.W  Drive(A1),SE_TimeOutDrive(A1)   | TimeOutDrive (+$158) = Drive
        RTS                                     | return

| SONY_POWERDOWN_NOW -- immediate motor off
SONY_POWERDOWN_NOW:
        MOVEQ.L #MtrOffAdr,D0                   | MtrOffAdr: motor control, CA2 = 1: motor off
        BSR.W   Sony_AdrAndStrb                 | AdrAndStrb
        TST.B   mtrOff(A0)                      | mtrOff: also cut the drive enable /ENBLx
        RTS                                     | return
| InvalTrkCache -- forget the track cache contents if they belong to the
| current drive
SONY_INVALTRKCACHE:
        MOVE.W  SE_TCDrive(A1),D0               | TCDrive (+$144)
        CMP.W   Drive(A1),D0                    | this drive?
        BNE.B   SONY_INVALTRKCACHE_EXIT         | no ->
        CLR.W   SE_TCDrive(A1)                  | TCDrive = 0: cache invalid
SONY_INVALTRKCACHE_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| FastPower, RWPowerUp, PowerUp -- select the drive and power it up
|   D0 (in) -- time to wait if the motor was off (PowerUp)
| If the motor was off, a new-interface drive is waited for until /READY
| (first 75 ms, then every 1 ms, at most about 1 s) and an old drive for
| D0: FastPower 0 (MakeSpdTbl measures the speed next), RWPowerUp
| PwrOnTime (400 ms). Returns to one level above the caller while
| waiting. (Apple later added a 600 ms wait after /READY before writes,
| "for speed +-1.5%" -- SonyUtil.a, 26 Feb 1988; the hand notes give
| 600 ms as the longest motor-on to RDY time of the SuperDrive.)
| -------------------------------------------------------------------------
Sony_FastPower:
        MOVEQ.L #0x0,D0                         | FastPower: no extra wait
        BRA.B   Sony_PowerUp                    | common path
Sony_RWPowerUp:
        MOVE    PwrOnTime(A1),D0                | RWPowerUp: PwrOnTime (400 ms)
Sony_PowerUp:
        MOVE    D0,D2                           | PowerUp: D2 = wait time
        BSR.B   Sony_DiskSelect                 | DiskSelect
        MOVEQ.L #MtrOnAdr,D0                    | MtrOnAdr: motor-on sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when the motor is on
        BPL.B   SONY_POWERUP_EXIT               | already on -> return
        BSR.W   Sony_Pulse                      | LSTRB pulse at MtrOnAdr (CA2 = 0): motor on
        MOVE    D2,D0                           | D0 = wait time
        MOVE    #0x2EE,D2                       | first wait 75 ms (750 * 100 us)
        BRA.W   SONY_WAITREADY                  | waitReady

| SONY_POWERUP_EXIT -- motor already on
SONY_POWERUP_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| DiskSelect -- select the current drive and enable it (/ENBL)
| (GetDrive, then jump through the JDiskSel vector; DiskSel1 skips
| GetDrive)
| -------------------------------------------------------------------------
| Called by: SONY_OPEN_XLATINIT, E_SONY_OPEN_CONT, SONY_CTL_EJECT_GO, Sony_DiskPrime, Sony_PowerUp (and 2 more)
Sony_DiskSelect:
        BSR.W   Sony_GetDrive                   | GetDrive
Sony_DiskSel1:
        MOVE.L  (JDiskSel).w,-(SP)              | DiskSel1: push the JDiskSel vector
        RTS                                     | and jump through it
| jtDiskSel (JDiskSel vector) -- a pending power-down of another drive is
| done now. Internal drives: VIA PA4 (vDriveSel) chooses the lower
| (drive 1, PA4 = 1) or upper (drive 2, PA4 = 0) drive, then the IWM
| internal drive line is selected. External drive and HD20s: the
| external line, with the HD20 daisy-chain handshake when pass-thru works.
| Note: for drive 2 PA4 is first set and then cleared; Apple's System
| patch PA182 (PatchSEROM.a, 21 May 87) replaced this routine "to fix the
| performance of the upper internal floppy drive" (it sets PA4 once:
| BSET for drive 1, BCLR for drive 2; the external path stays in ROM).
Sony_jtDiskSel:
        TST     TimeOut(A1)                     | TimeOut: power-down pending?
        BEQ.B   SONY_DISKSEL_SKIP               | no ->
        MOVE.W  SE_TimeOutDrive(A1),D0          | TimeOutDrive (+$158)
        CMP     Drive(A1),D0                    | the current drive?
        BEQ.B   SONY_DISKSEL_SKIP               | yes -> nothing to do
        MOVEQ.L #0x0,D0                         | another drive: power it down now
        BSR.B   Sony_PowerDown                  | PowerDown (it stays selected)
SONY_DISKSEL_SKIP:
        CLR     TimeOut(A1)                     | no power-down pending any more
        CMPI.W  #Drive2,D1                      | internal drive (offset $4A or $8C)?
        BGT.B   SONY_DISKSEL_NO                 | no -> external drive or HD20
        BSET    #vDriveSel,vBufD(A2)            | vDriveSel = 1: lower drive
        CMPI    #Drive1,D1                      | drive 1?
        BEQ.B   SONY_DISKSEL_INT                | yes ->
        BCLR    #vDriveSel,vBufD(A2)            | vDriveSel = 0: upper drive
SONY_DISKSEL_INT:
        TST.B   intDrive(A0)                    | intDrive: Drive-Sel = 0, /ENBL1 (internal drives)
        TST.B   mtrOn(A0)                       | mtrOn: LMotor-On = 1, /ENBL1 low
        RTS                                     | return
| external port: may already be enabled in state 2, so go safely through
| state 6 to state 7 (CA0 = CA1 = CA2 = 1)
SONY_DISKSEL_NO:
        TST.B   ph2H(A0)                        | CA2 high
        TST.B   ph1H(A0)                        | CA1 high
        TST.B   ph0H(A0)                        | CA0 high
        BCLR    #vHeadSel,vBufD(A2)             | SEL low: address $D, DrvExstAdr (/Exist for an HD20)
        TST.B   extDrive(A0)                    | extDrive: Drive-Sel = 1, /ENBL2 (external port)
        TST.B   SE_PassThru(A1)                 | PassThru (+$13E): HD20 pass-thru works?
        BEQ.B   SONY_DISKSEL_OK                 | yes -> daisy-chain selection
        TST.B   mtrOn(A0)                       | mtrOn: /ENBL2 low
        RTS                                     | return
| HD20 daisy chain: the external floppy (drive 3) sits behind the HD20s
SONY_DISKSEL_OK:
        CMPI.W  #SE_Drive3,D1                   | drive 3 (external floppy)?
        BNE.B   SONY_DISKSEL_HD20               | no -> HD20 drive
        TST.B   mtrOn(A0)                       | mtrOn: /ENBL2 low
        MOVEQ.L #0x2,D0                         | at most 2 chain clocks (one per HD20 in front)
SONY_DISKSEL_CONT:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | no interrupts
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
SONY_DISKSEL_CONT_2:
        TST.B   q7L(A0)                         | Q7L: status, bit 7 = sense at address $D
        DBPL    D0,SONY_DISKSEL_LOOP            | until it is 0 or the count is done
        TST.B   q6L(A0)                         | Q6L: back to read mode
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return

| SONY_DISKSEL_LOOP -- clock the HD20 daisy chain: pulse LSTRB, then CA1
| low and high again (the HD20 protocol is not in the documents at hand)
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
| HD20 drive: drop /ENBL briefly, then clock the chain to the drive
SONY_DISKSEL_HD20:
        TST.B   mtrOff(A0)                      | mtrOff: /ENBL2 off
        MOVE    Drive(A1),D0                    | drive number
        MOVE.L  (SP),(SP)                       | (delay)
        TST.B   mtrOn(A0)                       | mtrOn: /ENBL2 low again
        SUBQ.W  #0x4,D0                         | 4 -> 0, 5 -> 1: at most that many chain clocks
        BRA.B   SONY_DISKSEL_CONT               | clock the chain

| -------------------------------------------------------------------------
| SpeedCheckTbl -- per zone the upper and lower limit (+-2%) of the speed
| value of GetFreq1 ($4000000 / (sum of four FigTrkSpd counts / 8),
| proportional to the rotation speed) accepted by the speed check in
| jtReSeek; the midpoints are the targets of MakeSpdTbl. With the VIA
| timer at 783.36 kHz the midpoints are about 394, 429, 472, 525 and 590
| rpm (zones 0-4). Same as the Mac Plus driver.
| -------------------------------------------------------------------------
DT_Sony_SpeedCheckTbl:
        .byte   0x11,0xE9,0x11,0x35,0x13,0x8A   | zone 0: hi=0x11E9, lo=0x1135; zone 1 hi=0x138A
        .byte   0x12,0xC6,0x15,0x7F,0x14,0xA7   | zone 1 lo=0x12C6; zone 2: hi=0x157F, lo=0x14A7
        .byte   0x17,0xE2,0x16,0xF2,0x1A,0xDE   | zone 3: hi=0x17E2, lo=0x16F2; zone 4 hi=0x1ADE
        .byte   0x19,0xD0                       | zone 4 lo=0x19D0

| -------------------------------------------------------------------------
| MakeSpdTbl -- build the speed table of the current drive
|   D0 (out) -- error code (BMI)
| A new-interface (800K) drive regulates its own speed: just wait 800 ms
| so the disk is seated. For an old (400K) drive, measure the speed at
| PWM values $80 and $100 and interpolate the speed code (and the 2%
| delta) for each zone. Uses A3/A4 for return addresses.
| -------------------------------------------------------------------------
E_Sony_MakeSpdTbl:
        MOVE.L  (DiskVars_JMakeSpdTbl).w,-(SP)  | push MakeSpdTbl vector address
        RTS                                     | dispatch to Sony_MakeSpdTbl
| jtMakeSpdTbl (JMakeSpdTbl vector)
Sony_MakeSpdTbl:
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BPL.B   SONY_MAKESPDTBL_CONT            | no -> calibrate
        MOVE    #0x1F40,D0                      | 800 ms
        BRA.W   E_Sony_WakeUp                   | WakeUp: just wait

| SONY_MAKESPDTBL_CONT -- 400K drive: measure the speed value f at speed
| codes $80 and $100 ("Drive must spin at speed codes 128 and 256",
| Apple) and interpolate linearly: the code for speed value t is
| 128 * (t + f256 - 2 * f128) / (f256 - f128).
SONY_MAKESPDTBL_CONT:
        MOVE.L  (SP)+,A4                        | A4 = return address
        MOVE    #0x80,D2                        | speed code $80
        BSR.B   SONY_GETFREQ                    | measure speed -> D4
        BMI.B   SONY_MAKESPDTBL_ERR             | measurement failed -> abort
        MOVE.L  D4,D3                           | D3 = f128: speed value at code $80
        MOVE    #0x100,D2                       | speed code $100
        BSR.B   SONY_GETFREQ                    | measure speed -> D4
        BMI.B   SONY_MAKESPDTBL_ERR             | measurement failed -> abort
        MOVE.L  D4,D5                           | D5 = D4 = f256: speed value at code $100
        SUB.L   D3,D5                           | D5 = f256 - f128: change per 128 code steps
        BGT.B   SONY_MAKESPDTBL_CONT_2          | positive -> valid slope
        MOVEQ.L #0x1,D5                         | clamp minimum to avoid div-by-zero
SONY_MAKESPDTBL_CONT_2:
        LSL.L   #0x1,D3                         | D3 = 2 * f128
        MOVEQ.L #0x4,D6                         | D6 = 4 (5 speed zones, 0-based)
        LEA.L   DT_Sony_SpeedCheckTbl(PC),A5    | A5 -> SpeedCheckTbl (speed value limits)
        BSR.W   Sony_GetDrv1                    | reload drive offset
        LEA.L   TrkSpeedTbl(A1,D1.W),A3         | A3 -> per-drive speed table
| SONY_MAKESPDTBL_LOOP -- per zone: TSTblCode for the midpoint, TSTblDelta
| = code(upper limit) - code(midpoint), TSTblTicks = 0
SONY_MAKESPDTBL_LOOP:
        MOVEQ.L #0x0,D2                         | clear for word load
        MOVE    (A5)+,D2                        | D2 = upper limit of the zone
        MOVE.L  D2,D7                           | D7 = save upper limit
        ADD     (A5)+,D2                        | + lower limit
        LSR     #0x1,D2                         | D2 = t: the midpoint (target speed value)
SONY_MAKESPDTBL_CONT_3:
        ADD.L   D4,D2                           | t + f256
        SUB.L   D3,D2                           | t + f256 - 2 * f128
        LSL.L   #0x7,D2                         | * 128
        BGT.B   SONY_MAKESPDTBL_CONT_4          | positive -> valid
        MOVEQ.L #0x1,D2                         | clamp to minimum 1
SONY_MAKESPDTBL_CONT_4:
        DIVU    D5,D2                           | / (f256 - f128) = speed code for t
        ADDQ.W  #0x1,D2                         | round up
        CMPI    #0x18F,D2                       | above $18F?
        BLE.B   SONY_MAKESPDTBL_OK              | no -> use as-is
        MOVE    #0x18F,D2                       | clamp to max
SONY_MAKESPDTBL_OK:
        MOVE    D2,(A3)+                        | pass 1: TSTblCode; pass 2: code(upper), replaced below
        EXG     D7,D2                           | D2 = upper limit for pass 2, D7 = this code
        NOT     D0                              | toggle the pass flag (D0 = 0 from GetFreq)
        BNE.B   SONY_MAKESPDTBL_CONT_3          | do second limit
        SUBQ.W  #0x4,A3                         | A3 -> TSTblCode
        SUB     (A3)+,D7                        | D7 = code(upper) - code(midpoint): the 2% delta
        MOVE    D7,(A3)+                        | TSTblDelta
        CLR.L   (A3)+                           | TSTblTicks = 0: check the zone at its first use
        DBF     D6,SONY_MAKESPDTBL_LOOP         | next zone
SONY_MAKESPDTBL_ERR:
        TST     D0                              | set condition codes for caller
        JMP     (A4)                            | return

| -------------------------------------------------------
| SONY_GETFREQ -- set speed code D2, wait PwrOnTime for the motor, then
| GetFreq1: four FigTrkSpd measurements; returns in D4 the speed value
| $4000000 / (sum / 8), proportional to the rotation speed, or a
| negative D0 on error
SONY_GETFREQ:
        MOVE.L  (SP)+,A3                        | A3 = return address
        BSR.W   SONY_SETSPEED_CONT_3            | program speed code D2
        MOVE    PwrOnTime(A1),D0                | D0 = spin-up settling delay
        BSR.W   E_Sony_WakeUp                   | wait for motor to reach speed
| SONY_GETFREQ1 -- average 4 TACH period measurements
SONY_GETFREQ1:
        MOVEQ.L #0x0,D4                         | D4 = accumulated TACH time
        MOVEQ.L #0x3,D5                         | D5 = 3 (4 measurements, 0-based)
SONY_GETFREQ1_LOOP:
        BSR.B   E_Sony_FigTrkSpd                | VIA timer counts for 15 tach pulses (1/4 revolution)
        BMI.B   SONY_GETFREQ1_EXIT              | error -> abort
        ADD.L   D0,D4                           | accumulate TACH time
        DBF     D5,SONY_GETFREQ1_LOOP           | repeat 4 times
        LSR.L   #0x3,D4                         | D4 = average (sum/8, not sum/4)
        MOVE.L  #0x4000000,D0                   | D0 = constant for speed conversion
        DIVU    D4,D0                           | D0 = speed = $4000000 / avg_time
        MOVE    D0,D4                           | D4 = speed value
        MOVEQ.L #0x0,D0                         | D0 = noErr
SONY_GETFREQ1_EXIT:
        JMP     (A3)                            | return to caller

| E_Sony_FigTrkSpd -- measure the time of 15 tach pulses (through the
| JFigTrkSpd vector)
E_Sony_FigTrkSpd:
        MOVE.L  (DiskVars_JFigTrkSpd).w,-(SP)   | push FigTrkSpd vector address
        RTS                                     | dispatch to Sony_FigTrkSpd

| Sony_FigTrkSpd -- measure the time of 15 tach pulses, a quarter
| revolution (the drive's TACH line gives 60 pulses per revolution --
| Apple's SonyUtil.a), with VIA timer 2 counting down from $FFFF at
| 783.36 kHz; TACH is the sense line, read in IWM status bit 7.
| Returns the count in D0 (positive), or noDriveErr (-64) when T2 runs
| out first ($FFFF counts, about 84 ms; Apple: "Speeds as low as 192
| RPM may be measured").
Sony_FigTrkSpd:
        MOVE    SR,-(SP)                        | save SR
        MOVEM.L D1-D7/A0-A6,-(SP)               | save all registers
        MOVEQ.L #0x4,D0                         | PollStack = SP + 4 (one return address)
        BSR.W   E_Sony_SetUpPoll                | SetUpPoll: A5 = VIA port A, A6 = SCC data, PollStack
        MOVEQ.L #TachAdr,D0                     | TachAdr: tachometer sense
        BSR.W   Sony_AdrDisk                    | address TACH via phase lines
        LEA.L   (IWM_Base).l,A0                 | A0 = IWM base, absolute (DBase = $DFE1FF)
        TST.B   q6H(A0)                         | Q6H: L6 = 1, the status register is read at Q7L
        MOVEQ.L #-0x1,D1                        | D1 = $FFFF: T2 max count
        MOVEQ.L #0x5,D3                         | D3 = 5: VIA IFR bit for T2 timeout
        MOVE.L  (VIA).w,A2                      | A2 = VIA base
        LEA.L   vIFR(A2),A3                     | A3 = VIA IFR register
        LEA.L   q7L(A0),A1                      | A1 = IWM Q7L address (status read)
        BSR.B   SONY_STARTT2                    | start VIA T2 free-run timer
        BSR.B   SONY_WAITTACH                   | sync: wait for first TACH edge
        BEQ.B   SONY_FIGTRKSPD_CONT_2           | synchronized -> begin measurement
SONY_FIGTRKSPD_EXIT:
        TST.B   q6L(A0)                         | Q6L: L6 = 0, back to read mode
        BSR.W   Sony_EmptyPD                    | call PollProc
| re-arm VIA timer 2 to expire at once (A302 in Apple's history): a Time
| Manager request that came due while interrupts were off here would
| otherwise be lost
        MOVEQ.L #0x1,D1                         | T2 count 1:
        MOVEA.L (VIA).w,A2                      | A2 = VIA base
        BSR.B   SONY_STARTT2                    | StartT2: T2 expires at once
        MOVEM.L (SP)+,D1-D7/A0-A6               | restore all registers
        MOVE    (SP)+,SR                        | restore SR
        TST.L   D0                              | set condition codes on result
        RTS                                     | return from SONY_FIGTRKSPD_EXIT
| StartT2 -- load VIA timer 2 with D1 (low byte first; writing the high
| byte starts the timer); D1 is preserved
SONY_STARTT2:
        MOVE.B  D1,vT2C(A2)                     | T2 low byte
        ROR.W   #0x8,D1                         | high byte of D1
        MOVE.B  D1,vT2CH(A2)                    | T2 high byte: start counting
        ROR.W   #0x8,D1                         | restore D1
        RTS                                     | return

| SONY_FIGTRKSPD_CONT_2 -- TACH synchronized: restart T2 and count 15 edges
SONY_FIGTRKSPD_CONT_2:
        BSR.B   SONY_STARTT2                    | restart T2 at $FFFF
        MOVEQ.L #0xE,D2                         | D2 = 14 (15 edges, 0-based)
SONY_FIGTRKSPD_LOOP:
        BSR.B   SONY_WAITTACH                   | wait for next TACH edge
        BNE.B   SONY_FIGTRKSPD_EXIT             | timeout -> error exit
        DBF     D2,SONY_FIGTRKSPD_LOOP          | count 15 TACH edges
| read T2 counter value (elapsed = $FFFF - T2)
        MOVE.B  vT2CH(A2),D2                    | read T2C-H (high byte)
        MOVE.B  vT2C(A2),D1                     | read T2C-L (low byte)
        CMP.B   vT2CH(A2),D2                    | T2C-H changed during read?
        BEQ.B   SONY_FIGTRKSPD_OK               | no -> reading is consistent
        MOVEQ.L #0x0,D1                         | yes -> clear low byte (ambiguous)
SONY_FIGTRKSPD_OK:
        BTst    D3,(A3)                         | IFR bit 5: T2 timed out?
        BNE.B   SONY_FIGTRKSPD_EXIT             | yes -> measurement invalid
        LSL     #0x8,D2                         | D2 = high byte << 8
        OR.B    D1,D2                           | D2 = 16-bit T2 remaining
        NOT     D2                              | D2 = $FFFF - remaining = elapsed
        MOVEQ.L #0x0,D0                         | clear high word
        MOVE    D2,D0                           | D0 = elapsed time for 15 TACH edges
        BRA.B   SONY_FIGTRKSPD_EXIT             | return with D0 = time

| -------------------------------------------------------
| SONY_WAITTACH -- WaitTACH: detect a TACH rising edge (0->1 transition)
| Looks for two consecutive 0s then two consecutive 1s on TACH.
| Services SCC data during wait. Returns Z=1 if edge found,
| Z=0 (D0=-64) if T2 timeout or drive disconnected.
SONY_WAITTACH:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
| scan for TACH=0 (low phase)
SONY_WAITTACH_LOW:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WAITTACH_LOW_2             | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WAITTACH_LOW_2:
        TST.B   (A1)                            | read IWM status (TACH in bit 7)
        BMI.B   SONY_WAITTACH_LOW_3             | TACH=1 -> not low yet
        TST.B   (A1)                            | confirm second consecutive 0
        BPL.B   SONY_WAITTACH_HIGH              | two 0s found -> scan for 1s
SONY_WAITTACH_LOW_3:
        BTst    D3,(A3)                         | VIA IFR bit 5: T2 timed out?
        BEQ.B   SONY_WAITTACH_LOW               | no -> keep scanning
SONY_WAITTACH_TIMEOUT:
        MOVEQ.L #-0x40,D0                       | noDriveErr (-64): timeout or no drive
        BRA.B   SONY_DSKRTN                     | return through DskRtn

| SONY_WAITTACH_HIGH -- TACH went low: now scan for rising edge (two 1s)
SONY_WAITTACH_HIGH:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WAITTACH_HIGH_2            | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WAITTACH_HIGH_2:
        BTst    D3,(A3)                         | T2 timed out?
        BNE.B   SONY_WAITTACH_TIMEOUT           | yes -> error
        TST.B   (A1)                            | read TACH
        BPL.B   SONY_WAITTACH_HIGH              | still 0 -> keep waiting
        TST.B   (A1)                            | confirm second consecutive 1
        BPL.B   SONY_WAITTACH_HIGH              | false alarm -> keep waiting
        MOVEQ.L #0x0,D0                         | noErr: rising edge seen
        NOP                                     | (no-op)
| DskRtn -- continue at DskRtnAdr with CCR set from D0 (also used by
| GoWakeIt in WakeUp)
SONY_DSKRTN:
        MOVE.L  (DskRtnAdr).w,-(SP)             | push DskRtnAdr
        TST.W   D0                              | CCR = result
        RTS                                     | continue there

| -------------------------------------------------------------------------
| DiskVBLTask -- VBL task, every DskVBLTime ticks (0.5 s)
| Counts down a pending power-down (TimeOut) and turns the motor off when
| it expires; when no drive is powered, polls every drive for an inserted
| disk or a pressed eject button (Check4Disk). Runs at IPL 3 on the SE so
| AppleTalk cannot interrupt it (Mac Plus: IPL 1). Preserves A4-A6/D4-D7.
| -------------------------------------------------------------------------
Sony_DiskVBLTask:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI.W   #0x300,SR                       | IPL 3: no VBL and AppleTalk interrupts
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE    DskVBLTime(A1),vblCount(A0)     | VBLCount = DskVBLTime: run again in 0.5 s
        TST.B   Active(A1)                      | Active: request in progress?
        BNE.B   SONY_DISKVBLTASK_EXIT           | yes -> leave the drives alone
        TST     TimeOut(A1)                     | TimeOut: power-down pending?
        BEQ.B   SONY_DISKVBLTASK_POLL           | no -> poll the drives
        SUBQ.W  #0x1,TimeOut(A1)                | count it down
        BNE.B   SONY_DISKVBLTASK_EXIT           | not yet -> a drive is still powered: exit
        MOVEQ.L #MtrOffAdr,D0                   | MtrOffAdr: time is up, motor off
        BSR.W   Sony_AdrAndStrb                 | AdrAndStrb
SONY_DISKVBLTASK_POLL:
        MOVEQ.L #0x1,D3                         | start with drive 1
SONY_DISKVBLTASK_LOOP:
        BSR.B   Sony_Check4Disk                 | Check4Disk
        ADDQ.W  #0x1,D3                         | next drive
        CMPI.W  #0x5,D3                         | past drive 5?
        BGT.B   SONY_DISKVBLTASK_DONE           | yes -> done
        TST.B   SE_PassThru(A1)                 | PassThru (+$13E): second HD20 addressable?
        BEQ.B   SONY_DISKVBLTASK_LOOP           | yes -> check every drive
        CMPI.W  #0x4,D3                         | else only drives 1-4
        BLE.B   SONY_DISKVBLTASK_LOOP           | next drive
SONY_DISKVBLTASK_DONE:
        TST.B   mtrOff(A0)                      | mtrOff: cut the drive enable (Apple: "new drive fix")
SONY_DISKVBLTASK_EXIT:
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return

| -------------------------------------------------------------------------
| Check4Disk -- check logical drive D3 (GetDrive translates it): post a
| disk-inserted event (message high word 0, low word = drive number) for
| a newly inserted disk, or one with high word -1 (eject request) when
| the eject button of a drive holding a disk is pressed (new on the SE).
| -------------------------------------------------------------------------
Sony_Check4Disk:
        MOVE    D3,Drive(A1)                    | Drive = D3
        BSR.W   Sony_GetDrive                   | GetDrive: A0, A1, A2, D1
        TST.B   Installed(A1,D1.W)              | drive connected?
        BMI.B   SONY_CKEXIT                     | no -> exit
        TST.B   DiskInPlace(A1,D1.W)            | DiskInPlace: disk in place (1 or 2)?
        BGT.B   SONY_CKEJECT                    | yes -> CkEject
        BEQ.B   SONY_CKDIP                      | none -> CkDIP
        ADDQ.B  #0x1,DiskInPlace(A1,D1.W)       | just ejected ($FC-$FF): count up towards 0
        BMI.B   SONY_CKINVAL                    | still waiting -> CkInval
        BRA.B   SONY_CKDIP                      | waiting over -> CkDIP
SONY_CKEJECT:
        CMPI.W  #0x4,Drive(A1)                  | CkEject: HD20 (drive 4-5)?
        BGE.B   SONY_CKEXIT                     | yes -> no eject button
SONY_CKEJECT_SELECT:
        BSR.W   Sony_DiskSel1                   | DiskSel1: select the drive
        BSR.B   SONY_CKEJSW                     | CkEjSw: eject button pressed?
        BPL.B   SONY_CKEXIT                     | no -> exit
        MOVEQ.L #0x0,D0                         | D0 = 0
        SUBQ.L  #0x1,D0                         | D0 = -1: high word -1 = eject request
        MOVE.W  Drive(A1),D0                    | low word = drive number
        MOVEA.W #diskInsertEvt,A0               | A0 = diskInsertEvt (7)
        _PostEvent                              | post the event
        BRA.B   SONY_CKEXIT                     | any error is ignored
SONY_CKDIP:
        BSR.W   Sony_DiskSel1                   | CkDIP: DiskSel1
        CMPI.W  #0x4,Drive(A1)                  | floppy drive (1-3)?
        BLT.B   SONY_CKDIP_SENSE                | yes -> disk-in-place sense
| HD20: CA0 and CA2 low (CA1 high, SEL low from DiskSel1) is the address
| where DCDWaitHSHK and DCDReset sense the HD20's handshake line HSHK;
| HSHK high = HD20 idle and ready
        TST.B   (A0)                            | HD20: CA0 low (ph0L)
        TST.B   ph2L(A0)                        | CA2 low
        BSR.W   Sony_Sense                      | Sense: HSHK
        BMI.B   SONY_CKDIP_POST                 | HSHK high -> post a disk-inserted event
        BRA.B   SONY_CKEXIT                     | else exit

| SONY_CKDIP_SENSE -- floppy: read CSTIN sense line
SONY_CKDIP_SENSE:
        MOVEQ.L #DIPAdr,D0                      | DIPAdr: disk-in-place sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when a disk is in place
        BMI.B   SONY_CKEXIT                     | no disk -> exit
SONY_CKDIP_POST:
        BSR.B   SONY_CKEJSW                     | CkEjSw: read and reset (ignore) the eject button
        MOVEQ.L #0x0,D0                         | high word 0 = disk inserted
        MOVE.W  Drive(A1),D0                    | low word = drive number
SONY_CKDIP_EVENT:
        MOVE    #diskInsertEvt,A0               | A0 = diskInsertEvt (7)
        _PostEvent                              | post the event
        BNE.B   SONY_CKINVAL                    | not posted (probably boot time) -> CkInval
        ADDQ.B  #0x1,DiskInPlace(A1,D1.W)       | DiskInPlace = 1: disk in place, not clamped
SONY_CKINVAL:
        ST.B    Track(A1,D1.W)                  | CkInval: Track = $FFxx: current track invalid
        MOVE.L  (IWM).w,A0                      | A0 = IWM base again
| Called by: SONY_CKEJECT_SELECT, Sony_Check4Disk, SONY_CKEJECT, SONY_CKDIP, SONY_CKDIP_SENSE
SONY_CKEXIT:
        RTS                                     | return
| CkEjSw -- read and reset the latched eject button of the selected drive
| (new on the SE); BMI if it was pressed
SONY_CKEJSW:
        MOVEQ.L #EjectLAdr,D0                   | EjectLAdr (12): eject button latch
        BSR.W   Sony_AdrAndSense                | sense = 1 when the button was pressed
        BPL.B   SONY_CKEJSW_EXIT                | not pressed -> return (BPL)
        MOVEQ.L #RdDta1Adr,D0                   | RdDta1Adr (3): reset the latch
        BSR.W   Sony_AdrAndStrb                 | by strobing that address
        MOVEQ.L #0x0,D0                         | D0.W = -1
        SUBQ.W  #0x1,D0                         | (BMI)
SONY_CKEJSW_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| DrvTbl -- icon and drive information for physical drives 1-5 (new on
| the SE, from SonyIcon.a): offset of the media icon, offset of the drive
| icon (both relative to DRVTBL) and the drive info word returned by
| csCode 23 (Inside Macintosh V-470, MTN #272): bits 0-3 = drive type
| (2 = 400K, 3 = 800K drive, 7 = Hard Disk 20), bit 8 = external, bit 9
| = SCSI (clear: IWM), bit 10 = fixed, bit 11 = secondary drive.
| -------------------------------------------------------------------------
DRVTBL:
        .short  ICON_DISKETTE-DRVTBL            | drive 1: media icon (csCode 22)
        .short  ICON_LOWERDRIVE-DRVTBL          | drive 1: drive icon (csCode 21)
        .short  0x0003                          | drive 1 info: 800K drive, primary internal removable
        .short  ICON_DISKETTE-DRVTBL            | drive 2: media icon (csCode 22)
        .short  ICON_UPPERDRIVE-DRVTBL          | drive 2: drive icon (csCode 21)
        .short  0x0803                          | drive 2 info: 800K drive, secondary internal removable
        .short  ICON_DISKETTE-DRVTBL            | drive 3: media icon (csCode 22)
        .short  ICON_EXTDRIVE-DRVTBL            | drive 3: drive icon (csCode 21)
        .short  0x0103                          | drive 3 info: 800K drive, primary external removable
        .short  ICON_DISKETTE-DRVTBL            | drive 4: media icon (csCode 22)
        .short  ICON_DISKETTE-DRVTBL            | drive 4: drive icon (csCode 21)
        .short  0x0507                          | drive 4 info: Hard Disk 20, primary external fixed
        .short  ICON_DISKETTE-DRVTBL            | drive 5: media icon (csCode 22)
        .short  ICON_DISKETTE-DRVTBL            | drive 5: drive icon (csCode 21)
        .short  0x0D07                          | drive 5 info: Hard Disk 20, secondary external fixed

| -------------------------------------------------------------------------
| ctlLogIcon (csCode 22), ctlPhysIcon (csCode 21), ctlDrvInfo (csCode 23)
| for floppy drives
|   A0 (in)  -- control parameter block
|   CSParam (out) -- pointer to the icon (icon, mask and an empty Pascal
|                    string), or the drive info word
| Inside Macintosh V-470 calls csCode 21 the media icon and csCode 22 the
| drive icon; this code returns the drive icon for csCode 21 and the
| diskette icon for csCode 22, as MTN #272 describes them ("Return
| Physical Drive Icon (csCode=21)", "Return Media Icon (csCode=22)") and
| as Apple's SonyIcon.a does (ctlPhysIcon, ctlLogIcon). HD20 drives get
| their icon from the HD20 itself (SONY_DCD_ICON) and the drive info
| from here.
| -------------------------------------------------------------------------
SONY_CTL_MEDIAICON:
        BSR.B   SONY_GETDRVTBL                  | getDrvTbl: A3 -> DrvTbl entry of this drive
        BNE.B   SONY_CTL_ICONRET                | bad or missing drive -> return the error
        MOVE.W  (A3),D0                         | D0 = offset of the media icon
        LEA.L   DRVTBL(PC),A3                   | A3 -> DRVTBL
        ADD.L   A3,D0                           | D0 = address of the icon
        BRA.B   SONY_CTL_PARAM                  | return it
SONY_CTL_DRIVEICON:
        BSR.B   SONY_GETDRVTBL                  | getDrvTbl
        BNE.B   SONY_CTL_ICONRET                | bad or missing drive -> return the error
        MOVE.W  0x2(A3),D0                      | D0 = offset of the drive icon
        LEA.L   DRVTBL(PC),A3                   | A3 -> DRVTBL
        ADD.L   A3,D0                           | D0 = address of the icon
        BRA.B   SONY_CTL_PARAM                  | return it
SONY_CTL_DRVINFO:
        BSR.B   SONY_GETDRVTBL                  | getDrvTbl
        BNE.B   SONY_CTL_ICONRET                | bad or missing drive -> return the error
        MOVE.W  0x4(A3),D0                      | D0.L = drive info word (high word 0)
        CMPI.W  #0x4,Drive(A1)                  | HD20?
        BGE.B   SONY_CTL_PARAM                  | yes -> return the table value
        TST.B   NewIntf(A1,D1.W)                | new-interface (800K) drive?
        BMI.B   SONY_CTL_PARAM                  | yes -> drive type 3 (800K) from the table
        MOVE.B  #0x2,D0                         | old interface: drive type 2 (400K)
        NOP                                     | (no-op)
SONY_CTL_PARAM:
        MOVE.L  D0,csParam(A0)                  | CSParam = icon pointer or drive info
        MOVEQ.L #0x0,D0                         | noErr
SONY_CTL_ICONRET:
        BRA.W   Sony_DiskDone                   | complete the request
| getDrvTbl -- A3 -> DrvTbl entry for the physical drive behind the
| current logical drive; D0 = 0 (BEQ), or statusErr (-18, BNE) for a
| drive number outside 1..5 or a drive that is not connected
SONY_GETDRVTBL:
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1
        MOVE.W  Drive(A1),D0                    | D0 = logical drive number
        BEQ.W   SONY_GETDRVTBL_ERR              | 0 -> error
        CMPI.W  #0x5,D0                         | above 5?
        BGT.B   SONY_GETDRVTBL_ERR              | yes -> error
        TST.B   Installed(A1,D1.W)              | drive connected?
        BMI.B   SONY_GETDRVTBL_ERR              | no -> error
        LSL.W   #0x1,D0                         | * 2
        LEA.L   SE_DriveXlat(A1),A3             | A3 -> drive number translation table
        MOVE.W  0x0(A3,D0.W),D0                 | D0 = physical drive number
        SUBQ.W  #0x1,D0                         | - 1
        LSL.W   #0x1,D0                         | * 2
        MOVEA.W D0,A3                           | (save * 2)
        LSL.W   #0x1,D0                         | * 4
        ADD.W   A3,D0                           | * 6 = offset of the DrvTbl entry
        LEA.L   DRVTBL(PC),A3                   | A3 -> DRVTBL
        ADDA.W  D0,A3                           | A3 -> entry of this drive
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return (BEQ)
SONY_GETDRVTBL_ERR:
        MOVEQ.L #-0x12,D0                       | statusErr (-18)
        RTS                                     | return (BNE)

| -------------------------------------------------------------------------
| Icons -- 32x32 icon and mask, followed by an empty Pascal string (the
| "Where:" string of the Finder's Get Info window) and a pad byte:
| the 3.5-inch diskette (media icon of every drive), the external drive
| (a compact Macintosh with an arrow to an external drive), and the
| Macintosh SE with an arrow to its lower or upper internal drive.
| -------------------------------------------------------------------------
ICON_DISKETTE:
| 3.5-inch diskette (media icon of all drives): icon
        .long   0x7FFFFFF8                      | .############################...
        .long   0x81000104                      | #......#...............#.....#..
        .long   0x81007102                      | #......#.........###...#......#.
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81008901                      | #......#........#...#..#.......#
        .long   0x81007101                      | #......#.........###...#.......#
        .long   0x81000101                      | #......#...............#.......#
        .long   0x80FFFE01                      | #.......###############........#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x80000001                      | #..............................#
        .long   0x87FFFFE1                      | #....######################....#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x88000011                      | #...#......................#...#
        .long   0x7FFFFFFE                      | .##############################.
| 3.5-inch diskette (media icon of all drives): mask
        .long   0x7FFFFFF8                      | .############################...
        .long   0xFFFFFFFC                      | ##############################..
        .long   0xFFFFFFFE                      | ###############################.
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0xFFFFFFFF                      | ################################
        .long   0x7FFFFFFE                      | .##############################.
        .byte   0,0                             | empty Pascal string ("Where:"), pad byte

| external drive (drive 3): icon
ICON_EXTDRIVE:
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x7FFF8000                      | .################...............
        .long   0x80004000                      | #................#..............
        .long   0x9FFE4000                      | #..############..#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014000                      | #.#............#.#..............
        .long   0xA0014040                      | #.#............#.#.......#......
        .long   0xA0014040                      | #.#............#.#.......#......
        .long   0xA0014040                      | #.#............#.#.......#......
        .long   0x9FFE4040                      | #..############..#.......#......
        .long   0x800041F0                      | #................#.....#####....
        .long   0x800040E0                      | #................#......###.....
        .long   0x80004040                      | #................#.......#......
        .long   0x80FE4000                      | #.......#######..#..............
        .long   0x80005FFF                      | #................#.#############
        .long   0x80005001                      | #................#.#...........#
        .long   0x80005001                      | #................#.#...........#
        .long   0x800053F9                      | #................#.#..#######..#
        .long   0x7FFF9001                      | .################..#...........#
        .long   0x40009001                      | .#..............#..#...........#
        .long   0x7FFF9FFF                      | .################..#############
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
| external drive (drive 3): mask
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x7FFF8000                      | .################...............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFC000                      | ##################..............
        .long   0xFFFFDFFF                      | ##################.#############
        .long   0xFFFFDFFF                      | ##################.#############
        .long   0xFFFFDFFF                      | ##################.#############
        .long   0xFFFFDFFF                      | ##################.#############
        .long   0x7FFF9FFF                      | .################..#############
        .long   0x7FFF9FFF                      | .################..#############
        .long   0x7FFF9FFF                      | .################..#############
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .long   0x00000000                      | ................................
        .byte   0,0                             | empty Pascal string ("Where:"), pad byte

| lower internal drive of the Macintosh SE (drive 1): icon
ICON_LOWERDRIVE:
        .long   0x00000000                      | ................................
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x08000010                      | ....#......................#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08FFFF10                      | ....#...################...#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09555090                      | ....#..#.#.#.#.#.#.#....#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09550090                      | ....#..#.#.#.#.#........#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09500090                      | ....#..#.#.#............#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09500090                      | ....#..#.#.#............#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09540090                      | ....#..#.#.#.#..........#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x08FFFF10                      | ....#...################...#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08000010                      | ....#......................#....
        .long   0x0800FF10                      | ....#...........########...#....
        .long   0x08100010                      | ....#......#...............#....
        .long   0x08180010                      | ....#......##..............#....
        .long   0x08FCFF10                      | ....#...######..########...#....
        .long   0x08180010                      | ....#......##..............#....
        .long   0x08100010                      | ....#......#...............#....
        .long   0x08000010                      | ....#......................#....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x03FFFFC0                      | ......####################......
| lower internal drive of the Macintosh SE (drive 1): mask
        .long   0x00000000                      | ................................
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x03FFFFC0                      | ......####################......
        .byte   0,0                             | empty Pascal string ("Where:"), pad byte

| upper internal drive of the Macintosh SE (drive 2): icon
ICON_UPPERDRIVE:
        .long   0x00000000                      | ................................
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x08000010                      | ....#......................#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08FFFF10                      | ....#...################...#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09555090                      | ....#..#.#.#.#.#.#.#....#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09550090                      | ....#..#.#.#.#.#........#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09500090                      | ....#..#.#.#............#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09500090                      | ....#..#.#.#............#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09540090                      | ....#..#.#.#.#..........#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x09000090                      | ....#..#................#..#....
        .long   0x08FFFF10                      | ....#...################...#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08100010                      | ....#......#...............#....
        .long   0x08180010                      | ....#......##..............#....
        .long   0x08FCFF10                      | ....#...######..########...#....
        .long   0x08180010                      | ....#......##..............#....
        .long   0x08100010                      | ....#......#...............#....
        .long   0x0800FF10                      | ....#...........########...#....
        .long   0x08000010                      | ....#......................#....
        .long   0x08000010                      | ....#......................#....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x04000020                      | .....#....................#.....
        .long   0x03FFFFC0                      | ......####################......
| upper internal drive of the Macintosh SE (drive 2): mask
        .long   0x00000000                      | ................................
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x0FFFFFF0                      | ....########################....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x07FFFFE0                      | .....######################.....
        .long   0x03FFFFC0                      | ......####################......
        .byte   0,0                             | empty Pascal string ("Where:"), pad byte

| AdrMks (Apple's name) -- marks of a GCR address field: address mark
| $D5 $AA $96, bit slip marks $DE $AA (RdAddr compares these five; the $FF
| is not used). $D5 and $AA are reserved as mark bytes, no data nibble
| has these values (SWIM Chip User's Ref, "GCR Encoding").
DT_Sony_SectorAdrTbl:
        .byte   0xD5,0xAA,0x96,0xDE,0xAA,0xFF   | address mark $D5 $AA $96, slip marks $DE $AA, $FF

| E_Sony_SetUpPoll -- set up SCC/VIA for polling.
E_Sony_SetUpPoll:
        MOVE.L  (DiskVars_JSetUpPoll).w,-(SP)   | push SetUpPoll vector address
        RTS                                     | dispatch to Sony_SetUpPoll

| -------------------------------------------------------
| Sony_SetUpPoll -- prepare the polling of the SCC modem port during disk
| I/O with interrupts off: A6 = SCC channel A data, A5 = VIA port A
| (vBufD: bit 7 = SCC W/REQ, low when a byte is waiting; bit 5 = head
| select). Received bytes are pushed on the stack and later handed to
| PollProc by EmptyPD.
|   D0 (in) -- bytes of return addresses on the stack (4 or 8): PollStack
|              = SP + D0, the caller's stack level once they are popped
|              (Apple: "compensate for 1 or 2 levels"); EmptyPD resets SP
|              to it when there is no PollProc
Sony_SetUpPoll:
        LEA.L   (SCC_RdDataA).l,A6              | A6 = SCC channel A data read
        LEA.L   (VIA_PortA2).l,A5               | A5 = VIA port A (vBufD: SCC W/REQ in bit 7)
        ORI     #0x300,SR                       | no interrupts from now on
        MOVE.L  SP,(PollStack).w                | PollStack = SP
        ADD.L   D0,(PollStack).w                | + D0 (the return addresses)
        RTS                                     | return from Sony_SetUpPoll

| -------------------------------------------------------
| Sony_RdAddrSetup -- set up the polling, select the head of side
| SideTrack and read the next address mark (RdAddr)
|   D0, D1, D2, D3 (out) -- as RdAddr (D1 = side/track, D2 = sector,
|                           D3 = format byte)
Sony_RdAddrSetup:
        MOVEQ.L #0x8,D0                         | PollStack = SP + 8 (two return addresses)
        BSR.B   E_Sony_SetUpPoll                | set up A5/A6 and PollStack
        MOVEQ.L #RdDtaAdr,D0                    | RdDtaAdr: read data of the side 0 head
        BTST    #0x3,SideTrack(A1)              | side 1 (bit 11 of SideTrack)?
        BEQ.B   SONY_RDADDRSETUP_SIDE           | no -> side 0
        MOVEQ.L #RdDta1Adr,D0                   | RdDta1Adr: read data of the side 1 head
SONY_RDADDRSETUP_SIDE:
        BSR.W   Sony_AdrDisk                    | address it: that head's data on the RD line
| E_Sony_RdAddr -- read sector address field.
E_Sony_RdAddr:
        LEA.L   DT_Sony_SectorAdrTbl(PC),A2     | A2 -> AdrMks: address mark table
        MOVE.L  (DiskVars_JRdAddr).w,-(SP)      | push the JRdAddr vector
        RTS                                     | and jump through it

| -------------------------------------------------------------------------
| jtRdAddr (JRdAddr vector) -- read the next address mark
|   A2 (in) -- address mark table, A5/A6 (in) -- VIA / SCC pointers
|   D0 (out) -- >= 0: nibbles left of the must-find count; or noNybErr
|               (-66), noAdrMkErr (-67), badCkSmErr (-69), badBtSlpErr
|               (-70)
|   D1 (out) -- side (bit 11) and track (bits 0-10), D2 -- sector,
|               D3 -- format byte (Apple's source: "volume")
|   A3 (out) -- denibblize table - $96, A4 (out) -- IWM q6L
| The disk must be up to speed with the head selected, interrupts off.
| Address field (SWIM Chip User's Ref, "GCR Track Format"): marks $D5
| $AA $96, then as nibbles the track (bits 0-5), the sector, the side
| (bit 5) with track bits 6-10, the format byte and the checksum (XOR of
| the four), then the bit slip marks $DE $AA. A byte read from q6L is
| valid when bit 7 is set (asynchronous latch mode). noNybErr: MTN #272
| says "could not find five nibbles in 200 tries"; this code wants 3
| nibbles within 128 reads.
| -------------------------------------------------------------------------
Sony_RdAddr:
        MOVEQ.L #0x3,D3                         | D3 = 3: find 3 nibbles first (Apple: "try for 3 bytes")
        MOVEQ.L #0x7F,D2                        | D2: within at most 128 reads of the data register
        MOVEQ.L #0x0,D5                         | D5 = 0: nibbles are used as a word index
        MOVEA.L (IWM).w,A4                      | A4 = IWM base (low-memory IWM)
        ADDA.W  #q6L,A4                         | A4 -> q6L: data register (L6 = L7 = 0, motor on)
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
| first find 3 nibbles (there is data on the track at all)
SONY_RDADDR_SKIP:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_CONT                | no SCC byte waiting ->
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_CONT:
        MOVE.B  (A4),D5                         | read byte from IWM data register
        DBF     D2,SONY_RDADDR_LOOP             | decrement timeout
        MOVEQ.L #-0x42,D0                       | noNybErr (-66): fewer than 3 nibbles in 128 reads
        BRA.W   SONY_RDADDRXIT                  | -> error exit
SONY_RDADDR_LOOP:
        BPL.B   SONY_RDADDR_SKIP                | bit 7 clear: not a valid disk byte
        SUBQ.W  #0x1,D3                         | one more nibble
        BNE.B   SONY_RDADDR_SKIP                | until 3 were seen (not necessarily in a row)
        MOVE    #MustFindCt,D0                  | MustFindCt: find the mark within 1500 nibbles
        TST.B   NewIntf(A1,D1.W)                | NewIntf: 800K interface?
        BEQ.B   SONY_RDADDR_CONT_2              | 400K -> use $5DC timeout
        MOVE    #MustFindCt-32,D0               | new-interface drive: MustFindCt - 32
SONY_RDADDR_CONT_2:
        LEA.L   SONY_DENIBLTBL-0x96(PC),A3      | A3 -> denibblize table - $96 (indexed by disk byte)
SONY_RDADDR_CONT_3:
        MOVE.L  A2,A0                           | A0 -> address mark pattern $D5 $AA $96
        MOVEQ.L #0x3,D1                         | D1 = 3 header bytes to match
SONY_RDADDR_NEXT:
        MOVE.B  (A4),D5                         | read byte from IWM data register
        BPL.B   SONY_RDADDR_NEXT                | bit 7 clear: not valid, keep polling
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_2              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_2:
        DBF     D0,SONY_RDADDR_LOOP_2           | decrement scan timeout
        MOVEQ.L #-0x43,D0                       | noAdrMkErr (-67): no address mark within MustFindCt nibbles
        BRA.B   SONY_RDADDRXIT                  | return error
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
        ROR     #0x6,D1                         | park them in bits 10-15 (room for the side byte)
SONY_RDADDR_CONT_5:
        MOVE.B  (A4),D5                         | read 2nd addr field byte
        BPL.B   SONY_RDADDR_CONT_5              | poll until valid
        MOVE.B  0x0(A3,D5.W),D2                 | GCR decode: sector number
        EOR.B   D2,D4                           | accumulate into checksum
SONY_RDADDR_CONT_6:
        MOVE.B  (A4),D5                         | read 3rd addr field byte
        BPL.B   SONY_RDADDR_CONT_6              | poll until valid
        MOVE.B  0x0(A3,D5.W),D1                 | GCR decode: side (bit 5) and track bits 6-10
        EOR.B   D1,D4                           | accumulate into checksum
        ROL     #0x6,D1                         | D1 bits 0-11: side (bit 11) and track
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_3              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_3:
        MOVE.B  (A4),D5                         | read 4th addr field byte
        BPL.B   SONY_RDADDR_SKIP_3              | poll until valid
        MOVE.B  0x0(A3,D5.W),D3                 | GCR decode: format byte ($02/$22: 2:1 interleave, $20 = two-sided)
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
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDADDR_SKIP_4              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDADDR_SKIP_4:
        CMP.B   (A0)+,D5                        | compare trailer against $DE, $AA
        BNE.B   SONY_RDADDR_ERR_3               | mismatch -> bad bit-slip error
        DBF     D4,SONY_RDADDR_LOOP_3           | read next trailer byte
| Called by: SONY_RDADDR_CONT, SONY_RDADDR_SKIP_2, SONY_RDADDR_ERR_2, SONY_RDADDR_ERR_3, SONY_RDDATA_SKIP
SONY_RDADDRXIT:
        BRA.W   SONY_DSKRTN                     | RdAddrXit: return through DskRtn (D0 >= 0: ok)
SONY_RDADDR_ERR_2:
        MOVEQ.L #-0x45,D0                       | badCkSmErr (-69): address field checksum wrong
        BRA.B   SONY_RDADDRXIT                  | abort and return error
SONY_RDADDR_ERR_3:
        MOVEQ.L #-0x46,D0                       | badBtSlpErr (-70): address field slip marks wrong
        BRA.B   SONY_RDADDRXIT                  | abort and return error

| DtaMks (Apple) -- marks of a GCR data field: data mark $D5 $AA $AD, bit
| slip marks $DE $AA (the $FF is not compared)
SONY_DTAMKS:
        .byte   0xD5,0xAA,0xAD,0xDE,0xAA,0xFF   | data mark $D5 $AA $AD, slip marks $DE $AA, $FF
| E_Sony_RdData -- read the data field after the address field just read:
| A1 = data mark table, then through the JRdData vector
E_Sony_RdData:
        LEA.L   SONY_DTAMKS(PC),A1              | A1 -> DtaMks: data mark table
        MOVE.L  (DiskVars_JRdData).w,-(SP)      | push RdData vector
        RTS                                     | jump to RdData implementation

| -------------------------------------------------------------------------
| jtRdData (JRdData vector) -- read the GCR data field of the sector whose
| address field was just read: data mark ($D5 $AA $AD), sector number
| (to TagData+1), then 524 bytes (12 tag bytes to TagData+2.., 512 data
| bytes to (A0)) encoded 6-and-2 with three running checksums, the
| checksum and the bit slip marks. With DskVerify set (read-verify) the
| data are compared with the buffer instead of being stored.
| Data field (SWIM Chip User's Ref, "GCR Track Format"): $D5 $AA $AD,
| sector number, 699 nibbles for the 524 bytes (174 groups of three
| bytes as four nibbles -- one with their top 2 bits each, three with
| their low 6 bits -- and a last group of two), 4 nibbles for the three
| checksum bytes, then the slip marks $DE $AA. Each byte is XORed with a
| running checksum before encoding (the algorithm is listed there).
|   A0 (in) -- data buffer, A1 (in) -- DtaMks, A3/A4 (in) -- from RdAddr
|   D0 (out) -- 0 or noDtaMkErr (-71), badDCkSum (-72), badDBtSlp (-73),
|               dataVerErr (-68)
| -------------------------------------------------------------------------
Sony_RdData:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address
        MOVEQ.L #0x30,D2                        | D2 = 48: find the data mark within 48 nibbles
        MOVEQ.L #0x0,D3                         | D3 = 0: nibbles are used as a word index
        MOVEQ.L #-0x40,D0                       | D0 = $C0: mask for bits 7-6 (MOVEQ #-64)
        MOVE.L  #0x1FE000A,D4                   | counts: lo 10 -> 4 groups = 12 tag bytes, hi $1FE -> 170 groups + 2 = 512 data bytes
        MOVEQ.L #0x0,D5                         | init CkSumA
        MOVEQ.L #0x0,D6                         | init CkSumB
        MOVEQ.L #0x0,D7                         | init CkSumC
SONY_RDDATA_CONT:
        MOVE.L  A1,A2                           | put header/trailer table pointer into A2
        MOVEQ.L #0x3,D1                         | D1 = 3 data mark bytes to match ($D5 $AA $AD)
SONY_RDDATA_LOOP:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_LOOP                | no nibble yet -> read again
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP                | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP:
        DBF     D2,SONY_RDDATA_LOOP_2           | decrement timeout and loop
        MOVEQ.L #-0x47,D0                       | noDtaMkErr (-71): no data mark within 48 nibbles
        BRA.B   SONY_RDADDRXIT                  | abort and return error
SONY_RDDATA_LOOP_2:
        CMP.B   (A2)+,D3                        | compare the disk byte against the expected header
        BNE.B   SONY_RDDATA_CONT                | header mismatch, restart scan
        SUBQ.W  #0x1,D1                         | one more mark byte matched
        BNE.B   SONY_RDDATA_LOOP                | loop if more mark bytes to match
SONY_RDDATA_CONT_2:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_CONT_2              | no nibble yet -> read again
        LEA.L   (TagData_1).w,A1                | A1 -> TagData+1
        MOVE.B  0x0(A3,D3.W),(A1)+              | sector number of the data mark -> TagData+1
SONY_RDDATA_CONT_3:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_2              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_2:
        MOVE.B  (A4),D3                         | read a byte from disk
        BPL.B   SONY_RDDATA_CONT_3              | no nibble yet -> read again
        MOVE.B  0x0(A3,D3.W),D1                 | GCR decode: 6-bit nibble with 2+2+2 extra bits
        ROL.B   #0x2,D1                         | rotate extra bits into position
        MOVE.B  D1,D2                           | D2 = copy for masking low bits
        AND.B   D0,D2                           | D2 = bits 7-6 of byte A
SONY_RDDATA_CONT_4:
        MOVE.B  (A4),D3                         | read next GCR byte from disk
        BPL.B   SONY_RDDATA_CONT_4              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine decoded low 6 bits with high 2
        MOVE.B  D7,D3                           | D3 = previous checksum byte C
        ADD.B   D7,D3                           | X = bit 7 of checksum C
        ROL.B   #0x1,D7                         | rotate checksum C left (not through X)
        EOR.B   D7,D2                           | decrypt: XOR with running checksum
        MOVE.B  D2,(A1)+                        | store decoded tag/data byte A
        ADDX.B  D2,D5                           | accumulate checksum A into D5
        ROL.B   #0x2,D1                         | rotate next 2 extra bits into position
        MOVE.B  D1,D2                           | D2 = copy for masking
        AND.B   D0,D2                           | D2 = bits 7-6 of byte B
SONY_RDDATA_CONT_5:
        MOVE.B  (A4),D3                         | read next GCR byte from disk
        BPL.B   SONY_RDDATA_CONT_5              | poll until valid
        OR.B    0x0(A3,D3.W),D2                 | combine decoded low 6 with high 2
        EOR.B   D5,D2                           | decrypt: XOR with checksum D5
        MOVE.B  D2,(A1)+                        | store decoded byte B
        ADDX.B  D2,D6                           | accumulate checksum B into D6
        ROL.B   #0x2,D1                         | rotate last 2 extra bits into position
        AND.B   D0,D1                           | D1 = bits 7-6 of byte C
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_3              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_3:
        MOVE.B  (A4),D3                         | read next GCR byte from disk
        BPL.B   SONY_RDDATA_SKIP_3              | poll until valid
        OR.B    0x0(A3,D3.W),D1                 | combine decoded low 6 with high 2
        EOR.B   D6,D1                           | decrypt: XOR with checksum D6
        MOVE.B  D1,(A1)+                        | store decoded byte C
        ADDX.B  D1,D7                           | accumulate checksum C into D7
        SUBQ.W  #0x3,D4                         | decrement count of remaining bytes
        BPL.B   SONY_RDDATA_CONT_3              | more bytes in this buffer -> next group
        SWAP    D4                              | done with tag bytes
        TST.B   (DskVerify).w                   | read-verify (ioPosMode bit 6, DskVerify)?
        BEQ.B   SONY_RDDATA_SKIP_4              | no -> read data normally
        BRA.B   SONY_RDDATA_SKIP_6              | yes -> verify (compare) instead
SONY_RDDATA_LOOP_3:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_4              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
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
        ADD.B   D7,D3                           | X = bit 7 of checksum C
        ROL.B   #0x1,D7                         | rotate checksum C left (not through X)
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
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_5              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_5:
        MOVE.B  (A4),D3                         | read next GCR byte
        BPL.B   SONY_RDDATA_SKIP_5              | poll until valid
        OR.B    0x0(A3,D3.W),D1                 | combine low 6 with high 2
        EOR.B   D6,D1                           | decrypt byte C via XOR
        MOVE.B  D1,(A0)+                        | store decoded data byte C
        ADDX.B  D1,D7                           | accumulate into checksum D7
        SUBQ.W  #0x3,D4                         | 3 bytes decoded per group
        BRA.B   SONY_RDDATA_LOOP_3              | loop for remaining data bytes
SONY_RDDATA_LOOP_4:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_6              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
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
        ADD.B   D7,D3                           | X = bit 7 of checksum C
        ROL.B   #0x1,D7                         | rotate checksum C left (not through X)
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
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_7              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
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
SONY_RDDATA_DONE:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_8              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
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
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_9              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_9:
        MOVE.B  (A4),D3                         | read checksum byte for D7
        BPL.B   SONY_RDDATA_SKIP_9              | poll until valid
        MOVE.B  0x0(A3,D3.W),D3                 | GCR decode: low 6 checksum bits
        BMI.B   SONY_RDDATA_ERR_2               | invalid GCR byte -> error
        OR.B    D3,D1                           | D1 = full 8-bit checksum C
        CMP.B   D1,D7                           | compare with accumulated D7
        BEQ.B   SONY_RDDATA_CONT_12             | test the checksum
| Called by: SONY_RDDATA_CONT_10, SONY_RDDATA_CONT_11, SONY_RDDATA_SKIP_8, SONY_RDDATA_SKIP_9
SONY_RDDATA_ERR_2:
        MOVEQ.L #-0x48,D0                       | badDCkSum (-72): data checksum wrong or invalid nibble
        BRA.B   SONY_RDDATA_CONT_13             | return the error
SONY_RDDATA_ERR_3:
        MOVEQ.L #-0x44,D0                       | dataVerErr (-68): read-verify compare failed
        BRA.B   SONY_RDDATA_CONT_13             | return the error
SONY_RDDATA_CONT_12:
        MOVEQ.L #0x1,D4                         | D4 = 1: expect 2 trailer bytes ($DE $AA)
SONY_RDDATA_LOOP_5:
        MOVE.B  (A4),D3                         | read trailer byte from disk
        BPL.B   SONY_RDDATA_LOOP_5              | poll until valid
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_RDDATA_SKIP_10             | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_RDDATA_SKIP_10:
        CMP.B   (A2)+,D3                        | compare trailer against $DE, $AA
        BNE.B   SONY_RDDATA_ERR_4               | mismatch -> bad data bit-slip
        DBF     D4,SONY_RDDATA_LOOP_5           | read next trailer byte
        MOVEQ.L #0x0,D0                         | noErr: data read successful
SONY_RDDATA_CONT_13:
        BRA.W   SONY_DSKRTN                     | return through DskRtn
SONY_RDDATA_ERR_4:
        MOVEQ.L #-0x49,D0                       | badDBtSlp (-73): data field slip marks wrong
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
| 11111111 00 11111111 00 11111111 00 11111111: 10-bit self-sync bytes
| ("eight bits of 1 and two bits of 0", Software control of IWM) that
| put the IWM on the byte boundary whatever came before (SWIM Chip
| User's Ref, "GCR Track Format"); the IWM reads them as five $FF.
SONY_WRDATAMKS:
        .byte   0xFF,0x3F,0xCF,0xF3,0xFC,0xFF   | self-sync: 48 bits = four 10-bit groups (eight 1s, two 0s) + eight 1s
        .byte   0xD5,0xAA                       | data mark $D5 $AA ($AD is written by the loop)

| -------------------------------------------------------------------------
| WrData -- write the data field of the sector whose address field was
| just read (Larry Kenyon's GCR write routine): self-sync bytes, $D5 $AA
| $AD, sector number (TagData+1), the 12 tag bytes (TagData+2..) and the
| 512 bytes at (A0), encoded 6-and-2 with three running checksums, then
| the checksum nibbles and the slip marks (format: see RdData).
|   A0 (in) -- data buffer, A4/A5/A6 (in) -- IWM q6L / VIA / SCC pointers
|   D0 (out) -- 0 or wrUnderrun
| IWM access: Q6H (L6 = 1), then the first byte is written to Q7H (L7 =
| 1, motor on: write state, the byte goes to the write data buffer).
| Each further byte: wait for handshake bit 7 (buffer empty) read at q6L
| (L6 = 0, so L7 = 1, L6 = 0 selects the write handshake register), then
| write the byte to q6H (L6 = 1 again: write data register). Q7L ends the
| write state.
| -------------------------------------------------------------------------
E_Sony_WrData:
        LEA.L   SONY_WRDATAMKS(PC),A2           | A2 -> sync group and data mark template
        MOVE.L  (DiskVars_JWrData).w,-(SP)      | push the JWrData vector
        RTS                                     | and jump through it
| jtWrData (JWrData vector)
Sony_WrData:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save return address as continuation
        LEA.L   (TagData_1).w,A1                | A1 -> TagData+1: sector number and tags first
        MOVE.L  #0x2010009,D4                   | counts: lo 9 = tags 1-9; hi 513 = tags 10-12 + data bytes 1-510 (3 per group)
        MOVEQ.L #0x0,D2                         | D2 = 0: high byte clear for indexing
        MOVEQ.L #0x0,D3                         | clear nibble accumulator
        MOVEA.L (IWM).w,A3                      | A3 = IWM base (low-memory IWM)
        TST.B   q6H(A3)                         | Q6H: L6 = 1 (Apple: "first byte written is a bit weird")
        MOVEQ.L #0x6,D0                         | D0 = 6: bytes 2-7 of MarkTbl in the loop
        MOVEQ.L #0x0,D5                         | clear checksum register A
        MOVE.B  (A2)+,q7H(A3)                   | Q7H: write state (sense -> write load), $FF into the buffer
        LEA.L   q6H(A3),A3                      | A3 -> q6H: write data register
        MOVEQ.L #0x0,D6                         | clear checksum register B
        MOVEQ.L #0x0,D7                         | clear checksum register C
SONY_WRDATA_LOOP:
        MOVE.B  (A2)+,D1                        | load next header byte from template
SONY_WRDATA_NO:
        TST.B   (A4)                            | handshake register (q6L): bit 7 = buffer empty?
        BPL.B   SONY_WRDATA_NO                  | no -> wait for IWM
        MOVE.B  D1,(A3)                         | write sync/header byte to disk
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP                | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP:
        SUBQ.W  #0x1,D0                         | decrement header byte counter
        BNE.B   SONY_WRDATA_LOOP                | more header bytes -> loop
        MOVE.B  (A2)+,D1                        | D1 = $AA: data mark byte
        LEA.L   DT_Sony_NiblTbl(PC),A2          | A2 = GCR encode table (64 entries)
SONY_WRDATA_NO_2:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_2                | no -> wait
        MOVE.B  D1,(A3)                         | write $AA data mark to disk
        MOVEQ.L #0xB,D1                         | NiblTbl[$0B] = $AD: the loop writes it as "byte B"
        MOVE.B  (A1)+,D2                        | D2 = sector number (TagData+1): "byte C", not checksummed
        BRA.B   SONY_WRDATA_LOOP_2              | enter GCR encode loop
SONY_WRDATA_CONT:
        MOVE.L  A0,A1                           | switch source from tags to data buffer
SONY_WRDATA_NEXT:
        ADDX.B  D2,D7                           | accumulate byte C into checksum D7
        EOR.B   D6,D2                           | encrypt byte C: XOR with checksum D6
        MOVE.B  D2,D3                           | D3 = encrypted byte C
        LSR     #0x6,D3                         | D3 = A7 A6 B7 B6 C7 C6: the top bits of the group
SONY_WRDATA_NO_3:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_3                | no -> wait
        MOVE.B  0x0(A2,D3.W),(A3)               | write the top-bits nibble of the group
        SUBQ.W  #0x3,D4                         | 3 bytes encoded per group
        MOVE.B  D7,D3                           | D3 = checksum C
        ADD.B   D7,D3                           | X = bit 7 of checksum C
        ROL.B   #0x1,D7                         | rotate checksum C left (not through X)
        ANDI.B  #0x3F,D0                        | mask byte A to low 6 bits
SONY_WRDATA_NO_4:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_2              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
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
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_3              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_3:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_SKIP_3              | no -> wait
        MOVE.B  0x0(A2,D2.W),(A3)               | GCR encode low 6 bits of byte C
        MOVE.B  (A1)+,D2                        | D2 = next source byte (C)
        TST     D4                              | bytes remaining in segment?
        BNE.B   SONY_WRDATA_NEXT                | yes -> encode next group
        SWAP    D4                              | swap: switch from tags to data count
        BNE.B   SONY_WRDATA_CONT                | nonzero -> start data section
        CLR.B   D3                              | last group: only bytes 511 and 512, C = 0
        LSR     #0x6,D3                         | D3 = A7 A6 B7 B6 0 0
SONY_WRDATA_NO_6:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_6                | no -> wait
        MOVE.B  0x0(A2,D3.W),(A3)               | write the top-bits nibble of the last group
        MOVE.B  D5,D3                           | start the checksum top-bits nibble:
        ROL     #0x2,D3                         | checksum A bits 7-6,
        MOVE.B  D6,D3                           | then checksum B
        ROL     #0x2,D3                         | (bits 7-6 of A and B now in D3 bits 8-11)
        ANDI.B  #0x3F,D0                        | low 6 bits of byte A (data byte 511)
SONY_WRDATA_NO_7:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_7                | no -> wait
        MOVE.B  0x0(A2,D0.W),(A3)               | write it
        ANDI.B  #0x3F,D1                        | low 6 bits of byte B (data byte 512)
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_4              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_4:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_SKIP_4              | no -> wait
        MOVE.B  0x0(A2,D1.W),(A3)               | write it
        MOVE.B  D7,D3                           | add checksum C:
        LSR     #0x6,D3                         | D3 = top bits of checksums A, B, C
SONY_WRDATA_NO_8:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_8                | no -> wait
        MOVE.B  0x0(A2,D3.W),(A3)               | write the checksum top-bits nibble
        ANDI.B  #0x3F,D5                        | mask checksum D5 low 6 bits
SONY_WRDATA_NO_9:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_9                | no -> wait
        MOVE.B  0x0(A2,D5.W),(A3)               | GCR encode checksum D5 low 6
        ANDI.B  #0x3F,D6                        | mask checksum D6 low 6 bits
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_5              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_5:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_SKIP_5              | no -> wait
        MOVE.B  0x0(A2,D6.W),(A3)               | GCR encode checksum D6 low 6
        ANDI.B  #0x3F,D7                        | mask checksum D7 low 6 bits
SONY_WRDATA_NO_10:
        TST.B   (A4)                            | IWM handshake ready?
        BPL.B   SONY_WRDATA_NO_10               | no -> wait
        MOVE.B  0x0(A2,D7.W),(A3)               | GCR encode checksum D7 low 6
        LEA.L   SONY_SLIPMKS(PC),A2             | A2 = data field trailer ($DE $AA $FF $FF)
        MOVEQ.L #0x3,D2                         | D2 = 3: write 4 trailer bytes
SONY_WRDATA_LOOP_3:
        MOVE.B  (A4),D1                         | handshake register: bit 7 = buffer empty, bit 6 = 0 after an underrun
        BPL.B   SONY_WRDATA_LOOP_3              | poll until ready
        MOVE.B  (A2)+,(A3)                      | write next trailer byte to disk
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_WRDATA_SKIP_6              | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_WRDATA_SKIP_6:
        DBF     D2,SONY_WRDATA_LOOP_3           | loop for all 4 trailer bytes
        MOVEQ.L #0x0,D0                         | assume noErr
        BTST    #0x6,D1                         | handshake bit 6 still 1 (cleared by an underrun)?
        BNE.B   SONY_WRDATA_OK                  | yes -> success
        MOVEQ.L #-0x4A,D0                       | wrUnderrun (-74): write underrun
SONY_WRDATA_OK:
        TST.B   q7L-q6H(A3)                     | Q7L: L7 = 0, write state off (the last $FF is still being written)
        BRA.W   SONY_DSKRTN                     | return via continuation

| -------------------------------------------------------------------------
| TrailMks (Apple): the slip marks WrData writes after a data field, then
| the GCR nibble table NiblTbl (6-bit value -> disk nibble, its address is
| in the NiblTbl vector) and AdrMkTbl, the 27-byte skeleton of a sector
| header used by Format: sync group, address mark, sync group, data mark.
| The two $FF let the slip marks reach the disk before write mode ends
| (Software control of IWM: write a garbage byte $FF before turning off
| write mode). NiblTbl holds the 64 data nibbles (SWIM Chip User's Ref,
| "GCR Encoding": of the 81 bytes with bit 7 set and no more than two 0
| bits in a row, $D5 and $AA are the mark bytes and 64 encode data).
| -------------------------------------------------------------------------
SONY_SLIPMKS:
        .byte   0xDE,0xAA,0xFF,0xFF             | slip marks $DE $AA, then $FF $FF
DT_Sony_NiblTbl:
        .byte   0x96,0x97,0x9A,0x9B,0x9D,0x9E   | GCR encode: values 0-5
        .byte   0x9F,0xA6,0xA7,0xAB,0xAC,0xAD   | GCR encode: values 6-11
        .byte   0xAE,0xAF,0xB2,0xB3,0xB4,0xB5   | GCR encode: values 12-17
        .byte   0xB6,0xB7,0xB9,0xBA,0xBB,0xBC   | GCR encode: values 18-23
        .byte   0xBD,0xBE,0xBF,0xCB,0xCD,0xCE   | GCR encode: values 24-29
        .byte   0xCF,0xD3,0xD6,0xD7,0xD9,0xDA   | GCR encode: values 30-35
        .byte   0xDB,0xDC,0xDD,0xDE,0xDF,0xE5   | GCR encode: values 36-41
        .byte   0xE6,0xE7,0xE9,0xEA,0xEB,0xEC   | GCR encode: values 42-47
        .byte   0xED,0xEE,0xEF,0xF2,0xF3,0xF4   | GCR encode: values 48-53
        .byte   0xF5,0xF6,0xF7,0xF9,0xFA,0xFB   | GCR encode: values 54-59
        .byte   0xFC,0xFD,0xFE,0xFF             | GCR encode: values 60-63
SONY_ADRMKTBL:
        .byte   0xFF,0x3F,0xCF,0xF3,0xFC,0xFF   | 0-5: the six self-sync bytes (also SyncTbl)
        .byte   0xD5,0xAA,0x96,0x00,0x00,0x00   | 6-8: address mark $D5 $AA $96; 9-11: track, sector, side
        .byte   0x00,0x00,0xDE,0xAA,0xFF,0xFF   | 12-13: format byte, checksum; 14-16: $DE $AA $FF; 17: self-sync...
        .byte   0x3F,0xCF,0xF3,0xFC,0xFF,0xD5   | 18-22: ...self-sync bytes; 23: data mark $D5...
        .byte   0xAA,0xAD,0x00,0x00             | 24-25: ...$AA $AD; 26: sector; 27: not copied (headers are 27 bytes)

| -------------------------------------------------------------------------
| CtlFormat -- format the disk (csCode 6, floppy)
|   CSParam (in) -- 1 = format a two-sided drive one-sided (400K)
| Builds the 12 sector headers in a 512-byte stack buffer, then formats
| tracks 0-79 (both sides for a two-sided format) with SpdSeek and
| FormatTrack. Exits through FmtVerExit (shared with CtlVerify). There is
| no write-protect check here (MTN #272 lists wPrErr for csCode 6; Apple
| added the check on 18 Nov 1987, after this ROM).
| -------------------------------------------------------------------------
Sony_CtlFormat:
        SUBA    #0x200,SP                       | 512-byte buffer on the stack
        MOVE.L  SP,DiskBuffer(A1)               | DiskBuffer = buffer (sector headers)
        TST.B   Sides(A1,D1.W)                  | Sides: double-sided drive?
        SMI.B   TwoSided(A1)                    | TwoSided = $FF: format both sides
        BPL.B   SONY_CTLFORMAT_SIDES            | one-sided drive -> one-sided format
        CMPI    #0x1,csParam(A0)                | CSParam = 1: format one-sided anyway?
        BNE.B   SONY_CTLFORMAT_SIDES            | no ->
        CLR.B   TwoSided(A1)                    | one-sided format
SONY_CTLFORMAT_SIDES:
        TST.B   TwoSided(A1)                    | one or two sides?
        SNE.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt of the drive = the format we write
        MOVE    #0x7,GapSync(A1)                | GapSync = 7 sync groups between sectors to start with (System 7.1: 8)
        BSR.W   SONY_FVPOWERUP                  | FVPowerUp: power up (synchronously)
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  DiskBuffer(A1),A0               | A0 = header buffer
        LEA.L   SONY_ADRMKTBL(PC),A1            | A1 -> AdrMkTbl
        MOVEQ.L #0xB,D0                         | 12 sector headers
SONY_CTLFORMAT_MARKS:
        MOVEQ.L #0x1A,D1                        | 27 bytes each
        MOVE.L  A1,A2                           | A2 -> skeleton
SONY_CTLFORMAT_MARKS_2:
        MOVE.B  (A2)+,(A0)+                     | copy a byte
        DBF     D1,SONY_CTLFORMAT_MARKS_2       | 27 times
        DBF     D0,SONY_CTLFORMAT_MARKS         | 12 times
        BSR.W   Sony_GetDrv1                    | GetDrv1
        CLR     SideTrack(A1)                   | SideTrack = 0: start with track 0, side 0
SONY_CTLFORMAT_TRACKLOOP:
        BSR.B   SONY_SPDSEEK                    | SpdSeek: seek, check the speed
        BNE.B   SONY_FMTVEREXIT                 | error -> exit
        BSR.W   SONY_FORMATTRACK                | FormatTrack
        BNE.B   SONY_FMTVEREXIT                 | error -> exit
        BSR.W   Sony_GetDrv1                    | GetDrv1
        BCLR    #0x3,SideTrack(A1)              | side 0
        ADDQ.W  #0x1,SideTrack(A1)              | next track
        CMPI    #0x50,SideTrack(A1)             | all 80 tracks?
        BLT.B   SONY_CTLFORMAT_TRACKLOOP        | no -> next track
        MOVEQ.L #0x0,D0                         | noErr
SONY_FMTVEREXIT:
        MOVE    PwrOffTime(A1),D2               | FmtVerExit: normal power-off delay
        ADDA    #0x200,SP                       | release the stack buffer
        BRA.W   SONY_POFFEXIT                   | power down and complete the request
| speed limits used by SpdSeek: the same midpoints as SpeedCheckTbl,
| +-1% instead of +-2%
SONY_FMTSPEEDTBL:
        .byte   0x11,0xBC,0x11,0x62,0x13,0x59   | zone 0: hi=0x11BC, lo=0x1162; zone 1 hi=0x1359
        .byte   0x12,0xF7,0x15,0x49,0x14,0xDD   | zone 1 lo=0x12F7; zone 2: hi=0x1549, lo=0x14DD
        .byte   0x17,0xA6,0x17,0x2E,0x1A,0x9A   | zone 3: hi=0x17A6, lo=0x172E; zone 4 hi=0x1A9A
        .byte   0x1A,0x14                       | zone 4 lo=0x1A14

| -------------------------------------------------------------------------
| SpdSeek -- seek to SideTrack (synchronously); for an old-interface
| drive, measure and adjust the speed at the first track of each zone
|   D0 (out) -- 0 or error code
| -------------------------------------------------------------------------
SONY_SPDSEEK:
        MOVE.B  BadSpdInit(A1),BadSpdCnt(A1)    | BadSpdCnt = BadSpdInit
SONY_SPDSEEK_CKDRIFT:
        MOVE    SideTrack(A1),D6                | CkDrift: D6 = side/track wanted
        BSR.W   SONY_FMTVERSEEK                 | FmtVerSeek: seek synchronously
        BSR.W   Sony_GetDrv1                    | GetDrv1
        MOVE    Track(A1,D1.W),D6               | D6 = current track
        BMI.B   SONY_SPDSEEK_EXIT               | negative after a seek error -> exit
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BMI.B   SONY_SPDSEEK_OK                 | yes -> no speed check
        MOVEQ.L #0xF,D0                         | mask: track mod 16
        AND.B   D6,D0                           | D0 = track mod 16
        BNE.B   SONY_SPDSEEK_OK                 | not the first track of a zone -> done
        LSR     #0x4,D6                         | zone
        LSL     #0x3,D6                         | * 8
        LEA.L   TrkSpeedTbl(A1,D1.W),A2         | A2 -> TrkSpeedTbl
        LEA.L   TSTblTicks(A2,D6.W),A2          | A2 -> TSTblTicks: time of the last check of this zone
        MOVE.L  (Ticks).w,D2                    | Ticks
        MOVE.L  D2,(A2)                         | note the time of this check
        LEA.L   SONY_SPDSEEK_CHECK(PC),A3       | return address for the measurement
        BRA.W   SONY_GETFREQ1                   | measure (GetFreq1 in MakeSpdTbl)

| SONY_SPDSEEK_CHECK -- speed check callback for format (tighter tolerances)
SONY_SPDSEEK_CHECK:
        BMI.B   SONY_SPDSEEK_ERR                | measurement failed -> spdAdjErr
        MOVE    -(A2),D0                        | D0 = TSTblDelta: speed code change for 2% speed
        LSR     #0x1,D0                         | half of it
        LEA.L   SONY_FMTSPEEDTBL(PC),A0         | A0 -> format speed limits
        LSR     #0x1,D6                         | zone * 4
        ADDA    D6,A0                           | A0 -> limits of this zone
        CMP     (A0)+,D4                        | too fast (speed value above the upper limit)?
        BGT.B   SONY_SPDSEEK_ADJUST             | yes -> adjust
        NEG     D0                              | else D0 = -delta/2
        CMP     (A0),D4                         | too slow (at or below the lower limit)?
        BGT.B   SONY_SPDSEEK_OK                 | no -> speed is fine
SONY_SPDSEEK_ADJUST:
        SUB     D0,-(A2)                        | TSTblCode -= delta/2 (fast) or += delta/2 (slow)
        CLR.L   TSTblTicks(A2)                  | force a recheck
        SUBQ.B  #0x1,BadSpdCnt(A1)              | BadSpdCnt: adjustments left?
        BPL.B   SONY_SPDSEEK_CKDRIFT            | yes -> seek and check again
SONY_SPDSEEK_ERR:
        MOVEQ.L #-0x4F,D0                       | spdAdjErr (-79)
        BRA.B   SONY_SPDSEEK_EXIT               | return

| SpdSeekOK -- speed OK (or a new-interface drive)
SONY_SPDSEEK_OK:
        MOVEQ.L #0x0,D0                         | noErr
SONY_SPDSEEK_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| FormatTrack -- format the current track (both sides for a two-sided
| format), adjusting GapSync until the inter-sector gap is even
|   D0 (out) -- 0 or error code (also in DskErr)
| -------------------------------------------------------------------------
SONY_FORMATTRACK:
        BSR.W   Sony_GetDrv1                    | GetDrv1
        MOVE    SideTrack(A1),D6                | D6 = side/track
        MOVE    D6,D1                           | D1 = track
        BCLR    #0xB,D1                         | without the side bit
        LSR     #0x4,D1                         | zone
        MOVEQ.L #0xC,D0                         | 12 sectors in zone 0,
        SUB     D1,D0                           | one less per zone inward
        MOVE    D0,SectCnt(A1)                  | SectCnt = sectors on this track
        BSR.W   SONY_FILLINMARKS                | FillInMarks: track/sector fields of the headers
| SONY_FORMATTRACK_1 -- write raw track then verify
SONY_FORMATTRACK_1:
        BSR.W   SONY_DOFORMAT                   | FmtTrk1: DoFormat: write the track
        BEQ.B   SONY_FORMATTRACK_CHECK          | ok -> check the gap
        BSR.W   SONY_TOEMPTYPD                  | toEmptyPD: save the error, poll data
        ANDI    #-0x701,SR                      | open interrupts
        BRA.W   SONY_FORMATTRACK_EXIT           | exit with the write error
| check the inter-sector gap (poll data stays on the stack)
SONY_FORMATTRACK_CHECK:
        BSR.W   E_Sony_RdAddr                   | RdAddr: the next address mark
        BMI.B   SONY_FORMATTRACK_GAP            | error ->
        TST.B   D2                              | should be sector 0
        BEQ.B   SONY_FORMATTRACK_GAP            | it is ->
        MOVEQ.L #-0x52,D0                       | fmt1Err (-82): not sector 0
SONY_FORMATTRACK_GAP:
        BSR.W   SONY_TOEMPTYPD                  | toEmptyPD (preserves D0)
        ANDI    #-0x701,SR                      | open interrupts
        LEA.L   GapSync(A1),A0                  | A0 -> GapSync
        MOVE    (DskErr).w,D0                   | RdAddr result (via toEmptyPD): count left, or an error
        BMI.B   SONY_FORMATTRACK_DECRSN1        | error -> fewer sync groups
        MOVE.L  #MustFindCt+4,D2                | MustFindCt + 4 = 1504
        SUB     D0,D2                           | - count left = nibbles read before sector 0 (the gap)
        DIVU    #0x5,D2                         | / 5 = sync groups in that gap (a sync group reads as five $FF nibbles)
        MOVE    #-0x53,(DskErr).w               | assume fmt2Err (-83): not enough sync
        SUB     (A0),D2                         | - GapSync = groups more than standard
        BMI.B   SONY_FORMATTRACK_DECRSYNC       | too few -> DecrSync
        EXT.L   D2                              | extend for DIVU
        DIVU    SectCnt(A1),D2                  | / sectors = extra groups per sector
        BEQ.B   SONY_FORMATTRACK_OK             | none ->
        SUBQ.W  #0x1,D2                         | just one -> leave GapSync alone
        BEQ.B   SONY_FORMATTRACK_OK             | ->
        ADDQ.W  #0x1,(A0)                       | else GapSync + 1
SONY_FORMATTRACK_OK:
        BSR.W   Sony_GetDrv1                    | FTExitOK: GetDrv1
        BSET    #0x3,SideTrack(A1)              | side 1 done already?
        BNE.B   SONY_FORMATTRACK_DONE           | yes ->
        TST.B   TwoSided(A1)                    | two-sided format?
        BNE.W   SONY_FORMATTRACK                | yes -> format side 1
SONY_FORMATTRACK_DONE:
        CLR     (DskErr).w                      | success: DskErr = 0
SONY_FORMATTRACK_EXIT:
        MOVE    (DskErr).w,D0                   | FTExit: D0 = DskErr
        RTS                                     | return
| DecrSync / DecrSn1 -- fewer sync groups (not below minSync = 4)
SONY_FORMATTRACK_DECRSYNC:
        ADDQ.W  #0x1,D2                         | only one too few?
        BEQ.B   SONY_FORMATTRACK_OK             | yes -> accept
SONY_FORMATTRACK_DECRSN1:
        SUBQ.W  #0x1,(A0)                       | GapSync - 1
        CMPI    #minSync,(A0)                   | below minSync (4)?
        BLT.B   SONY_FORMATTRACK_EXIT           | yes -> give up (fmt2Err)
        BRA.B   SONY_FORMATTRACK_1              | FmtTrk1: format the track again

| -------------------------------------------------------------------------
| DoFormat -- write the current track (interrupts disabled): 200 sync
| groups, then for each sector GapSync sync groups, the 27-byte header,
| 703 data nibbles ($96) and the bit-slip marks; 2:1 interleave from the
| headers built by FillInMarks. 703 = 699 data + 4 checksum nibbles (the
| SWIM Chip User's Reference figure counts "699+3"), all $96 (6-bit
| value 0): the sector reads as 524 zero bytes with correct checksums.
| -------------------------------------------------------------------------
SONY_DOFORMAT:
        MOVE.L  (SP)+,(DskRtnAdr).w             | strip the return address
        MOVEQ.L #RdDtaAdr,D0                    | RdDtaAdr: side 0
        MOVE.L  (SonyVars).w,A1                 | reload SonyVars
        TST.B   TwoSided(A1)                    | two-sided format?
        BEQ.B   SONY_DOFORMAT_SIDE              | no -> side 0
        BTST    #0xB,D6                         | side 1 (bit 11)?
        BEQ.B   SONY_DOFORMAT_SIDE              | no -> side 0
        MOVEQ.L #RdDta1Adr,D0                   | RdDta1Adr: side 1
SONY_DOFORMAT_SIDE:
        BSR.W   Sony_AdrDisk                    | select the head
        MOVEQ.L #0x4,D0                         | PollStack = SP + 4 (one return address)
        BSR.W   E_Sony_SetUpPoll                | SetUpPoll: A5, A6, PollStack
        MOVEA.L (IWM).w,A4                      | A4 = IWM base (low-memory IWM)
        LEA.L   q6H(A4),A3                      | A3 -> q6H: write data register
        MOVE.L  DiskBuffer(A1),A0               | A0 -> sector headers
        MOVE    SectCnt(A1),D0                  | D0 = sector count
        MOVE    GapSync(A1),D1                  | D1 = GapSync
        SUBQ.W  #0x2,D1                         | - 2 for DBRA and the header sync group
        LEA.L   SONY_ADRMKTBL(PC),A1            | A1 -> SyncTbl (sync group)
        MOVE    #0xC7,D3                        | 200 sync groups (strtSync)
        TST.B   (A3)                            | Q6H: L6 = 1 (A3 = q6H)
        MOVE.B  D3,q7H(A4)                      | Q7H: write state; the first byte ($C7) is garbage (Apple)
        LEA.L   q6L(A4),A4                      | A4 -> q6L: write-handshake register in the write state
| SONY_DOFORMAT_STRTSYNC -- write initial self-sync ($FF) bytes, D3+1 groups of 6 bytes
SONY_DOFORMAT_STRTSYNC:
        MOVE.L  A1,A2                           | WrStrtSync: A2 -> sync group
        MOVEQ.L #0x2,D2                         | 3 pairs of nibbles
SONY_DOFORMAT_WSS1:
        MOVE.B  (A2)+,D4                        | prefetch
SONY_DOFORMAT_WSS1_HSHK:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_WSS1_HSHK         | no -> wait
        MOVE.B  D4,(A3)                         | write a sync nibble
        MOVE.B  (A2)+,D4                        | prefetch
        TST.B   (A5)                            | SCC data waiting?
        BMI.B   SONY_DOFORMAT_WSS1_HSHK2        | no ->
        MOVE.B  (A6),-(SP)                      | poll the SCC: byte onto the stack
SONY_DOFORMAT_WSS1_HSHK2:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_WSS1_HSHK2        | no -> wait
        MOVE.B  D4,(A3)                         | write a sync nibble
        DBF     D2,SONY_DOFORMAT_WSS1           | 3 pairs
        DBF     D3,SONY_DOFORMAT_STRTSYNC       | 200 groups
| SONY_DOFORMAT_NXTSECT -- per-sector loop: write inter-sector sync, address, gap, data
SONY_DOFORMAT_NXTSECT:
        MOVE    D1,D3                           | WrNxtSect: D3 = GapSync - 2
SONY_DOFORMAT_GAP:
        MOVE.L  A1,A2                           | A2 -> sync group
        MOVEQ.L #0x5,D2                         | 6 nibbles
SONY_DOFORMAT_GAP_2:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_GAP_2             | wait
        MOVE.B  (A2)+,(A3)                      | write a byte of the sync group
        TST.B   (A5)                            | SCC data waiting?
        BMI.B   SONY_DOFORMAT_GAP_3             | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | poll the SCC
SONY_DOFORMAT_GAP_3:
        DBF     D2,SONY_DOFORMAT_GAP_2          | 6 nibbles
        DBF     D3,SONY_DOFORMAT_GAP            | GapSync - 1 groups
| the sector header: sync group, address mark, sync group, data mark
        MOVEQ.L #0x1A,D2                        | 27 nibbles
SONY_DOFORMAT_ADRMK:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_ADRMK             | wait
        MOVE.B  (A0)+,(A3)                      | write a header nibble
        TST.B   (A5)                            | SCC data waiting?
        BMI.B   SONY_DOFORMAT_ADRMK_2           | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | poll the SCC
SONY_DOFORMAT_ADRMK_2:
        DBF     D2,SONY_DOFORMAT_ADRMK          | 27 nibbles
| the data field: 703 nibbles of $96 (encoded zeros)
        MOVE    #0x2BE,D2                       | 703 nibbles
SONY_DOFORMAT_DATA:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_DATA              | wait
        MOVE.B  #0x96,(A3)                      | write $96
        TST.B   (A5)                            | SCC data waiting?
        BMI.B   SONY_DOFORMAT_DATA_2            | no SCC byte waiting -> skip
        MOVE.B  (A6),-(SP)                      | poll the SCC
SONY_DOFORMAT_DATA_2:
        DBF     D2,SONY_DOFORMAT_DATA           | 703 nibbles
| then the slip marks $DE $AA and two $FF (AdrMkTbl+14)
        MOVEQ.L #0x3,D2                         | 4 nibbles
        ADDQ.W  #0x8,A2                         | A2 -> bit-slip marks (DE AA FF FF)
SONY_DOFORMAT_SLIP:
        TST.B   (A4)                            | write handshake ready?
        BPL.B   SONY_DOFORMAT_SLIP              | wait
        MOVE.B  (A2)+,(A3)                      | write a bit-slip nibble
        DBF     D2,SONY_DOFORMAT_SLIP           | 4 nibbles
        SUBQ.W  #0x1,D0                         | count the sector
        BGT.B   SONY_DOFORMAT_NXTSECT           | next sector
| check write completion status
        MOVE.B  (A4),D0                         | write-handshake register: bit 6 = 0 after an underrun
        MOVEQ.L #0x0,D2                         | assume no underrun
        BTST    #0x6,D0                         | bit 6 = 0: write underrun?
        BNE.B   SONY_DOFORMAT_OK                | no ->
        MOVEQ.L #-0x4A,D0                       | wrUnderrun (-74)
        BRA.B   SONY_DOFORMAT_EXIT              | exit write mode

| SONY_DOFORMAT_OK -- write completed successfully
SONY_DOFORMAT_OK:
        MOVEQ.L #0x0,D0                         | noErr
SONY_DOFORMAT_EXIT:
        TST.B   q7L-q6H(A3)                     | Q7L: L7 = 0, write state off (Apple: "after half of garbage nibble is written")
        MOVE.L  (DskRtnAdr).w,-(SP)             | continue at DskRtnAdr
        TST     D0                              | CCR = result
        RTS                                     | return there

| -------------------------------------------------------------------------
| FillInMarks -- fill in the track, sector, side, format byte and checksum
| of the 12 sector headers (D6 = side/track, D0 = sector count); sectors
| are numbered 0, n/2, 1, n/2+1, ... (2:1 interleave). Registers kept.
| -------------------------------------------------------------------------
SONY_FILLINMARKS:
        MOVEM.L D0-D7/A0-A1,-(SP)               | save registers
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  DiskBuffer(A1),A0               | A0 -> header buffer
        MOVEQ.L #FmtByte,D3                     | FmtByte $02: 2:1 interleave, one-sided
        TST.B   TwoSided(A1)                    | two-sided?
        BEQ.B   SONY_FILLINMARKS_1              | no ->
        MOVEQ.L #Fmt2Byte,D3                    | Fmt2Byte $22: 2:1 interleave, two-sided ($20)
SONY_FILLINMARKS_1:
        MOVE.L  (DiskVars_NiblTbl).w,A1         | A1 -> NiblTbl
        MOVE.B  0x0(A1,D3.W),D7                 | D7 = encoded format byte
        MOVE.B  D3,D5                           | start the checksum
        MOVEQ.L #0x3F,D3                        | 6-bit mask
        AND.B   D6,D3                           | track bits 0-5
        MOVE.B  0x0(A1,D3.W),D2                 | D2 = encoded track
        EOR.B   D3,D5                           | into the checksum
        LSR     #0x6,D6                         | side (now bit 5) and track bits 6-10
        EOR.B   D6,D5                           | into the checksum
        MOVE.B  0x0(A1,D6.W),D6                 | D6 = encoded side/track
        MOVE    D0,D1                           | sector count
        SUBQ.W  #0x1,D1                         | - 1
        LSR     #0x1,D1                         | / 2
        ADDQ.W  #0x1,D1                         | + 1 = second sector number
        SWAP    D1                              | (high word)
        CLR     D1                              | first sector number is always 0
SONY_FILLINMARKS_LOOP:
        MOVE.B  0x0(A1,D1.W),D3                 | D3 = encoded sector number
        MOVEQ.L #0x0,D4                         | D4 = 0 (word index)
        MOVE.B  D5,D4                           | checksum without the sector
        EOR.B   D1,D4                           | plus the sector
        ADDA    #0x9,A0                         | skip to the track field
        MOVE.B  D2,(A0)+                        | encoded track
        MOVE.B  D3,(A0)+                        | encoded sector
        MOVE.B  D6,(A0)+                        | encoded side
        MOVE.B  D7,(A0)+                        | encoded format byte
        MOVE.B  0x0(A1,D4.W),(A0)+              | encoded checksum
        ADDA    #0xC,A0                         | skip to the sector byte of the data mark
        MOVE.B  D3,(A0)+                        | encoded sector
        ADDQ.W  #0x1,D1                         | next sector of this half
        SWAP    D1                              | toggle between the two halves
        SUBQ.W  #0x1,D0                         | count it
        BNE.B   SONY_FILLINMARKS_LOOP           | more ->
        MOVEM.L (SP)+,D0-D7/A0-A1               | restore registers
        RTS                                     | return

| -------------------------------------------------------------------------
| CtlVerify -- verify the disk (csCode 5, floppy): read every sector of
| every track, from track 79 down to 0 (zone by zone: the sector map
| grows by one sector per zone), both sides of a two-sided disk.
| -------------------------------------------------------------------------
Sony_CtlVerify:
        SUBA    #0x200,SP                       | 512-byte buffer on the stack
        MOVE.L  SP,DiskBuffer(A1)               | DiskBuffer = buffer
        BSR.W   SONY_FVPOWERUP                  | FVPowerUp
        MOVEQ.L #0x4,D2                         | 5 zones
        MOVE    #0x7F,D4                        | sector map for track 79 (almost)
        MOVEQ.L #0x4F,D6                        | track 79
SONY_CTLVERIFY_CLASS:
        LSL     #0x1,D4                         | NxtVClass: one more sector
        ADDQ.W  #0x1,D4                         | in this zone
        MOVEQ.L #0xF,D3                         | 16 tracks per zone
SONY_CTLVERIFY_TRACK:
        MOVEM.L D2-D6,-(SP)                     | NxtVTrk
        BSR.W   SONY_FMTVERSEEK                 | FmtVerSeek: seek to D6 (synchronously)
        MOVEM.L (SP)+,D2-D6                     | restore zone/track state
        BSR.W   Sony_GetDrv1                    | GetDrv1
        MOVE    Track(A1,D1.W),D0               | current track
        BMI.B   SONY_CTLVERIFY_EXIT             | negative after a seek error -> exit
        BSR.B   SONY_VERTRACK                   | VerTrack
        BNE.B   SONY_CTLVERIFY_EXIT             | error -> exit
        SUBQ.W  #0x1,D6                         | next track
        DBF     D3,SONY_CTLVERIFY_TRACK         | rest of the zone
        DBF     D2,SONY_CTLVERIFY_CLASS         | next zone
SONY_CTLVERIFY_EXIT:
        BRA.W   SONY_FMTVEREXIT                 | FmtVerExit
| VerTrack -- read every sector of the current track (both sides of a
| two-sided disk); SectMapSave holds [map side 0][tries][map side 1][tries]
SONY_VERTRACK:
        MOVEM.L D2-D6,-(SP)                     | save registers
        ORI     #0x300,SR                       | no interrupts
        LEA.L   SectMapSave(A1),A0              | A0 -> SectMapSave
        MOVE    D4,(A0)                         | map of this track
        MOVEQ.L #0xC,D3                         | 12
        SUB     D2,D3                           | - zone = sectors on this track
        LSL     #0x2,D3                         | * 4: allow some slop (may not get 1-1)
        MOVE    D3,0x2(A0)                      | tries
        MOVE.L  (A0)+,(A0)+                     | duplicate for side 1
        BCLR    #0x3,SideTrack(A1)              | side 0
SONY_VERTRACK_LOOP:
        MOVE.L  D1,D6                           | VTLoop: D6 = drive vars offset
        BSR.W   Sony_RdAddrSetup                | RdAddrSetup: next address mark
        BPL.B   SONY_VERTRACK_1                 | ok ->
        BSR.B   SONY_TOEMPTYPD                  | toEmptyPD
        ANDI    #-0x701,SR                      | open interrupts
        BRA.B   SONY_VERTRACK_EXIT              | exit with the error
SONY_VERTRACK_1:
        LEA.L   SectSave(A1),A0                 | A0 -> SectSave
        MOVE    D2,(A0)+                        | sector number
        MOVE    (A0)+,D0                        | sector map
        BCLR    D2,D0                           | sector still wanted?
        BNE.B   SONY_VERTRACK_2                 | yes -> read it
        BSR.B   SONY_TOEMPTYPD                  | toEmptyPD
        ANDI    #-0x701,SR                      | open interrupts
        LEA.L   SectMapSave+2(A1),A0            | A0 -> tries (SectMapSave+2)
        BRA.B   SONY_VERTRACK_3                 | count the try
SONY_VERTRACK_2:
        CMPI.B  #0x1F,D3                        | format byte > $1F
        SGT.B   TwoSideFmt(A1,D6.W)             | TwoSideFmt = $FF for a two-sided disk
        MOVE.L  DiskBuffer(A1),A0               | A0 = buffer
        CLR.B   (DskVerify).w                   | never read-verify here
        BSR.W   E_Sony_RdData                   | RdData
        BSR.B   SONY_TOEMPTYPD                  | toEmptyPD
        TST     D0                              | read ok?
        BNE.B   SONY_VERTRACK_EXIT              | no -> exit
        LEA.L   SectSave(A1),A0                 | A0 -> SectSave
        MOVE    (A0)+,D2                        | sector just read
        MOVE    (A0),D0                         | sector map
        BCLR    D2,D0                           | mark it read
        MOVE    D0,(A0)+                        | store the map
        BEQ.B   SONY_VERTRACK_OK                | all read -> next side or done
SONY_VERTRACK_3:
        SUBQ.W  #0x1,(A0)                       | count the try
        BNE.B   SONY_VERTRACK_LOOP              | tries left -> next address mark
        MOVEQ.L #-0x54,D0                       | verErr (-84): track did not verify
        BRA.B   SONY_VERTRACK_EXIT              | exit
SONY_VERTRACK_OK:
        BSR.W   Sony_GetDrv1                    | VTExitOK: GetDrv1
        TST.B   TwoSideFmt(A1,D1.W)             | two-sided format?
        BEQ.B   SONY_VERTRACK_DONE              | no -> done
        BSET    #0x3,SideTrack(A1)              | side 1 done already?
        BNE.B   SONY_VERTRACK_DONE              | yes -> done
        ADDQ.W  #0x2,A0                         | A0 -> copy of map/tries
        MOVE.L  (A0),-(A0)                      | copy it back
        BRA.B   SONY_VERTRACK_LOOP              | verify side 1
SONY_VERTRACK_DONE:
        MOVEQ.L #0x0,D0                         | noErr
SONY_VERTRACK_EXIT:
        ANDI    #-0x701,SR                      | VTExit: open interrupts
        MOVEM.L (SP)+,D2-D6                     | restore registers
        TST     D0                              | CCR = result
        RTS                                     | return
| toEmptyPD -- save D0 in DskErr and process the poll data
| Called by: SONY_FORMATTRACK_1, SONY_FORMATTRACK_GAP, SONY_VERTRACK_LOOP, SONY_VERTRACK_1, SONY_VERTRACK_2
SONY_TOEMPTYPD:
        MOVE    D0,(DskErr).w                   | DskErr = result
        BRA.W   Sony_EmptyPD                    | EmptyPD
| FmtVerSeek / FVPowerUp -- call Seek or RWPowerUp and wait until it
| completes (SyncCall; DskErr is the completion flag -- Apple's change
| <2> of 2 Feb 1990 uses Active instead, as DskErr also holds errors)
SONY_FMTVERSEEK:
        LEA.L   E_Sony_Seek(PC),A0              | FmtVerSeek: Seek
SONY_SYNCCALL:
        CLR.B   (DskErr).w                      | SyncCall: DskErr = 0: not done
        BSR.B   SONY_SYNCCALL_CALL              | call it
SONY_SYNCCALL_WAIT:
        TST.B   (DskErr).w                      | done?
        BEQ.B   SONY_SYNCCALL_WAIT              | no -> wait
        RTS                                     | return

| call (A0): a routine that waits (WakeUp) returns into the wait loop
| above at once; DskErr becomes $FF when it has really finished
SONY_SYNCCALL_CALL:
        JSR     (A0)                            | call the routine (returns early while waiting)
        ST.B    (DskErr).w                      | DskErr = $FF: done
        RTS                                     | return

| FVPowerUp -- RWPowerUp, synchronously
SONY_FVPOWERUP:
        LEA.L   Sony_RWPowerUp(PC),A0           | FVPowerUp: RWPowerUp
        BRA.B   SONY_SYNCCALL                   | synchronously

| -------------------------------------------------------------------------
| DCDPrime -- read/write on an HD20 (from jtDiskPrime, interrupts still at
| IPL 1). The first access to a drive issues a status command to learn
| its size and characteristics; then the blocks are transferred with up
| to 255 blocks per command, with retries and one hard reset.
| -------------------------------------------------------------------------
Sony_DCDPrime:
        ANDI    #-0x701,SR                      | restore IPL to 0 (DCD path)
        MOVE.W  SE_LastDrive(A1),D0             | D0 = previous drive (LastDrive)
        CMP     Drive(A1),D0                    | same as current DCD drive?
        BEQ.B   SONY_DCDPRIME_SELECT            | yes -> skip settling delay
        MOVEQ.L #0xA,D0                         | 1ms drive-switch settling delay
        BSR.W   E_Sony_WakeUp                   | wait for drive to stabilize
SONY_DCDPRIME_SELECT:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address
        TST.B   (A0)                            | CA0 low (ph0L)
        TST.B   ph2L(A0)                        | CA2 low: with CA1 high, SEL low the HD20's HSHK is the sense line
        CMPI.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace >= 2 (already mounted)?
        BGE.B   SONY_DCDPRIME_GO                | yes -> skip DCD status query
        LEA.L   SONY_DCDPRIME_STATUS(PC),A0     | A0 = DCD status completion callback
        MOVE.L  A0,SE_StsRtnAddr(A1)            | StsRtnAddr: save callback address
        BRA.W   Sony_DCDStatus                  | go issue DCD status command
SONY_DCDPRIME_STATUS:
        BNE.W   SONY_DCDEXIT                    | DCD status error -> return
        BSR.W   Sony_GetDrive                   | reload IWM/VIA/SonyVars
        MOVE.B  #0x8,DiskInPlace(A1,D1.W)       | DiskInPlace = 8: DCD disk present
        MOVE.L  SE_DevType(A1),DriveType(A1,D1.W) | DriveType/DriveManf (drive var +$16) = device type, manufacturer
        MOVE.L  SE_DevChar(A1),D0               | D0 = characteristics byte + 3-byte block count (DevChar)
        SWAP    D0                              | block count low word to the high word
        MOVE.L  D0,DriveSize(A1,D1.W)           | drive size (drive var +$12) = block count, low word first
        CLR.B   DriveS1(A1,D1.W)                | +$14 = 0: high word = bits 16-23 of the block count
        LSR     #0x8,D0                         | D0 = characteristics byte
        MOVE.B  D0,DriveChar(A1,D1.W)           | DriveChar (drive var +$1A)
        BTST    #0x3,D0                         | DevChWP (bit 3): write-protected?
        SNE.B   WriteProt(A1,D1.W)              | WrProt: $FF if write-protected
        BTST    #0x4,D0                         | DevChEject (bit 4): removable medium?
        BEQ.B   SONY_DCDPRIME_GO                | no -> DiskInPlace stays 8
        MOVE.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2
SONY_DCDPRIME_GO:
        MOVE.L  (A1),A2                         | A2 = DCE pointer
        MOVE.L  dCtlPosition(A2),D5             | D5 = dCtlPosition (byte offset)
        MOVEQ.L #0x9,D1                         | shift count for /512
        LSR.L   D1,D5                           | D5 = starting block number
        MOVE.L  dCtlQHead(A2),A0                | A0 = IOParam block
        MOVEA.L SE_TagBufPtr(A1),A5             | A5 = TagBufPtr (or nil)
        MOVE.L  ioBuffer(A0),A4                 | A4 = ioBuffer pointer
        MOVE.L  ioReqCount(A0),D3               | D3 = ioReqCount (total bytes)
        MOVEQ.L #-0x32,D0                       | paramErr (-50): assume bad position
        ANDI    #0x1FF,D3                       | check alignment (must be 512 multiple)
        BNE.W   SONY_DCDEXIT                    | not aligned -> return paramErr
        MOVE.L  ioReqCount(A0),D3               | D3 = ioReqCount (reload)
        TST.B   (DskVerify).w                   | read-verify mode (DskVerify)?
        BEQ.B   SONY_DCDPRIME_CMD               | no -> proceed with I/O
        BSR.W   Sony_CheckRead                  | check if read operation
        BNE.B   SONY_DCDPRIME_CMD               | write -> proceed with I/O
        MOVE.L  D3,ioActCount(A0)               | verify read: set ioActCount = full
        ADD.L   D3,dCtlPosition(A2)             | advance dCtlPosition by full count
        MOVEQ.L #0x0,D0                         | noErr: verify read is a no-op for DCD
        BRA.W   SONY_DCDEXIT                    | return success
SONY_DCDPRIME_CMD:
        MOVE.B  Command+1(A1),SE_DCDCmd(A1)     | DCDCmd = ioTrap (2=read, 3=write)
        SUBQ.B  #0x2,SE_DCDCmd(A1)              | convert: 0=read, 1=write
SONY_DCDPRIME_NEXT:
        MOVEQ.L #0x9,D1                         | shift count for /512
        LSR.L   D1,D3                           | D3 = blocks remaining
        MOVEQ.L #0x0,D0                         | D0 = $000000FF (max blocks per cmd)
        SUBQ.B  #0x1,D0                         | D0 = 255
        CMP.L   D0,D3                           | more than 255 blocks?
        BLT.B   SONY_DCDPRIME_COUNT             | no -> use actual count
        MOVE.L  D0,D3                           | clamp to 255 blocks per command
SONY_DCDPRIME_COUNT:
        MOVE    D3,D2                           | D2 = block count (low word copy)
        SWAP    D3                              | D3.hi = block count for sequence
        MOVE    D2,D3                           | D3 = {count, count} for tracking
        MOVE.B  #0x3,RecalCnt(A1)               | retry count = 3 attempts
        CLR.B   SE_DCDFlags(A1)                 | DCDFlags: clear reset/retry flags
SONY_DCDPRIME_RETRY:
        BSR.W   SONY_DCDSETUPCMD                | build DCD command packet
        BSR.W   E_Sony_SendCmd                  | send command to DCD
        BNE.B   SONY_DCDPRIME_ERR               | send failed -> retry/error
SONY_DCDPRIME_WAIT:
        BSR.W   SONY_DCDWAITHSHK                | wait for DCD ready (poll HSHK)
        BPL.B   SONY_DCDPRIME_RCV               | ready -> receive response
        MOVE.B  #comErr,SE_LastResult(A1)       | LastResult = comErr (comm failure)
        CLR.L   SE_LastStatus(A1)               | clear LastStatus
        MOVE.B  #NoResp,SE_LastStatus(A1)       | LastStatus = NoResp ($40)
        BRA.B   SONY_DCDPRIME_ERR               | go to retry path
SONY_DCDPRIME_RCV:
        BSR.W   Sony_DCDRcvResponse             | receive DCD response packet
        BEQ.B   SONY_DCDPRIME_WAIT              | more blocks -> continue transfer
        ADD.L   D4,D5                           | accumulate blocks transferred
        TST     D0                              | transfer error?
        BEQ.B   SONY_DCDPRIME_DONE              | noErr -> update position
SONY_DCDPRIME_ERR:
        SUBQ.B  #0x1,RecalCnt(A1)               | decrement retry counter
        BLT.B   SONY_DCDPRIME_FAIL              | retries exhausted -> fatal error
        BEQ.B   SONY_DCDPRIME_RESET             | last retry -> try DCD reset
        CMPI.B  #comErr,SE_LastResult(A1)       | LastResult == comErr?
        BNE.B   SONY_DCDPRIME_AGAIN             | no -> retry without reset
        BTST    #bChksum,SE_LastStatus(A1)      | bChksum: checksum error in status?
        BNE.B   SONY_DCDPRIME_AGAIN             | yes -> retry without reset
        TST.B   SE_DCDFlags(A1)                 | DCDFlags: already tried reset?
        BEQ.B   SONY_DCDPRIME_RESET             | no -> try DCD reset
        CLR.B   RecalCnt(A1)                    | force last attempt
SONY_DCDPRIME_RESET:
        BSR.W   E_Sony_DCDReset                 | hard-reset the DCD controller
        BNE.B   SONY_DCDPRIME_FAIL              | reset failed -> fatal error
        ST.B    SE_DCDFlags(A1)                 | DCDFlags: mark reset attempted
SONY_DCDPRIME_AGAIN:
        BRA.B   SONY_DCDPRIME_RETRY             | retry the DCD command
SONY_DCDPRIME_FAIL:
        MOVEQ.L #-0x13,D0                       | readErr (-19): DCD read failed
        CMPI.B  #aRdCmd,Command+1(A1)           | was this a read operation?
        BEQ.B   SONY_DCDPRIME_FAILEXIT          | yes -> return readErr
        MOVEQ.L #-0x14,D0                       | writErr (-20): DCD write failed
SONY_DCDPRIME_FAILEXIT:
        BRA.B   SONY_DCDEXIT                    | return error
SONY_DCDPRIME_DONE:
        MOVEQ.L #0x9,D1                         | shift count for *512
        CLR     D3                              | clear low word of D3
        SWAP    D3                              | D3 = blocks transferred this round
        CMPI.B  #aRdCmd,Command+1(A1)           | read operation?
        BEQ.B   SONY_DCDPRIME_UPDATE            | yes -> skip tag update
        ADD.L   D3,(BufTgFFlg).w                | write: advance tag file block number
SONY_DCDPRIME_UPDATE:
        LSL.L   D1,D3                           | D3 = bytes transferred (* 512)
        MOVE.L  (A1),A3                         | A3 = DCE pointer
        ADD.L   D3,dCtlPosition(A3)             | advance dCtlPosition by bytes done
        MOVE.L  dCtlQHead(A3),A0                | A0 = IOParam block
        ADD.L   D3,ioActCount(A0)               | advance ioActCount by bytes done
        MOVE.L  ioReqCount(A0),D3               | D3 = ioReqCount (total requested)
        SUB.L   ioActCount(A0),D3               | D3 = remaining bytes
        BGT.W   SONY_DCDPRIME_NEXT              | more data -> issue next DCD command
        MOVEQ.L #0x0,D0                         | noErr: DCD transfer complete
| DCD exit -- drop /ENBL, open interrupts and complete the request
| Called by: SONY_DCDPRIME_GO, SONY_DCDPRIME_STATUS, SONY_DCDPRIME_FAILEXIT, SONY_DCD_ICONEXIT, SONY_DCD_COMMAND_END
SONY_DCDEXIT:
        MOVE.L  (IWM).w,A0                      | reload IWM base
        TST.B   mtrOff(A0)                      | mtrOff: /ENBL2 off, deselect the HD20
        ANDI    #-0x701,SR                      | restore IPL to 0
        BRA.W   Sony_DiskDone                   | return result to caller
| DCDWaitHSHK -- wait until the HD20 pulls its handshake line HSHK low
| (sense = status bit 7 = 0: it has a response to send, see the error
| codes rdHsHi = "HSHK high before starting" of DCDRcvPacket), polling
| 100 times and then every ChkTime (100 us units) for at most MaxTime
| checks; returns through A3 with BPL when ready, BMI on timeout
SONY_DCDWAITHSHK:
        MOVE.L  (SP)+,A3                        | A3 = return address
SONY_DCDWAITHSHK_1:
        MOVEQ.L #0x64,D0                        | D0 = 100: quick poll attempts
SONY_DCDWAITHSHK_2:
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        TST.B   q7L(A0)                         | Q7L: read status, HSHK in bit 7
        DBPL    D0,SONY_DCDWAITHSHK_2           | poll until HSHK low or the count is done
        BPL.B   SONY_DCDWAITHSHK_EXIT           | HSHK low -> response ready
        SUBQ.W  #0x1,SE_MaxTime(A1)             | decrement MaxTime counter
        BMI.B   SONY_DCDWAITHSHK_EXIT           | timeout expired -> return not ready
        MOVE.W  SE_ChkTime(A1),D0               | D0 = ChkTime (inter-poll delay)
        BSR.W   E_Sony_WakeUp                   | delay between poll cycles
        BRA.B   SONY_DCDWAITHSHK_1              | retry polling
SONY_DCDWAITHSHK_EXIT:
        JMP     (A3)                            | return to caller (N flag = result)
| DCDSetupCmd -- set up a read or write command for D3 blocks from block
| D5: StartBlock, SeqNum, ChkTime/MaxTime, and D6/D7 = bytes to send/
| receive per block (512 data bytes one way, none the other)
SONY_DCDSETUPCMD:
        MOVE.L  D5,D0                           | D0 = starting block number
        LSL.L   #0x8,D0                         | 3-byte block number, then DriveOut = 0
        MOVE.L  D0,SE_StartBlock(A1)            | StartBlock: store in command packet
        MOVE.B  D3,SE_SeqNum(A1)                | SeqNum: store block count as seq#
        MOVE.W  #0xA,SE_ChkTime(A1)             | ChkTime = 10: check every 1 ms
        MOVE.W  #0x2710,SE_MaxTime(A1)          | MaxTime = 10000 checks: 10 s
        MOVE.L  #0x200,D6                       | D6 = 512: data size per block
        MOVEQ.L #0x0,D7                         | D7 = 0: no tag data initially
| the Mac Plus driver cleared the flag bits only after the read/write test
        ANDI.B  #0x3F,SE_DCDCmd(A1)             | DCDCmd: clear flag bits 6-7 first
        TST.B   SE_DCDCmd(A1)                   | DCDCmd: read (0) or write (1+)?
        BNE.B   SONY_DCDSETUPCMD_EXIT           | write -> D6=data, D7=0
        EXG     D6,D7                           | read -> D6=0 (send), D7=512 (recv)
SONY_DCDSETUPCMD_EXIT:
        RTS                                     | return with command packet ready

| E_Sony_SendCmd -- send command to DCD.
E_Sony_SendCmd:
        MOVE.L  (JSendCmd).w,-(SP)              | push SendCmd vector address
        RTS                                     | dispatch to Sony_SendCmd

| -------------------------------------------------------------------------
| jtSendCmd (JSendCmd vector) -- send the command block to the HD20; for a
| write, also the 512 data bytes and 20 tag bytes of each block
| (DCDSendPacket). Read data and the response are received later by
| DCDRcvResponse. Group counts: (bytes + 6) / 7.
| -------------------------------------------------------------------------
Sony_SendCmd:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address
        LEA.L   q6L(A0),A3                      | A3 = q6L: handshake register in the write state
        MOVE.L  D6,SE_BufSize(A1)               | BufSize: set send data size
        ADD.L   D7,SE_BufSize(A1)               | add receive data size to total
        MOVE.B  SE_DCDCmd(A1),D1                | D1 = DCD command byte
        CMPI.B  #0x3,D1                         | status command (3+)?
        BGE.B   SONY_SENDCMD_SKIP               | yes -> no tag adjustment needed
        TST.B   D1                              | read command (0)?
        BNE.B   SONY_SENDCMD_NO                 | no (write) -> add tags to send size
        ADDI    #0x14,D7                        | read: add 20 tag bytes to receive
        BRA.B   SONY_SENDCMD_SKIP               | skip write path
SONY_SENDCMD_NO:
        ADDI    #0x14,D6                        | write: add 20 tag bytes to send size
        MOVE.L  A5,D0                           | TagBufPtr: external tag buffer?
        BNE.B   SONY_SENDCMD_SKIP               | yes -> tags already in user buffer
        ADDA.W  #SE_TagBytes,A1                 | point to DCD tag buffer area
        MOVE.L  (BufTgFNum).w,(A1)+             | copy tag data from system globals
        MOVE.L  (BufTgFFlg).w,(A1)+             | file flags
        MOVE.L  (BufTgDate).w,(A1)+             | date
        MOVE.L  (BufTgHD20).w,(A1)+             | HD20 tag extension bytes
        MOVE.L  (BufTgHD20_1).w,(A1)+           | HD20 tag extension bytes (cont)
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_SKIP:
        ADDQ.W  #0x6,D6                         | add 6 overhead bytes to send count
        DIVU    #0x7,D6                         | number of 7-byte groups (rounded up)
        ANDI    #0x7F,D6                        | mask to 7 bits
        ADDQ.W  #0x6,D7                         | add 6 overhead bytes to receive count
        DIVU    #0x7,D7                         | number of 7-byte groups (rounded up)
        ANDI    #0x7F,D7                        | mask to 7 bits
        MOVEQ.L #0x0,D4                         | D4 = 0: total blocks transferred
        BRA.B   SONY_SENDCMD_LOOP               | enter command send loop
SONY_SENDCMD_NEXT:
        TST.B   D1                              | read command?
        BEQ.B   SONY_SENDCMD_EXIT               | yes -> all blocks done, return
        ORI.B   #0x40,SE_DCDCmd(A1)             | set continuation bit in command
        MOVE.B  D3,SE_SeqNum(A1)                | SeqNum: store remaining block count
        ADDQ.L  #0x1,SE_TagBytes+4(A1)          | next file block number in the tags (flags/block long at +$1DA)
        MOVE.W  #tNextChk,SE_ChkTime(A1)        | ChkTime = 7: check every 700 us
        MOVE.W  #tNextMax,SE_MaxTime(A1)        | MaxTime = 10000 checks: 7 s (SonyEqu.a)
SONY_SENDCMD_LOOP:
        CMPI.B  #0x3,D1                         | status command?
        BGE.B   SONY_SENDCMD_OK                 | yes -> no tag copy needed
        TST.B   D1                              | read command?
        BEQ.B   SONY_SENDCMD_OK                 | yes -> no tag copy (tags in recv)
        MOVE.L  A5,D0                           | TagBufPtr: external tag buffer?
        BEQ.B   SONY_SENDCMD_OK                 | no -> use default tags
        ADDA.W  #SE_TagBytes,A1                 | point to DCD tag buffer area
        MOVE.L  (A5)+,(A1)+                     | copy 12 tag bytes from user buffer
        MOVE.L  (A5)+,(A1)+                     | tag bytes 5-8
        MOVE.L  (A5)+,(A1)+                     | tag bytes 9-12
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_OK:
        BSR.W   Sony_DCDSendPacket              | send DCD packet (serialize + transmit)
        BNE.W   SONY_SENDCMD_ERR                | send error -> set error status
SONY_SENDCMD_EXIT:
        RTS                                     | return from SONY_SENDCMD_EXIT

| -------------------------------------------------------------------------
| DCDRcvResponse -- receive the HD20's response packet (DCDRcvPacket) and
| check it: response byte = command + $80, sequence number, status; copy
| the tags of a read block and count it. For a write the next block is
| sent from here (SendCmd). BEQ: more blocks follow; BNE: done (D0 = 0)
| or error (D0 = 1, LastStatus/LastResult set).
| -------------------------------------------------------------------------
Sony_DCDRcvResponse:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address
        LEA.L   q6L(A0),A3                      | A3 = q6L: the read data register (L7 = 0, motor on)
        MOVE.B  SE_DCDCmd(A1),D1                | D1 = DCD command byte
        ANDI.B  #0x3F,D1                        | mask to base command (strip flags)
        BSR.W   Sony_DCDRcvPacket               | receive response packet from DCD
        BNE.W   SONY_SENDCMD_ERR                | receive error -> set error status
        MOVE.L  SE_Response(A1),D0              | D0 = command + response bytes
        MOVE.B  #InvalidResp,D0                 | D0.lo = InvalidResp error code
        SUBI.B  #0x80,SE_Response(A1)           | subtract $80: check Response = Cmd+$80
        CMP.B   SE_Response(A1),D1              | response matches expected?
        BNE.B   SONY_SENDCMD_ERR                | no -> invalid response error
        CMPI.B  #0x3,D1                         | status command?
        BGE.B   SONY_SENDCMD_CHKSTATUS          | yes -> skip sequence check
        MOVE.B  #SqncNumErr,D0                  | D0 = SqncNumErr error code
        CMP.B   SE_SeqNum(A1),D3                | sequence number matches?
        BEQ.B   SONY_SENDCMD_OK_2               | yes -> response validated
        SWAP    D0                              | pack error info into D0.hi
        MOVE.B  D3,D0                           | store expected seq# in D0.lo
        SWAP    D0                              | restore: D0.hi = {err, expected}
        ROR.L   #0x8,D0                         | rotate to pack received seq#
        MOVE.B  SE_SeqNum(A1),D0                | insert actual seq# received
        ROL.L   #0x8,D0                         | restore byte order
        BRA.B   SONY_SENDCMD_ERR                | sequence mismatch -> error
SONY_SENDCMD_OK_2:
        TST.B   D1                              | read command?
        BNE.B   SONY_SENDCMD_CHKSTATUS          | no -> skip tag extraction
        MOVE.L  A5,D0                           | TagBufPtr: external tag buffer?
        BEQ.B   SONY_SENDCMD_NO_2               | no -> copy to system globals
        ADDA.W  #SE_TagBytes,A1                 | point to DCD tag buffer
        MOVE.L  (A1)+,(A5)+                     | copy 12 received tag bytes to user
        MOVE.L  (A1)+,(A5)+                     | tag bytes 5-8
        MOVE.L  (A1)+,(A5)+                     | tag bytes 9-12
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_NO_2:
        ADDA.W  #SE_TagBytes,A1                 | point to DCD tag buffer
        MOVE.L  (A1)+,(BufTgFNum).w             | copy tag: file number
        MOVE.L  (A1)+,(BufTgFFlg).w             | copy tag: file flags
        MOVE.L  (A1)+,(BufTgDate).w             | copy tag: date
        MOVE.L  (A1)+,(BufTgHD20).w             | copy tag: HD20 extension
        MOVE.L  (A1)+,(BufTgHD20_1).w           | copy tag: HD20 extension (cont)
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_CHKSTATUS:
        MOVEQ.L #nonZerStat,D2                  | D2 = 1: nonZerStat result type
        MOVE.L  SE_Status(A1),D0                | D0 = DCD status from response
        BTST    #opFailed,D0                    | opFailed bit set?
        BNE.B   SONY_SENDCMD_ERR_2              | yes -> operation failed
        CMPI.B  #0xA,SE_Status(A1)              | status = $0A (disk changed)?
        BEQ.B   SONY_SENDCMD_ERR_2              | yes -> report as error
        ADDA.L  SE_BufSize(A1),A4               | advance data buffer by BufSize
        ADDQ.L  #0x1,D4                         | count blocks transferred
        SUBQ.B  #0x1,D3                         | decrement blocks remaining
        BNE.W   SONY_SENDCMD_NEXT               | more blocks -> send next command
        MOVEQ.L #0x0,D0                         | noErr: all blocks transferred
SONY_SENDCMD_RET:
        ANDI    #-0x5,SR                        | clear Z: BNE = finished
        RTS                                     | return with D0 = result
SONY_SENDCMD_ERR:
        MOVEQ.L #comErr,D2                      | D2 = 2: comErr result type
        ROR.L   #0x8,D0                         | pack error code into status word
SONY_SENDCMD_ERR_2:
        MOVE.L  D0,SE_LastStatus(A1)            | LastStatus: save DCD error status
        MOVE.B  D2,SE_LastResult(A1)            | LastResult: save result type
        MOVEQ.L #0x1,D0                         | D0 = 1: indicate error
        BRA.B   SONY_SENDCMD_RET                | return via common exit

| -------------------------------------------------------------------------
| DCDRcvPacket -- receive a packet from the HD20 into the command area
| (+$1D0) and the data buffer (A4): wait for $AA, then groups of 8 bytes
| (7 bytes with bit 7 set plus their collected low bits), honouring the
| HD20's holdoff marker ($BF) and the SCC; check the sum (must be 0).
|   D0 (out) -- 0 or RdHsHi ($20), RdSyncTO ($21), RdGroupTO ($22),
|               RdHoffSyncTO ($24), RdHsHiTO ($25), RdChksumErr ($26)
| -------------------------------------------------------------------------
Sony_DCDRcvPacket:
        MOVE    SR,-(SP)                        | save SR
        MOVEM.L D1-D7/A1/A4-A6,-(SP)            | save all registers
        ADDA.W  #SE_DCDCmd,A1                   | A1 -> DCD command area in SonyVars
        MOVEQ.L #0x0,D5                         | D5 = running checksum
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVEQ.L #RdHsHi,D0                      | D0 = RdHsHi error code
        TST.B   q7L(A0)                         | Q7L: read status, HSHK in bit 7
        BMI.W   SONY_RCVPKT_EXIT                | HSHK high -> error (should be low)
        MOVEM.L (SCCRd).w,A5-A6                 | A5 = SCCRd, A6 = SCCWr
        ADDQ.W  #0x2,A5                         | A5 = SCC channel A control
        ADDQ.W  #0x2,A6                         | A6 = SCC channel A control (write)
        ORI     #0x700,SR                       | raise IPL to 7 (disable all ints)
        TST.B   ph0H(A0)                        | CA0 high: ready to receive
        TST.B   ph1L(A0)                        | CA1 low
        TST.B   (A3)                            | q6L: L6 = 0, read mode; a stale data byte is read
        MOVEQ.L #RdSyncTO,D0                    | D0 = RdSyncTO error code
        MOVEQ.L #0x1,D6                         | D6 = $10000: sync timeout counter
        SWAP    D6                              | D6.hi = 1 -> D6 = $10000
SONY_RCVPKT_SYNC:
        SUBQ.L  #0x1,D6                         | decrement sync search timeout
        BEQ.W   SONY_RCVPKT_EXIT                | timeout -> RdSyncTO error
        CMPI.B  #0xAA,(A3)                      | received sync byte ($AA)?
        BNE.B   SONY_RCVPKT_SYNC                | no -> keep searching
        MOVE    #0x50,D6                        | D6 = 80: group receive timeout
SONY_RCVPKT_GET1:
        MOVE.B  (A3),D1                         | read first byte of group (cmd byte)
        DBMI    D6,SONY_RCVPKT_GET1             | poll until valid (bit 7 set)
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> RdGroupTO error
        CMPI.B  #0xBF,D1                        | holdoff marker byte?
        BNE.B   SONY_RCVPKT_NOTSHORT            | no -> normal data group
        MOVEQ.L #0x6,D7                         | D7 = 6: holdoff groups counter
        SWAP    D7                              | save in D7.hi
SONY_RCVPKT_NOTSHORT:
        SWAP    D1                              | save D1 in high word
SONY_RCVPKT_GET2:
        MOVE.B  (A3),D1                         | read byte 2 of group
        DBMI    D6,SONY_RCVPKT_GET2             | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D1                              | restore: D1 = {byte1, byte2}
SONY_RCVPKT_GET3:
        MOVE.B  (A3),D2                         | read byte 3 of group
        DBMI    D6,SONY_RCVPKT_GET3             | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D2                              | save in high word
SONY_RCVPKT_GET4:
        MOVE.B  (A3),D2                         | read byte 4 of group
        DBMI    D6,SONY_RCVPKT_GET4             | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D2                              | D2 = {byte3, byte4}
SONY_RCVPKT_GET5:
        MOVE.B  (A3),D3                         | read byte 5 of group
        DBMI    D6,SONY_RCVPKT_GET5             | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D3                              | save in high word
SONY_RCVPKT_GET6:
        MOVE.B  (A3),D3                         | read byte 6 of group
        DBMI    D6,SONY_RCVPKT_GET6             | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D3                              | D3 = {byte5, byte6}
SONY_RCVPKT_GET7:
        MOVE.B  (A3),D4                         | read byte 7 of the group (data byte 7)
        DBMI    D6,SONY_RCVPKT_GET7             | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D4                              | save in high word
SONY_RCVPKT_GET8:
        MOVE.B  (A3),D4                         | read byte 8: the low bits of data bytes 1-7
        DBMI    D6,SONY_RCVPKT_GET8             | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        DBF     D7,SONY_RCVPKT_DECODE           | decrement group counter, decode
        BRA.W   SONY_RCVPKT_LAST                | last group -> decode final bytes
| Called by: SONY_RCVPKT_GET1, SONY_RCVPKT_GET2, SONY_RCVPKT_GET3, SONY_RCVPKT_GET4, SONY_RCVPKT_GET5 (and 8 more)
SONY_RCVPKT_GROUPTO:
        MOVEQ.L #RdGroupTO,D0                   | RdGroupTO: group receive timeout
        BRA.W   SONY_RCVPKT_EXIT                | exit with error
SONY_RCVPKT_DECODE:
        MOVEQ.L #0x3,D6                         | D6.hi = 3: switch to data after 3 groups
        SWAP    D6                              | save in high word
        MOVE    #0x50,D6                        | D6.lo = 80: byte receive timeout
SONY_RCVPKT_GROUP:
        LSR.B   #0x1,D4                         | low bit of byte 1 (from byte 8) into X
        ADDX.B  D1,D1                           | byte 1 = received byte * 2 + low bit
        ADD.B   D1,D5                           | accumulate into checksum
        MOVE.B  D1,(A1)+                        | store decoded byte 1
SONY_RCVPKT_NEXT1:
        MOVE.B  (A3),D1                         | read next group byte 1
        DBMI    D6,SONY_RCVPKT_NEXT1            | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D1                              | save in high word
        MOVE.B  #0x3,(A6)                       | SCC channel A: select RR3 (interrupt pending) for the next read
        LSR.B   #0x1,D4                         | next low bit into X
        ADDX.B  D1,D1                           | byte 2 = received byte * 2 + low bit
        ADD.B   D1,D5                           | accumulate checksum
        MOVE.B  D1,(A1)+                        | store decoded byte 2
SONY_RCVPKT_NEXT2:
        MOVE.B  (A3),D1                         | read next group byte 2
        DBMI    D6,SONY_RCVPKT_NEXT2            | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D1                              | save in high word
        TST     D7                              | holdoff groups remaining?
        BEQ.B   SONY_RCVPKT_HOLDCHK             | no -> skip SCC check
        TST.B   (A5)                            | read RR3: SCC interrupt pending?
SONY_RCVPKT_HOLDCHK:
        SNE.B   D0                              | D0 = $FF if SCC needs service
        LSR.B   #0x1,D4                         | next low bit into X
        ADDX.B  D2,D2                           | byte 3 = received byte * 2 + low bit
        ADD.B   D2,D5                           | accumulate checksum
        MOVE.B  D2,(A1)+                        | store decoded byte 3
SONY_RCVPKT_NEXT3:
        MOVE.B  (A3),D2                         | read next group byte 3
        DBMI    D6,SONY_RCVPKT_NEXT3            | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D2                              | save in high word
        LSR.B   #0x1,D4                         | next low bit into X
        ADDX.B  D2,D2                           | byte 4 = received byte * 2 + low bit
        ADD.B   D2,D5                           | accumulate checksum
        MOVE.B  D2,(A1)+                        | store decoded byte 4
SONY_RCVPKT_NEXT4:
        MOVE.B  (A3),D2                         | read next group byte 4
        DBMI    D6,SONY_RCVPKT_NEXT4            | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D2                              | save in high word
        TST.B   D0                              | SCC needs service?
        BEQ.B   SONY_RCVPKT_BYTE5               | no -> skip
        TST.B   (A0)                            | CA0 low: ask the HD20 to hold off after this group
SONY_RCVPKT_BYTE5:
        LSR.B   #0x1,D4                         | next low bit into X
        ADDX.B  D3,D3                           | byte 5 = received byte * 2 + low bit
        ADD.B   D3,D5                           | accumulate checksum
        MOVE.B  D3,(A1)+                        | store decoded byte 5
SONY_RCVPKT_NEXT5:
        MOVE.B  (A3),D3                         | read next group byte 5
        DBMI    D6,SONY_RCVPKT_NEXT5            | poll until valid
SONY_RCVPKT_GROUPTO2:
        BPL.B   SONY_RCVPKT_GROUPTO             | timeout -> error
        SWAP    D3                              | save in high word
        SWAP    D6                              | check header/data group switch
        DBF     D6,SONY_RCVPKT_BYTE6            | decrement: switch to data after 3
        MOVE.L  A4,A1                           | switch dest from cmd area to data buf
SONY_RCVPKT_BYTE6:
        SWAP    D6                              | restore receive timeout
        LSR.B   #0x1,D4                         | next low bit into X
        ADDX.B  D3,D3                           | byte 6 = received byte * 2 + low bit
        ADD.B   D3,D5                           | accumulate checksum
        MOVE.B  D3,(A1)+                        | store decoded byte 6
SONY_RCVPKT_NEXT6:
        MOVE.B  (A3),D3                         | read next group byte 6
        DBMI    D6,SONY_RCVPKT_NEXT6            | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO2            | timeout -> error
        SWAP    D3                              | save in high word
        LSR.B   #0x1,D4                         | low bit of byte 7 into X
        SWAP    D4                              | D4.lo = byte 7
        ADDX.B  D4,D4                           | byte 7 = received byte * 2 + low bit
        ADD.B   D4,D5                           | accumulate checksum
        MOVE.B  D4,(A1)+                        | store decoded byte 7
SONY_RCVPKT_NEXT7:
        MOVE.B  (A3),D4                         | read byte 7 of the next group
        DBMI    D6,SONY_RCVPKT_NEXT7            | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO2            | timeout -> error
        SWAP    D4                              | D4.hi = byte 7 of the next group
        MOVE    #0x50,D6                        | reset receive timeout to 80
SONY_RCVPKT_NEXT8:
        MOVE.B  (A3),D4                         | read byte 8 of the next group (low bits)
        DBMI    D6,SONY_RCVPKT_NEXT8            | poll until valid
        BPL.B   SONY_RCVPKT_GROUPTO2            | timeout -> error
        TST.B   D0                              | SCC holdoff pending?
        DBNE    D7,SONY_RCVPKT_GROUP            | no -> decode next group
        BEQ.B   SONY_RCVPKT_LAST                | all groups done -> finalize
        TST.B   (A5)                            | service SCC channel A
        ANDI    #-0x701,SR                      | restore IPL (enable ints briefly)
        SUBQ.W  #0x1,D7                         | decrement holdoff group counter
        MOVEQ.L #0x10,D0                        | D0 = 16: brief delay loop
SONY_SENDCMD_LOOP_21:
        DBF     D0,SONY_SENDCMD_LOOP_21         | spin delay for SCC service
        ORI     #0x700,SR                       | raise IPL back to 7
        TST.B   ph0H(A0)                        | CA0 high again: continue
        TST.B   (A3)                            | read the data register (discard a stale byte)
        CLR     D0                              | D0 = $10000: sync search counter
SONY_RCVPKT_RESYNC:
        SUBQ.W  #0x1,D0                         | decrement sync timeout
        BEQ.B   SONY_RCVPKT_HOFFTO              | timeout -> holdoff sync error
        CMPI.B  #0xAA,(A3)                      | re-sync: found $AA?
        BNE.B   SONY_RCVPKT_RESYNC              | no -> keep searching
        BRA.W   SONY_RCVPKT_GROUP               | synced -> resume group receive
SONY_RCVPKT_HOFFTO:
        MOVEQ.L #RdHoffSyncTO,D0                | RdHoffSyncTO: holdoff re-sync timeout
        BRA.B   SONY_RCVPKT_EXIT                | exit with error
SONY_RCVPKT_LAST:
        SWAP    D7                              | D7 = remaining bytes in final group
        LSR.B   #0x1,D4                         | low bit of byte 1 into X
        ADDX.B  D1,D1                           | reconstruct byte 1
        ADD.B   D1,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | one fewer byte remaining
        BMI.B   SONY_RCVPKT_LAST2               | negative -> no more bytes to store
        MOVE.B  D1,(A1)+                        | store decoded byte 1
SONY_RCVPKT_LAST2:
        SWAP    D1                              | access byte 2 from high word
        LSR.B   #0x1,D4                         | low bit of byte 2 into X
        ADDX.B  D1,D1                           | reconstruct byte 2
        ADD.B   D1,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_RCVPKT_LAST3               | no more -> skip store
        MOVE.B  D1,(A1)+                        | store decoded byte 2
SONY_RCVPKT_LAST3:
        LSR.B   #0x1,D4                         | low bit of byte 3 into X
        ADDX.B  D2,D2                           | reconstruct byte 3
        ADD.B   D2,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_RCVPKT_LAST4               | no more -> skip store
        MOVE.B  D2,(A1)+                        | store decoded byte 3
SONY_RCVPKT_LAST4:
        SWAP    D2                              | access byte 4 from high word
        LSR.B   #0x1,D4                         | low bit of byte 4 into X
        ADDX.B  D2,D2                           | reconstruct byte 4
        ADD.B   D2,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_RCVPKT_LAST5               | no more -> skip store
        MOVE.B  D2,(A1)+                        | store decoded byte 4
SONY_RCVPKT_LAST5:
        LSR.B   #0x1,D4                         | low bit of byte 5 into X
        ADDX.B  D3,D3                           | reconstruct byte 5
        ADD.B   D3,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_RCVPKT_LAST6               | no more -> skip store
        MOVE.B  D3,(A1)+                        | store decoded byte 5
SONY_RCVPKT_LAST6:
        SWAP    D3                              | access byte 6 from high word
        LSR.B   #0x1,D4                         | low bit of byte 6 into X
        ADDX.B  D3,D3                           | reconstruct byte 6
        ADD.B   D3,D5                           | accumulate checksum
        SUBQ.W  #0x1,D7                         | decrement remaining
        BMI.B   SONY_RCVPKT_LAST7               | no more -> skip store
        MOVE.B  D3,(A1)+                        | store decoded byte 6
SONY_RCVPKT_LAST7:
        LSR.B   #0x1,D4                         | low bit of byte 7 into X
        SWAP    D4                              | access byte 7
        ADDX.B  D4,D4                           | reconstruct byte 7
        ADD.B   D4,D5                           | accumulate final checksum byte
        TST.B   ph1H(A0)                        | CA1 high: end of the packet
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVEQ.L #RdHsHiTO,D0                    | D0 = RdHsHiTO: assume HSHK error
        TST.B   q7L(A0)                         | Q7L: read status, HSHK high again?
        BPL.B   SONY_RCVPKT_EXIT                | HSHK still low -> RdHsHiTO
        MOVE.B  D5,D0                           | D0 = checksum (0 if the packet is correct)
        BEQ.B   SONY_RCVPKT_EXIT                | correct -> D0 = 0
        MOVEQ.L #RdChksumErr,D0                 | RdChksumErr ($26): checksum error
| Called by: SONY_RCVPKT_LAST7, Sony_DCDRcvPacket, SONY_RCVPKT_SYNC, SONY_RCVPKT_GROUPTO, SONY_RCVPKT_HOFFTO
SONY_RCVPKT_EXIT:
        TST.B   (A5)                            | read SCC channel A: resets the SCC register pointer
        TST.B   ph1H(A0)                        | CA1 high
        TST.B   (A0)                            | CA0 low
        MOVEM.L (SP)+,D1-D7/A1/A4-A6            | restore registers
        MOVE    (SP)+,SR                        | restore SR
        TST.B   D0                              | CCR = result (restoring SR also restored the old CCR)
        RTS                                     | return (BEQ = ok)

| -------------------------------------------------------------------------
| DCDSendPacket -- send a command packet to the HD20
|   A0 (in) -- IWM base, A3 (in) -- IWM q6L (write-handshake register
|              once in the write state)
|   A1 (in) -- SonyVars; the packet starts with the command block at
|              DCDCmd (+$1D0), then data from A4
|   D6/D7 (in) -- number of 7-byte groups to send / to receive
|   D0 (out) -- 0, or an HD20 error code: WrtHsLw ($10), WrtHSLwTO ($11),
|               WrtHSHighTO ($13)
| Packet: $AA sync, $80+groups to send+1, $80+groups to receive+1, then
| groups of 8 bytes for every 7 data bytes: a byte collecting the low
| bits of the 7 bytes, then the 7 bytes shifted right by one, every byte
| with bit 7 set; the last data byte is the checksum (sum = 0), followed
| by two $00 bytes. When an SCC interrupt is pending after a group, the
| driver sends $00, opens interrupts briefly and restarts with $AA.
| -------------------------------------------------------------------------
Sony_DCDSendPacket:
        MOVE    SR,-(SP)                        | save the interrupt level
        MOVEM.L D1-D7/A1/A4-A6,-(SP)            | save registers
        ADDA.W  #SE_DCDCmd,A1                   | A1 -> DCDCmd: command block
        MOVEM.L (SCCRd).w,A5-A6                 | A5 = SCCRd, A6 = SCCWr
        ADDQ.W  #0x2,A5                         | A5 -> SCC channel A control (read)
        ADDQ.W  #0x2,A6                         | A6 -> SCC channel A control (write)
        MOVE.B  D1,D4                           | command byte
        SWAP    D4                              | (keep it in the high word)
        SWAP    D6                              | (D6.hi = groups to send for now)
        MOVE    D7,D6                           | D6.lo = groups to receive
        SWAP    D6                              | D6.hi = groups to receive, D6.lo = groups to send
        MOVEQ.L #0x0,D5                         | checksum = 0
        ST.B    D4                              | D4.lo = $FF: low-bit byte of the first group
        MOVE.B  (A1)+,D1                        | 1st byte of the command block
        ADD.B   D1,D5                           | add it to the checksum
        ROXR.B  #0x1,D1                         | low bit -> X, shifted right
        ORI.B   #0x80,D1                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit in D4
        SWAP    D1                              | (keep it)
        MOVE.B  (A1)+,D1                        | 2nd byte
        ADD.B   D1,D5                           | checksum
        ROXR.B  #0x1,D1                         | low bit -> X
        ORI.B   #0x80,D1                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D1                              | (keep it)
        MOVE.B  (A1)+,D2                        | 3rd byte
        ADD.B   D2,D5                           | checksum
        ROXR.B  #0x1,D2                         | low bit -> X
        ORI.B   #0x80,D2                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D2                              | (keep it)
        MOVE.B  (A1)+,D2                        | 4th byte
        ADD.B   D2,D5                           | checksum
        ROXR.B  #0x1,D2                         | low bit -> X
        ORI.B   #0x80,D2                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D2                              | (keep it)
        MOVE.B  (A1)+,D3                        | 5th byte
        ADD.B   D3,D5                           | checksum
        ROXR.B  #0x1,D3                         | low bit -> X
        ORI.B   #0x80,D3                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D3                              | (keep it)
        MOVE.B  (A1)+,D3                        | 6th byte
        ADD.B   D3,D5                           | checksum
        ROXR.B  #0x1,D3                         | low bit -> X
        ORI.B   #0x80,D3                        | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D3                              | (keep it)
        SWAP    D4                              | D4.lo = command byte, D4.hi = low-bit byte
        TST.B   q6H(A0)                         | Q6H: L6 = 1, status register selected
        MOVEQ.L #WrtHsLw,D0                     | WrtHsLw ($10): HSHK must be high before we start
        TST.B   q7L(A0)                         | Q7L: HSHK (status bit 7)
        BPL.W   SONY_SENDPKT_EXIT               | low -> error
        TST.B   ph0H(A0)                        | CA0 high: request to send
        MOVEQ.L #WrtHSLwTO,D0                   | WrtHSLwTO ($11)
        MOVEQ.L #0x14,D7                        | $14 <<
        SWAP    D7                              | 16 = $140000: timeout count
SONY_SENDPKT_WAITLOW:
        SUBQ.L  #0x1,D7                         | count
        BEQ.W   SONY_SENDPKT_EXIT               | timeout -> error
        TST.B   q7L(A0)                         | HSHK
        BMI.B   SONY_SENDPKT_WAITLOW            | still high -> wait
        TST.B   ph1L(A0)                        | CA1 low
        LEA.L   q6H(A0),A0                      | A0 -> IWM q6H (until MOVE.L (IWM).w,A0 below)
        ORI     #0x700,SR                       | no interrupts
        MOVEQ.L #0x2,D7                         | 2 more groups from the command block,
        CMPI.B  #0x4,D4                         | for commands 0-3 (read, write, status)
        BLT.B   SONY_SENDPKT_SETUP              | yes ->
        MOVEQ.L #-0x1,D7                        | others: everything from A4
        MOVE.L  A4,A1                           | A1 = data
SONY_SENDPKT_SETUP:
        MOVEQ.L #0x4,D0                         | short delay loop
SONY_SENDCMD_LOOP_22:
        DBF     D0,SONY_SENDCMD_LOOP_22         | (5 times)
        MOVE.L  D6,D0                           | D0 = receive/send counts
        ADDI.L  #0x810081,D0                    | + $81 each: count + 1 with bit 7 set
        MOVE.B  #0xAA,q7H-q6H(A0)               | Q7H: write state, first byte $AA (sync)
SONY_SENDPKT_COUNT1:
        TST.B   (A3)                            | handshake: ready for a byte?
        BPL.B   SONY_SENDPKT_COUNT1             | no -> wait
        MOVE.B  D0,(A0)                         | send $81 + groups to send
        SWAP    D0                              | D0.lo = $81 + groups to receive
SONY_SENDPKT_COUNT2:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_COUNT2             | no -> wait
        MOVE.B  D0,(A0)                         | send $81 + groups to receive
        MOVEQ.L #-0x80,D0                       | D0 = $80: bit 7 of every encoded byte
        BRA.W   SONY_SENDCMD_CONT_11            | start the group loop
| group loop: send the 8 bytes of the current group while encoding the
| next 7 bytes from (A1)
SONY_SENDPKT_GROUP:
        MOVE.B  (A1)+,D4                        | next byte
        ADD.B   D4,D5                           | checksum
        ROXR.B  #0x1,D4                         | low bit -> X
        OR.B    D0,D4                           | bit 7 set
        SWAP    D4                              | D4.lo = low-bit byte of the current group
        ROXR.B  #0x2,D4                         | make room for the collected bits
SONY_SENDPKT_PUT0:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PUT0               | no -> wait
        MOVE.B  D4,(A0)                         | send the low-bit byte
        ST.B    D4                              | start the next low-bit byte
        MOVE.B  #0x3,(A6)                       | SCC channel A: select RR3 (interrupt pending)
SONY_SENDPKT_PUT1:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PUT1               | no -> wait
        MOVE.B  D1,(A0)                         | send data byte 1
        MOVE.B  (A1)+,D1                        | next byte
        ADD.B   D1,D5                           | checksum
        ROXR.B  #0x1,D1                         | low bit -> X
        OR.B    D0,D1                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D1                              | (keep it)
        TST.B   (A5)                            | read RR3: SCC interrupt pending?
        BEQ.B   SONY_SENDPKT_PUT2               | no ->
        BSET    #0x1F,D6                        | yes: D6 bit 31 = hold off after this group
SONY_SENDPKT_PUT2:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PUT2               | no -> wait
        MOVE.B  D1,(A0)                         | send data byte 2
        MOVE.B  (A1)+,D1                        | next byte
        ADD.B   D1,D5                           | checksum
        ROXR.B  #0x1,D1                         | low bit -> X
        OR.B    D0,D1                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D1                              | (keep it)
        TST     D6                              | more groups to send?
        BNE.B   SONY_SENDPKT_PUT3               | yes ->
        BCLR    #0x1F,D6                        | last group: no holdoff
SONY_SENDPKT_PUT3:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PUT3               | no -> wait
        MOVE.B  D2,(A0)                         | send data byte 3
        MOVE.B  (A1)+,D2                        | next byte
        ADD.B   D2,D5                           | checksum
        ROXR.B  #0x1,D2                         | low bit -> X
        OR.B    D0,D2                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D2                              | (keep it)
        BTST    #0x1F,D6                        | holdoff requested?
        BEQ.B   SONY_SENDPKT_PUT4               | no ->
        TST.B   ph0L-q6H(A0)                    | CA0 low: tell the HD20 we hold off after this group
SONY_SENDPKT_PUT4:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PUT4               | no -> wait
        MOVE.B  D2,(A0)                         | send data byte 4
        MOVE.B  (A1)+,D2                        | next byte
        ADD.B   D2,D5                           | checksum
        ROXR.B  #0x1,D2                         | low bit -> X
        OR.B    D0,D2                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D2                              | (keep it)
SONY_SENDPKT_PUT5:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PUT5               | no -> wait
        MOVE.B  D3,(A0)                         | send data byte 5
        MOVE.B  (A1)+,D3                        | next byte
        ADD.B   D3,D5                           | checksum
        ROXR.B  #0x1,D3                         | low bit -> X
        OR.B    D0,D3                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D3                              | (keep it)
        DBF     D7,SONY_SENDPKT_PUT6            | command block groups left?
        MOVE.L  A4,A1                           | no -> continue with the data
SONY_SENDPKT_PUT6:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PUT6               | no -> wait
        MOVE.B  D3,(A0)                         | send data byte 6
        MOVE.B  (A1)+,D3                        | next byte
        ADD.B   D3,D5                           | checksum
        ROXR.B  #0x1,D3                         | low bit -> X
        OR.B    D0,D3                           | bit 7 set
        ROXR.B  #0x1,D4                         | collect the low bit
        SWAP    D3                              | (keep it)
        SWAP    D4                              | D4.lo = data byte 7
SONY_SENDPKT_PUT7:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PUT7               | no -> wait
        MOVE.B  D4,(A0)                         | send data byte 7
        BCLR    #0x1F,D6                        | holdoff requested?
        BNE.B   SONY_SENDPKT_HOLDOFF            | yes ->
SONY_SENDCMD_CONT_11:
        DBF     D6,SONY_SENDPKT_GROUP           | next group
        BRA.B   SONY_SENDPKT_LAST               | all groups sent -> final group
SONY_SENDPKT_HOLDOFF:
| holdoff: let the SCC interrupt be serviced, then restart with $AA
        CLR.B   D0                              | D0 = $00
SONY_SENDPKT_HOLD0:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_HOLD0              | no -> wait
        MOVE.B  D0,(A0)                         | send $00
        ANDI    #-0x701,SR                      | open interrupts
        MOVE    #0x10,D0                        | short delay
SONY_SENDCMD_LOOP_25:
        DBF     D0,SONY_SENDCMD_LOOP_25         | (17 times)
        SUBQ.W  #0x1,D6                         | count this group (its DBF is skipped)
        TST.B   q7L-q6H(A0)                     | Q7L: write state off
        TST.B   q6L-q6H(A0)                     | Q6L
        TST.B   (A0)                            | Q6H (A0 = q6H): status register selected
        TST.B   ph0H-q6H(A0)                    | CA0 high: continue
        MOVE    #0x10,D0                        | short delay
SONY_SENDCMD_LOOP_26:
        DBF     D0,SONY_SENDCMD_LOOP_26         | (17 times)
        MOVEQ.L #-0x80,D0                       | D0 = $80 again
        ORI     #0x700,SR                       | no interrupts
        MOVE.B  #0xAA,q7H-q6H(A0)               | Q7H: write state again, $AA (sync)
        BRA.W   SONY_SENDPKT_GROUP              | continue with the next group
| final group: the checksum makes the sum of all data bytes zero
SONY_SENDPKT_LAST:
        NEG.B   D5                              | checksum = -sum
        ROXR.B  #0x1,D5                         | low bit -> X
        OR.B    D0,D5                           | bit 7 set
        SWAP    D4                              | low-bit byte of the final group
        ROXR.B  #0x2,D4                         | make room for the collected bits
SONY_SENDPKT_LPUT0:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_LPUT0              | no -> wait
        MOVE.B  D4,(A0)                         | send the low-bit byte
SONY_SENDPKT_LPUT1:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_LPUT1              | no -> wait
        MOVE.B  D1,(A0)                         | send data byte 1
        SWAP    D1                              | data bytes 2, 4, 6 are in the high words
SONY_SENDPKT_LPUT2:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_LPUT2              | no -> wait
        MOVE.B  D1,(A0)                         | send data byte 2
SONY_SENDPKT_LPUT3:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_LPUT3              | no -> wait
        MOVE.B  D2,(A0)                         | send data byte 3
        SWAP    D2                              | next
SONY_SENDPKT_LPUT4:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_LPUT4              | no -> wait
        MOVE.B  D2,(A0)                         | send data byte 4
SONY_SENDPKT_LPUT5:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_LPUT5              | no -> wait
        MOVE.B  D3,(A0)                         | send data byte 5
        SWAP    D3                              | next
SONY_SENDPKT_LPUT6:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_LPUT6              | no -> wait
        MOVE.B  D3,(A0)                         | send data byte 6
SONY_SENDPKT_CKSUM:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_CKSUM              | no -> wait
        MOVE.B  D5,(A0)                         | send the checksum
SONY_SENDPKT_PAD1:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PAD1               | no -> wait
        MOVEQ.L #0x0,D0                         | then two $00 bytes
        MOVE.B  D0,(A0)                         | send $00
SONY_SENDPKT_PAD2:
        TST.B   (A3)                            | ready?
        BPL.B   SONY_SENDPKT_PAD2               | no -> wait
        MOVE.B  D0,(A0)                         | send $00
        MOVE.L  (IWM).w,A0                      | A0 = IWM base
        TST.B   ph1H(A0)                        | CA1 high: end of the packet
        MOVEQ.L #WrtHSHighTO,D0                 | WrtHSHighTO ($13)
        MOVEQ.L #-0x1,D7                        | timeout count
SONY_SENDPKT_WAITHIGH:
        SUBQ.W  #0x1,D7                         | count
        BEQ.B   SONY_SENDPKT_EXIT               | timeout -> error
        TST.B   q7L(A0)                         | Q7L: ends the write state; L6 = 1: status, HSHK in bit 7
        BPL.B   SONY_SENDPKT_WAITHIGH           | still low -> wait
        MOVEQ.L #0x0,D0                         | noErr
SONY_SENDPKT_EXIT:
        TST.B   ph1H(A0)                        | CA1 high
        TST.B   (A0)                            | CA0 low
        MOVEM.L (SP)+,D1-D7/A1/A4-A6            | restore registers
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST.B   D0                              | CCR = result (restoring SR also restored the old CCR)
        RTS                                     | return (BEQ = ok)

| -------------------------------------------------------------------------
| DCDReset -- hard-reset the HD20 (jump through the JDCDReset vector)
| -------------------------------------------------------------------------
E_Sony_DCDReset:
        MOVE.L  (JDCDReset).w,-(SP)             | push the JDCDReset vector
        RTS                                     | and jump through it
| jtDCDReset (JDCDReset vector) -- assert the reset line (register
| address 1, dcdReset) for 100 ms (tRstAssert), wait 2 s (tRstSettle),
| then poll the handshake every 10 ms (tRstChk) for at most 16 s
| (tRstMax). Returns D0 = 0 when the HD20 is ready, -1 on timeout.
Sony_DCDReset:
        MOVE.L  (SP)+,A3                        | A3 = return address
        BSR.W   SONY_SETIWMMODE                 | SetIWMMode
        BSR.W   Sony_DiskSelect                 | DiskSelect: select the HD20 (new on the SE)
        TST.B   ph2H(A0)                        | CA2 high
        TST.B   ph1L(A0)                        | CA1 low
        TST.B   (A0)                            | CA0 low: address 1 = dcdReset
        MOVE    #tRstAssert,D0                  | tRstAssert: 1000 * 100 us = 100 ms
        BSR.W   E_Sony_WakeUp                   | WakeUp
        TST.B   ph1H(A0)                        | CA1 high
        TST.B   ph2L(A0)                        | CA2 low: reset line released
        MOVE    #tRstSettle,D0                  | tRstSettle: 20000 * 100 us = 2 s
        BSR.W   E_Sony_WakeUp                   | WakeUp
        MOVE.W  #tRstChk,SE_ChkTime(A1)         | ChkTime (+$1F4) = tRstChk: check every 10 ms
        MOVE.W  #tRstMax,SE_MaxTime(A1)         | MaxTime (+$1F6) = tRstMax: 1600 checks = 16 s
SONY_DCDRESET_CONT:
        BSR.W   Sony_Sense                      | Sense: HD20 handshake line
        BMI.B   SONY_DCDRESET_SKIP              | HSHK high -> HD20 ready (idle)
        SUBQ.W  #0x1,SE_MaxTime(A1)             | MaxTime: count the check
        BMI.B   SONY_DCDRESET_SKIP_2            | time is up -> error
        MOVE.W  SE_ChkTime(A1),D0               | ChkTime
        BSR.W   E_Sony_WakeUp                   | WakeUp
        BRA.B   SONY_DCDRESET_CONT              | check again
SONY_DCDRESET_SKIP:
        MOVEQ.L #0x0,D0                         | noErr
        JMP     (A3)                            | return
SONY_DCDRESET_SKIP_2:
        TST.B   q6L(A0)                         | Q6L: back to read mode
        MOVEQ.L #-0x1,D0                        | timeout: D0 = -1
        JMP     (A3)                            | return
| completion of the status command issued for an HD20 icon call: return
| a pointer to the icon in the HD20 status data
SONY_DCD_ICONDONE:
        BNE.B   SONY_DCD_ICONEXIT               | status command failed -> return the error
        LEA.L   SE_DevIcon(A1),A2               | A2 -> DevIcon (+$224 = status buffer + 44)
        MOVE.L  (A1),A0                         | A0 = DCE
        MOVE.L  dCtlQHead(A0),A0                | A0 = current request (dCtlQHead)
        MOVE.L  A2,csParam(A0)                  | CSParam = pointer to the icon
SONY_DCD_ICONEXIT:
        BRA.W   SONY_DCDEXIT                    | complete the request (DCD exit)

| -------------------------------------------------------------------------
| HD20 icon call (csCodes 21 and 22 for drives 4-5): only if the HD20
| reports an icon (DevChIcon in its characteristics byte); the icon is
| part of the status data, so a status command is issued first.
| -------------------------------------------------------------------------
SONY_DCD_ICON:
        BTST    #DevChIcon,DriveChar(A1,D1.W)   | DriveChar (drive var +$1A) bit 2 = DevChIcon: icon available?
        BEQ.W   Sony_DiskCtlErr                 | no -> controlErr
        LEA.L   SONY_DCD_ICONDONE(PC),A0        | completion routine: return the icon pointer
        MOVE.L  A0,SE_StsRtnAddr(A1)            | StsRtnAddr (+$1CC)

| -------------------------------------------------------------------------
| DCDStatus, HD20 verify and format -- send a one-block HD20 command
| (3 = status, $1A = verify, $19 = format) and wait for its completion,
| with one retry after a checksum error and one hard reset. After a
| status command, continue at StsRtnAddr with D0/CCR = result; after the
| other commands complete the request. (MTN #272: formatting an HD20 sets
| all its blocks to zero; a failed format or verify returns controlErr.)
| -------------------------------------------------------------------------
Sony_DCDStatus:
        MOVEQ.L #0x3,D3                         | HD20 command 3: status
        BRA.B   SONY_DCD_COMMAND                | send it
SONY_DCD_VERIFY:
        MOVEQ.L #0x1A,D3                        | HD20 command $1A: verify
        BRA.B   SONY_DCD_COMMAND                | send it
SONY_DCD_FORMAT:
        MOVEQ.L #0x19,D3                        | HD20 command $19: format
SONY_DCD_COMMAND:
        MOVEA.L (IWM).w,A0                      | A0 = IWM base (new on the SE)
        TST.B   mtrOff(A0)                      | mtrOff: /ENBL2 off before selecting
SONY_DCD_COMMAND_1:
        BSR.W   Sony_DiskSelect                 | DiskSelect: select the HD20
        TST.B   (A0)                            | CA0 low
        TST.B   ph2L(A0)                        | CA2 low
        CLR.B   SE_DCDFlags(A1)                 | DCDFlags (+$1F3) = 0: no retry or reset yet
        MOVE.B  D3,SE_DCDCmd(A1)                | DCDCmd (+$1D0) = command
SONY_DCD_COMMAND_RETRY:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        ANDI.B  #0x3F,SE_DCDCmd(A1)             | DCDCmd: clear bits 6-7
        SUBA.L  A4,A4                           | A4 = 0: no data buffer
        SUBA.L  A5,A5                           | A5 = 0: no tag buffer
        MOVEQ.L #0x1,D3                         | one block
        MOVEQ.L #0x0,D6                         | nothing to send
        MOVEQ.L #0x0,D7                         | nothing to receive
        MOVE.W  #tFVChk,SE_ChkTime(A1)          | ChkTime = tFVChk: check every 10 ms
        MOVE.W  #tFVMax,SE_MaxTime(A1)          | MaxTime = tFVMax: 18000 checks = 3 minutes
        CMPI.B  #0x3,SE_DCDCmd(A1)              | status command?
        BNE.B   SONY_DCD_COMMAND_SEND           | no ->
        MOVE.L  #0x14C,D7                       | receive 332 bytes of status
        MOVE.W  #tStsChk,SE_ChkTime(A1)         | ChkTime = tStsChk: check every 1 ms
        MOVE.W  #tStsMax,SE_MaxTime(A1)         | MaxTime = tStsMax: 10000 checks = 10 s
        LEA.L   SE_StsBuffer(A1),A4             | A4 -> status buffer (+$1F8)
SONY_DCD_COMMAND_SEND:
        BSR.W   E_Sony_SendCmd                  | SendCmd: send the command
        BEQ.B   SONY_DCD_COMMAND_WAIT           | sent -> wait for the response
SONY_DCD_COMMAND_ERR:
        CMPI.B  #0x2,SE_LastStatus(A1)          | high byte of LastStatus (+$1EE) = 2? (LastResult = comErr would be +$1F2)
        BEQ.B   SONY_DCD_COMMAND_RESET          | yes -> reset
        BTST    #bChksum,SE_LastStatus(A1)      | LastStatus (+$1EE) bit 30 (bChksum): checksum error?
        BEQ.B   SONY_DCD_COMMAND_RESET          | no -> reset
        BSET    #retryonce,SE_DCDFlags(A1)      | DCDFlags bit 1 (retryonce) set before?
        BNE.B   SONY_DCD_COMMAND_RETRY          | yes -> send the command again
SONY_DCD_COMMAND_RESET:
        BSET    #resetonce,SE_DCDFlags(A1)      | DCDFlags bit 0 (resetonce) set before?
        BNE.B   SONY_DCD_COMMAND_FAIL           | yes -> give up
        BSR.W   E_Sony_DCDReset                 | DCDReset
        BNE.B   SONY_DCD_COMMAND_FAIL           | failed -> give up
        BRA.B   SONY_DCD_COMMAND_RETRY          | send the command again
SONY_DCD_COMMAND_WAIT:
        BSR.W   SONY_DCDWAITHSHK                | wait for the handshake (ChkTime/MaxTime)
        BMI.B   SONY_DCD_COMMAND_ERR            | timeout -> error handling
        BSR.W   Sony_DCDRcvResponse             | receive the response
        TST     D0                              | error?
        BNE.B   SONY_DCD_COMMAND_ERR            | yes -> error handling
        MOVEQ.L #0x0,D0                         | noErr
        BRA.B   SONY_DCD_COMMANDDONE            | done
SONY_DCD_COMMAND_FAIL:
        MOVEQ.L #-0x11,D0                       | controlErr: command failed
SONY_DCD_COMMANDDONE:
        ANDI.B  #0x3F,SE_DCDCmd(A1)             | DCDCmd: clear bits 6-7 (new on the SE)
SONY_DCD_COMMAND_END:
        CMPI.B  #0x3,SE_DCDCmd(A1)              | status command?
        BEQ.B   SONY_DCD_COMMAND_STS            | yes -> continue at StsRtnAddr
        BRA.W   SONY_DCDEXIT                    | else complete the request (DCD exit)
SONY_DCD_COMMAND_STS:
        MOVEA.L SE_StsRtnAddr(A1),A0            | A0 = StsRtnAddr (+$1CC)
        TST     D0                              | CCR = result
        JMP     (A0)                            | continue there

.endif
    ROM_RESOURCE_END DRVR_4                     | end of the data: pads to even, sets the sizes

