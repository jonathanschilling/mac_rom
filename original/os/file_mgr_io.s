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

| ----------------------------------------------------------
| Create -- _Create ($A008). Plus file_mgr_io.s 268.
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
| Delete -- _Delete ($A009). Plus file_mgr_io.s body.
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
DISPOSECCURSOR_CONT_4:
        BSR.B   DISPOSECCURSOR_CONT_4_CONT_CONT | search dir for free slot
DISPOSECCURSOR_CONT_4_CONT:
        MOVE    (0x3A2).w,D0                    | D0 = result code from search
        MOVE.L  (FSTemp4).w,A5                  | A5 = found-slot address
        MOVE.L  A5,A3                           | A3 = entry pointer
        BGT.B   DISPOSECCURSOR_CONT_4_CONT      | retry if > (handled internally)
        RTS                                     | return; D0 = result
DISPOSECCURSOR_CONT_4_CONT_CONT:
        MOVE    #0x1,(0x3A2).w                  | set "rename mode" flag
        BSR.W   CREATE_CONT_8                   | find directory slot
        MOVE    D0,(0x3A2).w                    | stash result code
        MOVE.L  A5,(FSTemp4).w                  | stash slot address
        RTS                                     | return to caller (@ $4120)

| ----------------------------------------------------------
| Rename -- _Rename ($A00B). Plus file_mgr_io.s body.
| Rename a file or volume. ioMisc points to the new name.
| If new name is NIL, this is a volume-rename (MFS).
Rename:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        MOVE.L  28(A0),D2                       | D2 = new name ptr (ioMisc)
        BSR.W   DTRMV1_CONT_7                   | DTRMV + FndFilName for source
        BNE.W   RENAME_ERR_5                    | error ->
        TST     D2                              | new name specified?
        BEQ.W   RENAME_NO_3                     | no name, MFS rename ->
        MOVE.L  A2,A1                           | A1 = source VCB
        MOVE    D3,D7                           | D7 = source name length
        MOVEM.L D2/A4,(FSTemp8).w               | save new name info in temp
        BSR.W   DTRMV1_NO_4                     | DTRMV3: determine dest volume
        BNE.B   DISPOSECCURSOR_CONT_4_CONT_CONT_ERR_2 | error ->
        CMPA.L  A1,A2                           | same volume?
        BEQ.B   DISPOSECCURSOR_CONT_4_CONT_CONT_CONT | yes -> proceed with rename
        TST     D7                              | source had a name?
        BEQ.B   DISPOSECCURSOR_CONT_4_CONT_CONT_CONT | volume rename -> ok
DISPOSECCURSOR_CONT_4_CONT_CONT_ERR:
        MOVEQ.L #-0x25,D0                       | D0 = bdNamErr (-37)
DISPOSECCURSOR_CONT_4_CONT_CONT_ERR_2:
        BRA.W   FSQUEUE_DONE                    | return via FSQueue done
DISPOSECCURSOR_CONT_4_CONT_CONT_CONT:
        BSR.W   SETVOLINFO_HFS_CONT_3           | verify writable volume
        BNE.B   DISPOSECCURSOR_CONT_4_CONT_CONT_ERR_2 | error -> exit
        MOVE.L  A0,-(SP)                        | save param block
        MOVE    D2,D0                           | old name length (high word)
        MOVE.L  A4,A0                           | old name ptr
        MOVEM.L (FSTemp8).w,D2/A4               | get new name info
        SWAP    D0                              | set up for _CmpString
        MOVE    D2,D0                           | new name length (low word)
        MOVE.L  A4,A1                           | new name ptr
        _CmpString                              | compare old and new names
        MOVE.L  (SP)+,A0                        | restore param block
        BEQ.B   DISPOSECCURSOR_CONT_4_CONT_3    | same name (case-only rename) ->
        BSR.W   FNDFILNAME_OK                   | look up new name in MFS directory
        BNE.B   DISPOSECCURSOR_CONT_4_CONT_2    | not found (good) ->
        MOVEQ.L #-0x30,D0                       | dupFNErr: name already exists
DISPOSECCURSOR_CONT_4_CONT_2:
        CMPI    #-0x2B,D0                       | fnfErr (good) returned?
        BNE.B   DISPOSECCURSOR_CONT_4_CONT_CONT_ERR_2 | any other err -> abort
DISPOSECCURSOR_CONT_4_CONT_3:
        BSR.W   FndFilName                      | locate source entry again
        BNE.B   DISPOSECCURSOR_CONT_4_CONT_CONT_ERR_2 | error -> exit
        MOVE.L  SP,A4                           | A4 = stack mark before push
        MOVE.L  A5,A3                           | A3 = source entry address
        BSR.W   HFSCATMOVE_CONT_2               | D0 = source entry size
DISPOSECCURSOR_CONT_4_CONT_4:
        MOVE    -0x2(A3,D0.W),-(SP)             | push word from A3[D0.W-2]
        SUBQ.W  #0x2,D0                         | step backward by word
        BGT.B   DISPOSECCURSOR_CONT_4_CONT_4    | loop until entry pushed
        BSR.W   HFSCATMOVE_CONT_3               | compact source slot
        MOVE.L  (FSTemp8).w,D2                  | recover new name length
        BSR.W   DISPOSECCURSOR_CONT_4           | find slot for renamed entry
        BNE.B   HFSCATMOVE_ERR_5                | no slot -> re-insert source
        MOVEQ.L #0x18,D0                        | D0 = 24 (@ $41A6)
| copy saved entry data back to new location
HFSCATMOVE_LOOP_2:
        MOVE    (SP)+,(A5)+                     | pop word into new entry
        DBRA    D0,HFSCATMOVE_LOOP_2            | loop for all 25 words
        MOVE.L  A4,SP                           | rebalance stack to mark
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
        BRA.B   DISPOSECCURSOR_CONT_4_CONT_CONT_ERR_2 | bra to parent-routine cleanup

| MFS Rename: entry moved - need to re-insert at new position
HFSCATMOVE_ERR_5:
        MOVE.B  0x32(SP),D2                     | D2 = original name length (saved)
        BSR.W   DISPOSECCURSOR_CONT_4           | find space for re-insertion
        BEQ.B   HFSCATMOVE_NO_5                 | found space ->
        MOVE.L  A4,SP                           | rebalance stack
        MOVEQ.L #-0x3B,D0                       | DirFulErr: directory full
        BRA.B   HFSCATMOVE_ERR_4                | return error
HFSCATMOVE_NO_5:
        MOVE    (SP)+,(A5)+                     | pop a word back into slot
        CMPA.L  SP,A4                           | stack restored to mark?
        BNE.B   HFSCATMOVE_NO_5                 | no, keep copying
        BSR.B   HFSCATMOVE_CONT_6               | update directory entry header
        MOVEQ.L #-0x21,D0                       | DirFulErr (tentative, may be cleared)
        BRA.B   HFSCATMOVE_ERR_4                | return tentative error
HFSCATMOVE_CONT_6:
        MOVE.L   18(A3),D2                      | D2 = file number (cnid)
        BSR.W   SRCHNODE_GT_CONT_CONT           | search FCBs for this file
        BSR.W   HFSE_NEXT_CONT                  | get next matching FCB
        BNE.B   HFSCATMOVE_ERR_6                | no more -> done
HFSCATMOVE_OK_7:
        MOVE    D0,fcbFlPos(A1,D1.W)            | update FCB extent record
        BSR.W   HFSE_ERR_9                      | advance to next FCB match
        BEQ.B   HFSCATMOVE_OK_7                 | more -> loop
