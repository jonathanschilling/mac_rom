| File Manager -- calls by file name (directory level)
|
| The 64K ROM's flat-file (MFS) File Manager: OpenRF and FileOpen (_Open
| on a file arrives here through the Device Manager), Create, Delete,
| Rename, SetFilType, SetFilLock, RstFilLock, SetFileInfo, GetFileInfo,
| with the directory search. The corresponding Mac Plus code is in
| Apple's TFSDir/MFSDir files (Plus tree: os/file_mgr_dir.s).
|
| References: Inside Macintosh Vol II, Ch 4: The File Manager

| ----------------------------------------------------------
| OpenRF -- _OpenRF ($A00A).
| Pascal: function OpenRF(fileName: Str255; vRefNum: INTEGER;
| VAR refNum: INTEGER): OSErr;
| Opens the resource fork of a file. Differs from FileOpen only
| in that it clears (RegRsrc).w (= 0 = resource fork) instead of
| setting it to -1 (= data fork), then jumps to the common open
| path at FILEOPEN_CONT.
OpenRF:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: queue up the call
        CLR.B   (RegRsrc).w                     | resource fork (false = rsrc)
        BRA.B   FILEOPEN_CONT                   | -> common open path

| ----------------------------------------------------------
| FileOpen -- _Open ($A000) for file paths.
| Device Manager's Open ($A000) handler in device_mgr.s
| forwards here (JMP FileOpen(PC) at device_mgr.s:259) when
| the requested name doesn't match an installed driver -- i.e.
| for opening a regular file's data fork.
FileOpen:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: queue up the call
        ST      (RegRsrc).w                     | data fork (true = regular)
| FILEOPEN_CONT -- common open path (also reached from OpenRF above).
| Walks the FCB table looking for a free slot, then dispatches to
| the directory search to locate the named file.
FILEOPEN_CONT:
        BSR.B   SETVOLINFO_HFS_CONT_3_CONT      | Gt1stFCB: get first FCB entry
FILEOPEN_CONT_2:
        TST.L   fcbFlNm(A1,D1.W)                | FCB slot in use?
        BEQ.B   FILEOPEN_CONT_2_CONT_3          | free slot found ->
        BSR.B   HFSE_NEXT                       | advance to next FCB slot
        BCS.B   FILEOPEN_CONT_2                 | more slots to scan ->
        MOVEQ.L #-0x2A,D0                       | D0 = -42 = tmfoErr
FILEOPEN_CONT_2_CONT:
        CLR     24(A0)                          | ioRefNum = 0 (open failed)
FILEOPEN_CONT_2_CONT_2:
        BRA.W   FSQUEUE_DONE                    | finish via CmdDone
FILEOPEN_CONT_2_CONT_3:
        MOVE    D1,24(A0)                       | ioRefNum = FCB index (D1)
        ADD.L   A1,D1                           | D1 = absolute FCB ptr
        BSR.W   FndFilName                      | search MFS dir for fileName
        BNE.B   FILEOPEN_CONT_2_CONT            | not found -> err
        MOVEA.L  D1,A3                          | A3 = FCB to populate
        MOVE    -2(A1),D7                       | D7 = MDB block #+dirty bits
        BCLR    #0xF,D7                         | clear dirty bit (block #)
        MOVE    (A5),D3                         | D3 = file flags from dir
        ANDI.W   #0x1FF,D3                      | mask to flag bits
        MOVE.L  28(A0),D0                       | D0 = caller's ioMisc (clump)
        MOVE.L  D0,A4                           | A4 = ioMisc ptr (or 0)
        BEQ.B   FILEOPEN_CONT_2_CONT_4          | ok ->
        ADDQ.L   #0x8,A4                        | skip past ioFCBLEnd header
        CLR.W    (A4)+                          | clear ioFCBVers field
FILEOPEN_CONT_2_CONT_4:
        LEA.L     18(A5),A5                     | A5 = past dir header info
        MOVE.L  (A5)+,D2                        | D2 = file ID (CNID)
        MOVE    (A5)+,D4                        | D4 = data fork start block
        MOVE.L  (A5)+,D5                        | D5 = data fork LEOF
        MOVE.L  (A5)+,D6                        | D6 = data fork PEOF
        TST.B   (RegRsrc).w                     | regular (data) fork mode?
        BNE.B   FILEOPEN_CONT_2_CONT_5          | yes -> use data-fork values
        BSET    #0x9,D3                         | set fcb_FlgRsrcOpen flag
        MOVE    (A5)+,D4                        | D4 = rsrc fork start block
        MOVE.L  (A5)+,D5                        | D5 = rsrc fork LEOF
        MOVE.L  (A5)+,D6                        | D6 = rsrc fork PEOF
FILEOPEN_CONT_2_CONT_5:
        CMPI.B  #0x1,27(A0)                     | permission == fsRdPerm?
        BNE.B   FILEOPEN_CONT_2_NO              | no -> check write/excl
        BCLR    #0x8,D3                         | clear write-bit (read-only)
        BRA.B   FILEOPEN_CONT_2_CONT_8          | install FCB and exit
FILEOPEN_CONT_2_NO:
        MOVEQ.L #-0x36,D0                       | D0 = -54 = permErr
        BCHG    #0x8,D3                         | D3 ^= 1<<0x8
        BNE.B   FILEOPEN_CONT_2_CONT            | locked -> permErr
        BSR.W   HFSE_NEXT_CONT                  | search FCBs by file ID
        BNE.B   FILEOPEN_CONT_2_CONT_8          | no other open -> install
FILEOPEN_CONT_2_CONT_6:
        MOVE    fcbFlags(A1,D1.W),D0            | D0 = existing FCB flags
        EOR     D3,D0                           | XOR new vs existing flags
        ANDI    #0x300,D0                       | isolate write-related bits
        BNE.B   FILEOPEN_CONT_2_CONT_7          | share conflict -> next FCB
        MOVE    D1,24(A0)                       | return existing ioRefNum
        MOVEQ.L #-0x31,D0                       | D0 = -49 = opWrErr
        BRA.B   FILEOPEN_CONT_2_CONT_2          | finish with opWrErr
