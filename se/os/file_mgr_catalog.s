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

CMSVCS:                                         | Apple source module (MacSEROM.lst)
CMCREATECN:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D3-D7/A0-A4,-(A6)               | save regs
    BSR.W       P_CMSetUp                       | common setup (allocate CM vars)
    CLR.L       0xAC(A2)                        | invalidate cached DirID (vcbDirIDM)
    MOVE.L      D1,D5                           | D5 = CNode type / file type
    MOVE.L      D0,D3                           | D3 = parent DirID
    MOVEA.L     A0,A3                           | A3 = CName pointer
    SUBA.L      A0,A0                           | no CName (thread record key)
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCREC(PC)                     | locate parent's thread record
    BNE.W       CC_EXIT                         | parent not found ->
    MOVE.L      D3,D0                           | parID for key
    MOVEA.L     A3,A0                           | CName pointer
    LEA.L       (A4),A1                         | A1 = key record buffer
    JSR         BUILDKEY(PC)                    | build the catalog key record
    LEA.L       0x26(A4),A1                     | A1 = data record buffer (cdrOff)
    MOVEA.L     A1,A0                           | clear destination
    MOVE.W      #0x32,D0                        | (lencdr/2)-1 = 50 words
CC_CLR_CDR_LOOP:
    CLR.W       (A0)+                           | zero catalog data record
    DBF.W       D0,CC_CLR_CDR_LOOP              | loop for all words
    MOVE.B      D5,(A1)                         | set record type (cdrType)
    MOVE.L      (Time).W,D2                     | D2 = current date/time
    CMPI.B      #0x1,D5                         | creating a directory? (cdrDirRec)
    BNE.B       CC_INIT_FILE                    | no, init file record ->
    MOVE.L      0x26(A2),D6                     | assign DirID (vcbNxtCNID)
    MOVE.L      D6,0x6(A1)                      | dirDirID = new CNID
    ADDQ.L      #0x1,0x26(A2)                   | bump next available CNode ID
    MOVE.L      D2,0xA(A1)                      | set creation date (dirCrDat)
    MOVE.L      D2,0xE(A1)                      | set modification date (dirMdDat)
    MOVEQ.L     #0x46,D1                        | D1 = dir record size (lendir=70)
    BRA.B       CC_ADD_REC                      | add new record ->
| ----------------------------------------------------------
|
| CC_INIT_FILE
|
CC_INIT_FILE:
    MOVE.L      D2,0x2C(A1)                     | set creation date (filCrDat)
    MOVE.L      D2,0x30(A1)                     | set modification date (filMdDat)
    MOVE.L      0x26(A2),0x14(A1)               | assign file number (filFlNum = vcbNxtCNID)
    ADDQ.L      #0x1,0x26(A2)                   | bump next available CNode ID
    SWAP.W      D5                              | get file type from high word
    MOVE.B      D5,0x3(A1)                      | filTyp = file type byte
    SWAP.W      D5                              | restore record type in low byte
    MOVEQ.L     #0x66,D1                        | D1 = file record size (lenfil=102)
CC_ADD_REC:
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    LEA.L       (A4),A0                         | A0 = key record buffer
    JSR         BTINSERT(PC)                    | insert new record into catalog B-tree
    BEQ.B       CC_BLD_THD                      | ok ->
    CMPI.W      #0x21,D0                        | CNode already exists? (BTexists)
    BNE.W       CC_EXIT                         | no, other error ->
    MOVEQ.L     #0x31,D0                        | result = CMexists
    BRA.W       CC_EXIT                         | exit ->
| ----------------------------------------------------------
|
| CC_BLD_THD
|
| CCBldThd: build thread record for new directory CNode
CC_BLD_THD:
    MOVE.L      D2,D7                           | D7 = hint from BTInsert
    CMPI.B      #0x1,D5                         | creating a directory?
    BNE.B       CC_UPD_PAR                      | no, skip thread record ->
    MOVE.L      D6,D0                           | parID = new directory's DirID
    SUBA.L      A0,A0                           | no CName (thread key)
    LEA.L       (A4),A1                         | A1 = key record buffer
    JSR         BUILDKEY(PC)                    | build thread key record
    LEA.L       0x26(A4),A1                     | A1 = thread data buffer
    MOVE.W      #0x16,D0                        | (lenthd/2)-1 = 22 words
