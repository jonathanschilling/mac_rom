| Resource Manager
|
| Manages resources in resource files (including the ROM resource map
| at $176F8). Provides GetResource, LoadResource, ReleaseResource,
| AddResource, WriteResource, OpenResFile, CloseResFile, and
| resource map manipulation routines.
|
| The ROM itself contains a resource fork with DRVR, FONT, CURS,
| PACK, WDEF, MDEF, and SERD resources.
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
|
| References:
| Inside Macintosh Vol I, Ch 5: The Resource Manager

| ROM section: src/toolbox/resource_mgr.asm
|
| _GetIndResource inner loop: advance to next resource of matching type
| Called after RETURNS_24 sets up type list scan; iterates across types and maps
RESMGR_SKIP:
        BSR     RETURNS_28                      | advance to next ref entry in type list
        BEQ.B   GETNAMED_CMP_NAME               | found one - go load it
RESMGR_NEXT:
        BSR.B   RETURNS_22                      | advance to next map in chain
        BEQ.B   GETNAMED_LOOP                   | found map - scan its type list
        MOVE    #-0xC0,(ResErr).w               | resNotFound: no more maps to search
        BRA.B   RESMGR_SKIP_2                   | skip to epilogue with resNotFound

| ----------------------------------------------------------
|
| RESMGR_FOUND - GetIndResource: found matching resource
|
| Caches search state and loads the resource via CheckLoad.
RESMGR_FOUND:
        BSR     RESMGR_CONT_14                  | cache current search position in RMgr globals
        BSR     P_CheckLoad                     | load resource data into memory if needed
        MOVE.L  A0,0x10(A6)                     | store result handle in caller's stack frame
        MOVE.L  A0,(RMgrLastResHand).w          | cache as last-accessed resource handle
RESMGR_SKIP_2:
        MOVEQ.L #0x8,D0                         | 8 bytes of parameters to clean up
        BRA     RESMGR_CONT_11                  | go to common trap epilogue

| ----------------------------------------------------------
|
| RETURNS_20 - SetupMapScan: begin resource map chain traversal
|
| If RMgrCurOnly is set, searches only the current map (via RETURNS_21).
| Otherwise starts from the topmost (most recently opened) resource file.
| Returns: A4=map handle, A3=A2=dereferenced map ptr, D6=file refNum.
| Called by: CountResources, GETIND_FRESH, COUNT_UNIQ_TYPES, UNIQID_RETRY, GetResource (and 1 more)
RETURNS_20:
        TST.B   (RMgrCurOnly).w                 | search all maps or just current?
        BNE.B   RETURNS_21                      | current only - use CurMap refNum
        MOVE.L  (TopMapHndl).w,A4               | start from top of resource chain
        MOVE.L  (A4),A3                         | dereference map handle
        MOVE    0x14(A3),D6                     | D6 = file reference number
        MOVE.L  A3,A2                           | A2 = map pointer (for scanning)
        RTS                                     | return map pointer in A2

| ----------------------------------------------------------
|
| RETURNS_21 - FindMapByRefNum: locate map handle for a given refNum
|
| Walks the resource chain from TopMapHndl to find the map whose
| file refNum matches D6. refNum=0 means System file (SysMap).
| Returns: A4=map handle, A3=A2=map ptr; falls through to RESMGR_ERR if not found.
RETURNS_21:
        MOVE    (CurMap).w,D6                   | get current resource file refNum
| RESMGR_CONT -- find first resource type in the current map.
| Called by: INITRESOURCES_CONT_5, NewMap, SetResFileAttrs, STDMAPENTRY, CLOSERES_UNLINK
RESMGR_CONT:
        TST     D6                              | negative = invalid
        BMI     RESMGR_ERR                      | return error (not found)
        BNE.B   RESMGR_CONT_2                   | nonzero = specific file
        MOVE    (SysMap).w,D6                   | refNum 0 means System resource file
RESMGR_CONT_2:
        MOVE.L  (TopMapHndl).w,A4               | start walking from top of chain
        MOVEQ.L #0x0,D0                         | clear D0 for first iteration test
        BRA.B   RESMGR_LOOP                     | enter comparison loop

| ----------------------------------------------------------
|
| RESMGR_FOUND_2 - walk to next map in resource chain
|
| Follows the nextMap handle link (offset 0x10) to traverse the chain.
| PORTRECT offset = 0x10, which is the "next map handle" field.
RESMGR_FOUND_2:
        MOVE.L  PORTRECT(A3),D0                 | get next map handle from chain link
        BEQ     RESMGR_ERR                      | NIL = end of chain, not found
        EXG     D0,A4                           | A4 = next map handle
RESMGR_LOOP:
        MOVE.L  (A4),A3                         | dereference map handle
        CMP     0x14(A3),D6                     | compare map's refNum with target
        BNE.B   RESMGR_FOUND_2                  | no match - follow chain link
        MOVE.L  A3,A2                           | A2 = found map pointer
        RTS                                     | return matched map in A2

| ----------------------------------------------------------
|
| RETURNS_22 - NextMap: advance to next resource map in chain
|
| If searching current map only, returns NIL (end of search).
| Otherwise follows the nextMap chain link to the next open resource file.
| Returns: Z=0 if another map found, Z=1 if end of chain.
| Called by: COUNTRES_NEXTMAP, GETIND_NEXTMAP, CNTTYPE_NEXTMAP, UNIQID_NEXTMAP, GETRES_NEXTMAP (and 2 more)
RETURNS_22:
        TST.B   (RMgrCurOnly).w                 | searching current map only?
        BEQ.B   RESMGR_NEXT_2                   | no - follow chain to next map
        SUBA.L  A4,A4                           | yes - force NIL (no more maps)
        BRA.B   RESMGR_EXIT                     | test NIL and return end-of-chain

| ----------------------------------------------------------
|
| RESMGR_NEXT_2 - follow chain link to next map
|
RESMGR_NEXT_2:
        MOVE.L  (A4),A3                         | dereference current map handle
        MOVE.L  PORTRECT(A3),A4                 | A4 = next map handle (offset 0x10)
RESMGR_EXIT:
        MOVE.L  A4,D0                           | test if next map handle is NIL
        BEQ.B   RESMGR_ERR                      | NIL = end of chain
        MOVE.L  (A4),A3                         | dereference next map handle
        MOVE    0x14(A3),D6                     | D6 = file refNum of this map
        BRA.B   RESMGR_EXIT_3                   | return success (D0=0)

| ----------------------------------------------------------
|
| RETURNS_23 - GetTypeList: set up type list pointer for current map
|
| Dereferences the map handle and advances to the type list.
| VISRGN offset = 0x18, which is the "offset to type list" field in map.
| Returns: A2=first type entry, A3=type list base, D5=numTypes-1 (or -1).
RETURNS_23:
        MOVE.L  (A4),A3                         | dereference map handle
        ADDA    VISRGN(A3),A3                   | add type list offset (at map+0x18)
        MOVE.L  A3,A2                           | A2 = type list pointer
        MOVE    (A2)+,D5                        | D5 = number of types minus 1
        RTS                                     | return type list in A2 and count in D5

| ----------------------------------------------------------
|
| RESMGR_CONT_3 - CountAllRefs: count total reference entries in map
|
| Walks all type entries, summing their reference counts into D4.
| Used to find the end of reference lists (for name list offset calc).
| Called by: INITRESOURCES_CONT_3, INITRESOURCES_CONT_5, RsrcZoneInit, FINDNEXT_ENTER, UPDRES_COMPACT (and 2 more)
RESMGR_CONT_3:
        BSR.B   RETURNS_24                      | get first type entry + ref list
        BMI.B   RESMGR_EXIT_2                   | empty map - return
        ADDQ.W  #0x6,A3                         | skip past first type entry header
        ADD     D5,D4                           | D4 += remaining types count
        BRA.B   RESMGR_LOOP_3                   | enter accumulation loop

| ----------------------------------------------------------
|
| RESMGR_LOOP_2 - accumulate ref counts per type
|
RESMGR_LOOP_2:
        ADDQ.W  #0x8,A3                         | advance to next type entry (8 bytes)
        ADD     (A3),D4                         | D4 += count-1 for this type
RESMGR_LOOP_3:
        DBF     D5,RESMGR_LOOP_2                | loop through all type entries
RESMGR_EXIT_2:
        RTS                                     | return after summing resource counts

| ----------------------------------------------------------
|
| RETURNS_24 - GetFirstType: get first type entry and its ref list
|
| Sets up A3=type list, A2=first ref list, D3=first resType, D4=count-1.
| Returns: N flag set if type list is empty (D5 < 0).
RETURNS_24:
        BSR.B   RETURNS_23                      | A2=type list, D5=numTypes-1
        MOVE.L  (A2),D3                         | D3 = first resource type (e.g. 'DRVR')
        BSR.B   RETURNS_27                      | A2 = ref list for this type, D4=count-1
        TST     D5                              | test if any types exist
        RTS                                     | return Z flag set if no types exist

| ----------------------------------------------------------
|
| RETURNS_25 - FindResID: search ref list for resource by ID
|
| Scans the reference list entries (12 bytes each) looking for
| a resource whose ID (at ref+0) matches D2.
| Returns: A2=matching ref entry if found; branches to RESMGR_ERR if not.
RETURNS_25:
        MOVEQ.L #0xC,D0                         | 12 = size of each reference entry
RESMGR_LOOP_4:
        CMP     (A2),D2                         | compare ref entry ID with target D2
        ADDA    D0,A2                           | advance A2 past this entry
        DBEQ    D4,RESMGR_LOOP_4                | loop until match or end of list
        BEQ.B   RESMGR_FOUND_3                  | matched - back up to entry
        BRA.B   RESMGR_ERR                      | not found

| ----------------------------------------------------------
|
| RETURNS_26 - FindResType: search type list for matching resource type
|
| Scans the type list (8-byte entries) for a type matching D3.
| Returns: A2=matching type entry if found; branches to RESMGR_ERR if not.
| Called by: COUNTRES_LOOP, GETIND_FIND_TYPE, UNIQID_CHECK, GETRES_FIND_TYPE, GETNAMED_LOOP (and 3 more)
RETURNS_26:
        BSR.B   RETURNS_23                      | A2=type list, D5=numTypes-1
        BMI.B   RESMGR_ERR                      | empty type list - not found
        MOVEQ.L #0x8,D0                         | 8 = size of each type entry
RESMGR_LOOP_5:
        CMP.L   (A2),D3                         | compare type entry with target D3
        ADDA    D0,A2                           | advance past this type entry
        DBEQ    D5,RESMGR_LOOP_5                | loop until match or end
        BEQ.B   RESMGR_FOUND_3                  | matched - back up to entry
        BRA.B   RESMGR_ERR                      | not found

| ----------------------------------------------------------
|
| RETURNS_27 - GetRefList: get reference list for a type entry
|
| Given A2 pointing to a type entry, loads the count and computes
| the absolute pointer to its reference list.
| Returns: D4=count-1, A2=pointer to first reference entry.
| Called by: GETIND_FIND_TYPE, UNIQID_CHECK, GETRES_FIND_TYPE, GETNAMED_LOOP, RETURNS_24 (and 1 more)
RETURNS_27:
        MOVE    0x4(A2),D4                      | D4 = number of resources - 1
        MOVE.L  D0,-(SP)                        | save D0
        MOVEQ.L #0x0,D0                         | clear D0 for word extension
        MOVE    0x6(A2),D0                      | ref list offset from type list start
        MOVE.L  D0,A2                           | use as address displacement
        MOVE.L  (SP)+,D0                        | restore D0
        ADDA.L  A3,A2                           | A2 = type list base + offset = ref list
        RTS                                     | return ref list pointer in A2

