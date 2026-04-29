| System Equates - I/O parameter blocks, queue structures, low-memory globals
| Source: MPW 1.0 SysEqu.a, Apple Computer Inc. 1984-1986
| Note: only non-conflicting equates included (lowmem.inc has priority)


| File: SysEqu.a
|
| Version 2.0
|
| Copyright Apple Computer, Inc. 1984, 1985, 1986
| All Rights Reserved
|

| System Equates -- This file defines the low-level equates for the
| Macintosh software.  This is divided into two pieces for
| assembly space and speed considerations.  The wholeSystem flag is used
| to include the less common equates which realizes a complete set.  The
| comments marked with ";+" denote categories or managers.	Record
| stuctures may have additional private equates which are defined by and
| reserved for use by Apple Computer, Inc.

.equ wholeSystem, 1



| + ROM Equates

.equ ROMMapHndl, 0xB06                          | (long) handle of ROM resource map

| + Screen Equates

.equ ScrHRes, 0x104                             | screen horizontal dots/inch [word]


| Mouse/Keyboard


| + Parameter RAM (a twenty byte copy of the real parameter ram).


| Serial port use type

.equ useFree, 0                                 | Use undefined
.equ useATalk, 1                                | AppleTalk
.equ useAsync, 2                                | Async
.equ useExtClk, 3                               | externally clocked

| Unpacked, user versions of parameter ram



| + System Clocks



| + Cursor

.equ iBeamCursor, 1                             | text selection cursor
.equ crossCursor, 2                             | for structured selection
.equ plusCursor, 3                              | for drawing graphics
.equ watchCursor, 4                             | for indicating a long delay


| result codes for Relstring call

.equ sortsBefore, -1                            | str1 < str2
.equ sortsEqual, 0                              | str1 = str2
.equ sortsAfter, 1                              | str1 > str2

| + Queue Package

.equ qInUse, 7                                  | queue-in-use flag bit

| Header Record

.equ qHeadSize, 0xA                             | queue header size
.equ qFlags, 0                                  | miscellaneous flags [word]
.equ qHead, 2                                   | first element in queue [pointer]
.equ qTail, 6                                   | last element in queue [pointer]

| General Purpose Queue Element Definition

.equ qLink, 0                                   | link to next queue element [pointer]
.equ qType, 4                                   | queue element type [word]


| + Event Manager

.equ evType, 4                                  | event queue element is type 4

| Event Type Numbers (in EvtNum)

.equ nullEvt, 0                                 | event 0 is the null event
.equ mButDwnEvt, 1                              | mouse button down is event 1
.equ mButUpEvt, 2                               | mouse button up is event 2
.equ keyDwnEvt, 3                               | key down is event 3
.equ keyUpEvt, 4                                | key up is event 4
.equ autoKeyEvt, 5                              | auto-repeated key is event 5
.equ updatEvt, 6                                | update event
.equ diskInsertEvt, 7                           | disk-inserted event
.equ activateEvt, 8                             | activate/deactive event
.equ netWorkEvt, 0xA                            | network event
.equ ioDrvrEvt, 0xB                             | driver-defined event
.equ app1Evt, 0xC                               | application defined events
.equ app2Evt, 0xD
.equ app3Evt, 0xE
.equ app4Evt, 0xF

| Modifier bits in event record

.equ activeFlag, 0x0                            | activate?
.equ btnState, 0x7                              | state of button?
.equ cmdKey, 0x8                                | command key down?
.equ shiftKey, 0x9                              | shift key down?
.equ alphaLock, 0xA                             | alpha lock down?
.equ optionKey, 0xB                             | option key down?

| Event Record Definition

.equ evtNum, 0                                  | event code [word]
.equ evtMessage, 2                              | event message [long]
.equ evtTicks, 6                                | ticks since startup [long]
.equ evtMouse, 0xA                              | mouse location [long]
.equ evtMeta, 0xE                               | state of modifier keys [byte]
.equ evtMBut, 0xF                               | state of mouse button [byte]
.equ evtBlkSize, 0x10                           | size in bytes of the event record

.equ MonkeyLives, 0x100                         | monkey lives if >= 0 [word]


| + Memory Manager

| Master pointer bits for handles - USE _HLock, _HPurge, etc. for portability

.equ lock, 7                                    | lock bit in a master pointer
.equ purge, 6                                   | bit for purgeable/unpurgeable
.equ resource, 5                                | bit to flag a resource handle


