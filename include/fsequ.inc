| File System Equates
| Source: MPW 1.0 FSEqu.a, Apple Computer Inc. 1984-1986
| Converted to GNU as syntax for use in Macintosh ROM source


| File: FSEqu.a
|
| Version 2.0
|
| Copyright Apple Computer, Inc. 1984, 1985, 1986
| All Rights Reserved
|


.equ SigWord, 0xD2D7                            | signature bytes (MFS volume)

.equ TSigWord, 0x4244                           | signature bytes (HFS volume)

.equ HFSBit, 9                                  | defines HFS bit in trap word

| _______________________________________________________________________

| fixed location labels: (equivalent of zero page)

.equ FSFCBLen, 0x3F6                            | HFS present flag / FCB size (-1 in old ROM)

.equ WDRfnMin, -32767                           | Lowest assigned WD RefNum
.equ WDRfnMax, -4096                            | largest possible WDrefnum

.equ HFSTagData, 0x38A                          | Room for additional HFS tag data
.equ FCBSPtr, 0x34E                             | ptr to FCBs
.equ DefVCBPtr, 0x352                           | pointer to default VCB
.equ VCBQHdr, 0x356                             | VCB queue header

.equ FSQHdr, 0x360                              | file system queue header (10 bytes)
.equ FSBusy, 0x360                              | non-zero when the file system is busy
.equ FSQHead, 0x362                             | ptr to 1st queued cmd: 0 when queue empty
.equ FSQTail, 0x366                             | ptr to last queue element

|
| Volume Control Block equates: (prefix: VCB)
|
.equ vcbFlags, 6                                | flags word is first word after header
.equ vcbDirty, 15                               | flags dirty bit (tst.w tests,clr.b clears)

| first 64/104 bytes of VCB come directly from the directory master block

.equ vcbDInfoSt, 8                              | leave room for 6-byte queue header
.equ vcbDILen, 64                               | len of VCB data from master directory (from old FSEQU)

.equ vcbSigWord, 8                              | signature word
.equ vcbCrDate, 10                              | Creation date.
.equ vcbLsBkUp, 14                              | last backup date
.equ vcbLsMod, 14                               | alternate name for above
.equ vcbAtrb, 18                                | volume attributes. bit 15 = vol lock (1=locked)
.equ vcbAtVOK, 8                                | attrib consistent volume flag (set on clean _Unmount)
.equ vcbWrProt, 7                               | attrib write-protected bit (tst.b ATRB+1 tests)

.equ vcbNmFls, 20                               | number files in  MFS dir
.equ vcbDirSt, 22                               | start dir (512-byte) block on diskette (MFS)
.equ vcbVBMSt, 22                               | same as VCBDirSt, starting block of allocation map  (HFS) (overlaps)
.equ vcbBlLn, 24                                | length of dir in (512-byte) blocks (MFS)
.equ vcbAllocPtr, 24                            | same as VCBBlLn, Starting block for new file allocations
.equ vcbNmBlks, 26                              | number of blocks (of alloc size) this device
.equ vcbNmAlBlks, 26                            | (alternate label for a while)
.equ vcbAlBlkSiz, 28                            | num of bytes in an allocation block
.equ vcbClpSiz, 32                              | num of bytes to try to alloc as a clump
.equ vcbAlBlSt, 36                              | starting diskette (512-byte) block in block map
.equ vcbNxtCNID, 38                             | next free CNode identifier (HFS)
.equ vcbNxtFNum, 38                             | next free file number (MFS)
.equ vcbFreeBks, 42                             | number of free blocks on this volume
.equ vcbVN, 44                                  | volume name (including name length byte)
.equ vcbMaxNam, 27                              | 27 byte max name length
.equ IOVDirLen, vcbVN-vcbCrDate                 | Length of info to copy by GetVolInfo
|
| next 6 fields should be kept together
|
.equ vcbDrvNum, 72                              | drive number for this VCB
.equ vcbDRefNum, 74                             | driver refnum for this VCB
.equ vcbFSID, 76                                | ID of file system handling this volume
.equ vcbVRefNum, 78                             | unique refnum for this VCB
.equ vcbMAdr, 80                                | volume map address (FS volume)
.equ vcbBufAdr, 84                              | volume buffer address
.equ vcbMLen, 88                                | length of volume map (FS volume)