FILEOPEN_CONT_2_CONT_7:
        BSR.W   HFSE_ERR_9                      | find next FCB for same ID
        BEQ.B   FILEOPEN_CONT_2_CONT_6          | another match -> recheck
FILEOPEN_CONT_2_CONT_8:
        MOVE.L  D2,(A3)+                        | fcbFlNm = file ID
        MOVE    D3,(A3)+                        | fcbFlags = flags
        MOVE    D4,(A3)+                        | fcbStBlk = start block
        MOVE.L  D5,(A3)+                        | fcbEOF = LEOF
        MOVE.L  D6,(A3)+                        | fcbPLen = PEOF
        CLR.L   (A3)+                           | fcbCrPs = 0 (mark at 0)
        MOVE.L  A2,(A3)+                        | fcbVPtr = VCB ptr
        MOVE.L  A4,(A3)+                        | fcbBfAdr = ioMisc/clump ptr
        MOVE    D7,(A3)                         | fcbDirBlk = dir block #
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        BRA.B   CREATE_ERR_2                    | finish via CmdDone
| ----------------------------------------------------------
| Create -- _Create ($A008).
| Pascal: function Create(fileName: Str255; vRefNum: INTEGER;
| creator, fileType: OSType): OSErr;
| Creates a new MFS file. Looks up the name first; if found,
| returns dupFNErr. If not found (FNFErr), falls into the
| MFS-create path at CREATE_ERR (start of file_mgr_io.s)
| to allocate a directory entry and initialize the file.
| Plus 1986 added BCLR #0x1,(HFSFlags).w to clear the CreateDir
| bit and a TFSVCBTst dispatch for HFS volumes; classic 1984
| has neither (MFS only).
Create:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: queue up the call
        BSR.W   FndFilName                      | FndFilName: search for existing entry
        BNE.B   CREATE_ERR                      | not found -> create path
        MOVEQ.L #-0x30,D0                       | dupFNErr: file already exists
CREATE_ERR:
        CMPI    #-0x2B,D0                       | D0 == fnfErr (file not found)?
        BEQ.B   CREATE_NO_7                     | yes -> create the new file
CREATE_ERR_2:
        BRA.W   FSQUEUE_DONE                    | return error via FSQueue done
CREATE_NO_7:
        MOVEQ.L #-0x25,D0                       | D0 = bdNamErr (-37, bad name)
        TST     D2                              | name length zero?
        BEQ.B   CREATE_ERR_2                    | yes -> bdNamErr
        BSR.W   SETVOLINFO_HFS_CONT_3           | check write protect
        BNE.B   CREATE_ERR_2                    | write-protected -> error
        BSR.B   CREATE_CONT_8                   | find directory slot for new entry
        BNE.B   CREATE_ERR_2                    | no slot found -> error
        MOVE    D5,D0                           | D0 = entry size to clear
        MOVE.L  A5,A1                           | A1 = entry position

| MFS Create: initialize new directory entry
CREATE_CONT_6:
        CLR     (A1)+                           | zero the entry
        SUBQ.W  #0x2,D0                         | decrement byte counter by word
        BHI.B   CREATE_CONT_6                   | loop until entry zeroed
        BSET    #0x7,(A5)                       | set "in use" flag
        MOVE.B  26(A0),1(A5)                    | set file version (ioVersNum)
        MOVE.L  vcbNxtCNID(A2),18(A5)           | assign file number (VCBNxtCNID)
        ADDQ.L  #0x1,vcbNxtCNID(A2)             | bump next CNID
        LEA.L     0x2A(A5),A5                   | point to date fields
        MOVE.L  (Time).w,(A5)                   | creation date = now
        MOVE.L  (A5)+,(A5)+                     | modification date = creation date
        MOVE.B  D2,(A5)+                        | set name length byte
        BEQ.B   CREATE_EMPTY                    | empty name ->
CREATE_LOOP:
        MOVE.B  (A4)+,(A5)+                     | copy name bytes
        SUBQ.B  #0x1,D2                         | decrement name length counter
        BHI.B   CREATE_LOOP                     | loop until all bytes copied
CREATE_EMPTY:
        ST      6(A2)                           | 6(A2) := -1 (true)
        ADDQ.W  #0x1,vcbNmFls(A2)               | 20(A2) += 0x1
        MOVEQ.L #0x0,D0                         | return noErr
        BRA.B   CREATE_ERR_2                    | return via FSQueue done

| ----------------------------------------------------------
| CREATE_CONT_8
| CREATE_CONT_8: find space in MFS directory for a new entry
CREATE_CONT_8:
        MOVE.L  (SP)+,A3                        | A3 = return address (for JMP later)
        MOVEQ.L #0x34,D5                        | fixed entry fields (52 bytes)
        ADD     D2,D5                           | + name length = total entry size
        BCLR    #0x0,D5                         | round to even
        BSR.W   FILEFILETFSETCATINFO_HFS_CONT_2_CONT | read first directory block
        BRA.B   CREATE_CONT_9                   | join scan loop
CREATE_NO_8:
        BSR.W   FILEWRITE_NEXT                  | advance to next dir block
CREATE_CONT_9:
        BNE.B   CREATE_ERR_5                    | read error -> exit via A3
        MOVEQ.L #0x0,D0                         | D0 = scan offset within block
CREATE_CONT_10:
        TST.B   0(A5,D0.W)                      | entry in use?
        BEQ.B   CREATE_FOUND                    | no, found free space ->
        BSR.B   CREATE_NEXT                     | advance D0 to next entry
        BCS.B   CREATE_CONT_10                  | unsigned less ->
CREATE_FOUND:
        MOVE    D0,D4                           | D4 = current scan offset
        ADD     D5,D4                           | D4 = end of new entry
        CMPI    #0x200,D4                       | fits in 512-byte block?
        BCC.B   CREATE_NO_8                     | no -> next block
        BSET    #0x7,-2(A5)                     | flag block as dirty
        LEA.L     0(A5,D0.W),A5                 | A5 = address of new entry
        CLR.L   vcbDirIndex(A2)                 | 0x5A(A2) := 0
        MOVEQ.L #0x0,D0                         | return noErr