CC_CLR_THD_LOOP:
    CLR.W       (A1)+                           | zero thread record
    DBF.W       D0,CC_CLR_THD_LOOP              | loop for all words
    LEA.L       0x26(A4),A1                     | A1 = thread record
    MOVE.B      #0x3,(A1)                       | set record type (cdrThdRec=3)
    MOVE.L      D3,0xA(A1)                      | set parent ID (thdParID)
    MOVEA.L     A3,A0                           | source = input CName
    LEA.L       0xE(A1),A1                      | dest = thread CName (thdCName)
    JSR         UPDCNAME(PC)                    | copy the CName into thread
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    MOVE.W      #0x2E,D1                        | thread record size (lenthd=46)
    LEA.L       (A4),A0                         | A0 = key record
    LEA.L       0x26(A4),A1                     | A1 = thread record
    JSR         BTINSERT(PC)                    | insert thread record
    BEQ.B       CC_UPD_PAR                      | ok ->
    MOVE.L      D0,-(A6)                        | save error code
    MOVE.L      D3,D0                           | parID of directory record
    MOVEA.L     A3,A0                           | CName pointer
    LEA.L       (A4),A1                         | key record buffer
    JSR         BUILDKEY(PC)                    | rebuild dir key (to undo thread)
    MOVEA.L     A1,A0                           | A0 = key for delete
    MOVE.W      0xA6(A2),D0                     | catalog file refnum
    JSR         BTDELETE(PC)                    | delete the directory record
    MOVE.L      (A6)+,D0                        | restore original error code
    CMPI.W      #0x21,D0                        | thread already existed? (BTexists)
    BNE.B       CC_EXIT                         | no, other error ->
    MOVEQ.L     #0x31,D0                        | result = CMexists
    BRA.B       CC_EXIT                         | exit ->
| CCUpdPar: update parent directory
CC_UPD_PAR:
    MOVE.L      D3,D0                           | parent DirID
    SUBA.L      A0,A0                           | no CName
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate parent directory record
    BNE.B       CC_EXIT                         | error ->
    ADDQ.W      #0x1,0x4(A1)                    | bump valence (dirVal)
    MOVE.L      (Time).W,0xE(A1)                | set modification date (dirMdDat)
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    JSR         BTUPDATE(PC)                    | update parent B-tree record
    BNE.B       CC_EXIT                         | error ->
    MOVE.B      D5,D0                           | CNode type
    MOVE.L      D3,D1                           | parent DirID
    MOVEQ.L     #0x1,D2                         | increment value (+1)
    BSR.W       UPD_VCNTS                       | update VCB dir/file counts
    CLR.W       D0                              | result = noErr
    MOVE.L      D6,D1                           | return DirID in D1
    MOVE.L      D7,D2                           | return hint in D2
    JSR         MARKVCBTIME(PC)                 | mark VCB dirty
    JSR         CMFLUSH(PC)                     | flush the catalog B-tree
| Called by: CC_ADD_REC, CC_CLR_THD_LOOP, CC_UPD_PAR, CMCREATECN
CC_EXIT:
    ADDA.W      #0x8C,A6                        | deallocate CM vars (lenCMVars)
    MOVEM.L     (A6)+,D3-D7/A0-A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from CMCreateCN
CMDELETECN:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D6/A0-A1/A3-A4,-(A6)         | save regs
    BSR.W       P_CMSetUp                       | common setup (allocate CM vars)
    CLR.L       0xAC(A2)                        | invalidate cached DirID (vcbDirIDM)
    MOVE.L      D0,D3                           | D3 = parent DirID
    MOVEA.L     A0,A3                           | A3 = CName pointer
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate the CNode to delete
    BNE.W       DC_EXIT                         | not found ->
    MOVE.B      (A1),D4                         | D4 = record type (cdrType)
    MOVE.L      0x2(A0),D6                      | D6 = parent DirID (ckrParID)
    CMPI.B      #0x1,D4                         | directory record? (cdrDirRec)
    BNE.B       CMDELETECN_DODELETE             | no, must be a file ->
    MOVE.L      0x6(A1),D5                      | D5 = DirID (dirDirID)
    CMPI.L      #0x2,D5                         | root directory? (FSRtDirID=2)
    BNE.B       DC_CHK_EMPTY                    | no ->
    MOVEQ.L     #0x33,D0                        | result = CMRootCN (can't delete root)
    BRA.B       DC_EXIT                         | exit ->
DC_CHK_EMPTY:
    TST.W       0x4(A1)                         | directory empty? (dirVal)
    BEQ.B       CMDELETECN_DODELETE             | yes, ok to delete ->
    MOVEQ.L     #0x32,D0                        | result = CMnotempty
    BRA.B       DC_EXIT                         | exit ->
| DCDelete: delete catalog records for CNode
CMDELETECN_DODELETE:
    LEA.L       (A4),A0                         | A0 = key record
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    JSR         BTDELETE(PC)                    | delete directory/file record
    BNE.B       DC_EXIT                         | error ->
| DCDelThd: delete thread record (directories only)
    CMPI.B      #0x1,D4                         | directory being deleted?
    BNE.B       DC_UPD_PAR                      | no, skip thread ->
    SUBA.L      A0,A0                           | no CName (thread key)
    MOVE.L      D5,D0                           | parID = directory's DirID
    LEA.L       (A4),A1                         | key record buffer
    JSR         BUILDKEY(PC)                    | build thread key record
    LEA.L       (A4),A0                         | A0 = key record
    MOVE.W      0xA6(A2),D0                     | catalog file refnum
    JSR         BTDELETE(PC)                    | delete thread record
    BNE.B       DC_EXIT                         | error ->