| ----------------------------------------------------------
|
| RESMGR_FOUND_3 - search hit: back up A2 to point at matched entry
|
RESMGR_FOUND_3:
        SUBA    D0,A2                           | A2 was advanced past match; back up
RESMGR_EXIT_3:
        MOVEQ.L #0x0,D0                         | return success (D0=0, Z=1)
        RTS                                     | return success with D0=0

| ----------------------------------------------------------
|
| RESMGR_ERR - search miss: return "not found"
|
| Called by: SUPERLOAD_ERR, RESMGR_LOOP_4, RESMGR_LOOP_5, RESMGR_EMPTY, RESMGR_EXIT_7
RESMGR_ERR:
        MOVEQ.L #-0x1,D0                        | return failure (D0=-1, N=1)
        RTS                                     | return failure with D0=-1

| ----------------------------------------------------------
|
| RESMGR_CONT_4/RESMGR_CONT_5/RESMGR_CONT_6 - Resource Manager trap prologue
|
| RESMGR_CONT_4: full prologue (clears ROMMapInsert, CurOnly, ResErr)
| RESMGR_CONT_5: partial prologue (clears CurOnly + ResErr, preserves ROMMapInsert)
| RESMGR_CONT_6: minimal prologue (clears ResErr only)
| Sets up a LINK frame with 50 bytes of local storage and saves registers.
| If ROMMapInsert is set, inserts ROM map into chain before searching.
RESMGR_CONT_4:
        CLR     (ROMMapInsert).w                | clear ROM map insertion flag
| RESMGR_CONT_5 -- prologue: clear CurOnly, ResErr, set up frame.
RESMGR_CONT_5:
        CLR.B   (RMgrCurOnly).w                 | search all maps, not just current
| RESMGR_CONT_6 -- minimal prologue: clear ResErr.
| Called by: CountResources, GetIndResource, CountTypes, GetIndType, UniqueID (and 2 more)
RESMGR_CONT_6:
        CLR     (ResErr).w                      | clear last error code
        MOVE.L  (SP)+,A0                        | pop return address
        LINK    A6,#-0x32                       | allocate 50 bytes of locals
        CLR     -0x1C(A6)                       | clear local: search result flags
        CLR     -0x18(A6)                       | clear local: temp storage
        MOVE.B  (RMgrPerm).w,-0x17(A6)          | save RMgrPerm in locals
        MOVEM.L D1-D7/A1-A4,-(SP)               | save all working registers
        SUBA.L  A4,A4                           | A4 = NIL (no map selected yet)
        MOVE.L  A0,-(SP)                        | push return address back
        LEA.L   0x8(A6),A0                      | A0 = base of caller parameters
        TST.B   (ROMMapInsert).w                | should ROM map be in chain?
        BEQ.B   RESMGR_SKIP_3                   | no - skip insertion
        MOVEQ.L #0x0,D1                         | D1=0: insert ROM map before SysMap
        BSR.B   RESMGR_CONT_7                   | insert ROM map into resource chain
RESMGR_SKIP_3:
        RTS                                     | return after ROM map insertion

| ----------------------------------------------------------
|
| RESMGR_CONT_7 - InsertRemoveROMMap: insert/remove ROM map in resource chain
|
| D1=0: insert ROM map between SysMap and its predecessor
| D1!=0: remove ROM map from chain (reverse the insertion)
| This allows the ROM resource fork to be searched alongside disk files.
| Also swaps ResLoad/TmpResLoad so ROM resources respect the load flag.
RESMGR_CONT_7:
        MOVEM.L D0/A0-A2,-(SP)                  | save working registers
        MOVE.L  (SysMapHndl).w,A1               | A1 = system resource map handle
        MOVE.L  (ROMMapHandle).w,A2             | A2 = ROM resource map handle
        CMPA.L  A1,A2                           | ROM map same as system map?
        BEQ.B   RESMGR_CONT_10                  | already linked - nothing to do
        MOVE    (CurMap).w,D0                   | save current map refNum
        TST.L   D1                              | insert (0) or remove (nonzero)?
        BEQ.B   RESMGR_CONT_8                   | D1=0: inserting ROM map
        EXG     A1,A2                           | removing: swap targets
        CMPI    #0x1,D0                         | CurMap points to ROM map (refNum=1)?
        BNE.B   RESMGR_NO                       | no - leave CurMap alone
        MOVE    (SysMap).w,(CurMap).w           | redirect CurMap to System file
        BRA.B   RESMGR_NO                       | continue with chain walk

| ----------------------------------------------------------
|
| RESMGR_CONT_8 - inserting ROM map: update CurMap if it points to SysMap
|
RESMGR_CONT_8:
        CMP     (SysMap).w,D0                   | CurMap == SysMap refNum?
        BNE.B   RESMGR_NO                       | no - leave CurMap alone
        MOVE    #0x1,(CurMap).w                 | redirect CurMap to ROM map (refNum=1)
RESMGR_NO:
        MOVE.L  (TopMapHndl).w,A0               | start walking chain from top
RESMGR_CONT_9:
        MOVE.L  (A0),A0                         | dereference handle
        MOVE.L  0x10(A0),D0                     | get next map handle link
        BEQ.B   RESMGR_OK_2                     | end of chain - check if target is top
        CMP.L   A1,D0                           | found target's predecessor?
        BEQ.B   RESMGR_OK                       | yes - splice in/out the map
        MOVE.L  D0,A0                           | follow chain link
        BRA.B   RESMGR_CONT_9                   | continue walking chain

| ----------------------------------------------------------
|
| RESMGR_OK - splice: replace A1 with A2 in predecessor's next link
|
RESMGR_OK:
        MOVE.L  A2,0x10(A0)                     | predecessor now points to A2
        BRA.B   RESMGR_DONE                     | link ROM map to SysMap and swap ResLoad

| ----------------------------------------------------------
|
| RESMGR_OK_2 - target was TopMapHndl: replace it
|
RESMGR_OK_2:
        CMPA.L  (TopMapHndl).w,A1               | is target the top map?
        BNE.B   RESMGR_DONE                     | no - already done
        MOVE.L  A2,(TopMapHndl).w               | A2 becomes new top map
RESMGR_DONE:
        MOVE.L  (ROMMapHandle).w,A0             | always link ROM map -> SysMap
        MOVE.L  (A0),A0                         | dereference ROM map handle
        MOVE.L  (SysMapHndl).w,0x10(A0)         | ROM map's next = system map
        MOVE.B  (ResLoad).w,D0                  | swap ResLoad with TmpResLoad
        MOVE.B  (TmpResLoad).w,(ResLoad).w      | restore saved ResLoad value
        MOVE.B  D0,(TmpResLoad).w               | preserves load state across insert
RESMGR_CONT_10:
        MOVEM.L (SP)+,D0/A0-A2                  | restore working registers
        RTS                                     | return from map insertion

| ----------------------------------------------------------
|
| RESMGR_EXIT_4-RESMGR_EXIT_6 - trap epilogues with different parameter byte counts
|
| Each sets D0 to the number of parameter bytes to pop from caller's
| stack frame before returning. Falls into RESMGR_CONT_11 common epilogue.
RESMGR_EXIT_4:
        MOVEQ.L #0x6,D0                         | 6 bytes of params (e.g. SetResAttrs)
        BRA.B   RESMGR_CONT_11                  | common epilogue

| Called by: COUNTRES_NEXTMAP, UNIQID_NEXTMAP, CHANGEDRESOURCE_ERR, WRITERESOURCE_SKIP_2, HOMERESFILE_EXIT (and 2 more)
RESMGR_EXIT_5:
        MOVEQ.L #0x4,D0                         | 4 bytes of params (e.g. ReleaseResource)
        BRA.B   RESMGR_CONT_11                  | common epilogue

| Called by: UseResFile, GetResFileAttrs, STDMAPENTRY_ERR, UpdateResFile, CLOSERES_DISPOSE
RESMGR_ERR_2:
        MOVEQ.L #0x2,D0                         | 2 bytes of params (e.g. SetResLoad)
        BRA.B   RESMGR_CONT_11                  | common epilogue

| ----------------------------------------------------------
|
| RESMGR_EXIT_6/RESMGR_CONT_11 - common Resource Manager trap epilogue
|
| Removes ROM map from chain if it was inserted, restores globals,
| then falls into the stack-frame teardown at RESMGR_SKIP_4.
RESMGR_EXIT_6:
        MOVEQ.L #0x0,D0                         | 0 bytes of params (e.g. LoadResource)
| Called by: RESMGR_SKIP_2, RESMGR_EXIT_4, RESMGR_EXIT_5, RESMGR_ERR_2, GETRESINFO_EMPTY_3 (and 2 more)
RESMGR_CONT_11:
        TST.B   (ROMMapInsert).w                | was ROM map inserted into chain?
        BEQ.B   RESMGR_SKIP_4                   | no - skip removal
        MOVEQ.L #-0x1,D1                        | D1!=0: remove ROM map from chain
        BSR     RESMGR_CONT_7                   | remove ROM map
RESMGR_SKIP_4:
        CLR.B   (RMgrCurOnly).w                 | reset to search all maps
        CLR     (ROMMapInsert).w                | clear ROM map insertion flag
        CLR.B   (RMgrPerm).w                    | clear permanent resource flag
        MOVEM.L (SP)+,D1-D7/A1-A4               | restore saved registers
        UNLK    A6                              | tear down stack frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.L  D0,SP                           | remove D0 bytes of parameters
        MOVE.L  A0,-(SP)                        | push return address back
        SUBA.L  A0,A0                           | clear A0 (no handle on error path)
        MOVE    (ResErr).w,D0                   | check last Resource Manager error
        BEQ.B   RESMGR_ERR_3                    | no error - return normally
        MOVE.L  (ResErrProc).w,-(SP)            | push error handler proc address
        BNE.B   RESMGR_ERR_3                    | if non-NIL, RTS will call it
        ADDQ.W  #0x4,SP                         | no handler - pop the NIL
RESMGR_ERR_3:
        RTS                                     | return to caller after error

| ----------------------------------------------------------
|
| RESMGR_CONT_12 - FindResByHandle: find resource map entry for a given handle
|
| Given A1=resource handle, searches all maps for the reference entry
| whose handle field (ref+8) matches. Uses RMgrLastResHand cache for
| fast path. Returns: A2=ref entry, A3=type list, A4=map handle,
| D3=resType, D4=index, D5=type index, D6=refNum. Z=1 if found.
RESMGR_CONT_12:
        MOVE.L  A1,D0                           | test handle for NIL
        BEQ     RESMGR_ERR                      | NIL handle - return not found
        CMPA.L  (RMgrLastResHand).w,A1          | same as last looked-up handle?
        BEQ.B   RESMGR_OK_3                     | yes - use cached position (fast path)
RESMGR_CONT_13:
        BSR     RETURNS_20                      | set up map chain traversal
        MOVE.L  A0,-(SP)                        | save caller's A0