.equ vcbDirIndex, 90                            | directory index, block number used for
.equ vcbDirBlk, 92                              | GetFileInfo searches by index
.equ MFSVCBLen, 94                              | Length of MFS VCB

|
| Volume Control Block (VCB) extensions for HFS copied from Volume Info Block:
|
.equ vcbTDInfoSt, 94                            | Start of additional HFS info:
.equ vcbVolBkUp, 94                             | Date volume was last backed up
.equ vcbVSeqNum, 98                             | Index of volume in backup set
.equ vcbWrCnt, 100                              | Volume write count
.equ vcbXTClpSiz, 104                           | Extent B*-Tree clump size
.equ vcbCTClpSiz, 108                           | Catalog B*-Tree clump size
.equ vcbNmRtDirs, 112                           | Number of directories in root
.equ vcbFilCnt, 114                             | Total number of files in volume
.equ vcbDirCnt, 118                             | Total number of directories in volume
.equ vcbFndrInfo, 122                           | Finder info for volume
.equ vcbVCSize, 154                             | Volume cache size in blocks
.equ vcbVBMCSiz, 156                            | Bitmap cache size in blocks
.equ vcbCtlCSiz, 158                            | Extent and Catalog B*-Tree cache size (blocks)
|
| additional VCB information NOT copied from the MDB:
|
.equ vcbXTAlBks, 160                            | Size of extent B*-Tree in allocation blocks
.equ vcbCTAlBks, 162                            | Size of catalog B*-Tree in allocation blocks
.equ vcbXTRef, 164                              | File RefNum for Extent B*-Tree
.equ vcbCTRef, 166                              | File RefNum for Catalog B*-Tree
.equ vcbCtlBuf, 168                             | Pointer to extent desc. and catalog caches
.equ vcbDirIDM, 172                             | Directory last searched: 0 if invalid.
.equ vcbOffsM, 176                              | Offspring index at last search
.equ vcbLength, 178                             | VCB byte length

| File Control Block equates: (prefix: FCB)

.equ fcbModBit, 7                               | dirty bit for FCB entry in FCBMdRByt
.equ fcbOwnClp, 6                               | Clump-size specified flag (for truncate on close)
.equ fcbFilLck, 5                               | 1 if file is locked [write-protected]
.equ fcbShrWrt, 4                               | 1 if file is open for shared write access
.equ fcbWrtLck, 2                               | 1 if fork is reserved for write (byte range lock)
.equ fcbRscBit, 1                               | 1 if this is resource part (in FCBMdRByt)
.equ fcbWrtBit, 0                               | write permissions bit in FCBTypByt (1 if ok)

.equ fcbFlgMBit, 15                             | dirty bit in FCBFlags (word)
.equ fcbFlgCBit, 14                             | clump-size spec'd bit in FCBFlags (word)
.equ fcbFlgPBit, 13                             | Write-protected [file lock] bit in FCBFlags (word)
.equ fcbFlgSBit, 12                             | Shared-write bit in FCBFlags (word)
.equ fcbFlgLBit, 10                             | Byte range locked bit in FCBFlags (word)
.equ fcbFlgRBit, 9                              | resource bit in FCBFlags (word)
.equ fcbFlgWBit, 8                              | write permissions bit in FCBFlags (word)
.equ WrRsMask, 0x0300                           | rsrc/reg, write permissions mask
.equ PermMask, 0x1300                           | all bits related to access arbitration