| DCUpdPar: update parent directory
DC_UPD_PAR:
    MOVE.L      D6,D0                           | parent DirID
    SUBA.L      A0,A0                           | no CName
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate parent directory record
    BNE.B       DC_EXIT                         | error ->
    SUBQ.W      #0x1,0x4(A1)                    | decrement valence (dirVal)
    MOVE.L      (Time).W,0xE(A1)                | set modification date (dirMdDat)
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    JSR         BTUPDATE(PC)                    | update parent B-tree record
    BNE.B       DC_EXIT                         | error ->
    MOVE.B      D4,D0                           | CNode type
    MOVE.L      D6,D1                           | parent DirID
    MOVEQ.L     #-0x1,D2                        | decrement value (-1)
    BSR.W       UPD_VCNTS                       | update VCB dir/file counts
    CLR.W       D0                              | result = noErr
    JSR         MARKVCBTIME(PC)                 | mark VCB dirty
    JSR         CMFLUSH(PC)                     | flush the catalog B-tree
| Called by: CMDELETECN, CMDELETECN_DODELETE, DC_UPD_PAR, DC_CHK_EMPTY
DC_EXIT:
    ADDA.W      #0x8C,A6                        | deallocate CM vars (lenCMVars)
    MOVEM.L     (A6)+,D1-D6/A0-A1/A3-A4         | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from CMDeleteCN
| Called by: FNDFILNAME_CONT_3, MOUNTVOL_OK_3, MTCHECK, MOUNTVOL_FOUND_3, GETVOLINFO_CONT_6 (and 4 more)
CMGETCN:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/D3/A3-A4,-(A6)               | save regs
    BSR.W       P_CMSetUp                       | common setup (allocate CM vars)
    CLR.L       0xAC(A2)                        | invalidate cached DirID (vcbDirIDM)
    JSR         LOCCNODE(PC)                    | locate directory/file B-tree record
    ADDA.W      #0x8C,A6                        | deallocate CM vars
    MOVEM.L     (A6)+,D1/D3/A3-A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from CMGetCN
CMGETOFF:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/D3-D4/A4,-(A6)               | save regs
    BSR.W       P_CMSetUp                       | common setup (allocate CM vars)
    MOVE.L      D0,D3                           | D3 = DirID
    MOVE.W      D1,D4                           | D4 = offspring index
    MOVE.L      0xAC(A2),D1                     | cached DirID (vcbDirIDM)
    BEQ.B       GO_LOCATE_THD                   | no cache, locate thread ->
    CMP.L       D3,D1                           | same directory as cached?
    BEQ.B       GO_GET_OFF                      | yes, use cached position ->
| GOLocateThd: locate thread record to establish position
GO_LOCATE_THD:
    CLR.L       0xAC(A2)                        | invalidate cached DirID (vcbDirIDM)
    MOVE.L      D3,D0                           | DirID
    SUBA.L      A0,A0                           | no CName
    JSR         LOCCREC(PC)                     | locate the thread record
    BNE.B       GO_EXIT                         | not found ->
    MOVE.L      D3,0xAC(A2)                     | cache this DirID (vcbDirIDM)
    CLR.W       0xB0(A2)                        | clear offspring index marker (vcbOffsM)
| GOGetOff: get offspring record by relative index
GO_GET_OFF:
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    MOVE.W      D4,D1                           | D1 = desired offspring index
    SUB.W       0xB0(A2),D1                     | subtract cached index marker
    JSR         BTGETRECORD(PC)                 | get record by relative offset
    BEQ.B       GO_CHK_PARENT                   | ok ->
    CMPI.W      #0x20,D0                        | not found? (BTnotfound)
    BNE.B       GO_INVAL_EXIT                   | no, other error ->
GO_NOT_FOUND:
    MOVEQ.L     #0x30,D0                        | result = CMnotfound
GO_INVAL_EXIT:
    CLR.L       0xAC(A2)                        | invalidate cached DirID
    BRA.B       GO_EXIT                         | exit ->
GO_CHK_PARENT:
    CMP.L       0x2(A0),D3                      | same parent? (ckrParID)
    BNE.B       GO_NOT_FOUND                    | no, past end of children ->
    MOVE.W      D4,0xB0(A2)                     | cache offspring index (vcbOffsM)
| GOExit
GO_EXIT:
    ADDA.W      #0x8C,A6                        | deallocate CM vars
    MOVEM.L     (A6)+,D1/D3-D4/A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from CMGetOff
CMMOVECN:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/D3-D7/A0-A1/A3-A4,-(A6)      | save regs
    BSR.W       P_CMSetUp                       | common setup (allocate CM vars)
    CLR.L       0xAC(A2)                        | invalidate cached DirID (vcbDirIDM)
    MOVE.L      D1,D5                           | D5 = dest DirID/ParID
    MOVE.L      A1,D6                           | D6 = dest CName pointer
    MOVE.L      D0,D3                           | D3 = source DirID/ParID
    MOVEA.L     A0,A3                           | A3 = source CName pointer