RESMGR_FOUND_4:
        BSR     RETURNS_24                      | get first type and its ref list
        BMI.B   RESMGR_EMPTY                    | empty map - try next
        MOVE.L  A3,A0                           | A0 = type list base
        ADDQ.W  #0x8,A0                         | skip count word + first type entry header
RESMGR_LOOP_6:
        ADDQ.W  #0x2,A0                         | skip to next type's count-1 field
RESMGR_LOOP_7:
        ADDQ.W  #0x8,A2                         | advance to handle field (ref+8)
        CMPA.L  (A2)+,A1                        | compare handle with target
        DBEQ    D4,RESMGR_LOOP_7                | loop through ref entries
        BEQ.B   RESMGR_FOUND_5                  | found matching handle
        MOVE.L  (A0)+,D3                        | D3 = next resource type
        MOVE    (A0)+,D4                        | D4 = count-1 for this type
        DBF     D5,RESMGR_LOOP_6                | loop through remaining types
RESMGR_EMPTY:
        BSR     RETURNS_22                      | advance to next map in chain
        BEQ.B   RESMGR_FOUND_4                  | found map - scan it
        MOVE.L  (SP)+,A0                        | restore caller's A0
        BRA     RESMGR_ERR                      | not found in any map

| ----------------------------------------------------------
|
| RESMGR_FOUND_5 - handle matched: back up A2 to ref entry start and cache
|
RESMGR_FOUND_5:
        SUBA    #0xC,A2                         | A2 was at ref+12; back to entry start
        BSR.B   RESMGR_CONT_14                  | cache search state in RMgr globals
        MOVE.L  (SP)+,A0                        | restore caller's A0
        BRA     RESMGR_EXIT_3                   | return success (D0=0)

| ----------------------------------------------------------
|
| RESMGR_OK_3 - RestoreCachedSearch: fast path using cached search state
|
| Restores the last search position from RMgr globals. If the handle
| at the cached ref entry still matches, returns immediately.
| Otherwise invalidates the cache and does a full search.
RESMGR_OK_3:
        MOVEM.L (RMgrHiVars_LastResType).w,D3/A1-A4 | restore type,handle,ref,typelist,map
        MOVEM   (0xB94).w,D4-D6                 | restore count, type count, refNum
        ADDA.L  (A4),A2                         | convert relative A2 to absolute (ref ptr)
        ADDA.L  (A4),A3                         | convert relative A3 to absolute (type list)
        CMPA.L  0x8(A2),A1                      | cached ref entry still has same handle?
        BEQ     RESMGR_EXIT_3                   | yes - cache hit, return success
        CLR.L   (RMgrLastResHand).w             | cache invalid - clear it
        BRA.B   RESMGR_CONT_13                  | fall through to full search

| ----------------------------------------------------------
|
| RESMGR_CONT_14/RESMGR_CONT_15 - CacheSearchState: save current search position
|
| Converts A2 (ref ptr) and A3 (type list) to relative offsets from
| the map base, stores them along with D3-D6/A1/A4 in RMgr globals.
| RESMGR_CONT_14 also resets the sequential index counter.
RESMGR_CONT_14:
        MOVE    (MinusOne).w,(RMgrNextResIndex).w | reset GetIndResource index cache
| RESMGR_CONT_15 -- cache search state in RMgr globals.
RESMGR_CONT_15:
        MOVE.L  (A4),D0                         | D0 = dereferenced map handle (base addr)
        SUBA.L  D0,A2                           | make A2 relative to map base
        SUBA.L  D0,A3                           | make A3 relative to map base
        MOVEM.L D3/A1-A4,(RMgrHiVars_LastResType).w | save type,handle,ref,typelist,map
        MOVEM   D4-D6,(0xB94).w                 | save count, type count, refNum
        ADDA.L  D0,A2                           | restore A2 to absolute
        ADDA.L  D0,A3                           | restore A3 to absolute
        RTS                                     | return to caller with absolute pointers restored

| ----------------------------------------------------------
|
| RESMGR_CONT_16 - GetResName: get pointer to resource name string
|
| Reads the name offset from the reference entry (ref+2).
| If -1, the resource has no name; returns an empty Pascal string.
| Otherwise computes name list base + offset to return name pointer.
RESMGR_CONT_16:
        MOVE    0x2(A2),D0                      | D0 = name offset (-1 if no name)
        BMI.B   RESMGR_EXIT_7                   | no name - return empty string
        MOVE.L  (A4),A0                         | dereference map handle
        ADDA    0x1A(A0),A0                     | add name list offset (map+0x1A)
        ADDA    D0,A0                           | add per-resource name offset
        BRA     RESMGR_EXIT_3                   | return success, A0 = name string

| ----------------------------------------------------------
|
| RESMGR_EXIT_7 - no resource name: return empty Pascal string
|
RESMGR_EXIT_7:
        LEA.L   RESOURCE_MAP(PC),A0             | point to zero-byte (empty string)
        BRA     RESMGR_ERR                      | return not found

| ----------------------------------------------------------
|
| RETURNS_28 - NextRefEntry: advance to next reference entry
|
| Advances A2 by 12 bytes (one ref entry). If the current type's
| ref list is exhausted, moves to the next type in the type list.
| Returns: Z=1 if valid entry found; N=1 if no more entries.
RETURNS_28:
        ADDA    #0xC,A2                         | advance to next reference entry
        SUBQ.W  #0x1,D4                         | decrement ref count for this type
        BPL     RESMGR_EXIT_3                   | still refs left - return success
        SUBQ.W  #0x1,D5                         | decrement type count
        BMI     RESMGR_ERR                      | no more types - return failure
        MOVE    (A3),D0                         | D0 = numTypes-1 (from type list header)
        SUB     D5,D0                           | index of current type entry
        ASL     #0x3,D0                         | multiply by 8 (type entry size)
        MOVE.L  0x2(A3,D0.W),D3                 | D3 = resource type at this index
        MOVE    0x6(A3,D0.W),D4                 | D4 = count-1 for this type
        MOVEQ.L #0x1,D0                         | return nonzero (valid but new type)
        RTS                                     | return valid type indicator in D0

| ----------------------------------------------------------
|
| RESMGR_OK_4 - LoadROMResource: load resource from ROM (no file I/O)
|
| For ROM map resources, the data offset is relative to ROMBase.
| Creates a "fake" handle by using HandleZone to get the zone,
| then computing a master pointer that points directly into ROM.
RESMGR_OK_4:
        MOVE.L  A1,-(SP)                        | save A1
        MOVE.L  0x4(A2),D0                      | get resAttr byte + 3-byte data offset
        AND.L   (Lo3Bytes).w,D0                 | mask to 3-byte data offset
        ADD.L   (ROMBase).w,D0                  | D0 = absolute ROM address of data
        MOVE.L  D0,A1                           | A1 = pointer to resource data in ROM
        MOVE.L  (ROMMapHandle).w,A0             | get ROM map handle
        _HandleZone                             | A0 = zone containing ROM map handle
        ADDA.L  -0x4(A1),A0                     | A0 = master pointer (resource size before data)
        MOVE.L  A0,0x8(A2)                      | store handle in ref entry
        TST.B   (ResLoad).w                     | should we actually load data?
        BEQ.B   RESMGR_EMPTY_2                  | no - leave handle empty
        MOVE.L  A1,(A0)                         | set master pointer to ROM data address
        BSR     CHECKLOAD_CONT_3                | set handle flags from resAttr
RESMGR_EMPTY_2:
        MOVE.L  (SP)+,A1                        | restore A1
        RTS                                     | return with restored A1

| ----------------------------------------------------------
|
| P_Check Load
|
| Called during boot (22,904 times in 30s trace).
P_CheckLoad:
        MOVE.L  (0x7F0).w,A0                    | dispatch vector: _CheckLoad
        JMP     (A0)                            | call through vector (patchable)

| ----------------------------------------------------------
|
| Check Load
|
| Called during boot (22,904 times in 30s trace).
CheckLoad:
        MOVE.B  0x4(A2),D1                      | D1 = resAttr byte (sysHeap/purgeable/locked/etc)
        CMPA.L  (ROMMapHandle).w,A4             | is this a ROM resource?
        BEQ.B   RESMGR_OK_4                     | yes - load from ROM instead
        MOVE.L  (TheZone).w,-(SP)               | save current heap zone on stack
        BTST    #0x6,D1                         | test resSysHeap attribute (bit 6)
        BEQ.B   CHECKLOAD_NO                    | not sysHeap - use current zone
        MOVE.L  (SysZone).w,(TheZone).w         | allocate in system heap zone
CHECKLOAD_NO:
        MOVE.L  0x8(A2),A0                      | A0 = resource handle from ref entry
        SUBA.L  (A4),A3                         | make A3 relative to map base (relocatable)
        TST.B   (ResLoad).w                     | is auto-loading enabled?
        BEQ.B   CHECKLOAD_EMPTY                 | no - just create empty handle
        MOVE.L  A0,D0                           | test if handle already exists
        BNE.B   CHECKLOAD_OK                    | yes - check if data is loaded
        BSR.B   CHECKLOAD_CONT                  | get resource size, reserve if locked
        _NewHandle                              | allocate new handle for resource data
        BEQ.B   CHECKLOAD_CONT_2                | success - store handle and read data
        BRA.B   CHECKLOAD_ERR                   | allocation failed - set error

| ----------------------------------------------------------
|
| CHECKLOAD_CONT
|
| Called during boot.
CHECKLOAD_CONT:
        BSR.B   CHECKLOAD_CONT_5                | read 4-byte resource size from file
        MOVE.L  D0,D2                           | D2 = resource data size (for later)
        SUBA.L  (A4),A2                         | make A2 relative to map base
        BTST    #0x4,D1                         | test resLocked attribute (bit 4)
        BEQ.B   CHECKLOAD_SKIP                  | not locked - skip memory reservation
        _ResrvMem                               | reserve contiguous block for locked resource
CHECKLOAD_SKIP:
        MOVE.L  D2,D0                           | D0 = resource size for NewHandle/Realloc
        RTS                                     | return resource size in D0

| ----------------------------------------------------------
|
| CHECKLOAD_OK
|
| Called during boot (22,312 times in 30s trace).
CHECKLOAD_OK:
        TST.L   (A0)                            | is handle's master pointer non-NIL?
        BNE.B   CHECKLOAD_ERR_2                 | yes - resource already in memory
        BSR.B   CHECKLOAD_CONT                  | get resource size, reserve if locked
        _ReallocHandle                          | reallocate purged handle with new size
        BMI.B   CHECKLOAD_ERR                   | reallocation failed - set error
CHECKLOAD_CONT_2:
        ADDA.L  (A4),A2                         | restore A2 to absolute ref entry ptr
        MOVE.L  A0,0x8(A2)                      | store new handle in ref entry
        BSR.B   CHECKLOAD_CONT_6                | read resource data from file into handle
        BSR.B   CHECKLOAD_CONT_3                | set handle flags from resAttr bits
        MOVE    (ResErr).w,D0                   | check if read succeeded
        BEQ.B   CHECKLOAD_ERR_2                 | no error - finish successfully
        SUBA.L  (A4),A2                         | make A2 relative again for error path
