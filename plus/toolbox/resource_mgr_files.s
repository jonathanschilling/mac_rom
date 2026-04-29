| Resource Manager - Part 1: File Operations and Resource Search
|
| This file used to be misnamed `control_mgr.s` but contains no Control
| Manager code. The actual Control Manager publics live in
| `control_mgr_publics.s`; the Control Mgr internal helpers (CMP,
| FINDNEXT) that the FDisasm autoclassifier had labelled as a separate
| subsystem are in fact Resource Manager search helpers.
|
| This file contains the first half of the Resource Manager:
| - RSRCZONEINIT_CONT_2: Open resource fork (checks for printer driver STR -8192)
| - CreateResFile, OpenResFile, OpenRFPerm
| - UseResFile, GetResFileAttrs, SetResFileAttrs
| - STDMAPENTRY: StdMapEntry - find resource map by reference number
| - FINDNEXT_ALL-FINDNEXT_CUR_OFS: FindNext - find next resource by offset in map
| - MAXLOAD-MAXLOAD_CMP: MaxLoad - calculate buffer size for compaction
| - UpdateResFile with compaction (CmpFrm)
| - CloseResFile
| - CountResources, GetIndResource, CountTypes, GetIndType
| - UniqueID, GetResource, GetNamedResource
|
| Color QuickDraw stubs (MakeRGBPat, FillCRect, etc.) serve as
| entry points for the "current map only" variants (Count1Resources,
| Get1IndResource, etc.) on the Mac Plus which lacks Color QD.
| They set RMgrCurOnly=$FF then fall through to the search routines.
|
| NOTE: Symbolic offset names like contrlOwner, contrlMax, PORTRECT,
| VISRGN are reused here because their numeric values coincide with
| resource map and reference entry field offsets:
| contrlOwner (0x04) = resource ref attrs+offset / map data offset
| contrlRect (0x08) = resource ref handle field / map data length
| PORTRECT (0x10) = next map handle in chain
| contrlMax (0x16) = map attributes word
| VISRGN (0x18) = offset to type list from map start
|
| References:
| Inside Macintosh Vol I, Ch 5: The Resource Manager
| Mac OS 7.1 Source: Toolbox/ResourceMgr/ResourceMgr.a

| RSRCZONEINIT_CONT_2 - open resource fork, checking for printer driver
| If the resource is 'STR ' ID -8192, uses BootDrive for vRefNum
| (matches the printer driver resource file convention).
        MOVE.L  A1,A0                           | get master pointer
        _RecoverHandle                          | recover handle from master ptr
        LINK    A2,#-0xE                        | allocate locals: ID, type, name
        MOVE.L  A0,-(SP)                        | push resource handle
        PEA.L   -contrlOwner(A2)                | push ptr to ID result (local var)
        PEA.L   -contrlRect(A2)                 | push ptr to type result (local var)
        CLR.L   -(SP)                           | push nil for name
        _GetResInfo                             | get resource type and ID
        CMPI    #-0x2000,-contrlOwner(A2)       | ID = -8192 (printer driver STR)?
        BNE.B   OPENRF_SKIP_BOOT                | no, skip BootDrive override
        CMPI.L  #0x53545220,-contrlRect(A2)     | type = 'STR '?

        BNE.B   OPENRF_SKIP_BOOT                | not 'STR ', skip
        MOVE    (BootDrive).w,-0x1C(A6)         | override vRefNum with boot drive
OPENRF_SKIP_BOOT:
        UNLK    A2                              | discard locals
        MOVEM.L (SP)+,A0-A1                     | restore IOParam ptr and filename
OPENRF_SET_FNAME:
        MOVE.L  A1,ioFileName(A0)               | set filename in IOParam block
        CLR.L   ioOwnBuf(A0)                    | no private buffer
        _OpenRF                                 | open resource fork
        MOVE    ioRefNum(A0),D6                 | get file reference number
        MOVE    D0,(ResErr).w                   | save result code
        RTS                                     | return with D0=error, D6=refNum

| ----------------------------------------------------------
|
| _CreateResFile ($A9B1)
|
| Creates a new resource file. If the file does not exist, creates it
| first with _Create. Writes an empty resource map (16-byte header +
| 30-byte null map) to the resource fork.
|
CreateResFile:
        BSR     RESMGR_CONT_4                   | StdEntry: link A6, save regs
        MOVE.L  (A0),A1                         | get filename pointer
        BSR     CHECKLOAD_CONT_9                | set up IOParam block from filename
        BSR.B   RSRCZONEINIT_CONT_2             | try to open resource fork
        BEQ.B   CREATERES_CHKEOF                | opened OK, check if empty
        CMPI    #-0x2B,D0                       | error = fnfErr (-43)?
        BNE.B   CREATERES_EXIT                  | other error, bail out
        _Create                                 | file not found, create it
        MOVE    D0,(ResErr).w                   | save create result
        BMI.B   CREATERES_EXIT                  | create failed, bail out
        BSR.B   RSRCZONEINIT_CONT_2             | open the newly created file
        BMI.B   CREATERES_EXIT                  | open failed, bail out
CREATERES_CHKEOF:
        _GetEOF                                 | check resource fork size
        MOVE    #-0x30,(ResErr).w               | assume mapReadErr (-48)
        TST.L   ioOwnBuf(A0)                    | is resource fork empty (EOF=0)?
        BNE.B   CREATERES_CLOSE                 | non-empty, skip initialization
        MOVEQ.L #0x10,D0                        | write 16-byte resource header
        LEA.L   RESOURCE_MAP(PC),A1             | point to null resource map template
        MOVE.L  A1,D1                           | source address for write
        BSR     CHECKLOAD_CONT_11               | write header at current position
        MOVEQ.L #0x1E,D0                        | write 30-byte null map (NullRMSize)
        MOVEQ.L #0x40,D2                        | D2 = 0x100 after shift
        ASL     #0x2,D2                         | = 256 (offset to map in resource fork)
        BSR     CHECKLOAD_EMPTY_2               | write null map at offset 256
CREATERES_CLOSE:
        _Close                                  | close the file
CREATERES_EXIT:
        BRA     RESMGR_EXIT_5                   | StdFourExit: pop 4 bytes, return

| ----------------------------------------------------------
|
| _OpenResFile ($A997)
|
| Opens a resource file and links its map into the chain.
| Returns the file's reference number as function result.
| Called during boot.
OpenResFile:
        BSR     RESMGR_CONT_4                   | StdEntry: link A6, save regs
OPENRES_COMMON:
        MOVE.L  (A0),A1                         | get filename pointer
        BSR     P_NewMap                        | open file, read map into memory
        MOVE    D6,0xC(A6)                      | store refnum as function result
        BMI.B   OPENRES_EXIT                    | NewMap failed, skip linking
        MOVE    D6,(CurMap).w                   | set as current resource file
        TST     D0                              | check if ROM map needs linking
        BEQ.B   OPENRES_EXIT                    | no, skip
        MOVE.L  (TopMapHndl).w,0x10(A1)         | new map->nextMap = old TopMap
        MOVE.L  A4,(TopMapHndl).w               | TopMapHndl = new map handle
        BSR     INITRESOURCES_CONT_5            | preload flagged resources
OPENRES_EXIT:
        BRA     RESMGR_EXIT_5                   | StdFourExit