| MCChkSrc: make sure source CNode exists
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate source CNode
    BNE.W       CM_EPILOGUE                     | source not found ->
    MOVEQ.L     #0x0,D4                         | assume source is not a directory
    CMPI.B      #0x1,(A1)                       | directory record? (cdrDirRec)
    BNE.B       MC_CHK_DEST                     | no ->
    MOVE.L      0x6(A1),D4                      | D4 = source DirID (dirDirID)
| MCChkDest: make sure destination exists and is a directory
MC_CHK_DEST:
    MOVE.L      D5,D0                           | dest DirID/ParID
    MOVEA.L     D6,A0                           | dest CName pointer
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate destination CNode
    BNE.W       CM_EPILOGUE                     | dest not found ->
    CMPI.B      #0x1,(A1)                       | directory record? (cdrDirRec)
    BEQ.B       MC_CHK_DST_DIR                  | yes ->
    MOVE.W      #0xFF86,D0                      | result = BadMovErr (-122)
    BRA.W       CM_EPILOGUE                     | exit ->
| MCChkDst: check for invalid move operation
MC_CHK_DST_DIR:
    MOVE.L      0x6(A1),D7                      | D7 = dest DirID (dirDirID)
    TST.L       D4                              | source is a directory?
    BEQ.B       MC_LOC_SRC                      | no, skip ancestry check ->
    CMPI.L      #0x2,D4                         | root directory? (FSRtDirID)
    BEQ.B       MC_BAD_MOVE                     | can't move root ->
    CMP.L       D4,D7                           | moving to self?
    BEQ.B       MC_BAD_MOVE                     | invalid ->
| MCChkAncestor: prevent moving directory into its own descendant
MC_CHK_ANCESTOR:
    MOVE.L      0x2(A0),D0                      | parent DirID from key record
    CMP.L       D4,D0                           | is source an ancestor of dest?
    BEQ.B       MC_BAD_MOVE                     | yes, circular ->
    CMPI.L      #0x2,D0                         | reached root?
    BLE.B       MC_LOC_SRC                      | yes, ancestry check passed ->
    SUBA.L      A0,A0                           | no CName
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | trace ancestry upward
    BNE.W       CM_EPILOGUE                     | error ->
    BRA.B       MC_CHK_ANCESTOR                 | continue tracing ->
MC_BAD_MOVE:
    MOVE.W      #0xFF86,D0                      | result = BadMovErr (-122)
    BRA.W       CM_EPILOGUE                     | exit ->
| MCLocSrc: re-locate source CNode for the actual move
MC_LOC_SRC:
    MOVE.L      D3,D0                           | source ParID
    MOVEA.L     A3,A0                           | source CName
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate source CNode
    BNE.W       CM_EPILOGUE                     | error ->
    CMP.L       0x2(A0),D7                      | same parent (null move)?
    BNE.B       MC_COPY_SRC                     | no, real move ->
    MOVE.L      D2,D7                           | save hint for null move
    BRA.W       CMMOVECN_EXIT                   | done (null move) ->
| MCCopySrc: save source record data into CM vars
MC_COPY_SRC:
    MOVE.L      A1,-(A7)                        | save ptr to data record
    LEA.L       (A4),A1                         | dest = CM vars key buffer
    MOVEQ.L     #0x1,D0                         | key length + 1
    ADD.B       (A0),D0                         | = key size
    _BlockMove                                  | copy the key record
    MOVEA.L     (A7)+,A0                        | source = data record
    LEA.L       0x26(A4),A1                     | dest = CM vars data buffer
    MOVE.W      D1,D0                           | data record size
    EXT.L       D0                              | sign-extend for BlockMove
    _BlockMove                                  | copy the data record
| MCBldDst: build destination key and insert
    LEA.L       (A4),A0                         | A0 = key record
    MOVE.L      0x2(A0),D4                      | D4 = source ParID (save for later)
    MOVE.L      D7,0x2(A0)                      | set new ParID = dest DirID
    LEA.L       0x26(A4),A1                     | A1 = data record
    MOVEQ.L     #0x66,D1                        | assume file record size (lenfil)
    CMPI.B      #0x2,(A1)                       | file record? (cdrFilRec=2)
    BEQ.B       MC_INSERT_DST                   | yes ->
    MOVEQ.L     #0x46,D1                        | directory record size (lendir)
    MOVE.L      (Time).W,0xE(A1)                | set modification date (dirMdDat)
| MCInsertDst: insert at destination
MC_INSERT_DST:
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    JSR         BTINSERT(PC)                    | insert at destination
    BEQ.B       MC_UPD_DEST                     | ok ->
    CMPI.W      #0x21,D0                        | already exists? (BTexists)
    BNE.W       CM_EPILOGUE                     | no, other error ->
    MOVEQ.L     #0x31,D0                        | result = CMexists
    BNE.W       CM_EPILOGUE                     | exit ->