CREATE_ERR_5:
        JMP     (A3)                            | return via saved address
| ----------------------------------------------------------
| CREATE_NEXT: advance to next MFS directory entry
| Called during boot.
CREATE_NEXT:
        MOVEQ.L #0x0,D6                         | clear high bytes
        MOVE.B  0x32(A5,D0.W),D6                | name length of current entry
        ADD     D6,D0                           | + name length
        ADDI    #0x34,D0                        | + fixed fields = next entry offset
        BCLR    #0x0,D0                         | round to even
        CMPI    #0x1CC,D0                       | past usable area? (512-52=460=$1CC)
        RTS                                     | return (CS = more entries, CC = end)
CREATE_OK_5:
        MOVE.L  A1,-(SP)                        | save A1
        MOVE.L  18(A5),D2                       | TFS file number (filFlNum)
        BSR.W   HFSE_NEXT_CONT                  | Gt1stMatch: find FCB for this file
        BEQ.B   CREATE_FOUND_3                  | found: file is open ->
        MOVEQ.L #0x0,D0                         | not open: no error
CREATE_CONT_17:
        MOVE.L  (SP)+,A1                        | restore A1
        RTS                                     | return from open-test
CREATE_FOUND_3:
        MOVE    D1,ioRefNum(A0)                 | return refNum of open file
        MOVEQ.L #-0x2F,D0                       | D0 = fBsyErr (-47, file busy)
        BRA.B   CREATE_CONT_17                  | restore A1 and return

| ----------------------------------------------------------
| Delete -- _Delete ($A009).
| Delete a file by name. Tests file-locked attribute, frees
| the allocation extents, decrements vcbNmFls, shifts directory
| entries to fill the deleted slot's space.
Delete:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.W   FILEFILETFSETCATINFO_HFS_CONT_2 | find file by name
        MOVEQ.L #-0x2D,D0                       | preset fLckdErr
        BTST    #0x0,(A5)                       | test file-locked bit
        BNE.B   HFSCATMOVE_OK_5                 | locked - error exit
        BSR.B   CREATE_OK_5                     | check open file table
        BNE.B   HFSCATMOVE_OK_5                 | file is open - error
        SUBQ.W  #0x1,vcbNmFls(A2)               | decrement vcbNmFls (file count)
        ST      6(A2)                           | 6(A2) := -1 (true)
        MOVE    22(A5),D3                       | D3 = data fork start block
        BSR.W   LG2PHYS_CONT_10                 | free data fork extents
        MOVE    0x20(A5),D3                     | D3 = resource fork start block
        BSR.W   LG2PHYS_CONT_10                 | free resource fork extents
        BSR.B   HFSCATMOVE_CONT_3               | compact directory block
        MOVEQ.L #0x0,D0                         | return noErr
HFSCATMOVE_OK_5:
        BRA.W   FSQUEUE_DONE                    | return via FSQueue done
HFSCATMOVE_CONT_2:
        MOVEQ.L #0x0,D0                         | clear high bytes
        MOVE.B  0x32(A5),D0                     | name length from entry
        ADDI    #0x34,D0                        | + fixed fields = total entry size
        BCLR    #0x0,D0                         | round down to even
        RTS                                     | return computed size in D0
HFSCATMOVE_CONT_3:
        MOVEM.L D0/A0-A1/A5,-(SP)               | save D0/A0-A1/A5
        BSET    #0x7,-2(A1)                     | flag dir block as dirty
        CLR.L   vcbDirIndex(A2)                 | 0x5A(A2) := 0
        MOVE.L  A5,A0                           | A0 = dest (deleted slot)
        BSR.B   HFSCATMOVE_CONT_2               | D0 = deleted entry size
        ADDA.L  D0,A5                           | A5 = next entry (source)
        ADDA.W  #0x200,A1                       | A1 = end of dir block
HFSCATMOVE_CONT_4:
        CMPA.L  A1,A5                           | past end of block?
        BCC.B   HFSCATMOVE_DONE                 | yes, done ->
        MOVE    (A5)+,(A0)+                     | shift entry down
        BRA.B   HFSCATMOVE_CONT_4               | keep shifting

| ----------------------------------------------------------
| HFSCATMOVE_DONE
| clear remaining words in directory block
HFSCATMOVE_DONE:
        CLR     (A0)+                           | zero a word
        CMPA.L  A1,A0                           | past end of block?
        BCS.B   HFSCATMOVE_DONE                 | no, keep clearing
        MOVEM.L (SP)+,D0/A0-A1/A5               | restore regs
        RTS                                     | exit MFSDeleteEntry

| ----------------------------------------------------------
| RENAME_FINDSLOT - find room in the directory for Rename's entry
| Entry: A2 = VCB, D2.W = name length of the entry to insert
| Exit:  D0 = 0 (or dirFulErr / read error), A5 = A3 = the space
| Runs FndFilSpc (CREATE_CONT_8) one call level deeper, from
| RENAME_FINDSLOT_SEARCH, with ErCode ($3A2) preset to 1. When
| FndFilSpc has to wait for a disk read it returns to its caller's
| caller, i.e. into RENAME_FINDSLOT_RETRY, which spins until the
| search, finished from the I/O completion, has stored its result
| (<= 0) in ErCode and the slot address in FSTemp4.
| Apple source name: GetSpace (System 7.1 OS/HFS/MFSDIR1.a, FndFilSpc
| header: "Called By: Create,Rename(via GetSpace)")
RENAME_FINDSLOT:
        BSR.B   RENAME_FINDSLOT_SEARCH          | search one call level deeper
RENAME_FINDSLOT_RETRY:
        MOVE    (0x3A2).w,D0                    | D0 = ErCode (1 while the search is pending)
        MOVE.L  (FSTemp4).w,A5                  | A5 = found-slot address
        MOVE.L  A5,A3                           | A3 = A5 (MOVEA: flags still from ErCode)
        BGT.B   RENAME_FINDSLOT_RETRY           | still pending -> wait
        RTS                                     | return; D0 = result
