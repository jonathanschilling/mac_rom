| Resource Manager
|
| Apple source: ResourceMgr.a (MacSEROM.lst module RMGR). It starts with
| the empty-map template RESOURCE_MAP (used by CreateResFile), then
| InitResources, RsrcZoneInit, the file calls (CreateResFile, OpenResFile,
| UseResFile, Get/SetResFileAttrs, UpdateResFile, CloseResFile), the
| search calls (CountResources, GetIndResource, CountTypes, GetIndType,
| UniqueID, GetResource, GetNamedResource) and the resource calls
| (LoadResource, ReleaseResource, DetachResource, ChangedResource,
| WriteResource, HomeResFile, CurResFile, Get/SetResAttrs,
| Get/SetResInfo, AddResource, AddReference, RmveResource,
| RmveReference, ResError). The 64K ROM has no resources of its own.
|
| Resource file map structure (on disk and in memory):
| Offset 0: reserved for data offset LongInt
| Offset 4: reserved for map offset LongInt
| Offset 8: reserved for data length LongInt
| Offset 12: reserved for map length LongInt
| Offset 16: reserved for next map handle LongInt
| Offset 20: reserved for file ref num INTEGER
| Offset 22: file attributes INTEGER
| Offset 24: offset to type list INTEGER
| Offset 26: offset to name list INTEGER
| Offset 28: type list (number of types - 1, then type entries)
|
| Each type entry:
| Offset 0: resource type OSType (4 bytes, e.g. 'DRVR')
| Offset 4: count - 1 INTEGER
| Offset 6: offset to ref list INTEGER
|
| Each reference entry:
| Offset 0: resource ID INTEGER
| Offset 2: offset to name INTEGER (-1 if none)
| Offset 4: attributes BYTE + 3-byte offset to data
| Offset 8: reserved for handle LongInt
|
| Routines, in physical ROM order:
|   InitResources, RsrcZoneInit                    (init)
|   CreateResFile, OpenResFile                     (file create / open)
|   UseResFile, GetResFileAttrs, SetResFileAttrs   (current-file accessors)
|   UpdateResFile, CloseResFile                    (write / close)
|   SetResPurge, SetResLoad                        (load mode)
|   CountResources, GetIndResource,
|   CountTypes, GetIndType                         (enumeration)
|
| Resource Manager calling conventions (MPW 1.0 Resources.h):
| _InitResources -> INTEGER (system ref num)
| _OpenResFile stack: fileName -> INTEGER (ref num)
| _CloseResFile stack: refNum
| _GetResource stack: type, id -> Handle
| _CountTypes -> INTEGER
| _GetIndType stack: index -> type
| _CountResources stack: type -> INTEGER
| _GetIndResource stack: type, index -> Handle
| _LoadResource stack: handle
| _ReleaseResource stack: handle
| _AddResource stack: handle, type, id, name
| _ResError -> INTEGER (result code of last Resource Mgr call)
| References:
| Inside Macintosh Vol I, Ch 5: The Resource Manager

RESOURCE_MAP:                                   | 32-byte param blob + BSR to helper
        .short  0x0000, 0x0100                  | $D724-$D727
        .short  0x0000, 0x0100                  | $D728-$D72B
        .short  0x0000, 0x0000                  | $D72C-$D72F
        .short  0x0000, 0x001E                  | $D730-$D733
        .short  0x0000, 0x0000                  | $D734-$D737
        .short  0x0000, 0x0000                  | $D738-$D73B
        .short  0x001C, 0x001E                  | $D73C-$D73F
        .short  0xFFFF, 0x0000                  | $D740-$D743
| _GetIndResource inner loop: advance to next resource of matching type
| Called after RETURNS_24 sets up type list scan; iterates across types and maps

| ----------------------------------------------------------
| InitResources -- _InitResources ($A995). Plus does this work
| at boot in OPENRF_SET_FNAME (control_mgr.s 53). Loads System
| resource file (SysResName) into the system zone, sets up
| TopMapHndl/SysMapHndl/SysMap/CurMap globals, preloads flagged
| resources.
InitResources:
        BSR.W   RESMGR_PROLOG                   | $D744 -> $DCE4 (resource_mgr.s)
        LEA.L     (TheZone).w,A3                | save current zone
        MOVE.L  (A3),-(SP)                      | push current zone for restore
        MOVE.L  (SysZone).w,(A3)                | switch to system zone
        LEA.L     (SysResName).w,A1             | A1 = "System" filename
        BSR.B   NewMap                          | open file + allocate map (NewMap)
        MOVE.L  (SP)+,(A3)                      | restore zone
        MOVE    D6,8(A6)                        | store System refnum result
        TST.L   D0                              | NewMap success?
        BLE.B   INITRESOURCES_EXIT              | failed - skip globals setup
        LEA.L     (TopMapHndl).w,A0             | A0 -> resource manager globals
        MOVE.L  A2,(A0)+                        | TopMapHndl = SysMap handle
        MOVE.L  A2,(A0)+                        | SysMapHndl = SysMap handle
        MOVE    D6,(A0)+                        | SysMap = System refnum
        MOVE    D6,(A0)                         | CurMap = System refnum
        BSR.B   INITRES_LOADALL                 | preload flagged resources
INITRESOURCES_EXIT:
        BRA.W   CMP_WRITE_MAP_CONT_15           | epilog
INITRES_LOADALL:
        ST      (ResLoad).w                     | (ResLoad).w := -1 (true)
        BSR.W   RETURNS_21                      | walk all type entries in map
        BSR.W   STDMAPENTRY_CONT_2              | start ref-entry scan
        BMI.B   INITRES_LOADALL_DONE            | empty -> done
INITRES_LOADALL_LOOP:
        CLR.L   0x8(A2)                         | rHndl (+$8) := NIL (map just read from disk)
        BTST    #0x2,0x4(A2)                    | resPreload (bit 2) set in rAttr (+$4)?
        BEQ.B   INITRES_LOADALL_NEXT            | no -> skip resource
        BSR.W   RETURNS_28_CONT                 | yes -> load resource
INITRES_LOADALL_NEXT:
        BSR.W   STDMAPENTRY_CONT_3              | advance to next ref entry
        BEQ.B   INITRES_LOADALL_LOOP            | more -> continue scan
INITRES_LOADALL_DONE:
        RTS                                     | done preloading flagged resources
NewMap:
        MOVEQ.L #0x10,D0                        | allocate 16-byte map handle
        _NewHandle                              | map header fits in 16 bytes
        BMI.B   NEWMAP_ERR_3                    | NewHandle failed -> error exit
        MOVE.L  A0,A2                           | A2 = map handle
        BSR.W   CHECKLOAD_CONT_9                | set up IOParam for filename
        BSR.W   OPENRES_FORK                    | _OpenRF the resource fork
        BEQ.B   NEWMAP_GETEOF                   | success -> read map
        CMPI    #-0x31,D0                       | error eofErr (-49)?
        BNE.B   NEWMAP_ERR_2                    | other error -> dispose handle
        CLR     (ResErr).w                      | eof is non-fatal -> clear
        MOVE.L  A2,A0                           | A0 = map handle
        _DisposeHandle                          | free unused map handle
        RTS                                     | return with no map
NEWMAP_GETEOF:
        _GetEOF                                 | get fork length into ioLEOF
        MOVE    #-0x27,(ResErr).w               | assume mapReadErr (-39)
        TST.L   ioLEOF(A0)                      | resource fork EOF = 0?
        BEQ.B   NEWMAP_ERR                      | empty fork -> error
        MOVEQ.L #0x10,D0                        | read 16-byte resource header
        MOVE.L  (A2),A1                         | A1 = header destination buffer
        MOVE.L  A1,D1                           | D1 = buffer address for read
        MOVEQ.L #0x0,D2                         | D2 = file offset 0 (header)
        BSR.W   CHECKLOAD_CONT_10               | _SetFPos + _Read header
        BMI.B   NEWMAP_ERR                      | read failed -> error
        MOVEQ.L #0x10,D1                        | D1 = sizeof(header) = 16
        MOVE.L  4(A1),D2                        | A0 = handle of the topmost resource map
        ADD.L   D1,D2                           | D2 = mapOffset + 16 (skip header)
        MOVE.L  12(A1),D4                       | D4 = mapLength from header
        MOVE.L  D4,D0                           | A0 = pointer to the map header
        MOVE.L  A2,A0                           | Push the file reference number
        _SetHandleSize                          | grow handle to mapLength
        MOVE    D0,(ResErr).w                   | stash _SetHandleSize result
        BNE.B   NEWMAP_ERR                      | grow failed -> error
        MOVE.L  (A2),A1                         | A1 = grown map buffer
        MOVE.L  D4,D0                           | D0 = mapLength
        SUB.L   D1,D0                           | D0 -= 16 (skip header)
        ADD.L   A1,D1                           | D1 = read dest after header
        BSR.W   CHECKLOAD_CONT_10               | read map body
        BMI.B   NEWMAP_ERR                      | read failed -> error
        CLR.L   16(A1)                          | clear nextMap link
        MOVE    D6,20(A1)                       | store file refNum in map
        MOVEQ.L #0x1,D0                         | return D0 = 1 (loaded ok)
        RTS                                     | return success with map in A2
NEWMAP_ERR:
        BSR.W   CHECKLOAD_CONT_9                | reload IOParam for close
        _Close                                  | close opened resource fork
NEWMAP_ERR_2:
        MOVEA.L A2,A0                           | A0 = handle to dispose
        _DisposeHandle                          | free map handle
NEWMAP_ERR_3:
        MOVEQ.L #-0x1,D6                        | D6 = -1 (no refNum)
        MOVEQ.L #-0x1,D0                        | D0 = -1 (failure flag)
        RTS                                     | return failure

| ----------------------------------------------------------
| RsrcZoneInit -- _RsrcZoneInit ($A996). Reset Resource Manager
| state when application zone is reinitialized. Closes all open
| resource files except the system map, walks the system map's
| ref entries, clears each handle pointer if not from ROM map.
RsrcZoneInit:
        BSR.W   RESMGR_PROLOG                   | prologue
        TST     (SysMap).w                      | is Resource Mgr initialized?
        BMI.B   RSRCZONEINIT_EXIT               | no - just return
        BSR.B   RSRCZONEINIT_NEXT               | close all app res files
        BSR.W   RETURNS_21                      | find SysMap's map handle
        BSR.W   RETURNS_24                      | walk type list
        BMI.B   RSRCZONEINIT_EXIT               | empty - skip walk
RSRCZONEINIT_HANDLE_LOOP:
        BTST    #0x6,0x4(A2)                    | resSysHeap (bit 6) set in rAttr (+$4)?
        BNE.B   RSRCZONEINIT_HANDLE_NEXT        | in the system heap - keep the handle
        CLR.L   0x8(A2)                         | rHndl (+$8) := NIL (handle was in the app heap)
RSRCZONEINIT_HANDLE_NEXT:
        BSR.W   RETURNS_28                      | advance to next ref entry
        BPL.B   RSRCZONEINIT_HANDLE_LOOP        | more entries - continue
RSRCZONEINIT_EXIT:
        BRA.W   CMP_WRITE_MAP_CONT_15           | epilog

| ----------------------------------------------------------
| RSRCZONEINIT_NEXT
| Called during boot.
RSRCZONEINIT_NEXT:
        MOVE.L  (TopMapHndl).w,A0               | A0 = top of map chain
        CMPA.L  (SysMapHndl).w,A0               | reached system map?
        BEQ.B   OPENRES_FORK_EXIT               | reached system map -> return
        MOVE.L  (A0),A0                         | A0 = topmost map record
        MOVE    20(A0),-(SP)                    | push refNum from map header
        _CloseResFile                           | close that file (advances chain)
        BRA.B   RSRCZONEINIT_NEXT               | next-topmost
OPENRES_FORK:
        MOVE.L  A1,ioFileName(A0)               | ioFileName = filename ptr
        CLR     26(A0)                          | ioVersNum / ioPermssn = 0 (word-aligned)
        CLR.L   ioOwnBuf(A0)                    | ioOwnBuf = NIL (no private buffer)
        CLR     ioVRefNum(A0)                   | ioVRefNum = 0 (default volume)
        _OpenRF                                 | open resource fork by name
        MOVE    ioRefNum(A0),D6                 | D6 = ioRefNum from PB
        MOVE    D0,(ResErr).w                   | stash _OpenRF result code
OPENRES_FORK_EXIT:
        RTS                                     | return with refNum in D6

| ----------------------------------------------------------
| CreateResFile -- _CreateResFile ($A9B1). Plus 69. Creates a new
| resource file with empty 16-byte header + 30-byte null map.
CreateResFile:
        BSR.W   RESMGR_PROLOG                   | StdEntry: link A6, save regs
        MOVE.L  (A0),A1                         | A1 = filename pointer
        BSR.W   CHECKLOAD_CONT_9                | set up IOParam block from filename
        BSR.B   OPENRES_FORK                    | _OpenRF
        BEQ.B   CREATERES_CHKEOF                | success - check file size
        CMPI    #-0x2B,D0                       | error = fnfErr (-43)?
        BNE.B   CREATERES_CHKEOF_CONT           | other error -> exit
        _Create                                 | file not found, create it
        BSR.B   OPENRES_FORK                    | re-open
        BMI.B   CREATERES_CHKEOF_CONT           | re-open failed -> exit
CREATERES_CHKEOF:
        _GetEOF                                 | check resource fork size
        MOVE    #-0x30,(ResErr).w               | assume mapReadErr (-48)
        TST.L   ioLEOF(A0)                      | is resource fork empty (EOF=0)?
        BNE.B   CREATERES_CHKEOF_SKIP           | non-empty, skip initialization
        MOVEQ.L #0x10,D0                        | write 16-byte resource header
        LEA     RESOURCE_MAP(PC),A1             | point to null resource map template
        MOVE.L  A1,D1                           | source address for write
        BSR.W   CHECKLOAD_CONT_11               | write header at current position
        MOVEQ.L #0x1E,D0                        | write 30-byte null map (NullRMSize)
        MOVEQ.L #0x40,D2                        | D2 = 0x100 after shift
        ASL     #0x2,D2                         | D2 = 0x40 << 2 = 256 (file pos)
        BSR.W   CHECKLOAD_EMPTY_2               | write null map at offset 256