.equ StkLowPt, 0x110                            | Lowest stack as measured in VBL task [pointer]
.equ HiHeapMark, 0xBAE                          | (long) highest address used by a zone below sp<01Nov85 JTC>


.equ maxSize, 0x800000                          | outrageously large memory mgr request
.equ dfltStackSize, 0x00002000                  | 8K size for stack
.equ mnStackSize, 0x00000400                    | 1K minimum size for stack

| _InitZone argument table.

.equ startPtr, 0                                | Start address for zone [pointer]
.equ limitPtr, 4                                | Limit address for zone [pointer]
.equ cMoreMasters, 8                            | Number of masters to allocate at time [word]
.equ pGrowZone, 10                              | growZone procedure [pointer]

| Control/Status Call Codes

.equ killCode, 1                                | KillIO code
.equ drvStsCode, 8                              | status call code for drive status
.equ ejectCode, 7                               | control call eject code
.equ tgBuffCode, 8                              | set tag buffer code

| Driver flags, (Bit definitions for DCtlFlags byte)

.equ dReadEnable, 0                             | enabled for read operations
.equ dWritEnable, 1                             | enabled for writing
.equ dCtlEnable, 2                              | enabled for control operations
.equ dStatEnable, 3                             | enabled for status operations
.equ dNeedGoodBye, 4                            | needs a "goodbye kiss"
.equ dNeedTime, 5                               | needs "main thread" time
.equ dNeedLock, 6                               | needs to be accessed at interrupt level

| Run-Time flags, (Bit definitions for DCtlFlags+1 byte)

.equ dOpened, 5                                 | bit to mark driver 'Open'
.equ dRAMBased, 6                               | 1=RAM-based Driver, 0=ROM-based
.equ drvrActive, 7                              | bit to mark the driver active

| Drive queue element offsets

.equ dQDrive, 0x6                               | drive number [word]
.equ dQRefNum, 0x8                              | driver refnum [word]
.equ dQFSID, 0xA                                | file system handling this drive [word]
.equ dQDrvSz, 0xC                               | number of blocks this drive [word]
.equ dQDrvSz2, 0xE                              | if qType = 1, high word of drive size

| Queue Element Type Definitions

.equ ioQType, 2                                 | I/O queue element is type 2
.equ drvQType, 3                                | timer queue element is type 3
.equ fsQType, 5                                 | File System VCB element

| Device Control Entry Definition

.equ dCtlEntrySize, 0x28                        | length of a DCE [40 bytes]
.equ dCtlDriver, 0                              | driver [handle]
.equ dCtlFlags, 4                               | flags [word]
.equ dCtlQueue, 6                               | queue header
.equ dCtlQHead, 8                               | queue first-element [pointer]
.equ dCtlQTail, 0xC                             | queue last-element [pointer]
.equ dCtlPosition, 0x10                         | position [long]
.equ dCtlStorage, 0x14                          | driver's private storage [handle]
.equ dCtlRefNum, 0x18                           | refNum of this driver [word]
.equ dCtlCurTicks, 0x1A                         | counter for timing systemTask calls [long]
.equ dCtlWindow, 0x1E                           | driver's window (if any) [pointer]
.equ dCtlDelay, 0x22                            | number of ticks between sysTask calls [word]
.equ dCtlEMask, 0x24                            | desk accessory event mask [word]
.equ dCtlMenu, 0x26                             | menu ID associated with driver [word]

| Driver Globals

.equ UnitNtryCnt, 0x1D2                         | count of entries in unit table [word]


| Chooser

.equ chooserID, 1                               | caller value for the chooser

| + I/O System

| File positioning modes for ioPosMode field of I/O record

.equ fsAtMark, 0                                | at current position of mark
.equ fsFromStart, 1                             | offset relative to beginning of file
.equ fsFromLEOF, 2                              | offset relative to logical end-of-file
.equ fsFromMark, 3                              | offset relative to current mark
.equ rdVerify, 0x40                             | read verify mode

| Permission values for ioPermssn field of I/O record

.equ fsCurPerm, 0                               | whatever is currently allowed
.equ fsRdPerm, 1                                | request to read only
.equ fsWrPerm, 2                                | request to write only
.equ fsRdWrPerm, 3                              | request to read and write
.equ fsRdWrShPerm, 4                            | request for shared read and write

| I/O record (general fields with trap-specific ones listed below)

.equ ioQElSize, 0x32                            | length of I/O parameter block [50 bytes]