| ----------------------------------------------------------
|
| _OpenRFPerm ($A9C4)
|
| Opens a resource file with explicit permission byte.
| Stack: fileName(L), vRefNum(W), permission(B) -> refNum(W)
|
OpenRFPerm:
        MOVE.L  (SP)+,A0                        | save return address
        MOVE.B  (SP)+,(RMgrPerm).w              | pop permission byte into global
        MOVE    (SP)+,D0                        | pop vRefNum
        MOVE.L  A0,-(SP)                        | restore return address
        BSR     RESMGR_CONT_4                   | StdEntry: link A6, save regs
        MOVE    D0,-0x1C(A6)                    | store vRefNum in stack frame
        BRA.B   OPENRES_COMMON                  | join OpenResFile common path

| ----------------------------------------------------------
|
| _UseResFile ($A998)
|
| Sets the current resource file to the specified refnum.
| Called during boot.
UseResFile:
        BSR.B   STDMAPENTRY                     | StdMapEntry: find map by refnum
        MOVE    D6,(CurMap).w                   | set as current resource file
        BRA     RESMGR_ERR_2                    | StdTwoExit

| ----------------------------------------------------------
|
| _GetResFileAttrs ($A9F6)
|
| Returns the map attributes of the specified resource file.
| contrlMax offset (0x16) = map attributes field in resource map.
| Called during boot.
GetResFileAttrs:
        BSR.B   STDMAPENTRY                     | StdMapEntry: find map by refnum
        MOVE.B  contrlMax(A3),0xB(A6)           | return map attributes byte
        BRA     RESMGR_ERR_2                    | StdTwoExit

| ----------------------------------------------------------
|
| _SetResFileAttrs ($A9F7)
|
| Sets the map attributes of the specified resource file.
| Called during boot.
SetResFileAttrs:
        BSR     RESMGR_CONT_4                   | StdEntry: link A6, save regs
        MOVE    0xA(A6),D6                      | get refnum from stack frame
        BSR     RESMGR_CONT                     | GetMap: find map by refnum in D6
        BMI.B   SETRESATTR_EXIT                 | map not found, skip
        MOVE.B  0x9(A6),contrlMax(A3)           | set map attributes byte
SETRESATTR_EXIT:
        BRA     RESMGR_EXIT_5                   | StdFourExit

| ----------------------------------------------------------
|
| STDMAPENTRY - StdMapEntry
|
| Standard entry for routines that take a refnum parameter.
| Calls StdEntry, reads refnum from stack, finds the map.
| On failure, pops return address and exits with resNotFound.
| Called during boot.
STDMAPENTRY:
        MOVE.L  (SP)+,D0                        | save return address
        BSR     RESMGR_CONT_4                   | StdEntry: link A6, save regs
        MOVE.L  D0,-(SP)                        | restore return address
        MOVE    (A0),D6                         | get refnum from parameter area
        BSR     RESMGR_CONT                     | GetMap: find map by refnum in D6
        BMI.B   STDMAPENTRY_ERR                 | not found, error exit
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| STDMAPENTRY_ERR - StdMapEntry error exit
|
| Map not found: pop caller's return address, report resFNotFound.
STDMAPENTRY_ERR:
        ADDQ.W  #0x4,SP                         | discard caller's return address
        MOVE    #-0xC1,(ResErr).w               | resFNotFound (-193)
        BRA     RESMGR_ERR_2                    | StdTwoExit

| ----------------------------------------------------------
|
| FINDNEXT_ALL - FindNext (from beginning of all maps)
|
| Searches all resource maps for the next reference entry
| whose data offset is greater than the current position.
| Used by UpdateResFile to iterate resources in file order.
FINDNEXT_ALL:
        MOVEQ.L #0x0,D1                         | D1=0: search all entries
| FINDNEXT_FROM_START -- findNext from beginning, changed only.
FINDNEXT_FROM_START:
        MOVEQ.L #-0x1,D0                        | start from offset -1 (beginning)
        BRA.B   FINDNEXT_ENTER                  | enter FindNext loop