| MCUpdDest: update destination parent directory
MC_UPD_DEST:
    MOVE.L      D2,D7                           | D7 = new hint
    MOVE.L      0x2(A0),D0                      | dest ParID from inserted key
    EXG         D5,D0                           | swap: D5=dest ParID, D0=dest DirID
    MOVEA.L     D6,A0                           | dest CName pointer
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate dest parent directory
    BNE.W       CM_EPILOGUE                     | error ->
    ADDQ.W      #0x1,0x4(A1)                    | bump valence (dirVal)
    MOVE.L      (Time).W,0xE(A1)                | set modification date (dirMdDat)
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    JSR         BTUPDATE(PC)                    | update dest parent B-tree record
    BNE.W       CM_EPILOGUE                     | error ->
| update VCB counts for destination
    LEA.L       0x26(A4),A1                     | ptr to saved data record
    MOVE.B      (A1),D0                         | CNode type
    MOVE.L      D5,D1                           | dest ParID
    MOVEQ.L     #0x1,D2                         | increment (+1)
    BSR.W       UPD_ROOT_CNTS                   | update VCB counts
| MCDelSrc: delete source record
    MOVE.L      D3,D0                           | source ParID
    MOVEA.L     A3,A0                           | source CName
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate source CNode
    BNE.B       CM_EPILOGUE                     | error ->
    LEA.L       (A4),A0                         | A0 = key record
    MOVE.W      0xA6(A2),D0                     | catalog file refnum
    JSR         BTDELETE(PC)                    | delete source record
    BNE.B       CM_EPILOGUE                     | error ->
| MCUpdThd: update thread record if directory
    LEA.L       0x26(A4),A1                     | ptr to saved data record
    CMPI.B      #0x1,(A1)                       | directory? (cdrDirRec)
    BNE.B       MC_UPD_SRC                      | no, skip thread update ->
    MOVE.L      0x6(A1),D0                      | DirID (dirDirID)
    SUBA.L      A0,A0                           | no CName
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCREC(PC)                     | locate thread record
    BNE.B       CM_EPILOGUE                     | error ->
    MOVE.L      D5,0xA(A1)                      | update thdParID = new parent
    MOVE.W      0xA6(A2),D0                     | catalog file refnum
    JSR         BTUPDATE(PC)                    | update thread record
    BNE.B       CM_EPILOGUE                     | error ->
| MCUpdSrc: update source parent directory
MC_UPD_SRC:
    MOVE.L      D4,D0                           | source ParID
    SUBA.L      A0,A0                           | no CName
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate source parent
    BNE.B       CM_EPILOGUE                     | error ->
    SUBQ.W      #0x1,0x4(A1)                    | decrement valence (dirVal)
    MOVE.L      (Time).W,0xE(A1)                | set modification date (dirMdDat)
    MOVE.W      0xA6(A2),D0                     | catalog file refnum
    JSR         BTUPDATE(PC)                    | update source parent B-tree record
    BNE.B       CM_EPILOGUE                     | error ->
| update VCB counts for source
    LEA.L       0x26(A4),A1                     | ptr to saved data record
    MOVE.B      (A1),D0                         | CNode type
    MOVE.L      D4,D1                           | source ParID
    MOVEQ.L     #-0x1,D2                        | decrement (-1)
    BSR.W       UPD_ROOT_CNTS                   | update VCB counts
| MCExit
CMMOVECN_EXIT:
    CLR.W       D0                              | result = noErr
    MOVE.L      D7,D2                           | return hint in D2
    JSR         MARKVCBTIME(PC)                 | mark VCB dirty
    JSR         CMFLUSH(PC)                     | flush the catalog B-tree
| Called by: MC_UPD_DEST, MC_CHK_DEST, MC_INSERT_DST, MC_UPD_SRC, CMMOVECN (and 3 more)
CM_EPILOGUE:
    ADDA.W      #0x8C,A6                        | deallocate CM vars (lenCMVars)
    MOVEM.L     (A6)+,D1/D3-D7/A0-A1/A3-A4      | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from CMMoveCN
CMRENAMECN:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/D3-D7/A0-A1/A3-A4,-(A6)      | save regs
    BSR.W       P_CMSetUp                       | common setup (allocate CM vars)
    CLR.L       0xAC(A2)                        | invalidate cached DirID (vcbDirIDM)
    MOVE.L      D0,D3                           | D3 = ParID
    MOVEA.L     A0,A3                           | A3 = old CName pointer
    MOVE.L      A1,D5                           | D5 = new CName pointer
| locate source CNode
    JSR         LOCCNODE(PC)                    | locate the CNode to rename
    BNE.W       CMRENAMECN_EPILOGUE             | not found ->
    MOVE.L      D2,D4                           | D4 = catalog hint
    MOVE.W      D1,D6                           | D6 = data record size
| save catalog data record
    MOVEA.L     A1,A0                           | source = data record
    LEA.L       0x26(A4),A1                     | dest = CM vars data buffer
    MOVE.W      D6,D0                           | data record size
    EXT.L       D0                              | sign-extend for BlockMove
    _BlockMove                                  | copy data record