CREATERES_CHKEOF_SKIP:
        _Close                                  | close newly created file
CREATERES_CHKEOF_CONT:
        BRA.B   CREATERES_CHKEOF_ERR            | jump to common epilog

| ----------------------------------------------------------
| OpenResFile -- _OpenResFile ($A997). Plus 107. Opens a resource
| file (allocates map, links to TopMap chain, sets CurMap, preloads
| flagged resources).
OpenResFile:
        BSR.W   RESMGR_PROLOG                   | StdEntry: link A6, save regs
        MOVE.L  (A0),A1                         | A1 = filename pointer
        BSR.W   NewMap                          | open file, read map into memory
        MOVE    D6,12(A6)                       | store refnum as function result
        BMI.B   CREATERES_CHKEOF_ERR            | NewMap failed, skip linking
        MOVE    D6,(CurMap).w                   | set as current resource file
        TST     D0                              | check if ROM map needs linking
        BEQ.B   CREATERES_CHKEOF_ERR            | no, skip
        MOVE.L  (TopMapHndl).w,16(A1)           | new map->nextMap = old TopMap
        MOVE.L  A2,(TopMapHndl).w               | TopMapHndl = new map
        BSR.W   INITRES_LOADALL                 | preload flagged resources
CREATERES_CHKEOF_ERR:
        BRA.W   RESMGR_EXIT_5                   | ResMgr StdExit (UNLK + return)

| ----------------------------------------------------------
| UseResFile -- _UseResFile ($A998). Plus 145. Sets CurMap to refnum.
UseResFile:
        BSR.B   STDMAPENTRY                     | find map by refnum
        MOVE    D6,(CurMap).w                   | CurMap = refnum
        BRA.B   STDMAPENTRY_CONT                | epilog

| ----------------------------------------------------------
| GetResFileAttrs -- _GetResFileAttrs ($A9F6). Plus 157.
| Returns the resFileAttrs byte for a resource file refnum.
GetResFileAttrs:
        BSR.B   STDMAPENTRY                     | find map by refnum
        MOVE.B  0x16(A3),11(A6)                 | return map attributes (mAttr, +$16)
        BRA.B   STDMAPENTRY_CONT                | epilog

| ----------------------------------------------------------
| SetResFileAttrs -- _SetResFileAttrs ($A9F7). Plus 168.
| Sets resFileAttrs byte for a resource file refnum.
SetResFileAttrs:
        BSR.W   RESMGR_PROLOG                   | StdEntry: link A6, save regs
        MOVE    10(A6),D6                       | D6 = refnum from stack frame
        BSR.W   RESMGR_CONT                     | GetMap: find map by refnum
        BMI.B   CREATERES_CHKEOF_SKIP_2         | map not found, skip
        MOVE.B  9(A6),0x16(A3)                  | set map attributes (mAttr, +$16)
CREATERES_CHKEOF_SKIP_2:
        BRA.B   CREATERES_CHKEOF_ERR            | ResMgr StdExit

| ----------------------------------------------------------
| STDMAPENTRY - StdMapEntry
| Standard entry for routines that take a refnum parameter.
| Calls StdEntry, reads refnum from stack, finds the map.
| On failure, pops return address and exits with resNotFound.
| Called during boot.
STDMAPENTRY:
        MOVE.L  (SP)+,D0                        | save return address
        BSR.W   RESMGR_PROLOG                   | StdEntry: link A6, save regs
        MOVE.L  D0,-(SP)                        | restore return address
        MOVE    (A0),D6                         | get refnum from parameter area
        BSR.W   RESMGR_CONT                     | GetMap: find map by refnum in D6
        BMI.B   STDMAPENTRY_ERR_2               | not found, error exit
        RTS                                     | return to caller (map in A3)
STDMAPENTRY_ERR_2:
        ADDQ.W  #0x4,SP                         | discard caller's return address
        MOVE    #-0xC1,(ResErr).w               | resFNotFound (-193)
STDMAPENTRY_CONT:
        BRA.W   CMP_WRITE_MAP_SKIP              | StdTwoExit
STDMAPENTRY_CONT_2:
        MOVEQ.L #-0x1,D0                        | D0 = -1 (start before any entry)
        BRA.B   FINDNEXT_ENTER                  | enter FindNext loop
STDMAPENTRY_CONT_3:
        MOVE.L  0x4(A2),D0                      | D0 = current entry attrs+offset (rLocn, +$4)
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit data offset
FINDNEXT_ENTER:
        MOVEM.L D2-D7/A3-A4,-(SP)               | save registers
        MOVE.L  D0,D2                           | D2 = minimum data offset
        BSR.W   RETURNS_24                      | count all reference entries
        BMI.B   FINDNEXT_RTS                    | no entries -> failure
        LEA.L     (MinusOne).w,A0               | A0 = MinusOne lowmem
        SUBQ.L  #0x4,A0                         | A0 = sentinel address
        MOVE.L  A0,D6                           | D6 = best-entry sentinel
        MOVEQ.L #-0x1,D7                        | D7 = 0x7FFFFFFF (max offset)
        LSR.L   #0x1,D7                         | largest positive long
FINDNEXT_LOOP:                                  | iterate through entries
        TST.B    0x4(A2)                        | resSysRef (bit 7 of rAttr, +$4) set?
        BMI.B    STDMAPENTRY_SKIP               | yes -> skip (system reference, no data here)
        MOVE.L  0x4(A2),D0                      | get attrs+offset of this entry (rLocn, +$4)
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit data offset
        CMP.L   D0,D2                           | offset > minimum?
        BGE.B   STDMAPENTRY_SKIP                | no, skip
        CMP.L   D0,D7                           | offset < current best?
        BLE.B   STDMAPENTRY_SKIP                | no, skip
        MOVE.L  D0,D7                           | update best offset
        MOVE.L  A2,D6                           | update best entry pointer
STDMAPENTRY_SKIP:
        BSR.W   RETURNS_28                      | advance to next ref entry
        BPL.B   FINDNEXT_LOOP                   | more entries -> check next
FINDNEXT_DONE:
        MOVE.L  D6,A2                           | A2 = best matching ref entry
        MOVE.L  D7,D0                           | D0 = best offset found
        MOVE.L  0x4(A2),D7                      | get attrs+offset of best entry (rLocn, +$4)
        AND.L   (Lo3Bytes).w,D7                 | mask to data offset
        CMP.L   D0,D7                           | set Z if valid match found
FINDNEXT_RTS:
        MOVEM.L  (SP)+,D2-D7/A3-A4              | restore D2-D7, A3-A4
        RTS                                     | return Z=1 if entry found
FINDNEXT_OFS:
        MOVEM.L D7-A2,-(SP)                     | save D7 + A2
        MOVE.L  0x4(A2),D0                      | D0 = current entry attrs+offset (rLocn, +$4)
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit data offset
        MOVE.L  D0,D7                           | D7 = current data offset
        BSR.B   STDMAPENTRY_CONT_3              | find next greater offset
        BPL.B   FINDNEXT_OFS_LO                 | next found -> compute size
        MOVE.L  (A4),A0                         | A0 = map header pointer
        MOVE.L  4(A0),D0                        | D0 = mapOffset (end of data)
        SUB.L   D7,D0                           | D0 -= current offset
        SUB.L   (A0),D0                         | D0 -= dataOffset (size to fork end)
        MOVEQ.L #-0x1,D7                        | D7 = -1 (no more entries)
        BRA.B   FINDNEXT_OFS_RTS                | return last-entry size
FINDNEXT_OFS_LO:
        SUB.L   D7,D0                           | D0 = nextOffset - thisOffset (size)
FINDNEXT_OFS_RTS:
        MOVEM.L (SP)+,D7-A2                     | restore D7 + A2
        RTS                                     | return: D0 = size, D7 = next offset

| ----------------------------------------------------------
| UpdateResFile -- _UpdateResFile ($A999). Plus 316.
| Walks all changed resources for a refnum and writes them out,
| then writes the map back. If mapCompact is set, does full
| compaction (the "FindNext + write changed + maybe compact" loop).
UpdateResFile:
        BSR.W   STDMAPENTRY                     | find map by refnum
        BSR.W   CHECKLOAD_OK_4                  | test file read-only
        BNE.W   CMP_WRITE_MAP_SKIP              | read-only - skip
        BSR.W   STDMAPENTRY_CONT_2              | start ref-entry scan
        BMI.B   UPDRES_CHECK_COMPACT            | empty map - skip walk
UPDRES_WRITE_LOOP:
        BTST    #0x1,0x4(A2)                    | resChanged (bit 1) set in rAttr (+$4)?
        BEQ.B   UPDRES_WRITE_NEXT               | no -> skip write
        BSR.W   CHECKLOAD_CONT_8                | _WriteResource for this entry
UPDRES_WRITE_NEXT:
        BSR.W   STDMAPENTRY_CONT_3              | advance to next ref entry
        BEQ.B   UPDRES_WRITE_LOOP               | more entries -> continue
UPDRES_CHECK_COMPACT:
        BCLR    #0x6,0x16(A3)                   | test+clear mapCompact in mAttr (+$16)
        BEQ.B   CMP_WRITE_MAP                   | flag was clear -> just write map
        ST      (ResLoad).w                     | (ResLoad).w := -1 (true)
        BSR.W   STDMAPENTRY_CONT_2              | FindNext from start
        BNE.B   UPDRES_FIXUP                    | no entries -> just fix data fork
        MOVE.L  D0,D7                           | D7 = first entry's offset
        NEG.L   D7                              | D7 = -firstOffset (gap to remove)
UPDRES_ADJ_LOOP:
        TST.L   D7                              | any gap to compact?
        BEQ.B   UPDRES_ADJ_NEXT                 | no gap -> skip move
        BSR.W   RETURNS_28_CONT                 | move resource data forward
        LEA.L     0x4(A2),A0                    | A0 = &rLocn (+$4): attr byte + 3-byte offset
        MOVE.B  (A0),D0                         | D0 = saved attr byte
        CLR.B   (A0)                            | isolate offset bytes
        ADD.L   D7,(A0)                         | (A0) += D7
        MOVE.B  D0,(A0)                         | restore attr byte
        BSR.W   CHECKLOAD_CONT_8                | _WriteResource at new offset
UPDRES_ADJ_NEXT:
        BSR.B   FINDNEXT_OFS                    | advance + measure size
        BMI.B   UPDRES_FIXUP                    | no more -> finalize
        MOVE.L  D0,D7                           | D7 = data block size
        NEG.L   D7                              | D7 = -size
        BSR.W   CHECKLOAD_CONT_5                | compute resource entry overhead
        ADDQ.L  #0x4,D0                         | add 4-byte length prefix
        ADD.L   D0,D7                           | D7 += overhead (now signed gap)
        BSR.W   STDMAPENTRY_CONT_3              | advance to next entry
        BRA.B   UPDRES_ADJ_LOOP                 | continue compaction loop
UPDRES_FIXUP:
        ADD.L   D7,8(A3)                        | 8(A3) += D7
CMP_WRITE_MAP:
        BCLR    #0x5,0x16(A3)                   | clear+test mapChanged in mAttr (+$16)
        BEQ.B   CMP_WRITE_MAP_SKIP              | was not set, skip map rewrite
        MOVE.L  8(A3),D2                        | D2 = resource data length (dataSize, +$8)
        ADD.L   (A3),D2                         | D2 += resDataOffset = map file position
        MOVE.L  D2,0x4(A3)                      | update map offset in header (resMapOffset, +$4)
        MOVE.L  12(A3),D0                       | D0 = map length (header field at +0xC)
        MOVE.L  A3,D1                           | D1 = map data source address
        BSR.W   CHECKLOAD_EMPTY_2               | write map data to file at position D2
        MOVEQ.L #0x10,D0                        | D0 = 16 bytes (resource file header)
        BSR.W   CHECKLOAD_CONT_11               | write 16-byte header at file position 0
        BSR.W   CHECKLOAD_OK_3                  | set EOF and flush file
CMP_WRITE_MAP_SKIP:
        MOVEQ.L #0x2,D0                         | strip 2-byte refNum param
        BRA.W   RESMGR_EPILOG                   | ResMgr epilog (UNLK + return)

| ----------------------------------------------------------
| CloseResFile -- _CloseResFile ($A99A). Plus 734.
| Closes a resource file. If refnum=0, closes all app res files
| first via RsrcZoneInit. Calls _UpdateResFile to flush, then
| walks ref entries disposing all resource handles, unlinks the
| map from the chain, and closes the file.
CloseResFile:
        TST     4(SP)                           | refnum = 0 (close all app)?
        BNE.B   CMP_WRITE_MAP_CONT              | no - close specific file
        BSR.W   RSRCZONEINIT_NEXT               | yes - close all app files first
CMP_WRITE_MAP_CONT:
        BSR.W   STDMAPENTRY                     | find map by refNum, set up frame
        MOVE    D6,-(SP)                        | push refNum
        _UpdateResFile                          | flush map + changed resources
        BSR.W   RETURNS_24                      | walk type list of this map
CMP_WRITE_MAP_CONT_2:
        TST.B   0x4(A2)                         | resSysRef (bit 7 of rAttr, +$4) set?
        BMI.B   CMP_WRITE_MAP_CONT_3            | yes -> skip (system reference, no handle)
        MOVE.L  0x8(A2),D0                      | D0 = resource handle (rHndl, +$8)
        BEQ.B   CMP_WRITE_MAP_CONT_3            | nil handle -> skip
        MOVE.L  D0,-(SP)                        | push handle
        _ReleaseResource                        | dispose loaded resource