HFSCATMOVE_ERR_6:
        RTS                                     | return from FCB-update helper
RENAME_ERR_5:
        CMPI    #-0x23,D0                       | fnNotOpenErr (no FCB needed)?
        BNE.B   HFSCATMOVE_ERR_4                | some other err -> exit
        TST     D2                              | new name specified?
        BNE.W   DISPOSECCURSOR_CONT_4_CONT_CONT_ERR | error ->
RENAME_NO_3:
        TST     D3                              | source name length zero?
        BEQ.B   HFSCATMOVE_ERR_4                | yes -> nothing to rename
        BSR.W   DTRMV1_NO_4                     | determine dest volume
        BNE.B   HFSCATMOVE_ERR_4                | error -> exit
        BSR.W   SETVOLINFO_HFS_CONT_3           | verify writable volume
        BNE.B   HFSCATMOVE_ERR_4                | error -> exit
        TST     vcbDrvNum(A2)                   | volume mounted?
        BEQ.B   HFSCATMOVE_ERR_4                | no -> exit
        ST      6(A2)                           | 6(A2) := -1 (true)
        LEA.L     vcbVN(A2),A2                  | A2 = &0x2C(A2)
        MOVE.L  28(A0),A1                       | A1 = ioMisc (new volume name)
        MOVE.B  (A1)+,D0                        | D0 = new name length byte
        SUBQ.B  #0x1,D0                         | decrement (zero-based length)
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
| SetFilType -- _SetFilType ($A043). Plus file_mgr_io.s 1159.
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
| SetFilLock -- _SetFilLock ($A041). Plus file_mgr.s body.
| Lock a file (set file-locked attribute).
SetFilLock:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        ST      (FLckUnlck).w                   | flag: lock (not unlock)
        BRA.B   RSTFILLOCK_CONT                 | merge with RstFilLock body

| ----------------------------------------------------------
| RstFilLock -- _RstFilLock ($A042). Plus file_mgr.s body.
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
| SetFileInfo -- _SetFileInfo ($A00D). Plus file_mgr_io.s 1230.
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
        RTS                                     | return
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
| GetFileInfo -- _GetFileInfo ($A00C). Plus file_mgr_io.s 1513.
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

| GetFPos -- _GetFPos ($A018): FUNCTION GetFPos (refNum: INTEGER; VAR filePos: LONGINT) OSErr;
| SetFPos -- _SetFPos ($A044): FUNCTION SetFPos (refNum: INTEGER; posMode: INTEGER; posOff: LONGINT) OSErr;
| GetFPos clears ioPosMode (fsAtMark) and ioReqCount, then falls into
| L_mFileRead which positions and reads zero bytes (returning the mark
| in IOPosOffset). SetFPos uses caller's ioPosMode but clears
| ioReqCount, so it falls into L_mFileRead from one instruction later.
GetFPos:
        CLR.B   (ioPosMode+1)(A0)               | ioPosMode low byte = 0 (fsAtMark)
SetFPos:
        CLR.L   ioReqCount(A0)                  | ioReqCount = 0

| FileRead (vFileRead)
L_mFileRead:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.W   RFNCall                         | resolve refNum -> A1, D1
        BNE.W   L_MFILEREAD_EXIT_3              | bad refNum -> exit
        BSR.B   SEEK                            | set FCB mark to ioPosOffset
        BNE.W   L_MFILEREAD_EXIT_2              | seek error -> exit
        NEG.L   D2                              | D2 = bytes-to-EOF (positive if at EOF)
        BMI.W   L_MFILEREAD_CONT_2              | past EOF -> 0 bytes path
        CMP.L   D2,D7                           | ioReqCount > bytes-to-EOF?
        BLE.B   L_MFILEREAD_CONT                | no -> use ioReqCount
        MOVE.L  D2,D7                           | yes -> clamp to bytes-to-EOF
L_MFILEREAD_CONT:
        TST.L   D7                              | any bytes to read?
        BEQ.B   L_MFILEREAD_DONE                | zero -> done (just position)
        MOVE    ioPosMode(A0),D2                | D2 = ioPosMode word
        LSR.W    #0x8,D2                        | shift newline-mode flag into bit 0
        BCS.W    L_MFILEREAD_CONT_3             | newline mode -> byte-scan path
        MOVE    D5,D2                           | current file position (low word)
        ANDI    #0x1FF,D2                       | check lower 9 bits for blk bndry read
        BEQ.B   RDPART_CONT                     | br if so (can read into place)

| RdPart: must read a partial block first
RDPART:
        BSR.W   HFSE_RDFILEBLK                  | RdFileBlk: read the data block
        BNE.B   L_MFILEREAD_EXIT                | block-read err -> exit
        BTST    #0x6,(ioPosMode+1)(A0)          | read verify only?
        SNE     D0                              | D0 = -1 if verify-only
        BSR.W   DOPART                          | DoPart: copy partial block to user buffer
        BNE.B   L_MFILEREAD_EXIT                | copy err -> exit
RDPART_CONT:
        MOVE.L  D7,D4                           | D4 = bytes still to read
        BEQ.B   L_MFILEREAD_DONE                | zero -> done
        CMPI.L  #0x200,D4                       | less than one block?
        BCS.B   RDPART                          | yes -> partial block path
        ANDI    #-0x200,D4                      | round D4 down to whole blocks
        BSR.W   LG2PHYS_NO                      | map logical -> physical block
        MOVE    D3,D4                           | user buffer (IOBuffer)
        BSR.W   FP68K_CONT_128                  | compute extent contig blocks
        BPL.B   RDPART_CONT_2                   | contiguous -> bulk read
        CMP     D4,D3                           | contiguous count > requested?
        BCS.B   RDPART_CONT_2                   | yes -> use it
        CMP     D0,D3                           | below physical extent end?
        BCC.B   RDPART_CONT_2                   | no -> use partial bulk
        MOVE.L  D6,(FSTemp4).w                  | stash D6 across split read
        BSR.W   FILEOPEN_CONT_6_CONT_CONT_4     | issue extent-bounded read
        BNE.B   L_MFILEREAD_EXIT                | err -> exit
        MOVE.L  (FSTemp4).w,D6                  | restore D6
RDPART_CONT_2:
        MOVE    D4,D3                           | D3 = blocks for this read
        MOVE.L  ioBuffer(A0),A5                 | A5 = user buffer base
        ADDA.L  ioActCount(A0),A5               | A5 += bytes already transferred
        BSR.W   FILEOPEN_CONT_6_CONT_CONT       | issue read into user buffer
        BNE.B   L_MFILEREAD_EXIT                | err -> exit
        BSR.W   FILEWRITE_CONT_2                | advance D5/D7/ioActCount
        BRA.B   RDPART_CONT                     | loop until D7 = 0

| L_MFILEREAD_DONE - wait for one VBL tick, then loop back to smooth and refill
L_MFILEREAD_DONE:
        MOVEQ.L #0x0,D0                         | return noErr
L_MFILEREAD_EXIT:
        TST     D0                              | other error?
        BNE.B   L_MFILEREAD_EXIT_2              | br if so
        MOVE.L  ioActCount(A0),D2               | if actual count != requested count
        CMP.L   ioReqCount(A0),D2               | (IOActCount vs IOReqCount)
        BEQ.B   L_MFILEREAD_EXIT_2              | (br if equal, no EOF)
L_MFILEREAD_CONT_2:
        MOVEQ.L #-0x27,D0                       | D0 = eofErr (-39)
