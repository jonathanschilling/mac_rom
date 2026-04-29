| File Manager - HFS Catalog Operations
|
| Implements HFS catalog B-tree record operations.
| The catalog file is a B-tree that maps (parentID, name) to file/directory info.
|
| Catalog Manager (CM) routines:
| CMCreateCN - create a catalog node (file or directory)
| CMDeleteCN - delete a catalog node
| CMGetCN - look up a catalog node by parent ID + name
| CMMoveCN - move a node to a different parent directory
| CMRenameCN - rename a catalog node
| CMUpdateCN - update an existing catalog record
| CMFlush - flush the catalog B-tree to disk
| LocCNode - locate a catalog node record in the B-tree
| LocCRec - locate a specific catalog record
| UpdCName - update the name in a catalog key
|
| References:
| Inside Macintosh: Files, Ch 2: File Manager, "Data Organization on Volumes"
|

| ----------------------------------------------------------
|
| CM Create CN
|
CMCreateCN:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D3-D7/A0-A4,-(A6)               | save regs
| set up some initial stuff
        BSR     P_CMSetUp                       | common set up routine (CMSetUp)
        CLR.L   0xAC(A2)                        | invalidate current DirID marker (VCBDirIDM)
        MOVE.L  D1,D5                           | D5 = CNode type / file type
        MOVE.L  D0,D3                           | D3 = parID
        MOVE.L  A0,A3                           | A3 = CName pointer
| make sure parent exists
        SUBA.L  A0,A0                           | no CName
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCRec(PC)                     | locate the parent's thread record
        BNE     CC_EXIT                         | error ->
| build key for new CNode
        MOVE.L  D3,D0                           | parID
        MOVE.L  A3,A0                           | CName pointer
        LEA.L   (A4),A1                         | addr(key record buffer) = ckrOff(A4)
        JSR     BuildKey(PC)                    | build the key record
| initialize catalog data record (cdr) for directory or file
        LEA.L   0x26(A4),A1                     | addr(data record buffer) = cdrOff(A4)
        MOVE.L  A1,A0                           | clear
        MOVE    #0x32,D0                        | (lencdr/2)-1
CC_CLR_CDR_LOOP:
        CLR     (A0)+                           | the record first
        DBF     D0,CC_CLR_CDR_LOOP              | loop for all words
        MOVE.B  D5,(A1)                         | set record type (cdrType)
        MOVE.L  (Time).w,D2                     | D2 = current date/time
        CMPI.B  #0x1,D5                         | creating a directory? (CMDirCN)
        BNE.B   CC_INIT_FILE                    | no ->
        MOVE.L  vcbNxtCNID(A2),D6               | assign it a DirID
        MOVE.L  D6,0x6(A1)                      | dirDirID = new CNID
        ADDQ.L  #0x1,vcbNxtCNID(A2)             | bump next available CNode ID
        MOVE.L  D2,0xA(A1)                      | set creation date (dirCrDat)
        MOVE.L  D2,0xE(A1)                      | set modification date (dirMdDat)
        MOVEQ.L #0x46,D1                        | D1 = size of directory data record (lendir=70)
        BRA.B   CC_ADD_REC                      | add new record ->

| ----------------------------------------------------------
|
| CC_INIT_FILE
|
CC_INIT_FILE:
        MOVE.L  D2,0x2C(A1)                     | set creation date (filCrDat)
        MOVE.L  D2,0x30(A1)                     | set modification date (filMdDat)
        MOVE.L  vcbNxtCNID(A2),0x14(A1)         | assign file number (filFlNum = next CNID)
        ADDQ.L  #0x1,vcbNxtCNID(A2)             | bump next available CNode ID
        SWAP    D5                              | set file type
        MOVE.B  D5,0x3(A1)                      | filTyp
        SWAP    D5                              | restore record type in low byte
        MOVEQ.L #0x66,D1                        | D1 = size of file data record (lenfil=102)
| CCAddRec: add new directory/file record to catalog BTree
CC_ADD_REC:
        MOVE    0xA6(A2),D0                     | refnum of catalog file (VCBCtRef)
        LEA.L   (A4),A0                         | addr(key record buffer) = ckrOff(A4)
        JSR     P_mBTInsert(PC)                 | insert the record
        BEQ.B   CC_BLD_THD                      | ok ->
        CMPI    #0x21,D0                        | does CNode already exist? (BTexists)
        BNE     CC_EXIT                         | no, some other error ->
        MOVEQ.L #0x31,D0                        | set CM result code (CMexists)
        BRA     CC_EXIT                         | exit ->

| ----------------------------------------------------------
|
| CC_BLD_THD
|
| CCBldThd: build thread record for new directory CNode
CC_BLD_THD:
        MOVE.L  D2,D7                           | D7 = new hint
        CMPI.B  #0x1,D5                         | creating a directory?
        BNE.B   CC_UPD_PAR                      | no ->
        MOVE.L  D6,D0                           | parID = new directory ID
        SUBA.L  A0,A0                           | no CName
        LEA.L   (A4),A1                         | addr(key record buffer)
        JSR     BuildKey(PC)                    | build the key record
        LEA.L   0x26(A4),A1                     | clear
        MOVE    #0x16,D0                        | (lenthd/2)-1