CMP_WRITE_MAP_CONT_3:
        BSR.W   RETURNS_28                      | advance to next ref entry
        BPL.B   CMP_WRITE_MAP_CONT_2            | more entries -> continue
        BSR.W   RESMGR_CONT                     | find this map's predecessor in chain
        MOVE.L  16(A3),A0                       | A0 = this map's next-map link (mNext, +$10)
        TST.L   D0                              | was predecessor found?
        BNE.B   CMP_WRITE_MAP_OK                | yes, unlink via predecessor
        MOVE.L  A0,(TopMapHndl).w               | no predecessor: set TopMap to next
        BRA.B   CMP_WRITE_MAP_CONT_4            | check if closing system map
CMP_WRITE_MAP_OK:
        MOVE.L  D0,A1                           | A1 = predecessor map handle
        MOVE.L  (A1),A1                         | A1 = predecessor map record
        MOVE.L  A0,16(A1)                       | predecessor.nextMap = our nextMap
CMP_WRITE_MAP_CONT_4:
        CMPA.L  (SysMapHndl).w,A4               | closing the system map?
        BNE.B   CMP_WRITE_MAP_CONT_5            | no -> just maintain CurMap
        LEA.L     (TopMapHndl).w,A0             | A0 = ResMgr globals base
        CLR.L   (A0)+                           | clear TopMapHndl
        CLR.L   (A0)+                           | clear SysMapHndl
        ST      (A0)+                           | (A0)+ := -1 (true)
        ST      (A0)+                           | (A0)+ := -1 (true)
        BRA.B   CMP_WRITE_MAP_NO                | skip CurMap update path
CMP_WRITE_MAP_CONT_5:
        CMP     (CurMap).w,D6                   | closing the current resource file?
        BNE.B   CMP_WRITE_MAP_NO                | no, leave CurMap alone
        MOVE.L  (A0),A0                         | dereference next-map handle
        MOVE    20(A0),(CurMap).w               | CurMap = next map's refNum
CMP_WRITE_MAP_NO:
        BSR.W   CHECKLOAD_CONT_9                | set up IOParam for close
        _Close                                  | close resource fork
        MOVE    D0,(ResErr).w                   | store Close result in ResErr
        MOVEA.L A4,A0                           | A0 = MapList handle
        _DisposeHandle                          | release the map
        BRA.B   CMP_WRITE_MAP_SKIP              | ResMgr StdExit

| ----------------------------------------------------------
| SetResPurge -- _SetResPurge ($A993). Plus 1244.
| Install or remove the auto-write purge proc on the heap zone.
| When true, makes Memory Manager call back through CMP_WRITE_MAP_CONT_7
| before purging a resource handle, so changed resources get written.
SetResPurge:
        MOVE.L  (ApplZone).w,A0                 | A0 = ApplZone (purge proc target)
        MOVE.L  (SP)+,D0                        | D0 = return address
        TST.B   (SP)+                           | test Boolean install param
        PEA.L   CMP_WRITE_MAP_CONT_7(PC)        | push purge-proc address as default
        BNE.B   CMP_WRITE_MAP_CONT_6            | true - install
        CLR.L   (SP)                            | false - clear
CMP_WRITE_MAP_CONT_6:
        MOVE.L  (SP)+,0x28(A0)                  | store purge proc in zone header
        MOVE.L  D0,-(SP)                        | push return addr back
        RTS                                     | return after purge proc set

| ----------------------------------------------------------
| CMP_WRITE_MAP_CONT_7 -- Memory Mgr purge-time callback (PURGE_PROC).
| Plus equivalent: HOMERESFILE_CONT (resource_mgr.s 1230). When
| Memory Manager is about to purge a handle, this is called via
| zone purge proc. If the handle has the resource flag (bit 5)
| set, calls _WriteResource before allowing purge.
CMP_WRITE_MAP_CONT_7:
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = handle being purged
        BTST    #0x5,(A0)                       | test resource flag in master ptr
        BEQ.B   CMP_WRITE_MAP_CONT_8            | not a resource - skip write
        MOVE.L  A0,-(SP)                        | push handle for WriteResource
        _WriteResource                          | auto-save changed resource
CMP_WRITE_MAP_CONT_8:
        JMP     (A1)                            | return to Memory Manager

| ----------------------------------------------------------
| SetResLoad -- _SetResLoad ($A99B). Plus 1264.
| Sets the ResLoad global from a Boolean parameter.
SetResLoad:
        MOVE.L  (SP)+,A0                        | A0 = return address
        MOVE.B  (SP)+,(ResLoad).w               | set ResLoad from Boolean
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| CountResources -- _CountResources ($A99C).
| Counts resources of a given type across all maps in the chain.
CountResources:
        BSR.W   RESMGR_PROLOG                   | minimal prologue: clear ResErr
        MOVE.L  (A0),D1                         | D1 = ResType from caller
        MOVEQ.L #0x0,D7                         | D7 = count
        BSR.B   CMP_WRITE_MAP_CONT_9            | scan all maps via shared helper
        NEG     D7                              | D7 = positive count
        MOVE    D7,12(A6)                       | store result
        BRA.W   RESMGR_EXIT_5                   | ResMgr StdExit
CMP_WRITE_MAP_CONT_9:
        BSR.W   RETURNS_20                      | set up map chain traversal
CMP_WRITE_MAP_CONT_10:
        MOVE.L  D1,D3                           | D3 = ResType to find
        BSR.W   RETURNS_26                      | locate type entry in current map
        BMI.B   CMP_WRITE_MAP_CONT_12           | type not in this map -> next map
        BSR.W   RETURNS_27                      | walk ref entries of this type
CMP_WRITE_MAP_CONT_11:
        TST.B   0x4(A2)                         | test attr byte of this ref entry
        BMI.B   GETINDRES_SCAN_SKIP             | resSysRef (bit 7) set -> skip (reference entry)
        SUBQ.W  #0x1,D7                         | count this entry (decrement D7)
        BEQ.B   CMP_WRITE_MAP_CONT_13           | reached desired index -> exit
GETINDRES_SCAN_SKIP:
        BSR.W   RETURNS_28                      | advance to next ref entry
        BEQ.B   CMP_WRITE_MAP_CONT_11           | more entries -> continue
CMP_WRITE_MAP_CONT_12:
        BSR.W   RESMGR_NEXT_2                   | advance to next map in chain
        BEQ.B   CMP_WRITE_MAP_CONT_10           | map found -> scan it
CMP_WRITE_MAP_CONT_13:
        RTS                                     | done scanning all maps

| ----------------------------------------------------------
| GetIndResource -- _GetIndResource ($A99D).
| Returns the i-th resource of a given type. Uses shared scan
| helper CMP_WRITE_MAP_CONT_9 (which terminates on D7=0 instead
| of running through all entries).
GetIndResource:
        BSR.W   RESMGR_PROLOG                   | minimal prologue: clear ResErr
        MOVE    (A0)+,D7                        | D7 = 1-based index
        BLE.B   CMP_WRITE_MAP_OK_2              | <= 0 - return NIL
        MOVE.L  (A0)+,D1                        | D1 = ResType
        CLR.L   (A0)+                           | clear handle output slot
        BSR.B   CMP_WRITE_MAP_CONT_9            | find Nth resource of type
        BMI.B   CMP_WRITE_MAP_OK_2              | not found - return NIL
CMP_WRITE_MAP_CONT_14:
        BSR.W   RETURNS_28_CONT                 | load handle from ref entry -> A0
        MOVE.L  A0,14(A6)                       | store handle as result
CMP_WRITE_MAP_OK_2:
        MOVEQ.L #0x6,D0                         | strip 6-byte Pascal params
        BRA.B   CMP_WRITE_MAP_CONT_16           | jump to ResMgr epilog

| ----------------------------------------------------------
| CountTypes -- _CountTypes ($A99E).
| Returns count of unique resource types across all maps.
CountTypes:
        BSR.W   RESMGR_PROLOG                   | minimal prologue: clear ResErr
        BSR.B   CMP_WRITE_MAP_CONT_17           | build unique-types stack array
        UNLK    A6                              | tear down COUNT_UNIQ_TYPES's local frame
        MOVE    D7,8(A6)                        | store unique type count as result
CMP_WRITE_MAP_CONT_15:
        MOVEQ.L #0x0,D0                         | strip 0 bytes (no params)
CMP_WRITE_MAP_CONT_16:
        BRA.W   RESMGR_EPILOG                   | ResMgr epilog (UNLK + return)
| ----------------------------------------------------------
| CMP_WRITE_MAP_CONT_17 -- Build unique-types stack array.
| Walks all maps, pushing each unique resource type onto the
| stack. On exit: D7 = unique type count, stack has D7 4-byte
| type entries below A6. Caller (CountTypes/GetIndType) is
| responsible for the UNLK A6.
CMP_WRITE_MAP_CONT_17:
        MOVE.L  (SP)+,A0                        | save return address in A0
        LINK    A6,#0x0                         | create frame (types pushed below SP)
        MOVEQ.L #0x0,D7                         | D7 = unique type count (starts at 0)
        BSR.W   RETURNS_20                      | set up map chain traversal
CMP_WRITE_MAP_FOUND:
        BSR.W   RETURNS_23                      | load type list for this map ($DCA0)
        BMI.B   CNTTYPE_NEXT_MAP                | no types -> advance to next map
CNTTYPE_ENTRY_LP:
        MOVE.L  (A2),D3                         | D3 = resource type from type entry
        MOVE.L  SP,A1                           | A1 = stack pointer (unique types array)
        MOVE    D7,D0                           | D0 = count of unique types so far
        SUBQ.W  #0x1,D0                         | adjust for DBEQ loop (count-1)
        BMI.B   CNTTYPE_ENTRY_LP_NO             | no types yet, add this one
CNTTYPE_ENTRY_LP_LOOP:
        CMP.L   (A1)+,D3                        | already in unique-types array?
        BEQ.B   CNTTYPE_ENTRY_LP_CONT           | yes -> skip duplicate
        DBRA    D0,CNTTYPE_ENTRY_LP_LOOP        | next array slot
CNTTYPE_ENTRY_LP_NO:
        MOVE.L  D3,-(SP)                        | push new unique type onto array
        ADDQ.W  #0x1,D7                         | unique count++
CNTTYPE_ENTRY_LP_CONT:
        ADDQ.L  #0x8,A2                         | advance to next type entry (8 bytes)
        DBRA    D5,CNTTYPE_ENTRY_LP             | next type entry in this map
CNTTYPE_NEXT_MAP:
        BSR.W   RESMGR_NEXT_2                   | advance to next map in chain
        BEQ.B   CMP_WRITE_MAP_FOUND             | found map, scan its type list
        JMP     (A0)                            | return to caller (saved return addr)

| ----------------------------------------------------------
| GetIndType -- _GetIndType ($A99F).
| Returns the i-th unique resource type across all maps.
| Builds the unique-types stack array via CMP_WRITE_MAP_CONT_17,
| then indexes into it.
GetIndType:
        BSR.W   RESMGR_PROLOG                   | minimal prologue: clear ResErr
        MOVE    (A0)+,D2                        | D2 = 1-based index of desired type
        MOVE.L  (A0),D1                         | D1 = pointer to result variable
        BSR.B   CMP_WRITE_MAP_CONT_17           | build unique-types stack array
        MOVE.L  D1,A0                           | A0 = pointer to result variable
        CLR.L   (A0)                            | default result = 0 (no type found)
        SUBQ.W  #0x1,D2                         | convert 1-based index to 0-based
        BMI.B   CNTTYPE_ENTRY_LP_EXIT           | index was <= 0, return empty
        CMP     D2,D7                           | is index within unique type count?
        BLE.B   CNTTYPE_ENTRY_LP_EXIT           | no (D7 <= D2), return empty
        ASL     #0x2,D2                         | D2 *= 4 (4 bytes per type entry)
        MOVE.L  0(SP,D2.W),(A0)                 | copy indexed type from stack to result
CNTTYPE_ENTRY_LP_EXIT:
        UNLK    A6                              | tear down frame
        BRA.B   CMP_WRITE_MAP_OK_2              | jump to ResMgr epilog
| ----------------------------------------------------------
|
| _UniqueID ($A9C1): return a resource ID not used in any open resource file
| Pascal: FUNCTION UniqueID(theType: ResType): INTEGER;
| Candidate ID := (previous candidate + Random) AND $7FFF, starting from
| the low word of Ticks. Walks the whole map chain from TopMapHndl and
| retries (UNIQID_RETRY) as soon as a resource of theType with that ID is
| found. The result is in 0..32767 (0 is not excluded).
|
UniqueID:
        BSR.W   RESMGR_PROLOG                   | StdEntry: link A6, save regs
        MOVE    (Ticks_LoWord).w,D7             | D7 = Ticks low word (initial seed)
UNIQID_RETRY:
        BSR.W   RETURNS_20                      | start at the top map (TopMapHndl)
        SUBQ.W  #0x2,SP                         | allocate space for Random result
        _Random                                 | generate random word on stack
        ADD     (SP)+,D7                        | add randomness to seed
        ANDI    #0x7FFF,D7                      | force positive (resource IDs 0..32767)
        MOVE.L  8(A6),D3                        | D3 = resource type from parameter
        MOVE    D7,D2                           | D2 = candidate ID to test
UNIQID_CHECK:
        BSR.W   RETURNS_26                      | find type D3 in current map
        BMI.B   UNIQID_NEXTMAP                  | type not present, ID is unique here
        BSR.W   RETURNS_27                      | get ref list for this type
        BSR.W   RESMGR_LOOP_4                   | search ref list for ID D2
        BEQ.B   UNIQID_RETRY                    | ID already taken, retry with new seed
UNIQID_NEXTMAP:
        BSR.W   RESMGR_NEXT_2                   | advance to next map in chain
        BEQ.B   UNIQID_CHECK                    | more maps - keep checking uniqueness
        MOVE    D2,12(A6)                       | store unique ID as function result
        BRA.W   RESMGR_EXIT_5                   | epilogue: pop params, return