CHECKLOAD_ERR:
        MOVE    D0,(ResErr).w                   | store error code in ResErr global
        SUBA.L  A0,A0                           | clear A0 (return NIL handle on error)
        BRA.B   CHECKLOAD_EXIT                  | skip to restore and return

| ----------------------------------------------------------
|
| CHECKLOAD_EMPTY
|
| Called during boot.
CHECKLOAD_EMPTY:
        MOVE.L  A0,D0                           | ResLoad=false: test existing handle
        BNE.B   CHECKLOAD_ERR_2                 | handle exists - store it
        SUBA.L  (A4),A2                         | make A2 relative for Memory Mgr call
        _NewEmptyHandle                         | create placeholder handle (no data)
CHECKLOAD_EXIT:
        ADDA.L  (A4),A2                         | restore A2 to absolute ref entry ptr
CHECKLOAD_ERR_2:
        MOVE.L  A0,D0                           | test resulting handle
        BEQ.B   CHECKLOAD_SKIP_2                | NIL - don't store in ref entry
        MOVE.L  A0,0x8(A2)                      | store handle in ref entry (offset 8)
CHECKLOAD_SKIP_2:
        ADDA.L  (A4),A3                         | restore A3 to absolute type list ptr
        MOVE.L  (SP)+,(TheZone).w               | restore saved heap zone
        RTS                                     | return to caller after storing handle

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_3
|
| Called during boot.
CHECKLOAD_CONT_3:
        LSL.B   #0x3,D1                         | shift resAttr: purgeable bit -> bit 7
        BPL.B   CHECKLOAD_NO_2                  | not purgeable - use non-purgeable flags
        MOVEQ.L #-0x7F,D1                       | D1 = 0x81: purgeable + resource flag
        BRA.B   CHECKLOAD_CONT_4                | go set handle flags

| ----------------------------------------------------------
|
| CHECKLOAD_NO_2 - set handle flags for non-purgeable resource
|
| Called during boot.
CHECKLOAD_NO_2:
        MOVEQ.L #-0x80,D1                       | D1 = 0x80: resource flag only, not purgeable
CHECKLOAD_CONT_4:
        ROXR.B  #0x2,D1                         | position lock bit from resAttr into handle flags
        ANDI.B  #0x1F,(A0)                      | clear upper 3 flag bits of master pointer
        OR.B    D1,(A0)                         | set resource/purgeable/lock flags on handle
        RTS                                     | return with updated handle flags

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_5
|
| Called during boot.
CHECKLOAD_CONT_5:
        MOVEM.L D1-D2/A0-A1,-(SP)               | save working registers
        BSR.B   CHECKLOAD_CONT_7                | set up file position and handle for I/O
        SUBQ.L  #0x4,SP                         | allocate 4 bytes on stack for size longword
        MOVE.L  A7,D1                           | D1 = buffer address (stack temp)
        MOVEQ.L #0x4,D0                         | D0 = 4 bytes to read (resource data length)
        BSR.B   CHECKLOAD_CONT_10               | read 4-byte size from resource data fork
        MOVE.L  (SP)+,D0                        | D0 = resource data size from file
        MOVEM.L (SP)+,D1-D2/A0-A1               | restore working registers
        RTS                                     | return data size in D0

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_6
|
| Called during boot.
CHECKLOAD_CONT_6:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save working registers
        MOVE.L  D2,D0                           | D0 = resource data size
        BSR.B   CHECKLOAD_CONT_7                | set up file position and handle for I/O
        ADDQ.L  #0x4,D2                         | skip past 4-byte size prefix in data fork
        MOVE.L  (A1),D1                         | D1 = dereferenced handle (buffer address)
        BSR.B   CHECKLOAD_CONT_10               | read resource data from file into buffer
CHECKLOAD_EXIT_2:
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore working registers
        RTS                                     | return from data load

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_7
|
| Called during boot.
CHECKLOAD_CONT_7:
        ANDI.B  #0xFD,0x4(A2)                   | clear resChanged bit in ref entry attr
        MOVE.L  (A4),A0                         | dereference map handle
        MOVE.L  0x4(A2),D2                      | D2 = resAttr byte + 3-byte data offset
        AND.L   (Lo3Bytes).w,D2                 | mask to 24-bit data offset
        ADD.L   (A0),D2                         | D2 = absolute file position of resource data
        MOVE.L  0x8(A2),A1                      | A1 = resource handle
        RTS                                     | return absolute file position in D2

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_8
|
| Called during boot.
CHECKLOAD_CONT_8:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save working registers
        BSR.B   CHECKLOAD_CONT_7                | set up file pos, handle, clear changed bit
        MOVE.L  A1,A0                           | A0 = resource handle for GetHandleSize
        _GetHandleSize                          | D0 = size of resource data in memory
        TST.L   D0                              | valid size?
        BPL.B   CHECKLOAD_OK_2                  | yes - use it
        MOVEQ.L #0x0,D0                         | invalid handle - write zero size
CHECKLOAD_OK_2:
        MOVE.L  D0,-(SP)                        | push size longword as write buffer
        MOVE.L  A7,D1                           | D1 = buffer address (size on stack)
        MOVEQ.L #0x4,D0                         | D0 = 4 bytes to write (size prefix)
        BSR.B   CHECKLOAD_EMPTY_2               | write 4-byte size to data fork
        ADDQ.L  #0x4,D2                         | advance file position past size prefix
        MOVE.L  (A1),D1                         | D1 = dereferenced handle (data buffer)
        MOVE.L  (SP)+,D0                        | D0 = data size to write
        BSR.B   CHECKLOAD_EMPTY_2               | write resource data to file
        BRA.B   CHECKLOAD_EXIT_2                | restore registers and return

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_9
|
| Called during boot.
CHECKLOAD_CONT_9:
        LEA.L   -0x1A(A6),A0                    | A0 = IOParam block in local frame
        MOVE    D6,(A0)+                        | ioRefNum = file reference number
        ADDQ.W  #0x6,A0                         | skip ioPermssn/ioMisc fields
        MOVE.L  D1,(A0)+                        | ioBuffer = data buffer address
        MOVE.L  D0,(A0)+                        | ioReqCount = byte count to read/write
        ADDQ.W  #0x4,A0                         | skip ioActCount field
        MOVE    #0x1,(A0)+                      | ioPosMode = 1 (fsFromStart)
        MOVE.L  D2,(A0)+                        | ioPosOffset = file position
        LEA.L   -0x32(A6),A0                    | A0 = base of parameter block for _Read/_Write
        RTS                                     | return prepared param block in A0

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_10
|
| Called during boot.
CHECKLOAD_CONT_10:
        BSR.B   CHECKLOAD_EXIT_4                | save regs, make A2/A3 relative, swap return
        BSR.B   CHECKLOAD_CONT_9                | build IOParam block in stack frame
        _Read                                   | read data from resource file
        BRA.B   CHECKLOAD_ERR_3                 | store error code, restore ptrs, return

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_11
|
| Called during boot.
CHECKLOAD_CONT_11:
        MOVEQ.L #0x0,D2                         | write at file position 0 (start of file)
| CHECKLOAD_EMPTY_2 -- write null map at offset 256.
| Called by: CHECKLOAD_OK_2, CREATERES_CHKEOF, CMP_NEXT_RES, CMP_WRITE_MAP, CMP_FLUSH_BUF
CHECKLOAD_EMPTY_2:
        BSR.B   CHECKLOAD_EXIT_4                | save regs, make A2/A3 relative, swap return
        BSR.B   CHECKLOAD_CONT_9                | build IOParam block in stack frame
        _Write                                  | write data to resource file
CHECKLOAD_ERR_3:
        MOVE    D0,(ResErr).w                   | store I/O result in ResErr global
CHECKLOAD_EXIT_3:
        ADDA.L  (A4),A3                         | restore A3 to absolute type list ptr
        ADDA.L  (A4),A2                         | restore A2 to absolute ref entry ptr
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore registers saved by CHECKLOAD_EXIT_4
        RTS                                     | return from I/O operation

| ----------------------------------------------------------
|
| CHECKLOAD_EXIT_4
|
| Called during boot.
CHECKLOAD_EXIT_4:
        MOVEM.L D0-D1/A0,-(SP)                  | save D0/D1/A0 (will be restored by CHECKLOAD_EXIT_3)
        MOVE.L  0xC(SP),A0                      | A0 = return address of caller
        MOVE.L  A1,0xC(SP)                      | save A1 where return address was
        SUBA.L  (A4),A3                         | make A3 relative (map may move during I/O)
        SUBA.L  (A4),A2                         | make A2 relative (map may move during I/O)
        JMP     (A0)                            | return to caller (tail-call into I/O setup)

| ----------------------------------------------------------
|
| CHECKLOAD_OK_3
|
| Called during boot.
CHECKLOAD_OK_3:
        BSR.B   CHECKLOAD_EXIT_4                | save regs, make A2/A3 relative
        BSR     CHECKLOAD_OK_4                  | test if file is read-only
        BNE.B   CHECKLOAD_EXIT_3                | read-only - skip write, restore ptrs
        BSR.B   CHECKLOAD_CONT_9                | build IOParam block for map write
        BSR.B   CHECKLOAD_CONT_12               | compute new file size (data + map)
        MOVE.L  D0,0x1C(A0)                     | set ioMisc = new logical EOF position
        _SetEOF                                 | truncate/extend file to new size
        BRA.B   CHECKLOAD_ERR_3                 | store error, restore ptrs, return

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_12
|
| Called during boot.
CHECKLOAD_CONT_12:
        MOVEM.L D1/A1,-(SP)                     | save working registers
        MOVE.L  (A4),A1                         | dereference map handle
        MOVE.L  (A1)+,D0                        | D0 = data fork offset (map header+0)
        MOVE.L  (A1)+,D1                        | D1 = map offset (map header+4)
        ADD.L   (A1)+,D0                        | D0 += data fork length = end of data
        ADD.L   (A1)+,D1                        | D1 += map length = end of map
        CMP.L   D1,D0                           | which section ends later?
        BPL.B   CHECKLOAD_CONT_13               | data ends later - use D0 as file size
        MOVE.L  D1,D0                           | map ends later - use D1 as file size
CHECKLOAD_CONT_13:
        MOVEM.L (SP)+,D1/A1                     | restore registers
        RTS                                     | return file size in D0

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_14
|
| Called during boot.
CHECKLOAD_CONT_14:
        MOVE.L  0x8(A2),A0                      | A0 = resource handle from ref entry
        _GetHandleSize                          | D0 = current data size in memory
        ADDQ.L  #0x4,D0                         | add 4 for size prefix in data fork
        MOVE.L  D0,D1                           | D1 = total bytes needed on disk
        RTS                                     | return disk bytes needed in D1

| ----------------------------------------------------------
|
| CHECKLOAD_NO_3
|
| Called during boot.
CHECKLOAD_NO_3:
        MOVEM.L D1/D7/A0-A2,-(SP)               | save working registers
        MOVE.L  0x4(A2),D7                      | D7 = resAttr + data offset
        AND.L   (Lo3Bytes).w,D7                 | mask to 24-bit data offset
        MOVE.L  (A4),A0                         | dereference map handle
        MOVE.L  0x4(A0),D0                      | D0 = map offset in file
        SUB.L   (A0),D0                         | D0 = map offset - data offset = data length
        MOVE.L  D0,A1                           | A1 = total data fork length
        BMI.B   CHECKLOAD_NO_4                  | negative - invalid, recalculate
        CMPA.L  D7,A1                           | is resource offset within data fork?
        BMI.B   CHECKLOAD_NO_4                  | no - offset beyond data fork
        BSR     FINDNEXT_FROM_CUR               | find next resource's data offset
        BMI.B   CHECKLOAD_NEXT                  | no next resource - use total data length
        CMPA.L  D0,A1                           | is total data > next resource offset?
        BPL.B   CHECKLOAD_NEXT_2                | yes - use gap between resources
