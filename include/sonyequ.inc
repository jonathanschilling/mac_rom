| Sony Disk Driver Equates
| Source: MPW 1.0 SonyEqu.a, Apple Computer Inc. 1984-1986


| File: SonyEqu.a
|
| Version 1.0
|
| Copyright Apple Computer, Inc. 1984, 1985, 1986
| All Rights Reserved
|


| --------------------------------------------------------------------
|
| The following information was formerly in "private" files that were
| not released to the general developer community.
|
| The information in this file is not needed for normal application
| development. These equates and macros were necessary for development
| of the Macintosh ToolBox and Operating System, and are likely to be
| dependent on their current implementation. Use of any information
| in this file is likely to cause your software to fail on future
| versions of Macintosh system software or hardware.
|
| Apple Developer Support will not support any use of the following
| information.
|
| In order to prevent any "accidental" use of this information, it has
| been disabled using the conditional-assembly variable defined below.
| If you change this to a non-zero value, you're on your own.

.equ SonyNonPortable, 0



| SonyVars Data Structure (offsets):
| (1) Driver local vars.
| (2) Drive-specific vars.
| (3) More driver local vars.
| (4) Direct-connect driver locals.
|
| Drive Constants:
| (1) Floppy drive constants (tuneable).
| (2) Floppy drive sense/control constants.
| (3) Floppy drive formatting constants.
| (4) Direct-connect drive constants.
|
| Driver Constants:
| (1) Driver Control codes.
|
| Driver Vectors:
| (1) Location of disk routine vectors.
|
| _______________________________________________________________________

| _______________________________________;
| ;
| SonyVars Data Structure (offsets):	;
| _______________________________________;

| _______________________________________;
|
| (1) Driver local vars.				; * = known to be used in a copy-
.equ DiskUnitPtr, 0                             | pointer to device control entry
.equ DiskQVE, DiskUnitPtr+4                     | disk VBL task control block
.equ Drive, DiskQVE+14                          | * 0001 = int drive, 0002 = ext drive
.equ Wait, Drive+2                              | extra wait time for speed changes

.equ SideTrack, Wait+2                          | destination side/track
.equ OneToOne, SideTrack+2                      | open up rupts flg (no longer used)
.equ Active, OneToOne+1                         | * non-zero when driver is active
.equ TimeOut, Active+1                          | * power time out

.equ DiskBuffer, TimeOut+2                      | pointer to track data buffer
.equ FirstSect, DiskBuffer+4                    | low sector number needed on a track
.equ SectMap, FirstSect+2                       | bit map of sectors needed on a track
.equ FirstFSeq, SectMap+4                       | first file seq # for current r/w request
.equ FBlksDone, FirstFSeq+2                     | file blocks done previous to this track

.equ ReadErrInit, FBlksDone+2                   | init value, read error countdown cntr
.equ ReadErrCnt, ReadErrInit+1                  | read error countdown cntr
.equ RecalInit, ReadErrCnt+1                    | init value, recal count
.equ RecalCnt, RecalInit+1                      | recal count
.equ WrgSectInit, RecalCnt+1                    | init value, wrong sector countdown cnt
.equ WrgSectCnt, WrgSectInit+1                  | wrong sector countdown cnt
.equ BadSpdInit, WrgSectCnt+1                   | init value, bad speed
.equ BadSpdCnt, BadSpdInit+1                    | bad speed countdown value

.equ Command, BadSpdCnt+1                       | I/O command

.equ HeadSettle, Command+2                      | disk head settle time (@100usec)
.equ SpdChgTime, HeadSettle+2                   | motor speed change time (@100usec)
.equ PwrOnTime, SpdChgTime+2                    | * power-on wait time (@100usec)
.equ PwrOffTime, PwrOnTime+2                    | * power down time (@1/2sec)
.equ SeekTime, PwrOffTime+2                     | seek wait time (@100usec)
.equ SectTime, SeekTime+2                       | * sector time (@100usec)
.equ DskVBLTime, SectTime+2                     | VBL task time (@16ms)
.equ EjectTime, DskVBLTime+2                    | Eject time (@100usec)
.equ CkDelta, EjectTime+2                       | delta time before speed recheck
.equ EjectWait, CkDelta+4                       | VBL times after eject to ignore DIP

| Format/Verify code reuses some of these fields as follows:

.equ GapSync, SectMap                           | (2) start with 7 groups of intersector sync
.equ TwoSided, Command                          | (1) set non-zero for 2-sided format
.equ SectSave, FirstSect                        | (2) SectMpSave must follow
.equ SectMapSave, SectMap                       | (8) uses SectMap, FirstFSeq, FBlksDone
.equ SectCnt, FirstSect                         | (2) loop counter . . .

| _______________________________________;
|
| (2) Drive-specific vars.

.equ DrvLclLth, 66
.equ Drive1, EjectWait+2                        | * internal drive variables
.equ Drive2, Drive1+DrvLclLth                   | * external drive variables

.equ Track, 0                                   | current track location (used for spd)
.equ WriteProt, 2                               | * bit7=1=write-protected
.equ DiskInPlace, 3                             | * $FC-$FF= just ejected,
.equ Installed, 4                               | * 0=don't know, 1=inst., $FF=not inst.
.equ Sides, 5                                   | * bit7=0=1 sided
.equ DQEl, 6                                    | drive queue element for this drive
.equ DriveQLink, 6
.equ DriveQVers, 10
.equ DriveSize, 18                              | drive block size (DCD only!)
.equ TwoSideFmt, 18                             | * non-zero if 2-sided format
.equ NewIntf, 19                                | $FF if new interface, $00 for old
.equ DriveErrs, 20                              | drive soft errs

.equ DriveS1, 20                                | drive block size (high word)
.equ DriveType, 22                              | old OffSpeed (no longer supported)
.equ DriveManf, 24
.equ DriveChar, 26
.equ DriveMisc, 27

.equ SpdAdjCnt, 24                              | speed adjust count this drive
.equ TrkSpeedTbl, 26                            | 5-entry track speed table

.equ TSTblCode, 0                               | first is speed code
.equ TSTblDelta, 2                              | 2% speed code delta
.equ TSTblTicks, 4                              | longword last time checked tick cnt
.equ TrkSTEnd, 66                               | end of drive vars

| _______________________________________;
|
| (3) More driver local vars.

.equ WakeTimeCnt, Drive2+DrvLclLth              | WakeUp remainder count
.equ SaveRegs, WakeTimeCnt+2                    | * wakeup routine saves D3-D7,A3-A6 here

.equ TagBufPtr, SaveRegs+36                     | if non-zero, pointer to separate
.equ TagBufOS, TagBufPtr+4                      | temp offset into buffer
.equ DiskErrs, TagBufOS+2                       | global soft errors
.equ PassThru, DiskErrs+2                       | 0 if pass thru on external port
.equ SonyExtra, PassThru+1                      | extra byte
.equ CurSector, SonyExtra+1                     | current sector being read/written