.equ ioLink, 0x0                                | queue link in header [pointer]
.equ ioType, 0x4                                | type for safety check [byte]
.equ ioTrap, 0x6                                | the trap [word]
.equ ioCmdAddr, 0x8                             | address to dispatch to [pointer]

.equ ioCompletion, 0xC                          | completion routine [pointer]
.equ ioResult, 0x10                             | I/O result code [word]
.equ ioFileName, 0x12                           | file name pointer [pointer]
.equ ioVRefNum, 0x16                            | volume refnum [word]
.equ ioDrvNum, 0x16                             | drive number [word]
.equ ioRefNum, 0x18                             | file reference number [word]

.equ ioFileType, 0x1A                           | specified along with FileName [byte]

| specific fields for _Read, _Write

.equ ioBuffer, 0x20                             | data buffer [pointer]
.equ ioByteCount, 0x24                          | requested byte count [long]
.equ ioNumDone, 0x28                            | actual byte count completed [long]

.equ ioPosMode, 0x2C                            | initial file positioning mode/eol char [word]
.equ ioPosOffset, 0x2E                          | file position offset [long]

| specific fields for _Allocate

.equ ioReqCount, 0x24                           | requested new size [long]
.equ ioActCount, 0x28                           | actual byte count allocated [long]

| specific fields for _Open

.equ ioPermssn, 0x1B                            | permissions [byte]
.equ ioOwnBuf, 0x1C                             | "private" 522-byte buffer [pointer]

| specific fields for _ReName

.equ ioNewName, 0x1C                            | new name pointer [pointer]

| specific fields for  _GetFileInfo, _SetFileInfo

.equ ioFQElSize, 0x50                           | File command parameter length [80 bytes]

.equ ioFDirIndex, 0x1C                          | directory index of file [word]
.equ ioFlAttrib, 0x1E                           | in-use bit=7, lock bit=0 [byte]
.equ ioFFlType, 0x1F                            | file type [byte]
.equ ioFlUsrWds, 0x20                           | finder info [16 bytes]
.equ ioFFlNum, 0x30                             | file number [long]
.equ ioDirID, 0x30                              | directory ID

.equ ioFlStBlk, 0x34                            | start file block (0000 if none) [word]
.equ ioFlLgLen, 0x36                            | logical length (EOF) [long]
.equ ioFlPyLen, 0x3A                            | physical length in bytes [long]
.equ ioFlRStBlk, 0x3E                           | resource fork's start file block [word]
.equ ioFlRLgLen, 0x40                           | resource fork's logical length (EOF) [long]
.equ ioFlRPyLen, 0x44                           | resource fork's physical length [long]

.equ ioFlCrDat, 0x48                            | creation date & time [long]
.equ ioFlMdDat, 0x4C                            | last modification date & time [long]

| Specific fields for _GetEOF, _SetEOF

.equ ioLEOF, 0x1C                               | logical end-of-file [long]

| Specific fields for _SetFileType

.equ ioNewType, 0x1C                            | new type byte [byte]

| Specific fields for _GetVolInfo, _GetVolume, _SetVolume, _MountVol, _UnmountVol,
| _Eject.  Note that these traps have a bigger record size.

.equ ioVQElSize, 0x40                           | Volume command parameter length [64 bytes]
.equ ioVDrvNum, 0x16                            | drive or volume number [word]
.equ ioVNPtr, 0x12                              | name buffer (or zero) [pointer]
.equ ioVolIndex, 0x1C                           | volume index number [word]

.equ ioVCrDate, 0x1E                            | creation date & time [long]
.equ ioVLsBkUp, 0x22                            | last backup date & time [long]
.equ ioVAtrb, 0x26                              | Volume attributes [word]
.equ ioVNmFls, 0x28                             | # files in directory [word]
.equ ioVDirSt, 0x2A                             | start block of file dir [word]
.equ ioVBlLn, 0x2C                              | length of dir in blocks [word]
.equ ioVNmAlBlks, 0x2E                          | num blks (of alloc size) this dev [word]
.equ ioVAlBlkSiz, 0x30                          | alloc blk byte size [long]
.equ ioVClpSiz, 0x34                            | bytes to try to allocate at a time [long]
.equ ioAlBlSt, 0x38                             | starting block in block map [word]
.equ ioVNxtFNum, 0x3A                           | next free file number [long]
.equ ioVFrBlk, 0x3E                             | # free alloc blks for this vol [word]