CHECKLOAD_NEXT:
        MOVE.L  A1,D0                           | D0 = total data fork length
        BRA.B   CHECKLOAD_CONT_15               | compute available space from total

| ----------------------------------------------------------
|
| CHECKLOAD_NO_4
|
CHECKLOAD_NO_4:
        BSR     FINDNEXT_FROM_CUR               | find next resource's data offset
        BPL.B   CHECKLOAD_NEXT_2                | found - use gap to next resource
        BSR.B   CHECKLOAD_CONT_12               | compute total file size (max of data+map)
        SUB.L   (A0),D0                         | subtract data fork base offset
CHECKLOAD_CONT_15:
        SUB.L   D7,D0                           | subtract this resource's offset = available space
        MOVEQ.L #-0x1,D7                        | D7 = -1: flag that resource has no successor
        BRA.B   CHECKLOAD_EXIT_5                | return with available space in D0

| ----------------------------------------------------------
|
| CHECKLOAD_NEXT_2
|
| Called during boot.
CHECKLOAD_NEXT_2:
        SUB.L   D7,D0                           | D0 = gap between this and next resource
CHECKLOAD_EXIT_5:
        MOVEM.L (SP)+,D1/D7/A0-A2               | restore working registers
        RTS                                     | return gap size in D0

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_16
|
| Called during boot.
CHECKLOAD_CONT_16:
        BSR.B   CHECKLOAD_CONT_14               | D1 = new disk size (data + 4-byte prefix)
        BSR.B   CHECKLOAD_NO_3                  | D0 = available space at current offset
        CMP.L   D0,D1                           | does new data fit in existing slot?
        BLE     CHECKLOAD_OK_3                  | yes - write in place, update EOF
| CHECKLOAD_CONT_17 -- write resource data at end of data fork.
CHECKLOAD_CONT_17:
        BSR.B   CHECKLOAD_CONT_14               | D1 = new disk size (data + 4-byte prefix)
        BSR.B   CHECKLOAD_CONT_12               | D0 = total file size
        MOVE.L  (A4),A0                         | dereference map handle
        SUB.L   (A0),D0                         | D0 = file size - data base = end of data area
        MOVE.B  0x4(A2),-(SP)                   | save resAttr byte (will be overwritten)
        MOVE.L  D0,0x4(A2)                      | store new 3-byte data offset in ref entry
        MOVE.B  (SP)+,0x4(A2)                   | restore resAttr byte over offset's high byte
        ADD.L   D1,D0                           | D0 = new end of data area
        MOVE.L  D0,0x8(A0)                      | update data fork length in map header
        ORI.B   #0x60,0x16(A0)                  | set mapChanged + mapCompact flags
        BRA     CHECKLOAD_OK_3                  | write resource data and update EOF

| ----------------------------------------------------------
|
| CHECKLOAD_OK_4
|
| Called during boot.
CHECKLOAD_OK_4:
        MOVE.L  (A4),A0                         | dereference map handle
        BTST    #0x7,0x16(A0)                   | test mapReadOnly flag (bit 7 of map attrs)
        RTS                                     | Z=0 if read-only, Z=1 if writable

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_18
|
| Called during boot.
CHECKLOAD_CONT_18:
        BSR     CHECKLOAD_EXIT_4                | save regs, make A2/A3 relative
        MOVE.L  D2,-(SP)                        | save D2
        MOVEQ.L #0x46,D1                        | D1 = 0x46
        ASL     #0x2,D1                         | D1 = 0x118 (280 bytes: test grow amount)
        MOVE.L  A4,A0                           | A0 = map handle
        _GetHandleSize                          | D0 = current map handle size
        MOVE.L  D0,D2                           | D2 = original map size
        ADD.L   D1,D0                           | D0 = map size + 280 (try to grow)
        _SetHandleSize                          | attempt to grow map handle (test memory)
        EXG     D0,D2                           | D0 = original size, D2 = error from grow
        _SetHandleSize                          | shrink back to original size
        MOVE    D2,D0                           | D0 = error code from grow attempt
        BMI.B   CHECKLOAD_ERR_4                 | grow failed - not enough memory
        BSR.B   CHECKLOAD_OK_4                  | test if file is read-only
        BNE.B   CHECKLOAD_ERR_4                 | read-only - cannot extend file
        MOVE.L  A1,D0                           | test resource handle (A1 from caller)
        BEQ.B   CHECKLOAD_SKIP_3                | NIL handle - skip data size calc
        MOVE.L  A1,A0                           | A0 = resource handle
        _GetHandleSize                          | D0 = resource data size
        MOVE.L  D0,D2                           | D2 = data size
        BMI.B   CHECKLOAD_ERR_4                 | invalid handle - abort
        ADD.L   D0,D1                           | D1 += data size (total growth needed)
CHECKLOAD_SKIP_3:
        BSR     CHECKLOAD_CONT_9                | build IOParam block in stack frame
        LEA.L   0x1C(A0),A1                     | A1 = pointer to ioMisc field
        _GetEOF                                 | get current file EOF into ioMisc
        MOVE.L  (A1),D2                         | D2 = current EOF position
        ADD.L   D1,(A1)                         | ioMisc = current EOF + growth amount
        _SetEOF                                 | extend file to accommodate new data
CHECKLOAD_ERR_4:
        MOVE.L  (SP)+,D2                        | restore D2
        BRA     CHECKLOAD_ERR_3                 | store error, restore ptrs, return

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_19
|
| Called during boot.
CHECKLOAD_CONT_19:
        MOVEM.L D0-D1/A0-A1,-(SP)               | save working registers
        MOVE.L  (A4),A0                         | dereference map handle
        BSR     CHECKLOAD_CONT_12               | D0 = total file size
        CMP.L   (Lo3Bytes).w,D0                 | file size >= 16MB (24-bit limit)?
        BGE.B   CHECKLOAD_ERR_5                 | yes - map corrupt, set error
        MOVE.L  A0,A1                           | A1 = map base pointer
        ADDA    0x18(A0),A1                     | A1 = type list pointer (map + typeListOff)
        MOVE    (A1)+,D0                        | D0 = numTypes - 1
        BMI.B   CHECKLOAD_SKIP_4                | no types - skip to name list check
        MOVEQ.L #0x0,D1                         | D1 = running count of ref entries
CHECKLOAD_LOOP:
        ADD     0x4(A1),D1                      | D1 += count-1 for this type
        ADDQ.W  #0x1,D1                         | D1 += 1 (adjust from count-1 to count)
        ADDQ.W  #0x8,A1                         | advance to next type entry (8 bytes)
        DBF     D0,CHECKLOAD_LOOP               | loop through all type entries
        MULU    #0xC,D1                         | D1 = total ref entries * 12 bytes each
        ADDA.L  D1,A1                           | A1 = end of ref list = start of name list
CHECKLOAD_SKIP_4:
        MOVE    0x1A(A0),D1                     | D1 = name list offset from map header
        BGT.B   CHECKLOAD_CONT_20               | positive offset - validate it
        SUBA.L  A0,A1                           | A1 = computed name list offset from map base
        MOVE.L  A1,D1                           | D1 = computed offset
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit value
        CMP.L   0xC(A0),D1                      | compare with map length (header+0xC)
        BGT.B   CHECKLOAD_ERR_5                 | computed > map length - corrupt map
        BRA.B   CHECKLOAD_OK_5                  | map is valid

| ----------------------------------------------------------
|
| CHECKLOAD_CONT_20 - validate name list offset against computed position
|
| Called during boot.
CHECKLOAD_CONT_20:
        ADDA    D1,A0                           | A0 = map base + name list offset
        CMPA.L  A1,A0                           | is declared offset >= computed end?
        BMI.B   CHECKLOAD_ERR_5                 | no - name list overlaps ref list, corrupt
CHECKLOAD_OK_5:
        MOVEQ.L #0x0,D0                         | D0 = 0: map is valid (no error)
        BRA.B   CHECKLOAD_EXIT_6                | return success

| ----------------------------------------------------------
|
| CHECKLOAD_ERR_5 - map validation failed
|
CHECKLOAD_ERR_5:
        MOVE    #-0xC7,(ResErr).w               | set ResErr = -199 (mapReadErr)
CHECKLOAD_EXIT_6:
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore working registers
        RTS                                     | return mapReadErr

| ----------------------------------------------------------
|
| _LoadResource ($A9A2)
| stack: handle -> (loads resource data)
|
| Called during boot (28,906 times in 30s trace).
LoadResource:
        MOVEM.L D0/A0,-(SP)                     | save D0/A0 (restored by epilogue LOADRESOURCE_EXIT)
        PEA.L   LOADRESOURCE_EXIT(PC)           | push cleanup routine as return address
        BSR     RESMGR_CONT_5                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  0x14(A6),A1                     | A1 = resource handle from caller's stack
        TST.L   (A1)                            | is master pointer non-NIL?
        BNE.B   LOADRESOURCE_SKIP               | yes - already loaded, nothing to do
        BSR     RESMGR_CONT_12                  | find ref entry for this handle in all maps
        BEQ.B   LOADRESOURCE_FOUND              | found - go load the data
        MOVE    #-0xC0,(ResErr).w               | resNotFound: handle not in any resource map
        BRA.B   LOADRESOURCE_SKIP               | skip to epilogue

| ----------------------------------------------------------
|
| LOADRESOURCE_FOUND - force-load resource data from file
|
| Called during boot.
LOADRESOURCE_FOUND:
        MOVE.B  (ResLoad).w,-(SP)               | save current ResLoad state
        ST.B    (ResLoad).w                     | force ResLoad = true (always load)
        BSR     P_CheckLoad                     | load resource data into handle
        MOVE.B  (SP)+,(ResLoad).w               | restore original ResLoad state
LOADRESOURCE_SKIP:
        BRA     RESMGR_EXIT_6                   | epilogue: 0 param bytes

| ----------------------------------------------------------
|
| LOADRESOURCE_EXIT - LoadResource cleanup epilogue
|
| Called during boot (28,906 times in 30s trace).
LOADRESOURCE_EXIT:
        MOVEM.L (SP)+,D0/A0                     | restore D0/A0 saved before prologue
        MOVE.L  (SP)+,(SP)                      | collapse stack: remove handle param
        RTS                                     | return from operation

| ----------------------------------------------------------
|
| _ReleaseResource ($A9A3)
| stack: handle -> (releases resource)
|
| Called during boot.
ReleaseResource:
        BSR     WRITERESOURCE_CONT_2            | prologue + find ref entry for handle
        BTST    #0x1,0x4(A2)                    | test resChanged bit in resAttr
        BNE.B   RELEASERESOURCE_SKIP_2          | changed - don't release, skip to epilogue
        MOVE.L  A1,A0                           | A0 = resource handle for DisposeHandle
        _DisposeHandle                          | free the resource data
