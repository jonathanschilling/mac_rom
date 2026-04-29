| File Manager - File I/O (Open, Read, Write, Close, extent allocation)
|
| This file implements the core file I/O operations on open files.
| All calls take A0 = ParmBlkPtr (IOParam or FileParam).
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
        RTS                                     | return

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
        MOVE.L  D6,PNPAT(A3)                    | copy parental DirID (FCBDirID)
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
        RTS                                     | return

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
        MOVEQ.L #-0x30,D0                       | dupFNErr
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
        MOVE.L  D1,ioFFlNum(A0)                 | return DirID (ioFDirIndex)
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
        RTS                                     | return

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
        MOVEQ.L #-0x25,D0                       | dupFNErr
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
        MOVEQ.L #0x0,D0                         | dupFNErr
CREATE_CONT_16:
        MOVEM.L (SP)+,D2/A1                     | restore regs
        RTS                                     | return

| ----------------------------------------------------------
|
| CREATE_OK_4
|
CREATE_OK_4:
        MOVE    D1,ioRefNum(A0)                 | IOParam field
        MOVEQ.L #-0x2F,D0                       | dupFNErr
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
        MOVEQ.L #-0x2F,D0                       | dupFNErr
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
        MOVEQ.L #-0x30,D0                       | dupFNErr: destination already exists
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
        MOVE.L  ioFFlNum(A0),-(A6)              | save source DirID
        MOVE.L  0x1C(A0),ioFileName(A0)         | set dest name (ioNewName)
        MOVE.L  0x24(A0),ioFFlNum(A0)           | set dest DirID (ioNewDirID)
        MOVEM.L D3-D5,-(A6)                     | save source info
        BSR     P_FndFilName                    | look up destination
        MOVEM.L (A6)+,D3-D5                     | restore source info
        MOVE.L  (A6)+,ioFFlNum(A0)              | restore source DirID
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
        MOVEQ.L #-0x30,D0                       | dupFNErr
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
        MOVEQ.L #-0x30,D0                       | dupFNErr: name already exists
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
        RTS                                     | return

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
        MOVEQ.L #-0x30,D0                       | dupFNErr (file with that type exists)
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
        MOVEQ.L #0x0,D0                         | dupFNErr
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
        RTS                                     | return to caller
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
        RTS                                     | return

| ----------------------------------------------------------
|
| Fnd Fil Name
|
| Called during boot.
FndFilName:
        BSR     DTRMV3                          | call helper
        BEQ.B   FNDFILNAME_OK                   | ok ->
FNDFILNAME_CONT:
        RTS                                     | return

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
        MOVE.L  PORTBOUNDS(A3),D7               | D7 = catalog hint (WDCatHint)
FNDFILNAME_NO:
| check if caller provided a pathname with content
        MOVE.L  A4,D0                           | A4 = parsed pathname position
        BEQ.B   FNDFILNAME_NO_2                 | no pathname ->
        SUB.L   ioFileName(A0),D0               | offset from start of string
        SUBQ.L  #0x2,D0                         | subtract header
        BGT.B   FNDFILNAME_NO_3                 | has filename component ->
FNDFILNAME_NO_2:
| check for HFS DirID override
        BTst    #0x9,0x6(A0)                    | ioDirFlg set?
        BEQ.B   FNDFILNAME_NO_3                 | no ->
        MOVE.L  ioFFlNum(A0),D0                 | caller-supplied DirID?
        BEQ.B   FNDFILNAME_NO_3                 | no ->
        MOVE.L  D0,D6                           | D6 = DirID
        MOVEQ.L #0x0,D7                         | dupFNErr
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
        MOVEQ.L #-0x35,D0                       | dupFNErr
FNDFILNAME_ERR_3:
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        TST     D0                              | test
        RTS                                     | return

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
        MOVEQ.L #0x0,D0                         | dupFNErr
        MOVE    D0,vcbDirIndex(A2)              | VCB field
        BRA     GETFILEINFO_NO_4                | ->

| ----------------------------------------------------------
|
| GETFILEINFO_CONT
|
GETFILEINFO_CONT:
        MOVEQ.L #0x0,D1                         | dupFNErr
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
        MOVE.L  PORTBOUNDS(A3),D7               | D7 = catalog hint (WDCatHint)
GETFILEINFO_NO:
| check if caller specified a DirID directly
        BTst    #0x9,0x6(A0)                    | ioDirFlg set? (HFS-specific)
        BEQ.B   GETFILEINFO_NO_2                | no ->
        TST.L   ioFFlNum(A0)                    | caller-supplied DirID?
        BEQ.B   GETFILEINFO_NO_2                | no ->
        MOVE.L  ioFFlNum(A0),D6                 | D6 = caller's DirID
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
        MOVEQ.L #0x0,D0                         | dupFNErr
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
        MOVEQ.L #-0x25,D0                       | dupFNErr
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
        MOVEQ.L #-0x2B,D0                       | dupFNErr
        BRA.B   GETFILEINFO_ERR_7               | ->

| ----------------------------------------------------------
|
| GETFILEINFO_OK_9
|
| Called during boot.
GETFILEINFO_OK_9:
        MOVEQ.L #0x0,D0                         | dupFNErr
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
        MOVEQ.L #0x1,D7                         | dupFNErr
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
        MOVEQ.L #-0x2B,D0                       | dupFNErr
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
        RTS                                     | return

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
        RTS                                     | return

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

| GetFPos -- _GetFPos ($A018): FUNCTION GetFPos (refNum: INTEGER; VAR filePos: LONGINT) OSErr;
| ----------------------------------------------------------
|
| _GetFPos ($A018)
|
GetFPos:
        CLR.B   0x2D(A0)                        | clear