| --- New File System Equates  ---
|
| Catalog structure equates:

.equ fsRtParID, 1                               | DirID of parent's root
.equ fsRtDirID, 2                               | Root DirID
.equ fsXTCNID, 3                                | Extent B*-Tree file ID
.equ fsCTCNID, 4                                | Catalog B*-Tree file ID
.equ fsUsrCNID, 0x10                            | First assignable user CNode ID

| Additional equates for catalog information return:

.equ ioFlBkDat, 0x50                            | File's last backup date
.equ ioFlxFndrInfo, 0x54                        | File's additional finder info bytes
.equ ioFlParID, 0x64                            | File's parent directory ID
.equ ioFlClpSiz, 0x68                           | File's clump size, in bytes

| Additional equates for directory information return:

.equ ioDirFlg, 4                                | Bit in ioFlAttrb set to indicate directory
.equ ioDrUsrWds, 0x20                           | Directory's user info bytes
.equ ioDrDirID, 0x30                            | Directory ID
.equ ioDrNmFls, 0x34                            | Number of files in a directory
.equ ioDrCrDat, 0x48                            | Directory creation date
.equ ioDrMdDat, 0x4C                            | Directory modification date
.equ ioDrBkDat, 0x50                            | Directory backup date
.equ ioDrFndrInfo, 0x54                         | Directory finder info bytes
.equ ioDrParID, 0x64                            | Directory's parent directory ID

.equ ioHFQElSiz, 0x6C                           | Size of a Hierarchical File Queue Element

| Additional equates for _TFGetVolInfo:

.equ ioVLsMod, 0x22                             | Last modification date
.equ ioVSigWord, 0x40                           | Volume signature
.equ ioVCBVBMst, 0x2A
.equ ioVNxtCNID, 0x3A
.equ ioVDrvInfo, 0x42                           | Drive number (0 if volume is offline)
.equ ioVDRefNum, 0x44                           | Driver refNum
.equ ioVFSID, 0x46                              | ID of file system handling this volume
.equ ioVBkup, 0x48                              | Last backup date (0 if never backed up)
.equ ioVSeqNum, 0x4C                            | Sequence number of this volume in volume set
.equ ioVWrCnt, 0x4E                             | Volume write count
.equ ioVFilCnt, 0x52                            | Total number of files on volume
.equ ioVDirCnt, 0x56                            | Total number of directories on the volume
.equ ioVFndrInfo, 0x5A                          | Finder information for volume

.equ ioHVQElSize, 0x7A                          | Length of Hierarchical Volume information PB

| New fields for _GetFCBInfo:

.equ ioFCBIndx, 0x1C                            | FCB index for _GetFCBInfo
.equ ioFCBFiller1, 0x1E                         | filler
.equ ioFCBFlNm, 0x20                            | File number
.equ ioFCBFlags, 0x24                           | FCB flags
.equ ioFCBStBlk, 0x26                           | File start block
.equ ioFCBEOF, 0x28                             | Logical end-of-file
.equ ioFCBPLen, 0x2C                            | Physical end-of-file
.equ ioFCBCrPs, 0x30                            | Current file position
.equ ioFCBVRefNum, 0x34                         | Volume refNum
.equ ioFCBClpSiz, 0x36                          | File clump size
.equ ioFCBParID, 0x3A                           | Parent directory ID

| New fields for _GetWDInfo:

.equ ioWDIndex, 0x1A                            | Working Directory index for _GetWDInfo
.equ ioWDProcID, 0x1C                           | WD's ProcID (long)
.equ ioWDVRefNum, 0x20                          | WD's Volume RefNum (word)
.equ ioWDDirID, 0x30                            | WD's DirID (long)

| New fields for _FSControl call:

.equ ioFSVrsn, 0x20                             | File system version

| New field for CatMove

.equ ioNewDirID, 0x24                           | destination directory for CatMove

|
| --- End of New File System Equates ---

| Specific fields for _Control, _Status

.equ csCode, 0x1A                               | control/status code [word]
.equ csParam, 0x1C                              | operation-defined parameters [22 bytes]

| FInfo (Finder Information) record layout

.equ fdType, 0x0                                | type of file [long]
.equ fdCreator, 0x4                             | file's creator [long]
.equ fdFlags, 0x8                               | flags [word]
.equ fdLocation, 0xA                            | file's location [point]
.equ fdFldr, 0xE                                | file's window [word]