| build new key and insert renamed record
    LEA.L       (A4),A1                         | A1 = key record buffer
    MOVE.L      0x2(A1),D0                      | ParID from old key (ckrParID)
    MOVEA.L     D5,A0                           | new CName pointer
    JSR         BUILDKEY(PC)                    | build key with new name
    MOVEA.L     A1,A0                           | A0 = new key
    LEA.L       0x26(A4),A1                     | A1 = data record
    MOVE.W      D6,D1                           | data record size
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    JSR         BTINSERT(PC)                    | insert renamed record
    BEQ.B       RC_DEL_OLD                      | ok ->
    CMPI.W      #0x21,D0                        | already exists? (BTexists)
    BNE.W       CMRENAMECN_EPILOGUE             | no, other error ->
| "already exists": check if it's really a case-only rename
    LEA.L       (A4),A1                         | A1 = key record buffer
    MOVE.L      0x2(A1),D0                      | ParID from key
    MOVEA.L     D5,A0                           | new CName pointer
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCNODE(PC)                    | locate existing CNode with new name
    BNE.W       CMRENAMECN_EPILOGUE             | error ->
    MOVE.L      D2,D7                           | D7 = hint
    MOVE.L      A0,D6                           | D6 = ptr to key record
    LEA.L       0x26(A4),A0                     | ptr to saved data record
    MOVE.B      (A0),D0                         | saved record type
    CMP.B       (A1),D0                         | same type as found record?
    BNE.B       RC_EXISTS_ERR                   | no, different CNode ->
    CMPI.B      #0x1,D0                         | directory? (cdrDirRec)
    BNE.B       RC_CHK_FILNUM                   | no, check file ->
    MOVE.L      0x6(A1),D1                      | found DirID (dirDirID)
    CMP.L       0x6(A0),D1                      | same DirID as saved?
    BEQ.B       RC_CASE_RENAME                  | yes, case-only rename ->
    BRA.B       RC_EXISTS_ERR                   | different CNode ->
RC_CHK_FILNUM:
    MOVE.L      0x14(A1),D1                     | found file number (filFlNum)
    CMP.L       0x14(A0),D1                     | same file number as saved?
    BEQ.B       RC_CASE_RENAME                  | yes, case-only rename ->
RC_EXISTS_ERR:
    MOVEQ.L     #0x31,D0                        | result = CMexists
    BRA.B       CMRENAMECN_EPILOGUE             | exit ->
| RCCaseRename: case-only rename, update name in place
RC_CASE_RENAME:
    MOVEA.L     D6,A1                           | ptr to key record of found CNode
    LEA.L       0x6(A1),A1                      | ptr to CName in key (ckrCName)
    MOVEA.L     D5,A0                           | source = new CName
    JSR         UPDCNAME(PC)                    | update the CName in place
    MOVE.W      0xA6(A2),D0                     | catalog file refnum
    JSR         BTUPDATE(PC)                    | update B-tree record
    BRA.B       RC_UPD_THD                      | skip to thread update ->
| RCDelOld: normal rename - delete old record
RC_DEL_OLD:
    MOVE.L      D2,D7                           | D7 = new hint
    MOVE.L      D3,D0                           | old ParID
    MOVEA.L     A3,A0                           | old CName
    MOVE.L      D4,D2                           | old hint
    JSR         LOCCNODE(PC)                    | locate old CNode
    BNE.B       CMRENAMECN_EPILOGUE             | error ->
    LEA.L       (A4),A0                         | A0 = key record
    MOVE.W      0xA6(A2),D0                     | catalog file refnum
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         BTDELETE(PC)                    | delete old record
    BNE.B       CMRENAMECN_EPILOGUE             | error ->
| RCUpdThd: update thread record with new name
RC_UPD_THD:
    LEA.L       0x26(A4),A1                     | ptr to saved data record
    CMPI.B      #0x1,(A1)                       | directory? (cdrDirRec)
    BNE.B       CMRENAMECN_EXIT                 | no, skip thread update ->
    MOVE.L      0x6(A1),D0                      | DirID (dirDirID)
    SUBA.L      A0,A0                           | no CName
    MOVEQ.L     #0x0,D2                         | no hint
    JSR         LOCCREC(PC)                     | locate thread record
    BNE.B       CMRENAMECN_EPILOGUE             | error ->
    MOVEA.L     D5,A0                           | source = new CName
    LEA.L       0xE(A1),A1                      | dest = thread CName (thdCName)
    JSR         UPDCNAME(PC)                    | update thread CName
    MOVE.W      0xA6(A2),D0                     | catalog file refnum
    JSR         BTUPDATE(PC)                    | update thread record
| RCExit
CMRENAMECN_EXIT:
    CLR.W       D0                              | result = noErr
    MOVE.L      D7,D2                           | return hint in D2
    JSR         MARKVCBTIME(PC)                 | mark VCB dirty
    JSR         CMFLUSH(PC)                     | flush the catalog B-tree
| Called by: CMRENAMECN, RC_DEL_OLD, RC_EXISTS_ERR, RC_UPD_THD
CMRENAMECN_EPILOGUE:
    ADDA.W      #0x8C,A6                        | deallocate CM vars (lenCMVars)
    MOVEM.L     (A6)+,D1/D3-D7/A0-A1/A3-A4      | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from CMRenameCN