CC_CLR_THD_LOOP:
        CLR     (A1)+                           | the record first
        DBF     D0,CC_CLR_THD_LOOP              | loop for all words
        LEA.L   0x26(A4),A1                     | addr(thread record)
        MOVE.B  #0x3,(A1)                       | set record type (cdrThdRec=3)
        MOVE.L  D3,0xA(A1)                      | set parent ID (thdParID)
        MOVE.L  A3,A0                           | source = input CName
        LEA.L   0xE(A1),A1                      | dest = thread record CName (thdCName)
        JSR     UpdCName(PC)                    | move in the CName
| add thread record to catalog BTree
        MOVE    0xA6(A2),D0                     | refnum of catalog file (VCBCtRef)
        MOVE    #0x2E,D1                        | length of thread record (lenthd=46)
        LEA.L   (A4),A0                         | addr(key record)
        LEA.L   0x26(A4),A1                     | addr(thread record)
        JSR     P_mBTInsert(PC)                 | insert the record
        BEQ.B   CC_UPD_PAR                      | ok ->
| couldn't add thread record, delete newly created directory record
        MOVE.L  D0,-(A6)                        | save result code
        MOVE.L  D3,D0                           | parID
        MOVE.L  A3,A0                           | CName pointer
        LEA.L   (A4),A1                         | ptr(key record buffer)
        JSR     BuildKey(PC)                    | build the key record
        MOVE.L  A1,A0                           | ptr to key
        MOVE    0xA6(A2),D0                     | refnum of catalog file
        JSR     P_mBTDelete(PC)                 | delete the directory record
        MOVE.L  (A6)+,D0                        | restore original result code
        CMPI    #0x21,D0                        | did thread record already exist? (BTexists)
        BNE.B   CC_EXIT                         | no, some other error ->
        MOVEQ.L #0x31,D0                        | set CM result code (CMexists)
        BRA.B   CC_EXIT                         | exit ->
| CCUpdPar: update parent directory
CC_UPD_PAR:
        MOVE.L  D3,D0                           | ParID
        SUBA.L  A0,A0                           | no CName
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate the directory record
        BNE.B   CC_EXIT                         | error ->
        ADDQ.W  #0x1,0x4(A1)                    | bump valence (dirVal)
        MOVE.L  (Time).w,0xE(A1)                | set date/time last modified (dirMdDat)
        MOVE    0xA6(A2),D0                     | catalog refnum
        JSR     P_mBTUpdate(PC)                 | update the BTree record
        BNE.B   CC_EXIT                         | error ->
| update VCB directory and file counts
        MOVE.B  D5,D0                           | CNode type
        MOVE.L  D3,D1                           | ParID
        MOVEQ.L #0x1,D2                         | increment value
        BSR     UPD_VCNTS                       | UpdVCnts: update the counts
| CCExit
        CLR     D0                              | result = 'ok'
        MOVE.L  D6,D1                           | return DirID in D1
        MOVE.L  D7,D2                           | return hint in D2
        JSR     MarkVCBTime(PC)                 | mark the VCB dirty
        JSR     CMFlush(PC)                     | flush the catalog
CC_EXIT:
        ADDA    #0x8C,A6                        | de-allocate CM vars (lenCMVars)
        MOVEM.L (A6)+,D3-D7/A0-A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit CMCreateCN

| CMDeleteCN -- delete catalog entry.
| ----------------------------------------------------------
|
| CM Delete CN
|
CMDeleteCN:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D6/A0-A1/A3-A4,-(A6)         | save regs
| set up some common stuff
        BSR     P_CMSetUp                       | common set up routine
        CLR.L   0xAC(A2)                        | invalidate current DirID marker (VCBDirIDM)
        MOVE.L  D0,D3                           | D3 = parID
        MOVE.L  A0,A3                           | A3 = CName pointer
| locate subject CNode
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate the CNode
        BNE     DC_EXIT                         | didn't find it, exit ->
        MOVE.B  (A1),D4                         | D4 = CNode record type (cdrType)
        MOVE.L  0x2(A0),D6                      | D6 = CNode ParID (ckrParID)
| DCCkDir: if directory, make sure it's not root and is empty
        CMPI.B  #0x1,D4                         | directory record? (cdrDirRec)
        BNE.B   DC_DELETE                       | no, must be a file ->
        MOVE.L  0x6(A1),D5                      | save DirID (dirDirID)
        CMPI.L  #0x2,D5                         | root directory? (FSRtDirID=2)
        BNE.B   DC_CHK_EMPTY                    | no ->
        MOVEQ.L #0x33,D0                        | yes, set error code (CMRootCN)
        BRA     DC_EXIT                         | exit ->
DC_CHK_EMPTY:
        TST     0x4(A1)                         | directory empty? (dirVal)
        BEQ.B   DC_DELETE                       | yes ->
        MOVEQ.L #0x32,D0                        | set error code (CMnotempty)
        BRA.B   DC_EXIT                         | exit ->
| DCDelete: delete catalog records for CNode
DC_DELETE:
        LEA.L   (A4),A0                         | addr(key record)
        MOVE    0xA6(A2),D0                     | catalog file refnum (VCBCtRef)
        JSR     P_mBTDelete(PC)                 | delete directory/file record
        BNE.B   DC_EXIT                         | error ->
