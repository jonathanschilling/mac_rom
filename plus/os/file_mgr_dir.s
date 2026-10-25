| File Manager -- calls by file name (directory level)
|
| Apple sources, included by TFS.a (MacSEROM.lst module TURBOFS):
| TFSDir1.a ... TFSDir3.a and MFSDir1.a ... MFSDir3.a: OpenRF/FileOpen
| (open a fork: _Open on a file goes here through the Device Manager),
| PermssnChk, Create, Delete, Rename, CatMove, DirCreate, SetFilType,
| SetFilLock, RstFilLock, SetFileInfo, SetCatInfo, FndFilName (look up a
| file by name on HFS or MFS), GetFileInfo, GetCatInfo. All calls take
| A0 = parameter block (IOParam / FileParam / CInfoPBRec).
|
| FileParam - File information parameter block (MPW 1.0 Files.h):
| Offset 0-22: same as IOParam header (qLink..ioVRefNum)
| Offset 24: ioFRefNum INTEGER file reference number
| Offset 26: ioFVersNum BYTE file version number
| Offset 28: ioFDirIndex INTEGER directory index
| Offset 30: ioFlAttrib BYTE file attributes
| Offset 31: ioFlVersNum BYTE file version number
| Offset 32: ioFlFndrInfo FInfo Finder info (16 bytes)
| Offset 48: ioFlNum LongInt file number
| Offset 52: ioFlStBlk INTEGER first alloc block of data fork
| Offset 54: ioFlLgLen LongInt logical length of data fork
| Offset 58: ioFlPyLen LongInt physical length of data fork
| Offset 62: ioFlRStBlk INTEGER first alloc block of resource fork
| Offset 64: ioFlRLgLen LongInt logical length of resource fork
| Offset 68: ioFlRPyLen LongInt physical length of resource fork
| Offset 72: ioFlCrDat LongInt creation date
| Offset 76: ioFlMdDat LongInt modification date
|
| FInfo - Finder information (16 bytes, MPW 1.0 Files.h):
| Offset 0: fdType OSType file type (e.g. 'TEXT', 'APPL')
| Offset 4: fdCreator OSType creator application
| Offset 8: fdFlags INTEGER Finder flags
| Offset 10: fdLocation Point position in folder window
| Offset 14: fdFldr INTEGER folder containing file
|


| ----------------------------------------------------------
|
| _OpenRF ($A00A)
| A0 = paramBlock -> D0 = error; opens resource fork
|
| Called during boot.
OpenRF:
        BSR     FSQUEUE_SETUP                   | call helper
        CLR.B   (RegRsrc).w                     | clear
        BRA.B   FILEOPEN_CONT                   | ->

| ----------------------------------------------------------
|
| P_m File Open
|
| Called during boot.
P_mFileOpen:
        MOVE.L  (0x784).w,-(SP)                 | HFS vector: FileOpen
        RTS                                     | return from P_mFileOpen

| ----------------------------------------------------------
|
| File Open
|
| Called during boot.
| FileOpen (vFileOpen)
FileOpen:
        BSR     FSQUEUE_SETUP                   | FSQueue: queue up the call
        ST.B    (RegRsrc).w                     | open regular part of file
| first, make sure we have an open FCB
FILEOPEN_CONT:
        BSR.B   HFSE_CONT_14                    | Gt1stFCB: get first FCB entry
FILEOPEN_CONT_2:
        TST.L   0x0(A1,D1.W)                    | FCB unused? (FCBFlNm)
        BEQ.B   CHKVOL                          | br if so
        BSR.B   HFSE_NEXT                       | GtNxtFCB: get next one
        BCS.B   FILEOPEN_CONT_2                 | keep looking
        MOVEQ.L #-0x2A,D0                       | too many files open (TMFOErr)
FILEOPEN_CONT_3:
        CLR     ioRefNum(A0)                    | make refnum invalid
FILEOPEN_ERR:
        BRA     FSQUEUE_DONE                    | CmdDone
| ChkVol: search directory for the file to open
CHKVOL:
        MOVE    D1,ioRefNum(A0)                 | refnum is the FCB index
        ADD.L   A1,D1                           | save FCB ptr in D1
        BSR     P_FndFilName                    | look for the affected file & volume
        BNE.B   FILEOPEN_CONT_3                 | punt if problem ->
| zero the newly found FCB before use
        MOVE.L  A0,-(SP)                        | save param block ptr
        MOVE.L  D1,A0                           | point to FCB entry
        MOVEQ.L #0x2E,D0                        | (FCB length / 2) - 1
FILEOPEN_LOOP:
        CLR     (A0)+                           | clear a word in the FCB
        DBF     D0,FILEOPEN_LOOP                | until all done
        MOVE.L  (SP)+,A0                        | restore parameter block ptr
        BSR     TFSVCBTst                       | TFS volume?
        BNE     CREATE_NO_5                     | if not, MFS open ->
| handle an open for a TFS volume
        MOVEQ.L #-0x2B,D0                       | FNFErr: assume not found
        CMPI.B  #0x2,(A5)                       | is it a file record? (CDRFilRec)
        BNE.B   FILEOPEN_CONT_3                 | crash and burn on directory specs
        MOVE.L  D1,A3                           | A3 = FCB pointer
        MOVE.L  D7,0x36(A3)                     | store catalog hint (FCBCatPos)
        MOVE.L  0x4(A5),D0                      | get file type (FilUsrWds+FdType)
        MOVE.L  D0,0x32(A3)                     | copy to FCB (FCBFType)
        MOVE.L  D6,fcbDirID(A3)                 | copy parental DirID (FCBDirID)
| set up clump size
        MOVEQ.L #0x0,D0                         | clear top word
        MOVE    0x48(A5),D0                     | pick up file's clump size (FilClpSize)
        BEQ.B   FILEOPEN_EMPTY                  | if none set, default to volume's
        MULU    0x1E(A2),D0                     | multiply by alloc block size
        BSET    #0x6,0x4(A3)                    | set flag: own clump size (FCBOwnClp)
        BRA.B   FILEOPEN_CONT_4                 | go set it up
FILEOPEN_EMPTY:
        MOVE.L  vcbClpSiz(A2),D0                | pick up volume's clump size
        BCLR    #0x6,0x4(A3)                    | clear 'own clump size' flag
FILEOPEN_CONT_4:
        MOVE.L  D0,0x1E(A3)                     | set FCB clump size (FCBClmpSize)
| copy extent record from catalog to FCB
        MOVEM.L A0-A1,-(SP)                     | free up scratch registers
        MOVEQ.L #0xC,D0                         | length of an extent record (lenXDR)
        LEA.L   0x4A(A5),A0                     | data fork's extents (FilExtRec)
        TST.B   (RegRsrc).w                     | was this the fork desired?
        BNE.B   FILEOPEN_CONT_5                 | if set, that's what we wanted
        LEA.L   0x56(A5),A0                     | point to resource fork's extents
FILEOPEN_CONT_5:
        LEA.L   0x26(A3),A1                     | load address
        _BlockMove                              | copy the extent record
| copy CName into FCB
        MOVEQ.L #0x0,D0                         | clear top half of D0
        MOVE    D2,D0                           | get name length
        MOVE.L  A4,A0                           | point to filename in pathname
        LEA.L   0x3E(A3),A1                     | point to name field in FCB (FCBCName)
        MOVE.B  D0,(A1)+                        | copy in CName length
        _BlockMove                              | make a copy of the name string
        MOVEM.L (SP)+,A0-A1                     | restore the scratch registers
| set up file info from catalog record
        CLR     D7                              | D7 = 0 (no write count yet)
        MOVE    0x2(A5),D3                      | get file flags (filFlags)
        ANDI    #0x100,D3                       | isolate file-locked bit
        BEQ.B   FILEOPEN_NO                     | not locked ->
        BSET    #0xD,D3                         | set FCB locked flag
FILEOPEN_NO:
| load fork info from catalog record
        LEA.L   0x14(A5),A5                     | point to data fork info (filFlNum field)
        MOVE.L  (A5)+,D2                        | D2 = file number (filFlNum)
        MOVE    (A5)+,D4                        | D4 = data fork start block (filStBlk)
        MOVE.L  (A5)+,D5                        | D5 = data fork logical EOF (filLgLen)
        MOVE.L  (A5)+,D6                        | D6 = data fork physical EOF (filPyLen)
        TST.B   (RegRsrc).w                     | was this the fork desired?
        BNE.B   FILEOPEN_CONT_6                 | if set, that's what we wanted
        BSET    #0x9,D3                         | set resource fork flag
        MOVE    (A5)+,D4                        | D4 = rsrc fork start block (filRStBlk)
        MOVE.L  (A5)+,D5                        | D5 = rsrc fork logical EOF (filRLgLen)
        MOVE.L  (A5)+,D6                        | D6 = rsrc fork physical EOF (filRPyLen)
FILEOPEN_CONT_6:
| check file permissions
        BSR.B   P_PermssnChk                    | PermssnChk: check access permissions
        BEQ.B   SETUPFCB                        | ok ->
| permission denied: zero the FCB and exit
        MOVEQ.L #0x2E,D1                        | (FCB length / 2) - 1
FILEOPEN_LOOP_2:
        CLR     (A3)+                           | clear the FCB
        DBF     D1,FILEOPEN_LOOP_2              | until all done
        BRA     FILEOPEN_ERR                    | CmdDone with error