L_MFILEREAD_EXIT_2:
        MOVE.L  D5,fcbCrPs(A1,D1.W)             | store cumulative byte offset into param
        MOVE.L  D5,ioPosOffset(A0)              | return new file position
L_MFILEREAD_EXIT_3:
        BRA.W   FSQUEUE_DONE                    | return via FSQueue done
L_MFILEREAD_CONT_3:
        BSR.W   HFSE_RDFILEBLK                  | read one file data block
        BNE.B   L_MFILEREAD_EXIT                | block-read err -> exit
        MOVE.L  D5,D2                           | D2 = current position
        ANDI    #0x1FF,D2                       | D2 = offset within block
        MOVE.L  ioBuffer(A0),A3                 | A3 = user buffer base
        MOVE.L  ioActCount(A0),D4               | D4 = bytes already transferred

| newline byte-by-byte scan loop
L_MFILEREAD_LOOP:
        MOVE.B  0(A5,D2.W),D0                   | get byte from the buffer
        MOVE.B  D0,0(A3,D4.L)                   | put it into user's area
        ADDQ.L  #0x1,ioActCount(A0)             | actually read another byte (IOActCount)
        ADDQ.L  #0x1,D4                         | incr destination byte offset
        ADDQ.W  #0x1,D2                         | incr source byte offset
        ADDQ.L  #0x1,D5                         | incr current position
        CMP.B   ioPosMode(A0),D0                | is it the EOL character?
        BNE.B   L_MFILEREAD_NO_2                | no ->
        MOVEQ.L #0x0,D0                         | no error, we found EOL
        BRA.B   L_MFILEREAD_EXIT_2              | newline found -> success exit
L_MFILEREAD_NO_2:
        SUBQ.L  #0x1,D7                         | decr byte count
        BEQ.B   L_MFILEREAD_DONE                | count exhausted -> done
        CMP     D6,D2                           | reached end of buffer?
        BCS.B   L_MFILEREAD_LOOP                | loop if not
        BRA.B   L_MFILEREAD_CONT_3              | need next block from disk
| ----------------------------------------------------------
| L_MFILEREAD_LOOP_NO_CONT -- pick buffer ptr for FCB I/O.
| Push FCB.fcbExtBuf; if non-nil use it, else use VCB default
| buffer. On exit A5 = chosen buffer, (SP) unchanged above.
| ----------------------------------------------------------
L_MFILEREAD_LOOP_NO_CONT:
        MOVE.L  fcbBfAdr(A1,D1.W),-(SP)         | push FCB.fcbExtBuf
        BNE.B   HFSE_GETBUF_A5_RET              | non-nil -> use FCB buffer
        MOVE.L  vcbBufAdr(A2),(SP)              | nil -> use VCB default buffer
HFSE_GETBUF_A5_RET:
        MOVEA.L (SP)+,A5                        | A5 = chosen buffer ptr
        RTS                                     | return from buffer-pick helper

| ----------------------------------------------------------
| HFSE_RDFILEBLK -- read one file data block.
| Called from RDPART ($44C8) via BSR.W to this address.
| Uses FCB extent buffer (via the helper above), then falls into
| the common block-read tail at HFSE_RDFILEBLK_CONT.
| ----------------------------------------------------------
HFSE_RDFILEBLK:
        MOVEQ.L #0x1,D4                         | D4 = 1 (read one block)
        BSR.W   LG2PHYS_NO                      | map logical -> physical block
        BSR.B   L_MFILEREAD_LOOP_NO_CONT        | A5 = FCB extent buffer
        BRA.B   HFSE_RDFILEBLK_CONT             | -> common block-read tail
HFSE_READ_VBM_BLOCK:                            | entry from file_mgr.s HFSE_NO/HFSE_OK
        MOVEA.L vcbBufAdr(A2),A5                | A5 = VCB default buffer
HFSE_RDFILEBLK_CONT:
        MOVEQ.L #0x2,D6                         | D6 = 2 (block-size shift base)
        ASL.L   #0x8,D6                         | D6 = 0x200 (512-byte block size)
        MOVEA.L (SP)+,A6                        | A6 = requested block number
        BSR.W   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT | do block read @ $4624

        BSR.W   SRCHNODE_GT_CONT_CONT_2         | D0 = current block tag
        CMP     D0,D3                           | block tag matches request?
        BNE.B   L_MFILEREAD_LOOP_NO_CONT_5      | no -> need real I/O
        MOVEQ.L #0x0,D0                         | buffer hit -> noErr
L_MFILEREAD_LOOP_NO_CONT_2:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT | set up Disk Mgr param block
L_MFILEREAD_LOOP_NO_CONT_3:
        TST     D0                              | any error?
        BEQ.B   L_MFILEREAD_LOOP_NO_CONT_4      | no -> return success
        MOVEQ.L #-0x24,D0                       | D0 = ioErr (-36)
L_MFILEREAD_LOOP_NO_CONT_4:
        JMP     (A6)                            | return via saved A6 PC
L_MFILEREAD_LOOP_NO_CONT_5:
        BCLR    #0x7,-2(A5)                     | buffer dirty? (clear dirty bit)
        BEQ.B   L_MFILEREAD_LOOP_NO_CONT_7      | clean -> just read in
        MOVE    D0,D3                           | D3 = saved tag for reuse
        LEA     L_MFILEREAD_LOOP_NO_CONT_6(PC),A1 | A1 = "after-flush" PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2 | build write param block
        MOVEM.L -10(A5),D0-D1                   | D0/D1 = stored block tag
        MOVEM.L D0-D1,(BufTgFNum).w             | stamp BufTgFNum/BufTgFFlg
        _WriteAsync                             | flush buffer to disk
        RTS                                     | return from flush request
L_MFILEREAD_LOOP_NO_CONT_6:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT | post-flush continuation
        BNE.B   L_MFILEREAD_LOOP_NO_CONT_3      | flush err -> propagate
L_MFILEREAD_LOOP_NO_CONT_7:
        LEA.L     (Params).w,A0                 | A0 = global Params block
        LEA     FILEOPEN_CONT_6(PC),A1          | A1 = "after-read" PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2 | build read param block
        _ReadAsync                              | issue async read
        RTS                                     | return from read request
FILEOPEN_CONT_6:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT | post-read continuation
        BEQ.B   FILEOPEN_CONT_6_CONT            | ok -> save tag from buffer
        MOVEQ.L #0x0,D3                         | err -> mark buffer empty
FILEOPEN_CONT_6_CONT:
        MOVE    D3,-2(A5)                       | buffer header := tag (clean)
        MOVE.L  (BufTgFNum).w,-10(A5)           | stash file number in buffer
        MOVE.L  (BufTgFFlg).w,-6(A5)            | stash file flags in buffer
        BRA.B   L_MFILEREAD_LOOP_NO_CONT_3      | join error-test path
FILEOPEN_CONT_6_CONT_CONT:
        MOVE.L  (SP)+,A6                        | A6 = saved return PC
        MOVE.B  (ioPosMode+1)(A0),D0            | D0 = ioPosMode low byte
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT | set up D2/D3/A1 for I/O
        LSL.B   #0x1,D0                         | shift verify-flag into N
        BPL.B   FILEOPEN_CONT_6_CONT_CONT_2     | not verify -> normal read
        BSET    #0x6,(ioPosMode+1)(A0)          | flag verify-only mode
FILEOPEN_CONT_6_CONT_CONT_2:
        LEA     L_MFILEREAD_LOOP_NO_CONT_2(PC),A1 | A1 = "after-read" PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2 | build read param block
        _ReadAsync                              | issue async read
        RTS                                     | return