RENAME_FINDSLOT_SEARCH:
        MOVE    #0x1,(0x3A2).w                  | ErCode := 1 (search pending)
        BSR.W   CREATE_CONT_8                   | FndFilSpc: find space for the entry
        MOVE    D0,(0x3A2).w                    | ErCode := result
        MOVE.L  A5,(FSTemp4).w                  | stash slot address
        RTS                                     | to RENAME_FINDSLOT_RETRY or I/O completion

| ----------------------------------------------------------
| _Rename ($A00B): rename a file or a volume (MFS)
| Pascal: FUNCTION Rename(oldName: Str255; vRefNum: INTEGER;
|                        newName: Str255): OSErr;
| Entry: A0 = parameter block: ioNamePtr = old name, ioVRefNum,
|        ioMisc = new name
| Exit:  D0 = result code (via FSQUEUE_DONE = CmdDone)
| File: the new name must be on the same volume (or name none) and
| must not exist yet, unless it differs only in case. The old
| directory entry is copied onto the stack, removed from its block
| and re-inserted with the new name where RENAME_FINDSLOT finds
| room; if there is none it is put back under its old name
| (dirFulErr; fsRnErr if even that fails). Open FCBs of the file get
| the entry's new directory block.
| Volume: a new name with only a volume part ("Name:") renames the
| volume (vcbVN, at most 27 characters).
Rename:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE.L  28(A0),D2                       | D2 = new name ptr (ioMisc)
        BSR.W   DTRMV1_CONT_7                   | DtrmV2: volume of new name, D2 = file part len
        BNE.W   RENAME_ERR_5                    | error -> maybe a volume rename
        TST     D2                              | new name has a file-name part?
        BEQ.W   RENAME_NO_3                     | no -> volume rename
        MOVE.L  A2,A1                           | A1 = volume of the new name
        MOVE    D3,D7                           | D7 = new name's volume-name length (0 = none)
        MOVEM.L D2/A4,(FSTemp8).w               | save new name length + ptr
        BSR.W   DTRMV1_NO_4                     | DtrmV3: volume of the old name (ioNamePtr)
        BNE.B   RENAME_EXIT                     | error ->
        CMPA.L  A1,A2                           | same volume?
        BEQ.B   RENAME_SAMEVOL                  | yes -> proceed with rename
        TST     D7                              | did the new name give a volume?
        BEQ.B   RENAME_SAMEVOL                  | no -> use the old name's volume
RENAME_BADNAME:
        MOVEQ.L #-0x25,D0                       | D0 = bdNamErr (-37): different volumes
RENAME_EXIT:
        BRA.W   FSQUEUE_DONE                    | return via CmdDone
RENAME_SAMEVOL:
        BSR.W   SETVOLINFO_HFS_CONT_3           | volume locked or write-protected?
        BNE.B   RENAME_EXIT                     | error -> exit
        MOVE.L  A0,-(SP)                        | save param block
        MOVE    D2,D0                           | old name length (high word)
        MOVE.L  A4,A0                           | old name ptr
        MOVEM.L (FSTemp8).w,D2/A4               | get new name info
        SWAP    D0                              | set up for _CmpString
        MOVE    D2,D0                           | new name length (low word)
        MOVE.L  A4,A1                           | new name ptr
        _CmpString                              | compare old and new names
        MOVE.L  (SP)+,A0                        | restore param block
        BEQ.B   RENAME_MOVE                     | same name but for case -> skip dup check
        BSR.W   FNDFILNAME_OK                   | look up the new name on this volume
        BNE.B   RENAME_CHKERR                   | not found (good) ->
        MOVEQ.L #-0x30,D0                       | dupFNErr: name already exists
RENAME_CHKERR:
        CMPI    #-0x2B,D0                       | fnfErr (good) returned?
        BNE.B   RENAME_EXIT                     | any other err -> abort
RENAME_MOVE:
        BSR.W   FndFilName                      | find the old entry: A5 = entry, A1 = block
        BNE.B   RENAME_EXIT                     | error -> exit
        MOVE.L  SP,A4                           | A4 = stack mark before push
        MOVE.L  A5,A3                           | A3 = source entry address
        BSR.W   HFSCATMOVE_CONT_2               | D0 = source entry size
RENAME_PUSH_LOOP:
        MOVE    -0x2(A3,D0.W),-(SP)             | push the entry, last word first
        SUBQ.W  #0x2,D0                         | step backward by word
        BGT.B   RENAME_PUSH_LOOP                | loop until entry pushed
        BSR.W   HFSCATMOVE_CONT_3               | remove the old entry from its block
        MOVE.L  (FSTemp8).w,D2                  | recover new name length
        BSR.W   RENAME_FINDSLOT                 | find slot for renamed entry
        BNE.B   HFSCATMOVE_ERR_5                | no room -> put the old entry back
        MOVEQ.L #0x18,D0                        | 25 words = fixed part of the entry
| copy saved entry data back to new location
HFSCATMOVE_LOOP_2:
        MOVE    (SP)+,(A5)+                     | pop word into new entry
        DBRA    D0,HFSCATMOVE_LOOP_2            | loop for all 25 words
        MOVE.L  A4,SP                           | drop the rest (old name) from the stack
        MOVEM.L (FSTemp8).w,D2/A4               | get new name info
        MOVE.B  D2,(A5)+                        | set new name length

| MFS Rename: copy new name bytes into directory entry
HFSCATMOVE_OK_6:
        MOVE.B  (A4)+,(A5)+                     | copy one new-name byte
        SUBQ.W  #0x1,D2                         | count down
        BGT.B   HFSCATMOVE_OK_6                 | loop until name copied
        BSR.B   HFSCATMOVE_CONT_6               | update FCBs for renamed file
HFSCATMOVE_OK_6_CONT:
        MOVEQ.L #0x0,D0                         | D0 = noErr
HFSCATMOVE_ERR_4:                               | shared BRA.B target
        BRA.B   RENAME_EXIT                     | -> CmdDone with D0