.equ fcbFlNm, 0                                 | FCB file number. Non-zero marks FCB used.
.equ fcbFlags, 4                                | FCB flags
.equ fcbMdRByt, 4                               |  mod, write permissions, resource byte
.equ fcbTypByt, 5                               |  type byte

.equ fcbSBlk, 6                                 | File start block (in alloc size blks)
.equ fcbEOF, 8                                  | logical length or EOF in bytes
.equ fcbPLen, 12                                | Physical file length in bytes
.equ fcbCrPs, 16                                | current position within file.
.equ ioFIStILen, 20                             | Length to straight copy from FCB on _GetFCBInfo
.equ fcbVPtr, 20                                | Absolute pointer to the corresponding VCB
.equ fcbBfAdr, 24                               | file's buffer address.
.equ fcbFlPos, 28                               | directory block this file is in
.equ MFSFCBLen, 30                              | Length of MFS FCB structure

|
| FCB Extensions for HFS:
|
.equ fcbClmpSize, 30                            | Number of bytes per clump
.equ fcbBTCBPtr, 34                             | pointer to B*-Tree control block for this file
.equ fcbExtRec, 38                              | First 3 file extents
.equ fcbFType, 50                               | file's 4 Finder Type bytes
.equ fcbCatPos, 54                              | Catalog hint for use on Close
.equ fcbDirID, 58                               | Parent Directory ID
.equ fcbCName, 62                               | CName of open file


.equ fcbEntLen, 94                              | Length of each element in the FCB array


| _______________________________________________________________________
|
| Directory master block entries: (Prefix Dr)
|
.equ drSigWord, 0                               | signature word
.equ drCrDate, 2                                | Creation date.
.equ drLsMod, 6                                 | last backup date
.equ drAtrb, 10                                 | volume attributes. bit 15=write(locked=1)
.equ drNmFls, 12                                | number files in directory
.equ drDirSt, 14                                | start dir (512-byte) block on diskette
.equ drVBMSt, 14                                | starting sector of allocation map (overlaps)
.equ drBlLn, 16                                 | length of dir in (512-byte) blocks
.equ drAllocPtr, 16                             | Start of next allocation search
.equ drNmAlBlks, 18                             | number of blocks (of alloc size) this volume
.equ drAlBlkSiz, 20                             | min num of bytes to allocate (must be 512 mult)
.equ drClpSiz, 24                               | num of bytes to try to alloc as a clump
.equ drAlBlSt, 28                               | starting diskette (512-byte) block in block map
.equ drNxtCNID, 30                              | Next CNode identifier
.equ drNxtFNum, 30                              | next free file number
.equ drFreeBks, 34                              | number of free blocks on this volume
.equ drVN, 36                                   | volume name (including name length)
.equ MpTblStr, 64                               | byte start position of map table within
|
| Master Directory Block extensions for HFS:
|
.equ drTInfoSt, 64
.equ drVolBkup, 64                              | Date of last volume backup (overlaps)
.equ drVSeqNum, 68                              | Sequence number of volume within backup set
.equ drWrCnt, 70                                | Volume write count
.equ drXTClpSiz, 74                             | Extent B*-Tree clump size
.equ drCTClpSiz, 78                             | Catalog B*-Tree clump size
.equ drNmRtDirs, 82                             | Number of subdirectories in the root
.equ drFilCnt, 84                               | Total number of files in volume
.equ drDirCnt, 88                               | Total number of directories in volume
.equ drFndrInfo, 92                             | Finder info for volume
.equ drVCSize, 124                              | Volume cache size
.equ drVBMCSize, 126                            | Volume Bitmap cache size
.equ drCtlCSize, 128                            | Size of common volume cache
|
| length of additional VCB data from master directory block for HFS volumes:
|
.equ vcbTDILen, 130-drTInfoSt
|
| Information not copied into VCB:
|
.equ drXTFlSize, 130                            | Length of extent B*-Tree (LEOF and PEOF)
.equ drXTExtRec, 134                            | First (and only) extent-tree extent record
.equ drCTFlSize, 146                            | Length of catalog B*-Tree (LEOF and PEOF)
.equ drCTExtRec, 150                            | First catalog extent record
.equ LenMDB, 162                                | length of full MDB