| ----------------------------------------------------------
| GetResource -- _GetResource ($A9A0).
| Pascal: function GetResource(theType: ResType; theID: INTEGER): Handle;
| Searches the resource map chain for a resource by type and ID.
| Plus 1986 added a CurMap fast-path (try current map first via
| BPL.B GETRES_SEARCH after RETURNS_21, only fall back to full
| chain if not found via RETURNS_20); classic 1984 always does
| the full chain traversal directly via RESMGR_PROLOG.
GetResource:
        BSR.W   RESMGR_PROLOG                   | full prologue: clear ROMMapInsert/CurOnly/ResErr
        BSR.W   RETURNS_21                      | set up search from TopMapHndl
        MOVE    (A0)+,D2                        | D2 = resource ID
        MOVE.L  (A0)+,D3                        | D3 = resource type
        CLR.L   (A0)                            | clear result handle (nil = not found)
GETRES_FIND_TYPE:
        BSR.W   RETURNS_26                      | find type D3 in current map
        BMI.B   GETRES_NEXTMAP                  | type not in this map, try next
        BSR.W   RETURNS_27                      | get ref list for this type
        BSR.W   RESMGR_LOOP_4                   | search ref list for ID D2
        BEQ.W   CMP_WRITE_MAP_CONT_14           | found - go cache and load
GETRES_NEXTMAP:
        BSR.W   RESMGR_NEXT_2                   | advance to next map in chain
        BEQ.B   GETRES_FIND_TYPE                | more maps - keep searching
        BRA.W   CMP_WRITE_MAP_OK_2              | not found in any map - exit

| ----------------------------------------------------------
| GetNamedResource -- _GetNamedResource ($A9A1).
| Pascal: function GetNamedResource(theType: ResType; name: Str255): Handle;
| Searches the resource map chain for a resource by type and name.
| Plus 1986 uses the same CurMap fast-path optimization as
| GetResource (BSR RESMGR_CONT_6 minimal prologue); classic 1984
| uses the full RESMGR_PROLOG with full-chain traversal.
GetNamedResource:
        BSR.W   RESMGR_PROLOG                   | full prologue
        BSR.B   RETURNS_21                      | set up search from TopMapHndl
        MOVE.L  (A0),A1                         | A1 = pointer to name string
        CLR.L   16(A6)                          | clear result handle (nil = not found)
GETNAMED_LOOP:
        MOVE.L  12(A6),D3                       | D3 = resource type from parameter
        BSR.W   RETURNS_26                      | find type D3 in current map
        BMI.B   RESMGR_NEXT                     | type not in this map, try next
        BSR.W   RETURNS_27                      | get ref list for this type
GETNAMED_CMP_NAME:
        BSR.W   RESMGR_CONT_16                  | get name string for current ref
        BMI.B   RESMGR_SKIP                     | no name on this entry, skip
        MOVEQ.L #0x0,D0                         | clear D0 for length bytes
        MOVE.B  (A0)+,D0                        | D0.low = resource name length
        SWAP    D0                              | move resource length to high word
        MOVE.B  (A1)+,D0                        | D0.low = search name length
        _CmpString                              | compare Pascal strings (case-insens)
        SUBQ.W  #0x1,A1                         | restore A1 to before length byte
        BEQ.B   GETNAMED_FOUND                  | name matched - go return handle
RESMGR_SKIP:
        BSR.W   RETURNS_28                      | advance to next ref entry in list
        BEQ.B   GETNAMED_CMP_NAME               | more refs - check next name
RESMGR_NEXT:
        BSR.B   RESMGR_NEXT_2                   | advance to next map in chain
        BEQ.B   GETNAMED_LOOP                   | more maps - keep searching
        BRA.B   GETNAMED_EXIT                   | name not found in any map
GETNAMED_FOUND:
        BSR.W   RETURNS_28_CONT                 | load resource and get handle in A0
        MOVE.L  A0,16(A6)                       | store result handle in stack frame
GETNAMED_EXIT:
        MOVEQ.L #0x8,D0                         | D0 = 8 bytes of params to pop
        BRA.W   RESMGR_EPILOG                   | epilogue: pop 8, return
RETURNS_20:
        MOVE.L  (TopMapHndl).w,A4               | A4 = top of map chain
        MOVE.L  (A4),A3                         | dereference top map handle
        MOVE    20(A3),D6                       | D6 = top map's filRefNum
        BRA.B   RESMGR_LOOP_CONT                | jump into common map setup tail
RETURNS_21:
        MOVE    (CurMap).w,D6                   | D6 = current resource file refNum
RESMGR_CONT:
        TST     D6                              | negative = invalid
        BMI.W   RESMGR_ERR                      | invalid refNum - go set ResErr
        BNE.B   RESMGR_CONT_2                   | nonzero = specific file
        MOVE    (SysMap).w,D6                   | refNum 0 means System resource file
RESMGR_CONT_2:
        MOVE.L  (TopMapHndl).w,A4               | A4 = top of map chain
        MOVEQ.L #0x0,D0                         | D0 = 0 (not used, sets Z for entry)
        BRA.B   RESMGR_LOOP                     | enter chain walk to find refNum D6
RESMGR_FOUND_2:
        MOVE.L  16(A3),D0                       | get next map handle from chain link (mNext, +$10)
        BEQ.W   RESMGR_ERR                      | end of chain - refNum not found
        EXG     D0,A4                           | A4 = next map handle
RESMGR_LOOP:
        MOVE.L  (A4),A3                         | dereference map handle
        CMP     20(A3),D6                       | compare map's refNum with target
        BNE.B   RESMGR_FOUND_2                  | no match - follow chain link
RESMGR_LOOP_CONT:
        MOVE.L  A3,A2                           | A2 = found map pointer
        RTS                                     | return matched map in A2
| Called by: CMP_WRITE_MAP_CONT_12, CNTTYPE_NEXT_MAP, UNIQID_NEXTMAP, GETRES_NEXTMAP, RESMGR_NEXT (and 1 more)
RESMGR_NEXT_2:
        MOVEA.L  (A4),A3                        | dereference current map handle
        MOVEA.L  16(A3),A4                      | A4 = next map handle from chain link
        MOVE.L  A4,D0                           | test if next map handle is NIL
        BEQ.B   RESMGR_ERR                      | end of chain - return Z=0
        MOVE.L  (A4),A3                         | dereference next map handle
        MOVE    20(A3),D6                       | D6 = file refNum of this map
        BRA.B   RESMGR_EXIT_3                   | return Z=1 (more maps available)

| ----------------------------------------------------------
| RETURNS_23 - GetTypeList: set up type list pointer for current map
| Dereferences the map handle and advances to the type list.
| The map's mTypes field (+$18) holds the offset to the type list.
| Returns: A2=first type entry, A3=type list base, D5=numTypes-1 (or -1).
RETURNS_23:
        MOVE.L  (A4),A3                         | dereference map handle
        ADDA.W  24(A3),A3                       | add type list offset (mTypes, +$18)
        MOVE.L  A3,A2                           | A2 = type list pointer
        MOVE    (A2)+,D5                        | D5 = number of types minus 1
        RTS                                     | return type list in A2 and count in D5

| ----------------------------------------------------------
| RETURNS_24 - GetFirstType: get first type entry and its ref list
| Sets up A3=type list, A2=first ref list, D3=first resType, D4=count-1.
| Returns: N flag set if type list is empty (D5 < 0).
| Called by: RsrcZoneInit, FINDNEXT_ENTER, CMP_WRITE_MAP_CONT, RESMGR_CONT_13, RMVERESOURCE_CONT_4_CONT
RETURNS_24:
        BSR.B   RETURNS_23                      | get type list pointer + count in D5
        MOVE.L  (A2),D3                         | D3 = first resource type (e.g. 'DRVR')
        BSR.B   RETURNS_27                      | get ref list for first type
        TST     D5                              | test if any types exist
        RTS                                     | return Z flag set if no types exist
RESMGR_LOOP_4:
        CMP     (A2),D2                         | compare current ref ID with target D2
        BEQ.B   RESMGR_EXIT_3                   | ID match - return Z=1
        ADDA.W  #0xC,A2                         | advance to next ref entry (12 bytes)
        DBRA    D4,RESMGR_LOOP_4                | loop until found or end of refs
        BRA.B   RESMGR_ERR                      | ID not found - return Z=0
| Called by: CMP_WRITE_MAP_CONT_10, UNIQID_CHECK, GETRES_FIND_TYPE, GETNAMED_LOOP, RETURNS_24_CONT_4 (and 3 more)
RETURNS_26:
        BSR.B   RETURNS_23                      | get type list pointer + count in D5
        BMI.B   RESMGR_ERR                      | empty type list - return N=1
RESMGR_LOOP_5:
        CMP.L   (A2),D3                         | compare current type with target D3
        BEQ.B   RESMGR_EXIT_3                   | type match - return Z=1
        ADDQ.W  #0x8,A2                         | advance to next type entry (8 bytes)
        DBRA    D5,RESMGR_LOOP_5                | loop until found or end of types
        BRA.B   RESMGR_ERR                      | type not found - return N=1
| Called by: CMP_WRITE_MAP_CONT_10, UNIQID_CHECK, GETRES_FIND_TYPE, GETNAMED_LOOP, RETURNS_24 (and 2 more)
RETURNS_27:
        MOVE    4(A2),D4                        | D4 = numItems-1 from type entry
        MOVE    6(A2),A2                        | A2 = ref-list offset (relative)
        ADDA.L  A3,A2                           | A2 = absolute ref-list pointer
        RTS                                     | return D4=count-1, A2=refs
RESMGR_EXIT_3:
        MOVEQ.L #0x0,D0                         | set Z=1, return success
        RTS                                     | return Z=1 (matched)
| Called by: InitResources, RsrcZoneInit, CreateResFile, OpenResFile, SetResFileAttrs (and 18 more)
RESMGR_PROLOG:
        CLR     (ResErr).w                      | clear ResErr to 0
        MOVE.L  (SP)+,A0                        | A0 = caller return address
        LINK    A6,#-0x32                       | set up stack frame
        MOVEM.L D1-D7/A1-A4,-(SP)               | save caller registers
        MOVE.L  A0,-(SP)                        | push return address back
        LEA.L     8(A6),A0                      | A0 = pointer to first parameter
        RTS                                     | return to caller via pushed addr
RESMGR_EPILOG:
        MOVEM.L (SP)+,D1-D7/A1-A4               | restore caller registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | A0 = caller return address
        ADDA.L  D0,SP                           | SP += D0
        MOVE.L  A0,-(SP)                        | push return address
        MOVE    (ResErr).w,D0                   | D0 = ResErr result code
        BEQ.B   RESMGR_EPILOG_RTS               | no error - return clean
        MOVE.L  (ResErrProc).w,-(SP)            | push ResErrProc handler addr
        BNE.B   RESMGR_EPILOG_RTS               | handler installed - call it
        ADDQ.W  #0x4,SP                         | no handler - drop pushed nil
RESMGR_EPILOG_RTS:
        RTS                                     | return from RESMGR_EPILOG_RTS
| Called by: RESMGR_LOOP_4, RESMGR_LOOP_5, RETURNS_24_CONT_6, RESMGR_EMPTY, RESMGR_CONT_16_EXIT
RESMGR_ERR:
        MOVEQ.L #-0x1,D0                        | set N=1, Z=0 (not found)
        RTS                                     | return failure
RETURNS_24_CONT_4:
        BSR.B   RESMGR_CONT_12                  | locate map containing handle A1
        BMI.B   RESMGR_ERR                      | handle not found - exit
        CMP     (SysMap).w,D6                   | ensure home is the System map
        BNE.B   RESMGR_ERR                      | not in SysMap - bail out
        MOVE    (A2),D2                         | D2 = resource ID from ref entry
        BSR.W   RETURNS_21                      | set up search from CurMap
        BSR.B   RETURNS_26                      | find type D3 in current map
        BMI.B   RESMGR_ERR                      | type missing in CurMap - exit
        BSR.B   RETURNS_27                      | get ref list for this type
RETURNS_24_CONT_5:
        TST.B   4(A2)                           | test attributes byte (high bit)
        BPL.B   RETURNS_24_CONT_6               | resSysRef clear: not a reference - next entry
        CMP     8(A2),D2                        | refID (+$8) = ID of this system resource?
        BEQ.B   RESMGR_EXIT_3                   | ID match - return Z=1 found
RETURNS_24_CONT_6:
        BSR.B   RETURNS_28                      | advance to next ref entry
        BEQ.B   RETURNS_24_CONT_5               | more refs - check next
        BRA.B   RESMGR_ERR                      | end of ref list - not found

| update open FCBs with new parent DirID and hint
| Called by: RETURNS_24_CONT_4, LoadResource, WRITERESOURCE_CONT_2, SETRESATTRS_CONT, AddResource (and 2 more)
RESMGR_CONT_12:
        MOVE.L  A1,D0                           | test if handle A1 is NIL
        BEQ.B   RESMGR_ERR                      | NIL handle - bail out
        BSR.W   RETURNS_20                      | set up map chain traversal
RESMGR_CONT_13:
        BSR.W   RETURNS_24                      | get first type + ref list
        BMI.B   RESMGR_EMPTY                    | type list empty - try next map
FINDRES_HANDLE_LOOP:
        TST.B   4(A2)                           | test attributes byte
        BMI.B   FINDRES_HANDLE_NEXT             | resSysRef: +$8 holds no handle - skip
        CMPA.L  8(A2),A1                        | compare ref's handle with A1
        BEQ.B   RESMGR_EXIT_3                   | handle matches - return Z=1
FINDRES_HANDLE_NEXT:
        BSR.B   RETURNS_28                      | advance to next ref entry
        BPL.B   FINDRES_HANDLE_LOOP             | more refs - keep checking
RESMGR_EMPTY:
        BSR.W   RESMGR_NEXT_2                   | advance to next map in chain
        BEQ.B   RESMGR_CONT_13                  | more maps - search again
        BRA.B   RESMGR_ERR                      | handle not found in any map