RELEASERESOURCE_CONT:
        CMPI.L  #0x464F4E54,D3                  | is resource type 'FONT'?
        BNE.B   RELEASERESOURCE_SKIP            | no - skip font cache invalidation
        MOVE.L  (MinusOne).w,(LastSPExtra).w    | invalidate font cache (force recalc)
RELEASERESOURCE_SKIP:
        CLR.L   0x8(A2)                         | clear handle in ref entry (mark unloaded)
        CLR.L   (RMgrLastResHand).w             | invalidate last-accessed handle cache
RELEASERESOURCE_SKIP_2:
        BRA     RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| _DetachResource ($A992)
|
| Called during boot.
DetachResource:
        BSR.B   WRITERESOURCE_CONT_2            | prologue + find ref entry for handle
        BTST    #0x1,0x4(A2)                    | test resChanged bit in resAttr
        BNE.B   DETACHRESOURCE_ERR              | changed - can't detach, set error
        BCLR    #0x5,(A1)                       | clear resource flag in master pointer
        BRA.B   RELEASERESOURCE_CONT            | clear ref entry handle, invalidate cache

| ----------------------------------------------------------
|
| DETACHRESOURCE_ERR - can't detach changed resource
|
DETACHRESOURCE_ERR:
        MOVE    #-0xC6,(ResErr).w               | resAttrErr: resource attributes prevent this
        BRA.B   RELEASERESOURCE_SKIP_2          | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| _ChangedResource ($A9AA)
|
| Called during boot.
ChangedResource:
        BSR.B   WRITERESOURCE_CONT_2            | prologue + find ref entry for handle
        MOVE.B  (A1),D7                         | D7 = save master pointer flags byte
        BCLR    #0x6,(A1)                       | clear purgeable flag during write check
        BTST    #0x3,0x4(A2)                    | test resProtected attribute (bit 3)
        BNE.B   CHANGEDRESOURCE_CONT            | protected - can't mark changed
        BSR     CHECKLOAD_CONT_18               | ensure file can grow for new data
        BMI.B   CHANGEDRESOURCE_ERR             | memory/file error - abort
        BSET    #0x1,0x4(A2)                    | set resChanged bit in ref entry
        BSR     CHECKLOAD_CONT_16               | write resource data to file
        MOVE.L  (A4),A0                         | dereference map handle
        BSET    #0x5,0x16(A0)                   | set mapChanged flag in map attributes
        BRA.B   CHANGEDRESOURCE_ERR             | restore flags and return

| ----------------------------------------------------------
|
| CHANGEDRESOURCE_CONT - resource is protected, cannot mark changed
|
CHANGEDRESOURCE_CONT:
        MOVE    #-0xC6,(ResErr).w               | resAttrErr: resource is protected
CHANGEDRESOURCE_ERR:
        MOVE.B  D7,(A1)                         | restore master pointer flags byte
        BRA     RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| _WriteResource ($A9B0)
|
WriteResource:
        BSR.B   WRITERESOURCE_CONT_2            | prologue + find ref entry for handle
        BSR     CHECKLOAD_OK_4                  | test if file is read-only
        BNE.B   WRITERESOURCE_SKIP              | read-only - skip write
        BTST    #0x1,0x4(A2)                    | test resChanged bit in resAttr
        BEQ.B   WRITERESOURCE_SKIP              | not changed - nothing to write
        BSR     CHECKLOAD_CONT_8                | write resource data + size to file
WRITERESOURCE_SKIP:
        BRA     RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| WRITERESOURCE_CONT
|
| Called during boot.
WRITERESOURCE_CONT:
        MOVE.L  (MinusOne).w,0xC(SP)            | preset result to -1 (for SizeRsrc etc)
| WRITERESOURCE_CONT_2 -- prologue + find ref entry for handle.
| Called by: ReleaseResource, DetachResource, ChangedResource, WriteResource, HomeResFile
WRITERESOURCE_CONT_2:
        MOVE.L  (SP)+,D0                        | pop return address
        BSR     RESMGR_CONT_5                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  D0,-(SP)                        | push return address back
        MOVE.L  A0,D0                           | test resource handle (from caller param)
        BEQ.B   WRITERESOURCE_SKIP_2            | NIL handle - skip to epilogue
        MOVE.L  (A0),A1                         | A1 = master pointer (dereferenced handle)
        BSR     SETRESATTRS_CONT                | find ref entry for handle in all maps
        BEQ.B   WRITERESOURCE_EXIT              | found - return to caller
WRITERESOURCE_SKIP_2:
        ADDQ.W  #0x4,SP                         | discard return address (skip caller body)
        BRA     RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| WRITERESOURCE_EXIT - handle found, return to caller's operation body
|
| Called during boot.
WRITERESOURCE_EXIT:
        RTS                                     | return to operation body

| ----------------------------------------------------------
|
| _HomeResFile ($A9A4)
|
| Called during boot.
HomeResFile:
        MOVE    #-0x1,0x8(SP)                   | preset result to -1 (error case)
        BSR.B   WRITERESOURCE_CONT_2            | prologue + find ref entry for handle
        CMP     (SysMap).w,D6                   | is resource in System file?
        BNE.B   HOMERESFILE_EXIT                | no - return actual refNum
        MOVEQ.L #0x0,D6                         | System file returns refNum = 0 by convention
HOMERESFILE_EXIT:
        MOVE    D6,0xC(A6)                      | store result refNum in return value slot
        BRA     RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| HOMERESFILE_CONT
|
HOMERESFILE_CONT:
        MOVE.L  (SP)+,A1                        | A1 = return address
        MOVE.L  (SP)+,A0                        | A0 = resource handle (purge proc arg)
        BTST    #0x5,(A0)                       | test resource flag in master pointer
        BEQ.B   HOMERESFILE_SKIP                | not a resource handle - skip write
        MOVE.L  A0,-(SP)                        | push handle for WriteResource
        _WriteResource                          | auto-save changed resource before purge
HOMERESFILE_SKIP:
        JMP     (A1)                            | return to Memory Manager purge code

| ----------------------------------------------------------
|
| _SetResPurge ($A993)
|
SetResPurge:
        MOVE.L  (TheZone).w,A0                  | A0 = current heap zone header
        MOVE.L  (SP)+,D0                        | D0 = return address
        TST.B   (SP)+                           | test Boolean install parameter
        PEA.L   HOMERESFILE_CONT(PC)            | push purge-proc address as default
        BNE.B   SETRESPURGE_CONT                | true - install purge proc
        CLR.L   (SP)                            | false - remove purge proc (set to NIL)
SETRESPURGE_CONT:
        MOVE.L  (SP)+,0x28(A0)                  | store purge proc in zone header
        MOVE.L  D0,-(SP)                        | push return address back
| Called by: SetResLoad, CurResFile, ResError, AddReference, RmveReference
SETRESPURGE_EXIT:
        CLR.B   (RMgrCurOnly).w                 | reset search-current-only flag
        CLR     (ROMMapInsert).w                | reset ROM map insertion flag
        RTS                                     | return from search scope reset

| ----------------------------------------------------------
|
| _SetResLoad ($A99B)
|
| Called during boot.
SetResLoad:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.B  (SP)+,(ResLoad).w               | set ResLoad flag from Boolean parameter
        MOVE.L  A0,-(SP)                        | push return address back
        BRA.B   SETRESPURGE_EXIT                | clear RMgrCurOnly/ROMMapInsert and return

| ----------------------------------------------------------
|
| _CurResFile ($A994)
|
| Called during boot.
CurResFile:
        MOVE    (CurMap).w,0x4(SP)              | return current resource file refNum
        BRA.B   SETRESPURGE_EXIT                | clear flags and return

| ResError -- _ResError ($A9AF): FUNCTION ResError: Integer;
| ----------------------------------------------------------
|
| _ResError ($A9AF)
|
ResError:
        MOVE    (ResErr).w,0x4(SP)              | return last Resource Manager error code
        BRA.B   SETRESPURGE_EXIT                | clear flags and return

| ----------------------------------------------------------
|
| _AddReference ($A9AC)
|
AddReference:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xA,SP                         | remove 10 bytes of parameters
        MOVE.L  A0,-(SP)                        | push return address back
        MOVE    #-0xC3,(ResErr).w               | addResFailed: not implemented in ROM
        BRA.B   SETRESPURGE_EXIT                | clear flags and return

| ----------------------------------------------------------
|
| _RmveReference ($A9AE)
|
RmveReference:
        MOVE.L  (SP)+,(SP)                      | collapse stack: remove 4-byte handle param
        MOVE    #-0xC5,(ResErr).w               | rmvResFailed: not implemented in ROM
        BRA.B   SETRESPURGE_EXIT                | clear flags and return

| ----------------------------------------------------------
|
| _GetResAttrs ($A9A6)
|
| Called during boot.
GetResAttrs:
        BSR     RESMGR_CONT_5                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  (A0),A1                         | A1 = master pointer (dereference handle)
        BSR.B   SETRESATTRS_CONT                | find ref entry for this handle
        BMI.B   GETRESATTRS_SKIP                | not found - skip
        MOVE.B  0x4(A2),0xD(A6)                 | store resAttr byte in result word (low byte)
GETRESATTRS_SKIP:
        BRA     RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| _SetResAttrs ($A9A7)
|
SetResAttrs:
        BSR     RESMGR_CONT_5                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  0xA(A6),A1                      | A1 = resource handle from param
        BSR.B   SETRESATTRS_CONT                | find ref entry for this handle
        BMI.B   SETRESATTRS_SKIP                | not found - skip
        CMPA.L  (ROMMapHandle).w,A4             | is this a ROM resource?
        BEQ.B   SETRESATTRS_SKIP                | yes - ROM map is read-only, skip
        MOVE.B  0x9(A6),0x4(A2)                 | copy new resAttr byte into ref entry
        MOVE.L  (A4),A0                         | dereference map handle
        BSET    #0x5,0x16(A0)                   | set mapChanged flag in map attributes
SETRESATTRS_SKIP:
        BRA     RESMGR_EXIT_4                   | epilogue: 6 param bytes

| ----------------------------------------------------------
|
| SETRESATTRS_CONT
|
| Called during boot (4,238 times in 30s trace).
SETRESATTRS_CONT:
        BSR     RESMGR_CONT_12                  | find resource ref entry by handle in all maps
        BEQ.B   SETRESATTRS_EXIT                | found - return with Z=1
        MOVE    #-0xC0,(ResErr).w               | resNotFound: handle not in any resource map
SETRESATTRS_EXIT:
        RTS                                     | return after finding ref entry or setting error

| ----------------------------------------------------------
|
| _GetResInfo ($A9A8)
|
| Called during boot (3,620 times in 30s trace).
GetResInfo:
        BSR     RESMGR_CONT_5                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  0x14(A6),A1                     | A1 = resource handle from param
        BSR.B   SETRESATTRS_CONT                | find ref entry for this handle
        BEQ.B   GETRESINFO_EXIT                 | found - proceed to return info
        LEA.L   (MinusOne).w,A2                 | not found - A2 points to -1 (for resID)
        MOVEQ.L #0x0,D3                         | D3 = 0 (clear resource type)