| No room for the renamed entry: put the old entry back
HFSCATMOVE_ERR_5:
        MOVE.B  0x32(SP),D2                     | D2 = old name length (from the saved entry)
        BSR.W   RENAME_FINDSLOT                 | find space for re-insertion
        BEQ.B   HFSCATMOVE_NO_5                 | found space ->
        MOVE.L  A4,SP                           | drop the saved entry
        MOVEQ.L #-0x3B,D0                       | fsRnErr (-59): could not put it back
        BRA.B   HFSCATMOVE_ERR_4                | return error
HFSCATMOVE_NO_5:
        MOVE    (SP)+,(A5)+                     | pop a word back into slot
        CMPA.L  SP,A4                           | stack restored to mark?
        BNE.B   HFSCATMOVE_NO_5                 | no, keep copying
        BSR.B   HFSCATMOVE_CONT_6               | update FCBs of the file
        MOVEQ.L #-0x21,D0                       | dirFulErr (-33): no room for the new name
        BRA.B   HFSCATMOVE_ERR_4                | return tentative error
HFSCATMOVE_CONT_6:
        MOVE.L   18(A3),D2                      | D2 = file number (cnid)
        BSR.W   SRCHNODE_GT_CONT_CONT           | D0 = number of the dir block in the buffer
        BSR.W   HFSE_NEXT_CONT                  | first FCB of this file on this volume
        BNE.B   HFSCATMOVE_ERR_6                | no more -> done
HFSCATMOVE_OK_7:
        MOVE    D0,fcbFlPos(A1,D1.W)            | FCB's directory block := D0
        BSR.W   HFSE_ERR_9                      | advance to next FCB match
        BEQ.B   HFSCATMOVE_OK_7                 | more -> loop
HFSCATMOVE_ERR_6:
        RTS                                     | return from FCB-update helper
RENAME_ERR_5:
        CMPI    #-0x23,D0                       | nsvErr (new name's volume unknown)?
        BNE.B   HFSCATMOVE_ERR_4                | other error -> exit
        TST     D2                              | new name has a file-name part?
        BNE.W   RENAME_BADNAME                  | yes -> bdNamErr
RENAME_NO_3:
        TST     D3                              | new name has a volume part?
        BEQ.B   HFSCATMOVE_ERR_4                | no -> exit with D0
        BSR.W   DTRMV1_NO_4                     | DtrmV3: volume of the old name
        BNE.B   HFSCATMOVE_ERR_4                | error -> exit
        BSR.W   SETVOLINFO_HFS_CONT_3           | volume locked or write-protected?
        BNE.B   HFSCATMOVE_ERR_4                | error -> exit
        TST     vcbDrvNum(A2)                   | volume on line?
        BEQ.B   HFSCATMOVE_ERR_4                | no -> exit
        ST      6(A2)                           | mark VCB dirty (vcbFlags)
        LEA.L     vcbVN(A2),A2                  | A2 = &vcbVN
        MOVE.L  28(A0),A1                       | A1 = ioMisc (new volume name)
        MOVE.B  (A1)+,D0                        | D0 = new name length byte
        SUBQ.B  #0x1,D0                         | drop the trailing ':'
        CMPI.B  #0x1B,D0                        | length > 27 (max VCB name)?
        BLS.B   HFSCATMOVE_NO_5_ERR_CONT        | no -> use as-is
        MOVEQ.L #0x1B,D0                        | yes -> truncate to 27
HFSCATMOVE_NO_5_ERR_CONT:
        MOVE.B  D0,(A2)+                        | store name length in VCB
HFSCATMOVE_NO_5_ERR_CONT_2:
        MOVE.B  (A1)+,(A2)+                     | copy one volume name byte
        SUBQ.B  #0x1,D0                         | count down
        BHI.B   HFSCATMOVE_NO_5_ERR_CONT_2      | loop until done
        BRA.B   HFSCATMOVE_OK_6_CONT            | return noErr

| ----------------------------------------------------------
| SetFilType -- _SetFilType ($A043).
| Pascal: function SetFilType(fileName: Str255; vRefNum: INTEGER;
| ioFlVersNum: INTEGER): OSErr;
| Sets the file type byte. Saves old ioFVersNum, replaces with
| new type from offset 0x1C, calls FndFilName to find any file
| with the new type -- if found, returns dupFNErr. Plus 1986
| added a TFSVCBTst dispatch that returns CMnotempty for HFS
| volumes; classic 1984 always inlines the MFS path.
SetFilType:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE.B  26(A0),D1                       | save old ioFVersNum (offset 0x1A)
        MOVE.B  28(A0),26(A0)                   | replace with new type from offset 0x1C
        BSR.W   FndFilName                      | FndFilName: find file by type
        BNE.B   SETFILTYPE_NO                   | not found ->
        MOVEQ.L #-0x30,D0                       | dupFNErr: file with that type exists
SETFILTYPE_NO:
        MOVE.B  D1,26(A0)                       | restore old ioFVersNum
        CMPI    #-0x2B,D0                       | fnfErr (good - new type unique)?
        BNE.B   RSTFILLOCK_ERR                  | any other err -> exit
        BSR.B   FILEFILETFSETCATINFO_HFS_CONT_2 | re-find file by old type
        MOVE.B  28(A0),1(A5)                    | set new file type byte
        BRA.W   RSTFILLOCK_CONT_3               | mark dirty + return
| ----------------------------------------------------------
| SetFilLock -- _SetFilLock ($A041).
| Lock a file (set file-locked attribute).
SetFilLock:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        ST      (FLckUnlck).w                   | flag: lock (not unlock)
        BRA.B   RSTFILLOCK_CONT                 | merge with RstFilLock body

| ----------------------------------------------------------
| RstFilLock -- _RstFilLock ($A042).
| Unlock a file (clear file-locked attribute).
RstFilLock:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        CLR.B   (FLckUnlck).w                   | flag: unlock
RSTFILLOCK_CONT:
        BSR.B   FILEFILETFSETCATINFO_HFS_CONT_2 | locate entry + verify writable
        TST.B   (FLckUnlck).w                   | lock or unlock?
        BEQ.B   RSTFILLOCK_CONT_2               | ok ->
        BSET    #0x0,(A5)                       | set flag
        BNE.B   RSTFILLOCK_OK                   | already locked -> noErr
        BRA.B   RSTFILLOCK_CONT_3               | newly locked -> mark dirty