| ----------------------------------------------------------
| RESMGR_CONT_16 - GetResName: get pointer to resource name string
| Reads the name offset from the reference entry (ref+2).
| If -1, the resource has no name; returns an empty Pascal string.
| Otherwise computes name list base + offset to return name pointer.
RESMGR_CONT_16:
        MOVE    2(A2),D0                        | D0 = name offset (-1 if no name)
        BMI.B   RESMGR_CONT_16_EXIT             | no name - return empty string
        MOVE.L  (A4),A0                         | dereference map handle
        ADDA.W  26(A0),A0                       | add name list offset (map+0x1A)
        ADDA.W  D0,A0                           | add per-resource name offset
        BRA.W   RESMGR_EXIT_3                   | return success, A0 = name string
RESMGR_CONT_16_EXIT:
        LEA     RESOURCE_MAP(PC),A0             | A0 = empty-string (len=0) constant
        BRA.B   RESMGR_ERR                      | return with A0 = empty name
| Called by: RSRCZONEINIT_HANDLE_NEXT, STDMAPENTRY_SKIP, CMP_WRITE_MAP_CONT_3, GETINDRES_SCAN_SKIP, RESMGR_SKIP (and 3 more)
RETURNS_28:
        ADDA.W  #0xC,A2                         | advance to next ref entry (12 bytes)
        SUBQ.W  #0x1,D4                         | decrement remaining-refs count
        BPL.W   RESMGR_EXIT_3                   | more refs in this type - return Z=1
        SUBQ.W  #0x1,D5                         | decrement remaining-types count
        BMI.B   RESMGR_ERR                      | end of type list - return failure
        MOVE    (A3),D0                         | D0 = numTypes-1 from list header
        SUB     D5,D0                           | D0 = current type index
        ASL     #0x3,D0                         | multiply by 8 (type entry size)
        MOVE.L  2(A3,D0.W),D3                   | D3 = next resource type code
        MOVE    6(A3,D0.W),D4                   | D4 = numItems-1 for new type
        MOVEQ.L #0x1,D0                         | set Z=0 (more entries available)
        RTS                                     | return Z=1 (more refs to scan)
| Called by: INITRES_LOADALL_LOOP, UPDRES_ADJ_LOOP, CMP_WRITE_MAP_CONT_14, GETNAMED_FOUND, LOADRESOURCE_FOUND
RETURNS_28_CONT:
        MOVE.B  4(A2),D1                        | D1 = resource attributes byte
        BPL.B   RETURNS_28_CONT_3               | resSysRef clear: normal load
        BSR.B   RETURNS_28_NO                   | swap CurMap and SysMap (undone after the load)
        ADDQ.W  #0x8,A2                         | A2 -> refID (+$8) / refNameOff (+$A)
        MOVE    (A2),D1                         | D1 = refID (ID of the referenced resource)
        BSR.B   RESMGR_CONT_16                  | A0 = its name (refNameOff at A2+2)
        BMI.B   RETURNS_28_CONT_2               | no name - load by ID instead
        SUBQ.W  #0x4,SP                         | reserve handle slot on stack
        MOVE.L  D3,-(SP)                        | push resource type
        MOVE.L  A0,-(SP)                        | push name string pointer
        _GetNamedResource                       | recursively load by name
        MOVE.L  (SP)+,A0                        | A0 = handle from GetNamedResource
        MOVE.L  A0,D0                           | test if handle returned
        BNE.B   RETURNS_28_NO                   | got handle - swap maps and return
RETURNS_28_CONT_2:
        SUBQ.W  #0x4,SP                         | reserve handle slot on stack
        MOVE.L  D3,-(SP)                        | push resource type
        MOVE    D1,-(SP)                        | push resource ID
        _GetResource                            | recursively load by ID
        MOVE.L  (SP)+,A0                        | A0 = handle from GetResource
RETURNS_28_NO:
        MOVE    (CurMap).w,D0                   | save current CurMap
        MOVE    (SysMap).w,(CurMap).w           | restore SysMap as CurMap
        MOVE    D0,(SysMap).w                   | save old CurMap into SysMap slot
        RTS                                     | return with handle in A0
RETURNS_28_CONT_3:
        MOVE.L  (TheZone).w,-(SP)               | save current heap zone
        BTST    #0x6,D1                         | test resSysHeap bit
        BEQ.B   CHECKLOAD_NO                    | resSysHeap clear: keep the current zone
        MOVE.L  (SysZone).w,(TheZone).w         | resSysHeap: load into the system heap
CHECKLOAD_NO:
        MOVE.L  8(A2),A0                        | A0 = resource handle from ref entry
        SUBA.L  (A4),A3                         | make A3 relative to map base (relocatable)
        TST.B   (ResLoad).w                     | is auto-loading enabled?
        BEQ.B   CHECKLOAD_CONT_2_EMPTY          | no - just create empty handle
        MOVE.L  A0,D0                           | test if handle already exists
        BNE.B   CHECKLOAD_OK                    | yes - check if data is loaded
        BSR.B   CHECKLOAD_NO_CONT               | get resource size, reserve if locked
        _NewHandle                              | allocate new handle for resource data
        BEQ.B   CHECKLOAD_CONT_2                | success - store handle and read data
        BRA.B   CHECKLOAD_CONT_2_ERR            | allocation failed - set error
CHECKLOAD_NO_CONT:
        BSR.B   CHECKLOAD_CONT_5                | get resource size into D0
        SUBA.L  (A4),A2                         | A2 := relative ref offset
        BTST    #0x4,D1                         | test resLocked bit
        BEQ.B   CHECKLOAD_NO_CONT_2             | not locked - skip ResrvMem
        MOVE.L  D0,D2                           | save size in D2
        _ResrvMem                               | reserve low-memory block of size
        MOVE.L  D2,D0                           | D0 = saved size for caller
CHECKLOAD_NO_CONT_2:
        RTS                                     | return D0=size to caller

| ----------------------------------------------------------
| CHECKLOAD_OK
| Called during boot (22,312 times in 30s trace).
CHECKLOAD_OK:
        TST.L   (A0)                            | is handle's master pointer non-NIL?
        BNE.B   CHECKLOAD_CONT_2_NO             | already loaded - just return
        BSR.B   CHECKLOAD_NO_CONT               | get resource size, reserve if locked
        _ReallocHandle                          | reallocate purged handle with new size
        BMI.B   CHECKLOAD_CONT_2_ERR            | reallocation failed - set error
CHECKLOAD_CONT_2:
        ADDA.L  (A4),A2                         | restore A2 to absolute ref entry ptr
        MOVE.L  A0,8(A2)                        | store new handle in ref entry
        BSR.B   CHECKLOAD_CONT_6                | set handle flags (resource bit)
        BSR.B   CHECKLOAD_SKIP_2_CONT           | read resource data into handle
        MOVE    (ResErr).w,D0                   | check if read succeeded
        BEQ.B   CHECKLOAD_CONT_2_NO             | success - skip error path
        SUBA.L  (A4),A2                         | make A2 relative again for error path
CHECKLOAD_CONT_2_ERR:
        MOVE    D0,(ResErr).w                   | store error code in ResErr global
        SUBA.L  A0,A0                           | clear A0 (return NIL handle on error)
        BRA.B   CHECKLOAD_CONT_2_CONT           | finalize and restore zone
CHECKLOAD_CONT_2_EMPTY:
        MOVE.L  A0,D0                           | ResLoad=false: test existing handle
        BNE.B   CHECKLOAD_CONT_2_NO             | handle exists - keep it
        SUBA.L  (A4),A2                         | make A2 relative for Memory Mgr call
        MOVEQ.L #0x4,D0                         | D0 = 4 byte placeholder size
        _NewHandle                              | allocate empty handle
        _EmptyHandle                            | purge data ptr (handle is empty)
CHECKLOAD_CONT_2_CONT:
        ADDA.L  (A4),A2                         | restore A2 to absolute ref ptr
CHECKLOAD_CONT_2_NO:
        MOVE.L  A0,D0                           | test if handle is non-NIL
        BEQ.B   CHECKLOAD_SKIP_2                | NIL - skip storing handle
        MOVE.L  A0,8(A2)                        | store handle in ref entry+8
CHECKLOAD_SKIP_2:
        ADDA.L  (A4),A3                         | restore A3 to absolute type list ptr
        MOVE.L  (SP)+,(TheZone).w               | restore saved heap zone
        RTS                                     | return to caller after storing handle
CHECKLOAD_SKIP_2_CONT:
        LSL.B   #0x3,D1                         | resLocked (bit 4) -> bit 7, resPurgeable (bit 5) -> X
        BPL.B   CHECKLOAD_SKIP_2_NO             | not locked
        MOVEQ.L #-0x7F,D1                       | D1 = $81: locked
        BRA.B   CHECKLOAD_CONT_4                | go set handle flags
CHECKLOAD_SKIP_2_NO:
        MOVEQ.L #-0x80,D1                       | D1 = -128 (@ $DE5C)
CHECKLOAD_CONT_4:
        ROXR.B  #0x2,D1                         | D1 = lock (7) | purge from X (6) | resource (5)
        ANDI.B  #0x1F,(A0)                      | clear upper 3 flag bits of master pointer
        OR.B    D1,(A0)                         | set resource/purgeable/lock flags on handle
        RTS                                     | return with updated handle flags

| ----------------------------------------------------------
| CHECKLOAD_CONT_5
| Called during boot.
CHECKLOAD_CONT_5:
        MOVEM.L D1-D2/A0-A1,-(SP)               | save working registers
        BSR.B   CHECKLOAD_CONT_7                | set up file position and handle for I/O
        SUBQ.L  #0x4,SP                         | allocate 4 bytes on stack for size longword
        MOVE.L  SP,D1                           | D1 = buffer address (stack temp)
        MOVEQ.L #0x4,D0                         | D0 = 4 bytes to read (resource data length)
        BSR.B   CHECKLOAD_CONT_10               | issue _Read of size prefix
        MOVE.L  (SP)+,D0                        | D0 = resource data size from file
        MOVEM.L (SP)+,D1-D2/A0-A1               | restore working registers
        RTS                                     | return data size in D0
CHECKLOAD_CONT_6:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save working registers
        BSR.B   CHECKLOAD_CONT_7                | compute file pos D2 and A1=handle
        BSR.B   CHECKLOAD_CONT_5                | read size prefix into D0
        ADDQ.L  #0x4,D2                         | skip past size prefix in file
        MOVE.L  (A1),D1                         | D1 = handle's master pointer
        BSR.B   CHECKLOAD_CONT_10               | _Read D0 bytes into handle data
CHECKLOAD_EXIT_2:
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore regs
        RTS                                     | exit DoPart

| ----------------------------------------------------------
| CHECKLOAD_CONT_7
| Called during boot.
CHECKLOAD_CONT_7:
        ANDI.B  #0xFD,0x4(A2)                   | clear resChanged bit in ref entry attr
        MOVE.L  (A4),A0                         | dereference map handle
        MOVE.L  0x4(A2),D2                      | D2 = resAttr byte + 3-byte data offset
        AND.L   (Lo3Bytes).w,D2                 | mask to 24-bit data offset
        ADD.L   (A0),D2                         | D2 = absolute file position of resource data
        MOVE.L  0x8(A2),A1                      | A1 = resource handle
        RTS                                     | return absolute file position in D2
CHECKLOAD_CONT_8:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save working registers
        BSR.B   CHECKLOAD_CONT_7                | compute file pos D2 and A1=handle
        MOVE.L  A1,A0                           | A0 = handle for size query
        _GetHandleSize                          | D0 = current data size
        BPL.B   CHECKLOAD_OK_2                  | size >= 0 -> use as-is
        MOVEQ.L #0x0,D0                         | error -> treat as zero
CHECKLOAD_OK_2:
        MOVE.L  D0,-(SP)                        | push size longword as write buffer
        MOVE.L  SP,D1                           | D1 = buffer address (size on stack)
        MOVEQ.L #0x4,D0                         | D0 = 4 bytes to write (size prefix)
        BSR.B   CHECKLOAD_EMPTY_2               | _Write size prefix to file
        ADDQ.L  #0x4,D2                         | advance file position past size prefix
        MOVE.L  (A1),D1                         | D1 = dereferenced handle (data buffer)
        MOVE.L  (SP)+,D0                        | D0 = data size to write
        BSR.B   CHECKLOAD_EMPTY_2               | _Write resource data to file
        BRA.B   CHECKLOAD_EXIT_2                | restore regs and return
| Called by: NewMap, NEWMAP_ERR, CreateResFile, CMP_WRITE_MAP_NO, CHECKLOAD_CONT_10 (and 3 more)
CHECKLOAD_CONT_9:
        LEA.L   -0x1A(A6),A0                    | A0 -> ioRefNum (I/O block +$18 = -$1A(A6))
        MOVE    D6,(A0)+                        | ioRefNum = file reference number
        ADDQ.W  #0x6,A0                         | skip ioPermssn/ioMisc fields
        MOVE.L  D1,(A0)+                        | ioBuffer = data buffer address
        MOVE.L  D0,(A0)+                        | ioReqCount = byte count to read/write
        ADDQ.W  #0x4,A0                         | skip ioActCount field
        MOVE    #0x1,(A0)+                      | ioPosMode = 1 (fsFromStart)
        MOVE.L  D2,(A0)+                        | ioPosOffset = file position
        LEA.L   -0x32(A6),A0                    | A0 = base of parameter block for _Read/_Write
        RTS                                     | return prepared param block in A0
CHECKLOAD_CONT_10:
        MOVEM.L D0/A0-A1,-(SP)                  | save working registers
        BSR.B   CHECKLOAD_CONT_9                | build IOParam at -0x32(A6)
        _Read                                   | issue synchronous _Read
        BRA.B   CHECKLOAD_ERR_3                 | stash result in ResErr