| added for HFS

| FXInfo record layout

.equ fdIconID, 0x0                              | Icon ID [word]
.equ fdUnused, 0x2                              | unused but reserved [4 words]
.equ fdComment, 0xA                             | Comment ID [word]
.equ fdPutAway, 0xC                             | Home Dir ID [2 words]

| DInfo record layout

.equ frRect, 0x0                                | Folder Rect [4 words]
.equ frFlags, 0x8                               | Flags [word]
.equ frLocation, 0xA                            | Location [2 words]
.equ frView, 0xE                                | Folder view [word]

| DXInfo record layout

.equ frScroll, 0x0                              | scroll position [2 words]
.equ frOpenChain, 0x4                           | dirID chain of open folders [2 words]
.equ frUnused, 0x8                              | unused but reserved [word]
.equ frComment, 0xA                             | comment [word]
.equ frPutAway, 0xC                             | Dir ID [2 words]

| end of addition

| Masks for fdFlags field of FInfo record defined above

.equ fHasBundle, 13                             | set if file has a bundle
.equ fInvisible, 14                             | set if file's icon is invisible
.equ fTrash, -3                                 | file is in Trash window
.equ fDeskTop, -2                               | file is on desktop
.equ fDisk, 0                                   | file is in disk window

| File System Globals

.equ DrvQHdr, 0x308                             | queue header of drives in system [10 bytes]
.equ SFSaveDisk, 0x214                          | last vRefNum seen by standard file [word]
.equ CurDirStore, 46+0x36A                      | save dir across calls to Standard File [long]
.equ ROMDoEject, 0x1E                           | add this value to the value in ROMBase for DoEject utility


| + Date-Time record (for use with _Secs2Date, and _Date2Secs)


.equ dtYear, 0x0                                | year (1904..) [word]
.equ dtMonth, 0x2                               | month (1..12) [word]
.equ dtDay, 0x4                                 | day (1..31) [word]
.equ dtHour, 0x6                                | hour (0..23) [word]
.equ dtMinute, 0x8                              | minute (0..59) [word]
.equ dtSecond, 0xA                              | second (0..59) [word]
.equ dtDayOfWeek, 0xC                           | day of week, sunday..saturday (1..7) [word]


| + Miscellaneous stuff





| + Scratch Areas


.equ scratch20, 0x1E4                           | scratch [20 bytes]


| + Scrap Manager


.equ ScrapCount, 0x968                          | validation byte [word]


| + Desk Accessories


| Message Definitions (in CSCode of control call)

.equ accEvent, 0x40                             | event message from SystemEvent
.equ accRun, 0x41                               | run message from SystemTask
.equ accCursor, 0x42                            | cursor message from SystemTask
.equ accMenu, 0x43                              | menu message from SystemMenu
.equ accUndo, 0x44                              | undo message from SystemEdit
.equ accCut, 0x46                               | cut message from SystemEdit
.equ accCopy, 0x47                              | copy message from SystemEdit
.equ accPaste, 0x48                             | paste message from SystemEdit
.equ accClear, 0x49                             | clear message from SystemEdit

.equ goodBye, -1                                | goodbye message



| International stuff

.equ IntlSpec, 0xBA0                            | (long) - ptr to extra Intl data

| Switcher


| Trap bits for memory manager

.equ tSysOrCurZone, 10                          | bit set implies System Zone
.equ clearBit, 9                                | bit set means clear allocated memory.


| Peripheral chips and Magic Hardware addresses


| Hardware addresses and constants

.equ sndBufWLen, 0x0172                         | sound/disk buffer word length


| VIA (6522) interface chip


| Offsets

.equ vBufB, 0                                   | BUFFER B
.equ vBufAH, 0x200                              | buffer a (with handshake) [ Dont use! ]
.equ vDIRB, 0x400                               | DIRECTION B
.equ vDIRA, 0x600                               | DIRECTION A
.equ vT1C, 0x800                                | TIMER 1 COUNTER (L.O.)
.equ vT1CH, 0xA00                               | timer 1 counter (high order)
.equ vT1L, 0xC00                                | TIMER 1 LATCH (L.O.)
.equ vT1LH, 0xE00                               | timer 1 latch (high order)
.equ vT2C, 0x1000                               | TIMER 2 LATCH (L.O.)
.equ vT2CH, 0x1200                              | timer 2 counter (high order)
.equ vSR, 0x1400                                | SHIFT REGISTER
.equ vACR, 0x1600                               | AUX. CONTROL REG.
.equ vPCR, 0x1800                               | PERIPH. CONTROL REG.
.equ vIFR, 0x1A00                               | INT. FLAG REG.
.equ vIER, 0x1C00                               | INT. ENABLE REG.
.equ vBufA, 0x1E00                              | BUFFER A

