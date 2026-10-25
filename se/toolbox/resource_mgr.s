| Resource Manager
|
| Apple source: ResourceMgr.a (MacSEROM.lst module RMGR). In ROM order:
| InitResources, SuperLoad, NewMap,
| CLOSEDIALOG_LOOP; the file calls (CreateResFile, OpenResFile, OpenRFPerm,
| UseResFile, Get/SetResFileAttrs, UpdateResFile with the compaction
| CmpFrm, CloseResFile); the search calls (Count1Resources/CountResources,
| Get1IxResource/GetIndResource, Count1Types/CountTypes,
| Get1IxType/GetIndType, Unique1ID/UniqueID, Get1Resource/GetResource,
| Get1NamedResource/GetNamedResource); and the resource calls
| (CheckLoad, LoadResource, TE_APPLY_JUST_MEASURE, BTREC_GRGETNODE,
| ChangedResource, WriteResource, HomeResFile, SetResPurge, SetResLoad,
| CurResFile, ResError, Get/SetResAttrs, Get/SetResInfo, AddResource,
| RmveResource, SizeRsrc, MaxSizeRsrc, RsrcMapEntry). The ROM itself has a
| resource map (resources/res_map.s) that is searched after the System
| file when ROMMapInsert is set.
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
|
| The "1" variants and the resource map layout:
|
| The "1" variants (Count1Resources, Get1IxResource (Pascal:
| Get1IndResource), Count1Types, Get1IxType (Get1IndType), Unique1ID,
| Get1Resource, Get1NamedResource; Mac Plus additions, Inside Macintosh
| IV) search only the current resource file: each is one ST.B
| (RMgrCurOnly).w that falls into the general routine. The general
| routines enter through RESMGR_CONT_6, which leaves RMgrCurOnly alone;
| with it set, the map walk starts at CurMap (RETURNS_20 -> RETURNS_21)
| and ends after that one map (RETURNS_22). The common trap epilogue
| (RESMGR_SKIP_4) clears it again.
|
| There are no equates for the resource map and reference entry fields,
| so they are written as hex offsets (names from Apple's
| ResourceMgrPriv.a, System 7.1). Map: +$0 resDataOffset, +$4
| resMapOffset, +$8 dataSize, +$C mapSize (copy of the file header),
| +$10 mNext (next map handle), +$14 mRefNum, +$16 mAttr (attributes),
| +$18 mTypes (type list offset), +$1A mNames (name list offset).
| Reference entry (12 bytes): +$0 rID, +$2 rNameOff, +$4 rAttr (byte) /
| rLocn (long: attributes in the high byte, data offset), +$8 rHndl.

| ==========================================================
| Resource Manager begins here: Apple module RMGR (MacSEROM.lst also
| lists CMGREND, the end of the Control Manager module, at this offset).
| Block below is the system 'STR ' resource for default DA/desk-accessory
| names and other tightly-packed initialization data; treat as opaque.
| ==========================================================
RMGR:
    .long       0x00000100                      | system resource init data
    .long       0x00000100                      |
    .long       0x00000000                      |
    .long       0x0000001E                      |
    .long       0x00000000                      |
    .long       0x00000000                      |
    .long       0x001C001E                      |
    .long       0xFFFF0000                      |
    .short      0x0001                          |
| ----------------------------------------------------------
|
| _InitResources ($A995): initialize the Resource Manager.
| Pascal: function InitResources: INTEGER;
| Sets up the ROM resource map (TopMapHndl/SysMapHndl), then opens the
| system file's resource fork as the SysMap.
INITRESOURCES:
    CLR.L       (RMgrLastResHand).W             | clear last-handle cache
    BSR.W       RESMGR_CONT_4                   | check resource manager state
    TST.L       (TopMapHndl).W                  | already initialized?
    BGT.B       INITRESOURCES_SKIP              | yes -> just open system file
    CLR.L       (ResErrProc).W                  | no error proc installed
    BSR.B       INITRESOURCES_CONT_2            | set up ROM resource zone
    MOVE.L      A0,(TopMapHndl).W               | TopMapHndl = ROM map
    MOVE.L      A0,(SysMapHndl).W               | SysMapHndl = ROM map
    MOVE.L      (OneOne).W,(SysMap).W           | SysMap = $00010001 (refnum 1)
    BSR.W       INITRESOURCES_CONT_3            | populate map from ROM
    CLR.L       0x10(A1)                        | next-map link = nil (end of chain)
    BRA.B       INITRESOURCES_SKIP_2            | -> open System file
| Already initialized (or re-init): try to open System file's resource fork.
| Called during boot.
INITRESOURCES_SKIP:
    LEA.L       (TheZone).W,A3                  | A3 = &TheZone
    MOVE.L      (A3),-(A7)                      | save current zone
    MOVE.L      (SysZone).W,(A3)                | TheZone = SysZone (allocate in system zone)
    LEA.L       (SysResName).W,A1               | A1 = "System" filename
    BSR.W       P_NewMap                        | open resource fork -> A4 = map handle, D0 = refNum
    MOVE.L      (A7)+,(A3)                      | restore TheZone
    MOVE.W      D6,0x8(A6)                      | save D6 for later (refNum echo)
    TST.L       D0                              | open succeeded?
    BLE.B       INITRESOURCES_SKIP_2            | no (errno or 0) -> exit
    MOVE.L      A4,(TopMapHndl).W               | TopMapHndl = System map
    MOVE.L      A4,(SysMapHndl).W               | SysMapHndl = System map
    MOVE.W      D6,(CurMap).W                   | CurMap = System refNum
    MOVE.W      D6,(SysMap).W                   | SysMap = System refNum
    BSR.W       INITRESOURCES_CONT_4            | preload all resources flagged for it
    BSR.W       INITRESOURCES_CONT_3            | also bring in ROM map
    MOVE.L      (SysMapHndl).W,0x10(A1)         | ROM map's next = SysMap
    MOVEA.L     (SysMapHndl).W,A1               | A1 = SysMap handle
    MOVEA.L     (A1),A1                         | deref
    CLR.L       0x10(A1)                        | SysMap's next = nil
    BSR.B       INITRESOURCES_CONT              | run 'ROvr' (resource override) init code
INITRESOURCES_SKIP_2:
    BRA.W       RESMGR_EXIT_6                   | -> common ResMgr exit
| ----------------------------------------------------------
|
| Run 'ROvr' (Resource Override) #0 if present in System file.
| Allows the System file to patch ROM resources at startup.
| Called during boot.
INITRESOURCES_CONT:
    SUBQ.W      #0x4,A7                         | _GetResource result slot
    MOVE.L      #0x524F7672,-(A7)               | push 'ROvr' resType
    CLR.W       -(A7)                           | resID = 0
    _GetResource                                | -> handle
    MOVE.L      (A7)+,D0                        | D0 = handle
    BEQ.B       INITRESOURCES_SKIP_3            | not present -> done
    MOVEA.L     D0,A0                           | A0 = handle
    MOVEA.L     (A0),A0                         | A0 = code ptr
    JSR         (A0)                            | execute override code
INITRESOURCES_SKIP_3:
    RTS                                         | return from INITRESOURCES_CONT
| ----------------------------------------------------------
|
| Set up the ROM resource zone and load the ROM resource map.
| ROMBase + 0x1A points to a small header: numTypes, mapSize, mapData...
| Allocates a private system pointer for the ROM zone, initializes it,
| then allocates space for the ROM map handle.
INITRESOURCES_CONT_2:
    MOVEA.L     (ROMBase).W,A0                  | A0 = ROM base
    ADDA.L      0x1A(A0),A0                     | A0 = ROM resource header
    MOVEA.L     A0,A2                           | A2 = saved header ptr
    MOVEQ.L     #0x1C,D0                        | base zone size = 28 bytes
    ADD.W       (A0)+,D0                        | + numEntries
    ASL.L       #0x2,D0                         | * 4 (each entry = 4 bytes)
    ADD.W       (A0)+,D0                        | + mapDataSize
    MOVEA.L     D0,A1                           | A1 = total size for zone
    _NewPtrSys                                  | allocate sys-zone pointer
    MOVE.L      (TheZone).W,-(A7)               | save current zone
    CLR.L       -(A7)                           | grow-zone proc = nil
    MOVE.W      #0x4,-(A7)                      | numMasterPtrs = 4
    ADDA.L      A0,A1                           | A1 = end of zone
    MOVE.L      A1,-(A7)                        | push limitPtr
    MOVE.L      A0,-(A7)                        | push startPtr
    MOVEA.L     A0,A1                           | A1 = zone ptr
    MOVEA.L     A7,A0                           | A0 = ptr to args (zone params)
    _InitZone                                   | initialize the ROM zone
    BSET        #0x0,0x16(A1)                   | set zone.heapType bit 0 (locked)
    MOVE.L      A1,(TheZone).W                  | switch to ROM zone for next allocs
    ADDA.W      #0xE,A7                         | discard InitZone args (14 bytes)
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A2)+,D0                        | D0 = numEntries
    ASL.L       #0x2,D0                         | size = numEntries * 4
    _NewPtr                                     | allocate (used by ROM map?)
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVE.W      (A2)+,D0                        | D0 = mapSize
    _NewHandle                                  | allocate ROM map handle
    _HLock                                      | lock it
    MOVE.L      A0,(ROMMapHandle).W             | save ROM map handle
    MOVE.L      (A7)+,(TheZone).W               | restore caller's zone
    RTS                                         | return from INITRESOURCES_CONT_2
| ----------------------------------------------------------
|
| Populate ROM map handle from ROM data + register all ROM resources.
| Reads numEntries (D1) and mapDataSize (D2) from ROM header,
| BlockMoves the map data into ROMMapHandle, sets refNum = 1, then
| walks the type list calling RESMGR_OK_4 to register each resource.
| Called during boot.
INITRESOURCES_CONT_3:
    MOVEA.L     (ROMBase).W,A2                  | A2 = ROM base
    ADDA.L      0x1A(A2),A2                     | A2 = ROM resource header
    MOVE.W      (A2)+,D1                        | D1 = numEntries (skip)
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.W      (A2)+,D2                        | D2 = mapDataSize
    MOVE.L      D2,D0                           | D0 = size
    MOVEA.L     (ROMMapHandle).W,A0             | A0 = ROM map handle
    MOVEA.L     A0,A4                           | A4 = saved handle
    _SetHandleSize                              | grow to mapDataSize
    MOVE.L      D2,D0                           | D0 = size again
    MOVEA.L     (A4),A1                         | A1 = deref handle (dest)
    MOVEA.L     A2,A0                           | A0 = ROM map data (src)
    _BlockMove                                  | copy map data
    MOVE.W      #0x1,0x14(A1)                   | refNum = 1 (ROM map)
    BSR.W       RESMGR_CONT_3                   | walk type list -> A2, D4
INITRESOURCES_LOOP:
    MOVE.B      0x4(A2),D1                      | D1 = type-attr byte (preload flag etc)
    BSR.W       RESMGR_OK_4                     | register this entry
    ADDA.W      #0xC,A2                         | next entry (12 bytes)
    DBF.W       D4,INITRESOURCES_LOOP           | loop over all entries
    RTS                                         | return from INITRESOURCES_CONT_3
| ----------------------------------------------------------
|
| Preload all "preload" resources from the open resource map.
| INITRESOURCES_CONT_4 sets ResLoad = true; INITRES_LOADALL is the inner entry that runs:
|   1. Walk the map's type list, zeroing reference master-ptr slots
|   2. If ResLoad is true: SuperLoad each resource flagged for preload,
|      then CheckLoad each resource currently with a non-nil master.
INITRESOURCES_CONT_4:
    ST.B        (ResLoad).W                     | force ResLoad = true
INITRES_LOADALL:
    BSR.W       RESMGR_CONT                     | get current map context
    BMI.B       INITRESOURCES_ERR               | error -> exit
    BSR.W       RESMGR_CONT_3                   | walk type list -> A2, D4
    BMI.B       INITRESOURCES_ERR               | error -> exit
INITRESOURCES_LOOP_2:
    ADDQ.W      #0x8,A2                         | skip type+attr+count
    CLR.L       (A2)+                           | zero master-ptr slot
    DBF.W       D4,INITRESOURCES_LOOP_2         | loop over all types
    TST.B       (ResLoad).W                     | preload enabled?
    BEQ.B       INITRESOURCES_ERR               | no -> exit
    BSR.B       P_SuperLoad                     | bulk-load all preload-flagged
    BEQ.B       INITRESOURCES_ERR               | exit on error
    MOVEQ.L     #0x2,D1                         | search-mode 2 (current map only)
    BSR.W       FINDNEXT_FROM_START             | start at first resource
    BMI.B       INITRESOURCES_ERR               | none -> exit
INITRES_LOADALL_LOOP:
    BSR.W       P_CheckLoad                     | check & load this resource
    MOVEQ.L     #0x2,D1                         | search mode 2
    BSR.W       FINDNEXT_CUR_OFS                | next resource
    BEQ.B       INITRES_LOADALL_LOOP            | found -> continue
| Called by: INITRESOURCES_LOOP_2, INITRES_LOADALL
INITRESOURCES_ERR:
    RTS                                         | return from INITRESOURCES_CONT_4/INITRES_LOADALL
| ----------------------------------------------------------
|
| P_SuperLoad: indirect dispatch to the SuperLoad routine via low-mem $7E4.
| Default is VSUPERLOAD; can be patched.
| Called during boot.
P_SuperLoad:
    MOVEA.L     (0x7E4).W,A0                    | A0 = VSUPERLOAD vector
    JMP         (A0)                            | tail-call to current implementation
| ----------------------------------------------------------
|
| VSUPERLOAD: bulk-load all preload-flagged resources from one map.
| Walks the type list, allocating handles or pointers (sysHeap if attr bit 6
| set) for each entry that the resource map says to preload at startup.
| Uses a single _NewHandle of total size + per-resource fixups for speed.
VSUPERLOAD:
    BSR.W       SUPERLOAD_CONT_3                | compute total preload size + alloc temp buffer
    BMI.W       RESMGR_ERR                      | failed -> error
    BSR.W       RETURNS_24                      | walk reference list -> A2 = first ref
    MOVEA.L     (A4),A1                         | A1 = deref map handle
SUPERLOAD_NEXT:
    MOVE.L      0x4(A2),D0                      | D0 = ref's offset+attrs
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit offset
    CMP.L       (RMgrHiVars_LastResType).W,D0   | beyond preload set?
    BGE.B       SUPERLOAD_NEXT_TAIL             | yes -> next type
    MOVE.L      (TheZone).W,-(A7)               | save current zone
    BTST        #0x6,0x4(A2)                    | sysheap flag set?
    BEQ.B       SUPERLOAD_NO                    | no -> use current zone
    MOVE.L      (SysZone).W,(TheZone).W         | yes -> allocate from SysZone
SUPERLOAD_NO:
    MOVE.L      0x4(A2),D2                      | D2 = ref offset (for SUPERLOAD_RETRY)
    AND.L       (Lo3Bytes).W,D2                 | mask to 24-bit
    BSR.B       SUPERLOAD_RETRY                 | read 4-byte data length
    BTST        #0x4,0x4(A2)                    | nonrelocatable flag (use _NewPtr)?
    SUBA.L      (A4),A2                         | A2 -> offset (handle may move)
    SUBA.L      (A4),A3                         | A3 -> offset (handle may move)
    BEQ.B       SUPERLOAD_NO_2                  | no -> alloc handle path
    _NewPtr                                     | alloc fixed-pointer for resource data
    BMI.B       SUPERLOAD_ERR                   | OOM -> error
    MOVEA.L     A0,A1                           | A1 = ptr
    _NewEmptyHandle                             | alloc empty handle to reference it
    MOVE.L      A0,D1                           | D1 = handle
    MOVE.L      A1,(A0)                         | handle.master = ptr
    MOVE.L      A0,D0                           | D0 = handle
    SUB.L       -(A1),D0                        | adjust block header
    BSET        #0x7,-0x4(A1)                   | mark block as locked (master flags)
    BCLR        #0x6,-0x4(A1)                   | clear purgeable bit
    MOVE.L      D0,(A1)+                        | back-link to handle
    BRA.B       SUPERLOAD_CONT                  | -> read data + register
| Standard relocatable handle path.
SUPERLOAD_NO_2:
    _NewHandle                                  | alloc handle for resource data
    BMI.B       SUPERLOAD_ERR                   | OOM -> error path
    MOVE.L      A0,D1                           | D1 = handle
    MOVEA.L     (A0),A1                         | A1 = deref (data buffer)