| DCDelThd: delete thread record (directories only)
        CMPI.B  #0x1,D4                         | directory being deleted?
        BNE.B   DC_UPD_PAR                      | no ->
        SUBA.L  A0,A0                           | no CName
        MOVE.L  D5,D0                           | parID = directory DirID
        LEA.L   (A4),A1                         | addr(key record buffer)
        JSR     BuildKey(PC)                    | build thread key record
        LEA.L   (A4),A0                         | addr(key record)
        MOVE    0xA6(A2),D0                     | catalog file refnum
        JSR     P_mBTDelete(PC)                 | delete thread record
        BNE.B   DC_EXIT                         | error ->
| DCUpdPar: update parent directory
DC_UPD_PAR:
        MOVE.L  D6,D0                           | ParID
        SUBA.L  A0,A0                           | no CName
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate parent directory record
        BNE.B   DC_EXIT                         | error ->
        SUBQ.W  #0x1,0x4(A1)                    | decrement valence (dirVal)
        MOVE.L  (Time).w,0xE(A1)                | set date/time last modified (dirMdDat)
        MOVE    0xA6(A2),D0                     | catalog refnum
        JSR     P_mBTUpdate(PC)                 | update the BTree record
        BNE.B   DC_EXIT                         | error ->
| update VCB directory and file counts
        MOVE.B  D4,D0                           | CNode type
        MOVE.L  D6,D1                           | ParID
        MOVEQ.L #-0x1,D2                        | decrement value
        BSR     UPD_VCNTS                       | UpdVCnts: update the counts
| DCExit
        CLR     D0                              | result = 'ok'
        JSR     MarkVCBTime(PC)                 | mark the VCB dirty
        JSR     CMFlush(PC)                     | flush the catalog
DC_EXIT:
        ADDA    #0x8C,A6                        | de-allocate CM vars
        MOVEM.L (A6)+,D1-D6/A0-A1/A3-A4         | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit CMDeleteCN

| CMGetCN -- locate catalog record.
| ----------------------------------------------------------
|
| CM Get CN
|
| Called by: FNDFILNAME_CONT_3, MOUNTVOL_OK_3, MTCHECK, MOUNTVOL_FOUND_3, GETVOLINFO_CONT_6 (and 4 more)
CMGetCN:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/D3/A3-A4,-(A6)               | save regs
        BSR     P_CMSetUp                       | common set up routine
        CLR.L   0xAC(A2)                        | invalidate current DirID marker (VCBDirIDM)
| locate directory/file BTree record for the CNode
        JSR     LocCNode(PC)                    | locate the record
| GCExit
        ADDA    #0x8C,A6                        | de-allocate CM vars
        MOVEM.L (A6)+,D1/D3/A3-A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit CMGetCN

| CMGetOff -- get Nth offspring record.
| ----------------------------------------------------------
|
| CM Get Off
|
CMGetOff:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/D3-D4/A4,-(A6)               | save regs
        BSR     P_CMSetUp                       | common set up routine
        MOVE.L  D0,D3                           | D3 = DirID
        MOVE    D1,D4                           | D4 = offspring index
        MOVE.L  0xAC(A2),D1                     | D1 = cached DirID (vcbDirIDM)
        BEQ.B   GO_LOCATE_THD                   | yes ->
        CMP.L   D3,D1                           | Compare
        BEQ.B   GO_GET_OFF                      | yes ->
GO_LOCATE_THD:
        CLR.L   0xAC(A2)                        | invalidate current DirID marker (VCBDirIDM)
        MOVE.L  D3,D0                           | DirID
        SUBA.L  A0,A0                           | no CName
        JSR     LocCRec(PC)                     | locate the thread record
        BNE.B   GO_EXIT                         | didn't find it, exit ->
        MOVE.L  D3,0xAC(A2)                     | update current DirID (VCBDirIDM)
        CLR     0xB0(A2)                        | clear offspring index marker (VCBOffsM)
| GOGetOff: get offspring record
GO_GET_OFF:
        MOVE    0xA6(A2),D0                     | catalog file refnum (VCBCtRef)
        MOVE    D4,D1                           | selection index = offspring index
        SUB     0xB0(A2),D1                     | - current offspring index marker
        JSR     P_mBTGetRecord(PC)              | get the record
        BEQ.B   GO_CHK_PARENT                   | ok ->
        CMPI    #0x20,D0                        | result = 'not found'? (BTnotfound)
        BNE.B   GO_INVAL_EXIT                   | no, some other error ->
GO_NOT_FOUND:
        MOVEQ.L #0x30,D0                        | set error code (CMnotfound)
GO_INVAL_EXIT:
        CLR.L   0xAC(A2)                        | invalidate current DirID marker
        BRA.B   GO_EXIT                         | exit ->
GO_CHK_PARENT:
        CMP.L   0x2(A0),D3                      | same parent? (ckrParID)
        BNE.B   GO_NOT_FOUND                    | no ->
        MOVE    D4,0xB0(A2)                     | update offspring index marker (VCBOffsM)
| GOExit
GO_EXIT:
        ADDA    #0x8C,A6                        | de-allocate CM vars
        MOVEM.L (A6)+,D1/D3-D4/A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit CMGetOff