.equ vBufD, 0x1E00                              | disk head select buffer

| Buffer A:

.equ vAOut, 0x7F                                | VBufA output bits
.equ vAInit, 0x7B                               | VBufA initial values med. volume
.equ vSound, 0x7                                | sound volume bits
.equ vSndPg2, 3                                 | select sound page 2 if 0
.equ vOverlay, 4                                | overlay bit (overlay when 1)
.equ vHeadSel, 5
.equ vPage2, 6                                  | select video page 2 if 0
.equ vSCCWrReq, 7                               | SCC write/request line

| Buffer B:

.equ vBOut, 0x87                                | VBufB output bits
.equ vBInit, 0x07                               | VBufB initial values
.equ rtcData, 0
.equ rtcClk, 1
.equ rtcEnb, 2                                  | enabled when 0
.equ vSW, 3                                     | mouse switch (0 when down)|
.equ vX2, 4                                     | mouse X level
.equ vY2, 5                                     | mouse Y level
.equ vH4, 6                                     | horizontal sync
.equ vSndEnb, 7                                 | /sound enable (reset when 1)


| SCC Serial Chip Addresses


.equ aData, 6                                   | offset for A channel data
.equ aCtl, 2                                    | offset for A channel control
.equ bData, 4                                   | offset for B channel data
.equ bCtl, 0                                    | offset for B channel control

.equ sccData, 4                                 | general offset for data from control

.equ rxBF, 0                                    | SCC receive buffer full
.equ txBE, 2                                    | SCC transmit buffer empty

| Disk Address


.equ ph0L, 0                                    | disk address offsets from base
.equ ph0H, 0x200
.equ ph1L, 0x400
.equ ph1h, 0x600
.equ ph2L, 0x800
.equ ph2H, 0xA00
.equ ph3L, 0xC00
.equ ph3H, 0xE00
.equ mtrOff, 0x1000
.equ mtrOn, 0x1200
.equ intDrive, 0x1400                           | enable internal drive address
.equ extDrive, 0x1600                           | enable external drive address
.equ q6L, 0x1800
.equ q6H, 0x1A00
.equ q7L, 0x1C00
.equ q7H, 0x1E00


| Interrupt secondary vectors




| Parameter Ram

.equ SPValid, 0x1F8                             | validation field ($A7) [byte]
.equ SPATalkA, 0x1F9                            | AppleTalk node number hint for port A

.equ SPPrint, 0x207                             | print stuff [byte]

.equ SPMisc1, 0x20A                             | miscellaneous [1 byte]

.equ GetParam, 0x1E4                            | system parameter scratch [20 bytes]
.equ SysParam, 0x1F8                            | system parameter memory [20 bytes]

| Cursor

.equ MTemp, 0x828                               | Low-level interrupt mouse location [long]
.equ RawMouse, 0x82C                            | un-jerked mouse coordinates [long]
.equ TheCrsr, 0x844                             | Cursor data, mask & hotspot [68 bytes]

| Mouse/Keyboard

.equ KbdVars, 0x216                             | Keyboard manager variables [4 bytes]
.equ KeypadMap, 0x17C                           | bitmap for numeric pad-18bits [long]
.equ JGNEFilter, 0x29A                          | GetNextEvent filter proc [pointer]
.equ KeyMVars, 0xB04                            | (word) for ROM KEYM proc state

.equ Mouse, 0x830                               | processed mouse coordinate [long]

| System Clocks



| + Vertical Blanking Interrupt Handler

| VBL Block Queue Element

.equ vType, 1                                   | VBL queue element is type 1
.equ inVbl, 6                                   | bit index for "in VBL" flag

.equ vblink, 0                                  | Link to next element [pointer]
.equ vblType, 4                                 | Unique ID for validity [word]
.equ vblAddr, 6                                 | service routine [pointer]
.equ vblCount, 0xA                              | timeout count [word]
.equ vblPhase, 0xC                              | phase count [word]

.equ VBLQueue, 0x160                            | VBL queue header [10 bytes]

| Event manager

