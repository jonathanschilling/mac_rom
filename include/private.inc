| Private System Equates - memory manager internals, driver vectors, cursor
| Source: MPW 1.0 Private.a, Apple Computer Inc. 1984-1986


| File: Private.a
|
| Version 2.0
|
| Copyright Apple Computer, Inc. 1984, 1985, 1986
| All Rights Reserved
|

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

.equ PrNonPortable, 0



| _______________________________________________________________________
|
| System Equates -- These equates supplement the low-level equates for the
| Macintosh hardware and software defined in SysEqu.  These equates are private
| to Apple Computer, Inc. and should be used solely for building system
| software.
|
| _______________________________________________________________________

| + Hardware Address Equates (for 512K through 128K Macs)

| Unpacked, user versions of parameter ram

.equ SdEnable, 0x261                            | Sound enabled? [byte]

| Event Record Definition

.equ evtMax, 0x1E                               | maximum number of events in buffer

| Heap Zone header

.equ spare1, 0x2C                               | unused spare [long]


| Mouse/Keyboard

.equ Tocks, 0x173                               | Lisa sub-tick count [byte]

| Chooser


| Memory Manager

.equ minFree, 12                                | 12 byte minimum block size
.equ freeTag, 0x0                               | Tag for Free block
.equ nRelTag, 0x40000000                        | Tag for Non-Relocatable block
.equ relTag, 0x80000000                         | Tag for Relocatable block
.equ minAddr, 0x0                               | Min legal address
.equ maxAddr, 0x800000                          | Max legal address for 512K machine
.equ maxMasters, 0x1000                         | Ridiculously large allocation chunk size
.equ dfltMasters, 32                            | Default to 32 master pointers

| Driver Status record definition

.equ dsQType, 0xA                               | not used [word]
.equ dsNeedsFlush, 0x13                         | reserved [byte]

| This variable was named RetryCount in SONYEqu

.equ SONYRetry, 5


.equ PollRtnAddr, 0x128                         | 'other' driver locals [pointer]
.equ DiskVars, 0x222                            | Disk driver variables [62 bytes]


.equ LastPGlobal, 0x954                         | address of last printer global

| QuickDraw Glue Vectors

.equ JHideCursor, 0x800
.equ JScrnAddr, 0x80C
.equ JScrnSize, 0x810
.equ JUpdateProc, 0x820
.equ LGrafJump, 0x824
.equ JFontInfo, 0x8E4                           | jump entry for FMFontMetrics [long]

| Miscellaneous Globals

.equ SysCom, 0x100                              | start of system communication area
.equ ToolTable, 0x0C00                          | 512 longs, up to $1400
.equ OSTable, 0x0400                            | 256 longs, up to $800, where old table of 512 words was
.equ JShell, 0x212                              | journaling shell state [wprd]
.equ FileVars, 0x340                            | file system vars [184 bytes]
.equ LoadVars, 0x900                            | loader variables [68 bytes]
.equ LastLGlobal, 0x944                         | address past last loader global
.equ CoreEditVars, 0x954                        | core edit variables [12 bytes]
.equ ScreenVars, 0x292                          | Screen driver variables [8 bytes]
.equ SoundVars, 0x262                           | Sound driver variables [32 bytes]

| Font Manager Low Memory Globals

.equ FOutItalic, 0x99F                          | italic factor
.equ FOutULShadow, 0x9A1                        | underline halo
.equ FOutULThick, 0x9A2                         | underline thickness
.equ FOutDescent, 0x9A6                         | height below baseline
.equ FOutWidMax, 0x9A7                          | maximum width of character
.equ FOutLeading, 0x9A8                         | space between lines
.equ FOutNumer, 0x9AA                           | point for numerators of scale factor
.equ FOutDenom, 0x9AE                           | point for denominators of scale factor

| _______________________________________________________________________
|
| Toolbox Equates -- These equates supplement the high-level equates for the
| Macintosh toolbox software in ToolEqu.a.	 These equates are private
| to Apple Computer, Inc. and should be used solely for building system
| software.
|
| _______________________________________________________________________

.equ DeskPort, 0x9E2                            | Desk grafPort (Whole screen) [pointer]

| _______________________________________________________________________
|
| QuickDraw Equates -- This file supplements the public equates for QuickDraw.
| found in the file QuickEqu.a These equates are private
| to Apple Computer, Inc. and should be used solely for building system
| software.
|
| _______________________________________________________________________

.equ symbols, 0
.equ forMac, 1

| Region State record

.equ rgnPtr, 0x0                                | [handle]
.equ dataPtr, 0x4                               | [handle]
.equ scanBuf, 0x8                               | [pointer]
.equ scanSize, 0xC                              | [word]
.equ thisV, 0xE                                 | [word]
.equ nextV, 0x10                                | [word]
.equ minH, 0x12                                 | [word]
.equ maxH, 0x14                                 | [word]
.equ leftH, 0x16                                | [word]
.equ rgnRec, 0x18                               | size of as region record