CHECKLOAD_CONT_11:
        MOVEQ.L #0x0,D2                         | D2 = 0 (file pos = start of fork)
CHECKLOAD_EMPTY_2:
        MOVEM.L D0/A0-A1,-(SP)                  | save working registers
        BSR.B   CHECKLOAD_CONT_9                | build IOParam at -0x32(A6)
        _Write                                  | issue synchronous Write to resource fork
CHECKLOAD_ERR_3:
        MOVE    D0,(ResErr).w                   | stash _Write error code
CHECKLOAD_EXIT_3:
        MOVEM.L (SP)+,D0/A0-A1                  | restore saved regs
        RTS                                     | return from CHECKLOAD_EXIT_3
CHECKLOAD_OK_3:
        MOVEM.L D0/A0-A1,-(SP)                  | save working registers
        BSR.B   CHECKLOAD_OK_4                  | verify file mode is open-for-write
        BNE.B   CHECKLOAD_EXIT_3                | not writable - exit silently
        BSR.B   CHECKLOAD_CONT_9                | build IOParam at -0x32(A6)
        MOVE.L  (A4),A1                         | A1 = current map base ptr
        MOVE.L  4(A1),D0                        | D0 = offsetToMap from header
        ADD.L   12(A1),D0                       | + lengthOfMap = end of fork
        MOVE.L  D0,28(A0)                       | ioMisc = new EOF position
        _SetEOF                                 | truncate fork at new EOF
        BRA.B   CHECKLOAD_ERR_3                 | stash result in ResErr
CHECKLOAD_CONT_9_CONT_5:
        BSR.B   CHECKLOAD_CONT_14               | D0,D1 = current resource size + 4
        BSR.W   FINDNEXT_OFS                    | locate gap or compute new offset
        BPL.B   CHECKLOAD_CONT_9_CONT_8         | has slot - try to fit in place
        SUB.L   D0,D1                           | D1 = growth required
        BLE.B   CHECKLOAD_CONT_9_CONT_11        | fits in place - just write data
        BSR.B   CHECKLOAD_CONT_9_CONT_7         | shift map+name list down by D1
        BRA.B   CHECKLOAD_CONT_9_CONT_10        | mark map dirty, write data
CHECKLOAD_CONT_14:
        MOVE.L  8(A2),A0                        | A0 = handle from ref entry
        _GetHandleSize                          | D0 = handle's current data size
        ADDQ.W  #0x4,D0                         | +4 for size prefix on disk
        MOVE.L  D0,D1                           | D1 = total bytes to write
        RTS                                     | return D0=size, D1=total
CHECKLOAD_CONT_9_CONT_7:
        MOVE.L  (A4),A0                         | A0 = map base ptr
        ADDQ.L  #0x4,A0                         | skip past offsetToData field
        ADD.L   D1,(A0)+                        | (A0)+ += D1
        MOVE.L  (A0),D0                         | D0 = old offsetToMap
        ADD.L   D1,(A0)                         | (A0) += D1
        SUBQ.L  #0x8,A0                         | A0 = back to map base
        RTS                                     | return D0=old offsetToMap
CHECKLOAD_CONT_9_CONT_8:
        CMP.L   D0,D1                           | compare new size with old slot
        BLE.B   CHECKLOAD_CONT_9_CONT_11        | fits in old slot - write in place
        MOVE.L  (A4),A0                         | A0 = map base ptr
        BSET    #0x6,22(A0)                     | set mapCompact flag in attrs
CHECKLOAD_CONT_9_CONT_9:
        BSR.B   CHECKLOAD_CONT_14               | D0,D1 = current size + 4
        BSR.B   CHECKLOAD_CONT_9_CONT_7         | shift map+name list, D0=new offset
        MOVE.B  4(A2),-(SP)                     | save attribute byte
        MOVE.L  D0,4(A2)                        | ref offset+attr := new offset
        MOVE.B  (SP)+,4(A2)                     | restore attribute byte
CHECKLOAD_CONT_9_CONT_10:
        BSET    #0x5,22(A0)                     | set mapDirty flag in attrs
CHECKLOAD_CONT_9_CONT_11:
        BRA.B   CHECKLOAD_OK_3                  | write resource data to file

| ----------------------------------------------------------
| CHECKLOAD_OK_4
| Called during boot.
CHECKLOAD_OK_4:
        MOVE.L  (A4),A0                         | dereference map handle
        BTST    #0x7,0x16(A0)                   | test mapReadOnly flag (bit 7 of map attrs)
        RTS                                     | Z=0 if read-only, Z=1 if writable
CHECKLOAD_OK_4_CONT:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save working registers
        SUBA.L  (A4),A3                         | A3 := relative type-list offset
        SUBA.L  (A4),A2                         | A2 := relative ref-entry offset
        MOVEQ.L #0x46,D1                        | D1 = 0x46 (margin in 4-byte units)
        ASL     #0x2,D1                         | D1 = 0x118 byte margin
        MOVE.L  A4,A0                           | A0 = map handle
        _GetHandleSize                          | D0 = current map size in heap
        MOVE.L  D0,D2                           | collapse stack: remove handle param
        ADD.L   D1,D0                           | grow heap allocation by margin
        _SetHandleSize                          | expand map handle in zone
        EXG     D0,D2                           | D0=err code, D2=old size
        _SetHandleSize                          | shrink back to original size
        TST     D2                              | test if first SetHandleSize failed
        BMI.B   CHECKLOAD_SKIP_3_CONT           | error - skip EOF expansion
        BSR.B   CHECKLOAD_OK_4                  | check if file is writable
        BNE.B   CHECKLOAD_SKIP_3_CONT           | read-only - skip EOF expansion
        MOVE.L  A1,D0                           | test if extra-data handle is set
        BEQ.B   CHECKLOAD_SKIP_3                | no extra data - go set EOF
        MOVE.L  A1,A0                           | A0 = extra data handle
        _GetHandleSize                          | D0 = extra data size
        MOVE.L  D0,D2                           | save size in D2
        BMI.B   CHECKLOAD_SKIP_3_CONT           | error - skip EOF expansion
        ADD.L   D0,D1                           | D1 = total growth needed
CHECKLOAD_SKIP_3:
        BSR.W   CHECKLOAD_CONT_9                | build IOParam block in stack frame
        LEA.L   ioLEOF(A0),A1                   | A1 = pointer to ioLEOF field (ioMisc alias)
        _GetEOF                                 | get current file EOF into ioLEOF
        MOVE.L  (A1),D2                         | D2 = current EOF position
        ADD.L   D1,(A1)                         | ioLEOF = current EOF + growth amount
        _SetEOF                                 | extend file to accommodate new data
        EXG     D0,D2                           | D0=old EOF, D2=err result
        MOVE.L  D0,(A1)                         | ioLEOF := old EOF
        _SetEOF                                 | restore EOF if SetEOF failed
CHECKLOAD_SKIP_3_CONT:
        MOVE    D2,(ResErr).w                   | stash result code in ResErr
        ADDA.L  (A4),A3                         | A3 := absolute type-list ptr
        ADDA.L  (A4),A2                         | A2 := absolute ref-entry ptr
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore working registers
        RTS                                     | return from CHECKLOAD_SKIP_3_CONT

| ----------------------------------------------------------
| LoadResource -- _LoadResource ($A9A2). Plus 1062.
| Load a resource handle's data from disk if not already loaded.
LoadResource:
        MOVEM.L D0/A0,-(SP)                     | save D0/A0 (restored by epilogue)
        PEA     LOADRESOURCE_EXIT(PC)           | push cleanup routine as return address
        BSR.W   RESMGR_PROLOG                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  20(A6),A1                       | A1 = resource handle from caller's stack
        TST.L   (A1)                            | is master pointer non-NIL?
        BNE.B   LOADRESOURCE_SKIP               | yes - already loaded, nothing to do
        BSR.W   RESMGR_CONT_12                  | find ref entry for this handle in all maps
        BEQ.B   LOADRESOURCE_FOUND              | found - go load the data
        MOVE    #-0xC0,(ResErr).w               | resNotFound: handle not in any resource map
        BRA.B   LOADRESOURCE_SKIP               | skip to epilogue
LOADRESOURCE_FOUND:
        MOVE.B  (ResLoad).w,-(SP)               | save current ResLoad state
        ST      (ResLoad).w                     | force ResLoad = true (always load)
        BSR.W   RETURNS_28_CONT                 | load resource data into handle
        MOVE.B  (SP)+,(ResLoad).w               | restore original ResLoad state
LOADRESOURCE_SKIP:
        BRA.W   CMP_WRITE_MAP_CONT_15           | dispatch to common epilogue
LOADRESOURCE_EXIT:                              | @ $E000 (cleanup pushed by PEA above)
        MOVEM.L (SP)+,D0/A0                     | restore caller's D0/A0
        MOVE.L  (SP)+,(SP)                      | collapse: discard PEA-pushed return addr
        RTS                                     | return from LOADRESOURCE_EXIT

| ----------------------------------------------------------
| ReleaseResource -- _ReleaseResource ($A9A3). Plus 1103.
| Discard handle's data and clear the cached handle.
ReleaseResource:
        BSR.B   WRITERESOURCE_CONT_2            | prologue + find ref entry for handle
        BTST    #0x1,4(A2)                      | test resChanged (bit 1) in resAttr
        BNE.B   RELEASERESOURCE_SKIP_2          | changed -> skip dispose/clear
        MOVE.L  A1,A0                           | A0 = handle to dispose
        _DisposeHandle                          | free handle's data block
        BRA.B   RELEASERESOURCE_SKIP            | clear cached handle in ref

| ----------------------------------------------------------
| DetachResource -- _DetachResource ($A992). Plus 1124.
| Mark handle as no longer a resource (caller owns it).
DetachResource:
        BSR.B   WRITERESOURCE_CONT_2            | prologue + find ref entry for handle
        BTST    #0x1,4(A2)                      | test resChanged bit in resAttr
        BNE.B   RELEASERESOURCE_SKIP_2          | changed -> skip BCLR
        BCLR    #0x5,(A1)                       | clear resource flag in master pointer
RELEASERESOURCE_SKIP:
        CLR.L   0x8(A2)                         | clear cached handle ptr in ref entry
RELEASERESOURCE_SKIP_2:
        BRA.B   CHANGEDRESOURCE_EPILOG          | -> $E04E common epilog

| ----------------------------------------------------------
| ChangedResource -- _ChangedResource ($A9AA). Plus 1144.
| Marks a resource handle as changed so the next _UpdateResFile
| will rewrite it. Tests resProtected, ensures the resource file
| can grow, sets the resChanged bit, and writes the new data.
| Plus 1986 additionally marks the map as changed (BSET 0x16(A0));
| classic 1984 omits that step.
ChangedResource:
        BSR.B   WRITERESOURCE_CONT_2            | prologue + find ref entry for handle
        MOVE.B  (A1),D7                         | D7 = save master pointer flags byte
        BCLR    #0x6,(A1)                       | clear purgeable flag during write check
        BTST    #0x3,4(A2)                      | test resProtected attribute (bit 3)
        BNE.B   CHANGEDRESOURCE_ERR             | protected - can't mark changed
        BSR.W   CHECKLOAD_OK_4_CONT             | ensure file can grow for new data
        BMI.B   CHANGEDRESOURCE_ERR             | memory/file error - abort
        BSET    #0x1,4(A2)                      | set resChanged bit in ref entry
        BSR.W   CHECKLOAD_CONT_9_CONT_5         | write resource data to file
CHANGEDRESOURCE_ERR:
        MOVE.B   D7,(A1)                        | restore master pointer flags byte
CHANGEDRESOURCE_EPILOG:
        BRA.B    RESMGR_EXIT_5                  | epilogue: 4 param bytes

| ----------------------------------------------------------
| WriteResource -- _WriteResource ($A9B0). Plus 1172.
| Writes a resource handle's data back to its resource file if
| the resource is marked as changed and the file is writable.
WriteResource:
        BSR.B   WRITERESOURCE_CONT_2            | prologue + find ref entry for handle
        BSR.W   CHECKLOAD_OK_4                  | test if file is read-only
        BNE.B   WRITERESOURCE_SKIP              | read-only - skip write
        BTST    #0x1,4(A2)                      | test resChanged bit in resAttr
        BEQ.B   WRITERESOURCE_SKIP              | not changed - nothing to write
        BSR.W   CHECKLOAD_CONT_8                | write resource data + size to file
WRITERESOURCE_SKIP:
        BRA.B   RESMGR_EXIT_5                   | epilogue: 4 param bytes
| Called by: ReleaseResource, DetachResource, ChangedResource, WriteResource, HomeResFile
WRITERESOURCE_CONT_2:
        MOVE.L  (SP)+,D0                        | D0 = caller return address
        BSR.W   RESMGR_PROLOG                   | set up stack frame, save regs
        MOVE.L  D0,-(SP)                        | push return addr back on stack
        MOVE.L  (A0),A1                         | A1 = handle from first param
        BSR.W   RESMGR_CONT_12                  | locate ref entry across maps
        BEQ.B   WRITERESOURCE_EXIT              | found - return with A2=ref ptr
        ADDQ.W  #0x4,SP                         | drop pushed return address
        MOVE    #-0xC0,(ResErr).w               | ResErr = resNotFound (-192)
        BRA.B   RESMGR_EXIT_5                   | epilogue, 4-byte param frame

| ----------------------------------------------------------
| HomeResFile -- _HomeResFile ($A9A4). Plus 1216.
| Returns the file refNum of the file that owns this resource.
| System file returns 0 by convention.
HomeResFile:
        MOVE    (MinusOne).w,8(SP)              | preset result to -1 (error case)
        BSR.B   WRITERESOURCE_CONT_2            | prologue + find ref entry
        CMP     (SysMap).w,D6                   | is resource in System file?
        BNE.B   HOMERESFILE_EXIT                | no - return actual refNum
        MOVEQ.L #0x0,D6                         | System file returns refNum = 0 by convention