.equ jPlayCtl, 16                               | playBack call
.equ jRecordCtl, 17                             | record call
.equ jcTickCount, 0                             | journal code for TickCount
.equ jcGetMouse, 1                              | journal code for GetMouse
.equ jcButton, 2                                | journal code for Button
.equ jcGetKeys, 3                               | journal code for GetKeys
.equ jcEvent, 4                                 | journal code for GetNextEvent(Avail)


| Event Queue Element Data Stucture

.equ evtQWhat, 6                                | event code [word]
.equ evtQMessage, 8                             | event message [long]
.equ evtQWhen, 0xC                              | ticks since startup [long]
.equ evtQWhere, 0x10                            | mouse location [long]
.equ evtQMeta, 0x14                             | state of modifier keys [byte]
.equ evtQMBut, 0x15                             | state of mouse button [byte]
.equ evtQBlkSize, 0x16                          | size of event record counting queue info

| flags in flags field in heapzone header

.equ fOnCheck, 0                                | Turn On Checking
.equ fChecking, 1                               | Checking on
.equ fNSelCompct, 4                             | Use non-selective compact algorithm when 1.
.equ fNoRvrAlloc, 5                             | Don't use rover allocation scheme when 1.
.equ fNSelPurge, 6                              | Use non-selective purge algorithm when 1.
.equ fRelAtEnd, 7                               | MakeBk packs rels at end of free bk when 1.

.equ ROZ, 0x0                                   | bit in flags field of MemMgr zone header

| Block Types

.equ tybkMask, 3                                | Mask for block type
.equ tybkFree, 0                                | Free Block
.equ tybkNRel, 1                                | Non-Relocatable
.equ tybkRel, 2                                 | Relocatable

| Block Offsets

.equ tagBC, 0                                   | Tag and Byte Count field [long]
.equ handle, 4                                  | back pointer to master pointer [pointer]
.equ blkData, 8                                 | data starts here

| Heap Zone header

.equ bkLim, 0x0                                 | last block in zone [pointer]
.equ purgePtr, 0x4                              | roving purge placeholder [pointer]
.equ hFstFree, 0x8                              | first free handle [pointer]
.equ zcbFree, 0xC                               | # of free bytes in zone [long]
.equ gzProc, 0x10                               | grow zone procedure [pointer]
.equ mAllocCnt, 0x14                            | # of master ptrs to allocate [word]
.equ flags, 0x16                                | Flags [word]
.equ cntRel, 0x18                               | # of allocated relocatable blocks [word]
.equ maxRel, 0x1A                               | max # of allocated rel. blocks [word]
.equ cntNRel, 0x1C                              | # of allocated non-rel. blocks [word]
.equ maxNRel, 0x1E                              | max # of allocated non-rel. blocks [word]
.equ cntEmpty, 0x20                             | # of empty handles [word]
.equ cntHandles, 0x22                           | total # of handles [word]
.equ minCBFree, 0x24                            | min # of bytes free [long]
.equ purgeProc, 0x28                            | purge warning procedure [pointer]
.equ allocPtr, 0x30                             | roving allocator [pointer]
.equ heapData, 0x34                             | start of heap zone data



.equ MmInOK, 0x12E                              | initial memory mgr checks ok? [byte]
.equ HpChk, 0x316                               | heap check RAM code [pointer]
.equ MaskBC, 0x31A                              | Memory Manager Byte Count Mask [long]
.equ MaskHandle, 0x31A                          | Memory Manager Handle Mask [long]
.equ MaskPtr, 0x31A                             | Memory Manager Pointer Mask [long]

| + System Error Handler


| + Drivers

.equ dskRfN, 0xFFFB                             | 3.5" disk reference number

| Serial I/O Driver

.equ SerialVars, 0x2D0                          | async driver variables [16 bytes]


| Serial handshake record definition

.equ shFXOn, 0x0                                | XOn/XOff output control flags [byte]
.equ shFCTS, 0x1                                | CTS hardware handshake flag [byte]
.equ shXOn, 0x2                                 | XOn character [byte]
.equ shXOff, 0x3                                | XOff character [byte]
.equ shErrs, 0x4                                | errors that cause abort [byte]
.equ shEvts, 0x5                                | status changes that cause events [byte]
.equ shFInX, 0x6                                | XOn/XOff input flow control flag [byte]
.equ shNull, 0x7                                | not used [byte]

| Serial status record definition