FILEOPEN_CONT_6_CONT_CONT_2_CONT:
        MOVEM.L (HFSVars_HFSStkTop).w,D1-A6     | restore registers from HFSStkTop
        RTS                                     | return
FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT:
        MOVEM.L D1-A6,(HFSVars_HFSStkTop).w     | stash registers to HFSStkTop
        LEA.L     (Params).w,A0                 | A0 = global Params block
        MOVE    vcbDRefNum(A2),ioRefNum(A0)     | ioRefNum = vcb driver refNum
        MOVE.L  A5,ioBuffer(A0)                 | ioBuffer = cache block
        MOVE.L  D6,ioReqCount(A0)               | ioReqCount = transfer size
        MOVE    #0x1,ioPosMode(A0)              | ioPosMode = fsFromStart
        RTS                                     | return; param block ready
FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2:
        MOVE.L  A1,ioCompletion(A0)             | ioCompletion = completion routine
        MOVEQ.L #0x0,D6                         | D6 = 0 (clear high bytes)
        MOVE    D3,D6                           | D6 = block number (low word)
        ASL.L   #0x1,D6                         | D6 = block * 2
        ASL.L   #0x8,D6                         | D6 = block * 512 = byte offset
        MOVE.L  D6,ioPosOffset(A0)              | ioPosOffset := byte offset
        MOVE    vcbDrvNum(A2),ioVRefNum(A0)     | ioVRefNum := drive number
        RTS                                     | return; pb fully set
FILEOPEN_CONT_6_CONT_CONT_3:
        MOVE.L  vcbBufAdr(A2),A5                | A5 = volume default buffer
FILEOPEN_CONT_6_CONT_CONT_4:
        MOVEQ.L #0x2,D6                         | D6 = 2 (block-size shift base)
        ASL.L   #0x8,D6                         | D6 = 0x200 (one block)
        MOVE.L  (SP)+,A6                        | A6 = saved return PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT | set up Disk Mgr param block
        MOVEM.L -10(A5),D0-D1                   | D0/D1 = stored block tag
        MOVEM.L D0-D1,(BufTgFNum).w             | stamp BufTgFNum/BufTgFFlg
        LEA     FILE_WRITE_TAG_PROC(PC),A1      | A1 = "after-write" PC
FILEOPEN_CONT_6_CONT_CONT_5:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT_2 | finish param block
        _WriteAsync                             | flush block to disk
        RTS                                     | return from write request

| ----------------------------------------------------------
| FILE_WRITE_TAG_PROC -- async write completion / tag proc
| Used as a code-pointer hook by FILEOPEN_CONT_6_CONT_CONT_4 (line
| ~800) which loads its address into A1 before calling _WriteAsync.
| NOT _UseResFile -- that's in control_mgr.s. Earlier mass-rename
| pass mislabeled this as UseResFile.
FILE_WRITE_TAG_PROC:
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT | restore caller's registers
        MOVE    D3,-2(A5)                       | stamp tag word into buffer
        BRA.W   L_MFILEREAD_LOOP_NO_CONT_3      | join error-test path
PreRdFileBlk:                                   | prep cache tags + read block
        MOVE.L  (SP)+,A6                        | A6 = saved return PC
        BSR.B   FILEOPEN_CONT_6_CONT_CONT_2_CONT_CONT | set up Disk Mgr param block
        MOVE.L  fcbFlNm(A1,D1.W),(BufTgFNum).w  | BufTgFNum := FCB file number
        MOVE    fcbFlags(A1,D1.W),(BufTgFFlg).w | BufTgFFlg := FCB flags
        MOVE.L  D5,D0                           | D0 = current byte position
        LSR.L   #0x8,D0                         | / 256
        LSR.L   #0x1,D0                         | / 2 = block number within file
        MOVE    D0,(BufTgFBkNum).w              | BufTgFBkNum := block number
        BSR.W   L_MFILEREAD_LOOP_NO_CONT        | A5 = chosen buffer
        BSR.W   SRCHNODE_GT_CONT_CONT_2         | D0 = current buffer tag
        CMP     D3,D0                           | matches request?
        BCS.B   USERESFILE_CONT                 | below request -> reuse buffer
        LSR.L   #0x8,D6                         | D6 = read length / 256
        LSR.L   #0x1,D6                         | D6 = blocks in this read
        ADD     D3,D6                           | D6 = end-block of this read
        CMP     D6,D0                           | buffer tag past read end?
        BCC.B   USERESFILE_CONT                 | yes -> reuse buffer
        CLR     -2(A5)                          | invalidate buffer (mismatch)
USERESFILE_CONT:
        LEA     L_MFILEREAD_LOOP_NO_CONT_2(PC),A1 | A1 = "after-read" PC
        BRA.B   FILEOPEN_CONT_6_CONT_CONT_5     | issue async read

| ----------------------------------------------------------
| FileWrite -- _Write ($A003) for file paths. Plus file_mgr_io.s 2234.
| Pascal: function FileWrite(refNum: INTEGER; buffPtr: Ptr;
| count: LongInt; mode: INTEGER): OSErr;
| Writes data from a buffer to an open file. Device Manager's
| Write trap entry in device_mgr.s forwards here (JMP FileWrite(PC)
| at device_mgr.s:376) when the refnum is a positive file refNum
| rather than a negative driver refNum. Sequence: FSQUEUE_SETUP,
| TstMod (modification check), Seek (position file), then either
| same-length or extend-and-write paths.
FileWrite:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.W   TstMod                          | TstMod: caller is allowed to modify?
        BNE.W   FILEWRITE_NO_3                  | denied -> error
        BSR.W   SEEK                            | Seek: position and set up D5, D7
        BNE.B   FILEWRITE_CONT                  | error positioning ->
        TST.L   D2                              | positioned past EOF?
        BMI.B   FILEWRITE_NO                    | yes ->
        ADD.L   D2,D5                           | extend added to current position
FILEWRITE_NO:
        MOVE.L  D5,D4                           | D4 = file position
        ADD.L   D7,D4                           | D4 = end-of-write position
        CMP.L   fcbEOF(A1,D1.W),D4              | past current logical EOF?
        BLS.B   SAMELEN                         | no -> overwrite path
        SUB.L   fcbPLen(A1,D1.W),D4             | D4 -= fcbPLen(A1,D1.W)
        BLS.B   FILEWRITE_NO_2                  | fits in physical -> just bump EOF
        BSR.W   LG2PHYS_NO_3                    | allocate more extents
FILEWRITE_CONT:
        BNE.B   FILEWRITE_EXIT                  | err -> exit
FILEWRITE_NO_2:
        MOVE.L  D5,D4                           | D4 = position
        ADD.L   D7,D4                           | actually transferred this many more (IOActCount)
        MOVE.L  D4,fcbEOF(A1,D1.W)              | fcbEOF := new logical EOF
SAMELEN:
        MOVE    D5,D0                           | current file position
        ANDI    #0x1FF,D0                       | get index within block
        BEQ.B   WRMAIN                          | on block boundary -> bulk write
WRPART:
        BSR.W   HFSE_RDFILEBLK                  | read the block
        BNE.B   FILEWRITE_ERR                   | read err -> exit
        MOVEQ.L #0x1,D0                         | D0=1 for write
        BSR.B   DOPART                          | merge user data into buffer
        BSET    #0x7,-2(A5)                     | flag buffer dirty