| Common: read resource data into A1 buffer, register handle in map.
SUPERLOAD_CONT:
    BSR.B       SUPERLOAD_RETRY                 | re-fetch data length and offset
    _BlockMove                                  | copy data from preloaded buffer
    ADDA.L      (A4),A2                         | A2 -> ref entry (deref'd)
    ADDA.L      (A4),A3                         | A3 -> next ref
    MOVE.L      D1,0x8(A2)                      | ref.handle = D1
    MOVEA.L     D1,A0                           | A0 = handle
    MOVE.B      0x4(A2),D1                      | D1 = attribute flags
    BSR.W       CHECKLOAD_CONT_3                | apply attribute bits to block header
    MOVE.L      (A7)+,(TheZone).W               | restore zone
SUPERLOAD_NEXT_TAIL:
    BSR.W       RETURNS_28                      | next ref entry -> A2
    BPL.B       SUPERLOAD_NEXT                  | not at end -> loop
    MOVEA.L     D7,A0                           | A0 = preload buffer
    _DisposeHandle                              | free temp buffer
    MOVEQ.L     #0x0,D0                         | success
    RTS                                         | return from VSUPERLOAD
| Error path: free temp buffer and propagate error.
SUPERLOAD_ERR:
    MOVE.L      (A7)+,(TheZone).W               | restore zone
    MOVEA.L     D7,A0                           | A0 = temp buffer
    _DisposeHandle                              | free
    BRA.W       RESMGR_ERR                      | -> error
| SUPERLOAD_RETRY -- get resource data offset and size from map.
| ----------------------------------------------------------
|
| SUPERLOAD_RETRY
|
| Read the 4-byte big-endian data length at offset D2 in temp buffer.
| Returns: D0 = data length, A0 = ptr to byte after the length field.
SUPERLOAD_RETRY:
    MOVEA.L     D7,A0                           | A0 = preload buffer handle
    MOVEA.L     (A0),A0                         | deref to data
    ADDA.L      D2,A0                           | + offset to resource data
| 4-byte big-endian read into D0 (byte-by-byte; portable across alignment).
SUPERLOAD_CONT_2:
    MOVE.B      (A0)+,D0                        | byte 0 -> D0 low byte
    LSL.W       #0x8,D0                         | shift to D0 high byte
    MOVE.B      (A0)+,D0                        | byte 1 -> D0 low byte
    SWAP.W      D0                              | move bytes 0..1 to D0 high word
    MOVE.B      (A0)+,D0                        | byte 2 -> D0 low byte
    LSL.W       #0x8,D0                         | shift
    MOVE.B      (A0)+,D0                        | byte 3 -> D0 low byte
    RTS                                         | D0 = (b0,b1,b2,b3) big-endian long
| ----------------------------------------------------------
|
| SUPERLOAD_CONT_3 -- size up the preload temp buffer.
|
| Computes how much heap space is available between HeapEnd and the
| top-of-heap ceiling (min(SP-MinStack, ApplLimit)). Then tries three
| candidate "preload total" sizes cached at $B90/$B8C/$B88; any that
| fits in available space is used to allocate a temporary buffer that
| VSUPERLOAD reads the entire preload payload into in a single _Read.
| Returns: A0 = handle to temp buffer (locked), D0 >= 0 on success.
SUPERLOAD_CONT_3:
    TST.L       (RMgrHiVars_LastResType).W      | preload metadata cached?
    BEQ.B       SUPERLOAD_ERR_2                 | no -> error exit
    MOVEQ.L     #0x0,D7                         | D7 = available space (init)
    MOVE.L      A7,D0                           | D0 = current stack pointer
    _StripAddress                               | strip address bits 24-31
    SUB.L       (MinStack).W,D0                 | D0 = SP - minimum stack reserve
    CMP.L       (ApplLimit).W,D0                | smaller than ApplLimit?
    BCS.B       SUPERLOAD_OK                    | yes -> use D0 as ceiling
    MOVE.L      (ApplLimit).W,D0                | else clamp to ApplLimit
SUPERLOAD_OK:
    SUB.L       (HeapEnd).W,D0                  | D0 = ceiling - heap top
    BLE.B       SUPERLOAD_SKIP_2                | no headroom -> skip
    CMPI.L      #0xC,D0                         | at least 12 bytes free?
    BLS.B       SUPERLOAD_SKIP_2                | no -> skip
    MOVE.L      D0,D7                           | D7 = headroom above HeapEnd
SUPERLOAD_SKIP_2:
    _MaxBlock                                   | D0 = largest free block in zone
    CMP.L       D7,D0                           | bigger than headroom?
    BLE.B       SUPERLOAD_CAP_OK                | no -> keep headroom
    MOVE.L      D0,D7                           | yes -> use MaxBlock
SUPERLOAD_CAP_OK:
    MOVE.L      (0xB90).W,D0                    | try cached preload total #3
    BSR.B       SUPERLOAD_CONT_5                | fits in D7?
    BPL.B       SUPERLOAD_CONT_4                | yes -> allocate
    MOVE.L      (0xB8C).W,D0                    | try cached preload total #2
    BSR.B       SUPERLOAD_CONT_5                | fits in D7?
    BPL.B       SUPERLOAD_CONT_4                | yes -> allocate
    MOVE.L      (0xB88).W,D0                    | try cached preload total #1
    BSR.B       SUPERLOAD_CONT_5                | fits in D7?
    BMI.B       SUPERLOAD_ERR_2                 | no -> give up
SUPERLOAD_CONT_4:
    _NewHandle                                  | probe-allocate (D0 = chosen size)
    BMI.B       SUPERLOAD_ERR_2                 | failed -> error
    _DisposeHandle                              | release probe (zone now compacted)
    MOVE.L      D1,D0                           | D0 = preload data length
    _NewHandle                                  | allocate real preload buffer
    BMI.B       SUPERLOAD_ERR_2                 | OOM -> error
    MOVE.L      D1,D0                           | D0 = preload data length
    MOVE.L      A0,D7                           | D7 = preload buffer handle
    MOVE.L      (A0),D1                         | D1 = deref'd buffer ptr
    MOVEA.L     (A4),A0                         | A0 = deref'd map handle
    MOVE.L      (A0),D2                         | D2 = data fork base offset
    BSR.W       CHECKLOAD_CONT_10               | _Read preload chunk into buffer
    BEQ.B       SUPERLOAD_OK_2                  | success -> return D7 = handle
    MOVEA.L     D7,A0                           | read failed -> dispose buffer
    _DisposeHandle                              | free temp buffer
SUPERLOAD_ERR_2:
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (error)
SUPERLOAD_OK_2:
    RTS                                         | return from SUPERLOAD_CONT_3
| ----------------------------------------------------------
|
| SUPERLOAD_CONT_5 -- test whether a candidate preload size fits in D7.
|
| Stores D0 -> (RMgrHiVars_LastResType) so VSUPERLOAD's loop can use
| it as the "preload-end offset" sentinel (compared against ref offsets).
| Returns CCR set by CMP.L (D7 vs total) so caller's BPL = fits.
SUPERLOAD_CONT_5:
    MOVE.L      D0,(RMgrHiVars_LastResType).W   | save candidate as preload-end offset
    BEQ.W       RESMGR_ERR                      | zero -> abort with map error
    BMI.B       SUPERLOAD_EXIT                  | negative -> stale CCR, no-fit
    MOVE.L      D0,D1                           | D1 = ref count from map header
    ADD.L       D0,D0                           | D0 = 2 * count (rough size estimate)
    MOVEA.L     (A4),A0                         | A0 = deref map handle
    ADD.L       0xC(A0),D0                      | D0 += map data length (total bytes)
    CMP.L       D0,D7                           | D7 (free) >= D0 (needed)?
SUPERLOAD_EXIT:
    RTS                                         | CCR: BPL = fits
| ----------------------------------------------------------
|
| P_NewMap -- jump-vectored entry to the NewMap routine.
|
| Indirects through the patchable jNewMap vector at $7EC. Default
| points to VNEWMAP below.
| Called during boot.
P_NewMap:
    MOVEA.L     (0x7EC).W,A0                    | A0 = jNewMap dispatch vector
    JMP         (A0)                            | tail-call current implementation
| ----------------------------------------------------------
|
| VNEWMAP -- create a new in-memory resource map for an open file.
|
| Allocates a 36-byte map header, opens the resource fork, reads the
| map header from disk, expands the handle to fit the entire map, then
| reads the map data. On success returns A4 = map handle, D6 = refnum,
| D0 = 1 (ROM map needs linking). On failure D6 = D0 = -1.
VNEWMAP:
    CLR.L       (RMgrHiVars_LastResType).W      | clear last-type cache
    CLR.L       (RMgrLastResHand).W             | clear last-handle cache
    MOVEQ.L     #0x24,D0                        | D0 = 36 bytes (map header)
    _NewHandle                                  | allocate handle for header
    MOVE.W      D0,(ResErr).W                   | record allocation result
    BMI.W       NEWMAP_ERR_3                    | OOM -> error tail
    MOVEA.L     A0,A4                           | A4 = new map handle
    BSR.W       CHECKLOAD_CONT_9                | init IOParam from filename
    BSR.W       RSRCZONEINIT_CONT_2             | open resource fork
    BEQ.B       NEWMAP_CONT                     | success -> read map
    CMPI.W      #0xFFCF,D0                      | error = paramErr (-49) ROM map?
    BNE.W       NEWMAP_ERR_2                    | other error -> bail
    MOVEM.L     D6/A2-A4,-(A7)                  | save regs across resmap scan
    BSR.W       RESMGR_CONT                     | look up by ROM refnum
    MOVEM.L     (A7)+,D6/A2-A4                  | restore regs
    BNE.W       NEWMAP_ERR_2                    | not found -> bail
    CLR.W       (ResErr).W                      | clear error
    MOVEA.L     A4,A0                           | A0 = unused header
    _DisposeHandle                              | free it (ROM map is in place)
    RTS                                         | return from VNEWMAP
| NEWMAP_CONT: file open succeeded, parse header and load map data.
NEWMAP_CONT:
    _GetEOF                                     | get logical EOF of fork
    MOVE.W      #0xFFD9,(ResErr).W              | preset eofErr (-39)
    TST.L       0x1C(A0)                        | empty fork?
    BEQ.B       VNEWMAP_ERR_CLOSE               | yes -> error
    MOVEQ.L     #0x24,D0                        | D0 = 36 bytes
    MOVEA.L     (A4),A1                         | A1 = deref map handle
    MOVE.L      A1,D1                           | D1 = data buffer addr
    MOVEQ.L     #0x0,D2                         | D2 = file offset 0
    BSR.W       CHECKLOAD_CONT_10               | _Read 36 bytes (resource header)
    BMI.B       VNEWMAP_ERR_CLOSE               | read failed -> error
    MOVEA.L     A1,A0                           | A0 = header buffer
    ADDA.W      #0x10,A0                        | A0 -> map-offset/length fields
    LEA.L       (RMgrHiVars_LastResType).W,A1   | A1 = RM scratch cache base
    MOVEQ.L     #0x14,D0                        | D0 = 20 bytes
    _BlockMove                                  | copy 5 longs to scratch cache
    MOVEA.L     A0,A1                           | A1 = past-fields ptr
    SUBA.W      #0x10,A1                        | A1 = back to header start
    BSR.B       NEWMAP_RETRY                    | clear scratch overrides
    MOVEQ.L     #0xC,D1                         | D1 = 12 (header preamble size)
    MOVE.L      0x4(A1),D2                      | D2 = map data offset in fork
    ADD.L       D1,D2                           | D2 += 12 (skip preamble)
    MOVE.L      0xC(A1),D4                      | D4 = map length (+$C)
    MOVE.L      D4,D0                           | D0 = D4
    MOVEA.L     A4,A0                           | A0 = map handle
    _SetHandleSize                              | grow handle to fit full map
    MOVE.W      D0,(ResErr).W                   | save resize result
    BNE.B       VNEWMAP_ERR_CLOSE               | resize failed -> error
    MOVEA.L     (A4),A1                         | A1 = deref'd map block
    MOVE.L      D4,D0                           | D0 = total map length
    SUB.L       D1,D0                           | D0 -= 12 (data only)
    ADD.L       A1,D1                           | D1 = ptr past header (12)
    BSR.W       CHECKLOAD_CONT_10               | _Read map data into block
    BMI.B       VNEWMAP_ERR_CLOSE               | read failed -> error
    TST.L       (RMgrHiVars_LastResType).W      | override-mode active?
    BEQ.B       NEWMAP_SKIP                     | no -> skip
    MOVE.L      0xC(A1),(RMgrHiVars_LastResType).W | publish map data length to globals
    BSR.B       NEWMAP_RETRY                    | clear scratch overrides
NEWMAP_SKIP:
    MOVE.L      D4,0xC(A1)                      | store actual map length in header
    BSR.W       CHECKLOAD_CONT_19               | rebuild type/ref pointers in map
    BMI.B       VNEWMAP_ERR_CLOSE               | error -> abort
    CLR.L       0x10(A1)                        | clear nextMap (caller links)
    MOVE.W      D6,0x14(A1)                     | header.refNum = file refnum
    MOVEQ.L     #0x1,D0                         | D0 = 1 (success, link to chain)
    RTS                                         | return from VNEWMAP
| Error tail: close file, dispose header, clear scratch.
| Called by: NEWMAP_CONT, NEWMAP_SKIP
VNEWMAP_ERR_CLOSE:
    BSR.W       CHECKLOAD_CONT_9                | re-init IOParam (for _Close)
    _Close                                      | close resource fork
NEWMAP_ERR_2:
    MOVEA.L     A4,A0                           | A0 = map header handle
    _DisposeHandle                              | dispose header
NEWMAP_ERR_3:
    CLR.L       (RMgrHiVars_LastResType).W      | clear scratch cache
    CLR.L       (RMgrLastResHand).W             | clear last-handle cache
    MOVEQ.L     #-0x1,D6                        | D6 = -1 (no refnum)
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (error)
    RTS                                         | return from NEWMAP_ERR_3
| ----------------------------------------------------------
|
| NEWMAP_RETRY -- clear scratch override unless magic is set.
|
| The magic 0x20B7A185 marks "override mode" -- set by the override
| handshake in NEW_RES_FILE so the next VNEWMAP knows to splice a
| custom map. This routine clears the scratch globals after each
| VNEWMAP unless the magic is still pending.
| Called during boot.
NEWMAP_RETRY:
    MOVE.L      (RMgrHiVars_LastResType).W,D0   | D0 = current scratch value
    SUBI.L      #0x20B7A185,D0                  | match override magic?
    BEQ.B       NEWMAP_SKIP_2                   | yes -> keep RMgrHiVars set
    CLR.L       (RMgrHiVars_LastResType).W      | no -> clear scratch
NEWMAP_SKIP_2:
    CLR.L       (RMgrLastResHand).W             | always clear last-handle cache
    RTS                                         | return from NEWMAP_RETRY
| ----------------------------------------------------------
|
| RSRCZONEINIT ($A996) -- prepare resource manager for new app zone.
|
| Closes all resource files above the system map, then walks the system
| map's reference list and clears the cached handle for any resource
| that lacks the resSysHeap attribute. This forces such resources to
| reload from disk into the new app zone on next access.
| Called during boot.
RSRCZONEINIT:
    BSR.W       RESMGR_CONT_4                   | StdEntry: link A6, save regs
    TST.W       (SysMap).W                      | system map present?
    BMI.B       RSRCZONEINIT_EXIT               | no -> exit
    BSR.B       RSRCZONEINIT_NEXT               | close all maps above system map
    MOVEA.L     (SysMapHndl).W,A4               | A4 = system map handle
    BSR.W       RESMGR_CONT_3                   | walk system map ref list
    BMI.B       RSRCZONEINIT_EXIT               | error -> exit
RSRCZONEINIT_LOOP:
    BTST        #0x6,0x4(A2)                    | resSysHeap bit set?
    BNE.B       RSRCZONEINIT_CONT               | yes -> keep cached handle
    CLR.L       0x8(A2)                         | no -> clear handle (force reload)
RSRCZONEINIT_CONT:
    ADDA.W      #0xC,A2                         | next 12-byte ref entry
    DBF.W       D4,RSRCZONEINIT_LOOP            | loop through all refs
RSRCZONEINIT_EXIT:
    BRA.W       RESMGR_EXIT_6                   | StdExit
| ----------------------------------------------------------
|
| RSRCZONEINIT_NEXT -- close all resource files above the system map.
|
| Walks down the resource map chain, calling _CloseResFile on each
| top map until we reach the system map.
| Called during boot.
RSRCZONEINIT_NEXT:
    MOVEA.L     (TopMapHndl).W,A0               | A0 = top map handle
    CMPA.L      (SysMapHndl).W,A0               | reached system map?
    BEQ.B       RSRCZONEINIT_DONE               | yes -> done
    MOVEA.L     (A0),A0                         | A0 = deref'd map block
    MOVE.W      0x14(A0),-(A7)                  | push refnum
    _CloseResFile                               | close this map's file
    BRA.B       RSRCZONEINIT_NEXT               | loop until at SysMap
| ----------------------------------------------------------
|
| RSRCZONEINIT_DONE -- exit when chain has been collapsed to SysMap.
|
| Called during boot.
RSRCZONEINIT_DONE:
    RTS                                         | return from RSRCZONEINIT_NEXT
| ----------------------------------------------------------
|
| RSRCZONEINIT_CONT_2 -- open resource fork (with printer-driver fixup).
|
| If the resource is 'STR ' ID -8192 (printer driver), uses BootDrive
| for vRefNum -- this matches the printer driver resource file convention
| that ROM-resident printer drivers are loaded from the boot disk.
| Stack frame on entry: A0 = IOParam ptr, A1 = filename string ptr.
| Returns D6 = file refnum, D0 = result code in ResErr.
| Called during boot.
RSRCZONEINIT_CONT_2:
    MOVE.L      A1,D0                           | D0 = filename pointer
    BTST        #0x0,D0                         | odd address?
    BNE.B       OPENRF_SET_FNAME                | yes -> not a handle, plain ptr
    BTST        #0x1D,D0                        | bit 29 set (handle marker)?
    BEQ.B       OPENRF_SET_FNAME                | clear -> plain ptr, skip lookup
    MOVEM.L     A0-A1,-(A7)                     | save IOParam ptr and filename
    MOVEA.L     A1,A0                           | A0 = master ptr (suspect handle)
    _RecoverHandle                              | recover handle from master ptr
    LINK        A2,#-0xE                        | locals: ID(W), type(L), name slot
    MOVE.L      A0,-(A7)                        | push resource handle
    PEA.L       -0x4(A2)                        | push ptr to ID result
    PEA.L       -0x8(A2)                        | push ptr to type result
    CLR.L       -(A7)                           | push nil for name (no copy)
    _GetResInfo                                 | get type and ID of resource
    CMPI.W      #0xE000,-0x4(A2)                | ID = -8192 (printer driver STR)?
    BNE.B       OPENRF_SKIP_BOOT                | no -> skip BootDrive override
    CMPI.L      #0x53545220,-0x8(A2)            | type = 'STR ' (0x53545220)?
    BNE.B       OPENRF_SKIP_BOOT                | no -> skip
    MOVE.W      (BootDrive).W,-0x1C(A6)         | override caller's vRefNum -> BootDrive
OPENRF_SKIP_BOOT:
    UNLK        A2                              | discard locals
    MOVEM.L     (A7)+,A0-A1                     | restore IOParam ptr and filename
OPENRF_SET_FNAME:
    MOVE.L      A1,0x12(A0)                     | IOParam.ioFileName = filename
    CLR.L       0x1C(A0)                        | IOParam.ioOwnBuf = 0 (no buffer)
    _OpenRF                                     | open resource fork
    MOVE.W      0x18(A0),D6                     | D6 = IOParam.ioRefNum
    MOVE.W      D0,(ResErr).W                   | save result code
    RTS                                         | return from RSRCZONEINIT_CONT_2
| ----------------------------------------------------------
|
| _CreateResFile ($A9B1) -- create a new resource file.
|
| Creates a new resource file. If the file does not exist, creates it
| first with _Create. Writes an empty resource map (16-byte header +
| 30-byte null map at file offset 256) to the resource fork.
CREATERESFILE:
    BSR.W       RESMGR_CONT_4                   | StdEntry: link A6, save regs
    MOVEA.L     (A0),A1                         | A1 = filename pointer
    BSR.W       CHECKLOAD_CONT_9                | init IOParam from filename
    BSR.B       RSRCZONEINIT_CONT_2             | try to open resource fork
    BEQ.B       CREATERES_CHKEOF                | opened OK -> check empty
    CMPI.W      #0xFFD5,D0                      | error = fnfErr (-43)?
    BNE.B       CREATERES_EXIT                  | other error -> bail out
    _Create                                     | file not found -> create it
    MOVE.W      D0,(ResErr).W                   | save create result
    BMI.B       CREATERES_EXIT                  | create failed -> bail
    BSR.B       RSRCZONEINIT_CONT_2             | open the newly created file
    BMI.B       CREATERES_EXIT                  | open failed -> bail
CREATERES_CHKEOF:
    _GetEOF                                     | check resource fork size
    MOVE.W      #0xFFD0,(ResErr).W              | preset mapReadErr (-48)
    TST.L       0x1C(A0)                        | resource fork empty?
    BNE.B       CREATERES_CLOSE                 | non-empty -> skip init
    MOVEQ.L     #0x10,D0                        | D0 = 16 bytes (resource header)
    LEA.L       RMGR(PC),A1                     | A1 = null resource map template
    MOVE.L      A1,D1                           | D1 = template src
    BSR.W       CHECKLOAD_CONT_11               | _Write 16-byte header @ offset 0
    MOVEQ.L     #0x1E,D0                        | D0 = 30 bytes (NullRMSize)
    MOVEQ.L     #0x40,D2                        | D2 = 0x40
    ASL.W       #0x2,D2                         | D2 = 256 (offset to map)
    BSR.W       CHECKLOAD_EMPTY_2               | _Write 30-byte map @ offset 256
CREATERES_CLOSE:
    _Close                                      | close the file
CREATERES_EXIT:
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| _OpenResFile ($A997) -- open a resource file and link its map.
|
| Opens a resource file by filename, builds an in-memory resource map
| from its resource fork, and links the new map at the head of the
| resource map chain (TopMapHndl). Returns the file's reference number
| as the function result.
OPENRESFILE:
    BSR.W       RESMGR_CONT_4                   | StdEntry: link A6, save regs
| OPENRES_COMMON: shared body for OpenResFile and OpenRFPerm.
OPENRES_COMMON:
    MOVE.L      (MinusOne).W,(LastSPExtra).W    | invalidate FS save-extra cache
    MOVEA.L     (A0),A1                         | A1 = filename ptr
    BSR.W       P_NewMap                        | open file, read map into memory
    MOVE.W      D6,0xC(A6)                      | store refnum as function result
    BMI.B       OPENRES_EXIT                    | NewMap failed -> skip linking
    MOVE.W      D6,(CurMap).W                   | set as current resource file
    TST.W       D0                              | ROM map (no link) or new (link)?
    BEQ.B       OPENRES_EXIT                    | ROM map -> skip linking
    MOVE.L      (TopMapHndl).W,0x10(A1)         | new map.nextMap = old TopMap
    MOVE.L      A4,(TopMapHndl).W               | TopMapHndl = new map handle
    BSR.W       INITRES_LOADALL                 | preload flagged resources
OPENRES_EXIT:
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| _OpenRFPerm ($A9C4) -- open with explicit permission byte.
|
| Stack: fileName(L), vRefNum(W), permission(B) -> refNum(W).
| Pops permission byte and vRefNum, joins OpenResFile common path.
OPENRFPERM:
    MOVEA.L     (A7)+,A0                        | save return address
    MOVE.B      (A7)+,(RMgrPerm).W              | pop permission byte -> global
    MOVE.W      (A7)+,D0                        | pop vRefNum
    MOVE.L      A0,-(A7)                        | restore return address
    BSR.W       RESMGR_CONT_4                   | StdEntry: link A6, save regs
    MOVE.W      D0,-0x1C(A6)                    | save vRefNum in stack frame
    BRA.B       OPENRES_COMMON                  | join OpenResFile common path
| ----------------------------------------------------------
|
| _UseResFile ($A998) -- set current resource file by refnum.
USERESFILE:
    BSR.B       STDMAPENTRY                     | StdMapEntry: find map by refnum
    MOVE.W      D6,(CurMap).W                   | set as current map
    BRA.W       RESMGR_ERR_2                    | StdTwoExit
| ----------------------------------------------------------
|
| _GetResFileAttrs ($A9F6) -- read map attributes word for a refnum.
GETRESFILEATTRS:
    BSR.B       STDMAPENTRY                     | StdMapEntry: find map by refnum
    MOVE.B      0x16(A3),0xB(A6)                | return map attributes byte (mAttr, +$16)
    BRA.W       RESMGR_ERR_2                    | StdTwoExit
| ----------------------------------------------------------
|
| _SetResFileAttrs ($A9F7) -- write map attributes word for a refnum.
SETRESFILEATTRS:
    BSR.W       RESMGR_CONT_4                   | StdEntry: link A6, save regs
    MOVE.W      0xA(A6),D6                      | D6 = refnum from stack frame
    BSR.W       RESMGR_CONT                     | GetMap: find map by refnum
    BMI.B       SETRESFILEATTRS_EXIT            | not found -> skip
    MOVE.B      0x9(A6),0x16(A3)                | set map attributes byte (mAttr, +$16)
SETRESFILEATTRS_EXIT:
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| STDMAPENTRY (STDMAPENTRY) -- standard entry for refnum-keyed routines.
|
| Pops caller's return addr, calls StdEntry to set up frame, finds the
| map matching refnum from parameter area. On failure pops return addr
| and exits with resFNotFound.
STDMAPENTRY:
    MOVE.L      (A7)+,D0                        | save caller's return address
    BSR.W       RESMGR_CONT_4                   | StdEntry: link A6, save regs
    MOVE.L      D0,-(A7)                        | restore return address
    MOVE.W      (A0),D6                         | D6 = refnum from parameter area
    BSR.W       RESMGR_CONT                     | GetMap: find map by refnum
    BMI.B       STDMAPENTRY_ERR                 | not found -> error exit
    RTS                                         | return from STDMAPENTRY
| Map not found: pop caller's return address, signal resFNotFound.
STDMAPENTRY_ERR:
    ADDQ.W      #0x4,A7                         | discard caller's return address
    MOVE.W      #0xFF3F,(ResErr).W              | resFNotFound (-193)
    BRA.W       RESMGR_ERR_2                    | StdTwoExit
| ----------------------------------------------------------
|
| FINDNEXT_ALL - FindNext (from beginning of all maps)
|
| Searches all resource maps for the next reference entry
| whose data offset is greater than the current position.
| Used by UpdateResFile to iterate resources in file order.
FINDNEXT_ALL:
    MOVEQ.L     #0x0,D1                         | D1=0: search all entries
| FINDNEXT_FROM_START -- findNext from beginning, changed only.
FINDNEXT_FROM_START:
    MOVEQ.L     #-0x1,D0                        | start from offset -1 (beginning)
    BRA.B       FINDNEXT_ENTER                  | continue at shared scan body
| ----------------------------------------------------------
|
| FINDNEXT_FROM_CUR - FindNext (from current entry's offset)
|
| Searches for the next resource entry whose data offset
| is greater than the current entry's offset. Used during
| UpdateResFile compaction to process resources in file order.
| Called during boot.
FINDNEXT_FROM_CUR:
    MOVEQ.L     #0x0,D1                         | D1=0: search all entries
| FINDNEXT_CUR_OFS -- shared body: read current ref's offset into D0.
FINDNEXT_CUR_OFS:
    MOVE.L      0x4(A2),D0                      | D0 = current ref's attrs+offset
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit data offset
FINDNEXT_ENTER:
    MOVEM.L     D2-D7/A3,-(A7)                  | save scan state
    MOVE.L      D0,D2                           | D2 = minimum data offset
    BSR.W       RESMGR_CONT_3                   | walk type list -> A2, D4 = ref count
    BMI.B       FINDNEXT_RET                    | empty -> return failure
    LEA.L       (MinusOne).W,A3                 | A3 = sentinel base
    SUBQ.L      #0x4,A3                         | A3 -> just before MinusOne
    MOVE.L      A3,D6                           | D6 = best entry so far (sentinel)
    MOVEQ.L     #-0x1,D7                        | D7 = 0xFFFFFFFF
    LSR.L       #0x1,D7                         | D7 = 0x7FFFFFFF (max long)
    TST.W       D1                              | flag-only mode (D1 != 0)?
    BEQ.B       FINDNEXT_ALL_LOOP               | no -> scan all entries
FINDNEXT_FLAG_LOOP:
    BTST        D1,0x4(A2)                      | test attr bit D1 of this ref
    BEQ.B       FINDNEXT_FLAG_SKIP              | clear -> skip
    MOVE.L      0x4(A2),D0                      | D0 = this ref's attrs+offset
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit data offset
    CMP.L       D0,D2                           | offset > current minimum?
    BGE.B       FINDNEXT_FLAG_SKIP              | no -> skip
    CMP.L       D0,D7                           | offset < current best?
    BLE.B       FINDNEXT_FLAG_SKIP              | no -> skip
    MOVE.L      D0,D7                           | yes -> update best offset
    MOVE.L      A2,D6                           | update best entry pointer
FINDNEXT_FLAG_SKIP:
    ADDA.W      #0xC,A2                         | next 12-byte ref entry
    DBF.W       D4,FINDNEXT_FLAG_LOOP           | loop through all refs
    BRA.B       FINDNEXT_DONE                   | finalize result
| ----------------------------------------------------------
|
| FINDNEXT_ALL_LOOP - FindNext inner loop (all entries, no flag check)
|
| Scans all reference entries for the one with the smallest
| data offset that is still greater than the minimum in D2.
| Called during boot.
FINDNEXT_ALL_LOOP:
    MOVE.L      0x4(A2),D0                      | D0 = this ref's attrs+offset
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit data offset
    CMP.L       D0,D2                           | offset > current minimum?
    BGE.B       FINDNEXT_ALL_SKIP               | no -> skip
    CMP.L       D0,D7                           | offset < current best?
    BLE.B       FINDNEXT_ALL_SKIP               | no -> skip
    MOVE.L      D0,D7                           | yes -> update best offset
    MOVE.L      A2,D6                           | update best entry pointer
FINDNEXT_ALL_SKIP:
    ADDA.W      #0xC,A2                         | next 12-byte ref entry
    DBF.W       D4,FINDNEXT_ALL_LOOP            | loop through all refs
FINDNEXT_DONE:
    MOVEA.L     D6,A2                           | A2 = best matching ref entry
    MOVE.L      D7,D0                           | D0 = best offset found
    MOVE.L      0x4(A2),D7                      | D7 = best entry's attrs+offset
    AND.L       (Lo3Bytes).W,D7                 | mask to 24-bit offset
    CMP.L       D0,D7                           | set Z=1 iff valid match
FINDNEXT_RET:
    MOVEM.L     (A7)+,D2-D7/A3                  | restore scan state
    RTS                                         | Z=1 if match, MI if no match
| ----------------------------------------------------------
|
| _UpdateResFile ($A999) -- write changed resources back to file.
|
| Two paths: if mapCompact is clear, write only changed resources
| in file order. If mapCompact is set, do full compaction (write all
| resources sequentially through CmpFrm to close gaps).
UPDATERESFILE:
    BSR.W       STDMAPENTRY                     | StdMapEntry: find map by refnum
    BSR.W       CHECKLOAD_OK_4                  | test if file is read-only
    BEQ.B       UPDRES_CHECK_CHG                | writable -> proceed
    MOVE.W      #0xFF39,(ResErr).W              | wPrErr (-199): write-protected
    BRA.W       RESMGR_ERR_2                    | StdTwoExit
UPDRES_CHECK_CHG:
    BTST        #0x5,0x16(A0)                   | mapChanged set?
    BEQ.W       RESMGR_ERR_2                    | not changed -> done
    BSR.W       CHECKLOAD_OK_3                  | flush map header to disk
    BMI.W       RESMGR_ERR_2                    | write error -> bail
    BCLR        #0x6,0x16(A3)                   | clear+test mapCompact flag in mAttr (+$16)
    BNE.B       UPDRES_FULL_COMPACT             | was set -> full compaction
    MOVEQ.L     #0x1,D1                         | D1=1: changed entries only
    BSR.W       FINDNEXT_FROM_START             | FindNext(changed, from start)
    BMI.B       UPDRES_DONE_CHANGED             | nothing changed -> skip writes
UPDRES_WRITE_CHANGED_LOOP:
    BSR.W       CHECKLOAD_CONT_8                | write this changed resource
    BSR.W       FINDNEXT_CUR_OFS                | FindNext changed after current
    BEQ.B       UPDRES_WRITE_CHANGED_LOOP       | found -> write next
UPDRES_DONE_CHANGED:
    BRA.W       CMP_WRITE_MAP                   | finish: write updated map
| Full-compaction path: rewrite every resource sequentially.
UPDRES_FULL_COMPACT:
    BSR.W       FINDNEXT_ALL                    | FindNext(any) from beginning
    BMI.W       CMP_WRITE_MAP                   | empty map -> just write header
    MOVEA.L     (A4),A0                         | A0 = deref'd map block
    MOVE.L      (A0),D7                         | D7 = current data fork end
    SUB.L       0x4(A0),D7                      | D7 = data end - data start
    BCS.B       CMP_BEGIN                       | underflow -> skip adjust
    BSR.W       RESMGR_CONT_3                   | walk type list -> A2, D4
| UPDRES_ADJ_LOOP: shift every ref entry's data offset by D7.
UPDRES_ADJ_LOOP:
    ADD.L       D7,0x4(A2)                      | adjust ref's offset by delta
    ADDA.W      #0xC,A2                         | next 12-byte ref entry
    DBF.W       D4,UPDRES_ADJ_LOOP              | loop through all refs
    MOVE.L      0x4(A0),(A0)                    | data fork end = data start
    BSR.W       FINDNEXT_ALL                    | rescan from beginning
CMP_BEGIN:
    MOVEQ.L     #0x0,D7                         | D7 = compaction write position
    BRA.B       CMP_GAP_CHECK                   | enter compaction gap-check
| CMP_WRITE_RES: write the current resource (changed or unchanged).
CMP_WRITE_RES:
    BTST        #0x1,0x4(A2)                    | resChanged bit set?
    BEQ.B       CMP_DISK_LEN                    | no -> read size from file
    BSR.W       CHECKLOAD_CONT_8                | write changed resource to disk
    MOVEA.L     0x8(A2),A0                      | A0 = resource handle
    _GetHandleSize                              | D0 = resource data size in mem
    BRA.B       CMP_ADD_LEN_PFX                 | -> add length prefix
CMP_DISK_LEN:
    BSR.W       CHECKLOAD_CONT_5                | read 4-byte length prefix from file
CMP_ADD_LEN_PFX:
    ADDQ.L      #0x4,D0                         | + 4 bytes for length prefix
    MOVE.L      0x4(A2),D7                      | D7 = current ref's offset+attrs
    ADD.L       D0,D7                           | D7 += data length (next pos)
    AND.L       (Lo3Bytes).W,D7                 | mask to 24-bit
    BSR.W       FINDNEXT_FROM_CUR               | FindNext after this entry
    BMI.W       CMP_STORE_DATALEN               | none -> finalize
CMP_GAP_CHECK:
    MOVE.L      D7,D0                           | D0 = expected next position
    SUB.L       0x4(A2),D0                      | D0 -= next ref's offset
    AND.L       (Lo3Bytes).W,D0                 | D0 = gap size (24-bit)
    BEQ.B       CMP_WRITE_RES                   | no gap -> just write next res
    SUBA.L      (A4),A2                         | A2 -> offset (handle may move)
    BSR.W       CHECKLOAD_CONT_12               | D0 = total data fork size
    MOVE.L      D0,D3                           | D3 = candidate buffer size
    _MaxBlock                                   | D0 = largest free block
    CMP.L       D3,D0                           | bigger than candidate?
    BGE.B       CMP_BUF_SIZE_OK                 | yes -> keep D3
    EXG         D3,D0                           | swap so D3 = larger
CMP_BUF_SIZE_OK:
    MOVEQ.L     #0x40,D0                        | D0 = 0x40
    ASL.W       #0x4,D0                         | D0 = 0x400 = 1024 (min buffer)
    CMP.L       D0,D3                           | candidate >= 1024?
    BGE.B       CMP_ALLOC_HEAP_BUF              | yes -> heap-alloc buffer
    MOVE.L      D0,D3                           | clamp to 1024
    LINK        A3,#-0x400                      | use stack frame for buffer
    MOVE.L      A7,(A3)                         | A3.master = A7 (buffer ptr)
    BRA.B       CMP_LOOP_ENTRY                  | enter compaction
CMP_ALLOC_HEAP_BUF:
    MOVE.L      D3,D0                           | D0 = buffer size
    _NewHandle                                  | allocate compaction buffer
    _HLock                                      | lock so it won't move
    MOVEA.L     A0,A3                           | A3 = buffer handle
CMP_LOOP_ENTRY:
    ADDA.L      (A4),A2                         | restore A2 to absolute
    MOVE.L      (A3),D0                         | D0 = deref'd buffer ptr
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit address
    ADD.L       D0,D3                           | D3 = buffer end address
    MOVEA.L     D0,A1                           | A1 = buffer write ptr
    MOVE.L      A1,D4                           | D4 = buffer read limit
    MOVE.L      D7,D5                           | D5 = file write position
    MOVEA.L     (0x7E8).W,A0                    | A0 = jCmpFrm dispatch vector
    JMP         (A0)                            | tail-call CmpFrm
| ----------------------------------------------------------
|
| VCMPFRM (CmpFrm) -- compaction frame: copy resources to close gaps.
|
| For each resource in file order, either copies from memory (changed)
| or from disk (unchanged) into the compaction buffer, then flushes
| the buffer to disk to close gaps between resources. Tail-called via
| jump vector $7E8 from the UpdateResFile compact path above.
VCMPFRM:
    BTST        #0x1,0x4(A2)                    | resChanged bit set?
    BEQ.B       CMP_COPY_FROM_DISK              | no -> copy from disk
    BSR.B       CMP_ADD_TO_BUF                  | copy changed resource from mem
    BPL.B       CMP_NEXT_RES                    | success -> next resource
CMP_COPY_FROM_DISK:
    BSR.W       CMP_COPY_UNCHANGE               | copy unchanged resource from disk
CMP_NEXT_RES:
    BSR.W       FINDNEXT_FROM_CUR               | FindNext after current
    BEQ.B       VCMPFRM                         | found -> compact it
    MOVE.L      A1,D0                           | D0 = current write pointer
    SUB.L       (A3),D0                         | D0 = bytes in buffer
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit count
    MOVE.L      (A3),D1                         | D1 = buffer base (source)
    MOVEA.L     (A4),A0                         | A0 = deref map handle
    MOVE.L      D7,D2                           | D2 = cumulative file pos
    ADD.L       (A0),D2                         | D2 += data fork base
    BSR.W       CHECKLOAD_EMPTY_2               | _Write buffer to file
    ADD.L       D0,D7                           | D7 += bytes written
    CMPA.L      A7,A3                           | buffer was on stack?
    BHI.B       CMP_UNLK_A3                     | yes -> just unlink
    MOVEA.L     A3,A0                           | A0 = compaction buffer handle
    _DisposeHandle                              | free heap-alloc'd buffer
    BRA.B       CMP_AFTER_FREE                  | continue
CMP_UNLK_A3:
    UNLK        A3                              | discard stack-frame buffer
CMP_AFTER_FREE:
    MOVEA.L     (A4),A3                         | A3 = deref'd map block
| CMP_STORE_DATALEN: store final data fork length in map header.
CMP_STORE_DATALEN:
    MOVE.L      D7,0x8(A3)                      | map.dataLength = D7
CMP_WRITE_MAP:
    BCLR        #0x5,0x16(A3)                   | clear+test mapChanged
    BEQ.B       CMP_MAP_EXIT                    | unchanged -> exit
    MOVE.L      0x8(A3),D2                      | D2 = data length (dataSize, +$8)
    ADD.L       (A3),D2                         | D2 += data fork base = map pos
    MOVE.L      D2,0x4(A3)                      | map.mapOffset = D2
    MOVE.L      0xC(A3),D0                      | D0 = map data length
    MOVE.L      A3,D1                           | D1 = map data source
    BSR.W       CHECKLOAD_EMPTY_2               | _Write map to file at D2
    MOVEQ.L     #0x10,D0                        | D0 = 16 (resource header)
    BSR.W       CHECKLOAD_CONT_11               | _Write 16-byte header at offset 0
    BSR.W       CHECKLOAD_OK_3                  | set EOF and flush
CMP_MAP_EXIT:
    BRA.W       RESMGR_ERR_2                    | StdTwoExit
| ----------------------------------------------------------
|
| CMP_ADD_TO_BUF (CMP_COPY_CHANGED) -- copy changed resource to compaction buffer.
|
| Reads the resource handle's data and copies it to the compaction
| buffer, flushing the buffer to disk when full. Writes the 4-byte
| length prefix first, then the data itself. Splits into chunks if
| the buffer cannot hold the entire resource at once.
CMP_ADD_TO_BUF:
    BSR.W       CMP_FLUSH_BUF                   | flush buffer if needed
    MOVEA.L     0x8(A2),A0                      | A0 = resource handle (rHndl, +$8)
    _GetHandleSize                              | D0 = resource data size
    TST.L       D0                              | valid handle?
    BMI.W       RESMGR_ERR                      | invalid -> error
    BSR.B       CMP_UPD_REF_OFS                 | update ref's offset for new pos
    BSR.B       CMP_WRITE_LONG                  | write 4-byte length prefix
    MOVE.L      D0,D2                           | D2 = remaining bytes
    ADD.L       A1,D2                           | D2 = buffer end after copy
    CMP.L       D2,D4                           | does data fit in buffer?
    MOVEA.L     (A0),A0                         | A0 = deref'd resource data
    BGE.B       CMP_BLOCKMOVE                   | fits -> single BlockMove
    MOVE.L      D0,D2                           | D2 = total bytes still to copy
    MOVEQ.L     #0x0,D1                         | D1 = source offset
| CMP_CHG_CHUNK: chunked copy loop (data > buffer capacity).
CMP_CHG_CHUNK:
    MOVEA.L     0x8(A2),A0                      | A0 = resource handle (may move)
    MOVEA.L     (A0),A0                         | A0 = deref'd data
    ADDA.L      D1,A0                           | offset into resource data
    MOVE.L      D3,D0                           | D0 = buffer end address
    SUB.L       A1,D0                           | D0 = remaining buffer space
    CMP.L       D2,D0                           | enough for remainder?
    BGE.B       CMP_CHG_FINAL                   | yes -> copy final chunk
    ADD.L       D0,D1                           | advance source offset
    SUB.L       D0,D2                           | reduce remaining count
    BSR.B       CMP_COPY_CHUNK                  | copy chunk to buffer
    BSR.W       CMP_FLUSH_BUF                   | flush buffer to disk
    BRA.B       CMP_CHG_CHUNK                   | next chunk
| ----------------------------------------------------------
|
| CMP_CHG_FINAL - final chunk: copy remaining bytes to buffer
|
CMP_CHG_FINAL:
| CMP_CHG_FINAL: final chunk of a chunked copy.
    MOVE.L      D2,D0                           | D0 = remaining byte count
| CMP_COPY_CHUNK -- copy chunk to buffer (saves D4 read-limit first).
CMP_COPY_CHUNK:
    MOVE.L      A1,D4                           | D4 = read limit (before write)
    NOP                                         | alignment padding (no-op)
| CMP_BLOCKMOVE -- BlockMove D0 bytes from A0 to A1, advance write ptr.
CMP_BLOCKMOVE:
    CMPA.L      A0,A1                           | source == dest (already in place)?
    BEQ.B       CMP_ADV_WRITEPTR                | yes -> skip BlockMove
    MOVE.L      D0,-(A7)                        | save byte count
    _BlockMove                                  | copy D0 bytes from A0 to A1
    MOVE.L      (A7)+,D0                        | restore byte count
| CMP_ADV_WRITEPTR -- advance write pointer and update read limit.
CMP_ADV_WRITEPTR:
    ADD.L       D0,D5                           | advance file write position
    ADDA.L      D0,A1                           | advance buffer write pointer
CMP_UPD_RDLIMIT:
    CMP.L       A1,D4                           | read limit behind write pointer?
    BGE.B       CMP_RDLIMIT_OK                  | no -> read limit still valid
    MOVE.L      A1,D4                           | yes -> update read limit
CMP_RDLIMIT_OK:
    RTS                                         | return from CMP_ADV_WRITEPTR
| ----------------------------------------------------------
|
| CMP_UPD_REF_OFS -- update ref entry's data offset to current buffer pos.
|
| Computes the new data offset from the buffer write pointer relative
| to buffer base, plus the cumulative file write offset. Preserves
| the attribute bits in the high byte (top 8 bits).
CMP_UPD_REF_OFS:
    MOVEM.L     D0-D1/A0,-(A7)                  | save working regs
    MOVEQ.L     #-0x3,D1                        | D1 = 0xFD mask (preserve attr bits 0,1)
    LEA.L       0x4(A2),A0                      | A0 = ptr to ref attrs+offset field (rLocn, +$4)
    AND.B       (A0),D1                         | D1 = preserved attr byte
    MOVE.L      A1,D0                           | D0 = buffer write ptr
    SUB.L       (A3),D0                         | D0 = offset within buffer
    ADD.L       D7,D0                           | D0 += cumulative file pos
    MOVE.L      D0,(A0)                         | store new 3-byte offset
    MOVE.B      D1,(A0)                         | restore attr byte (top byte)
    MOVEM.L     (A7)+,D0-D1/A0                  | restore working regs
    RTS                                         | return from CMP_UPD_REF_OFS
| ----------------------------------------------------------
|
| CMP_WRITE_ZERO / CMP_WRITE_LONG -- write 4-byte length prefix.
|
| Entry at CMP_WRITE_ZERO writes a zero-length resource (D0 = 0).
| Entry at CMP_WRITE_LONG writes D0 as a 4-byte big-endian value into
| the compaction buffer, MSB first via ROL.L #8.
CMP_WRITE_ZERO:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (zero-length resource)
| CMP_WRITE_LONG -- write D0 as 4-byte BE prefix at A1.
CMP_WRITE_LONG:
    MOVE.L      D1,-(A7)                        | save D1
    MOVEQ.L     #0x3,D1                         | D1 = 3 (loop count for 4 bytes)
CMP_WLONG_LOOP:
    ROL.L       #0x8,D0                         | rotate left 8 (MSB to low byte)
    MOVE.B      D0,(A1)+                        | store byte
    DBF.W       D1,CMP_WLONG_LOOP               | loop 4 times
    ADDQ.L      #0x4,D5                         | advance file write position by 4
    MOVE.L      (A7)+,D1                        | restore D1
    BRA.B       CMP_UPD_RDLIMIT                 | update buffer read limit
| ----------------------------------------------------------
|
| CMP_COPY_UNCHANGE (CMP_COPY_UNCHANGE) -- copy unchanged resource from disk.
|
| For an unchanged resource, reads its data from disk into the
| compaction buffer. If the entire resource fits in remaining buffer
| space, reads it directly. Otherwise reads in chunks, flushing the
| buffer to disk between reads.
CMP_COPY_UNCHANGE:
    MOVE.L      0x4(A2),D0                      | D0 = ref's offset+attrs
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit data offset
    SUB.L       D5,D0                           | D0 = offset - current write pos
    BGE.B       CMP_READ_INTACT                 | resource is ahead -> seek+copy
    BSR.W       CMP_FLUSH_BUF                   | else flush buffer
    BSR.B       CMP_UPD_REF_OFS                 | update ref's offset
    BRA.B       CMP_WRITE_ZERO                  | write zero-length resource
CMP_READ_INTACT:
    ADD.L       A1,D0                           | D0 = expected end addr in buffer
    ADDQ.L      #0x4,D0                         | + 4 bytes for length prefix
    CMP.L       D0,D4                           | fits in buffer?
    BGE.B       CMP_READ_UPD_OFS                | yes -> read directly
    BSR.W       CMP_FLUSH_BUF                   | flush buffer
    MOVE.L      0x4(A2),D0                      | D0 = ref's offset+attrs
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    MOVE.L      D0,D5                           | D5 = position resource starts at
    BSR.B       CMP_READ_FILE                   | read into buffer
CMP_READ_UPD_OFS:
    MOVE.L      0x4(A2),D0                      | D0 = ref's offset+attrs
    BSR.B       CMP_UPD_REF_OFS                 | update ref's offset
    SUB.L       D5,D0                           | D0 = ref offset - read base
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    MOVEA.L     A1,A0                           | A0 = buffer write ptr
    ADDA.L      D0,A0                           | A0 = ptr to length prefix in buf
    BSR.W       SUPERLOAD_CONT_2                | D0 = 4-byte BE length, A0 += 4
    ADDQ.L      #0x4,D0                         | D0 += 4 (include length prefix)
    SUBQ.L      #0x4,A0                         | A0 = back to length prefix
    MOVE.L      D0,D2                           | D2 = total bytes to copy
    ADD.L       A0,D2                           | D2 = end addr after copy
    CMP.L       D2,D4                           | fits in buffer remainder?
    BGE.W       CMP_BLOCKMOVE                   | yes -> single move
    ADD.L       A0,D5                           | D5 = effective read pos
    SUB.L       A1,D5                           | D5 -= buffer base = file pos
    AND.L       (Lo3Bytes).W,D5                 | mask to 24-bit
    MOVE.L      D0,D2                           | D2 = bytes left to copy
    MOVE.L      D4,D0                           | D0 = bytes available in buffer
    SUB.L       A0,D0                           | D0 -= buffer offset
    BSR.W       CMP_BLOCKMOVE                   | copy first chunk
    MOVE.L      A1,D4                           | D4 = new read limit
| CMP_READ_LOOP: chunked read loop for resources larger than buffer.
CMP_READ_LOOP:
    BSR.B       CMP_FLUSH_BUF                   | flush buffer to disk
    BSR.B       CMP_READ_FILE                   | read next chunk
    BEQ.B       CMP_READ_ERROR                  | EOF/error -> bail
    SUB.L       D0,D2                           | D2 -= bytes read
    MOVEA.L     A1,A0                           | A0 = buffer write ptr
    ADDA.L      D2,A0                           | A0 = end addr after copy
    CMP.L       A0,D4                           | fits in buffer?
    BGE.B       CMP_READ_FINAL                  | yes -> final chunk
    MOVE.L      D4,D0                           | D0 = bytes available
    SUB.L       A1,D0                           | D0 -= write ptr offset
    BSR.W       CMP_ADV_WRITEPTR                | advance ptrs
    BRA.B       CMP_READ_LOOP                   | next chunk
CMP_READ_FINAL:
    MOVE.L      A0,D0                           | D0 = end addr
    SUB.L       A1,D0                           | D0 -= write ptr (= bytes written)
    BRA.W       CMP_ADV_WRITEPTR                | advance ptrs
CMP_READ_ERROR:
    MOVE.W      #0xFF39,(ResErr).W              | wPrErr (-199) - write error
    BRA.W       CMP_UPD_RDLIMIT                 | update read limit, return
| ----------------------------------------------------------
|
| CMP_READ_FILE (CMP_READ_INTACT) -- read up to one disk block from file.
|
| Reads from current file position into compaction buffer, clamped to
| the smaller of (data fork remaining) or (buffer remaining). On
| return D0 = bytes read.
CMP_READ_FILE:
    MOVEM.L     D0-D2/A0,-(A7)                  | save working regs
    BSR.W       CHECKLOAD_CONT_12               | D0 = data fork total size
    MOVEA.L     (A4),A0                         | A0 = deref'd map handle
    SUB.L       D5,D0                           | D0 -= current file pos
    SUB.L       (A0),D0                         | D0 -= data fork base
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit (bytes remaining)
    MOVE.L      D3,D1                           | D1 = buffer end addr
    SUB.L       A1,D1                           | D1 = buffer remaining
    CMP.L       D1,D0                           | bytes remaining > buffer space?
    BLE.B       CMP_READF_CLAMP                 | no -> use D0
    MOVE.L      D1,D0                           | yes -> clamp to buffer space
CMP_READF_CLAMP:
    MOVE.L      A1,D1                           | D1 = read dest (buffer write ptr)
    MOVE.L      D5,D2                           | D2 = file read offset
    ADD.L       (A0),D2                         | D2 += data fork base = abs pos
    MOVE.L      A1,D4                           | D4 = new read limit (start)
    ADD.L       D0,D4                           | D4 += bytes to read = end
    AND.L       (Lo3Bytes).W,D4                 | mask to 24-bit
    BSR.W       CHECKLOAD_CONT_10               | _Read into buffer
    TST.L       D0                              | bytes read = 0?
    MOVEM.L     (A7)+,D0-D2/A0                  | restore working regs
    RTS                                         | return CCR set by TST
| ----------------------------------------------------------
|
| CMP_FLUSH_BUF -- flush compaction buffer to disk if it is sector-aligned.
|
| Computes how much of the buffer can be written as full disk sectors
| (multiples of 0x200), writes that prefix to the file, and shifts
| any remainder down to the buffer base via _BlockMove.
| Called by: CMP_ADD_TO_BUF, CMP_CHG_CHUNK, CMP_COPY_UNCHANGE, CMP_READ_UPD_OFS, CMP_READ_LOOP
CMP_FLUSH_BUF:
    MOVEM.L     D0-D2,-(A7)                     | save working regs
    MOVE.L      A1,D0                           | D0 = current write ptr
    SUB.L       (A3),D0                         | D0 = bytes in buffer
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    BEQ.B       CMP_FLUSH_RET                   | empty -> done
    MOVEA.L     (A4),A0                         | A0 = deref'd map handle
    MOVE.L      D7,D2                           | D2 = file write pos
    ADD.L       (A0),D2                         | D2 += data fork base
    ADD.L       D2,D0                           | D0 = absolute end addr
    ANDI.W      #0xFE00,D0                      | round down to 512-byte boundary
    SUB.L       D2,D0                           | D0 = aligned bytes to write
    BLE.B       CMP_FLUSH_RET                   | none -> done
    MOVE.L      (A3),D1                         | D1 = buffer base ptr
    BSR.W       CHECKLOAD_EMPTY_2               | _Write D0 bytes at D2
    ADD.L       D0,D7                           | D7 += bytes written
    SUBA.L      D0,A1                           | A1 -= bytes written (logical)
    SUB.L       D0,D4                           | D4 -= bytes written
    MOVE.L      A1,-(A7)                        | save adjusted write ptr
    MOVEA.L     (A3),A1                         | A1 = buffer base (BlockMove dest)
    MOVEA.L     (A3),A0                         | A0 = buffer base
    ADDA.L      D0,A0                           | A0 += bytes written (BlockMove src)
    ADD.L       D4,D0                           | (compute remainder size)
    SUB.L       A0,D0                           | D0 = bytes after the flush
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    _BlockMove                                  | shift remainder to buffer base
    MOVEA.L     (A7)+,A1                        | restore A1
CMP_FLUSH_RET:
    MOVEM.L     (A7)+,D0-D2                     | restore working regs
    RTS                                         | return from CMP_FLUSH_BUF
| ----------------------------------------------------------
|
| _CloseResFile ($A99A) -- close a resource file and unlink its map.
|
| Flushes any pending updates to disk via _UpdateResFile, then walks
| the map's reference list disposing every loaded resource handle
| via the _DisposHandle trap. Finally unlinks the map from the chain
| (TopMapHndl or its predecessor) and disposes the map handle.
|
| Special case: if refnum=0, closes all resource files above SysMap.
CLOSERESFILE:
    MOVE.L      (MinusOne).W,(LastSPExtra).W    | invalidate FS save-extra cache
    MOVE.W      (RMgrLastResFile).W,D0          | last cached refnum
    CMP.W       0x4(A7),D0                      | matches refnum being closed?
    BNE.B       CLOSERES_CHK_ALL                | no -> skip cache invalidation
    CLR.L       (RMgrLastResHand).W             | clear last-handle cache
CLOSERES_CHK_ALL:
    TST.W       0x4(A7)                         | refnum == 0 (close all)?
    BNE.B       LOC_E1FE                        | no -> close named file only
    BSR.W       RSRCZONEINIT_NEXT               | yes -> close all above SysMap
LOC_E1FE:
    BSR.W       STDMAPENTRY                     | StdMapEntry: find map by refnum
    MOVE.W      D6,-(A7)                        | push refnum
    _UpdateResFile                              | flush changed resources to disk
    MOVEQ.L     #0x23,D0                        | trap word for _DisposHandle
    _GetTrapAddress                             | A0 = _DisposHandle dispatch
    BSR.W       RESMGR_CONT_3                   | walk type list -> A2, D4
    BMI.B       CLOSERES_UNLINK                 | empty -> just unlink
    MOVEA.L     A0,A4                           | A4 = _DisposHandle entry
    ADDQ.W      #0x8,A2                         | skip type+attr+count fields
CLOSERES_DISP_LP:
    MOVE.L      (A2)+,D0                        | D0 = ref's resource handle
    BEQ.B       CLOSERES_DISP_NXT               | not loaded -> skip
    MOVEA.L     D0,A0                           | A0 = handle for trap
    JSR         (A4)                            | _DisposHandle (drop resource)
CLOSERES_DISP_NXT:
    ADDQ.W      #0x8,A2                         | skip 8 bytes (next ref+offset)
    DBF.W       D4,CLOSERES_DISP_LP             | loop through all refs
CLOSERES_UNLINK:
    BSR.W       RESMGR_CONT                     | get predecessor map handle
    MOVEA.L     0x10(A3),A0                     | A0 = next-map link
    TST.L       D0                              | predecessor present?
    BNE.B       CLOSERES_PRED_LNK               | yes -> patch predecessor's link
    MOVE.L      A0,(TopMapHndl).W               | no (head) -> TopMapHndl = next
    BRA.B       CLOSERES_CHK_SYS                | check SysMap fallback
| ----------------------------------------------------------
|
| CLOSERES_PRED_LNK -- unlink map from chain via predecessor.
|
CLOSERES_PRED_LNK:
    MOVEA.L     D0,A1                           | A1 = predecessor map handle
    MOVEA.L     (A1),A1                         | A1 = deref'd predecessor
    MOVE.L      A0,0x10(A1)                     | predecessor.next = our.next
CLOSERES_CHK_SYS:
    CMPA.L      (SysMapHndl).W,A4               | closing the system map?
    BNE.B       CLOSERES_UPD_CUR                | no -> normal close
    LEA.L       (TopMapHndl).W,A0               | yes -> reset to ROM-only state
    MOVE.L      (ROMMapHandle).W,(A0)+          | TopMapHndl = ROMMap
    MOVE.L      (ROMMapHandle).W,(A0)+          | SysMapHndl = ROMMap
    MOVE.L      (OneOne).W,(A0)+                | CurMap=SysMap=1 (ROM refnum)
    MOVEA.L     (ROMMapHandle).W,A0             | A0 = ROM map handle
    MOVEA.L     (A0),A0                         | A0 = deref'd ROM map block
    CLR.L       0x10(A0)                        | ROM.nextMap = nil (head of chain)
    BRA.B       CLOSERESFILE_DO_CLOSE           | -> close file
| ----------------------------------------------------------
|
| CLOSERES_UPD_CUR -- update CurMap if closing the current resource file.
|
| If we're closing the file referenced by CurMap, advance CurMap to
| the predecessor map's refnum so subsequent calls have a valid map.
| Called during boot.
CLOSERES_UPD_CUR:
    CMP.W       (CurMap).W,D6                   | closing current map?
    BNE.B       CLOSERESFILE_DO_CLOSE           | no -> skip update
    MOVEA.L     (A0),A0                         | A0 = deref'd next map
    MOVE.W      0x14(A0),(CurMap).W             | CurMap = next.refNum
CLOSERESFILE_DO_CLOSE:
    BSR.W       CHECKLOAD_CONT_9                | init IOParam with refnum
    _Close                                      | close the file
    BEQ.B       CLOSERES_DISPOSE                | success -> dispose map
    MOVE.W      D0,(ResErr).W                   | save close error
CLOSERES_DISPOSE:
    MOVEA.L     A4,A0                           | A0 = map handle
    _DisposeHandle                              | dispose map block
    BRA.W       RESMGR_ERR_2                    | StdTwoExit
| ----------------------------------------------------------
|
| _Count1Resources ($A80D), _CountResources ($A99C) -- count resources of type.
|
| _Count1Resources searches only the current map (sets RMgrCurOnly=true).
| _CountResources searches all maps in the chain.
| Stack: resType(L) -> count(W).
COUNT1RESOURCES:
    ST.B        (RMgrCurOnly).W                 | RMgrCurOnly = true (current map only)
COUNTRESOURCES:
    BSR.W       RESMGR_CONT_6                   | StdEntry: link A6, save regs
    MOVE.L      (A0),D3                         | D3 = resource type from stack
    MOVEQ.L     #0x0,D1                         | D1 = running count
    BSR.W       RETURNS_20                      | initialize map iteration
COUNTRES_LOOP:
    BSR.W       RETURNS_26                      | find type in current map -> A2
    BMI.B       COUNTRES_NEXTMAP                | not in this map -> next
    ADD.W       0x4(A2),D1                      | add this map's count
    ADDQ.W      #0x1,D1                         | + 1 (count is stored as N-1)
COUNTRES_NEXTMAP:
    BSR.W       RETURNS_22                      | advance to next map
    BEQ.B       COUNTRES_LOOP                   | found -> count it too
    MOVE.W      D1,0xC(A6)                      | return total in result slot
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| _Get1IndResource ($A80E), _GetIndResource ($A99D) -- get nth resource of type.
|
| _Get1IndResource searches only the current map (sets RMgrCurOnly).
| _GetIndResource searches all maps in chain.
| Stack: resType(L), index(W) -> handle(L).
| Caches the (curOnly, type, index, A2) tuple in RMgr globals so a
| subsequent call with same type and index+1 can skip the search.
GET1INDRESOURCE:
    ST.B        (RMgrCurOnly).W                 | RMgrCurOnly = true (current map only)
GETINDRESOURCE:
    BSR.W       RESMGR_CONT_6                   | StdEntry: link A6, save regs
    MOVE.W      (A0)+,D7                        | D7 = index
    BLE.W       GETIND_NOTFOUND                 | <= 0 -> not found
    MOVE.L      (A0)+,D3                        | D3 = resource type
    CLR.L       (A0)+                           | clear handle slot in stack frame
    MOVE.B      (RMgrCurOnly).W,D0              | D0 = current curOnly mode
    CMP.B       (RMgrLastCurOnly).W,D0          | matches cached mode?
    BNE.B       GETIND_FRESH                    | no -> fresh search
    TST.L       (RMgrLastResHand).W             | cached handle still valid?
    BEQ.B       GETIND_FRESH                    | no -> fresh search
    CMP.L       (RMgrHiVars_LastResType).W,D3   | type matches cache?
    BNE.B       GETIND_FRESH                    | no -> fresh search
    CMP.W       (RMgrNextResIndex).W,D7         | index = cached_next?
    BNE.B       GETIND_FRESH                    | no -> fresh search
    ADDQ.W      #0x1,(RMgrNextResIndex).W       | bump cached index
    BSR.W       RESMGR_OK_3                     | restore A2/D4 from cache
    TST.W       D4                              | refs left in this map?
    BEQ.B       GETIND_CACHE_ADV                | no -> next map
    SUBQ.W      #0x1,D4                         | yes -> decrement count
    ADDA.W      #0xC,A2                         | advance to next ref entry (12 bytes)
    BRA.B       GETIND_LOAD                     | -> load resource
| ----------------------------------------------------------
|
| GETIND_CACHE_ADV -- cache hit but type exhausted, advance to next map.
|
GETIND_CACHE_ADV:
    MOVEQ.L     #0x0,D7                         | D7 = 0 (need 0 more after found)
    BRA.B       GETIND_NEXTMAP                  | -> next map
| ----------------------------------------------------------
|
| GETIND_FRESH -- fresh search: iterate maps for nth resource of type.
|
| Iterates the map chain. For each map, counts refs of type D3.
| If accumulated >= D7, the result is in this map; else subtract
| and continue. Updates the cache for sequential access.
| Called during boot (11,458 times in 30s trace).
GETIND_FRESH:
    MOVE.B      D0,(RMgrLastCurOnly).W          | cache curOnly mode
    MOVE.W      D7,(RMgrNextResIndex).W         | cache requested index
    ADDQ.W      #0x1,(RMgrNextResIndex).W       | next call expects index+1
    SUBQ.W      #0x1,D7                         | D7 = refs to skip (index-1)
    BSR.W       RETURNS_20                      | initialize map iteration
GETIND_FIND_TYPE:
    BSR.W       RETURNS_26                      | find type in current map -> A2
    BMI.B       GETIND_NEXTMAP                  | not in this map -> next
    BSR.W       RETURNS_27                      | D4 = ref count for this type
    CMP.W       D7,D4                           | enough refs in this map?
    BMI.B       GETIND_SUB_SKIP                 | no -> subtract and continue
    SUB.W       D7,D4                           | D4 = remaining after this one
    ADD.W       D7,D7                           | D7 *= 2
    ADD.W       D7,D7                           | D7 *= 4
    ADDA.W      D7,A2                           | A2 += D7*4
    ADD.W       D7,D7                           | D7 *= 8
    ADDA.W      D7,A2                           | A2 += D7*8 (total: D7*12)
    BRA.B       GETIND_LOAD                     | -> load resource
| ----------------------------------------------------------
|
| GETIND_SUB_SKIP -- not enough refs in this map, subtract and continue.
|
| Called during boot (7,490 times in 30s trace).
GETIND_SUB_SKIP:
    SUB.W       D4,D7                           | D7 -= refs we passed
    SUBQ.W      #0x1,D7                         | -1 (count was N-1)
GETIND_NEXTMAP:
    BSR.W       RETURNS_22                      | advance to next map
    BEQ.B       GETIND_FIND_TYPE                | found -> search it
    BMI.B       GETIND_NOTFOUND                 | end of chain -> not found
| GETIND_LOAD: load resource at A2 and cache it.
GETIND_LOAD:
    BSR.W       RESMGR_CONT_15                  | save A2 in cache, derive handle
    BSR.W       P_CheckLoad                     | load resource if not cached
    MOVE.L      A0,0xE(A6)                      | return handle in result slot
    MOVE.L      A0,(RMgrLastResHand).W          | cache last handle
    BRA.B       GETIND_EXIT                     | -> exit
| ----------------------------------------------------------
|
| GETIND_NOTFOUND -- resource not found by index.
|
GETIND_NOTFOUND:
    MOVE.W      #0xFF40,(ResErr).W              | resNotFound (-192)
GETIND_EXIT:
    BRA.W       RESMGR_EXIT_4                   | StdSixExit
| ----------------------------------------------------------
|
| _Count1Types ($A81C), _CountTypes ($A99E) -- count distinct resource types.
|
| _Count1Types restricts to current map (sets RMgrCurOnly).
| _CountTypes counts distinct types across the entire map chain.
| Returns count via stack frame at +0x8.
COUNT1TYPES:
    ST.B        (RMgrCurOnly).W                 | RMgrCurOnly = true (current map only)
COUNTTYPES:
    BSR.W       RESMGR_CONT_6                   | StdEntry: link A6, save regs
    BSR.B       COUNT_UNIQ_TYPES                | D7 = count of unique types (uses A7)
    UNLK        A6                              | drop tmp frame (helper used SP)
    MOVE.W      D7,0x8(A6)                      | return count in stack frame
    BRA.W       RESMGR_EXIT_6                   | StdExit
| ----------------------------------------------------------
|
| COUNT_UNIQ_TYPES -- count unique resource types across all maps.
|
| Walks every map in the chain, collecting unique resource types
| on the stack. Uses a linear search against types-already-seen to
| avoid counting duplicates. Returns D7 = number of unique types,
| with the type list left on the stack starting at A7 (caller must
| pop or unlink to reclaim).
| Called during boot.
COUNT_UNIQ_TYPES:
    MOVEA.L     (A7)+,A0                        | save return address
    LINK        A6,#0x0                         | scratch frame on top of return addr
    MOVEQ.L     #0x0,D7                         | D7 = unique-type count
    BSR.W       RETURNS_20                      | initialize map iteration
CNTTYPE_MAP_LOOP:
    BSR.W       RETURNS_23                      | A2 = first type entry, D5 = count
    BMI.B       CNTTYPE_NEXTMAP                 | empty -> next map
CNTTYPE_ENTRY_LP:
    MOVE.L      (A2),D3                         | D3 = type 4-char code
    MOVEA.L     A7,A1                           | A1 = base of types-seen list
    MOVE.W      D7,D0                           | D0 = number to compare
    SUBQ.W      #0x1,D0                         | D0 = D7-1 (DBcc range)
    BMI.B       CNTTYPE_ADD_NEW                 | first time -> add unconditionally
CNTTYPE_CMP_LOOP:
    CMP.L       (A1)+,D3                        | already in list?
    DBEQ.W      D0,CNTTYPE_CMP_LOOP             | loop while different
    BEQ.B       CNTTYPE_NEXT_ENT                | found duplicate -> skip
CNTTYPE_ADD_NEW:
    MOVE.L      D3,-(A7)                        | push new type onto list
    ADDQ.W      #0x1,D7                         | bump unique count
CNTTYPE_NEXT_ENT:
    ADDQ.L      #0x8,A2                         | next type entry (8 bytes each)
    DBF.W       D5,CNTTYPE_ENTRY_LP             | loop through types in this map
CNTTYPE_NEXTMAP:
    BSR.W       RETURNS_22                      | advance to next map
    BEQ.B       CNTTYPE_MAP_LOOP                | found -> scan it too
    JMP         (A0)                            | tail-return to caller (A0 = ret addr)
| ----------------------------------------------------------
|
| _Get1IndType ($A80F), _GetIndType ($A99F) -- get type of nth distinct type.
|
| _Get1IndType restricts to current map (sets RMgrCurOnly).
| _GetIndType walks the chain.
| Stack: typePtr(L), index(W) -> stores type code at *typePtr.
GET1INDTYPE:
    ST.B        (RMgrCurOnly).W                 | RMgrCurOnly = true (current map only)
GETINDTYPE:
    BSR.W       RESMGR_CONT_6                   | StdEntry: link A6, save regs
    MOVE.W      (A0)+,D2                        | D2 = index
    MOVE.L      (A0),D1                         | D1 = output type pointer
    BSR.B       COUNT_UNIQ_TYPES                | enumerate types onto stack
    MOVEA.L     D1,A0                           | A0 = output pointer
    CLR.L       (A0)                            | default: zero result
    SUBQ.W      #0x1,D2                         | D2 = index - 1 (0-based)
    BMI.B       GETINDTYPE_EXIT                 | < 0 -> bail
    CMP.W       D2,D7                           | enough types found?
    BLE.B       GETINDTYPE_EXIT                 | no -> leave zero
    ASL.W       #0x2,D2                         | D2 = index * 4 (longs offset)
    MOVE.L      0x0(A7,D2.W),(A0)               | *resultPtr = stack[D2]
GETINDTYPE_EXIT:
    UNLK        A6                              | discard scratch + type list
    BRA.W       RESMGR_EXIT_4                   | StdSixExit
| ----------------------------------------------------------
|
| _Unique1ID ($A810), _UniqueID ($A9C1) -- generate unique resource ID.
|
| Picks a random ID in 0..0x7FFF that is not already used by any
| resource of the given type. _Unique1ID restricts to current map.
| Stack: type(L) -> id(W).
UNIQUE1ID:
    ST.B        (RMgrCurOnly).W                 | RMgrCurOnly = true (current map only)
UNIQUEID:
    BSR.W       RESMGR_CONT_6                   | StdEntry: link A6, save regs
    MOVE.W      (Ticks_LoWord).W,D7             | D7 = seed from Ticks low word
UNIQID_RETRY:
    BSR.W       RETURNS_20                      | begin map chain traversal
    SUBQ.W      #0x2,A7                         | reserve 2-byte slot for _Random
    _Random                                     | seed _Random with global state
    ADD.W       (A7)+,D7                        | mix Random output into D7
    ANDI.W      #0x7FFF,D7                      | clamp to 15-bit positive range
    MOVE.L      0x8(A6),D3                      | D3 = resource type
    MOVE.W      D7,D2                           | D2 = candidate id
UNIQID_CHECK:
    BSR.W       RETURNS_26                      | find type in current map
    BMI.B       UNIQID_NEXTMAP                  | not in this map -> next
    BSR.W       RETURNS_27                      | D4 = ref count
    BSR.W       RETURNS_25                      | scan refs for matching id
    BEQ.B       UNIQID_RETRY                    | id taken -> regenerate
UNIQID_NEXTMAP:
    BSR.W       RETURNS_22                      | advance to next map
    BEQ.B       UNIQID_CHECK                    | found -> check it too
    MOVE.W      D2,0xC(A6)                      | return id in result slot
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| _Get1Resource ($A81F), _GetResource ($A9A0) -- get resource by type and ID.
|
| _Get1Resource searches only the current map (sets RMgrCurOnly).
| _GetResource walks the entire chain, top map first.
| Stack: type(L), id(W) -> handle(L).
GET1RESOURCE:
    ST.B        (RMgrCurOnly).W                 | RMgrCurOnly = true (current map only)
GETRESOURCE:
    BSR.W       RESMGR_CONT_6                   | StdEntry: link A6, save regs
    BSR.W       RETURNS_21                      | check curOnly mode
    BPL.B       GETRES_SEARCH                   | curOnly -> search current
    BSR.W       RETURNS_20                      | full chain -> set up scan
GETRES_SEARCH:
    MOVE.W      (A0)+,D2                        | D2 = id
    MOVE.L      (A0)+,D3                        | D3 = type
    CLR.L       (A0)                            | clear handle slot in stack frame
GETRES_FIND_TYPE:
    BSR.W       RETURNS_26                      | find type in current map
    BMI.B       GETRES_NEXTMAP                  | not in map -> next map
    BSR.W       RETURNS_27                      | D4 = ref count
    BSR.W       RETURNS_25                      | scan refs for id == D2
    BEQ.B       GETRES_FOUND                    | found -> load it
GETRES_NEXTMAP:
    BSR.W       RETURNS_22                      | advance to next map
    BEQ.B       GETRES_FIND_TYPE                | found -> search it
    BRA.B       GETRES_EXIT                     | end of chain -> exit
GETRES_FOUND:
    BSR.W       RESMGR_CONT_14                  | save A2, derive ref handle
    BSR.W       P_CheckLoad                     | load resource if not cached
    MOVE.L      A0,0xE(A6)                      | return handle in result slot
    MOVE.L      A0,(RMgrLastResHand).W          | cache last handle
GETRES_EXIT:
    BRA.W       RESMGR_EXIT_4                   | StdSixExit
| ----------------------------------------------------------
|
| _Get1NamedResource ($A820), _GetNamedResource ($A9A1) -- find by name.
|
| Looks up a resource by Pascal-string name (case-insensitive) within
| the given type. Walks all references for the type, comparing each
| ref's name (offset 0x18-relative) against the search name via
| _CmpString. Returns first match.
| Stack: type(L), name(L) -> handle(L).
GET1NAMEDRESOURCE:
    ST.B        (RMgrCurOnly).W                 | RMgrCurOnly = true (current map only)
GETNAMEDRESOURCE:
    BSR.W       RESMGR_CONT_6                   | StdEntry: link A6, save regs
    BSR.B       RETURNS_21                      | check curOnly mode
    MOVEA.L     (A0),A1                         | A1 = caller's name string
    CLR.L       0x10(A6)                        | clear handle result slot
GETNAMED_LOOP:
    MOVE.L      0xC(A6),D3                      | D3 = type
    BSR.W       RETURNS_26                      | find type in current map
    BMI.B       RESMGR_NEXT                     | not in map -> next map
    BSR.W       RETURNS_27                      | D4 = ref count
GETNAMED_CMP_NAME:
    BSR.W       RESMGR_CONT_16                  | A0 = ref's name (or sets MI)
    BMI.B       RESMGR_SKIP                     | no name -> skip ref
    MOVEQ.L     #0x0,D0                         | D0 = 0
    MOVE.B      (A0)+,D0                        | D0.W = ref's name length
    SWAP.W      D0                              | name length to D0 high word
    MOVE.B      (A1)+,D0                        | D0.W = caller's name length
    _CmpString                                  | compare (D0 high=A0len, low=A1len)
    SUBQ.W      #0x1,A1                         | restore A1 to start of name
    BEQ.B       RESMGR_FOUND                    | match -> load it
| Resource Manager
|
| Manages resources in resource files (including the ROM resource map
| at $176F8). Provides GetResource, LoadResource, TE_APPLY_JUST_MEASURE,
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
| RESMGR_SKIP -- name comparison didn't match, advance to next ref.
RESMGR_SKIP:
    BSR.W       RETURNS_28                      | advance A2 to next ref
    BEQ.B       GETNAMED_CMP_NAME               | more refs -> compare next
RESMGR_NEXT:
    BSR.B       RETURNS_22                      | end of refs -> next map
    BEQ.B       GETNAMED_LOOP                   | found -> search it
    MOVE.W      #0xFF40,(ResErr).W              | resNotFound (-192)
    BRA.B       RESMGR_SKIP_2                   | -> exit
RESMGR_FOUND:
    BSR.W       RESMGR_CONT_14                  | save A2, derive ref handle
    BSR.W       P_CheckLoad                     | load resource if not cached
    MOVE.L      A0,0x10(A6)                     | return handle in result slot
    MOVE.L      A0,(RMgrLastResHand).W          | cache last handle
RESMGR_SKIP_2:
    MOVEQ.L     #0x8,D0                         | D0 = 8 (extra bytes in stack frame)
    BRA.W       RESMGR_CONT_11                  | StdEightExit
| ----------------------------------------------------------
|
| RETURNS_20 - SetupMapScan: begin resource map chain traversal
|
| If RMgrCurOnly is set, searches only the current map (via RETURNS_21).
| Otherwise starts from the topmost (most recently opened) resource file.
| Returns: A4=map handle, A3=A2=dereferenced map ptr, D6=file refNum.
| Called by: COUNTRESOURCES, GETIND_FRESH, COUNT_UNIQ_TYPES, UNIQID_RETRY, GETRESOURCE (and 1 more)
RETURNS_20:
    TST.B       (RMgrCurOnly).W                 | search all maps or just current?
    BNE.B       RETURNS_21                      | current only -> use CurMap refnum
    MOVEA.L     (TopMapHndl).W,A4               | A4 = topmost map handle
    MOVEA.L     (A4),A3                         | A3 = deref'd map block
    MOVE.W      0x14(A3),D6                     | D6 = map.refNum
    MOVEA.L     A3,A2                           | A2 = map block (for type list base)
    RTS                                         | return from RETURNS_20
| ----------------------------------------------------------
|
| RETURNS_21 - FindMapByRefNum: locate map handle for a given refNum
|
| Walks the resource chain from TopMapHndl to find the map whose
| file refNum matches D6. refNum=0 means System file (SysMap).
| Returns: A4=map handle, A3=A2=map ptr; falls through to RESMGR_ERR if not found.
RETURNS_21:
    MOVE.W      (CurMap).W,D6                   | D6 = current map's refnum
| RESMGR_CONT -- locate map by refnum in D6.
| Called by: INITRES_LOADALL, VNEWMAP, SETRESFILEATTRS, STDMAPENTRY, CLOSERES_UNLINK
RESMGR_CONT:
    TST.W       D6                              | refnum < 0 (invalid)?
    BMI.W       RESMGR_ERR                      | yes -> error
    BNE.B       RESMGR_CONT_2                   | non-zero -> use as-is
    MOVE.W      (SysMap).W,D6                   | refnum 0 -> use SysMap
RESMGR_CONT_2:
    MOVEA.L     (TopMapHndl).W,A4               | A4 = top of map chain
    MOVEQ.L     #0x0,D0                         | D0 = 0 (init for EXG)
    BRA.B       RESMGR_LOOP                     | enter chain walk
| ----------------------------------------------------------
|
| RESMGR_FOUND_2 -- walk to next map in resource chain.
|
| Follows the nextMap handle link (offset 0x10) to traverse the chain.
| PORTRECT offset = 0x10, which is the "next map handle" field.
RESMGR_FOUND_2:
    MOVE.L      0x10(A3),D0                     | D0 = next-map handle
    BEQ.W       RESMGR_ERR                      | nil -> end of chain
    EXG         D0,A4                           | A4 = next map handle
RESMGR_LOOP:
    MOVEA.L     (A4),A3                         | A3 = deref'd map block
    CMP.W       0x14(A3),D6                     | refNum match?
    BNE.B       RESMGR_FOUND_2                  | no -> next map in chain
    MOVEA.L     A3,A2                           | A2 = map block (for type list base)
    RTS                                         | return from RESMGR_LOOP
| ----------------------------------------------------------
|
| RETURNS_22 - NextMap: advance to next resource map in chain
|
| If searching current map only, returns NIL (end of search).
| Otherwise follows the nextMap chain link to the next open resource file.
| Returns: Z=0 if another map found, Z=1 if end of chain.
| Called by: COUNTRES_NEXTMAP, GETIND_NEXTMAP, CNTTYPE_NEXTMAP, UNIQID_NEXTMAP, GETRES_NEXTMAP (and 2 more)
RETURNS_22:
    TST.B       (RMgrCurOnly).W                 | searching current map only?
    BEQ.B       RESMGR_NEXT_2                   | no -> follow chain to next map
    SUBA.L      A4,A4                           | yes -> force nil (no more maps)
    BRA.B       RESMGR_EXIT                     | test nil and return end-of-chain
| ----------------------------------------------------------
|
| RESMGR_NEXT_2 -- follow chain link to next map.
|
RESMGR_NEXT_2:
    MOVEA.L     (A4),A3                         | A3 = deref'd current map
    MOVEA.L     0x10(A3),A4                     | A4 = nextMap handle
RESMGR_EXIT:
    MOVE.L      A4,D0                           | D0 = next handle (sets CCR)
    BEQ.B       RESMGR_ERR                      | nil -> end of chain
    MOVEA.L     (A4),A3                         | A3 = deref'd next map
    MOVE.W      0x14(A3),D6                     | D6 = next.refNum
    BRA.B       RESMGR_EXIT_3                   | clear D0, return Z=1 (found)
| ----------------------------------------------------------
|
| RETURNS_23 -- GetTypeList: set up type list pointer for current map.
|
| Dereferences the map handle and advances to the type list.
| VISRGN offset = 0x18, which is the "offset to type list" field in map.
| Returns: A2=first type entry, A3=type list base, D5=numTypes-1 (or -1).
RETURNS_23:
    MOVEA.L     (A4),A3                         | A3 = deref'd map block
    ADDA.W      0x18(A3),A3                     | A3 += offset to type list
    MOVEA.L     A3,A2                           | A2 = type list base
    MOVE.W      (A2)+,D5                        | D5 = numTypes - 1, A2 -> first entry
    RTS                                         | return from RETURNS_23
| ----------------------------------------------------------
|
| RESMGR_CONT_3 -- CountAllRefs: count total reference entries in map.
|
| Walks all type entries, summing their reference counts into D4.
| Used to find the end of reference lists (for name list offset calc).
| Called by: INITRESOURCES_CONT_3, INITRES_LOADALL, RSRCZONEINIT, FINDNEXT_ENTER, UPDRES_FULL_COMPACT (and 2 more)
RESMGR_CONT_3:
    BSR.B       RETURNS_24                      | get first type entry + ref list
    BMI.B       RESMGR_EXIT_2                   | empty map -> return
    ADDQ.W      #0x6,A3                         | skip past first type entry header
    ADD.W       D5,D4                           | accumulate this type's count
    BRA.B       RESMGR_LOOP_3                   | enter accumulation loop
| ----------------------------------------------------------
|
| RESMGR_LOOP_2 -- accumulate ref counts per type.
|
RESMGR_LOOP_2:
    ADDQ.W      #0x8,A3                         | next type entry (8 bytes)
    ADD.W       (A3),D4                         | += count from this type
RESMGR_LOOP_3:
    DBF.W       D5,RESMGR_LOOP_2                | loop through all types
RESMGR_EXIT_2:
    RTS                                         | return from RESMGR_EXIT_2
| ----------------------------------------------------------
|
| RETURNS_24 -- GetFirstType: get first type entry and its ref list.
|
| Sets up A3=type list, A2=first ref list, D3=first resType, D4=count-1.
| Returns: N flag set if type list is empty (D5 < 0).
RETURNS_24:
    BSR.B       RETURNS_23                      | A2=type list, D5=numTypes-1
    MOVE.L      (A2),D3                         | D3 = first resource type (e.g. 'DRVR')
    BSR.B       RETURNS_27                      | A2=ref list, D4=count-1
    TST.W       D5                              | empty type list?
    RTS                                         | return CCR set by TST
| ----------------------------------------------------------
|
| RETURNS_25 -- FindResID: search ref list for resource by ID.
|
| Scans the reference list entries (12 bytes each) looking for
| a resource whose ID (at ref+0) matches D2.
| Returns: A2=matching ref entry if found; branches to RESMGR_ERR if not.
RETURNS_25:
    MOVEQ.L     #0xC,D0                         | 12 = size of each reference entry
RESMGR_LOOP_4:
    CMP.W       (A2),D2                         | id match?
    ADDA.W      D0,A2                           | next ref entry (12 bytes)
    DBEQ.W      D4,RESMGR_LOOP_4                | loop until match or end
    BEQ.B       RESMGR_FOUND_3                  | match -> back up A2 and exit
    BRA.B       RESMGR_ERR                      | exhausted -> not found
| ----------------------------------------------------------
|
| RETURNS_26 -- FindResType: search type list for matching resource type.
|
| Scans the type list (8-byte entries) for a type matching D3.
| Returns: A2=matching type entry if found; branches to RESMGR_ERR if not.
| Called by: COUNTRES_LOOP, GETIND_FIND_TYPE, UNIQID_CHECK, GETRES_FIND_TYPE, GETNAMED_LOOP (and 3 more)
RETURNS_26:
    BSR.B       RETURNS_23                      | A2=type list, D5=numTypes-1
    BMI.B       RESMGR_ERR                      | empty type list -> not found
    MOVEQ.L     #0x8,D0                         | 8 = size of each type entry
RESMGR_LOOP_5:
    CMP.L       (A2),D3                         | type match?
    ADDA.W      D0,A2                           | next type entry (8 bytes)
    DBEQ.W      D5,RESMGR_LOOP_5                | loop until match or end
    BEQ.B       RESMGR_FOUND_3                  | match -> back up A2 and exit
    BRA.B       RESMGR_ERR                      | exhausted -> not found
| ----------------------------------------------------------
|
| RETURNS_27 -- GetRefList: get reference list for a type entry.
|
| Given A2 pointing to a type entry, loads the count and computes
| the absolute pointer to its reference list.
| Returns: D4=count-1, A2=pointer to first reference entry.
| Called by: GETIND_FIND_TYPE, UNIQID_CHECK, GETRES_FIND_TYPE, GETNAMED_LOOP, RETURNS_24 (and 1 more)
RETURNS_27:
    MOVE.W      0x4(A2),D4                      | D4 = count - 1
    MOVE.L      D0,-(A7)                        | save D0
    MOVEQ.L     #0x0,D0                         | clear high word for word -> long
    MOVE.W      0x6(A2),D0                      | D0 = ref list offset (16-bit)
    MOVEA.L     D0,A2                           | A2 = offset (will adjust)
    MOVE.L      (A7)+,D0                        | restore D0
    ADDA.L      A3,A2                           | A2 = type-list-base + offset (abs ptr)
    RTS                                         | return from RETURNS_27
| ----------------------------------------------------------
|
| RESMGR_FOUND_3 -- search hit: back up A2 to point at matched entry.
|
RESMGR_FOUND_3:
    SUBA.W      D0,A2                           | back up to matched entry
| RESMGR_EXIT_3: clear error code and return success.
| Called by: RESMGR_EXIT, RESMGR_FOUND_5, RESMGR_OK_3, RESMGR_CONT_16, RETURNS_28
RESMGR_EXIT_3:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (success, Z=1)
    RTS                                         | return from RESMGR_EXIT_3
| ----------------------------------------------------------
|
| RESMGR_ERR -- search miss: return "not found".
|
| Called by: VSUPERLOAD, SUPERLOAD_ERR, SUPERLOAD_CONT_5, CMP_ADD_TO_BUF, RESMGR_CONT (and 9 more)
RESMGR_ERR:
    MOVEQ.L     #-0x1,D0                        | D0 = -1 (error, N=1)
    RTS                                         | return from RESMGR_ERR
| ----------------------------------------------------------
|
| RESMGR_CONT_4/RESMGR_CONT_5/RESMGR_CONT_6 - Resource Manager trap prologue
|
| RESMGR_CONT_4: full prologue (clears ROMMapInsert, CurOnly, ResErr)
| RESMGR_CONT_5: partial prologue (clears CurOnly + ResErr, preserves ROMMapInsert)
| RESMGR_CONT_6: minimal prologue (clears ResErr only)
| Sets up a LINK frame with 50 bytes of local storage and saves registers.
| If ROMMapInsert is set, inserts ROM map into chain before searching.
| Called by: INITRESOURCES, RSRCZONEINIT, CREATERESFILE, OPENRESFILE, OPENRFPERM (and 3 more)
RESMGR_CONT_4:
    CLR.W       (ROMMapInsert).W                | clear ROMMapInsert flag
| RESMGR_CONT_5: partial prologue (clears CurOnly only).
| Called by: LOADRESOURCE, WRITERESOURCE_CONT_2, GETRESATTRS, SETRESATTRS, GETRESINFO (and 2 more)
RESMGR_CONT_5:
    CLR.B       (RMgrCurOnly).W                 | search all maps, not just current
| RESMGR_CONT_6 -- minimal prologue: clear ResErr only.
| Called by: COUNTRESOURCES, GETINDRESOURCE, COUNTTYPES, GETINDTYPE, UNIQUEID (and 2 more)
RESMGR_CONT_6:
    CLR.W       (ResErr).W                      | clear last error code
    MOVEA.L     (A7)+,A0                        | save caller's return address
    LINK        A6,#-0x32                       | 50 bytes of locals
    CLR.W       -0x1C(A6)                       | local: vRefNum = 0
    CLR.W       -0x18(A6)                       | local: spare slot = 0
    MOVE.B      (RMgrPerm).W,-0x17(A6)          | local: permission = RMgrPerm
    MOVEM.L     D1-D7/A1-A4,-(A7)               | save callee-clobbered regs
    SUBA.L      A4,A4                           | A4 = nil (no map yet)
    MOVE.L      A0,-(A7)                        | restore return address on stack
    LEA.L       0x8(A6),A0                      | A0 = caller's parameter area
    TST.B       (ROMMapInsert).W                | ROMMapInsert requested?
    BEQ.B       RESMGR_SKIP_3                   | no -> done
    MOVEQ.L     #0x0,D1                         | D1=0 (insert direction)
    BSR.B       RESMGR_CONT_7                   | splice ROM map into chain
RESMGR_SKIP_3:
    RTS                                         | return from prologue
| ----------------------------------------------------------
|
| RESMGR_CONT_7 - InsertRemoveROMMap: insert/remove ROM map in resource chain
|
| D1=0: insert ROM map between SysMap and its predecessor
| D1!=0: remove ROM map from chain (reverse the insertion)
| This allows the ROM resource fork to be searched alongside disk files.
| Also swaps ResLoad/TmpResLoad so ROM resources respect the load flag.
RESMGR_CONT_7:
    MOVEM.L     D0/A0-A2,-(A7)                  | save working regs
    MOVEA.L     (SysMapHndl).W,A1               | A1 = system map handle (the "target")
    MOVEA.L     (ROMMapHandle).W,A2             | A2 = ROM map handle (the "patch")
    CMPA.L      A1,A2                           | already in chain (==)?
    BEQ.B       RESMGR_CONT_10                  | yes -> nothing to do
    MOVE.W      (CurMap).W,D0                   | save current map refnum
    TST.L       D1                              | direction: 0 = insert, !=0 = remove
    BEQ.B       RESMGR_CONT_8                   | insert -> CONT_8
    EXG         A1,A2                           | remove: swap target/patch
    CMPI.W      #0x1,D0                         | CurMap == ROM (refnum 1)?
    BNE.B       RESMGR_NO                       | no -> skip
    MOVE.W      (SysMap).W,(CurMap).W           | yes -> CurMap = SysMap
    BRA.B       RESMGR_NO                       | walk chain
| ----------------------------------------------------------
|
| RESMGR_CONT_8 -- inserting ROM map: update CurMap if it points to SysMap.
|
RESMGR_CONT_8:
    CMP.W       (SysMap).W,D0                   | CurMap == SysMap?
    BNE.B       RESMGR_NO                       | no -> skip
    MOVE.W      #0x1,(CurMap).W                 | yes -> CurMap = ROM (1)
RESMGR_NO:
    MOVEA.L     (TopMapHndl).W,A0               | A0 = top of chain (start search)
RESMGR_CONT_9:
    MOVEA.L     (A0),A0                         | A0 = deref'd current map
    MOVE.L      0x10(A0),D0                     | D0 = next-map link
    BEQ.B       RESMGR_OK_2                     | end of chain -> patch TopMapHndl
    CMP.L       A1,D0                           | next is target (A1)?
    BEQ.B       RESMGR_OK                       | yes -> splice
    MOVEA.L     D0,A0                           | advance to next map handle
    BRA.B       RESMGR_CONT_9                   | continue search
| ----------------------------------------------------------
|
| RESMGR_OK -- splice: replace A1 with A2 in predecessor's next link.
|
RESMGR_OK:
    MOVE.L      A2,0x10(A0)                     | predecessor.nextMap = A2
    BRA.B       RESMGR_DONE                     | finalize
| ----------------------------------------------------------
|
| RESMGR_OK_2 -- target was TopMapHndl: replace it.
|
RESMGR_OK_2:
    CMPA.L      (TopMapHndl).W,A1               | TopMapHndl was target?
    BNE.B       RESMGR_DONE                     | no -> nothing to patch
    MOVE.L      A2,(TopMapHndl).W               | yes -> TopMapHndl = A2
RESMGR_DONE:
    MOVEA.L     (ROMMapHandle).W,A0             | A0 = ROM map handle
    MOVEA.L     (A0),A0                         | A0 = deref'd ROM map block
    MOVE.L      (SysMapHndl).W,0x10(A0)         | ROM.nextMap = SysMap (link below)
    MOVE.B      (ResLoad).W,D0                  | swap ResLoad <-> TmpResLoad
    MOVE.B      (TmpResLoad).W,(ResLoad).W      | so ROM searches respect the flag
    MOVE.B      D0,(TmpResLoad).W               | (caller restores at epilogue)
RESMGR_CONT_10:
    MOVEM.L     (A7)+,D0/A0-A2                  | restore working regs
    RTS                                         | return from RESMGR_CONT_7
| ----------------------------------------------------------
|
| RESMGR_EXIT_4-RESMGR_EXIT_6 - trap epilogues with different parameter byte counts
|
| Each sets D0 to the number of parameter bytes to pop from caller's
| stack frame before returning. Falls into RESMGR_CONT_11 common epilogue.
RESMGR_EXIT_4:
    MOVEQ.L     #0x6,D0                         | D0 = 6 (StdSixExit pop count)
    BRA.B       RESMGR_CONT_11                  | -> common epilogue
| RESMGR_EXIT_5: pop 4 bytes (StdFourExit).
| Called by: CREATERES_EXIT, OPENRES_EXIT, SETRESFILEATTRS_EXIT, COUNTRES_NEXTMAP, UNIQID_NEXTMAP (and 8 more)
RESMGR_EXIT_5:
    MOVEQ.L     #0x4,D0                         | D0 = 4 (StdFourExit pop count)
    BRA.B       RESMGR_CONT_11                  | -> common epilogue
| RESMGR_ERR_2: pop 2 bytes (StdTwoExit).
| Called by: UPDRES_CHECK_CHG, USERESFILE, GETRESFILEATTRS, STDMAPENTRY_ERR, UPDATERESFILE (and 2 more)
RESMGR_ERR_2:
    MOVEQ.L     #0x2,D0                         | D0 = 2 (StdTwoExit pop count)
    BRA.B       RESMGR_CONT_11                  | -> common epilogue
| ----------------------------------------------------------
|
| RESMGR_EXIT_6/RESMGR_CONT_11 - common Resource Manager trap epilogue.
|
| Removes ROM map from chain if it was inserted, restores globals,
| then falls into the stack-frame teardown at RESMGR_SKIP_4.
| If ResErr != 0 and ResErrProc set, calls error handler before return.
RESMGR_EXIT_6:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (no params to pop)
| RESMGR_CONT_11: common epilogue body.
| Called by: RESMGR_SKIP_2, RESMGR_EXIT_4, RESMGR_EXIT_5, RESMGR_ERR_2, GETRESINFO_EMPTY_3 (and 2 more)
RESMGR_CONT_11:
    TST.B       (ROMMapInsert).W                | ROM map was inserted?
    BEQ.B       RESMGR_SKIP_4                   | no -> skip removal
    MOVEQ.L     #-0x1,D1                        | D1 = -1 (remove direction)
    BSR.W       RESMGR_CONT_7                   | unsplice ROM map from chain
RESMGR_SKIP_4:
    CLR.B       (RMgrCurOnly).W                 | reset CurOnly flag
    CLR.W       (ROMMapInsert).W                | reset ROMMapInsert flag
    CLR.B       (RMgrPerm).W                    | reset permission byte
    MOVEM.L     (A7)+,D1-D7/A1-A4               | restore callee-saved regs
    UNLK        A6                              | discard local frame
    MOVEA.L     (A7)+,A0                        | A0 = caller's return address
    ADDA.L      D0,A7                           | pop D0 bytes of params
    MOVE.L      A0,-(A7)                        | restore return address on stack
    SUBA.L      A0,A0                           | A0 = nil (set up for ResErrProc)
    MOVE.W      (ResErr).W,D0                   | D0 = current ResErr
    BEQ.B       RESMGR_ERR_3                    | no error -> skip dispatch
    MOVE.L      (ResErrProc).W,-(A7)            | push ResErrProc address
    BNE.B       RESMGR_ERR_3                    | non-nil -> RTS dispatches to it
    ADDQ.W      #0x4,A7                         | nil -> drop pushed value
RESMGR_ERR_3:
    RTS                                         | RTS to caller (or ResErrProc)
| ----------------------------------------------------------
|
| RESMGR_CONT_12 - FindResByHandle: find resource map entry for a given handle
|
| Given A1=resource handle, searches all maps for the reference entry
| whose handle field (ref+8) matches. Uses RMgrLastResHand cache for
| fast path. Returns: A2=ref entry, A3=type list, A4=map handle,
| D3=resType, D4=index, D5=type index, D6=refNum. Z=1 if found.
RESMGR_CONT_12:
    MOVE.L      A1,D0                           | test handle for nil
    BEQ.W       RESMGR_ERR                      | nil -> error
    CMPA.L      (RMgrLastResHand).W,A1          | matches cached last handle?
    BEQ.B       RESMGR_OK_3                     | yes -> fast path via cache
RESMGR_CONT_13:
    BSR.W       RETURNS_20                      | begin map chain traversal
    MOVE.L      A0,-(A7)                        | save caller's return ptr
RESMGR_FOUND_4:
    BSR.W       RETURNS_24                      | get first type + ref list
    BMI.B       RESMGR_EMPTY                    | empty map -> next map
    MOVEA.L     A3,A0                           | A0 = type list base
    ADDQ.W      #0x8,A0                         | A0 -> first type entry's count field
RESMGR_LOOP_6:
    ADDQ.W      #0x2,A0                         | advance through type entries
RESMGR_LOOP_7:
    ADDQ.W      #0x8,A2                         | next 12-byte ref entry (skip first 8)
    CMPA.L      (A2)+,A1                        | handle field matches A1?
    DBEQ.W      D4,RESMGR_LOOP_7                | loop until match or end
    BEQ.B       RESMGR_FOUND_5                  | matched -> finalize
    MOVE.L      (A0)+,D3                        | next type code
    MOVE.W      (A0)+,D4                        | next type's count
    DBF.W       D5,RESMGR_LOOP_6                | loop through types
RESMGR_EMPTY:
    BSR.W       RETURNS_22                      | next map
    BEQ.B       RESMGR_FOUND_4                  | found -> search it
    MOVEA.L     (A7)+,A0                        | end of chain -> restore ret ptr
    BRA.W       RESMGR_ERR                      | -> not found
| ----------------------------------------------------------
|
| RESMGR_FOUND_5 - handle matched: back up A2 to ref entry start and cache
|
RESMGR_FOUND_5:
    SUBA.W      #0xC,A2                         | back up A2 to start of ref entry
    BSR.B       RESMGR_CONT_14                  | cache search state
    MOVEA.L     (A7)+,A0                        | restore caller's return ptr
    BRA.W       RESMGR_EXIT_3                   | -> success exit
| ----------------------------------------------------------
|
| RESMGR_OK_3 - RestoreCachedSearch: fast path using cached search state
|
| Restores the last search position from RMgr globals. If the handle
| at the cached ref entry still matches, returns immediately.
| Otherwise invalidates the cache and does a full search.
RESMGR_OK_3:
    MOVEM.L     (RMgrHiVars_LastResType),D3/A1-A4 | restore D3/A1-A4 from cache
    MOVEM.W     (0xB94),D4-D6                   | restore D4-D6 from cache
    ADDA.L      (A4),A2                         | A2 += map base (was relative)
    ADDA.L      (A4),A3                         | A3 += map base (was relative)
    CMPA.L      0x8(A2),A1                      | cached ref still has our handle?
    BEQ.W       RESMGR_EXIT_3                   | yes -> success
    CLR.L       (RMgrLastResHand).W             | no -> invalidate cache
    BRA.B       RESMGR_CONT_13                  | -> full search
| ----------------------------------------------------------
|
| RESMGR_CONT_14/RESMGR_CONT_15 - CacheSearchState: save current search position
|
| Converts A2 (ref ptr) and A3 (type list) to relative offsets from
| the map base, stores them along with D3-D6/A1/A4 in RMgr globals.
| RESMGR_CONT_14 also resets the sequential index counter.
RESMGR_CONT_14:
    MOVE.W      (MinusOne).W,(RMgrNextResIndex).W | reset sequential index counter
| RESMGR_CONT_15 -- cache search state in RMgr globals (no index reset).
RESMGR_CONT_15:
    MOVE.L      (A4),D0                         | D0 = deref'd map handle (base addr)
    SUBA.L      D0,A2                           | A2 -> relative to map base
    SUBA.L      D0,A3                           | A3 -> relative to map base
    MOVEM.L     D3/A1-A4,(RMgrHiVars_LastResType) | cache D3/A1-A4 to globals
    MOVEM.W     D4-D6,(0xB94)                   | cache D4-D6 to globals
    ADDA.L      D0,A2                           | restore A2 to absolute
    ADDA.L      D0,A3                           | restore A3 to absolute
    RTS                                         | return from RESMGR_CONT_15
| ----------------------------------------------------------
|
| RESMGR_CONT_16 - GetResName: get pointer to resource name string
|
| Reads the name offset from the reference entry (ref+2).
| If -1, the resource has no name; returns an empty Pascal string.
| Otherwise computes name list base + offset to return name pointer.
RESMGR_CONT_16:
    MOVE.W      0x2(A2),D0                      | D0 = name offset (or -1)
    BMI.B       GETRESNAME_EMPTY                | -1 -> no name path
    MOVEA.L     (A4),A0                         | A0 = deref'd map block
    ADDA.W      0x1A(A0),A0                     | A0 += offset to name list
    ADDA.W      D0,A0                           | A0 += this entry's name offset
    BRA.W       RESMGR_EXIT_3                   | -> success
| GETRESNAME_EMPTY: no-name path -- return ptr to empty Pascal string in ROM.
GETRESNAME_EMPTY:
    LEA.L       RMGR(PC),A0                     | A0 = empty string template (zero-len)
    BRA.W       RESMGR_ERR                      | -> error/empty exit
| ----------------------------------------------------------
|
| RETURNS_28 - NextRefEntry: advance to next reference entry
|
| Advances A2 by 12 bytes (one ref entry). If the current type's
| ref list is exhausted, moves to the next type in the type list.
| Returns: Z=1 if valid entry found; N=1 if no more entries.
RETURNS_28:
    ADDA.W      #0xC,A2                         | next 12-byte ref entry
    SUBQ.W      #0x1,D4                         | refs left in this type?
    BPL.W       RESMGR_EXIT_3                   | yes -> success
    SUBQ.W      #0x1,D5                         | types left?
    BMI.W       RESMGR_ERR                      | no -> not found
    MOVE.W      (A3),D0                         | D0 = total numTypes - 1
    SUB.W       D5,D0                           | D0 = type index (already consumed)
    ASL.W       #0x3,D0                         | D0 *= 8 (entry size)
    MOVE.L      0x2(A3,D0.W),D3                 | D3 = next type code
    MOVE.W      0x6(A3,D0.W),D4                 | D4 = next type's count
    MOVEQ.L     #0x1,D0                         | D0 = 1 (CCR Z=0)
    RTS                                         | return from RETURNS_28
| ----------------------------------------------------------
|
| RESMGR_OK_4 - LoadROMResource: load resource from ROM (no file I/O)
|
| For ROM map resources, the data offset is relative to ROMBase.
| Creates a "fake" handle by using HandleZone to get the zone,
| then computing a master pointer that points directly into ROM.
RESMGR_OK_4:
    MOVE.L      A1,-(A7)                        | save A1
    MOVE.L      0x4(A2),D0                      | D0 = ref's offset+attrs
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit data offset
    ADD.L       (ROMBase).W,D0                  | D0 += ROMBase = ROM data ptr
    MOVEA.L     D0,A1                           | A1 = data pointer in ROM
    MOVEA.L     (ROMMapHandle).W,A0             | A0 = ROM map handle
    _HandleZone                                 | A0 = zone owning ROM map handle
    MOVE.L      -0x4(A1),D0                     | D0 = ROM data length prefix (BE)
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit length
    ADDA.L      D0,A0                           | A0 = zone-relative ROM data ptr (faux master)
    MOVE.L      A0,0x8(A2)                      | ref.handle = faux handle ptr
    TST.B       (ResLoad).W                     | ResLoad enabled?
    BEQ.B       RESMGR_EMPTY_2                  | no -> leave ref pointing into ROM
    MOVE.L      A1,(A0)                         | publish ROM data ptr at faux master
    BSR.W       CHECKLOAD_CONT_3                | apply attribute bits to block header
RESMGR_EMPTY_2:
    MOVEA.L     (A7)+,A1                        | restore A1
    RTS                                         | return from RESMGR_OK_4
| ----------------------------------------------------------
|
| P_CheckLoad / VCHECKLOAD -- ensure a resource's data is in memory.
|
| Indirects through jCheckLoad ($7F0). Default is VCHECKLOAD which
| dispatches: ROM map -> RESMGR_OK_4 (faux handle into ROM), else
| reads data from disk if ResLoad is set, else returns empty handle.
| Honours the resSysHeap attribute (allocates from SysZone if set).
| Called during boot (22,904 times in 30s trace).
P_CheckLoad:
    MOVEA.L     (0x7F0).W,A0                    | A0 = jCheckLoad vector
    JMP         (A0)                            | tail-call current implementation
VCHECKLOAD:
    MOVE.B      0x4(A2),D1                      | D1 = ref attribute byte
    CMPA.L      (ROMMapHandle).W,A4             | resource is in ROM map?
    BEQ.B       RESMGR_OK_4                     | yes -> faux ROM handle
    MOVE.L      (TheZone).W,-(A7)               | save current zone
    BTST        #0x6,D1                         | resSysHeap bit set?
    BEQ.B       CHECKLOAD_NO                    | no -> use current zone
    MOVE.L      (SysZone).W,(TheZone).W         | yes -> allocate from SysZone
CHECKLOAD_NO:
    MOVEA.L     0x8(A2),A0                      | A0 = ref's handle field
    SUBA.L      (A4),A3                         | A3 -> offset (handle may move)
    TST.B       (ResLoad).W                     | ResLoad enabled?
    BEQ.B       CHECKLOAD_EMPTY                 | no -> empty-handle path
    MOVE.L      A0,D0                           | already loaded?
    BNE.B       CHECKLOAD_OK                    | yes -> realloc/reload existing
    BSR.B       CHECKLOAD_ALLOC_HANDLE          | no -> compute size, prep _NewHandle
    _NewHandle                                  | allocate new handle
    BEQ.B       CHECKLOAD_CONT_2                | success -> store + read
    BRA.B       CHECKLOAD_ERR                   | failure -> error
| CHECKLOAD_ALLOC_HANDLE: helper -- compute resource data size + reserve memory if locked.
CHECKLOAD_ALLOC_HANDLE:
    BSR.B       CHECKLOAD_CONT_5                | read data length from file -> D0
    MOVE.L      D0,D2                           | D2 = data length
    SUBA.L      (A4),A2                         | A2 -> offset (handle may move)
    BTST        #0x4,D1                         | resLocked attr set?
    BEQ.B       CHECKLOAD_SKIP                  | no -> skip reserve
    _ResrvMem                                   | reserve memory at low end of zone
CHECKLOAD_SKIP:
    MOVE.L      D2,D0                           | D0 = size for caller
    RTS                                         | return from CHECKLOAD_ALLOC_HANDLE
| ----------------------------------------------------------
|
| CHECKLOAD_OK -- handle exists; reload if purged.
|
| Called during boot (22,312 times in 30s trace).
CHECKLOAD_OK:
    TST.L       (A0)                            | handle's master = nil (purged)?
    BNE.B       CHECKLOAD_ERR_2                 | not purged -> already loaded
    BSR.B       CHECKLOAD_ALLOC_HANDLE          | compute size + reserve
    _ReallocHandle                              | re-allocate purged handle
    BMI.B       CHECKLOAD_ERR                   | failed -> error
CHECKLOAD_CONT_2:
    ADDA.L      (A4),A2                         | restore A2 to absolute
    MOVE.L      A0,0x8(A2)                      | ref.handle = new handle
    BSR.B       CHECKLOAD_CONT_6                | read data into handle
    BSR.B       CHECKLOAD_CONT_3                | apply attribute bits to block header
    MOVE.W      (ResErr).W,D0                   | check read result
    BEQ.B       CHECKLOAD_ERR_2                 | success -> exit
    SUBA.L      (A4),A2                         | A2 -> offset (for error tail)
CHECKLOAD_ERR:
    MOVE.W      D0,(ResErr).W                   | save error code
    SUBA.L      A0,A0                           | A0 = nil (no handle)
    BRA.B       CHECKLOAD_EXIT                  | -> exit
| ----------------------------------------------------------
|
| CHECKLOAD_EMPTY -- ResLoad off path: return empty handle.
|
| Called during boot.
CHECKLOAD_EMPTY:
    MOVE.L      A0,D0                           | already have a handle?
    BNE.B       CHECKLOAD_ERR_2                 | yes -> exit (caller untouched)
    SUBA.L      (A4),A2                         | A2 -> offset (handle may move)
    _NewEmptyHandle                             | allocate empty handle
CHECKLOAD_EXIT:
    ADDA.L      (A4),A2                         | restore A2 to absolute
CHECKLOAD_ERR_2:
    MOVE.L      A0,D0                           | A0 = nil (error)?
    BEQ.B       CHECKLOAD_SKIP_2                | yes -> skip store
    MOVE.L      A0,0x8(A2)                      | ref.handle = A0
CHECKLOAD_SKIP_2:
    ADDA.L      (A4),A3                         | restore A3 to absolute
    MOVE.L      (A7)+,(TheZone).W               | restore zone
    RTS                                         | return from CHECKLOAD_EXIT
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_3 -- map ref attribute bits to Memory Manager handle state.
|
| Translates the 4 high attribute bits (resLocked, resPurgeable etc.)
| from D1 into the corresponding HFlags via _HSetState. Encodes:
|  - resLocked (bit 4) -> handleLocked
|  - resPurgeable (bit 5) -> handlePurgeable
| Note: resSysHeap (bit 6) is consumed earlier (selects zone).
CHECKLOAD_CONT_3:
    LSL.B       #0x3,D1                         | shift attr bits 4,5 to MSB
    BPL.B       CHECKLOAD_NO_2                  | resLocked clear -> 0xFFFFFF80
    MOVEQ.L     #-0x7F,D1                       | resLocked set -> 0xFFFFFF81 base
    BRA.B       CHECKLOAD_CONT_4                | -> apply
CHECKLOAD_NO_2:
    MOVEQ.L     #-0x80,D1                       | base = 0xFFFFFF80 (no flags yet)
CHECKLOAD_CONT_4:
    ROXR.B      #0x2,D1                         | rotate purgeable bit into position
    _HGetState                                  | D0 = current handle flags
    ANDI.B      #0x1F,D0                        | preserve low 5 bits (block header)
    OR.B        D1,D0                           | OR in attribute bits
    _HSetState                                  | publish new handle state
    RTS                                         | return from CHECKLOAD_CONT_3
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_5 -- read 4-byte data length prefix from file.
|
| Reads the 4-byte big-endian data length stored at the resource's
| offset in the data fork. Returns the length in D0.
| Called during boot.
CHECKLOAD_CONT_5:
    MOVEM.L     D1-D2/A0-A1,-(A7)               | save working regs
    BSR.B       CHECKLOAD_CONT_7                | compute file offset, mark not-changed
    SUBQ.L      #0x4,A7                         | reserve 4-byte read buffer
    MOVE.L      A7,D1                           | D1 = buffer addr
    MOVEQ.L     #0x4,D0                         | D0 = 4 bytes
    BSR.B       CHECKLOAD_CONT_10               | _Read 4 bytes into buffer
    MOVE.L      (A7)+,D0                        | D0 = length read
    MOVEM.L     (A7)+,D1-D2/A0-A1               | restore working regs
    RTS                                         | return from CHECKLOAD_CONT_5
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_6 -- read resource data into handle's buffer.
|
| Reads D0 bytes (already known) from data fork at resource's offset
| into the buffer at *0x8(A2). Caller must have allocated/sized handle.
| Called during boot.
CHECKLOAD_CONT_6:
    MOVEM.L     D0-D2/A0-A1,-(A7)               | save working regs
    MOVE.L      D2,D0                           | D0 = data length
    BSR.B       CHECKLOAD_CONT_7                | recompute file offset
    ADDQ.L      #0x4,D2                         | skip past length prefix
    MOVE.L      (A1),D1                         | D1 = handle's data buffer ptr
    BSR.B       CHECKLOAD_CONT_10               | _Read D0 bytes into buffer
CHECKLOAD_EXIT_2:
    MOVEM.L     (A7)+,D0-D2/A0-A1               | restore working regs
    RTS                                         | return from CHECKLOAD_CONT_6
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_7 -- compute resource data file offset, mark "not changed".
|
| Reads the 24-bit data offset from ref+4, masks attribute bits,
| adds data fork base to give absolute file position. Also clears
| resChanged bit (0x02) so subsequent updates don't re-flag.
| Returns: D2 = absolute file offset, A1 = handle field ptr.
| Called during boot.
CHECKLOAD_CONT_7:
    ANDI.B      #0xFD,0x4(A2)                   | clear resChanged bit (0x02)
    MOVEA.L     (A4),A0                         | A0 = deref'd map handle
    MOVE.L      0x4(A2),D2                      | D2 = ref's offset+attrs
    AND.L       (Lo3Bytes).W,D2                 | mask to 24-bit offset
    ADD.L       (A0),D2                         | D2 += data fork base
    MOVEA.L     0x8(A2),A1                      | A1 = ref's handle field
    RTS                                         | return from CHECKLOAD_CONT_7
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_8
|
| Called during boot.
CHECKLOAD_CONT_8:
    MOVEM.L     D0-D2/A0-A1,-(A7)               | save working regs
    BSR.B       CHECKLOAD_CONT_7                | A1 = ref handle, D2 = file offset
    MOVEA.L     A1,A0                           | A0 = handle
    _GetHandleSize                              | D0 = data length (or err)
    TST.L       D0                              | error ?
    BPL.B       CHECKLOAD_OK_2                  | no, length is valid
    MOVEQ.L     #0x0,D0                         | yes, treat as zero length
CHECKLOAD_OK_2:
    MOVE.L      D0,-(A7)                        | save data length
    MOVE.L      A7,D1                           | D1 = ptr to length on stack
    MOVEQ.L     #0x4,D0                         | D0 = 4 bytes (length prefix)
    BSR.B       CHECKLOAD_EMPTY_2               | _Write 4-byte length prefix
    ADDQ.L      #0x4,D2                         | advance file pos past prefix
    MOVE.L      (A1),D1                         | D1 = data buffer ptr
    MOVE.L      (A7)+,D0                        | D0 = data length
    BSR.B       CHECKLOAD_EMPTY_2               | _Write data
    BRA.B       CHECKLOAD_EXIT_2                | restore regs and return
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_9 -- build IOParam block in local frame for FS call.
|
| Populates the IOParam block at -0x1A(A6) with refnum, buffer ptr,
| byte count, posMode = 1 (fsFromStart), and posOffset. Returns A0
| pointing to the param block start (-0x32(A6)) for trap dispatch.
| Called during boot.
CHECKLOAD_CONT_9:
    LEA.L       -0x1A(A6),A0                    | A0 -> ioRefNum (I/O block +$18 = -$1A(A6))
    MOVE.W      D6,(A0)+                        | ioParam.ioRefNum = D6
    ADDQ.W      #0x6,A0                         | skip ioVersNum, ioPermssn, ioMisc
    MOVE.L      D1,(A0)+                        | ioParam.ioBuffer = D1
    MOVE.L      D0,(A0)+                        | ioParam.ioReqCount = D0
    ADDQ.W      #0x4,A0                         | skip ioActCount
    MOVE.W      #0x1,(A0)+                      | ioParam.ioPosMode = 1 (fsFromStart)
    MOVE.L      D2,(A0)+                        | ioParam.ioPosOffset = D2
    LEA.L       -0x32(A6),A0                    | A0 = param block base for trap
    RTS                                         | return from CHECKLOAD_CONT_9
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_10 -- _Read wrapper.
|
| Stack: D0=byteCount, D1=bufferPtr, D2=fileOffset, D6=refnum (unchanged).
| Saves regs and converts A2/A3 to relative offsets, builds IOParam,
| issues _Read trap, restores state.
| Called during boot.
CHECKLOAD_CONT_10:
    BSR.B       CHECKLOAD_EXIT_4                | save regs, A2/A3 -> relative
    BSR.B       CHECKLOAD_CONT_9                | build IOParam in local frame
    _Read                                       | read data from resource file
    BRA.B       CHECKLOAD_ERR_3                 | store error, restore, return
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_11 -- _Write at file position 0 (resource file header).
|
| Called during boot.
CHECKLOAD_CONT_11:
    MOVEQ.L     #0x0,D2                         | D2 = 0 (write at start of file)
| CHECKLOAD_EMPTY_2 -- _Write wrapper at given file offset.
| Called by: CHECKLOAD_OK_2, CREATERES_CHKEOF, CMP_NEXT_RES, CMP_WRITE_MAP, CMP_FLUSH_BUF
CHECKLOAD_EMPTY_2:
    BSR.B       CHECKLOAD_EXIT_4                | save regs, A2/A3 -> relative
    BSR.B       CHECKLOAD_CONT_9                | build IOParam in local frame
    _Write                                      | write data to resource file
CHECKLOAD_ERR_3:
    MOVE.W      D0,(ResErr).W                   | save trap result
CHECKLOAD_EXIT_3:
    ADDA.L      (A4),A3                         | restore A3 to absolute
    ADDA.L      (A4),A2                         | restore A2 to absolute
    MOVEM.L     (A7)+,D0-D1/A0-A1               | restore working regs
    RTS                                         | return from CHECKLOAD_EXIT_3
| ----------------------------------------------------------
|
| CHECKLOAD_EXIT_4 -- prologue helper for CHECKLOAD_CONT_10/EMPTY_2.
|
| Saves D0-D1/A0-A1 on stack, swaps the caller's return address with
| A1 (so RTS goes back through the wrapper), and converts A2/A3 to
| map-relative offsets (since handle may move during trap).
| Called during boot.
CHECKLOAD_EXIT_4:
    MOVEM.L     D0-D1/A0,-(A7)                  | save D0-D1/A0
    MOVEA.L     0xC(A7),A0                      | A0 = caller's return addr
    MOVE.L      A1,0xC(A7)                      | replace ret addr with A1
    SUBA.L      (A4),A3                         | A3 -> offset (handle may move)
    SUBA.L      (A4),A2                         | A2 -> offset (handle may move)
    JMP         (A0)                            | tail-call into caller's body
| ----------------------------------------------------------
|
| CHECKLOAD_OK_3 -- _SetEOF wrapper for resource fork.
|
| Sets the resource fork's EOF to the maximum of (data fork end +
| map length) and (map offset + map length). Used to ensure file
| size on disk reflects the in-memory map state.
| Called during boot.
CHECKLOAD_OK_3:
    BSR.B       CHECKLOAD_EXIT_4                | save regs, A2/A3 -> relative
    BSR.W       CHECKLOAD_OK_4                  | check if file is read-only
    BNE.B       CHECKLOAD_EXIT_3                | yes -> exit (no SetEOF)
    BSR.B       CHECKLOAD_CONT_9                | build IOParam block
    BSR.B       CHECKLOAD_CONT_12               | D0 = max(data end, map end)
    MOVE.L      D0,0x1C(A0)                     | ioParam.ioMisc = new EOF
    _SetEOF                                     | set logical EOF
    BRA.B       CHECKLOAD_ERR_3                 | save result, restore, return
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_12 -- compute total file size from map header.
|
| Reads the four 4-byte fields at the start of the map (data offset,
| map offset, data length, map length) and returns the maximum of
| (data offset + data length) and (map offset + map length).
| Called during boot.
CHECKLOAD_CONT_12:
    MOVEM.L     D1/A1,-(A7)                     | save D1/A1
    MOVEA.L     (A4),A1                         | A1 = deref'd map block
    MOVE.L      (A1)+,D0                        | D0 = data fork base offset
    MOVE.L      (A1)+,D1                        | D1 = map fork offset
    ADD.L       (A1)+,D0                        | D0 += data fork length
    ADD.L       (A1)+,D1                        | D1 += map length
    CMP.L       D1,D0                           | data end >= map end?
    BPL.B       CHECKLOAD_CONT_13               | yes -> use D0
    MOVE.L      D1,D0                           | no -> use D1
CHECKLOAD_CONT_13:
    MOVEM.L     (A7)+,D1/A1                     | restore D1/A1
    RTS                                         | return from CHECKLOAD_CONT_13
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_14 -- get on-disk size of changed resource.
|
| Reads handle size of the resource (the in-memory data length) and
| adds 4 for the length prefix. Returns D0 = D1 = total disk bytes.
| Called during boot.
CHECKLOAD_CONT_14:
    MOVEA.L     0x8(A2),A0                      | A0 = ref's handle
    _GetHandleSize                              | D0 = data length in memory
    ADDQ.L      #0x4,D0                         | + 4 bytes for length prefix
    MOVE.L      D0,D1                           | D1 = total
    RTS                                         | return from CHECKLOAD_CONT_14
| ----------------------------------------------------------
|
| CHECKLOAD_NO_3 -- compute available space at ref's current offset.
|
| Returns D0 = available bytes between this ref's data offset and the
| next resource (or end of data fork). Used by CHECKLOAD_CONT_16 to
| decide if a changed resource can stay in place or must be appended.
| Called during boot.
CHECKLOAD_NO_3:
    MOVEM.L     D1/D7/A0-A2,-(A7)               | save working regs
    MOVE.L      0x4(A2),D7                      | D7 = ref's offset+attrs
    AND.L       (Lo3Bytes).W,D7                 | mask to 24-bit data offset
    MOVEA.L     (A4),A0                         | A0 = deref'd map block
    MOVE.L      0x4(A0),D0                      | D0 = map fork offset
    SUB.L       (A0),D0                         | D0 = map - data base
    MOVEA.L     D0,A1                           | A1 = data fork length
    BMI.B       CHECKLOAD_FIND_NEXT             | underflow -> use total
    CMPA.L      D7,A1                           | data length <= ref offset?
    BMI.B       CHECKLOAD_FIND_NEXT             | yes -> use total
    BSR.W       FINDNEXT_FROM_CUR               | find next resource after this
    BMI.B       CHECKLOAD_NEXT                  | none -> use end of data fork
    CMPA.L      D0,A1                           | next is past data length?
    BPL.B       CHECKLOAD_NEXT_2                | yes -> use D0 - D7
CHECKLOAD_NEXT:
    MOVE.L      A1,D0                           | D0 = data length
    BRA.B       CHECKLOAD_CONT_15               | -> finalize
CHECKLOAD_FIND_NEXT:
    BSR.W       FINDNEXT_FROM_CUR               | find next resource
    BPL.B       CHECKLOAD_NEXT_2                | found -> D0 = next offset
    BSR.B       CHECKLOAD_CONT_12               | else D0 = total file size
    SUB.L       (A0),D0                         | D0 -= data base = data span
CHECKLOAD_CONT_15:
    SUB.L       D7,D0                           | D0 -= our offset = available
    MOVEQ.L     #-0x1,D7                        | D7 = -1 (sentinel)
    BRA.B       CHECKLOAD_EXIT_5                | -> exit
| ----------------------------------------------------------
|
| CHECKLOAD_NEXT_2 -- gap-to-next computation.
|
| Called during boot.
CHECKLOAD_NEXT_2:
    SUB.L       D7,D0                           | D0 = next - our offset
CHECKLOAD_EXIT_5:
    MOVEM.L     (A7)+,D1/D7/A0-A2               | restore working regs
    RTS                                         | return from CHECKLOAD_NO_3
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_16 -- write changed resource (in-place if it fits).
|
| If changed data fits in current slot, write in place via CHECKLOAD_OK_3.
| Otherwise fall through to CHECKLOAD_CONT_17 to append at end of data fork.
| Called during boot.
CHECKLOAD_CONT_16:
    BSR.B       CHECKLOAD_CONT_14               | D1 = new disk size (data + 4-byte prefix)
    BSR.B       CHECKLOAD_NO_3                  | D0 = available space at current offset
    CMP.L       D0,D1                           | does new data fit in existing slot?
    BLE.W       CHECKLOAD_OK_3                  | yes -> write in place + SetEOF
| CHECKLOAD_CONT_17 -- write resource data at end of data fork.
CHECKLOAD_CONT_17:
    BSR.B       CHECKLOAD_CONT_14               | D1 = new disk size (data + 4-byte prefix)
    BSR.B       CHECKLOAD_CONT_12               | D0 = total file size
    MOVEA.L     (A4),A0                         | A0 = deref'd map block
    SUB.L       (A0),D0                         | D0 -= data fork base
    MOVE.B      0x4(A2),-(A7)                   | save attribute byte
    MOVE.L      D0,0x4(A2)                      | ref.offset = D0 (new offset)
    MOVE.B      (A7)+,0x4(A2)                   | restore attribute byte
    ADD.L       D1,D0                           | D0 += disk size
    MOVE.L      D0,0x8(A0)                      | map.dataLength = new end
    ORI.B       #0x60,0x16(A0)                  | set mapChanged + mapCompact
    BRA.W       CHECKLOAD_OK_3                  | -> write + SetEOF
| ----------------------------------------------------------
|
| CHECKLOAD_OK_4 -- test mapReadOnly bit (0x80 of map attrs).
|
| Returns Z=1 (BEQ) if writable, Z=0 if read-only.
| Called during boot.
CHECKLOAD_OK_4:
    MOVEA.L     (A4),A0                         | A0 = deref'd map block
    BTST        #0x7,0x16(A0)                   | mapReadOnly bit?
    RTS                                         | return CCR set by BTST
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_18 -- pre-grow map handle by 280 bytes for new entry.
|
| Probes the map handle by growing it 280 bytes (0x118), then shrinks
| back. If grow succeeds and file is writable, also extends the file
| via _SetEOF by (handle_size + new_resource_size) bytes. Used before
| AddResource so map and file have room.
| Called during boot.
CHECKLOAD_CONT_18:
    BSR.W       CHECKLOAD_EXIT_4                | save regs, A2/A3 -> relative
    MOVE.L      D2,-(A7)                        | save D2
    MOVEQ.L     #0x46,D1                        | D1 = 0x46
    ASL.W       #0x2,D1                         | D1 = 0x118 (280 bytes probe)
    MOVEA.L     A4,A0                           | A0 = map handle
    _GetHandleSize                              | D0 = current map size
    MOVE.L      D0,D2                           | D2 = current size (saved)
    ADD.L       D1,D0                           | D0 += 280
    _SetHandleSize                              | grow map by 280 bytes
    EXG         D0,D2                           | D2 = grow result, D0 = original size
    _SetHandleSize                              | shrink back to original
    MOVE.W      D2,D0                           | D0 = grow result
    BMI.B       CHECKLOAD_ERR_4                 | grow failed -> error
    BSR.B       CHECKLOAD_OK_4                  | file read-only?
    BNE.B       CHECKLOAD_ERR_4                 | yes -> error
    MOVE.L      A1,D0                           | A1 = caller's handle (or nil)
    BEQ.B       CHECKLOAD_SKIP_3                | nil -> skip _GetHandleSize
    MOVEA.L     A1,A0                           | A0 = handle to size
    _GetHandleSize                              | D0 = caller's resource size
    MOVE.L      D0,D2                           | save (for error path)
    BMI.B       CHECKLOAD_ERR_4                 | invalid -> error
    ADD.L       D0,D1                           | D1 += resource size
CHECKLOAD_SKIP_3:
    BSR.W       CHECKLOAD_CONT_9                | build IOParam block
    LEA.L       0x1C(A0),A1                     | A1 = ioParam.ioMisc field
    _GetEOF                                     | populate ioMisc with current EOF
    MOVE.L      (A1),D2                         | D2 = current EOF
    ADD.L       D1,(A1)                         | ioMisc += new bytes needed
    _SetEOF                                     | extend the file
CHECKLOAD_ERR_4:
    MOVE.L      (A7)+,D2                        | restore D2
    BRA.W       CHECKLOAD_ERR_3                 | save result, restore, return
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_19 (ValidateMap) -- sanity-check the just-loaded map.
|
| Validates that the map's offsets are consistent: file size fits in
| 24 bits, attribute bit 0 of byte 0x19 is clear, computed type-list
| terminus is consistent with the name list offset. Returns D0=0 on
| valid, sets ResErr=mapReadErr (-199) and returns -1 on bad map.
| Called during boot.
CHECKLOAD_CONT_19:
    MOVEM.L     D0-D1/A0-A1,-(A7)               | save working regs
    MOVEA.L     (A4),A0                         | A0 = deref'd map block
    BSR.W       CHECKLOAD_CONT_12               | D0 = total file size
    CMP.L       (Lo3Bytes).W,D0                 | exceeds 24-bit address range?
    BGE.B       CHECKLOAD_ERR_5                 | yes -> bad map
    BTST        #0x0,0x19(A0)                   | reserved bit set?
    BNE.B       CHECKLOAD_ERR_5                 | yes -> bad map
    MOVEA.L     A0,A1                           | A1 = type list scan ptr
    ADDA.W      0x18(A0),A1                     | A1 = map + offsetToTypeList
    MOVE.W      (A1)+,D0                        | D0 = numTypes - 1
    BMI.B       CHECKLOAD_SKIP_4                | empty -> skip walk
    MOVEQ.L     #0x0,D1                         | D1 = total ref count
CHECKLOAD_LOOP:
    ADD.W       0x4(A1),D1                      | D1 += this type's count - 1
    ADDQ.W      #0x1,D1                         | + 1 (count was N-1)
    ADDQ.W      #0x8,A1                         | next 8-byte type entry
    DBF.W       D0,CHECKLOAD_LOOP               | loop through all types
    MULU.W      #0xC,D1                         | D1 *= 12 (ref entry size)
    ADDA.L      D1,A1                           | A1 = computed end of ref list
CHECKLOAD_SKIP_4:
    MOVE.W      0x1A(A0),D1                     | D1 = name list offset
    BGT.B       CHECKLOAD_CONT_20               | non-empty -> validate offset
    SUBA.L      A0,A1                           | A1 -= map base = relative pos
    MOVE.L      A1,D1                           | D1 = computed end (rel)
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    CMP.L       0xC(A0),D1                      | matches map.dataLength?
    BGT.B       CHECKLOAD_ERR_5                 | exceeds -> bad map
    BRA.B       CHECKLOAD_OK_5                  | -> success
| ----------------------------------------------------------
|
| CHECKLOAD_CONT_20 -- validate name list offset against computed position.
|
| Called during boot.
CHECKLOAD_CONT_20:
    ADDA.W      D1,A0                           | A0 = map + nameListOffset
    CMPA.L      A1,A0                           | name list >= computed end?
    BMI.B       CHECKLOAD_ERR_5                 | no -> bad map
CHECKLOAD_OK_5:
    MOVEQ.L     #0x0,D0                         | D0 = 0 (success)
    BRA.B       CHECKLOAD_EXIT_6                | -> exit
| ----------------------------------------------------------
|
| CHECKLOAD_ERR_5 -- map validation failed.
|
CHECKLOAD_ERR_5:
    MOVE.W      #0xFF39,(ResErr).W              | mapReadErr (-199)
CHECKLOAD_EXIT_6:
    MOVEM.L     (A7)+,D0-D1/A0-A1               | restore working regs
    RTS                                         | return from CHECKLOAD_CONT_19
| ----------------------------------------------------------
|
| _LoadResource ($A9A2) -- load (or reload) a resource into memory.
|
| Stack: handle(L) -> (no result; ResErr indicates error).
| For cached handles already populated, no-op. Otherwise locates
| the ref entry and forces a load via P_CheckLoad with ResLoad=true
| (regardless of caller's ResLoad setting).
LOADRESOURCE:
    MOVEM.L     D0/A0,-(A7)                     | save D0/A0
    PEA.L       LOADRESOURCE_EXIT(PC)           | push special tail epilogue
    BSR.W       RESMGR_CONT_5                   | partial prologue (LINK frame)
    MOVEA.L     0x14(A6),A1                     | A1 = handle from stack frame
    TST.L       (A1)                            | already loaded?
    BNE.B       RELEASERESOURCE_FORCE_LOAD      | yes -> done
    BSR.W       RESMGR_CONT_12                  | locate ref entry by handle
    BEQ.B       LOADRESOURCE_FOUND              | found -> load it
    MOVE.W      #0xFF40,(ResErr).W              | resNotFound (-192)
    BRA.B       RELEASERESOURCE_FORCE_LOAD      | -> exit
LOADRESOURCE_FOUND:
    MOVE.B      (ResLoad).W,-(A7)               | save current ResLoad
    ST.B        (ResLoad).W                     | force ResLoad = true
    BSR.W       P_CheckLoad                     | load resource data
    MOVE.B      (A7)+,(ResLoad).W               | restore caller's ResLoad
RELEASERESOURCE_FORCE_LOAD:
    BRA.W       RESMGR_EXIT_6                   | StdExit
| Special tail-epilogue used by LoadResource (popped by RESMGR_CONT_11).
LOADRESOURCE_EXIT:
    MOVEM.L     (A7)+,D0/A0                     | restore D0/A0 saved at top
    MOVE.L      (A7)+,(A7)                      | drop our extra frame
    RTS                                         | return from LoadResource
| ----------------------------------------------------------
|
| _ReleaseResource ($A9A3) -- release a resource handle.
|
| Disposes the handle if not changed (resChanged clear), then nulls
| the ref's handle field so future GetResource reloads from disk.
| If resChanged is set, leaves the handle (caller should write first).
RELEASERESOURCE:
    BSR.W       WRITERESOURCE_CONT_2            | locate ref by handle (StdEntry)
    BTST        #0x1,0x4(A2)                    | resChanged set?
    BNE.B       RELEASERESOURCE_EXIT            | yes -> leave handle alone
    MOVEA.L     A1,A0                           | A0 = handle to dispose
    _DisposeHandle                              | dispose
RELEASERESOURCE_CONT:
    CMPI.L      #0x464F4E54,D3                  | type == 'FONT'?
    BNE.B       RELEASERESOURCE_SKIP            | no -> skip FS cache reset
    MOVE.L      (MinusOne).W,(LastSPExtra).W    | invalidate FS save-extra cache
RELEASERESOURCE_SKIP:
    CLR.L       0x8(A2)                         | ref.handle = nil
    CLR.L       (RMgrLastResHand).W             | invalidate last-handle cache
RELEASERESOURCE_EXIT:
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| _DetachResource ($A992) -- detach handle from resource map.
|
| Clears the resource bit in the handle's master flags, then nulls
| the ref entry so subsequent GetResource reloads from disk. Caller
| takes ownership of the handle. Fails if resChanged is set.
DETACHRESOURCE:
    BSR.B       WRITERESOURCE_CONT_2            | locate ref by handle (StdEntry)
    BTST        #0x1,0x4(A2)                    | resChanged set?
    BNE.B       DETACHRESOURCE_ERR              | yes -> error
    MOVEA.L     A1,A0                           | A0 = handle
    _HClrRBit                                   | clear resource bit in HFlags
    BRA.B       RELEASERESOURCE_CONT            | -> shared cleanup
DETACHRESOURCE_ERR:
    MOVE.W      #0xFF3A,(ResErr).W              | resAttrErr (-198)
    BRA.B       RELEASERESOURCE_EXIT            | -> exit
| ----------------------------------------------------------
|
| _ChangedResource ($A9AA) -- mark resource as modified.
|
| Sets the resChanged bit in the ref entry. If the resource doesn't
| have its on-disk space reserved (resReserved clear), grows the
| map handle by 280 bytes via CHECKLOAD_CONT_18 to ensure room for
| a future _UpdateResFile. Marks the map as modified.
CHANGEDRESOURCE:
    BSR.B       WRITERESOURCE_CONT_2            | locate ref by handle (StdEntry)
    MOVEA.L     A1,A0                           | A0 = handle
    _HGetState                                  | D0 = current handle state
    MOVE.B      D0,D7                           | save state in D7
    _HNoPurge                                   | mark non-purgeable while we modify
    BTST        #0x3,0x4(A2)                    | resReserved bit set?
    BNE.B       SETRESATTRS_MARK_CHANGED        | yes -> skip pre-grow
    BSR.W       CHECKLOAD_CONT_18               | pre-grow map for new ref
    BMI.B       SETRESATTRS_RESTORE             | grow failed, restore + exit
    BSET        #0x1,0x4(A2)                    | set resChanged bit (modified)
    BSR.W       CHECKLOAD_CONT_16               | recompute file size cache
    MOVEA.L     (A4),A0                         | A0 = deref'd map handle
    BSET        #0x5,0x16(A0)                   | set mapChanged bit in map header
    BRA.B       SETRESATTRS_RESTORE             | -> restore handle state
SETRESATTRS_MARK_CHANGED:
    MOVE.W      #0xFF3A,(ResErr).W              | resAttrErr (-198)
SETRESATTRS_RESTORE:
    MOVEA.L     A1,A0                           | A0 = handle
    MOVE.B      D7,D0                           | D0 = saved handle state
    _HSetState                                  | restore handle state
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| _WriteResource ($A9B0) -- write a changed resource to disk.
|
| Writes the in-memory data of a resource back to its file. Only
| acts if file is writable AND resChanged is set. Otherwise no-op.
WRITERESOURCE:
    BSR.B       WRITERESOURCE_CONT_2            | locate ref by handle (StdEntry)
    BSR.W       CHECKLOAD_OK_4                  | file read-only?
    BNE.B       CHANGEDRESOURCE_AFTER_WRITE     | yes -> skip write
    BTST        #0x1,0x4(A2)                    | resChanged set?
    BEQ.B       CHANGEDRESOURCE_AFTER_WRITE     | no -> skip write
    BSR.W       CHECKLOAD_CONT_8                | write changed data to disk
CHANGEDRESOURCE_AFTER_WRITE:
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| WRITERESOURCE_CONT: zero-arg variant of WRITERESOURCE_CONT_2 (used when caller has no handle param).
WRITERESOURCE_CONT:
    MOVE.L      (MinusOne).W,0xC(A7)            | sentinel handle = -1
| WRITERESOURCE_CONT_2 (StdHandleEntry): standard entry for handle-keyed traps.
| Called by: RELEASERESOURCE, DETACHRESOURCE, CHANGEDRESOURCE, WRITERESOURCE, HOMERESFILE
WRITERESOURCE_CONT_2:
    MOVE.L      (A7)+,D0                        | save caller's return addr
    BSR.W       RESMGR_CONT_5                   | partial prologue
    MOVE.L      D0,-(A7)                        | restore return addr
    MOVE.L      A0,D0                           | A0 = caller's handle
    BEQ.B       WRITERESOURCE_SKIP_2            | nil -> error exit
    MOVEA.L     (A0),A1                         | A1 = handle's master ptr
    BSR.W       FINDRESHANDLE                   | locate ref by handle in maps
    BEQ.B       WRITERESOURCE_EXIT              | found -> return to caller's body
WRITERESOURCE_SKIP_2:
    ADDQ.W      #0x4,A7                         | discard saved return addr
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| WRITERESOURCE_EXIT -- handle found, return to caller's operation body.
|
| Called during boot.
WRITERESOURCE_EXIT:
    RTS                                         | return from WRITERESOURCE_CONT_2
| ----------------------------------------------------------
|
| _HomeResFile ($A9A4) -- find which resource file owns a handle.
|
| Stack: handle(L) -> refNum(W). Returns -1 if not in any map.
| If owning map is SysMap, returns 0 (the conventional alias).
HOMERESFILE:
    MOVE.W      #0xFFFF,0x8(A7)                 | preset result = -1 (not found)
    BSR.B       WRITERESOURCE_CONT_2            | StdHandleEntry: locate ref
    CMP.W       (SysMap).W,D6                   | owning map is SysMap?
    BNE.B       HOMERESFILE_EXIT                | no -> use refnum as-is
    MOVEQ.L     #0x0,D6                         | yes -> return 0 (SysMap alias)
HOMERESFILE_EXIT:
    MOVE.W      D6,0xC(A6)                      | return refNum in result slot
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| RESOURCEPURGE_HOOK -- SetResPurge purge-proc trampoline.
|
| Installed as the zone's purge proc. On purge, looks up the handle
| in the resource map; if it's a resource and resChanged is set,
| writes it back via _WriteResource before returning to default purge.
RESOURCEPURGE_HOOK:
    MOVEA.L     (A7)+,A1                        | A1 = caller's return address
    MOVEA.L     (A7)+,A0                        | A0 = handle being purged
    _HGetState                                  | D0 = handle state
    BTST        #0x5,D0                         | resource bit set?
    BEQ.B       HOMERESFILE_SKIP                | not a resource -> skip
    MOVE.L      A0,-(A7)                        | push handle for trap
    _WriteResource                              | write changes to disk
HOMERESFILE_SKIP:
    JMP         (A1)                            | tail to default purge proc
| ----------------------------------------------------------
|
| _SetResPurge ($A993) -- install/remove resource purge handler.
|
| Stack: install(B). If install != 0, replaces zone purgeProc with
| RESOURCEPURGE_HOOK trampoline so changed resources auto-flush on purge.
| If install == 0, restores nil (default purge).
SETRESPURGE:
    MOVEA.L     (TheZone).W,A0                  | A0 = current zone
    MOVE.L      (A7)+,D0                        | save return address
    TST.B       (A7)+                           | install flag != 0?
    PEA.L       RESOURCEPURGE_HOOK(PC)          | push trampoline addr
    BNE.B       SETRESPURGE_CONT                | install -> use trampoline
    CLR.L       (A7)                            | uninstall -> nil purgeProc
SETRESPURGE_CONT:
    MOVE.L      (A7)+,0x28(A0)                  | zone.pPurgeProc = top of stack
    MOVE.L      D0,-(A7)                        | restore return addr
| Called by: SETRESLOAD, CURRESFILE, RESERROR, ADDREFERENCE, RMVEREFERENCE
SETRESPURGE_EXIT:
    CLR.B       (RMgrCurOnly).W                 | clear curOnly flag
    CLR.W       (ROMMapInsert).W                | clear ROMMapInsert flag
    RTS                                         | return from SETRESPURGE
| ----------------------------------------------------------
|
| _SetResLoad ($A99B) -- set the auto-load flag.
|
| Stack: load(B). Updates the global ResLoad flag controlling whether
| GetResource etc. read data immediately or return empty handles.
SETRESLOAD:
    MOVEA.L     (A7)+,A0                        | save return address
    MOVE.B      (A7)+,(ResLoad).W               | ResLoad = caller's flag
    MOVE.L      A0,-(A7)                        | restore return addr
    BRA.B       SETRESPURGE_EXIT                | -> common cleanup
| _CurResFile ($A994) -- return the current resource file's refnum.
CURRESFILE:
    MOVE.W      (CurMap).W,0x4(A7)              | return CurMap in result slot
    BRA.B       SETRESPURGE_EXIT                | -> common cleanup
| _ResError ($A9AF) -- return the last Resource Manager error code.
RESERROR:
    MOVE.W      (ResErr).W,0x4(A7)              | return ResErr in result slot
    BRA.B       SETRESPURGE_EXIT                | -> common cleanup
| _AddReference ($A9CB) -- vestigial, returns addRefFailed (-195).
ADDREFERENCE:
    MOVEA.L     (A7)+,A0                        | save return addr
    ADDA.W      #0xA,A7                         | drop 10 bytes of params
    MOVE.L      A0,-(A7)                        | restore return addr
    MOVE.W      #0xFF3D,(ResErr).W              | addRefFailed (-195)
    BRA.B       SETRESPURGE_EXIT                | -> common cleanup
| _RmveReference ($A9CC) -- vestigial, returns rmvRefFailed (-197).
RMVEREFERENCE:
    MOVE.L      (A7)+,(A7)                      | drop one long of params
    MOVE.W      #0xFF3B,(ResErr).W              | rmvRefFailed (-197)
    BRA.B       SETRESPURGE_EXIT                | -> common cleanup
| ----------------------------------------------------------
|
| _GetResAttrs ($A9A6) -- read attribute byte for a resource handle.
|
| Stack: handle(L) -> attrs(B). Uses partial prologue + handle lookup
| via FINDRESHANDLE, then reads ref+4 attribute byte.
GETRESATTRS:
    BSR.W       RESMGR_CONT_5                   | partial prologue
    MOVEA.L     (A0),A1                         | A1 = handle's master ptr
    BSR.B       FINDRESHANDLE                   | locate ref by handle
    BMI.B       GETRESATTRS_NOT_FOUND           | not found -> error exit
    MOVE.B      0x4(A2),0xD(A6)                 | return ref's attribute byte
GETRESATTRS_NOT_FOUND:
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| _SetResAttrs ($A9A7) -- write attribute byte for a resource handle.
|
| Stack: handle(L), attrs(B). Cannot modify ROM-map resources
| (they're read-only). Sets mapChanged on the owning map.
SETRESATTRS:
    BSR.W       RESMGR_CONT_5                   | partial prologue
    MOVEA.L     0xA(A6),A1                      | A1 = handle from stack frame
    BSR.B       FINDRESHANDLE                   | locate ref by handle
    BMI.B       SETRESATTRS_EXIT                | not found -> error exit
    CMPA.L      (ROMMapHandle).W,A4             | resource is in ROM map?
    BEQ.B       SETRESATTRS_EXIT                | yes -> ignore (read-only)
    MOVE.B      0x9(A6),0x4(A2)                 | ref.attrs = caller's byte
    MOVEA.L     (A4),A0                         | A0 = deref'd map block
    BSET        #0x5,0x16(A0)                   | set mapChanged bit
SETRESATTRS_EXIT:
    BRA.W       RESMGR_EXIT_4                   | StdSixExit
| ----------------------------------------------------------
|
| FINDRESHANDLE -- find ref entry by handle, set ResErr on failure.
|
| Wrapper around RESMGR_CONT_12 that sets ResErr=resNotFound (-192)
| if the handle isn't in any map. Returns Z=1 on found, Z=0 on miss.
| Called by: WRITERESOURCE_CONT_2, GETRESATTRS, SETRESATTRS, GETRESINFO, SETRESINFO
FINDRESHANDLE:
    BSR.W       RESMGR_CONT_12                  | locate ref by handle (full search)
    BEQ.B       FINDRESHANDLE_RTS               | found -> return success
    MOVE.W      #0xFF40,(ResErr).W              | resNotFound (-192)
FINDRESHANDLE_RTS:
    RTS                                         | return from FINDRESHANDLE
| ----------------------------------------------------------
|
| _GetResInfo ($A9A8) -- read type, ID, and name for a resource handle.
|
| Stack: handle(L), idPtr(L), typePtr(L), namePtr(L). Returns the
| resource's ID at *idPtr, type code at *typePtr, and name string
| at *namePtr (each pointer may be nil to skip that field).
| If handle isn't in any map, returns (id=-1, type=0, name="").
GETRESINFO:
    BSR.W       RESMGR_CONT_5                   | partial prologue
    MOVEA.L     0x14(A6),A1                     | A1 = handle from stack frame
    BSR.B       FINDRESHANDLE                   | locate ref by handle
    BEQ.B       GETRESINFO_EXIT                 | found -> use ref data
    LEA.L       (MinusOne).W,A2                 | A2 -> -1 (sentinel id)
    MOVEQ.L     #0x0,D3                         | D3 = 0 (sentinel type)
GETRESINFO_EXIT:
    LEA.L       0x10(A6),A0                     | A0 = ptr to namePtr in frame
    MOVEA.L     (A0),A1                         | A1 = caller's idPtr
    MOVE.L      A1,D0                           | nil?
    BEQ.B       GETRESINFO_EMPTY                | yes -> skip
    MOVE.W      (A2),(A1)                       | *idPtr = ref.id (or -1 sentinel)
GETRESINFO_EMPTY:
    MOVEA.L     -(A0),A1                        | A1 = caller's typePtr
    MOVE.L      A1,D0                           | nil?
    BEQ.B       GETRESINFO_EMPTY_2              | yes -> skip
    MOVE.L      D3,(A1)                         | *typePtr = type code
GETRESINFO_EMPTY_2:
    MOVEA.L     -(A0),A1                        | A1 = caller's namePtr
    MOVE.L      A1,D0                           | nil?
    BEQ.B       GETRESINFO_EMPTY_3              | yes -> done
    CLR.B       (A1)                            | preset *namePtr = "" (zero len)
    BSR.W       RESMGR_CONT_16                  | A0 = ref's name (or MI if none)
    BMI.B       GETRESINFO_EMPTY_3              | no name -> leave empty
    BSR.B       GETRESINFO_CONT                 | copy name to *namePtr
GETRESINFO_EMPTY_3:
    MOVEQ.L     #0x10,D0                        | D0 = 16 (StdSixteenExit pop)
    BRA.W       RESMGR_CONT_11                  | -> common epilogue
| GETRESINFO_CONT: copy Pascal string from A0 to A1 (length+1 bytes).
GETRESINFO_CONT:
    MOVEQ.L     #0x0,D0                         | clear high byte of D0
    MOVE.B      (A0),D0                         | D0 = string length
    ADDQ.W      #0x1,D0                         | + 1 (length byte itself)
    _BlockMove                                  | copy length+chars
    RTS                                         | return from GETRESINFO_CONT
| ----------------------------------------------------------
|
| _SetResInfo ($A9A9) -- update id and name of a resource.
|
| Stack: handle(L), id(W), namePtr(L). Reassigns the resource's id
| in its ref entry. If a non-nil namePtr is provided, calls
| RMVERESOURCE_CONT_5 to splice in the new name in the name list.
| Errors with resAttrErr if resReserved bit is set.
SETRESINFO:
    BSR.W       RESMGR_CONT_5                   | partial prologue
    MOVEA.L     0xE(A6),A1                      | A1 = handle from stack frame
    BSR.B       FINDRESHANDLE                   | locate ref by handle
    BMI.B       SETRESINFO_ERR                  | not found -> error exit
    BTST        #0x3,0x4(A2)                    | resReserved bit set?
    BNE.B       SETRESINFO_CONT                 | yes -> resAttrErr
    MOVE.L      0x8(A6),D0                      | D0 = caller's namePtr
    BEQ.B       SETRESINFO_SKIP                 | nil -> skip name update
    SUBA.L      A1,A1                           | A1 = nil (no resource handle)
    BSR.W       CHECKLOAD_CONT_18               | pre-grow map for name change
    BMI.B       SETRESINFO_ERR                  | failed -> error exit
    MOVEA.L     D0,A0                           | A0 = caller's namePtr
    BSR.W       RMVERESOURCE_CONT_5             | remove old name from name list
    BSR.W       RMVERESOURCE_EMPTY              | insert new name in name list
    BSR.W       CHECKLOAD_OK_3                  | _SetEOF for new file size
SETRESINFO_SKIP:
    MOVEA.L     (A4),A0                         | A0 = deref'd map block
    BSET        #0x5,0x16(A0)                   | set mapChanged bit
    MOVE.W      0xC(A6),(A2)                    | ref.id = caller's new id
    BRA.B       SETRESINFO_ERR                  | -> exit
SETRESINFO_CONT:
    MOVE.W      #0xFF3A,(ResErr).W              | resAttrErr (-198)
SETRESINFO_ERR:
    MOVEQ.L     #0xA,D0                         | D0 = 10 (StdTenExit pop)
    BRA.W       RESMGR_CONT_11                  | -> common epilogue
| ----------------------------------------------------------
|
| _AddResource ($A9AB) -- attach a handle as a new resource.
|
| Stack: handle(L), type(L), id(W), name(L).
| Pre-flight checks: handle is non-nil, not already a resource.
| Allocates ref entry (ADDRESOURCE_CONT), populates id/name/type,
| sets resource bit (_HSetRBit), inserts into ref list, writes
| data to end of fork via CHECKLOAD_CONT_17.
ADDRESOURCE:
    BSR.W       RESMGR_CONT_4                   | full prologue
    MOVE.W      #0xFF3E,(ResErr).W              | preset addResFailed (-194)
    MOVEA.L     0x12(A6),A1                     | A1 = handle from stack frame
    MOVE.L      A1,D0                           | nil handle?
    BEQ.B       ADDRESOURCE_ERR                 | yes -> error exit
    BSR.W       RESMGR_CONT_12                  | already a resource?
    BEQ.B       ADDRESOURCE_ERR                 | yes -> error exit
    BSR.W       RETURNS_21                      | use current map (refnum)
    BSR.W       CHECKLOAD_CONT_18               | pre-grow map for new ref
    BMI.B       ADDRESOURCE_ERR                 | failed -> error exit
    MOVE.L      0xE(A6),D3                      | D3 = type from stack frame
    BSR.B       ADDRESOURCE_CONT                | allocate new ref entry -> A2
    MOVE.W      0xC(A6),(A2)+                   | ref.id = caller's id
    MOVE.W      #0xFFFF,(A2)+                   | ref.nameOffset = -1 (no name yet)
    MOVE.L      #0x2000000,(A2)+                | ref.attrs+offset = resChanged | 0
    MOVEA.L     0x12(A6),A0                     | A0 = caller's handle
    _HSetRBit                                   | mark handle as resource
    MOVE.L      A0,(A2)                         | ref.handle = handle
    SUBQ.L      #0x8,A2                         | back A2 to start of ref entry
    MOVEA.L     0x8(A6),A0                      | A0 = name pointer (or nil)
    BSR.W       RMVERESOURCE_EMPTY              | insert name in name list
    BSR.W       CHECKLOAD_CONT_17               | write data at end of fork
ADDRESOURCE_ERR:
    MOVEQ.L     #0xE,D0                         | D0 = 14 (StdFourteenExit)
    BRA.W       RESMGR_CONT_11                  | -> common epilogue
| ----------------------------------------------------------
|
| ADDRESOURCE_CONT -- allocate a new ref entry for AddResource.
|
| Two cases: type already in this map (CONT_2: extend ref list) or
| new type (insert new type entry + ref). Sets mapChanged on the map.
| For new types, shifts the type list down by 8 bytes via
| RMVERESOURCE_CONT_4 (block move) and updates each subsequent
| type's ref-list offset (ADDRESOURCE_LOOP loop).
| Returns A2 = new ref entry (12 bytes).
ADDRESOURCE_CONT:
    BSET        #0x5,0x16(A3)                   | set mapChanged bit
    BSR.W       RETURNS_26                      | type already in this map?
    BEQ.B       ADDRESOURCE_CONT_2              | yes -> extend existing ref list
    MOVEQ.L     #0x14,D0                        | D0 = 20 bytes (new type+ref total)
    BSR.W       RMVERESOURCE_CONT               | shift name list down by 20
    BSR.W       RETURNS_23                      | re-read type list base/count
    BMI.B       ADDRESOURCE_EMPTY               | empty -> first type
    BSR.W       RETURNS_27                      | A2 = ref list (8-byte type entry)
ADDRESOURCE_EMPTY:
    MOVEA.L     A2,A3                           | A3 = new ref slot dest
    MOVEA.L     (A4),A2                         | A2 = deref'd map
    ADDA.W      0x1A(A2),A2                     | A2 += offset to name list
    SUBA.W      #0x14,A2                        | A2 -= 20 (just-vacated slot)
    MOVEQ.L     #0x8,D0                         | D0 = 8 (type entry size)
    MOVEA.L     A3,A0                           | A0 = source (original ref slot)
    MOVEA.L     A2,A1                           | A1 = dest (new type entry slot)
    BSR.W       RMVERESOURCE_CONT_4             | shift refs down 8 bytes (insert type)
    MOVEA.L     (A4),A0                         | A0 = deref'd map
    ADDA.W      0x18(A0),A0                     | A0 = type list base
    ADDQ.W      #0x1,(A0)                       | bump numTypes (W)
    MOVE.L      D3,(A3)+                        | type entry: type code
    CLR.W       (A3)+                           | type entry: count - 1 = 0
    SUBA.L      A0,A1                           | A1 = ref list offset (relative)
    MOVE.W      A1,(A3)                         | type entry: ref-list offset
    ADDQ.L      #0x8,A2                         | A2 = back to first ref (after type)
    MOVE.W      (A0)+,D5                        | D5 = numTypes - 1 (was already bumped)
    BRA.B       ADDRESOURCE_LOOP                | -> patch subsequent type offsets
| ----------------------------------------------------------
|
| ADDRESOURCE_CONT_2 -- extend existing ref list for AddResource.
|
| Called during boot.
ADDRESOURCE_CONT_2:
    MOVEQ.L     #0xC,D0                         | D0 = 12 (one ref entry)
    BSR.W       RMVERESOURCE_CONT               | shift name list down by 12
    MOVEA.L     (A4),A1                         | A1 = deref'd map
    ADDA.W      0x1A(A1),A1                     | A1 += offset to name list
    SUBA.W      D0,A1                           | A1 -= 12 (just-vacated slot)
    BSR.W       RETURNS_26                      | re-locate type entry -> A2
    MOVE.L      A2,-(A7)                        | save type entry ptr
    ADDQ.W      #0x1,0x4(A2)                    | bump type's count - 1 (W)
    MOVEQ.L     #0xC,D0                         | D0 = 12
    MULU.W      0x4(A2),D0                      | D0 = 12 * (count - 1) -- offset
    MOVEA.W     0x6(A2),A2                      | A2 = ref-list relative offset
    ADDA.L      A3,A2                           | A2 += type list base = abs ptr
    ADDA.W      D0,A2                           | A2 = end of this type's refs
    MOVEA.L     A2,A0                           | A0 = source (start of insert pos)
    MOVEQ.L     #0xC,D0                         | D0 = 12 (insert size)
    BSR.W       RMVERESOURCE_CONT_4             | shift refs+names down 12 bytes
    MOVEA.L     (A7)+,A0                        | A0 = type entry ptr (saved)
    BRA.B       ADDRESOURCE_CONT_3              | -> patch subsequent type offsets
| ADDRESOURCE_LOOP: bump each subsequent type's ref-list offset.
ADDRESOURCE_LOOP:
    ADD.W       D0,0x6(A0)                      | type[i].refOffset += D0
ADDRESOURCE_CONT_3:
    ADDQ.W      #0x8,A0                         | next 8-byte type entry
    DBF.W       D5,ADDRESOURCE_LOOP             | loop through remaining types
    RTS                                         | return from ADDRESOURCE_CONT
| ----------------------------------------------------------
|
| _RmveResource ($A9AD) -- remove a resource from its file.
|
| Stack: handle(L). Removes the ref entry, deletes the name entry,
| and (if last ref of type) removes the type entry. Compacts the
| ref/type lists in-place. Sets mapChanged + mapCompact bits.
| Errors with rmvResFailed if resReserved set, file is wrong map,
| or handle isn't a resource.
RMVERESOURCE:
    BSR.W       RESMGR_CONT_5                   | partial prologue
    MOVE.W      #0xFF3C,(ResErr).W              | preset rmvResFailed (-196)
    MOVEA.L     (A0),A1                         | A1 = handle's master ptr
    BSR.W       RESMGR_CONT_12                  | locate ref by handle
    BMI.B       RMVERESOURCE_SKIP_3             | not found -> error exit
    BTST        #0x3,0x4(A2)                    | resReserved bit set?
    BNE.B       RMVERESOURCE_SKIP_3             | yes -> error
    CMP.W       (CurMap).W,D6                   | resource is in current map?
    BNE.B       RMVERESOURCE_SKIP_3             | no -> error (only current allowed)
    MOVEA.L     A1,A0                           | A0 = handle to clear
    _HClrRBit                                   | clear resource bit on handle
    MOVEQ.L     #0x60,D0                        | D0 = mapChanged | mapCompact
    CLR.L       (RMgrLastResHand).W             | invalidate handle cache
    MOVEA.L     (A4),A0                         | A0 = deref'd map block
    OR.B        D0,0x16(A0)                     | set both bits in map.attrs
    BSR.W       RMVERESOURCE_CONT_5             | delete name from name list
    MOVEQ.L     #-0xC,D7                        | D7 = -12 (ref-list shrink)
    MOVEA.L     A2,A0                           | A0 = ref entry to remove
    SUBA.W      D7,A0                           | A0 += 12 (next ref)
    BSR.W       RETURNS_26                      | re-locate type entry -> A2
    MOVEA.L     (A4),A1                         | A1 = deref'd map
    ADDA.W      0x1A(A1),A1                     | A1 += offset to name list
    MOVE.L      D7,D0                           | D0 = -12 (shift size)
    BSR.W       RMVERESOURCE_CONT_4             | shift refs+names up 12 bytes
    MOVEA.L     A2,A0                           | A0 = type entry
    ADDQ.W      #0x8,A0                         | A0 = next type entry
    SUBQ.W      #0x1,D5                         | types remaining after this one?
    BMI.B       RMVERESOURCE_NO                 | none -> skip patch loop
    BSR.B       ADDRESOURCE_LOOP                | shrink subsequent types' offsets
RMVERESOURCE_NO:
    SUBQ.W      #0x1,0x4(A2)                    | decrement type's count - 1
    BPL.B       RMVERESOURCE_SKIP               | still has refs -> done
    ADDQ.W      #0x8,A2                         | A2 = next type entry (this gone)
    MOVEA.L     A2,A0                           | A0 = source (after deleted type)
    ADDA.W      D0,A1                           | A1 += -12 (already shifted)
    MOVEQ.L     #-0x8,D0                        | D0 = -8 (type entry size)
    ADD.L       D0,D7                           | D7 += -8 (cumulative shrink)
    BSR.W       RMVERESOURCE_CONT_4             | shift everything up 8 bytes
    MOVEA.L     (A4),A0                         | A0 = deref'd map
    ADDA.W      0x18(A0),A0                     | A0 = type list base
    SUBQ.W      #0x1,(A0)                       | decrement numTypes
    MOVE.W      (A0)+,D5                        | D5 = new numTypes - 1
    BMI.B       RMVERESOURCE_SKIP               | empty type list -> skip
    BSR.W       ADDRESOURCE_LOOP                | shrink remaining types' offsets
RMVERESOURCE_SKIP:
    MOVE.L      D7,D0                           | D0 = total bytes shrunk
    BSR.B       RMVERESOURCE_CONT               | shrink map handle by D0
    CMPI.W      #0x1,D6                         | ROM map?
    BEQ.B       RMVERESOURCE_SKIP_2             | yes -> skip _SetEOF
    BSR.W       CHECKLOAD_OK_3                  | _SetEOF for new file size
RMVERESOURCE_SKIP_2:
    CLR.W       (ResErr).W                      | success: clear error
RMVERESOURCE_SKIP_3:
    CLR.L       (RMgrLastResHand).W             | invalidate handle cache
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| RMVERESOURCE_EMPTY -- insert resource name in name list.
|
| If A0 points to a non-empty Pascal name, appends it to the name
| list (growing the map handle as needed) and stores the relative
| offset in ref+2. If A0 = nil or empty name, stores -1 (no name).
| Called during boot.
RMVERESOURCE_EMPTY:
    CLR.L       (RMgrLastResHand).W             | invalidate handle cache
    MOVEM.L     D0-D2/A0-A1,-(A7)               | save working regs
    MOVEQ.L     #-0x1,D2                        | D2 = -1 (no-name sentinel)
    TST.B       (A0)                            | name length zero?
    BEQ.B       RMVERESOURCE_OK                 | yes -> store sentinel
    MOVEA.L     (A4),A1                         | A1 = deref'd map
    MOVE.L      0xC(A1),D1                      | D1 = current map data length
    MOVE.L      D1,D2                           | D2 = pre-grow offset (= name pos)
    MOVEQ.L     #0x0,D0                         | D0 = 0
    MOVE.B      (A0),D0                         | D0 = name length
    ADDQ.L      #0x1,D0                         | + 1 (length byte itself)
    BSR.B       RESIZERESMAP                    | grow map by D0 bytes
    MOVEQ.L     #0x0,D0                         | clear D0
    MOVEA.L     (A4),A1                         | A1 = deref'd map (may have moved)
    MOVE.W      0x1A(A1),D0                     | D0 = offset to name list
    SUB.L       D0,D2                           | D2 = name list relative offset
    ADDA.L      D1,A1                           | A1 = abs ptr where name goes
    BSR.W       GETRESINFO_CONT                 | _BlockMove name to A1
RMVERESOURCE_OK:
    MOVE.W      D2,0x2(A2)                      | ref.nameOffset = D2 (or -1)
    MOVEM.L     (A7)+,D0-D2/A0-A1               | restore working regs
    RTS                                         | return from RMVERESOURCE_EMPTY
| ----------------------------------------------------------
|
| RMVERESOURCE_CONT -- shift name list down (D0 > 0) or up (D0 < 0).
|
| Common helper for inserting/removing fixed-size blocks in the
| name list. Grows or shrinks the map handle, then BlockMoves the
| name list portion to make room (or close the gap).
| Called during boot.
RMVERESOURCE_CONT:
    MOVEM.L     D0-D1/D7/A0-A1,-(A7)            | save working regs
    MOVEA.L     (A4),A0                         | A0 = deref'd map
    MOVE.L      0xC(A0),D1                      | D1 = current map data length
    TST.L       D0                              | shift size negative?
    BMI.B       RMVERESOURCE_CONT_2             | yes (shrink) -> skip grow
    BSR.B       RESIZERESMAP                    | grow by D0 bytes
    MOVEA.L     (A4),A0                         | A0 = re-deref (may have moved)
RMVERESOURCE_CONT_2:
    MOVEA.L     A0,A1                           | A1 = map base
    MOVEQ.L     #0x0,D7                         | D7 = 0
    MOVE.W      0x1A(A0),D7                     | D7 = offset to name list
    ADDA.L      D7,A0                           | A0 = abs ptr to name list start
    ADD.W       D0,0x1A(A1)                     | map.nameListOffset += D0
    ADDA.L      D1,A1                           | A1 = abs ptr past data length
    BSR.B       RMVERESOURCE_CONT_4             | BlockMove name list to new pos
    TST.L       D0                              | grow direction (0 = grow done)?
    BPL.B       RMVERESOURCE_DONE               | grow -> done
    BSR.B       RESIZERESMAP                    | shrink -> resize handle smaller
RMVERESOURCE_DONE:
    MOVEM.L     (A7)+,D0-D1/D7/A0-A1            | restore working regs
    RTS                                         | return from RMVERESOURCE_CONT
| ----------------------------------------------------------
|
| RESIZERESMAP -- grow/shrink the map handle by D0 bytes.
|
| Adjusts map.dataLength field by D0 then calls _SetHandleSize.
| Negative D0 shrinks; positive D0 grows. Uses CHECKLOAD_EXIT_4 to
| save state and CHECKLOAD_EXIT_3 to restore.
| Called during boot.
RESIZERESMAP:
    BSR.W       CHECKLOAD_EXIT_4                | save regs, A2/A3 -> relative
    MOVEA.L     (A4),A0                         | A0 = deref'd map
    ADD.L       0xC(A0),D0                      | D0 = old length + delta
    MOVE.L      D0,0xC(A0)                      | map.dataLength = new length
    MOVEA.L     A4,A0                           | A0 = map handle
    _SetHandleSize                              | resize handle
    BRA.W       CHECKLOAD_EXIT_3                | restore state and return
| ----------------------------------------------------------
|
| RMVERESOURCE_CONT_4 -- BlockMove from A0 to A0+A1, count = (A1-A0).
|
| Helper for shifting blocks within the map. EXG D0,A1 makes A1 the
| destination offset relative to A0; the new dest is computed as
| A0 + offset.
| Called during boot.
RMVERESOURCE_CONT_4:
    MOVEM.L     D0/A0-A1,-(A7)                  | save args
    EXG         D0,A1                           | swap: D0 = orig A1, A1 = orig D0 offset
    SUB.L       A0,D0                           | D0 = orig A1 - A0 = byte count
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    ADDA.L      A0,A1                           | A1 = A0 + offset (dest addr)
    _BlockMove                                  | copy D0 bytes from A0 to A1
    MOVEM.L     (A7)+,D0/A0-A1                  | restore args
    RTS                                         | return from RMVERESOURCE_CONT_4
| ----------------------------------------------------------
|
| RMVERESOURCE_CONT_5 -- delete a name from the name list.
|
| Reads ref's nameOffset (ref+2). If -1, no name: nothing to do.
| Otherwise BlockMoves the name-list tail up to close the gap, then
| shrinks the map handle. Walks every ref entry in the map adjusting
| nameOffset fields whose offsets are above the deleted name.
| Finally sets ref.nameOffset = -1.
| Called during boot.
RMVERESOURCE_CONT_5:
    MOVEM.L     D0-D2/A0-A1,-(A7)               | save working regs
    MOVE.W      0x2(A2),D2                      | D2 = ref's nameOffset
    BMI.B       RMVERESOURCE_SKIP_4             | -1 (no name) -> skip
    MOVEA.L     (A4),A0                         | A0 = deref'd map
    MOVEA.L     A0,A1                           | A1 = deref'd map
    MOVEQ.L     #0x0,D0                         | clear high word
    MOVE.W      0x1A(A0),D0                     | D0 = offset to name list
    ADDA.L      D0,A0                           | A0 = abs ptr to name list
    ADDA.W      D2,A0                           | A0 = abs ptr to this name
    ADDA.L      0xC(A1),A1                      | A1 = end of map (just past data)
    MOVEQ.L     #0x0,D0                         | clear high word
    MOVE.B      (A0),D0                         | D0 = name length
    ADDQ.L      #0x1,D0                         | D0 = length + 1 (length byte)
    ADDA.L      D0,A0                           | A0 = abs ptr past name
    NEG.L       D0                              | D0 = -length (shrink amount)
    MOVE.L      D0,D1                           | D1 = -length (for ref-walk)
    BSR.B       RMVERESOURCE_CONT_4             | shift name list tail up
    BSR.B       RESIZERESMAP                    | shrink map handle
    MOVEM.L     D3-D5/A2-A3,-(A7)               | save scan state
    BSR.W       RESMGR_CONT_3                   | walk all refs -> A2, D4
RMVERESOURCE_LOOP:
    CMP.W       0x2(A2),D2                      | this ref's nameOffset > deleted?
    BGE.B       RMVERESOURCE_NO_2               | no -> leave alone
    ADD.W       D1,0x2(A2)                      | yes -> ref.nameOffset += -length
RMVERESOURCE_NO_2:
    ADDA.W      #0xC,A2                         | next 12-byte ref entry
    DBF.W       D4,RMVERESOURCE_LOOP            | loop through all refs
    MOVEM.L     (A7)+,D3-D5/A2-A3               | restore scan state
RMVERESOURCE_SKIP_4:
    MOVEM.L     (A7)+,D0-D2/A0-A1               | restore working regs
    MOVE.W      (MinusOne).W,0x2(A2)            | ref.nameOffset = -1
    RTS                                         | return from RMVERESOURCE_CONT_5
| ----------------------------------------------------------
|
| _SizeRsrc / _SizeResource ($A9A5) -- get resource data size.
|
| Stack: handle(L) -> size(L). If loaded, returns _GetHandleSize.
| If purged, reads the 4-byte length prefix from the file.
SIZERESOURCE:
    BSR.W       WRITERESOURCE_CONT              | locate ref by handle
    TST.L       (A1)                            | handle's master = nil (purged)?
    BEQ.B       SIZERSRC_NO                     | yes -> read length from file
    MOVEA.L     A1,A0                           | A0 = handle
    _GetHandleSize                              | D0 = data length
    BRA.B       SIZERSRC_EXIT                   | -> return result
SIZERSRC_NO:
    MOVE.B      0x4(A2),-(A7)                   | save attribute byte
    BSR.W       CHECKLOAD_CONT_5                | read 4-byte length from file
    MOVE.B      (A7)+,0x4(A2)                   | restore attribute byte (was cleared)
SIZERSRC_EXIT:
    MOVE.L      D0,0xC(A6)                      | return size in result slot
    BRA.W       RESMGR_EXIT_5                   | StdFourExit
| ----------------------------------------------------------
|
| _MaxSizeRsrc ($A821) -- maximum size resource could grow to in place.
|
| Stack: handle(L) -> size(L). If loaded, returns current handle size.
| If purged, returns the available slot size (data offset gap to next).
MAXSIZERSRC:
    BSR.W       WRITERESOURCE_CONT              | locate ref by handle
    TST.L       (A1)                            | handle's master = nil (purged)?
    BNE.B       MAXSIZERSRC_OK                  | no -> return size
    BSR.W       CHECKLOAD_NO_3                  | D0 = available slot size
    BRA.B       MAXSIZERSRC_CONT                | -> return result
| ----------------------------------------------------------
|
| MAXSIZERSRC_OK -- resource loaded: return actual handle size.
|
MAXSIZERSRC_OK:
    MOVEA.L     A1,A0                           | A0 = handle
    _GetHandleSize                              | D0 = size
MAXSIZERSRC_CONT:
    BRA.B       SIZERSRC_EXIT                   | return D0 in result slot
| ----------------------------------------------------------
|
| _RsrcMapEntry ($A9C5) -- get offset of ref entry from map base.
|
| Stack: handle(L) -> offset(L). Returns ref entry's relative offset
| (24-bit). Used for low-level resource manipulation.
RSRCMAPENTRY:
    BSR.W       WRITERESOURCE_CONT              | locate ref by handle
    MOVE.L      A2,D0                           | D0 = ref entry abs ptr
    SUB.L       (A4),D0                         | D0 -= map base = relative offset
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    BRA.B       SIZERSRC_EXIT                   | return D0 in result slot
