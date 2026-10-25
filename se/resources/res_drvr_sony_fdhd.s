| =========================================================================
| DRVR 4 .Sony -- the SuperDrive disk driver of the Macintosh SE FDHD (1989)
| =========================================================================
| ROM offsets +0x34678..+0x36C87: the 8-byte resource header (shared by
| both SE ROMs) and the 9736-byte driver body at +0x34680. The SE FDHD
| ROM ($B306E171) replaced the 1987 SE's 800K driver by this driver in the
| same slot; the MAC_SE build assembles the 1987 driver instead
| (resources/res_drvr_sony.s). The driver did not fit the
| slot: about 3.4 KB of it -- the GCR read, format and verify code and the
| icon calls -- live in the free space at the end of the ROM
| (extra/rom_tail.s, $3D000-$3DD51). Driver and tail reach each other
| only through two jump tables: SONY_TAIL_* here (to the tail's entry
| table at $43D000) and TAIL_DRV_* there (to SONY_DRVENT_* here).
|
| Hardware: the SWIM floppy controller (Sander-Wozniak Integrated
| Machine: the IWM and the ISM, the Integrated Sander Machine, in one
| chip; one register set is selected at a time, see the SWIM section
| further down) with Apple's SuperDrive (FDHD = Floppy Drive High
| Density), plus the older 400K and 800K drives. The SWIM runs from a
| 15.6672 MHz clock (FCLK; Apple's SonyMFM.a: "For a 15.6672MHz input
| clock (Mac SE, Mac II, etc)"), twice the 7/8 MHz that the IWM's mode
| bits assume, so the IWM gets the 2 us GCR bit cell in its slow mode
| (mode $17, SetIWMMode) and the ISM parameter RAM is set up for 2 us MFM
| bit cells (mParams). Formats: 400K/800K GCR disks (zoned speed, IWM
| registers, as before) and 720K/1440K MFM disks (IBM System 34 format,
| ISM registers; 1440K needs high-density media); PowerUp switches a
| SuperDrive between its GCR and MFM drive modes. A SuperDrive behind a
| plain IWM is treated as an 800K drive. Drives, as in the 1987 SE
| driver (physical numbers; DiskOpen hands out logical numbers and the
| table at driveXlat maps them back):
|   drive 1   lower internal floppy   (VIA port A bit 4 = 1, vDriveSel)
|   drive 2   upper internal floppy   (VIA port A bit 4 = 0)
|   drive 3   external floppy
|   drive 4,5 first and second HD20   (driver refNum -2, unit 1)
| Register conventions: A1 = SonyVars, D1 = offset of the current drive's
| variables, A0 = IWM/SWIM base, A2 = VIA base.
|
| Drive registers: selected by CA0-CA2 (phase lines 0-2) and SEL (VIA
| port A bit 5), address bits = CA1 CA0 SEL CA2 (Apple's SonyEqu.a
| names). A sense register is read on the SENSE line (IWM status register
| bit 7, ISM handshake register bit 3); a control register executes its
| command when LSTRB (phase line 3) is pulsed:
|   sense    2 DIPAdr     0 = disk in place    6 WrProtAdr 0 = write-protected
|            4 StepLAdr   0 = step under way   9 SidesAdr  1 = two-sided drive
|            5 mfmDrvAdr  1 = SuperDrive      10 Tk0Adr    0 = head on track 0
|            7 gcrModeAdr 1 = MFM drive mode  11 ReadyAdr  0 = ready
|            8 MtrOnAdr   0 = motor on        12 EjectLAdr 1 = eject button pressed
|           13 DrvExstAdr 0 = drive connected 14 TachAdr   tachometer, 60 pulses/turn
|           15 NewIntfAdr 1 = ready handshake (800K drive); on a SuperDrive
|              twoMegAdr: 0 = high-density disk (ChkDiskType)
|   control  0/1 DirLAdr/DirHAdr: step direction in/out, 4 StepLAdr: step,
|            6 mfmModeAdr/7 gcrModeAdr: SuperDrive to MFM/GCR mode,
|            8 MtrOnAdr/9 MtrOffAdr: motor on/off, 13 EjectHAdr: eject
|   1/3 RdDtaAdr/RdDta1Adr select head 0/1 for reading (in MFM mode the
|   SuperDrive's index pulse appears on SENSE there, see mDoFormat); a
|   strobe at address 3 resets the eject button latch (CkEjSw). An HD20
|   answers at 5 (/Exist, CkDCDExist) and is reset through 1 (DCDReset).
|
| Relation to the 1987 SE driver: the same Apple Sony driver sources
| (Larry Kenyon et al.) with the SWIM/SuperDrive support (change C437,
| Steve Christensen, 1986-88; merged into the driver sources 18 Apr 1988),
| i.e. the state of Apple's sources around their version 1.9 of 29 Sep
| 1988 (the ROM's build date reads "Tue, Oct 11, 1988"); later changes in
| Apple's System 7.1 sources (TimeVIADB write splice timing, SWIM2) are
| not in it. About 83% of the 1987 driver's code and tables reappear in
| driver and tail (68% byte for byte, the rest with other branch
| distances or variable offsets). Main changes:
|   - SonyVars is $34A bytes (1987 SE: $344): drvTblPtr ($178), isSWIM
|     ($17C) and mfmMode ($17D) are inserted before the HD20 variables,
|     which move up 6 bytes; hasSuperDrives at $13F; new floppy drive
|     variables mfmDrive (+$16), mfmDisk (+$17) and twoMegFmt (+$18, which
|     is SpdAdjCnt on 400K drives)
|   - DiskOpen looks for a SWIM (Check4SWIM) and SuperDrives, sets driver
|     version 2, installs three MFM vectors (jMRdAddr..jMWrData at $680)
|     and the icon table pointer
|   - DiskPrime selects the register set (SetChipMode) and, for a new
|     disk, finds out GCR or MFM (ChkDiskType); MFM disks use mGetTrack,
|     sectors numbered from 1, a 7.5 ms sector time and 1:1 writes
|   - AdrDisk, Sense, Pulse and DiskSelect have ISM versions (mAdrDisk,
|     mSense, mPulse, mDiskSelect) using the ISM phase, handshake and mode
|     registers;
|     PowerUp switches a SuperDrive between GCR and MFM mode; Seek was
|     rewritten (/STEP handshake) and loads the ISM parameter RAM; Recal
|     uses SetChipMode
|   - the MFM read, write, format and verify routines (Apple's SonyMFM.a)
|   - WakeUp and DiskSelect use their vectors only if the routine there
|     starts with a NOP (System 5.0 patches for older ROMs would crash)
|   - status calls through a table, new csCodes 6 (format list) and 10
|     (MFM status); CtlFormat takes a format number, CtlVerify and the
|     track cache (18 sectors with SuperDrives) know MFM; eject seeks to
|     track 79 first and gives no pulse without a disk; drive info
|     reports type 4 for SuperDrives; drive 1/2 selection fixed (PA4)
|   - the HD20 code is unchanged apart from the moved variables
|
| Names: Apple's Sony driver sources (System 7.1: Sony.a, SonyRWT.a,
| SonyUtil.a, SonyMFM.a, SonyFormat.a, SonyIcon.a -- a later version of
| this code) where they exist; the HD20 code and local labels keep the
| 1987 SE driver's names (res_drvr_sony.s).
|
| SonyVars ($34A bytes, DiskVarLth): up to drive 2 ($8C) the layout of
| the Mac Plus driver in include/sonyequ.inc; the third floppy drive at
| $CE moves the later driver variables up by 66 bytes, and drvTblPtr,
| isSWIM and mfmMode come before the HD20 variables. The .set lines after
| the resource header give this driver's offsets:
|   $004A/$008C/$00CE  Drive1-Drive3, floppy drive variables (66 bytes)
|   $0112-$0167        SaveRegs ... TimeQEl (as in the 1987 SE driver)
|   $016C driveXlat (6 words)  $0178 drvTblPtr  $017C isSWIM  $017D mfmMode
|   $017E/$019A        Drive4/Drive5, HD20 drive variables (28 bytes)
|   $01D2-$0349        HD20 driver variables (StsRtnAddr ... DevIcon)
| =========================================================================

Resource_DRVR_0004_DotSony:
| ROM resource header of DRVR 4 (8 bytes; the same in both SE ROMs)
Resource_DRVR_0004_DotSony_Header:
        .long   0xC0002610                      | ROM resource header: tag $C0, physical size $2610 (8 + $2608)
        .long   0x00000074                      | relative handle: master pointer at ROM zone + $74
| --- ROM-variant difference @ $34680 ---
| SE:      800K .Sony driver (resources/res_drvr_sony.s)
| SE FDHD: SuperDrive .Sony driver (this file)
| Reason: the SE FDHD replaced the driver (same $2610-byte resource slot)
.if ROM_TARGET != MAC_SE
| -------------------------------------------------------------------------
| SonyVars offsets of this driver, named as in Apple's Sony sources (MPW
| SonyEqu.a; the SuperDrive variables with their System 7.1 SonyEqu.a
| names). From Drive3 on they differ from the Mac Plus values in
| include/sonyequ.inc; .set replaces those for the rest of this
| assembly (no other code of the SE tree uses these names).
| -------------------------------------------------------------------------
| drive variables, offsets from the drive's block (D1 = Drive1..Drive5)
.set Track, 0                                   | current track (word); negative = unknown
.set WriteProt, 2                               | bit 7 = 1: write-protected disk
.set DiskInPlace, 3                             | 0 no disk, 1 in place, 2 clamped, 3 1440K disk with GCR format, 8 HD20; $FC-$FF just ejected
.set Installed, 4                               | 1 = connected, $FF = not connected, 0 = unknown
.set Sides, 5                                   | $FF = two-sided drive
.set DQEl, 6                                    | drive queue element (qLink)
.set DriveQVers, 10                             | qType of the drive queue element (HD20: 1, dQDrvSz2 used)
.set TwoSideFmt, 18                             | floppy: $FF = two-sided disk format
.set DriveSize, 18                              | HD20: size in blocks, low word (dQDrvSz)
.set NewIntf, 19                                | floppy: $FF = new interface (ready handshake)
.set DriveErrs, 20                              | floppy: soft error count (word)
.set DriveS1, 20                                | HD20: size in blocks, high word (dQDrvSz2)
.set mfmDrive, 22                               | $FF = SuperDrive with a SWIM, 0 = 400K/800K drive
.set DriveType, 22                              | HD20: device type (word)
.set mfmDisk, 23                                | $FF = MFM disk (ISM registers), 0 = GCR
.set twoMegFmt, 24                              | SuperDrive: $FF = 1440K (high-density) disk, 0 = 720K
.set SpdAdjCnt, 24                              | 400K drive: speed adjustment count (word)
.set TrkSpeedTbl, 26                            | 400K drive: 5 zones x 8 bytes (speed code, delta, time of check)
.set DriveChar, 26                              | HD20: characteristics byte
| drive variable blocks
.set Drive1, 0x004A                             | lower internal floppy (66 bytes)
.set Drive2, 0x008C                             | upper internal floppy
.set Drive3, 0x00CE                             | external floppy
.set Drive4, 0x017E                             | first HD20 (28 bytes)
.set Drive5, 0x019A                             | second HD20
| driver variables after the floppy drives
.set SaveRegs, 0x0112                           | WakeUp/EmptyPD register save area (36 bytes)
.set TagBufPtr, 0x0136                          | separate tag buffer (csCode 8), 0 = none
.set TagBufOS, 0x013A                           | offset of the current block's tags in it
.set DiskErrs, 0x013C                           | soft error count of all drives (word)
.set PassThru, 0x013E                           | 0 = HD20 pass-thru works, $FF = no pass-thru
.set hasSuperDrives, 0x013F                     | $FF = at least one SuperDrive connected
.set CurSector, 0x0140                          | sector being read or written (word)
.set TCRdEnable, 0x0142                         | $FF = read other sectors of the track into the cache
.set TCInstalled, 0x0143                        | $FF = track cache installed and on
.set TCDrive, 0x0144                            | drive of the cached track (0 = cache invalid)
.set TCSideTrack, 0x0146                        | side/track of the cached track
.set TCSectMap, 0x0148                          | bit map of the cached sectors
.set TCBuffer, 0x014C                           | track cache buffer (524 bytes per sector)
.set TCNumCached, 0x0150                        | sectors read into the cache (word)
.set TCNumUsed, 0x0152                          | sectors taken from the cache (word)
.set LastDrive, 0x0154                          | Drive before the current request (word)
.set TimeOutDrive, 0x0158                       | drive of the pending power-down (word)
.set TimeQEl, 0x015A                            | Time Manager queue element of WakeUp
.set driveXlat, 0x016C                          | drive number translation table (6 words)
.set drvTblPtr, 0x0178                          | pointer to the icon/drive info table (DRVTBL)
.set isSWIM, 0x017C                             | $FF = SWIM installed, 0 = IWM
.set mfmMode, 0x017D                            | $FF = ISM register set selected, 0 = IWM set
| HD20 (DCD) driver variables
.set StsRtnAddr, 0x01D2                         | where to continue after an HD20 status command
.set DCDCmd, 0x01D6                             | command byte (response: command + $80)
.set SeqNum, 0x01D7                             | sequence number (block count)
.set StartBlock, 0x01D8                         | starting block (commands); status bytes (responses)
.set TagBytes, 0x01DC                           | 20 tag bytes (status: device type, manufacturer, ...)
.set DevChar, 0x01E0                            | status: characteristics byte + 3-byte block count
.set BufSize, 0x01F0                            | bytes per block sent plus received
.set LastStatus, 0x01F4                         | last status or error information
.set LastResult, 0x01F8                         | result type (1 nonZerStat, 2 comErr)
.set DCDFlags, 0x01F9                           | bit 0 reset done (resetonce), bit 1 retry done (retryonce)
.set ChkTime, 0x01FA                            | handshake poll interval (100 us units)
.set MaxTime, 0x01FC                            | number of polls before a timeout
.set StsBuffer, 0x01FE                          | status data of a status command
.set DevIcon, 0x022A                            | icon in the status data (StsBuffer+44)
.set DiskVarLth, 0x034A                         | size of SonyVars
| -------------------------------------------------------------------------
| DRVR header (Inside Macintosh II-188): flags, delay, event mask, menu,
| the offsets of the five entry points from the start of the header,
| and the driver name.
| -------------------------------------------------------------------------
Driver_Sony:
| MacSEROM.lst name of the driver resource
_DRVR_4_.Sony:
        .short  0x4F00                          | drvrFlags: dNeedLock+dStatEnable+dCtlEnable+dWritEnable+dReadEnable
        .short  0x0000                          | drvrDelay: no periodic action
        .short  0x0000                          | drvrEMask: no desk accessory events
        .short  0x0000                          | drvrMenu: no menu
        .short  E_Sony_Open-Driver_Sony         | drvrOpen: $0074
        .short  E_Sony_Prime-Driver_Sony        | drvrPrime: $04F6
        .short  E_Sony_Control-Driver_Sony      | drvrCtl: $0224
        .short  E_Sony_Status-Driver_Sony       | drvrStatus: $03DA
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
| (JFigTrkSpd..NiblTbl, $222-$25A), followed by InitDsk2 (JDiskSel,
| JSendCmd, JDCDReset), InitDskMFM (the three MFM vectors at $680, new)
| and the tuneable drive constants. RdAddr, RdData and SetUpPoll moved to
| the ROM tail: their vectors point to entries of the jump table at the
| end of this driver (SONY_TAIL_RDADDR..), which jump to the tail.
| -------------------------------------------------------------------------
INITDSKTBL:
        .short  Sony_FigTrkSpd-INITDSKTBL       | JFigTrkSpd ($222)
        .short  Sony_DiskPrime-INITDSKTBL       | JDiskPrime ($226)
        .short  SONY_TAIL_RDADDR-INITDSKTBL     | JRdAddr ($22A): via the tail jump table
        .short  SONY_TAIL_RDDATA-INITDSKTBL     | JRdData ($22E): via the tail jump table
        .short  Sony_WrData-INITDSKTBL          | JWrData ($232)
        .short  Sony_Seek-INITDSKTBL            | JSeek ($236)
        .short  SONY_TAIL_SETUPPOLL-INITDSKTBL  | JSetUpPoll ($23A): via the tail jump table
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
| InitDskMFM -- the three MFM vectors (new), stored from jMRdAddr ($680) on
INITDSKMFM:
        .short  SONY_JTMRDADDR-INITDSKTBL       | jMRdAddr ($680): MFM read address field
        .short  SONY_JTMRDDATA-INITDSKTBL       | jMRdData ($684): MFM read data field
        .short  SONY_JTMWRDATA-INITDSKTBL       | jMWrData ($688): MFM write data field
| InitParams -- tuneable drive constants, copied into SonyVars from
| ReadErrInit (+$2A) on; the same 32 bytes as in the SE driver
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
| Allocates the $34A-byte SonyVars block (1987 SE: $344), sets up the
| drive number translation table, the 21 disk routine vectors (the three
| MFM vectors at $680 are new) and the tuneable constants, stores the
| pointer to the icon/drive-info table (SONY_TAIL_SETDRVTBL, tail), installs
| the VBL task and the Time Manager element used by WakeUp, looks for a
| SWIM (Check4SWIM), checks whether an HD20 on the external port passes
| requests through, and finally looks for connected drives:
|   drive 1   lower internal floppy  (VIA PA4 = 1)
|   drive 2   upper internal floppy  (VIA PA4 = 0)
|   drive 3   external floppy
|   drives 4,5 HD20 (DCD) on the external port
| Each connected drive gets a drive queue element (_AddDrive). Floppy
| drives are given consecutive logical drive numbers 1, 2, ... in the
| order found and the translation table at driveXlat is updated (see
| Inside Macintosh V-469). New for SuperDrives (Apple's C437): a drive
| that answers the mfmDrvAdr sense is marked as new-interface drive
| (Apple 1.2: SuperDrives "look like they have an old interface", their
| address 15 reports the media density) and, when a SWIM is present, as
| SuperDrive (mfmDrive, hasSuperDrives).
| =========================================================================
E_Sony_Open:
        MOVE.L  #DiskVarLth,D0                  | DiskVarLth: $34A bytes of driver variables (1987 SE: $344)
        _NewPtrSysClear                         | allocate zeroed system heap block
        MOVE.L  A0,(SonyVars).w                 | store SonyVars ptr in low memory
        MOVE.L  A1,(A0)                         | DiskUnitPtr: save DCE ptr at offset 0
        MOVE.L  (UTableBase).w,A2               | unit table base
        MOVE.L  0x10(A2),0x4(A2)                | unit 1 (refNum -2, HD20 drives) shares the .Sony DCE
        MOVE.B  #0x2,0x7(A1)                    | driver version 2 (DCtlQueue+1): 2 = MFM-capable driver (SE: 1)
        ST.B    Active(A0)                      | Active: mark driver active (exclude VBL)
        LEA.L   driveXlat(A0),A2                | A2 -> drive number translation table (driveXlat)
        MOVEQ.L #0x0,D0                         | entry 0 = 0
SONY_OPEN_XLATINIT:
        MOVE.W  D0,(A2)+                        | entry n = n: identity mapping to start with
        ADDQ.W  #0x1,D0                         | next entry
        CMPI.W  #0x5,D0                         | entries 0-5 (drive numbers 0-5) done?
        BLE.B   SONY_OPEN_XLATINIT              | no -> continue
        BSR.W   SONY_TAIL_SETDRVTBL             | SetDrvTbl (tail): drvTblPtr = DRVTBL (A0 = SonyVars)
        MOVE.L  A0,A2                           | A2 = SonyVars for later use
| initialize the disk routine jump table (15 vectors)
        LEA.L   INITDSKTBL(PC),A0               | point to InitDskTbl offset table
        LEA.L   (DiskVars_JFigTrkSpd).w,A1      | first jump table entry
        MOVEQ.L #0xE,D1                         | 15 vectors (0..14)
        MOVE.L  A0,D0                           | base address for offset computation
        BSR.B   DISPSETUP                       | DispSetUp: convert to absolute addrs
| second table: DiskSel, SendCmd, DCDReset; third table: the MFM routines
        LEA.L   (JDiskSel).w,A1                 | JDiskSel ($B40): DiskSel, SendCmd, DCDReset
        MOVEQ.L #0x2,D1                         | 3 vectors
        BSR.B   DISPSETUP                       | install them
        MOVEQ.L #0x2,D1                         | 3 more vectors
        LEA.L   (0x680).w,A1                    | jMRdAddr ($680): mRdAddr, mRdData, mWrData
        BSR.B   DISPSETUP                       | install them
        ST.B    OneToOne(A2)                    | OneToOne: set 1:1 flag (legacy, unused)
| copy tuneable drive constants (32 bytes) into SonyVars
        LEA.L   ReadErrInit(A2),A1              | dest: ReadErrInit(A2)
        LEA.L   INITPARAMS(PC),A0               | source: InitParams table
        MOVEQ.L #0x20,D0                        | 32 bytes to copy
        _BlockMove                              | copy drive constants
| allocate VBL task for power-down and disk-in-place sensing
        LEA.L   DiskQVE(A2),A0                  | DiskQVE: VBL task control block
        MOVE    #0x1,0x4(A0)                    | QType = VType (VBL task)
        LEA.L   Sony_DiskVBLTask(PC),A1         | address of VBL task routine
        MOVE.L  A1,0x6(A0)                      | VBLAddr: set task entry point
        MOVE    #0x1E,0xA(A0)                   | VBLCount = 30 ticks (~0.5 sec)
        _VInstall                               | install into vertical retrace queue
| install Time Manager queue element for wakeup timing
        LEA.L   TimeQEl(A2),A0                  | TimeQEl: Time Manager queue element (WakeUp)
        _InsTime                                | register with Time Manager
| look for a SWIM, then check pass-thru on the external connector (DCD
| detection)
        BSR.W   Sony_Check4SWIM                 | Check4SWIM: isSWIM = $FF if a SWIM answers; A1 = SonyVars
        MOVE.W  #0x6,Drive(A1)                  | Drive = 6, one above the last drive (Mac Plus: 7); GetDrive bounds it to 5
        BSR.W   Sony_DiskSelect                 | select the external interface for this drive number
        BSR.W   Sony_CkDCDExist                 | CkDCDExist: does an HD20 answer for drive 6?
        SPL.B   PassThru(A1)                    | PassThru: $FF = HD20 answers for any number (no pass-thru)
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
        TST.B   PassThru(A1)                    | PassThru: can a second HD20 be addressed?
        BMI.W   E_SONY_OPEN_SKIP                | no -> skip drive 5
E_SONY_OPEN_SELECT:
        TST.B   0x1000(A0)                      | mtrOff: MotorOn = 0, /ENBL off before the next drive is selected
E_SONY_OPEN_CONT:
        BSR.W   Sony_DiskSelect                 | DiskSelect: select this drive's interface
        CMPI.W  #0x4,D2                         | floppy drive (1-3)?
        BLT.B   CHKCONNECT                      | yes -> floppy sense
        MOVE.W  Drive(A1),D5                    | HD20: logical drive number = physical drive number
        BSR.W   Sony_CkDCDExist                 | CkDCDExist: HD20 connected at this position?
        BMI.B   E_SONY_OPEN_SKIP                | no -> skip
        MOVE    #0x1,DriveQVers(A1,D1.W)        | qType (drive queue element +4) = 1: dQDrvSz2 holds the high word of the size
        MOVEQ.L #-0x2,D3                        | DCDRfN: refNum -2 for HD20 drives
        BRA.B   E_SONY_OPEN_XLAT                | install the drive queue element
| ChkConnect -- floppy drive: find out whether a drive is connected and
| how many sides it has.
CHKCONNECT:
        MOVEQ.L #0xD,D0                         | DrvExstAdr (13): drive-exists sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when a drive is connected
        BMI.B   E_SONY_OPEN_SKIP                | not connected, skip this drive
        MOVEQ.L #0x9,D0                         | SidesAdr (9): number-of-sides sense
        BSR.W   Sony_AdrAndSense                | sense = 1 for a two-sided drive
        SMI.B   Sides(A1,D1.W)                  | Sides = $FF: two-sided drive
        MOVEQ.L #0xF,D0                         | NewIntfAdr (15): new-interface sense
        BSR.W   Sony_AdrAndSense                | sense = 1: ready handshake (800K drive); a SuperDrive reports its media density here
        SMI.B   NewIntf(A1,D1.W)                | NewIntf = $FF: new interface
        MOVEQ.L #0x5,D0                         | mfmDrvAdr (5): SuperDrive sense
        BSR.W   Sony_AdrAndSense                | sense = 1: the drive is a SuperDrive (MFM capable)
        BPL.B   CHKCONNECT_RFN                  | no -> 400K or 800K drive
        ST.B    NewIntf(A1,D1.W)                | NewIntf = $FF: a SuperDrive has the new interface (address 15 may read 0)
        TST.B   isSWIM(A1)                      | isSWIM: is a SWIM installed?
        BPL.B   CHKCONNECT_RFN                  | no -> the IWM cannot do MFM: use it as an 800K drive
        ST.B    mfmDrive(A1,D1.W)               | mfmDrive = $FF: SuperDrive
        ST.B    hasSuperDrives(A1)              | hasSuperDrives = $FF: at least one SuperDrive connected
CHKCONNECT_RFN:
        MOVEQ.L #-0x5,D3                        | SonyRfN: refNum -5 for floppy drives
| Swap translation table entries D2 (physical) and D5 (logical), so that
| logical drive D5 maps to this physical drive. For HD20 drives D5 = D2
| and the swap changes nothing.
E_SONY_OPEN_XLAT:
        LEA.L   driveXlat(A1),A1                | A1 -> drive number translation table
        ADD.W   D5,D5                           | D5 = logical drive number * 2 (word index)
        ADD.W   D2,D2                           | D2 = physical drive number * 2
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
| Branch from: SONY_CONTROL_BADCODE, SONY_CTL_KILLIO, SONY_CTL_FORMAT, SONY_CTL_VERIFY, SONY_CTL_TAGBUF (and 11 more)
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
| (4-5), both relative to CODES; a zero word ends the table. The same
| csCodes as in the 1987 SE driver; the icon calls (21, 22) for floppy
| drives and the drive info call (23) went to the ROM tail (SONY_TAIL_*
| jump table entries).
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
        .short  SONY_TAIL_DRIVEICON-CODES       | floppy drives 1-3
        .short  SONY_DCD_ICON-CODES             | HD20 drives 4-5
        .short  22                              | csCode 22: iconLogCC: get media icon
        .short  SONY_TAIL_MEDIAICON-CODES       | floppy drives 1-3
        .short  SONY_DCD_ICON-CODES             | HD20 drives 4-5
        .short  23                              | csCode 23: infoCC: get drive info
        .short  SONY_TAIL_DRVINFO-CODES         | floppy drives 1-3
        .short  SONY_TAIL_DRVINFO-CODES         | HD20 drives 4-5
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
        BNE.B   SONY_CONTROL_DISPATCH           | bad drive number: dispatch with D0 = nsDrvErr
        TST.B   Installed(A1,D1.W)              | drive connected (Installed = 1)?
        BPL.B   SONY_CONTROL_DISPATCH           | yes -> D0 = 0
        MOVEQ.L #-0x40,D0                       | noDriveErr: drive not connected
SONY_CONTROL_DISPATCH:
        LEA.L   CODES(PC),A3                    | A3 -> dispatch table
        MOVEA.L A3,A4                           | A4 = table base for the handler offset
SONY_CONTROL_SCAN:
        MOVE.W  (A3)+,D2                        | csCode of this table entry
        BEQ.B   SONY_CONTROL_BADCODE            | end of table -> controlErr
        CMP.W   0x1A(A0),D2                     | csCode of the request?
        BNE.B   SONY_CONTROL_NEXT               | no -> next entry
        CMPI.W  #0x4,Drive(A1)                  | HD20 drive (drive number 4 or 5)?
        BLT.B   SONY_CONTROL_JUMP               | no -> use the floppy offset
        ADDQ.W  #0x2,A3                         | yes -> handler offset for HD20 drives
SONY_CONTROL_JUMP:
        ADDA.W  (A3),A4                         | A4 = handler address (table base + offset)
        TST.W   D0                              | CCR = result of the drive check
        JMP     (A4)                            | go to the handler
SONY_CONTROL_NEXT:
        ADDQ.W  #0x4,A3                         | skip both offsets (csCode already skipped)
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
        BRA.W   SONY_TAIL_CTLFORMAT             | Sony_CtlFormat (tail): go format
| ctlSonyVer (csCode 5, floppy) -- verify the disk in the drive.
SONY_CTL_VERIFY:
        BNE.W   Sony_DiskDone                   | bad or missing drive -> return the error
        BRA.W   SONY_TAIL_CTLVERIFY             | Sony_CtlVerify (tail): go verify
| ctlTagBuf (csCode 8) -- set (CSParam <> 0) or clear the separate tag
| buffer; drive number not needed.
SONY_CTL_TAGBUF:
        MOVE.L  0x1C(A0),TagBufPtr(A1)          | TagBufPtr = CSParam
        MOVEQ.L #0x0,D0                         | always noErr
        BRA.W   Sony_DiskDone                   | complete the request
| ctlTrkCache (csCode 9) -- track cache control; drive number not needed.
|   CSParam+0: non-zero = enable, zero = disable the cache
|   CSParam+1: >0 = install (allocate), <0 = remove, 0 = neither
| Always completes with noErr (MTN #272: "When the cache is removed,
| 680x0 register D0 contains the previous size of the cache"; TCdispose
| returns that size, but D0 is cleared before DiskDone).
SONY_CTL_TRKCACHE:
        ADDA.W  #0x1C,A0                        | A0 -> CSParam
        MOVE.B  (A0)+,D1                        | D1 = enable flag
        MOVE.B  (A0)+,D0                        | D0 = install/remove flag
        BEQ.B   SONY_CTLTCENB                   | neither -> just enable/disable
        BPL.B   SONY_CTLTCINST                  | positive -> install a cache buffer
        BSR.B   SONY_TCDISPOSE                  | negative -> TCdispose: remove the buffer
        BRA.B   SONY_CTLTCENB                   | and disable the cache
SONY_CTLTCINST:
        TST.L   TCBuffer(A1)                    | TCBuffer: buffer already allocated?
        BNE.B   SONY_CTLTCENB                   | yes -> keep it
        CMPI.W  #0x2,(MemTop).w                 | MemTop high word <= 2: at most 128K of RAM?
        BLE.B   SONY_CTLTCENB                   | yes -> no cache
        MOVE.L  #0x1890,D0                      | $1890 = 12 sectors * 524 bytes (GCR track)
        TST.B   hasSuperDrives(A1)              | hasSuperDrives: any SuperDrive connected?
        BPL.B   SONY_CONTROL_ALLOC              | no -> a 12-sector buffer is enough
        MOVE.L  #0x24D8,D0                      | $24D8 = 18 sectors * 524 bytes (1440K MFM track)
SONY_CONTROL_ALLOC:
        _NewPtrSysClear                         | allocate it in the system heap
        BNE.B   SONY_CTLTCENB                   | no memory -> no cache
        MOVE.L  A0,TCBuffer(A1)                 | TCBuffer = new buffer
        CLR.W   TCDrive(A1)                     | TCDrive = 0: cache contents invalid
| Branch from: SONY_CTL_TRKCACHE, SONY_CTLTCINST, SONY_CONTROL_ALLOC
SONY_CTLTCENB:
        TST.L   TCBuffer(A1)                    | TCBuffer: any buffer?
        SNE.B   TCInstalled(A1)                 | TCInstalled = 0 if there is none
        BEQ.B   SONY_CONTROL_DONE               | no buffer -> done
        TST.B   D1                              | enable requested?
        SNE.B   TCInstalled(A1)                 | TCInstalled = $FF (on) or 0 (off)
SONY_CONTROL_DONE:
        MOVEQ.L #0x0,D0                         | always noErr
        BRA.W   Sony_DiskDone                   | complete the request
| TCdispose -- release the track cache buffer
|   D0 (out) -- number of bytes freed (0 if there was no buffer)
| The Mac Plus driver also used this as its grow-zone procedure.
SONY_TCDISPOSE:
        CLR.L   -(SP)                           | assume nothing freed
        MOVE.L  TCBuffer(A1),D0                 | TCBuffer: buffer allocated?
        BEQ.B   SONY_TCDISPOSE_DONE             | no -> return 0
        MOVEA.L D0,A0                           | A0 = buffer
        _GetPtrSize                             | D0 = its size
        MOVE.L  D0,(SP)                         | = number of bytes freed
        _DisposePtr                             | release it
        CLR.L   TCBuffer(A1)                    | TCBuffer = nil
        CLR.B   TCInstalled(A1)                 | TCInstalled = 0
SONY_TCDISPOSE_DONE:
        MOVE.L  (SP)+,D0                        | D0 = bytes freed
        RTS                                     | return
| ctlSonyEjc (csCode 7, floppy) -- eject the disk. New: if a disk has been
| seen in the drive, the head is first moved to track 79 (away from the
| directory tracks, Apple: "to make sure the head is off of all important
| parts of the disk"; System 7.1 seeks to track 40: "Peripherals wanted
| 79 before but now changed their minds!"), recalibrating if the seek
| fails; the eject pulse is skipped when no disk is in the drive any
| more (avoids the click), and with the ISM registers selected LSTRB is
| driven through the phase register.
SONY_CTL_EJECT:
        BNE.W   Sony_DiskDone                   | bad or missing drive -> return the error
        TST.B   DiskInPlace(A1,D1.W)            | DiskInPlace: has a disk been seen in this drive?
        BLE.B   SONY_CTL_EJECT_GO               | no (0) or just ejected (<0) -> skip the seek
        BSR.W   Sony_RWPowerUp                  | RWPowerUp: make sure the drive is powered up
        MOVEQ.L #0x4F,D6                        | track 79
        BSR.W   E_Sony_Seek                     | Seek
        BGT.B   SONY_CTL_EJECT_GO               | seek done (track number > 0) -> eject
        BEQ.B   SONY_CTL_EJECT_SEEK2            | 0: Seek recalibrated -> seek again
        BSR.W   E_Sony_Recal                    | seek failed: Recal first
        BMI.B   SONY_CTL_EJECT_GO               | recal failed -> eject anyway
SONY_CTL_EJECT_SEEK2:
        MOVEQ.L #0x4F,D6                        | track 79 again
        BSR.W   E_Sony_Seek                     | Seek
SONY_CTL_EJECT_GO:
        BSR.W   SONY_INVALTRKCACHE              | InvalTrkCache: forget cached sectors of this drive
        MOVEQ.L #0x0,D0                         | immediate power-off
        BSR.W   Sony_PowerDown                  | PowerDown
        BSR.W   Sony_DiskSelect                 | DiskSelect: keep the interface enabled
        MOVEQ.L #0x2,D0                         | DIPAdr: disk-in-place sense, at the drive
        BSR.W   Sony_AdrAndSense                | sense = 0 when a disk is in place
        BPL.B   SONY_CTL_EJECT_PULSE            | disk there -> eject it
        MOVEQ.L #0x0,D0                         | no disk: immediate power-off
        BSR.W   Sony_PowerDown                  | PowerDown
        BRA.B   SONY_CTL_EJECTDONE              | and exit without the eject pulse
SONY_CTL_EJECT_PULSE:
        MOVE    #0x7D0,D0                       | wait 200 ms
        BSR.W   Sony_CallWakeUp                 | WakeUp (returns after the delay)
        MOVEQ.L #0xD,D0                         | EjectHAdr (13): eject command
        BSR.W   Sony_AdrDisk                    | address it
        TST.B   mfmMode(A1)                     | mfmMode: ISM register set selected?
        BPL.B   SONY_CTL_EJECT_IWMHI            | no -> IWM phase lines
        MOVE.B  #0xFF,wPhase(A0)                | wPhase = $FF: CA0-CA2 stay 1 (address 13), LSTRB high
        BRA.B   SONY_CTL_EJECT_CKNEW            | eject pulse started
SONY_CTL_EJECT_IWMHI:
        TST.B   0xE00(A0)                       | ph3H: LSTRB high, start of the eject pulse
SONY_CTL_EJECT_CKNEW:
        TST.B   NewIntf(A1,D1.W)                | new-interface drive (800K drive or SuperDrive)?
        BMI.B   SONY_NEWDRVEJECT                | yes -> a short pulse is enough
        MOVE    EjectTime(A1),D0                | EjectTime: 0.75 s pulse for old drives
        BSR.W   Sony_CallWakeUp                 | WakeUp
        TST.B   mfmMode(A1)                     | mfmMode: ISM register set?
        BPL.B   SONY_CTL_EJECT_IWMLO            | no -> IWM phase lines
        MOVE.B  #0xF7,wPhase(A0)                | wPhase = $F7: LSTRB low
        BRA.B   SONY_CTL_EJECTDONE              | done
SONY_CTL_EJECT_IWMLO:
        TST.B   0xC00(A0)                       | ph3L: LSTRB low, end of the pulse
        BRA.B   SONY_CTL_EJECTDONE              | done
| NewDrvEject -- a new-interface drive only needs a short pulse (Apple:
| "1us < assert LSTRB < 300ms"), but /ENBL must stay asserted until 150
| us after the disk has left the drive (/CSTIN, the disk-in-place sense,
| goes away); wait for that at most 1.6 s.
SONY_NEWDRVEJECT:
        TST.B   mfmMode(A1)                     | mfmMode: ISM register set?
        BPL.B   SONY_NEWDRVEJECT_IWM            | no -> IWM phase lines
        MOVE.B  #0xF7,wPhase(A0)                | wPhase = $F7: LSTRB low
        BRA.B   SONY_NEWDRVEJECT_WAIT           | wait for the disk to leave
SONY_NEWDRVEJECT_IWM:
        TST.B   0xC00(A0)                       | ph3L: LSTRB low
SONY_NEWDRVEJECT_WAIT:
        MOVEQ.L #0xF,D3                         | wait at most 16 * 100 ms
SONY_NEWDRVEJECT_LOOP:
        MOVE    #0x3E8,D0                       | 100 ms
        BSR.W   Sony_CallWakeUp                 | WakeUp
        MOVEQ.L #0x2,D0                         | DIPAdr: disk-in-place sense
        BSR.W   Sony_AdrAndSense                | sense = 1 once the disk has left the drive
        DBMI    D3,SONY_NEWDRVEJECT_LOOP        | until the disk is out or the time is up
        MOVEQ.L #0xA,D0                         | 1 ms more
        BSR.W   Sony_CallWakeUp                 | WakeUp
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
| StatusTbl -- status call dispatch table (new; the 1987 SE driver only
| knew csCode 8): csCode and handler offset (relative to STATUSTBL);
| a zero word ends the table.
| -------------------------------------------------------------------------
STATUSTBL:
        .short  6                               | csCode 6: FmtLstCode: list of possible disk formats
        .short  Sony_PassportSts-STATUSTBL      | handler
        .short  8                               | csCode 8: drive status (the drive variables)
        .short  Sony_DriveStatus-STATUSTBL      | handler
        .short  10                              | csCode 10: MFMStsCode: drive/disk/controller type
        .short  Sony_MFMStatus-STATUSTBL        | handler
        .short  0                               | end of table

| -------------------------------------------------------------------------
| DiskStatus -- status entry: look up the csCode in StatusTbl, check the
| drive number and call the handler with
|   A0 = CSParam, A1 = SonyVars, D1 = drive vars offset,
|   D0 = noDriveErr and CCR = PL/MI from Installed (handler may test it)
| (Apple's C437 code, 1 May 1987: status calls dispatched like control
| calls).
| -------------------------------------------------------------------------
E_Sony_Status:
        MOVEQ.L #-0x12,D0                       | statusErr: assume an unsupported csCode
        LEA.L   STATUSTBL(PC),A3                | A3 -> dispatch table
        MOVEA.L A3,A4                           | A4 = table base for the handler offset
        BRA.B   SONY_STATUS_SCAN                | check the first entry
SONY_STATUS_NEXT:
        ADDQ.W  #0x2,A3                         | skip the handler offset
SONY_STATUS_SCAN:
        MOVE.W  (A3)+,D2                        | csCode of this table entry
        BEQ.B   SONY_STATUS_DONE                | end of table -> statusErr
        CMP.W   0x1A(A0),D2                     | csCode of the request?
        BNE.B   SONY_STATUS_NEXT                | no -> next entry
        BSR.W   Sony_CkDrvNum                   | CkDrvNum: check the drive number, set up A1/D1
        BNE.B   SONY_STATUS_DONE                | bad drive number -> return the error
        MOVEQ.L #-0x40,D0                       | noDriveErr, for handlers that need a drive
        TST.B   Installed(A1,D1.W)              | Installed: CCR = MI if the drive is not connected
        LEA.L   0x1C(A0),A0                     | A0 -> CSParam
        ADDA.W  (A3),A4                         | A4 = handler address
        JSR     (A4)                            | call it (CCR from the Installed test)
SONY_STATUS_DONE:
        BRA.W   Sony_DiskDone                   | complete the request
| DriveStatus (csCode 8) -- copy the first 22 bytes of the drive
| variables (track, write-protect, disk-in-place, installed, sides, drive
| queue element, two-sided format, new interface, soft error count) to
| CSParam.
Sony_DriveStatus:
        MOVEQ.L #0xB,D0                         | 11 words
        ADDA    D1,A1                           | A1 -> this drive's variables
SONY_DRIVESTATUS_LOOP:
        MOVE    (A1)+,(A0)+                     | copy a word
        SUBQ.W  #0x1,D0                         | count it
        BGT.B   SONY_DRIVESTATUS_LOOP           | until all 11 words are copied (D0 = 0 = noErr)
        RTS                                     | return (D0 = 0)
| PassportSts (csCode 6) -- return the list of possible disk formats
|   CSParam+0 (in/out) -- number of entries wanted / returned
|   CSParam+2 (in)     -- pointer to the caller's table (8 bytes per entry)
| Floppy drives: one entry (400K) for a one-sided drive, two (400K, 800K)
| for a two-sided GCR drive, three (400K, 800K, 720K) for a SuperDrive,
| and for a 1440K disk in a SuperDrive only the 1440K entry; the entry of
| the current format gets bit 30 set. HD20 drives return one entry with
| their size in blocks (not in Apple's later SonyMFM-era Sony.a, which has
| no HD20 code). Errors: noDriveErr, offLinErr (disk not clamped),
| paramErr (count <= 0).
Sony_PassportSts:
        BLE.B   SONY_PASSPORTSTS_CHK            | drive not connected -> noDriveErr
        MOVEQ.L #-0x41,D0                       | offLinErr: assume the disk is not clamped
        CMPI.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace >= 2: disk clamped?
        BLT.B   SONY_PASSPORTSTS_CHK            | no -> the information is not valid
        MOVEQ.L #-0x32,D0                       | paramErr in case the count is <= 0
        MOVE.W  (A0),D2                         | D2 = number of entries wanted
SONY_PASSPORTSTS_CHK:
        BLE.B   SONY_PASSPORTSTS_EXIT           | error or count <= 0 -> return
        CMPI.W  #0x4,Drive(A1)                  | HD20 drive (4 or 5)?
        BLT.B   SONY_PASSPORTSTS_FLOPPY         | no -> floppy formats
        MOVE.L  DriveSize(A1,D1.W),D0           | dQDrvSz / dQDrvSz2 of the HD20
        SWAP    D0                              | D0 = size in blocks
        MOVE.W  #0x1,(A0)+                      | one entry returned
        MOVEA.L (A0),A0                         | A0 -> caller's table
        MOVE.L  D0,(A0)+                        | entry: number of blocks
        MOVE.L  #0x40000000,(A0)+               | current format, no geometry
        BRA.B   SONY_PASSPORTSTS_OK             | -> noErr
SONY_PASSPORTSTS_FLOPPY:
        LEA.L   DISKFMTTBL(PC),A2               | A2 -> DiskFmtTbl
        MOVEQ.L #0x1,D3                         | one entry (one-sided drive)
        MOVEQ.L #0x0,D0                         | current format: entry 0 (400K)
        TST.B   Sides(A1,D1.W)                  | Sides: two-sided drive?
        BPL.B   SONY_PASSPORTSTS_COUNT          | no -> 400K only
        MOVE.B  TwoSideFmt(A1,D1.W),D0          | TwoSideFmt: 0 = one-sided, $FF = two-sided disk
        NEG.B   D0                              | current format: entry 0 (400K) or 1 (800K)
        MOVEQ.L #0x2,D3                         | two entries (400K, 800K)
        TST.B   mfmDrive(A1,D1.W)               | mfmDrive: SuperDrive?
        BPL.B   SONY_PASSPORTSTS_COUNT          | no -> two GCR formats
        MOVEQ.L #0x3,D3                         | three entries (400K, 800K, 720K)
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: MFM disk?
        BPL.B   SONY_PASSPORTSTS_COUNT          | no -> current format is GCR
        MOVEQ.L #0x2,D0                         | current format: entry 2 (720K)
        TST.B   twoMegFmt(A1,D1.W)              | twoMegFmt: 1440K (double density) disk?
        BPL.B   SONY_PASSPORTSTS_COUNT          | no -> 720K
        LEA.L   DISKFMTTBL_1440K(PC),A2         | A2 -> 1440K entry
        MOVEQ.L #0x0,D0                         | current format: the only entry
        MOVEQ.L #0x1,D3                         | one entry (1440K)
SONY_PASSPORTSTS_COUNT:
        CMP.W   D3,D2                           | more entries wanted than there are?
        BLE.B   SONY_PASSPORTSTS_STORE          | no ->
        MOVE.W  D3,D2                           | yes -> return all of them
SONY_PASSPORTSTS_STORE:
        MOVE.W  D2,(A0)+                        | number of entries returned
        SUBQ.W  #0x1,D2                         | -1 for DBF
        MOVE.W  D2,D3                           | D3 = loop count at the current format...
        SUB.W   D0,D3                           | ...(index relative to the first entry)
        MOVEA.L (A0),A0                         | A0 -> caller's table
SONY_PASSPORTSTS_LOOP:
        MOVE.L  (A2)+,(A0)+                     | entry: number of blocks
        MOVE.L  (A2)+,D0                        | D0 = characteristics
        CMP.W   D2,D3                           | current format?
        BNE.B   SONY_PASSPORTSTS_PUT            | no ->
        BSET    #0x1E,D0                        | yes -> bit 30: the disk has this format
SONY_PASSPORTSTS_PUT:
        MOVE.L  D0,(A0)+                        | store the characteristics
        DBF     D2,SONY_PASSPORTSTS_LOOP        | next entry
SONY_PASSPORTSTS_OK:
        MOVEQ.L #0x0,D0                         | noErr
SONY_PASSPORTSTS_EXIT:
        RTS                                     | return
| DiskFmtTbl -- the possible floppy formats, 8 bytes each: number of
| blocks (long); characteristics byte (bit 7 = track/side/sector counts
| valid, bit 6 = current format, set by PassportSts, bit 4 = double
| density, bits 0-3 = number of sides); sectors per track; tracks.
DISKFMTTBL:
        .long   2*400                           | 400K GCR: 800 blocks
        .byte   0x81,10                         | tracks/sides/sectors valid, single density, 1 side; 10 sectors (average)
        .short  80                              | 80 tracks
        .long   2*800                           | 800K GCR: 1600 blocks
        .byte   0x82,10                         | valid, single density, 2 sides; 10 sectors (average)
        .short  80                              | 80 tracks
        .long   2*720                           | 720K MFM: 1440 blocks
        .byte   0x82,9                          | valid, single density, 2 sides; 9 sectors
        .short  80                              | 80 tracks
DISKFMTTBL_1440K:
        .long   2*1440                          | 1440K MFM: 2880 blocks
        .byte   0x92,18                         | valid, double density, 2 sides; 18 sectors
        .short  80                              | 80 tracks
| MFMStatus (csCode 10) -- return MFM related drive/disk/controller info
| (the "MFM Drive, MFM Disk, MFM Format, Disk Controller" bytes of the
| IOP SWIM Driver ERS, DriveStatus $12-$15)
|   CSParam+0 -- $FF = SuperDrive, $00 = 400K/800K GCR drive (mfmDrive)
|   CSParam+1 -- $FF = MFM disk, $00 = GCR (mfmDisk)
|   CSParam+2 -- $FF = 1440K, $00 = 720K MFM disk (twoMegFmt)
|   CSParam+3 -- $FF = SWIM, $00 = IWM (isSWIM)
Sony_MFMStatus:
        MOVE.L  mfmDrive(A1,D1.W),D0            | mfmDrive, mfmDisk, twoMegFmt
        MOVE.B  isSWIM(A1),D0                   | isSWIM into the low byte
        MOVE.L  D0,(A0)                         | to CSParam
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return

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
        MOVE    0x16(A0),D0                     | D0 = ioVRefNum = drive number
        BEQ.B   SONY_CKDRVNUM_ERR               | 0 -> nsDrvErr
        CMPI.W  #0x5,D0                         | drive numbers 1-5 only
        BHI.B   SONY_CKDRVNUM_ERR               | above 5 (unsigned: negative numbers too) -> nsDrvErr
        MOVE.W  Drive(A1),LastDrive(A1)         | LastDrive = previous Drive
        MOVE    D0,Drive(A1)                    | Drive = requested drive
        BSR.W   Sony_GetDrv1                    | GetDrv1: D1 = vars offset of the translated drive
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return (BEQ)
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
| Checks the drive, sets up the SWIM (SetChipMode) when there is one and
| selects the drive, checks for a disk; on the first access to a newly
| inserted disk the drive is powered up in GCR mode, recalibrated, the
| speed table built, the write protection noted (DiskInPlace = 2) and
| ChkDiskType finds out whether the disk is GCR or MFM (720K/1440K).
| HD20 drives (drive 4-5) go to the HD20 prime code instead.
| -------------------------------------------------------------------------
Sony_DiskPrime:
        ORI     #0x100,SR                       | exclude VBL interrupts (IPL 1)
        MOVE    0x6(A0),D3                      | D3 = ioTrap
        BTST    #0x6,0x2D(A0)                   | read-verify mode? (ioPosMode bit 6)
        SNE.B   (DskVerify).w                   | note it in DskVerify
        BSR.B   Sony_CkDrvNum                   | CkDrvNum: check the drive number
        BNE.W   SONY_DISKERR                    | bad drive number -> return the error
        MOVE    D3,Command(A1)                  | Command (+$32) = I/O command (ioTrap)
| check drive is installed
        MOVEQ.L #-0x40,D0                       | noDriveErr (-64): assume no drive
        TST.B   Installed(A1,D1.W)              | Installed: 1 = connected, $FF = not
        BMI.W   SONY_DISKERR                    | not connected -> return the error
        TST.B   isSWIM(A1)                      | isSWIM: SWIM installed?
        BPL.B   SONY_DISKPRIME_SELECT           | no -> skip
        BSR.W   Sony_SetChipMode                | SetChipMode: select the register set for the disk (IWM or ISM)
SONY_DISKPRIME_SELECT:
        BSR.W   Sony_DiskSelect                 | DiskSelect: select the drive
| check drive type and disk insertion
        CMPI.W  #0x4,Drive(A1)                  | HD20 drive (4 or 5)?
        BGE.W   Sony_DCDPrime                   | yes -> HD20 read/write
        MOVEQ.L #0x2,D0                         | DIPAdr: disk-in-place sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when a disk is in place
        BPL.B   SONY_DISKPRIME_CONT             | disk in place ->
| no disk in drive
        CLR.B   DiskInPlace(A1,D1.W)            | DiskInPlace = 0: no disk here
        MOVE.B  #0x80,wZeroes(A0)               | wZeroes = $80: MotorOn off if the ISM registers are selected (IWM: ph3L)
        TST.B   0x1000(A0)                      | mtrOff: cut /ENBL so that the drive does not tick
        MOVEQ.L #-0x41,D0                       | offLinErr (-65): no disk in the drive
        BRA.B   SONY_DISKERR                    | return the error
| first access to this disk: power up, recalibrate, measure speeds
SONY_DISKPRIME_CONT:
        CMPI.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2: already clamped and recalibrated?
        BEQ.B   SONY_CKWRPROT                   | yes -> check write protection
        CLR.B   mfmDisk(A1,D1.W)                | mfmDisk = 0: power up in GCR mode (Apple: "for proper disk chucking")
        TST.B   isSWIM(A1)                      | isSWIM: SWIM installed?
        BPL.B   SONY_DISKPRIME_POWER            | no -> skip
        BSR.W   Sony_SetChipMode                | SetChipMode: switch the SWIM to the IWM register set
SONY_DISKPRIME_POWER:
        BSR.W   Sony_FastPower                  | FastPower: power up (waits only for /READY of a new-interface drive)
        BSR.W   E_Sony_Recal                    | Recal: seek to track 0
        BMI.B   SONY_DSKIMMOFF                  | error -> immediate power-down
        BSR.W   E_Sony_MakeSpdTbl               | MakeSpdTbl: measure the speed of each zone
        BNE.B   SONY_DSKIMMOFF                  | error -> immediate power-down
        MOVEQ.L #0x6,D0                         | WrProtAdr: write-protect sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when write-protected
        SPL.B   WriteProt(A1,D1.W)              | WriteProt = $FF for a write-protected disk
        CLR.B   TwoSideFmt(A1,D1.W)             | TwoSideFmt = 0: assume a one-sided format at first
        MOVE.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2: clamped (recalibrated)
        BRA.W   Sony_ChkDiskType                | ChkDiskType: GCR or MFM? (continues at CkWrProt)
| CkWrProt -- a write to a write-protected disk fails (ChkDiskType ends
| here too)
SONY_CKWRPROT:
        BSR.W   Sony_CheckRead                  | CheckRead: is it a read?
        BEQ.B   SONY_RWPOWER                    | yes -> power up and go
        MOVE    (BufTgFBkNum).w,FirstFSeq(A1)   | FirstFSeq = file block number of the first tag (TagData+8)
        TST.B   WriteProt(A1,D1.W)              | WriteProt: disk write-protected?
        BPL.B   SONY_RWPOWER                    | no -> power up and go
        MOVEQ.L #-0x2C,D0                       | wPrErr (-44): disk is write-protected
| DskRWOff / DskImmOff / POffExit / DiskErr -- the exits of DiskPrime,
| after an error and after the last sector (DskRWOff is also the exit of
| format and verify): start the power-down (DskRWOff: after PwrOffTime,
| DskImmOff: at once), open the interrupts, complete the request
| Branch from: SONY_TODRWOFF, SONY_DISKPRIME_SKIP_3, SONY_TODSKRWOFF, Sony_ChkDiskType, SONY_DRVENT_DSKRWOFF
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
| sector and sector bitmap for the next track to process; MFM disks have
| a different sector layout (mGetTrack, which returns to gtResume)
SONY_GETTRACK:
        MOVE.L  (A1),A2                         | A2 = DCE
        MOVE.L  0x8(A2),A0                      | A0 = current request (dCtlQHead)
        MOVE.L  0x10(A2),D0                     | D0 = dCtlPosition (byte position)
        MOVEQ.L #0x9,D7                         | 2^9 = 512 bytes per block
        LSR.L   D7,D0                           | D0 = block number on the disk
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: MFM disk?
        BMI.W   Sony_mGetTrack                  | yes -> mGetTrack (fixed 9 or 18 sectors per track)
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
| gtResume -- mGetTrack continues here too: D5 = track, D6 = side and
| D0/D2/D3 set up so that D0 - D2 is the first sector wanted and D3 - that
| the number of sectors left on the track
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
        MOVE.L  0x24(A0),D5                     | D5 = ioReqCount
        MOVE.L  0x28(A0),D2                     | D2 = ioActCount (bytes done so far)
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
        MOVE.L  0x20(A0),A3                     | A3 = ioBuffer
        ADDA.L  D2,A3                           | + bytes already done
        MOVE.L  A3,DiskBuffer(A1)               | DiskBuffer = buffer address for the first sector
        LSR.L   D7,D2                           | blocks done so far
        MOVE    D2,FBlksDone(A1)                | FBlksDone (for the file tags)
        MOVE.B  RecalInit(A1),RecalCnt(A1)      | RecalCnt = RecalInit: recals allowed on this track
| CheckCache -- use the track cache when possible
        CLR.B   TCRdEnable(A1)                  | TCRdEnable = 0: assume no reads into the cache
        BSR.W   Sony_CheckRead                  | CheckRead: is it a read?
        BEQ.B   SONY_READCACHE                  | yes -> read through the cache
        BSR.W   Sony_CacheValid                 | CacheValid: cache valid for this drive/side/track?
        BNE.B   SONY_TORESEEK                   | no -> go do the I/O
        MOVE.L  D5,D0                           | bitmap of the sectors being written
        NOT.L   D0                              | = sectors not being written
        AND.L   D0,TCSectMap(A1)                | TCSectMap: drop the sectors we overwrite
SONY_TORESEEK:
        BRA.W   E_Sony_ReSeek                   | go do the I/O
| readCache -- take the sectors that are in the cache
SONY_READCACHE:
        TST.B   (DskVerify).w                   | read-verify?
        BNE.B   SONY_TORESEEK                   | yes -> never from the cache
        BSR.W   Sony_CacheValid                 | CacheValid?
        BNE.W   SONY_RDCACHENV                  | no -> set the cache up for this track
        MOVE.L  D5,D2                           | sectors wanted
        AND.L   TCSectMap(A1),D2                | TCSectMap: and cached?
        BEQ.W   SONY_RC_CONT                    | none -> go do the I/O
        MOVEQ.L #0x2,D7                         | 2
        ASL.L   #0x8,D7                         | * 256 = 512 bytes per sector
        MOVE    D4,D0                           | first sector wanted
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: MFM disk?
        BPL.B   SONY_DISKPRIME_CACHEOFS         | no ->
        SUBQ.W  #0x1,D0                         | MFM sectors are numbered from 1
SONY_DISKPRIME_CACHEOFS:
        MULU    #0x20C,D0                       | * 524 = offset of its entry in the cache
        MOVEA.L TCBuffer(A1),A4                 | A4 = TCBuffer
        ADDA    D0,A4                           | A4 -> cache entry of the first sector
SONY_RC_LOOP:
        BTst    D4,D2                           | sector wanted and cached?
        BEQ.B   SONY_DISKPRIME_SKIP_3           | no -> skip to next sector
        BCLR    D4,D5                           | remove it from the sectors wanted
        MOVEM.L A0-A1,-(SP)                     | preserve A0/A1 over _BlockMove
        TST.L   TagBufPtr(A1)                   | TagBufPtr: separate tag buffer?
        BEQ.B   SONY_DISKPRIME_NO_3             | no -> tags go to TagData
        MOVE    D4,D0                           | current sector
        SUB     FirstSect(A1),D0                | - FirstSect = sector index on this track
        ADD     FBlksDone(A1),D0                | + FBlksDone = block index in the request
        MULU    #0xC,D0                         | * 12 = offset into the tag buffer
        MOVEA.L TagBufPtr(A1),A1                | A1 = tag buffer
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
        ADDQ.W  #0x1,TCNumUsed(A1)              | TCNumUsed: count cache hits
        ADD.L   D7,0x10(A2)                     | dCtlPosition += 512
        ADD.L   D7,0x28(A0)                     | ioActCount += 512
SONY_DISKPRIME_SKIP_3:
        ADDA.L  D7,A3                           | next block in the user buffer
        ADDA.L  D7,A4                           | next cache entry
        ADDA    #0xC,A4                         | (12 tag bytes per entry)
        ADDQ.W  #0x1,D4                         | next sector
        SUBQ.W  #0x1,D3                         | count it
        BNE.B   SONY_RC_LOOP                    | until all sectors of this track are checked
        MOVE.L  D5,SectMap(A1)                  | SectMap = sectors still wanted
        BNE.B   SONY_RC_CONT                    | some left -> read them
        MOVE.L  0x28(A0),D0                     | ioActCount
        CMP.L   0x24(A0),D0                     | compared with ioReqCount
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
        MOVE.W  Drive(A1),TCDrive(A1)           | TCDrive = Drive
        MOVE.W  SideTrack(A1),TCSideTrack(A1)   | TCSideTrack = SideTrack
        CLR.L   TCSectMap(A1)                   | TCSectMap = 0: nothing cached yet
        BRA.B   E_Sony_ReSeek                   | go do the I/O
| TCRdEnbChk -- enable reads into the cache (TCRdEnable) for a
| synchronous call that needs no sectors on another track; BEQ if enabled
Sony_TCRdEnbChk:
        TST.B   TCInstalled(A1)                 | TCInstalled: cache installed and on?
        BEQ.B   SONY_TCRDENBCHK_OFF             | no ->
        BTST    #0xA,Command(A1)                | asynchronous call (ioTrap bit 10)?
        BNE.B   SONY_TCRDENBCHK_SET             | yes -> no caching (NE)
        TST.B   D6                              | last track of the request?
SONY_TCRDENBCHK_SET:
        SEQ.B   TCRdEnable(A1)                  | TCRdEnable = $FF if so
        RTS                                     | return
| SONY_TCRDENBCHK_OFF -- cache not installed: set D6=1 to skip caching
SONY_TCRDENBCHK_OFF:
        MOVEQ.L #0x1,D6                         | force NE
        BRA.B   SONY_TCRDENBCHK_SET             | TCRdEnable = 0
| CacheValid -- BEQ if the cache holds data of the current drive and
| side/track
Sony_CacheValid:
        TST.B   TCInstalled(A1)                 | TCInstalled: installed and on?
        BEQ.B   SONY_CACHEVALID_NO              | no -> not valid
        MOVE.W  TCDrive(A1),D0                  | TCDrive
        BEQ.B   SONY_CACHEVALID_NO              | 0 -> not valid
        CMP     Drive(A1),D0                    | same drive?
        BNE.B   SONY_CACHEVALID_NO              | no -> not valid
        MOVE    SideTrack(A1),D0                | current side/track
        SUB.W   TCSideTrack(A1),D0              | - TCSideTrack
        BEQ.B   SONY_CACHEVALID_EXIT            | same -> valid (D0 = 0)
SONY_CACHEVALID_NO:
        MOVEQ.L #-0x1,D0                        | not valid
SONY_CACHEVALID_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| ReSeek -- jump through the JReSeek vector.
| -------------------------------------------------------------------------
| Branch from: SONY_TORESEEK, SONY_RC_CONT, SONY_RDCACHENV, SONY_DORECAL
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
        BMI.B   SONY_ONTRACK                    | yes -> no speed check
        LSR     #0x4,D6                         | D6 = zone (16 tracks per zone)
        LSL     #0x3,D6                         | * 8 = offset of the zone entry
        LEA.L   TrkSpeedTbl(A1,D1.W),A2         | A2 -> TrkSpeedTbl in the drive vars
        LEA.L   0x4(A2,D6.W),A2                 | A2 -> time of the last check of this zone
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
        CLR.L   0x4(A2)                         | force a recheck next time
SONY_RESEEK_NO:
        ADDQ.W  #0x1,SpdAdjCnt(A1,D1.W)         | SpdAdjCnt: count speed adjustments
        SUBQ.B  #0x1,BadSpdCnt(A1)              | BadSpdCnt: adjustments left?
        BPL.B   SONY_RESEEK1                    | yes -> seek (sets the new speed) and check again
        MOVEQ.L #-0x4F,D0                       | spdAdjErr (-79): speed cannot be adjusted
SONY_TODORECAL:
        BRA.W   SONY_DORECAL                    | recal or give up
| OnTrack -- DiskPrime part IV: read each address mark passing under the
| head; read or write the sector when it is wanted, optionally read other
| sectors of the track into the track cache.
|   current file block = FirstFSeq + FBlksDone + (sector - FirstSect)
|   tag buffer offset  = [FBlksDone + (sector - FirstSect)] * 12
| MFM disks (mfmDisk) use a fixed 7.5 ms sector time and sector numbers
| starting at 1 (Apple's C437 changes).
| Branch from: SONY_RESEEK1, SONY_RESEEK_CONT_2, SONY_RESEEK_CONT_4, SONY_RESEEK_DONE, SONY_RESEEK_RETRY_3
SONY_ONTRACK:
        MOVE.B  WrgSectInit(A1),WrgSectCnt(A1)  | WrgSectCnt = WrgSectInit: wrong sectors tolerated
SONY_ONTRACK1:
        MOVE    D1,D6                           | OnTrack1: D6 = drive vars offset
        BSR.W   SONY_TAIL_RDADDRSETUP           | RdAddrSetup (tail): read the next address mark
        BMI.W   SONY_ADRDTAERR                  | error -> AdrDtaErr
        CMP     SideTrack(A1),D1                | right side and track?
        BNE.W   SONY_WRGSIDETRK                 | no -> WrgSideTrk
        MOVE.W  D2,CurSector(A1)                | CurSector = sector number
        MOVE    D2,(TagData).w                  | TagData+0 = sector number (for writes)
        MOVE.L  SectMap(A1),D0                  | sectors wanted on this track
        BTST    D2,D0                           | is this one of them?
        BNE.W   SONY_OTSETUP                    | yes -> read or write it
| not wanted: read it into the track cache if caching this track
        TST.B   TCRdEnable(A1)                  | TCRdEnable: reading into the cache?
        BEQ.W   SONY_WRGSECTADR                 | no -> WrgSectAdr
        MOVE.L  TCSectMap(A1),D0                | TCSectMap
        BTST    D2,D0                           | already cached?
        BNE.W   SONY_WRGSECTADR                 | yes -> WrgSectAdr
        LEA.L   SONY_TAIL_RDDATA(PC),A0         | A0 = initial JRdData vector (SONY_TAIL_RDDATA)
        CMPA.L  (DiskVars_JRdData).w,A0         | JRdData still the driver's own?
        SNE.B   TCRdEnable(A1)                  | TCRdEnable = 0 if RdData is patched (copy protection)
        BNE.W   SONY_WRGSECTADR                 | patched -> do not cache
        MOVE    D2,D1                           | D1 = sector number
        TST.B   mfmDisk(A1,D6.W)                | mfmDisk: MFM disk? (D6 = drive vars offset)
        BPL.B   SONY_RESEEK_CACHEOFS            | no ->
        SUBQ.W  #0x1,D2                         | MFM sectors are numbered from 1
SONY_RESEEK_CACHEOFS:
        MULU    #0x20C,D2                       | * 524 = cache entry offset
        MOVEA.L TCBuffer(A1),A0                 | A0 = TCBuffer
        ADDA.L  D2,A0                           | A0 -> cache entry
        ADDA    #0xC,A0                         | A0 -> data part (after the 12 tag bytes)
        BSR.W   SONY_TAIL_READDATA              | RdData (tail) into the cache
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1/D1 again (RdData destroys them)
        MOVE.W  D1,D6                           | D6 = drive vars offset again
        TST.W   D0                              | CCR = RdData result
        SPL.B   TCRdEnable(A1)                  | TCRdEnable = 0 after an error
        BMI.B   SONY_ONTRACK_CACHEDONE          | error -> ignore (may be a copy-protected sector)
        ADDQ.W  #0x1,TCNumCached(A1)            | TCNumCached: count cached sectors
        MOVE.W  CurSector(A1),D2                | D2 = CurSector
        MOVEA.L TCBuffer(A1),A0                 | A0 = TCBuffer
        MOVE    D2,D1                           | sector number
        TST.B   mfmDisk(A1,D6.W)                | mfmDisk: MFM disk?
        BPL.B   SONY_RESEEK_CACHETAGS           | no ->
        SUBQ.W  #0x1,D1                         | MFM sectors are numbered from 1
SONY_RESEEK_CACHETAGS:
        MULU    #0x20C,D1                       | * 524
        ADDA.L  D1,A0                           | A0 -> cache entry
        LEA.L   (BufTgFNum).w,A2                | A2 -> TagData+2: tags just read
        MOVE.L  (A2)+,(A0)+                     | copy the 12 tag bytes
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 5-8
        MOVE.L  (A2)+,(A0)+                     | copy tag bytes 9-12
        MOVE.L  TCSectMap(A1),D4                | TCSectMap
        BSET    D2,D4                           | mark the sector as cached
        MOVE.L  D4,TCSectMap(A1)                | update the map
SONY_ONTRACK_CACHEDONE:
        BSet    #0x7,(IntFlag).w                | interrupts to be opened for AppleTalk?
        BNE.B   SONY_RESEEK_POLLONLY            | no -> just poll data
        MOVE    SectTime(A1),D0                 | one sector time
        TST.B   mfmDisk(A1,D6.W)                | mfmDisk: MFM disk?
        BPL.B   SONY_RESEEK_WAITSECT            | no ->
        MOVEQ.L #0x4B,D0                        | MFM: fixed sector time 7.5 ms (75 * 100 us)
SONY_RESEEK_WAITSECT:
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
        CMPI.B  #0x1F,D3                        | format byte > $1F: two-sided format
        SGT.B   TwoSideFmt(A1,D6.W)             | TwoSideFmt = $FF for two-sided
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
        MOVE.W  D1,TagBufOS(A1)                 | TagBufOS
        BSR.W   Sony_CheckRead                  | CheckRead: a read?
        BEQ.B   SONY_OTREAD                     | yes -> OTRead
| OTWrite -- write the sector
        MOVE.L  TagBufPtr(A1),D3                | TagBufPtr: separate tag buffer?
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
        BSR.W   E_Sony_WrData                   | E_Sony_WrData: write the sector
        BMI.W   SONY_ADRDTAERR                  | error -> AdrDtaErr
        BRA.B   SONY_GOTSECT                    | sector done
| OTRead -- read the sector
SONY_OTREAD:
        BSR.W   SONY_TAIL_READDATA              | RdData (tail): read the sector
        BMI.W   SONY_ADRDTAERR                  | error -> AdrDtaErr
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.L  TagBufPtr(A1),D0                | TagBufPtr: separate tag buffer?
        BEQ.B   SONY_GOTSECT                    | no -> done
        MOVE.L  D0,A0                           | A0 = tag buffer
        ADDA.W  TagBufOS(A1),A0                 | + TagBufOS
        LEA.L   (BufTgFNum).w,A2                | A2 -> TagData+2: tags just read
        MOVE.L  (A2)+,(A0)+                     | copy the 12 tag bytes
        MOVE.L  (A2)+,(A0)+                     | tag bytes 5-8
        MOVE.L  (A2)+,(A0)+                     | tag bytes 9-12
| GotSect -- mark the sector done, update position and byte count, then
| continue with the track (or the next track)
SONY_GOTSECT:
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1
        MOVE.L  SectMap(A1),D4                  | sector map
        MOVE.W  CurSector(A1),D2                | CurSector
        BCLR    D2,D4                           | this sector is done
        MOVE.L  D4,SectMap(A1)                  | update the map
        MOVE.L  (A1),A2                         | A2 = DCE
        MOVE.L  0x8(A2),A0                      | A0 = request (dCtlQHead)
        MOVEQ.L #0x2,D3                         | 2
        ASL.L   #0x8,D3                         | * 256 = 512
        ADD.L   D3,0x10(A2)                     | dCtlPosition += 512
        ADD.L   D3,0x28(A0)                     | ioActCount += 512
        MOVE.L  0x24(A0),D3                     | ioReqCount
        SUB.L   0x28(A0),D3                     | D3 = 0 when the request is done
        BSET    #0x7,(IntFlag).w                | interrupts to be opened for AppleTalk?
        BEQ.B   SONY_RESEEK_NO_3                | yes -> wait a sector time with interrupts open
        BSR.B   Sony_CheckRead                  | CheckRead: read?
        BEQ.B   SONY_RESEEK_CONT_7              | yes -> continue (1-1 possible)
        TST.L   D4                              | last sector on this track?
        BNE.B   SONY_RESEEK_WRNEXT              | no -> 1-1 writes only for MFM disks
        BSR.B   Sony_EmptyPD                    | EmptyPD
        MOVEQ.L #0x7,D0                         | 700 us
        BSR.W   Sony_CallWakeUp                 | WakeUp: let the erase head turn off after the last write
        BRA.B   SONY_RESEEK_DONE                | continue
SONY_RESEEK_WRNEXT:
        TST.B   mfmDisk(A1,D6.W)                | mfmDisk: MFM disk?
        BMI.B   SONY_RESEEK_CONT_7              | yes -> continue at once (MFM writes 1-1)
| wait a sector time with interrupts open
SONY_RESEEK_NO_3:
        MOVE    SectTime(A1),D0                 | one sector time
        TST.B   mfmDisk(A1,D6.W)                | mfmDisk: MFM disk?
        BPL.B   SONY_RESEEK_WAITSECT_2          | no ->
        MOVEQ.L #0x4B,D0                        | MFM: fixed sector time 7.5 ms
SONY_RESEEK_WAITSECT_2:
        BSR.W   SONY_WAKESETUP                  | WakeSetUp
        BSR.B   Sony_EmptyPD                    | EmptyPD
        BSR.W   SONY_WAKEUP_GO                  | WakeGo: wait, interrupts open
        BRA.B   SONY_RESEEK_DONE                | continue
| a read: continue at once (1-1 reads are possible)
SONY_RESEEK_CONT_7:
        BSR.B   Sony_EmptyPD                    | EmptyPD
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
        CMPI.B  #0x2,Command+1(A1)              | low byte of Command: ARdCmd?
        RTS                                     | return

| -------------------------------------------------------------------------
| EmptyPD -- call the poll data procedure (PollProc, set by the serial
| driver) to process serial data that was put on the stack while
| interrupts were off, or reset the stack to PollStack if there is none.
| -------------------------------------------------------------------------
| Called by: SONY_RESEEK_WAITSECT, SONY_RESEEK_POLLONLY, SONY_GOTSECT, SONY_RESEEK_WAITSECT_2, SONY_RESEEK_CONT_7 (and 6 more)
Sony_EmptyPD:
        MOVE.L  (SP)+,A4                        | A4 = return address
        PEA.L   SONY_EMPTYPD_RESUME(PC)         | PollProc returns to SONY_EMPTYPD_RESUME
        MOVE.L  (PollProc).w,-(SP)              | PollProc installed?
        BEQ.B   SONY_EMPTYPD_NOPROC             | no -> throw the data away
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVEM.L D0/D2-D3/A0/A4,SaveRegs(A1)     | save D0/D2/D3/A0/A4 in SaveRegs
        RTS                                     | go to PollProc
| SONY_EMPTYPD_RESUME -- PollProc resume point: restore registers
SONY_EMPTYPD_RESUME:
        BSR.W   Sony_GetDrv1                    | GetDrv1
        MOVEM.L SaveRegs(A1),D0/D2-D3/A0/A4     | restore D0/D2/D3/A0/A4
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
        ADDQ.W  #0x1,DiskErrs(A1)               | DiskErrs: global soft error count
        ADDQ.W  #0x1,DriveErrs(A1,D1.W)         | DriveErrs: drive soft error count
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
        TST.B   mfmDisk(A1,D6.W)                | mfmDisk: MFM disk?
        BPL.B   SONY_RESEEK_WAITSECT_3          | no ->
        MOVEQ.L #0x4B,D0                        | MFM: fixed sector time 7.5 ms
SONY_RESEEK_WAITSECT_3:
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
| DrvVarOS -- offset of each drive's variables in SonyVars, for physical
| drive numbers 1-5 (indexed with drive*2, hence DRVVAROFS-2 below). The
| floppy drives are at the same offsets as in the 1987 SE driver; the
| HD20 variables are 6 bytes higher ($17E/$19A, SE: $178/$194) because
| drvTblPtr, isSWIM and mfmMode were inserted at $178-$17D.
DRVVAROFS:
        .short  Drive1                          | drive 1: lower internal floppy ($4A)
        .short  Drive2                          | drive 2: upper internal floppy ($8C)
        .short  Drive3                          | drive 3: external floppy ($CE)
        .short  Drive4                          | drive 4: first HD20 ($17E; SE: $178)
        .short  Drive5                          | drive 5: second HD20 ($19A; SE: $194)
| GetRDrive, GetDrive, GetDrv1, GetDrv2 -- set up the much-used registers
|   A0 (out) -- IWM base (GetRDrive, GetDrive)
|   A2 (out) -- VIA base (GetRDrive, GetDrive)
|   A1 (out) -- SonyVars
|   D1 (out) -- offset of the current drive's variables
| GetDrive and GetDrv1 translate Drive (a logical drive number) through
| the table at driveXlat; GetRDrive does not translate (it is not
| called in this ROM, as in the 1987 SE driver). Drive numbers above 5
| (the pass-thru probe in DiskOpen uses 6) are bounded to 5.
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
| Called by: Sony_CkDrvNum, SONY_RESEEK_CACHEOFS, SONY_GOTSECT, SONY_EMPTYPD_RESUME, SONY_EMPTYPD_NOPROC (and 14 more)
Sony_GetDrv1:
        BSR.B   Sony_GetDrv2                    | GetDrv1: A1 = SonyVars, D1 = logical drive * 2
        LEA.L   driveXlat(A1),A1                | A1 -> drive number translation table
        MOVE.W  0x0(A1,D1.W),D1                 | D1 = physical drive number
        MOVEA.L (SonyVars).w,A1                 | A1 = SonyVars again
        ADD.W   D1,D1                           | * 2
        MOVE.W  DRVVAROFS-2(PC,D1.W),D1         | D1 = drive vars offset
        RTS                                     | return
| GetDrv2 -- A1 = SonyVars, D1 = Drive * 2 (Drive bounded to 5)
Sony_GetDrv2:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        MOVE    Drive(A1),D1                    | D1 = Drive
        CMPI.W  #0x5,D1                         | above the last drive number?
        BLS.B   SONY_GETDRV3                    | 0-5 (unsigned compare) -> use it
        MOVEQ.L #0x5,D1                         | else drive number 5
SONY_GETDRV3:
        ADD     D1,D1                           | D1 = drive number * 2
        RTS                                     | return

| -------------------------------------------------------------------------
| AdrDisk -- address one of the 16 drive registers
|   D0 (in) -- register address, bits 0-3 = CA2, SEL, CA0, CA1 (Apple's
|              order CA1-CA0-SEL-CA2, bit 3 to bit 0)
| CA0-CA2 are IWM phase lines 0-2, SEL is VIA port A bit 5 (vHeadSel).
| CA0 = CA1 = 1 must be true while SEL changes from 1 to 0 (Apple's
| comment), hence both are set first. With the ISM
| register set selected (mfmMode) the phase lines are set through the
| ISM phase register instead (mAdrDisk).
| -------------------------------------------------------------------------
| Called by: SONY_CTL_EJECT_PULSE, Sony_AdrAndSense, Sony_AdrAndStrb, Sony_FigTrkSpd, SONY_MDOFORMAT_HEAD (and 1 more)
Sony_AdrDisk:
        BSR.B   Sony_GetDrive                   | GetDrive: A0 = IWM, A2 = VIA, A1, D1
        TST.B   mfmMode(A1)                     | mfmMode: ISM register set selected?
        BMI.W   Sony_mAdrDisk                   | yes -> mAdrDisk
        TST.B   0x200(A0)                       | CA0 high (ph0H)
        TST.B   0x600(A0)                       | CA1 high (ph1H)
        LSR.B   #0x1,D0                         | bit 0: CA2
        BCC.B   SONY_ADRDISK_CONT               | 0 ->
        TST.B   0xA00(A0)                       | CA2 high (ph2H)
        BRA.B   SONY_ADRDISK_CONT_2             | ->
SONY_ADRDISK_CONT:
        TST.B   0x800(A0)                       | CA2 low (ph2L)
SONY_ADRDISK_CONT_2:
        LSR.B   #0x1,D0                         | bit 1: SEL
        BCC.B   SONY_ADRDISK_CONT_3             | 0 ->
        BSET    #0x5,0x1E00(A2)                 | SEL high: VIA port A bit 5
        BRA.B   SONY_ADRDISK_SKIP               | ->
SONY_ADRDISK_CONT_3:
        BClr    #0x5,0x1E00(A2)                 | SEL low
SONY_ADRDISK_SKIP:
        LSR.B   #0x1,D0                         | bit 2: CA0
        BCS.B   SONY_ADRDISK_CONT_4             | 1 -> leave it high
        TST.B   (A0)                            | CA0 low (ph0L)
SONY_ADRDISK_CONT_4:
        LSR.B   #0x1,D0                         | bit 3: CA1
        BCS.B   SONY_ADRDISK_CONT_5             | 1 -> leave it high
        TST.B   0x400(A0)                       | CA1 low (ph1L)
SONY_ADRDISK_CONT_5:
        RTS                                     | return
| AdrAndSense / Sense -- read the sense line of a drive register
|   D0 (in)  -- register address (AdrAndSense only)
|   D0 (out) -- status byte; the sense line is bit 7 (BMI = 1)
| With the ISM registers selected the sense line is bit 3 of the ISM
| handshake register (mSense); with the IWM it is bit 7 of the status
| register, which is read in state L7 = 0, L6 = 1 from a clearing
| location (q7L).
| Called by: CHKCONNECT, SONY_CTL_EJECT_GO, SONY_NEWDRVEJECT_LOOP, SONY_DISKPRIME_SELECT, SONY_DISKPRIME_POWER (and 11 more)
Sony_AdrAndSense:
        BSR.B   Sony_AdrDisk                    | AdrAndSense: address the register
| Sense -- read the sense line of the register addressed before
Sony_Sense:
        TST.B   mfmMode(A1)                     | Sense: mfmMode: ISM register set selected?
        BMI.W   Sony_mSense                     | yes -> mSense
SONY_SENSE_IWM:
        MOVE    SR,-(SP)                        | IWM: save the interrupt level
        ORI     #0x300,SR                       | no interrupts
        TST.B   0x1A00(A0)                      | q6H: L6 = 1 (with L7 = 0: status register)
        MOVE.B  0x1C00(A0),D0                   | read at q7L: status register, bit 7 = SENSE
        TST.B   0x1800(A0)                      | q6L: L6 = 0, back to the read state
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST.B   D0                              | N = sense line
        RTS                                     | return
| AdrAndStrb / Pulse -- pulse LSTRB (phase line PH3) to perform a drive
| control function: the drive takes CA2 as the value for the control
| register addressed by CA1, CA0 and SEL
|   D0 (in) -- control register address (AdrAndStrb only)
| With the ISM registers selected LSTRB (PHASE3) is pulsed through the
| phase register (mPulse).
| Called by: SONY_SEEKLP_DIR, Sony_Recal, SONY_POWERDOWN_NOW, SONY_POWERUP_SETMODE, Sony_DiskVBLTask (and 1 more)
Sony_AdrAndStrb:
        BSR.B   Sony_AdrDisk                    | AdrAndStrb: address the register
| Pulse -- pulse LSTRB for the register addressed before
Sony_Pulse:
        TST.B   mfmMode(A1)                     | Pulse: mfmMode: ISM register set selected?
        BMI.W   Sony_mPulse                     | yes -> mPulse
SONY_PULSE_IWM:
        MOVE    SR,-(SP)                        | IWM: save the interrupt level
        ORI     #0x300,SR                       | no interrupts
        TST.B   0xE00(A0)                       | ph3H: LSTRB high, the drive executes the command
        NOP                                     | (pulse width)
        NOP                                     | (pulse width)
        TST.B   0xC00(A0)                       | ph3L: LSTRB low
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return
| CkDCDExist -- is an HD20 connected at the selected position?
| An HD20 shows /DrvExst = 1 and /Sides = 1 (like no floppy drive) and
| asserts its /Exist line (register address 5).
|   D0 (out) -- MI: no HD20; PL: HD20 present (D0 = status byte)
Sony_CkDCDExist:
        MOVEQ.L #0xD,D0                         | DrvExstAdr (13)
        BSR.B   Sony_AdrAndSense                | sense = 0: a floppy drive is connected
        BPL.B   SONY_CKDCDEXIST_NONE            | floppy (or nothing) -> no HD20
        TST.B   (A0)                            | CA0 low: register 9 (SidesAdr)
        BSR.B   Sony_Sense                      | Sense
        BPL.B   SONY_CKDCDEXIST_NONE            | sense = 0 -> no HD20
        TST.B   0x200(A0)                       | CA0 high,
        TST.B   0x400(A0)                       | CA1 low: register 5 (dcdExist)
        BSR.B   Sony_Sense                      | Sense: 0 = HD20 present
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
        TST.B   NewIntf(A1,D1.W)                | NewIntf: new-interface drive?
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
        MOVE.B  SONY_SETSPEED_CONT_6+1(PC,D2.W),D5 | D5.lo = dither pattern LSB
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
| bytes of a group of 10 that get the later LFSR state (as in the 1987
| SE driver)
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
| jtSeek (JSeek vector) -- step the head from Track to D6; the step loop
| was rewritten for the SuperDrive (Apple's C437, 17 Jun 87): the step
| direction is set once, then for each step /STEP must be high before
| the pulse, and Wait100 waits until it is high again (cantStepErr if
| not). With the ISM registers selected the parameter RAM is set up for
| the new track zone (SetParams). After the last step the first /READY
| check comes 500 us later: a SuperDrive's /READY is not valid for 150
| us after a step (hand notes on floppy stuff).
Sony_Seek:
        MOVE.L  (SP)+,A6                        | save return address
        BSR.W   Sony_GetDrv1                    | set up SonyVars (A1) and drive vars
        MOVE    Track(A1,D1.W),D7               | D7 = current track
        BPL.B   SONY_SEEKLP                     | valid ->
| current track unknown: recalibrate
        BSR.W   E_Sony_Recal                    | Recal
        MOVE    D0,D7                           | D7 = result (track 0 or error)
        BRA.B   SONY_SEEKEND                    | SeekEnd with the Recal result (no seek)
SONY_SEEKLP:
        MOVEQ.L #0x0,D0                         | SeekLp: assume step in (DirLAdr, toward higher tracks)
        MOVE.W  D6,D5                           | D5 = number of steps...
        SUB.W   D7,D5                           | ...= destination - current track
        BEQ.B   SONY_SEEKEND1                   | already there -> SeekEnd1: no head settle time, just wait out any speed change
        BGT.B   SONY_SEEKLP_DIR                 | step in ->
        MOVEQ.L #0x1,D0                         | DirHAdr: step out (toward track 0)
        NEG.W   D5                              | make the step count positive
SONY_SEEKLP_DIR:
        BSR.W   Sony_AdrAndStrb                 | AdrAndStrb: set the stepper direction
        MOVEQ.L #-0x4B,D7                       | cantStepErr (-75): assume one of the steps fails
        SUBQ.W  #0x1,D5                         | -1 for DBF
SONY_SEEKLP1:
        MOVEQ.L #0x4,D0                         | StepLAdr: /STEP sense
        BSR.W   Sony_AdrAndSense                | must be high before the step
        BPL.B   SONY_SEEKEND                    | low -> SeekEnd with cantStepErr
        BSR.W   Sony_Pulse                      | Pulse: step (/STEP goes low)
        BSR.B   SONY_WAIT100                    | Wait100: wait until /STEP is high again
        DBF     D5,SONY_SEEKLP1                 | next step
        MOVE.W  D6,D7                           | all steps done: D7 = new track
| SeekEnd -- store the track (D7: track or error code), with the ISM
| registers selected set up the parameter RAM for the zone, then wait
| for the head to settle (or for /READY on a new-interface drive) and
| for any speed change
SONY_SEEKEND:
        BSR.W   Sony_GetDrv1                    | SeekEnd: GetDrv1 (restores D1 = drive vars offset)
        MOVE    D7,Track(A1,D1.W)               | Track = new track
        TST.B   mfmMode(A1)                     | mfmMode: ISM register set selected?
        BPL.B   SONY_SEEKEND_SETTLE             | no ->
        BSR.W   Sony_SetParams                  | SetParams: parameter RAM for this zone
        BEQ.B   SONY_SEEKEND_SETTLE             | ok ->
        MOVE.W  D0,D7                           | error: return it
SONY_SEEKEND_SETTLE:
        MOVE    HeadSettle(A1),D0               | HeadSettle: 30 ms head settle time
        MOVEQ.L #0x5,D2                         | new drives: wait 500 us before checking /READY
        BSR.B   SONY_WAITREADY                  | waitReady
SONY_SEEKEND1:
        MOVE    Wait(A1),D0                     | Wait: speed change or power-on time still to go
        MOVEQ.L #0x0,D2                         | no first wait
        BSR.B   SONY_WAITREADY                  | waitReady
        MOVE    D7,D0                           | D0 = result
        JMP     (A6)                            | return
| Wait100 -- wait for a step: SeekTime for an old drive, else poll
| /STEP until it goes high again (at most 81 times)
SONY_WAIT100:
        MOVE    SeekTime(A1),D0                 | SeekTime: 12 ms
        BSR.B   SONY_CHECKNEW                   | CheckNew: old drive -> WakeUp for D0 and return
        MOVEQ.L #0x50,D2                        | poll count
SONY_WAIT100_LOOP:
        MOVEQ.L #0x4,D0                         | StepLAdr
        BSR.W   Sony_AdrAndSense                | sense
        DBMI    D2,SONY_WAIT100_LOOP            | until /STEP is high again
        RTS                                     | return
| CheckNew -- for an old-interface (400K) drive, wait D0 with WakeUp and
| return to the caller's caller; return at once for a new drive
SONY_CHECKNEW:
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BMI.B   SONY_CHECKNEW_EXIT              | new interface -> return at once (no WakeUp)
| SONY_CHECKNEW_WAIT -- 400K drive: pop caller's return, wait D0 * 100 us
SONY_CHECKNEW_WAIT:
        ADDQ.W  #0x4,SP                         | drop our caller's return address
        TST     D0                              | any time to wait?
        BNE.B   Sony_CallWakeUp                 | time to wait -> WakeUp (through Sony_CallWakeUp)
| SONY_CHECKNEW_EXIT -- no delay needed
SONY_CHECKNEW_EXIT:
        RTS                                     | return
| waitReady -- wait for /READY of a new-interface drive
|   D0 (in) -- wait time for an old drive (100 us units)
|   D2 (in) -- first wait before polling /READY (100 us units, 0 = none)
| /READY is polled every 1 ms; after about 1 s the drive is taken as
| ready anyway (Apple: "if we timeout, we must be ready??"; hand notes:
| a SuperDrive's /READY comes at most 600 ms after motor-on). Returns to
| one level above the caller while waiting.
SONY_WAITREADY:
        BSR.B   SONY_CHECKNEW                   | CheckNew: old drive -> just wait D0
        MOVE.L  (SP)+,A4                        | A4 = return address
        MOVE    #0x3E8,D5                       | at most 1000 * 1 ms
        MOVE    D2,D0                           | first wait
        BEQ.B   SONY_WAITREADY_SENSE            | none -> check at once
SONY_WAITREADY_LOOP:
        BSR.B   Sony_CallWakeUp                 | WakeUp
SONY_WAITREADY_SENSE:
        MOVEQ.L #0xB,D0                         | ReadyAdr: /READY sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when ready
        BPL.B   SONY_WAITREADY_DONE             | ready ->
        MOVEQ.L #0xA,D0                         | then check every 1 ms
        DBF     D5,SONY_WAITREADY_LOOP          | until ready or 1 s has passed
SONY_WAITREADY_DONE:
        CLR     Wait(A1)                        | Wait = 0: no extra wait time
        JMP     (A4)                            | return

| -------------------------------------------------------------------------
| CallWakeUp -- WakeUp entry used throughout this driver: go through the
| JWakeUp vector only if the routine it points to starts with a NOP
| ($4E71), else call jtWakeUp directly. Apple (Sony driver history 1.1,
| 18 Apr 88): WakeUp and DiskSelect "are patched in the system disk 5.0
| patches, and executing those patches with the new SuperDrive roms would
| cause the system to crash"; patches meant for this ROM mark themselves
| with a leading NOP. Sony_DiskSel1 does the same for JDiskSel.
| -------------------------------------------------------------------------
| Called by: SONY_CTL_EJECT_PULSE, SONY_CTL_EJECT_CKNEW, SONY_NEWDRVEJECT_LOOP, SONY_GOTSECT, SONY_CHECKNEW_WAIT (and 9 more)
Sony_CallWakeUp:
        MOVE.L  A0,-(SP)                        | save A0
        MOVEA.L (DiskVars_JWakeUp).w,A0         | A0 = routine in the JWakeUp vector
        CMPI.W  #0x4E71,(A0)                    | does it start with a NOP?
        MOVEA.L (SP)+,A0                        | restore A0
        BNE.B   Sony_WakeUp                     | no -> ignore the vector, use jtWakeUp (else fall into E_Sony_WakeUp)

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
E_Sony_WakeUp:
        MOVE.L  (DiskVars_JWakeUp).w,-(SP)      | push the JWakeUp vector
        RTS                                     | and jump through it
| jtWakeUp (JWakeUp vector)
Sony_WakeUp:
        MOVEM.L D3-D7/A3-A6,SaveRegs(A1)        | save the caller's registers first
        MOVE.L  (SP)+,(DskRtnAdr).w             | return address -> DskRtnAdr
        BSR.B   SONY_WAKESETUP                  | WakeSetUp: prime the timer
        BRA.B   SONY_WAKEUP_RET                 | return to the caller's caller
| WakeGo -- wait set up by WakeSetUp: save the state and return
SONY_WAKEUP_GO:
        MOVEM.L D3-D7/A3-A6,SaveRegs(A1)        | WakeGo: save the caller's registers
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
        LEA.L   TimeQEl(A1),A0                  | A0 -> TimeQEl
        LEA.L   SONY_GOWAKEIT(PC),A1            | GoWakeIt
        MOVE.L  A1,0x6(A0)                      | tmAddr = GoWakeIt
        ANDI.L  #0xFFFF,D0                      | clear the high word of D0
        CMPI    #0xA,D0                         | at least 10 * 100 us
        BCC.B   SONY_WAKESETUP_2                | yes ->
        MOVEQ.L #0xA,D0                         | else 1 ms
SONY_WAKESETUP_2:
        DIVU    #0xA,D0                         | / 10 = milliseconds
        EXT.L   D0                              | PrimeTime takes a long count
        MOVE.L  (0x568).w,A1                    | A1 = jPrimeTime vector
        JSR     (A1)                            | PrimeTime (A0 = TimeQEl)
        BRA.W   Sony_GetDrv1                    | restore A1/D1 and return
| GoWakeIt -- Time Manager task: resume the waiting caller
SONY_GOWAKEIT:
        MOVEM.L D0-D7/A0-A6,-(SP)               | save all registers
        BSR.W   Sony_GetDrive                   | GetDrive
        MOVEM.L SaveRegs(A1),D3-D7/A3-A6        | restore the caller's D3-D7/A3-A6
        MOVEQ.L #0x0,D0                         | D0 = 0
        BSR.W   SONY_DSKRTN                     | DskRtn: call the routine at DskRtnAdr
        MOVEM.L (SP)+,D0-D7/A0-A6               | restore the registers
SONY_GOWAKEIT_EXIT:
        RTS                                     | return to the Time Manager

| -------------------------------------------------------------------------
| Recal -- recalibrate: step out to track 0 (D7 = 80: at most 79 steps)
|   D0 (out) -- 0 or an error code, also stored as the current track
| Selects the register set first (SetChipMode). Returns to one level
| above the caller while waiting (A5 = return address).
| -------------------------------------------------------------------------
| Called by: SONY_CTL_EJECT, SONY_DISKPRIME_POWER, SONY_DORECAL, Sony_Seek, SONY_CHKDISKTYPE_MFM
E_Sony_Recal:
        MOVE.L  (DiskVars_JRecal).w,-(SP)       | push Recal vector address
        RTS                                     | dispatch to Sony_Recal
| jtRecal (JRecal vector) -- select the register set for the disk
| (SetChipMode; SetIWMMode on the 1987 SE), power the drive up again and
| step out until track 0 is sensed.
Sony_Recal:
        MOVE.L  (SP)+,A5                        | A5 = return address
        BSR.W   Sony_GetDrive                   | GetDrive
        BSR.W   SONY_INVALTRKCACHE              | InvalTrkCache
        BSR.W   Sony_SetChipMode                | SetChipMode: initialize the register set (IWM or SWIM)
        BNE.B   SONY_RECAL_ERR_2                | could not set it up -> return the error
        BSR.W   Sony_RWPowerUp                  | RWPowerUp: re-enable the interface
        MOVEQ.L #0x50,D7                        | D7 = 80: at most 79 steps
        MOVEQ.L #0x1,D0                         | DirHAdr: step out (toward track 0)
        BSR.W   Sony_AdrAndStrb                 | AdrAndStrb: set the direction once
| SlowLoop -- one step per SeekTime (half of it for new-interface drives)
SONY_RECAL_CONT:
        MOVE    SeekTime(A1),D0                 | SeekTime: 12 ms
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BPL.B   SONY_RECAL_CONT_2               | no -> full time
        LSR     #0x1,D0                         | yes -> 6 ms
SONY_RECAL_CONT_2:
        BSR.W   Sony_CallWakeUp                 | WakeUp
        MOVEQ.L #0xA,D0                         | Tk0Adr: track 0 sense
        BSR.W   Sony_AdrAndSense                | sense = 0 at track 0
        BPL.B   SONY_RECAL_DONE                 | there -> done
        MOVEQ.L #0x4,D0                         | StepLAdr: /STEP sense
        BSR.W   Sony_AdrAndSense                | sense = 1 when ready to step
        BPL.B   SONY_RECALFAIL                  | not ready -> cantStepErr
        MOVEQ.L #-0x4C,D0                       | tk0BadErr (-76) if we run out of steps
        SUBQ.W  #0x1,D7                         | count the step
        BEQ.B   SONY_RECAL_ERR_2                | 79 steps without track 0 -> error
        BSR.W   Sony_Pulse                      | Pulse: step
        BRA.B   SONY_RECAL_CONT                 | again
SONY_RECALFAIL:
        MOVEQ.L #-0x4B,D0                       | cantStepErr (-75): no step possible, not at track 0
        BRA.B   SONY_RECAL_ERR_2                | return it
| SONY_RECAL_DONE -- reached track 0 successfully
SONY_RECAL_DONE:
        MOVEQ.L #0x0,D0                         | track 0
SONY_RECAL_ERR_2:
        MOVE    D0,Track(A1,D1.W)               | Track = 0 or error code
        JMP     (A5)                            | return

| -------------------------------------------------------------------------
| SetIWMMode -- make sure the IWM mode register holds $17: bit 0 latch
| mode, 1 asynchronous handshake, 2 1-second timer disabled, 3 = 0 slow
| mode, 4 FCLK divided by 8 (IWM Design Spec, SWIM Chip User's
| Reference). The slow-mode bit cell is 32 FCLKs, 2.04 us at the SE's
| 15.6672 MHz FCLK: the 2 us GCR cell (Apple's SonyEqu.a gives the SE
| $17, "changed ... to set half speed"; the Mac 128K, 512K and Plus use
| $1F, fast mode, with an 8 MHz FCLK). Called by SetChipMode when the
| IWM register set is selected.
|   D0 (out), CCR -- 0 (BEQ) or initIWMErr (BNE) after about a second
| The mode register is written in state L7 = L6 = 1, MotorOn = 0 (a
| write at q7H) and read back as bits 0-4 of the status register (q6H,
| then a read at q7L); while /ENBL is still active, status bit 5, the
| mode register cannot be accessed (Apple's C437 change of 20 May 87:
| mask the bits, wait for bit 5 = 0).
| -------------------------------------------------------------------------
SONY_SETIWMMODE:
        TST.B   0x1A00(A0)                      | q6H: L6 = 1 (status register)
        MOVEQ.L #0x1F,D0                        | mask for the mode bits (status bits 0-4)
        AND.B   0x1C00(A0),D0                   | read at q7L: status register
        TST.B   0x1800(A0)                      | q6L: back to the read state
        CMPI.B  #0x17,D0                        | mode $17 already set?
        BEQ.B   SONY_SETIWMMODE_DONE            | yes -> return (BEQ)
        MOVEQ.L #0x2,D2                         | D2 = $20000: timeout of about a second
        SWAP    D2                              | (in the high word)
SONY_SETIWMMODE_LOOP:
        MOVEQ.L #-0x4D,D0                       | initIWMErr (-77): assume timeout
        SUBQ.L  #0x1,D2                         | count down
        BMI.B   SONY_SETIWMMODE_EXIT            | timeout -> return (BNE)
        TST.B   0x1000(A0)                      | mtrOff: MotorOn = 0 (with the 1-second timer enabled /ENBL stays on until it runs out)
        TST.B   0x1A00(A0)                      | q6H: L6 = 1 (status register)
        MOVEQ.L #0x3F,D0                        | mask for the enable and mode bits
        AND.B   0x1C00(A0),D0                   | read at q7L: status register
        BCLR    #0x5,D0                         | status bit 5: /ENBL1 or /ENBL2 still active? (clear it in D0)
        BNE.B   SONY_SETIWMMODE_LOOP            | yes -> keep waiting
        CMPI.B  #0x17,D0                        | already $17?
        BEQ.B   SONY_SETIWMMODE_DONE            | yes -> done
        MOVE.B  #0x17,0x1E00(A0)                | write at q7H (state 110): mode register = $17
        TST.B   0x1C00(A0)                      | q7L: L7 = 0, status register again
        BRA.B   SONY_SETIWMMODE_LOOP            | check again
SONY_SETIWMMODE_DONE:
        TST.B   0x1800(A0)                      | q6L: back to the read state
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
        MOVE.W  Drive(A1),TimeOutDrive(A1)      | TimeOutDrive = Drive
        RTS                                     | return
| SONY_POWERDOWN_NOW -- immediate motor off
SONY_POWERDOWN_NOW:
        MOVEQ.L #0x9,D0                         | MtrOffAdr (9): motor off
        BSR.W   Sony_AdrAndStrb                 | AdrAndStrb: motor off command to the drive
        MOVE.B  #0x80,wZeroes(A0)               | wZeroes = $80: MotorOn off if the ISM registers are selected (IWM: ph3L)
        TST.B   0x1000(A0)                      | mtrOff: cut /ENBL
        RTS                                     | return
| InvalTrkCache -- forget the track cache contents if they belong to the
| current drive
SONY_INVALTRKCACHE:
        MOVE.W  TCDrive(A1),D0                  | TCDrive
        CMP.W   Drive(A1),D0                    | this drive?
        BNE.B   SONY_INVALTRKCACHE_EXIT         | no ->
        CLR.W   TCDrive(A1)                     | TCDrive = 0: cache invalid
SONY_INVALTRKCACHE_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| FastPower, RWPowerUp, PowerUp -- select the drive and power it up
|   D0 (in) -- time to wait if the motor was off (PowerUp)
| If the motor was off, a new-interface drive is waited for until /READY
| (first 75 ms, then every 1 ms, at most about 1 s) and an old drive for
| D0: FastPower 0 (MakeSpdTbl measures the speed next), RWPowerUp
| PwrOnTime (400 ms). A SuperDrive is first switched to MFM (constant
| speed) or GCR (zoned speed) drive mode as mfmDisk requires; if the
| mode changed, the drive gets the full power-up wait as if the motor
| had been off. After a motor start, writes (and formats) wait another
| 600 ms so the speed is within 1.5% (Apple's C437 change of 26 Feb 88).
| Hand notes on floppy stuff: "Changing MFM <-> GCR can take as long as
| a motor-on", /READY comes at most 600 ms after motor-on. Returns to
| one level above the caller while waiting.
| -------------------------------------------------------------------------
Sony_FastPower:
        MOVEQ.L #0x0,D0                         | FastPower: no extra wait
        BRA.B   Sony_PowerUp                    | common path
| RWPowerUp -- power up and wait PwrOnTime
Sony_RWPowerUp:
        MOVE    PwrOnTime(A1),D0                | RWPowerUp: PwrOnTime (400 ms)
Sony_PowerUp:
        MOVE    D0,D2                           | PowerUp: D2 = wait time
        BSR.B   Sony_DiskSelect                 | DiskSelect
        MOVE.B  mfmDrive(A1,D1.W),D5            | mfmDrive: SuperDrive?
        BPL.B   SONY_POWERUP_MTRCHK             | no -> no drive mode to set
        MOVEQ.L #0x7,D0                         | GCRModeAdr (7): drive mode sense
        BSR.W   Sony_AdrAndSense                | sense = 1: drive is in MFM mode
        MOVE.B  D0,-(SP)                        | save the old mode (bit 7)
        MOVEQ.L #0x7,D0                         | GCRModeAdr: assume GCR mode is wanted
        MOVE.B  mfmDisk(A1,D1.W),D5             | mfmDisk: MFM disk?
        BPL.B   SONY_POWERUP_SETMODE            | no -> GCR
        MOVEQ.L #0x6,D0                         | MFMModeAdr (6): MFM mode
SONY_POWERUP_SETMODE:
        BSR.W   Sony_AdrAndStrb                 | AdrAndStrb: switch the drive to MFM or GCR mode
        MOVE.B  (SP)+,D0                        | old mode
        EOR.B   D0,D5                           | D5 bit 7 = 1 if the mode changed
SONY_POWERUP_MTRCHK:
        MOVEQ.L #0x8,D0                         | MtrOnAdr: motor-on sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when the motor is on
        OR.B    D5,D0                           | or the mode changed?
        BPL.B   SONY_POWERUP_EXIT               | motor on and no mode change -> return
        BSR.W   Sony_Pulse                      | Pulse at MtrOnAdr: motor on
        MOVE    D2,D0                           | D0 = wait time
        MOVE    #0x2EE,D2                       | first wait 75 ms (750 * 100 us)
        MOVE.L  (SP)+,D4                        | pop the return address (waitReady returns one level up)
        BSR.W   SONY_WAITREADY                  | waitReady: wait for /READY (at least 75 ms)
        MOVE.L  D4,-(SP)                        | return address back on the stack
        CMPI.B  #0x2,Command+1(A1)              | Command low byte = 2 (ARdCmd): a read?
        BEQ.B   SONY_POWERUP_EXIT               | yes -> done
        MOVE.W  #0x1770,D0                      | writes: 600 ms more so the speed is within 1.5%
        BRA.W   Sony_CallWakeUp                 | WakeUp, returns to our caller
| SONY_POWERUP_EXIT -- motor already on
SONY_POWERUP_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| DiskSelect -- select the current drive and enable it (/ENBL)
| (GetDrive, then DiskSel1: through the JDiskSel vector only if the
| routine there starts with a NOP, see Sony_CallWakeUp)
| -------------------------------------------------------------------------
| Called by: SONY_OPEN_XLATINIT, E_SONY_OPEN_CONT, SONY_CTL_EJECT_GO, SONY_DISKPRIME_SELECT, Sony_PowerUp (and 3 more)
Sony_DiskSelect:
        BSR.W   Sony_GetDrive                   | GetDrive
| DiskSel1 -- select the drive set up by GetDrive
Sony_DiskSel1:
        MOVE.L  A0,-(SP)                        | DiskSel1: save A0
        MOVEA.L (JDiskSel).w,A0                 | A0 = routine in the JDiskSel vector
        CMPI.W  #0x4E71,(A0)                    | does it start with a NOP?
        MOVEA.L (SP)+,A0                        | restore A0
        BNE.B   Sony_jtDiskSel                  | no -> ignore the vector, use jtDiskSel
SONY_DISKSEL1_VEC:
        MOVE.L  (JDiskSel).w,-(SP)              | push the JDiskSel vector
        RTS                                     | and jump through it
| jtDiskSel (JDiskSel vector) -- a pending power-down of another drive is
| done now. With the ISM registers selected the ISM mode register
| enables the drive (mDiskSelect). Internal drives: VIA PA4 (vDriveSel)
| chooses the lower (drive 1, PA4 = 1) or upper (drive 2, PA4 = 0)
| drive, then the IWM drive select is set to internal (/ENBL1); PA4 is
| now set only for drive 1 and cleared only for drive 2 (the 1987 SE set
| it for both and then cleared it, Apple's A855 fix "performance problem
| of the upper internal drive"). External drive and HD20s: drive select
| external (/ENBL2), with the HD20 daisy-chain handshake when pass-thru
| works.
Sony_jtDiskSel:
        TST     TimeOut(A1)                     | TimeOut: power-down pending?
        BEQ.B   SONY_DISKSEL_SKIP               | no ->
        MOVE.W  TimeOutDrive(A1),D0             | TimeOutDrive
        CMP     Drive(A1),D0                    | the current drive?
        BEQ.B   SONY_DISKSEL_SKIP               | yes -> nothing to do
        MOVEQ.L #0x0,D0                         | another drive: power it down now
        BSR.W   Sony_PowerDown                  | PowerDown (it stays selected)
SONY_DISKSEL_SKIP:
        CLR     TimeOut(A1)                     | no power-down pending any more
        TST.B   mfmMode(A1)                     | mfmMode: ISM register set selected?
        BMI.W   Sony_mDiskSelect                | yes -> mDiskSelect
        CMPI.W  #Drive2,D1                      | internal drive (Drive1 or Drive2)?
        BGT.B   SONY_DISKSEL_NO                 | no -> external drive or HD20
        CMPI    #Drive1,D1                      | drive 1?
        BEQ.B   SONY_DISKSEL_LOWER              | yes ->
        BCLR    #0x4,0x1E00(A2)                 | vDriveSel = 0: upper drive
        BRA.B   SONY_DISKSEL_INT                | select it
SONY_DISKSEL_LOWER:
        BSET    #0x4,0x1E00(A2)                 | vDriveSel = 1: lower drive
SONY_DISKSEL_INT:
        TST.B   0x1400(A0)                      | intDrive: drive select = internal (/ENBL1)
        TST.B   0x1200(A0)                      | mtrOn: MotorOn = 1, /ENBL1 active
        RTS                                     | return
| external port: may already be enabled in state 2, so go safely through
| state 6 to state 7 (CA0 = CA1 = CA2 = 1)
SONY_DISKSEL_NO:
        TST.B   0xA00(A0)                       | CA2 high
        TST.B   0x600(A0)                       | CA1 high
        TST.B   0x200(A0)                       | CA0 high
        BCLR    #0x5,0x1E00(A2)                 | SEL low (/Exist address)
        TST.B   0x1600(A0)                      | extDrive: drive select = external (/ENBL2)
        TST.B   PassThru(A1)                    | PassThru: HD20 pass-thru works?
        BEQ.B   SONY_DISKSEL_OK                 | yes -> daisy-chain selection
        TST.B   0x1200(A0)                      | mtrOn: /ENBL2 low
        RTS                                     | return
| HD20 daisy chain: the external floppy (drive 3) sits behind the HD20s
SONY_DISKSEL_OK:
        CMPI.W  #Drive3,D1                      | drive 3 (external floppy)?
        BNE.B   SONY_DISKSEL_HD20               | no -> HD20 drive
        TST.B   0x1200(A0)                      | mtrOn: /ENBL2 low
        MOVEQ.L #0x2,D0                         | at most 2 chain clocks (one per HD20 in front)
SONY_DISKSEL_CONT:
        MOVE    SR,-(SP)                        | save the interrupt level
        ORI     #0x300,SR                       | no interrupts
        TST.B   0x1A00(A0)                      | q6H: L6 = 1 (status register)
SONY_DISKSEL_CONT_2:
        TST.B   0x1C00(A0)                      | read at q7L: status bit 7 = sense line
        DBPL    D0,SONY_DISKSEL_LOOP            | until it is 0 or the count is done
        TST.B   0x1800(A0)                      | q6L: back to the read state
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return
| SONY_DISKSEL_LOOP -- clock the HD20 daisy chain: pulse LSTRB, then CA1
| low and high again (the HD20 protocol is not in the documents at hand)
SONY_DISKSEL_LOOP:
        TST.B   0xE00(A0)                       | ph3H: LSTRB high
        MOVE.L  (SP),(SP)                       | (delay)
        TST.B   0xC00(A0)                       | ph3L: LSTRB low
        MOVE.L  (SP),(SP)                       | (delay)
        TST.B   0x400(A0)                       | CA1 low
        MOVE.L  (SP),(SP)                       | (delay)
        TST.B   0x600(A0)                       | CA1 high
        MOVE.L  (SP),(SP)                       | (delay)
        BRA.B   SONY_DISKSEL_CONT_2             | sense again
| HD20 drive: drop /ENBL briefly, then clock the chain to the drive
SONY_DISKSEL_HD20:
        TST.B   0x1000(A0)                      | mtrOff: drop /ENBL2
        MOVE    Drive(A1),D0                    | drive number
        MOVE.L  (SP),(SP)                       | (delay)
        TST.B   0x1200(A0)                      | mtrOn: /ENBL2 low again
        SUBQ.W  #0x4,D0                         | 4 -> 0, 5 -> 1: at most that many chain clocks
        BRA.B   SONY_DISKSEL_CONT               | clock the chain

| -------------------------------------------------------------------------
| SpeedCheckTbl -- per zone the upper and lower limit (+-2%) of the speed
| value of GetFreq1 ($4000000 / (sum of four FigTrkSpd counts / 8),
| proportional to the rotation speed) accepted by the speed check in
| jtReSeek; the midpoints are the targets of MakeSpdTbl. With the VIA
| timer at 783.36 kHz the midpoints are about 394, 429, 472, 525 and 590
| rpm (zones 0-4). Same as the 1987 SE driver.
| -------------------------------------------------------------------------
DT_Sony_SpeedCheckTbl:
        .byte   0x11,0xE9,0x11,0x35,0x13,0x8A   | zone 0: hi=0x11E9, lo=0x1135; zone 1 hi=0x138A
        .byte   0x12,0xC6,0x15,0x7F,0x14,0xA7   | zone 1 lo=0x12C6; zone 2: hi=0x157F, lo=0x14A7
        .byte   0x17,0xE2,0x16,0xF2,0x1A,0xDE   | zone 3: hi=0x17E2, lo=0x16F2; zone 4 hi=0x1ADE
        .byte   0x19,0xD0                       | zone 4 lo=0x19D0

| -------------------------------------------------------------------------
| MakeSpdTbl -- build the speed table of the current drive
|   D0 (out) -- error code (BMI)
| A new-interface drive (800K drive, SuperDrive) regulates its own
| speed: just wait 800 ms so that the disk is seated (this also covers
| the SuperDrive's 500 ms minimum for the first motor-on after a disk is
| inserted, hand notes on floppy stuff). For an old (400K) drive,
| measure the speed at PWM values $80 and $100 and interpolate the speed
| code (and the 2% delta) for each zone. Uses A3/A4 for return
| addresses.
| -------------------------------------------------------------------------
E_Sony_MakeSpdTbl:
        MOVE.L  (DiskVars_JMakeSpdTbl).w,-(SP)  | push MakeSpdTbl vector address
        RTS                                     | dispatch to Sony_MakeSpdTbl
| jtMakeSpdTbl (JMakeSpdTbl vector)
Sony_MakeSpdTbl:
        TST.B   NewIntf(A1,D1.W)                | new-interface drive?
        BPL.B   SONY_MAKESPDTBL_CONT            | no -> calibrate
        MOVE    #0x1F40,D0                      | 800 ms
        BRA.W   Sony_CallWakeUp                 | WakeUp: just wait
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
        BSR.W   Sony_CallWakeUp                 | WakeUp: wait for the motor to reach the speed
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
        BSR.W   SONY_TAIL_E_SETUPPOLL           | SetUpPoll (tail): A5 = VIA port A, A6 = SCC data, PollStack
        MOVEQ.L #0xE,D0                         | TachAdr (14): tachometer sense
        BSR.W   Sony_AdrDisk                    | address TACH via phase lines
        MOVEA.L (IWM).w,A0                      | A0 = IWM base from the low-memory pointer (1987 SE: absolute address)
        TST.B   0x1A00(A0)                      | q6H: L6 = 1, the status register is read at q7L
        MOVEQ.L #-0x1,D1                        | D1 = $FFFF: T2 max count
        MOVEQ.L #0x5,D3                         | D3 = 5: VIA IFR bit for T2 timeout
        MOVE.L  (VIA).w,A2                      | A2 = VIA base
        LEA.L   0x1A00(A2),A3                   | A3 = VIA IFR register
        LEA.L   0x1C00(A0),A1                   | A1 = IWM Q7L address (status read)
        BSR.B   SONY_STARTT2                    | start VIA T2 free-run timer
        BSR.B   SONY_WAITTACH                   | sync: wait for first TACH edge
        BEQ.B   SONY_FIGTRKSPD_CONT_2           | synchronized -> begin measurement
SONY_FIGTRKSPD_EXIT:
        TST.B   0x1800(A0)                      | q6L: L6 = 0, back to the read state
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
        MOVE.B  D1,0x1000(A2)                   | T2 low byte
        ROR.W   #0x8,D1                         | high byte of D1
        MOVE.B  D1,0x1200(A2)                   | T2 high byte: start counting
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
        MOVE.B  0x1200(A2),D2                   | read T2C-H (high byte)
        MOVE.B  0x1000(A2),D1                   | read T2C-L (low byte)
        CMP.B   0x1200(A2),D2                   | T2C-H changed during read?
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
        MOVE    DskVBLTime(A1),0xA(A0)          | VBLCount = DskVBLTime: run again in 0.5 s
        TST.B   Active(A1)                      | Active: request in progress?
        BNE.B   SONY_DISKVBLTASK_EXIT           | yes -> leave the drives alone
        TST     TimeOut(A1)                     | TimeOut: power-down pending?
        BEQ.B   SONY_DISKVBLTASK_POLL           | no -> poll the drives
        SUBQ.W  #0x1,TimeOut(A1)                | count it down
        BNE.B   SONY_DISKVBLTASK_EXIT           | not yet -> a drive is still powered: exit
        MOVEQ.L #0x9,D0                         | MtrOffAdr: time is up, motor off
        BSR.W   Sony_AdrAndStrb                 | AdrAndStrb
SONY_DISKVBLTASK_POLL:
        MOVEQ.L #0x1,D3                         | start with drive 1
SONY_DISKVBLTASK_LOOP:
        BSR.B   Sony_Check4Disk                 | Check4Disk
        ADDQ.W  #0x1,D3                         | next drive
        CMPI.W  #0x5,D3                         | past drive 5?
        BGT.B   SONY_DISKVBLTASK_DONE           | yes -> done
        TST.B   PassThru(A1)                    | PassThru: second HD20 addressable?
        BEQ.B   SONY_DISKVBLTASK_LOOP           | yes -> check every drive
        CMPI.W  #0x4,D3                         | else only drives 1-4
        BLE.B   SONY_DISKVBLTASK_LOOP           | next drive
SONY_DISKVBLTASK_DONE:
        MOVE.B  #0x80,wZeroes(A0)               | wZeroes = $80: MotorOn off if the ISM registers are selected (IWM: ph3L)
        TST.B   0x1000(A0)                      | mtrOff: cut /ENBL (Apple: "new drive fix")
SONY_DISKVBLTASK_EXIT:
        MOVE    (SP)+,SR                        | restore the interrupt level
        RTS                                     | return

| -------------------------------------------------------------------------
| Check4Disk -- check logical drive D3 (GetDrive translates it): post a
| disk-inserted event (message high word 0, low word = drive number) for
| a newly inserted disk, or one with high word -1 (eject request) when
| the eject button of a drive holding a disk is pressed. HD20 drives are
| addressed through the ISM phase register when the ISM set is selected.
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
        MOVEQ.L #-0x1,D0                        | D0 = -1: high word -1 = eject request
        MOVE.W  Drive(A1),D0                    | low word = drive number
        MOVEA.W #0x7,A0                         | A0 = diskInsertEvt (7)
        _PostEvent                              | post the event
        BRA.B   SONY_CKEXIT                     | any error is ignored
SONY_CKDIP:
        BSR.W   Sony_DiskSel1                   | CkDIP: DiskSel1
        CMPI.W  #0x4,Drive(A1)                  | floppy drive (1-3)?
        BLT.B   SONY_CKDIP_SENSE                | yes -> disk-in-place sense
| HD20: CA0 and CA2 low (CA1 high, SEL low from DiskSel1) is the address
| where DCDWaitHSHK and DCDReset sense the HD20's handshake line HSHK;
| HSHK high = HD20 idle and ready
        TST.B   mfmMode(A1)                     | mfmMode: ISM register set selected?
        BPL.B   SONY_CKDIP_HD20                 | no -> IWM phase lines
        MOVE.B  #0xF2,wPhase(A0)                | wPhase = $F2: CA0 = CA2 = 0, CA1 = 1 (as below)
        BRA.B   SONY_CKDIP_HD20SENSE            | sense
SONY_CKDIP_HD20:
        TST.B   (A0)                            | HD20: CA0 low
        TST.B   0x800(A0)                       | CA2 low
SONY_CKDIP_HD20SENSE:
        BSR.W   Sony_Sense                      | Sense: HSHK
        BMI.B   SONY_CKDIP_POST                 | HSHK high -> post a disk-inserted event
        BRA.B   SONY_CKEXIT                     | else exit
| SONY_CKDIP_SENSE -- floppy: read CSTIN sense line
SONY_CKDIP_SENSE:
        MOVEQ.L #0x2,D0                         | DIPAdr: disk-in-place sense
        BSR.W   Sony_AdrAndSense                | sense = 0 when a disk is in place
        BMI.B   SONY_CKEXIT                     | no disk -> exit
SONY_CKDIP_POST:
        BSR.B   SONY_CKEJSW                     | CkEjSw: read and reset (ignore) the eject button
        MOVEQ.L #0x7,D0                         | diskInsertEvt (7); D0 high word 0 = disk inserted
        MOVEA.L D0,A0                           | A0 = event code
        MOVE.W  Drive(A1),D0                    | low word = drive number
        _PostEvent                              | post the event
        BNE.B   SONY_CKINVAL                    | not posted (probably boot time) -> CkInval
        ADDQ.B  #0x1,DiskInPlace(A1,D1.W)       | DiskInPlace = 1: disk in place, not clamped
SONY_CKINVAL:
        ST.B    Track(A1,D1.W)                  | CkInval: Track = $FFxx: current track invalid
        MOVE.L  (IWM).w,A0                      | A0 = IWM base again
| Branch from: Sony_Check4Disk, SONY_CKEJECT, SONY_CKEJECT_SELECT, SONY_CKDIP_HD20SENSE, SONY_CKDIP_SENSE
SONY_CKEXIT:
        RTS                                     | return
| CkEjSw -- read and reset the latched eject button of the selected drive
| (BMI if it was pressed); one-sided (400K) drives have no eject button
| and are skipped
SONY_CKEJSW:
        TST.B   Sides(A1,D1.W)                  | Sides: two-sided drive?
        BPL.B   SONY_CKEJSW_EXIT                | no (400K drive) -> return (BPL)
SONY_CKEJSW_SENSE:
        MOVEQ.L #0xC,D0                         | EjectLAdr (12): eject button latch
        BSR.W   Sony_AdrAndSense                | sense = 1 when the button was pressed
        BPL.B   SONY_CKEJSW_EXIT                | not pressed -> return (BPL)
        MOVEQ.L #0x3,D0                         | RdDta1Adr (3): reset the latch
        BSR.W   Sony_AdrAndStrb                 | by strobing that address
        MOVEQ.L #-0x1,D0                        | D0 = -1: the button was pressed (BMI)
SONY_CKEJSW_EXIT:
        RTS                                     | return
| MarkTbl (Apple) -- the six self-sync bytes and the first two bytes of
| the data mark, written by WrData (as in the 1987 SE driver). As a bit
| stream the self-sync bytes are 11111111 00 11111111 00 11111111 00
| 11111111 00 11111111: 10-bit self-sync bytes ("eight bits of 1 and two
| bits of 0", Software control of IWM) that put the IWM on the byte
| boundary whatever came before (SWIM Chip User's Ref, "GCR Track
| Format"); the IWM reads them as five $FF.
SONY_WRDATAMKS:
        .byte   0xFF,0x3F,0xCF,0xF3,0xFC,0xFF   | self-sync: 48 bits = four 10-bit groups (eight 1s, two 0s) + eight 1s
        .byte   0xD5,0xAA                       | data mark $D5 $AA ($AD is written by the loop)

| -------------------------------------------------------------------------
| WrData -- write the data mark of the sector that just passed: MFM disks
| go to mWrData, GCR disks through the JWrData vector to Larry Kenyon's
| GCR write routine (jtWrData): sync group, $D5 $AA $AD, sector number
| (TagData+1), the 12 tag bytes (TagData+2..) and the 512 bytes at (A0),
| encoded 6-and-2 with three running checksums, then the checksum
| nibbles and the bit-slip marks (format: see RdData).
|   A0 (in) -- data buffer, A4/A5/A6 (in) -- IWM q6L (from RdAddr) / VIA
|              port A / SCC data pointers (mWrData needs only A5/A6)
|   D0 (out) -- 0 or wrUnderrun
| IWM access: q6H (L6 = 1), then the first byte is written to q7H (L7 =
| 1, motor on: write state, the byte goes to the write data buffer).
| Each further byte: wait for handshake bit 7 (buffer empty) read at q6L
| (L6 = 0, so L7 = 1, L6 = 0 selects the write handshake register), then
| write the byte to q6H (L6 = 1 again: write data register). q7L ends the
| write state.
| -------------------------------------------------------------------------
E_Sony_WrData:
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: MFM disk?
        BMI.W   Sony_mWrData                    | yes -> mWrData
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
        TST.B   0x1A00(A3)                      | q6H: L6 = 1 (Apple: "first byte written is a bit weird")
        MOVEQ.L #0x6,D0                         | D0 = 6: bytes 2-7 of MarkTbl in the loop
        MOVEQ.L #0x0,D5                         | clear checksum register A
        MOVE.B  (A2)+,0x1E00(A3)                | first byte ($FF) at q7H: write state (L7 = L6 = 1, MotorOn = 1: write data)
        LEA.L   0x1A00(A3),A3                   | A3 -> q6H: write data register
        MOVEQ.L #0x0,D6                         | clear checksum register B
        MOVEQ.L #0x0,D7                         | clear checksum register C
SONY_WRDATA_LOOP:
        MOVE.B  (A2)+,D1                        | load next header byte from template
SONY_WRDATA_NO:
        TST.B   (A4)                            | q6L in the write state: handshake bit 7 = buffer empty?
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
        MOVEQ.L #0xB,D1                         | D1 = $0B: NiblTbl[$0B] = $AD, the data mark's last byte, goes out first
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
        BTST    #0x6,D1                         | handshake bit 6 still 1 (the IWM clears it on an underrun)?
        BNE.B   SONY_WRDATA_OK                  | yes -> success
        MOVEQ.L #-0x4A,D0                       | wrUnderrun (-74): write underrun
SONY_WRDATA_OK:
        TST.B   0x200(A3)                       | q7L (A3+$200): L7 = 0, write state off (the last $FF is still being written)
        BRA.W   SONY_DSKRTN                     | return via continuation

| -------------------------------------------------------------------------
| TrailMks (Apple): the bit-slip marks WrData writes after a data field
| (Format takes the same bytes from AdrMkTbl); the two $FF let the slip
| marks reach the disk before write mode ends ("write a garbage byte (HEX
| FF) before turning off the write mode", Software Control of the IWM).
| Then the GCR nibble table NiblTbl (6-bit value -> disk nibble, its
| address is in the NiblTbl vector; of the 81 bytes with bit 7 set and no
| more than two 0 bits in a row, $D5 and $AA are the mark bytes and 64
| encode data, SWIM Chip User's Ref, "GCR Encoding"); AdrMkTbl, which
| follows here in the 1987 SE driver, is in the ROM tail now.
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

| =========================================================================
| SWIM / SuperDrive MFM support (Apple's SonyMFM.a by Steve Christensen,
| change C437, 1986-88): register set selection, parameter RAM set-up,
| disk type detection, drive addressing through the ISM registers, and
| the MFM read, write, format and verify routines.
| The SWIM is the IWM and the ISM in one chip at the IWM's addresses;
| after a reset the IWM register set is selected. Switching (SWIM Chip
| Spec of Sep 1987, SWIM Chip User's Reference rev 1.5 of Jan 1988):
|   IWM -> ISM: with MotorOn off, four writes to the IWM mode register
|               (state L7 = L6 = 1, MotorOn = 0) with bit 6 = 1, 0, 1, 1
|   ISM -> IWM: a write to wZeroes with bit 6 set (this driver writes $F8,
|               which also clears MotorOn, HDSEL, write and ACTION); the
|               first IWM access after it must clear L7 (q7L)
| The phase lines keep their levels across a switch. The ISM registers
| (wData/rData, wMark/rMark, wCRC = wIWMConfig, rError, wParams/rParams,
| wPhase/rPhase, wSetup/rSetup, wZeroes/wOnes/rStatus for the mode
| register, rHandshake) and their bits are listed with the equates in
| include/sonyequ.inc; successive ISM accesses must be at least 4 FCLKs
| apart.
| MFM track format written by mDoFormat (IBM System 34; SWIM Chip User's
| Reference, "MFM Track Format"): after the index pulse 80 gap bytes
| ($4E), 12 sync bytes ($00), the index mark $C2 $C2 $C2 $FC and 50 gap
| bytes; per sector 12 sync bytes, the address mark $A1 $A1 $A1 $FE,
| cylinder, side, sector (from 1), size code 2 (512 bytes), 2 CRC bytes,
| 22 gap bytes, 12 sync bytes, the data mark $A1 $A1 $A1 $FB, 512 data
| bytes, 2 CRC bytes and 80 (720K) or 101 (1440K) gap bytes (the User's
| Reference gives 84 and 101); then gap bytes up to the index pulse.
| 9 (720K) or 18 (1440K) sectors per side on 80 cylinders, no tag bytes.
| The $C2 and $A1 of the marks are written through wMark (a clock
| transition left out, which no data byte can have); the ISM computes
| the CCITT CRC (preset to all ones before the first mark byte), writes
| it for wCRC and checks it when reading (handshake register bit 1).
| =========================================================================
| Check4SWIM -- look for a SWIM: try the IWM -> ISM switch, then write
| and read back three phase register values ($F5, $F6, $F7: all four
| lines outputs, LSTRB low, CA0-CA2 = 101, 011, 111). With a plain IWM
| these accesses are ph2L and q6L, which never returns the values. Sets
| isSWIM = $FF if a SWIM answers, and returns with the IWM register set
| selected, the IWM in the read state and MotorOn set.
|   A1 (out) -- SonyVars; A0, D0 destroyed
Sony_Check4SWIM:
        MOVEA.L (SonyVars).w,A1                 | A1 = SonyVars
        MOVE.W  SR,-(SP)                        | save SR
        ORI.W   #0x300,SR                       | and disable interrupts
        MOVEA.L (IWM).w,A0                      | A0 = IWM base
        TST.B   0x1400(A0)                      | intDrive: drive select = internal
        TST.B   0x1C00(A0)                      | q7L: L7 = 0 first, a safe path to the mode register
        TST.B   0x1000(A0)                      | mtrOff: MotorOn = 0 (needed to write the mode and to switch)
        TST.B   0x1A00(A0)                      | q6H: L6 = 1 (state 010: status register)
        MOVEQ.L #0x57,D0                        | $57 = bit 6 (ISM select) + IWM mode $17
        MOVE.B  D0,0x1E00(A0)                   | write at q7H (state 110: mode register): bit 6 = 1,
        MOVE.B  #0x17,0x1E00(A0)                | 0,
        MOVE.B  D0,0x1E00(A0)                   | 1,
        MOVE.B  D0,0x1E00(A0)                   | 1: a SWIM now has the ISM registers selected
        MOVEQ.L #-0xB,D0                        | $F5: phase register test value 1
        MOVE.B  D0,wPhase(A0)                   | wPhase (with an IWM: ph2L)
        CMP.B   rPhase(A0),D0                   | rPhase (with an IWM: q6L): the same value back?
        BNE.B   SONY_CHECK4SWIM_IWM             | no -> IWM
        MOVEQ.L #-0xA,D0                        | $F6: test value 2
        MOVE.B  D0,wPhase(A0)                   | wPhase
        CMP.B   rPhase(A0),D0                   | rPhase
        BNE.B   SONY_CHECK4SWIM_IWM             | mismatch -> IWM
        MOVEQ.L #-0x9,D0                        | $F7: test value 3
        MOVE.B  D0,wPhase(A0)                   | wPhase
        CMP.B   rPhase(A0),D0                   | rPhase
        BNE.B   SONY_CHECK4SWIM_IWM             | mismatch -> IWM
        ST.B    isSWIM(A1)                      | isSWIM = $FF: a SWIM is installed
        MOVE.B  #0xF8,wZeroes(A0)               | wZeroes = $F8: MotorOn, ISM select, HDSEL, write and ACTION off: back to the IWM
SONY_CHECK4SWIM_IWM:
        TST.B   0x1C00(A0)                      | q7L: L7 = 0 (the first access after the switch back)
        TST.B   0x1800(A0)                      | q6L: L6 = 0, read state
        TST.B   0x1200(A0)                      | mtrOn: MotorOn = 1, drive enabled again
        MOVE.W  (SP)+,SR                        | restore SR
        RTS                                     | return

| -------------------------------------------------------------------------
| SetChipMode -- select the register set the disk needs: the ISM
| registers for an MFM disk (mfmDisk), the IWM registers otherwise; with
| a plain IWM just SetIWMMode. Which set is selected is found out by
| writing and reading back three phase register values (Apple: "safe for
| use even if an HD-20 is selected since they are the ID states"); in
| the IWM set the reads (q6L) do not return them. For MFM the ISM is set
| up: ACTION off, IWM configuration $C0, setup register $20, parameter
| RAM (SetParams); if that fails, the chip goes back to the IWM set. Two
| attempts are made to switch to the ISM.
|   D0 (out), CCR -- 0 or initIWMErr; mfmMode = $FF if the ISM register
|                    set is selected
| Also called from the tail (CtlFormat, CtlVerify) through
| SONY_DRVENT_SETCHIPMODE.
| -------------------------------------------------------------------------
| Called by: Sony_DiskPrime, SONY_DISKPRIME_CONT, Sony_Recal, Sony_DCDReset, SONY_DCD_COMMAND (and 1 more)
Sony_SetChipMode:
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1
        TST.B   isSWIM(A1)                      | isSWIM: SWIM installed?
        BPL.W   SONY_SETIWMMODE                 | no -> SetIWMMode
        MOVE.W  SR,-(SP)                        | save SR
        ORI.W   #0x300,SR                       | and disable interrupts
        MOVEQ.L #0x1,D2                         | two tries to switch to the ISM registers
SONY_SETCHIPMODE_TRY:
        MOVEA.L (IWM).w,A0                      | A0 = SWIM base
        MOVE.B  #0x38,wZeroes(A0)               | wZeroes = $38: HDSEL, write and ACTION off if the ISM set is selected (IWM: ph3L)
        MOVEQ.L #-0xB,D0                        | $F5: phase register test value 1
        MOVE.B  D0,wPhase(A0)                   | wPhase (IWM: ph2L)
        CMP.B   rPhase(A0),D0                   | rPhase (IWM: q6L): the same value back?
        BNE.B   SONY_SETCHIPMODE_IWM            | no -> the IWM registers are selected
        MOVEQ.L #-0xA,D0                        | $F6
        MOVE.B  D0,wPhase(A0)                   | wPhase
        CMP.B   rPhase(A0),D0                   | rPhase
        BNE.B   SONY_SETCHIPMODE_IWM            | mismatch -> IWM registers
        MOVEQ.L #-0x9,D0                        | $F7
        MOVE.B  D0,wPhase(A0)                   | wPhase
        CMP.B   rPhase(A0),D0                   | rPhase
        BNE.B   SONY_SETCHIPMODE_IWM            | mismatch -> IWM registers
        TST.B   mfmDisk(A1,D1.W)                | the ISM registers are selected: MFM disk (mfmDisk)?
        BMI.B   SONY_SETCHIPMODE_ISM            | yes -> finish the ISM set-up
        MOVE.B  #0xF8,wZeroes(A0)               | wZeroes = $F8: back to the IWM registers (MotorOn, HDSEL, write, ACTION off)
        TST.B   0x1C00(A0)                      | q7L: L7 = 0 first, out of the write state
SONY_SETCHIPMODE_IWM:
        CLR.B   mfmMode(A1)                     | mfmMode = 0: IWM registers
        MOVE.L  D2,-(SP)                        | save D2 (SetIWMMode uses it; Apple 1.7, Aug 88)
        BSR.W   SONY_SETIWMMODE                 | SetIWMMode: normal IWM set-up
        MOVE.L  (SP)+,D2                        | restore D2
        TST.W   D0                              | result
        BNE.B   SONY_SETCHIPMODE_EXIT           | error -> return it
        TST.B   mfmDisk(A1,D1.W)                | mfmDisk: is the IWM set what we want?
        BPL.B   SONY_SETCHIPMODE_EXIT           | yes -> done
        TST.B   0x1C00(A0)                      | q7L: L7 = 0
        TST.B   0x1000(A0)                      | mtrOff: MotorOn = 0
        TST.B   0x1A00(A0)                      | q6H: L6 = 1
        MOVEQ.L #0x57,D0                        | $57 = bit 6 (ISM select) + IWM mode $17
        MOVE.B  D0,0x1E00(A0)                   | mode register writes (q7H): bit 6 = 1,
        MOVE.B  #0x17,0x1E00(A0)                | 0,
        MOVE.B  D0,0x1E00(A0)                   | 1,
        MOVE.B  D0,0x1E00(A0)                   | 1: switch to the ISM registers
        DBF     D2,SONY_SETCHIPMODE_TRY         | check again that the ISM is selected
        BRA.B   SONY_SETCHIPMODE_ERR            | not after two tries -> initIWMErr
SONY_SETCHIPMODE_ISM:
        MOVE.B  #0x38,wZeroes(A0)               | wZeroes = $38: HDSEL, write and ACTION off (and parameter RAM counter = 0)
        MOVE.B  #0xC0,wIWMConfig(A0)            | wIWMConfig = $C0 (ACTION = 0): bit 7 the IWM timer can be killed, bit 6 it counts twice as long (16 MHz FCLK)
        MOVEQ.L #0x20,D0                        | setup $20: bit 5 IBM drive (RDDATA/WRDATA pulses); 0: MFM with Trans-Space machine, no error correction, FCLK, Q3/HDSEL input, no timer
        MOVE.B  D0,wSetup(A0)                   | wSetup
        CMP.B   rSetup(A0),D0                   | rSetup: written correctly?
        BNE.B   SONY_SETCHIPMODE_FAIL           | no -> error
        BSR.B   Sony_SetParams                  | SetParams: parameter RAM for the current track
        BEQ.B   SONY_SETCHIPMODE_SETMODE        | ok ->
SONY_SETCHIPMODE_FAIL:
        MOVE.B  #0xF8,wZeroes(A0)               | wZeroes = $F8: shut down, back to the IWM registers
SONY_SETCHIPMODE_ERR:
        TST.B   0x1C00(A0)                      | q7L: L7 = 0, IWM in a non-write state
        MOVEQ.L #-0x4D,D0                       | initIWMErr (-77)
SONY_SETCHIPMODE_SETMODE:
        SEQ.B   mfmMode(A1)                     | mfmMode = $FF if the ISM set-up worked
SONY_SETCHIPMODE_EXIT:
        MOVE.W  (SP)+,SR                        | restore SR
        TST.W   D0                              | CCR = result
        RTS                                     | return

| -------------------------------------------------------------------------
| SetParams -- load the 16 ISM parameter RAM bytes for the zone of the
| current track (MPARAMZONES), unless they are already there; up to five
| attempts, each verified by reading the RAM back. rParams and wParams
| step through the 16 bytes (auto-increment; every wZeroes write resets
| the counter to byte 0); the tables hold the bytes in reverse order, so
| the loop counter D0 = 15..0 indexes them directly. The MOVE.W (SP),(SP)
| keep the SWIM accesses apart (Apple 1.6, Jul 88: "Added extra delays in
| SetParams to fix violation of SWIM timing restriction").
|   A0 (in) -- SWIM base, A1/D1 (in) -- SonyVars / drive vars
|   D0 (out) -- 0 or initIWMErr
| Called by SetChipMode and Seek (after each seek with the ISM registers
| selected).
| -------------------------------------------------------------------------
Sony_SetParams:
        MOVE.W  Track(A1,D1.W),D0               | D0 = current track
        LEA.L   MPARAMZONES-2(PC),A2            | A2 -> zone table - 2
SONY_SETPARAMS_ZONE:
        ADDQ.W  #0x2,A2                         | skip the parameter set offset
        CMP.W   (A2)+,D0                        | track >= last track + 1 of this zone?
        BGE.B   SONY_SETPARAMS_ZONE             | yes -> next zone
        MOVE.W  (A2),D0                         | offset of the zone's parameter set
        LEA.L   MPARAMZONES(PC,D0.W),A2         | A2 -> parameter set (16 bytes, in reverse order)
        MOVEQ.L #0x4,D2                         | five tries
SONY_SETPARAMS_TRY:
        MOVE.B  #0x38,wZeroes(A0)               | wZeroes = $38: parameter RAM counter = 0 (HDSEL, write, ACTION stay off)
        SWAP    D2                              | (keep the try count in the high word)
        MOVEQ.L #0xF,D0                         | 16 bytes
SONY_SETPARAMS_CHECK:
        MOVE.W  (SP),(SP)                       | (delay between SWIM accesses)
        MOVE.B  rParams(A0),D2                  | rParams: parameter RAM byte 15 - D0
        CMP.B   0x0(A2,D0.W),D2                 | the value it should have?
        DBNE    D0,SONY_SETPARAMS_CHECK         | compare all 16
        BNE.B   SONY_SETPARAMS_LOAD             | different -> load the parameter RAM
        MOVEQ.L #0x0,D0                         | already set up: noErr
        RTS                                     | return
SONY_SETPARAMS_LOAD:
        MOVE.B  #0x38,wZeroes(A0)               | wZeroes = $38: parameter RAM counter = 0
        MOVEQ.L #0xF,D0                         | 16 bytes
SONY_SETPARAMS_LOOP:
        MOVE.W  (SP),(SP)                       | (delay between SWIM accesses)
        MOVE.B  0x0(A2,D0.W),wParams(A0)        | wParams: parameter RAM byte 15 - D0
        DBF     D0,SONY_SETPARAMS_LOOP          | all 16
        SWAP    D2                              | try count
        DBF     D2,SONY_SETPARAMS_TRY           | verify / try again
        MOVEQ.L #-0x4D,D0                       | initIWMErr (-77): parameter RAM cannot be set up
SONY_SETPARAMS_EXIT:
        RTS                                     | return
| mParamZones -- last track + 1 and parameter set offset of each zone
| (Apple: different parameter sets "can be used to optimize the error
| correction performance to handle variations in peak shift, drive speed,
| etc."); here the first zone covers all 80 tracks
MPARAMZONES:
        .short  80,MPARAMS-MPARAMZONES          | zone 0: tracks 0-79 (every track: the only zone used)
        .short  80,MPARAMS2-MPARAMZONES         | zone 1: same limit, never reached
        .short  80,MPARAMS-MPARAMZONES          | zone 2: same limit, never reached
        .short  80,MPARAMS-MPARAMZONES          | zone 3: same limit, never reached
| mParams -- ISM parameter RAM values for MFM disks: 2, 3 and 4 us cells
| at the 15.6672 MHz FCLK (t2 = 2 us = 31.33 clocks), register $F first.
| The counter values are in half clocks (register = 2 * clocks, odd for
| x.5) after the reduction for the delays in the SWIM (Min by 3, all other
| times by 2 clocks); Mult and the Early/Late/Normal nibbles are plain
| numbers. Write side: Time1 = t2 (2 us), Time0 = t3 - t2 (1 us) and
| 125 ns (2 clocks) of write pre-compensation (Late = 9, Early = 5 around
| Normal = 7); like Min = [t2/2] and Mult = 65536/(32*t2) these are the
| values of the example in the SWIM Chip User's Reference (pp. 14-17).
| The read bounds (xSx, xLx, RPT, CSLS) are not the User's Reference
| ones (its "real-world" values in parentheses): Apple, 1 Mar 88,
| "Updated to latest SWIM params recommended by Sony (their rev 4.0)".
MPARAMS:
        .byte   (31-2)*2+1                      | [F] Time1 = 31.5 clocks (2 us)
        .byte   0x57                            | [E] Early/Norm = 5/7
        .byte   (15-2)*2+1                      | [D] Time0 = 15.5 clocks (1 us)
        .byte   0x97                            | [C] Late/Norm = 9/7
        .byte   (14-2)*2+1                      | [B] LLS = 14.5 clocks (16.0)
        .byte   (14-2)*2+1                      | [A] LLL = 14.5 clocks (16.0)
        .byte   (25-2)*2+1                      | [9] LSS = 25.5 clocks (24.0)
        .byte   (25-2)*2+1                      | [8] LSL = 25.5 clocks (24.0)
        .byte   (15-2)*2+1                      | [7] CSLS = 15.5 clocks (15.5)
        .byte   (15-2)*2+1                      | [6] RPT = 15.5 clocks (23.5)
        .byte   (14-2)*2+0                      | [5] SLS = 14.0 clocks (15.5)
        .byte   (14-2)*2+0                      | [4] SLL = 14.0 clocks (15.5)
        .byte   (25-2)*2+0                      | [3] SSS = 25.0 clocks (23.0)
        .byte   (25-2)*2+0                      | [2] SSL = 25.0 clocks (23.0)
        .byte   65                              | [1] Mult = 65
        .byte   (15-3)*2                        | [0] Min = 15.0 clocks
| second parameter set: identical to mParams in this ROM (Apple: "change
| back after getting the 2nd parm set right"); only zone 1 refers to it
MPARAMS2:
        .byte   (31-2)*2+1                      | [F] Time1 = 31.5 clocks
        .byte   0x57                            | [E] Early/Norm = 5/7
        .byte   (15-2)*2+1                      | [D] Time0 = 15.5 clocks
        .byte   0x97                            | [C] Late/Norm = 9/7
        .byte   (14-2)*2+1                      | [B] LLS = 14.5 clocks
        .byte   (14-2)*2+1                      | [A] LLL = 14.5 clocks
        .byte   (25-2)*2+1                      | [9] LSS = 25.5 clocks
        .byte   (25-2)*2+1                      | [8] LSL = 25.5 clocks
        .byte   (15-2)*2+1                      | [7] CSLS = 15.5 clocks
        .byte   (15-2)*2+1                      | [6] RPT = 15.5 clocks
        .byte   (14-2)*2+0                      | [5] SLS = 14.0 clocks
        .byte   (14-2)*2+0                      | [4] SLL = 14.0 clocks
        .byte   (25-2)*2+0                      | [3] SSS = 25.0 clocks
        .byte   (25-2)*2+0                      | [2] SSL = 25.0 clocks
        .byte   65                              | [1] Mult = 65
        .byte   (15-3)*2                        | [0] Min = 15.0 clocks
| 32 spare bytes reserved for parameter sets (Apple's comment: "so we don't
| have to worry about shuffling pieces of the driver about ROM when
| parameter changes come along"); they hold a message instead
MPARAMSPARE:
        .ascii  "SO...WHAT ARE YOU STARING AT?   " | unused (32 bytes)

| -------------------------------------------------------------------------
| ChkDiskType -- GCR or MFM? Entered from jtDiskPrime (not a subroutine:
| Recal calls WakeUp, which needs DiskPrime's stack level) after a new
| disk was recalibrated in GCR mode (DiskInPlace = 2). Only for a
| SuperDrive with a SWIM. The SuperDrive reports the media density at
| address 15 (twoMegAdr, the NewIntfAdr address of other drives): sense 0
| = high-density disk, taken as 1440K (twoMegFmt = $FF). (The comment of
| twoMegAdr in Apple's SonyEqu.a, "0=1 meg disk, 1=2 meg disk", has the
| polarity the other way round; the code, here and in System 7.1, uses
| sense 0 = 1440K.) If a GCR sector can be read, the disk is GCR --
| unless it is a 1440K disk, which is marked DiskInPlace = 3 ("a
| high-density disk formatted as 400K/800K GCR", Technical Note #272)
| and rejected with GCRonMFMErr (-400); otherwise the drive is switched
| to MFM (Recal through SetChipMode, PowerUp sets the drive's MFM mode)
| and, for a 720K disk, an MFM sector with 512-byte blocks must be found,
| else the disk is treated as GCR. Continues at CkWrProt.
| -------------------------------------------------------------------------
Sony_ChkDiskType:
        MOVE.B  isSWIM(A1),D0                   | isSWIM
        AND.B   mfmDrive(A1,D1.W),D0            | and mfmDrive: SWIM and a SuperDrive?
        BPL.B   SONY_CHKDISKTYPE_DONE           | no -> GCR, back to DiskPrime
        MOVEQ.L #0xF,D0                         | twoMegAdr (15): media density sense
        BSR.W   Sony_AdrAndSense                | AdrAndSense: sense = 0 for a high-density disk
        SPL.B   twoMegFmt(A1,D1.W)              | twoMegFmt = $FF (1440K disk) if the sense is 0
        BSR.B   SONY_GETASECTOR                 | GetASector: try to read a GCR address mark
        TST.W   D0                              | found one?
        BMI.B   SONY_CHKDISKTYPE_MFM            | no -> try MFM
        MOVE.B  twoMegFmt(A1,D1.W),mfmDisk(A1,D1.W) | mfmDisk = twoMegFmt: a GCR sector on a 1440K disk?
        BPL.B   SONY_CHKDISKTYPE_DONE           | no -> GCR disk, done
        ADDQ.B  #0x1,DiskInPlace(A1,D1.W)       | DiskInPlace = 3: clamped, but a 1440K disk with GCR format
        MOVE.W  #-0x190,D0                      | GCRonMFMErr (-400)
        BRA.W   SONY_DSKRWOFF                   | power down and return the error
SONY_CHKDISKTYPE_MFM:
        ST.B    mfmDisk(A1,D1.W)                | mfmDisk = $FF: try MFM
        BSR.W   E_Sony_Recal                    | Recal: select the ISM registers, power up in MFM mode
        BNE.B   SONY_CHKDISKTYPE_NOMFM          | error -> MFM only if 1440K
        TST.B   twoMegFmt(A1,D1.W)              | twoMegFmt: 1440K disk?
        BMI.B   SONY_CHKDISKTYPE_DONE           | yes -> it must be MFM
        BSR.B   SONY_GETASECTOR                 | GetASector: try to read an MFM address mark
        SUBI.B  #0x22,D3                        | block size code must be 2 (+$20): 512-byte blocks
        OR.W    D3,D0                           | and no read error?
        BEQ.B   SONY_CHKDISKTYPE_DONE           | yes -> MFM, done
SONY_CHKDISKTYPE_NOMFM:
        MOVE.B  twoMegFmt(A1,D1.W),mfmDisk(A1,D1.W) | mfmDisk = twoMegFmt: MFM only for a 1440K disk
SONY_CHKDISKTYPE_DONE:
        BRA.W   SONY_CKWRPROT                   | back to DiskPrime at CkWrProt
| GetASector -- try up to six times to read an address mark on side 0
|   D0 (out) -- RdAddr result (MI = none found); D3 -- format byte
SONY_GETASECTOR:
        MOVEQ.L #0x5,D1                         | six tries
SONY_GETASECTOR_LOOP:
        MOVE.W  D1,-(SP)                        | save the try count
        MOVE.W  SR,-(SP)                        | save the interrupt level
        CLR.W   SideTrack(A1)                   | SideTrack = 0: side 0 (it might be a 400K disk)
        BSR.W   SONY_TAIL_RDADDRSETUP           | RdAddrSetup (tail): read an address mark
        BSR.W   Sony_EmptyPD                    | EmptyPD: process the poll data (sets A1, D1)
        MOVE.W  (SP)+,SR                        | restore the interrupt level
        MOVE.W  (SP)+,D1                        | restore the try count
        TST.W   D0                              | found one?
        DBPL    D1,SONY_GETASECTOR_LOOP         | no -> try again
        BRA.W   Sony_GetDrv1                    | GetDrv1 and return

| -------------------------------------------------------------------------
| mAdrDisk -- AdrDisk with the ISM registers selected: CA0-CA2 are set
| through the phase register (bits 0-3 = PHASE0-3 = CA0, CA1, CA2, LSTRB;
| bits 4-7 = 1: all four lines outputs), SEL through VIA port A bit 5 as
| before (the SWIM's own HDSEL output is not used: the setup register
| leaves the Q3/HDSEL pin an input).
|   D0 (in) -- register address ([CA1][CA0][SEL][CA2])
| -------------------------------------------------------------------------
Sony_mAdrDisk:
        MOVE.B  #0xF3,wPhase(A0)                | wPhase = $F3: CA0 = CA1 = 1, CA2 = LSTRB = 0 (Apple: "CA0,CA1 must be 1 when changing SEL to zero")
        BTST    #0x1,D0                         | SEL (bit 1) high or low?
        BEQ.B   SONY_MADRDISK_SELLO             | low ->
        BSET    #0x5,0x1E00(A2)                 | SEL high (vHeadSel)
        BRA.B   SONY_MADRDISK_PHASES            | ->
SONY_MADRDISK_SELLO:
        BCLR    #0x5,0x1E00(A2)                 | SEL low
SONY_MADRDISK_PHASES:
        MOVE.B  MPHASETBL(PC,D0.W),wPhase(A0)   | wPhase: CA0-CA2 of this register, LSTRB low
        RTS                                     | return
| mPhaseTbl -- phase register value for each drive register address
| [CA1 CA0 SEL CA2]: $F0 + CA2 * 4 + CA1 * 2 + CA0 (SEL is not a phase
| line; LSTRB = 0, all four lines outputs)
MPHASETBL:
        .byte   0xF0,0xF4,0xF0,0xF4             | addresses 0-3 (CA1 = CA0 = 0)
        .byte   0xF1,0xF5,0xF1,0xF5             | addresses 4-7 (CA0 = 1)
        .byte   0xF2,0xF6,0xF2,0xF6             | addresses 8-11 (CA1 = 1)
        .byte   0xF3,0xF7,0xF3,0xF7             | addresses 12-15 (CA1 = CA0 = 1)
        .ascii  "SWC!"                          | not part of the table: initials (Steve Christensen)
| mSense -- sense line with the ISM registers selected (rHandshake bit 3)
|   D0 (out) -- $FF/$00 = sense line (BMI = 1)
Sony_mSense:
        BTST    #0x3,rHandshake(A0)             | rHandshake bit 3: SENSE input
        SNE.B   D0                              | D0 = $FF if set
        TST.B   D0                              | CCR
        RTS                                     | return
| mPulse -- pulse LSTRB (PHASE3) through the phase register, keeping
| CA0-CA2: the drive executes the command at the selected address
Sony_mPulse:
        MOVE.W  SR,-(SP)                        | save SR
        ORI.W   #0x300,SR                       | no interrupts
        MOVE.L  D0,-(SP)                        | save D0
        MOVEQ.L #-0x8,D0                        | $F8: bits 4-7 outputs, bit 3 PHASE3 (LSTRB) high...
        OR.B    rPhase(A0),D0                   | ...PHASE0-2 (CA0-CA2) as they are
        MOVE.B  D0,wPhase(A0)                   | wPhase: LSTRB high
        NOP                                     | (pulse width)
        SUBQ.B  #0x8,D0                         | PHASE3 off
        MOVE.B  D0,wPhase(A0)                   | wPhase: LSTRB low
        MOVE.L  (SP)+,D0                        | restore D0
        MOVE.W  (SP)+,SR                        | restore SR
        RTS                                     | return

| -------------------------------------------------------------------------
| mDiskSelect -- jtDiskSel with the ISM registers selected: the mode
| register enables the drive (bit 1 + MotorOn: /ENBL1, the internal
| drives; bit 2 + MotorOn: /ENBL2, the external port); VIA PA4 chooses
| the lower/upper internal drive and the HD20 daisy chain is clocked
| through the phase register, as in the IWM version.
| -------------------------------------------------------------------------
Sony_mDiskSelect:
        CMPI.W  #Drive2,D1                      | internal drive (Drive1 or Drive2)?
        BGT.B   SONY_MDISKSEL_EXT               | no -> external drive or HD20
        CMPI.W  #Drive1,D1                      | drive 1?
        BNE.B   SONY_MDISKSEL_UPPER             | no -> upper drive
        BSET    #0x4,0x1E00(A2)                 | vDriveSel = 1: lower drive
        BRA.B   SONY_MDISKSEL_INT               | ->
SONY_MDISKSEL_UPPER:
        BCLR    #0x4,0x1E00(A2)                 | vDriveSel = 0: upper drive
SONY_MDISKSEL_INT:
        MOVE.B  #0x4,wZeroes(A0)                | wZeroes = $04: drive 2 (external) enable off
        MOVE.B  #0x82,wOnes(A0)                 | wOnes = $82: MotorOn + drive 1 enable: /ENBL1 (internal) active
        RTS                                     | return
SONY_MDISKSEL_EXT:
        MOVE.B  #0xF7,wPhase(A0)                | wPhase = $F7: state 7 (CA0-CA2 = 1) in case we are enabled
        BCLR    #0x5,0x1E00(A2)                 | SEL low (/Exist address)
        TST.B   PassThru(A1)                    | PassThru: HD20 pass-thru works?
        BEQ.B   SONY_MDISKSEL_CHAIN             | yes -> daisy-chain selection
        MOVE.B  #0x2,wZeroes(A0)                | wZeroes = $02: drive 1 (internal) enable off
        MOVE.B  #0x84,wOnes(A0)                 | wOnes = $84: MotorOn + drive 2 enable: /ENBL2 (external) active
        RTS                                     | return
SONY_MDISKSEL_CHAIN:
        CMPI.W  #Drive3,D1                      | drive 3 (external floppy)?
        BNE.B   SONY_MDISKSEL_HD20              | no -> HD20 drive
        MOVE.B  #0x2,wZeroes(A0)                | wZeroes = $02: internal enable off
        MOVE.B  #0x84,wOnes(A0)                 | wOnes = $84: MotorOn + external enable
        MOVEQ.L #0x2,D0                         | clock the chain at most 3 times
SONY_MDISKSEL_CLOCK:
        MOVE.W  SR,-(SP)                        | save the interrupt level
        ORI.W   #0x300,SR                       | no interrupts
        BRA.B   SONY_MDISKSEL_SENSE             | sense first
SONY_MDISKSEL_LOOP:
        MOVE.B  #0xFF,wPhase(A0)                | wPhase = $FF: LSTRB high
        MOVE.L  (SP),(SP)                       | (delay)
        MOVE.B  #0xF7,wPhase(A0)                | wPhase = $F7: LSTRB low
        MOVE.L  (SP),(SP)                       | (delay)
        MOVE.B  #0xF5,wPhase(A0)                | wPhase = $F5: CA1 low
        MOVE.L  (SP),(SP)                       | (delay)
        MOVE.B  #0xF7,wPhase(A0)                | wPhase = $F7: CA1 high
        MOVE.L  (SP),(SP)                       | (delay)
SONY_MDISKSEL_SENSE:
        BTST    #0x3,rHandshake(A0)             | rHandshake bit 3: sense line
        DBEQ    D0,SONY_MDISKSEL_LOOP           | until it is 0 or the count is done
        MOVE.W  (SP)+,SR                        | restore the interrupt level
        RTS                                     | return
SONY_MDISKSEL_HD20:
        MOVE.B  #0x4,wOnes(A0)                  | wOnes = $04: drive 2 (external) enable
        MOVE.B  #0x80,wZeroes(A0)               | wZeroes = $80: MotorOn off, drop /ENBL2
        MOVE.W  Drive(A1),D0                    | drive number
        MOVE.L  (SP),(SP)                       | (delay)
        MOVE.B  #0x80,wOnes(A0)                 | wOnes = $80: MotorOn, assert /ENBL2 again
        SUBQ.W  #0x4,D0                         | 4 -> 0, 5 -> 1: number of chain clocks
        BRA.B   SONY_MDISKSEL_CLOCK             | clock the chain

| -------------------------------------------------------------------------
| mGetTrack -- GetTrack for MFM disks: 9 (720K) or 18 (1440K) sectors per
| side on all 80 tracks, sectors numbered from 1
|   D0 (in)  -- block number
|   D0 (out) -- first sector wanted - 1, D2 = -1, D3 = sectors per side + 1,
|               D5 = track, D6 = side ($FF = side 1); continues at gtResume
| -------------------------------------------------------------------------
Sony_mGetTrack:
        MOVEQ.L #0x5A,D2                        | 720K: 90...
        LSL.W   #0x4,D2                         | ...* 16 = 1440 blocks
        MOVEQ.L #0x9,D3                         | 9 sectors per track side
        TST.B   twoMegFmt(A1,D1.W)              | twoMegFmt: 1440K disk?
        BPL.B   SONY_MGETTRACK_CHK              | no ->
        ADD.W   D2,D2                           | 1440K: 2880 blocks
        MOVEQ.L #0x12,D3                        | 18 sectors per track side
SONY_MGETTRACK_CHK:
        CMP.L   D2,D0                           | block beyond the end of the disk?
        BGE.W   SONY_DSKPARMERR                 | yes -> paramErr
        DIVU.W  D3,D0                           | D0 = [sector - 1][2 * track + side]
        LSR.W   #0x1,D0                         | side in the carry
        SCS.B   D6                              | D6 = $FF for side 1
        MOVE.W  D0,D5                           | D5 = track
        SWAP    D0                              | D0 = first sector wanted - 1
        MOVEQ.L #-0x1,D2                        | D2 = -1 (first block of the track, relative)
        ADDQ.W  #0x1,D3                         | D3 = sectors per side + 1
        BRA.W   SONY_GTRESUME                   | back into GetTrack (gtResume)
| mAddrMarks -- the four bytes of an MFM address mark
MADDRMARKS:
        .byte   0xA1,0xA1,0xA1,0xFE             | MFM address mark: three $A1 mark bytes, $FE

| -------------------------------------------------------------------------
| mRdAddr -- read the next MFM address field (through the jMRdAddr vector)
|   A5/A6 (in)  -- VIA port A / SCC data pointers (SetUpPoll)
|   D0 (out)    -- 0, noAdrMkErr (-67), badCkSmErr (-69: CRC) or
|                  noNybErr (-66: byte timeout)
|   D1 (out)    -- side/track (track in bits 0-10, side in bit 11)
|   D2 (out)    -- sector (1-9 or 1-18), D3 -- block size code + $20
|   A3/A4 (out) -- rHandshake / rMark pointers (for mRdData)
| The address field (cylinder, side, sector, size, 2 CRC bytes), the
| error and handshake registers end up in TagData+2.. . The disk must be
| up to speed with the head selected, the ISM registers selected and
| interrupts off. After ACTION is set the ISM itself looks for a sync
| field followed by a mark byte; the first byte it delivers is that mark
| byte (SWIM Chip User's Reference, mode register). All bytes are read
| through rMark, which returns data bytes too and does not flag a mark
| byte as an error (rData would). Byte timeouts use Apple's mByteTOCnt
| (30 here; 60 in System 7.1).
| -------------------------------------------------------------------------
Sony_mRdAddr:
        LEA.L   MADDRMARKS(PC),A2               | A2 -> address mark bytes
        MOVE.L  (0x680).w,-(SP)                 | push the jMRdAddr vector ($680)
        RTS                                     | and jump through it
| jtMRdAddr (jMRdAddr vector)
SONY_JTMRDADDR:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save the return address
        LEA.L   (BufTgFNum).w,A0                | A0 -> TagData+2
        CLR.L   (A0)+                           | zero 12 bytes of TagData
        CLR.L   (A0)+                           | (sector info is returned there)
        CLR.L   (A0)+                           | (TagData+2..+13)
        MOVEA.L (IWM).w,A4                      | A4 = SWIM base
        LEA.L   rHandshake(A4),A3               | A3 -> rHandshake
        LEA.L   rMark(A4),A4                    | A4 -> rMark
        MOVEQ.L #-0x43,D0                       | noAdrMkErr (-67): assume no address mark is found
        MOVE.W  #0x4E20,D2                      | timeout count for the search (20000, mSctrTOCnt)
SONY_MRDADDR_MARK:
        TST.B   rError-rMark(A4)                | rError: reading clears the error register (needed before a read)
        MOVE.B  #0x18,wZeroes-rMark(A4)         | wZeroes = $18: write and ACTION off (read mode)
        MOVE.B  #0x1,wOnes-rMark(A4)            | wOnes = $01: clear FIFO on...
        MOVE.B  #0x1,wZeroes-rMark(A4)          | ...and off: FIFO empty, CRC generator preset for reading
        TST.B   rError-rMark(A4)                | rError: clear it again
        MOVE.B  #0x8,wOnes-rMark(A4)            | wOnes = $08: ACTION on: look for sync field + mark byte
        MOVEA.L A2,A0                           | A0 -> mark bytes wanted
        MOVEQ.L #0x3,D1                         | four mark bytes
SONY_MRDADDR_POLL:
        TST.B   (A5)                            | SCC W/REQ (VIA PA7): byte waiting?
        BMI.B   SONY_MRDADDR_WAIT               | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MRDADDR_WAIT:
        TST.B   (A3)                            | rHandshake bit 7: byte in the FIFO?
        DBMI    D2,SONY_MRDADDR_POLL            | no -> wait (with timeout)
        BPL.W   SONY_MFM_READEXIT               | timed out -> noAdrMkErr
        MOVE.B  (A4),D5                         | read the byte (rMark: no error for a mark byte)
        CMP.B   (A0)+,D5                        | the expected mark byte?
        DBNE    D1,SONY_MRDADDR_POLL            | next one
        BNE.B   SONY_MRDADDR_MARK               | no -> restart the search
        MOVEQ.L #0x1E,D0                        | found the address mark: byte timeout count (mByteTOCnt)
SONY_MRDADDR_CYL:
        TST.B   (A3)                            | wait for a byte
        DBMI    D0,SONY_MRDADDR_CYL             | (with timeout)
        BPL.B   SONY_MRDADDR_TIMEOUT            | timeout -> noNybErr
        MOVEQ.L #0x0,D1                         | D1 = 0
        MOVE.B  (A4),D1                         | D1 = cylinder
        LEA.L   (BufTgFNum).w,A0                | A0 -> TagData+2: address field goes there
        MOVE.B  D1,(A0)+                        | store the cylinder
        MOVEQ.L #0x1E,D0                        | byte timeout count
SONY_MRDADDR_SIDE:
        TST.B   (A3)                            | wait for a byte
        DBMI    D0,SONY_MRDADDR_SIDE            | (with timeout)
        BPL.B   SONY_MRDADDR_TIMEOUT            | timeout
        MOVE.B  (A4),(A0)+                      | side number, also into the tags
        BEQ.B   SONY_MRDADDR_SECT               | side 0 ->
        BSET    #0xB,D1                         | side 1: bit 11 of the side/track word
SONY_MRDADDR_SECT:
        MOVEQ.L #0x1E,D0                        | byte timeout count
        MOVEQ.L #0x0,D2                         | D2 = 0
SONY_MRDADDR_SECTW:
        TST.B   (A3)                            | wait for a byte
        DBMI    D0,SONY_MRDADDR_SECTW           | (with timeout)
        BPL.B   SONY_MRDADDR_TIMEOUT            | timeout
        MOVE.B  (A4),D2                         | D2 = sector number
        MOVE.B  D2,(A0)+                        | into the tags
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MRDADDR_SIZE               | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MRDADDR_SIZE:
        MOVEQ.L #0x1E,D0                        | byte timeout count
        MOVEQ.L #0x20,D3                        | $20: makes it look like a two-sided format byte
SONY_MRDADDR_SIZEW:
        TST.B   (A3)                            | wait for a byte
        DBMI    D0,SONY_MRDADDR_SIZEW           | (with timeout)
        BPL.B   SONY_MRDADDR_TIMEOUT            | timeout
        OR.B    (A4),D3                         | D3 = block size code + $20
        MOVE.B  D3,(A0)+                        | into the tags
        MOVEQ.L #-0x45,D0                       | badCkSmErr (-69): assume a CRC error
        BRA.W   SONY_MFM_CHECKCRC               | check the CRC (shared with mRdData)
SONY_MRDADDR_TIMEOUT:
        BRA.W   SONY_MFM_READTOERR              | noNybErr
| mDataMarks -- the four bytes of an MFM data mark
MDATAMARKS:
        .byte   0xA1,0xA1,0xA1,0xFB             | MFM data mark: three $A1 mark bytes, $FB

| -------------------------------------------------------------------------
| mRdData -- read (or, with DskVerify set, compare) the data field that
| follows the address field just read (through the jMRdData vector)
|   A0 (in) -- data buffer (512 bytes), A3/A4 (in) -- from mRdAddr
|   D0 (out) -- 0, noDtaMkErr (-71), badDCksum (-72: CRC), dataVerErr
|               (-68: compare failed) or noNybErr (-66: timeout)
| The CRC bytes and the error and handshake registers go to TagData+10.
| D3 is preserved (mVerTrack uses it). The ISM is restarted as in
| mRdAddr; the next mark it finds must be the data mark.
| -------------------------------------------------------------------------
Sony_mRdData:
        LEA.L   MDATAMARKS(PC),A1               | A1 -> data mark bytes
        MOVE.L  (0x684).w,-(SP)                 | push the jMRdData vector ($684)
        RTS                                     | and jump through it
| jtMRdData (jMRdData vector)
SONY_JTMRDDATA:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save the return address
        MOVE.W  #0x1FF,D4                       | 512 bytes - 1
        TST.B   rError-rMark(A4)                | rError: clear the error register
        MOVE.B  #0x18,wZeroes-rMark(A4)         | wZeroes = $18: write and ACTION off (read mode)
        MOVE.B  #0x1,wOnes-rMark(A4)            | wOnes = $01: clear FIFO on...
        MOVE.B  #0x1,wZeroes-rMark(A4)          | ...and off: FIFO empty, CRC generator preset for reading
        TST.B   rError-rMark(A4)                | rError: clear it again
        MOVE.B  #0x8,wOnes-rMark(A4)            | wOnes = $08: ACTION on: look for sync field + mark byte
        MOVEQ.L #-0x47,D0                       | noDtaMkErr (-71): assume no data mark
        MOVEQ.L #0x3,D1                         | four mark bytes
        MOVEQ.L #-0x1,D2                        | timeout count
SONY_MRDDATA_MARK:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MRDDATA_WAIT               | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MRDDATA_WAIT:
        TST.B   (A3)                            | rHandshake bit 7: byte in the FIFO?
        DBMI    D2,SONY_MRDDATA_MARK            | no -> wait (with timeout)
        BPL.B   SONY_MRDDATA_TIMEOUT            | timed out -> noNybErr
        MOVEQ.L #0x1E,D2                        | byte timeout for the next byte (mByteTOCnt)
        MOVE.B  (A4),D5                         | read the byte
        CMP.B   (A1)+,D5                        | the expected data mark byte?
        DBNE    D1,SONY_MRDDATA_MARK            | next one
        BNE.B   SONY_MFM_READEXIT               | no -> noDtaMkErr
        TST.B   (DskVerify).w                   | DskVerify: compare instead of read?
        BNE.B   SONY_MRDDATA_VFY                | yes -> compare
SONY_MRDDATA_BLK:
        TST.B   (A3)                            | byte already there?
        BMI.B   SONY_MRDDATA_BYTE               | yes -> read it
        MOVEQ.L #0x1E,D1                        | byte timeout count
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MRDDATA_BLKW               | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MRDDATA_BLKW:
        TST.B   (A3)                            | wait for a byte
        DBMI    D1,SONY_MRDDATA_BLKW            | (with timeout)
        BPL.B   SONY_MRDDATA_TIMEOUT            | timeout -> noNybErr
SONY_MRDDATA_BYTE:
        MOVE.B  (A4),(A0)+                      | read the data byte into the buffer
        DBF     D4,SONY_MRDDATA_BLK             | 512 bytes
        BRA.B   SONY_MRDDATA_CRC                | check the CRC
SONY_MRDDATA_TIMEOUT:
        BRA.B   SONY_MFM_READTOERR              | noNybErr
SONY_MRDDATA_VFY:
        TST.B   (A3)                            | compare: byte already there?
        BMI.B   SONY_MRDDATA_VFYBYTE            | yes -> compare it
        MOVEQ.L #0x1E,D1                        | byte timeout count
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MRDDATA_VFYW               | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MRDDATA_VFYW:
        TST.B   (A3)                            | wait for a byte
        DBMI    D1,SONY_MRDDATA_VFYW            | (with timeout)
        BPL.B   SONY_MRDDATA_TIMEOUT            | timeout -> noNybErr
SONY_MRDDATA_VFYBYTE:
        MOVE.B  (A4),D2                         | read a data byte
        CMP.B   (A0)+,D2                        | the same as in the buffer?
        DBNE    D4,SONY_MRDDATA_VFY             | next (until done or a mismatch)
        BNE.B   SONY_MFM_VERIFYERR              | mismatch -> dataVerErr
SONY_MRDDATA_CRC:
        MOVEQ.L #-0x48,D0                       | badDCksum (-72): assume a CRC error
        LEA.L   (BufTgDate).w,A0                | A0 -> TagData+10: the CRC goes into the tags
| CheckCRC -- read the two CRC bytes; the handshake register is kept
| from before the second one is read: its CRC error bit (1) covers all
| bytes up to and including that byte (SWIM Chip User's Reference)
SONY_MFM_CHECKCRC:
        MOVEQ.L #0x1E,D4                        | CheckCRC: byte timeout count
SONY_MFM_CHECKCRC_1:
        TST.B   (A3)                            | wait for the first CRC byte
        DBMI    D4,SONY_MFM_CHECKCRC_1          | (with timeout)
        BPL.B   SONY_MFM_READTOERR              | timeout
        MOVE.B  (A4),(A0)+                      | save it in the tags
        MOVEQ.L #0x1E,D4                        | byte timeout count
SONY_MFM_CHECKCRC_2:
        MOVE.B  (A3),D5                         | wait for the second CRC byte, keep the handshake register
        DBMI    D4,SONY_MFM_CHECKCRC_2          | (with timeout)
        BPL.B   SONY_MFM_READTOERR              | timeout
        MOVE.B  (A4),(A0)+                      | second CRC byte into the tags
        MOVE.B  rError-rMark(A4),(A0)+          | followed by the error register (reading clears it)
        MOVE.B  D5,(A0)                         | and the handshake register
        ANDI.B  #0x22,D5                        | handshake bit 1 (CRC error) or bit 5 (an rError bit set)?
        BNE.B   SONY_MFM_READEXIT               | yes -> return the error
        MOVEQ.L #0x0,D0                         | noErr
| Branch from: SONY_MRDADDR_WAIT, SONY_MRDDATA_WAIT, SONY_MFM_CHECKCRC_2, SONY_MFM_READTOERR, SONY_MFM_VERIFYERR
SONY_MFM_READEXIT:
        MOVE.B  #0x18,wZeroes-rMark(A4)         | ReadExit: wZeroes = $18, write and ACTION off
        MOVE.L  (DskRtnAdr).w,-(SP)             | push the return address
        TST.W   D0                              | CCR = result
        RTS                                     | return
SONY_MFM_READTOERR:
        MOVEQ.L #-0x42,D0                       | noNybErr (-66): timed out waiting for a byte
        BRA.B   SONY_MFM_READEXIT               | exit
SONY_MFM_VERIFYERR:
        MOVEQ.L #-0x44,D0                       | dataVerErr (-68): read-verify compare failed
        BRA.B   SONY_MFM_READEXIT               | exit

| -------------------------------------------------------------------------
| mWrData -- write the data field of the sector whose address field was
| just read (through the jMWrData vector): after a timed delay (the
| write splice, so that the data field starts about 22 bytes after the
| address field) 12 sync bytes, the data mark, 512 data bytes and the 2
| CRC bytes, then 4 gap bytes so that the CRC is shifted out completely
| before writing stops. No other overhead, so MFM can write one-to-one.
| First the phase lines are set to drive address 5/7 (CA0 = CA2 = 1,
| CA1 = 0; SEL, the head, unchanged) instead of the read data address
| 1/3: that takes the drive's index signal off SENSE while writing
| (Apple 1.3, May 88: "to avoid the drive's index crosstalk problem").
| Writing starts with two bytes in the FIFO before ACTION is set; an
| underrun ends the write (the ISM clears ACTION) and shows as the
| handshake register's error bit.
|   A0 (in) -- data buffer, A5/A6 (in) -- VIA port A / SCC data pointers
|   D0 (out) -- 0 or wrUnderrun (-74)
| -------------------------------------------------------------------------
Sony_mWrData:
        LEA.L   MDATAMARKS(PC),A2               | A2 -> data mark bytes
        MOVE.L  (0x688).w,-(SP)                 | push the jMWrData vector ($688)
        RTS                                     | and jump through it
| jtMWrData (jMWrData vector)
SONY_JTMWRDATA:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save the return address
        MOVEA.L (IWM).w,A4                      | A4 = SWIM base
        LEA.L   (A4),A3                         | A3 -> wData
        LEA.L   rHandshake(A4),A4               | A4 -> rHandshake
        MOVE.B  #0xF5,wPhase-wData(A3)          | wPhase = $F5: CA0 = CA2 = 1, CA1 = 0: drive address 5/7, index signal off
        TST.B   rError-wData(A3)                | rError: clear the error register
        MOVE.B  #0x18,wZeroes-wData(A3)         | wZeroes = $18: write and ACTION off
        MOVE.B  #0x10,wOnes-wData(A3)           | wOnes = $10: write mode (before the FIFO is cleared: CRC preset for writing)
        MOVE.B  #0x1,wOnes-wData(A3)            | wOnes = $01: clear FIFO on...
        MOVE.B  #0x1,wZeroes-wData(A3)          | ...and off: FIFO empty
        TST.B   rError-wData(A3)                | rError: clear it again
        MOVE.W  #0x2C26,D0                      | write splice: wait $2C26/65536 ms = 172 us...
        MULU.W  (TimeSCCDB).w,D0                | ...* TimeSCCDB (SCC polling loops per ms)
        SWAP    D0                              | D0.W = loop count
SONY_MWRDATA_DELAY:
        BTST    #0x7,(A5)                       | SCC W/REQ: byte waiting?
        DBEQ    D0,SONY_MWRDATA_DELAY           | wait (TimeSCCDB assumes this loop)
        BNE.B   SONY_MWRDATA_SYNC               | time is up ->
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
        SUBQ.W  #0x2,D0                         | adjust for the missed DBEQ and the MOVE
        BPL.B   SONY_MWRDATA_DELAY              | wait some more
SONY_MWRDATA_SYNC:
        MOVEQ.L #0x9,D0                         | 10 more sync bytes
        MOVEQ.L #0x0,D1                         | sync byte $00
        MOVE.B  D1,(A3)                         | first two sync bytes...
        MOVE.B  D1,(A3)                         | ...fill the FIFO
        MOVE.B  #0x8,wOnes-wData(A3)            | wOnes = $08: ACTION on, start writing
SONY_MWRDATA_SYNCLOOP:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MWRDATA_SYNCW              | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MWRDATA_SYNCW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MWRDATA_SYNCW              | no -> wait
        MOVE.B  D1,(A3)                         | write a sync byte
        DBF     D0,SONY_MWRDATA_SYNCLOOP        | loop
        MOVEQ.L #0x2,D0                         | three mark bytes
SONY_MWRDATA_MARK:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MWRDATA_MARKW              | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MWRDATA_MARKW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MWRDATA_MARKW              | no -> wait
        MOVE.B  (A2)+,wMark-wData(A3)           | wMark: write $A1 as a mark byte
        DBF     D0,SONY_MWRDATA_MARK            | loop
SONY_MWRDATA_LASTMARK:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MWRDATA_LASTMARK           | no -> wait
        MOVE.B  (A2),(A3)                       | last mark byte ($FB) as data
        MOVE.W  #0x1FF,D0                       | 512 bytes - 1
SONY_MWRDATA_DATA:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MWRDATA_DATAW              | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MWRDATA_DATAW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MWRDATA_DATAW              | no -> wait
        MOVE.B  (A0)+,(A3)                      | write a data byte
        DBF     D0,SONY_MWRDATA_DATA            | loop
SONY_MWRDATA_CRC:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MWRDATA_CRC                | no -> wait
        MOVE.B  D0,wCRC-wData(A3)               | wCRC: the ISM writes its two CRC bytes (the byte written does not matter)
        MOVEQ.L #0x3,D0                         | four gap bytes
SONY_MWRDATA_GAP:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MWRDATA_GAPW               | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MWRDATA_GAPW:
        MOVE.B  (A4),D2                         | room in the FIFO? (keep the handshake)
        BPL.B   SONY_MWRDATA_GAPW               | no -> wait
        MOVE.B  #0x4E,(A3)                      | write a gap byte ($4E)
        DBF     D0,SONY_MWRDATA_GAP             | loop
        MOVEQ.L #0x0,D0                         | assume no underrun
        BTST    #0x5,D2                         | handshake bit 5: an rError bit (underrun) set?
        BEQ.B   SONY_MWRDATA_EXIT               | no ->
        MOVEQ.L #-0x4A,D0                       | wrUnderrun (-74)
SONY_MWRDATA_EXIT:
        MOVE.B  #0x18,wZeroes-wData(A3)         | wZeroes = $18: write and ACTION off
        MOVE.L  (DskRtnAdr).w,-(SP)             | push the return address
        TST.W   D0                              | CCR = result
        RTS                                     | return

| -------------------------------------------------------------------------
| mFmtTrack -- format both sides of the current MFM track (called by
| CtlFormat in the tail through SONY_DRVENT_MFMTTRACK)
|   D0 (out) -- 0 or error code
| Before side 1 it waits 750 us so the drive accepts the head switch.
| -------------------------------------------------------------------------
Sony_mFmtTrack:
        BSR.W   Sony_GetDrv1                    | GetDrv1: A1, D1
        MOVE.W  SideTrack(A1),D4                | D4 = current side/track
        MOVEQ.L #0x0,D5                         | D5 = 0: side 0
        BCLR    #0xB,D4                         | side 1?
        BEQ.B   SONY_MFMTTRACK_FMT              | no ->
        MOVEQ.L #0x1,D5                         | D5 = 1: side 1
        MOVEQ.L #0x0,D2                         | D2.L = 0
        MOVE.W  (TimeDBRA).w,D2                 | D2 = TimeDBRA (DBRA loops per ms)
        MOVE.L  D2,D0                           | D0 = TimeDBRA
        ADD.L   D2,D0                           | * 2
        ADD.L   D2,D0                           | * 3
        LSR.L   #0x2,D0                         | / 4 = DBF count for 750 us
SONY_MFMTTRACK_DELAY:
        DBF     D0,SONY_MFMTTRACK_DELAY         | wait before switching heads
SONY_MFMTTRACK_FMT:
        MOVEQ.L #0x8,D2                         | 9 sectors - 1 (720K)
        MOVE.B  twoMegFmt(A1,D1.W),D0           | twoMegFmt: 1440K disk?
        BPL.B   SONY_MFMTTRACK_DOIT             | no ->
        MOVEQ.L #0x11,D2                        | 18 sectors - 1 (1440K)
        BSET    #0x1F,D2                        | bit 31: double density
SONY_MFMTTRACK_DOIT:
        BSR.B   Sony_mDoFormat                  | mDoFormat: format this side (interrupts off)
        BSR.W   SONY_TAIL_TOEMPTYPD             | toEmptyPD (tail): process the poll data, result in DskErr
        ANDI.W  #0xF8FF,SR                      | open interrupts
        MOVE.W  (DskErr).w,D0                   | error?
        BNE.B   SONY_MFMTTRACK_EXIT             | yes -> return it
        BSR.W   Sony_GetDrv1                    | GetDrv1
        BSET    #0x3,SideTrack(A1)              | second side done? (set the side bit: bit 11 of SideTrack)
        BEQ.B   Sony_mFmtTrack                  | no -> format side 1
        MOVEQ.L #0x0,D0                         | noErr
SONY_MFMTTRACK_EXIT:
        RTS                                     | return

| -------------------------------------------------------------------------
| mDoFormat -- format one side of an MFM track (interrupts off, disk up to
| speed, head positioned)
|   D2 (in) -- sectors per track - 1 (8 or 17; bit 31 = 1440K)
|   D4 (in) -- track, D5 (in) -- side
|   D0 (out) -- 0, noIndexErr (-83, Fmt2Err) or wrUnderrun
| The track layout is described at the start of the SWIM section. While
| waiting for the index pulse (the SuperDrive puts it on SENSE while the
| read data address 1/3 is selected) the ISM already writes gap bytes;
| the track starts at the pulse's rising edge. Then the phase lines go
| to drive address 5/7 (index signal off, Apple 1.3) until 5 gap bytes
| after the last sector. The data fields are filled with $F6. Side 0
| ends after those 5 bytes, before the index pulse, so that the head can
| be switched in time (about 1 ms; Apple: 3 instead of 4 revolutions per
| cylinder, 16 s less for a disk).
| -------------------------------------------------------------------------
Sony_mDoFormat:
        MOVE.L  (SP)+,(DskRtnAdr).w             | save the return address
        MOVEQ.L #0x1,D0                         | RdDtaAdr: head of side 0
        TST.W   D5                              | side 0?
        BEQ.B   SONY_MDOFORMAT_HEAD             | yes ->
        MOVEQ.L #0x3,D0                         | RdDta1Adr: head of side 1
SONY_MDOFORMAT_HEAD:
        BSR.W   Sony_AdrDisk                    | AdrDisk: select the head
        MOVEQ.L #0x4,D0                         | 4 bytes of poll data space
        BSR.W   SONY_TAIL_E_SETUPPOLL           | SetUpPoll (tail): A5, A6, PollStack
        MOVEA.L (IWM).w,A4                      | A4 = SWIM base
        LEA.L   (A4),A3                         | A3 -> wData
        LEA.L   rHandshake(A4),A4               | A4 -> rHandshake
        TST.B   rError-wData(A3)                | rError: clear the error register
        MOVE.B  #0x18,wZeroes-wData(A3)         | wZeroes = $18: write and ACTION off
        MOVE.B  #0x10,wOnes-wData(A3)           | wOnes = $10: write mode
        MOVE.B  #0x1,wOnes-wData(A3)            | wOnes = $01: toggle clear FIFO...
        MOVE.B  #0x1,wZeroes-wData(A3)          | ...to empty the FIFO
        MOVEQ.L #0x4E,D1                        | gap byte $4E
        MOVE.B  D1,(A3)                         | first two gap bytes...
        MOVE.B  D1,(A3)                         | ...fill the FIFO
        MOVE.B  #0x8,wOnes-wData(A3)            | wOnes = $08: ACTION on, start writing
        MOVE.W  #0x34BC,D3                      | index timeout: 2 * 6750 bytes (300 rpm, 16 us per byte)
SONY_MDOFORMAT_IDXLO:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_IDXLOW           | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_IDXLOW:
        MOVE.B  (A4),D0                         | room in the FIFO? (keep the handshake)
        BPL.B   SONY_MDOFORMAT_IDXLOW           | no -> wait
        MOVE.B  D1,(A3)                         | write a gap byte
        BTST    #0x3,D0                         | handshake bit 3, SENSE = index signal: low?
        BEQ.B   SONY_MDOFORMAT_IDXHI            | yes -> wait for it to go high
        DBF     D3,SONY_MDOFORMAT_IDXLO         | keep waiting
        BRA.W   SONY_MDOFORMAT_NOINDEX          | timed out -> noIndexErr
SONY_MDOFORMAT_IDXHI:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_IDXHIW           | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_IDXHIW:
        MOVE.B  (A4),D0                         | room in the FIFO? (keep the handshake)
        BPL.B   SONY_MDOFORMAT_IDXHIW           | no -> wait
        MOVE.B  D1,(A3)                         | write a gap byte
        BTST    #0x3,D0                         | SENSE: index pulse high?
        BNE.B   SONY_MDOFORMAT_START            | yes -> start of the track
        DBF     D3,SONY_MDOFORMAT_IDXHI         | keep waiting
        BRA.W   SONY_MDOFORMAT_NOINDEX          | timed out -> noIndexErr
SONY_MDOFORMAT_START:
        MOVE.B  #0xF5,wPhase-wData(A3)          | wPhase = $F5: drive address 5/7, index signal off while formatting
        MOVEQ.L #0x4E,D0                        | 79 more gap bytes (80 in all)
SONY_MDOFORMAT_GAP4A:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_GAP4AW           | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_GAP4AW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_GAP4AW           | no -> wait
        MOVE.B  D1,(A3)                         | gap byte
        DBF     D0,SONY_MDOFORMAT_GAP4A         | loop
        MOVEQ.L #0xB,D0                         | 12 sync bytes
        MOVEQ.L #0x0,D1                         | sync byte $00
SONY_MDOFORMAT_ISYNC:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_ISYNCW           | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_ISYNCW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_ISYNCW           | no -> wait
        MOVE.B  D1,(A3)                         | sync byte
        DBF     D0,SONY_MDOFORMAT_ISYNC         | loop
        MOVEQ.L #0x2,D0                         | three index mark bytes
SONY_MDOFORMAT_IMARK:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_IMARKW           | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_IMARKW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_IMARKW           | no -> wait
        MOVE.B  #0xC2,wMark-wData(A3)           | wMark: $C2 as a mark byte
        DBF     D0,SONY_MDOFORMAT_IMARK         | loop
SONY_MDOFORMAT_IMARK4:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_IMARK4           | no -> wait
        MOVE.B  #0xFC,(A3)                      | $FC: end of the index mark
        MOVEQ.L #0x31,D0                        | 50 gap bytes
SONY_MDOFORMAT_GAP1:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_GAP1W            | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_GAP1W:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_GAP1W            | no -> wait
        MOVE.B  #0x4E,(A3)                      | gap byte
        DBF     D0,SONY_MDOFORMAT_GAP1          | loop
        MOVEQ.L #0x1,D6                         | first sector: 1
        BRA.B   SONY_MDOFORMAT_ASYNC            | start with its sync bytes
SONY_MDOFORMAT_NEXTSECT:
        MOVEQ.L #0x4F,D0                        | 80 gap bytes after a sector (720K)
        TST.L   D2                              | 1440K?
        BPL.B   SONY_MDOFORMAT_GAP3             | no ->
        MOVEQ.L #0x64,D0                        | 101 gap bytes (1440K)
SONY_MDOFORMAT_GAP3:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_GAP3W            | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_GAP3W:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_GAP3W            | no -> wait
        MOVE.B  #0x4E,(A3)                      | gap byte
        DBF     D0,SONY_MDOFORMAT_GAP3          | loop
SONY_MDOFORMAT_ASYNC:
        MOVEQ.L #0xB,D0                         | 12 sync bytes
        MOVEQ.L #0x0,D1                         | sync byte $00
SONY_MDOFORMAT_ASYNCL:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_ASYNCW           | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_ASYNCW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_ASYNCW           | no -> wait
        MOVE.B  D1,(A3)                         | sync byte
        DBF     D0,SONY_MDOFORMAT_ASYNCL        | loop
        MOVEQ.L #0x2,D0                         | three address mark bytes
SONY_MDOFORMAT_AMARK:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_AMARKW           | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_AMARKW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_AMARKW           | no -> wait
        MOVE.B  #0xA1,wMark-wData(A3)           | wMark: $A1 as a mark byte
        DBF     D0,SONY_MDOFORMAT_AMARK         | loop
SONY_MDOFORMAT_AMARK4:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_AMARK4           | no -> wait
        MOVE.B  #0xFE,(A3)                      | $FE: end of the address mark
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_CYL              | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_CYL:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_CYL              | no -> wait
        MOVE.B  D4,(A3)                         | cylinder (track) number
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_SIDE             | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_SIDE:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_SIDE             | no -> wait
        MOVE.B  D5,(A3)                         | side number
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_SECT             | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_SECT:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_SECT             | no -> wait
        MOVE.B  D6,(A3)                         | sector number
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_SIZE             | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_SIZE:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_SIZE             | no -> wait
        MOVE.B  #0x2,(A3)                       | block size code 2: 512 bytes
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_ACRC             | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_ACRC:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_ACRC             | no -> wait
        MOVE.B  D0,wCRC-wData(A3)               | wCRC: the two CRC bytes of the address field
        MOVEQ.L #0x15,D0                        | 22 gap bytes
SONY_MDOFORMAT_GAP2:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_GAP2W            | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_GAP2W:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_GAP2W            | no -> wait
        MOVE.B  #0x4E,(A3)                      | gap byte
        DBF     D0,SONY_MDOFORMAT_GAP2          | loop
        MOVEQ.L #0xB,D0                         | 12 sync bytes
        MOVEQ.L #0x0,D1                         | sync byte $00
SONY_MDOFORMAT_DSYNC:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_DSYNCW           | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_DSYNCW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_DSYNCW           | no -> wait
        MOVE.B  D1,(A3)                         | sync byte
        DBF     D0,SONY_MDOFORMAT_DSYNC         | loop
        MOVEQ.L #0x2,D0                         | three data mark bytes
SONY_MDOFORMAT_DMARK:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_DMARKW           | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_DMARKW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_DMARKW           | no -> wait
        MOVE.B  #0xA1,wMark-wData(A3)           | wMark: $A1 as a mark byte
        DBF     D0,SONY_MDOFORMAT_DMARK         | loop
SONY_MDOFORMAT_DMARK4:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_DMARK4           | no -> wait
        MOVE.B  #0xFB,(A3)                      | $FB: end of the data mark
        MOVE.W  #0x1FF,D0                       | 512 bytes - 1
SONY_MDOFORMAT_DATA:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_DATAW            | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_DATAW:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_DATAW            | no -> wait
        MOVE.B  #0xF6,(A3)                      | fill byte $F6
        DBF     D0,SONY_MDOFORMAT_DATA          | loop
SONY_MDOFORMAT_DCRC:
        TST.B   (A4)                            | room in the FIFO?
        BPL.B   SONY_MDOFORMAT_DCRC             | no -> wait
        MOVE.B  D0,wCRC-wData(A3)               | wCRC: the two CRC bytes of the data field
        ADDQ.W  #0x1,D6                         | next sector number
        DBF     D2,SONY_MDOFORMAT_NEXTSECT      | next sector
        MOVEQ.L #0x4,D0                         | 5 gap bytes before looking at the index again
        MOVEQ.L #0x4E,D1                        | gap byte $4E
        MOVE.W  #0x3E8,D3                       | up to 1000 gap bytes to the index pulse
        TST.W   D5                              | side 0?
        BNE.B   SONY_MDOFORMAT_LASTGAP          | no -> wait for the index pulse
        MOVEQ.L #0x4,D3                         | side 0: stop after the 5 bytes
        BRA.B   SONY_MDOFORMAT_LASTGAP          | write them
SONY_MDOFORMAT_IDXON:
        MOVE.B  #0xF4,wPhase-wData(A3)          | wPhase = $F4: CA2 = 1, CA0 = CA1 = 0: address 1/3 again, index signal back on SENSE
SONY_MDOFORMAT_LASTGAP:
        TST.B   (A5)                            | SCC W/REQ: byte waiting?
        BMI.B   SONY_MDOFORMAT_LASTGAPW         | no -> skip
        MOVE.B  (A6),-(SP)                      | push the SCC byte (poll data)
SONY_MDOFORMAT_LASTGAPW:
        MOVE.B  (A4),D2                         | room in the FIFO? (keep the handshake)
        BPL.B   SONY_MDOFORMAT_LASTGAPW         | no -> wait
        MOVE.B  D1,(A3)                         | gap byte
        SUBQ.W  #0x1,D0                         | first 5 bytes written?
        BGT.B   SONY_MDOFORMAT_LASTNEXT         | no -> next
        BEQ.B   SONY_MDOFORMAT_IDXON            | just now -> turn the index signal on
        BTST    #0x3,D2                         | SENSE: index pulse high?
        BNE.B   SONY_MDOFORMAT_DONE             | yes -> done
SONY_MDOFORMAT_LASTNEXT:
        DBF     D3,SONY_MDOFORMAT_LASTGAP       | next gap byte
        TST.W   D5                              | side 0?
        BEQ.B   SONY_MDOFORMAT_DONE             | yes -> the index pulse does not matter
SONY_MDOFORMAT_NOINDEX:
        MOVEQ.L #-0x53,D0                       | noIndexErr (-83, Fmt2Err): no index pulse
        BRA.B   SONY_MDOFORMAT_EXIT             | exit
SONY_MDOFORMAT_DONE:
        MOVEQ.L #0x0,D0                         | assume no underrun
        BTST    #0x5,D2                         | handshake bit 5: an rError bit (underrun) set?
        BEQ.B   SONY_MDOFORMAT_EXIT             | no ->
        MOVEQ.L #-0x4A,D0                       | wrUnderrun (-74)
SONY_MDOFORMAT_EXIT:
        MOVE.B  #0x18,wZeroes-wData(A3)         | wZeroes = $18: write and ACTION off
        MOVE.L  (DskRtnAdr).w,-(SP)             | push the return address
        TST.W   D0                              | CCR = result
        RTS                                     | return

| -------------------------------------------------------------------------
| mVerTrack -- verify both sides of the current MFM track: read every
| sector (allowing four revolutions) and check that track and side match
|   D6 (in) -- track, A1/D1 (in) -- SonyVars / drive vars
|   D0 (out) -- 0 or verErr (-84)
| -------------------------------------------------------------------------
Sony_mVerTrack:
        MOVEM.L D2-D7,-(SP)                     | save registers
        ORI.W   #0x300,SR                       | no interrupts
        MOVE.W  D6,SideTrack(A1)                | SideTrack = track, side 0
SONY_MVERTRACK_SIDE:
        MOVEQ.L #0x24,D7                        | 4 * 9 tries (720K)
        MOVE.L  #0x3FE,D6                       | sector map: sectors 1-9
        TST.B   twoMegFmt(A1,D1.W)              | twoMegFmt: 1440K disk?
        BPL.B   SONY_MVERTRACK_LOOP             | no ->
        MOVEQ.L #0x48,D7                        | 4 * 18 tries
        MOVE.L  #0x7FFFE,D6                     | sector map: sectors 1-18
SONY_MVERTRACK_LOOP:
        BSR.W   SONY_TAIL_RDADDRSETUP           | RdAddrSetup (tail): next address mark
        BNE.B   SONY_MVERTRACK_NEXT             | error -> next
        BTST    D2,D6                           | this sector still to be read?
        BEQ.B   SONY_MVERTRACK_NEXT             | no -> next
        CMP.W   SideTrack(A1),D1                | track and side as expected?
        BNE.B   SONY_MVERTRACK_NEXT             | no -> next
        MOVE.W  D2,D3                           | D3 = sector number
        MOVEA.L DiskBuffer(A1),A0               | A0 = buffer
        CLR.B   (DskVerify).w                   | no read-verify (we only want to read)
        BSR.W   Sony_mRdData                    | mRdData: read the sector
        BNE.B   SONY_MVERTRACK_NEXT             | error -> next
        BCLR    D3,D6                           | sector done
SONY_MVERTRACK_NEXT:
        BSR.W   SONY_TAIL_TOEMPTYPD             | toEmptyPD (tail): process the poll data
        TST.L   D6                              | all sectors read?
        DBEQ    D7,SONY_MVERTRACK_LOOP          | no -> again (while tries are left)
        BEQ.B   SONY_MVERTRACK_NEXTSIDE         | yes -> next side
        MOVEQ.L #-0x54,D0                       | verErr (-84): not every sector could be read
        BRA.B   SONY_MVERTRACK_EXIT             | exit
SONY_MVERTRACK_NEXTSIDE:
        BSET    #0x3,SideTrack(A1)              | second side done? (set side bit)
        BEQ.B   SONY_MVERTRACK_SIDE             | no -> verify side 1
SONY_MVERTRACK_EXIT:
        ANDI.W  #0xF8FF,SR                      | open interrupts
        MOVEM.L (SP)+,D2-D7                     | restore registers
        TST.W   D0                              | CCR = result
        RTS                                     | return

| -------------------------------------------------------------------------
| DCDPrime -- read/write on an HD20 (from jtDiskPrime, interrupts still at
| IPL 1). The first access to a drive issues a status command to learn
| its size and characteristics; then the blocks are transferred with up
| to 255 blocks per command, with retries and one hard reset.
| -------------------------------------------------------------------------
Sony_DCDPrime:
        ANDI    #-0x701,SR                      | restore IPL to 0 (DCD path)
        MOVE.W  LastDrive(A1),D0                | D0 = previous drive (LastDrive)
        CMP     Drive(A1),D0                    | same as current DCD drive?
        BEQ.B   SONY_DCDPRIME_SELECT            | yes -> skip settling delay
        MOVEQ.L #0xA,D0                         | 1ms drive-switch settling delay
        BSR.W   Sony_CallWakeUp                 | wait for drive to stabilize
SONY_DCDPRIME_SELECT:
        MOVE.L  (IWM).w,A0                      | A0 = IWM base address
        TST.B   (A0)                            | CA0 low (ph0L)
        TST.B   0x800(A0)                       | CA2 low: with CA1 high, SEL low the HD20's HSHK is the sense line
        CMPI.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace >= 2 (already mounted)?
        BGE.B   SONY_DCDPRIME_GO                | yes -> skip DCD status query
        LEA.L   SONY_DCDPRIME_STATUS(PC),A0     | A0 = DCD status completion callback
        MOVE.L  A0,StsRtnAddr(A1)               | StsRtnAddr: save callback address
        BRA.W   Sony_DCDStatus                  | go issue DCD status command
SONY_DCDPRIME_STATUS:
        BNE.W   SONY_DCDEXIT                    | DCD status error -> return
        BSR.W   Sony_GetDrive                   | reload IWM/VIA/SonyVars
        MOVE.B  #0x8,DiskInPlace(A1,D1.W)       | DiskInPlace = 8: DCD disk present
        MOVE.L  TagBytes(A1),DriveType(A1,D1.W) | DriveType/DriveManf = device type, manufacturer
        MOVE.L  DevChar(A1),D0                  | D0 = characteristics byte + 3-byte block count (DevChar)
        SWAP    D0                              | block count low word to the high word
        MOVE.L  D0,DriveSize(A1,D1.W)           | drive size = block count, low word first
        CLR.B   DriveS1(A1,D1.W)                | high byte of DriveS1 = 0: dQDrvSz2 = bits 16-23 of the block count
        LSR     #0x8,D0                         | D0 = characteristics byte
        MOVE.B  D0,DriveChar(A1,D1.W)           | DriveChar
        BTST    #0x3,D0                         | DevChWP (bit 3): write-protected?
        SNE.B   WriteProt(A1,D1.W)              | WrProt: $FF if write-protected
        BTST    #0x4,D0                         | DevChEject (bit 4): removable medium?
        BEQ.B   SONY_DCDPRIME_GO                | no -> DiskInPlace stays 8
        MOVE.B  #0x2,DiskInPlace(A1,D1.W)       | DiskInPlace = 2
SONY_DCDPRIME_GO:
        MOVE.L  (A1),A2                         | A2 = DCE pointer
        MOVE.L  0x10(A2),D5                     | D5 = dCtlPosition (byte offset)
        MOVEQ.L #0x9,D1                         | shift count for /512
        LSR.L   D1,D5                           | D5 = starting block number
        MOVE.L  0x8(A2),A0                      | A0 = IOParam block
        MOVEA.L TagBufPtr(A1),A5                | A5 = TagBufPtr (or nil)
        MOVE.L  0x20(A0),A4                     | A4 = ioBuffer pointer
        MOVE.L  0x24(A0),D3                     | D3 = ioReqCount (total bytes)
        MOVEQ.L #-0x32,D0                       | paramErr (-50): assume bad position
        ANDI    #0x1FF,D3                       | check alignment (must be 512 multiple)
        BNE.W   SONY_DCDEXIT                    | not aligned -> return paramErr
        MOVE.L  0x24(A0),D3                     | D3 = ioReqCount (reload)
        TST.B   (DskVerify).w                   | read-verify mode (DskVerify)?
        BEQ.B   SONY_DCDPRIME_CMD               | no -> proceed with I/O
        BSR.W   Sony_CheckRead                  | check if read operation
        BNE.B   SONY_DCDPRIME_CMD               | write -> proceed with I/O
        MOVE.L  D3,0x28(A0)                     | verify read: set ioActCount = full
        ADD.L   D3,0x10(A2)                     | advance dCtlPosition by full count
        MOVEQ.L #0x0,D0                         | noErr: verify read is a no-op for DCD
        BRA.W   SONY_DCDEXIT                    | return success
SONY_DCDPRIME_CMD:
        MOVE.B  Command+1(A1),DCDCmd(A1)        | DCDCmd = ioTrap (2=read, 3=write)
        SUBQ.B  #0x2,DCDCmd(A1)                 | convert: 0=read, 1=write
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
        CLR.B   DCDFlags(A1)                    | DCDFlags: clear reset/retry flags
SONY_DCDPRIME_RETRY:
        BSR.W   SONY_DCDSETUPCMD                | build DCD command packet
        BSR.W   E_Sony_SendCmd                  | send command to DCD
        BNE.B   SONY_DCDPRIME_ERR               | send failed -> retry/error
SONY_DCDPRIME_WAIT:
        BSR.W   SONY_DCDWAITHSHK                | wait for DCD ready (poll HSHK)
        BPL.B   SONY_DCDPRIME_RCV               | ready -> receive response
        MOVE.B  #0x2,LastResult(A1)             | LastResult = comErr (comm failure)
        CLR.L   LastStatus(A1)                  | clear LastStatus
        MOVE.B  #0x40,LastStatus(A1)            | LastStatus = NoResp ($40)
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
        CMPI.B  #0x2,LastResult(A1)             | LastResult == comErr?
        BNE.B   SONY_DCDPRIME_AGAIN             | no -> retry without reset
        BTST    #0x1E,LastStatus(A1)            | bChksum: checksum error in status?
        BNE.B   SONY_DCDPRIME_AGAIN             | yes -> retry without reset
        TST.B   DCDFlags(A1)                    | DCDFlags: already tried reset?
        BEQ.B   SONY_DCDPRIME_RESET             | no -> try DCD reset
        CLR.B   RecalCnt(A1)                    | force last attempt
SONY_DCDPRIME_RESET:
        BSR.W   E_Sony_DCDReset                 | hard-reset the DCD controller
        BNE.B   SONY_DCDPRIME_FAIL              | reset failed -> fatal error
        ST.B    DCDFlags(A1)                    | DCDFlags: mark reset attempted
SONY_DCDPRIME_AGAIN:
        BRA.B   SONY_DCDPRIME_RETRY             | retry the DCD command
SONY_DCDPRIME_FAIL:
        MOVEQ.L #-0x13,D0                       | readErr (-19): DCD read failed
        CMPI.B  #0x2,Command+1(A1)              | was this a read operation?
        BEQ.B   SONY_DCDPRIME_FAILEXIT          | yes -> return readErr
        MOVEQ.L #-0x14,D0                       | writErr (-20): DCD write failed
SONY_DCDPRIME_FAILEXIT:
        BRA.B   SONY_DCDEXIT                    | return error
SONY_DCDPRIME_DONE:
        MOVEQ.L #0x9,D1                         | shift count for *512
        CLR     D3                              | clear low word of D3
        SWAP    D3                              | D3 = blocks transferred this round
        CMPI.B  #0x2,Command+1(A1)              | read operation?
        BEQ.B   SONY_DCDPRIME_UPDATE            | yes -> skip tag update
        ADD.L   D3,(BufTgFFlg).w                | write: advance tag file block number
SONY_DCDPRIME_UPDATE:
        LSL.L   D1,D3                           | D3 = bytes transferred (* 512)
        MOVE.L  (A1),A3                         | A3 = DCE pointer
        ADD.L   D3,0x10(A3)                     | advance dCtlPosition by bytes done
        MOVE.L  0x8(A3),A0                      | A0 = IOParam block
        ADD.L   D3,0x28(A0)                     | advance ioActCount by bytes done
        MOVE.L  0x24(A0),D3                     | D3 = ioReqCount (total requested)
        SUB.L   0x28(A0),D3                     | D3 = remaining bytes
        BGT.W   SONY_DCDPRIME_NEXT              | more data -> issue next DCD command
        MOVEQ.L #0x0,D0                         | noErr: DCD transfer complete
| DCD exit -- drop /ENBL, open interrupts and complete the request
| Branch from: SONY_DCDPRIME_STATUS, SONY_DCDPRIME_GO, SONY_DCDPRIME_FAILEXIT, SONY_DCD_ICONEXIT, SONY_DCD_COMMANDDONE
SONY_DCDEXIT:
        MOVE.L  (IWM).w,A0                      | reload IWM base
        TST.B   0x1000(A0)                      | mtrOff: /ENBL2 off, deselect the HD20
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
        TST.B   0x1A00(A0)                      | q6H: L6 = 1, status register selected
        TST.B   0x1C00(A0)                      | q7L: read status, HSHK in bit 7
        DBPL    D0,SONY_DCDWAITHSHK_2           | poll until HSHK low or the count is done
        BPL.B   SONY_DCDWAITHSHK_EXIT           | HSHK low -> response ready
        SUBQ.W  #0x1,MaxTime(A1)                | decrement MaxTime counter
        BMI.B   SONY_DCDWAITHSHK_EXIT           | timeout expired -> return not ready
        MOVE.W  ChkTime(A1),D0                  | D0 = ChkTime (inter-poll delay)
        BSR.W   Sony_CallWakeUp                 | delay between poll cycles
        BRA.B   SONY_DCDWAITHSHK_1              | retry polling
SONY_DCDWAITHSHK_EXIT:
        JMP     (A3)                            | return to caller (N flag = result)
| DCDSetupCmd -- set up a read or write command for D3 blocks from block
| D5: StartBlock, SeqNum, ChkTime/MaxTime, and D6/D7 = bytes to send/
| receive per block (512 data bytes one way, none the other)
SONY_DCDSETUPCMD:
        MOVE.L  D5,D0                           | D0 = starting block number
        LSL.L   #0x8,D0                         | 3-byte block number, then DriveOut = 0
        MOVE.L  D0,StartBlock(A1)               | StartBlock: store in command packet
        MOVE.B  D3,SeqNum(A1)                   | SeqNum: store block count as seq#
        MOVE.W  #0xA,ChkTime(A1)                | ChkTime = 10: check every 1 ms
        MOVE.W  #0x2710,MaxTime(A1)             | MaxTime = 10000 checks: 10 s
        MOVE.L  #0x200,D6                       | D6 = 512: data size per block
        MOVEQ.L #0x0,D7                         | D7 = 0: no tag data initially
| the Mac Plus driver cleared the flag bits only after the read/write test
        ANDI.B  #0x3F,DCDCmd(A1)                | DCDCmd: clear flag bits 6-7 first
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
        LEA.L   0x1800(A0),A3                   | A3 = q6L: write-handshake register in the write state (DCDSendPacket)
        MOVE.L  D6,BufSize(A1)                  | BufSize: set send data size
        ADD.L   D7,BufSize(A1)                  | add receive data size to total
        MOVE.B  DCDCmd(A1),D1                   | D1 = DCD command byte
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
        ADDA.W  #TagBytes,A1                    | point to DCD tag buffer area
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
        ORI.B   #0x40,DCDCmd(A1)                | set continuation bit in command
        MOVE.B  D3,SeqNum(A1)                   | SeqNum: store remaining block count
        ADDQ.L  #0x1,TagBytes+4(A1)             | next file block number in the tags (flags/block long at +$1E0)
        MOVE.W  #0x7,ChkTime(A1)                | ChkTime = 7 (tNextChk): check every 700 us
        MOVE.W  #0x2710,MaxTime(A1)             | MaxTime = 10000 checks (tNextMax): 7 s (SonyEqu.a)
SONY_SENDCMD_LOOP:
        CMPI.B  #0x3,D1                         | status command?
        BGE.B   SONY_SENDCMD_OK                 | yes -> no tag copy needed
        TST.B   D1                              | read command?
        BEQ.B   SONY_SENDCMD_OK                 | yes -> no tag copy (tags in recv)
        MOVE.L  A5,D0                           | TagBufPtr: external tag buffer?
        BEQ.B   SONY_SENDCMD_OK                 | no -> use default tags
        ADDA.W  #TagBytes,A1                    | point to DCD tag buffer area
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
        LEA.L   0x1800(A0),A3                   | A3 = q6L: data register in the read state (DCDRcvPacket)
        MOVE.B  DCDCmd(A1),D1                   | D1 = DCD command byte
        ANDI.B  #0x3F,D1                        | mask to base command (strip flags)
        BSR.W   Sony_DCDRcvPacket               | receive response packet from DCD
        BNE.W   SONY_SENDCMD_ERR                | receive error -> set error status
        MOVE.L  DCDCmd(A1),D0                   | D0 = command + response bytes
        MOVE.B  #0x30,D0                        | D0.lo = InvalidResp error code
        SUBI.B  #0x80,DCDCmd(A1)                | subtract $80: check Response = Cmd+$80
        CMP.B   DCDCmd(A1),D1                   | response matches expected?
        BNE.B   SONY_SENDCMD_ERR                | no -> invalid response error
        CMPI.B  #0x3,D1                         | status command?
        BGE.B   SONY_SENDCMD_CHKSTATUS          | yes -> skip sequence check
        MOVE.B  #0x31,D0                        | D0 = SqncNumErr error code
        CMP.B   SeqNum(A1),D3                   | sequence number matches?
        BEQ.B   SONY_SENDCMD_OK_2               | yes -> response validated
        SWAP    D0                              | pack error info into D0.hi
        MOVE.B  D3,D0                           | store expected seq# in D0.lo
        SWAP    D0                              | restore: D0.hi = {err, expected}
        ROR.L   #0x8,D0                         | rotate to pack received seq#
        MOVE.B  SeqNum(A1),D0                   | insert actual seq# received
        ROL.L   #0x8,D0                         | restore byte order
        BRA.B   SONY_SENDCMD_ERR                | sequence mismatch -> error
SONY_SENDCMD_OK_2:
        TST.B   D1                              | read command?
        BNE.B   SONY_SENDCMD_CHKSTATUS          | no -> skip tag extraction
        MOVE.L  A5,D0                           | TagBufPtr: external tag buffer?
        BEQ.B   SONY_SENDCMD_NO_2               | no -> copy to system globals
        ADDA.W  #TagBytes,A1                    | point to DCD tag buffer
        MOVE.L  (A1)+,(A5)+                     | copy 12 received tag bytes to user
        MOVE.L  (A1)+,(A5)+                     | tag bytes 5-8
        MOVE.L  (A1)+,(A5)+                     | tag bytes 9-12
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_NO_2:
        ADDA.W  #TagBytes,A1                    | point to DCD tag buffer
        MOVE.L  (A1)+,(BufTgFNum).w             | copy tag: file number
        MOVE.L  (A1)+,(BufTgFFlg).w             | copy tag: file flags
        MOVE.L  (A1)+,(BufTgDate).w             | copy tag: date
        MOVE.L  (A1)+,(BufTgHD20).w             | copy tag: HD20 extension
        MOVE.L  (A1)+,(BufTgHD20_1).w           | copy tag: HD20 extension (cont)
        MOVE.L  (SonyVars).w,A1                 | restore A1 = SonyVars
SONY_SENDCMD_CHKSTATUS:
        MOVEQ.L #0x1,D2                         | D2 = 1: nonZerStat result type
        MOVE.L  StartBlock(A1),D0               | D0 = DCD status from response
        BTST    #0x18,D0                        | opFailed bit set?
        BNE.B   SONY_SENDCMD_ERR_2              | yes -> operation failed
        CMPI.B  #0xA,StartBlock(A1)             | status = $0A (disk changed)?
        BEQ.B   SONY_SENDCMD_ERR_2              | yes -> report as error
        ADDA.L  BufSize(A1),A4                  | advance data buffer by BufSize
        ADDQ.L  #0x1,D4                         | count blocks transferred
        SUBQ.B  #0x1,D3                         | decrement blocks remaining
        BNE.W   SONY_SENDCMD_NEXT               | more blocks -> send next command
        MOVEQ.L #0x0,D0                         | noErr: all blocks transferred
SONY_SENDCMD_RET:
        ANDI    #-0x5,SR                        | clear Z: BNE = finished
        RTS                                     | return with D0 = result
SONY_SENDCMD_ERR:
        MOVEQ.L #0x2,D2                         | D2 = 2: comErr result type
        ROR.L   #0x8,D0                         | pack error code into status word
SONY_SENDCMD_ERR_2:
        MOVE.L  D0,LastStatus(A1)               | LastStatus: save DCD error status
        MOVE.B  D2,LastResult(A1)               | LastResult: save result type
        MOVEQ.L #0x1,D0                         | D0 = 1: indicate error
        BRA.B   SONY_SENDCMD_RET                | return via common exit

| -------------------------------------------------------------------------
| DCDRcvPacket -- receive a packet from the HD20 into the command area
| (+$1D6) and the data buffer (A4): wait for $AA, then groups of 8 bytes
| (7 bytes with bit 7 set plus their collected low bits), honouring the
| HD20's holdoff marker ($BF) and the SCC; check the sum (must be 0).
|   D0 (out) -- 0 or RdHsHi ($20), RdSyncTO ($21), RdGroupTO ($22),
|               RdHoffSyncTO ($24), RdHsHiTO ($25), RdChksumErr ($26)
| -------------------------------------------------------------------------
Sony_DCDRcvPacket:
        MOVE    SR,-(SP)                        | save SR
        MOVEM.L D1-D7/A1/A4-A6,-(SP)            | save all registers
        ADDA.W  #DCDCmd,A1                      | A1 -> DCD command area in SonyVars
        MOVEQ.L #0x0,D5                         | D5 = running checksum
        TST.B   0x1A00(A0)                      | q6H: L6 = 1, status register selected
        MOVEQ.L #0x20,D0                        | D0 = RdHsHi error code
        TST.B   0x1C00(A0)                      | q7L: read status, HSHK in bit 7
        BMI.W   SONY_RCVPKT_EXIT                | HSHK high -> error (should be low)
        MOVEM.L (SCCRd).w,A5-A6                 | A5 = SCCRd, A6 = SCCWr
        ADDQ.W  #0x2,A5                         | A5 = SCC channel A control
        ADDQ.W  #0x2,A6                         | A6 = SCC channel A control (write)
        ORI     #0x700,SR                       | raise IPL to 7 (disable all ints)
        TST.B   0x200(A0)                       | CA0 high: ready to receive
        TST.B   0x400(A0)                       | CA1 low
        TST.B   (A3)                            | q6L: L6 = 0, read state: (A3) reads the data register
        MOVEQ.L #0x21,D0                        | D0 = RdSyncTO error code
        MOVEQ.L #0x2,D6                         | sync timeout counter: $20000 (1987 SE: $10000)
        SWAP    D6                              | D6 = $20000
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
| Branch from: SONY_RCVPKT_GET1, SONY_RCVPKT_GET2, SONY_RCVPKT_GET3, SONY_RCVPKT_GET4, SONY_RCVPKT_GET5 (and 8 more)
SONY_RCVPKT_GROUPTO:
        MOVEQ.L #0x22,D0                        | RdGroupTO: group receive timeout
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
        TST.B   0x200(A0)                       | CA0 high again: continue
        TST.B   (A3)                            | read the data register (discard the byte)
        CLR     D0                              | D0 = $10000: sync search counter
SONY_RCVPKT_RESYNC:
        SUBQ.W  #0x1,D0                         | decrement sync timeout
        BEQ.B   SONY_RCVPKT_HOFFTO              | timeout -> holdoff sync error
        CMPI.B  #0xAA,(A3)                      | re-sync: found $AA?
        BNE.B   SONY_RCVPKT_RESYNC              | no -> keep searching
        BRA.W   SONY_RCVPKT_GROUP               | synced -> resume group receive
SONY_RCVPKT_HOFFTO:
        MOVEQ.L #0x24,D0                        | RdHoffSyncTO: holdoff re-sync timeout
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
        TST.B   0x600(A0)                       | CA1 high: end of the packet
        TST.B   0x1A00(A0)                      | q6H: L6 = 1, status register selected
        MOVEQ.L #0x25,D0                        | D0 = RdHsHiTO: assume HSHK error
        TST.B   0x1C00(A0)                      | q7L: read status, HSHK high again?
        BPL.B   SONY_RCVPKT_EXIT                | HSHK still low -> RdHsHiTO
        MOVE.B  D5,D0                           | D0 = checksum (0 if the packet is correct)
        BEQ.B   SONY_RCVPKT_EXIT                | correct -> D0 = 0
        MOVEQ.L #0x26,D0                        | RdChksumErr ($26): checksum error
| Branch from: Sony_DCDRcvPacket, SONY_RCVPKT_SYNC, SONY_RCVPKT_GROUPTO, SONY_RCVPKT_HOFFTO, SONY_RCVPKT_LAST7
SONY_RCVPKT_EXIT:
        TST.B   (A5)                            | read SCC channel A: resets the SCC register pointer
        TST.B   0x600(A0)                       | CA1 high
        TST.B   (A0)                            | CA0 low
        MOVEM.L (SP)+,D1-D7/A1/A4-A6            | restore registers
        MOVE    (SP)+,SR                        | restore SR
        TST.W   D0                              | CCR = result (restoring SR also restored the old CCR)
        RTS                                     | return (BEQ = ok)

| -------------------------------------------------------------------------
| DCDSendPacket -- send a command packet to the HD20
|   A0 (in) -- IWM base, A3 (in) -- IWM q6L (write-handshake register
|              once in the write state)
|   A1 (in) -- SonyVars; the packet starts with the command block at
|              DCDCmd (+$1D6), then data from A4
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
        ADDA.W  #DCDCmd,A1                      | A1 -> DCDCmd: command block
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
        TST.B   0x1A00(A0)                      | q6H: L6 = 1, status register selected
        MOVEQ.L #0x10,D0                        | WrtHsLw ($10): HSHK must be high before we start
        TST.B   0x1C00(A0)                      | q7L: HSHK (status bit 7)
        BPL.W   SONY_SENDPKT_EXIT               | low -> error
        TST.B   0x200(A0)                       | CA0 high: request to send
        MOVEQ.L #0x11,D0                        | WrtHSLwTO ($11)
        MOVEQ.L #0x14,D7                        | $14 <<
        SWAP    D7                              | 16 = $140000: timeout count
SONY_SENDPKT_WAITLOW:
        SUBQ.L  #0x1,D7                         | count
        BEQ.W   SONY_SENDPKT_EXIT               | timeout -> error
        TST.B   0x1C00(A0)                      | HSHK
        BMI.B   SONY_SENDPKT_WAITLOW            | still high -> wait
        TST.B   0x400(A0)                       | CA1 low
        LEA.L   0x1A00(A0),A0                   | A0 -> IWM q6H
        ORI     #0x700,SR                       | no interrupts
        MOVEQ.L #0x2,D7                         | 2 more groups from the command block,
        CMPI.B  #0x4,D4                         | for commands 0-3 (read, write, status)
        BLT.B   SONY_SENDCMD_CONT_4             | yes ->
        MOVEQ.L #-0x1,D7                        | others: everything from A4
        MOVE.L  A4,A1                           | A1 = data
SONY_SENDCMD_CONT_4:
        MOVEQ.L #0x10,D0                        | short delay loop (1987 SE: 5 times)
SONY_SENDCMD_LOOP_22:
        DBF     D0,SONY_SENDCMD_LOOP_22         | (17 times)
        MOVE.L  D6,D0                           | D0 = receive/send counts
        ADDI.L  #0x810081,D0                    | + $81 each: count + 1 with bit 7 set
        MOVE.B  #0xAA,0x400(A0)                 | q7H (A0+$400): write state, first byte $AA (sync)
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
        TST.B   -0x1A00(A0)                     | CA0 low: tell the HD20 we hold off after this group
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
| holdoff: let the SCC interrupt be serviced, then restart with $AA
SONY_SENDPKT_HOLDOFF:
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
        TST.B   0x200(A0)                       | q7L (A0+$200): write state off
        TST.B   -0x200(A0)                      | q6L (A0-$200)
        TST.B   (A0)                            | q6H (A0 = q6H): status register selected
        TST.B   -0x1800(A0)                     | CA0 high (A0-$1800 = ph0H): continue
        MOVE    #0x10,D0                        | short delay
SONY_SENDCMD_LOOP_26:
        DBF     D0,SONY_SENDCMD_LOOP_26         | (17 times)
        MOVEQ.L #-0x80,D0                       | D0 = $80 again
        ORI     #0x700,SR                       | no interrupts
        MOVE.B  #0xAA,0x400(A0)                 | q7H (A0+$400): write state again, $AA (sync)
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
        TST.B   0x600(A0)                       | CA1 high: end of the packet
        MOVEQ.L #0x13,D0                        | WrtHSHighTO ($13)
        MOVEQ.L #-0x1,D7                        | timeout count
SONY_SENDPKT_WAITHIGH:
        SUBQ.W  #0x1,D7                         | count
        BEQ.B   SONY_SENDPKT_EXIT               | timeout -> error
        TST.B   0x1C00(A0)                      | read the status: HSHK (Q7 low ends write mode)
        BPL.B   SONY_SENDPKT_WAITHIGH           | still low -> wait
        MOVEQ.L #0x0,D0                         | noErr
SONY_SENDPKT_EXIT:
        TST.B   0x600(A0)                       | CA1 high
        TST.B   (A0)                            | CA0 low
        MOVEM.L (SP)+,D1-D7/A1/A4-A6            | restore registers
        MOVE    (SP)+,SR                        | restore the interrupt level
        TST.W   D0                              | CCR = result (restoring SR also restored the old CCR)
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
        BSR.W   Sony_SetChipMode                | SetChipMode: IWM register set for the HD20 (SE: SetIWMMode)
        BSR.W   Sony_DiskSelect                 | DiskSelect: select the HD20
        TST.B   0xA00(A0)                       | CA2 high
        TST.B   0x400(A0)                       | CA1 low
        TST.B   (A0)                            | CA0 low: address 1 = dcdReset
        MOVE    #0x3E8,D0                       | tRstAssert: 1000 * 100 us = 100 ms
        BSR.W   Sony_CallWakeUp                 | WakeUp
        TST.B   0x600(A0)                       | CA1 high
        TST.B   0x800(A0)                       | CA2 low: reset line released
        MOVE    #0x4E20,D0                      | tRstSettle: 20000 * 100 us = 2 s
        BSR.W   Sony_CallWakeUp                 | WakeUp
        MOVE.W  #0x64,ChkTime(A1)               | ChkTime = tRstChk: check every 10 ms
        MOVE.W  #0x640,MaxTime(A1)              | MaxTime = tRstMax: 1600 checks = 16 s
SONY_DCDRESET_CONT:
        BSR.W   Sony_Sense                      | Sense: HD20 handshake line
        BMI.B   SONY_DCDRESET_SKIP              | HSHK high -> HD20 ready (idle)
        SUBQ.W  #0x1,MaxTime(A1)                | MaxTime: count the check
        BMI.B   SONY_DCDRESET_SKIP_2            | time is up -> error
        MOVE.W  ChkTime(A1),D0                  | ChkTime
        BSR.W   Sony_CallWakeUp                 | WakeUp
        BRA.B   SONY_DCDRESET_CONT              | check again
SONY_DCDRESET_SKIP:
        MOVEQ.L #0x0,D0                         | noErr
        JMP     (A3)                            | return
SONY_DCDRESET_SKIP_2:
        TST.B   0x1800(A0)                      | q6L: back to read mode
        MOVEQ.L #-0x1,D0                        | timeout: D0 = -1
        JMP     (A3)                            | return
| completion of the status command issued for an HD20 icon call: return
| a pointer to the icon in the HD20 status data
SONY_DCD_ICONDONE:
        BNE.B   SONY_DCD_ICONEXIT               | status command failed -> return the error
        LEA.L   DevIcon(A1),A2                  | A2 -> DevIcon (status buffer + 44)
        MOVE.L  (A1),A0                         | A0 = DCE
        MOVE.L  0x8(A0),A0                      | A0 = current request (dCtlQHead)
        MOVE.L  A2,0x1C(A0)                     | CSParam = pointer to the icon
SONY_DCD_ICONEXIT:
        BRA.W   SONY_DCDEXIT                    | complete the request (DCD exit)

| -------------------------------------------------------------------------
| HD20 icon call (csCodes 21 and 22 for drives 4-5): only for a valid,
| connected drive (checked first, new) that reports an icon (DevChIcon
| in its characteristics byte); the icon is part of the status data, so
| a status command is issued first.
| -------------------------------------------------------------------------
SONY_DCD_ICON:
        BNE.W   Sony_DiskDone                   | bad or missing drive -> return the error
SONY_DCD_ICON_CHK:
        BTST    #0x2,DriveChar(A1,D1.W)         | DriveChar bit 2 = DevChIcon: icon available?
        BEQ.W   Sony_DiskCtlErr                 | no -> controlErr
        LEA.L   SONY_DCD_ICONDONE(PC),A0        | completion routine: return the icon pointer
        MOVE.L  A0,StsRtnAddr(A1)               | StsRtnAddr

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
        MOVEA.L (IWM).w,A0                      | A0 = IWM base
        TST.B   0x1000(A0)                      | IWM motor off: drop /ENBL before selecting
        TST.B   isSWIM(A1)                      | isSWIM: SWIM installed?
        BPL.B   SONY_DCD_COMMAND_1              | no -> IWM set-up not needed
        BSR.W   Sony_SetChipMode                | SetChipMode: select the register set (IWM unless mfmDisk, here the low byte of DriveType, is set)
SONY_DCD_COMMAND_1:
        BSR.W   Sony_DiskSelect                 | DiskSelect: select the HD20
        TST.B   (A0)                            | CA0 low
        TST.B   0x800(A0)                       | CA2 low
        CLR.B   DCDFlags(A1)                    | DCDFlags = 0: no retry or reset yet
        MOVE.B  D3,DCDCmd(A1)                   | DCDCmd = command
SONY_DCD_COMMAND_RETRY:
        MOVE.L  (SonyVars).w,A1                 | A1 = SonyVars
        ANDI.B  #0x3F,DCDCmd(A1)                | DCDCmd: clear bits 6-7
        SUBA.L  A4,A4                           | A4 = 0: no data buffer
        SUBA.L  A5,A5                           | A5 = 0: no tag buffer
        MOVEQ.L #0x1,D3                         | one block
        MOVEQ.L #0x0,D6                         | nothing to send
        MOVEQ.L #0x0,D7                         | nothing to receive
        MOVE.W  #0x64,ChkTime(A1)               | ChkTime = tFVChk: check every 10 ms
        MOVE.W  #0x4650,MaxTime(A1)             | MaxTime = tFVMax: 18000 checks = 3 minutes
        CMPI.B  #0x3,DCDCmd(A1)                 | status command?
        BNE.B   SONY_DCD_COMMAND_SEND           | no ->
        MOVE.L  #0x14C,D7                       | receive 332 bytes of status
        MOVE.W  #0xA,ChkTime(A1)                | ChkTime = tStsChk: check every 1 ms
        MOVE.W  #0x2710,MaxTime(A1)             | MaxTime = tStsMax: 10000 checks = 10 s
        LEA.L   StsBuffer(A1),A4                | A4 -> status buffer
SONY_DCD_COMMAND_SEND:
        BSR.W   E_Sony_SendCmd                  | SendCmd: send the command
        BEQ.B   SONY_DCD_COMMAND_WAIT           | sent -> wait for the response
SONY_DCD_COMMAND_ERR:
        CMPI.B  #0x2,LastStatus(A1)             | high byte of LastStatus = 2? (LastResult = comErr would be +$1F8)
        BEQ.B   SONY_DCD_COMMAND_RESET          | yes -> reset
        BTST    #0x1E,LastStatus(A1)            | LastStatus bit 30 (bChksum): checksum error?
        BEQ.B   SONY_DCD_COMMAND_RESET          | no -> reset
        BSET    #0x1,DCDFlags(A1)               | DCDFlags bit 1 (retryonce) set before?
        BNE.B   SONY_DCD_COMMAND_RETRY          | yes -> send the command again
SONY_DCD_COMMAND_RESET:
        BSET    #0x0,DCDFlags(A1)               | DCDFlags bit 0 (resetonce) set before?
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
        ANDI.B  #0x3F,DCDCmd(A1)                | DCDCmd: clear bits 6-7
        CMPI.B  #0x3,DCDCmd(A1)                 | status command?
        BNE.W   SONY_DCDEXIT                    | no -> complete the request (DCD exit)
        MOVEA.L StsRtnAddr(A1),A0               | A0 = StsRtnAddr
        TST     D0                              | CCR = result
        JMP     (A0)                            | continue there

| -------------------------------------------------------------------------
| Jump table into the ROM tail: routines that did not fit into the
| driver's resource slot were placed in the free space at the end of the
| ROM (FDHD_ResourceTailPatchCode, $43D000); each entry here jumps to one
| entry of the tail's entry table (absolute addresses, the ROM runs at
| $400000). The JRdAddr, JRdData and JSetUpPoll vectors point to the
| first three entries.
| -------------------------------------------------------------------------
SONY_TAIL_RDADDR:
        JMP     (TAILENT_RDADDR-BASEOFROM+0x400000).l | RdAddr vector target (jtRdAddr)
SONY_TAIL_RDDATA:
        JMP     (TAILENT_RDDATA-BASEOFROM+0x400000).l | RdData vector target (jtRdData)
SONY_TAIL_SETUPPOLL:
        JMP     (TAILENT_SETUPPOLL-BASEOFROM+0x400000).l | SetUpPoll vector target (jtSetUpPoll)
SONY_TAIL_DRIVEICON:
        JMP     (TAILENT_DRIVEICON-BASEOFROM+0x400000).l | csCode 21 (drive icon) for floppy drives
SONY_TAIL_MEDIAICON:
        JMP     (TAILENT_MEDIAICON-BASEOFROM+0x400000).l | csCode 22 (media icon) for floppy drives
SONY_TAIL_DRVINFO:
        JMP     (TAILENT_DRVINFO-BASEOFROM+0x400000).l | csCode 23 (drive info)
SONY_TAIL_CTLFORMAT:
        JMP     (TAILENT_CTLFORMAT-BASEOFROM+0x400000).l | CtlFormat: format (csCode 6)
SONY_TAIL_CTLVERIFY:
        JMP     (TAILENT_CTLVERIFY-BASEOFROM+0x400000).l | CtlVerify: verify (csCode 5)
SONY_TAIL_RDADDRSETUP:
        JMP     (TAILENT_RDADDRSETUP-BASEOFROM+0x400000).l | RdAddrSetup: set up polling, select the head, RdAddr
SONY_TAIL_READDATA:
        JMP     (TAILENT_READDATA-BASEOFROM+0x400000).l | RdData entry (GCR via JRdData, MFM: mRdData)
SONY_TAIL_TOEMPTYPD:
        JMP     (TAILENT_TOEMPTYPD-BASEOFROM+0x400000).l | toEmptyPD: EmptyPD keeping D0 (in DskErr)
SONY_TAIL_E_SETUPPOLL:
        JMP     (TAILENT_E_SETUPPOLL-BASEOFROM+0x400000).l | SetUpPoll entry (through JSetUpPoll)
SONY_TAIL_SETDRVTBL:
        JMP     (TAILENT_SETDRVTBL-BASEOFROM+0x400000).l | SetDrvTbl: store the icon table pointer (DiskOpen)
| initials (SWC, GGD and LAK sign Apple's Sony driver history notes:
| Steve Christensen, Gary Davidian, Larry Kenyon) and unused space up to
| the driver entry table
SONY_INITIALS:
        .ascii  "SWC GGD LAK JSP "              | initials
        .fill   20,1,0                          | unused

| -------------------------------------------------------------------------
| Driver entry table for the code in the ROM tail: the tail calls driver
| routines through its own jump table (TAIL_DRV_*, absolute JMPs to the
| entries here), so neither side depends on the other's routine
| addresses. SONY_DRVENT_DISKDONE is jumped to directly from the tail.
| -------------------------------------------------------------------------
SONY_DRVENT_ADRDISK:
        BRA.W   Sony_AdrDisk                    | AdrDisk
SONY_DRVENT_GETDRV1:
        BRA.W   Sony_GetDrv1                    | GetDrv1
SONY_DRVENT_MRDADDR:
        BRA.W   Sony_mRdAddr                    | mRdAddr
SONY_DRVENT_DSKRTN:
        BRA.W   SONY_DSKRTN                     | DskRtn: continue at DskRtnAdr
SONY_DRVENT_MRDDATA:
        BRA.W   Sony_mRdData                    | mRdData
SONY_DRVENT_SETCHIPMODE:
        BRA.W   Sony_SetChipMode                | SetChipMode
SONY_DRVENT_DISKSELECT:
        BRA.W   Sony_DiskSelect                 | DiskSelect
SONY_DRVENT_ADRANDSENSE:
        BRA.W   Sony_AdrAndSense                | AdrAndSense
SONY_DRVENT_MFMTTRACK:
        BRA.W   Sony_mFmtTrack                  | mFmtTrack
SONY_DRVENT_DSKRWOFF:
        BRA.W   SONY_DSKRWOFF                   | DskRWOff: power down with delay, complete the request
SONY_DRVENT_MVERTRACK:
        BRA.W   Sony_mVerTrack                  | mVerTrack
SONY_DRVENT_EMPTYPD:
        BRA.W   Sony_EmptyPD                    | EmptyPD
SONY_DRVENT_SEEK:
        BRA.W   E_Sony_Seek                     | Seek
SONY_DRVENT_RWPOWERUP:
        BRA.W   Sony_RWPowerUp                  | RWPowerUp
SONY_DRVENT_DISKDONE:
        BRA.W   Sony_DiskDone                   | DiskDone
SONY_DRVENT_GETFREQ1:
        BRA.W   SONY_GETFREQ1                   | GetFreq1: measure the speed (ReSeek/SpdSeek)
| unused space to the end of the resource
SONY_DRVPAD:
        .fill   16,1,0                          | unused, up to the end of the resource slot

.endif