| CMMoveCN -- move the catalog entry.
| ----------------------------------------------------------
|
| CM Move CN
|
CMMoveCN:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/D3-D7/A0-A1/A3-A4,-(A6)      | save regs
        BSR     P_CMSetUp                       | common set up routine
        CLR.L   0xAC(A2)                        | invalidate current DirID marker (VCBDirIDM)
        MOVE.L  D1,D5                           | D5 = dest DirID/ParID
        MOVE.L  A1,D6                           | D6 = dest CName ptr
        MOVE.L  D0,D3                           | D3 = source DirID/ParID
        MOVE.L  A0,A3                           | A3 = source CName pointer
| MCChkSrc: make sure source CNode exists
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate the record
        BNE     MC_ERR_EXIT                     | didn't find source ->
        MOVEQ.L #0x0,D4                         | assume source is not a directory
        CMPI.B  #0x1,(A1)                       | directory record? (cdrDirRec)
        BNE.B   MC_CHK_DEST                     | no ->
        MOVE.L  0x6(A1),D4                      | D4 = directory ID (dirDirID)
| MCChkDest: make sure destination exists and is a directory
MC_CHK_DEST:
        MOVE.L  D5,D0                           | dest DirID/ParID
        MOVE.L  D6,A0                           | dest CName ptr
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate destination
        BNE     MC_ERR_EXIT                     | didn't find dest ->
        CMPI.B  #0x1,(A1)                       | directory record? (cdrDirRec)
        BEQ.B   MC_CHK_DST_DIR                  | yes ->
        MOVE    #-0x7A,D0                       | result = BadMovErr
        BRA     MC_ERR_EXIT                     | exit ->
| MCChkDst: check for invalid move operation
MC_CHK_DST_DIR:
        MOVE.L  0x6(A1),D7                      | D7 = dest directory ID (dirDirID)
        TST.L   D4                              | source is a directory?
        BEQ.B   MC_LOC_SRC                      | no ->
        CMPI.L  #0x2,D4                         | root directory? (FSRtDirID)
        BEQ.B   MC_BAD_MOVE                     | yes, can't move root ->
        CMP.L   D4,D7                           | moving to same directory?
        BEQ.B   MC_BAD_MOVE                     | yes, invalid ->
MC_CHK_ANCESTOR:
        MOVE.L  0x2(A0),D0                      | D0 = parent DirID from thread record
        CMP.L   D4,D0                           | Compare
        BEQ.B   MC_BAD_MOVE                     | yes ->
        CMPI.L  #0x2,D0                         | Compare
        BLE.B   MC_LOC_SRC                      | ->
| MCChkAncestors: check moving into own descendant
        SUBA.L  A0,A0                           | no CName
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | trace ancestry
        BNE     MC_ERR_EXIT                     | error ->
        BRA.B   MC_CHK_ANCESTOR                 | continue checking ->
MC_BAD_MOVE:
        MOVE    #-0x7A,D0                       | result = BadMovErr
        BRA     MC_ERR_EXIT                     | exit ->
| MCLocSrc: locate source CNode record
MC_LOC_SRC:
        MOVE.L  D3,D0                           | source parID
        MOVE.L  A3,A0                           | source CName
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate source CNode
        BNE     MC_ERR_EXIT                     | error ->
        CMP.L   0x2(A0),D7                      | same parent (null move)?
        BNE.B   MC_COPY_SRC                     | no, real move ->
        MOVE.L  D2,D7                           | save hint for null move
        BRA     MC_EXIT                         | all done (null move) ->
| MCCopySrc: save source record data
MC_COPY_SRC:
        MOVE.L  A1,-(SP)                        | save ptr to data record
        LEA.L   (A4),A1                         | dest = CM vars key buffer
        MOVEQ.L #0x1,D0                         | key length + 1
        ADD.B   (A0),D0                         | = key size
        _BlockMove                              | copy the key record
        MOVE.L  (SP)+,A0                        | source = data record
        LEA.L   0x26(A4),A1                     | dest = CM vars data buffer
        MOVE    D1,D0                           | data record size
        EXT.L   D0                              | sign-extend for BlockMove
        _BlockMove                              | copy the data record
| MCBldDst: build destination key and insert
        LEA.L   (A4),A0                         | addr(key record)
        MOVE.L  0x2(A0),D4                      | D4 = source ParID (save for later)
        MOVE.L  D7,0x2(A0)                      | set new ParID = dest DirID
        LEA.L   0x26(A4),A1                     | addr(data record)
        MOVEQ.L #0x66,D1                        | assume file record size (lenfil)
        CMPI.B  #0x2,(A1)                       | file record? (cdrFilRec=2)
        BEQ.B   MC_INSERT_DST                   | yes ->
        MOVEQ.L #0x46,D1                        | directory record size (lendir)
        MOVE.L  (Time).w,0xE(A1)                | set modification date (dirMdDat)
MC_INSERT_DST:
        MOVE    0xA6(A2),D0                     | catalog file refnum
        JSR     P_mBTInsert(PC)                 | insert at destination
        BEQ.B   MC_UPD_DEST                     | ok ->
        CMPI    #0x21,D0                        | already exists? (BTexists)
        BNE     MC_ERR_EXIT                     | no, other error ->
        MOVEQ.L #0x31,D0                        | set CM result code (CMexists)
        BNE     MC_ERR_EXIT                     | exit ->