RSTFILLOCK_CONT_2:
        BCLR    #0x0,(A5)                       | jump via A3
        BEQ.B   RSTFILLOCK_OK                   | already unlocked -> noErr
RSTFILLOCK_CONT_3:
        BSET    #0x7,-2(A1)                     | flag dir block as dirty
RSTFILLOCK_OK:
        MOVEQ.L #0x0,D0                         | return noErr
RSTFILLOCK_ERR:
        BRA.W   FSQUEUE_DONE                    | return via FSQueue done

| ----------------------------------------------------------
| SetFileInfo -- _SetFileInfo ($A00D).
| Pascal: function SetFileInfo(fileName: Str255; vRefNum: INTEGER;
| VAR fileInfo: FInfo): OSErr;
| Updates a file's Finder info (16 bytes at offset 0x20 in
| FileParam = ioFlFndrInfo). Reads the FInfo from the param block
| and writes it into the MFS directory entry's filUsrWds field
| (offset 2 in the 52-byte MFS dir entry). Plus 1986 stores at
| filUsrWds offset 0x4 in the HFS file record (different layout)
| and dispatches via TFSVCBTst.
SetFileInfo:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   FILEFILETFSETCATINFO_HFS_CONT_2 | FndFilName + write protect check
        MOVEM.L 0x20(A0),D1-D4                  | load ioFlFndrInfo (16 bytes) from param
        MOVEM.L D1-D4,2(A5)                     | store in MFS dir entry filUsrWds
        BRA.B   RSTFILLOCK_CONT_3               | -> mark dirty + return

| ----------------------------------------------------------
| FILEFILETFSETCATINFO_HFS_CONT_2: find file and check write protect (shared by Set calls)
FILEFILETFSETCATINFO_HFS_CONT_2:
        MOVE.L  (SP)+,(FSTemp4).w               | stash return PC for re-entry
        BSR.B   FndFilName                      | locate file by name
        BNE.B   RSTFILLOCK_ERR                  | not found -> error
        BSR.W   SETVOLINFO_HFS_CONT_3           | verify volume is writable
        BNE.B   RSTFILLOCK_ERR                  | write-protected -> error
        MOVE.L  (FSTemp4).w,A3                  | A3 = saved return PC
        JMP     (A3)                            | jump via A3
FILEFILETFSETCATINFO_HFS_CONT_2_CONT:
        MOVE    vcbAllocPtr(A2),D4              | D4 = vcb roving alloc ptr
        MOVE    vcbVBMSt(A2),D3                 | D3 = VBM start block
        ADD     D3,D4                           | D4 = absolute scan start
        BSR.B   SRCHNODE_GT_CONT_CONT           | D0 = vcb max block count
        CMP     D3,D0                           | D0 below VBM start?
        BCS.B   FILEFILETFSETCATINFO_HFS_CONT_2_CONT_2 | yes -> reset to start
        CMP     D4,D0                           | D0 in active scan range?
        BCS.B   FILEFILETFSETCATINFO_HFS_CONT_2_CONT_3 | yes -> use as resume point
FILEFILETFSETCATINFO_HFS_CONT_2_CONT_2:
        MOVEQ.L #0x0,D0                         | reset scan resume to 0
FILEFILETFSETCATINFO_HFS_CONT_2_CONT_3:
        MOVE    D3,(NxtDB).w                    | NxtDB := scan start
        MOVE    D4,(MaxDB).w                    | MaxDB := scan end
        MOVE    D0,(CkdDB).w                    | CkdDB := first block to recheck
        BEQ.B   FILEWRITE_NEXT                  | zero -> step into loop
        MOVEQ.L #0x0,D0                         | dupFNErr
        RTS                                     | return; D0 = noErr
FILEWRITE_NEXT:
        MOVE    (NxtDB).w,D3                    | D3 = next dir block to read
        ADDQ.W  #0x1,(NxtDB).w                  | advance NxtDB
        CMP     (MaxDB).w,D3                    | past scan end?
        BCC.B   SRCHNODE_GT_CONT                | yes -> end of scan
        CMP     (CkdDB).w,D3                    | already-checked block?
        BEQ.B   FILEWRITE_NEXT                  | yes -> skip
        BRA.W   HFSE_READ_VBM_BLOCK             | read next VBM block
SRCHNODE_GT_CONT:
        MOVEQ.L #-0x21,D0                       | D0 = eofErr (-39)
        RTS                                     | return; scan exhausted
SRCHNODE_GT_CONT_CONT:
        MOVE.L  vcbBufAdr(A2),A5                | A5 = volume buffer
SRCHNODE_GT_CONT_CONT_2:
        MOVE    -2(A5),D0                       | D0 = block size word (header)
        ANDI    #0x7FFF,D0                      | strip dirty bit, leave size
        RTS                                     | return from SRCHNODE_GT_CONT_CONT_2
FndFilName:
        BSR.W   DTRMV1_NO_4                     | set up VCB and locate volume
        BEQ.B   FNDFILNAME_OK                   | volume mounted -> proceed
FNDFILNAME_CONT:
        RTS                                     | return; D0 = error
FNDFILNAME_OK:
        BSR.B   FNDFILNAME_CONT_4               | dispatch external FS if needed
        BNE.B   FNDFILNAME_CONT                 | dispatched -> return
        MOVE.L  (SP)+,A3                        | A3 = caller's return PC
        MOVE    vcbNmFls(A2),D7                 | D7 = file count on volume
        BEQ.B   GETFILEINFO_OK_8                | no files -> fnfErr
        BSR.B   FILEFILETFSETCATINFO_HFS_CONT_2_CONT | set up dir-block scan