| SetFPos -- _SetFPos ($A044): FUNCTION SetFPos (refNum: INTEGER; posMode: INTEGER; posOff:
SetFPos:
        CLR.L   0x24(A0)                        | clear
| FileRead (vFileRead)
L_mFileRead:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     P_RFNCall                       | RFNCall: map the reference number
        BNE     L_MFILEREAD_EXIT_3              | exit on errors (don't set IOPosOffset)
        BSR.B   SEEK                            | Seek: do any positioning, D5=cur pos, D7=IOReqCount
        BNE.B   L_MFILEREAD_EXIT_2              | exit if positioned before file start
| figure min(requested count, distance to EOF)
        NEG.L   D2                              | EOF - current pos (from Seek)
        BMI.B   L_MFILEREAD_CONT_2              | if negative, report end of file
        CMP.L   D2,D7                           | number of bytes desired within EOF?
        BLE.B   L_MFILEREAD_CONT                | br if so
        MOVE.L  D2,D7                           | just read distance to EOF
L_MFILEREAD_CONT:
        TST.L   D7                              | byte count 0?
        BEQ.B   L_MFILEREAD_DONE                | all done if none to read
        MOVE    ioPosMode(A0),D2                | get newline stuff
        LSR     #0x8,D2                         | newline char in low byte, enb in carry
        BCS.B   L_MFILEREAD_CONT_3              | if newline enabled, do it differently
        BTST    #0x6,0x2D(A0)                   | read verify?
        BEQ.B   L_MFILEREAD_NO                  | br if not
        MOVEM.L D1/A1,-(A6)                     | save A1/D1 across FlushCache call
        MOVE    D1,D0                           | set up to flush file's blocks
        MOVEQ.L #0x0,D1                         | just normal call
        MOVE.L  vcbBufAdr(A2),A1                | point to volume buffer
        JSR     P_mFlushCache(PC)               | write all file blocks before read-verify
        MOVEM.L (A6)+,D1/A1                     | and trash so we actually read them
L_MFILEREAD_NO:
        MOVE    D5,D2                           | current file position (low word)
        ANDI    #0x1FF,D2                       | check lower 9 bits for blk bndry read
        BEQ.B   RDMAIN                          | br if so (can read into place)
| RdPart: must read a partial block first
RDPART:
        BSR     L_MFILEREAD_CONT_5              | RdFileBlk: read the data block
        BNE.B   L_MFILEREAD_EXIT                | exit on errors
        BTST    #0x6,0x2D(A0)                   | read verify only?
        SNE.B   D0                              | $00 if not, $FF if so
        BSR     DOPART                          | DoPart: copy partial block to user buffer
        BNE.B   L_MFILEREAD_EXIT                | exit on verify errors
| RdMain: read multiple blocks into place in user's buffer
RDMAIN:
        MOVE.L  D7,D4                           | number of bytes we want
        BEQ.B   L_MFILEREAD_DONE                | all done if no more bytes
        ANDI    #-0x200,D4                      | only read whole blocks ($FE00 mask)
        TST.L   D4                              | any whole blocks to read?
        BEQ.B   RDPART                          | br if not
        JSR     P_mCacheRDIP(PC)                | CacheRdIP: read blocks into user buffer
        BNE.B   L_MFILEREAD_EXIT                | disk errors ->
        BSR     FILEWRITE_CONT_2                | UpdteCntPos: update D7, D5, IOActCount
        BRA.B   RDMAIN                          | loop
| FRdOK
L_MFILEREAD_DONE:
        MOVEQ.L #0x0,D0                         | no errors (except maybe EOF)
L_MFILEREAD_EXIT:
        TST     D0                              | other error?
        BNE.B   L_MFILEREAD_EXIT_2              | br if so
        MOVE.L  0x28(A0),D2                     | if actual count != requested count
        CMP.L   0x24(A0),D2                     | (IOActCount vs IOReqCount)
        BEQ.B   L_MFILEREAD_EXIT_2              | (br if equal, no EOF)
| FRdEOFXit
L_MFILEREAD_CONT_2:
        MOVEQ.L #-0x27,D0                       | EOFErr: hit end of file
L_MFILEREAD_EXIT_2:
        MOVE.L  D5,0x10(A1,D1.W)                | update current position in FCB (FCBCrPs)
        MOVE.L  D5,ioPosOffset(A0)              | always return current pos
L_MFILEREAD_EXIT_3:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_3
|
| FRNewLine: reading while looking for end of line characters
L_MFILEREAD_CONT_3:
        BSR.B   L_MFILEREAD_CONT_5              | RdFileBlk: read the data block
        BNE.B   L_MFILEREAD_EXIT                | exit on errors
        MOVE.L  D5,D2                           | current file position
        ANDI    #0x1FF,D2                       | get the index within block
        MOVE.L  0x20(A0),A3                     | user buffer (IOBuffer)
        MOVE.L  0x28(A0),D4                     | where to start continuing read (IOActCount)
| newline byte-by-byte scan loop
L_MFILEREAD_LOOP:
        MOVE.B  0x0(A5,D2.W),D0                 | get byte from the buffer
        MOVE.B  D0,0x0(A3,D4.L)                 | put it into user's area
        ADDQ.L  #0x1,0x28(A0)                   | actually read another byte (IOActCount)
        ADDQ.L  #0x1,D4                         | incr destination byte offset
        ADDQ.W  #0x1,D2                         | incr source byte offset
        ADDQ.L  #0x1,D5                         | incr current position
        CMP.B   ioPosMode(A0),D0                | is it the EOL character?
        BNE.B   L_MFILEREAD_NO_2                | no ->
        MOVEQ.L #0x0,D0                         | no error, we found EOL
        BRA.B   L_MFILEREAD_EXIT_2              | exit ->
L_MFILEREAD_NO_2:
        SUBQ.L  #0x1,D7                         | decr byte count
        BEQ.B   L_MFILEREAD_DONE                | exit, checking for EOF condition
        CMP     D6,D2                           | reached end of buffer?
        BCS.B   L_MFILEREAD_LOOP                | loop if not
        BRA.B   L_MFILEREAD_CONT_3              | get another block

| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_4
|
| Called during boot.
| L_MFILEREAD_CONT_4/PreRdFileBlk: read file block, but only if within current LEOF
L_MFILEREAD_CONT_4:
        BSR.B   L_MFILEREAD_CONT_6              | read the file block
        CMP.L   D3,D5                           | current pos < LEOF boundary? (D3=rounded LEOF)
        BCS.B   L_MFILEREAD_OK                  | yes, block has valid data ->
        MOVEQ.L #0x4,D1                         | no, block is beyond LEOF: RBdirty option
        BRA.B   L_MFILEREAD_OK                  | ->

| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_5
|
| Called during boot.
| L_MFILEREAD_CONT_5/RdFileBlk: read a file block into volume cache
L_MFILEREAD_CONT_5:
        BSR.B   L_MFILEREAD_CONT_6              | map file pos and read block
        BTST    #0x6,0x2D(A0)                   | read verify mode? (IOPosMode bit 6)
        BEQ.B   L_MFILEREAD_OK                  | no ->
        MOVEQ.L #0x1,D1                         | yes: force read (GBRead option)
L_MFILEREAD_OK:
        MOVE.L  vcbBufAdr(A2),A1                | volume cache queue
        MOVE.L  D5,D2                           | file position
        LSR.L   #0x8,D2                         | / 256...
        LSR.L   #0x1,D2                         | / 2 = file block number
        RTS                                     | return cache queue and block number

| ----------------------------------------------------------
|
| L_MFILEREAD_CONT_6
|
| Called during boot.
L_MFILEREAD_CONT_6:
        MOVEM.L D1-D2/A0-A1,-(A6)               | save regs
| L_MFILEREAD_CONT_6: read file block into cache (PreRdFileBlk helper)
| only reads if block is within current LEOF
        MOVE.L  (SP)+,A1                        | A1 = Lg2Phys vector
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE    D1,D0                           | file refnum
        MOVEQ.L #0x0,D1                         | no GetBlock options
        MOVEQ.L #0x2,D6                         | D6 = 512 (block size)
        LSL.L   #0x8,D6                         | D6 = 0x200 = 512 bytes
        JSR     (A1)                            | Lg2Phys: map file pos to disk block
        ADDQ.B  #0x8,D1                         | D1 = GBrelease option
        JSR     P_mGetBlock(PC)                 | GetBlock: read block from cache
        MOVE.L  A0,A5                           | A5 = block data pointer
        MOVE.L  (A6)+,-(SP)                     | restore return address
        MOVEM.L (A6)+,D1-D2/A0-A1               | restore regs
        TST     D0                              | set condition codes
        RTS                                     | return with block data in A5

| ----------------------------------------------------------
|
| File Write
|
| Called during boot.
FileWrite:
        BSR     FSQUEUE_SETUP                   | call helper
        BSR     TstMod                          | call helper
| FileWrite (vFileWrite)
        BNE.B   FILEWRITE_NO_3                  | br if not allowed to modify
        BSR     SEEK                            | Seek: position and set up D5, D7
        BNE.B   FILEWRITE_CONT                  | br if positioned before start
        TST.L   D2                              | positioned past EOF?
        BMI.B   FILEWRITE_NO                    | br if not
        ADD.L   D2,D5                           | extend added to cur pos
| set up D3 so PreRdFileBlk knows when block must actually be read
FILEWRITE_NO:
        MOVE.L  #0x1FF,D3                       | 511
        ADD.L   D4,D3                           | add current LEOF from Seek
        ANDI    #-0x200,D3                      | LEOF rounded to next block boundary
| see if file has to be made physically longer
        MOVE.L  D5,D4                           | current position after positioning
        ADD.L   D7,D4                           | end byte for write + 1
        CMP.L   0x8(A1,D1.W),D4                 | will it fit within old EOF? (FCBEOF)
        BLS.B   SAMELEN                         | if so, leave file at same phys length
        SUB.L   0xC(A1,D1.W),D4                 | past the phys end? (FCBPLen)
        BLS.B   FILEWRITE_NO_2                  | no, just reset the EOF
| ran off physical end: allocate more blocks
        BSR     ADJEOF_CONT_4                   | Alloc: allocate more space
FILEWRITE_CONT:
        BNE.B   FILEWRITE_EXIT                  | exit if didn't get it
| update logical length
FILEWRITE_NO_2:
        MOVE.L  D5,D4                           | current position after positioning
        ADD.L   D7,D4                           | + # bytes to write
        MOVE.L  D4,0x8(A1,D1.W)                 | is new logical end-of-file (FCBEOF)
| SameLen: data will fit, start writing
SAMELEN:
        MOVE    D5,D0                           | check if writing to a block boundary
        ANDI    #0x1FF,D0                       | if so, low 9 bits will be 0
        BEQ.B   WRMAIN                          | if so, try writing full blocks out
| WrPart: must write a partial block first
WRPART:
        BSR     L_MFILEREAD_CONT_4              | PreRdFileBlk: get the appropriate block
        BNE.B   FILEWRITE_ERR                   | skip if bad read
        MOVEQ.L #0x1,D0                         | D0=1 for write
        BSR.B   DOPART                          | DoPart: copy data from user buffer
        JSR     MarkA5Block(PC)                 | mark the block dirty
| WrMain: write entire blocks
WRMAIN:
        MOVE.L  D7,D4                           | number bytes we want
        BEQ.B   FILEWRITE_DONE                  | all done if no more bytes
        ANDI    #-0x200,D4                      | only write whole blocks ($FE00)
        TST.L   D4                              | must want at least 512 bytes
        BEQ.B   WRPART                          | br if not
        JSR     P_mCacheWRIP(PC)                | CacheWrIP: write blocks from user buffer
        BNE.B   FILEWRITE_ERR                   | disk errors ->
        BSR.B   FILEWRITE_CONT_2                | UpdteCntPos: update D7, D5, IOActCount
        BRA.B   WRMAIN                          | loop
| FWrOK
FILEWRITE_DONE:
        MOVEQ.L #0x0,D0                         | no errors
FILEWRITE_ERR:
        BSR     P_AdjEof                        | AdjEOF: adjust other FCBs for this file
        MOVE.L  D5,0x10(A1,D1.W)                | update current position in FCB (FCBCrPs)
FILEWRITE_EXIT:
        MOVE.L  0x10(A1,D1.W),ioPosOffset(A0)   | always return current pos
FILEWRITE_NO_3:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| FILEWRITE_CONT_2 - UpdteCntPos: update byte count, actual count, and file position
|
| Called during boot.
FILEWRITE_CONT_2:
        SUB.L   D6,D7                           | adjust for number of bytes read/written
        ADD.L   D6,0x28(A0)                     | actually transferred this many more (IOActCount)
        ADD.L   D6,D5                           | update current position
        RTS                                     | return updated counts and position

| ----------------------------------------------------------
|
| DOPART
|
| Called during boot.
| DoPart: copy partial block to/from user buffer
| D0: 0=read, 1=write, $FF=verify-read
DOPART:
        MOVE.L  D5,D2                           | current file position
        ANDI    #0x1FF,D2                       | get index within block
        SUB     D2,D6                           | D6 = bytes remaining in this block
        CMP.L   D6,D7                           | need more than one block's worth?
        BCC.B   FILEWRITE_OK                    | no, D6 is fine
        MOVE.L  D7,D6                           | yes, limit to bytes remaining
FILEWRITE_OK:
        MOVE.L  0x20(A0),A3                     | user buffer (IOBuffer)
        ADDA.L  0x28(A0),A3                     | + IOActCount = target
        BSR.B   FILEWRITE_CONT_2                | UpdteCntPos: update D7, D5, IOActCount
        MOVEM.L D1/A0-A2,-(SP)                  | save regs
        MOVE.L  A3,A0                           | source = user buffer
        MOVE.L  A5,A1                           | dest = cache buffer
        ADDA    D2,A1                           | + index into block
        TST.B   D0                              | D0 > 0? (write)
        BGT.B   FILEWRITE_OK_2                  | yes, user->cache ->
        BMI.B   FILEWRITE_CONT_3                | D0 < 0? (verify) ->
        EXG     A0,A1                           | read: swap src/dst (cache->user)
FILEWRITE_OK_2:
        MOVE.L  D6,D0                           | byte count
        MOVE.L  (0x4B8).w,A2                    | _BlockMove vector
        JSR     (A2)                            | move the data
FILEWRITE_ERR_2:
        MOVEQ.L #0x0,D0                         | no error
FILEWRITE_EXIT_2:
        MOVEM.L (SP)+,D1/A0-A2                  | restore regs
        RTS                                     | exit DoPart
| verify mode: compare bytes
FILEWRITE_CONT_3:
        MOVEQ.L #-0x24,D0                       | assume IOErr
        SUBQ.W  #0x1,D6                         | loop count - 1
FILEWRITE_LOOP:
        CMPM.B  (A0)+,(A1)+                     | compare bytes
        DBNE    D6,FILEWRITE_LOOP               | loop until mismatch or done
        BNE.B   FILEWRITE_EXIT_2                | mismatch: return IOErr
        BRA.B   FILEWRITE_ERR_2                 | match: return no error

| ----------------------------------------------------------
|
| FILEWRITE_CONT_4
|
| Called during boot.
FILEWRITE_CONT_4:
        MOVE    vcbAllocPtr(A2),D0              | VCB field
        MOVE    vcbVBMSt(A2),D3                 | VCB field
        ADD     D3,D0                           | D0 = AllocPtr + VBMSt
        MOVE    D0,(MaxDB).w                    | set max directory block
        BRA.B   FILEWRITE_NO_4                  | ->

| ----------------------------------------------------------
|
| FILEWRITE_NEXT
|
| Called during boot.
| FILEWRITE_NEXT: read next MFS directory block (advance CkdDB)
FILEWRITE_NEXT:
        MOVE    (CkdDB).w,D3                    | current directory block number
        ADDQ.W  #0x1,D3                         | next block
        CMP     (MaxDB).w,D3                    | past end of directory?
        BCS.B   FILEWRITE_NO_4                  | no ->
        MOVEQ.L #-0x21,D0                       | dupFNErr
        RTS                                     | return

| ----------------------------------------------------------
|
| FILEWRITE_NO_4
|
| Called during boot.
| FILEWRITE_NO_4: read MFS directory block D3 into cache
FILEWRITE_NO_4:
        MOVE    D3,(CkdDB).w                    | update current directory block
        BSR     L_MFILEREAD_CONT_6              | read block into cache (A5 = data)
        MOVE.L  (SysCtlCPtr).w,A1               | A1 = system control cache
        BRA.B   FILEWRITE_CONT_7                | ->

| FILEWRITE_NEXT_2 -- read next block.
| ----------------------------------------------------------
|
| FILEWRITE_NEXT_2
|
FILEWRITE_NEXT_2:
        BSR     L_MFILEREAD_CONT_6              | call helper
        BRA.B   FILEWRITE_CONT_6                | ->

| ----------------------------------------------------------
|
| FILEWRITE_CONT_5
|
| FILEWRITE_CONT_5: read MFS directory block D3 into volume cache
FILEWRITE_CONT_5:
        BSR     L_MFILEREAD_CONT_6              | read block D3 into cache
        MOVEQ.L #0x4,D1                         | RBdirty option (release dirty)
FILEWRITE_CONT_6:
        MOVE.L  (SysVolCPtr).w,A1               | system volume cache
FILEWRITE_CONT_7:
        MOVEQ.L #0x0,D2                         | block 0 (for GetBlock)
        MOVE    D3,D2                           | D2 = directory block number
        MOVE    vcbVRefNum(A2),D0               | VCB field
        RTS                                     | return

| ----------------------------------------------------------
|
| _FlushFile ($A045)
|
| _FlushFile ($A045)
FlushFile:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        ST.B    (FlushOnly).w                   | indicate flush only (don't close)
        BRA.B   FILECLOSE_CONT                  | share code with FileClose
| FileClose
FileClose:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        CLR.B   (FlushOnly).w                   | indicate close (not just flush)
FILECLOSE_CONT:
        BSR     P_RFNCall                       | RfNCall: is refnum for a valid open file?
        BEQ.B   FILECLOSE_CONT_2                | br if valid
        CMPI    #-0x35,D0                       | volume offline? (VolOffLinErr)
        BNE.B   FILECLOSE_ERR                   | no, some other error ->
FILECLOSE_CONT_2:
        BSR.B   FILECLOSE_CONT_3                | FClose: do the actual flush/close
FILECLOSE_ERR:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| FILECLOSE_CONT_3
|
| Called during boot.
| FClose: do the actual flush/close for TFS files
FILECLOSE_CONT_3:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D3/A0-A5,-(A6)               | save registers
        BSR     TFSVCBTst                       | TFS volume?
        BNE     FILECLOSE_NO_3                  | no, MFS close ->
| check if file has a B-tree open
        TST.L   0x22(A1,D1.W)                   | B-tree BTCB ptr? (FCBBTCBptr)
        BEQ.B   FILECLOSE_NO                    | no ->
        MOVE    D1,D0                           | file refnum
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   FILECLOSE_OK                    | yes, just flush ->
        JSR     P_mBTClose(PC)                  | BTClose: close the B-tree
        BRA.B   FILECLOSE_CONT_4                | ->

| ----------------------------------------------------------
|
| FILECLOSE_OK
|
FILECLOSE_OK:
        JSR     P_mBTFlush(PC)                  | call helper
FILECLOSE_CONT_4:
        BNE     FILECLOSE_ERR_4                 | error ->
| FClose TFS path: flush/close a single TFS file
FILECLOSE_NO:
        MOVEQ.L #0x0,D0                         | assume no error
        TST     vcbDrvNum(A2)                   | volume online?
        BEQ     FILECLOSE_SKIP_2                | no (offline), skip flush ->
        CMPI.L  #0x10,0x0(A1,D1.W)              | system file? (CNID < 16)

        BCS     FILECLOSE_SKIP_2                | yes, skip (handled by volume flush) ->
| check if FCB is dirty
        BCLR    #0x7,0x4(A1,D1.W)               | clear FCB dirty bit (FCBModBit)
        BEQ     FILECLOSE_DONE                  | was clean, skip flush ->
| FCB was dirty: check if we should/can flush
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   UPDTECNTPOS                     | yes, skip truncate ->
        BSR     TstMod                          | can we modify this file?
        BNE.B   UPDTECNTPOS                     | no, skip truncate ->
| truncate to clump-rounded PEOF on close
        MOVE.L  0xC(A1,D1.W),D3                 | D3 = current PEOF (FCBPLen)
        BTST    #0x6,0x4(A1,D1.W)               | own clump size? (FCBOwnClp)
        BEQ.B   FILECLOSE_SKIP                  | no, skip rounding ->
        MOVEM.L D0-D1,-(SP)                     | save regs
        MOVE.L  D3,D0                           | D0 = new PEOF in alloc blocks
        MOVE.L  0x1E(A1,D1.W),D1                | get clump size for file (FCBClmpSize)
        BSR     RoundAlloc                      | round up to next clump
        MOVE.L  vcbAlBlkSiz(A2),D1              | allocation block size
        MULU    D1,D0                           | compute new EOF in bytes
        MOVE.L  D0,D3                           | D3 = rounded PEOF
        MOVEM.L (SP)+,D0-D1                     | restore scratch regs
FILECLOSE_SKIP:
        JSR     P_mTruncateFile(PC)             | TruncateFile: truncate to rounded length
        BNE     FILECLOSE_ERR_3                 | error ->
| UpdteCntPos: update catalog record from FCB
UPDTECNTPOS:
        MOVE.L  A1,-(A6)                        | save FCB array ptr
        MOVE.L  0x3A(A1,D1.W),D0                | parent DirID (FCBDirID)
        LEA.L   0x3E(A1,D1.W),A0                | ptr to CName (FCBCName)
        MOVEQ.L #0x0,D2                         | no hint
        JSR     CMGetCN(PC)                     | locate catalog record
        MOVE.L  A1,A5                           | A5 = catalog data record
        MOVE.L  (A6)+,A1                        | restore FCB array ptr
        BNE     FILECLOSE_ERR_3                 | error ->
| copy FCB extent record back to catalog
        MOVEM.L A0-A1,-(SP)                     | save regs
        LEA.L   0x26(A1,D1.W),A0                | source = FCB extent record (FCBExtRec)
        LEA.L   0x4A(A5),A3                     | dest = data fork extents (filExtRec)
        BTST    #0x9,0x4(A1,D1.W)               | resource fork? (FCBRscBit)
        BEQ.B   FILECLOSE_NO_2                  | no ->
        LEA.L   0x56(A5),A3                     | dest = rsrc fork extents (filRExtRec)
FILECLOSE_NO_2:
        MOVE.L  A3,A1                           | dest for _BlockMove
        MOVEQ.L #0xC,D0                         | extent record length (lenXDR)
        _BlockMove                              | copy extent record to catalog
        MOVEM.L (SP)+,A0-A1                     | restore regs
| update file info in catalog record
        LEA.L   0x18(A5),A3                     | ptr to file lengths in catalog
        BSR     FILECLOSE_CONT_6                | UpdFlNtry: update file entry from FCB
        MOVE.L  (Time).w,0x30(A5)               | set modification date (filMdDat)
        JSR     CMUpdateCN(PC)                  | update the catalog record
        BNE.B   FILECLOSE_ERR_3                 | error ->
| if resource fork with LEOF >= 128, update rsrc fork block 0 in volume cache
        BTST    #0x9,0x4(A1,D1.W)               | resource fork? (FCBRscBit)
        BEQ.B   FILECLOSE_DONE                  | no, done ->
        CMPI.L  #0x80,0x8(A1,D1.W)              | LEOF >= 128 bytes? (FCBEOF)

        BCS.B   FILECLOSE_DONE                  | no, skip resource map copy ->
| read resource fork block 0 from volume cache and update it
        MOVEM.L D1/A1,-(A6)                     | save regs
        MOVE.L  A0,A3                           | A3 = catalog key record
        MOVE.L  vcbBufAdr(A2),A1                | volume cache
        MOVE    D1,D0                           | file refnum
        MOVEQ.L #0x0,D1                         | no GetBlock options
        MOVEQ.L #0x0,D2                         | block 0
        JSR     P_mGetBlock(PC)                 | get resource fork block 0
        BNE.B   FILECLOSE_ERR_2                 | error ->
| copy catalog info into resource fork block 0 for Desktop file
        MOVE.L  A0,-(SP)                        | save block ptr
        LEA.L   ioFFlNum(A0),A1                 | dest = first 32 bytes in block
        LEA.L   0x6(A3),A0                      | source = catalog key CName area
        MOVEQ.L #0x20,D0                        | 32 bytes
        _BlockMove                              | copy key info
        MOVEQ.L #0x20,D0                        | 32 bytes just copied
        ADDA.L  D0,A1                           | advance dest by 32
        LEA.L   0x2(A5),A0                      | source = catalog record (past type)
        MOVEQ.L #0x12,D0                        | 18 bytes
        _BlockMove                              | copy file flags/dates
        MOVEQ.L #0x12,D0                        | 18 bytes just copied
        ADDA.L  D0,A1                           | advance dest by 18
        LEA.L   0x38(A5),A0                     | source = extended Finder info
        MOVEQ.L #0x10,D0                        | 16 bytes
        _BlockMove                              | copy Finder info
        MOVEQ.L #0x10,D0                        | 16 bytes just copied
        ADDA.L  D0,A1                           | advance dest by 16
        MOVE.L  0x2C(A5),(A1)+                  | copy filCrDat
        MOVE.L  0x1A(A5),(A1)+                  | copy filLgLen (data fork)
        MOVE.L  0x24(A5),(A1)+                  | copy filRLgLen (rsrc fork)
        MOVE.L  (SP)+,A0                        | restore block ptr
        MOVE.L  vcbBufAdr(A2),A1                | volume cache
        MOVEQ.L #0x4,D1                         | release dirty (RBdirty)
        JSR     P_mRelBlock(PC)                 | release block
FILECLOSE_ERR_2:
        MOVEM.L (A6)+,D1/A1                     | restore regs
FILECLOSE_DONE:
        MOVEQ.L #0x0,D0                         | no error
| FClose exit: flush volume cache for this file
FILECLOSE_ERR_3:
        MOVEM.L D0-D1/A1,-(A6)                  | save regs
        MOVE    D1,D0                           | file refnum
        MOVEQ.L #0x0,D1                         | no FlushCache options
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   FILECLOSE_OK_2                  | yes, no trash ->
        MOVEQ.L #0x1,D1                         | FCtrash: trash after flush
FILECLOSE_OK_2:
        MOVE.L  vcbBufAdr(A2),A1                | volume cache
        JSR     P_mFlushCache(PC)               | flush volume cache for this file
        BSR     TFSVCBTst                       | TFS volume?
        BEQ.B   FILECLOSE_OK_3                  | yes ->
        BSR     CREATE_CONT_7                   | MFS: flush MFS directory
FILECLOSE_OK_3:
        MOVEM.L (A6)+,D0-D1/A1                  | restore saved error code and regs
| if closing (not just flushing), clear the FCB
FILECLOSE_SKIP_2:
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   FILECLOSE_ERR_4                 | yes, keep FCB ->
        LEA.L   0x0(A1,D1.W),A3                 | point to FCB entry
        MOVEQ.L #0x2E,D2                        | (FCB length / 2) - 1
FILECLOSE_LOOP:
        CLR     (A3)+                           | clear the FCB
        DBF     D2,FILECLOSE_LOOP               | until all done
FILECLOSE_ERR_4:
        MOVEM.L (A6)+,D1-D3/A0-A5               | restore regs
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit FClose

| ----------------------------------------------------------
|
| FILECLOSE_NO_3
|
| Called during boot.
| MFS FClose path
FILECLOSE_NO_3:
        BClr    #0x7,0x4(A1,D1.W)               | clear FCB dirty bit (FCBModBit)
        BEQ.B   FILECLOSE_DONE                  | was clean, skip flush ->
| find the file's MFS directory entry
        MOVE    0x1C(A1,D1.W),D3                | start block (FCBStBlk, used as dir hint)
        BSR     FILEWRITE_NO_4                  | read directory block containing this file
        BNE.B   FILECLOSE_ERR_3                 | error ->
        MOVEQ.L #0x0,D0                         | initial entry offset
        MOVE.L  0x0(A1,D1.W),D3                 | file number (FCBFlNm)
FILECLOSE_CONT_5:
        CMP.L   0x12(A5,D0.W),D3                | match file number in directory entry?
        BEQ.B   FILECLOSE_OK_4                  | yes ->
        BSR     CREATE_NEXT                     | next directory entry
        BCS.B   FILECLOSE_CONT_5                | keep scanning
        MOVEQ.L #-0x2B,D0                       | FNFErr: file not in directory
        BRA.B   FILECLOSE_ERR_3                 | ->

| ----------------------------------------------------------
|
| FILECLOSE_OK_4
|
| Called during boot.
| MFS FClose: update directory entry from FCB data
FILECLOSE_OK_4:
        LEA.L   0x16(A5,D0.W),A3                | ptr to fork lengths in MFS entry
        BSR.B   FILECLOSE_CONT_6                | UpdFlNtry: copy FCB lengths to entry
        MOVE.L  (Time).w,0x2E(A5,D0.W)          | set modification date
        JSR     MarkA5Block(PC)                 | mark directory block dirty
        BRA.B   FILECLOSE_DONE                  | ->

| ----------------------------------------------------------
|
| FILECLOSE_CONT_6
|
| Called during boot.
| FILECLOSE_CONT_6/UpdFlNtry: update file lengths in catalog from FCB
| A3 = ptr to file length fields in catalog, (A1,D1) = FCB
FILECLOSE_CONT_6:
        MOVE.L  A4,-(SP)                        | save A4
        LEA.L   0x4(A1,D1.W),A4                 | A4 = FCB flags (FCBMdRByt)
        MOVE    (A4)+,D3                        | get flags
        LSL     #0x7,D3                         | resource fork bit in carry
        BCC.B   FILECLOSE_CONT_7                | data fork ->
        ADDA    #0xA,A3                         | skip data fork fields (10 bytes)
FILECLOSE_CONT_7:
        MOVE    (A4)+,(A3)+                     | copy start block (FCBStBlk)
        MOVE.L  (A4)+,(A3)+                     | copy LEOF (FCBEOF)
        MOVE.L  (A4)+,(A3)+                     | copy PEOF (FCBPLen)
        MOVE.L  (SP)+,A4                        | restore A4
        RTS                                     | exit UpdFlNtry

| ----------------------------------------------------------
|
| _GetEOF ($A011)
|
| Called during boot.
| _GetEOF ($A011)
GetEOF:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   P_RFNCall                       | RfNCall: is refnum for a valid open file?
        BNE.B   GETEOF_NO                       | br if not
        MOVE.L  0x8(A1,D1.W),0x1C(A0)           | return the logical EOF (FCBEOF -> IOLEOF)
GETEOF_NO:
        BRA     FSQUEUE_DONE                    | CmdDone

| ----------------------------------------------------------
|
| P_RFN Call
|
| Called during boot.
P_RFNCall:
        MOVE.L  (0x790).w,-(SP)                 | HFS vector: RFNCall
        RTS                                     | return

| ----------------------------------------------------------
|
| RFN Call
|
| Called during boot.
| RFNCall: map a reference number to FCB/VCB pointers
RFNCall:
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB array
        MOVEQ.L #0x0,D1                         | clear high word
        MOVE    ioRefNum(A0),D1                 | D1 = file refnum
        BSR.B   CKFILERFN                       | CkFileRfn: validate refnum
        BNE.B   RFNCALL_CONT                    | invalid ->
        MOVE.L  0x0(A1,D1.W),D2                 | D2 = file number (FCBFlNm)
        MOVE.L  0x14(A1,D1.W),A2                | A2 = VCB pointer (FCBVPtr)
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        BSR     FNDFILNAME_CONT_4               | CkExtFS: check for external file system
RFNCALL_CONT:
        TST     D0                              | set condition codes
        RTS                                     | exit RFNCall

| ----------------------------------------------------------
|
| CKFILERFN
|
| Called during boot.
| CkFileRfn: check that refnum points to a valid open file
CKFILERFN:
        MOVEQ.L #-0x33,D0                       | assume refnum error (RFNumErr)
        MOVEQ.L #0x0,D2                         | clear high word
        MOVE    D1,D2                           | check refnum alignment
        DIVU    #0x5E,D2                        | / FCB size
        SWAP    D2                              | get remainder
        SUBQ.W  #0x2,D2                         | remainder must be 2 (offset past FCB header)
        BNE.B   RFNCALL_OK                      | invalid refnum ->
        CMP     (A1),D1                         | past end of FCB array?
        BCC.B   RFNCALL_OK                      | yes, invalid ->
        MOVEQ.L #-0x26,D0                       | assume closed file (FNOpnErr)
        TST.L   0x0(A1,D1.W)                    | FCB in use? (FCBFlNm)
        BEQ.B   RFNCALL_OK                      | no, file not open ->
        MOVEQ.L #0x0,D0                         | valid open file
RFNCALL_OK:
        TST     D0                              | set condition codes
        RTS                                     | exit CkFileRfn

| ----------------------------------------------------------
|
| TstMod: test if we may modify this file
|
| Called during boot.
TstMod:
        BSR.B   P_RFNCall                       | RfNCall: map the reference number
        BNE.B   TSTMOD_EXIT                     | exit on errors
        MOVEQ.L #-0x3D,D0                       | assume wrPermErr
        BTST    #0x0,0x4(A1,D1.W)               | write permission? (FCBWriteBit)
        BEQ.B   TSTMOD_EXIT                     | no, can't modify ->
        BSR     SETVOLINFO_HFS_CONT_3           | check volume write protect
TSTMOD_EXIT:
        TST     D0                              | set condition codes
        RTS                                     | exit TstMod

| ----------------------------------------------------------
|
| Get FCB Info_hfs
|
| _GetFCBInfo (HFS): return info about an open FCB
GetFCBInfo_hfs:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   FNDFCB                          | FndFCB: find the FCB by refnum or index
        BNE.B   GETFCBINFO_HFS_ERR              | error ->
        MOVE    D1,ioRefNum(A0)                 | return the actual refnum
        LEA.L   0x0(A1,D1.W),A3                 | A3 = FCB entry
| copy first 20 bytes of FCB to param block
        MOVE.L  A0,-(SP)                        | save param block
        LEA.L   0x20(A0),A1                     | dest = ioFCBFlNm area in param block
        MOVE.L  A3,A0                           | source = FCB
        MOVEQ.L #0x14,D0                        | 20 bytes (FCBFlNm through FCBVPtr)
        _BlockMove                              | copy FCB fields
        MOVE.L  (SP)+,A0                        | restore param block
| copy additional FCB fields
        MOVE    vcbVRefNum(A2),0x34(A0)         | ioFCBVRefNum = volume refnum
        MOVE.L  0x1E(A3),0x36(A0)               | ioFCBClpSiz = clump size (FCBClmpSize)
        MOVE.L  PNPAT(A3),0x3A(A0)              | ioFCBParID = parent DirID (FCBDirID)
| copy FCB CName to caller's buffer
        MOVE.L  ioFileName(A0),D0               | filename buffer pointer
        BEQ.B   GETFCBINFO_HFS_NO               | no buffer ->
        MOVE.L  D0,A1                           | A1 = dest buffer
        MOVE.L  A0,-(SP)                        | save param block
        LEA.L   0x3E(A3),A0                     | source = FCBCName
        MOVEQ.L #0x1,D0                         | include length byte
        ADD.B   (A0),D0                         | + name length
        _BlockMove                              | _BlockMove
        MOVE.L  (SP)+,A0                        | restore param block pointer
| GetFCBInfo exit: set requested volume and check external FS
GETFCBINFO_HFS_NO:
        MOVE.L  A2,(ReqstVol).w                 | set requested volume
        MOVE.L  A3,D1                           | D1 = FCB pointer
        BSR     CKExtFS                         | check external FS
GETFCBINFO_HFS_ERR:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| FNDFCB
|
| FndFCB: find an FCB by refnum or by index (for GetFCBInfo)
FNDFCB:
        MOVE.L  (FCBSPtr).w,A1                  | FCB array
        MOVE    ioRefNum(A0),D1                 | requested refnum
        MOVE    0x1C(A0),D0                     | ioFCBIndx: index (0 = use refnum)
        BEQ.B   GETFCBINFO_HFS_FOUND            | index=0: use refnum directly ->
| indexed search: find Nth user-open FCB
        MOVEQ.L #0x0,D2                         | D2 = VCB filter (0 = any volume)
        MOVE    ioVRefNum(A0),D2                | filter by volume?
        BEQ.B   GETFCBINFO_HFS_NO_2             | no VRefNum: scan all ->
        MOVE    D2,D0                           | determine volume from VRefNum
        BSR     P_DTRMV1                        | DTRMV1
        BNE.B   GETFCBINFO_HFS_ERR_2            | error ->
        MOVE.L  A2,D2                           | D2 = VCB pointer filter
        MOVE    0x1C(A0),D0                     | restore index
GETFCBINFO_HFS_NO_2:
        BSR     HFSE_CONT_14                    | Gt1stFCB
GETFCBINFO_HFS_CONT:
        MOVE.L  0x0(A1,D1.W),D3                 | file number (FCBFlNm)
        BEQ.B   GETFCBINFO_HFS_SKIP             | FCB empty, skip ->
        MOVE.L  0x14(A1,D1.W),A2                | VCB pointer (FCBVPtr)
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   GETFCBINFO_HFS_OK               | no, MFS file ok ->
        CMPI.L  #0x10,D3                        | system file? (CNID < 16)
        BCS.B   GETFCBINFO_HFS_SKIP             | yes, skip system files ->
GETFCBINFO_HFS_OK:
        TST.L   D2                              | volume filter active?
        BEQ.B   GETFCBINFO_HFS_NO_3             | no ->
        CMP.L   0x14(A1,D1.W),D2                | same volume? (FCBVPtr)
        BNE.B   GETFCBINFO_HFS_SKIP             | no, skip ->
GETFCBINFO_HFS_NO_3:
        SUBQ.W  #0x1,D0                         | decrement index
        BEQ.B   GETFCBINFO_HFS_FOUND            | found the Nth one ->
GETFCBINFO_HFS_SKIP:
        BSR     HFSE_NEXT                       | GtNxtFCB
        BCS.B   GETFCBINFO_HFS_CONT             | more FCBs ->
        MOVEQ.L #-0x26,D0                       | FNOpnErr: no matching FCB found
        BRA.B   GETFCBINFO_HFS_ERR_2            | ->

| ----------------------------------------------------------
|
| GETFCBINFO_HFS_FOUND
|
GETFCBINFO_HFS_FOUND:
        BSR     CKFILERFN                       | call helper
GETFCBINFO_HFS_ERR_2:
        TST     D0                              | test
        RTS                                     | return

| ----------------------------------------------------------
|
| hfs Un_Lock Range
|
| _LockRng / _UnlockRng (HFS): stub - always succeeds
hfsUn_LockRange:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     P_RFNCall                       | RfNCall: validate refnum
        BNE.B   HFSUN_LOCKRANGE_ERR             | error ->
        MOVEQ.L #0x0,D0                         | no error (range locking not implemented)
HFSUN_LOCKRANGE_ERR:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| HFSUN_LOCKRANGE_CONT
|
| HFSUN_LOCKRANGE_CONT/FileAlloc: allocate space for file (MFS/HFS dispatch)
HFSUN_LOCKRANGE_CONT:
        BSR     TFSVCBTst                       | TFS volume?
        BNE.B   HFSUN_LOCKRANGE_NO              | no, MFS alloc ->
        BSR     GETFILEINFO_OK_14               | TFSBitTst: check HFS flag
        BEQ     ADJEOF_CONT_4                   | HFS: use Alloc ->
        BRA     ADJEOF_CONT_5                   | MFS path ->

| ----------------------------------------------------------
|
| HFSUN_LOCKRANGE_NO
|
HFSUN_LOCKRANGE_NO:
        MOVEQ.L #0x0,D0                         | dupFNErr
        BRA     LG2PHYS_CONT_2                  | ->

| ----------------------------------------------------------
|
| _Allocate ($A010)
|
| _Allocate ($A010): pre-allocate disk space for a file
Allocate:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     TstMod                          | test if we may modify this file
        BNE.B   ALLOCATE_ERR                    | br if not
        MOVEQ.L #0x0,D6                         | D6 = 0 (bytes allocated so far)
        MOVE.L  0x24(A0),D4                     | D4 = requested bytes (ioReqCount)
        BEQ.B   ALLOCATE_EMPTY                  | zero request ->
        TST     vcbFreeBks(A2)                  | any free blocks?
        BEQ.B   ALLOCATE_EMPTY                  | no, disk full ->
        BSR.B   HFSUN_LOCKRANGE_CONT            | FileAlloc: allocate the space
        BNE.B   ALLOCATE_ERR                    | error ->
ALLOCATE_EMPTY:
        MOVE.L  D6,0x28(A0)                     | return actual bytes allocated (ioActCount)
        BSR     P_AdjEof                        | AdjEOF: adjust other FCBs
        MOVEQ.L #-0x22,D0                       | DskFulErr (in case partial alloc)
        CMP.L   0x24(A0),D6                     | compare
        BCS.B   ALLOCATE_ERR                    | unsigned less ->
        MOVEQ.L #0x0,D0                         | dupFNErr
ALLOCATE_ERR:
        BRA     FSQUEUE_DONE                    | ->

| ----------------------------------------------------------
|
| _SetEOF ($A012)
|
| Called during boot.
| _SetEOF ($A012)
SetEOF:
        BSR     FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR     TstMod                          | test if we may modify this file
        BNE.B   SETEOF_EXIT                     | br if not
        MOVE.L  0x1C(A0),D7                     | get requested logical end of file (IOLEOF)
        MOVE.L  D7,D4                           | and copy it
        SUB.L   0xC(A1,D1.W),D4                 | compare with current PEOF (FCBPLen)
        BHI.B   SETEOF_CONT_3                   | it's longer: alloc blks ->
        BCS.B   SETEOF_CONT                     | it's shorter: dealloc blks ->
| SEOFOK: same length or file adjusted
SETEOF_OK:
        BSR     GETFILEINFO_OK_14               | TFSBitTst: was HFS bit set?
        BEQ.B   SETEOF_NO                       | if not, adjust LEOF as requested
        CMP.L   0x8(A1,D1.W),D7                 | is new PEOF < current LEOF? (FCBEOF)
        BCC.B   SETEOF_OK_2                     | if not, current LEOF is still valid
SETEOF_NO:
        MOVE.L  D7,0x8(A1,D1.W)                 | set the new LEOF (FCBEOF)
        CMP.L   0x10(A1,D1.W),D7                | is current position past this? (FCBCrPs)
        BCC.B   SETEOF_OK_2                     | br if not
        MOVE.L  D7,0x10(A1,D1.W)                | if so, pin to this (FCBCrPs)
SETEOF_OK_2:
        BSR     P_AdjEof                        | AdjEOF: adjust any other FCBs for this file
        MOVEQ.L #0x0,D0                         | no error
SETEOF_EXIT:
        BRA     FSQUEUE_DONE                    | CmdDone
| shrtnFil: shorten the file
SETEOF_CONT:
        BSR     GETFILEINFO_OK_15               | TFSVolTst: is it TFS?
        BNE     ADJEOF_NO                       | no, MFS handles it ->
        MOVE.L  D7,D4                           | recover requested LEOF
| truncate the file space beyond the new PEOF
        MOVE.L  D4,D3                           | used to figure new physical length
        ST.B    (FlushOnly).w                   | set "round to extent" to avoid thrashing
        JSR     P_mTruncateFile(PC)             | truncate PEOF to LEOF
        BNE.B   SETEOF_EXIT                     | exit if in trouble
SETEOF_CONT_2:
        MOVEM.L D0-D2,-(A6)                     | save scratch regs
        MOVE    D1,D0                           | file refnum
        MOVE.L  0xC(A1,D1.W),D1                 | new PEOF (FCBPLen)
        MOVEQ.L #-0x1,D2                        | trash to end of file
        JSR     P_mTrashBlocks(PC)              | trash cached blocks beyond new length
        MOVEM.L (A6)+,D0-D2                     | restore scratch regs
        BRA.B   SETEOF_OK                       | go adjust LEOF
| lngthnFil: lengthen the file
SETEOF_CONT_3:
        JSR     ADJEOF_CONT_4(PC)               | Alloc: allocate more space
        BNE.B   SETEOF_EXIT                     | exit if can't allocate
        BRA.B   SETEOF_OK                       | ->

| ----------------------------------------------------------
|
| P_Adj Eof
|
| Called during boot.
P_AdjEof:
        MOVE.L  (0x794).w,-(SP)                 | HFS vector: AdjEof
        RTS                                     | return

| ----------------------------------------------------------
|
| Adj Eof
|
| Called during boot.
| AdjEOF: adjust EOF in other open FCBs for this file
| copies LEOF/PEOF from current FCB to all other FCBs with same file number
AdjEof:
        MOVEM.L D0-D6/A0-A5,-(SP)               | save all regs
| extract file info from current FCB
        ADDA    D1,A1                           | point to this FCB
        MOVE.L  (A1)+,D2                        | D2 = file number (FCBFlNm)
        BSET    #0x7,(A1)                       | mark FCB dirty (FCBModBit)
        MOVE    (A1),D0                         | D0 = FCB flags
        MOVEM.L (A1)+,D3-D6/A2                  | D3=flags, D4=StBlk, D5=LEOF, D6=PEOF, A2=CrPs?
        MOVE    D0,D6                           | D6 = FCB flags (for fork type check)
        LEA.L   0xE(A1),A1                      | skip past FCBVPtr area
        MOVEM.L (A1)+,A3-A5                     | A3-A5 = remaining FCB fields
| scan all FCBs for matching file number
        BSR     HFSE_CONT_15                    | Gt1stMatch: find first FCB with same file #
        BNE.B   ADJEOF_FOUND_2                  | no matches ->
ADJEOF_FOUND:
        LEA.L   0x4(A1,D1.W),A0                 | point to this FCB's flags
        MOVE    (A0)+,D0                        | get this FCB's flags
        EOR     D6,D0                           | compare fork type
        LSL     #0x7,D0                         | resource fork bit in carry
        BCS.B   ADJEOF_SKIP                     | different fork type, skip ->
| same fork: update EOF/PEOF from current FCB
        MOVE    D3,(A0)+                        | update StBlk
        MOVE.L  D4,(A0)+                        | update LEOF
        MOVE.L  D5,(A0)+                        | update PEOF
        LEA.L   0x22(A0),A0                     | skip to end of FCB
        MOVEM.L A3-A5,-(A0)                     | update remaining fields
ADJEOF_SKIP:
        BSR     HFSE_ERR_9                      | GtNxtMatch: find next matching FCB
        BEQ.B   ADJEOF_FOUND                    | found one ->
ADJEOF_FOUND_2:
        MOVEM.L (SP)+,D0-D6/A0-A5               | restore regs
        RTS                                     | exit AdjEOF

| ----------------------------------------------------------
|
| ADJEOF_NO
|
| Called during boot.
ADJEOF_NO:
        MOVEQ.L #0x0,D6                         | dupFNErr
| MFS SetEOF shrink: walk chain to truncation point
        MOVE    0x6(A1,D1.W),D3                 | D3 = start alloc block (FCBStBlk)
        MOVE.L  vcbAlBlkSiz(A2),D2              | D2 = alloc block size
        MOVE.L  D7,D4                           | D4 = new LEOF
        BNE.B   ADJEOF_CONT_2                   | nonzero, walk chain ->
        CLR     0x6(A1,D1.W)                    | LEOF=0: clear start block (FCBStBlk)
        BRA.B   ADJEOF_CONT_3                   | go free entire chain ->

| ----------------------------------------------------------
|
| ADJEOF_CONT
|
| Called during boot.
ADJEOF_CONT:
        MOVE    D5,D3                           | D3 = current alloc block number
| MFS SetEOF shrink: walk chain to new PEOF and truncate
ADJEOF_CONT_2:
        ADD.L   D2,D6                           | accumulate PEOF
        BSR     LG2PHYS_NEXT_2                  | get next block in chain
        SUB.L   D2,D4                           | subtract alloc block size from remaining
        BHI.B   ADJEOF_CONT                     | more to walk ->
| reached the new PEOF: truncate the chain
        CMP.L   0xC(A1,D1.W),D6                 | new PEOF >= current PEOF?
        BCC     SETEOF_OK                       | yes, nothing to truncate ->
        MOVE    D5,-(SP)                        | save next block
        MOVEQ.L #0x1,D5                         | mark current block as end-of-chain (1)
        BSR     LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: write end-of-chain to alloc map
        MOVE    (SP)+,D3                        | D3 = first block to free
ADJEOF_CONT_3:
        BSR     LG2PHYS_CONT_10                 | MFSDealloc: free remaining chain
        MOVE.L  D6,0xC(A1,D1.W)                 | update FCBPLen to new PEOF
        MOVE.L  D6,D4                           | D4 = new PEOF (for LEOF adjustment)
        BRA     SETEOF_CONT_2                   | go adjust LEOF ->

| ----------------------------------------------------------
|
| ADJEOF_CONT_4
|
| ADJEOF_CONT_4/Alloc: allocate disk space for file (MFS/HFS dispatch)
ADJEOF_CONT_4:
        BSR     GETFILEINFO_OK_15               | TFSVolTst: is it TFS?
        BNE     LG2PHYS_NO_3                    | no, MFS Alloc ->
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE.L  D3,-(A6)                        | save D3
        MOVEQ.L #0x0,D3                         | dupFNErr
        BRA.B   ADJEOF_CONT_6                   | ->

| ----------------------------------------------------------
|
| ADJEOF_CONT_5
|
ADJEOF_CONT_5:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE.L  D3,-(A6)                        | save D3 on A6 stack
        ST.B    D3                              | Set byte to true
ADJEOF_CONT_6:
        JSR     P_mExtendFile(PC)               | call helper
        MOVE.L  (A6)+,D3                        | restore D3 from A6 stack
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | test
        RTS                                     | return

| ----------------------------------------------------------
|
| P_m Lg2Phys
|
| Called during boot.
P_mLg2Phys:
        MOVE.L  (0x6FC).w,-(SP)                 | HFS vector: Lg2Phys
        RTS                                     | return

| ----------------------------------------------------------
|
| Lg2Phys
|
| Called during boot.
Lg2Phys:
        BSR     GETFILEINFO_OK_15               | TFSVCBTst: is it an HFS volume?
        BNE.B   LG2PHYS_NO                      | no, MFS path ->
        JMP     MapFBlock(PC)                   | HFS: use extent-based mapping

| ----------------------------------------------------------
|
| LG2PHYS_NO - MFS Lg2Phys: simple linear extent mapping
|
| Called during boot.
LG2PHYS_NO:
        MOVEM.L D1-D2/D4-D5/D7,-(SP)            | save registers
        MOVE.L  vcbAlBlkSiz(A2),D7              | D7 = allocation block size
        MOVE    0x6(A1,D1.W),D3                 | D3 = start alloc block from FCB
        ADD.L   D5,D4                           | D4 = end position (pos + max bytes - 1)
        SUBQ.L  #0x1,D4                         | adjust to last byte in range
        MOVEQ.L #0x9,D1                         | shift count for /512
        MOVEQ.L #0x0,D6                         | D6 = bytes mapped so far
        LSR.L   D1,D4                           | D4 = end block (in 512-byte blocks)
        LSR.L   D1,D7                           | D7 = alloc block size in 512-byte blocks
        MOVE.L  D5,D2                           | D2 = start block
        LSR.L   D1,D2                           | convert bytes to 512-byte blocks
        BRA.B   LG2PHYS_CONT                    | ->

| ----------------------------------------------------------
|
| LG2PHYS_NEXT
|
| Called during boot (3,127 times in 30s trace).
| walk MFS extent chain
LG2PHYS_NEXT:
        BSR.B   LG2PHYS_NEXT_2                  | get next extent entry
        MOVE    D5,D3                           | D3 = next alloc block start
        SUB     D7,D4                           | adjust end/start for this extent
        SUB     D7,D2                           | blocks remaining in this extent
LG2PHYS_CONT:
        CMP     D7,D2                           | start block within this extent?
        BCC.B   LG2PHYS_NEXT                    | no, try next extent
| found the right extent: compute disk block
        MOVE    D3,D0                           | alloc block start
        SUBQ.W  #0x2,D0                         | - 2 (alloc blocks start at 2)
        MULU    D7,D0                           | * alloc blk size (in 512-byte blocks)
        ADD     D2,D0                           | + offset within alloc block
        ADD     vcbAlBlSt(A2),D0                | + volume alloc block start
        MOVE.L  D0,-(SP)                        | save disk block number
| count contiguous blocks from this extent
LG2PHYS_OK:
        MOVE    D7,D0                           | blocks remaining in this extent
        SUB     D2,D0                           | - offset into extent
        ADD     D0,D6                           | add to contiguous block count
        SUB     D0,D4                           | subtract from remaining request
        BMI.B   LG2PHYS_DONE                    | done if covered all requested blocks
        BSR.B   LG2PHYS_NEXT_2                  | get next extent
        MOVEQ.L #0x0,D2                         | start at beginning of next extent
        ADDQ.W  #0x1,D3                         | check if next extent is contiguous
        CMP     D3,D5                           | (next alloc block == expected?)
        BEQ.B   LG2PHYS_OK                      | yes, keep counting contiguous blocks
| validate result and convert to byte count
LG2PHYS_DONE:
        MOVE.L  (SP)+,D3                        | restore disk block number
        MOVE    D3,D0                           | ending block = start + count
        ADD     D6,D0                           | D0 = start block + block count
        MOVE    vcbAlBlSt(A2),D4                | volume alloc block start
        MULU    vcbNmAlBlks(A2),D7              | total disk blocks = NmAlBlks * blk size
        ADD     D4,D7                           | + alloc start = end of volume
        CMP     D7,D0                           | past end of volume?
        BHI.B   LG2PHYS_ERR                     | yes, error ->
        CMP     D4,D3                           | before alloc start?
        BCS.B   LG2PHYS_ERR                     | yes, error ->
        ASL.L   D1,D6                           | convert block count to byte count (*512)
        MOVEM.L (SP)+,D1-D2/D4-D5/D7            | restore registers
        CMP.L   D4,D6                           | more than requested?
        BLS.B   LG2PHYS_NO_2                    | no ->
        MOVE.L  D4,D6                           | limit to requested amount
LG2PHYS_NO_2:
        MOVEQ.L #0x0,D0                         | success
        RTS                                     | return from Lg2Phys with success
LG2PHYS_ERR:
        MOVEM.L (SP)+,D1-D2/D4-D5/D7            | restore registers
        MOVE    #0x10,D0                        | FNFErr: mapping error
        RTS                                     | return from Lg2Phys with error

| ----------------------------------------------------------
|
| LG2PHYS_NEXT_2
|
| Called during boot (3,700 times in 30s trace).
| LG2PHYS_NEXT_2: MFS alloc map lookup - get next alloc block from 12-bit map
| D3 = current alloc block, returns D5 = next alloc block
LG2PHYS_NEXT_2:
        MOVEM.L D0/A2,-(SP)                     | save regs
        MOVE.L  vcbMAdr(A2),A2                  | A2 = allocation map base
        MOVE    D3,D0                           | alloc block number
        SUBQ.W  #0x2,D0                         | subtract 2 (map starts at block 2)
        MULU    #0xC,D0                         | * 12 bits per entry
        ROR.L   #0x4,D0                         | convert bit offset to byte.nibble
        ASL     #0x1,D0                         | byte offset (word-aligned)
        MOVE.L  0x0(A2,D0.W),D5                 | get longword containing 12-bit entry
        CLR     D0                              | isolate nibble offset
        ROL.L   #0x4,D0                         | shift nibble index to low bits
        ADDI    #0xC,D0                         | + 12 bits
        ROL.L   D0,D5                           | rotate entry to low 12 bits
        ANDI    #0xFFF,D5                       | mask to 12 bits
        MOVEM.L (SP)+,D0/A2                     | restore regs
        RTS                                     | return with entry in D5

| ----------------------------------------------------------
|
| LG2PHYS_NO_3 - MFS Alloc: allocate space for file (Alloc entry for MFS)
|
LG2PHYS_NO_3:
        MOVE.L  D4,D0                           | D0 = max bytes to allocate
LG2PHYS_CONT_2:
        MOVEM.L D1-D5/D7/A0-A3,-(SP)            | save regs
        MOVE.L  vcbAlBlkSiz(A2),D7              | alloc block size
        MOVE.L  D7,D6                           | compute free space in bytes
        MULU    vcbFreeBks(A2),D6               | = alloc blk size * free blocks
        CMP.L   D6,D4                           | request > free space?
        BLS.B   LG2PHYS_NO_4                    | no ->
        MOVE.L  D6,D4                           | limit to available space
LG2PHYS_NO_4:
        CMP.L   D0,D4                           | enough space?
        BCC.B   LG2PHYS_OK_2                    | yes ->
        MOVEQ.L #-0x22,D0                       | DskFulErr
LG2PHYS_EXIT:
        MOVEM.L (SP)+,D1-D5/D7/A0-A3            | restore regs
        RTS                                     | exit Alloc with DskFulErr
| MFS Alloc: extend file by allocating blocks from alloc map
LG2PHYS_OK_2:
        MOVE.L  0xC(A1,D1.W),D2                 | D2 = current PEOF (FCBPLen)
        MOVEQ.L #0x0,D6                         | D6 = bytes allocated so far
        MOVE    0x6(A1,D1.W),D3                 | D3 = start alloc block (FCBStBlk)
        BNE.B   LG2PHYS_CONT_3                  | have blocks already ->
| first allocation: get a new start block
        BSR.B   LG2PHYS_NEXT_3                  | find free block
        MOVE    D5,0x6(A1,D1.W)                 | set start block (FCBStBlk)
        MOVE    D5,D3                           | D3 = current alloc block
        MOVEQ.L #0x1,D5                         | dupFNErr
        BSR     LG2PHYS_CONT_9                  | call helper
        BRA.B   LG2PHYS_CONT_5                  | ->

| ----------------------------------------------------------
|
| LG2PHYS_ERR_2
|
LG2PHYS_ERR_2:
        MOVE    D5,D3                           | D3 = next alloc block in chain
LG2PHYS_CONT_3:
        BSR.B   LG2PHYS_NEXT_2                  | call helper
        CMPI    #0x1,D5                         | compare
        BNE.B   LG2PHYS_ERR_2                   | error ->
LG2PHYS_NO_5:
        CMP     vcbNmAlBlks(A2),D3              | compare
        BHI.B   LG2PHYS_OK_3                    | yes ->
        ADDQ.W  #0x1,D3                         | peek at next block
        BSR.B   LG2PHYS_NEXT_2                  | call helper
        SUBQ.W  #0x1,D3                         | restore current block number
| found free block: link it into the chain
        TST     D5                              | next block occupied?
        BNE.B   LG2PHYS_OK_3                    | yes, find another free ->
        MOVE    D3,D5                           | new block = current + 1
        ADDQ.W  #0x1,D5                         | D5 = next sequential block
LG2PHYS_CONT_4:
        BSR     LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: link current -> new block in map
        MOVE    D5,D3                           | D3 = new block (now current)
        MOVEQ.L #0x1,D5                         | mark new block as end-of-chain (1)
        BSR.B   LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: set new block's map entry
| update counts
LG2PHYS_CONT_5:
        ADD.L   D7,D6                           | add alloc block size to allocated
        ADD.L   D7,D2                           | add to PEOF
        SUBQ.W  #0x1,vcbFreeBks(A2)             | one fewer free block
        CMP.L   D6,D4                           | allocated enough?
        BHI.B   LG2PHYS_NO_5                    | no, allocate more ->
| done: update FCB PEOF
        MOVE.L  D2,0xC(A1,D1.W)                 | update FCBPLen
        BSR     MarkVCB                         | mark VCB dirty
        MOVEQ.L #0x0,D0                         | no error
        BRA.B   LG2PHYS_EXIT                    | exit ->
| next block is occupied: find a free one
LG2PHYS_OK_3:
        BSR.B   LG2PHYS_NEXT_3                  | LG2PHYS_NEXT_3: scan for next free block
        BRA.B   LG2PHYS_CONT_4                  | link it in ->

| ----------------------------------------------------------
|
| LG2PHYS_NEXT_3
|
| LG2PHYS_NEXT_3: MFS find free block - scan alloc map for best free run
LG2PHYS_NEXT_3:
        MOVEM.L D0-D4/D6/A1/A3,-(SP)            | save regs
        SUB.L   D6,D4                           | remaining bytes needed
        CMP.L   vcbClpSiz(A2),D4                | more than one clump?
        BCC.B   LG2PHYS_OK_4                    | yes, use full request ->
        MOVE.L  vcbClpSiz(A2),D4                | no, round up to clump size
| MFS Alloc: scan entire alloc map for best-fit free chain
LG2PHYS_OK_4:
        MOVE.L  vcbMAdr(A2),A1                  | A1 = alloc map base
        MOVE    vcbNmAlBlks(A2),A3              | A3 = total alloc blocks
        ADDQ.W  #0x1,A3                         | + 1 (sentinel)
        MOVEQ.L #0x0,D5                         | D5 = nibble toggle (odd/even 12-bit entry)
        MOVEQ.L #0x2,D0                         | D0 = current block number (start at 2)
        MOVEQ.L #0x2,D2                         | D2 = best-fit start block
        MOVEQ.L #0x0,D3                         | D3 = current free run length
        MOVEQ.L #0x0,D6                         | D6 = best free run length
        CLR     -(SP)                           | push best-fit block number (0 = none)
LG2PHYS_NO_6:
        MOVE.B  (A1)+,D1                        | read high byte of 12-bit entry
        LSL     #0x8,D1                         | shift to high position
        BCHG    #0x0,D5                         | bchg
        BNE.B   LG2PHYS_ERR_3                   | error ->
        MOVE.B  (A1),D1                         | read low nibble byte
        LSR     #0x4,D1                         | shift nibble to low position
        BRA.B   LG2PHYS_CONT_6                  | ->

| ----------------------------------------------------------
|
| LG2PHYS_ERR_3
|
LG2PHYS_ERR_3:
        MOVE.B  (A1)+,D1                        | read low byte of 12-bit entry
        ANDI    #0xFFF,D1                       | mask
| MFS Alloc scan: check if this block is free (entry = 0)
LG2PHYS_CONT_6:
        BNE.B   LG2PHYS_NO_8                    | not free, end of free run ->
        ADD.L   D7,D3                           | extend free run by alloc block size
        CMP.L   D6,D3                           | better than current best?
        BLS.B   LG2PHYS_NO_7                    | no ->
        MOVE.L  D3,D6                           | yes, update best free run length
        MOVE    D2,(SP)                         | save best-fit start block
        CMP.L   D4,D3                           | compare
        BCC.B   LG2PHYS_CONT_8                  | unsigned greater or equal ->
LG2PHYS_NO_7:
        ADDQ.W  #0x1,D0                         | advance to next alloc block
        BRA.B   LG2PHYS_CONT_7                  | ->

| ----------------------------------------------------------
|
| LG2PHYS_NO_8
|
LG2PHYS_NO_8:
        ADDQ.W  #0x1,D0                         | advance past occupied block
        MOVE    D0,D2                           | D2 = new free run start candidate
        MOVEQ.L #0x0,D3                         | dupFNErr
LG2PHYS_CONT_7:
        CMP     A3,D0                           | compare
        BLS.B   LG2PHYS_NO_6                    | no ->
LG2PHYS_CONT_8:
        MOVE    (SP)+,D5                        | D5 = best-fit start block
        MOVEM.L (SP)+,D0-D4/D6/A1/A3            | restore regs
        RTS                                     | return

| ----------------------------------------------------------
|
| LG2PHYS_CONT_9
|
| LG2PHYS_CONT_9: MFS alloc map write - set 12-bit entry in alloc map
| D3 = alloc block number, D5 = value to store (12-bit next block)
LG2PHYS_CONT_9:
        MOVEM.L D0/D6/A2,-(SP)                  | save regs
        MOVE.L  vcbMAdr(A2),A2                  | A2 = allocation map base
        MOVE    D3,D0                           | alloc block number
        SUBQ.W  #0x2,D0                         | subtract 2 (map starts at block 2)
        MULU    #0xC,D0                         | * 12 bits per entry
        ROR.L   #0x4,D0                         | convert bit offset to byte.nibble
        ASL     #0x1,D0                         | word-aligned byte offset
        MOVE.L  0x0(A2,D0.W),D6                 | get longword containing entry
        SWAP    D0                              | get nibble offset
        LSR     #0x8,D0                         | shift nibble index
        LSR     #0x4,D0                         | to low 4 bits
        ADDI    #0xC,D0                         | + 12 bits
        ROL.L   D0,D6                           | rotate entry to low 12 bits
        ANDI    #-0x1000,D6                     | clear old 12-bit value
        OR      D5,D6                           | merge new value
        ROR.L   D0,D6                           | rotate back to position
        SWAP    D0                              | restore byte offset
        MOVE.L  D6,0x0(A2,D0.W)                 | write back to alloc map
        MOVEM.L (SP)+,D0/D6/A2                  | restore regs
        RTS                                     | return after updating map

| ----------------------------------------------------------
|
| LG2PHYS_CONT_10
|
| LG2PHYS_CONT_10/MFSDealloc: free an MFS allocation chain starting at block D3
LG2PHYS_CONT_10:
        TST     D3                              | start block = 0?
        BEQ.B   LG2PHYS_CONT_11                 | nothing to free ->
LG2PHYS_NO_9:
        BSR     LG2PHYS_NEXT_2                  | get next block in chain (D5)
        MOVE    D5,-(SP)                        | save next block
        CLR     D5                              | write 0 (free) to map entry
        BSR.B   LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: write 0 to alloc map
        ADDQ.W  #0x1,vcbFreeBks(A2)             | increment free block count
        MOVE    (SP)+,D3                        | D3 = next block in chain
        CMPI    #0x1,D3                         | end-of-chain marker? (block 1)
        BNE.B   LG2PHYS_NO_9                    | no, keep freeing ->
        BSR     MarkVCB                         | mark VCB dirty
LG2PHYS_CONT_11:
        RTS                                     | exit MFSDealloc

| P_mBlkAlloc -- allocate the disk space.
| ----------------------------------------------------------
|
| P_m Blk Alloc
|
P_mBlkAlloc:
        MOVE.L  (0x77C).w,-(SP)                 | HFS vector: BlkAlloc
        RTS                                     | return

| ----------------------------------------------------------
|
| Blk Alloc
|
BlkAlloc:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1/D4-D7/A0-A1,-(A6)            | save caller's registers
        TST     vcbFreeBks(A2)                  | any blocks free at all?
        BEQ     BLKALLOC_EXIT_2                 | exit if not (DskFulErr)
        ANDI    #0x1,D3                         | clear all extra bits for our use
        TST     D2                              | preferred starting block selected?
        BNE.B   BLKALLOC_OK                     | yes, leave it be
        MOVE    vcbAllocPtr(A2),D2              | no, start from volume-wide pointer
        BSET    #0x7,D3                         | set flag to update vcbAllocPtr later
BLKALLOC_OK:
        SWAP    D3                              | get high word accessible
        MOVE    D2,D3                           | store starting block
        SWAP    D3                              | restore flags word for use
        BCLR    #0xF,D3                         | clear wrap-around flag
| blkLoop
BLKALLOC_NO:
        BSR     ReadBM                          | pick up the bitmap block of interest
        TST     D1                              | no errors?
        BMI     BKALLOCEXIT                     | if negative, D0 is now error code
        MOVE    vcbNmAlBlks(A2),A1              | set up the size of the volume
| look for free fragment at or beyond starting block
BLKALLOC_CONT:
        CMP     A1,D2                           | reached end-of-volume?
        BCS.B   BLKALLOC_NO_2                   | if not (D2 < A1), march along
        ROL.L   D1,D0                           | rotate D0 back into place
        MOVE.L  D0,0x0(A0,D6.W)                 | replace it in the buffer (clean)
        CLR     D2                              | reset starting block to beginning
        BSR     ReadBM                          | read the appropriate bitmap block
        BSET    #0xF,D3                         | indicate we wrapped around the EOV
        BNE     BLKALLOC_EXIT_2                 | exit if already set (DskFulErr)
BLKALLOC_NO_2:
        TST     D1                              | any errors occur?
        BMI     BKALLOCEXIT                     | punt on errors
        TST.L   D0                              | if bit 31 clear (free alloc block)?
        BPL.B   BLKALLOC_CONT_2                 | if so, check fragment size
        BSR     READBM_CONT_2                   | FrBitScan: look for another free bit
        BRA.B   BLKALLOC_CONT                   | and keep trying

| ----------------------------------------------------------
|
| BLKALLOC_CONT_2
|
| bkAlFree: found a free fragment, check if big enough
BLKALLOC_CONT_2:
        SUBA    D2,A1                           | change A1 to # blocks left to EOV
        BTST    #0x0,D3                         | is contiguous allocation requested?
        BEQ     BLKALLOC_NO_4                   | if not, just start allocating here
        MOVE.L  D4,-(A6)                        | store original alloc request size
        MOVEM.L D0-D1,-(A6)                     | free up for use in division
        MOVE.L  D4,D0                           | set up to divide
        MOVE    0x1E(A2),D1                     | by allocation block size (vcbAlBlkSiz+2)
        JSR     DivUp(PC)                       | round result up to next alloc block
        MOVE.L  D0,D4                           | D4 = min number of alloc blocks
        MOVEM.L (A6)+,D0-D1                     | restore original registers
        CLR     D7                              | set up fragment length count
BLKALLOC_CONT_3:
        CMP     D7,D4                           | check current length: enough already?
        BLS.B   BLKALLOC_CONT_4                 | if request <= fragment so far, go for it
        CMP     A1,D7                           | reached the edge?
        BEQ.B   BLKALLOC_NO_3                   | if so, fragment wasn't big enough
        TST.L   D0                              | if bit 31 set (allocated block)?
        BMI.B   BLKALLOC_NO_3                   | if so, fragment wasn't big enough
        ADDQ.W  #0x1,D7                         | bump fragment length count
        BSR     READBM_NEXT                     | NextBit: pick up next bit from bitmap
        TST     D1                              | any errors occur?
        BMI     BKALLOCEXIT                     | punt on errors
        BRA.B   BLKALLOC_CONT_3                 | otherwise keep trying
| fragment too small
BLKALLOC_NO_3:
        MOVE.L  (A6)+,D4                        | restore original request size (bytes)
        ADD     D7,D2                           | update starting block
        CMP     A1,D7                           | did we reach to the EOV?
        BCS.B   BLKALLOC_NEXT                   | nope, try this for next position
        BTST    #0xF,D3                         | did we wrap around yet?
        BNE.B   BLKALLOC_EXIT                   | yes, give up: history repeats itself
        BSET    #0xF,D3                         | no, give it another shot
        CLR     D2                              | from the beginning of the volume
BLKALLOC_NEXT:
        BTst    #0xF,D3                         | did we wrap around yet?
        BEQ     BLKALLOC_NO                     | if not, scan on
        SWAP    D3                              | get a hold of the starting block
        CMP     D2,D3                           | are we back where we started?
        BLS.B   BLKALLOC_EXIT                   | if we're beyond the start, quit
        SWAP    D3                              | otherwise, restore D3
        BRA     BLKALLOC_NO                     | and scan on
BLKALLOC_EXIT:
        ROL.L   D1,D0                           | rotate D0 back into place
        MOVE.L  D0,0x0(A0,D6.W)                 | and replace it in the buffer
        BRA     BLKALLOC_EXIT_2                 | exit with DskFulErr, D3=0
| contiguous fragment big enough
BLKALLOC_CONT_4:
        MOVE.L  (A6)+,D4                        | retrieve request size in bytes
        ROL.L   D1,D0                           | restore D0 to original position
        MOVE.L  D0,0x0(A0,D6.W)                 | replace it in the buffer (still clean)
        BSR     ReadBM                          | set up from the current position (D2)
        TST     D1                              | any errors occur?
        BMI     BKALLOCEXIT                     | punt on errors
| bkAllocDoIt: round request to clump size and start allocating
BLKALLOC_NO_4:
        MOVEM.L D0-D1,-(A6)                     | save current bitmap word & bit count
        MOVE.L  D4,D0                           | get requested allocation length (bytes)
        MOVE.L  0x1E(A3),D1                     | get clump size for file (FCBClmpSize)
        JSR     RoundAlloc(PC)                  | divide, rounding up -> size in AlBlks
        MOVE.L  D0,D4                           | stash it away
        MOVEM.L (A6)+,D0-D1                     | retrieve original bitmap word & count
        CLR.L   D7                              | zero out actual allocation counter
| mark blocks allocated from the starting block
BLKALLOC_OK_2:
        TST     D4                              | allocated enough already?
        BEQ.B   BKALLOCOK                       | if so, quit
        CMP     A1,D7                           | is there more here?
        BCC.B   BKALLOCOK                       | if D7 >= A1, reached EOV
        TST.L   D0                              | check bit 31 (current block)
        BMI.B   BKALLOCOK                       | if allocated, stop trying
        TST     vcbFreeBks(A2)                  | does vol think there are bits left?
        BEQ.B   BKALLOCOK                       | nope, we're done
        SUBQ.W  #0x1,vcbFreeBks(A2)             | one fewer now
        JSR     MarkVCB(PC)                     | mark the VCB dirty
        BSET    #0x1F,D0                        | mark current block as allocated
        ADDQ.W  #0x1,D7                         | add one to allocated block count
        SUBQ.W  #0x1,D4                         | subtract one from request size
        JSR     P_mMarkBlock(PC)                | this block is dirty
        BSR     READBM_NEXT                     | NextBit: get next bit from bitmap
        TST     D1                              | check: any errors reading BM?
        BGE.B   BLKALLOC_OK_2                   | if D1>0, all was well
        BRA.B   BKALLOCEXIT                     | otherwise give up (D0 is error code)
| BkAllocOK: allocation is done
BKALLOCOK:
        BTst    #0x7,D3                         | did we start from VCB's AllocPtr?
        BEQ.B   BLKALLOC_NO_5                   | if not, never mind
        MOVE    D2,D4                           | prepare new allocPtr
        CMP     vcbNmAlBlks(A2),D4              | is it at EOV?
        BCS.B   BLKALLOC_OK_3                   | if CS, D4 < NmAlBlks: ok
        CLR     D4                              | if D4 >= NmAlBlks, wrap around
BLKALLOC_OK_3:
        MOVE    D4,vcbAllocPtr(A2)              | update VCB's allocation pointer
BLKALLOC_NO_5:
        ROL.L   D1,D0                           | rotate bitmap word back into place
        MOVE.L  D0,0x0(A0,D6.W)                 | put it back where it came from
        JSR     P_mMarkBlock(PC)                | mark the buffer dirty
        MOVE.L  D7,D3                           | return actual allocation size
        MOVEQ.L #0x0,D0                         | sweet success
| BkAllocExit
BKALLOCEXIT:
        MOVEM.L (A6)+,D1/D4-D7/A0-A1            | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes for return
        RTS                                     | and call it a day
| bkAllocFull
BLKALLOC_EXIT_2:
        MOVEQ.L #0x0,D3                         | no blocks allocated
        MOVEQ.L #-0x22,D0                       | disk is full (DskFulErr)
        BRA.B   BKALLOCEXIT                     | return with error

| P_mBlkDealloc -- deallocate the space.
| ----------------------------------------------------------
|
| P_m Blk Dealloc
|
P_mBlkDealloc:
        MOVE.L  (0x780).w,-(SP)                 | HFS vector: BlkDealloc
        RTS                                     | return

| ----------------------------------------------------------
|
| Blk Dealloc
|
BlkDealloc:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D6/A0,-(A6)                  | save registers for use
        MOVEQ.L #0x0,D0                         | set up completion code
        TST     D3                              | check block count
        BEQ.B   BLKDEALLOC_DONE                 | if zero, we're done
        BSR     ReadBM                          | pick up the relevant bitmap information
BLKDEALLOC_CONT:
        TST     D1                              | any error occur?
        BMI.B   BLKDEALLOC_DONE                 | if not, keep going
        BCLR    #0x1F,D0                        | free up the block
        JSR     P_mMarkBlock(PC)                | call helper
        ADDQ.W  #0x1,vcbFreeBks(A2)             | one more free block on volume
        JSR     MarkVCB(PC)                     | call helper
        SUBQ.W  #0x1,D3                         | decrement blocks remaining
        BEQ.B   BLKDEALLOC_OK                   | ok ->
        BSR     READBM_NEXT                     | call helper
        BRA.B   BLKDEALLOC_CONT                 | continue deallocating
BLKDEALLOC_OK:
        ROL.L   D1,D0                           | rotate D0 back into position
        MOVE.L  D0,0x0(A0,D6.W)                 | put bitmap word back
        MOVEQ.L #0x0,D0                         | success
BLKDEALLOC_DONE:
        MOVEM.L (A6)+,D1-D6/A0                  | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit BlkDealloc

| ----------------------------------------------------------
|
| Blk Chk
|
| BlkChk: check and fix bitmap for extent record blocks
BlkChk:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D7/A1,-(A6)                  | save registers
        MOVE.L  A0,A1                           | A1 = ptr to extent record
        MOVEQ.L #0x0,D3                         | D3 = error flag (0 = ok)
        MOVEQ.L #0x0,D7                         | D7 = extent record offset index
BLKCHK_NEXT:
        MOVE    0x0(A1,D7.W),D2                 | D2 = start alloc block from extent
        MOVEQ.L #0x0,D4                         | clear high word
        MOVE    0x2(A1,D7.W),D4                 | D4 = block count from extent
        BEQ.B   BLKCHK_DONE                     | empty extent, done ->
        BSR.B   ReadBM                          | read bitmap for start block
        BRA.B   BLKCHK_CONT                     | ->
BLKCHK_LOOP:
        BSet    #0x1F,D0                        | mark block as allocated
        BNE.B   BLKCHK_OK                       | was already set ->
        MOVEQ.L #-0x1,D3                        | block was free: flag error
        JSR     P_mMarkBlock(PC)                | mark bitmap dirty
BLKCHK_OK:
        ADDQ.W  #0x1,D2                         | next block number
        ROL.L   #0x1,D0                         | advance to next bit in bitmap word
        SUBQ.W  #0x1,D1                         | decrement bits remaining
        BGT.B   BLKCHK_CONT                     | bits left ->
        TST     D4                              | more blocks to check?
        BEQ.B   BLKCHK_NO                       | no ->
        BSR     READBM_NEXT_2                   | NextWord: get next bitmap word
BLKCHK_CONT:
        TST     D1                              | any error?
        BMI.B   BLKCHK_ERR                      | error ->
        DBF     D4,BLKCHK_LOOP                  | check next block
        ROL.L   D1,D0                           | rotate back
BLKCHK_NO:
        MOVE.L  D0,0x0(A0,D6.W)                 | put bitmap word back
        ADDQ.W  #0x4,D7                         | next extent descriptor (4 bytes each)
        CMPI    #0xC,D7                         | all 3 extents checked? (3*4=12)
        BCS.B   BLKCHK_NEXT                     | no, check next extent ->
BLKCHK_DONE:
        MOVE.L  D3,D0                           | return error flag
BLKCHK_ERR:
        MOVEM.L (A6)+,D1-D7/A1                  | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST.L   D0                              | set condition codes
        RTS                                     | exit BlkChk

| ----------------------------------------------------------
|
| UpdateFree: recount free blocks by scanning entire bitmap
|
UpdateFree:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D0-D6/A0-A1,-(A6)               | save registers
        MOVEQ.L #0x0,D4                         | D4 = free block counter
        MOVEQ.L #0x0,D2                         | start at block 0
        BSR     ReadBM                          | read first bitmap block
        MOVE    vcbNmAlBlks(A2),D2              | D2 = total allocation blocks
UPDATEFREE_CONT:
        TST     D1                              | any error?
        BMI.B   UPDATEFREE_ERR                  | error ->
        TST.L   D0                              | bit 31 clear? (free block)
        BMI.B   UPDATEFREE_NO                   | no, allocated ->
        ADDQ.W  #0x1,D4                         | count free block
UPDATEFREE_NO:
        SUBQ.W  #0x1,D2                         | more blocks to scan?
        BEQ.B   UPDATEFREE_DONE                 | no, done ->
        BSR     READBM_NEXT                     | NextBit: get next bitmap bit
        BRA.B   UPDATEFREE_CONT                 | keep scanning
UPDATEFREE_DONE:
        MOVE    D4,vcbFreeBks(A2)               | update VCB free block count
UPDATEFREE_ERR:
        MOVEM.L (A6)+,D0-D6/A0-A1               | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | exit UpdateFree

| ReadBM -- pick up the bitmap block of interest.
| ----------------------------------------------------------
|
| Read BM
|
| Called by: BLKALLOC_NO, BLKALLOC_CONT, BLKALLOC_CONT_4, BlkDealloc, BLKCHK_NEXT (and 1 more)
ReadBM:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE    D2,D5                           | D5 = alloc block number
        LSR     #0x8,D5                         | divide by 4096
        LSR     #0x4,D5                         | D5 = bitmap disk block index
| ReadBM: read bitmap block for allocation block D2
        MOVE    D2,D6                           | D6 = alloc block number
        ANDI    #0xFE0,D6                       | mask to word boundary (block / 32)
        LSR     #0x3,D6                         | byte offset into bitmap buffer
        MOVE    D2,D1                           | D1 = bit position within word
        ANDI    #0x1F,D1                        | mask to 0-31
        BSR     READBM_NEXT_3                   | GetBMBlk: read the bitmap block
        BEQ.B   READBM_OK                       | ok ->
        MOVEQ.L #-0x1,D1                        | error: set D1 negative
        BRA.B   READBM_CONT                     | ->
READBM_OK:
        MOVE.L  0x0(A0,D6.W),D0                 | D0 = bitmap longword
        ROL.L   D1,D0                           | rotate target bit to bit 31
        NEG     D1                              | D1 = 32 - bit position
        ADDI    #0x20,D1                        | = bits remaining in this word
READBM_CONT:
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | exit ReadBM

| ----------------------------------------------------------
|
| READBM_NEXT - NextBit: advance to next bit in bitmap
|
| Called by: BLKALLOC_CONT_3, BLKALLOC_OK_2, BLKDEALLOC_CONT, UPDATEFREE_NO, READBM_CONT_2
READBM_NEXT:
        MOVE.L  (SP)+,-(A6)                     | save return address
        ROL.L   #0x1,D0                         | rotate to next bit
        SUBQ.W  #0x1,D1                         | decrement bits remaining
        BNE.B   READBM_EXIT                     | more bits in this word ->
        BSR.B   READBM_NEXT_2                   | NextWord: get next bitmap word
READBM_EXIT:
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | exit NextBit

| ----------------------------------------------------------
|
| READBM_CONT_2 - FrBitScan: scan for next free bit, skipping $FFFFFFFF words
|
READBM_CONT_2:
        MOVE.L  (SP)+,-(A6)                     | save return address
        ADDQ.W  #0x1,D2                         | advance past current block
        BSR.B   READBM_NEXT                     | NextBit: get next bit
READBM_CONT_3:
        CMP.L   (MinusOne).w,D0                 | all bits set (all allocated)?
        BNE.B   READBM_EXIT                     | no, found a potential free bit ->
        ADD     D1,D2                           | skip past remaining bits in word
        CMP     A1,D2                           | past end of volume?
        BCC.B   READBM_OK_2                     | yes, back up ->
        BSR.B   READBM_NEXT_2                   | NextWord: get next word
        BRA.B   READBM_CONT_3                   | keep scanning
READBM_OK_2:
        SUB     D1,D2                           | back up starting position
        BRA.B   READBM_EXIT                     | return

| ----------------------------------------------------------
|
| READBM_NEXT_2 - NextWord: get next longword from bitmap buffer
|
READBM_NEXT_2:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVE.L  D0,0x0(A0,D6.W)                 | put current word back in buffer
        ADDQ.W  #0x4,D6                         | advance buffer index by 4 bytes
        CMPI    #0x200,D6                       | past end of 512-byte buffer?
        BCS.B   READBM_NO                       | no, still in same block ->
        ADDQ.W  #0x1,D5                         | next bitmap block number
        BSR     READBM_NEXT_3                   | GetBMBlk: read next bitmap block
        BEQ.B   READBM_OK_3                     | ok ->
        MOVEQ.L #-0x1,D1                        | error: set D1 negative
        BRA.B   READBM_CONT_4                   | ->
READBM_OK_3:
        CLR     D6                              | reset buffer index to start
READBM_NO:
        MOVE.L  0x0(A0,D6.W),D0                 | D0 = next bitmap longword
        MOVEQ.L #0x20,D1                        | D1 = 32 bits in this word
READBM_CONT_4:
        MOVE.L  (A6)+,-(SP)                     | restore return address
        RTS                                     | exit NextWord

| ----------------------------------------------------------
|
| READBM_NEXT_3 - GetBMBlk: read a volume bitmap block from cache
|
READBM_NEXT_3:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D2/A1-A2,-(A6)               | save registers
        MOVE    vcbVRefNum(A2),D0               | volume refnum
        MOVEQ.L #0x0,D2                         | clear high word
        MOVE    vcbVBMSt(A2),D2                 | bitmap start block (VCBVBMSt)
        ADD     D5,D2                           | + bitmap block offset = logical block
        MOVE.L  vcbMAdr(A2),A1                  | bitmap cache queue (VCBMAdr)
        MOVEQ.L #0x8,D1                         | GetBlock with GBrelease option
        JSR     P_mGetBlock(PC)                 | get the bitmap block
        MOVEM.L (A6)+,D1-D2/A1-A2               | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit GetBMBlk

| P_mDeallocFile -- deallocate all file extents.
| ----------------------------------------------------------
|
| P_m Dealloc File
|
P_mDeallocFile:
        MOVE.L  (0x764).w,-(SP)                 | HFS vector: DeallocFile
        RTS                                     | return

| ----------------------------------------------------------
|
| Dealloc File
|
DeallocFile:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D7/A0-A1/A3-A4,-(A6)         | save registers
        BSR     TRUNCATEFILE_CONT_4             | FXSetUp: set up common stuff
        MOVE.L  A0,A3                           | A3 = ptr to CName
        MOVE.L  D0,D7                           | D7 = ParID
        CLR.B   D6                              | D6 = initial fork type (0 = data fork)
| DFFkLoop: locate catalog record for file
DEALLOCFILE_CONT:
        CLR     D4                              | initial FABN
        MOVE.L  A3,A0                           | ptr to CName
        MOVE.L  D7,D0                           | ParID
        CLR.L   D2                              | no hint
        JSR     CMGetCN(PC)                     | locate catalog record
        BNE     DEALLOCFILE_ERR                 | didn't get it ->
        CMPI.B  #0x2,(A1)                       | file CNode? (CMFilCN)
        BEQ.B   DEALLOCFILE_OK                  | yes ->
        MOVEQ.L #0x30,D0                        | result = 'not found' (CMnotfound)
        BNE     DEALLOCFILE_ERR                 | exit ->
DEALLOCFILE_OK:
        MOVE.L  0x14(A1),D5                     | D5 = file number (filFlNum)
        LEA.L   0x2(A4),A0                      | ptr to FXM key buffer (FXVxkrOff)
        CLR     0x6(A0)                         | indicate catalog resident extent record (xkrFABN=0)
        TST.B   D6                              | deleting the data fork?
        BNE.B   DEALLOCFILE_NO                  | no ->
        LEA.L   0x4A(A1),A1                     | position to data fork extent record (filExtRec)
        BRA.B   DEALLOCFILE_FOUND               | copy extent record ->
DEALLOCFILE_NO:
        LEA.L   0x56(A1),A1                     | position to resource fork extent record (filRExtRec)
        BRA.B   DEALLOCFILE_FOUND               | copy extent record ->
| DFRecLoop: set up key for next extent file record
DEALLOCFILE_NEXT:
        LEA.L   0x2(A4),A0                      | A0 = ptr to FXM key buffer
        MOVE.B  #0x7,(A0)                       | key length (lenxkr-1)
        MOVE.B  D6,0x1(A0)                      | fork type (xkrFkType)
        MOVE.L  D5,0x2(A0)                      | file number (xkrFNum)
        MOVE    D4,0x6(A0)                      | file alloc block number (xkrFABN)
| get the next extent record
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        CLR.L   D2                              | no hint
        JSR     P_mBTSearch(PC)                 | find the record
        BEQ.B   DEALLOCFILE_FOUND               | found it ->
        CMPI    #0x20,D0                        | record not found? (BTnotfound)
        BEQ.B   DEALLOCFILE_DONE                | yes, done with this fork ->
        BRA.B   DEALLOCFILE_ERR                 | error ->
| DFCopyRec: copy extent data to FXM buffer
DEALLOCFILE_FOUND:
        LEA.L   0xA(A4),A0                      | dest = xdr buffer in FXM vars (FXVxdrOff)
        MOVEQ.L #0x2,D0                         | loop index in long words (lenxdr/4 - 1)
DEALLOCFILE_LOOP:
        MOVE.L  (A1)+,(A0)+                     | copy the record
        DBF     D0,DEALLOCFILE_LOOP             | loop for 3 longwords (12 bytes)
| DFRelExt: release extents for this record
        LEA.L   0xA(A4),A1                      | A1 = ptr to extent record
        CLR     D1                              | offset to 1st extent
DEALLOCFILE_NEXT_2:
        MOVE    0x0(A1,D1.W),D2                 | starting alloc blk number (xdrStABN)
        MOVE    0x2(A1,D1.W),D3                 | number of alloc blks (xdrNumABlks)
        BEQ.B   DEALLOCFILE_NO_2                | extent not used, delete the record ->
        JSR     P_mBlkDealloc(PC)               | deallocate the space
        BNE.B   DEALLOCFILE_ERR                 | error ->
        ADD     D3,D4                           | bump FABN to beg of next extent
        ADDQ.W  #0x4,D1                         | bump to next extent (lenExt)
        CMPI    #0x8,D1                         | past last extent? (maxExtOff)
        BLE.B   DEALLOCFILE_NEXT_2              | no, release next one ->
| DFDelRec: delete extent record
DEALLOCFILE_NO_2:
        LEA.L   0x2(A4),A0                      | A0 = ptr to search key
        TST     0x6(A0)                         | catalog resident record? (xkrFABN)
        BEQ.B   DEALLOCFILE_OK_2                | yes, nothing to delete ->
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        JSR     P_mBTDelete(PC)                 | delete the record
        BNE.B   DEALLOCFILE_ERR                 | error ->
DEALLOCFILE_OK_2:
        TST     D3                              | end with null extent entry?
        BNE.B   DEALLOCFILE_NEXT                | no, get next record for same fork ->
| DFNxtFork: check for another fork
DEALLOCFILE_DONE:
        NOT.B   D6                              | just finished resource fork ($FF -> $00)?
        BNE     DEALLOCFILE_CONT                | $00 -> $FF: release space for resource fork
| DFExit
        CLR     D0                              | result = ok
        BSR     TRUNCATEFILE_CONT_5             | XFFlush: flush the extent file
DEALLOCFILE_ERR:
        ADDA    #0x16,A6                        | de-allocate FXM vars (lenFXVars)
        MOVEM.L (A6)+,D1-D7/A0-A1/A3-A4         | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | test
        RTS                                     | return

| P_mExtendFile -- extend the file.
| ----------------------------------------------------------
|
| P_m Extend File
|
P_mExtendFile:
        MOVE.L  (0x768).w,-(SP)                 | HFS vector: ExtendFile
        RTS                                     | return

| ----------------------------------------------------------
|
| Extend File
|
| ExtendFile: extend the disk space allocated to a file
ExtendFile:
        MOVE.L  (SP)+,-(A6)                     | save return address
        MOVEM.L D1-D5/D7/A0-A4,-(A6)            | save regs
        BSR     TRUNCATEFILE_CONT_4             | FXSetUp: set up common stuff
        BSET    #0x6,(A4)                       | 1st try contig allocation (FXVTContig)
        TST.B   D3                              | forced contiguous requested? (EFContig)
        BEQ.B   EXTENDFILE_NO                   | no ->
        BSET    #0x7,(A4)                       | set flag
EXTENDFILE_NO:
        LEA.L   0x0(A1,D1.W),A3                 | A3 = FCB pointer
        MOVE.L  0xC(A3),-(A6)                   | save previous PEOF (FCBPLen)
| round # of bytes requested up to next alloc blk
        MOVE.L  vcbAlBlkSiz(A2),D0              | allocation block size
        ADD.L   D0,D4                           | D4 + AlBlkSiz (for rounding up)
        SUBQ.L  #0x1,D4                         | adjust for integer division
        DIVU    D0,D4                           | D4 / AlBlkSiz = blocks needed
        MULU    D0,D4                           | D4 rounded up
| EFLocExt: locate extent mapping new PEOF - 1 (last byte)
        MOVE.L  0xC(A3),D0                      | current PEOF (FCBPLen)
        ADD.L   D4,D0                           | + # of bytes requested = new PEOF
        SUBQ.L  #0x1,D0                         | new PEOF - 1 = last byte in file
        BSR     XFSearch                        | locate the extent
        BNE.B   EXTENDFILE_CONT                 | didn't find it ->
        ADD.L   D4,0xC(A3)                      | update PEOF (FCBPLen)
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        BRA     EXTENDFILE_DONE                 | all done ->
EXTENDFILE_CONT:
        CMPI    #0x10,D0                        | out of range? (FXRangeErr)
        BNE     EXTENDFILE_ERR                  | no, some error ->
        MOVE.L  D2,D7                           | D7 = BTree hint
        MOVE    D3,D6                           | D6 = ending FABN + 1
| adjust PEOF to end of extent
        MOVE    D6,D0                           | (ending FABN + 1)
        MULU    0x1E(A2),D0                     | in bytes = max PEOF for extent
        SUB.L   0xC(A3),D0                      | PEOF already at end of extent?
        BEQ.B   EXTENDFILE_RETRY                | yes ->
        ADD.L   D0,0xC(A3)                      | no, adjust PEOF to end of extent
        BSET    #0x7,0x4(A3)                    | mark FCB dirty
        SUB.L   D0,D4                           | adjust remaining count
| EFAddSpace: allocate additional disk space
EXTENDFILE_RETRY:
        MOVE    0x0(A1,D1.W),D5                 | starting alloc blk number (xdrStABN)
        ADD     0x2(A1,D1.W),D5                 | + # of blks = last blk + 1
EXTENDFILE_CONT_2:
        MOVE    D5,D2                           | preferred starting blk = last blk + 1
        BTST    #0x6,(A4)                       | trying for contig? (FXVTContig)
        SNE.B   D3                              | yes, set flag for BlkAlloc
        JSR     P_mBlkAlloc(PC)                 | allocate the disk space
        BEQ.B   EXTENDFILE_CONT_3               | got it ->
        CMPI    #-0x22,D0                       | disk full error? (DskFulErr)
        BNE     EXTENDFILE_ERR                  | no, some other error ->
        BCLR    #0x6,(A4)                       | did we just try for contig?
        BEQ     EXTENDFILE_ERR                  | no, must be out of space ->
        BTST    #0x7,(A4)                       | forced contig requested? (FXVFContig)
        BNE     EXTENDFILE_ERR                  | yes, couldn't get it ->
        BRA.B   EXTENDFILE_CONT_2               | try non-contig ->
| EFExtExt: see if current extent can be extended
EXTENDFILE_CONT_3:
        CMP     D2,D5                           | get preferred space?
        BNE.B   EXTENDFILE_NO_2                 | no, must add an extent ->
        ADD     D3,0x2(A1,D1.W)                 | add new blks to current extent (xdrNumABlks)
        BRA.B   EXTENDFILE_CONT_4               | use common code ->

| ----------------------------------------------------------
|
| EXTENDFILE_NO_2
|
| EFAddExt: add a new extent entry
EXTENDFILE_NO_2:
        TST     0x2(A1,D1.W)                    | current extent null? (xdrNumABlks)
        BEQ.B   EXTENDFILE_OK                   | yes, use it ->
        ADDQ.W  #0x4,D1                         | bump to next extent (lenExt)
        CMPI    #0x8,D1                         | past last extent? (maxExtOff)
        BGT.B   EXTENDFILE_OK_2                 | yes ->
EXTENDFILE_OK:
        MOVE    D2,0x0(A1,D1.W)                 | set starting alloc blk # (xdrStABN)
        MOVE    D3,0x2(A1,D1.W)                 | and # of blks (xdrNumABlks)
| EFUpdExt: update the extent record
EXTENDFILE_CONT_4:
        MOVE.L  D7,D2                           | BTree hint
        BSR     XFSEARCH_CONT_4                 | XRUpdate: update the extent record
        BNE     EXTENDFILE_ERR                  | error ->
        MOVE.L  D2,D7                           | D7 = new hint
        BRA.B   EXTENDFILE_CONT_5               | go update FCB ->

| ----------------------------------------------------------
|
| EXTENDFILE_OK_2
|
| EFNewRec: add a new extent record
EXTENDFILE_OK_2:
        MOVE.L  (A3),D5                         | D5 = file number (FCBFlNm)
        CMPI.L  #0x3,D5                         | mapping the extents file? (FSXtCNID=3)
        BNE.B   EXTENDFILE_NO_3                 | no ->
        MOVEQ.L #0x11,D0                        | result = 'extent file overflow' (FXOvFlErr)
        BRA.B   EXTENDFILE_ERR                  | exit ->

| ----------------------------------------------------------
|
| EXTENDFILE_NO_3
|
EXTENDFILE_NO_3:
        LEA.L   0x2(A4),A0                      | point to FXM key buffer (FXVxkrOff)
        LEA.L   0xA(A4),A1                      | point to FXM data buffer (FXVxdrOff)
        MOVE.B  #0x7,(A0)                       | key length (lenxkr-1)
        CLR.B   0x1(A0)                         | assume data fork (xkrFkType)
        BTST    #0x1,0x4(A3)                    | mapping resource fork? (FCBRscBit)
        SNE.B   0x1(A0)                         | yes, set resource fork flag
        MOVE.L  D5,0x2(A0)                      | file number (xkrFNum)
        MOVE    D6,0x6(A0)                      | starting FABN (xkrFABN)
| clear new extent record
        MOVE    #0x5,D0                         | (lenxdr/2)-1
EXTENDFILE_LOOP:
        CLR     (A1)+                           | zero a word
        DBF     D0,EXTENDFILE_LOOP              | loop for 6 words (12 bytes)
        LEA.L   0xA(A4),A1                      | restore ptr to xdr
        CLR     D1                              | offset to 1st extent
        MOVE    D2,0x0(A1,D1.W)                 | set starting alloc blk # (xdrStABN)
        MOVE    D3,0x2(A1,D1.W)                 | and # of blks (xdrNumABlks)
        MOVE.L  D1,-(A6)                        | save D1
        MOVE    #0xC,D1                         | record length (lenxdr)
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        JSR     P_mBTInsert(PC)                 | insert the new record
        MOVE.L  (A6)+,D1                        | restore D1
        TST     D0                              | restore BTInsert result
        BNE.B   EXTENDFILE_ERR                  | error ->
        MOVE.L  D2,D7                           | D7 = new hint
| EFUpdFCB: update FCB and see if more space is needed
EXTENDFILE_CONT_5:
        ADD     D3,D6                           | update ending FABN + 1
        MULU    0x1E(A2),D3                     | convert # of blks to bytes (VCBAlBlkSiz+2)
        ADD.L   D3,0xC(A3)                      | adjust PEOF to include new space (FCBPLen)
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        SUB.L   D3,D4                           | allocated enough space?
        BGT     EXTENDFILE_RETRY                | no, do it again ->
        ADD.L   D4,0xC(A3)                      | adjust PEOF to alloc blk boundary
| EFExit
EXTENDFILE_DONE:
        CLR     D0                              | result = ok
        BSR     TRUNCATEFILE_CONT_5             | XFFlush: flush the extent file
EXTENDFILE_ERR:
        MOVE.L  0xC(A3),D6                      | new PEOF (FCBPLen)
        MOVE.L  (A6)+,D1                        | - previous PEOF
        SUB.L   D1,D6                           | = # of bytes allocated
        ADDA    #0x16,A6                        | de-allocate FXM vars
        MOVEM.L (A6)+,D1-D5/D7/A0-A4            | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit ExtendFile

| ----------------------------------------------------------
|
| FXM Key Cmp
|
| FXMKeyCmp: compare two extent file keys
FXMKeyCmp:
        MOVEM.L A0-A1,-(SP)                     | save registers
| compare file ID's
        MOVE.L  0x2(A0),D0                      | compare file numbers (xkrFNum)
        CMP.L   0x2(A1),D0                      | compare search vs. trial file number
        BHI.B   FXMKEYCMP_CONT_2                | search fileNum > trial fileNum ->
        BCS.B   FXMKEYCMP_CONT                  | search fileNum < trial fileNum ->
| file ID's equal, compare fork types
        MOVE.B  0x1(A0),D0                      | compare fork types (xkrFkType)
        CMP.B   0x1(A1),D0                      | compare search vs. trial fork type
        BHI.B   FXMKEYCMP_CONT_2                | search fork > trial fork ->
        BCS.B   FXMKEYCMP_CONT                  | search fork < trial fork ->
| fork types equal, compare starting block numbers
        MOVE    0x6(A0),D0                      | compare block numbers (xkrFABN)
        CMP     0x6(A1),D0                      | compare search vs. trial block num
        BHI.B   FXMKEYCMP_CONT_2                | search block > trial block ->
        BCS.B   FXMKEYCMP_CONT                  | search block < trial block ->
| KCIsEQ
        CLR     D0                              | result = "equal"
        BRA.B   FXMKEYCMP_EXIT                  | return equal
| KCIsLT
FXMKEYCMP_CONT:
        MOVE    #-0x1,D0                        | result = "less than"
        BRA.B   FXMKEYCMP_EXIT                  | return less than
| KCIsGT
FXMKEYCMP_CONT_2:
        MOVE    #0x1,D0                         | result = "greater than"
FXMKEYCMP_EXIT:
        MOVEM.L (SP)+,A0-A1                     | restore regs
        TST     D0                              | test
        RTS                                     | return

| ----------------------------------------------------------
|
| Map F Block
|
| MapFBlock: maps file position to physical disk address (HFS)
MapFBlock:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D2/D4-D5/D7/A0-A1/A3-A4,-(A6) | save registers
        BSR     TRUNCATEFILE_CONT_4             | FXSetUp: set up common stuff
        LEA.L   0x0(A1,D1.W),A3                 | A3 = FCB pointer
| locate the extent mapping the desired file position
        MOVE.L  D5,D0                           | file position
        BSR     XFSearch                        | locate the extent
        BNE.B   MAPFBLOCK_EXIT                  | exit on errors
        LEA.L   0x0(A1,D1.W),A1                 | A1 = ptr to extent entry
        MOVE    D3,D1                           | D1 = beg FABN for extent
        SUB     0x2(A1),D1                      | (ending FABN+1 - numABlks = beg FABN)
        MOVE    D3,D2                           | D2 = end FABN in extent + 1
| determine end of available space (PEOF or end of extent)
        MULU    0x1E(A2),D2                     | convert end FABN+1 to file pos (VCBAlBlkSiz+2)
        MOVE.L  0xC(A3),D0                      | get PEOF (FCBPLen)
        CMP.L   D0,D2                           | end of extent > PEOF?
        BLE.B   MAPFBLOCK_NO                    | no, use end of extent ->
        MOVE.L  D0,D2                           | yes, use PEOF
MAPFBLOCK_NO:
        DIVU    0x1E(A2),D2                     | D2 = end of avail space (end FABN+1)
| set up some constants
        MOVE.L  vcbAlBlkSiz(A2),D6              | D6 = # blks per alloc blk
        DIVU    #0x200,D6                       | (alloc blk size / 512)
        MOVEQ.L #0x0,D7                         | D7 = start blk # for alloc blks
        MOVE    vcbAlBlSt(A2),D7                | volume alloc block start (VCBAlBlSt)
| calculate physical start block
        MOVE.L  D5,D3                           | file position / alloc blk size
        DIVU    0x1E(A2),D3                     | = FABN mapping file position
        SWAP    D3                              | get remainder in low word
        MOVEQ.L #0x0,D0                         | compute block offset within alloc block
        MOVE    D3,D0                           | D0 = remainder (bytes into alloc block)
        LSR.L   #0x8,D0                         | / 256
        LSR.L   #0x1,D0                         | / 2 = offset in phys blocks
        SWAP    D3                              | restore FABN
        SUB     D1,D3                           | - beg FABN = alloc blk delta
        ADD     (A1),D3                         | + starting ABN (xdrStABN)
        MULU    D6,D3                           | convert to physical block #
        ADD     D0,D3                           | + offset within alloc block
        ADD.L   D7,D3                           | + alloc block start on volume
| calculate number of available bytes
        MOVE    D2,D6                           | end FABN+1 * alloc blk size
        MULU    0x1E(A2),D6                     | = ending file pos + 1
        SUB.L   D5,D6                           | - file position = size avail
        CMP.L   D4,D6                           | compare with desired number
        BCS.B   MAPFBLOCK_CONT                  | < D4 bytes, leave it alone
        MOVE.L  D4,D6                           | > D4 bytes, set to D4 bytes
MAPFBLOCK_CONT:
        MOVEQ.L #0x0,D0                         | we're ok
| MFExit
MAPFBLOCK_EXIT:
        ADDA    #0x16,A6                        | de-allocate FXM vars
        MOVEM.L (A6)+,D1-D2/D4-D5/D7/A0-A1/A3-A4 | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set CCR for result
        RTS                                     | exit MapFBlock

| P_mTruncateFile -- truncateFile: truncate to rounded length.
| ----------------------------------------------------------
|
| P_m Truncate File
|
P_mTruncateFile:
        MOVE.L  (0x76C).w,-(SP)                 | HFS vector: TruncateFile
        RTS                                     | return

| ----------------------------------------------------------
|
| Truncate File
|
TruncateFile:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D7/A0-A4,-(A6)               | save registers
        BSR     TRUNCATEFILE_CONT_4             | FXSetUp: set up common stuff
        LEA.L   0x0(A1,D1.W),A3                 | A3 = FCB pointer
        BTST    #0x1,0x4(A3)                    | mapping resource fork? (FCBRscBit)
        SNE.B   D6                              | D6 = option flags
| TFLocExt: locate extent mapping last byte of truncated file
        MOVE.L  D3,D5                           | D5 = new PEOF
        MOVE.L  vcbAlBlkSiz(A2),D0              | round the new PEOF
        ADD.L   D0,D5                           | D5 + AlBlkSiz (for rounding up)
        SUBQ.L  #0x1,D5                         | adjust for integer division
        DIVU    D0,D5                           | D5 / AlBlkSiz = blocks needed
        MULU    D0,D5                           | up to next alloc blk
        MOVE.L  D5,D0                           | new PEOF - 1 = last byte in file
        SUBQ.L  #0x1,D0                         | point to last byte of file
        BGE.B   TRUNCATEFILE_CONT               | new PEOF > 0 ->
| truncating to zero: release all extents
        MOVE.L  D5,0xC(A3)                      | update PEOF in FCB (FCBPLen)
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        SUBA.L  A0,A0                           | indicate FCB resident record
        MOVEQ.L #0x0,D7                         | no hint
        LEA.L   0x26(A3),A1                     | point to FCB extent record (FCBExtRec)
        CLR     D4                              | last FABN in extent + 1
        BRA     TRUNCATEFILE_CONT_3             | release all extents ->
TRUNCATEFILE_CONT:
        BSR     XFSearch                        | locate the extent
        BNE     TRUNCATEFILE_ERR                | error ->
        MOVE.L  D2,D7                           | D7 = BTree hint
        MOVE    D3,D4                           | D4 = last FABN in extent + 1
        MOVE.L  D5,0xC(A3)                      | update PEOF in FCB (FCBPLen)
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        TST.B   (FlushOnly).w                   | truncate to end of extent? (TFTrunExt)
        BEQ.B   TRUNCATEFILE_NO                 | no, truncate to new PEOF ->
        MOVE    0x2(A1,D1.W),D3                 | D3 = # of blks in extent (xdrNumABlks)
        BRA     TRUNCATEFILE_EMPTY              | release remaining extents in record ->
| TFTrunPEOF: truncate extent containing new PEOF
TRUNCATEFILE_NO:
        MOVE.L  D5,D0                           | new PEOF - 1 (last byte in file)
        SUBQ.L  #0x1,D0                         | point to last byte of truncated file
        DIVU    0x1E(A2),D0                     | / alloc blk size = last FABN in file
        SUB     D0,D3                           | (last extent FABN+1) - (last file FABN)
        SUBQ.W  #0x1,D3                         | - 1 = # to deallocate
        BEQ.B   TRUNCATEFILE_CONT_2             | nothing to deallocate ->
        MOVE    0x0(A1,D1.W),D2                 | starting ABN (xdrStABN)
        ADD     0x2(A1,D1.W),D2                 | + # alloc blks in extent
        SUB     D3,D2                           | - # to dealloc = starting ABN to free
        JSR     P_mBlkDealloc(PC)               | deallocate the space
        BNE     TRUNCATEFILE_ERR                | error ->
TRUNCATEFILE_CONT_2:
        MOVE    D3,D0                           | D0 = # of blks deallocated
        MOVE    0x2(A1,D1.W),D3                 | D3 = orig # of blks (xdrNumABlks)
        SUB     D0,0x2(A1,D1.W)                 | update # of blks in extent
        BNE.B   TRUNCATEFILE_EMPTY              | extent not empty ->
        CLR     0x0(A1,D1.W)                    | set extent null (xdrStABN)
        BRA.B   TRUNCATEFILE_EMPTY              | release remaining extents in record ->
| TFLoop: get next extent record in BTree
TRUNCATEFILE_NEXT:
        LEA.L   0x2(A4),A0                      | A0 = ptr to search key buffer (FXVxkrOff)
        MOVE.B  #0x7,(A0)                       | key length (lenxkr-1)
        MOVE.B  D6,0x1(A0)                      | fork type (xkrFkType)
        MOVE.L  (A3),0x2(A0)                    | file number (xkrFNum = FCBFlNm)
        MOVE    D4,0x6(A0)                      | file alloc block number (xkrFABN)
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        CLR.L   D2                              | no hint
        JSR     P_mBTSearch(PC)                 | find the record
        BEQ.B   TRUNCATEFILE_FOUND              | found it ->
        CMPI    #0x20,D0                        | record not found? (BTnotfound)
        BEQ.B   TRUNCATEFILE_DONE               | yes, all done ->
        BRA.B   TRUNCATEFILE_ERR                | error ->
TRUNCATEFILE_FOUND:
        MOVE.L  D2,D7                           | save hint in D7
| copy extent data to FXM buffer
        LEA.L   0xA(A4),A0                      | dest = xdr buffer in FXM vars (FXVxdrOff)
        MOVEQ.L #0x2,D0                         | loop index in long words (lenxdr/4 - 1)
TRUNCATEFILE_LOOP:
        MOVE.L  (A1)+,(A0)+                     | copy the record
        DBF     D0,TRUNCATEFILE_LOOP            | loop for 3 longwords (12 bytes)
        LEA.L   0x2(A4),A0                      | A0 = ptr to search key
        LEA.L   0xA(A4),A1                      | A1 = ptr to extent record
| TFRelExt: release extents for this record
TRUNCATEFILE_CONT_3:
        CLR     D1                              | offset to 1st extent
TRUNCATEFILE_NEXT_2:
        MOVE    0x0(A1,D1.W),D2                 | starting alloc blk number (xdrStABN)
        MOVE    0x2(A1,D1.W),D3                 | number of alloc blks (xdrNumABlks)
        BEQ.B   TRUNCATEFILE_NO_2               | extent not used, update the record ->
        JSR     P_mBlkDealloc(PC)               | deallocate the space
        BNE.B   TRUNCATEFILE_ERR                | error ->
        CLR.L   0x0(A1,D1.W)                    | set the extent null
        ADD     D3,D4                           | bump FABN to beg of next extent
| TFRelRExt
TRUNCATEFILE_EMPTY:
        ADDQ.W  #0x4,D1                         | bump to next extent (lenExt=4)
        CMPI    #0x8,D1                         | past last extent? (maxExtOff=8)
        BLE.B   TRUNCATEFILE_NEXT_2             | no, release next one ->
| TFUpdRec: update extent record
TRUNCATEFILE_NO_2:
        TST     0x2(A1)                         | 1st extent null? (xdrNumABlks)
        BEQ.B   TRUNCATEFILE_OK                 | yes, delete record ->
        MOVE.L  D7,D2                           | BTree hint
        BSR     XFSEARCH_CONT_4                 | XRUpdate: update the record
        BRA.B   TRUNCATEFILE_OK_2               | ->

| ----------------------------------------------------------
|
| TRUNCATEFILE_OK
|
TRUNCATEFILE_OK:
        MOVE.L  A0,D0                           | FCB resident record?
        BEQ.B   TRUNCATEFILE_OK_2               | yes, nothing to delete ->
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        JSR     P_mBTDelete(PC)                 | delete the record
        BNE.B   TRUNCATEFILE_ERR                | error ->
TRUNCATEFILE_OK_2:
        TST     D3                              | end with null extent entry?
        BNE.B   TRUNCATEFILE_NEXT               | no, continue with next record ->
| TFExit
TRUNCATEFILE_DONE:
        CLR     D0                              | result = ok
        BSR.B   TRUNCATEFILE_CONT_5             | XFFlush: flush the extent file
TRUNCATEFILE_ERR:
        ADDA    #0x16,A6                        | de-allocate FXM vars (lenFXVars)
        MOVEM.L (A6)+,D1-D7/A0-A4               | restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | set condition codes
        RTS                                     | exit TruncateFile

| ----------------------------------------------------------
|
| TRUNCATEFILE_CONT_4 - FXSetUp: allocate FXM vars on A6 stack
|
TRUNCATEFILE_CONT_4:
        SUBA    #0x16,A6                        | allocate FXM vars (lenFXVars)
        MOVE.L  A6,A4                           | A4 = pointer to FXM vars
        CLR.B   (A4)                            | clear all flags (FXVFlags)
        RTS                                     | exit FXSetUp

| ----------------------------------------------------------
|
| TRUNCATEFILE_CONT_5
|
| XFFlush: flush the extent file for a specified volume
TRUNCATEFILE_CONT_5:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/A1,-(A6)                     | save registers
        MOVE    0xA4(A2),D1                     | D1 = refnum of extent file (VCBXTRef)
        MOVE    D1,D0                           | flush the extent BTree
        JSR     P_mBTFlush(PC)                  | flush B-tree to disk
        BNE.B   TRUNCATEFILE_ERR_2              | error ->
        MOVE.L  (FCBSPtr).w,A1                  | FCB dirty? (FCBModBit)
        BTST    #0x7,0x4(A1,D1.W)               | test dirty bit in FCB flags
        BEQ.B   TRUNCATEFILE_DONE_2             | no, all done ->
        JSR     MarkVCB(PC)                     | mark the VCB dirty
        JSR     FlushMDB(PC)                    | flush the MDB
        BNE.B   TRUNCATEFILE_ERR_2              | error ->
TRUNCATEFILE_DONE_2:
        CLR     D0                              | result = 'ok'
TRUNCATEFILE_ERR_2:
        MOVEM.L (A6)+,D1/A1                     | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit XFFlush

| ----------------------------------------------------------
|
| XF Search
|
| XFSearch: search extent file for extent mapping a file position
XFSearch:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D4-D6,-(A6)                     | save regs
        MOVE.L  D0,D4                           | D4 = file position to be mapped
        DIVU    0x1E(A2),D4                     | convert to FABN (VCBAlBlkSiz+2)
        MOVE.L  (A3),D5                         | D5 = file number (FCBFlNm)
| FSSchFCB: search FCB extent record first
        SUBA.L  A0,A0                           | indicate FCB resident record
        MOVEQ.L #0x0,D2                         | no hint
        LEA.L   0x26(A3),A1                     | point to extent record (FCBExtRec)
        MOVE    D4,D0                           | desired FABN
        CLR     D3                              | starting FABN
        BSR     XFSEARCH_CONT_2                 | XRSearch: search record for extent entry
        BEQ     XFSEARCH_FOUND_2                | found it ->
        CMPI    #0x8,D1                         | end before last extent entry? (maxExtOff)
        BLT     XFSEARCH_ERR                    | yes, no more extents ->
        TST     0x2(A1,D1.W)                    | end with a null extent? (xdrNumABlks)
        BEQ     XFSEARCH_ERR                    | yes, no more extents ->
        CMPI.L  #0x3,D5                         | mapping the extents file? (FSXtCNID)
        BEQ     XFSEARCH_ERR                    | yes, no more extents ->
| FSSchFile: locate desired record in extents file
        LEA.L   0x2(A4),A0                      | A0 = ptr to key buffer (FXVxkrOff)
        MOVE.B  #0x7,(A0)                       | key length (lenxkr-1)
        BTST    #0x1,0x4(A3)                    | mapping resource fork? (FCBRscBit)
        SNE.B   D6                              | D6 = fork flag
        MOVE.B  D6,0x1(A0)                      | fork type (xkrFkType)
        MOVE.L  D5,0x2(A0)                      | file number (xkrFNum)
        MOVE    D4,0x6(A0)                      | desired FABN (xkrFABN)
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        CLR.L   D2                              | no hint
        JSR     P_mBTSearch(PC)                 | search BTree for extent record
        BEQ.B   XFSEARCH_FOUND                  | a direct hit ->
        CMPI    #0x20,D0                        | result = 'not found'? (BTnotfound)
        BNE.B   XFSEARCH_ERR                    | no, error ->
        MOVE    0xA4(A2),D0                     | extents file refnum
        MOVEQ.L #-0x1,D1                        | indicate previous record
        JSR     P_mBTGetRecord(PC)              | get previous extent record
        BEQ.B   XFSEARCH_CONT                   | got it ->
        CMPI    #0x20,D0                        | result = 'not found'?
        BEQ.B   XFSEARCH_OK                     | yes, no extent record ->
        BRA.B   XFSEARCH_ERR                    | error ->
XFSEARCH_CONT:
        CMP.L   0x2(A0),D5                      | same file? (xkrFNum)
        BNE.B   XFSEARCH_OK                     | no ->
        CMP.B   0x1(A0),D6                      | same fork? (xkrFkType)
        BEQ.B   XFSEARCH_FOUND                  | yes, we got it ->
| FSMissed: didn't find extent record, return pointing to last extent in FCB
XFSEARCH_OK:
        SUBA.L  A0,A0                           | indicate FCB resident record
        MOVEQ.L #0x0,D2                         | no hint
        LEA.L   0x26(A3),A1                     | point to FCB extent record
        MOVE    #0x8,D1                         | the last extent (maxExtOff)
        MOVEQ.L #0x10,D0                        | result = 'range error' (FXRangeErr)
        BRA.B   XFSEARCH_ERR                    | exit ->

| ----------------------------------------------------------
|
| XFSEARCH_FOUND
|
| FSCopyRec: found extent record, copy key and data into FXM vars
XFSEARCH_FOUND:
        MOVE.L  A1,-(SP)                        | save ptr(xdr) in cache buffer
        LEA.L   0x2(A4),A1                      | dest = key buffer in FXM vars (FXVxkrOff)
        MOVEQ.L #0x1,D0                         | loop index (lenxkr/4 - 1)
XFSEARCH_LOOP:
        MOVE.L  (A0)+,(A1)+                     | copy the key record
        DBF     D0,XFSEARCH_LOOP                | loop for 2 longwords (8 bytes)
        MOVE.L  (SP)+,A0                        | source = xdr in cache buffer
        LEA.L   0xA(A4),A1                      | dest = xdr in FXM vars (FXVxdrOff)
        MOVEQ.L #0x2,D0                         | loop index (lenxdr/4 - 1)
XFSEARCH_LOOP_2:
        MOVE.L  (A0)+,(A1)+                     | copy the data record
        DBF     D0,XFSEARCH_LOOP_2              | loop for 3 longwords (12 bytes)
| FSSchRec: search record for desired extent entry
        LEA.L   0x2(A4),A0                      | A0 = ptr to xkr in FXM vars
        LEA.L   0xA(A4),A1                      | A1 = ptr to xdr in FXM vars
        MOVE    0x6(A0),D3                      | D3 = beg FABN for extent record (xkrFABN)
        MOVE    D4,D0                           | desired FABN
        BSR     XFSEARCH_CONT_2                 | XRSearch: search record for desired FABN
        BNE.B   XFSEARCH_ERR                    | didn't find it ->
| FSExit
XFSEARCH_FOUND_2:
        CLR     D0                              | result = ok
XFSEARCH_ERR:
        MOVEM.L (A6)+,D4-D6                     | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit XFSearch

| ----------------------------------------------------------
|
| XFSEARCH_CONT_2
|
| XRSearch: search extent record for extent mapping a given FABN
| D0=desired FABN, A1=ptr to xdr, D3=beginning FABN for record
XFSEARCH_CONT_2:
        MOVE.L  D2,-(SP)                        | save regs
        MOVE    D0,D2                           | D2 = desired FABN
        CLR     D1                              | D1 = initial offset
XFSEARCH_NO:
        MOVE    0x2(A1,D1.W),D0                 | number of alloc blks in extent (xdrNumABlks)
        BEQ.B   XFSEARCH_EMPTY                  | null extent ->
        ADD     D0,D3                           | ending FABN + 1
        CMP     D2,D3                           | desired FABN within this extent?
        BHI.B   XFSEARCH_DONE                   | yes, all done ->
        ADDQ.W  #0x4,D1                         | bump to next extent (lenExt)
        CMPI    #0x8,D1                         | past last extent? (maxExtOff)
        BLE.B   XFSEARCH_NO                     | no, continue search ->
XFSEARCH_EMPTY:
        SUBQ.W  #0x4,D1                         | back up to previous extent
        BGE.B   XFSEARCH_CONT_3                 | still within the record ->
        CLR     D1                              | reset to 1st extent
XFSEARCH_CONT_3:
        MOVEQ.L #0x10,D0                        | result = 'range error' (FXRangeErr)
        BRA.B   XFSEARCH_EXIT                   | exit ->
| RSExit
XFSEARCH_DONE:
        CLR     D0                              | result = ok
XFSEARCH_EXIT:
        MOVE.L  (SP)+,D2                        | restore regs
        TST     D0                              | set condition codes
        RTS                                     | exit XRSearch

| ----------------------------------------------------------
|
| XFSEARCH_CONT_4 - XRUpdate: update the current extent record
|
XFSEARCH_CONT_4:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/A0-A1,-(A6)                  | save registers
        MOVE.L  A0,D0                           | FCB resident record?
        BNE.B   XFSEARCH_NO_2                   | no, must update extents file ->
        BSET    #0x7,0x4(A3)                    | mark FCB dirty (FCBModBit)
        BRA.B   XFSEARCH_DONE_2                 | all done ->
| RUUpdFile: re-locate and update extent file record
XFSEARCH_NO_2:
        MOVE    0xA4(A2),D0                     | extents file refnum (VCBXTRef)
        JSR     P_mBTSearch(PC)                 | re-locate the extent file record
        BNE.B   XFSEARCH_ERR_2                  | error ->
        LEA.L   0xA(A4),A0                      | source = xdr in FXM vars (FXVxdrOff)
        MOVEQ.L #0x2,D0                         | loop index (lenxdr/4 - 1)
XFSEARCH_LOOP_3:
        MOVE.L  (A0)+,(A1)+                     | update the xdr in cache buffer
        DBF     D0,XFSEARCH_LOOP_3              | loop for 3 longwords (12 bytes)
        MOVE    0xA4(A2),D0                     | extents file refnum
        JSR     P_mBTUpdate(PC)                 | update BTree record
        BNE.B   XFSEARCH_ERR_2                  | error ->
XFSEARCH_DONE_2:
        CLR     D0                              | result = 'ok'
XFSEARCH_ERR_2:
        MOVEM.L (A6)+,D1/A0-A1                  | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit XRUpdate