WRMAIN:
        MOVE.L  D7,D4                           | D4 = bytes still to write
        BEQ.B   FILEWRITE_DONE                  | zero -> done
        CMPI.L  #0x200,D4                       | less than one block?
        BCS.B   WRPART                          | yes -> partial write
        ANDI    #-0x200,D4                      | round down to whole blocks
        BSR.W   LG2PHYS_NO                      | map logical -> physical block
        MOVE.L  ioBuffer(A0),A5                 | A5 = user buffer base
        ADDA.L  ioActCount(A0),A5               | A5 += ioActCount offset
        BSR.W   PreRdFileBlk                    | read block + update tags
        BNE.B   FILEWRITE_ERR                   | err -> exit
        BSR.B   FILEWRITE_CONT_2                | advance D5/D7/ioActCount
        BRA.B   WRMAIN                          | loop until D7 = 0
FILEWRITE_DONE:
        MOVEQ.L #0x0,D0                         | return noErr
FILEWRITE_ERR:
        BSR.W   AdjEof                          | MFSDealloc: free remaining extent chain
        MOVE.L  D5,fcbCrPs(A1,D1.W)             | FCB current mark = D5
FILEWRITE_EXIT:
        MOVE.L  fcbCrPs(A1,D1.W),ioPosOffset(A0) | copy mark back to IOParam.ioPosOffset
FILEWRITE_NO_3:
        BRA.W   FSQUEUE_DONE                    | -> common exit ($3954)

| ----------------------------------------------------------
| FILEWRITE_CONT_2 - UpdteCntPos: update byte count, actual count, and file position
| Called during boot.
FILEWRITE_CONT_2:
        SUB.L   D6,D7                           | adjust for number of bytes read/written
        ADD.L   D6,ioActCount(A0)               | actually transferred this many more (IOActCount)
        ADD.L   D6,D5                           | update current position
        RTS                                     | return updated counts and position
DOPART:
        MOVE.L  D5,D2                           | current file position
        ANDI    #0x1FF,D2                       | get index within block
        SUB     D2,D6                           | D6 = bytes remaining in this block
        CMP.L   D6,D7                           | need more than one block's worth?
        BCC.B   FILEWRITE_OK                    | no, D6 is fine
        MOVE.L  D7,D6                           | yes, limit to bytes remaining
FILEWRITE_OK:
        MOVE.L  ioBuffer(A0),A3                 | user buffer (IOBuffer)
        ADDA.L  ioActCount(A0),A3               | + IOActCount = target
        BSR.B   FILEWRITE_CONT_2                | UpdteCntPos: update D7, D5, IOActCount
        MOVEM.L A0-A1,-(SP)                     | save regs
        MOVE.L  A3,A0                           | source = user buffer
        MOVE.L  A5,A1                           | dest = cache buffer
        ADDA.W  D2,A1                           | + index into block
        TST.B   D0                              | D0 > 0? (write)
        BGT.B   FILEWRITE_OK_2                  | yes, user->cache ->
        BMI.B   FILEWRITE_CONT_3                | verify (-1) -> compare path
        EXG     A0,A1                           | read (0) -> swap to cache->user
FILEWRITE_OK_2:
        MOVE.L  D6,D0                           | D0 = byte count
        _BlockMove                              | copy D0 bytes A0->A1
FILEWRITE_ERR_2:
        MOVEQ.L #0x0,D0                         | return noErr
FILEWRITE_EXIT_2:
        MOVEM.L (SP)+,A0-A1                     | restore A0/A1
        RTS                                     | return from DOPART
FILEWRITE_CONT_3:
        MOVEQ.L #-0x24,D0                       | D0 = ioErr (presumed for verify)
FILEWRITE_LOOP:
        CMPM.B  (A0)+,(A1)+                     | compare user vs cache byte
        BNE.B   FILEWRITE_EXIT_2                | mismatch -> verify error
        SUBQ.W  #0x1,D6                         | decrement byte count
        BNE.B   FILEWRITE_LOOP                  | loop until done
        BRA.B   FILEWRITE_ERR_2                 | verify match -> noErr

| ----------------------------------------------------------
| FlushFile -- _FlushFile ($A045). Plus file_mgr_io.s 2423.
| Pascal: function FlushFile(refNum: INTEGER): OSErr;
| Writes any pending data and FCB updates for an open file to
| disk without closing the file. Sets FlushOnly := -1 (true) so
| the common path skips the FCB-disposal step.
FlushFile:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        ST      (FlushOnly).w                   | FlushOnly := -1 (flush only)
        BRA.B   FILECLOSE_CONT                  | -> common flush/close path

| ----------------------------------------------------------
| FileClose -- _Close ($A001) for file paths. Plus file_mgr_io.s 2428.
| Pascal: function FileClose(refNum: INTEGER): OSErr;
| Closes an open file: flushes pending data, releases the FCB
| slot. Sets FlushOnly := 0 so the common path runs the full
| close (flush + dispose). Device Manager's Close trap entry in
| device_mgr.s also forwards file-refnum requests here.
FileClose:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        CLR.B   (FlushOnly).w                   | FlushOnly := 0 (close, not just flush)
FILECLOSE_CONT:
        BSR.W   RFNCall                         | RfNCall: is refnum for a valid open file?
        BEQ.B   FILECLOSE_CONT_2                | br if valid
        CMPI    #-0x35,D0                       | volume offline? (VolOffLinErr)
        BNE.B   FILECLOSE_ERR                   | no, some other error -> skip flush
FILECLOSE_CONT_2:
        BSR.B   FILECLOSE_NO_3                  | flush FCBs on offline volume
FILECLOSE_ERR:
        BRA.W    FSQUEUE_DONE                   | -> common exit
FP68K_CONT_128:
        BSR.W   L_MFILEREAD_LOOP_NO_CONT        | A5 = chosen buffer
        MOVE    -2(A5),D3                       | D3 = block tag from buffer
        BCLR    #0xF,D3                         | strip dirty-bit, leave block num
        RTS                                     | return; D3 = clean block num
FILECLOSE_NO_3:
        MOVE.L  (SP)+,A4                        | A4 = saved return PC
        BCLR    #0x7,fcbFlags(A1,D1.W)          | FCB dirty? (clear & test)
        BEQ.B   FP68K_CONT_128_CONT_3           | clean -> skip flush, dispose FCB
        BSR.B   FP68K_CONT_128                  | get current buffer block num
        BPL.B   FP68K_CONT_128_CONT_2           | buffer matches FCB -> just write dir
        BSR.W   FILEOPEN_CONT_6_CONT_CONT_4     | flush dirty buffer to disk
        BNE.B   FP68K_CONT_128_LOOP_CONT        | flush err -> exit
FP68K_CONT_128_CONT_2:
        MOVE    fcbFlPos(A1,D1.W),D3            | D3 = FCB.fcbCtlgBlk or similar
        BSR.W   HFSE_READ_VBM_BLOCK             | read directory block
        BNE.B   FP68K_CONT_128_LOOP_CONT        | error ->
FP68K_CONT_128_SCAN:                            | directory entry scan loop top
        MOVEQ.L #0x0,D0                         | D0 = 0 (offset within block)
        MOVE.L  fcbFlNm(A1,D1.W),D3             | D3 = FCB.fcbFlNm (target file number)
FILECLOSE_CONT_5:
        CMP.L   0x12(A5,D0.W),D3                | match?
        BEQ.B   FILECLOSE_OK_4                  | yes ->
        BSR.W   CREATE_NEXT                     | advance D0 to next directory entry
        BCS.B   FILECLOSE_CONT_5                | more entries -> retry compare
        MOVEQ.L #-0x2B,D0                       | D0 = FNFErr (file not found)
        BRA.B   FP68K_CONT_128_LOOP_CONT        | return error via A4