| ----------------------------------------------------------
|
| FINDNEXT_FROM_CUR - FindNext (from current entry's offset)
|
| Searches for the next resource entry whose data offset
| is greater than the current entry's offset. Used during
| UpdateResFile compaction to process resources in file order.
| Called during boot.
FINDNEXT_FROM_CUR:
        MOVEQ.L #0x0,D1                         | D1=0: search all entries
| FINDNEXT_CUR_OFS -- find next changed entry after current.
FINDNEXT_CUR_OFS:
        MOVE.L  contrlOwner(A2),D0              | get current ref's attrs+offset
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit data offset
FINDNEXT_ENTER:
        MOVEM.L D2-D7/A3,-(SP)                  | save registers
        MOVE.L  D0,D2                           | D2 = minimum data offset
        BSR     RESMGR_CONT_3                   | count all reference entries
        BMI.B   FINDNEXT_RET                    | no entries, return failure
        LEA.L   (MinusOne).w,A3                 | A3 = sentinel address
        SUBQ.L  #0x4,A3                         | point before MinusOne
        MOVE.L  A3,D6                           | D6 = best entry so far (none)
        MOVEQ.L #-0x1,D7                        | D7 = 0x7FFFFFFF (max offset)
        LSR.L   #0x1,D7                         | largest positive long
        TST     D1                              | D1=0: all entries, D1!=0: flagged only
        BEQ.B   FINDNEXT_ALL_LOOP               | search all entries
FINDNEXT_FLAG_LOOP:
        BTst    D1,contrlOwner(A2)              | test attribute bit D1 in ref entry
        BEQ.B   FINDNEXT_FLAG_SKIP              | bit not set, skip this entry
        MOVE.L  contrlOwner(A2),D0              | get attrs+offset of this entry
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit data offset
        CMP.L   D0,D2                           | offset > minimum?
        BGE.B   FINDNEXT_FLAG_SKIP              | no, skip (not past current pos)
        CMP.L   D0,D7                           | offset < current best?
        BLE.B   FINDNEXT_FLAG_SKIP              | no, skip (not closer)
        MOVE.L  D0,D7                           | update best offset
        MOVE.L  A2,D6                           | update best entry pointer
FINDNEXT_FLAG_SKIP:
        ADDA    #0xC,A2                         | advance to next ref entry (12 bytes)
        DBF     D4,FINDNEXT_FLAG_LOOP           | loop through all entries
        BRA.B   FINDNEXT_DONE                   | done, finalize result

| ----------------------------------------------------------
|
| FINDNEXT_ALL_LOOP - FindNext inner loop (all entries, no flag check)
|
| Scans all reference entries for the one with the smallest
| data offset that is still greater than the minimum in D2.
| Called during boot.
FINDNEXT_ALL_LOOP:
        MOVE.L  contrlOwner(A2),D0              | get attrs+offset of this entry
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit data offset
        CMP.L   D0,D2                           | offset > minimum?
        BGE.B   FINDNEXT_ALL_SKIP               | no, skip
        CMP.L   D0,D7                           | offset < current best?
        BLE.B   FINDNEXT_ALL_SKIP               | no, skip
        MOVE.L  D0,D7                           | update best offset
        MOVE.L  A2,D6                           | update best entry pointer
FINDNEXT_ALL_SKIP:
        ADDA    #0xC,A2                         | next ref entry (12 bytes each)
        DBF     D4,FINDNEXT_ALL_LOOP            | loop through all entries
FINDNEXT_DONE:
        MOVE.L  D6,A2                           | A2 = best matching ref entry
        MOVE.L  D7,D0                           | D0 = best offset found
        MOVE.L  contrlOwner(A2),D7              | get attrs+offset of best entry
        AND.L   (Lo3Bytes).w,D7                 | mask to data offset
        CMP.L   D0,D7                           | set Z if valid match found
FINDNEXT_RET:
        MOVEM.L (SP)+,D2-D7/A3                  | restore registers
        RTS                                     | return Z=1 if match found

| ----------------------------------------------------------
|
| MAXLOAD - MaxLoad: calculate compaction buffer size
|
| Computes ideal buffer size for resource compaction. Uses the larger
| of the resource fork size (CHECKLOAD_CONT_12) and the largest free block (_MaxBlock),
| capped at 4096 bytes minimum.
MAXLOAD:
        BSR     CHECKLOAD_CONT_12               | compute resource fork total size
        MOVE.L  D0,D3                           | D3 = resource fork size
        _MaxBlock                               | D0 = largest contiguous free block
        BSR.B   MAXLOAD_CMP                     | pick larger of D0 and D3
        MOVEQ.L #0x40,D3                        | D3 = 0x40 (will become 4096)
        ASL     #0x6,D3                         | D3 = 4096 (minimum buffer size)
| MAXLOAD_CMP -- pick larger of D0 and D3.
MAXLOAD_CMP:
        CMP.L   D0,D3                           | is D3 >= D0?
        BGE.B   MAXLOAD_RET                     | yes, D3 is already larger
        EXG     D0,D3                           | no, swap so D3 = larger value
MAXLOAD_RET:
        RTS                                     | D3 = max(fork size, free block, 4096)

| ----------------------------------------------------------
|
| _UpdateResFile ($A999)
|
| Called during boot.
UpdateResFile:
        BSR     STDMAPENTRY                     | StdMapEntry: find map by refnum
        BSR     CHECKLOAD_OK_4                  | test if file is read-only
        BEQ.B   UPDRES_CHECK_CHG                | writable, proceed with update
        MOVE    #-0xC7,(ResErr).w               | wPrErr (-199): write-protected
        BRA     RESMGR_ERR_2                    | StdTwoExit

| ----------------------------------------------------------
|
| UPDRES_CHECK_CHG - UpdateResFile: check mapChanged and write resources
|
| Tests the mapChanged flag; if not set, nothing to update.
| Two paths: if mapCompact is clear, write only changed resources
| in file order; if mapCompact is set, do full compaction (UPDRES_COMPACT).
| Called during boot.
UPDRES_CHECK_CHG:
        BTst    #0x5,0x16(A0)                   | test mapChanged bit in map attrs
        BEQ     RESMGR_ERR_2                    | not changed, nothing to update
        BSR     CHECKLOAD_OK_3                  | flush map to disk (write header+map)
        BMI     RESMGR_ERR_2                    | write error, bail out
        BCLR    #0x6,contrlMax(A3)              | clear+test mapCompact flag
        BNE.B   UPDRES_COMPACT                  | was set: do full compaction
        MOVEQ.L #0x1,D1                         | D1=1: search only changed entries
        BSR     FINDNEXT_FROM_START             | FindNext from beginning, changed only
        BMI.B   UPDRES_WRITE_MAP                | no changed resources, skip to map write
UPDRES_WRITE_LOOP:
        BSR     CHECKLOAD_CONT_8                | write this changed resource to disk
        BSR     FINDNEXT_CUR_OFS                | find next changed entry after current
        BEQ.B   UPDRES_WRITE_LOOP               | found one, write it too
UPDRES_WRITE_MAP:
        BRA     CMP_WRITE_MAP                   | go write updated map to disk

| ----------------------------------------------------------
|
| UPDRES_COMPACT - UpdateResFile compaction path
|
| Compacts the resource fork by rewriting all resources in file order.
| First adjusts data offsets if the map has moved, then enters the
| CmpFrm compaction loop to sequentially write resources.
UPDRES_COMPACT:
        BSR     FINDNEXT_ALL                    | FindNext from beginning (all entries)
        BMI     CMP_WRITE_MAP                   | no entries at all, write map only
        MOVE.L  (A4),A0                         | dereference map handle
        MOVE.L  (A0),D7                         | D7 = data fork offset (old)
        SUB.L   0x4(A0),D7                      | D7 = old data offset - map offset
        BCS.B   UPDRES_CMP_START                | map offset > data offset, skip adjust
        BSR     RESMGR_CONT_3                   | count all ref entries (D4 = total)
UPDRES_ADJ_LOOP:
        ADD.L   D7,contrlOwner(A2)              | adjust each ref's data offset by delta
        ADDA    #0xC,A2                         | advance to next ref entry (12 bytes)
        DBF     D4,UPDRES_ADJ_LOOP              | loop through all ref entries
        MOVE.L  0x4(A0),(A0)                    | set data offset = map offset (aligned)
        BSR     FINDNEXT_ALL                    | FindNext from beginning again
UPDRES_CMP_START:
        MOVEQ.L #0x0,D7                         | D7 = cumulative write position (start=0)
        BRA.B   CMP_GAP_CHECK                   | enter compaction gap-check loop

| ----------------------------------------------------------
|
| CMP_WRITE_RES - compaction loop: write current resource
|
| If the resChanged bit is set, writes the in-memory resource data
| to disk (CHECKLOAD_CONT_8) and gets its handle size. Otherwise reads the
| existing resource data size from the file (CHECKLOAD_CONT_5).
CMP_WRITE_RES:
        BTst    #0x1,contrlOwner(A2)            | test resChanged bit in ref attrs
        BEQ.B   CMP_READ_SIZE                   | not changed, read size from file
        BSR     CHECKLOAD_CONT_8                | write changed resource data to disk
        MOVE.L  contrlRect(A2),A0               | A0 = resource handle (ref+8)
        _GetHandleSize                          | D0 = size of resource data in memory
        BRA.B   CMP_ADD_LEN_PFX                 | skip to offset computation

| ----------------------------------------------------------
|
| CMP_READ_SIZE - read existing resource size from file
|
CMP_READ_SIZE:
        BSR     CHECKLOAD_CONT_5                | read 4-byte data length from resource file
CMP_ADD_LEN_PFX:
        ADDQ.L  #0x4,D0                         | add 4 for the length prefix itself
        MOVE.L  contrlOwner(A2),D7              | D7 = current ref's attrs+offset
        ADD.L   D0,D7                           | D7 = offset past this resource's data
        AND.L   (Lo3Bytes).w,D7                 | mask to 24-bit offset
        BSR     FINDNEXT_FROM_CUR               | find next entry after this offset
        BMI.B   CMP_STORE_DATALEN               | no more entries, finalize compaction
CMP_GAP_CHECK:
        MOVE.L  D7,D0                           | D0 = expected write position
        SUB.L   contrlOwner(A2),D0              | D0 = gap between write pos and ref offset
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit gap size
        BEQ.B   CMP_WRITE_RES                   | no gap, resource is contiguous - write it
        SUBA.L  (A4),A2                         | make A2 relative (handle may move)
        BSR     MAXLOAD                         | compute compaction buffer size
        MOVE.L  D3,D0                           | D0 = buffer size for NewHandle
        _NewHandle                              | allocate compaction buffer
        ADDA.L  (A4),A2                         | restore A2 to absolute
        _HLock                                  | lock buffer so it won't move
        MOVE.L  A0,A3                           | A3 = compaction buffer handle
        MOVE.L  (A3),D0                         | D0 = dereferenced buffer pointer
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        ADD.L   D0,D3                           | D3 = buffer end address
        MOVE.L  D0,A1                           | A1 = buffer write pointer
        MOVE.L  A1,D4                           | D4 = buffer read limit
        MOVE.L  D7,D5                           | D5 = current file write position
        MOVE.L  (0x7E8).w,A0                    | dispatch vector: _CmpFrm
        JMP     (A0)                            | enter compaction frame loop

| ----------------------------------------------------------
|
| CmpFrm - compaction frame: copy resources to close gaps
|
| For each resource in file order, either copies from memory (changed)
| or from disk (unchanged) into the compaction buffer, then flushes
| the buffer to disk to close gaps between resources.
CmpFrm:
        BTST    #0x1,contrlOwner(A2)            | test resChanged bit in ref attrs
        BEQ.B   CMP_COPY_FROM_DSK               | not changed, copy from disk (CMP_COPY_UNCHANGE)
        BSR.B   CMP_COPY_CHANGED                | copy changed resource from memory to buffer
        BPL.B   CMP_NEXT_RES                    | success, advance to next resource
CMP_COPY_FROM_DSK:
        BSR     CMP_COPY_UNCHANGE               | copy unchanged resource from disk to buffer
CMP_NEXT_RES:
        BSR     FINDNEXT_FROM_CUR               | find next resource in file order
        BEQ.B   CmpFrm                          | found one, compact it too
        MOVE.L  A1,D0                           | D0 = current buffer write position
        SUB.L   (A3),D0                         | D0 = bytes remaining in buffer
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit count
        MOVE.L  (A3),D1                         | D1 = buffer base address (source)
        MOVE.L  (A4),A0                         | dereference map handle
        MOVE.L  D7,D2                           | D2 = cumulative file write position
        ADD.L   (A0),D2                         | D2 += data fork offset = absolute pos
        BSR     CHECKLOAD_EMPTY_2               | write buffer contents to file at D2
        ADD.L   D0,D7                           | advance file write position
        MOVE.L  A3,A0                           | A0 = compaction buffer handle
        _DisposeHandle                          | free the compaction buffer
        MOVE.L  (A4),A3                         | A3 = dereferenced map pointer
CMP_STORE_DATALEN:
        MOVE.L  D7,PORTBOUNDS(A3)               | store new data length in map header
CMP_WRITE_MAP:
        BClr    #0x5,contrlMax(A3)              | clear+test mapChanged flag
        BEQ.B   CMP_MAP_EXIT                    | was not set, skip map rewrite
        MOVE.L  PORTBOUNDS(A3),D2               | D2 = data fork length
        ADD.L   (A3),D2                         | D2 += data fork offset = map file pos
        MOVE.L  D2,contrlOwner(A3)              | update map offset in map header
        MOVE.L  0xC(A3),D0                      | D0 = map length (header field at +0xC)
        MOVE.L  A3,D1                           | D1 = map data source address
        BSR     CHECKLOAD_EMPTY_2               | write map data to file at position D2
        MOVEQ.L #0x10,D0                        | D0 = 16 bytes (resource file header)
        BSR     CHECKLOAD_CONT_11               | write 16-byte header at file position 0
        BSR     CHECKLOAD_OK_3                  | set EOF and flush file
CMP_MAP_EXIT:
        BRA     RESMGR_ERR_2                    | StdTwoExit

| ----------------------------------------------------------
|
| CMP_COPY_CHANGED - copy changed resource from memory to compaction buffer
|
| Reads the resource handle's data and copies it into the compaction
| buffer, flushing the buffer to disk when full. Writes the 4-byte
| data length prefix first, then the data itself.
CMP_COPY_CHANGED:
        BSR     CMP_FLUSH_BUF                   | flush buffer if needed, update file pos
        MOVE.L  contrlRect(A2),A0               | A0 = resource handle (ref+8)
        _GetHandleSize                          | D0 = size of resource data
        TST.L   D0                              | valid handle?
        BMI     RESMGR_ERR                      | invalid - return error
        BSR.B   CMP_UPD_REF_OFS                 | update ref entry's data offset for new pos
        BSR.B   CMP_WRITE_LONG                  | write 4-byte length prefix to buffer
        MOVE.L  D0,D2                           | D2 = remaining bytes to copy
        ADD.L   A1,D2                           | D2 = buffer end after full copy
        CMP.L   D2,D4                           | does data fit in remaining buffer?
        MOVE.L  (A0),A0                         | A0 = dereferenced resource data
        BGE.B   CMP_BLOCKMOVE                   | fits entirely - BlockMove it
        MOVE.L  D0,D2                           | D2 = total bytes still to copy
        MOVEQ.L #0x0,D1                         | D1 = source offset within resource data
CMP_CHG_CHUNK:
        MOVE.L  contrlRect(A2),A0               | A0 = resource handle (may have moved)
        MOVE.L  (A0),A0                         | dereference resource handle
        ADDA.L  D1,A0                           | offset into resource data by D1
        MOVE.L  D3,D0                           | D0 = buffer end address
        SUB.L   A1,D0                           | D0 = space remaining in buffer
        CMP.L   D2,D0                           | enough space for remaining data?
        BGE.B   CMP_CHG_FINAL                   | yes - copy final chunk
        ADD.L   D0,D1                           | advance source offset by chunk size
        SUB.L   D0,D2                           | reduce remaining count
        BSR.B   CMP_COPY_CHUNK                  | copy chunk to buffer and flush
        BSR     CMP_FLUSH_BUF                   | flush buffer to disk, reset pointers
        BRA.B   CMP_CHG_CHUNK                   | loop for next chunk

| ----------------------------------------------------------
|
| CMP_CHG_FINAL - final chunk: copy remaining bytes to buffer
|
CMP_CHG_FINAL:
        MOVE.L  D2,D0                           | D0 = remaining byte count (final chunk)
| CMP_COPY_CHUNK -- copy chunk to buffer and flush.
CMP_COPY_CHUNK:
        MOVE.L  A1,D4                           | D4 = buffer read limit (before write)
        NOP                                     | alignment padding (no-op)
| CMP_BLOCKMOVE -- copy 4-byte length prefix within buffer.
CMP_BLOCKMOVE:
        CMPA.L  A0,A1                           | source == dest (already in place)?
        BEQ.B   CMP_ADV_WRITEPTR                | yes - skip BlockMove
        MOVE.L  D0,-(SP)                        | save byte count
        _BlockMove                              | copy D0 bytes from A0 to A1
        MOVE.L  (SP)+,D0                        | restore byte count
| CMP_ADV_WRITEPTR -- advance write pointer, update limit.
CMP_ADV_WRITEPTR:
        ADD.L   D0,D5                           | advance file write position
        ADDA.L  D0,A1                           | advance buffer write pointer
CMP_UPD_RDLIMIT:
        CMP.L   A1,D4                           | is read limit behind write pointer?
        BGE.B   CMP_RDLIMIT_OK                  | no, read limit still valid
        MOVE.L  A1,D4                           | yes, update read limit to write ptr
CMP_RDLIMIT_OK:
        RTS                                     | return to compaction caller

| ----------------------------------------------------------
|
| CMP_UPD_REF_OFS - update ref entry's data offset to reflect new position
|
| Computes the new data offset from the buffer write pointer
| relative to buffer base, plus the cumulative file write offset.
| Preserves the attribute bits in the high byte.
CMP_UPD_REF_OFS:
        MOVEM.L D0-D1/A0,-(SP)                  | save working registers
        MOVEQ.L #-0x3,D1                        | D1 = 0xFD mask (preserve attr bits 0-1)
        LEA.L   contrlOwner(A2),A0              | A0 = ptr to ref attrs+offset field
        AND.B   (A0),D1                         | D1 = preserved attribute bits
        MOVE.L  A1,D0                           | D0 = buffer write pointer
        SUB.L   (A3),D0                         | D0 = offset within buffer
        ADD.L   D7,D0                           | D0 += cumulative file position
        MOVE.L  D0,(A0)                         | store new 3-byte data offset
        MOVE.B  D1,(A0)                         | restore attribute byte in high position
        MOVEM.L (SP)+,D0-D1/A0                  | restore working registers
        RTS                                     | ref entry offset updated

| ----------------------------------------------------------
|
| CMP_WRITE_ZERO - write zero length prefix to buffer
|
| Entry at CMP_WRITE_ZERO writes a zero-length resource (D0=0).
| Entry at CMP_WRITE_LONG writes D0 as a 4-byte big-endian value into the
| compaction buffer, one byte at a time (MSB first via ROL).
CMP_WRITE_ZERO:
        MOVEQ.L #0x0,D0                         | D0 = 0 (empty resource data length)
| CMP_WRITE_LONG -- write 4-byte length prefix to buffer.
CMP_WRITE_LONG:
        MOVE.L  D1,-(SP)                        | save D1
        MOVEQ.L #0x3,D1                         | loop counter: 4 bytes (3..0)
CMP_WLONG_LOOP:
        ROL.L   #0x8,D0                         | rotate MSB into low byte
        MOVE.B  D0,(A1)+                        | write one byte to buffer
        DBF     D1,CMP_WLONG_LOOP               | loop for all 4 bytes
        ADDQ.L  #0x4,D5                         | advance file write position by 4
        MOVE.L  (SP)+,D1                        | restore D1
        BRA.B   CMP_UPD_RDLIMIT                 | update buffer read limit

| ----------------------------------------------------------
|
| CMP_COPY_UNCHANGE - copy unchanged resource from file to compaction buffer
|
| Reads the resource data directly from the file into the buffer.
| If the resource's file offset is behind the current write position,
| the data was already overwritten - write zero-length placeholder.
| Otherwise reads the 4-byte length prefix and data in chunks.
CMP_COPY_UNCHANGE:
        MOVE.L  contrlOwner(A2),D0              | get ref attrs+offset
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit data offset
        SUB.L   D5,D0                           | D0 = file offset relative to write pos
        BGE.B   CMP_READ_INTACT                 | offset ahead, data still intact
        BSR     CMP_FLUSH_BUF                   | flush buffer, data was overwritten
        BSR.B   CMP_UPD_REF_OFS                 | update ref offset to new position
        BRA.B   CMP_WRITE_ZERO                  | write zero-length placeholder

| ----------------------------------------------------------
|
| CMP_READ_INTACT - read unchanged resource from file into buffer
|
| The resource data is still at its original file position.
| Reads the 4-byte length prefix first, then the data body.
| Handles the case where data spans multiple buffer fills.
CMP_READ_INTACT:
        ADD.L   A1,D0                           | D0 = buffer addr where data would land
        ADDQ.L  #0x4,D0                         | account for 4-byte length prefix
        CMP.L   D0,D4                           | does length prefix fit in buffer?
        BGE.B   CMP_READ_UPD_OFS                | yes, proceed with read
        BSR     CMP_FLUSH_BUF                   | flush buffer to make room
        MOVE.L  contrlOwner(A2),D0              | reload ref attrs+offset
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit offset
        MOVE.L  D0,D5                           | D5 = file position of this resource
        BSR.B   CMP_READ_FILE                   | read resource data from file into buffer
CMP_READ_UPD_OFS:
        MOVE.L  contrlOwner(A2),D0              | reload ref attrs+offset
        BSR.B   CMP_UPD_REF_OFS                 | update ref offset to new buffer position
        SUB.L   D5,D0                           | D0 = distance from write pos to data
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit offset
        MOVE.L  A1,A0                           | A0 = current buffer write pointer
        ADDA.L  D0,A0                           | A0 = position of length prefix in buffer
        MOVEQ.L #0x4,D0                         | D0 = 4 bytes (length prefix size)
        BSR     CMP_BLOCKMOVE                   | copy 4-byte length prefix within buffer
        BSR     SUPERLOAD_CONT_2                | read 4 bytes from A0 as big-endian long
        MOVE.L  D0,D2                           | D2 = resource data length
        ADD.L   A0,D2                           | D2 = buffer end after copying all data
        CMP.L   D2,D4                           | does entire resource fit in buffer?
        BGE     CMP_BLOCKMOVE                   | yes, copy it all in one BlockMove
        MOVE.L  contrlOwner(A2),D5              | D5 = new file position for this resource
        ADDQ.L  #0x4,D5                         | skip past length prefix
        AND.L   (Lo3Bytes).w,D5                 | mask to 24-bit offset
        MOVE.L  D0,D2                           | D2 = remaining data bytes to copy
        MOVE.L  D4,D0                           | D0 = bytes available in buffer
        SUB.L   A0,D0                           | D0 = buffer space from data start to limit
        BSR     CMP_BLOCKMOVE                   | copy what fits into buffer
        MOVE.L  A1,D4                           | D4 = new buffer read limit
CMP_READ_LOOP:
        BSR.B   CMP_FLUSH_BUF                   | flush buffer to disk
        BSR.B   CMP_READ_FILE                   | read next chunk from file
        BEQ.B   CMP_READ_ERROR                  | read failed, report error
        SUB.L   D0,D2                           | D2 -= bytes just read
        MOVE.L  A1,A0                           | A0 = buffer base (source for copy)
        ADDA.L  D2,A0                           | A0 = position where data ends
        CMP.L   A0,D4                           | more data than buffer can hold?
        BGE.B   CMP_READ_FINAL                  | no, final chunk fits
        MOVE.L  D4,D0                           | D0 = available bytes in buffer
        SUB.L   A1,D0                           | D0 = usable buffer size
        BSR     CMP_ADV_WRITEPTR                | advance write pointer, update limit
        BRA.B   CMP_READ_LOOP                   | flush and read next chunk

| ----------------------------------------------------------
|
| CMP_READ_FINAL - final chunk fits in buffer
|
CMP_READ_FINAL:
        MOVE.L  A0,D0                           | D0 = end position of data
        SUB.L   A1,D0                           | D0 = bytes to copy (final chunk)
        BRA     CMP_ADV_WRITEPTR                | copy and advance write pointer

| ----------------------------------------------------------
|
| CMP_READ_ERROR - read error during compaction
|
CMP_READ_ERROR:
        MOVE    #-0xC7,(ResErr).w               | wPrErr (-199): resource write error
        BRA     CMP_UPD_RDLIMIT                 | update buffer limit and return

| ----------------------------------------------------------
|
| CMP_READ_FILE - read resource data from file into compaction buffer
|
| Computes how many bytes remain in the file between the current
| read position (D5) and EOF, clamps to available buffer space,
| then reads that chunk into the buffer via CHECKLOAD_CONT_10.
CMP_READ_FILE:
        MOVEM.L D0-D2/A0,-(SP)                  | save working registers
        BSR     CHECKLOAD_CONT_12               | D0 = total resource fork size
        MOVE.L  (A4),A0                         | dereference map handle
        SUB.L   D5,D0                           | D0 -= current file read position
        SUB.L   (A0),D0                         | D0 -= data fork offset = remaining bytes
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit count
        MOVE.L  D3,D1                           | D1 = buffer end address
        SUB.L   A1,D1                           | D1 = available buffer space
        CMP.L   D1,D0                           | more data than buffer can hold?
        BLE.B   CMP_READF_CLAMP                 | no, D0 fits in buffer
        MOVE.L  D1,D0                           | yes, clamp to buffer capacity
CMP_READF_CLAMP:
        MOVE.L  A1,D1                           | D1 = buffer address (read destination)
        MOVE.L  D5,D2                           | D2 = file read position
        ADD.L   (A0),D2                         | D2 += data fork offset = absolute pos
        MOVE.L  A1,D4                           | D4 = read limit base
        ADD.L   D0,D4                           | D4 += bytes to read = new limit
        AND.L   (Lo3Bytes).w,D4                 | mask to 24-bit address
        BSR     CHECKLOAD_CONT_10               | read D0 bytes from file at D2 into D1
        TST.L   D0                              | test bytes actually read (Z if zero)
        MOVEM.L (SP)+,D0-D2/A0                  | restore working registers
        RTS                                     | Z=1 if no data read (EOF)

| CMP_FLUSH_BUF -- flush buffer if needed, update file pos.
| ----------------------------------------------------------
|
| CMP_FLUSH_BUF
|
| Called by: CMP_COPY_CHANGED, CMP_CHG_CHUNK, CMP_COPY_UNCHANGE, CMP_READ_INTACT, CMP_READ_LOOP
CMP_FLUSH_BUF:
        MOVEM.L D0-D2,-(SP)                     | save working registers
        MOVE.L  A1,D0                           | D0 = buffer write pointer
        SUB.L   (A3),D0                         | D0 = bytes used in buffer
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit count
        BEQ.B   CMP_FLUSH_RET                   | buffer empty, nothing to flush
        MOVE.L  (A4),A0                         | dereference map handle
        MOVE.L  D7,D2                           | D2 = cumulative file write position
        ADD.L   (A0),D2                         | D2 += data fork offset = absolute pos
        ADD.L   D2,D0                           | D0 = absolute end position
        ANDI    #-0x200,D0                      | round down to 512-byte boundary
        SUB.L   D2,D0                           | D0 = aligned byte count to write
        BLE.B   CMP_FLUSH_RET                   | nothing to write after alignment
        MOVE.L  (A3),D1                         | D1 = buffer base (source for write)
        BSR     CHECKLOAD_EMPTY_2               | write D0 bytes to file at position D2
        ADD.L   D0,D7                           | advance cumulative file write pos
        SUBA.L  D0,A1                           | adjust buffer write ptr (data shifted)
        SUB.L   D0,D4                           | adjust buffer read limit
        MOVE.L  A1,-(SP)                        | save adjusted write pointer
        MOVE.L  (A3),A1                         | A1 = buffer base (BlockMove dest)
        MOVE.L  (A3),A0                         | A0 = buffer base (source)
        ADDA.L  D0,A0                           | A0 += written bytes = unwritten start
        ADD.L   D4,D0                           | D0 = remaining unwritten bytes
        SUB.L   A0,D0                           | D0 = count of bytes to shift down
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit count
        _BlockMove                              | shift remaining data to buffer start
        MOVE.L  (SP)+,A1                        | restore buffer write pointer
CMP_FLUSH_RET:
        MOVEM.L (SP)+,D0-D2                     | restore working registers
        RTS                                     | complete buffer shift and return

| ----------------------------------------------------------
|
| _CloseResFile ($A99A)
|
| Closes a resource file: updates it, disposes all resource handles,
| unlinks its map from the chain, and closes the file.
| Called during boot.
CloseResFile:
        MOVE    #-0x1,(FONDID).w                | invalidate cached FOND ID
        CLR.L   (LastFOND).w                    | clear cached FOND handle
        MOVE    (RMgrLastResFile).w,D0          | D0 = last cached resource file refnum
        CMP     0x4(SP),D0                      | closing the cached file?
        BNE.B   CLOSERES_CHK_ALL                | no, leave cache alone
        CLR.L   (RMgrLastResHand).w             | invalidate cached resource handle
CLOSERES_CHK_ALL:
        TST     0x4(SP)                         | refnum = 0 (close all app files)?
        BNE.B   CLOSERES_FINDMAP                | no, close specific file
        BSR     RSRCZONEINIT_NEXT               | close all app resource files first
CLOSERES_FINDMAP:
        BSR     STDMAPENTRY                     | StdMapEntry: find map by refnum
        MOVE    D6,-(SP)                        | push refnum for UpdateResFile
        _UpdateResFile                          | flush any changed resources to disk
        MOVEQ.L #0x23,D0                        | trap number 0x23 = _DisposeHandle
        _GetTrapAddress                         | A0 = address of _DisposeHandle
        BSR     RESMGR_CONT_3                   | count all ref entries in this map
        BMI.B   CLOSERES_UNLINK                 | no entries, skip handle disposal
        MOVE.L  A0,A4                           | A4 = _DisposeHandle address
        ADDQ.W  #0x8,A2                         | advance to first ref entry's handle field
CLOSERES_DISP_LP:
        MOVE.L  (A2)+,D0                        | D0 = resource handle from ref entry
        BEQ.B   CLOSERES_DISP_NXT               | NIL handle, skip disposal
        MOVE.L  D0,A0                           | A0 = handle to dispose
        JSR     (A4)                            | call _DisposeHandle
CLOSERES_DISP_NXT:
        ADDQ.W  #0x8,A2                         | skip remaining 8 bytes to next ref handle
        DBF     D4,CLOSERES_DISP_LP             | loop through all ref entries
CLOSERES_UNLINK:
        BSR     RESMGR_CONT                     | find this map's predecessor in chain
        MOVE.L  PORTRECT(A3),A0                 | A0 = this map's next-map link
        TST.L   D0                              | was predecessor found?
        BNE.B   CLOSERES_PRED_LNK               | yes, unlink via predecessor
        MOVE.L  A0,(TopMapHndl).w               | no predecessor: set TopMap to next
        BRA.B   CLOSERES_CHK_SYS                | check if closing system map

| ----------------------------------------------------------
|
| CLOSERES_PRED_LNK - unlink map from chain via predecessor
|
CLOSERES_PRED_LNK:
        MOVE.L  D0,A1                           | A1 = predecessor map handle
        MOVE.L  (A1),A1                         | dereference predecessor
        MOVE.L  A0,0x10(A1)                     | predecessor->next = this map's next
CLOSERES_CHK_SYS:
        CMPA.L  (SysMapHndl).w,A4               | closing the system resource file?
        BNE.B   CLOSERES_UPD_CUR                | no, check CurMap update
        LEA.L   (TopMapHndl).w,A0               | A0 = ptr to TopMapHndl global
        MOVE.L  (ROMMapHandle).w,(A0)+          | TopMapHndl = ROM map handle
        MOVE.L  (ROMMapHandle).w,(A0)+          | SysMapHndl = ROM map handle
        MOVE.L  (OneOne).w,(A0)+                | SysMap/CurMap = refNum 1 (ROM)
        MOVE.L  (ROMMapHandle).w,A0             | dereference ROM map handle
        MOVE.L  (A0),A0                         | A0 = ROM map pointer
        CLR.L   0x10(A0)                        | ROM map has no next map (end of chain)
        BRA.B   CLOSERES_FILE                   | skip to file close

| ----------------------------------------------------------
|
| CLOSERES_UPD_CUR - update CurMap if closing the current resource file
|
| Called during boot.
CLOSERES_UPD_CUR:
        CMP     (CurMap).w,D6                   | closing the current resource file?
        BNE.B   CLOSERES_FILE                   | no, leave CurMap alone
        MOVE.L  (A0),A0                         | dereference next-map handle
        MOVE    0x14(A0),(CurMap).w             | CurMap = next map's refNum
CLOSERES_FILE:
        BSR     CHECKLOAD_CONT_9                | set up IOParam block for Close
        _Close                                  | close the resource fork file
        BEQ.B   CLOSERES_DISPOSE                | success, skip error store
        MOVE    D0,(ResErr).w                   | store Close error code
CLOSERES_DISPOSE:
        MOVE.L  A4,A0                           | A0 = map handle to dispose
        _DisposeHandle                          | free the in-memory resource map
        BRA     RESMGR_ERR_2                    | StdTwoExit

| ----------------------------------------------------------
|
| MakeRGBPat - Color QD stub, reused as _Count1Resources entry
|
| On the Mac Plus (no Color QD), this sets RMgrCurOnly to search
| only the current resource file, then falls through to CountResources.
MakeRGBPat:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| Called 3,781 times during 30s boot-to-Finder.
CountResources:
        BSR     RESMGR_CONT_6                   | minimal prologue: clear ResErr
        MOVE.L  (A0),D3                         | D3 = resource type to count
        MOVEQ.L #0x0,D1                         | D1 = running count (starts at 0)
        BSR     RETURNS_20                      | set up map chain traversal
COUNTRES_LOOP:
        BSR     RETURNS_26                      | find type D3 in current map
        BMI.B   COUNTRES_NEXTMAP                | type not found in this map
        ADD     contrlOwner(A2),D1              | D1 += count-1 for this type
        ADDQ.W  #0x1,D1                         | adjust for count-1 encoding (+1)
COUNTRES_NEXTMAP:
        BSR     RETURNS_22                      | advance to next map in chain
        BEQ.B   COUNTRES_LOOP                   | more maps, keep counting
        MOVE    D1,0xC(A6)                      | store total count as function result
        BRA     RESMGR_EXIT_5                   | StdFourExit

| ----------------------------------------------------------
|
| FillCRect - Color QD stub, reused as _Get1IndResource entry
|
FillCRect:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| Called 11,465 times during 30s boot-to-Finder.
GetIndResource:
        BSR     RESMGR_CONT_6                   | minimal prologue: clear ResErr
        MOVE    (A0)+,D7                        | D7 = 1-based index of desired resource
        BLE     GETIND_NOTFOUND                 | index <= 0 is invalid
        MOVE.L  (A0)+,D3                        | D3 = resource type to search for
        CLR.L   (A0)+                           | clear result handle (assume not found)
        MOVE.B  (RMgrCurOnly).w,D0              | D0 = current "search current only" flag
        CMP.B   (RMgrLastCurOnly).w,D0          | same search mode as last call?
        BNE.B   GETIND_FRESH                    | no, invalidate cache
        TST.L   (RMgrLastResHand).w             | is there a cached search position?
        BEQ.B   GETIND_FRESH                    | no, start fresh search
        CMP.L   (RMgrHiVars_LastResType).w,D3   | same type as last search?
        BNE.B   GETIND_FRESH                    | no, start fresh search
        CMP     (RMgrNextResIndex).w,D7         | sequential index (next after last)?
        BNE.B   GETIND_FRESH                    | no, start fresh search
        ADDQ.W  #0x1,(RMgrNextResIndex).w       | advance expected next index
        BSR     RESMGR_OK_3                     | restore cached search position
        TST     D4                              | any refs remaining in this type?
        BEQ.B   GETIND_CACHE_ADV                | no, advance to next type/map
        SUBQ.W  #0x1,D4                         | consume one ref from count
        ADDA    #0xC,A2                         | advance to next ref entry (12 bytes)
        BRA.B   GETIND_LOAD                     | go load this resource

| ----------------------------------------------------------
|
| GETIND_CACHE_ADV - cache hit but type exhausted, advance to next map
|
GETIND_CACHE_ADV:
        MOVEQ.L #0x0,D7                         | D7 = 0 (no more to skip)
        BRA.B   GETIND_NEXTMAP                  | advance to next map in chain

| ----------------------------------------------------------
|
| GETIND_FRESH - fresh search: iterate maps for nth resource of type
|
| Called during boot (11,458 times in 30s trace).
GETIND_FRESH:
        MOVE.B  D0,(RMgrLastCurOnly).w          | update cached search mode
        MOVE    D7,(RMgrNextResIndex).w         | cache current index
        ADDQ.W  #0x1,(RMgrNextResIndex).w       | set expected next index
        SUBQ.W  #0x1,D7                         | convert 1-based index to 0-based
        BSR     RETURNS_20                      | set up map chain traversal
GETIND_FIND_TYPE:
        BSR     RETURNS_26                      | find type D3 in current map
        BMI.B   GETIND_NEXTMAP                  | type not in this map, try next
        BSR     RETURNS_27                      | get ref list: D4=count-1, A2=refs
        CMP     D7,D4                           | enough refs to satisfy index?
        BMI.B   GETIND_SUB_SKIP                 | no, skip this map's refs
        SUB     D7,D4                           | D4 -= items skipped (remaining count)
        ADD     D7,D7                           | D7 *= 2
        ADD     D7,D7                           | D7 *= 4 (now 4x original skip count)
        ADDA    D7,A2                           | advance A2 by 4*skip
        ADD     D7,D7                           | D7 *= 8 (now 8x original)
        ADDA    D7,A2                           | advance A2 by 8*skip (total 12*skip)
        BRA.B   GETIND_LOAD                     | go load indexed resource

| ----------------------------------------------------------
|
| GETIND_SUB_SKIP - not enough refs in this map, subtract and continue
|
| Called during boot (7,490 times in 30s trace).
GETIND_SUB_SKIP:
        SUB     D4,D7                           | D7 -= refs available (count-1)
        SUBQ.W  #0x1,D7                         | D7 -= 1 more (count was count-1)
GETIND_NEXTMAP:
        BSR     RETURNS_22                      | advance to next map in chain
        BEQ.B   GETIND_FIND_TYPE                | found map, search its type list
        BMI.B   GETIND_NOTFOUND                 | end of chain, resource not found
GETIND_LOAD:
        BSR     RESMGR_CONT_15                  | cache search state in RMgr globals
        BSR     P_CheckLoad                     | load resource data if needed
        MOVE.L  A0,0xE(A6)                      | store result handle in stack frame
        MOVE.L  A0,(RMgrLastResHand).w          | cache as last-accessed resource
        BRA.B   GETIND_EXIT                     | exit

| ----------------------------------------------------------
|
| GETIND_NOTFOUND - resource not found by index
|
GETIND_NOTFOUND:
        MOVE    #-0xC0,(ResErr).w               | resNotFound (-192)
GETIND_EXIT:
        BRA     RESMGR_EXIT_4                   | epilogue: pop 6 bytes, return

| ----------------------------------------------------------
|
| SetCCursor - Color QD stub, reused as _Count1Types entry
|
SetCCursor:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| CountTypes -- _CountTypes ($A99E): FUNCTION CountTypes: Integer;
CountTypes:
        BSR     RESMGR_CONT_6                   | minimal prologue: clear ResErr
        BSR.B   COUNT_UNIQ_TYPES                | count unique types across all maps
        UNLK    A6                              | tear down COUNT_UNIQ_TYPES's local frame
        MOVE    D7,0x8(A6)                      | store unique type count as result
        BRA     RESMGR_EXIT_6                   | epilogue: pop 0 bytes, return

| ----------------------------------------------------------
|
| COUNT_UNIQ_TYPES - count unique resource types across all maps
|
| Walks every map in the chain, collecting unique resource types
| on the stack. Uses a linear search to avoid counting duplicates.
| Returns D7 = number of unique types found.
| Called during boot.
COUNT_UNIQ_TYPES:
        MOVE.L  (SP)+,A0                        | save return address in A0
        LINK    A6,#0x0                         | create frame (types pushed below SP)
        MOVEQ.L #0x0,D7                         | D7 = unique type count (starts at 0)
        BSR     RETURNS_20                      | set up map chain traversal
CNTTYPE_MAP_LOOP:
        BSR     RETURNS_23                      | get type list for current map
        BMI.B   CNTTYPE_NEXTMAP                 | empty type list, try next map
CNTTYPE_ENTRY_LP:
        MOVE.L  (A2),D3                         | D3 = resource type from type entry
        MOVE.L  A7,A1                           | A1 = stack pointer (unique types array)
        MOVE    D7,D0                           | D0 = count of unique types so far
        SUBQ.W  #0x1,D0                         | adjust for DBEQ loop (count-1)
        BMI.B   CNTTYPE_ADD_NEW                 | no types yet, add this one
CNTTYPE_CMP_LOOP:
        CMP.L   (A1)+,D3                        | compare with each known unique type
        DBEQ    D0,CNTTYPE_CMP_LOOP             | loop until match or exhausted
        BEQ.B   CNTTYPE_NEXT_ENT                | already known, skip to next entry
CNTTYPE_ADD_NEW:
        MOVE.L  D3,-(SP)                        | push new unique type onto stack
        ADDQ.W  #0x1,D7                         | increment unique type count
CNTTYPE_NEXT_ENT:
        ADDQ.L  #0x8,A2                         | advance to next type entry (8 bytes)
        DBF     D5,CNTTYPE_ENTRY_LP             | loop through all types in this map
CNTTYPE_NEXTMAP:
        BSR     RETURNS_22                      | advance to next map in chain
        BEQ.B   CNTTYPE_MAP_LOOP                | found map, scan its type list
        JMP     (A0)                            | return to caller (saved return addr)

| ----------------------------------------------------------
|
| FillCOval - Color QD stub, reused as _Get1IndType entry
|
FillCOval:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| GetIndType -- _GetIndType ($A99F): PROCEDURE GetIndType (VAR theType: ResType; index: Integer);
GetIndType:
        BSR     RESMGR_CONT_6                   | minimal prologue: clear ResErr
        MOVE    (A0)+,D2                        | D2 = 1-based index of desired type
        MOVE.L  (A0),D1                         | D1 = pointer to result variable
        BSR.B   COUNT_UNIQ_TYPES                | count unique types (builds stack array)
        MOVE.L  D1,A0                           | A0 = pointer to result variable
        CLR.L   (A0)                            | default result = 0 (no type found)
        SUBQ.W  #0x1,D2                         | convert 1-based index to 0-based
        BMI.B   GETINDTYPE_EXIT                 | index was <= 0, return empty
        CMP     D2,D7                           | is index within unique type count?
        BLE.B   GETINDTYPE_EXIT                 | no (D7 <= D2), return empty
        ASL     #0x2,D2                         | D2 *= 4 (each type is a longword)
        MOVE.L  0x0(A7,D2.W),(A0)               | copy indexed type from stack to result
GETINDTYPE_EXIT:
        UNLK    A6                              | tear down COUNT_UNIQ_TYPES's local frame
        BRA     RESMGR_EXIT_4                   | epilogue: pop 6 bytes, return

| ----------------------------------------------------------
|
| FillCRoundRect - Color QD stub, reused as _Unique1ID entry
|
FillCRoundRect:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| UniqueID -- _UniqueID ($A9C1): FUNCTION UniqueID (theType: ResType): Integer;
UniqueID:
        BSR     RESMGR_CONT_6                   | minimal prologue: clear ResErr
        MOVE    (Ticks_LoWord).w,D7             | D7 = initial seed from tick counter
UNIQID_RETRY:
        BSR     RETURNS_20                      | set up map chain traversal
        SUBQ.W  #0x2,SP                         | allocate space for Random result
        _Random                                 | generate random word on stack
        ADD     (SP)+,D7                        | add randomness to candidate ID
        ANDI    #0x7FFF,D7                      | force positive (resource IDs 0-32767)
        MOVE.L  0x8(A6),D3                      | D3 = resource type from parameter
        MOVE    D7,D2                           | D2 = candidate ID to test
UNIQID_CHECK:
        BSR     RETURNS_26                      | find type D3 in current map
        BMI.B   UNIQID_NEXTMAP                  | type not found, ID is unique here
        BSR     RETURNS_27                      | get ref list for this type
        BSR     RETURNS_25                      | search for ID D2 in ref list
        BEQ.B   UNIQID_RETRY                    | ID already exists, generate new one
UNIQID_NEXTMAP:
        BSR     RETURNS_22                      | advance to next map in chain
        BEQ.B   UNIQID_CHECK                    | more maps, keep checking uniqueness
        MOVE    D2,0xC(A6)                      | store unique ID as function result
        BRA     RESMGR_EXIT_5                   | StdFourExit

| ----------------------------------------------------------
|
| PlotCIcon - Color QD stub, reused as _Get1Resource entry
|
PlotCIcon:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| Called 11,438 times during 30s boot-to-Finder.
GetResource:
        BSR     RESMGR_CONT_6                   | minimal prologue: clear ResErr
        BSR     RETURNS_21                      | try CurMap first (fast path)
        BPL.B   GETRES_SEARCH                   | found CurMap, start search there
        BSR     RETURNS_20                      | set up full map chain traversal
GETRES_SEARCH:
        MOVE    (A0)+,D2                        | D2 = resource ID to find
        MOVE.L  (A0)+,D3                        | D3 = resource type to find
        CLR.L   (A0)                            | clear result handle (assume not found)
GETRES_FIND_TYPE:
        BSR     RETURNS_26                      | find type D3 in current map
        BMI.B   GETRES_NEXTMAP                  | type not in this map
        BSR     RETURNS_27                      | get ref list for this type
        BSR     RETURNS_25                      | search for ID D2 in ref list
        BEQ.B   GETRES_FOUND                    | found it, go load
GETRES_NEXTMAP:
        BSR     RETURNS_22                      | advance to next map in chain
        BEQ.B   GETRES_FIND_TYPE                | more maps, keep searching
        BRA.B   GETRES_EXIT                     | not found in any map

| ----------------------------------------------------------
|
| GETRES_FOUND - GetResource: found resource, cache and load
|
| Called during boot (11,369 times in 30s trace).
GETRES_FOUND:
        BSR     RESMGR_CONT_14                  | cache search state, reset index
        BSR     P_CheckLoad                     | load resource data if needed
        MOVE.L  A0,0xE(A6)                      | store result handle in stack frame
        MOVE.L  A0,(RMgrLastResHand).w          | cache as last-accessed resource
GETRES_EXIT:
        BRA     RESMGR_EXIT_4                   | epilogue: pop 6 bytes, return

| ----------------------------------------------------------
|
| OpenCPicture - Color QD stub, reused as _Get1NamedResource entry
|
OpenCPicture:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| GetNamedResource -- _GetNamedResource ($A9A1): FUNCTION GetNamedResource (theType: ResType; name: Str255): Handle;
GetNamedResource:
        BSR     RESMGR_CONT_6                   | minimal prologue: clear ResErr
        BSR.B   RETURNS_21                      | set up search from CurMap
        MOVE.L  (A0),A1                         | A1 = pointer to name string to find
        CLR.L   0x10(A6)                        | clear result handle (assume not found)
GETNAMED_LOOP:
        MOVE.L  0xC(A6),D3                      | D3 = resource type from parameter
        BSR     RETURNS_26                      | find type D3 in current map
        BMI.B   RESMGR_NEXT                     | type not in this map, try next
        BSR     RETURNS_27                      | get ref list for this type
GETNAMED_CMP_NAME:
        BSR     RESMGR_CONT_16                  | get name string for current ref entry
        BMI.B   RESMGR_SKIP                     | no name on this entry, skip
        MOVEQ.L #0x0,D0                         | clear D0 for length bytes
        MOVE.B  (A0)+,D0                        | D0.low = resource name length
        SWAP    D0                              | move to high word
        MOVE.B  (A1)+,D0                        | D0.low = search name length
        _CmpString                              | compare Pascal strings (case-insensitive)
        SUBQ.W  #0x1,A1                         | back up A1 to name start (undo A1++)
        BEQ.B   RESMGR_FOUND                    | strings match - resource found