GETFILEINFO_CONT_8:
        BEQ.B   GETFILEINFO_OK_9                | zeroed -> begin scan
        CMPI    #-0x21,D0                       | eofErr (end of scan)?
        BNE.B   GETFILEINFO_ERR_7               | any other err -> exit via A3
GETFILEINFO_OK_8:
        MOVEQ.L #-0x2B,D0                       | D0 = fnfErr (-43)
        BRA.B   GETFILEINFO_ERR_7               | return fnfErr via A3
GETFILEINFO_OK_9:
        MOVEQ.L #0x0,D0                         | D0 = entry offset (start at 0)
        MOVE.L  A4,A1                           | A1 = target name ptr
| MFS directory search: scan entries for matching filename
GETFILEINFO_CONT_9:
        MOVE    D0,D4                           | D4 = current entry offset
        TST.B   0(A5,D4.W)                      | entry in use? (first byte nonzero)
        BEQ.B   GETFILEINFO_NO_9                | no, end of directory ->
        MOVE.B  1(A5,D4.W),D6                   | entry's volume flags byte
        CMP.B   26(A0),D6                       | matches our volume?
        BNE.B   GETFILEINFO_SKIP_3              | no -> skip to next entry
        MOVE.L  A0,-(SP)                        | save A0 (FCB ptr)
        LEA.L   0x32(A5,D4.W),A0                | A0 = &name field in MFS directory entry
        MOVEQ   #0,D0                           | clear high half
        MOVE.B  (A0)+,D0                        | D0 = length byte (advance past length)
        SWAP    D0                              | move length into high word
        MOVE    D2,D0                           | D0 low = target name length/ptr
        _CmpString                              | byte-for-byte case-sensitive compare
        MOVEA.L (SP)+,A0                        | restore A0
        BEQ.B   GETFILEINFO_FOUND_3             | names match -> success path
GETFILEINFO_SKIP_3:
        SUBQ.W  #0x1,D7                         | decrement file counter
        BEQ.B   GETFILEINFO_OK_8                | all files checked ->
        MOVE    D4,D0                           | current offset
        BSR.W   CREATE_NEXT                     | get next MFS directory entry
        BCS.B   GETFILEINFO_CONT_9              | more entries ->
GETFILEINFO_NO_9:
        BSR.W   FILEWRITE_NEXT                  | advance to next dir block
        BRA.B   GETFILEINFO_CONT_8              | join scan loop
GETFILEINFO_FOUND_3:                            | reached when CmpString found match
        MOVE.L  A5,A1                           | A1 = dir block base
        LEA.L     0(A5,D4.W),A5                 | A5 = matched entry address
GETFILEINFO_ERR_7:
        JMP     (A3)                            | return via saved A3
| ----------------------------------------------------------
| FNDFILNAME_CONT_4
| Called during boot.
| FNDFILNAME_CONT_4: check for external FS and dispatch if so
FNDFILNAME_CONT_4:
        BSR.W   HFSE_NO_9_CONT_3                | check external FS
        BNE.B   FNDFILNAME_ERR_3                | external FS, dispatch ->
        TST     vcbDrvNum(A2)                   | volume mounted on a drive?
        BNE.B   FNDFILNAME_ERR_3                | error ->
        MOVEQ.L #-0x35,D0                       | dupFNErr
FNDFILNAME_ERR_3:
        TST     D0                              | set CCR for caller
        RTS                                     | return; D0 = err code

| ----------------------------------------------------------
| GetFileInfo -- _GetFileInfo ($A00C).
| Pascal: function GetFileInfo(fileName: Str255; vRefNum: INTEGER;
| VAR fileInfo: FInfo): OSErr;
| Returns information about a file. Looks up by name (D1=0) or
| by directory index (D1>0). Plus 1986 added BCLR #0,(HFSFlags).w
| for HFS dispatch and uses BGT (positive index only); classic
| 1984 uses BNE (any non-zero treated as indexed lookup).
GetFileInfo:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE    28(A0),D1                       | D1 = ioFDirIndex
        BNE.B   GETFILEINFO_CONT_2              | non-zero -> indexed lookup
        BSR.W   FndFilName                      | FndFilName: look up by name
        BNE.B   GETFILEINFO_ERR_2               | error ->
        BRA.B   GETFILEINFO_CONT_11_CONT_NO     | found by name -> copy info
GETFILEINFO_CONT_2:
        BSR.W   DTRMV1                          | call helper
        BNE.B   GETFILEINFO_ERR_2               | volume not mounted -> err
        BSR.B   FNDFILNAME_CONT_4               | dispatch external FS if needed
        BNE.B   GETFILEINFO_ERR_2               | dispatched -> exit
        CMP     vcbNmFls(A2),D1                 | index past last file?
        BHI.B   GETFILEINFO_ERR_8               | yes ->
        MOVE    vcbAllocPtr(A2),D5              | VCB field
        MOVE    vcbVBMSt(A2),D3                 | VCB field
        ADD     D3,D5                           | D5 = AllocPtr + VBMSt (start block)
        MOVE    vcbDirIndex(A2),D7              | VCB field
        BEQ.B   GETFILEINFO_OK_11               | ok ->
        CMP     D7,D1                           | index past cached position?
        BCS.B   GETFILEINFO_OK_11               | unsigned less ->
        MOVE    vcbDirBlk(A2),D3                | VCB field
        BRA.B   GETFILEINFO_CONT_10             | resume from cached position
GETFILEINFO_OK_11:
        MOVEQ.L #0x1,D7                         | D7 = 1 (@ $43CC)

| MFS GetFileInfo indexed: resume from cached position or start fresh
GETFILEINFO_CONT_10:
        CMP     D5,D3                           | past end of directory?
        BCC.B   GETFILEINFO_ERR_8               | yes ->
        MOVE    D3,vcbDirBlk(A2)                | cache current dir block
        MOVE    D7,vcbDirIndex(A2)              | cache current file index
        BSR.W   HFSE_READ_VBM_BLOCK             | read directory block
        BNE.B   GETFILEINFO_ERR_8               | error ->
        MOVEQ.L #0x0,D0                         | initial entry offset