GETRESINFO_EXIT:
        LEA.L   0x10(A6),A0                     | A0 = pointer to resID output param
        MOVE.L  (A0),A1                         | A1 = caller's resID pointer
        MOVE.L  A1,D0                           | test if caller provided resID pointer
        BEQ.B   GETRESINFO_EMPTY                | NIL - caller doesn't want resID
        MOVE    (A2),(A1)                       | store resource ID at caller's pointer
GETRESINFO_EMPTY:
        MOVE.L  -(A0),A1                        | A1 = caller's resType pointer
        MOVE.L  A1,D0                           | test if caller provided resType pointer
        BEQ.B   GETRESINFO_EMPTY_2              | NIL - caller doesn't want type
        MOVE.L  D3,(A1)                         | store 4-byte resource type
GETRESINFO_EMPTY_2:
        MOVE.L  -(A0),A1                        | A1 = caller's name string pointer
        MOVE.L  A1,D0                           | test if caller provided name pointer
        BEQ.B   GETRESINFO_EMPTY_3              | NIL - caller doesn't want name
        CLR.B   (A1)                            | default: empty Pascal string (length=0)
        BSR     RESMGR_CONT_16                  | get resource name string pointer into A0
        BMI.B   GETRESINFO_EMPTY_3              | no name - leave empty string
        BSR.B   GETRESINFO_CONT                 | copy Pascal string from A0 to A1
GETRESINFO_EMPTY_3:
        MOVEQ.L #0x10,D0                        | 16 bytes of parameters to clean up
        BRA     RESMGR_CONT_11                  | common epilogue

| ----------------------------------------------------------
|
| GETRESINFO_CONT
|
| Called during boot (3,597 times in 30s trace).
GETRESINFO_CONT:
        MOVEQ.L #0x0,D0                         | clear D0 for byte extension
        MOVE.B  (A0),D0                         | D0 = Pascal string length byte
        ADDQ.W  #0x1,D0                         | add 1 for length byte itself
        _BlockMove                              | copy Pascal string from A0 to A1
        RTS                                     | return from string copy

| ----------------------------------------------------------
|
| _SetResInfo ($A9A9)
|
| Called during boot.
SetResInfo:
        BSR     RESMGR_CONT_5                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  0xE(A6),A1                      | A1 = resource handle from param
        BSR.B   SETRESATTRS_CONT                | find ref entry for this handle
        BMI.B   SETRESINFO_ERR                  | not found - skip to epilogue
        BTST    #0x3,0x4(A2)                    | test resProtected attribute (bit 3)
        BNE.B   SETRESINFO_CONT                 | protected - can't change info
        MOVE.L  0x8(A6),D0                      | D0 = new name pointer (NIL = no rename)
        BEQ.B   SETRESINFO_SKIP                 | NIL - skip name change, just set ID
        SUBA.L  A1,A1                           | A1 = NIL (no resource data handle for CHECKLOAD_CONT_18)
        BSR     CHECKLOAD_CONT_18               | ensure file can grow for new name
        BMI.B   SETRESINFO_ERR                  | error - abort
        MOVE.L  D0,A0                           | A0 = new name Pascal string
        BSR     RMVERESOURCE_CONT_5             | remove old name from name list
        BSR     RMVERESOURCE_EMPTY              | add new name to name list
        BSR     CHECKLOAD_OK_3                  | write updated map to file
SETRESINFO_SKIP:
        MOVE.L  (A4),A0                         | dereference map handle
        BSET    #0x5,0x16(A0)                   | set mapChanged flag in map attributes
        MOVE    0xC(A6),(A2)                    | store new resource ID in ref entry
        BRA.B   SETRESINFO_ERR                  | skip to epilogue

| ----------------------------------------------------------
|
| SETRESINFO_CONT - resource is protected
|
SETRESINFO_CONT:
        MOVE    #-0xC6,(ResErr).w               | resAttrErr: resource is protected
SETRESINFO_ERR:
        MOVEQ.L #0xA,D0                         | 10 bytes of parameters to clean up
        BRA     RESMGR_CONT_11                  | common epilogue

| ----------------------------------------------------------
|
| _AddResource ($A9AB)
| stack: handle, type, id, name -> (adds to current file)
|
| Called during boot.
AddResource:
        BSR     RESMGR_CONT_4                   | full prologue: clear ROMMapInsert/CurOnly/ResErr
        MOVE    #-0xC2,(ResErr).w               | preset addResFailed error
        MOVE.L  0x12(A6),A1                     | A1 = handle to add as resource
        MOVE.L  A1,D0                           | test handle for NIL
        BEQ.B   ADDRESOURCE_ERR                 | NIL handle - abort
        BSR     RESMGR_CONT_12                  | check if handle already in a resource map
        BEQ.B   ADDRESOURCE_ERR                 | already a resource - can't add again
        BSR     RETURNS_21                      | find map for CurMap (current resource file)
        BSR     CHECKLOAD_CONT_18               | ensure file can grow for new resource
        BMI.B   ADDRESOURCE_ERR                 | error - abort
        MOVE.L  0xE(A6),D3                      | D3 = resource type from caller param
        BSR.B   ADDRESOURCE_CONT                | find or create type entry, make ref slot
        MOVE    0xC(A6),(A2)+                   | store resource ID in new ref entry
        MOVE    #-0x1,(A2)+                     | name offset = -1 (no name initially)
        MOVE.L  #0x2000000,(A2)+                | resAttr=0x02 (resChanged), dataOffset=0
        MOVE.L  0x12(A6),A0                     | A0 = handle being added
        BSET    #0x5,(A0)                       | set resource flag in master pointer
        MOVE.L  A0,(A2)                         | store handle in ref entry (offset 8)
        SUBQ.L  #0x8,A2                         | back up A2 to ref entry start
        MOVE.L  0x8(A6),A0                      | A0 = resource name Pascal string
        BSR     RMVERESOURCE_EMPTY              | add name to name list if non-empty
        BSR     CHECKLOAD_CONT_17               | write resource data at end of data fork
ADDRESOURCE_ERR:
        MOVEQ.L #0xE,D0                         | 14 bytes of parameters to clean up
        BRA     RESMGR_CONT_11                  | common epilogue

| ----------------------------------------------------------
|
| ADDRESOURCE_CONT
|
| Called during boot.
ADDRESOURCE_CONT:
        BSET    #0x5,0x16(A3)                   | set mapChanged flag in map attributes
        BSR     RETURNS_26                      | search type list for matching type D3
        BEQ.B   ADDRESOURCE_CONT_2              | type exists - add ref to existing type
        MOVEQ.L #0x14,D0                        | 20 bytes: 8 (type entry) + 12 (ref entry)
        BSR     RMVERESOURCE_CONT               | grow map handle by 20 bytes
        BSR     RETURNS_23                      | re-get type list after handle resize
        BMI.B   ADDRESOURCE_EMPTY               | empty list - use current position
        BSR     RETURNS_27                      | skip past existing refs to find insert point
ADDRESOURCE_EMPTY:
        MOVE.L  A2,A3                           | A3 = insertion point for new type entry
        MOVE.L  (A4),A2                         | dereference map handle
        ADDA    0x1A(A2),A2                     | A2 = name list start
        SUBA    #0x14,A2                        | back up 20 bytes (new space at end)
        MOVEQ.L #0x8,D0                         | shift 8 bytes (type entry size)
        MOVE.L  A3,A0                           | A0 = source: old position
        MOVE.L  A2,A1                           | A1 = dest: shifted position
        BSR     RMVERESOURCE_CONT_4             | block move existing data down by 8 bytes
        MOVE.L  (A4),A0                         | dereference map handle
        ADDA    0x18(A0),A0                     | A0 = type list count word
        ADDQ.W  #0x1,(A0)                       | increment number of types
        MOVE.L  D3,(A3)+                        | store new resource type in type entry
        CLR     (A3)+                           | count-1 = 0 (one resource of this type)
        SUBA.L  A0,A1                           | compute ref list offset from type list
        MOVE    A1,(A3)                         | store ref list offset in type entry
        ADDQ.L  #0x8,A2                         | A2 = new ref entry (after type entry)
        MOVE    (A0)+,D5                        | D5 = updated type count for ADDRESOURCE_LOOP loop
        BRA.B   ADDRESOURCE_LOOP                | adjust ref list offsets for existing types

| ----------------------------------------------------------
|
| ADDRESOURCE_CONT_2
|
| Called during boot.
ADDRESOURCE_CONT_2:
        MOVEQ.L #0xC,D0                         | 12 bytes: one new ref entry
        BSR     RMVERESOURCE_CONT               | grow map handle by 12 bytes
        MOVE.L  (A4),A1                         | dereference map handle
        ADDA    0x1A(A1),A1                     | A1 = name list start
        SUBA    D0,A1                           | A1 = new ref entry position (before names)
        BSR     RETURNS_26                      | re-find type entry for type D3
        MOVE.L  A2,-(SP)                        | save type entry pointer
        ADDQ.W  #0x1,0x4(A2)                    | increment count-1 for this type
        MOVEQ.L #0xC,D0                         | 12 bytes per ref entry
        MULU    0x4(A2),D0                      | D0 = count * 12 (offset to end of ref list)
        MOVE    0x6(A2),A2                      | A2 = ref list offset from type list
        ADDA.L  A3,A2                           | A2 = absolute ref list pointer
        ADDA    D0,A2                           | A2 = end of existing refs (insert point)
        MOVE.L  A2,A0                           | A0 = source for block move
        MOVEQ.L #0xC,D0                         | shift by 12 bytes (one ref entry)
        BSR     RMVERESOURCE_CONT_4             | move subsequent data down by 12 bytes
        MOVE.L  (SP)+,A0                        | restore type entry pointer
        BRA.B   ADDRESOURCE_CONT_3              | adjust ref list offsets for later types

| ----------------------------------------------------------
|
| ADDRESOURCE_LOOP - adjust ref list offsets after type/ref insertion
|
| Called during boot.
ADDRESOURCE_LOOP:
        ADD     D0,0x6(A0)                      | add insertion delta to ref list offset
ADDRESOURCE_CONT_3:
        ADDQ.W  #0x8,A0                         | advance to next type entry (8 bytes)
        DBF     D5,ADDRESOURCE_LOOP             | loop through remaining types
        RTS                                     | return after advancing type offsets

| ----------------------------------------------------------
|
| _RmveResource ($A9AD)
|
RmveResource:
        BSR     RESMGR_CONT_5                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE    #-0xC4,(ResErr).w               | preset rmvResFailed error
        MOVE.L  (A0),A1                         | A1 = master pointer (dereference handle)
        BSR     RESMGR_CONT_12                  | find ref entry for this handle
        BMI.B   RMVERESOURCE_SKIP_3             | not found - skip
        BTST    #0x3,0x4(A2)                    | test resProtected attribute (bit 3)
        BNE.B   RMVERESOURCE_SKIP_3             | protected - can't remove
        CMP     (CurMap).w,D6                   | is resource in current map?
        BNE.B   RMVERESOURCE_SKIP_3             | no - can only remove from current file
        BCLR    #0x5,(A1)                       | clear resource flag in master pointer
        MOVEQ.L #0x60,D0                        | mapChanged + mapCompact flags
        CLR.L   (RMgrLastResHand).w             | invalidate handle cache
        MOVE.L  (A4),A0                         | dereference map handle
        OR.B    D0,0x16(A0)                     | set mapChanged + mapCompact in map attrs
        BSR     RMVERESOURCE_CONT_5             | remove resource name from name list
        MOVEQ.L #-0xC,D7                        | D7 = -12 (negative ref entry size)
        MOVE.L  A2,A0                           | A0 = ref entry to remove
        SUBA    D7,A0                           | A0 = byte after ref entry (source for move)
        BSR     RETURNS_26                      | re-find type entry for this type
        MOVE.L  (A4),A1                         | dereference map handle
        ADDA    0x1A(A1),A1                     | A1 = name list (end of refs = dest limit)
        MOVE.L  D7,D0                           | D0 = -12 (shrink by one ref entry)
        BSR     RMVERESOURCE_CONT_4             | shift subsequent data up by 12 bytes
        MOVE.L  A2,A0                           | A0 = type entry for ref list offset fixup
        ADDQ.W  #0x8,A0                         | skip to next type entry
        SUBQ.W  #0x1,D5                         | decrement remaining type count
        BMI.B   RMVERESOURCE_NO                 | no more types to adjust
        BSR.B   ADDRESOURCE_LOOP                | adjust ref list offsets for later types