FILECLOSE_OK_4:
        LEA.L     0x16(A5,D0.W),A3              | A3 = &directory-entry[D0+0x16]
        BSR.B   FP68K_CONT_128_LOOP_CONT_BODY   | process found entry
        MOVE.L  (Time).w,0x2E(A5,D0.W)          | timestamp = current time
        BSET    #0x7,-2(A5)                     | flag dir block as dirty
FP68K_CONT_128_CONT_3:
        TST.B   (FlushOnly).w                   | flush only?
        BNE.B   FP68K_CONT_128_LOOP_OK          | yes, keep FCB ->
        LEA.L     fcbFlNm(A1,D1.W),A3           | point to FCB entry
        MOVEQ.L #0xE,D0                         | D0 = 14 (clear 15 words)
FP68K_CONT_128_LOOP:
        CLR     (A3)+                           | clear one FCB word
        DBRA    D0,FP68K_CONT_128_LOOP          | loop 15 words
FP68K_CONT_128_LOOP_OK:
        MOVEQ.L #0x0,D0                         | return noErr
FP68K_CONT_128_LOOP_CONT:
        JMP     (A4)                            | return via saved A4
FP68K_CONT_128_LOOP_CONT_BODY:                  | @ $4824 (directory-entry handler)

| ----------------------------------------------------------
| FILECLOSE_CONT_6
| Called during boot.
| FILECLOSE_CONT_6/UpdFlNtry: update file lengths in catalog from FCB
| A3 = ptr to file length fields in catalog, (A1,D1) = FCB
FILECLOSE_CONT_6:
        MOVE.L  A4,-(SP)                        | save A4
        LEA.L   fcbFlags(A1,D1.W),A4            | A4 = FCB flags (FCBMdRByt)
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
| _GetEOF ($A011): get logical end of file
| Returns FCB.fcbEOF in ioMisc (offset 28).
GetEOF:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   RFNCall                         | RfNCall: is refnum for a valid open file?
        BNE.B   GETEOF_NO                       | br if not
        MOVE.L  fcbEOF(A1,D1.W),28(A0)          | return the logical EOF (FCBEOF -> IOLEOF)
GETEOF_NO:
        BRA.W   FSQUEUE_DONE                    | return via FSQueue done
RFNCall:
        MOVE.L  (FCBSPtr).w,A1                  | A1 = FCB table base
        CLR.L   D1                              | D1 = 0 (clear high bytes)
        MOVE    ioRefNum(A0),D1                 | D1 = refNum from param block
        MOVE.L  D1,D2                           | D2 = refNum (working copy)
        MOVEQ.L #-0x33,D0                       | D0 = rfNumErr (-51) preset
        DIVU    #0x1E,D2                        | D2 = D2 /u #0x1E
        SWAP    D2                              | D2 high word = remainder
        SUBQ.W  #0x2,D2                         | D2 -= 0x2 (remainder -> FCB index)
        BNE.B   RFNCALL_CONT                    | non-zero -> misaligned refnum -> rfNumErr
        CMP     (A1),D1                         | D1 <= (A1) = FCBS byte count?
        BCC.B   RFNCALL_CONT                    | no (D1 too large) -> rfNumErr
        MOVEQ.L #-0x26,D0                       | D0 = rfNumErr (if FCB turns out closed)
        MOVE.L  fcbFlNm(A1,D1.W),D2             | D2 = FCB.fcbFlNm (file number; 0 = closed)
        BEQ.B   RFNCALL_CONT                    | FCB closed -> return rfNumErr
        MOVEA.L fcbVPtr(A1,D1.W),A2             | A2 = FCB.fcbVPtr (VCB)
        BSR.W   FNDFILNAME_CONT_4               | validate + load helper
RFNCALL_CONT:
        TST.W   D0                              | Z reflects noErr / error
        RTS                                     | return; D0 = result

| ----------------------------------------------------------
| TstMod: test if we may modify this file
| Called during boot.
TstMod:
        BSR.B   RFNCall                         | validate refnum -> A1, D1
        BNE.B   TSTMOD_EXIT                     | exit on errors
        MOVEQ.L #-0x3D,D0                       | assume wrPermErr
        BTST    #0x0,fcbFlags(A1,D1.W)          | write permission? (FCBWriteBit)
        BEQ.B   TSTMOD_EXIT                     | no, can't modify ->
        BSR.W   SETVOLINFO_HFS_CONT_3           | check volume write protect
TSTMOD_EXIT:
        TST     D0                              | set CCR from D0
        RTS                                     | return; D0 = err code

| ----------------------------------------------------------
| _Allocate ($A010): pre-allocate disk space for a file
| Plus 1986 added zero-request and free-blocks early-out checks;
| classic 1984 always calls FileAlloc.
Allocate:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   TstMod                          | verify refNum + write perms
        BNE.B   ALLOCATE_ERR                    | denied -> exit
        MOVE.L  ioReqCount(A0),D4               | D4 = ioReqCount (bytes requested)
        MOVEQ.L #0x0,D0                         | D0 = 0 (no flags)
        BSR.W   LG2PHYS_CONT_2                  | allocate D4 bytes -> D6
        BNE.B   ALLOCATE_ERR                    | err -> exit
        MOVE.L  D6,ioActCount(A0)               | return actual bytes allocated (ioActCount)
        BSR.W   AdjEof                          | AdjEOF: adjust other FCBs
        MOVEQ.L #-0x22,D0                       | DskFulErr (in case partial alloc)
        CMP.L   ioReqCount(A0),D6               | got full request?
        BCS.B   ALLOCATE_ERR                    | unsigned less ->
        MOVEQ.L #0x0,D0                         | dupFNErr
ALLOCATE_ERR:
        BRA.W   FSQUEUE_DONE                    | -> noErr

| ----------------------------------------------------------
| _SetEOF ($A012): set logical end-of-file
SetEOF:
        BSR.W   FSQUEUE_SETUP                   | FSQueue: wait our turn
        BSR.B   TstMod                          | verify refnum + write perms
        BNE.B   SETEOF_EXIT                     | test failed -> exit via common tail
        MOVE.L  28(A0),D7                       | D7 = ioMisc (new EOF)
        MOVE.L  D7,D4                           | D4 = new EOF (work copy)
        SUB.L   fcbPLen(A1,D1.W),D4             | D4 -= fcbPLen(A1,D1.W)
        BCS.B   ADJEOF_NO                       | shrinking -> truncate
        BHI.B   SETEOF_CONT_3                   | branch if > (unsigned)
SETEOF_NO:
        MOVEQ.L #0x0,D0                         | D0 = 0 (noErr)
        MOVE.L  D7,fcbEOF(A1,D1.W)              | FCB.fcbEOF = requested EOF
        CMP.L   fcbCrPs(A1,D1.W),D7             | mark > new EOF?
        BCC.B   SETEOF_OK_2                     | no -> skip mark update
        MOVE.L  D7,fcbCrPs(A1,D1.W)             | yes: clamp FCB current mark to new EOF
SETEOF_OK_2:
        BSR.B   AdjEof                          | adjust physical EOF to match
SETEOF_EXIT:
        BRA.W   FSQUEUE_DONE                    | -> common FS exit