.equ ssCumErrs, 0x0                             | cumulative errors [byte]
.equ ssXOffSent, 0x1                            | XOff sent as input control flag [byte]
.equ ssRdPend, 0x2                              | read pending flag [byte]
.equ ssWrPend, 0x3                              | write pending flag [byte]
.equ ssCTSHold, 0x4                             | CTS flow control hold flag [byte]
.equ ssXOffHold, 0x5                            | XOff received as output flow control [byte]

| Disk Driver

| Driver Code Header (for I/O drivers, desk accessories)

.equ drvrFlags, 0x0                             | various flags and permissions [word]
.equ drvrDelay, 0x2                             | # of ticks between systask calls [word]
.equ drvrEMask, 0x4                             | event mask [word]
.equ drvrMenu, 0x6                              | driver menu ID [word]
.equ drvrOpen, 0x8                              | open routine offset [word]
.equ drvrPrime, 0xA                             | prime routine offset [word]
.equ drvrCtl, 0xC                               | control routine offset [word]
.equ drvrStatus, 0xE                            | status routine offset [word]
.equ drvrClose, 0x10                            | warmstart reset routine offset [word]
.equ drvrName, 0x12                             | length byte and name of driver [string]

| Driver Status record definition

.equ dsTrack, 0x0                               | current track [word]
.equ dsWriteProt, 0x2                           | bit 7=1 if volume locked [byte]
.equ dsDiskInPlace, 0x3                         | disk in place [byte]
.equ dsInstalled, 0x4                           | drive installed [byte]
.equ dsSides, 0x5                               | bit 7=0 if single-sided drive [byte]
.equ dsQLink, 0x6                               | next queue entry [pointer]
.equ dsDQVers, 0xA                              | 1 for HD20 [word]
.equ dsDQDrive, 0xC                             | drive number [word]
.equ dsDQRefNum, 0xE                            | driver reference number [word]
.equ dsDQFSID, 0x10                             | file-system identifier [word]
.equ dsTwoSideFmt, 0x12                         | -1 if two-sided disk [byte]
.equ dsDiskErrs, 0x14                           | error count [word]

.equ dsDrvSize, 0x12                            | drive block size low word [word]
.equ dsDrvS1, 0x14                              | drive block size high word [word]
.equ dsDrvType, 0x16                            | 1 for HD20 [word]
.equ dsDrvManf, 0x18                            | 1 for Apple Computer, Inc [word]
.equ dsDrvChar, 0x1A                            | 230 ($E6) for HD20 [word]
.equ dsDrvMisc, 0x1C                            | 0 -- reserved [byte]



| Drive command codes

.equ dcRead, 0
.equ dcWrite, 1
.equ dcStatus, 3
.equ dcInit, 25
.equ dcScan, 26

| Sound Stuff

.equ SoundVBL, 0x26A                            | vertical retrace control element [16 bytes]

| I/O System

.equ noQueueBit, 0x9                            | tells I/O system not to queue the request
.equ asyncTrpBit, 0xA                           | bit in high byte of trap specifying async

.equ toExtFS, 0x3F2                             | hook for external file systems

| File System Globals


| I/O Command Equates for I/O Queue Elements (match trap numbers)

.equ aRdCmd, 2                                  | read command
.equ aWrCmd, 3                                  | write command
.equ aCtlCmd, 4                                 | control command
.equ aStsCmd, 5                                 | status command

| New fields for _SetPMSP call: PMSP = "Poor Man's Search Path"

.equ ioPMSPFlg, 0x1A                            | Flag whether to enable the PMSP
.equ ioPMSPHook, 0x1C                           | Pointer to PMSP hook proc

| Print variables

.equ ScrDmpEnb, 0x2F8                           | screen dump enabled? [byte]

| Scrap Variables

.equ ScrapVars, 0x960                           | scrap manager variables [32 bytes]
.equ ScrapInfo, 0x960                           | scrap length [long]
.equ ScrapEnd, 0x980                            | end of scrap vars

| Segment Loader



| device manager - Chooser message values

.equ newSelMsg, 12                              | a new selection has been made
.equ fillListMsg, 13                            | fill the list with choices to be made
.equ getSelMsg, 14                              | mark one or more choices as selcted
.equ selectMsg, 15                              | a choice has actually been made
.equ deselectMsg, 16                            | a choice has been canceled
.equ terminateMsg, 17                           | lets device package clean up
.equ buttonMsg, 19                              | a button has been clicked

.equ TheChooser, 1