HOMERESFILE_EXIT:
        MOVE    D6,12(A6)                       | store result refNum in return slot
        BRA.B   RESMGR_EXIT_5                   | -> common epilog

| ----------------------------------------------------------
| CurResFile -- _CurResFile ($A994). Plus 1275.
| Returns the refNum of the current resource file (CurMap).
CurResFile:
        MOVE    (CurMap).w,4(SP)                | return CurMap refNum to caller
WRITERESOURCE_EXIT:
        RTS                                     | return from WRITERESOURCE_EXIT

| ----------------------------------------------------------
| GetResAttrs -- _GetResAttrs ($A9A6). Plus 1313.
| Returns the resAttr byte for a resource handle.
GetResAttrs:
        BSR.W   RESMGR_PROLOG                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  (A0),A1                         | A1 = master pointer (dereference handle)
        BSR.B   SETRESATTRS_CONT                | find ref entry for this handle
        BMI.B   RESMGR_EXIT_5                   | not found - skip
        MOVE.B  4(A2),13(A6)                    | store resAttr byte in result word (low byte)

| ----------------------------------------------------------
| RESMGR_EXIT_5 -- common epilogue: 4 param bytes. Plus 390.
RESMGR_EXIT_5:
        MOVEQ.L #0x4,D0                         | 4 bytes of params
        BRA.B   RESMGR_EXIT_TRAMP               | -> common epilog trampoline

| ----------------------------------------------------------
| SetResAttrs -- _SetResAttrs ($A9A7). Plus 1326.
| Sets the resAttr byte for a resource handle. Marks map changed.
SetResAttrs:
        BSR.W   RESMGR_PROLOG                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  10(A6),A1                       | A1 = resource handle from param
        BSR.B   SETRESATTRS_CONT                | find ref entry for this handle
        BMI.B   SETRESATTRS_SKIP                | not found - skip
        MOVE.B  9(A6),4(A2)                     | copy new resAttr byte into ref entry
SETRESATTRS_SKIP:
        BRA.W   CMP_WRITE_MAP_OK_2              | mark map changed, run common epilog

| ----------------------------------------------------------
| SETRESATTRS_CONT -- find ref entry for handle (used by GetResAttrs/
| SetResAttrs/GetResInfo/SetResInfo/ChangedResource). On entry A1 = master
| pointer. Sets A2 -> ref entry on success, returns BMI on failure.
SETRESATTRS_CONT:
        BSR.W   RETURNS_24_CONT_4               | check handle is in CurMap
        BEQ.B   SETRESATTRS_CONT_EXIT           | found - return success
        BSR.W   RESMGR_CONT_12                  | not in CurMap, search all maps
        BEQ.B   SETRESATTRS_CONT_EXIT           | found - return success
        MOVE    #-0xC0,(ResErr).w               | resNotFound: handle not in any map
SETRESATTRS_CONT_EXIT:
        RTS                                     | return Z=1 if found, N=1 otherwise

| ----------------------------------------------------------
| GetResInfo -- _GetResInfo ($A9A8). Plus 1356.
| Returns the resID, resType, and resName for a resource handle.
GetResInfo:
        BSR.W   RESMGR_PROLOG                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  20(A6),A1                       | A1 = resource handle from param
        BSR.B   SETRESATTRS_CONT                | find ref entry for this handle
        BEQ.B   GETRESINFO_EXIT                 | found - proceed to return info
        LEA.L     (MinusOne).w,A2               | not found - A2 points to -1 (for resID)
        MOVEQ.L #0x0,D3                         | D3 = 0 (clear resource type)
GETRESINFO_EXIT:
        LEA.L     16(A6),A0                     | A0 -> name pointer slot in stack frame
        MOVE.L  (A0),A1                         | A1 = name buffer pointer
        MOVE    (A2),(A1)                       | store resID at *namePtr (treated as int)
        MOVE.L  -(A0),A1                        | A1 = resType slot
        MOVE.L  D3,(A1)                         | store resType
        MOVE.L  -(A0),A1                        | A1 = name slot
        CLR.B   (A1)                            | preset empty Pascal string (length 0)
        BSR.W   RESMGR_CONT_16                  | locate resource name string -> A0
        BMI.B   GETRESINFO_DONE                 | no name - leave empty
        BSR.B   GETRESINFO_CONT                 | copy Pascal string from A0 to A1
GETRESINFO_DONE:
        MOVEQ.L #0x10,D0                        | 16 bytes of params

| ----------------------------------------------------------
| RESMGR_EXIT_TRAMP -- long-jump trampoline to RESMGR_EPILOG (BRA.B sources).
RESMGR_EXIT_TRAMP:
        BRA.W   RESMGR_EPILOG                   | jump to common epilog

| ----------------------------------------------------------
| GETRESINFO_CONT -- copy Pascal string A0 -> A1. Plus 1391.
GETRESINFO_CONT:
        MOVEQ.L #0x0,D0                         | clear D0 for byte extension
        MOVE.B  (A0),D0                         | D0 = Pascal string length byte
        ADDQ.L  #0x1,D0                         | add 1 for length byte itself
        _BlockMove                              | copy Pascal string from A0 to A1
        RTS                                     | return after copying name

| ----------------------------------------------------------
| SetResInfo -- _SetResInfo ($A9A9). Plus 1403.
| Sets a resource's resID and/or name. Skips if read-only/protected.
SetResInfo:
        BSR.W   RESMGR_PROLOG                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  14(A6),A1                       | A1 = resource handle from param
        BSR.B   SETRESATTRS_CONT                | find ref entry for this handle
        BMI.B   SETRESINFO_ERR                  | not found - skip
        BTST    #0x3,4(A2)                      | test resProtected attribute
        BNE.B   SETRESINFO_ERR                  | protected - can't change
        SUBA.L  A1,A1                           | A1 = NIL (any handle works for read-only test)
        BSR.W   CHECKLOAD_OK_4_CONT             | ensure file can grow
        BMI.B   SETRESINFO_ERR                  | error - abort
        MOVE    12(A6),(A2)                     | store new resID
        MOVE.L  8(A6),D0                        | D0 = name pointer (or NIL)
        BEQ.B   SETRESINFO_ERR                  | NIL - skip name change
        MOVE.L  D0,A0                           | A0 = name pointer
        BSR.W   RMVERESOURCE_CONT_4_CONT        | reserve name string slot in map
        BSR.W   RMVERESOURCE_EMPTY              | write name into reserved slot
SETRESINFO_ERR:
        MOVEQ.L #0xA,D0                         | 10 bytes of params (4+2+4)
        BRA.B   RESMGR_EXIT_TRAMP               | -> common epilog trampoline

| ----------------------------------------------------------
| AddResource -- _AddResource ($A9AB). Plus 1441.
| Add a handle as a new resource to the current resource file.
| Sets resAttr = resChanged so the data gets written on next update.
AddResource:
        BSR.W   RESMGR_PROLOG                   | full prologue: clear ROMMapInsert/CurOnly/ResErr
        MOVE    #-0xC2,(ResErr).w               | preset addResFailed error
        MOVE.L  18(A6),A1                       | A1 = handle to add as resource
        MOVE.L  A1,D0                           | test handle for NIL
        BEQ.B   ADDRESOURCE_ERR                 | NIL handle - abort
        BSR.W   RESMGR_CONT_12                  | check if handle already in a resource map
        BEQ.B   ADDRESOURCE_ERR                 | already a resource - can't add again
        BSR.W   RETURNS_21                      | find map for CurMap (current resource file)
        BSR.W   CHECKLOAD_OK_4_CONT             | ensure file can grow for new resource
        BMI.B   ADDRESOURCE_ERR                 | error - abort
        MOVE.L  14(A6),D3                       | D3 = resource type from caller param
        BSR.B   ADDRESOURCE_CONT                | find or create type entry, make ref slot
        MOVE    12(A6),(A2)+                    | store resource ID in new ref entry
        MOVE    (MinusOne).w,(A2)+              | name offset = -1 (no name yet)
        MOVE.L  #0x02000000,(A2)+               | resAttr=0x02 (resChanged), dataOffset=0
        MOVE.L  18(A6),A0                       | A0 = handle being added
        BSET    #0x5,(A0)                       | set resource flag in master pointer
        MOVE.L  A0,(A2)                         | store handle in ref entry (offset 8)
        SUBQ.L  #0x8,A2                         | back up A2 to ref entry start
        MOVE.L  8(A6),A0                        | A0 = resource name Pascal string
        BSR.W   RMVERESOURCE_EMPTY              | add name to name list if non-empty
        BSR.W   CHECKLOAD_CONT_9_CONT_9         | place the resource data at the end of the data area
ADDRESOURCE_ERR:
        MOVEQ    #0xE,D0                        | D0 = 14 bytes of params to pop
        BRA.W    RESMGR_EXIT_TRAMP              | jump to common epilogue

| ----------------------------------------------------------
| ADDRESOURCE_CONT
| Called during boot.
ADDRESOURCE_CONT:
        BSET    #0x5,22(A3)                     | set mapChanged flag in map attributes
        BSR.W   RETURNS_26                      | search type list for matching type D3
        BEQ.B   ADDRESOURCE_CONT_2              | type exists - add ref to existing type
        MOVEQ.L #0x14,D0                        | 20 bytes: 8 (type entry) + 12 (ref entry)
        BSR.W   RMVERESOURCE_CONT               | grow map handle by 20 bytes
        BSR.W   RETURNS_23                      | re-get type list after handle resize
        BMI.B   ADDRESOURCE_EMPTY               | empty list - use current position
        BSR.W   RETURNS_27                      | skip past existing refs to find insert point
ADDRESOURCE_EMPTY:
        MOVE.L  A2,A3                           | A3 = insertion point for new type entry
        MOVE.L  (A4),A2                         | dereference map handle
        ADDA.W  26(A2),A2                       | A2 = name list start
        SUBA.W  #0x14,A2                        | back up 20 bytes (new space at end)
        MOVEQ.L #0x8,D0                         | shift 8 bytes (type entry size)
        MOVE.L  A3,A0                           | A0 = source: old position
        MOVE.L  A2,A1                           | A1 = dest: shifted position
        BSR.W   RMVERESOURCE_CONT_4             | block move existing data down by 8 bytes
        MOVE.L  (A4),A0                         | dereference map handle
        ADDA.W  24(A0),A0                       | A0 = type list count word
        ADDQ.W  #0x1,(A0)                       | increment number of types
        MOVE.L  D3,(A3)+                        | store new resource type in type entry
        CLR     (A3)+                           | count-1 = 0 (one resource of this type)
        SUBA.L  A0,A1                           | compute ref list offset from type list
        MOVE    A1,(A3)                         | store ref list offset in type entry
        ADDQ.L  #0x8,A2                         | A2 = new ref entry (after type entry)
        MOVE    (A0)+,D5                        | D5 = updated type count for ADDRESOURCE_LOOP loop
        BRA.B   ADDRESOURCE_LOOP                | fix offsets for following types
ADDRESOURCE_CONT_2:
        MOVEQ.L #0xC,D0                         | D0 = 12 bytes (one ref entry)
        BSR.W   RMVERESOURCE_CONT               | grow map handle by 12 bytes
        MOVE.L  (A4),A1                         | A1 = map base ptr
        ADDA.W  26(A1),A1                       | A1 = name list start
        SUBA.W  D0,A1                           | A1 = end of new free space
        BSR.W   RETURNS_26                      | re-find type entry for type D3
        MOVE.L  A2,-(SP)                        | save type entry pointer
        ADDQ.W  #0x1,4(A2)                      | 4(A2) += 0x1
        MOVE    6(A2),A2                        | A2 = ref list relative offset
        ADDA.L  A3,A2                           | A2 = absolute ref list ptr
        MOVE.L  A2,A0                           | A0 = first existing ref entry
        MOVEQ.L #0xC,D0                         | D0 = 12 bytes per ref entry
        BSR.W   RMVERESOURCE_CONT_4             | shift refs down to make slot
        MOVE.L  (SP)+,A0                        | A0 = saved type entry pointer
        BRA.B   ADDRESOURCE_CONT_3              | advance to next type, fix ofs
ADDRESOURCE_LOOP:
        ADD     D0,6(A0)                        | 6(A0) += D0
ADDRESOURCE_CONT_3:
        ADDQ.W  #0x8,A0                         | advance to next type entry
        DBRA    D5,ADDRESOURCE_LOOP             | fix offsets for all following
        RTS                                     | return after offset adjustment

| ----------------------------------------------------------
| AddReference -- _AddReference ($A9AC). Plus 1292 (stub).
| Classic ROM has full implementation: copy a System-file resource into
| the current resource file by reference. Plus replaces this with a
| stub that just sets addRefFailed (the System-file mechanism changed).
AddReference:
        BSR.W   RESMGR_PROLOG                   | prologue
        MOVE    #-0xC3,(ResErr).w               | preset addRefFailed error
        MOVE    (CurMap).w,D0                   | D0 = current resource file
        CMP     (SysMap).w,D0                   | CurMap == SysMap?
        BEQ.B   ADDREFERENCE_ERR                | system map - can't add ref
        MOVE.L  14(A6),A1                       | A1 = source resource handle
        BSR.W   RETURNS_24_CONT_4               | ensure source is in CurMap
        BEQ.B   ADDREFERENCE_ERR                | already in CurMap - bail
        BSR.W   RESMGR_CONT_12                  | locate handle's home map
        BMI.B   ADDREFERENCE_ERR                | not found - bail
        CMP     (SysMap).w,D6                   | home must be SysMap
        BNE.B   ADDREFERENCE_ERR                | not in SysMap - bail
        BSR.W   RESMGR_CONT_16                  | get pointer to resource name
        MOVE.L  A0,-(SP)                        | push name string ptr
        MOVE    (A2),-(SP)                      | push source resID
        BSR.W   RETURNS_21                      | set up search from CurMap
        SUBA.L  A1,A1                           | A1 = NIL (any handle for grow chk)
        BSR.W   CHECKLOAD_OK_4_CONT             | ensure CurMap can grow
        BEQ.B   ADDRESOURCE_EMPTY_CONT_3        | ok - go add reference
        ADDQ.W  #0x6,SP                         | drop name+ID from stack
        BRA.W   ADDREFERENCE_ERR                | error - bail