| MCUpdDest: update destination parent directory
MC_UPD_DEST:
        MOVE.L  D2,D7                           | save new hint
        MOVE.L  0x2(A0),D0                      | dest ParID from key
        EXG     D5,D0                           | save it, get dest DirID
        MOVE.L  D6,A0                           | dest CName ptr
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate dest parent directory
        BNE     MC_ERR_EXIT                     | error ->
        ADDQ.W  #0x1,0x4(A1)                    | bump valence (dirVal)
        MOVE.L  (Time).w,0xE(A1)                | set date/time last modified (dirMdDat)
        MOVE    0xA6(A2),D0                     | catalog refnum
        JSR     P_mBTUpdate(PC)                 | update the BTree record
        BNE     MC_ERR_EXIT                     | error ->
| update VCB counts for destination
        LEA.L   0x26(A4),A1                     | ptr to saved data record
        MOVE.B  (A1),D0                         | CNode type
        MOVE.L  D5,D1                           | dest ParID
        MOVEQ.L #0x1,D2                         | increment
        BSR     UPD_ROOT_CNTS                   | UpdVCnts
| MCDelSrc: delete source record
        MOVE.L  D3,D0                           | source ParID
        MOVE.L  A3,A0                           | source CName
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate source CNode
        BNE.B   MC_ERR_EXIT                     | error ->
        LEA.L   (A4),A0                         | addr(key record)
        MOVE    0xA6(A2),D0                     | catalog file refnum
        JSR     P_mBTDelete(PC)                 | delete source record
        BNE.B   MC_ERR_EXIT                     | error ->
| MCUpdThd: update thread record if directory
        LEA.L   0x26(A4),A1                     | ptr to data record
        CMPI.B  #0x1,(A1)                       | directory? (cdrDirRec)
        BNE.B   MC_UPD_SRC                      | no ->
        MOVE.L  0x6(A1),D0                      | DirID (dirDirID)
        SUBA.L  A0,A0                           | no CName
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCRec(PC)                     | locate thread record
        BNE.B   MC_ERR_EXIT                     | error ->
        MOVE.L  D5,0xA(A1)                      | update thdParID = new parent
        MOVE    0xA6(A2),D0                     | catalog refnum
        JSR     P_mBTUpdate(PC)                 | update thread record
        BNE.B   MC_ERR_EXIT                     | error ->
| MCUpdSrc: update source parent directory
MC_UPD_SRC:
        MOVE.L  D4,D0                           | source ParID
        SUBA.L  A0,A0                           | no CName
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate source parent
        BNE.B   MC_ERR_EXIT                     | error ->
        SUBQ.W  #0x1,0x4(A1)                    | decrement valence (dirVal)
        MOVE.L  (Time).w,0xE(A1)                | set date/time last modified
        MOVE    0xA6(A2),D0                     | catalog refnum
        JSR     P_mBTUpdate(PC)                 | update the BTree record
        BNE.B   MC_ERR_EXIT                     | error ->
| update VCB counts for source
        LEA.L   0x26(A4),A1                     | ptr to data record
        MOVE.B  (A1),D0                         | CNode type
        MOVE.L  D4,D1                           | source ParID
        MOVEQ.L #-0x1,D2                        | decrement
        BSR     UPD_ROOT_CNTS                   | UpdVCnts
| MCExit
MC_EXIT:
        CLR     D0                              | result = 'ok'
        MOVE.L  D7,D2                           | return hint in D2
        JSR     MarkVCBTime(PC)                 | mark the VCB dirty
        JSR     CMFlush(PC)                     | call
MC_ERR_EXIT:
        ADDA    #0x8C,A6                        | deallocate CM vars from A6 stack
        MOVEM.L (A6)+,D1/D3-D7/A0-A1/A3-A4      | Restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | Return

| CMRenameCN -- rename the root directory.
| ----------------------------------------------------------
|
| CM Rename CN
|
CMRenameCN:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/D3-D7/A0-A1/A3-A4,-(A6)      | save regs
        BSR     P_CMSetUp                       | common set up routine
        CLR.L   0xAC(A2)                        | invalidate current DirID marker
        MOVE.L  D0,D3                           | D3 = ParID
        MOVE.L  A0,A3                           | A3 = old CName pointer
        MOVE.L  A1,D5                           | D5 = new CName pointer
| locate source CNode
        JSR     LocCNode(PC)                    | locate the CNode
        BNE     RC_ERR_EXIT                     | didn't find it ->
        MOVE.L  D2,D4                           | D4 = catalog hint
        MOVE    D1,D6                           | D6 = data record size
| save catalog data record
        MOVE.L  A1,A0                           | source = data record
        LEA.L   0x26(A4),A1                     | dest = CM vars data buffer
        MOVE    D6,D0                           | data record size
        EXT.L   D0                              | sign-extend for BlockMove
        _BlockMove                              | copy data record