.equ TCRdEnable, CurSector+2                    | (byte) set non-zero to activate reads into cache
.equ TCInstalled, TCRdEnable+1                  | (byte) non-zero when caching is installed and on
.equ TCDrive, TCInstalled+1                     | (word) drive number of cache blks (zero to inval)
.equ TCSideTrack, TCDrive+2                     | (word) side/track of cache blocks
.equ TCSectMap, TCSideTrack+2                   | (long) bitmap of sectors currently cached
.equ TCBuffer, TCSectMap+4                      | (long) pointer to track cache buffer (512+12)*12
.equ TCNumCached, TCBuffer+4                    | (word) number read into cache
.equ TCNumUsed, TCNumCached+2                   | (word actual number used

.equ LastDrive, TCNumUsed+2                     | (word) set at CkDrvNum to previous value of Drive
.equ TimeOutDrive, LastDrive+4                  | (word) set at PowerDown to value of Drive

.equ TimeQEl, TimeOutDrive+2                    | a time queue element
.equ NextGZProc, TimeQEl+tmQSize                | (long) saved old GZ proc

.equ SonyVarEnd, NextGZProc+4                   | end of sony vars excluding DCD

| _______________________________________;
|
| (4) Direct-connect driver locals.

.equ TagSize, 20                                | 20 bytes tags/block

.equ DCDLclLth, 28                              | (use fields through DriveMisc)
.equ Drive3, SonyVarEnd                         | first DCD
.equ Drive4, Drive3+DCDLclLth                   | second DCD
.equ Drive5, Drive4+DCDLclLth                   | third DCD
.equ Drive6, Drive5+DCDLclLth                   | fourth DCD

.equ StsRtnAddr, Drive6+DCDLclLth               | DCD status call return address

.equ DCDCmd, StsRtnAddr+4                       | command byte to DCD
.equ Response, DCDCmd                           | response byte (command+$80)
.equ SeqNum, Response+1                         | mb sequence number (sys commands only)
.equ Status, SeqNum+1                           | returned status bytes
.equ StartBlock, Status                         | starting block # (in commands)
.equ DriveOut, StartBlock+3                     | we send drive number in this field
.equ DriveIn, Status+2                          | low 6 bits
.equ TagBytes, Status+4                         | tag bytes get stuffed here temporarily
.equ DevType, TagBytes                          | first 20 bytes of status are written
.equ DevManufctr, DevType+2                     |  in the 20-byte tag buffer
.equ DevChar, DevManufctr+2
.equ DevBlks, DevChar                           | low 3 bytes of this longword
.equ DevSpares, DevChar+4
.equ DevBadBlks, DevSpares+2
.equ DevMisc, DevBadBlks+2                      | 8 bytes misc
.equ BufSize, TagBytes+TagSize                  | number of bytes/block
.equ LastStatus, BufSize+4                      | last status returned
.equ LastResult, LastStatus+4                   | error type
.equ DCDFlags, LastResult+1                     | flag of whether we've done a reset
.equ ChkTime, DCDFlags+1                        | 100usec check ready count
.equ MaxTime, ChkTime+2                         | maximum number of checks
.equ StsBuffer, MaxTime+2                       | 512 bytes of status
.equ DevReserve, StsBuffer
.equ DevIcon, DevReserve+44
.equ DevFiller, DevIcon+256                     | 32 bytes for optional name

.equ DiskVarLth, DevFiller+32

| StsBufSize = DiskVarLth - StsBuffer (cannot compute at assembly time)


| device characteristics byte:

.equ DevChEject, 4                              | ejectable if 1
.equ DevChWP, 3                                 | write protected if 1
.equ DevChIcon, 2                               | icon available if 1


| _______________________________________;
| ;
| Drive Constants:				;
| _______________________________________;


.equ DQSides, -1                                | Bit 7 of this byte: 0=single-sided Sony, 1=double sided
.equ DQInstall, -2                              | 0=unknown, 1=installed, FF=no disk
.equ DQDIP, -3                                  | $FC-$FF = disk just ejected,
.equ DQWrPrt, -4                                | Bit 7 of this byte: 1=disk is write protected.

| _______________________________________;
|
| (1) Floppy drive constants (tuneable).

.equ KSeekTime, 120                             | 12 ms trk-to-trk
.equ KHdSetTime, 300                            | 30 ms head settle time
.equ KEjectTime, 7500                           | .75 seconds eject time
.equ KEjectWait, -4                             | - number of VBL calls after eject before dip check
.equ KSectTime, 100                             | minimum sector time in 100 us increments (10 ms)
.equ KPowerOn, 4000                             | read/write powerup time in 100 us increments
.equ KRWPOff, 5                                 | read/write power off time (in 1/2 seconds)
.equ KDskVBLTime, 30                            | happens every 1/2 second
.equ KSpdChgTime, 1500                          | speed change wait time = 150ms
.equ KCkDelta, 14400                            | speed check delta time (in 1/60 sec) (4 min)

| _______________________________________;
|
| (2) Floppy drive sense/control constants.
| (ca1-ca0-sel-ca2).

.equ DirLAdr, 0                                 | dirtn low
.equ DirHAdr, 1
.equ RdDtaAdr, 1                                | side 0 read data
.equ RdDta1Adr, 3                               | side 1 read data
.equ StepLAdr, 4                                | step low and step sense address
.equ StepHAdr, 5
.equ MtrOnAdr, 8
.equ MtrOffAdr, 9
.equ EjectLAdr, 12
.equ EjectHAdr, 13

.equ DIPAdr, 2                                  | disk in place sense address
.equ WrProtAdr, 6                               | write protect sense address
.equ SidesAdr, 9                                | sense for number of sides
.equ Tk0Adr, 10                                 | track 0 sense address
.equ ReadyAdr, 11                               | /Ready sense address
.equ DrvExstAdr, 13                             | sense=0 when a drive is connected
.equ TachAdr, 14                                | tach feedback sense address
.equ NewIntfAdr, 15                             | implements ready handshake if 1

| _______________________________________;
|
| (3) Floppy drive formatting constants.

.equ FmtByte, 0x02                              | 2-1 interleave, single-sided
.equ Fmt2Byte, 0x22                             | 2-1 interleave, double-sided

.equ MustFindCt, 1500
.equ minSync, 4                                 | min number of inter-sector sync groups

| _______________________________________;
|
| (4) Direct-connect drive constants.

| This variable has been renamed SONYRetry and placed in Privates
| RetryCount  EQU	5				; Number of HardReset/retries allowed

.equ BlkSize, 512                               | 512 bytes data/block
.equ SyncByte, 0xAA                             | Sync byte for start of transmission

.equ noError, 0                                 | resultTypes
.equ nonZerStat, 1
.equ comErr, 2

| New HD20 error codes

.equ WrtHsLw, 0x10                              | HSHK low before starting
.equ WrtHSLwTO, 0x11                            | Time out waiting for HSHK to go low
.equ WrtHSHighTO, 0x13                          | Time out waiting for HSHK to go high
.equ RdHsHi, 0x20                               | HSHK high before starting
.equ RdSyncTO, 0x21                             | Time out waiting for sync ($AA) bye
.equ RdGroupTO, 0x22                            | Time out waiting for group
.equ RdHoffSyncTO, 0x24                         | Time out waiting for sync after holdoff
.equ RdHsHiTO, 0x25                             | Time out waiting for HSHK high
.equ RdChksumErr, 0x26                          | Checksum error on response packet
.equ InvalidResp, 0x30                          | First byte in response packet was wrong
.equ SqncNumErr, 0x31                           | Sequence number in response packet was wrong
.equ DNumberErr, 0x32                           | Drive number in response packet was wrong
.equ NoResp, 0x40                               | No response packet ever received

| LastStatus

.equ opFailed, 24                               | bit to test for operation failed
.equ bChksum, 30                                | bit number for checksum error

| DCDFlags

.equ resetonce, 0
.equ retryonce, 1

.equ maxTries, 4                                | max # times to try command
.equ tSeekChk, 10                               | check during a seek every 1 ms
.equ tSeekMax, 10000                            | max time for seek = 10 secs
.equ tStsChk, 10                                | check during a status every 1 ms
.equ tStsMax, 10000                             | max time for status = 10 secs
.equ tQuickTime, 100
.equ tNextChk, 7                                | check for next block after 700 usec
.equ tNextMax, 10000                            | max time for next block = 7 secs
.equ tFVChk, 100                                | check during fmt/vfy every 10 ms
.equ tFVMax, 18000                              | max time for fmt/vfy = 3 minutes
.equ tRstAssert, 1000                           | assert reset for 100 msec
.equ tRstSettle, 20000                          | 2 sec wait for busy to settle
.equ tRstChk, 100                               | check during reset every 10 ms
.equ tRstMax, 1600                              | max time for reset = 16 seconds

| DCD sense/cntl addr (ca1-ca0-sel-ca2)

.equ dcdExist, 5                                | /Exist (/Sides=/DrvIn=1 also)
.equ dcdReset, 1                                | for 1ms resets DCD controller

| _______________________________________;
| ;
| Driver Constants: 			;
| _______________________________________;

| _______________________________________;
|
| (1) Driver Control codes.

.equ verifyCC, 5                                | 'verify' control code
.equ formatCC, 6                                | 'format' control code
.equ tagBufCC, 8                                | 'set tag buffer' control code
.equ TCacheCC, 9                                | 'track cache' control
.equ iconIDCC, 20                               | 'get icon id' control code
.equ iconCC, 21                                 | 'get icon' control code

| _______________________________________;
| ;
| Driver Vectors:				;
| _______________________________________;

| _______________________________________;
|
| (1) Location of disk routine vectors.

.equ JFigTrkSpd, DiskVars
.equ JDiskPrime, JFigTrkSpd+4
.equ JRdAddr, JDiskPrime+4
.equ JRdData, JRdAddr+4

.equ JWrData, JRdData+4
.equ JSeek, JWrData+4
.equ JSetUpPoll, JSeek+4
.equ JRecal, JSetUpPoll+4

.equ JControl, JRecal+4
.equ JWakeUp, JControl+4
.equ JReSeek, JWakeUp+4
.equ JMakeSpdTbl, JReSeek+4

.equ JAdrDisk, JMakeSpdTbl+4
.equ JSetSpeed, JAdrDisk+4
.equ NiblTbl, JSetSpeed+4