| SetupFCB: fill in the FCB fields
SETUPFCB:
        MOVE.L  D2,(A3)+                        | FCBFlNm = file number
        MOVE    D3,(A3)+                        | FCBMdRByt + flags
        MOVE    D4,(A3)+                        | FCBStBlk = start block
        MOVE.L  D5,(A3)+                        | FCBEOF = logical EOF
        MOVE.L  D6,(A3)+                        | FCBPLen = physical EOF
        CLR.L   (A3)+                           | FCBCrPs = 0 (current position)
        MOVE.L  A2,(A3)+                        | FCBVPtr = VCB pointer
        MOVE.L  0x1C(A0),A4                     | get IOBuffer (for user's own buffer)
        MOVE.L  A4,D0                           | have a buffer?
        BEQ.B   FILEOPEN_NO_2                   | no ->
| set up user's own buffer as cache entry
        CLR.L   (A4)+                           | clear forward link
        CLR.L   (A4)+                           | clear backward link
        CLR     (A4)                            | clear flags
        BSET    #0x5,(A4)                       | mark as empty (CBHempty)
        ADDQ.W  #0x2,A4                         | skip past flags
FILEOPEN_NO_2:
        MOVE.L  A4,(A3)+                        | FCBBfAdr = own buffer ptr
        MOVE    D7,(A3)+                        | FCBFlPos = 0
        ADDQ.L  #0x4,A3                         | skip FCBClmpSize (already set)
        CLR.L   (A3)+                           | FCBBTCBptr = nil (no B-tree open)
| scan for other open forks of same file to adjust permissions
        BSET    #0x7,0x5(A2)                    | set volume modified flag (VCBFlags)
        MOVE    ioRefNum(A0),D4                 | this file's refnum
        BSR     HFSE_CONT_15                    | Gt1stMatch: find first matching FCB
FILEOPEN_FOUND:
        CMP     D1,D4                           | same as our refnum? (skip self)
        BEQ.B   FILEOPEN_SKIP                   | yes, skip ->
        MOVE.B  0x4(A1,D1.W),D5                 | get other FCB's flags (FCBMdRByt)
        MOVE.B  D5,D6                           | compare fork types
        EOR.B   D3,D6                           | XOR to check resource/data fork match
        LSR.B   #0x2,D6                         | fork bit in carry
        BCC.B   FILEOPEN_CONT_7                 | same fork type, adjust permissions ->
FILEOPEN_SKIP:
        BSR     HFSE_ERR_9                      | GtNxtMatch: find next matching FCB
        BEQ.B   FILEOPEN_FOUND                  | found another match ->
        BRA.B   FILEOPEN_FOUND_2                | no more matches ->
| found another FCB for same file: adjust EOF
FILEOPEN_CONT_7:
        JSR     P_AdjEof(PC)                    | AdjEOF: adjust EOF for other open forks
        MOVE.B  D5,0x4(A1,D1.W)                 | update other FCB's flags
FILEOPEN_FOUND_2:
        MOVEQ.L #0x0,D0                         | no error
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| P_Permssn Chk
|
| Called during boot.
P_PermssnChk:
        MOVE.L  (0x788).w,-(SP)                 | HFS vector: PermssnChk
        RTS                                     | return from P_PermssnChk

| ----------------------------------------------------------
|
| Permssn Chk
|
| Called during boot.
| PermssnChk: check file access permissions
PermssnChk:
        CMPI.B  #0x1,ioPermssn(A0)              | read-only requested? (fsCurPerm=1)
        BEQ.B   PERMSSNCHK_OK_2                 | yes, always allowed ->
        BSET    #0x8,D3                         | set write-permission flag
        BEQ.B   PERMSSNCHK_OK                   | was previously clear (first open) ->
| file already open with write permission
        TST.B   ioPermssn(A0)                   | shared access? (fsRdPerm=0)
        BEQ.B   PERMSSNCHK_OK_2                 | yes, downgrade to read-only ->
        CLR     ioRefNum(A0)                    | make refnum invalid
        MOVEQ.L #-0x36,D0                       | opWrErr: file already open for writing
        BRA.B   PERMSSNCHK_EXIT                 | exit ->
| first open with write permission
PERMSSNCHK_OK:
        BTst    #0x2,ioPermssn(A0)              | deny-read requested? (fsRdDenyPerm)
        BEQ.B   PERMSSNCHK_NO                   | no ->
        BSET    #0xC,D3                         | set deny-read flag
PERMSSNCHK_NO:
        BRA.B   PERMSSNCHK_CONT                 | go scan for conflicts ->
| read-only or downgraded access
PERMSSNCHK_OK_2:
        BClr    #0x8,D3                         | clear write-permission flag
        MOVEQ.L #0x0,D0                         | no error
PERMSSNCHK_EXIT:
        RTS                                     | exit PermssnChk
| FCBScan: check for permission conflicts with other open FCBs
PERMSSNCHK_CONT:
        BSR     HFSE_CONT_15                    | Gt1stMatch: find first matching FCB
PERMSSNCHK_CONT_2:
        BNE.B   PERMSSNCHK_FOUND                | no more matches ->
        MOVE    0x4(A1,D1.W),D0                 | get other FCB's flags (FCBMdRByt)
        EOR     D3,D0                           | compare file/fork bits
        ANDI    #0x300,D0                       | same file and fork type?
        BNE.B   PERMSSNCHK_NO_2                 | no, different fork ->
        BTST    #0xC,D3                         | deny-read requested?
        BEQ.B   PERMSSNCHK_NO_3                 | no ->
        BTST    #0x4,0x4(A1,D1.W)               | other FCB has write permission?
        BEQ.B   PERMSSNCHK_NO_3                 | no ->
PERMSSNCHK_NO_2:
        BSR     HFSE_ERR_9                      | GtNxtMatch: find next matching FCB
        BRA.B   PERMSSNCHK_CONT_2               | keep scanning
| conflict found: file already open
PERMSSNCHK_NO_3:
        MOVE    D1,ioRefNum(A0)                 | return conflicting refnum
        MOVEQ.L #-0x31,D0                       | fLckdErr: file locked or in use
        BRA.B   PERMSSNCHK_EXIT_2               | exit ->
| no conflicts
PERMSSNCHK_FOUND:
        MOVEQ.L #0x0,D0                         | no error
PERMSSNCHK_EXIT_2:
        RTS                                     | exit PermssnChk

| ----------------------------------------------------------
|
| Create Dir_hfs
|
CreateDir_hfs:
        BSR     FSQUEUE_SETUP                   | call helper
        BSET    #0x1,(HFSFlags).w               | set flag
        BRA.B   CREATE_CONT                     | ->

| Create -- _Create ($A008): FUNCTION Create (fileName: Str255; vRefNum: INTEGER; creator:
| ----------------------------------------------------------
|
| _Create ($A008)
|
Create:
        BSR     FSQUEUE_SETUP                   | call helper
        BCLR    #0x1,(HFSFlags).w               | clear flag
CREATE_CONT:
        BSR     P_FndFilName                    | call helper
        BNE.B   CREATE_ERR                      | error ->
        MOVEQ.L #-0x30,D0                       | dupFNErr (-48): duplicate file name
        BRA.B   CREATE_ERR_2                    | ->

| ----------------------------------------------------------
|
| CREATE_ERR
|
| Create/CreateDir: check if file already exists
CREATE_ERR:
        CMPI    #-0x2B,D0                       | FNFErr? (name not found = ok to create)
        BNE.B   CREATE_ERR_2                    | other error ->
        BSR     TFSVCBTst                       | TFS volume?
        BEQ.B   CREATECN                        | yes, TFS create ->
        BTST    #0x1,(HFSFlags).w               | CreateDir on MFS?
        BEQ     CREATE_NO_7                     | no, MFS file create ->
        MOVEQ.L #-0x7B,D0                       | DirNFErr: can't create dirs on MFS
        BRA.B   CREATE_ERR_2                    | ->

| ----------------------------------------------------------
|
| CREATECN
|
| CreateCN: create the catalog record
CREATECN:
        MOVE.B  0x1A(A0),D1                     | get file type from param block
        SWAP    D1                              | move to high word (for CNode type)
        MOVE.B  #0x2,D1                         | assume CMFilCN (file)
        BTST    #0x1,(HFSFlags).w               | CreateDir?
        BEQ.B   CREATE_NO                       | no ->
        MOVE.B  #0x1,D1                         | CMDirCN (directory)
CREATE_NO:
        MOVE.L  A0,-(A6)                        | save param block ptr
        BSR.B   PUSHCNAME                       | PushCName: save CName on A6 stack
        MOVE    D2,-(A6)                        | save VRefNum
        MOVE.L  D6,D0                           | parent DirID
        JSR     CMCreateCN(PC)                  | create catalog node
        MOVE    (A6)+,D2                        | restore VRefNum
        BSR.B   CREATE_CONT_2                   | PopCName: restore CName from A6 stack
        MOVE.L  (A6)+,A0                        | restore param block ptr
        TST     D0                              | check result
        BEQ.B   CREATE_OK                       | ok ->
        CMPI    #0x30,D0                        | CMnotfound? (parent dir not found)
        BNE.B   CREATE_ERR_2                    | no, other error ->
        MOVEQ.L #-0x78,D0                       | convert to dirNFErr
        BRA.B   CREATE_ERR_2                    | ->
CREATE_OK:
        BTst    #0x1,(HFSFlags).w               | was this CreateDir?
        BEQ.B   CREATE_NO_2                     | no ->
        MOVE.L  D1,ioDirID(A0)                  | return DirID (ioFDirIndex)
CREATE_NO_2:
        MOVEQ.L #0x0,D0                         | no error
CREATE_ERR_2:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| PUSHCNAME
|
| PushCName: save CName on A6 stack, return Pascal string in A0
| Called by: RENAME_OK_2, CREATE_NO, DELETE_SKIP, RENAME_NO_2, HFSCATMOVE_NO_2
PUSHCNAME:
        MOVEM.L D0/A1,-(SP)                     | save regs
        SUBA.L  A0,A0                           | A0 = nil (default)
        TST     D2                              | CName length
        BEQ.B   CREATE_NO_3                     | no name ->
| copy CName to A6 stack as Pascal string
        MOVE    D2,A0                           | A0 = name length (temp)
        ADDQ.W  #0x1,D2                         | include length byte
        BCLR    #0x0,D2                         | round up to even
        SUBA    D2,A6                           | allocate space on A6 stack
        MOVE    D2,-(SP)                        | save rounded size
        MOVE    A0,D2                           | D2 = name length
        MOVE.L  A4,A0                           | source = parsed CName
        MOVE.L  A6,A1                           | dest = A6 stack
        MOVEQ.L #0x0,D0                         | clear high word for BlockMove
        MOVE    D2,D0                           | byte count
        _BlockMove                              | copy name
        MOVE    D2,-(A6)                        | push name length
        MOVE    (SP)+,D2                        | restore rounded size
        MOVE.L  A6,A0                           | A0 = Pascal string on stack
        ADDQ.L  #0x1,A0                         | skip to length byte
CREATE_NO_3:
        MOVEM.L (SP)+,D0/A1                     | restore regs
        RTS                                     | exit PushCName

| ----------------------------------------------------------
|
| CREATE_CONT_2 - PopCName: restore CName from A6 stack
|
CREATE_CONT_2:
        TST     D2                              | was a name pushed?
        BEQ.B   CREATE_NO_4                     | no ->
        MOVE    (A6)+,-(SP)                     | pop name length
        ADDA    D2,A6                           | deallocate name buffer
        MOVE    (SP)+,D2                        | D2 = restored rounded size
CREATE_NO_4:
        RTS                                     | return from CREATE_NO_4

| ----------------------------------------------------------
|
| CREATE_NO_5
|
| Called during boot.
| MFSOpen: MFS file open path
CREATE_NO_5:
        MOVE.L  D1,A3                           | A3 = FCB pointer
        MOVE    (CkdDB).w,D7                    | D7 = write count for tag data
        MOVE    (A5),D3                         | get MFS file flags
        ANDI    #0x1FF,D3                       | mask to flag bits
        BTST    #0x8,D3                         | file locked?
        BEQ.B   CREATE_NO_6                     | no ->
        BSET    #0xD,D3                         | set FCB locked flag
CREATE_NO_6:
        MOVE.L  vcbClpSiz(A2),0x1E(A3)          | set clump size from VCB (FCBClmpSize)
| load fork info from MFS directory entry
        LEA.L   0x12(A5),A5                     | point to file number in MFS entry
        MOVE.L  (A5)+,D2                        | D2 = file number
        MOVE    (A5)+,D4                        | D4 = data fork start block
        MOVE.L  (A5)+,D5                        | D5 = data fork logical EOF
        MOVE.L  (A5)+,D6                        | D6 = data fork physical EOF
        TST.B   (RegRsrc).w                     | opening resource fork?
        BNE.B   CREATE_OK_2                     | no, data fork is what we want ->
        BSET    #0x9,D3                         | set resource fork flag
        MOVE    (A5)+,D4                        | D4 = rsrc fork start block
        MOVE.L  (A5)+,D5                        | D5 = rsrc fork logical EOF
        MOVE.L  (A5)+,D6                        | D6 = rsrc fork physical EOF
CREATE_OK_2:
        BSR     P_PermssnChk                    | PermssnChk: check access permissions
        BNE.B   CREATE_CONT_4                   | denied ->
        BRA     SETUPFCB                        | go set up FCB fields ->

| ----------------------------------------------------------
|
| CREATE_CONT_3
|
CREATE_CONT_3:
        CLR     ioRefNum(A0)                    | clear
CREATE_CONT_4:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| CREATE_NO_7
|
CREATE_NO_7:
        TST     D2                              | test
        BEQ.B   CREATE_OK_3                     | ok ->
        MOVE    D2,D0                           | D0 = name length
CREATE_ERR_3:
        SUBQ.W  #0x1,D0                         | scan backwards through name
        BLT.B   CREATE_CONT_5                   | negative ->
        CMPI.B  #0x3A,0x0(A4,D0.W)              | compare
        BNE.B   CREATE_ERR_3                    | error ->
CREATE_OK_3:
        MOVEQ.L #-0x25,D0                       | bdNamErr (-37): bad file name
CREATE_ERR_4:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| CREATE_CONT_5
|
| MFS Create: check write protect and find space in directory
CREATE_CONT_5:
        BSR     SETVOLINFO_HFS_CONT_3           | check write protect
        BNE.B   CREATE_ERR_4                    | write protected ->
        BSR.B   CREATE_CONT_8                   | find/make space in MFS directory
        BNE.B   CREATE_ERR_4                    | error ->
        MOVE    D5,D0                           | D0 = entry size to clear
        MOVE.L  A5,A1                           | A1 = entry position
| MFS Create: initialize new directory entry
CREATE_CONT_6:
        CLR     (A1)+                           | zero the entry
        SUBQ.W  #0x2,D0                         | decrement byte counter by word
        BHI.B   CREATE_CONT_6                   | keep zeroing
| fill in MFS directory entry fields
        BSET    #0x7,(A5)                       | set "in use" flag
        MOVE.B  0x1A(A0),0x1(A5)                | set file version (ioVersNum)
        MOVE.L  vcbNxtCNID(A2),0x12(A5)         | assign file number (VCBNxtCNID)
        ADDQ.L  #0x1,vcbNxtCNID(A2)             | bump next CNID
| set creation and modification dates
        LEA.L   0x2A(A5),A5                     | point to date fields
        MOVE.L  (Time).w,(A5)                   | creation date = now
        MOVE.L  (A5)+,(A5)+                     | modification date = creation date
| copy filename into entry
        MOVE.B  D2,(A5)+                        | set name length byte
        BEQ.B   CREATE_EMPTY                    | empty name ->
CREATE_LOOP:
        MOVE.B  (A4)+,(A5)+                     | copy name bytes
        SUBQ.B  #0x1,D2                         | decrement name length counter
        BHI.B   CREATE_LOOP                     | loop until all bytes copied
CREATE_EMPTY:
        BSR     MarkVCB                         | mark VCB dirty
        ADDQ.W  #0x1,vcbNmFls(A2)               | increment file count
        BSR.B   CREATE_CONT_7                   | MFS directory flush
        MOVEQ.L #0x0,D0                         | no error
        BRA.B   CREATE_ERR_4                    | ->

| ----------------------------------------------------------
|
| CREATE_CONT_7
|
| Called during boot.
| CREATE_CONT_7: MFS directory flush - flush the system control cache for this volume
CREATE_CONT_7:
        MOVE    vcbVRefNum(A2),D0               | volume refnum
        MOVE.L  (SysCtlCPtr).w,A1               | system control cache
        MOVEQ.L #0x0,D1                         | no FlushCache options
        JMP     P_mFlushCache(PC)               | tail-call FlushCache

| ----------------------------------------------------------
|
| CREATE_CONT_8
|
| CREATE_CONT_8: find space in MFS directory for a new entry
CREATE_CONT_8:
        MOVE.L  (SP)+,A3                        | A3 = return address (for JMP later)
        MOVEQ.L #0x34,D5                        | fixed entry fields (52 bytes)
        ADD     D2,D5                           | + name length = total entry size
        BCLR    #0x0,D5                         | round to even
        BSR     FILEWRITE_CONT_4                | read first directory block
        BRA.B   CREATE_CONT_9                   | ->
| scan directory blocks for free space
CREATE_NO_8:
        BSR     FILEWRITE_NEXT                  | read next directory block
CREATE_CONT_9:
        BNE.B   CREATE_ERR_5                    | error ->
        MOVEQ.L #0x0,D0                         | initial entry offset
CREATE_CONT_10:
        TST.B   0x0(A5,D0.W)                    | entry in use?
        BEQ.B   CREATE_FOUND                    | no, found free space ->
        BSR.B   CREATE_NEXT                     | call helper
        BCS.B   CREATE_CONT_10                  | unsigned less ->
| MFS Create: insert new entry in directory block
CREATE_FOUND:
        MOVE    D0,D4                           | D4 = insertion offset
        ADD     D5,D4                           | + entry size
        CMPI    #0x200,D4                       | fits in this block?
        BCC.B   CREATE_NO_8                     | no, need to expand ->
        JSR     MarkA5Block(PC)                 | mark directory block dirty
        LEA.L   0x0(A5,D0.W),A5                 | A5 = ptr to new entry position
        CLR.L   vcbDirIndex(A2)                 | invalidate directory index cache
        MOVEQ.L #0x0,D0                         | no error
CREATE_ERR_5:
        JMP     (A3)                            | return to caller

| ----------------------------------------------------------
|
| CREATE_NEXT: advance to next MFS directory entry
|
| Called during boot.
CREATE_NEXT:
        MOVEQ.L #0x0,D6                         | clear high bytes
        MOVE.B  0x32(A5,D0.W),D6                | name length of current entry
        ADD     D6,D0                           | + name length
        ADDI    #0x34,D0                        | + fixed fields = next entry offset
        BCLR    #0x0,D0                         | round to even
        CMPI    #0x1CC,D0                       | past usable area? (512-52=460=$1CC)
        RTS                                     | return (CS = more entries, CC = end)

| ----------------------------------------------------------
|
| CREATE_CONT_11
|
| CREATE_CONT_11: get WDCB array base and initial offset
CREATE_CONT_11:
        MOVE.L  (WDCBsPtr).w,A1                 | A1 = WDCB array
        MOVEQ.L #0x2,D1                         | D1 = 2 (offset past WDCB header)
        RTS                                     | return array base and offset

| ----------------------------------------------------------
|
| CREATE_SKIP: advance to next WDCB entry (16 bytes each)
|
| Called by: OPENWD_HFS_CONT_3, OPENWD_HFS_OK, GETWDINFO_HFS_NO, GETWDINFO_HFS_SKIP, CREATE_NEXT_2
CREATE_SKIP:
        ADDI    #0x10,D1                        | advance by WDCB size (16 bytes)
        CMP     (A1),D1                         | past end of array?
        RTS                                     | return (CS = more, CC = end)

| ----------------------------------------------------------
|
| CREATE_CONT_12: find first WDCB belonging to volume A2
|
CREATE_CONT_12:
        BSR.B   CREATE_CONT_11                  | get WDCB array base
CREATE_CONT_13:
        CMPA.L  0x0(A1,D1.W),A2                 | same volume? (WDVCBPtr)
        BEQ.B   CREATE_FOUND_2                  | yes, found ->
| CREATE_NEXT_2: advance to next WDCB and continue scanning
CREATE_NEXT_2:
        BSR.B   CREATE_SKIP                     | next WDCB
        BCS.B   CREATE_CONT_13                  | more entries ->
        MOVE    #0x0,CCR                        | clear Z: not found
CREATE_FOUND_2:
        RTS                                     | return (Z = found, NZ = not found)

| ----------------------------------------------------------
|
| CREATE_CONT_14
|
| CREATE_CONT_14: CkDirBusy - check if any files in directory D6 are open
CREATE_CONT_14:
        MOVEM.L D2/A1,-(SP)                     | save regs
        MOVE.L  0x6(A5),D2                      | D2 = DirID of directory being deleted
        BSR.B   CREATE_CONT_12                  | scan FCBs for files in this dir
CREATE_CONT_15:
        BNE.B   CREATE_ERR_6                    | error ->
        CMP.L   0x4(A1,D1.W),D2                 | compare
        BEQ.B   CREATE_OK_4                     | ok ->
        BSR.B   CREATE_NEXT_2                   | call helper
        BRA.B   CREATE_CONT_15                  | ->

| ----------------------------------------------------------
|
| CREATE_ERR_6
|
CREATE_ERR_6:
        MOVEQ.L #0x0,D0                         | noErr
CREATE_CONT_16:
        MOVEM.L (SP)+,D2/A1                     | restore regs
        RTS                                     | return from CREATE_CONT_16

| ----------------------------------------------------------
|
| CREATE_OK_4
|
CREATE_OK_4:
        MOVE    D1,ioRefNum(A0)                 | IOParam field
        MOVEQ.L #-0x2F,D0                       | fBsyErr (-47): file busy
        BRA.B   CREATE_CONT_16                  | ->

| ----------------------------------------------------------
|
| CREATE_OK_5
|
| CREATE_OK_5: CkFileBusy - check if file is open (has any FCBs)
CREATE_OK_5:
        MOVE.L  A1,-(SP)                        | save A1
        MOVE.L  0x14(A5),D2                     | TFS file number (filFlNum)
        BSR     TFSVCBTst                       | TFS volume?
        BEQ.B   CREATE_OK_6                     | yes ->
        MOVE.L  0x12(A5),D2                     | MFS file number
CREATE_OK_6:
        BSR     HFSE_CONT_15                    | Gt1stMatch: find FCB for this file
        BEQ.B   CREATE_FOUND_3                  | found: file is open ->
        MOVEQ.L #0x0,D0                         | not open: no error
CREATE_CONT_17:
        MOVE.L  (SP)+,A1                        | restore A1
        RTS                                     | exit CkFileBusy

| ----------------------------------------------------------
|
| CREATE_FOUND_3
|
CREATE_FOUND_3:
        MOVE    D1,ioRefNum(A0)                 | IOParam field
        MOVEQ.L #-0x2F,D0                       | fBsyErr (-47): file busy
        BRA.B   CREATE_CONT_17                  | ->

| ----------------------------------------------------------
|
| _Delete ($A009)
|
| _Delete ($A009)
Delete:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
        BSR     TFSVCBTst                       | TFS volume?
        BNE     HFSCATMOVE_NO_3                 | no, MFS Delete ->
| check if file is locked
        MOVEQ.L #-0x2D,D0                       | fLckdErr
        BTST    #0x0,0x2(A5)                    | file locked? (filFlags bit 0)
        BNE.B   DELETE_ERR                      | yes, can't delete ->
| determine record type: directory or file
        BCLR    #0x1,(HFSFlags).w               | clear CreateDir flag
        CMPI.B  #0x1,(A5)                       | directory record? (cdrDirRec)
        BNE.B   DELETE_NO                       | no ->
        BSET    #0x1,(HFSFlags).w               | set CreateDir flag (for delete)
        BSR.B   CREATE_CONT_14                  | CkFileBusy: check if any files open in dir
        BRA.B   DELETE_CONT                     | ->
| file record: check if file is open
DELETE_NO:
        CMPI.B  #0x2,(A5)                       | file record? (cdrFilRec)
        BNE.B   DELETE_SKIP                     | no (thread?), skip ->
        MOVE.L  D2,-(A6)                        | save VRefNum
        BSR.B   CREATE_OK_5                     | CkFileBusy: check if file is in use
        MOVE.L  (A6)+,D2                        | restore VRefNum
        TST     D0                              | file busy?
DELETE_CONT:
        BNE.B   DELETE_ERR                      | yes, can't delete ->
| deallocate file's disk space and delete catalog entry
DELETE_SKIP:
        BSR     PUSHCNAME                       | PushCName: save CName
        MOVE.L  D2,-(A6)                        | save VRefNum
        MOVE.L  D7,D2                           | catalog hint
        CMPI.B  #0x2,(A5)                       | file record?
        BNE.B   DELETE_NO_2                     | no, just delete catalog entry ->
| file: deallocate disk space first
        MOVE.L  0x14(A5),D0                     | file number (filFlNum)
        JSR     TrashFBlocks(PC)                | trash cached blocks for this file
        MOVE.L  D6,D0                           | parent DirID
        JSR     P_mDeallocFile(PC)              | deallocate all file extents
        BNE.B   DELETE_ERR                      | error ->
DELETE_NO_2:
        MOVE.L  D6,D0                           | parent DirID
        JSR     CMDeleteCN(PC)                  | delete catalog entry
        MOVE.L  (A6)+,D2                        | restore VRefNum
        BSR     CREATE_CONT_2                   | PopCName: restore CName
        CMPI    #0x32,D0                        | CMnotempty? (directory not empty)
        BNE.B   DELETE_ERR                      | no, other error ->
        MOVEQ.L #-0x2F,D0                       | fBsyErr: directory not empty
DELETE_ERR:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| _Rename ($A00B)
|
| _Rename ($A00B)
Rename:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE.L  0x1C(A0),D2                     | D2 = new name ptr (ioMisc)
        BSR     DTRMV1_CONT_7                   | DTRMV + FndFilName for source
        BNE     RENAME_ERR_5                    | error ->
| check if rename crosses volumes (HFS move-rename)
        TST     D2                              | new name specified?
        BEQ     RENAME_NO_3                     | no name, MFS rename ->
        MOVE.L  A2,A1                           | A1 = source VCB
        MOVE    D3,D7                           | D7 = source name length
        MOVEM.L D2/A4,(FSTemp8).w               | save new name info in temp
        BSR     DTRMV3                          | DTRMV3: determine dest volume
        BNE.B   RENAME_ERR_2                    | error ->
        CMPA.L  A1,A2                           | same volume?
        BEQ.B   RENAME_OK                       | yes ->
        TST     D7                              | source had a name?
        BEQ.B   RENAME_OK                       | no, allow cross-volume ->
RENAME_ERR:
        MOVEQ.L #-0x25,D0                       | FNFErr
RENAME_ERR_2:
        CMPI    #0x21,D0                        | BTexists?
        BNE.B   RENAME_NO                       | no ->
        MOVEQ.L #-0x30,D0                       | convert to dupFNErr
RENAME_NO:
        BRA     FSQUEUE_DONE                    | CmdDone
| TFS Rename: find source and dest on same volume
RENAME_OK:
        BSR     SETVOLINFO_HFS_CONT_3           | check write protect
        BNE.B   RENAME_ERR_2                    | write protected ->
        BSR     TFSVCBTst                       | TFS volume?
        BNE     HFSCATMOVE_NO_4                 | no, MFS Rename ->
| locate source file in catalog
        BSR     P_FndFilName                    | FndFilName: find source file
        BNE.B   RENAME_ERR_2                    | not found ->
        MOVEQ.L #-0x2D,D0                       | fLckdErr: assume locked
        BTST    #0x0,0x2(A5)                    | file locked? (filFlags bit 0)
        BNE.B   RENAME_ERR_2                    | yes, can't rename ->
        MOVE.L  D6,D4                           | D4 = source parent DirID
        MOVE.L  D7,D5                           | D5 = source catalog hint
| locate destination (new name) in catalog
        MOVEM.L D2/D4-D5/A4,-(A6)               | save regs
        MOVE.L  ioFileName(A0),-(A6)            | save original filename ptr
        MOVE.L  0x1C(A0),D2                     | get new name ptr (ioMisc)
        MOVE.L  D2,ioFileName(A0)               | temporarily set as filename
        BSR     P_FndFilName                    | FndFilName: look up new name
        MOVEM.L D2/A4,(FSTemp8).w               | save new name parse results
        MOVE.L  (A6)+,ioFileName(A0)            | restore original filename ptr
        MOVEM.L (A6)+,D2/D4-D5/A4               | restore regs
        TST     D0                              | test
        BNE.B   RENAME_ERR_3                    | error ->
| check if new name already exists (or is same file)
        MOVE.L  A0,-(SP)                        | save param block
        MOVEM.L D2/A4,-(A6)                     | save source name info
        MOVE    D2,D0                           | source name length (high word)
        MOVE.L  A4,A0                           | source name ptr
        SWAP    D0                              | put lengths in correct order for _CmpString
        MOVEM.L (FSTemp8).w,D2/A4               | get dest name info
        MOVE    D2,D0                           | dest name length (low word)
        MOVE.L  A4,A1                           | dest name ptr
        _CmpString                              | compare source and dest names
        MOVEM.L (A6)+,D2/A4                     | restore source name info
        MOVE.L  (SP)+,A0                        | restore param block
        BNE.B   RENAME_CONT                     | names differ ->
        CMP.L   D4,D6                           | same parent directory?
        BEQ.B   RENAME_OK_2                     | yes: case-only rename ->
RENAME_CONT:
        MOVEQ.L #-0x30,D0                       | dupFNErr (-48): duplicate file name
RENAME_ERR_3:
        CMPI    #-0x2B,D0                       | FNFErr? (dest not found = ok to rename)
  .short 0x6680                                 | BNE.B RENAME_ERR_2
        CMP.L   D4,D6                           | compare
        BNE     RENAME_ERR                      | error ->
| do the catalog rename
RENAME_OK_2:
        BSR     PUSHCNAME                       | PushCName: save source CName
        MOVE.L  D2,-(SP)                        | save source VRefNum
        MOVE.L  A0,A1                           | A1 = source CName
        MOVEM.L (FSTemp8).w,D2/A4               | get dest name info
        BSR     PUSHCNAME                       | PushCName: save dest CName
        MOVE.L  (SP)+,-(A6)                     | save source VRefNum on A6 stack
        MOVE.L  D2,-(A6)                        | save dest VRefNum on A6 stack
        EXG     A0,A1                           | A0=old CName, A1=new CName
        MOVE.L  D4,D0                           | parent DirID
        MOVE.L  D5,D2                           | catalog hint
        JSR     CMRenameCN(PC)                  | rename the catalog entry
        MOVE.L  D2,D7                           | D7 = new hint
        TST     D0                              | rename successful?
        BNE.B   RENAME_NO_2                     | no ->
| if renamed in root, update VCB volume name
        CMPI.L  #0x1,D4                         | root's parent? (FSRtParID=1)
        BEQ.B   RENAME_OK_3                     | yes, update volume name ->
        CMPI.L  #0x2,D4                         | root dir? (FSRtDirID=2)
        BNE.B   RENAME_NO_2                     | no ->
        TST.L   0x4(A6)                         | renamed from root? (check saved VRefNum)
        BGT.B   RENAME_NO_2                     | no ->
RENAME_OK_3:
        BSR     SETVOLINFO_HFS_CONT             | update VCB volume name
        MOVEQ.L #0x0,D0                         | clear error (rename succeeded)
        MOVEQ.L #0x1,D6                         | flag: volume name changed
RENAME_NO_2:
        MOVE.L  (A6)+,D2                        | restore dest VRefNum
        MOVE.L  (A6)+,-(SP)                     | restore source VRefNum
        BSR     CREATE_CONT_2                   | PopCName: restore dest CName
        MOVE.L  (SP)+,D2                        | restore source VRefNum
        BSR     CREATE_CONT_2                   | PopCName: restore source CName
        TST     D0                              | rename ok?
        BNE     RENAME_ERR_2                    | no ->
        CMPI.L  #0x1,D6                         | volume name changed?
        BEQ     RENAME_ERR_2                    | yes, done ->
| update FCBs for renamed file: new CName and catalog hint
        MOVEM.L (FSTemp8).w,D2/A4               | get dest name info
        BSR     PUSHCNAME                       | PushCName: save new name
        MOVE.L  D2,-(A6)                        | save VRefNum
        MOVE.L  D6,D0                           | dest parent DirID
        MOVE.L  D7,D2                           | catalog hint
        JSR     CMGetCN(PC)                     | look up renamed record
        MOVE.L  (A6)+,D2                        | restore VRefNum
        BSR     CREATE_CONT_2                   | PopCName: restore new name
        TST     D0                              | found?
        BNE     RENAME_ERR_2                    | no ->
| update all open FCBs for this file with new name
        MOVE.B  D2,D3                           | D3 = new name length
        MOVE.L  A1,A5                           | A5 = catalog data record
        MOVE.L  A4,A0                           | A0 = new CName ptr
        MOVE.L  0x14(A5),D2                     | file number (filFlNum)
        BSR     HFSE_CONT_15                    | Gt1stMatch: find FCB for this file
        BNE     RENAME_ERR_2                    | not open ->
RENAME_CONT_2:
        MOVE.L  D7,0x36(A1,D1.W)                | update catalog hint in FCB (FCBCatPos)
        LEA.L   0x3E(A1,D1.W),A1                | ptr to FCB CName (FCBCName)
        MOVE.B  D3,(A1)+                        | copy new name length
        MOVEQ.L #0x0,D0                         | clear high word for BlockMove
        MOVE.B  D3,D0                           | D0 = name length for _BlockMove
        _BlockMove                              | copy new name to FCB
        MOVE.L  (FCBSPtr).w,A1                  | FCB array
        BSR     HFSE_ERR_9                      | GtNxtMatch: find next FCB for same file
        BEQ.B   RENAME_CONT_2                   | update this one too ->
        MOVEQ.L #0x0,D0                         | no error
RENAME_ERR_4:
        BRA     RENAME_ERR_2                    | ->

| ----------------------------------------------------------
|
| RENAME_ERR_5
|
RENAME_ERR_5:
        CMPI    #-0x23,D0                       | compare
        BNE.B   RENAME_ERR_4                    | error ->
        TST     D2                              | test
        BNE     RENAME_ERR                      | error ->
| MFS Rename path: rename on MFS volume (including volume name)
RENAME_NO_3:
        TST     D3                              | new name given?
        BEQ.B   RENAME_ERR_4                    | no ->
        BSR     DTRMV3                          | determine destination volume
        BNE.B   RENAME_ERR_4                    | error ->
        BSR     SETVOLINFO_HFS_CONT_3           | check write protect
        BNE.B   RENAME_ERR_4                    | write protected ->
        TST     vcbDrvNum(A2)                   | volume online?
        BEQ.B   RENAME_ERR_4                    | no ->
| copy new name to VCB volume name
        MOVE.L  0x1C(A0),A1                     | A1 = new name string (ioMisc)
        BSR     SETVOLINFO_HFS_CONT             | update VCB volume name
| if TFS volume, also rename root directory in catalog
        BSR     TFSVCBTst                       | TFS volume?
        BNE     RENAME_ERR_2                    | no, done ->
        MOVEQ.L #0x0,D2                         | no hint
        MOVEQ.L #0x2,D0                         | root DirID (FSRtDirID)
        MOVE.L  D2,A0                           | no old CName (root has no name)
        LEA.L   vcbVN(A2),A1                    | new name = VCB volume name
        JSR     CMRenameCN(PC)                  | rename root directory
        BRA     RENAME_ERR_2                    | ->

| ----------------------------------------------------------
|
| hfs Cat Move
|
| _CatMove (HFS): move a file/directory to a different parent
hfsCatMove:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
| determine destination directory
        MOVE.L  ioFileName(A0),-(A6)            | save source filename
        MOVE.L  0x1C(A0),ioFileName(A0)         | temporarily use dest name (ioMisc)
        BSR     DTRMV3                          | DTRMV3: determine dest volume/dir
        MOVE.L  (A6)+,ioFileName(A0)            | restore source filename
| determine source directory
        MOVE.L  A2,A1                           | A1 = dest VCB
        MOVE    D3,D7                           | D7 = dest name length
        BSR     DTRMV3                          | DTRMV3: determine source volume/dir
        BNE.B   HFSCATMOVE_ERR_2                | error ->
        CMPA.L  A1,A2                           | same volume?
        BEQ.B   HFSCATMOVE_OK                   | yes ->
        TST     D7                              | dest had a name?
        BEQ.B   HFSCATMOVE_OK                   | no, allow ->
HFSCATMOVE_ERR:
        MOVEQ.L #-0x25,D0                       | FNFErr: cross-volume move not allowed
HFSCATMOVE_ERR_2:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| HFSCATMOVE_OK
|
| check write protect and find source file
HFSCATMOVE_OK:
        BSR     SETVOLINFO_HFS_CONT_3           | check write protect
        BNE.B   HFSCATMOVE_ERR_2                | write protected ->
        BSR     FNDFILNAME_CONT_4               | CkExtFS
        BNE.B   HFSCATMOVE_ERR_2                | external FS ->
        MOVEQ.L #-0x32,D0                       | CMnotempty (assumed error)
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   HFSCATMOVE_ERR_2                | no, can't CatMove on MFS ->
| find source file in catalog
        BSR     P_FndFilName                    | locate source by name
        BNE.B   HFSCATMOVE_ERR_2                | not found ->
        MOVEQ.L #0x0,D3                         | D3 = 0 (assume not file)
        CMPI.B  #0x2,(A5)                       | file record? (cdrFilRec)
        BNE.B   HFSCATMOVE_NO                   | no (directory) ->
        MOVE.L  0x14(A5),D3                     | D3 = file number (filFlNum)
| find destination directory
HFSCATMOVE_NO:
        MOVE.L  D6,D4                           | D4 = source parent DirID
        MOVE.L  D7,D5                           | D5 = source catalog hint
        MOVEM.L D2/A4,(FSTemp8).w               | save source name parse results
| temporarily swap to dest name for lookup
        MOVE.L  ioFileName(A0),-(A6)            | save source filename
        MOVE.L  ioDirID(A0),-(A6)               | save source DirID
        MOVE.L  ioNewName(A0),ioFileName(A0)    | set dest name (ioNewName)
        MOVE.L  ioNewDirID(A0),ioDirID(A0)      | set dest DirID (ioNewDirID)
        MOVEM.L D3-D5,-(A6)                     | save source info
        BSR     P_FndFilName                    | look up destination
        MOVEM.L (A6)+,D3-D5                     | restore source info
        MOVE.L  (A6)+,ioDirID(A0)               | restore source DirID
        MOVE.L  (A6)+,ioFileName(A0)            | restore source filename
        TST     D0                              | dest found?
        BEQ.B   HFSCATMOVE_OK_2                 | yes, same-name exists at dest ->
        CMPI    #-0x25,D0                       | FNFErr? (dest name not found = ok)
        BNE.B   HFSCATMOVE_ERR_2                | other error ->
        TST     D2                              | dest had a name component?
        BNE.B   HFSCATMOVE_ERR                  | yes: name not found at dest is error ->
        BRA.B   HFSCATMOVE_NO_2                 | no name: move to dest dir ->

| ----------------------------------------------------------
|
| HFSCATMOVE_OK_2
|
| hfsCatMove: check dest is a directory and get its DirID
HFSCATMOVE_OK_2:
        CMPI.B  #0x1,(A5)                       | directory record? (cdrDirRec)
        BNE.B   HFSCATMOVE_ERR                  | no, FNFErr ->
        MOVE.L  0x6(A5),D6                      | D6 = dest directory ID (dirDirID)
        MOVEQ.L #0x0,D7                         | D7 = 0 (no catalog hint)
| hfsCatMove: move a catalog entry to a different directory
HFSCATMOVE_NO_2:
        MOVEM.L (FSTemp8).w,D2/A4               | get dest name info
        CMP.L   D4,D6                           | same parent? (null move)
        BEQ.B   HFSCATMOVE_OK_4                 | yes, nothing to do ->
| call CMMoveCN to move the catalog entry
        BSR     PUSHCNAME                       | PushCName: save source CName
        MOVE.L  D2,-(A6)                        | save VRefNum
        MOVE.L  D3,-(A6)                        | save file number
        MOVE.L  D4,D0                           | source parent DirID
        MOVE.L  D5,D2                           | source catalog hint (actually not used - dest name ptr?)
        MOVE.L  D6,D1                           | dest parent DirID
        MOVE.L  D7,D3                           | dest catalog hint (actually not used)
        SUBA.L  A1,A1                           | no dest CName (keep same name)
        JSR     CMMoveCN(PC)                    | move the catalog entry
        MOVE.L  D2,D7                           | D7 = new hint
        MOVE.L  (A6)+,D3                        | restore file number
        MOVE.L  (A6)+,D2                        | restore VRefNum
        BSR     CREATE_CONT_2                   | PopCName: restore CName
        TST     D0                              | move ok?
        BEQ.B   HFSCATMOVE_OK_3                 | yes ->
        CMPI    #0x31,D0                        | CMexists?
        BNE.B   HFSCATMOVE_ERR_3                | no, other error ->
        MOVEQ.L #-0x30,D0                       | dupFNErr (-48): duplicate file name
HFSCATMOVE_ERR_3:
        BRA     HFSCATMOVE_ERR_2                | exit ->
| update open FCBs with new parent DirID and hint
HFSCATMOVE_OK_3:
        MOVE.L  D3,D2                           | D2 = file number for FCB scan
        BEQ.B   HFSCATMOVE_OK_4                 | no file number ->
        BSR     HFSE_CONT_15                    | Gt1stMatch: find FCB for this file
        BNE     HFSCATMOVE_OK_4                 | not open ->
HFSCATMOVE_CONT:
        MOVE.L  D7,0x36(A1,D1.W)                | update catalog hint (FCBCatPos)
        MOVE.L  D6,0x3A(A1,D1.W)                | update parent DirID (FCBDirID)
        BSR     HFSE_ERR_9                      | GtNxtMatch: find next FCB
        BEQ.B   HFSCATMOVE_CONT                 | update this one too ->
HFSCATMOVE_OK_4:
        MOVEQ.L #0x0,D0                         | no error
        BRA     HFSCATMOVE_ERR_2                | exit ->

| ----------------------------------------------------------
|
| HFSCATMOVE_NO_3
|
| MFS Delete path
HFSCATMOVE_NO_3:
        MOVEQ.L #-0x2D,D0                       | fLckdErr: assume locked
        BTST    #0x0,(A5)                       | file locked?
        BNE.B   HFSCATMOVE_OK_5                 | yes, can't delete ->
        BSR     CREATE_OK_5                     | CkFileBusy: is file in use?
        BNE.B   HFSCATMOVE_OK_5                 | yes, busy ->
| delete MFS file: deallocate blocks and remove directory entry
        SUBQ.W  #0x1,vcbNmFls(A2)               | decrement file count
        BSR     MarkVCB                         | mark VCB dirty
        MOVE    0x16(A5),D3                     | data fork start block
        BSR     LG2PHYS_CONT_10                 | MFSDealloc: free data fork blocks
        MOVE    0x20(A5),D3                     | rsrc fork start block
        BSR     LG2PHYS_CONT_10                 | MFSDealloc: free rsrc fork blocks
        MOVE.L  0x12(A5),D0                     | file number
        BSR.B   HFSCATMOVE_CONT_3               | MFSDeleteEntry: remove from directory
        JSR     TrashFBlocks(PC)                | trash cached blocks for this file
        BSR     CREATE_CONT_7                   | MFS directory flush
        MOVEQ.L #0x0,D0                         | no error
HFSCATMOVE_OK_5:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| HFSCATMOVE_CONT_2 - MFS: compute directory entry size from name length
|
HFSCATMOVE_CONT_2:
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  0x32(A5),D0                     | name length from entry
        ADDI    #0x34,D0                        | + fixed fields = total entry size
        BCLR    #0x0,D0                         | round down to even
        RTS                                     | return computed size in D0

| ----------------------------------------------------------
|
| HFSCATMOVE_CONT_3 - MFSDeleteEntry: remove entry by compressing directory
|
HFSCATMOVE_CONT_3:
        MOVEM.L D0/A0-A1/A5,-(SP)               | save regs
        MOVE.L  A1,A0                           | A0 = directory block (for MarkBlock)
        JSR     P_mMarkBlock(PC)                | mark directory block dirty
        CLR.L   vcbDirIndex(A2)                 | invalidate directory index cache
| compress directory: shift entries after deleted one
        MOVE.L  A5,A0                           | A0 = dest (deleted entry position)
        BSR.B   HFSCATMOVE_CONT_2               | get deleted entry's size
        ADDA.L  D0,A5                           | A5 = source (next entry after deleted)
        ADDA    #0x200,A1                       | A1 = end of directory block
HFSCATMOVE_CONT_4:
        CMPA.L  A1,A5                           | past end of block?
        BCC.B   HFSCATMOVE_DONE                 | yes, done ->
        MOVE    (A5)+,(A0)+                     | shift entry down
        BRA.B   HFSCATMOVE_CONT_4               | keep shifting

| ----------------------------------------------------------
|
| HFSCATMOVE_DONE
|
| clear remaining words in directory block
HFSCATMOVE_DONE:
        CLR     (A0)+                           | zero a word
        CMPA.L  A1,A0                           | past end of block?
        BCS.B   HFSCATMOVE_DONE                 | no, keep clearing
        MOVEM.L (SP)+,D0/A0-A1/A5               | restore regs
        RTS                                     | exit MFSDeleteEntry

| ----------------------------------------------------------
|
| HFSCATMOVE_NO_4
|
| MFS Rename: compare old and new names, then rename
HFSCATMOVE_NO_4:
        MOVE.L  A0,-(SP)                        | save param block
        MOVE    D2,D0                           | old name length (high word)
        MOVE.L  A4,A0                           | old name ptr
        MOVEM.L (FSTemp8).w,D2/A4               | get new name info
        SWAP    D0                              | set up for _CmpString
        MOVE    D2,D0                           | new name length (low word)
        MOVE.L  A4,A1                           | new name ptr
        _CmpString                              | compare old and new names
        MOVE.L  (SP)+,A0                        | restore param block
        BEQ.B   HFSCATMOVE_CONT_5               | same name (case-only rename) ->
| different name: check if new name already exists
        BSR     FNDFILNAME_NO_3                 | look up new name in MFS directory
        BNE.B   HFSCATMOVE_FOUND                | not found (good) ->
        MOVEQ.L #-0x30,D0                       | dupFNErr (-48): duplicate file name
HFSCATMOVE_FOUND:
        CMPI    #-0x2B,D0                       | FNFErr? (new name not found = ok)
        BNE.B   HFSCATMOVE_ERR_4                | other error ->
| do the rename
HFSCATMOVE_CONT_5:
        BSR     P_FndFilName                    | re-locate old file
        BNE.B   HFSCATMOVE_ERR_4                | error ->
        MOVEQ.L #-0x2D,D0                       | fLckdErr
        BTST    #0x0,(A5)                       | file locked?
        BNE.B   HFSCATMOVE_ERR_4                | yes ->
| save old directory entry on A6 stack
        MOVE.L  A6,A4                           | A4 = save point
        MOVE.L  A5,A3                           | A3 = old entry
        BSR.B   HFSCATMOVE_CONT_2               | get entry size
HFSCATMOVE_LOOP:
        MOVE    -0x2(A3,D0.W),-(A6)             | push entry data onto A6 stack
        SUBQ.W  #0x2,D0                         | decrement word counter
        BGT.B   HFSCATMOVE_LOOP                 | loop
| delete old entry and insert with new name
        BSR.B   HFSCATMOVE_CONT_3               | MFSDeleteEntry: remove old entry
        MOVE.L  (FSTemp8).w,D2                  | get new name info
        BSR     CREATE_CONT_8                   | MFS insert new directory entry
        BNE.B   HFSCATMOVE_ERR_5                | error ->
| copy saved entry data to new location
        MOVE.L  A5,A3                           | A3 = new entry location
        MOVEQ.L #0x18,D0                        | 24 bytes of file info to copy
| copy saved entry data back to new location
HFSCATMOVE_LOOP_2:
        MOVE    (A6)+,(A5)+                     | copy entry word
        DBF     D0,HFSCATMOVE_LOOP_2            | loop for all 25 words
        MOVE.L  A4,A6                           | restore A6 stack
        MOVEM.L (FSTemp8).w,D2/A4               | get new name info
        MOVE.B  D2,(A5)+                        | set new name length
| MFS Rename: copy new name bytes into directory entry
HFSCATMOVE_OK_6:
        MOVE.B  (A4)+,(A5)+                     | copy name byte
        SUBQ.W  #0x1,D2                         | more bytes?
        BGT.B   HFSCATMOVE_OK_6                 | yes ->
        BSR.B   HFSCATMOVE_CONT_6               | update directory entry header
        BSR     MarkVCBTime                     | mark VCB dirty with timestamp
        BSR     CREATE_CONT_7                   | MFS directory flush
        MOVEQ.L #0x0,D0                         | no error
HFSCATMOVE_ERR_4:
        BRA     FSQUEUE_DONE                    | CmdDone
| MFS Rename: entry moved - need to re-insert at new position
HFSCATMOVE_ERR_5:
        MOVE.B  0x32(A6),D2                     | name length from saved entry
        BSR     CREATE_CONT_8                   | find space for re-insertion
        BEQ.B   HFSCATMOVE_FOUND_2              | found space ->
        MOVE.L  A4,A6                           | restore A6
        MOVEQ.L #-0x3B,D0                       | DirFulErr: directory full
        BRA.B   HFSCATMOVE_ERR_4                | ->
| copy saved entry to new position
HFSCATMOVE_FOUND_2:
        MOVE.L  A5,A3                           | A3 = new entry position
HFSCATMOVE_NO_5:
        MOVE    (A6)+,(A5)+                     | copy entry word
        CMPA.L  A6,A4                           | past end of saved entry?
        BNE.B   HFSCATMOVE_NO_5                 | no, keep copying
        BSR.B   HFSCATMOVE_CONT_6               | update directory entry header
        MOVEQ.L #-0x21,D0                       | DirFulErr (tentative, may be cleared)
        BRA.B   HFSCATMOVE_ERR_4                | ->

| ----------------------------------------------------------
|
| HFSCATMOVE_CONT_6
|
| HFSCATMOVE_CONT_6: find all FCBs for this MFS file and update them
HFSCATMOVE_CONT_6:
        MOVE.L  0x12(A3),D2                     | file number from directory entry
        MOVE    (CkdDB).w,D0                    | current directory block
        BSR     HFSE_CONT_15                    | Gt1stMatch: find FCB for this file
        BNE.B   HFSCATMOVE_ERR_6                | error ->
HFSCATMOVE_OK_7:
        MOVE    D0,0x1C(A1,D1.W)                | update FCB start block
        BSR     HFSE_ERR_9                      | call helper
        BEQ.B   HFSCATMOVE_OK_7                 | ok ->
HFSCATMOVE_ERR_6:
        RTS                                     | return from HFSCATMOVE_ERR_6

| ----------------------------------------------------------
|
| _SetFilType ($A043)
|
| _SetFilType: set file type (MFS-only trap, fails on HFS)
SetFilType:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE.B  0x1A(A0),D1                     | save ioVersNum
        MOVE.B  0x1C(A0),0x1A(A0)               | temporarily put new type in ioVersNum
        BSR     P_FndFilName                    | FndFilName: find file by type
        MOVE.B  D1,0x1A(A0)                     | restore ioVersNum
        TST     D0                              | found?
        BNE.B   SETFILTYPE_NO                   | no ->
        BSR     TFSVCBTst                       | TFS volume?
        BEQ.B   SETFILTYPE_OK                   | yes, can't SetFilType on TFS ->
        MOVEQ.L #-0x30,D0                       | dupFNErr (-48): duplicate file name
SETFILTYPE_NO:
        CMPI    #-0x2B,D0                       | FNFErr? (no file with that type = ok)
        BNE.B   RSTFILLOCK_ERR                  | other error ->
        BSR     FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
        BSR     TFSVCBTst                       | TFS volume?
        BNE     GETFILEINFO_NO_5                | no, MFS SetFilType ->
SETFILTYPE_OK:
        MOVEQ.L #-0x32,D0                       | CMnotempty: not supported on TFS
        BRA.B   RSTFILLOCK_ERR                  | ->
| SetFilLock -- trap handler for _SetFilLock ($A041).
| _SetFilLock ($A041)
SetFilLock:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        ST.B    (FLckUnlck).w                   | flag: lock (not unlock)
        BRA.B   RSTFILLOCK_CONT                 | ->
| RstFilLock -- trap handler for _RstFilLock ($A042).
| _RstFilLock ($A042)
RstFilLock:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        CLR.B   (FLckUnlck).w                   | flag: unlock
| SetFilLock/RstFilLock: TFS path
RSTFILLOCK_CONT:
        BSR     FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
        BSR     TFSVCBTst                       | TFS volume?
        BNE     GETFILEINFO_NO_6                | no, MFS path ->
        MOVEQ.L #-0x2B,D0                       | FNFErr
        CMPI.B  #0x2,(A5)                       | file record? (cdrFilRec)
        BNE.B   RSTFILLOCK_ERR                  | no ->
        TST.B   (FLckUnlck).w                   | lock or unlock?
        BEQ.B   RSTFILLOCK_CONT_2               | unlock ->
        BSET    #0x0,0x2(A5)                    | set file lock bit (filFlags bit 0)
        BNE.B   RSTFILLOCK_OK                   | was already locked ->
        BRA.B   RSTFILLOCK_CONT_3               | go update catalog ->

| ----------------------------------------------------------
|
| RSTFILLOCK_CONT_2
|
RSTFILLOCK_CONT_2:
        BClr    #0x0,0x2(A5)                    | clear flag
        BEQ.B   RSTFILLOCK_OK                   | ok ->
RSTFILLOCK_CONT_3:
        MOVE.L  D7,D2                           | D2 = catalog hint
        JSR     CMUpdateCN(PC)                  | call helper
        BRA.B   RSTFILLOCK_ERR                  | ->

| ----------------------------------------------------------
|
| RSTFILLOCK_OK
|
RSTFILLOCK_OK:
        MOVEQ.L #0x0,D0                         | noErr
RSTFILLOCK_ERR:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| _SetFileInfo ($A00D)
|
| _SetFileInfo ($A00D)
SetFileInfo:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName: locate file, check write protect
        BSR     TFSVCBTst                       | TFS volume?
        BNE     GETFILEINFO_NO_7                | no, MFS SetFileInfo ->
        MOVEQ.L #-0x2B,D0                       | FNFErr: assume not found
        CMPI.B  #0x2,(A5)                       | file record? (cdrFilRec)
        BNE.B   RSTFILLOCK_ERR                  | no ->
| copy Finder info from param block to catalog record
        MOVEM.L 0x20(A0),D1-D4                  | get ioFlFndrInfo (16 bytes)
        MOVEM.L D1-D4,0x4(A5)                   | store in filUsrWds
        MOVEM.L 0x48(A0),D1-D2                  | get ioFlCrDat + ioFlMdDat
        MOVEM.L D1-D2,0x2C(A5)                  | store in filCrDat + filMdDat
        BRA.B   RSTFILLOCK_CONT_3               | go update catalog ->

| ----------------------------------------------------------
|
| File File TF Set Cat Info_hfs
|
| _SetCatInfo (HFS): set file or directory info
FileFileTFSetCatInfo_hfs:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
        BSR     TFSVCBTst                       | TFS volume?
        BNE     GETFILEINFO_NO_7                | no, MFS ->
| file record: copy all Finder info + dates
        CMPI.B  #0x2,(A5)                       | file record? (cdrFilRec)
        BNE.B   FILEFILETFSETCATINFO_HFS_NO     | no, try directory ->
        MOVEM.L 0x20(A0),D0-D3                  | ioFlFndrInfo (16 bytes)
        MOVEM.L D0-D3,0x4(A5)                   | -> filUsrWds
        MOVEM.L 0x54(A0),D0-D3                  | ioFlXFndrInfo (16 bytes)
        MOVEM.L D0-D3,0x38(A5)                  | -> filFndrInfo
        MOVEM.L 0x48(A0),D0-D1                  | ioFlCrDat + ioFlMdDat
        MOVEM.L D0-D1,0x2C(A5)                  | -> filCrDat + filMdDat
        MOVE.L  0x50(A0),0x34(A5)               | ioFlBkDat -> filBkDat
        BRA.B   FILEFILETFSETCATINFO_HFS_CONT   | ->
| directory record: copy directory info + dates
FILEFILETFSETCATINFO_HFS_NO:
        MOVEQ.L #-0x25,D0                       | FNFErr
        CMPI.B  #0x1,(A5)                       | directory record? (cdrDirRec)
        BNE.B   FILEFILETFSETCATINFO_HFS_ERR    | no, error ->
        MOVEM.L 0x20(A0),D1-D4                  | ioFlFndrInfo (16 bytes) -> dirUsrInfo
        MOVEM.L D1-D4,0x16(A5)                  | store into catalog directory record
        MOVEM.L 0x54(A0),D0-D3                  | ioFlXFndrInfo -> dirFndrInfo
        MOVEM.L D0-D3,0x26(A5)                  | store into catalog directory record
        MOVEM.L 0x48(A0),D0-D2                  | dates (CrDat/MdDat/BkDat)
        MOVEM.L D0-D2,0xA(A5)                   | -> dirCrDat/dirMdDat/dirBkDat
FILEFILETFSETCATINFO_HFS_CONT:
        MOVEQ.L #0x0,D0                         | no error
FILEFILETFSETCATINFO_HFS_ERR:
        BRA     RSTFILLOCK_CONT_3               | go update catalog

| ----------------------------------------------------------
|
| FILEFILETFSETCATINFO_HFS_CONT_2: find file and check write protect (shared by Set calls)
|
| Called by: Delete, SETFILTYPE_NO, RSTFILLOCK_CONT, SetFileInfo, FileFileTFSetCatInfo_hfs
FILEFILETFSETCATINFO_HFS_CONT_2:
        MOVE.L  (SP)+,-(A6)                     | save return address
        BSR.B   P_FndFilName                    | FndFilName: locate file by name
        BNE.B   FILEFILETFSETCATINFO_HFS_ERR_2  | error ->
        BSR     SETVOLINFO_HFS_CONT_3           | check volume write protect
        BNE.B   FILEFILETFSETCATINFO_HFS_ERR_2  | write protected ->
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | return from FILEFILETFSETCATINFO_HFS_CONT_2
FILEFILETFSETCATINFO_HFS_ERR_2:
        ADDQ.W  #0x4,A6                         | pop caller's return address
        BRA     FSQUEUE_DONE                    | CmdDone with error

| ----------------------------------------------------------
|
| P_Fnd Fil Name
|
| Called during boot.
P_FndFilName:
        MOVE.L  (0x78C).w,-(SP)                 | HFS vector: FndFilName
        RTS                                     | return from P_FndFilName

| ----------------------------------------------------------
|
| Fnd Fil Name
|
| Called during boot.
FndFilName:
        BSR     DTRMV3                          | call helper
        BEQ.B   FNDFILNAME_OK                   | ok ->
FNDFILNAME_CONT:
        RTS                                     | return from FNDFILNAME_CONT

| ----------------------------------------------------------
|
| FNDFILNAME_OK
|
| Called during boot.
| FndFilName common entry: get DirID from WDCB and check for DirID override
FNDFILNAME_OK:
        MOVEQ.L #0x2,D6                         | default to root DirID (FSRtDirID)
        MOVE.L  A3,D7                           | have a WDCB?
        BEQ.B   FNDFILNAME_NO                   | no ->
        MOVE.L  0x4(A3),D6                      | D6 = DirID from WDCB (WDDirID)
        MOVE.L  WDCatHint(A3),D7                | D7 = catalog hint (WDCatHint)
FNDFILNAME_NO:
| check if caller provided a pathname with content
        MOVE.L  A4,D0                           | A4 = parsed pathname position
        BEQ.B   FNDFILNAME_NO_2                 | no pathname ->
        SUB.L   ioFileName(A0),D0               | offset from start of string
        SUBQ.L  #0x2,D0                         | subtract header
        BGT.B   FNDFILNAME_NO_3                 | has filename component ->
FNDFILNAME_NO_2:
| check for HFS DirID override
        BTst    #0x9,0x6(A0)                    | HFS call? (HFSBit 9 of ioTrap: ioDirID valid)
        BEQ.B   FNDFILNAME_NO_3                 | no ->
        MOVE.L  ioDirID(A0),D0                  | caller-supplied DirID?
        BEQ.B   FNDFILNAME_NO_3                 | no ->
        MOVE.L  D0,D6                           | D6 = DirID
        MOVEQ.L #0x0,D7                         | D7 = 0: no catalog hint
| FNDFILNAME_NO_3: MFS FndFilName - look up file in MFS directory
FNDFILNAME_NO_3:
        BSR     FNDFILNAME_CONT_4               | CkExtFS
        BNE.B   FNDFILNAME_CONT                 | external FS ->
        BSR     TFSVCBTst                       | TFS volume?
        BNE     GETFILEINFO_NO_8                | no, do MFS name search ->
| TFS: use catalog instead (fall through to TFS FndFilName)
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1/A0-A1,-(A6)                  | save regs
        MOVE.L  D2,D1                           | D1 = name length
        MOVE.L  D2,D4                           | D4 = name length (for later)
FNDFILNAME_NEXT:
        MOVEQ.L #-0x78,D0                       | dirNFErr
        MOVEQ.L #0x0,D1                         | clear name length
| TFS FndFilName: parse pathname component by component
FNDFILNAME_CONT_2:
        MOVEQ.L #0x0,D3                         | D3 = 0 (no directory prefix flag)
        CMP     D4,D1                           | past end of pathname?
        BGE.B   FNDFILNAME_OK_3                 | yes, use what we have ->
        CMPI.B  #0x3A,0x0(A4,D1.W)              | colon separator?
        BEQ.B   FNDFILNAME_OK_2                 | yes, end of this component ->
        CMPI    #0x1F,D1                        | name too long? (max 31 chars)
        BLT.B   FNDFILNAME_NO_4                 | no ->
        MOVEQ.L #-0x25,D0                       | FNFErr: name too long
        BRA     FNDFILNAME_EXIT                 | exit ->

| ----------------------------------------------------------
|
| FNDFILNAME_NO_4
|
FNDFILNAME_NO_4:
        ADDQ.W  #0x1,D1                         | advance past separator
        BRA.B   FNDFILNAME_CONT_2               | ->

| ----------------------------------------------------------
|
| FNDFILNAME_OK_2
|
| found colon: this component is a directory prefix
FNDFILNAME_OK_2:
        BSet    #0x5,(HFSFlags).w               | set HFS pathname flag
        TST     D1                              | was colon at position 0? (leading colon)
        SEQ.B   D3                              | D3 = $FF if leading colon (relative path)
        SWAP    D3                              | save flag in high word
        MOVE    D4,D3                           | remaining pathname length
        SUB     D1,D3                           | - component length
        SUBQ.W  #0x1,D3                         | - colon itself
        BGT.B   FNDFILNAME_CONT_3               | more components ->
FNDFILNAME_OK_3:
        MOVEQ.L #-0x2B,D0                       | FNFErr (no filename after directories)
| FNDFILNAME_CONT_3: parse pathname component and look up in catalog (FndFilName helper)
FNDFILNAME_CONT_3:
        SWAP    D3                              | get flags in low word
        MOVEM.L D6-D7,-(A6)                     | save DirID and hint
| copy current pathname component to A6 stack as Pascal string
        MOVEM.L D0/A1,-(SP)                     | save regs
        MOVE.L  D1,A0                           | A0 = component length
        ADDQ.W  #0x1,D1                         | include length byte
        LSR     #0x1,D1                         | round up to word boundary
        LSL     #0x1,D1                         | restore to even byte count
        SUBA.L  D1,A6                           | allocate space on A6 stack
        MOVE.L  D1,-(SP)                        | save rounded size
        MOVE.L  A0,D1                           | D1 = component length
        MOVE.L  A4,A0                           | source = pathname component
        MOVE.L  A6,A1                           | dest = A6 stack buffer
        MOVE.L  D1,D0                           | byte count
        _BlockMove                              | copy component
        MOVE    D1,-(A6)                        | save component length
        MOVE.L  (SP)+,D1                        | restore rounded size
        MOVE.L  A6,A0                           | A0 = Pascal string on stack
        ADDQ.L  #0x1,A0                         | skip past length word to length byte
        MOVEM.L (SP)+,D0/A1                     | restore regs
| look up this pathname component in the catalog
        EXG     D6,D0                           | D0 = parent DirID, D6 = saved result
        MOVE.L  D7,D2                           | catalog hint
        JSR     CMGetCN(PC)                     | look up component in catalog
| deallocate stack buffer
        MOVE    (A6)+,-(SP)                     | pop saved length
        ADDA.L  D1,A6                           | deallocate name buffer
        MOVEQ.L #0x0,D1                         | clear high word
        MOVE    (SP)+,D1                        | restore component length
        TST     D0                              | lookup successful?
        BNE.B   FNDFILNAME_ERR                  | no ->
| if pathname had a directory prefix, follow thread to get actual directory
        TST.B   D3                              | had a directory prefix?
        BEQ.B   FNDFILNAME_NO_5                 | no ->
        MOVEQ.L #-0x78,D0                       | dirNFErr
        CMPI.L  #0x1,0x2(A0)                    | at root's parent? (ckrParID = FSRtParID)

        BEQ.B   FNDFILNAME_ERR                  | yes, can't go higher ->
        MOVE.L  0x2(A0),D0                      | get parent DirID from catalog key
        MOVEQ.L #0x0,D2                         | no hint
        SUBA.L  A0,A0                           | no CName (thread lookup)
        JSR     CMGetCN(PC)                     | look up parent directory
        BNE.B   FNDFILNAME_ERR                  | error ->
        MOVE.L  0x2(A0),D0                      | parent DirID from result
        MOVEQ.L #0x0,D2                         | no hint
| check result of directory/thread lookup
FNDFILNAME_NO_5:
        CMPI    #-0x2B,D6                       | was lookup error FNFErr?
        BEQ.B   FNDFILNAME_OK_4                 | yes, component is the filename ->
| component was a directory: advance to next component
        MOVEM.L (A6)+,D6-D7                     | restore saved DirID/hint
        MOVE.L  0x6(A1),D6                      | D6 = DirID of found directory
        MOVE.L  D2,D7                           | D7 = new catalog hint
        ADDQ.W  #0x1,D1                         | skip past colon separator
        ADDA.L  D1,A4                           | advance pathname pointer
        SUB     D1,D4                           | decrease remaining length
        BRA     FNDFILNAME_NEXT                 | parse next component

| ----------------------------------------------------------
|
| FNDFILNAME_OK_4
|
| TFS FndFilName: found the file/directory
FNDFILNAME_OK_4:
        MOVEQ.L #0x0,D0                         | no error
        MOVE.L  A1,A5                           | A5 = catalog data record
        MOVE.L  D2,0x4(A6)                      | save catalog hint on A6 stack
        BRA.B   FNDFILNAME_ERR_2                | ->
| TFS FndFilName: catalog lookup error
FNDFILNAME_ERR:
        CMPI    #0x30,D0                        | CMnotfound?
        BNE.B   FNDFILNAME_ERR_2                | no, other error ->
        MOVE.L  D6,D0                           | use saved error code
| TFS FndFilName exit
FNDFILNAME_ERR_2:
        MOVEM.L (A6)+,D6-D7                     | restore DirID/hint
        MOVE.L  D1,D2                           | D2 = name length
FNDFILNAME_EXIT:
        MOVEM.L (A6)+,D1/A0-A1                  | restore regs
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit FndFilName

| ----------------------------------------------------------
|
| FNDFILNAME_CONT_4
|
| Called during boot.
| FNDFILNAME_CONT_4: check for external FS and dispatch if so
FNDFILNAME_CONT_4:
        BSR     CKExtFS                         | check external FS
        BNE.B   FNDFILNAME_ERR_3                | external FS, dispatch ->
        TST     vcbDrvNum(A2)                   | test
        BNE.B   FNDFILNAME_ERR_3                | error ->
        MOVEQ.L #-0x35,D0                       | volOffLinErr (-53): volume off line
FNDFILNAME_ERR_3:
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        TST     D0                              | test
        RTS                                     | return from FNDFILNAME_ERR_3

| ----------------------------------------------------------
|
| Get Cat Info_hfs
|
GetCatInfo_hfs:
        BSR     FSQUEUE_SETUP                   | call helper
        BSET    #0x0,(HFSFlags).w               | set flag
        TST     0x1C(A0)                        | test
        BMI.B   GETFILEINFO_CONT                | negative ->
        BRA.B   GETFILEINFO                     | ->

| ----------------------------------------------------------
|
| _GetFileInfo ($A00C)
|
| Called during boot.
GetFileInfo:
        BSR     FSQUEUE_SETUP                   | call helper
        BCLR    #0x0,(HFSFlags).w               | clear flag
| GetFileInfo: lookup by name or use ioFDirIndex
GETFILEINFO:
        MOVE    0x1C(A0),D1                     | D1 = ioFDirIndex
        BGT.B   GETFILEINFO_CONT_2              | positive: index by position ->
        BSR     P_FndFilName                    | FndFilName: look up by name
        BEQ.B   GETFILEINFO_FOUND               | found ->
        CMPI    #-0x25,D0                       | FNFErr?
        BNE     GETFILEINFO_ERR_2               | other error ->
        TST.B   D2                              | had a name component?
        BNE     GETFILEINFO_ERR_2               | yes, real error ->
        BRA.B   GETFILEINFO_EXIT                | no name: return root info ->
| found file: check TFS or MFS
GETFILEINFO_FOUND:
        BSR     TFSVCBTst                       | TFS volume?
        BNE     GETFILEINFO_NO_10               | no, MFS GetFileInfo ->
        MOVE.L  D6,D1                           | D1 = parent DirID
        MOVEQ.L #0x0,D0                         | D0 = 0: clears vcbDirIndex (no indexed position)
        MOVE    D0,vcbDirIndex(A2)              | VCB field
        BRA     GETFILEINFO_NO_4                | ->

| ----------------------------------------------------------
|
| GETFILEINFO_CONT
|
GETFILEINFO_CONT:
        MOVEQ.L #0x0,D1                         | D1 = 0
GETFILEINFO_CONT_2:
        BSet    #0x5,(HFSFlags).w               | set flag
| GetFileInfo/GetCatInfo common setup
        BSR     P_DTRMV1                        | DTRMV1: determine volume from VRefNum
        BNE     GETFILEINFO_ERR_2               | error ->
        BSR.B   FNDFILNAME_CONT_4               | CkExtFS: check external FS
        BNE     GETFILEINFO_ERR_2               | external FS ->
| determine parent DirID from WDCB
        MOVEQ.L #0x2,D6                         | default to root DirID (FSRtDirID)
        MOVE.L  A3,D7                           | have a WDCB?
        BEQ.B   GETFILEINFO_NO                  | no ->
        MOVE.L  0x4(A3),D6                      | D6 = DirID from WDCB (WDDirID)
        MOVE.L  WDCatHint(A3),D7                | D7 = catalog hint (WDCatHint)
GETFILEINFO_NO:
| check if caller specified a DirID directly
        BTst    #0x9,0x6(A0)                    | HFS call? (HFSBit 9 of ioTrap: ioDirID valid)
        BEQ.B   GETFILEINFO_NO_2                | no ->
        TST.L   ioDirID(A0)                     | caller-supplied DirID?
        BEQ.B   GETFILEINFO_NO_2                | no ->
        MOVE.L  ioDirID(A0),D6                  | D6 = caller's DirID
        MOVEQ.L #0x0,D7                         | no hint
GETFILEINFO_NO_2:
        BSR     TFSVCBTst                       | TFS volume?
        BEQ.B   GETFILEINFO_OK                  | yes ->
| MFS GetFileInfo: only supports root directory
        MOVEQ.L #-0x78,D0                       | dirNFErr
        CMPI.L  #0x2,D6                         | root directory?
        BNE     GETFILEINFO_ERR_2               | no, MFS has no subdirectories ->
        TST     D1                              | index > 0? (ioFDirIndex)
        BGT     GETFILEINFO_OK_10               | yes, MFS indexed GetFileInfo ->
| MFS root directory info (synthetic)
GETFILEINFO_EXIT:
        LEA.L   ioFlAttrib(A0),A1               | clear return area
        MOVEQ.L #0x26,D0                        | 39 words to clear
GETFILEINFO_LOOP:
        CLR     (A1)+                           | zero a word
        DBF     D0,GETFILEINFO_LOOP             | loop until return area cleared
        BSET    #0x4,ioFlAttrib(A0)             | set directory bit
        MOVE.L  #0x2,ioFFlNum(A0)               | DirID = root (FSRtDirID)

        MOVE.L  #0x1,0x64(A0)                   | parent DirID = 1 (FSRtParID)

        MOVE    vcbNmFls(A2),0x34(A0)           | ioFlStBlk = root file count (VCBNmFls)
        MOVE.L  vcbCrDate(A2),0x48(A0)          | ioFlCrDat = volume creation date
        MOVE.L  vcbLsBkUp(A2),0x4C(A0)          | ioFlBkDat = last backup date
| copy volume name to caller's buffer
        MOVE.L  ioFileName(A0),D0               | filename buffer pointer
        BEQ.B   GETFILEINFO_SKIP                | no buffer ->
        TST     0x1C(A0)                        | ioFDirIndex set?
        BEQ.B   GETFILEINFO_SKIP                | no, skip name copy ->
        MOVE.L  D0,A1                           | A1 = dest
        LEA.L   vcbVN(A2),A0                    | A0 = volume name
        MOVEQ.L #0x1,D0                         | include length byte
        ADD.B   (A0),D0                         | + name length
        _BlockMove                              | copy volume name
GETFILEINFO_SKIP:
        MOVEQ.L #0x0,D0                         | no error
        BRA     GETFILEINFO_ERR_2               | exit ->

| ----------------------------------------------------------
|
| GETFILEINFO_OK
|
| TFS GetFileInfo/GetCatInfo path
GETFILEINFO_OK:
        MOVEQ.L #0x1,D0                         | FSRtParID (parent of root = 1)
        CMP.L   D0,D6                           | trying to get root's parent?
        BEQ.B   GETFILEINFO_SKIP_2              | yes, not supported ->
| index == 0: get by name (thread lookup)
        TST     D1                              | ioFDirIndex
        BNE.B   GETFILEINFO_CONT_3              | nonzero: index by position ->
        MOVEM.L A0-A1,-(A6)                     | save param block
        MOVE.L  D6,D0                           | DirID
        MOVE.L  D7,D2                           | catalog hint
        SUBA.L  A0,A0                           | no CName (thread lookup)
        JSR     CMGetCN(PC)                     | get catalog record by DirID
        BNE.B   GETFILEINFO_ERR                 | error ->
        MOVE.L  D2,D7                           | save updated hint
        BRA.B   GETFILEINFO_CONT_5              | go format result ->
| index > 0: get Nth offspring of directory
GETFILEINFO_CONT_3:
        BTst    #0x0,(HFSFlags).w               | MFS compatibility mode?
        BNE.B   GETFILEINFO_OK_2                | yes, different path ->
        MOVE    D1,D5                           | D5 = requested offspring index
| check if we can resume from cached position
        MOVE    0xB0(A2),D1                     | VCBOffsM: cached offspring index
        CMP.L   0xAC(A2),D6                     | same DirID as cached? (VCBDirIDM)
        BNE.B   GETFILEINFO_NO_3                | no, start from beginning ->
        CMP     vcbDirIndex(A2),D5              | requested index >= cached?
        BCS.B   GETFILEINFO_NO_3                | no, can't resume ->
        MOVE    vcbDirIndex(A2),D0              | resume from cached position
        MOVE    D5,vcbDirIndex(A2)              | update cached index
        SUB     D0,D5                           | D5 = relative offset from cache
        BRA.B   GETFILEINFO_CONT_4              | ->
| start enumeration from beginning of directory
GETFILEINFO_NO_3:
        MOVEQ.L #0x1,D1                         | start from offspring 1
        MOVE    D5,vcbDirIndex(A2)              | cache the requested index
        SUBQ.W  #0x1,D5                         | D5 = relative offset (0-based)
GETFILEINFO_CONT_4:
        MOVEM.L A0-A1,-(A6)                     | save param block
GETFILEINFO_LOOP_2:
        MOVE.L  D6,D0                           | DirID
        MOVE.L  D7,D2                           | catalog hint
        SUBA.L  A0,A0                           | no CName
        JSR     CMGetOff(PC)                    | get Nth offspring record
        BNE.B   GETFILEINFO_ERR                 | error ->
        MOVE.L  D2,D7                           | D7 = catalog hint
        ADDQ.W  #0x1,D1                         | bump offspring index
        CMPI.B  #0x2,(A1)                       | compare
        BNE.B   GETFILEINFO_LOOP_2              | error ->
        DBF     D5,GETFILEINFO_LOOP_2           | loop for Nth offspring
        BRA.B   GETFILEINFO_CONT_5              | got the record ->
| catalog error exit
GETFILEINFO_ERR:
        MOVEM.L (A6)+,A0-A1                     | restore param block
        CMPI    #0x30,D0                        | CMnotfound?
        BNE.B   GETFILEINFO_ERR_2               | no, other error ->
GETFILEINFO_SKIP_2:
        MOVEQ.L #-0x2B,D0                       | FNFErr: file not found
GETFILEINFO_ERR_2:
        BRA     FSQUEUE_DONE                    | CmdDone
| MFS compatibility mode: get offspring directly
GETFILEINFO_OK_2:
        MOVEM.L A0-A1,-(A6)                     | save param block
        MOVE.L  D6,D0                           | DirID
        MOVE.L  D7,D2                           | hint
        SUBA.L  A0,A0                           | no CName
        JSR     CMGetOff(PC)                    | get offspring record
        BNE.B   GETFILEINFO_ERR                 | error ->
| GETFILEINFO_CONT_5: format result from catalog record into param block
GETFILEINFO_CONT_5:
        LEA.L   0x6(A0),A3                      | A3 = ptr to CName in catalog key (ckrCName)
        MOVE.L  0x2(A0),D1                      | D1 = parent DirID (ckrParID)
        MOVE.L  A1,A5                           | A5 = catalog data record
        MOVEM.L (A6)+,A0-A1                     | restore param block
| copy filename to caller's buffer
        MOVE.L  ioFileName(A0),D0               | filename buffer pointer
        BEQ.B   GETFILEINFO_NO_4                | no buffer ->
        MOVE.L  D0,A4                           | A4 = dest
        MOVE.B  (A3),D0                         | name length
GETFILEINFO_LOOP_3:
        MOVE.B  (A3)+,(A4)+                     | copy name (including length byte)
        SUBQ.B  #0x1,D0                         | decrement name byte counter
        BCC.B   GETFILEINFO_LOOP_3              | loop until all bytes copied
GETFILEINFO_NO_4:
| check record type: file or directory?
        BTst    #0x0,(HFSFlags).w               | MFS mode?
        BNE.B   GETFILEINFO_OK_6                | yes, MFS formatting ->
        CMPI.B  #0x2,(A5)                       | file record? (cdrFilRec)
        BNE.B   GETFILEINFO_SKIP_2              | no (not a file), FNFErr ->
| copy file record fields to param block
        LEA.L   ioFlAttrib(A0),A4               | dest = param block file info area
        MOVEQ.L #0x18,D0                        | word count - 1 (50 bytes = 25 words)
        LEA.L   0x2(A5),A3                      | source = catalog record (past cdrType)
GETFILEINFO_LOOP_4:
        MOVE    (A3)+,(A4)+                     | copy file info
        DBF     D0,GETFILEINFO_LOOP_4           | loop for all file info words
        BCLR    #0x4,ioFlAttrib(A0)             | clear directory bit (it's a file)
GETFILEINFO_EXIT_2:
| set file attributes and scan for open FCBs
        ANDI.B  #0x73,ioFlAttrib(A0)            | mask to valid attribute bits
        CLR     ioRefNum(A0)                    | clear refnum (assume not open)
        MOVE.L  0x14(A5),D2                     | TFS file number (filFlNum)
        BSR     TFSVCBTst                       | TFS volume?
        BEQ.B   GETFILEINFO_OK_3                | yes ->
        MOVE.L  0x12(A5),D2                     | MFS file number
GETFILEINFO_OK_3:
        BSR     HFSE_CONT_15                    | Gt1stMatch: find first matching FCB
        BNE.B   GETFILEINFO_FOUND_2             | no matches ->
GETFILEINFO_OK_4:
        BTst    #0x1,0x4(A1,D1.W)               | test flag
        BEQ.B   GETFILEINFO_OK_5                | ok ->
        BSET    #0x2,ioFlAttrib(A0)             | set flag
        BRA.B   GETFILEINFO_CONT_6              | ->

| ----------------------------------------------------------
|
| GETFILEINFO_OK_5
|
GETFILEINFO_OK_5:
        BSet    #0x3,ioFlAttrib(A0)             | set flag
GETFILEINFO_CONT_6:
        BSet    #0x7,ioFlAttrib(A0)             | set flag
        BNE.B   GETFILEINFO_ERR_3               | error ->
        MOVE    D1,ioRefNum(A0)                 | IOParam field
| update this FCB's fork lengths from catalog
GETFILEINFO_ERR_3:
        LEA.L   0x34(A0),A3                     | ptr to param block fork info
        BSR     FILECLOSE_CONT_6                | UpdFlNtry: copy fork lengths to param block
        BSR     HFSE_ERR_9                      | GtNxtMatch: find next matching FCB
        BEQ.B   GETFILEINFO_OK_4                | ok ->
GETFILEINFO_FOUND_2:
        MOVEQ.L #0x0,D0                         | noErr
        BRA     GETFILEINFO_ERR_2               | ->

| ----------------------------------------------------------
|
| GETFILEINFO_OK_6
|
GETFILEINFO_OK_6:
        LEA.L   ioFlAttrib(A0),A4               | load address
        CMPI.B  #0x2,(A5)                       | compare
        BNE.B   GETFILEINFO_ERR_4               | error ->
        MOVEQ.L #0x22,D0                        | 35 words (70 bytes of catalog record)
        LEA.L   0x2(A5),A3                      | source = catalog record (past cdrType)
| TFS GetFileInfo: copy file record to param block
GETFILEINFO_LOOP_5:
        MOVE    (A3)+,(A4)+                     | copy file info word
        DBF     D0,GETFILEINFO_LOOP_5           | loop for all info words
| compute clump size from catalog entry
        MOVEQ.L #0x0,D0                         | clear high word
        MOVE    0x48(A5),D0                     | file's clump size (filClpSize)
        MULU    0x1E(A2),D0                     | * alloc block size = bytes
        MOVE.L  D0,0x68(A0)                     | ioFlClpSiz
        MOVE.L  D1,0x64(A0)                     | ioFlParID = parent DirID
        BCLR    #0x4,ioFlAttrib(A0)             | clear directory bit (it's a file)
        BRA     GETFILEINFO_EXIT_2              | go to common exit (FCB scan)

| ----------------------------------------------------------
|
| GETFILEINFO_ERR_4
|
| GetCatInfo directory record: copy directory info to param block
GETFILEINFO_ERR_4:
        CMPI.B  #0x1,(A5)                       | directory record? (cdrDirRec)
        BNE     GETFILEINFO_SKIP_2              | no, FNFErr ->
| copy directory fields to param block
        MOVE    0x2(A5),ioFlAttrib(A0)          | ioDrUsrWds (flags)
        MOVE    0x4(A5),0x34(A0)                | ioDrNmFls (valence)
        MOVE.L  0x6(A5),ioFFlNum(A0)            | ioDrDirID
        MOVE.L  D1,0x64(A0)                     | ioDrParID = parent DirID
        MOVEM.L 0xA(A5),D0-D2                   | dates (CrDat/MdDat/BkDat)
        MOVEM.L D0-D2,0x48(A0)                  | -> ioDrCrDat/ioDrMdDat/ioDrBkDat
        MOVEM.L 0x16(A5),D0-D3                  | dirUsrInfo (16 bytes)
        MOVEM.L D0-D3,0x20(A0)                  | -> ioDrUsrWds
        MOVEM.L 0x26(A5),D0-D3                  | dirFndrInfo (16 bytes)
        MOVEM.L D0-D3,0x54(A0)                  | -> ioDrFndrInfo
        BCLR    #0x7,ioFlAttrib(A0)             | clear "in use" flag
        BSET    #0x4,ioFlAttrib(A0)             | set directory flag
        MOVEQ.L #0x0,D0                         | no error
        BRA     GETFILEINFO_ERR_2               | exit ->

| ----------------------------------------------------------
|
| GETFILEINFO_NO_5
|
GETFILEINFO_NO_5:
        MOVE.B  0x1C(A0),0x1(A5)                | set file type byte
        BRA.B   GETFILEINFO_CONT_7              | ->

| ----------------------------------------------------------
|
| GETFILEINFO_NO_6
|
GETFILEINFO_NO_6:
        TST.B   (FLckUnlck).w                   | test
        BEQ.B   GETFILEINFO_OK_7                | ok ->
        BSET    #0x0,(A5)                       | set flag
        BNE.B   GETFILEINFO_ERR_5               | error ->
        BRA.B   GETFILEINFO_CONT_7              | ->

| ----------------------------------------------------------
|
| GETFILEINFO_OK_7
|
GETFILEINFO_OK_7:
        BClr    #0x0,(A5)                       | clear flag
        BEQ.B   GETFILEINFO_ERR_5               | ok ->
| MFS SetFileInfo/SetFilLock: mark dirty and flush
GETFILEINFO_CONT_7:
        MOVE.L  A1,A0                           | A0 = directory block
        JSR     P_mMarkBlock(PC)                | mark directory block dirty
        BSR     CREATE_CONT_7                   | MFS directory flush
GETFILEINFO_ERR_5:
        MOVEQ.L #0x0,D0                         | no error
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| GETFILEINFO_NO_7
|
GETFILEINFO_NO_7:
        MOVEM.L 0x20(A0),D1-D4                  | block move regs
        MOVEM.L D1-D4,0x2(A5)                   | block move regs
        MOVEM.L 0x48(A0),D1-D2                  | block move regs
        MOVEM.L D1-D2,0x2A(A5)                  | block move regs
        BRA.B   GETFILEINFO_CONT_7              | ->

| ----------------------------------------------------------
|
| GETFILEINFO_NO_8
|
| Called during boot.
GETFILEINFO_NO_8:
        MOVE.L  (SP)+,A3                        | restore A3
        TST.B   D2                              | test
        BNE.B   GETFILEINFO_ERR_6               | error ->
        MOVEQ.L #-0x25,D0                       | bdNamErr (-37): bad file name
        BRA.B   GETFILEINFO_ERR_7               | ->

| ----------------------------------------------------------
|
| GETFILEINFO_ERR_6
|
| Called during boot.
GETFILEINFO_ERR_6:
        MOVE    vcbNmFls(A2),D7                 | VCB field
        BEQ.B   GETFILEINFO_OK_8                | ok ->
        BSR     FILEWRITE_CONT_4                | call helper
GETFILEINFO_CONT_8:
        BEQ.B   GETFILEINFO_OK_9                | ok ->
        CMPI    #-0x21,D0                       | compare
        BNE.B   GETFILEINFO_ERR_7               | error ->
GETFILEINFO_OK_8:
        MOVEQ.L #-0x2B,D0                       | fnfErr (-43): file not found
        BRA.B   GETFILEINFO_ERR_7               | ->

| ----------------------------------------------------------
|
| GETFILEINFO_OK_9
|
| Called during boot.
GETFILEINFO_OK_9:
        MOVEQ.L #0x0,D0                         | noErr
        MOVE.L  A4,A1                           | A1 = parsed name ptr
| MFS directory search: scan entries for matching filename
GETFILEINFO_CONT_9:
        MOVE    D0,D4                           | D4 = current entry offset
        TST.B   0x0(A5,D4.W)                    | entry in use? (first byte nonzero)
        BEQ.B   GETFILEINFO_NO_9                | no, end of directory ->
| check drive number and filename
        MOVE.B  0x1(A5,D4.W),D6                 | entry's volume flags byte
        CMP.B   0x1A(A0),D6                     | matches our volume?
        BNE.B   GETFILEINFO_SKIP_3              | no, skip ->
| compare filename using _CmpString
        MOVE.L  A0,-(SP)                        | save param block
        LEA.L   0x32(A5,D4.W),A0                | ptr to entry's filename (Pascal string)
        MOVEQ.L #0x0,D0                         | entry name length (high word)
        MOVE.B  (A0)+,D0                        | get entry name length byte
        SWAP    D0                              | move to high word for CmpString
        MOVE    D2,D0                           | search name length (low word)
        _CmpString                              | case-insensitive compare
        MOVE.L  (SP)+,A0                        | restore param block
        BEQ.B   GETFILEINFO_FOUND_3             | match found ->
GETFILEINFO_SKIP_3:
        SUBQ.W  #0x1,D7                         | decrement file counter
        BEQ.B   GETFILEINFO_OK_8                | all files checked ->
        MOVE    D4,D0                           | current offset
        BSR     CREATE_NEXT                     | get next MFS directory entry
        BCS.B   GETFILEINFO_CONT_9              | more entries ->
GETFILEINFO_NO_9:
        BSR     FILEWRITE_NEXT                  | MFS read next directory block
        BRA.B   GETFILEINFO_CONT_8              | continue search
| match found
GETFILEINFO_FOUND_3:
        MOVE.L  A5,A1                           | A1 = directory block base
        LEA.L   0x0(A5,D4.W),A5                 | A5 = ptr to matched entry
GETFILEINFO_ERR_7:
        JMP     (A3)                            | Jump

| ----------------------------------------------------------
|
| GETFILEINFO_OK_10
|
| Called during boot.
GETFILEINFO_OK_10:
        CMP     vcbNmFls(A2),D1                 | compare
        BHI.B   GETFILEINFO_ERR_8               | yes ->
        MOVE    vcbAllocPtr(A2),D5              | VCB field
        MOVE    vcbVBMSt(A2),D3                 | VCB field
        ADD     D3,D5                           | D5 = AllocPtr + VBMSt (start block)
        MOVE    vcbDirIndex(A2),D7              | VCB field
        BEQ.B   GETFILEINFO_OK_11               | ok ->
        CMP     D7,D1                           | compare
        BCS.B   GETFILEINFO_OK_11               | unsigned less ->
        MOVE    vcbDirBlk(A2),D3                | VCB field
        BRA.B   GETFILEINFO_CONT_10             | ->

| ----------------------------------------------------------
|
| GETFILEINFO_OK_11
|
| Called during boot.
GETFILEINFO_OK_11:
        MOVEQ.L #0x1,D7                         | D7 = 1: first directory entry index
| MFS GetFileInfo indexed: resume from cached position or start fresh
GETFILEINFO_CONT_10:
        CMP     D5,D3                           | past end of directory?
        BCC.B   GETFILEINFO_ERR_8               | yes ->
        MOVE    D3,vcbDirBlk(A2)                | cache current dir block
        MOVE    D7,vcbDirIndex(A2)              | cache current file index
        BSR     FILEWRITE_NO_4                  | read directory block
        BNE.B   GETFILEINFO_ERR_8               | error ->
        MOVEQ.L #0x0,D0                         | initial entry offset
GETFILEINFO_CONT_11:
        MOVEQ.L #0x0,D6                         | D6 = 0 (unused)
        TST.B   0x0(A5,D0.W)                    | test
        BEQ.B   GETFILEINFO_OK_12               | ok ->
        CMP     D7,D1                           | compare
        BEQ.B   GETFILEINFO_OK_13               | ok ->
        ADDQ.W  #0x1,D7                         | advance to next directory entry
        BSR     CREATE_NEXT                     | call helper
        BCS.B   GETFILEINFO_CONT_11             | unsigned less ->
GETFILEINFO_OK_12:
        ADDQ.W  #0x1,D3                         | advance to next directory block
        BRA.B   GETFILEINFO_CONT_10             | ->

| ----------------------------------------------------------
|
| GETFILEINFO_ERR_8
|
GETFILEINFO_ERR_8:
        MOVEQ.L #-0x2B,D0                       | fnfErr (-43): file not found
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| GETFILEINFO_OK_13
|
| Called during boot.
| found the Nth MFS file: copy name and info to param block
GETFILEINFO_OK_13:
        LEA.L   0x0(A5,D0.W),A5                 | A5 = ptr to matched directory entry
        LEA.L   0x32(A5),A3                     | A3 = ptr to filename in entry
        MOVE.L  ioFileName(A0),D0               | caller's filename buffer
        BEQ.B   GETFILEINFO_NO_10               | no buffer ->
        MOVE.L  D0,A4                           | A4 = dest for name copy
        MOVE.B  (A3),D0                         | name length
GETFILEINFO_CONT_12:
        MOVE.B  (A3)+,(A4)+                     | copy name byte
        SUBQ.B  #0x1,D0                         | decrement name length counter
        BCC.B   GETFILEINFO_CONT_12             | unsigned greater or equal ->
| MFS GetFileInfo: copy MFS directory entry to param block
GETFILEINFO_NO_10:
        LEA.L   ioFlAttrib(A0),A4               | dest = param block file info area
        MOVEQ.L #0x18,D0                        | word count - 1 (50 bytes)
        LEA.L   (A5),A3                         | source = MFS directory entry
GETFILEINFO_LOOP_6:
        MOVE    (A3)+,(A4)+                     | copy file info
        DBF     D0,GETFILEINFO_LOOP_6           | loop for all 25 words
        BCLR    #0x4,ioFlAttrib(A0)             | clear directory flag (it's a file)
| for HFS-aware callers: add extended info
        BTST    #0x0,(HFSFlags).w               | HFS mode?
        BEQ.B   GETFILEINFO_NO_11               | no ->
        MOVE.L  #0x2,0x64(A0)                   | ioFlParID = root DirID

        CLR.L   0x50(A0)                        | clear ioFlBkDat
        MOVE.L  A0,-(SP)                        | save param block
        LEA.L   0x54(A0),A0                     | clear extended Finder info area
        MOVEQ.L #0x3,D0                         | 4 longwords
GETFILEINFO_LOOP_7:
        CLR.L   (A0)+                           | zero a longword
        DBF     D0,GETFILEINFO_LOOP_7           | loop for 4 longwords
        MOVE.L  (SP)+,A0                        | restore param block
GETFILEINFO_NO_11:
        BRA     GETFILEINFO_EXIT_2              | go to common exit (set refnum, scan FCBs)

| ----------------------------------------------------------
|
| GETFILEINFO_OK_14
|
| Called during boot.
GETFILEINFO_OK_14:
        MOVE    0x6(A0),D0                      | get ioTrap word
        BTST    #0x9,D0                         | test flag
        RTS                                     | return from GETFILEINFO_OK_14

| ----------------------------------------------------------
|
| GETFILEINFO_OK_15
|
| Called during boot.
GETFILEINFO_OK_15:
        MOVE.L  0x14(A1,D1.W),A2                | A2 = VCB from FCB (FCBVPtr)
| TFSVCBTst -- tFS volume?.
| Called by: MOUNTVOL_CONT_6, MOUNTVOL_CONT_8, MOUNTVOL_SKIP_3, MOUNTVOL_NO_6, MTVOLDONE (and 32 more)
TFSVCBTst:
        CMPI    #0x4244,vcbSigWord(A2)          | compare
        RTS                                     | return from TFSVCBTst

| ----------------------------------------------------------
|
| SEEK
|
| Called during boot.
| Seek: position within file, set up D5=cur pos, D7=IOReqCount
SEEK:
        CLR.L   0x28(A0)                        | haven't actually done any bytes yet (IOActCount)
        MOVEQ.L #-0x32,D0                       | assume bad count (ParamErr)
        MOVE.L  0x24(A0),D7                     | # bytes to read/write (IOReqCount)
        BMI.B   TFSVCBTST_ERR                   | exit with error if negative
        MOVE.L  ioPosOffset(A0),D2              | position value user supplied
        MOVE.L  0x10(A1,D1.W),D5                | current file position (FCBCrPs)
        MOVE.L  0x8(A1,D1.W),D4                 | get the current EOF (FCBEOF)
        MOVE.B  0x2D(A0),D0                     | the position mode is in bits 0,1
        ROXR.B  #0x2,D0                         | get position bits in carry, sign
        BCC.B   TFSVCBTST_CONT_2                | br if mode 0 or 1
        BMI.B   TFSVCBTST_CONT                  | br if mode 3
| relative to end of file (mode 2)
        MOVE.L  D4,D5                           | start from EOF
TFSVCBTST_CONT:
        ADD.L   D2,D5                           | add offset to position
        BRA.B   TFSVCBTST_OK                    | ->
| PM01: mode 0 or 1
TFSVCBTST_CONT_2:
        BPL.B   TFSVCBTST_OK                    | mode 0 (relative to current): use D5 as-is
        MOVE.L  D2,D5                           | mode 1 (absolute): use offset as position
TFSVCBTST_OK:
        BPL.B   TFSVCBTST_OK_2                  | position >= 0? ok ->
        MOVEQ.L #-0x28,D0                       | PosErr: negative position
        BRA.B   TFSVCBTST_ERR                   | exit ->
| check position vs EOF
TFSVCBTST_OK_2:
        MOVE.L  D5,D2                           | D2 = position - EOF
        SUB.L   D4,D2                           | (positive = past EOF)
        BLE.B   TFSVCBTST_OK_3                  | position <= EOF? ok ->
        MOVE.L  D4,D5                           | clamp to EOF
TFSVCBTST_OK_3:
        MOVE.L  D5,0x10(A1,D1.W)                | update current position in FCB (FCBCrPs)
        MOVEQ.L #0x0,D0                         | no error
TFSVCBTST_ERR:
        RTS                                     | exit Seek

