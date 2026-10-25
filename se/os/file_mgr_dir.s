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

| _OpenRF: open resource fork
OPENRF:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    CLR.B       (RegRsrc).W                     | not a regular resource open
    BRA.B       FILEOPEN_CONT                   | join Open path
| _Open: open data fork (vectored through $784)
FILEOPEN:
    MOVE.L      (0x784).W,-(A7)                 | indirect jump via Open vector
    RTS                                         | jump to vector target
VFILEOPEN:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    ST.B        (RegRsrc).W                     | mark as regular resource open
| find a free FCB for the file
FILEOPEN_CONT:
    BSR.B       HFSE_CONT_14                    | Gt1stFCB: get first FCB
FILEOPEN_CONT_2:
    TST.L       0x0(A1,D1.W)                    | FCBFlNm: slot free?
    BEQ.B       CHKVOL                          | yes: use this FCB
    BSR.B       HFSE_NEXT                       | GtNxtFCB: next FCB
    BCS.B       FILEOPEN_CONT_2                 | more: keep scanning
    MOVEQ.L     #-0x2A,D0                       | tmfoErr (-42): too many files
FILEOPEN_TOO_MANY_FILES:
    CLR.W       0x18(A0)                        | ioRefNum = 0 (invalid)
FILEOPEN_EXIT:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| found a free FCB: resolve file and set up FCB
CHKVOL:
    MOVE.W      D1,0x18(A0)                     | ioRefNum = FCB offset
    ADD.L       A1,D1                           | D1 = absolute FCB address
    BSR.W       P_FndFilName                    | resolve filename to catalog
    BNE.B       FILEOPEN_TOO_MANY_FILES         | error: exit
| zero out the FCB (47 words = 94 bytes)
    MOVE.L      A0,-(A7)                        | save param block ptr
    MOVEA.L     D1,A0                           | A0 = FCB to clear
    MOVEQ.L     #0x2E,D0                        | 47 words to clear
FILEOPEN_LOOP:
    CLR.W       (A0)+                           | zero FCB word
    DBF.W       D0,FILEOPEN_LOOP                | loop all words
    MOVEA.L     (A7)+,A0                        | restore param block ptr
| HFS or MFS open path?
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.W       CREATE_NO_5                     | MFS: MFS open path
| HFS open: verify file record found in catalog
    MOVEQ.L     #-0x2B,D0                       | fnOpnErr (-43): file not open
    CMPI.B      #0x2,(A5)                       | cdrFilRec (file record)?
    BNE.B       FILEOPEN_TOO_MANY_FILES         | no: error
| set up FCB from HFS catalog record
    MOVEA.L     D1,A3                           | A3 = FCB address
    MOVE.L      D7,0x36(A3)                     | FCBCatPos = catalog hint
    MOVE.L      0x4(A5),D0                      | file type from catalog (fdType)
    MOVE.L      D0,0x32(A3)                     | FCBFType = file type
    MOVE.L      D6,0x3A(A3)                     | FCBDirID = parent directory ID
| set up clump size
    MOVEQ.L     #0x0,D0                         | clear top word
    MOVE.W      0x48(A5),D0                     | file's clump size (FilClpSize)
    BEQ.B       FILEOPEN_EMPTY                  | none: use volume default
    MULU.W      0x1E(A2),D0                     | multiply by alloc block size
    BSET        #0x6,0x4(A3)                    | set FCBOwnClp flag
    BRA.B       FILEOPEN_CONT_4                 | go set clump size
FILEOPEN_EMPTY:
    MOVE.L      0x20(A2),D0                     | volume's clump size (vcbClpSiz)
    BCLR        #0x6,0x4(A3)                    | clear own-clump-size flag
FILEOPEN_CONT_4:
    MOVE.L      D0,0x1E(A3)                     | FCBClmpSize = clump size
| copy extent record from catalog to FCB
    MOVEM.L     A0-A1,-(A7)                     | save scratch registers
    MOVEQ.L     #0xC,D0                         | extent record length (lenXDR)
    LEA.L       0x4A(A5),A0                     | data fork extents (FilExtRec)
    TST.B       (RegRsrc).W                     | opening data fork?
    BNE.B       FILEOPEN_CONT_5                 | yes: use data extents
    LEA.L       0x56(A5),A0                     | resource fork extents
FILEOPEN_CONT_5:
    LEA.L       0x26(A3),A1                     | FCBExtRec in FCB
    _BlockMove                                  | copy extent record
| copy CName into FCB
    MOVEQ.L     #0x0,D0                         | clear top half of D0
    MOVE.W      D2,D0                           | D0 = name length
    MOVEA.L     A4,A0                           | A0 = filename in pathname
    LEA.L       0x3E(A3),A1                     | A1 = FCBCName in FCB
    MOVE.B      D0,(A1)+                        | store CName length byte
    _BlockMove                                  | copy name string
    MOVEM.L     (A7)+,A0-A1                     | restore scratch registers
| set up file info from catalog record
    CLR.W       D7                              | D7 = 0 (no write count yet)
    MOVE.W      0x2(A5),D3                      | get file flags (filFlags)
    ANDI.W      #0x100,D3                       | isolate file-locked bit
    BEQ.B       FILEOPEN_NO                     | not locked
    BSET        #0xD,D3                         | set FCB locked flag
FILEOPEN_NO:
| load fork info from catalog record
    LEA.L       0x14(A5),A5                     | point to data fork info
    MOVE.L      (A5)+,D2                        | D2 = file number (filFlNum)
    MOVE.W      (A5)+,D4                        | D4 = data start block (filStBlk)
    MOVE.L      (A5)+,D5                        | D5 = data logical EOF (filLgLen)
    MOVE.L      (A5)+,D6                        | D6 = data physical EOF (filPyLen)
    TST.B       (RegRsrc).W                     | opening data fork?
    BNE.B       FILEOPEN_CONT_6                 | yes: use data fork info
    BSET        #0x9,D3                         | set resource fork flag
    MOVE.W      (A5)+,D4                        | D4 = rsrc start block (filRStBlk)
    MOVE.L      (A5)+,D5                        | D5 = rsrc logical EOF (filRLgLen)
    MOVE.L      (A5)+,D6                        | D6 = rsrc physical EOF (filRPyLen)
FILEOPEN_CONT_6:
| check file permissions
    BSR.B       P_PermssnChk                    | PermssnChk: check access permissions
    BEQ.B       SETUPFCB                        | ok: fill in FCB
| permission denied: zero the FCB and exit
    MOVEQ.L     #0x2E,D1                        | (FCB length / 2) - 1
FILEOPEN_LOOP_2:
    CLR.W       (A3)+                           | clear the FCB
    DBF.W       D1,FILEOPEN_LOOP_2              | until all done
    BRA.W       FILEOPEN_EXIT                   | CmdDone with error