| ----------------------------------------------------------
| ADJEOF_NO
| Called during boot.
ADJEOF_NO:
        MOVEQ.L #0x0,D6                         | dupFNErr
        MOVE    fcbSBlk(A1,D1.W),D3             | D3 = start alloc block (FCBStBlk)
        MOVE.L  vcbAlBlkSiz(A2),D2              | D2 = alloc block size
        MOVE.L  D7,D4                           | D4 = new LEOF
        BNE.B   ADJEOF_CONT_2                   | nonzero, walk chain ->
        CLR     fcbSBlk(A1,D1.W)                | LEOF=0: clear start block (FCBStBlk)
        BRA.B   ADJEOF_CONT_3                   | free entire extent chain
ADJEOF_CONT:
        MOVE.W   D5,D3                          | D3 = next alloc block in chain
ADJEOF_CONT_2:
        ADD.L   D2,D6                           | D6 += alloc-block size (running total)
        BSR.W   LG2PHYS_NEXT_2                  | walk to next extent in MFS map
        SUB.L   D2,D4                           | subtract one block-size from D4
        BHI.B   ADJEOF_CONT                     | branch if > (unsigned)
        CMP.L   fcbPLen(A1,D1.W),D6             | reached old physical EOF?
        BCC.B   SETEOF_NO                       | yes -> nothing to free
        MOVE    D5,-(SP)                        | D3 = next alloc block start
        MOVEQ.L #0x1,D5                         | D5 = 1 (mark "free chain")
        BSR.W   LG2PHYS_CONT_9                  | free extents past D6
        MOVE    (SP)+,D3                        | restore D3
ADJEOF_CONT_3:
        BSR.W   LG2PHYS_CONT_10                 | free remaining extents
        MOVE.L  D6,fcbPLen(A1,D1.W)             | fcbPLen := new physical length
        BRA.B   SETEOF_NO                       | finalize (set logical EOF)
SETEOF_CONT_3:
        BSR.W   LG2PHYS_NO_3                    | extend file to new EOF
        BNE.B   SETEOF_EXIT                     | LG2PHYS_NO_3 error -> exit via common tail
        BRA.B   SETEOF_NO                       | finalize EOF
AdjEof:
        MOVEM.L D0-D6/A0-A2,-(SP)               | save D0-D6/A0-A2
        ADDA.W  D1,A1                           | A1 = current FCB
        MOVE.L  (A1)+,D2                        | D2 = file number; A1 -> flags
        BSET    #0x7,(A1)                       | set fcbDirty bit
        MOVE    (A1),D0                         | D0 = FCB flags (incl fork bit)
        MOVEM.L (A1)+,D3-D6/A2                  | (A1)+ -> D3-D6/A2
        MOVE    D0,D6                           | D6 = our FCB flags
        BSR.W   HFSE_NEXT_CONT                  | search first FCB matching this fileID
        BNE.B   ADJEOF_FOUND_2                  | no more FCBs -> exit
ADJEOF_FOUND:
        LEA.L     fcbFlags(A1,D1.W),A0          | point to this FCB's flags
        MOVE    (A0)+,D0                        | get this FCB's flags
        EOR     D6,D0                           | D0 = bits that differ from us
        LSL     #0x7,D0                         | resource fork bit in carry
        BCS.B   ADJEOF_SKIP                     | fork bit differs -> skip update
        MOVE    D3,(A0)+                        | update StBlk
        MOVE.L  D4,(A0)+                        | update LEOF
        MOVE.L  D5,(A0)+                        | update PEOF
ADJEOF_SKIP:
        BSR.W   HFSE_ERR_9                      | advance to next FCB match
        BEQ.B   ADJEOF_FOUND                    | another match -> update it too
ADJEOF_FOUND_2:
        MOVEM.L (SP)+,D0-D6/A0-A2               | restore D0-D6/A0-A2
        RTS                                     | return from AdjEof

| ----------------------------------------------------------
| LG2PHYS_NO - MFS Lg2Phys: simple linear extent mapping
| Called during boot.
LG2PHYS_NO:
        MOVEM.L D1-D2/D4-D5/D7,-(SP)            | save registers
        MOVE.L  vcbAlBlkSiz(A2),D7              | D7 = allocation block size
        MOVE    fcbSBlk(A1,D1.W),D3             | D3 = start alloc block from FCB
        ADD.L   D5,D4                           | D4 = end position (pos + max bytes - 1)
        SUBQ.L  #0x1,D4                         | adjust to last byte in range
        MOVEQ.L #0x9,D1                         | shift count for /512
        MOVEQ.L #0x0,D6                         | D6 = bytes mapped so far
        LSR.L   D1,D4                           | D4 = end block (in 512-byte blocks)
        LSR.L   D1,D7                           | D7 = alloc block size in 512-byte blocks
        MOVE.L  D5,D2                           | D2 = start block
        LSR.L   D1,D2                           | convert bytes to 512-byte blocks
        BRA.B   LG2PHYS_CONT                    | enter walk loop
LG2PHYS_NEXT:
        BSR.B   LG2PHYS_NEXT_2                  | walk to next alloc block
        MOVE    D5,D3                           | D3 = next alloc block start
        SUB     D7,D4                           | adjust end/start for this extent
        SUB     D7,D2                           | blocks remaining in this extent
LG2PHYS_CONT:
        CMP     D7,D2                           | start block within this extent?
        BCC.B   LG2PHYS_NEXT                    | no, try next extent
        MOVE    D3,D0                           | alloc block start
        SUBQ.W  #0x2,D0                         | - 2 (alloc blocks start at 2)
        MULU    D7,D0                           | D0 = block * blocks-per-alloc
        ADD     D2,D0                           | + offset within alloc block
        ADD     vcbAlBlSt(A2),D0                | + volume alloc block start
        MOVE    D0,-(SP)                        | stash starting block on stack
| count contiguous blocks from this extent
LG2PHYS_OK:
        MOVE    D7,D0                           | blocks remaining in this extent
        SUB     D2,D0                           | - offset into extent
        ADD     D0,D6                           | add to contiguous block count
        SUB     D0,D4                           | subtract from remaining request
        BMI.B   LG2PHYS_DONE                    | done if covered all requested blocks
        BSR.B   LG2PHYS_NEXT_2                  | walk to next extent in chain
        MOVEQ.L #0x0,D2                         | start at beginning of next extent
        ADDQ.W  #0x1,D3                         | check if next extent is contiguous
        CMP     D3,D5                           | (next alloc block == expected?)
        BEQ.B   LG2PHYS_OK                      | yes, keep counting contiguous blocks
LG2PHYS_DONE:
        MOVE    (SP)+,D3                        | D3 = starting physical block
        MOVE    D3,D0                           | D0 = starting block
        ADD     D6,D0                           | D0 = ending block (sanity check)
        MOVE    vcbAlBlSt(A2),D4                | D4 = volume alloc block start
        MULU    vcbNmAlBlks(A2),D7              | D7 = D7 *u 26(A2)
        ADD     D4,D7                           | D7 = volume end (alloc area)
        CMP     D7,D0                           | ending block past volume end?
        BHI.B   LG2PHYS_ERR                     | yes -> bad volume metadata
        CMP     D4,D3                           | starting block before alloc area?
        BCS.B   LG2PHYS_ERR                     | yes -> bad
        ASL.L   D1,D6                           | D6 = bytes (D6 * 512)
        MOVEM.L (SP)+,D1-D2/D4-D5/D7            | restore D1-D2/D4-D5/D7
        CMP.L   D4,D6                           | contiguous bytes > requested?
        BLS.B   LG2PHYS_NO_2                    | no -> use D6 as-is
        MOVE.L  D4,D6                           | yes -> clamp to requested
LG2PHYS_NO_2:
        RTS                                     | return; D6 = bytes mappable