| -----------------------------------------------------
|
| Offsets in a PicSave record:
|
.equ thePic, 0                                  | PICHANDLE
.equ picMax, 4                                  | LongInt
.equ picIndex, 8                                | LongInt
.equ picClipRgn, 12                             | RgnHandle
.equ picBkPat, 16                               | Pattern
.equ picTxFont, 24                              | WORD
.equ picTxFace, 26                              | Style
.equ picTxMode, 28                              | WORD
.equ picTxSize, 30                              | WORD
.equ picSpExtra, 32                             | Fixed Point
.equ picTxNumer, 36                             | Point
.equ picTxDenom, 40                             | Point
.equ picTxLoc, 44                               | Point
.equ picPnLoc, 48                               | Point
.equ picPnSize, 52                              | Point
.equ picPnMode, 56                              | WORD
.equ picPnPat, 58                               | Pattern
.equ picFillPat, 66                             | Pattern
.equ picTheRect, 74                             | Rect
.equ picOvSize, 82                              | Point
.equ picOrigin, 86                              | Point
.equ picFgColor, 90                             | Long
.equ picBkColor, 94                             | Long

.equ picSaveRec, 98                             | total size in bytes


| for Mac+ Only - 2-way comm cmd

.equ RDSync, 0                                  | sync up w/each other

| command byte from nub to MPS

.equ RDSysErr, 1                                | system error
.equ RDTrapCall, 2                              | trap call
.equ RDDta, 3                                   | data comin' down the road

| command byte from MPS to nub

.equ RDGetN, 1                                  | GetNBytes
.equ RDSetN, 2                                  | SetNBytes
.equ RDCallProc, 3                              | CallProc
.equ RDSetAtrap, 4                              | SetATrap
.equ RDResume, 5                                | Resume execution

| end Mac+ only


.equ FlEvtMask, 0x25E                           | (word) mask of allowable events to flush at FlushEvents.


.equ AtalkHk2, 0xB18                            | (long) Appletalk hook

.equ SCSIFlag, 0xB22                            | (word) Configuration Flag for SCSI



.equ RMGRHiVars, 0xB80                          | $B80-$BFF are switched vars

.equ NewUnused, 0xBC0                           | (word) - used to be FlEvtMask

.equ FmtDefaults, 52+0x36A                      | ptr to formatting defs (TFSVars + 52)  [long]

| addresses of TE hooks installed in trap table

.equ TETrimMeasure, (4*253+OSTable)             | trimMeasure hook
.equ TEFindWord, (4*254+OSTable)                | findWord hook
.equ TEFindLine, (4*255+OSTable)                | findLine hook

.equ JBlockMove, 0x4B8                          | Special equate for OUR HeapGuts Jump Table

.equ jInsTime, (600-512)*4+OSTable              |
.equ jRmvTime, (601-512)*4+OSTable              |
.equ jPrimeTime, (602-512)*4+OSTable            |

.equ jLg2Phys, (703-512)*4+OSTable              |

.equ jFlushCache, (704-512)*4+OSTable           |
.equ jGetBlock, (705-512)*4+OSTable             |
.equ jMarkBlock, (706-512)*4+OSTable            |
.equ jRelBlock, (707-512)*4+OSTable             |
.equ jTrashBlocks, (708-512)*4+OSTable          |
.equ jTrashVBlks, (709-512)*4+OSTable           |
.equ jCacheWrIP, (710-512)*4+OSTable            |
.equ jCacheRdIP, (711-512)*4+OSTable            |


.equ jBasicIO, (712-512)*4+OSTable              |
.equ jRdBlocks, (713-512)*4+OSTable             |
.equ jWrBlocks, (714-512)*4+OSTable             |
.equ jSetUpTags, (715-512)*4+OSTable            |

.equ jBTClose, (716-512)*4+OSTable              |
.equ jBTDelete, (717-512)*4+OSTable             |
.equ jBTFlush, (718-512)*4+OSTable              |
.equ jBTGetRecord, (719-512)*4+OSTable          |
.equ jBTInsert, (720-512)*4+OSTable             |
.equ jBTOpen, (721-512)*4+OSTable               |
.equ jBTSearch, (722-512)*4+OSTable             |
.equ jBTUpdate, (723-512)*4+OSTable             |

.equ jGetNode, (724-512)*4+OSTable              |
.equ jRelNode, (725-512)*4+OSTable              |
.equ jAllocNode, (726-512)*4+OSTable            |
.equ jFreeNode, (727-512)*4+OSTable             |
.equ jExtBTFile, (728-512)*4+OSTable            |

.equ jDeallocFile, (729-512)*4+OSTable          |
.equ jExtendFile, (730-512)*4+OSTable           |
.equ jTruncateFile, (731-512)*4+OSTable         |

.equ jCMSetUp, (732-512)*4+OSTable              |

.equ jDtrmV1, (734-512)*4+OSTable               |
.equ jBlkAlloc, (735-512)*4+OSTable             |
.equ jBlkDeAlloc, (736-512)*4+OSTable           |
.equ jFileOpen, (737-512)*4+OSTable             |
.equ jPermssnChk, (738-512)*4+OSTable           |
.equ jFndFilName, (739-512)*4+OSTable           |
.equ jRfNCall, (740-512)*4+OSTable              |
.equ jAdjEOF, (741-512)*4+OSTable               |


.equ jClkNoMem, (595-512)*4+OSTable             | vector for clock


.equ jSegStack, (760-512)*4+OSTable             | vector for segment loader

| vectors for RMGR low levels routines
.equ jSuperLoad, (761-512)*4+OSTable            |
.equ jCmpFrm, (762-512)*4+OSTable               |
.equ jNewMap, (763-512)*4+OSTable               |
.equ jCheckLoad, (764-512)*4+OSTable            |