.equ drUsrInfo, 256                             | User information for volume


| _______________________________________________________________________
|
| File Entry equates: (prefix: Fl)
| (delete indication may be needed; for now just check VCB del fnum . . .)

.equ flWrtFlag, 0                               | write-allowed bit in flags byte (0 if allowed)
.equ flTypMask, 0xFE                            | (user file-type in bits 1-7)

.equ flFlags, 0                                 | bit 7=1 (used), bit 0=file lock flag
.equ flTyp, 1                                   | file type (used as a name extension)
.equ flUsrWds, 2                                | user words for file. (16 bytes)
.equ flFlNum, 18                                | file number

.equ flStBlk, 22                                | Start file block (alloc blk size)(0000 if none)
.equ flLgLen, 24                                | File logical length in bytes (EOF)
.equ flPyLen, 28                                | File physical length in bytes

.equ flRStBlk, 32                               | Start file block, resource fork (0000 if none)
.equ flRLgLen, 34                               | File logical length (EOF), resource fork
.equ flRPyLen, 38                               | File physical length, resource fork

.equ flCrDat, 42                                | File creation date & time (32 bits in seconds)
.equ flMdDat, 46                                | last modification date & time (32 bits in seconds)
.equ flNam, 50                                  | file name, starting with length byte
.equ flNTLen, 50                                | length of each file entry, excluding name

| _______________________________________________________________________
|
| Working Directory Control Block equates: (prefix: WD)
|
.equ WDVCBPtr, 0                                | pointer to VCB of residing WD (longint)
.equ WDDirID, 4                                 | WD directory Identification (longint)
.equ WDCatHint, 8                               | Catalog node hint
.equ WDProcID, 12                               | process that created WD
.equ WDCBLen, 16                                | Length of a WDCB

| _______________________________________________________________________
|
| Poor Man's Search Path equates: (prefix: SP)
|
.equ PMSPHook, -6                               | Hook for PMSP modification
.equ PMSPIndx, -2                               | Index to PMSP index from start of PMSP
.equ SPHdrSize, 6                               | Size of negative-offset header

.equ SPVRefNum, 0                               | Offset to VRefNum in PMSP entry
.equ SPDirID, 2                                 | Offset to Directory ID in PMSP entry
.equ SPEntLen, 6                                | Length of a PMSP entry

.equ MaxDVCnt, 8                                | Leave room for 8 default VRefNums
.equ PMSPSize, MaxDVCnt*SPEntLen+SPHdrSize+2    | Size of PMSP table +header + index word

.equ AlBlkLim, 31744                            | 31744 = $7C00, a nice round number close to




| Cache Buffer Header (CBH) structure - from MPW 1.0 FSPrivate.a
| Each cache entry is a 28-byte header + 512 bytes of block data.
| Cache entries are linked in a doubly-linked circular list.
.equ CBHFlink, 0                                | forward link (next cache entry)
.equ CBHBlink, 4                                | backward link (prev cache entry)
.equ CBHVCBPtr, 8                               | VCB pointer (which volume)
.equ CBHFlNum, 12                               | file number (CNID)
.equ CBHFRefNum, 16                             | file reference number (word)
.equ CBHDBlk, 18                                | disk block number (long, -1=empty)
.equ CBHFlBlk, 22                               | file block number (long)
.equ CBHFlags, 26                               | flags byte
.equ CBHdirty, 7                                |   bit 7: buffer dirty
.equ CBHinuse, 6                                |   bit 6: buffer in use
.equ CBHempty, 5                                |   bit 5: buffer is empty
.equ CBHFkType, 27                              | fork type (0=data, 0xFF=resource)
.equ CBHData, 28                                | start of 512-byte data area
.equ lenCBH, 28                                 | length of CBH header