RMVERESOURCE_NO:
        SUBQ.W  #0x1,0x4(A2)                    | decrement count-1 for this type
        BPL.B   RMVERESOURCE_SKIP               | still has resources - keep type entry
        ADDQ.W  #0x8,A2                         | point past type entry to remove
        MOVE.L  A2,A0                           | A0 = source for shift up
        ADDA    D0,A1                           | adjust dest limit for ref list shrink
        MOVEQ.L #-0x8,D0                        | D0 = -8 (shrink by one type entry)
        ADD.L   D0,D7                           | total shrink = -20 (type + ref)
        BSR     RMVERESOURCE_CONT_4             | shift subsequent data up by 8 bytes
        MOVE.L  (A4),A0                         | dereference map handle
        ADDA    0x18(A0),A0                     | A0 = type list count word
        SUBQ.W  #0x1,(A0)                       | decrement number of types
        MOVE    (A0)+,D5                        | D5 = updated type count
        BMI.B   RMVERESOURCE_SKIP               | no types left - skip offset fixup
        BSR     ADDRESOURCE_LOOP                | adjust ref list offsets for remaining types
RMVERESOURCE_SKIP:
        MOVE.L  D7,D0                           | D0 = total bytes removed (negative)
        BSR.B   RMVERESOURCE_CONT               | shrink map handle and adjust name offset
        CMPI    #0x1,D6                         | is this the ROM map (refNum=1)?
        BEQ.B   RMVERESOURCE_SKIP_2             | yes - don't write ROM map to disk
        BSR     CHECKLOAD_OK_3                  | write updated map to file, set EOF
RMVERESOURCE_SKIP_2:
        CLR     (ResErr).w                      | clear error: remove succeeded
RMVERESOURCE_SKIP_3:
        CLR.L   (RMgrLastResHand).w             | invalidate handle cache
        BRA     RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| RMVERESOURCE_EMPTY
|
| Called during boot.
RMVERESOURCE_EMPTY:
        CLR.L   (RMgrLastResHand).w             | invalidate handle cache
        MOVEM.L D0-D2/A0-A1,-(SP)               | save working registers
        MOVEQ.L #-0x1,D2                        | D2 = -1 (no name offset, default)
        TST.B   (A0)                            | is name string empty (length=0)?
        BEQ.B   RMVERESOURCE_OK                 | yes - store -1 as name offset
        MOVE.L  (A4),A1                         | dereference map handle
        MOVE.L  0xC(A1),D1                      | D1 = map size (from map header)
        MOVE.L  D1,D2                           | D2 = current map size (= append position)
        MOVEQ.L #0x0,D0                         | clear D0 for byte extension
        MOVE.B  (A0),D0                         | D0 = name string length
        ADDQ.L  #0x1,D0                         | add 1 for length byte
        BSR.B   RMVERESOURCE_CONT_3             | grow map handle by name string size
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.L  (A4),A1                         | re-dereference map (may have moved)
        MOVE    0x1A(A1),D0                     | D0 = name list offset from map header
        SUB.L   D0,D2                           | D2 = name offset relative to name list
        ADDA.L  D1,A1                           | A1 = old end of map = dest for name copy
        BSR     GETRESINFO_CONT                 | copy Pascal name string from A0 to A1
RMVERESOURCE_OK:
        MOVE    D2,0x2(A2)                      | store name offset in ref entry (or -1)
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore working registers
        RTS                                     | return after copying name

| ----------------------------------------------------------
|
| RMVERESOURCE_CONT
|
| Called during boot.
RMVERESOURCE_CONT:
        MOVEM.L D0-D1/D7/A0-A1,-(SP)            | save working registers
        MOVE.L  (A4),A0                         | dereference map handle
        MOVE.L  0xC(A0),D1                      | D1 = current map size
        TST.L   D0                              | growing (positive) or shrinking (negative)?
        BMI.B   RMVERESOURCE_CONT_2             | shrinking - resize after move
        BSR.B   RMVERESOURCE_CONT_3             | grow map handle first
        MOVE.L  (A4),A0                         | re-dereference after resize
RMVERESOURCE_CONT_2:
        MOVE.L  A0,A1                           | A1 = map base for name list calc
        MOVEQ.L #0x0,D7                         | clear D7 for word extension
        MOVE    0x1A(A0),D7                     | D7 = current name list offset
        ADDA.L  D7,A0                           | A0 = name list source position
        ADD     D0,0x1A(A1)                     | adjust name list offset by D0 bytes
        ADDA.L  D1,A1                           | A1 = end of map (dest for block move)
        BSR.B   RMVERESOURCE_CONT_4             | shift name list by D0 bytes
        TST.L   D0                              | was this a shrink operation?
        BPL.B   RMVERESOURCE_DONE               | no - already resized, done
        BSR.B   RMVERESOURCE_CONT_3             | shrink map handle after moving data
RMVERESOURCE_DONE:
        MOVEM.L (SP)+,D0-D1/D7/A0-A1            | restore working registers
        RTS                                     | return from map resize

| ----------------------------------------------------------
|
| RMVERESOURCE_CONT_3
|
| Called during boot.
RMVERESOURCE_CONT_3:
        BSR     CHECKLOAD_EXIT_4                | save regs, make A2/A3 relative
        MOVE.L  (A4),A0                         | dereference map handle
        ADD.L   0xC(A0),D0                      | D0 = new map size (old + delta)
        MOVE.L  D0,0xC(A0)                      | update map size in map header
        MOVE.L  A4,A0                           | A0 = map handle for SetHandleSize
        _SetHandleSize                          | resize map handle to new size
        BRA     CHECKLOAD_EXIT_3                | restore A2/A3 and return

| ----------------------------------------------------------
|
| RMVERESOURCE_CONT_4
|
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

| ----------------------------------------------------------
|
| RMVERESOURCE_CONT_5
|
| Called during boot.
RMVERESOURCE_CONT_5:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save working registers
        MOVE    0x2(A2),D2                      | D2 = name offset from name list
        BMI.B   RMVERESOURCE_SKIP_4             | -1 means no name - skip removal
        MOVE.L  (A4),A0                         | dereference map handle
        MOVE.L  A0,A1                           | A1 = map base (for end calc)
        MOVEQ.L #0x0,D0                         | clear D0 for word extension
        MOVE    0x1A(A0),D0                     | D0 = name list offset from map base
        ADDA.L  D0,A0                           | A0 = name list base
        ADDA    D2,A0                           | A0 = this resource's name string
        ADDA.L  0xC(A1),A1                      | A1 = end of map (map base + map size)
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE.B  (A0),D0                         | D0 = name string length byte
        ADDQ.L  #0x1,D0                         | add 1 for length byte itself
        ADDA.L  D0,A0                           | A0 = byte after name string (source for move)
        NEG.L   D0                              | D0 = -(name size) (negative for shrink)
        MOVE.L  D0,D1                           | D1 = negative delta for offset fixup
        BSR.B   RMVERESOURCE_CONT_4             | shift data after name up (remove name)
        BSR.B   RMVERESOURCE_CONT_3             | shrink map handle by name size
        MOVEM.L D3-D5/A2-A3,-(SP)               | save registers for ref list scan
        BSR     RESMGR_CONT_3                   | count all ref entries into D4
RMVERESOURCE_LOOP:
        CMP     0x2(A2),D2                      | is this ref's name offset after removed name?
        BGE.B   RMVERESOURCE_NO_2               | no - leave offset unchanged
        ADD     D1,0x2(A2)                      | yes - adjust name offset by removal delta
RMVERESOURCE_NO_2:
        ADDA    #0xC,A2                         | advance to next ref entry (12 bytes)
        DBF     D4,RMVERESOURCE_LOOP            | loop through all ref entries
        MOVEM.L (SP)+,D3-D5/A2-A3               | restore registers
RMVERESOURCE_SKIP_4:
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore outer working registers
        MOVE    (MinusOne).w,0x2(A2)            | set name offset to -1 (no name)
        RTS                                     | return after clearing name offset

| ----------------------------------------------------------
|
| Size Rsrc
|
| Called during boot.
SizeRsrc:
        BSR     WRITERESOURCE_CONT              | prologue + find ref entry, preset result=-1
        TST.L   (A1)                            | is resource data loaded in memory?
        BEQ.B   SIZERSRC_NO                     | no - read size from file
        MOVE.L  A1,A0                           | A0 = resource handle
        _GetHandleSize                          | D0 = size of resource data in memory
        BRA.B   SIZERSRC_EXIT                   | store result and return

| ----------------------------------------------------------
|
| SIZERSRC_NO - resource not loaded: read size from data fork
|
| Called during boot.
SIZERSRC_NO:
        MOVE.B  0x4(A2),-(SP)                   | save resAttr byte (CHECKLOAD_CONT_5 modifies it)
        BSR     CHECKLOAD_CONT_5                | read 4-byte size prefix from data fork
        MOVE.B  (SP)+,0x4(A2)                   | restore resAttr byte
SIZERSRC_EXIT:
        MOVE.L  D0,0xC(A6)                      | store size result in return value slot
        BRA     RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| Op Color
|
OpColor:
        BSR     WRITERESOURCE_CONT              | prologue + find ref entry, preset result=-1
        TST.L   (A1)                            | is resource data loaded?
        BNE.B   OPCOLOR_OK                      | yes - get handle size
        BSR     CHECKLOAD_NO_3                  | not loaded - compute max size from data fork
        BRA.B   OPCOLOR_CONT                    | store result

| ----------------------------------------------------------
|
| OPCOLOR_OK - resource loaded: return actual handle size
|
OPCOLOR_OK:
        MOVE.L  A1,A0                           | A0 = resource handle
        _GetHandleSize                          | D0 = handle size
OPCOLOR_CONT:
        BRA.B   SIZERSRC_EXIT                   | store result in return value

| ----------------------------------------------------------
|
| _RsrcMapEntry ($A9C5)
|
RsrcMapEntry:
        BSR     WRITERESOURCE_CONT              | prologue + find ref entry, preset result=-1
        MOVE.L  A2,D0                           | D0 = absolute ref entry address
        SUB.L   (A4),D0                         | subtract map base = relative offset
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit offset
        BRA.B   SIZERSRC_EXIT                   | store offset as result