| build new key and insert renamed record
        LEA.L   (A4),A1                         | addr(key record buffer)
        MOVE.L  0x2(A1),D0                      | ParID from old key (ckrParID)
        MOVE.L  D5,A0                           | new CName pointer
        JSR     BuildKey(PC)                    | build key with new name
        MOVE.L  A1,A0                           | ptr to new key
        LEA.L   0x26(A4),A1                     | ptr to data record
        MOVE    D6,D1                           | data record size
        MOVE    0xA6(A2),D0                     | catalog file refnum
        JSR     P_mBTInsert(PC)                 | insert renamed record
        BEQ.B   RC_DEL_OLD                      | ok ->
        CMPI    #0x21,D0                        | already exists? (BTexists)
        BNE     RC_ERR_EXIT                     | no, other error ->
| "already exists": check if it's really a case-only rename
        LEA.L   (A4),A1                         | addr(key record)
        MOVE.L  0x2(A1),D0                      | ParID
        MOVE.L  D5,A0                           | new CName
        MOVEQ.L #0x0,D2                         | no hint
        JSR     LocCNode(PC)                    | locate existing CNode with new name
        BNE     RC_ERR_EXIT                     | error ->
        MOVE.L  D2,D7                           | D7 = hint
        MOVE.L  A0,D6                           | D6 = ptr(key record)
        LEA.L   0x26(A4),A0                     | ptr(saved data record)
        MOVE.B  (A0),D0                         | saved record type
        CMP.B   (A1),D0                         | same type as found record?
        BNE.B   RC_EXISTS_ERR                   | no, different CNode ->
        CMPI.B  #0x1,D0                         | directory? (cdrDirRec)
        BNE.B   RC_CHK_FILNUM                   | no, check file ->
        MOVE.L  0x6(A1),D1                      | found DirID
        CMP.L   0x6(A0),D1                      | same DirID as saved?
        BEQ.B   RC_CASE_RENAME                  | yes, same CNode (case-only rename) ->
        BRA.B   RC_EXISTS_ERR                   | different CNode ->
RC_CHK_FILNUM:
        MOVE.L  0x14(A1),D1                     | found file number (filFlNum)
        CMP.L   0x14(A0),D1                     | same file number?
        BEQ.B   RC_CASE_RENAME                  | yes, same CNode ->
RC_EXISTS_ERR:
        MOVEQ.L #0x31,D0                        | result = CMexists
        BRA.B   RC_ERR_EXIT                     | exit ->
| case-only rename: just update the name in place
RC_CASE_RENAME:
        MOVE.L  D6,A1                           | ptr(key record of found CNode)
        LEA.L   0x6(A1),A1                      | ptr to CName in key (ckrCName)
        MOVE.L  D5,A0                           | source = new CName
        JSR     UpdCName(PC)                    | update the CName
        MOVE    0xA6(A2),D0                     | catalog refnum
        JSR     P_mBTUpdate(PC)                 | update BTree record
        BRA.B   RC_UPD_THD                      | skip to thread update ->
| RCDelOld: normal rename - delete old record
RC_DEL_OLD:
        MOVE.L  D2,D7                           | D7 = new hint
        MOVE.L  D3,D0                           | old ParID
        MOVE.L  A3,A0                           | old CName
        MOVE.L  D4,D2                           | old hint
        JSR     LocCNode(PC)                    | locate old CNode
        BNE     RC_ERR_EXIT                     | error ->
        LEA.L   (A4),A0                         | addr(key record)
        MOVE    0xA6(A2),D0                     | catalog file refnum
        MOVEQ.L #0x0,D2                         | no hint
        JSR     P_mBTDelete(PC)                 | delete old record
        BNE.B   RC_ERR_EXIT                     | error ->
| RCUpdThd: update thread record with new name
RC_UPD_THD:
        LEA.L   0x26(A4),A1                     | ptr to data record
        CMPI.B  #0x1,(A1)                       | directory? (cdrDirRec)
        BNE.B   RC_EXIT                         | no ->
        MOVE.L  0x6(A1),D0                      | DirID (dirDirID)
        SUBA.L  A0,A0                           | no CName
        CLR.L   D2                              | no hint
        JSR     LocCRec(PC)                     | locate thread record
        BNE.B   RC_ERR_EXIT                     | error ->
        MOVE.L  D5,A0                           | source = new CName
        LEA.L   0xE(A1),A1                      | dest = thread CName (thdCName)
        JSR     UpdCName(PC)                    | update thread CName
        MOVE    0xA6(A2),D0                     | catalog refnum
        JSR     P_mBTUpdate(PC)                 | update thread record
| RCExit
RC_EXIT:
        CLR     D0                              | result = 'ok'
        MOVE.L  D7,D2                           | return hint in D2
        JSR     MarkVCBTime(PC)                 | mark the VCB dirty
        JSR     CMFlush(PC)                     | flush the catalog
RC_ERR_EXIT:
        ADDA    #0x8C,A6                        | de-allocate CM vars
        MOVEM.L (A6)+,D1/D3-D7/A0-A1/A3-A4      | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit CMRenameCN