| GetBlock option flags (bits in D5 parameter)
.equ GBrelease, 3                               | release block after get
.equ GBnoRead, 2                                | don't read block from disk
.equ GBexist, 1                                 | get existing cache block only
.equ GBRead, 0                                  | force read from disk

| RelBlock option flags
.equ RBdirty, 2                                 | mark buffer dirty on release
.equ RBtrash, 1                                 | trash buffer after release
.equ RBwrite, 0                                 | force write to disk on release

| FlushCache option flags
.equ FCtrash, 0                                 | trash buffers after flush

| B-tree Node Descriptor (14 bytes) - from MPW 1.0 FSPrivate.a
.equ NDFlink, 0                                 | forward link node number (long)
.equ NDBlink, 4                                 | backward link node number (long)
.equ NDType, 8                                  | node type (byte): 0=index, 1=header, 2=map, $FF=leaf
.equ NDNHeight, 9                               | node height (byte): 0=header, 1=leaf, 2+=index
.equ NDNRecs, 10                                | number of records in node (word)
.equ NDResv2, 12                                | reserved (word)
.equ BTNodeSize, 512                            | default node size (bytes)

| B-tree Header Record (30 bytes in memory, 106 on disk) - BTH
.equ BTHDepth, 0                                | current depth of tree (word)
.equ BTHRoot, 2                                 | root node number (long)
.equ BTHNRecs, 6                                | number of leaf records (long)
.equ BTHFNode, 10                               | first leaf node number (long)
.equ BTHLNode, 14                               | last leaf node number (long)
.equ BTHNodeSize, 18                            | node size in bytes (word)
.equ BTHKeyLen, 20                              | max key length (word)
.equ BTHNNodes, 22                              | total nodes in tree (long)
.equ BTHFree, 26                                | free nodes available (long)
.equ lenMemBTH, 30                              | length of in-memory BTH

| B-tree Control Block (54 bytes) - BTCB
.equ BTCFlags, 0                                | flags (byte)
.equ BTCDirty, 7                                |   bit 7: B-tree dirty
.equ BTCKeyUpd, 6                               |   bit 6: index key update required
.equ BTCNewIRec, 5                              |   bit 5: new index record required
.equ BTCDelIRec, 4                              |   bit 4: index record delete required
.equ BTCRefNum, 2                               | file refnum (word)
.equ BTCKeyCR, 4                                | key compare routine pointer (long)
.equ BTCCQPtr, 8                                | cache queue pointer (long)
.equ BTCVarPtr, 12                              | B-tree variables pointer (long)
.equ BTCLevel, 16                               | current level (word)
.equ BTCNodeM, 18                               | current node mark (long)
.equ BTCIndexM, 22                              | current index mark (word)
.equ BTCDepth, 24                               | tree depth (word) [= BTHDepth]
.equ BTCRoot, 26                                | root node number (long) [= BTHRoot]
.equ BTCNRecs, 30                               | leaf record count (long) [= BTHNRecs]
.equ BTCFNode, 34                               | first leaf node (long) [= BTHFNode]
.equ BTCLNode, 38                               | last leaf node (long) [= BTHLNode]
.equ BTCNodeSize, 42                            | node size (word) [= BTHNodeSize]
.equ BTCKeyLen, 44                              | max key length (word) [= BTHKeyLen]
.equ BTCNNodes, 46                              | total nodes (long) [= BTHNNodes]
.equ BTCFree, 50                                | free nodes (long) [= BTHFree]
.equ LenBTCB, 54                                | length of BTCB

| Tree Path Record (6 bytes) - tracks descent path through B-tree
.equ TPRNodeN, 0                                | node number (long)
.equ TPRRIndx, 4                                | record index (word)
.equ LenTPR, 6                                  | length of one TPR entry