LG2PHYS_ERR:
        MOVEQ.L #0x1B,D0                        | D0 = dsBadAllocBlock (27)
        _SysError                               | fatal: corrupt alloc map
| ----------------------------------------------------------
| LG2PHYS_NEXT_2
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
LG2PHYS_NO_3:
        MOVE.L   D4,D0                          | D0 = bytes still needed
LG2PHYS_CONT_2:
        MOVEM.L D1-D5/D7-A3,-(SP)               | save regs
        MOVE.L  vcbAlBlkSiz(A2),D7              | alloc block size
        MOVE.L  D7,D6                           | compute free space in bytes
        MULU    vcbFreeBks(A2),D6               | D6 = D6 *u 0x2A(A2)
        CMP.L   D6,D4                           | request > free space?
        BLS.B   LG2PHYS_NO_4                    | no ->
        MOVE.L  D6,D4                           | limit to available space
LG2PHYS_NO_4:
        CMP.L   D0,D4                           | enough space?
        BCC.B   LG2PHYS_OK_2                    | yes ->
        MOVEQ.L #-0x22,D0                       | DskFulErr
LG2PHYS_EXIT:
        MOVEM.L (SP)+,D1-D5/D7-A3               | restore D1-D5/D7-A3
        RTS                                     | return from MFS alloc

| MFS Alloc: extend file by allocating blocks from alloc map
LG2PHYS_OK_2:
        MOVE.L  fcbPLen(A1,D1.W),D2             | D2 = current PEOF (FCBPLen)
        MOVEQ.L #0x0,D6                         | D6 = bytes allocated so far
        MOVE    fcbSBlk(A1,D1.W),D3             | D3 = start alloc block (FCBStBlk)
        BNE.B   LG2PHYS_CONT_3                  | have blocks already ->
        BSR.B   LG2PHYS_NEXT_3                  | find free block
        MOVE    D5,fcbSBlk(A1,D1.W)             | set start block (FCBStBlk)
        MOVE    D5,D3                           | D3 = current alloc block
        MOVEQ.L #0x1,D5                         | dupFNErr
        BSR.W   LG2PHYS_CONT_9                  | call helper
        BRA.B   LG2PHYS_CONT_5                  | count this block, advance
LG2PHYS_ERR_2:
        MOVE.W   D5,D3                          | read high byte of 12-bit entry
LG2PHYS_CONT_3:
        BSR.B   LG2PHYS_NEXT_2                  | call helper
        CMPI    #0x1,D5                         | end-of-chain (1)?
        BNE.B   LG2PHYS_ERR_2                   | error ->
LG2PHYS_NO_5:
        CMP     vcbNmAlBlks(A2),D3              | block past end of volume?
        BHI.B   LG2PHYS_OK_3                    | yes ->
        ADDQ.W  #0x1,D3                         | peek at next block
        BSR.B   LG2PHYS_NEXT_2                  | call helper
        SUBQ.W  #0x1,D3                         | restore current block number
        TST     D5                              | next block occupied?
        BNE.B   LG2PHYS_OK_3                    | yes, find another free ->
        MOVE    D3,D5                           | new block = current + 1
        ADDQ.W  #0x1,D5                         | D5 = next sequential block
LG2PHYS_CONT_4:
        BSR     LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: link current -> new block in map
        MOVE    D5,D3                           | D3 = new block (now current)
        MOVEQ.L #0x1,D5                         | mark new block as end-of-chain (1)
        BSR.B   LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: set new block's map entry
LG2PHYS_CONT_5:
        ADD.L   D7,D6                           | D6 += alloc-block bytes (running)
        ADD.L   D7,D2                           | D2 += alloc-block bytes (PEOF)
        SUBQ.W  #0x1,vcbFreeBks(A2)             | 0x2A(A2) -= 0x1
        CMP.L   D6,D4                           | allocated enough?
        BHI.B   LG2PHYS_NO_5                    | branch if > (unsigned)
        MOVE.L  D2,fcbPLen(A1,D1.W)             | D2 = new free run start candidate
        ST      6(A2)                           | 6(A2) := -1 (true)
        MOVEQ.L #0x0,D0                         | return noErr
        BRA.B   LG2PHYS_EXIT                    | restore regs and return
LG2PHYS_OK_3:
        BSR.B   LG2PHYS_NEXT_3                  | find another free run
        BRA.B   LG2PHYS_CONT_4                  | link new run into chain

| ----------------------------------------------------------
| LG2PHYS_NEXT_3
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
        BCHG    #0x0,D5                         | D5 ^= 1<<0x0
        BNE.B   LG2PHYS_ERR_3                   | error ->
        MOVE.B  (A1),D1                         | read low nibble byte
        LSR     #0x4,D1                         | shift nibble to low position
        BRA.B   LG2PHYS_CONT_6                  | test 12-bit entry for free
LG2PHYS_ERR_3:
        MOVE.B   (A1)+,D1                       | read low byte of 12-bit entry
        ANDI.W   #0xFFF,D1                      | isolate low 12 bits

| MFS Alloc scan: check if this block is free (entry = 0)
LG2PHYS_CONT_6:
        BNE.B   LG2PHYS_NO_8                    | not free, end of free run ->
        ADD.L   D7,D3                           | extend free run by alloc block size
        CMP.L   D6,D3                           | better than current best?
        BLS.B   LG2PHYS_NO_7                    | no ->
        MOVE.L  D3,D6                           | yes, update best free run length
        MOVE    D2,(SP)                         | save best-fit start block
        CMP.L   D4,D3                           | run >= requested size?
        BCC.B   LG2PHYS_CONT_8                  | unsigned greater or equal ->
LG2PHYS_NO_7:
        ADDQ.W  #0x1,D0                         | advance to next block
        BRA.B   LG2PHYS_CONT_7                  | loop scan
LG2PHYS_NO_8:
        ADDQ.W  #0x1,D0                         | advance past occupied block
        MOVE    D0,D2                           | D2 = new free run start candidate
        MOVEQ.L #0x0,D3                         | dupFNErr
LG2PHYS_CONT_7:
        CMP     A3,D0                           | end of alloc map?
        BLS.B   LG2PHYS_NO_6                    | branch if <= (unsigned)
LG2PHYS_CONT_8:
        MOVE    (SP)+,D5                        | D5 = best-fit start block
        MOVEM.L (SP)+,D0-D4/D6/A1/A3            | restore D0-D4/D6/A1/A3
        RTS                                     | return from free-run scan

| ----------------------------------------------------------
| LG2PHYS_CONT_9
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
LG2PHYS_CONT_10:
        TST     D3                              | D3 = first alloc block in chain
        BEQ.B   LG2PHYS_CONT_11                 | empty chain -> nothing to free
LG2PHYS_NO_9:
        BSR.W   LG2PHYS_NEXT_2                  | get next block in chain (D5)
        MOVE    D5,-(SP)                        | save next block
        CLR     D5                              | write 0 (free) to map entry
        BSR.B   LG2PHYS_CONT_9                  | LG2PHYS_CONT_9: write 0 to alloc map
        ADDQ.W  #0x1,vcbFreeBks(A2)             | increment free block count
        MOVE    (SP)+,D3                        | D3 = next block in chain
        CMPI    #0x1,D3                         | end-of-chain marker? (block 1)
        BNE.B   LG2PHYS_NO_9                    | no, keep freeing ->
        ST      6(A2)                           | 6(A2) := -1 (true, VCB dirty)
LG2PHYS_CONT_11:                                | @ $4B42 (skip-all exit)
        RTS                                     | return from chain-free helper