CMUPDATECN:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D2/A0-A1,-(A6)               | save regs
    BSR.B       P_CMSetUp                       | common setup (allocate CM vars)
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    JSR         BTUPDATE(PC)                    | write updated data into B-tree record
    BEQ.B       UC_FLUSH                        | ok ->
    CMPI.W      #0x20,D0                        | not found? (BTnotfound)
    BNE.B       UC_EXIT                         | no, other error ->
    MOVEQ.L     #0x30,D0                        | result = CMnotfound
    BRA.B       UC_EXIT                         | exit ->
UC_FLUSH:
    JSR         MARKVCBTIME(PC)                 | mark VCB dirty
    JSR         CMFLUSH(PC)                     | flush the catalog B-tree
UC_EXIT:
    ADDA.W      #0x8C,A6                        | deallocate CM vars
    MOVEM.L     (A6)+,D1-D2/A0-A1               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from CMUpdateCN
| P_CMSetUp -- common set up routine.
| ----------------------------------------------------------
|
| P_CM Set Up
|
| Called by: CMCREATECN, CMDELETECN, CMGETCN, CMGETOFF, CMMOVECN (and 2 more)
P_CMSetUp:
    MOVE.L      (0x770).W,-(A7)                 | HFS vector: CMSetUp trampoline
    RTS                                         | dispatch via vector
VCMSETUP:
    SUBA.W      #0x8C,A6                        | allocate CM vars on A6 stack (lenCMVars)
    MOVEA.L     A6,A4                           | A4 = ptr to CM vars
    RTS                                         | return from CMSetUp
| ----------------------------------------------------------
|
| UPD_VCNTS - UpdVCnts: update VCB directory and file counts
|
UPD_VCNTS:
    CMPI.B      #0x1,D0                         | directory? (cdrDirRec)
    BNE.B       UPD_VCNTS_FILE                  | no ->
    ADD.L       D2,0x76(A2)                     | update directory count (vcbDirCnt)
    BRA.B       UPD_ROOT_CNTS                   | check root counts ->
UPD_VCNTS_FILE:
    ADD.L       D2,0x72(A2)                     | update file count (vcbFilCnt)
| UPD_ROOT_CNTS: update root counts if in root directory
UPD_ROOT_CNTS:
    CMPI.L      #0x2,D1                         | root directory? (FSRtDirID=2)
    BNE.B       UPD_VCNTS_DONE                  | no ->
    CMPI.B      #0x1,D0                         | directory?
    BNE.B       UPD_ROOT_FILES                  | no ->
    ADD.W       D2,0x70(A2)                     | update root dir count (vcbNmRtDirs)
    BRA.B       UPD_VCNTS_DONE                  | ->
UPD_ROOT_FILES:
    ADD.W       D2,0x14(A2)                     | update root file count (vcbNmFls)
UPD_VCNTS_DONE:
    RTS                                         | return from UpdVCnts
| BuildKey: build a catalog key record
| Called by: CMCREATECN, CC_BLD_THD, CC_CLR_THD_LOOP, CMDELETECN_DODELETE, CMRENAMECN (and 1 more)
CMMAINT:                                        | Apple source module (MacSEROM.lst)
BUILDKEY:
    MOVEM.L     D0/A0-A1,-(A7)                  | save regs
    MOVE.B      #0x6,(A1)                       | ckrKeyLen = 6 (minimum: len+rsrvd+parID)
    CLR.B       0x1(A1)                         | ckrResrv = 0 (reserved byte)
    MOVE.L      D0,0x2(A1)                      | ckrParID = parent directory ID
    CLR.B       0x6(A1)                         | ckrCName length = 0 initially
    MOVE.L      A0,D0                           | CName pointer null?
    BEQ.B       BLDKEY_DONE                     | yes, thread key (no name) ->
    MOVE.L      A1,-(A7)                        | save key buffer ptr
    LEA.L       0x6(A1),A1                      | dest = ckrCName position
    BSR.W       UPDCNAME                        | copy name into key
    MOVE.B      (A1),D0                         | D0 = name length
    MOVEA.L     (A7)+,A1                        | restore key buffer ptr
    ADD.B       D0,(A1)                         | ckrKeyLen += name length
BLDKEY_DONE:
    MOVEM.L     (A7)+,D0/A0-A1                  | restore regs
    RTS                                         | return from BuildKey
| Called by: CC_UPD_PAR, DC_UPD_PAR, CMMOVECN_EXIT, CMRENAMECN_EXIT, UC_FLUSH
CMFLUSH:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/A1,-(A6)                     | save regs
    MOVE.W      0xA6(A2),D1                     | D1 = catalog file refnum (vcbCTRef)
    MOVE.W      D1,D0                           | D0 = refnum for BTFlush
    JSR         BTFLUSH(PC)                     | flush catalog B-tree to disk
    BNE.B       CMFLUSH_EXIT                    | error ->
    MOVEA.L     (FCBSPtr).W,A1                  | A1 = FCB array base
    BTST        #0x7,0x4(A1,D1.W)               | catalog FCB dirty? (FCBModBit)
    BEQ.B       CMFLUSH_OK                      | no ->
    JSR         MARKVCB(PC)                     | mark VCB dirty
    JSR         FLUSHMDB(PC)                    | flush the MDB to disk
    BNE.B       CMFLUSH_EXIT                    | error ->