ADDRESOURCE_EMPTY_CONT_3:
        BSR.W   ADDRESOURCE_CONT                | find/create type, alloc ref slot
        MOVE.L  8(A6),A0                        | A0 = caller's name string
        BSR.W   RMVERESOURCE_EMPTY              | add caller name to name list
        MOVE    12(A6),(A2)                     | store caller resID in new ref
        CLR.L   4(A2)                           | clear attrs+offset
        BSET    #0x7,4(A2)                      | set resSysRef (bit 7): entry is a reference
        ADDQ.W  #0x8,A2                         | A2 -> refID (+$8) / refNameOff (+$A)
        MOVE    (SP)+,(A2)                      | store source resID at +8
        MOVE.L  (SP)+,A0                        | A0 = saved source name ptr
        BSR.W   RMVERESOURCE_EMPTY              | add source name to name list
ADDREFERENCE_ERR:
        BRA.W   SETRESINFO_ERR                  | epilogue: pop 10 bytes

| ----------------------------------------------------------
| RmveResource -- _RmveResource ($A9AD). Plus 1543.
| Remove a resource handle from the current resource file. Marks
| map changed + compact-needed. Falls into RMVE_MARK_MAP common path.
RmveResource:
        BSR.W   RESMGR_PROLOG                   | prologue
        MOVE    #-0xC4,(ResErr).w               | preset rmvResFailed error
        MOVE.L  (A0),A1                         | A1 = master pointer (dereference handle)
        BSR.W   RESMGR_CONT_12                  | locate ref entry across maps
        BMI.B   RMVERESOURCE_EXIT               | not found - bail
        BTST    #0x3,4(A2)                      | test resProtected bit
        BNE.B   RMVERESOURCE_EXIT               | protected - cannot remove
        CMP     (CurMap).w,D6                   | verify home is CurMap
        BNE.B   RMVERESOURCE_EXIT               | in different map - bail
        BCLR    #0x5,(A1)                       | clear resource flag in master pointer
        MOVEQ.L #0x60,D0                        | mapChanged + mapCompact bits

| ----------------------------------------------------------
| RMVERESOURCE_MARK -- common tail used by RmveResource (full path,
| D0 = 0x60 = mapChanged + mapCompact) and RmveReference (D0 = 0x20 =
| mapChanged only). OR's D0 into the map attributes byte and shrinks
| the map handle to remove the freed entries.
RMVERESOURCE_MARK:
        MOVE.L  (A4),A0                         | dereference map handle
        OR.B    D0,22(A0)                       | mapAttr |= D0
        BSR.W   RMVERESOURCE_CONT_4_CONT        | rebuild type/ref pointers
        MOVEQ.L #-0xC,D7                        | D7 = -12 (one ref entry shrink)
        MOVE.L  A2,A0                           | A0 = ref entry to remove
        SUBA.W  D7,A0                           | A0 = first byte after ref entry
        BSR.W   RETURNS_26                      | re-find type entry for D3
        MOVE.L  (A4),A1                         | A1 = map base
        ADDA.W  26(A1),A1                       | A1 = end of name list
        MOVE.L  D7,D0                           | D0 = -12 (shift count)
        BSR.W   RMVERESOURCE_CONT_4             | shift refs+names up by 12
        MOVE.L  A2,A0                           | A0 = type entry being modified
        ADDQ.W  #0x8,A0                         | skip past this type entry
        SUBQ.W  #0x1,D5                         | decrement remaining-types count
        BMI.B   RMVERESOURCE_TYPE_DEC           | no more types - go decrement
        BSR.W   ADDRESOURCE_LOOP                | fix offsets for following types
RMVERESOURCE_TYPE_DEC:
        SUBQ.W  #0x1,4(A2)                      | decrement count-1 for this type
        BPL.B   RMVERESOURCE_KEEP_TYPE          | still has resources - keep type entry
        ADDQ.W  #0x8,A2                         | point past type entry to remove
        MOVE.L  A2,A0                           | A0 = source for shift up
        ADDA.W  D0,A1                           | adjust dest limit for ref list shrink
        MOVEQ.L #-0x8,D0                        | D0 = -8 (shrink by one type entry)
        ADD.L   D0,D7                           | total shrink = -20 (type + ref)
        BSR.W   RMVERESOURCE_CONT_4             | shift subsequent data up by 8 bytes
        MOVE.L  (A4),A0                         | dereference map handle
        ADDA.W  24(A0),A0                       | A0 = type list count word
        SUBQ.W  #0x1,(A0)                       | decrement number of types
        MOVE    (A0)+,D5                        | D5 = updated type count
        BMI.B   RMVERESOURCE_KEEP_TYPE          | no types left - skip offset fixup
        BSR.W   ADDRESOURCE_LOOP                | adjust ref list offsets for remaining types
RMVERESOURCE_KEEP_TYPE:
        MOVE.L  D7,D0                           | D0 = total bytes to shrink
        BSR.W   RMVERESOURCE_CONT               | shrink map handle by D0
        CLR     (ResErr).w                      | clear ResErr (success)
RMVERESOURCE_EXIT:
        BRA.W   RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
| RmveReference -- _RmveReference ($A9AE). Plus 1303 (stub).
| Classic ROM has full implementation: remove a resource reference
| from the current resource file's ref list (without removing the
| resource itself if it's also in another file). Plus stubs this.
RmveReference:
        BSR.W   RESMGR_PROLOG                   | prologue
        MOVE    #-0xC5,(ResErr).w               | preset rmvRefFailed error
        MOVE.L  (A0),A1                         | A1 = master pointer
        BSR.W   RETURNS_24_CONT_4               | find ref entry in CurMap
        BMI.B   RMVERESOURCE_EXIT               | not found - error exit
        BTST    #0x3,4(A2)                      | test resProtected
        BNE.B   RMVERESOURCE_EXIT               | protected - error exit
        ADDQ.W  #0x8,A2                         | A2 -> refID (+$8) / refNameOff (+$A)
        BSR.W   RMVERESOURCE_CONT_4_CONT        | remove the name at refNameOff from the name list
        SUBQ.W  #0x8,A2                         | restore A2
        MOVEQ.L #0x20,D0                        | mapChanged only (bit 5)
        BRA.W   RMVERESOURCE_MARK               | mark map changed + return

| ----------------------------------------------------------
| ResError -- _ResError ($A9AF). Plus 1284.
| Returns the most recent Resource Manager error code.
ResError:
        MOVE    (ResErr).w,4(SP)                | return last Resource Mgr error code
        RTS                                     | return ResErr to caller

| ----------------------------------------------------------
| RMVERESOURCE_EMPTY -- store name in ref entry's name-offset slot,
| appending the Pascal string to the map's name list if non-empty.
| Called by AddResource (line 809), SetResInfo (line 779), and the
| AddReference body (lines 899/906). (Plus's
| RMVERESOURCE_EMPTY differs by an added CLR.L (RMgrLastResHand).w
| at entry and uses the extracted RMVERESOURCE_CONT_3 helper instead
| of inline RMVERESOURCE_CONT_OK).
| Entry: A0 = Pascal name string, A2 = ref entry. Exit: ref's name
| offset field set to -1 (empty) or new offset into name list.
RMVERESOURCE_EMPTY:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save working registers
        MOVEQ.L #-0x1,D2                        | D2 = -1 (no-name default)
        TST.B   (A0)                            | name string empty (length 0)?
        BEQ.B   RMVERESOURCE_OK                 | yes - store -1 as name offset
        MOVE.L  (A4),A1                         | A1 = dereferenced map handle
        MOVE.L  12(A1),D1                       | D1 = current map size
        MOVE.L  D1,D2                           | D2 = old map size = append position
        MOVEQ.L #0x0,D0                         | clear D0 for byte extension
        MOVE.B  (A0),D0                         | D0 = name string length
        ADDQ.L  #0x1,D0                         | + 1 for length byte
        BSR.W   RMVERESOURCE_CONT_OK            | grow map by name size + write to disk
        MOVE.L  (A4),A1                         | re-dereference (may have moved)
        MOVE    26(A1),D0                       | D0 = name list offset
        SUB     D0,D2                           | D2 = name offset relative to name list
        ADDA.L  D1,A1                           | A1 = old map end = dest for name copy
        BSR.W   GETRESINFO_CONT                 | copy Pascal name string A0 -> A1
RMVERESOURCE_OK:
        MOVE    D2,2(A2)                        | store name offset in ref entry
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore working registers
        RTS                                     | return after name copy
RMVERESOURCE_CONT:
        MOVEM.L D0-D1/A0-A1,-(SP)               | save working registers
        MOVE.L  (A4),A0                         | dereference map handle
        MOVE.L  12(A0),D1                       | D1 = current map size
        TST.L   D0                              | growing (positive) or shrinking (negative)?
        BMI.B   RMVERESOURCE_CONT_CONT          | shrinking - resize after move
        BSR.B   RMVERESOURCE_CONT_OK            | grow map handle by D0 bytes
        MOVE.L  (A4),A0                         | re-dereference after resize
RMVERESOURCE_CONT_CONT:
        MOVE.L  A0,A1                           | A1 = map base
        ADDA.W  26(A0),A0                       | A0 = name list start
        ADD     D0,26(A1)                       | 26(A1) += D0
        ADDA.L  D1,A1                           | A1 = end of map
        BSR.B   RMVERESOURCE_CONT_4             | shift name list by D0 bytes
        TST.L   D0                              | shrink (negative) or grow?
        BPL.B   RMVERESOURCE_CONT_CONT_2        | grow - already done
        BSR.B   RMVERESOURCE_CONT_OK            | shrink - resize map after move
RMVERESOURCE_CONT_CONT_2:
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore working registers
        RTS                                     | return after resize
RMVERESOURCE_CONT_OK:
        SUBA.L  (A4),A3                         | A3 := relative type-list ofs
        SUBA.L  (A4),A2                         | A2 := relative ref-entry ofs
        MOVEM.L D0/A0,-(SP)                     | save D0/A0
        MOVE.L  (A4),A0                         | A0 = map base
        ADD.L   12(A0),D0                       | D0 = new map size
        MOVE.L  D0,12(A0)                       | map[12] = updated size
        MOVE.L  A4,A0                           | A0 = map handle
        _SetHandleSize                          | resize map handle
        BSR.W   CHECKLOAD_OK_3                  | extend file fork if writable
        MOVEM.L (SP)+,D0/A0                     | restore D0/A0
        ADDA.L  (A4),A3                         | A3 := absolute type-list ptr
        ADDA.L  (A4),A2                         | A2 := absolute ref-entry ptr
        RTS                                     | return after resize

| ----------------------------------------------------------
| RMVERESOURCE_CONT_4
| Called during boot.
RMVERESOURCE_CONT_4:
        MOVEM.L D0/A0-A1,-(SP)                  | save registers
        EXG     D0,A1                           | D0 = dest end, A1 = shift delta
        SUB.L   A0,D0                           | D0 = byte count (dest - source)
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit count (handles negative)
        ADDA.L  A0,A1                           | A1 = source + delta = destination start
        _BlockMove                              | move D0 bytes from A0 to A1
        MOVEM.L (SP)+,D0/A0-A1                  | restore registers
        RTS                                     | return after memory move
RMVERESOURCE_CONT_4_CONT:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save working registers
        MOVE    2(A2),D2                        | D2 = name offset from ref entry
        BMI.B   RMVERESOURCE_CONT_4_CONT_4      | no name (-1) - skip name removal
        MOVE.L  (A4),A0                         | A0 = map base
        MOVE.L  A0,A1                           | A1 = map base
        ADDA.W  26(A0),A0                       | A0 = name list start
        ADDA.W  D2,A0                           | A0 = name string in name list
        ADDA.L  12(A1),A1                       | A1 = end of map
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A0),D0                         | D0 = name length
        ADDQ.L  #0x1,D0                         | +1 for length byte
        ADDA.L  D0,A0                           | A0 = first byte after name
        NEG.L   D0                              | D0 = -length (shrink delta)
        MOVE.L  D0,D1                           | D1 = shrink amount
        BSR.B   RMVERESOURCE_CONT_4             | shift map up by name size
        BSR.B   RMVERESOURCE_CONT_OK            | resize map handle
        MOVEM.L D3-D7/A2-A4,-(SP)               | save more registers
        BSR.W   RETURNS_24                      | get first type + ref list
RMVERESOURCE_CONT_4_CONT_2:
        LEA.L     2(A2),A1                      | A1 = name offset slot of ref
        MOVE.B  4(A2),D0                        | D0 = rAttr (+$4); bit 7 = resSysRef
RMVERESOURCE_CONT_4_NO:
        TST     (A1)                            | test name offset (-1 if none)
        BMI.B   RMVERESOURCE_CONT_4_CONT_3      | no name - skip
        CMP     (A1),D2                         | compare ref's name ofs with D2
        BGE.B   RMVERESOURCE_CONT_4_CONT_3      | before removed name - keep
        ADD     D1,(A1)                         | (A1) += D1
RMVERESOURCE_CONT_4_CONT_3:
        ADDQ.W  #0x8,A1                         | A1 -> refNameOff (+$A)
        BCLR    #0x7,D0                         | test+clear resSysRef (bit 7)
        BNE.B   RMVERESOURCE_CONT_4_NO          | reference: adjust refNameOff too
        BSR.W   RETURNS_28                      | advance to next ref entry
        BPL.B   RMVERESOURCE_CONT_4_CONT_2      | more entries - continue
        MOVEM.L (SP)+,D3-D7/A2-A4               | restore registers
RMVERESOURCE_CONT_4_CONT_4:
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore working registers
        MOVE    (MinusOne).w,2(A2)              | ref's name offset := -1
        RTS                                     | return after fixup