| CMUpdateCN -- call helper.
| ----------------------------------------------------------
|
| CM Update CN
|
CMUpdateCN:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D2/A0-A1,-(A6)               | Save regs for CMUpdateCN
        BSR     P_CMSetUp                       | P_CMSetUp: get VCB, catalog BTCB
        MOVE    0xA6(A2),D0                     | D3 = parent DirID
        JSR     P_mBTUpdate(PC)                 | A3 = CName
        BEQ.B   UC_FLUSH                        | BuildKey: catalog key for lookup
        CMPI    #0x20,D0                        | BTSearch: find the record to update
        BNE.B   UC_EXIT                         | Not found?
        MOVEQ.L #0x30,D0                        | BTUpdate: write new data into existing record
        BRA.B   UC_EXIT                         | Set VCB dirty (catalog data changed)

| ----------------------------------------------------------
|
| UC_FLUSH
|
UC_FLUSH:
        JSR     MarkVCBTime(PC)                 | mark the VCB dirty
        JSR     CMFlush(PC)                     | flush the catalog
UC_EXIT:
        ADDA    #0x8C,A6                        | de-allocate CM vars
        MOVEM.L (A6)+,D1-D2/A0-A1               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit CMUpdateCN

| P_CMSetUp -- common set up routine.
| ----------------------------------------------------------
|
| P_CM Set Up
|
| Called by: CMCreateCN, CMDeleteCN, CMGetCN, CMGetOff, CMMoveCN (and 2 more)
P_CMSetUp:
        MOVE.L  (0x770).w,-(SP)                 | HFS vector: CMSetUp
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| CM Set Up - allocate CM vars on A6 stack
|
CMSetUp:
        SUBA    #0x8C,A6                        | allocate CM vars on A6 stack (lenCMVars)
        MOVE.L  A6,A4                           | A4 = ptr(CM vars)
        RTS                                     | exit CMSetUp

| ----------------------------------------------------------
|
| UPD_VCNTS - UpdVCnts: update VCB directory and file counts
|
UPD_VCNTS:
        CMPI.B  #0x1,D0                         | directory? (cdrDirRec)
        BNE.B   UPD_VCNTS_FILE                  | no ->
        ADD.L   D2,vcbDirCnt(A2)                | update directory count
        BRA.B   UPD_ROOT_CNTS                   | ->
UPD_VCNTS_FILE:
        ADD.L   D2,vcbFilCnt(A2)                | update file count
| UPD_ROOT_CNTS: update root counts if in root directory
UPD_ROOT_CNTS:
        CMPI.L  #0x2,D1                         | root directory? (FSRtDirID=2)
        BNE.B   UPD_VCNTS_DONE                  | no ->
        CMPI.B  #0x1,D0                         | directory?
        BNE.B   UPD_ROOT_FILES                  | no ->
        ADD     D2,vcbNmRtDirs(A2)              | update root dir count
        BRA.B   UPD_VCNTS_DONE                  | ->
UPD_ROOT_FILES:
        ADD     D2,vcbNmFls(A2)                 | update root file count
UPD_VCNTS_DONE:
        RTS                                     | return to File Manager dispatch loop

| BuildKey -- build the key record.
| ----------------------------------------------------------
|
| Build Key
|
| Called by: CMCreateCN, CC_BLD_THD, CC_CLR_THD_LOOP, DC_DELETE, CMRenameCN (and 1 more)
BuildKey:
        MOVEM.L D0/A0-A1,-(SP)                  | Save regs for BuildKey
        MOVE.B  #0x6,(A1)                       | A1 = key buffer (from BTCVarPtr)
        CLR.B   0x1(A1)                         | D0 = parent directory ID to pack into key
        MOVE.L  D0,0x2(A1)                      | Store 4-byte parentID at ckrParID (key offset 2-5)
        CLR.B   0x6(A1)                         | A3 = CName pointer
        MOVE.L  A0,D0                           | A3 = nil? (thread record key: empty name)
        BEQ.B   BLDKEY_DONE                     | Empty name: ckrKeyLen = 5 (1+4 = keyLen byte + parentID)
        MOVE.L  A1,-(SP)                        | Copy Pascal name string into key at ckrCName
        LEA.L   0x6(A1),A1                      | D0 = name length
        BSR     UpdCName                        | D0 += 5 (parentID + reserved byte)
        MOVE.B  (A1),D0                         | ckrKeyLen = 5 + name_length (padded to even)
        MOVE.L  (SP)+,A1                        | Pad to even length if needed
        ADD.B   D0,(A1)                         | Return (A0 = key, D0 = key size)
BLDKEY_DONE:
        MOVEM.L (SP)+,D0/A0-A1                  | Restore registers
        RTS                                     | Return

| CMFlush -- flush the catalog.
| ----------------------------------------------------------
|
| CM Flush
|
| Called by: CC_UPD_PAR, DC_UPD_PAR, MC_EXIT, RC_EXIT, UC_FLUSH
CMFlush:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/A1,-(A6)                     | save registers
        MOVE    0xA6(A2),D1                     | D1 = refnum of catalog file (VCBCTRef)
        MOVE    D1,D0                           | flush the catalog BTree
        JSR     P_mBTFlush(PC)                  | flush catalog B-tree to disk
        BNE.B   CMFLUSH_EXIT                    | error ->
        MOVE.L  (FCBSPtr).w,A1                  | FCB dirty? (FCBModBit)
        BTST    #0x7,0x4(A1,D1.W)               | test dirty bit in FCB flags
        BEQ.B   CMFLUSH_OK                      | no, all done ->
        JSR     MarkVCB(PC)                     | mark the VCB dirty
        JSR     FlushMDB(PC)                    | flush the MDB
        BNE.B   CMFLUSH_EXIT                    | error ->