GETFILEINFO_CONT_11:
        MOVEQ.L #0x0,D6                         | D6 = 0 (unused)
        TST.B   0(A5,D0.W)                      | entry empty (end of dir)?
        BEQ.B   GETFILEINFO_OK_12               | ok ->
        CMP     D7,D1                           | reached requested index?
        BEQ.B   GETFILEINFO_OK_13               | ok ->
        ADDQ.W  #0x1,D7                         | advance to next directory entry
        BSR.W   CREATE_NEXT                     | call helper
        BCS.B   GETFILEINFO_CONT_11             | unsigned less ->
GETFILEINFO_OK_12:
        ADDQ.W  #0x1,D3                         | advance to next dir block
        BRA.B   GETFILEINFO_CONT_10             | loop into block-read code
GETFILEINFO_ERR_8:
        MOVEQ.L #-0x2B,D0                       | D0 = fnfErr (-43)
GETFILEINFO_ERR_2:
        BRA.W   FSQUEUE_DONE                    | return via FSQueue done
GETFILEINFO_OK_13:
        LEA.L     0(A5,D0.W),A5                 | A5 = ptr to matched directory entry
        LEA.L     0x32(A5),A3                   | A3 = ptr to filename in entry
        MOVE.L  ioFileName(A0),D0               | caller's filename buffer
        BEQ.B   GETFILEINFO_CONT_11_CONT_NO     | no buffer ->
        MOVE.L  D0,A4                           | A4 = dest for name copy
        MOVE.B  (A3),D0                         | name length
GETFILEINFO_CONT_12:
        MOVE.B  (A3)+,(A4)+                     | copy one name byte to caller buf
        SUBQ.B  #0x1,D0                         | count down
        BCC.B   GETFILEINFO_CONT_12             | loop until done
GETFILEINFO_CONT_11_CONT_NO:
        LEA.L     ioFlAttrib(A0),A4             | A4 = &30(A0)
        MOVEQ.L #0x18,D0                        | D0 = 24 (49 words / 2 - 1)
        LEA.L     (A5),A3                       | A3 = source dir entry
GETFILEINFO_LOOP_6:
        MOVE    (A3)+,(A4)+                     | copy one word of FInfo
        DBRA    D0,GETFILEINFO_LOOP_6           | loop 25 words
        BSR.W   CREATE_OK_5                     | check if file is open in any FCB
        BNE.B   GETFILEINFO_ERR_3               | open -> mark fcbWriteLock
        BCLR    #0x7,ioFlAttrib(A0)             | clear "in use" bit (Finder flag)
GETFILEINFO_FOUND_2:
        MOVEQ.L #0x0,D0                         | return noErr
        BRA.B   GETFILEINFO_ERR_2               | return via FSQueue done
GETFILEINFO_ERR_3:
        LEA.L     0x34(A0),A3                   | A3 = &ioFlFndrInfo in pb
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB table base
        BSR.W   FILECLOSE_CONT_6                | merge FCB-locked bits
        BSR.W   HFSE_ERR_9                      | GtNxtMatch: find next matching FCB
        BEQ.B   GETFILEINFO_ERR_3               | more matches -> loop
        BRA.B   GETFILEINFO_FOUND_2             | done -> return noErr

| ----------------------------------------------------------
| SEEK
| ----------------------------------------------------------
| SEEK -- position within an open file (internal helper)
| Entry: A0 = IOParam, A1 = FCBsPtr, D1 = FCB offset in table
| ioPosMode(A0) = fsAtMark / fsFromStart / fsFromLEOF / fsFromMark
| ioPosOffset(A0) = requested offset (signed)
| Exit: D5 = new absolute position (clamped to EOF),
| D7 = ioReqCount, D0 = noErr / paramErr / posErr (eofErr)
| ----------------------------------------------------------
SEEK:
        CLR.L   ioActCount(A0)                  | IOActCount = 0 (no bytes moved yet)
        MOVEQ.L #-0x32,D0                       | D0 = paramErr (-50)
        MOVE.L  ioReqCount(A0),D7               | D7 = ioReqCount
        BMI.B   SEEK_EXIT                       | negative count -> paramErr
        MOVE.L  ioPosOffset(A0),D2              | D2 = user-supplied offset
        MOVE.L  fcbCrPs(A1,D1.W),D5             | D5 = FCB current mark
        MOVE.L  fcbEOF(A1,D1.W),D4              | D4 = FCB logical EOF
        MOVE.B  (ioPosMode+1)(A0),D0            | D0 = ioPosMode (low byte)
        ROXR.B  #0x2,D0                         | rotate mode bits 1-0 into C/N
        BCC.B   SEEK_MODE_AT_OR_START           | mode bit 1 = 0 -> mode 0/1
        BMI.B   SEEK_ADD_OFFSET                 | mode bit 0 = 1 -> mode 3 (fsFromMark)
        MOVE.L  D4,D5                           | mode 2 (fsFromLEOF): D5 = EOF
SEEK_ADD_OFFSET:
        ADD.L   D2,D5                           | D5 = base + offset
        BRA.B   SEEK_CHECK                      | -> check clamp
SEEK_MODE_AT_OR_START:
        BPL.B   SEEK_CHECK                      | mode 0 (fsAtMark): leave D5 unchanged
        MOVE.L  D2,D5                           | mode 1 (fsFromStart): D5 = offset
SEEK_CHECK:
        BPL.B   SEEK_CHECK_EOF                  | D5 >= 0 -> check EOF
        MOVEQ.L #-0x28,D0                       | D0 = posErr (-40: before start)
        BRA.B   SEEK_EXIT                       | exit with error
SEEK_CHECK_EOF:
        MOVE.L  D5,D2                           | D2 = position
        SUB.L   D4,D2                           | D2 = position - EOF
        BLE.B   SEEK_OK                         | position <= EOF -> ok
        MOVE.L  D4,D5                           | else clamp to EOF
SEEK_OK:
        MOVE.L  D5,fcbCrPs(A1,D1.W)             | update FCB current mark
        MOVEQ.L #0x0,D0                         | D0 = noErr
SEEK_EXIT:
        RTS                                     | return from SEEK