| SetupFCB: fill in the FCB fields
SETUPFCB:
    MOVE.L      D2,(A3)+                        | FCBFlNm = file number
    MOVE.W      D3,(A3)+                        | FCBMdRByt + flags
    MOVE.W      D4,(A3)+                        | FCBStBlk = start block
    MOVE.L      D5,(A3)+                        | FCBEOF = logical EOF
    MOVE.L      D6,(A3)+                        | FCBPLen = physical EOF
    CLR.L       (A3)+                           | FCBCrPs = 0 (current position)
    MOVE.L      A2,(A3)+                        | FCBVPtr = VCB pointer
    MOVEA.L     0x1C(A0),A4                     | get ioBuffer (user's own buffer)
    MOVE.L      A4,D0                           | have a buffer?
    BEQ.B       FILEOPEN_NO_2                   | no: skip buffer setup
| set up user's own buffer as cache entry
    CLR.L       (A4)+                           | clear forward link
    CLR.L       (A4)+                           | clear backward link
    CLR.W       (A4)                            | clear flags
    BSET        #0x5,(A4)                       | mark as empty (CBHempty)
    ADDQ.W      #0x2,A4                         | skip past flags word
FILEOPEN_NO_2:
    MOVE.L      A4,(A3)+                        | FCBBfAdr = own buffer ptr
    MOVE.W      D7,(A3)+                        | FCBFlPos = 0
    ADDQ.L      #0x4,A3                         | skip FCBClmpSize (already set)
    CLR.L       (A3)+                           | FCBBTCBPtr = nil (no B-tree)
| scan for other open forks of same file
    BSET        #0x7,0x5(A2)                    | set volume modified flag (VCBFlags)
    MOVE.W      0x18(A0),D4                     | this file's refnum
    BSR.W       HFSE_CONT_15                    | Gt1stMatch: find first matching FCB
FILEOPEN_FOUND:
    CMP.W       D1,D4                           | same as our refnum? (skip self)
    BEQ.B       FILEOPEN_SKIP                   | yes: skip to next match
    MOVE.B      0x4(A1,D1.W),D5                 | other FCB's flags (FCBMdRByt)
    MOVE.B      D5,D6                           | compare fork types
    EOR.B       D3,D6                           | XOR to check resource/data match
    LSR.B       #0x2,D6                         | fork bit into carry
    BCC.B       FILEOPEN_CONT_7                 | same fork: adjust permissions
FILEOPEN_SKIP:
    BSR.W       HFSE_ERR_9                      | GtNxtMatch: find next matching FCB
    BEQ.B       FILEOPEN_FOUND                  | found another match
    BRA.B       CHECK_FORK_ALREADY_OPEN_DONE    | no more matches: done
| found another FCB for same fork: adjust EOF
FILEOPEN_CONT_7:
    JSR         P_AdjEof(PC)                    | AdjEOF: adjust for other open forks
    MOVE.B      D5,0x4(A1,D1.W)                 | update other FCB's flags
CHECK_FORK_ALREADY_OPEN_DONE:
    MOVEQ.L     #0x0,D0                         | no error
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| P_Permssn Chk
|
| Called during boot.
P_PermssnChk:
    MOVE.L      (0x788).W,-(A7)                 | HFS vector: PermssnChk
    RTS                                         | jump via vector
| PermssnChk: check file access permissions
VPERMSSNCHK:
    CMPI.B      #0x1,0x1B(A0)                   | read-only? (ioPermssn = fsCurPerm)
    BEQ.B       PERMSSNCHK_OK_2                 | yes: always allowed
    BSET        #0x8,D3                         | set write-permission flag
    BEQ.B       PERMSSNCHK_OK                   | was clear: first open with write
| file already open with write permission
    TST.B       0x1B(A0)                        | shared access? (fsRdPerm = 0)
    BEQ.B       PERMSSNCHK_OK_2                 | yes: downgrade to read-only
    CLR.W       0x18(A0)                        | make ioRefNum invalid
    MOVEQ.L     #-0x36,D0                       | opWrErr (-54): already open for write
    BRA.B       PERMSSNCHK_EXIT                 | exit with error
| first open with write permission
PERMSSNCHK_OK:
    BTST        #0x2,0x1B(A0)                   | deny-read requested? (fsRdDenyPerm)
    BEQ.B       PERMSSNCHK_NO                   | no
    BSET        #0xC,D3                         | set deny-read flag
PERMSSNCHK_NO:
    BRA.B       PERMSSNCHK_CONT                 | go scan for conflicts
| read-only or downgraded access
PERMSSNCHK_OK_2:
    BCLR        #0x8,D3                         | clear write-permission flag
    MOVEQ.L     #0x0,D0                         | no error
PERMSSNCHK_EXIT:
    RTS                                         | exit PermssnChk
| FCBScan: check for permission conflicts with other open FCBs
PERMSSNCHK_CONT:
    BSR.W       HFSE_CONT_15                    | Gt1stMatch: find first matching FCB
PERMSSNCHK_CONT_2:
    BNE.B       PERMSSNCHK_NO_CONFLICT          | no more matches: ok
    MOVE.W      0x4(A1,D1.W),D0                 | other FCB's flags (FCBMdRByt)
    EOR.W       D3,D0                           | compare file/fork bits
    ANDI.W      #0x300,D0                       | same file and fork type?
    BNE.B       PERMSSNCHK_NO_2                 | no: different fork, skip
    BTST        #0xC,D3                         | deny-read requested?
    BEQ.B       PERMSSNCHK_NO_3                 | no: conflict found
    BTST        #0x4,0x4(A1,D1.W)               | other has write permission?
    BEQ.B       PERMSSNCHK_NO_3                 | no: conflict found
PERMSSNCHK_NO_2:
    BSR.W       HFSE_ERR_9                      | GtNxtMatch: find next matching FCB
    BRA.B       PERMSSNCHK_CONT_2               | keep scanning
| conflict found: file already open
PERMSSNCHK_NO_3:
    MOVE.W      D1,0x18(A0)                     | return conflicting refnum
    MOVEQ.L     #-0x31,D0                       | fLckdErr (-49): file in use
    BRA.B       PERMSSNCHK_EXIT_2               | exit with error
| no conflicts found
PERMSSNCHK_NO_CONFLICT:
    MOVEQ.L     #0x0,D0                         | no error
PERMSSNCHK_EXIT_2:
    RTS                                         | exit PermssnChk
CREATEDIR:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSET        #0x1,(HFSFlags)                 | set CreateDir flag
    BRA.B       CREATE_TRY_RESOLVE              | shared create path
FILECREATE:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BCLR        #0x1,(HFSFlags)                 | clear CreateDir flag (file create)
CREATE_TRY_RESOLVE:
    BSR.W       P_FndFilName                    | resolve filename to catalog
    BNE.B       CREATE_NAME_NOT_FOUND           | not found: ok to create
    MOVEQ.L     #-0x30,D0                       | dupFNErr (-48): name already exists
    BRA.B       CREATE_DONE                     | exit with error
| name not found: check error and volume type
CREATE_NAME_NOT_FOUND:
    CMPI.W      #0xFFD5,D0                      | fnfErr (-43)?
    BNE.B       CREATE_DONE                     | other error: exit
    BSR.W       SETVOLINFO_HFS_CONT_3           | check write protect
    BNE.B       CREATE_DONE                     | write-protected: exit
    BSR.W       TFSVCBTST                       | HFS volume?
    BEQ.B       CREATECN                        | yes: HFS create path
    BTST        #0x1,(HFSFlags)                 | CreateDir on MFS volume?
    BEQ.W       CREATE_NO_7                     | no: MFS file create
    MOVEQ.L     #-0x7B,D0                       | dirNFErr (-123): no dirs on MFS
    BRA.B       CREATE_DONE                     | exit with error
| ----------------------------------------------------------
|
| CREATECN
|
| CreateCN: create the catalog record
CREATECN:
    MOVE.B      0x1A(A0),D1                     | file type from param block
    SWAP.W      D1                              | move to high word
    MOVE.B      #0x2,D1                         | assume CMFilCN (file record)
    BTST        #0x1,(HFSFlags)                 | CreateDir request?
    BEQ.B       CREATE_NO                       | no: creating a file
    MOVE.B      #0x1,D1                         | CMDirCN (directory record)
CREATE_NO:
    MOVE.L      A0,-(A6)                        | save param block ptr on FS stack
    BSR.B       PUSHCNAME                       | push CName onto FS stack
    MOVE.W      D2,-(A6)                        | save name length
    MOVE.L      D6,D0                           | D0 = parent directory ID
    JSR         CMCREATECN(PC)                  | catalog manager: create record
    MOVE.W      (A6)+,D2                        | restore name length
    BSR.B       CREATE_CONT_2                   | pop CName from FS stack
    MOVEA.L     (A6)+,A0                        | restore param block ptr
    TST.W       D0                              | create succeeded?
    BEQ.B       CREATE_OK                       | yes: finish up
    CMPI.W      #0x30,D0                        | catalog full error?
    BNE.B       CREATE_DONE                     | other error: exit
    MOVEQ.L     #-0x78,D0                       | catChangedErr (-120)
    BRA.B       CREATE_DONE                     | exit with error
CREATE_OK:
    BTST        #0x1,(HFSFlags)                 | was CreateDir?
    BEQ.B       CREATE_NO_DIRID                 | no: skip DirID return
    MOVE.L      D1,0x30(A0)                     | ioDirID = new directory ID
CREATE_NO_DIRID:
    MOVEQ.L     #0x0,D0                         | no error
| Called by: CREATE_NAME_NOT_FOUND, CREATE_NO, CREATE_TRY_RESOLVE
CREATE_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| PUSHCNAME
|
| PushCName: save CName on A6 stack, return Pascal string in A0
| Called by: RENAME_DO_CATALOG, CREATE_NO, DELETE_FILE, RENAME_NO_2, HFSCATMOVE_NO_2
PUSHCNAME:
    MOVEM.L     D0/A1,-(A7)                     | save regs
    SUBA.L      A0,A0                           | A0 = nil (default)
    TST.W       D2                              | CName length?
    BEQ.B       CREATE_NO_3                     | no name: return nil
| copy CName to A6 stack as Pascal string
    MOVEA.W     D2,A0                           | A0 = name length (temp)
    ADDQ.W      #0x1,D2                         | include length byte
    BCLR        #0x0,D2                         | round up to even
    SUBA.W      D2,A6                           | allocate space on A6 stack
    MOVE.W      D2,-(A7)                        | save rounded size
    MOVE.W      A0,D2                           | D2 = name length
    MOVEA.L     A4,A0                           | source = parsed CName
    MOVEA.L     A6,A1                           | dest = A6 stack
    MOVEQ.L     #0x0,D0                         | clear high word for BlockMove
    MOVE.W      D2,D0                           | byte count
    _BlockMove                                  | copy name
    MOVE.W      D2,-(A6)                        | push name length
    MOVE.W      (A7)+,D2                        | restore rounded size
    MOVEA.L     A6,A0                           | A0 = Pascal string on stack
    ADDQ.L      #0x1,A0                         | skip to length byte
CREATE_NO_3:
    MOVEM.L     (A7)+,D0/A1                     | restore regs
    RTS                                         | return from PushCName
| ----------------------------------------------------------
|
| CREATE_CONT_2 - PopCName: restore CName from A6 stack
|
| Called by: RENAME_NO_2, CREATE_NO, DELETE_NO_2, HFSCATMOVE_NO_2
CREATE_CONT_2:
    TST.W       D2                              | was a name pushed?
    BEQ.B       CREATE_NO_4                     | no: nothing to pop
    MOVE.W      (A6)+,-(A7)                     | pop name length
    ADDA.W      D2,A6                           | deallocate name buffer
    MOVE.W      (A7)+,D2                        | D2 = restored rounded size
CREATE_NO_4:
    RTS                                         | return from PopCName
| ----------------------------------------------------------
|
| CREATE_NO_5
|
| Called during boot.
| MFSOpen: MFS file open path
CREATE_NO_5:
    MOVEA.L     D1,A3                           | A3 = FCB pointer
    MOVE.W      (CkdDB).W,D7                    | D7 = write count for tag data
    MOVE.W      (A5),D3                         | get MFS file flags
    ANDI.W      #0x1FF,D3                       | mask to flag bits
    BTST        #0x8,D3                         | file locked?
    BEQ.B       CREATE_NO_6                     | no
    BSET        #0xD,D3                         | set FCB locked flag
CREATE_NO_6:
    MOVE.L      0x20(A2),0x1E(A3)               | FCBClmpSize = vcbClpSiz
| load fork info from MFS directory entry
    LEA.L       0x12(A5),A5                     | point to file number in MFS entry
    MOVE.L      (A5)+,D2                        | D2 = file number
    MOVE.W      (A5)+,D4                        | D4 = data fork start block
    MOVE.L      (A5)+,D5                        | D5 = data fork logical EOF
    MOVE.L      (A5)+,D6                        | D6 = data fork physical EOF
    TST.B       (RegRsrc).W                     | opening data fork?
    BNE.B       FILEOPEN_PERMSSNCHK             | yes: data fork info is set
    BSET        #0x9,D3                         | set resource fork flag
    MOVE.W      (A5)+,D4                        | D4 = rsrc fork start block
    MOVE.L      (A5)+,D5                        | D5 = rsrc fork logical EOF
    MOVE.L      (A5)+,D6                        | D6 = rsrc fork physical EOF
FILEOPEN_PERMSSNCHK:
    BSR.W       P_PermssnChk                    | PermssnChk: check access permissions
    BNE.B       FILEOPEN_RFN_DONE               | denied: exit with error
    BRA.W       SETUPFCB                        | go set up FCB fields
    CLR.W       0x18(A0)                        | (dead code) clear ioRefNum
FILEOPEN_RFN_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| CREATE_NO_7
|
| MFS file create: check for path separator in name
CREATE_NO_7:
    TST.W       D2                              | name length zero?
    BEQ.B       CREATE_OK_3                     | yes: bad name
    MOVE.W      D2,D0                           | D0 = name length
CREATE_ERR_3:
    SUBQ.W      #0x1,D0                         | scan backwards through name
    BLT.B       CREATE_MFS_PATH                 | no colon found: ok to create
    CMPI.B      #0x3A,0x0(A4,D0.W)              | colon (':') in name?
    BNE.B       CREATE_ERR_3                    | no: keep scanning
| name has colon or is empty: bad name for MFS
CREATE_OK_3:
    MOVEQ.L     #-0x25,D0                       | bdNamErr (-37): bad filename
CREATE_BAD_NAME_RTS:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| MFS create: check write protect and find directory space
CREATE_MFS_PATH:
    BSR.B       CREATE_CONT_8                   | check write protect
    BNE.B       CREATE_BAD_NAME_RTS             | write-protected: exit
    MOVE.W      D5,D0                           | D0 = entry size to clear
    MOVEA.L     A5,A1                           | A1 = entry position
| MFS Create: initialize new directory entry
CREATE_CONT_6:
    CLR.W       (A1)+                           | zero the entry
    SUBQ.W      #0x2,D0                         | decrement byte counter
    BHI.B       CREATE_CONT_6                   | keep zeroing
| fill in MFS directory entry fields
    BSET        #0x7,(A5)                       | set "in use" flag
    MOVE.B      0x1A(A0),0x1(A5)                | file version (ioVersNum)
    MOVE.L      0x26(A2),0x12(A5)               | assign file number (vcbNxtCNID)
    ADDQ.L      #0x1,0x26(A2)                   | bump next CNID
| set creation and modification dates
    LEA.L       0x2A(A5),A5                     | point to date fields
    MOVE.L      (Time).W,(A5)                   | creation date = now
    MOVE.L      (A5)+,(A5)+                     | modification date = creation date
| copy filename into entry
    MOVE.B      D2,(A5)+                        | set name length byte
    BEQ.B       CREATE_MFS_BUMP_NMFLS           | empty name: skip copy
CREATE_LOOP:
    MOVE.B      (A4)+,(A5)+                     | copy name bytes
    SUBQ.B      #0x1,D2                         | decrement name length
    BHI.B       CREATE_LOOP                     | loop until all copied
CREATE_MFS_BUMP_NMFLS:
    BSR.W       MARKVCB                         | mark VCB dirty
    ADDQ.W      #0x1,0x14(A2)                   | increment vcbNmFls (file count)
    BSR.B       CREATE_CONT_7                   | MFS directory flush
    MOVEQ.L     #0x0,D0                         | no error
    BRA.B       CREATE_BAD_NAME_RTS             | CmdDone
| Called by: CREATE_MFS_BUMP_NMFLS, HFSCATMOVE_NO_3, HFSCATMOVE_OK_6, SETFILEINFO_MFS_FLUSH, FILECLOSE_OK_2
| MFS directory flush: flush system control cache for this volume
CREATE_CONT_7:
    MOVE.W      0x4E(A2),D0                     | vcbVRefNum
    MOVEA.L     (SysCtlCPtr).W,A1               | system control cache
    MOVEQ.L     #0x0,D1                         | no FlushCache options
    JMP         FLUSHCACHE(PC)                  | tail-call FlushCache
| find space in MFS directory for a new entry
CREATE_CONT_8:
    MOVEA.L     (A7)+,A3                        | A3 = return address (for JMP later)
    MOVEQ.L     #0x34,D5                        | fixed entry fields (52 bytes)
    ADD.W       D2,D5                           | + name length = total entry size
    BCLR        #0x0,D5                         | round to even
    BSR.W       FILEWRITE_CONT_4                | read first directory block
    BRA.B       CREATE_CONT_9                   | check for errors
| scan directory blocks for free space
CREATE_NO_8:
    BSR.W       FILEWRITE_NEXT                  | read next directory block
CREATE_CONT_9:
    BNE.B       CREATE_ERR_5                    | I/O error: exit
    MOVEQ.L     #0x0,D0                         | initial entry offset
CREATE_CONT_10:
    TST.B       0x0(A5,D0.W)                    | entry in use?
    BEQ.B       CREATE_FOUND                    | no: found free space
    BSR.B       CREATE_NEXT                     | advance to next entry
    BCS.B       CREATE_CONT_10                  | more entries in block
| check if new entry fits in this block
CREATE_FOUND:
    MOVE.W      D0,D4                           | D4 = insertion offset
    ADD.W       D5,D4                           | + entry size
    CMPI.W      #0x200,D4                       | fits in this block?
    BCC.B       CREATE_NO_8                     | no: try next block
    JSR         MARKA5BLOCK(PC)                 | mark directory block dirty
    LEA.L       0x0(A5,D0.W),A5                 | A5 = new entry position
    CLR.L       0x5A(A2)                        | invalidate vcbDirIndex cache
    MOVEQ.L     #0x0,D0                         | no error
CREATE_ERR_5:
    JMP         (A3)                            | tail-call return from CREATE_ERR_5 via A3
| ----------------------------------------------------------
|
| CREATE_NEXT: advance to next MFS directory entry
|
| Called during boot.
CREATE_NEXT:
    MOVEQ.L     #0x0,D6                         | clear high bytes
    MOVE.B      0x32(A5,D0.W),D6                | name length of current entry
    ADD.W       D6,D0                           | + name length
    ADDI.W      #0x34,D0                        | + fixed fields (52 bytes)
    BCLR        #0x0,D0                         | round to even
    CMPI.W      #0x1CC,D0                       | past usable area? (512-52=460)
    RTS                                         | return (CS=more, CC=end)
| ----------------------------------------------------------
|
| CREATE_CONT_11
|
| CREATE_CONT_11: get WDCB array base and initial offset
CREATE_CONT_11:
    MOVEA.L     (WDCBsPtr).W,A1                 | A1 = WDCB array
    MOVEQ.L     #0x2,D1                         | D1 = 2 (past WDCB header)
    RTS                                         | return array base and offset
| ----------------------------------------------------------
|
| CREATE_SKIP: advance to next WDCB entry (16 bytes each)
|
| Called by: OPENWD_HFS_CONT_3, OPENWD_SCAN_LOOP, GETWDINFO_HFS_NO, GETWDINFO_INDEX_LOOP, CREATE_NEXT_2
CREATE_SKIP:
    ADDI.W      #0x10,D1                        | advance by WDCB size (16 bytes)
    CMP.W       (A1),D1                         | past end of array?
    RTS                                         | return (CS=more, CC=end)
| ----------------------------------------------------------
|
| CREATE_CONT_12: find first WDCB belonging to volume A2
|
CREATE_CONT_12:
    BSR.B       CREATE_CONT_11                  | get WDCB array base
CREATE_CONT_13:
    CMPA.L      0x0(A1,D1.W),A2                 | same volume? (WDVCBPtr)
    BEQ.B       CREATE_FOUND_2                  | yes: found
| CREATE_NEXT_2: advance to next WDCB and continue scanning
CREATE_NEXT_2:
    BSR.B       CREATE_SKIP                     | next WDCB
    BCS.B       CREATE_CONT_13                  | more entries ->
    MOVE.W      #0x0,CCR                        | clear Z: not found
CREATE_FOUND_2:
    RTS                                         | return from CREATE_FOUND_2
| ----------------------------------------------------------
|
| CREATE_CONT_14
|
| CREATE_CONT_14: CkDirBusy - check if any files in directory D6 are open
CREATE_CONT_14:
    MOVEM.L     D2/A1,-(A7)                     | save regs
    MOVE.L      0x6(A5),D2                      | D2 = DirID being deleted
    BSR.B       CREATE_CONT_12                  | scan WDCBs for this volume
CREATE_CONT_15:
    BNE.B       CREATE_ERR_6                    | no more WDCBs: dir not busy
    CMP.L       0x4(A1,D1.W),D2                 | WDCB's DirID matches?
    BEQ.B       CREATE_OK_4                     | yes: directory is busy
    BSR.B       CREATE_NEXT_2                   | advance to next WDCB
    BRA.B       CREATE_CONT_15                  | keep scanning
| ----------------------------------------------------------
|
| CREATE_ERR_6
|
CREATE_ERR_6:
    MOVEQ.L     #0x0,D0                         | not busy: no error
CREATE_CONT_16:
    MOVEM.L     (A7)+,D2/A1                     | restore regs
    RTS                                         | exit CkDirBusy
| ----------------------------------------------------------
|
| CREATE_OK_4
|
CREATE_OK_4:
    MOVE.W      D1,0x18(A0)                     | return conflicting WDCB refnum
    MOVEQ.L     #-0x2F,D0                       | fBsyErr (-47): directory is busy
    BRA.B       CREATE_CONT_16                  | exit with error
| CkFileBusy: check if file is open (has any FCBs)
CREATE_OK_5:
    MOVE.L      A1,-(A7)                        | save A1
    MOVE.L      0x14(A5),D2                     | HFS file number (filFlNum)
    BSR.W       TFSVCBTST                       | HFS volume?
    BEQ.B       CREATE_OK_6                     | yes: use HFS file number
    MOVE.L      0x12(A5),D2                     | MFS file number
CREATE_OK_6:
    BSR.W       HFSE_CONT_15                    | Gt1stMatch: find FCB for file
    BEQ.B       CREATE_FOUND_3                  | found: file is open
    MOVEQ.L     #0x0,D0                         | not open: no error
CREATE_CONT_17:
    MOVEA.L     (A7)+,A1                        | restore A1
    RTS                                         | exit CkFileBusy
CREATE_FOUND_3:
    MOVE.W      D1,0x18(A0)                     | return conflicting FCB refnum
    MOVEQ.L     #-0x2F,D0                       | fBsyErr (-47): file is busy
    BRA.B       CREATE_CONT_17                  | exit with error
FILEDELETE:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.W       HFSCATMOVE_NO_3                 | no: MFS Delete path
| HFS Delete: check if file/dir is locked
    MOVEQ.L     #-0x2D,D0                       | fLckdErr (-45)
    BTST        #0x0,0x2(A5)                    | file locked? (filFlags bit 0)
    BNE.B       DELETE_DIR_NOT_EMPTY            | yes: can't delete
| determine record type: directory or file
    BCLR        #0x1,(HFSFlags)                 | clear CreateDir flag
    CMPI.B      #0x1,(A5)                       | directory record? (cdrDirRec)
    BNE.B       DELETE_NO                       | no: check file record
    BSET        #0x1,(HFSFlags)                 | set dir flag (for delete)
    BSR.B       CREATE_CONT_14                  | CkDirBusy: files open in dir?
    BRA.B       DELETE_CONT                     | check result
| file record: check if file is open
DELETE_NO:
    CMPI.B      #0x2,(A5)                       | file record? (cdrFilRec)
    BNE.B       DELETE_FILE                     | no (thread): skip busy check
    MOVE.L      D2,-(A6)                        | save VRefNum on FS stack
    BSR.B       CREATE_OK_5                     | CkFileBusy: is file open?
    MOVE.L      (A6)+,D2                        | restore VRefNum
    TST.W       D0                              | file busy?
DELETE_CONT:
    BNE.B       DELETE_DIR_NOT_EMPTY            | yes: can't delete
| deallocate file's disk space and delete catalog entry
DELETE_FILE:
    BSR.W       PUSHCNAME                       | PushCName: save CName
    MOVE.L      D2,-(A6)                        | save VRefNum
    MOVE.L      D7,D2                           | catalog hint
    CMPI.B      #0x2,(A5)                       | file record?
    BNE.B       DELETE_NO_2                     | no: just delete catalog entry
| file: deallocate disk space first
    MOVE.L      0x14(A5),D0                     | file number (filFlNum)
    JSR         TRASHFBLOCKS(PC)                | trash cached blocks for file
    MOVE.L      D6,D0                           | parent DirID
    JSR         DEALLOCFILE(PC)                 | deallocate all file extents
    BNE.B       DELETE_DIR_NOT_EMPTY            | error: exit
DELETE_NO_2:
    MOVE.L      D6,D0                           | parent DirID
    JSR         CMDELETECN(PC)                  | delete catalog entry
    MOVE.L      (A6)+,D2                        | restore VRefNum
    BSR.W       CREATE_CONT_2                   | PopCName: restore CName
    CMPI.W      #0x32,D0                        | CMnotempty? (dir not empty)
    BNE.B       DELETE_DIR_NOT_EMPTY            | other error: exit
    MOVEQ.L     #-0x2F,D0                       | fBsyErr (-47): dir not empty
DELETE_DIR_NOT_EMPTY:
    BRA.W       FSQUEUE_DONE                    | CmdDone
RENAME:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    MOVE.L      0x1C(A0),D2                     | D2 = new name ptr (ioMisc)
    BSR.W       DTRMV1_CONT_7                   | DTRMV + FndFilName for source
    BNE.W       RENAME_ERR_5                    | error: exit
| check if rename crosses volumes
    TST.W       D2                              | new name specified?
    BEQ.W       RENAME_NO_3                     | no name: MFS rename path
    MOVEA.L     A2,A1                           | A1 = source VCB
    MOVE.W      D3,D7                           | D7 = source name length
    MOVEM.L     D2/A4,(FSTemp8)                 | save new name info in temp
    BSR.W       P_DTRMV3                        | DTRMV3: determine dest volume
    BNE.B       RENAME_ERR_2                    | error: exit
    CMPA.L      A1,A2                           | same volume?
    BEQ.B       RENAME_HFS_PATH                 | yes: proceed
    TST.W       D7                              | source had a name?
    BEQ.B       RENAME_HFS_PATH                 | no: allow cross-volume
RENAME_ERR:
    MOVEQ.L     #-0x25,D0                       | bdNamErr (-37)
| Called by: RENAME_NO_2, RENAME_HFS_PATH, RENAME, RENAME_ERR_3, RENAME_ERR_4 (and 1 more)
RENAME_ERR_2:
    CMPI.W      #0x21,D0                        | BTexists?
    BNE.B       RENAME_DUPFN_TRANSLATE          | no: keep error code
    MOVEQ.L     #-0x30,D0                       | convert to dupFNErr (-48)
RENAME_DUPFN_TRANSLATE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| HFS Rename: check write protect and find source
RENAME_HFS_PATH:
    BSR.W       SETVOLINFO_HFS_CONT_3           | check write protect
    BNE.B       RENAME_ERR_2                    | write-protected: exit
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.W       HFSCATMOVE_NO_4                 | no: MFS Rename path
| locate source file in catalog
    BSR.W       P_FndFilName                    | FndFilName: find source
    BNE.B       RENAME_ERR_2                    | not found: exit
    MOVEQ.L     #-0x2D,D0                       | fLckdErr (-45)
    BTST        #0x0,0x2(A5)                    | file locked?
    BNE.B       RENAME_ERR_2                    | yes: can't rename
    MOVE.L      D6,D4                           | D4 = source parent DirID
    MOVE.L      D7,D5                           | D5 = source catalog hint
| locate destination (new name) in catalog
    MOVEM.L     D2/D4-D5/A4,-(A6)               | save source info on FS stack
    MOVE.L      0x12(A0),-(A6)                  | save original ioFileName ptr
    MOVE.L      0x1C(A0),D2                     | new name ptr (ioMisc)
    MOVE.L      D2,0x12(A0)                     | temporarily set as filename
    BSR.W       P_FndFilName                    | FndFilName: look up new name
    MOVEM.L     D2/A4,(FSTemp8)                 | save new name parse results
    MOVE.L      (A6)+,0x12(A0)                  | restore original ioFileName
    MOVEM.L     (A6)+,D2/D4-D5/A4               | restore source info
    TST.W       D0                              | dest lookup result?
    BNE.B       RENAME_ERR_3                    | error: check if fnfErr
| dest name exists: check if same file (case-only rename)
    MOVE.L      A0,-(A7)                        | save param block
    MOVEM.L     D2/A4,-(A6)                     | save source name info
    MOVE.W      D2,D0                           | source name length (high word)
    MOVEA.L     A4,A0                           | source name ptr
    SWAP.W      D0                              | lengths in correct order
    MOVEM.L     (FSTemp8),D2/A4                 | dest name info
    MOVE.W      D2,D0                           | dest name length (low word)
    MOVEA.L     A4,A1                           | dest name ptr
    _CmpString                                  | compare source and dest names
    MOVEM.L     (A6)+,D2/A4                     | restore source name info
    MOVEA.L     (A7)+,A0                        | restore param block
    BNE.B       RENAME_CONT                     | names differ: dupFNErr
    CMP.L       D4,D6                           | same parent directory?
    BEQ.B       RENAME_DO_CATALOG               | yes: case-only rename ok
RENAME_CONT:
    MOVEQ.L     #-0x30,D0                       | dupFNErr (-48): dest exists
RENAME_ERR_3:
    CMPI.W      #0xFFD5,D0                      | fnfErr (-43)? (ok to rename)
    BNE.B       RENAME_ERR_2                    | other error: exit
    CMP.L       D4,D6                           | same parent directory?
    BNE.W       RENAME_ERR                      | no: cross-dir rename error
| do the catalog rename
RENAME_DO_CATALOG:
    BSR.W       PUSHCNAME                       | PushCName: save source CName
    MOVE.L      D2,-(A7)                        | save source VRefNum
    MOVEA.L     A0,A1                           | A1 = source CName
    MOVEM.L     (FSTemp8),D2/A4                 | get dest name parse results
    BSR.W       PUSHCNAME                       | PushCName: save dest CName
    MOVE.L      (A7)+,-(A6)                     | push source VRefNum to FS stack
    MOVE.L      D2,-(A6)                        | push dest VRefNum
    EXG         A0,A1                           | A0=dest CName, A1=source CName
    MOVE.L      D4,D0                           | D0 = source parent DirID
    MOVE.L      D5,D2                           | D2 = source catalog hint
    JSR         CMRENAMECN(PC)                  | catalog: rename entry
    MOVE.L      D2,D7                           | D7 = updated catalog hint
    TST.W       D0                              | rename succeeded?
    BNE.B       RENAME_NO_2                     | no: cleanup and exit
| check if root dir or volume renamed (update volume name)
    CMPI.L      #0x1,D4                         | root directory? (DirID=1)
    BEQ.B       RENAME_UPDATE_VOL_NAME          | yes: update volume name
    CMPI.L      #0x2,D4                         | root parent? (DirID=2)
    BNE.B       RENAME_NO_2                     | no: skip volume update
    TST.L       0x4(A6)                         | dest VRefNum > 0?
    BGT.B       RENAME_NO_2                     | yes: skip volume update
RENAME_UPDATE_VOL_NAME:
    BSR.W       SETVOLINFO_HFS_CONT             | update volume name in VCB
    MOVEQ.L     #0x0,D0                         | no error
    MOVEQ.L     #0x1,D6                         | flag: volume name changed
| cleanup: pop both CNames from FS stack
RENAME_NO_2:
    MOVE.L      (A6)+,D2                        | pop dest VRefNum
    MOVE.L      (A6)+,-(A7)                     | move source VRefNum to stack
    BSR.W       CREATE_CONT_2                   | PopCName: pop dest CName
    MOVE.L      (A7)+,D2                        | restore source VRefNum
    BSR.W       CREATE_CONT_2                   | PopCName: pop source CName
    TST.W       D0                              | rename succeeded?
    BNE.W       RENAME_ERR_2                    | no: exit with error
    CMPI.L      #0x1,D6                         | volume name changed (D6 = 1) ?
    BEQ.W       RENAME_ERR_2                    | yes, no FCBs to update
| update open FCBs with new name and catalog hint
    MOVEM.L     (FSTemp8),D2/A4                 | get dest name info
    BSR.W       PUSHCNAME                       | PushCName: save dest CName
    MOVE.L      D2,-(A6)                        | save VRefNum
    MOVE.L      D6,D0                           | parent DirID
    MOVE.L      D7,D2                           | catalog hint
    JSR         CMGETCN(PC)                     | re-read catalog entry (renamed)
    MOVE.L      (A6)+,D2                        | restore VRefNum
    BSR.W       CREATE_CONT_2                   | PopCName: restore dest CName
    TST.W       D0                              | catalog read ok?
    BNE.W       RENAME_ERR_2                    | error: exit
    MOVE.B      D2,D3                           | D3 = new name length
    MOVEA.L     A1,A5                           | A5 = catalog record ptr
    MOVEA.L     A4,A0                           | A0 = new name ptr
    MOVE.L      0x14(A5),D2                     | file number from catalog
    BSR.W       HFSE_CONT_15                    | Gt1stMatch: find FCB for file
    BNE.W       RENAME_ERR_2                    | no open FCB: done
| update each open FCB with new catalog hint and name
RENAME_CONT_2:
    MOVE.L      D7,0x36(A1,D1.W)                | FCBCatPos = updated hint
    LEA.L       0x3E(A1,D1.W),A1                | A1 = FCBCName in FCB
    MOVE.B      D3,(A1)+                        | store new name length
    MOVEQ.L     #0x0,D0                         | clear high word
    MOVE.B      D3,D0                           | byte count
    _BlockMove                                  | copy new name to FCB
    MOVEA.L     (FCBSPtr).W,A1                  | reset FCB array base
    BSR.W       HFSE_ERR_9                      | GtNxtMatch: next FCB for file
    BEQ.B       RENAME_CONT_2                   | found: update it too
RENAME_NEXT_FCB_FOR_FILE:
    MOVEQ.L     #0x0,D0                         | no error
| Called by: RENAME_NO_3, RENAME_ERR_5, RENAME_VOL_VERIFY_ONLINE
RENAME_ERR_4:
    BRA.W       RENAME_ERR_2                    | exit via error handler
| ----------------------------------------------------------
|
| RENAME_ERR_5
|
RENAME_ERR_5:
    CMPI.W      #0xFFDD,D0                      | extFSErr (-35)?
    BNE.B       RENAME_ERR_4                    | other error: exit
    TST.W       D2                              | new name specified?
    BNE.W       RENAME_ERR                      | yes: bdNamErr
| MFS Rename path: rename volume name
RENAME_NO_3:
    TST.W       D3                              | new name given?
    BEQ.B       RENAME_ERR_4                    | no: exit
    BSR.W       P_DTRMV3                        | determine destination volume
    BNE.B       RENAME_ERR_4                    | error: exit
    BSR.W       SETVOLINFO_HFS_CONT_3           | check write protect
    BNE.B       RENAME_ERR_4                    | write-protected: exit
    CMPI.W      #0x4244,0x8(A2)                 | HFS volume? (sig = 'BD')
    BEQ.B       RENAME_VOL_VERIFY_ONLINE        | yes: check online
    TST.W       0x48(A2)                        | MFS volume online? (vcbDrvNum)
    BEQ.B       RENAME_ERR_4                    | no: exit
    BRA.B       RENAME_VOL_COPY_NAME            | update volume name
RENAME_VOL_VERIFY_ONLINE:
    BSR.W       CkExtFS_AndOnline               | verify volume online
    BNE.B       RENAME_ERR_4                    | offline: exit
| copy new name to VCB volume name
RENAME_VOL_COPY_NAME:
    MOVEA.L     0x1C(A0),A1                     | A1 = new name (ioMisc)
    BSR.W       SETVOLINFO_HFS_CONT             | update VCB volume name
| if HFS, also rename root directory in catalog
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       RENAME_NEXT_FCB_FOR_FILE        | no: done (MFS has no catalog)
    MOVEQ.L     #0x0,D2                         | no catalog hint
    MOVEQ.L     #0x2,D0                         | root DirID (FSRtDirID)
    MOVEA.L     D2,A0                           | no old CName
    LEA.L       0x2C(A2),A1                     | new name = vcbVN
    JSR         CMRENAMECN(PC)                  | rename root directory
    BRA.W       RENAME_ERR_2                    | exit via error handler
| _CatMove: move a file/directory to a different parent
TFMOVE:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
| determine destination directory
    MOVE.L      0x12(A0),-(A6)                  | save source ioFileName
    MOVE.L      0x1C(A0),0x12(A0)               | temporarily use dest name
    BSR.W       P_DTRMV3                        | DTRMV3: determine dest volume
    MOVE.L      (A6)+,0x12(A0)                  | restore source ioFileName
| determine source directory
    MOVEA.L     A2,A1                           | A1 = dest VCB
    MOVE.W      D3,D7                           | D7 = dest name length
    BSR.W       P_DTRMV3                        | DTRMV3: determine source volume
    BNE.B       CATMOVE_BAD_NAME_RTS            | error: exit
    CMPA.L      A1,A2                           | same volume?
    BEQ.B       CATMOVE_HFS_PATH                | yes: proceed
    TST.W       D7                              | dest had a name?
    BEQ.B       CATMOVE_HFS_PATH                | no: allow
CATMOVE_NO_CROSSVOL:
    MOVEQ.L     #-0x25,D0                       | bdNamErr (-37): cross-vol move
| Called by: CATMOVE_HFS_PATH, TFMOVE, HFSCATMOVE_NO, HFSCATMOVE_ERR_3, CATMOVE_NEXT_FCB
CATMOVE_BAD_NAME_RTS:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| check write protect and find source file
CATMOVE_HFS_PATH:
    BSR.W       SETVOLINFO_HFS_CONT_3           | check write protect
    BNE.B       CATMOVE_BAD_NAME_RTS            | write-protected: exit
    BSR.W       CkExtFS_AndOnline               | CkExtFS: check external FS
    BNE.B       CATMOVE_BAD_NAME_RTS            | external FS: exit
    MOVEQ.L     #-0x32,D0                       | CMnotempty (assumed error)
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.B       CATMOVE_BAD_NAME_RTS            | no: can't CatMove on MFS
| find source file in catalog
    BSR.W       P_FndFilName                    | locate source by name
    BNE.B       CATMOVE_BAD_NAME_RTS            | not found: exit
    MOVEQ.L     #0x0,D3                         | D3 = 0 (assume directory)
    CMPI.B      #0x2,(A5)                       | file record? (cdrFilRec)
    BNE.B       HFSCATMOVE_NO                   | no: directory
    MOVE.L      0x14(A5),D3                     | D3 = file number (filFlNum)
| find destination directory
HFSCATMOVE_NO:
    MOVE.L      D6,D4                           | D4 = source parent DirID
    MOVE.L      D7,D5                           | D5 = source catalog hint
    MOVEM.L     D2/A4,(FSTemp8)                 | save source name info
| temporarily swap to dest name for lookup
    MOVE.L      0x12(A0),-(A6)                  | save source ioFileName
    MOVE.L      0x30(A0),-(A6)                  | save source ioDirID
    MOVE.L      0x1C(A0),0x12(A0)               | set dest name (ioNewName)
    MOVE.L      0x24(A0),0x30(A0)               | set dest DirID (ioNewDirID)
    MOVEM.L     D3-D5,-(A6)                     | save source info
    BSR.W       P_FndFilName                    | look up destination
    MOVEM.L     (A6)+,D3-D5                     | restore source info
    MOVE.L      (A6)+,0x30(A0)                  | restore source ioDirID
    MOVE.L      (A6)+,0x12(A0)                  | restore source ioFileName
    TST.W       D0                              | dest found?
    BEQ.B       HFSCATMOVE_OK_2                 | yes: check if directory
    CMPI.W      #0xFFDB,D0                      | fnfErr (-37)?
    BNE.B       CATMOVE_BAD_NAME_RTS            | other error: exit
    TST.W       D2                              | dest had a name component?
    BNE.B       CATMOVE_NO_CROSSVOL             | yes: name not found error
    BRA.B       HFSCATMOVE_NO_2                 | no name: move to dest dir
| ----------------------------------------------------------
|
| HFSCATMOVE_OK_2
|
| hfsCatMove: check dest is a directory and get its DirID
HFSCATMOVE_OK_2:
    CMPI.B      #0x1,(A5)                       | directory record? (cdrDirRec)
    BNE.B       CATMOVE_NO_CROSSVOL             | no: bdNamErr
    MOVE.L      0x6(A5),D6                      | D6 = dest directory ID
    MOVEQ.L     #0x0,D7                         | D7 = 0 (no catalog hint)
| move catalog entry to different directory
HFSCATMOVE_NO_2:
    MOVEM.L     (FSTemp8),D2/A4                 | get source name info
    CMP.L       D4,D6                           | same parent? (null move)
    BEQ.B       CATMOVE_NEXT_FCB                | yes: nothing to do
| call CMMoveCN to move the catalog entry
    BSR.W       PUSHCNAME                       | PushCName: save source CName
    MOVE.L      D2,-(A6)                        | save VRefNum
    MOVE.L      D3,-(A6)                        | save file number
    MOVE.L      D4,D0                           | source parent DirID
    MOVE.L      D5,D2                           | source catalog hint
    MOVE.L      D6,D1                           | dest parent DirID
    MOVE.L      D7,D3                           | dest catalog hint
    SUBA.L      A1,A1                           | no dest CName (keep same name)
    JSR         CMMOVECN(PC)                    | move the catalog entry
    MOVE.L      D2,D7                           | D7 = new hint
    MOVE.L      (A6)+,D3                        | restore file number
    MOVE.L      (A6)+,D2                        | restore VRefNum
    BSR.W       CREATE_CONT_2                   | PopCName: restore CName
    TST.W       D0                              | move ok?
    BEQ.B       HFSCATMOVE_OK_3                 | yes: update FCBs
    CMPI.W      #0x31,D0                        | CMexists?
    BNE.B       HFSCATMOVE_ERR_3                | other error: exit
    MOVEQ.L     #-0x30,D0                       | dupFNErr (-48)
HFSCATMOVE_ERR_3:
    BRA.W       CATMOVE_BAD_NAME_RTS            | exit with error
| update open FCBs with new parent DirID and hint
HFSCATMOVE_OK_3:
    MOVE.L      D3,D2                           | D2 = file number for FCB scan
    BEQ.B       CATMOVE_NEXT_FCB                | directory: no FCBs to update
    BSR.W       HFSE_CONT_15                    | Gt1stMatch: find FCB for file
    BNE.B       CATMOVE_NEXT_FCB                | not open: done
HFSCATMOVE_CONT:
    MOVE.L      D7,0x36(A1,D1.W)                | FCBCatPos = updated hint
    MOVE.L      D6,0x3A(A1,D1.W)                | FCBDirID = new parent DirID
    BSR.W       HFSE_ERR_9                      | GtNxtMatch: next FCB for file
    BEQ.B       HFSCATMOVE_CONT                 | update it too
CATMOVE_NEXT_FCB:
    MOVEQ.L     #0x0,D0                         | no error
    BRA.W       CATMOVE_BAD_NAME_RTS            | CmdDone
| MFS Delete path
HFSCATMOVE_NO_3:
    MOVEQ.L     #-0x2D,D0                       | fLckdErr (-45)
    BTST        #0x0,(A5)                       | file locked?
    BNE.B       DELETE_MFS_DONE                 | yes: can't delete
    BSR.W       CREATE_OK_5                     | CkFileBusy: is file in use?
    BNE.B       DELETE_MFS_DONE                 | yes: busy
| delete MFS file: deallocate blocks and remove entry
    SUBQ.W      #0x1,0x14(A2)                   | decrement vcbNmFls (file count)
    BSR.W       MARKVCB                         | mark VCB dirty
    MOVE.W      0x16(A5),D3                     | data fork start block
    BSR.W       LG2PHYS_CONT_10                 | MFSDealloc: free data fork blocks
    MOVE.W      0x20(A5),D3                     | rsrc fork start block
    BSR.W       LG2PHYS_CONT_10                 | MFSDealloc: free rsrc fork blocks
    MOVE.L      0x12(A5),D0                     | file number
    BSR.B       HFSCATMOVE_CONT_3               | MFSDeleteEntry: remove from dir
    JSR         TRASHFBLOCKS(PC)                | trash cached blocks for file
    BSR.W       CREATE_CONT_7                   | MFS directory flush
    MOVEQ.L     #0x0,D0                         | no error
DELETE_MFS_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| HFSCATMOVE_CONT_2 - MFS: compute directory entry size from name length
|
HFSCATMOVE_CONT_2:
    MOVEQ.L     #0x0,D0                         | clear high bytes
    MOVE.B      0x32(A5),D0                     | name length from entry
    ADDI.W      #0x34,D0                        | + fixed fields (52 bytes)
    BCLR        #0x0,D0                         | round to even
    RTS                                         | return entry size
HFSCATMOVE_CONT_3:
    MOVEM.L     D0/A0-A1/A5,-(A7)               | save regs
    MOVEA.L     A1,A0                           | A0 = directory block buffer
    JSR         MARKBLOCK(PC)                   | mark directory block dirty
    CLR.L       0x5A(A2)                        | invalidate vcbDirIndex cache
| compress directory: shift entries after deleted one
    MOVEA.L     A5,A0                           | A0 = dest (deleted entry position)
    BSR.B       HFSCATMOVE_CONT_2               | get deleted entry size
    ADDA.L      D0,A5                           | A5 = source (next entry)
    ADDA.W      #0x200,A1                       | A1 = end of directory block
HFSCATMOVE_CONT_4:
    CMPA.L      A1,A5                           | past end of block?
    BCC.B       HFSCATMOVE_DONE                 | yes: done shifting
    MOVE.W      (A5)+,(A0)+                     | shift entry down
    BRA.B       HFSCATMOVE_CONT_4               | keep shifting
| ----------------------------------------------------------
|
| HFSCATMOVE_DONE
|
| clear remaining words in directory block
HFSCATMOVE_DONE:
    CLR.W       (A0)+                           | zero remaining word
    CMPA.L      A1,A0                           | past end of block?
    BCS.B       HFSCATMOVE_DONE                 | no: keep clearing
    MOVEM.L     (A7)+,D0/A0-A1/A5               | restore regs
    RTS                                         | exit MFSDeleteEntry
| ----------------------------------------------------------
|
| HFSCATMOVE_NO_4
|
| MFS Rename: compare old and new names, then rename
HFSCATMOVE_NO_4:
    MOVE.L      A0,-(A7)                        | save param block
    MOVE.W      D2,D0                           | old name length (high word)
    MOVEA.L     A4,A0                           | old name ptr
    MOVEM.L     (FSTemp8),D2/A4                 | get new name info
    SWAP.W      D0                              | set up for _CmpString
    MOVE.W      D2,D0                           | new name length (low word)
    MOVEA.L     A4,A1                           | new name ptr
    _CmpString                                  | compare old and new names
    MOVEA.L     (A7)+,A0                        | restore param block
    BEQ.B       HFSCATMOVE_CONT_5               | same name: case-only rename
| different name: check if new name already exists
    BSR.W       FNDFILNAME_NO_3                 | look up new name in MFS dir
    BNE.B       HFSCATMOVE_FOUND                | not found: ok to rename
    MOVEQ.L     #-0x30,D0                       | dupFNErr (-48): name exists
HFSCATMOVE_FOUND:
    CMPI.W      #0xFFD5,D0                      | fnfErr (-43)? (ok to rename)
    BNE.B       RSTFILLOCK_ERR                  | other error: exit
| do the rename
| re-locate old file and check lock
HFSCATMOVE_CONT_5:
    BSR.W       P_FndFilName                    | re-locate old file
    BNE.B       RSTFILLOCK_ERR                  | error: exit
    MOVEQ.L     #-0x2D,D0                       | fLckdErr (-45)
    BTST        #0x0,(A5)                       | file locked?
    BNE.B       RSTFILLOCK_ERR                  | yes: can't rename
| save old directory entry on A6 stack
    MOVEA.L     A6,A4                           | A4 = save point
    MOVEA.L     A5,A3                           | A3 = old entry
    BSR.B       HFSCATMOVE_CONT_2               | get entry size
HFSCATMOVE_LOOP:
    MOVE.W      -0x2(A3,D0.W),-(A6)             | push entry data onto A6 stack
    SUBQ.W      #0x2,D0                         | decrement word counter
    BGT.B       HFSCATMOVE_LOOP                 | loop
| delete old entry and insert with new name
    BSR.B       HFSCATMOVE_CONT_3               | MFSDeleteEntry: remove old entry
    MOVE.L      (FSTemp8).W,D2                  | get new name length
    BSR.W       CREATE_CONT_8                   | find space for new entry
    BNE.B       HFSCATMOVE_ERR_5                | error: try to re-insert old
| copy saved entry data to new location
    MOVEA.L     A5,A3                           | A3 = new entry location
    MOVEQ.L     #0x18,D0                        | 25 words of file info
HFSCATMOVE_LOOP_2:
    MOVE.W      (A6)+,(A5)+                     | copy entry word
    DBF.W       D0,HFSCATMOVE_LOOP_2            | loop for all 25 words
    MOVEA.L     A4,A6                           | restore A6 stack
    MOVEM.L     (FSTemp8),D2/A4                 | get new name info
    MOVE.B      D2,(A5)+                        | set new name length
| copy new name bytes into directory entry
HFSCATMOVE_OK_6:
    MOVE.B      (A4)+,(A5)+                     | copy name byte
    SUBQ.W      #0x1,D2                         | more bytes?
    BGT.B       HFSCATMOVE_OK_6                 | yes: keep copying
    BSR.B       HFSCATMOVE_CONT_6               | update FCBs for renamed file
    BSR.W       MARKVCBTIME                     | mark VCB dirty with timestamp
    BSR.W       CREATE_CONT_7                   | MFS directory flush
    MOVEQ.L     #0x0,D0                         | no error
| Called by: HFSCATMOVE_CONT_5, HFSCATMOVE_FOUND, HFSCATMOVE_ERR_5, HFSCATMOVE_NO_5
RSTFILLOCK_ERR:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| rename failed after delete: try to re-insert old entry
HFSCATMOVE_ERR_5:
    MOVE.B      0x32(A6),D2                     | name length from saved entry
    BSR.W       CREATE_CONT_8                   | find space for re-insertion
    BEQ.B       HFSCATMOVE_FOUND_2              | found space: re-insert
    MOVEA.L     A4,A6                           | restore A6 stack
    MOVEQ.L     #-0x3B,D0                       | dirFulErr (-59): directory full
    BRA.B       RSTFILLOCK_ERR                  | exit with error
| copy saved entry to new position
HFSCATMOVE_FOUND_2:
    MOVEA.L     A5,A3                           | A3 = new entry position
HFSCATMOVE_NO_5:
    MOVE.W      (A6)+,(A5)+                     | copy entry word
    CMPA.L      A6,A4                           | past end of saved data?
    BNE.B       HFSCATMOVE_NO_5                 | no: keep copying
    BSR.B       HFSCATMOVE_CONT_6               | update FCBs for re-inserted file
    MOVEQ.L     #-0x21,D0                       | internal error code
    BRA.B       RSTFILLOCK_ERR                  | exit
| update open FCBs for renamed MFS file
HFSCATMOVE_CONT_6:
    MOVE.L      0x12(A3),D2                     | file number from entry
    MOVE.W      (CkdDB).W,D0                    | current directory block
    BSR.W       HFSE_CONT_15                    | Gt1stMatch: find FCB for file
    BNE.B       SETFILEINFO_NEXT_FCB_RTS        | not open: done
HFSCATMOVE_OK_7:
    MOVE.W      D0,0x1C(A1,D1.W)                | update FCBFlPos (dir block)
    BSR.W       HFSE_ERR_9                      | GtNxtMatch: next FCB for file
    BEQ.B       HFSCATMOVE_OK_7                 | update it too
SETFILEINFO_NEXT_FCB_RTS:
    RTS                                         | exit
| _SetFilType ($A043): set MFS file type (fails on HFS)
SETFILTYPE:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    MOVE.B      0x1A(A0),D1                     | save ioVersNum
    MOVE.B      0x1C(A0),0x1A(A0)               | temporarily set new type
    BSR.W       P_FndFilName                    | FndFilName: find by type
    MOVE.B      D1,0x1A(A0)                     | restore ioVersNum
    TST.W       D0                              | found?
    BNE.B       SETFILTYPE_NO                   | no: check error
    BSR.W       TFSVCBTST                       | HFS volume?
    BEQ.B       SETFILTYPE_OK                   | yes: not supported on HFS
    MOVEQ.L     #-0x30,D0                       | dupFNErr (-48): type exists
SETFILTYPE_NO:
    CMPI.W      #0xFFD5,D0                      | fnfErr (-43)? (ok to set)
    BNE.B       SETFILLOCK_DONE                 | other error: exit
    BSR.W       FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.W       GETFILEINFO_NO_5                | no: MFS SetFilType
SETFILTYPE_OK:
    MOVEQ.L     #-0x32,D0                       | paramErr (-50): not on HFS
    BRA.B       SETFILLOCK_DONE                 | exit with error
| _SetFilLock ($A041): lock a file
SETFILLOCK:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    ST.B        (FLckUnlck).W                   | flag: lock
    BRA.B       SETFILLOCK_HFS_PATH             | shared path
| _RstFilLock ($A042): unlock a file
RSTFILLOCK:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    CLR.B       (FLckUnlck).W                   | flag: unlock
| SetFilLock/RstFilLock: HFS path
SETFILLOCK_HFS_PATH:
    BSR.W       FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.W       GETFILEINFO_NO_6                | no: MFS path
    MOVEQ.L     #-0x2B,D0                       | fnfErr (-43)
    CMPI.B      #0x2,(A5)                       | file record? (cdrFilRec)
    BNE.B       SETFILLOCK_DONE                 | no: exit
    TST.B       (FLckUnlck).W                   | lock or unlock?
    BEQ.B       RSTFILLOCK_CONT_2               | unlock path
    BSET        #0x0,0x2(A5)                    | set file lock bit
    BNE.B       RSTFILLOCK_OK                   | already locked: done
    BRA.B       RSTFILLOCK_CONT_3               | update catalog
RSTFILLOCK_CONT_2:
    BCLR        #0x0,0x2(A5)                    | clear file lock bit
    BEQ.B       RSTFILLOCK_OK                   | already unlocked: done
RSTFILLOCK_CONT_3:
    MOVE.L      D7,D2                           | catalog hint
    JSR         CMUPDATECN(PC)                  | update catalog record
    BRA.B       SETFILLOCK_DONE                 | exit
RSTFILLOCK_OK:
    MOVEQ.L     #0x0,D0                         | no error (already in state)
| Called by: SETFILTYPE_NO, SETFILTYPE_OK, SETFILLOCK_HFS_PATH, RSTFILLOCK_CONT_3, SETFILEINFO
SETFILLOCK_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| _SetFileInfo ($A00D): set file info from param block
SETFILEINFO:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.W       FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.W       GETFILEINFO_NO_7                | no: MFS SetFileInfo
    MOVEQ.L     #-0x2B,D0                       | fnfErr (-43)
    CMPI.B      #0x2,(A5)                       | file record? (cdrFilRec)
    BNE.B       SETFILLOCK_DONE                 | no: exit
| copy Finder info and dates from param block to catalog
    MOVEM.L     0x20(A0),D1-D4                  | ioFlFndrInfo (16 bytes)
    MOVEM.L     D1-D4,0x4(A5)                   | -> filUsrWds in catalog
    MOVEM.L     0x48(A0),D1-D2                  | ioFlCrDat + ioFlMdDat
    MOVEM.L     D1-D2,0x2C(A5)                  | -> filCrDat + filMdDat
    BRA.B       RSTFILLOCK_CONT_3               | update catalog record
| _SetCatInfo: set catalog info (HFS extended)
SETCATINFO:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSR.B       FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.W       GETFILEINFO_NO_7                | no: MFS path
    CMPI.B      #0x2,(A5)                       | file record? (cdrFilRec)
    BNE.B       FILEFILETFSETCATINFO_HFS_NO     | no: check directory
| file record: copy Finder info, dates, and extended info
    MOVEM.L     0x20(A0),D0-D3                  | ioFlFndrInfo (16 bytes)
    MOVEM.L     D0-D3,0x4(A5)                   | -> filUsrWds in catalog
    MOVEM.L     0x54(A0),D0-D3                  | ioFlXFndrInfo (16 bytes)
    MOVEM.L     D0-D3,0x38(A5)                  | -> filFndrInfo2 in catalog
    MOVEM.L     0x48(A0),D0-D1                  | ioFlCrDat + ioFlMdDat
    MOVEM.L     D0-D1,0x2C(A5)                  | -> filCrDat + filMdDat
    MOVE.L      0x50(A0),0x34(A5)               | ioFlBkDat -> filBkDat
    BRA.B       FILEFILETFSETCATINFO_HFS_CONT   | update catalog
| directory record: copy directory info + dates
FILEFILETFSETCATINFO_HFS_NO:
    MOVEQ.L     #-0x25,D0                       | bdNamErr (-37)
    CMPI.B      #0x1,(A5)                       | directory record? (cdrDirRec)
    BNE.B       FILEFILETFSETCATINFO_HFS_ERR    | no: exit with error
    MOVEM.L     0x20(A0),D1-D4                  | ioFlFndrInfo (user info)
    MOVEM.L     D1-D4,0x16(A5)                  | -> dirUsrInfo in catalog
    MOVEM.L     0x54(A0),D0-D3                  | ioFlXFndrInfo (ext info)
    MOVEM.L     D0-D3,0x26(A5)                  | -> dirFndrInfo2
    MOVEM.L     0x48(A0),D0-D2                  | ioFlCrDat + ioFlMdDat + backup
    MOVEM.L     D0-D2,0xA(A5)                   | -> dirCrDat + dirMdDat + dirBkDat
FILEFILETFSETCATINFO_HFS_CONT:
    MOVEQ.L     #0x0,D0                         | no error
FILEFILETFSETCATINFO_HFS_ERR:
    BRA.W       RSTFILLOCK_CONT_3               | update catalog and exit
| FndFilName + write protect check (shared by Delete/Lock/SetInfo)
| Called by: FILEDELETE, SETFILTYPE_NO, SETFILLOCK_HFS_PATH, SETFILEINFO, SETCATINFO
FILEFILETFSETCATINFO_HFS_CONT_2:
    MOVE.L      (A7)+,-(A6)                     | save return address on FS stack
    BSR.B       P_FndFilName                    | find file by name
    BNE.B       FILEFILETFSETCATINFO_HFS_ERR_2  | not found: exit
    BSR.W       SETVOLINFO_HFS_CONT_3           | check write protect
    BNE.B       FILEFILETFSETCATINFO_HFS_ERR_2  | write-protected: exit
    MOVE.L      (A6)+,-(A7)                     | restore return address
    RTS                                         | return from FILEFILETFSETCATINFO_HFS_CONT_2
FILEFILETFSETCATINFO_HFS_ERR_2:
    ADDQ.W      #0x4,A6                         | discard saved return address
    BRA.W       FSQUEUE_DONE                    | CmdDone with error
| ----------------------------------------------------------
|
| P_Fnd Fil Name
|
| Called during boot.
P_FndFilName:
    MOVE.L      (0x78C).W,-(A7)                 | HFS vector: FndFilName
    RTS                                         | jump via vector
| FndFilName: resolve pathname to volume, directory, and catalog record
VFNDFILNAME:
    BSR.W       P_DTRMV3                        | DTRMV3: determine volume/dir
    BEQ.B       FNDFILNAME_OK                   | ok: continue
FNDFILNAME_CONT:
    RTS                                         | return with error in D0
| ----------------------------------------------------------
|
| FNDFILNAME_OK
|
| Called during boot.
| FndFilName common entry: get DirID from WDCB and check for DirID override
FNDFILNAME_OK:
    MOVEQ.L     #0x2,D6                         | default root DirID (FSRtDirID)
    MOVE.L      A3,D7                           | have a WDCB?
    BEQ.B       FNDFILNAME_NO                   | no: use root
    MOVE.L      0x4(A3),D6                      | D6 = DirID from WDCB
    MOVE.L      0x8(A3),D7                      | D7 = catalog hint
FNDFILNAME_NO:
| check if caller provided a pathname with content
    MOVE.L      A4,D0                           | A4 = parsed pathname position
    BEQ.B       FNDFILNAME_NO_2                 | no pathname
    SUB.L       0x12(A0),D0                     | offset from start of string
    SUBQ.L      #0x2,D0                         | subtract header
    BGT.B       FNDFILNAME_NO_3                 | has filename component
FNDFILNAME_NO_2:
| check for HFS DirID override
    BTST        #0x9,0x6(A0)                    | HFS call? (HFSBit 9 of ioTrap: ioDirID valid)
    BEQ.B       FNDFILNAME_NO_3                 | no: use WDCB's DirID
    MOVE.L      0x30(A0),D0                     | caller-supplied DirID?
    BEQ.B       FNDFILNAME_NO_3                 | no: use WDCB's
    MOVE.L      D0,D6                           | D6 = caller's DirID
    MOVEQ.L     #0x0,D7                         | clear catalog hint
| MFS/TFS common: check external FS and dispatch
FNDFILNAME_NO_3:
    BSR.W       CkExtFS_AndOnline               | CkExtFS: check external FS
    BNE.B       FNDFILNAME_CONT                 | external FS: exit
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.W       GETFILEINFO_NO_8                | no: MFS name search
| TFS: use catalog for name resolution
    MOVE.L      (A7)+,-(A6)                     | save return address on FS stack
    MOVEM.L     D1/A0-A1,-(A6)                  | save regs
    MOVE.L      D2,D1                           | D1 = name length
    MOVE.L      D2,D4                           | D4 = total pathname length
FNDFILNAME_NEXT:
    MOVEQ.L     #-0x78,D0                       | dirNFErr (-120) default
    MOVEQ.L     #0x0,D1                         | scan position = 0
| TFS FndFilName: parse pathname component by component
FNDFILNAME_CONT_2:
    MOVEQ.L     #0x0,D3                         | D3 = 0 (no dir prefix flag)
    CMP.W       D4,D1                           | past end of pathname?
    BGE.B       FNDFILNAME_OK_3                 | yes: use what we have
    CMPI.B      #0x3A,0x0(A4,D1.W)              | colon separator?
    BEQ.B       FNDFILNAME_OK_2                 | yes: end of component
    CMPI.W      #0x1F,D1                        | name too long? (max 31)
    BLT.B       FNDFILNAME_NO_4                 | no: keep scanning
    MOVEQ.L     #-0x25,D0                       | bdNamErr (-37): too long
    BRA.W       FNDFILNAME_EXIT                 | exit
| ----------------------------------------------------------
|
| FNDFILNAME_NO_4
|
FNDFILNAME_NO_4:
    ADDQ.W      #0x1,D1                         | advance to next char
    BRA.B       FNDFILNAME_CONT_2               | keep scanning
| ----------------------------------------------------------
|
| FNDFILNAME_OK_2
|
| found colon: this component is a directory prefix
| found colon: this component is a directory prefix
FNDFILNAME_OK_2:
    BSET        #0x5,(HFSFlags)                 | set HFS pathname flag
    TST.W       D1                              | leading colon? (position 0)
    SEQ.B       D3                              | D3 = $FF if relative path
    SWAP.W      D3                              | save flag in high word
    MOVE.W      D4,D3                           | remaining pathname length
    SUB.W       D1,D3                           | - component length
    SUBQ.W      #0x1,D3                         | - colon itself
    BGT.B       FNDFILNAME_CONT_3               | more components
FNDFILNAME_OK_3:
    MOVEQ.L     #-0x2B,D0                       | fnfErr (-43): no filename
| look up pathname component in catalog
FNDFILNAME_CONT_3:
    SWAP.W      D3                              | get flags in low word
    MOVEM.L     D6-D7,-(A6)                     | save DirID and hint
| copy current component to A6 stack as Pascal string
    MOVEM.L     D0/A1,-(A7)                     | save regs
    MOVEA.L     D1,A0                           | A0 = component length
    ADDQ.W      #0x1,D1                         | include length byte
    LSR.W       #0x1,D1                         | round up to word boundary
    LSL.W       #0x1,D1                         | even byte count
    SUBA.L      D1,A6                           | allocate on A6 stack
    MOVE.L      D1,-(A7)                        | save rounded size
    MOVE.L      A0,D1                           | D1 = component length
    MOVEA.L     A4,A0                           | source = pathname component
    MOVEA.L     A6,A1                           | dest = A6 stack buffer
    MOVE.L      D1,D0                           | byte count
    _BlockMove                                  | copy component
    MOVE.W      D1,-(A6)                        | save component length
    MOVE.L      (A7)+,D1                        | restore rounded size
    MOVEA.L     A6,A0                           | A0 = Pascal string on stack
    ADDQ.L      #0x1,A0                         | skip to length byte
    MOVEM.L     (A7)+,D0/A1                     | restore regs
| look up this pathname component in the catalog
    EXG         D6,D0                           | D0 = parent DirID, D6 = saved
    MOVE.L      D7,D2                           | catalog hint
    JSR         CMGETCN(PC)                     | look up component in catalog
| pop component from A6 stack
    MOVE.W      (A6)+,-(A7)                     | pop component length
    ADDA.L      D1,A6                           | deallocate component buffer
    MOVEQ.L     #0x0,D1                         | clear high word
    MOVE.W      (A7)+,D1                        | D1 = component length
    TST.W       D0                              | lookup succeeded?
    BNE.B       FNDFILNAME_ERR                  | no: error
| handle leading-colon (relative path): walk up to parent
    TST.B       D3                              | had leading colon?
    BEQ.B       FNDFILNAME_NO_5                 | no: normal lookup
    MOVEQ.L     #-0x78,D0                       | dirNFErr (-120) default
    CMPI.L      #0x1,0x2(A0)                    | at root parent? (DirID=1)
    BEQ.B       FNDFILNAME_ERR                  | yes: can't go higher
    MOVE.L      0x2(A0),D0                      | parent DirID from thread
    MOVEQ.L     #0x0,D2                         | no hint
    SUBA.L      A0,A0                           | no CName (thread lookup)
    JSR         CMGETCN(PC)                     | look up parent directory
    BNE.B       FNDFILNAME_ERR                  | error: exit
    MOVE.L      0x2(A0),D0                      | parent DirID of parent
    MOVEQ.L     #0x0,D2                         | no hint
| check if this was the final component or a directory prefix
FNDFILNAME_NO_5:
    CMPI.W      #0xFFD5,D6                      | was previous result fnfErr?
    BEQ.B       FNDFILNAME_OK_4                 | yes: this is the final result
    MOVEM.L     (A6)+,D6-D7                     | restore saved DirID and hint
    MOVE.L      0x6(A1),D6                      | D6 = this directory's DirID
    MOVE.L      D2,D7                           | D7 = catalog hint
| advance to next pathname component
    ADDQ.W      #0x1,D1                         | skip past colon
    ADDA.L      D1,A4                           | advance pathname pointer
    SUB.W       D1,D4                           | remaining pathname length
    BRA.W       FNDFILNAME_NEXT                 | parse next component
| ----------------------------------------------------------
|
| FNDFILNAME_OK_4
|
| TFS FndFilName: found the file/directory
FNDFILNAME_OK_4:
    MOVEQ.L     #0x0,D0                         | no error
    MOVEA.L     A1,A5                           | A5 = catalog data record
    MOVE.L      D2,0x4(A6)                      | update saved hint on A6 stack
    BRA.B       FNDFILNAME_ERR_2                | cleanup and return
| TFS FndFilName: catalog lookup error
FNDFILNAME_ERR:
    CMPI.W      #0x30,D0                        | CMnotfound?
    BNE.B       FNDFILNAME_ERR_2                | no: keep error code
    MOVE.L      D6,D0                           | restore saved error (fnfErr)
| TFS FndFilName exit: restore regs and return
FNDFILNAME_ERR_2:
    MOVEM.L     (A6)+,D6-D7                     | restore DirID and hint
    MOVE.L      D1,D2                           | D2 = final name length
FNDFILNAME_EXIT:
    MOVEM.L     (A6)+,D1/A0-A1                  | restore saved regs
    MOVE.L      (A6)+,-(A7)                     | restore return address
    TST.W       D0                              | set CCR for caller
    RTS                                         | return from FndFilName
| CkExtFS + volume online check
| Called by: GETVOLINFO_CONT_6, SETVOLINFO, RENAME_VOL_VERIFY_ONLINE, CATMOVE_HFS_PATH, FNDFILNAME_NO_3 (and 2 more)
CkExtFS_AndOnline:
    BSR.W       P_CKExtFS                       | check for external FS
    BNE.B       FNDFILNAME_ERR_3                | external: pass through
    TST.W       0x48(A2)                        | volume online? (vcbDrvNum)
    BNE.B       FNDFILNAME_ERR_3                | yes: ok
    MOVEQ.L     #-0x35,D0                       | nsvErr (-53): vol not mounted
FNDFILNAME_ERR_3:
    MOVE.L      A2,(ReqstVol).W                 | set requested volume
    TST.W       D0                              | set CCR for caller
    RTS                                         | exit CkExtFS
| _GetCatInfo: get catalog info for file or directory
GETCATINFO:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BSET        #0x0,(HFSFlags)                 | set GetCatInfo flag
    TST.W       0x1C(A0)                        | ioFDirIndex < 0?
    BMI.B       GETFILEINFO_CONT                | yes: index from parent dir
    BRA.B       GETFILEINFO_BEGIN               | shared path with GetFileInfo
| _GetFileInfo ($A00C): get file info by name or index
GETFILEINFO:
    BSR.W       FSQUEUE_SETUP                   | FSQueue: wait our turn
    BCLR        #0x0,(HFSFlags)                 | clear GetCatInfo flag
GETFILEINFO_BEGIN:
    MOVE.W      0x1C(A0),D1                     | ioFDirIndex
    BGT.B       GETFILEINFO_CONT_2              | positive: indexed lookup
| name-based lookup
    BSR.W       P_FndFilName                    | find file by name
    BEQ.B       GETFILEINFO_HFS_OR_MFS          | found: get info
    CMPI.W      #0xFFDB,D0                      | extFSErr?
    BNE.W       GETFILEINFO_DONE                | other error: exit
    TST.B       D2                              | had name component?
    BNE.W       GETFILEINFO_DONE                | yes: real error
    BRA.B       GETFILEINFO_EXIT                | no name: synth root info
GETFILEINFO_HFS_OR_MFS:
    BSR.W       TFSVCBTST                       | HFS volume?
    BNE.W       GETFILEINFO_NO_10               | no: MFS GetFileInfo
    MOVE.L      D6,D1                           | D1 = parent DirID
    BRA.W       GETFILEINFO_NO_4                | HFS info path
| indexed lookup (ioFDirIndex > 0 or < 0 for GetCatInfo)
GETFILEINFO_CONT:
    MOVEQ.L     #0x0,D1                         | D1 = 0 (will be set by lookup)
GETFILEINFO_CONT_2:
    BSET        #0x5,(HFSFlags)                 | set HFS pathname flag
    BSR.W       P_DTRMV1                        | determine volume
    BNE.W       GETFILEINFO_DONE                | error: exit
    BSR.B       CkExtFS_AndOnline               | CkExtFS + online check
    BNE.W       GETFILEINFO_DONE                | error: exit
| get DirID from WDCB
    MOVEQ.L     #0x2,D6                         | default root (FSRtDirID)
    MOVE.L      A3,D7                           | have WDCB?
    BEQ.B       GETFILEINFO_NO                  | no: use root
    MOVE.L      0x4(A3),D6                      | D6 = DirID from WDCB
    MOVE.L      0x8(A3),D7                      | D7 = catalog hint
GETFILEINFO_NO:
| check for HFS DirID override
    BTST        #0x9,0x6(A0)                    | HFS call? (HFSBit 9 of ioTrap: ioDirID valid)
    BEQ.B       GETFILEINFO_INDEXED             | no
    TST.L       0x30(A0)                        | caller DirID provided?
    BEQ.B       GETFILEINFO_INDEXED             | no
    MOVE.L      0x30(A0),D6                     | D6 = caller's DirID
    MOVEQ.L     #0x0,D7                         | clear hint
GETFILEINFO_INDEXED:
    BSR.W       TFSVCBTST                       | HFS volume?
    BEQ.B       GETFILEINFO_OK                  | yes: TFS indexed lookup
| MFS: only root dir supported for indexed
    MOVEQ.L     #-0x78,D0                       | dirNFErr (-120)
    CMPI.L      #0x2,D6                         | root directory? (DirID=2)
    BNE.W       GETFILEINFO_DONE                | no: error
    TST.W       D1                              | have an index?
    BGT.W       GETFILEINFO_OK_10               | yes: MFS indexed file lookup
| MFS root directory info (synthetic GetCatInfo response)
GETFILEINFO_EXIT:
    LEA.L       0x1E(A0),A1                     | start of return area
    MOVEQ.L     #0x26,D0                        | 39 words to clear
GETFILEINFO_LOOP:
    CLR.W       (A1)+                           | zero return area
    DBF.W       D0,GETFILEINFO_LOOP             | loop
| fill in synthetic root directory record
    BSET        #0x4,0x1E(A0)                   | set directory attribute bit
    MOVE.L      #0x2,0x30(A0)                   | ioDirID = root (FSRtDirID)
    MOVE.L      #0x1,0x64(A0)                   | ioFlParID = root parent
    MOVE.W      0x14(A2),0x34(A0)               | ioDrNmFls = vcbNmFls
    MOVE.L      0xA(A2),0x48(A0)                | ioDrCrDat = vcbCrDate
    MOVE.L      0xE(A2),0x4C(A0)                | ioDrMdDat = vcbLsMod
| copy volume name to caller's buffer if provided
    MOVE.L      0x12(A0),D0                     | ioNamePtr provided?
    BEQ.B       GETFILEINFO_VOLNAME_DONE        | no: skip name copy
    TST.W       0x1C(A0)                        | ioFDirIndex = 0?
    BEQ.B       GETFILEINFO_VOLNAME_DONE        | yes: no name for index=0
    MOVEA.L     D0,A1                           | dest = caller's name buffer
    LEA.L       0x2C(A2),A0                     | source = vcbVN (volume name)
    MOVEQ.L     #0x1,D0                         | 1 + length byte
    ADD.B       (A0),D0                         | + name length
    _BlockMove                                  | copy volume name
GETFILEINFO_VOLNAME_DONE:
    MOVEQ.L     #0x0,D0                         | no error
    BRA.B       GETFILEINFO_DONE                | exit
| ----------------------------------------------------------
|
| GETFILEINFO_OK
|
| TFS GetFileInfo/GetCatInfo path
GETFILEINFO_OK:
    MOVEQ.L     #0x1,D0                         | FSRtParID (root's parent = 1)
    CMP.L       D0,D6                           | root's parent?
    BEQ.B       GETFILEINFO_FNF_TRANSLATE       | yes: fnfErr (not supported)
| index == 0: get by name (thread lookup)
    TST.W       D1                              | ioFDirIndex
    BNE.B       GETFILEINFO_CONT_3              | nonzero: index by position
    MOVEM.L     A0-A1,-(A6)                     | save param block
    MOVE.L      D6,D0                           | DirID
    MOVE.L      D7,D2                           | catalog hint
    SUBA.L      A0,A0                           | no CName (thread lookup)
    JSR         CMGETCN(PC)                     | get catalog record by DirID
    BNE.B       GETFILEINFO_ERR                 | error: cleanup
    MOVE.L      D2,D7                           | save updated hint
    BRA.B       GETFILEINFO_CONT_5              | format result
| index > 0: get Nth offspring of directory
GETFILEINFO_CONT_3:
    BTST        #0x0,(HFSFlags)                 | GetCatInfo mode?
    BNE.B       GETCATINFO_OFFSPRING            | yes: direct offspring lookup
    MOVE.W      D1,D5                           | D5 = requested offspring index
| check if we can resume from cached position
    MOVE.W      0xB0(A2),D1                     | VCBOffsM: cached offspring index
    CMP.L       0xAC(A2),D6                     | same DirID as cached?
    BNE.B       GETFILEINFO_NO_3                | no: start from beginning
    CMP.W       0x5A(A2),D5                     | requested >= cached?
    BCS.B       GETFILEINFO_NO_3                | no: can't resume
    MOVE.W      0x5A(A2),D0                     | resume from cached position
    MOVE.W      D5,0x5A(A2)                     | update cached index
    SUB.W       D0,D5                           | D5 = relative offset from cache
    BRA.B       GETFILEINFO_DIR_LOOP            | start enumeration
| start enumeration from beginning of directory
GETFILEINFO_NO_3:
    MOVEQ.L     #0x1,D1                         | start from offspring 1
    MOVE.W      D5,0x5A(A2)                     | cache requested index
    SUBQ.W      #0x1,D5                         | D5 = relative offset (0-based)
GETFILEINFO_DIR_LOOP:
    MOVEM.L     A0-A1,-(A6)                     | save param block
GETFILEINFO_LOOP_2:
    MOVE.L      D6,D0                           | DirID
    MOVE.L      D7,D2                           | catalog hint
    SUBA.L      A0,A0                           | no CName
    JSR         CMGETOFF(PC)                    | get Nth offspring record
    BNE.B       GETFILEINFO_ERR                 | error: cleanup
    MOVE.L      D2,D7                           | D7 = catalog hint
    ADDQ.W      #0x1,D1                         | bump offspring index
    CMPI.B      #0x2,(A1)                       | file record? (cdrFilRec)
    BNE.B       GETFILEINFO_LOOP_2              | no: skip non-files
    DBF.W       D5,GETFILEINFO_LOOP_2           | loop for Nth file
    BRA.B       GETFILEINFO_CONT_5              | got the record
| catalog error exit
GETFILEINFO_ERR:
    MOVEM.L     (A6)+,A0-A1                     | restore param block
    CMPI.W      #0x30,D0                        | CMnotfound?
    BNE.B       GETFILEINFO_DONE                | other error: exit
GETFILEINFO_FNF_TRANSLATE:
    MOVEQ.L     #-0x2B,D0                       | fnfErr (-43)
| Called by: GETFILEINFO_BEGIN, GETFILEINFO_CONT_2, GETFILEINFO_INDEXED, GETFILEINFO_VOLNAME_DONE, GETFILEINFO_ERR (and 2 more)
GETFILEINFO_DONE:
    BRA.W       FSQUEUE_DONE                    | CmdDone
| GetCatInfo mode: get offspring directly (includes directories)
GETCATINFO_OFFSPRING:
    MOVEM.L     A0-A1,-(A6)                     | save param block
    MOVE.W      #0xFFFF,0x5A(A2)                | invalidate dir index cache
    MOVE.L      D6,D0                           | DirID
    MOVE.L      D7,D2                           | hint
    SUBA.L      A0,A0                           | no CName
    JSR         CMGETOFF(PC)                    | get offspring record
    BNE.B       GETFILEINFO_ERR                 | error: cleanup
| GETFILEINFO_CONT_5: format result from catalog record into param block
| format result from catalog record into param block
GETFILEINFO_CONT_5:
    LEA.L       0x6(A0),A3                      | A3 = CName in catalog key
    MOVE.L      0x2(A0),D1                      | D1 = parent DirID (ckrParID)
    MOVEA.L     A1,A5                           | A5 = catalog data record
    MOVEM.L     (A6)+,A0-A1                     | restore param block
| copy filename to caller's buffer
    MOVE.L      0x12(A0),D0                     | ioNamePtr provided?
    BEQ.B       GETFILEINFO_NO_4                | no: skip name copy
    MOVEA.L     D0,A4                           | A4 = dest buffer
    MOVE.B      (A3),D0                         | name length
GETFILEINFO_LOOP_3:
    MOVE.B      (A3)+,(A4)+                     | copy name (incl length byte)
    SUBQ.B      #0x1,D0                         | decrement counter
    BCC.B       GETFILEINFO_LOOP_3              | loop until done
| check record type: file or directory?
GETFILEINFO_NO_4:
    BTST        #0x0,(HFSFlags)                 | GetCatInfo mode?
    BNE.B       GETFILEINFO_OK_6                | yes: format all record types
    CMPI.B      #0x2,(A5)                       | file record? (cdrFilRec)
    BNE.B       GETFILEINFO_FNF_TRANSLATE       | no: fnfErr (GetFileInfo only)
| copy file record fields to param block
    LEA.L       0x1E(A0),A4                     | dest = ioFlAttrib area
    MOVEQ.L     #0x18,D0                        | 25 words (50 bytes)
    LEA.L       0x2(A5),A3                      | source = catalog data (past type)
GETFILEINFO_LOOP_4:
    MOVE.W      (A3)+,(A4)+                     | copy file info
    DBF.W       D0,GETFILEINFO_LOOP_4           | loop for all words
    BCLR        #0x4,0x1E(A0)                   | clear directory bit (it's a file)
| set file attributes and scan for open FCBs
GETFILEINFO_EXIT_2:
    ANDI.B      #0x73,0x1E(A0)                  | mask valid attribute bits
    CLR.W       0x18(A0)                        | clear ioRefNum (assume not open)
    MOVE.L      0x14(A5),D2                     | HFS file number (filFlNum)
    BSR.W       TFSVCBTST                       | HFS volume?
    BEQ.B       GETFILEINFO_HFS_FILENUM         | yes: use HFS file number
    MOVE.L      0x12(A5),D2                     | MFS file number
GETFILEINFO_HFS_FILENUM:
    BSR.W       HFSE_CONT_15                    | Gt1stMatch: find FCB for file
    BNE.B       GETFILEINFO_FCB_DONE            | not open: done
| scan open FCBs for attribute bits
GETFILEINFO_OK_4:
    BTST        #0x1,0x4(A1,D1.W)               | FCB has write permission?
    BEQ.B       GETFILEINFO_OK_5                | no
    BSET        #0x2,0x1E(A0)                   | set ioFlAttrib write bit
    BRA.B       GETFILEINFO_CONT_6              | check resource fork
| ----------------------------------------------------------
|
| GETFILEINFO_OK_5
|
GETFILEINFO_OK_5:
    BSET        #0x3,0x1E(A0)                   | set ioFlAttrib read bit
GETFILEINFO_CONT_6:
    BSET        #0x7,0x1E(A0)                   | set "file open" bit in ioFlAttrib
    BNE.B       GETFILEINFO_ERR_3               | already set: skip refnum
    MOVE.W      D1,0x18(A0)                     | ioRefNum = first open FCB
GETFILEINFO_ERR_3:
    LEA.L       0x34(A0),A3                     | A3 = ioFlStBlk area
    BSR.W       FILECLOSE_CONT_6                | update fork lengths from FCB
    BSR.W       HFSE_ERR_9                      | GtNxtMatch: next FCB for file
    BEQ.B       GETFILEINFO_OK_4                | more FCBs: check attributes
GETFILEINFO_FCB_DONE:
    MOVEQ.L     #0x0,D0                         | no error
    BRA.W       GETFILEINFO_DONE                | CmdDone
| ----------------------------------------------------------
|
| GETFILEINFO_OK_6
|
| GetCatInfo format path: handle both file and directory records
GETFILEINFO_OK_6:
    LEA.L       0x1E(A0),A4                     | dest = ioFlAttrib area
    CMPI.B      #0x2,(A5)                       | file record? (cdrFilRec)
    BNE.B       GETFILEINFO_ERR_4               | no: check directory
| GetCatInfo file record: copy extended info
    MOVEQ.L     #0x22,D0                        | 35 words (70 bytes, extended)
    LEA.L       0x2(A5),A3                      | source = catalog data
GETFILEINFO_LOOP_5:
    MOVE.W      (A3)+,(A4)+                     | copy file info
    DBF.W       D0,GETFILEINFO_LOOP_5           | loop
| compute clump size from alloc blocks
    MOVEQ.L     #0x0,D0                         | clear high word
    MOVE.W      0x48(A5),D0                     | filClpSize from catalog
    MULU.W      0x1E(A2),D0                     | * vcbAlBlkSiz
    MOVE.L      D0,0x68(A0)                     | ioFlClpSiz
    MOVE.L      D1,0x64(A0)                     | ioFlParID = parent DirID
    BCLR        #0x4,0x1E(A0)                   | clear directory bit (file)
    BRA.W       GETFILEINFO_EXIT_2              | set attributes + FCB scan
| GetCatInfo directory record
GETFILEINFO_ERR_4:
    CMPI.B      #0x1,(A5)                       | directory record? (cdrDirRec)
    BNE.W       GETFILEINFO_FNF_TRANSLATE       | no: fnfErr
    MOVE.W      0x2(A5),0x1E(A0)                | dirFlags -> ioFlAttrib
    MOVE.W      0x4(A5),0x34(A0)                | dirVal -> ioDrNmFls
    MOVE.L      0x6(A5),0x30(A0)                | dirDirID -> ioDirID
    MOVE.L      D1,0x64(A0)                     | ioFlParID = parent DirID
    MOVEM.L     0xA(A5),D0-D2                   | dirCrDat + dirMdDat + dirBkDat
    MOVEM.L     D0-D2,0x48(A0)                  | -> ioDrCrDat + ioDrMdDat + ioDrBkDat
    MOVEM.L     0x16(A5),D0-D3                  | dirUsrInfo (16 bytes)
    MOVEM.L     D0-D3,0x20(A0)                  | -> ioDrUsrWds
    MOVEM.L     0x26(A5),D0-D3                  | dirFndrInfo (16 bytes)
    MOVEM.L     D0-D3,0x54(A0)                  | -> ioDrFndrInfo
    BCLR        #0x7,0x1E(A0)                   | clear "open" bit
    BSET        #0x4,0x1E(A0)                   | set directory bit
    MOVEQ.L     #0x0,D0                         | no error
    BRA.W       GETFILEINFO_DONE                | CmdDone
| ----------------------------------------------------------
|
| GETFILEINFO_NO_5
|
| MFS SetFilType path: set file version in MFS entry
GETFILEINFO_NO_5:
    MOVE.B      0x1C(A0),0x1(A5)                | set file version byte
    BRA.B       SETFILEINFO_MFS_FLUSH           | update and flush
| ----------------------------------------------------------
|
| GETFILEINFO_NO_6
|
| MFS SetFilLock/RstFilLock path
GETFILEINFO_NO_6:
    TST.B       (FLckUnlck).W                   | lock or unlock?
    BEQ.B       GETFILEINFO_OK_7                | unlock path
    BSET        #0x0,(A5)                       | set file lock bit
    BNE.B       GETFILEINFO_ERR_5               | already locked: done
    BRA.B       SETFILEINFO_MFS_FLUSH           | changed: mark dirty + flush
GETFILEINFO_OK_7:
    BCLR        #0x0,(A5)                       | clear file lock bit
    BEQ.B       GETFILEINFO_ERR_5               | already unlocked: done
| MFS SetFileInfo/SetFilLock: mark dirty and flush
SETFILEINFO_MFS_FLUSH:
    MOVEA.L     A1,A0                           | A0 = directory block
    JSR         MARKBLOCK(PC)                   | mark directory block dirty
    BSR.W       CREATE_CONT_7                   | MFS directory flush
GETFILEINFO_ERR_5:
    MOVEQ.L     #0x0,D0                         | no error
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| GETFILEINFO_NO_7
|
| MFS SetFileInfo: copy Finder info and dates to MFS directory entry
GETFILEINFO_NO_7:
    MOVEM.L     0x20(A0),D1-D4                  | ioFlFndrInfo (16 bytes)
    MOVEM.L     D1-D4,0x2(A5)                   | -> MFS entry Finder info
    MOVEM.L     0x48(A0),D1-D2                  | ioFlCrDat + ioFlMdDat
    MOVEM.L     D1-D2,0x2A(A5)                  | -> MFS entry dates
    BRA.B       SETFILEINFO_MFS_FLUSH           | mark dirty and flush
| ----------------------------------------------------------
|
| GETFILEINFO_NO_8
|
| Called during boot.
| MFS FndFilName: search MFS directory for filename
GETFILEINFO_NO_8:
    MOVEA.L     (A7)+,A3                        | A3 = return address (for JMP)
    TST.B       D2                              | have a filename?
    BNE.B       GETFILEINFO_ERR_6               | yes: search directory
    MOVEQ.L     #-0x25,D0                       | bdNamErr (-37): no name
    BRA.B       GETFILEINFO_ERR_7               | exit
GETFILEINFO_ERR_6:
    MOVE.W      0x14(A2),D7                     | D7 = vcbNmFls (file count)
    BEQ.B       GETFILEINFO_OK_8                | no files: fnfErr
    BSR.W       FILEWRITE_CONT_4                | read first directory block
GETFILEINFO_CONT_8:
    BEQ.B       GETFILEINFO_OK_9                | ok: start scanning
    CMPI.W      #0xFFDF,D0                      | eofErr (-33)?
    BNE.B       GETFILEINFO_ERR_7               | other error: exit
GETFILEINFO_OK_8:
    MOVEQ.L     #-0x2B,D0                       | fnfErr (-43): not found
    BRA.B       GETFILEINFO_ERR_7               | exit
| ----------------------------------------------------------
|
| GETFILEINFO_OK_9
|
| Called during boot.
GETFILEINFO_OK_9:
    MOVEQ.L     #0x0,D0                         | initial entry offset
    MOVEA.L     A4,A1                           | A1 = parsed name ptr
| MFS directory search: scan entries for matching filename
GETFILEINFO_CONT_9:
    MOVE.W      D0,D4                           | D4 = current entry offset
    TST.B       0x0(A5,D4.W)                    | entry in use?
    BEQ.B       SETFILEINFO_MFS_NEXT_BLOCK      | no: next block
| check file version byte
    MOVE.B      0x1(A5,D4.W),D6                 | entry's version byte
    CMP.B       0x1A(A0),D6                     | matches ioVersNum?
    BNE.B       GETFILEINFO_SKIP_3              | no: skip entry
| compare filename using _CmpString
    MOVE.L      A0,-(A7)                        | save param block
    LEA.L       0x32(A5,D4.W),A0                | entry filename (Pascal string)
    MOVEQ.L     #0x0,D0                         | clear high word
    MOVE.B      (A0)+,D0                        | entry name length
    SWAP.W      D0                              | move to high word
    MOVE.W      D2,D0                           | search name length (low word)
    _CmpString                                  | case-insensitive compare
    MOVEA.L     (A7)+,A0                        | restore param block
    BEQ.B       GETFILEINFO_FOUND_3             | match found
GETFILEINFO_SKIP_3:
    SUBQ.W      #0x1,D7                         | decrement file counter
    BEQ.B       GETFILEINFO_OK_8                | all files checked: fnfErr
    MOVE.W      D4,D0                           | current offset
    BSR.W       CREATE_NEXT                     | advance to next MFS entry
    BCS.B       GETFILEINFO_CONT_9              | more entries in block
SETFILEINFO_MFS_NEXT_BLOCK:
    BSR.W       FILEWRITE_NEXT                  | read next directory block
    BRA.B       GETFILEINFO_CONT_8              | continue search
| match found: return entry position
GETFILEINFO_FOUND_3:
    MOVEA.L     A5,A1                           | A1 = directory block base
    LEA.L       0x0(A5,D4.W),A5                 | A5 = matched entry ptr
GETFILEINFO_ERR_7:
    JMP         (A3)                            | tail-call return from GETFILEINFO_ERR_7 via A3
| ----------------------------------------------------------
|
| GETFILEINFO_OK_10
|
| Called during boot.
| MFS indexed GetFileInfo: get Nth file by position
GETFILEINFO_OK_10:
    CMP.W       0x14(A2),D1                     | index > vcbNmFls?
    BHI.B       GETFILEINFO_ERR_8               | yes: fnfErr
| set up directory block scan position
    MOVE.W      0x18(A2),D5                     | vcbAllocPtr (first data block)
    MOVE.W      0x16(A2),D3                     | vcbVBMSt (bitmap start block)
    ADD.W       D3,D5                           | D5 = first dir block
| check if we can resume from cached position
    MOVE.W      0x5A(A2),D7                     | vcbDirIndex (cached index)
    BEQ.B       GETFILEINFO_OK_11               | no cache: start from beginning
    CMP.W       D7,D1                           | index >= cached?
    BCS.B       GETFILEINFO_OK_11               | no: can't resume
    MOVE.W      0x5C(A2),D3                     | resume from cached block
    BRA.B       GETFILEINFO_CONT_10             | start scan
| ----------------------------------------------------------
|
| GETFILEINFO_OK_11
|
| Called during boot.
GETFILEINFO_OK_11:
    MOVEQ.L     #0x1,D7                         | start from file index 1
| scan directory blocks for Nth file
GETFILEINFO_CONT_10:
    CMP.W       D5,D3                           | past last directory block?
    BCC.B       GETFILEINFO_ERR_8               | yes: fnfErr
    MOVE.W      D3,0x5C(A2)                     | cache current block number
    MOVE.W      D7,0x5A(A2)                     | cache current file index
    BSR.W       FILEWRITE_NO_4                  | read directory block
    BNE.B       GETFILEINFO_ERR_8               | error: fnfErr
    MOVEQ.L     #0x0,D0                         | initial entry offset
GETFILEINFO_CONT_11:
    MOVEQ.L     #0x0,D6                         | clear scratch
    TST.B       0x0(A5,D0.W)                    | entry in use?
    BEQ.B       GETFILEINFO_OK_12               | no: next block
    CMP.W       D7,D1                           | found Nth file?
    BEQ.B       GETFILEINFO_OK_13               | yes: return this entry
    ADDQ.W      #0x1,D7                         | bump file counter
    BSR.W       CREATE_NEXT                     | advance to next entry
    BCS.B       GETFILEINFO_CONT_11             | more entries in block
GETFILEINFO_OK_12:
    ADDQ.W      #0x1,D3                         | next directory block
    BRA.B       GETFILEINFO_CONT_10             | read and scan
GETFILEINFO_ERR_8:
    MOVEQ.L     #-0x2B,D0                       | fnfErr (-43): not found
    BRA.W       FSQUEUE_DONE                    | CmdDone
| ----------------------------------------------------------
|
| GETFILEINFO_OK_13
|
| Called during boot.
| found the Nth MFS file: copy name and info to param block
| found Nth MFS file: copy name and info to param block
GETFILEINFO_OK_13:
    LEA.L       0x0(A5,D0.W),A5                 | A5 = matched entry ptr
    LEA.L       0x32(A5),A3                     | A3 = entry filename
| copy filename to caller's buffer
    MOVE.L      0x12(A0),D0                     | ioNamePtr provided?
    BEQ.B       GETFILEINFO_NO_10               | no: skip name copy
    MOVEA.L     D0,A4                           | A4 = dest buffer
    MOVE.B      (A3),D0                         | name length
GETFILEINFO_CONT_12:
    MOVE.B      (A3)+,(A4)+                     | copy name (incl length byte)
    SUBQ.B      #0x1,D0                         | decrement counter
    BCC.B       GETFILEINFO_CONT_12             | loop until done
| copy MFS directory entry to param block
GETFILEINFO_NO_10:
    LEA.L       0x1E(A0),A4                     | dest = ioFlAttrib area
    MOVEQ.L     #0x18,D0                        | 25 words (50 bytes)
    LEA.L       (A5),A3                         | source = MFS entry
GETFILEINFO_LOOP_6:
    MOVE.W      (A3)+,(A4)+                     | copy file info
    DBF.W       D0,GETFILEINFO_LOOP_6           | loop
    BCLR        #0x4,0x1E(A0)                   | clear directory bit (file)
| GetCatInfo on MFS: fill in HFS-compat fields
    BTST        #0x0,(HFSFlags)                 | GetCatInfo mode?
    BEQ.B       GETFILEINFO_NO_11               | no: skip extra fields
    MOVE.L      #0x2,0x64(A0)                   | ioFlParID = root (FSRtDirID)
    CLR.L       0x50(A0)                        | clear ioFlBkDat
    MOVE.L      A0,-(A7)                        | save param block
    LEA.L       0x54(A0),A0                     | clear extended Finder info
    MOVEQ.L     #0x3,D0                         | 4 longs (16 bytes)
GETFILEINFO_LOOP_7:
    CLR.L       (A0)+                           | zero extended info
    DBF.W       D0,GETFILEINFO_LOOP_7           | loop
    MOVEA.L     (A7)+,A0                        | restore param block
GETFILEINFO_NO_11:
    BRA.W       GETFILEINFO_EXIT_2              | set attributes + FCB scan
| helper: test ioDirFlg bit
TFSBitTst:
    BTST        #0x9,0x6(A0)                    | HFS call? (HFSBit 9 of ioTrap: ioDirID valid)
    RTS                                         | return with CCR
| ----------------------------------------------------------
|
| GETFILEINFO_OK_15
|
| Called during boot.
| get VCB from FCB and fall through to TFSVCBTst
GETFILEINFO_OK_15:
    MOVEA.L     0x14(A1,D1.W),A2                | A2 = FCBVPtr (VCB from FCB)
| TFSVCBTst: check if volume is HFS (signature = 'BD' = 0x4244)
| Called by: MOUNTVOL_CONT_6, MOUNTVOL_CONT_8, MOUNTVOL_REMOUNT_NEXT_FCB, MOUNTVOL_NO_6, MTVOLDONE (and 32 more)
TFSVCBTST:
    CMPI.W      #0x4244,0x8(A2)                 | HFS signature? (vcbSigWord)
    RTS                                         | return (Z=HFS, NZ=MFS)
| ----------------------------------------------------------
|
| SEEK
|
| Called during boot.
| Seek: position within file, set up D5=cur pos, D7=IOReqCount
SEEK:
    CLR.L       0x28(A0)                        | haven't actually done any bytes yet (IOActCount)
    MOVEQ.L     #-0x32,D0                       | assume bad count (ParamErr)
    MOVE.L      0x24(A0),D7                     | # bytes to read/write (IOReqCount)
    BMI.B       TFSVCBTST_ERR                   | negative count: exit
    MOVE.L      0x2E(A0),D2                     | ioPosOffset: user's position value
    MOVE.L      0x10(A1,D1.W),D5                | FCBCrPs: current file position
    MOVE.L      0x8(A1,D1.W),D4                 | FCBEOF: logical end of file
| decode position mode (bits 0-1 of ioPosMode)
    MOVE.B      0x2D(A0),D0                     | ioPosMode byte
    ROXR.B      #0x2,D0                         | shift mode bits to C and N
    BCC.B       TFSVCBTST_CONT_2                | mode 0 or 1: from start/current
    BMI.B       TFSVCBTST_CONT                  | mode 3: from EOF + offset
    MOVE.L      D4,D5                           | mode 2: set to EOF
TFSVCBTST_CONT:
    ADD.L       D2,D5                           | add offset to base position
    BRA.B       TFSVCBTST_OK                    | check result
| mode 0 (from start) or mode 1 (from current)
TFSVCBTST_CONT_2:
    BPL.B       TFSVCBTST_OK                    | mode 0: keep current pos
    MOVE.L      D2,D5                           | mode 1: set absolute position
TFSVCBTST_OK:
    BPL.B       TFSVCBTST_OK_2                  | position >= 0: ok
    MOVEQ.L     #-0x28,D0                       | posErr (-40): before start
    BRA.B       TFSVCBTST_ERR                   | exit
| clamp position to EOF
TFSVCBTST_OK_2:
    MOVE.L      D5,D2                           | D2 = new position
    SUB.L       D4,D2                           | D2 = position - EOF
    BLE.B       TFSVCBTST_OK_3                  | within file: ok
    MOVE.L      D4,D5                           | clamp to EOF
TFSVCBTST_OK_3:
    MOVE.L      D5,0x10(A1,D1.W)                | update FCBCrPs
    MOVEQ.L     #0x0,D0                         | no error
TFSVCBTST_ERR:
    RTS                                         | return from Seek