CMFLUSH_OK:
        CLR     D0                              | result = 'ok'
CMFLUSH_EXIT:
        MOVEM.L (A6)+,D1/A1                     | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit CMFlush

| ----------------------------------------------------------
|
| CM Key Cmp
|
CMKeyCmp:
        MOVEM.L D1-D2/A0-A3,-(SP)               | save registers
        MOVE.L  A0,A2                           | A2 = ptr(search key)
        MOVE.L  A1,A3                           | A3 = ptr(trial key)
| compare DirID's first
        MOVE.L  0x2(A2),D0                      | compare parID's (ckrParID)
        CMP.L   PORTBITS(A3),D0                 | compare search ParID vs trial ParID
        BHI.B   KC_IS_GT                        | search ParID > trial ParID ->
        BCS     KC_IS_LT                        | search ParID < trial ParID ->
| ParID's are equal, compare the CNames
        LEA.L   vcbFlags(A2),A0                 | ptr(CName string) for search key (ckrCName)
        LEA.L   0x6(A3),A1                      | ptr(CName string) for trial key
        MOVEQ.L #0x0,D0                         | D0(high word) = length(search key)
        MOVE.B  (A0)+,D0                        | get search CName length
        SWAP    D0                              | D0(low word) = length(trial key)
        MOVE.B  (A1)+,D0                        | get trial CName length
        _CompareString                          | compare the CNames (RelString)
        BEQ.B   KC_IS_EQ                        | search CName = trial CName ->
        BGT.B   KC_IS_GT                        | search CName > trial CName ->
| KCIsLT
KC_IS_LT:
        MOVEQ.L #-0x1,D0                        | result = "less than"
        BRA.B   KC_EXIT                         | return less than
| KCIsEQ
KC_IS_EQ:
        MOVEQ.L #0x0,D0                         | result = "equal"
        BRA.B   KC_EXIT                         | return equal
| KCIsGT
KC_IS_GT:
        MOVEQ.L #0x1,D0                         | result = "greater than"
KC_EXIT:
        MOVEM.L (SP)+,D1-D2/A0-A3               | restore registers
        TST     D0                              | set up condition codes
        RTS                                     | exit CMKeyCmp

| LocCNode -- locate source CNode.
| ----------------------------------------------------------
|
| Loc C Node
|
| Called by: MC_UPD_DEST, CMRenameCN, CC_UPD_PAR, CMDeleteCN, DC_UPD_PAR (and 7 more)
LocCNode:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
| locate catalog record using given CNode specification
        JSR     LocCRec(PC)                     | locate the record
        BNE.B   LOCCNODE_EXIT                   | didn't find it ->
        CMPI.B  #0x3,(A1)                       | thread record? (cdrThdRec)
        BNE.B   LOCCNODE_EXIT                   | no, all done ->
| thread record found, locate corresponding directory record
        LEA.L   0xE(A1),A0                      | addr(directory CName) = thdCName
        MOVE.L  0xA(A1),D0                      | parent directory ID = thdParID
        JSR     LocCRec(PC)                     | locate directory record
LOCCNODE_EXIT:
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit LocCNode

| LocCRec -- locate thread record.
| ----------------------------------------------------------
|
| Loc C Rec
|
| Called by: LocCNode, CMCreateCN, GO_LOCATE_THD, MC_UPD_DEST, RC_UPD_THD
LocCRec:
        MOVE.L  (SP)+,-(A6)                     | Save return address
        LEA.L   (A4),A1                         | Load address
        JSR     BuildKey(PC)                    | call
        MOVE.L  A0,D0                           | test if CName ptr is null
        BNE.B   LOCCREC_SEARCH                  | no ->
        CLR.L   D2                              | no hint (null CName)
LOCCREC_SEARCH:
        LEA.L   (A4),A0                         | Load address
        MOVE    0xA6(A2),D0                     | catalog file refnum (VCBCTRef)
        JSR     P_mBTSearch(PC)                 | call
        BEQ.B   LOCCREC_EXIT                    | yes ->
        CMPI    #0x20,D0                        | Compare
        BNE.B   LOCCREC_EXIT                    | no ->
        MOVEQ.L #0x30,D0                        | result = CatNotFound (0x30)
        NOP                                     | Operation
LOCCREC_EXIT:
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | Return

| UpdCName -- move in the CName.
| ----------------------------------------------------------
|
| Upd C Name
|
UpdCName:
        MOVEM.L D0-D1/A0-A1,-(SP)               | Save registers
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  (A0)+,D0                        | D0 = source CName length
        MOVEQ.L #0x1F,D1                        | D1 = max CName length (31)
        CMP     D1,D0                           | Compare
        BLE.B   UPDCNAME_COPY                   | ->
        MOVE    D1,D0                           | clamp to max length
UPDCNAME_COPY:
        MOVE.B  D0,(A1)+                        | store length byte in dest
        _BlockMove                              | _BlockMove
        MOVEM.L (SP)+,D0-D1/A0-A1               | Restore registers
        RTS                                     | Return