CMFLUSH_OK:
    CLR.W       D0                              | result = noErr
CMFLUSH_EXIT:
    MOVEM.L     (A6)+,D1/A1                     | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from CMFlush
CMKEYCMP:
    MOVEM.L     D1-D2/A0-A3,-(A7)               | save regs
    MOVEA.L     A0,A2                           | A2 = ptr to search key
    MOVEA.L     A1,A3                           | A3 = ptr to trial key
| compare ParIDs first
    MOVE.L      0x2(A2),D0                      | search ParID (ckrParID)
    CMP.L       0x2(A3),D0                      | compare vs trial ParID
    BHI.B       KC_IS_GT                        | search > trial ->
    BCS.B       KC_IS_LT                        | search < trial ->
| ParIDs equal, compare CNames
    LEA.L       0x6(A2),A0                      | ptr to search CName (ckrCName)
    LEA.L       0x6(A3),A1                      | ptr to trial CName
    MOVEQ.L     #0x0,D0                         | clear for length bytes
    MOVE.B      (A0)+,D0                        | D0 high = search CName length
    SWAP.W      D0                              | swap lengths
    MOVE.B      (A1)+,D0                        | D0 low = trial CName length
    _CompareString                              | compare CNames (RelString)
    BEQ.B       KC_IS_EQ                        | equal ->
    BGT.B       KC_IS_GT                        | search > trial ->
| KCIsLT
KC_IS_LT:
    MOVEQ.L     #-0x1,D0                        | result = "less than"
    BRA.B       KC_EXIT                         | ->
| KCIsEQ
KC_IS_EQ:
    MOVEQ.L     #0x0,D0                         | result = "equal"
    BRA.B       KC_EXIT                         | ->
| KCIsGT
KC_IS_GT:
    MOVEQ.L     #0x1,D0                         | result = "greater than"
KC_EXIT:
    MOVEM.L     (A7)+,D1-D2/A0-A3               | restore regs
    TST.W       D0                              | set condition codes
    RTS                                         | return from CMKeyCmp
| Called by: MC_UPD_DEST, CMRENAMECN, CC_UPD_PAR, CMDELETECN, DC_UPD_PAR (and 7 more)
LOCCNODE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    JSR         LOCCREC(PC)                     | locate catalog record
    BNE.B       LOCCNODE_RETURN                 | not found ->
    CMPI.B      #0x3,(A1)                       | thread record? (cdrThdRec)
    BNE.B       LOCCNODE_RETURN                 | no, found actual record ->
| thread found: follow it to the directory record
    LEA.L       0xE(A1),A0                      | A0 = directory CName (thdCName)
    MOVE.L      0xA(A1),D0                      | D0 = parent DirID (thdParID)
    BSR.W       LOCCREC                         | locate directory record
LOCCNODE_RETURN:
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from LocCNode
| Called by: LOCCNODE, CMCREATECN, GO_LOCATE_THD, MC_UPD_DEST, RC_UPD_THD
LOCCREC:
    MOVE.L      (0x7C8).W,-(A7)                 | HFS vector: LocCRec trampoline
    RTS                                         | dispatch via vector
VLOCCREC:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    LEA.L       (A4),A1                         | A1 = key record buffer
    JSR         BUILDKEY(PC)                    | build catalog key from D0/A0
    MOVE.L      A0,D0                           | CName pointer null?
    BNE.B       VLOCCREC_SEARCH                 | no, use caller's hint ->
    MOVEQ.L     #0x0,D2                         | null CName: no hint
VLOCCREC_SEARCH:
    LEA.L       (A4),A0                         | A0 = key record
    MOVE.W      0xA6(A2),D0                     | catalog file refnum (vcbCTRef)
    JSR         BTSEARCH(PC)                    | search catalog B-tree
    BEQ.B       LOCCREC_EXIT                    | found ->
    CMPI.W      #0x20,D0                        | BTnotfound?
    BNE.B       LOCCREC_EXIT                    | no, other error ->
    MOVEQ.L     #0x30,D0                        | result = CMnotfound
LOCCREC_EXIT:
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from LocCRec
UPDCNAME:
    MOVEM.L     D0-D1/A0-A1,-(A7)               | save regs
    MOVEQ.L     #0x0,D0                         | clear high bytes
    MOVE.B      (A0)+,D0                        | D0 = source CName length
    MOVEQ.L     #0x1F,D1                        | D1 = max CName length (31)
    CMP.W       D1,D0                           | exceeds max?
    BLE.B       UPDCNAME_COPY                   | no ->
    MOVE.W      D1,D0                           | clamp to max length
UPDCNAME_COPY:
    MOVE.B      D0,(A1)+                        | store length byte in dest
    _BlockMove                                  | copy name bytes
    MOVEM.L     (A7)+,D0-D1/A0-A1               | restore regs
    RTS                                         | return from UpdCName
