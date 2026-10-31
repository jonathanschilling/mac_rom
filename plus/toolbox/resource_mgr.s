| Resource Manager
|
| Apple source: ResourceMgr.a (MacSEROM.lst module RMGR). In ROM order:
| the empty-map template RESOURCE_MAP, InitResources, SuperLoad, NewMap,
| RsrcZoneInit; the file calls (CreateResFile, OpenResFile, OpenRFPerm,
| UseResFile, Get/SetResFileAttrs, UpdateResFile with the compaction
| CmpFrm, CloseResFile); the search calls (Count1Resources/CountResources,
| Get1IxResource/GetIndResource, Count1Types/CountTypes,
| Get1IxType/GetIndType, Unique1ID/UniqueID, Get1Resource/GetResource,
| Get1NamedResource/GetNamedResource); and the resource calls
| (CheckLoad, LoadResource, ReleaseResource, DetachResource,
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

| ----------------------------------------------------------
|
| RESOURCE_MAP
|
| RESOURCE_MAP: empty resource map template (34 bytes)
| used to initialize a new resource file with no resources
| header: dataOfs=256, mapOfs=256, dataLen=0, mapLen=30
| map: typeListOfs=28, nameListOfs=30, typeCount=-1 (0 types)
RESOURCE_MAP:
  .byte 0x00,0x00,0x01,0x00,0x00,0x00
  .byte 0x01,0x00,0x00,0x00,0x00,0x00
  .byte 0x00,0x00,0x00,0x1E,0x00,0x00
  .byte 0x00,0x00,0x00,0x00,0x00,0x00
  .byte 0x00,0x1C,0x00,0x1E,0xFF,0xFF
  .byte 0x00,0x00,0x00,0x01

| InitResources -- _InitResources ($A995): FUNCTION InitResources: Integer;
InitResources:
        CLR.L   (RMgrLastResHand).w             | clear last resource handle
        BSR     RESMGR_CONT_4                   | initialize resource manager globals
        TST.L   (TopMapHndl).w                  | is resource map already initialized?
        BGT.B   INITRESOURCES_SKIP              | yes -> skip initialization
        CLR.L   (ResErrProc).w                  | clear resource error procedure
        BSR.B   INITRESOURCES_CONT_2            | build ROM resource map
        MOVE.L  A0,(TopMapHndl).w               | set ROM map as top map
        MOVE.L  A0,(SysMapHndl).w               | set ROM map as system map
        MOVE.L  (OneOne).w,(SysMap).w           | set system map refnum to $0001
        BSR     INITRESOURCES_CONT_3            | load system resource file
        CLR.L   0x10(A1)                        | clear next map handle (terminate list)
        BRA.B   INITRESOURCES_SKIP_2            | branch to end of init

| ----------------------------------------------------------
|
| INITRESOURCES_SKIP
|
| Called during boot.
INITRESOURCES_SKIP:
        LEA.L   (TheZone).w,A3                  | get pointer to current heap zone
        MOVE.L  (A3),-(SP)                      | save current zone on stack
        MOVE.L  (SysZone).w,(A3)                | switch to system heap zone
        LEA.L   (SysResName).w,A1               | get pointer to 'System' filename
        BSR     P_NewMap                        | open system resource map
        MOVE.L  (SP)+,(A3)                      | restore previous heap zone
        MOVE    D6,0x8(A6)                      | save file reference number
        TST.L   D0                              | did map open successfully?
        BLE.B   INITRESOURCES_SKIP_2            | no -> skip to end
        MOVE.L  A4,(TopMapHndl).w               | set system map as top map
        MOVE.L  A4,(SysMapHndl).w               | set system map as system map
        MOVE    D6,(CurMap).w                   | set current map refnum
        MOVE    D6,(SysMap).w                   | set system map refnum
        BSR     INITRESOURCES_CONT_4            | enable resource loading
        BSR     INITRESOURCES_CONT_3            | process initial resources
        MOVE.L  (SysMapHndl).w,0x10(A1)         | link system map to next map
        MOVE.L  (SysMapHndl).w,A1               | get system map handle
        MOVE.L  (A1),A1                         | dereference system map handle
        CLR.L   0x10(A1)                        | clear next map field
        BSR.B   INITRESOURCES_CONT              | init ROM override resources
INITRESOURCES_SKIP_2:
        BRA     RESMGR_EXIT_6                   | branch to end

| ----------------------------------------------------------
|
| INITRESOURCES_CONT
|
| Called during boot.
INITRESOURCES_CONT:
        SUBQ.W  #0x4,SP                         | make space for resource handle
        MOVE.L  #0x524F7672,-(SP)               | push 'ROvr' resource type
        CLR     -(SP)                           | push resource ID 0
        _GetResource                            | get 'ROvr' resource
        MOVE.L  (SP)+,D0                        | pop resource handle
        BEQ.B   INITRESOURCES_SKIP_3            | if nil -> skip override
        MOVE.L  D0,A0                           | copy handle to A0
        MOVE.L  (A0),A0                         | dereference handle to get pointer
        JSR     (A0)                            | jump to override code
INITRESOURCES_SKIP_3:
        RTS                                     | return from INITRESOURCES_SKIP_3

| ----------------------------------------------------------
|
| INITRESOURCES_CONT_2
|
| Called during boot.
INITRESOURCES_CONT_2:
        MOVE.L  (ROMBase).w,A0                  | get ROM base address
        ADDA.L  0x1A(A0),A0                     | add offset to ROM resource map
        MOVE.L  A0,A2                           | save ROM map pointer
        MOVEQ.L #0x1A,D0                        | zone size = 4 * ($1A + X) + Y
        ADD     (A0)+,D0                        | + X = number of ROM resources
        ASL.L   #0x2,D0                         | * 4 (bytes per master pointer)
        ADD     (A0)+,D0                        | + Y = size of the ROM resource map
        MOVE.L  D0,A1                           | copy size to A1
        _NewPtrSys                              | allocate pointer in system heap
        MOVE.L  (TheZone).w,-(SP)               | save current zone
        CLR.L   -(SP)                           | push 0
        MOVE    #0x4,-(SP)                      | push 4
        ADDA.L  A0,A1                           | add size to pointer
        MOVE.L  A1,-(SP)                        | push end address
        MOVE.L  A0,-(SP)                        | push start address
        MOVE.L  A0,A1                           | copy start address to A1
        MOVE.L  A7,A0                           | copy stack pointer to A0
        _InitZone                               | initialize ROM zone
        BSET    #0x0,0x16(A1)                   | set zone flags
        MOVE.L  A1,(TheZone).w                  | set ROM zone as current
        ADDA    #0xE,SP                         | clean up stack
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (A2)+,D0                        | D0 = X = number of ROM resources
        ASL.L   #0x2,D0                         | * 4: one master pointer per resource
        _NewPtr                                 | master pointer block in the ROM zone
        MOVEQ.L #0x0,D0                         | clear D0
        MOVE    (A2)+,D0                        | D0 = Y = size of the ROM resource map
        _NewHandle                              | allocate handle for ROM map
        BSET    #0x7,(A0)                       | lock handle
        MOVE.L  A0,(ROMMapHandle).w             | save ROM map handle
        MOVE.L  (SP)+,(TheZone).w               | restore previous zone
        RTS                                     | return from INITRESOURCES_CONT_2

| ----------------------------------------------------------
|
| INITRESOURCES_CONT_3
|
| Called during boot.
INITRESOURCES_CONT_3:
        MOVE.L  (ROMBase).w,A2                  | A2 = ROM base address
        ADDA.L  0x1A(A2),A2                     | A2 -> ROM resource header: X, Y, then the map
        MOVE    (A2)+,D1                        | skip X (number of ROM resources)
        MOVEQ.L #0x0,D2                         | Clear D2 for zero-extending the size word
        MOVE    (A2)+,D2                        | D2 = size of ROM resource map data (word)
        MOVE.L  D2,D0                           | D0 = size of ROM resource map data (long)
        MOVE.L  (ROMMapHandle).w,A0             | A0 = handle for the RAM copy of the ROM resource map
        MOVE.L  A0,A4                           | A4 = save handle for later use
        _SetHandleSize                          | _SetHandleSize: resize ROM Map handle to fit the map data
        MOVE.L  D2,D0                           | D0 = size of map data again for BlockMove
        MOVE.L  (A4),A1                         | A1 = destination pointer (dereferenced handle)
        MOVE.L  A2,A0                           | A0 = source pointer (current position in ROM map data)
        _BlockMove                              | _BlockMove: copy the ROM resource map data into the handle
        MOVE    #0x1,0x14(A1)                   | Set file reference number of the new map to 1 (ROM)
        BSR     RESMGR_CONT_3                   | A2 = first reference entry, D4 = entries - 1
INITRESOURCES_LOOP:
        MOVE.B  0x4(A2),D1                      | D1 = resource attributes byte from reference list entry
        BSR     RESMGR_OK_4                     | set up rHndl: master pointer into the ROM data
        ADDA    #0xC,A2                         | A2 = advance to next resource reference list entry (12 bytes)
        DBF     D4,INITRESOURCES_LOOP           | loop through all reference entries
        RTS                                     | Return from subroutine

| ----------------------------------------------------------
|
| INITRESOURCES_CONT_4
|
| Called during boot.
INITRESOURCES_CONT_4:
        ST.B    (ResLoad).w                     | Set ResLoad flag to TRUE (temporarily enable resource loading)
| INITRESOURCES_CONT_5 -- preload flagged resources.
INITRESOURCES_CONT_5:
        BSR     RESMGR_CONT                     | GetMap: find the map of refNum D6
        BMI.B   INITRESOURCES_ERR               | no such map: exit
        BSR     RESMGR_CONT_3                   | A2 = first reference entry, D4 = entries - 1
        BMI.B   INITRESOURCES_ERR               | no entries: exit
INITRESOURCES_LOOP_2:
        ADDQ.W  #0x8,A2                         | A2 -> rHndl (+8) of the reference entry
        CLR.L   (A2)+                           | Clear the handle field in the resource reference list entry
        DBF     D4,INITRESOURCES_LOOP_2         | loop through all reference entries
        TST.B   (ResLoad).w                     | Check if ResLoad was originally TRUE
        BEQ.B   INITRESOURCES_ERR               | ResLoad FALSE: no preloading
        BSR.B   P_SuperLoad                     | SuperLoad (via jSuperLoad): fast preload
        BEQ.B   INITRESOURCES_ERR               | EQ: resources preloaded, done
        MOVEQ.L #0x2,D1                         | D1 = resPreload (rAttr bit 2) for FirstRes
        BSR     FINDNEXT_FROM_START             | FirstRes: first resPreload entry in file order
        BMI.B   INITRESOURCES_ERR               | none: done
INITRESOURCES_RETRY:
        BSR     P_CheckLoad                     | CheckLoad: load this resource
        MOVEQ.L #0x2,D1                         | D1 = resPreload (rAttr bit 2)
        BSR     FINDNEXT_CUR_OFS                | NextRes: next resPreload entry in file order
        BEQ.B   INITRESOURCES_RETRY             | found one: load it
INITRESOURCES_ERR:
        RTS                                     | Return from subroutine

| ----------------------------------------------------------
|
| P_Super Load
|
| Called during boot.
P_SuperLoad:
        MOVE.L  (0x7E4).w,A0                    | A0 = Get address from jSuperLoad vector
        JMP     (A0)                            | Jump to the SuperLoad patch routine

| ----------------------------------------------------------
|
| Super Load
|
| Called during boot.
SuperLoad:
        BSR     SUPERLOAD_CONT_3                | read the preload data into a buffer (D7)
        BMI     RESMGR_ERR                      | no preload key or no room: fail
        BSR     RETURNS_24                      | Find first resource in the current map
        MOVE.L  (A4),A1                         | A1 = pointer to the resource map data
SUPERLOAD_NEXT:
        MOVE.L  0x4(A2),D0                      | D0 = rLocn (+$4): attributes + data offset
        AND.L   (Lo3Bytes).w,D0                 | D0 = offset of the data in the file
        CMP.L   (RMgrHiVars_LastResType).w,D0   | beyond the data read into the buffer?
        BGE.B   SUPERLOAD_SKIP                  | yes: not in the buffer, skip it
        MOVE.L  (TheZone).w,-(SP)               | Save current heap zone
        BTST    #0x6,0x4(A2)                    | Test resSysHeap attribute (bit 6)
        BEQ.B   SUPERLOAD_NO                    | If not set, use application heap
        MOVE.L  (SysZone).w,(TheZone).w         | If set, switch to system heap
SUPERLOAD_NO:
        MOVE.L  0x4(A2),D2                      | D2 = rLocn (+$4)
        AND.L   (Lo3Bytes).w,D2                 | D2 = offset of the data in the file
        BSR.B   SUPERLOAD_RETRY                 | D0 = data length, A0 = data in the buffer
        BTST    #0x4,0x4(A2)                    | test resLocked (rAttr bit 4)
        SUBA.L  (A4),A2                         | A2 = offset of current resource reference entry from map start
        SUBA.L  (A4),A3                         | A3 = type list ptr as offset (map may move)
        BEQ.B   SUPERLOAD_NO_2                  | not locked: allocate a normal handle
        _NewPtr                                 | locked: allocate the block low (nonrelocatable)
        BMI.B   SUPERLOAD_ERR                   | If allocation fails, branch to error handler
        MOVE.L  A0,A1                           | A1 = the new pointer
        _NewEmptyHandle                         | empty handle (master pointer) for the block
        MOVE.L  A0,D1                           | D1 = the new handle
        MOVE.L  A1,(A0)                         | Store the pointer in the handle
        MOVE.L  A0,D0                           | D0 = the new handle
        SUB.L   -(A1),D0                        | A1 -> block header +4 (zone ptr); D0 = relative handle
        BSET    #0x7,-0x4(A1)                   | block header tag byte: set bit 7
        BCLR    #0x6,-0x4(A1)                   | clear bit 6: block type 10 = relocatable
        MOVE.L  D0,(A1)+                        | block header +4 := relative handle
        BRA.B   SUPERLOAD_CONT                  | Continue to copy data

| ----------------------------------------------------------
|
| SUPERLOAD_NO_2
|
SUPERLOAD_NO_2:
        _NewHandle                              | _NewHandle: Allocate a relocatable block for the resource data
        BMI.B   SUPERLOAD_ERR                   | If allocation fails, branch to error handler
        MOVE.L  A0,D1                           | D1 = the new handle
        MOVE.L  (A0),A1                         | A1 = pointer to the data (dereference handle)
SUPERLOAD_CONT:
        BSR.B   SUPERLOAD_RETRY                 | A0 = data in the buffer, D0 = length (again)
        _BlockMove                              | copy the data from the buffer to the block
        ADDA.L  (A4),A2                         | A2 = restore absolute pointer to reference entry
        ADDA.L  (A4),A3                         | A3 = type list pointer again
        MOVE.L  D1,0x8(A2)                      | Store the new handle in the resource reference list entry
        MOVE.L  D1,A0                           | A0 = the new handle
        MOVE.B  0x4(A2),D1                      | D1 = resource attributes byte
        BSR     CHECKLOAD_CONT_3                | Set the attributes (e.g., locked, purgeable) on the new handle
        MOVE.L  (SP)+,(TheZone).w               | Restore the original heap zone
SUPERLOAD_SKIP:
        BSR     RETURNS_28                      | Advance to the next resource in the map
        BPL.B   SUPERLOAD_NEXT                  | If not end of map, loop to process next resource
        MOVE.L  D7,A0                           | A0 = preload buffer handle
        _DisposeHandle                          | free the preload buffer
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        RTS                                     | return from SUPERLOAD_SKIP

| ----------------------------------------------------------
|
| SUPERLOAD_ERR
|
SUPERLOAD_ERR:
        MOVE.L  (SP)+,(TheZone).w               | Restore the original heap zone
        MOVE.L  D7,A0                           | A0 = preload buffer handle
        _DisposeHandle                          | free the preload buffer
        BRA     RESMGR_ERR                      | Branch to common error exit

| SUPERLOAD_RETRY -- A0 = preload buffer + D2: read the length word.
| ----------------------------------------------------------
|
| SUPERLOAD_RETRY
|
SUPERLOAD_RETRY:
        MOVE.L  D7,A0                           | A0 = preload buffer handle
        MOVE.L  (A0),A0                         | A0 = buffer (resource data from the file)
        ADDA.L  D2,A0                           | A0 -> this resource: length word, then data
| SUPERLOAD_CONT_2 -- read 4 bytes from A0 as big-endian long.
SUPERLOAD_CONT_2:
        MOVE.B  (A0)+,D0                        | Read MSB of data length
        LSL     #0x8,D0                         | Shift to bits 23-16
        MOVE.B  (A0)+,D0                        | Read byte 2 of data length
        SWAP    D0                              | Move word to high word of D0
        MOVE.B  (A0)+,D0                        | Read byte 3 of data length
        LSL     #0x8,D0                         | Shift to bits 7-0 of low word
        MOVE.B  (A0)+,D0                        | Read LSB of data length
        RTS                                     | Return with data length in D0

| ----------------------------------------------------------
|
| SUPERLOAD_CONT_3
|
| Called during boot.
SUPERLOAD_CONT_3:
        TST.L   (RMgrHiVars_LastResType).w      | preload key valid (HSCache, set by NewMap)?
        BEQ.B   SUPERLOAD_ERR_2                 | no: old file format, no SuperLoad
        MOVEQ.L #0x0,D7                         | D7 = 0 (initialize max available memory)
        MOVE.L  A7,D0                           | D0 = current stack pointer
        AND.L   (Lo3Bytes).w,D0                 | Mask to 24-bit address
        SUB.L   (MinStack).w,D0                 | D0 = available stack space
        CMP.L   (ApplLimit).w,D0                | Is stack pointer above application memory limit?
        BCS.B   SUPERLOAD_OK                    | If so, stack is within bounds
        MOVE.L  (ApplLimit).w,D0                | If not, use ApplLimit as effective top of stack
SUPERLOAD_OK:
        SUB.L   (HeapEnd).w,D0                  | D0 = memory between top of heap and stack
        BLE.B   SUPERLOAD_SKIP_2                | If no space, skip
        CMPI.L  #0xC,D0                         | Is there at least 12 bytes?
        BLS.B   SUPERLOAD_SKIP_2                | If not, skip
        MOVE.L  D0,D7                           | D7 = potential free memory block size
SUPERLOAD_SKIP_2:
        _MaxBlock                               | _MaxBlock: Get size of largest free block in the heap
        CMP.L   D7,D0                           | Is largest heap block bigger than stack-heap gap?
        BLE.B   SUPERLOAD_NO_3                  | If not, keep the stack-heap gap size
        MOVE.L  D0,D7                           | If so, use the larger heap block size
SUPERLOAD_NO_3:
        MOVE.L  (IllegalInstructionVector).w,D0 | reads absolute $10 (later code: HSCache+preExtra)
        BSR.B   SUPERLOAD_CONT_5                | does a buffer that big fit (SizeFits)?
        BPL.B   SUPERLOAD_CONT_4                | If enough memory, proceed
        MOVE.L  (AddressErrorVector).w,D0       | reads absolute $C (later code: HSCache+preUnLock)
        BSR.B   SUPERLOAD_CONT_5                | does that fit?
        BPL.B   SUPERLOAD_CONT_4                | If enough memory, proceed
        MOVE.L  (BusErrorVector).w,D0           | reads absolute $8 (later code: HSCache+preLock)
        BSR.B   SUPERLOAD_CONT_5                | does that fit?
        BMI.B   SUPERLOAD_ERR_2                 | If still not enough memory, fail
SUPERLOAD_CONT_4:
        _NewHandle                              | _NewHandle: Attempt to allocate a handle of the required size
        BMI.B   SUPERLOAD_ERR_2                 | If allocation fails, exit with error
        _DisposeHandle                          | _DisposeHandle: Immediately free it (this was just a test)
        MOVE.L  D1,D0                           | D0 = number of bytes to read
        _NewHandle                              | _NewHandle: Allocate the handle for real
        BMI.B   SUPERLOAD_ERR_2                 | If allocation fails, exit with error
        MOVE.L  D1,D0                           | D0 = number of bytes to read
        MOVE.L  A0,D7                           | D7 = preload buffer handle
        MOVE.L  (A0),D1                         | D1 = pointer to the allocated block
        MOVE.L  (A4),A0                         | A0 = pointer to the current resource map
        MOVE.L  (A0),D2                         | D2 = resDataOffset (map +$0): file position
        BSR     CHECKLOAD_CONT_10               | RdData: read the resource data into the buffer
        BEQ.B   SUPERLOAD_OK_2                  | If read was successful, continue
        MOVE.L  D7,A0                           | If read failed, A0 = handle to dispose
        _DisposeHandle                          | _DisposeHandle: Free the allocated handle
SUPERLOAD_ERR_2:
        MOVEQ.L #-0x1,D0                        | D0 = -1 (error code)
SUPERLOAD_OK_2:
        RTS                                     | return from SUPERLOAD_OK_2

| SUPERLOAD_CONT_5 -- SizeFits: does a D0-byte buffer (twice, + map) fit?
| ----------------------------------------------------------
|
| SUPERLOAD_CONT_5
|
SUPERLOAD_CONT_5:
        MOVE.L  D0,(RMgrHiVars_LastResType).w   | Store required size in a global variable
        BEQ     RESMGR_ERR                      | If required size is 0, branch to error
        BMI.B   SUPERLOAD_EXIT                  | If required size is negative, it's a flag, just return
        MOVE.L  D0,D1                           | D1 = required size
        ADD.L   D0,D0                           | D0 = required size * 2
        MOVE.L  (A4),A0                         | A0 = pointer to current map
        ADD.L   0xC(A0),D0                      | D0 = (size * 2) + map data length
        CMP.L   D0,D7                           | Compare required memory (D0) with available memory (D7)
SUPERLOAD_EXIT:
        RTS                                     | Return (condition codes will be set by CMP)

| ----------------------------------------------------------
|
| P_New Map
|
| Called during boot.
P_NewMap:
        MOVE.L  (0x7EC).w,A0                    | A0 = Get address from jNewMap vector
        JMP     (A0)                            | Jump to the NewMap patch routine

| ----------------------------------------------------------
|
| New Map
|
| Called during boot.
NewMap:
        CLR.L   (RMgrHiVars_LastResType).w      | invalidate the preload key / cache (HSCache)
        CLR.L   (RMgrLastResHand).w             | Clear last resource handle cache
        MOVEQ.L #0x24,D0                        | 36 = file header (16) + preload key (20)
        _NewHandle                              | _NewHandle: Allocate a handle for the new resource map header
        MOVE    D0,(ResErr).w                   | Store result code in ResErr
        BMI     NEWMAP_ERR_3                    | If allocation failed, branch to error handler
        MOVE.L  A0,A4                           | A4 = the new resource map handle
        BSR     CHECKLOAD_CONT_9                | SetFileIO: A0 = I/O block in the frame
        BSR     RSRCZONEINIT_CONT_2             | ORFCommon: open the resource fork, D6 = refNum
        BEQ.B   NEWMAP_CONT                     | If successful, proceed to read the map
        CMPI    #-0x31,D0                       | opWrErr (-49): file already open?
        BNE     NEWMAP_ERR_2                    | If not, go to generic error handler
        MOVEM.L D6/A2-A4,-(SP)                  | Save registers
        BSR     RESMGR_CONT                     | GetMap: is there a map for refNum D6?
        MOVEM.L (SP)+,D6/A2-A4                  | Restore registers
        BNE     NEWMAP_ERR_2                    | no map: error
        CLR     (ResErr).w                      | Clear error code
        MOVE.L  A4,A0                           | A0 = handle to dispose
        _DisposeHandle                          | _DisposeHandle: Free the allocated map header
        RTS                                     | return from NewMap

| ----------------------------------------------------------
|
| NEWMAP_CONT
|
| Called during boot.
NEWMAP_CONT:
        _GetEOF                                 | _GetEOF: Get the end-of-file position
        MOVE    #-0x27,(ResErr).w               | assume eofErr (-39): empty fork
        TST.L   0x1C(A0)                        | Check the file's logical EOF
        BEQ.B   NEWMAP_ERR                      | If file is empty, it's an error
        MOVEQ.L #0x24,D0                        | 36 = file header + preload key
        MOVE.L  (A4),A1                         | A1 = pointer to the map header
        MOVE.L  A1,D1                           | D1 = pointer to the map header
        MOVEQ.L #0x0,D2                         | D2 = 0: from the start of the file
        BSR     CHECKLOAD_CONT_10               | RdData: header + preload key into the map handle
        BMI.B   NEWMAP_ERR                      | If read fails, branch to error handler
        MOVE.L  A1,A0                           | A0 = pointer to map header
        ADDA.L  #0x10,A0                        | A0 -> preload key (after the 16-byte header)
        LEA.L   (RMgrHiVars_LastResType).w,A1   | A1 = HSCache
        MOVEQ.L #0x14,D0                        | D0 = 20 bytes to move
        _BlockMove                              | copy the 20-byte preload key to HSCache
        MOVE.L  A0,A1                           | A1 -> preload key
        SUBA.L  #0x10,A1                        | A1 -> file header again
        BSR.B   NEWMAP_RETRY                    | PreFormat: is the preload key valid?
        MOVEQ.L #0xC,D1                         | D1 = 12 (header size - 4)
        MOVE.L  0x4(A1),D2                      | D2 = resMapOffset (+$4): map position in file
        ADD.L   D1,D2                           | skip the first 12 bytes of the map
        MOVE.L  0xC(A1),D4                      | D4 = mapSize (+$C)
        MOVE.L  D4,D0                           | D0 = map data length
        MOVE.L  A4,A0                           | A0 = the resource map handle
        _SetHandleSize                          | _SetHandleSize: Resize the handle to fit the entire map
        MOVE    D0,(ResErr).w                   | Store result code in ResErr
        BNE.B   NEWMAP_ERR                      | If resize failed, branch to error handler
        MOVE.L  (A4),A1                         | A1 = pointer to the resized map block
        MOVE.L  D4,D0                           | D0 = map data length
        SUB.L   D1,D0                           | D0 = map data length - 12
        ADD.L   A1,D1                           | D1 = pointer to where map data should go
        BSR     CHECKLOAD_CONT_10               | Read the actual resource map data from file
        BMI.B   NEWMAP_ERR                      | If read fails, branch to error handler
        TST.L   (RMgrHiVars_LastResType).w      | preload key valid?
        BEQ.B   NEWMAP_SKIP                     | If not, skip this part
        MOVE.L  0xC(A1),(RMgrHiVars_LastResType).w | second key (the map's mapSize field) -> HSCache
        BSR.B   NEWMAP_RETRY                    | PreFormat: check the second key
NEWMAP_SKIP:
        MOVE.L  D4,0xC(A1)                      | restore the true mapSize (+$C)
        BSR     CHECKLOAD_CONT_19               | CheckMap: is the map consistent?
        BMI.B   NEWMAP_ERR                      | If error, branch to handler
        CLR.L   0x10(A1)                        | mNext (+$10) := nil
        MOVE    D6,0x14(A1)                     | mRefNum (+$14) := file refNum
        MOVEQ.L #0x1,D0                         | D0 = 1 (success)
        RTS                                     | return from NEWMAP_SKIP

| ----------------------------------------------------------
|
| NEWMAP_ERR
|
NEWMAP_ERR:
        BSR     CHECKLOAD_CONT_9                | SetFileIO: A0 = I/O block for _Close
        _Close                                  | _Close: Close the resource file
NEWMAP_ERR_2:
        MOVE.L  A4,A0                           | A0 = handle to dispose
        _DisposeHandle                          | _DisposeHandle: Free the map header handle
NEWMAP_ERR_3:
        CLR.L   (RMgrHiVars_LastResType).w      | invalidate SuperLoad (HSCache := 0)
        CLR.L   (RMgrLastResHand).w             | Clear last resource handle cache
        MOVEQ.L #-0x1,D6                        | D6 = -1 (error)
        MOVEQ.L #-0x1,D0                        | D0 = -1 (error)
        RTS                                     | return from NEWMAP_ERR_3

| ----------------------------------------------------------
|
| NEWMAP_RETRY
|
| Called during boot.
NEWMAP_RETRY:
        MOVE.L  (RMgrHiVars_LastResType).w,D0   | D0 = preload key read from the file (HSCache)
        SUBI.L  #0x20B7A185,D0                  | = preKey ($20B7A185)?
        BEQ.B   NEWMAP_SKIP_2                   | yes: keep it
        CLR.L   (RMgrHiVars_LastResType).w      | no: invalidate SuperLoad
NEWMAP_SKIP_2:
        CLR.L   (RMgrLastResHand).w             | Clear the last resource handle cache
        RTS                                     | return from NEWMAP_SKIP_2

| ----------------------------------------------------------
|
| _RsrcZoneInit ($A996)
|
| Called during boot.
RsrcZoneInit:
        BSR     RESMGR_CONT_4                   | Initialize resource manager globals
        TST     (SysMap).w                      | Check if the system resource map exists
        BMI.B   RSRCZONEINIT_ERR                | If not, skip
        BSR.B   RSRCZONEINIT_NEXT               | Close all open resource files down to the system map
        MOVE.L  (SysMapHndl).w,A4               | A4 = handle to the system resource map
        BSR     RESMGR_CONT_3                   | A2 = first reference entry, D4 = entries - 1
        BMI.B   RSRCZONEINIT_ERR                | no entries: done
RSRCZONEINIT_LOOP:
        BTst    #0x6,0x4(A2)                    | Test resSysHeap attribute
        BNE.B   RSRCZONEINIT_CONT               | If set, keep the handle
        CLR.L   0x8(A2)                         | If not, clear the resource handle (force reload from disk)
RSRCZONEINIT_CONT:
        ADDA    #0xC,A2                         | Advance to next resource reference entry
        DBF     D4,RSRCZONEINIT_LOOP            | Loop through all resources
RSRCZONEINIT_ERR:
        BRA     RESMGR_EXIT_6                   | Branch to continue initialization

| ----------------------------------------------------------
|
| RSRCZONEINIT_NEXT
|
| Called during boot.
RSRCZONEINIT_NEXT:
        MOVE.L  (TopMapHndl).w,A0               | A0 = handle of the topmost resource map
        CMPA.L  (SysMapHndl).w,A0               | Is the top map the system map?
        BEQ.B   RSRCZONEINIT_DONE               | If yes, we are done
        MOVE.L  (A0),A0                         | A0 = pointer to the map header
        MOVE    0x14(A0),-(SP)                  | Push the file reference number
        _CloseResFile                           | _CloseResFile: Close the current top resource file
        BRA.B   RSRCZONEINIT_NEXT               | Loop to close the next one

| ----------------------------------------------------------
|
| RSRCZONEINIT_DONE
|
| Called during boot.
RSRCZONEINIT_DONE:
        RTS                                     | Return from subroutine

| ----------------------------------------------------------
|
| RSRCZONEINIT_CONT_2
|
| Called during boot.
RSRCZONEINIT_CONT_2:
        MOVE.L  A1,D0                           | D0 = file name pointer
        BTST    #0x0,D0                         | Is the address odd?
        BNE.B   OPENRF_SET_FNAME                | If so, it's an error
        BTST    #0x1D,D0                        | Test bit 29 (used for special file system calls)
        BEQ.B   OPENRF_SET_FNAME                | If clear, it's a normal pointer
        MOVEM.L A0-A1,-(SP)                     | Save registers before calling file system

| RSRCZONEINIT_CONT_2 - open resource fork, checking for printer driver
| If the resource is 'STR ' ID -8192, uses BootDrive for vRefNum
| (matches the printer driver resource file convention).
        MOVE.L  A1,A0                           | get master pointer
        _RecoverHandle                          | recover handle from master ptr
        LINK    A2,#-0xE                        | allocate locals: ID, type, name
        MOVE.L  A0,-(SP)                        | push resource handle
        PEA.L   -0x4(A2)                        | push ptr to ID result (local var)
        PEA.L   -0x8(A2)                        | push ptr to type result (local var)
        CLR.L   -(SP)                           | push nil for name
        _GetResInfo                             | get resource type and ID
        CMPI    #-0x2000,-0x4(A2)               | ID = -8192 (printer driver STR)?
        BNE.B   OPENRF_SKIP_BOOT                | no, skip BootDrive override
        CMPI.L  #0x53545220,-0x8(A2)            | type = 'STR '?

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
        MOVE    #-0x30,(ResErr).w               | assume dupFNErr (-48): fork already exists
        TST.L   ioLEOF(A0)                      | is resource fork empty (EOF=0)?
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
| mAttr (+$16) = map attributes field in the resource map.
| Called during boot.
GetResFileAttrs:
        BSR.B   STDMAPENTRY                     | StdMapEntry: find map by refnum
        MOVE.B  0x16(A3),0xB(A6)                | return map attributes byte (mAttr, +$16)
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
        MOVE.B  0x9(A6),0x16(A3)                | set map attributes byte (mAttr, +$16)
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
        RTS                                     | return from STDMAPENTRY

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
        MOVE.L  0x4(A2),D0                      | get current ref's attrs+offset (rLocn, +$4)
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
        BTst    D1,0x4(A2)                      | test attribute bit D1 in ref entry (rAttr, +$4)
        BEQ.B   FINDNEXT_FLAG_SKIP              | bit not set, skip this entry
        MOVE.L  0x4(A2),D0                      | get attrs+offset of this entry (rLocn, +$4)
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
        MOVE.L  0x4(A2),D0                      | get attrs+offset of this entry (rLocn, +$4)
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
        MOVE.L  0x4(A2),D7                      | get attrs+offset of best entry (rLocn, +$4)
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
| _UpdateResFile ($A999); the label is MacPlusROM.lst's spelling
| UpdateResFIle
|
| Called during boot.
UpdateResFIle:
        BSR     STDMAPENTRY                     | StdMapEntry: find map by refnum
        BSR     CHECKLOAD_OK_4                  | test if file is read-only
        BEQ.B   UPDRES_CHECK_CHG                | writable, proceed with update
        MOVE    #-0xC7,(ResErr).w               | mapReadErr (-199): map is read-only
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
        BCLR    #0x6,0x16(A3)                   | clear+test mapCompact flag in mAttr (+$16)
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
        MOVE.L  (A0),D7                         | D7 = resDataOffset (map +$0, old)
        SUB.L   0x4(A0),D7                      | D7 = old data offset - map offset
        BCS.B   UPDRES_CMP_START                | map offset > data offset, skip adjust
        BSR     RESMGR_CONT_3                   | count all ref entries (D4 = total)
UPDRES_ADJ_LOOP:
        ADD.L   D7,0x4(A2)                      | adjust each ref's data offset by delta (rLocn)
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
        BTst    #0x1,0x4(A2)                    | test resChanged bit in ref attrs (rAttr, +$4)
        BEQ.B   CMP_READ_SIZE                   | not changed, read size from file
        BSR     CHECKLOAD_CONT_8                | write changed resource data to disk
        MOVE.L  0x8(A2),A0                      | A0 = resource handle (rHndl, +$8)
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
        MOVE.L  0x4(A2),D7                      | D7 = current ref's attrs+offset (rLocn, +$4)
        ADD.L   D0,D7                           | D7 = offset past this resource's data
        AND.L   (Lo3Bytes).w,D7                 | mask to 24-bit offset
        BSR     FINDNEXT_FROM_CUR               | find next entry after this offset
        BMI.B   CMP_STORE_DATALEN               | no more entries, finalize compaction
CMP_GAP_CHECK:
        MOVE.L  D7,D0                           | D0 = expected write position
        SUB.L   0x4(A2),D0                      | D0 = gap between write pos and ref offset (rLocn)
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
        BTST    #0x1,0x4(A2)                    | test resChanged bit in ref attrs (rAttr, +$4)
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
        ADD.L   (A0),D2                         | D2 += resDataOffset = file position
        BSR     CHECKLOAD_EMPTY_2               | write buffer contents to file at D2
        ADD.L   D0,D7                           | advance file write position
        MOVE.L  A3,A0                           | A0 = compaction buffer handle
        _DisposeHandle                          | free the compaction buffer
        MOVE.L  (A4),A3                         | A3 = dereferenced map pointer
CMP_STORE_DATALEN:
        MOVE.L  D7,0x8(A3)                      | store new data length in map header (dataSize, +$8)
CMP_WRITE_MAP:
        BClr    #0x5,0x16(A3)                   | clear+test mapChanged flag in mAttr (+$16)
        BEQ.B   CMP_MAP_EXIT                    | was not set, skip map rewrite
        MOVE.L  0x8(A3),D2                      | D2 = data length (dataSize, +$8)
        ADD.L   (A3),D2                         | D2 += resDataOffset = map file position
        MOVE.L  D2,0x4(A3)                      | update map offset in map header (resMapOffset, +$4)
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
        MOVE.L  0x8(A2),A0                      | A0 = resource handle (rHndl, +$8)
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
        MOVE.L  0x8(A2),A0                      | A0 = resource handle (rHndl; may have moved)
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
        MOVEQ.L #-0x3,D1                        | D1 = $FD: mask that clears resChanged (bit 1)
        LEA.L   0x4(A2),A0                      | A0 = ptr to ref attrs+offset field (rLocn, +$4)
        AND.B   (A0),D1                         | D1 = old attributes without resChanged
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
        MOVE.L  0x4(A2),D0                      | get ref attrs+offset (rLocn, +$4)
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
        MOVE.L  0x4(A2),D0                      | reload ref attrs+offset (rLocn)
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit offset
        MOVE.L  D0,D5                           | D5 = file position of this resource
        BSR.B   CMP_READ_FILE                   | read resource data from file into buffer
CMP_READ_UPD_OFS:
        MOVE.L  0x4(A2),D0                      | reload ref attrs+offset (rLocn)
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
        MOVE.L  0x4(A2),D5                      | D5 = new file position for this resource (rLocn)
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
        MOVE    #-0xC7,(ResErr).w               | mapReadErr (-199): no bytes read, abort
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
        SUB.L   (A0),D0                         | D0 -= resDataOffset = remaining bytes
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit count
        MOVE.L  D3,D1                           | D1 = buffer end address
        SUB.L   A1,D1                           | D1 = available buffer space
        CMP.L   D1,D0                           | more data than buffer can hold?
        BLE.B   CMP_READF_CLAMP                 | no, D0 fits in buffer
        MOVE.L  D1,D0                           | yes, clamp to buffer capacity
CMP_READF_CLAMP:
        MOVE.L  A1,D1                           | D1 = buffer address (read destination)
        MOVE.L  D5,D2                           | D2 = file read position
        ADD.L   (A0),D2                         | D2 += resDataOffset = file position
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
        ADD.L   (A0),D2                         | D2 += resDataOffset = file position
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
        MOVE.L  0x10(A3),A0                     | A0 = this map's next-map link (mNext, +$10)
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
| _Count1Resources ($A80D): count the resources of a given type in the
| current resource file only (Mac Plus addition, Inside Macintosh IV)
| Pascal: FUNCTION Count1Resources(theType: ResType): INTEGER;
| Entry: 4(SP).L = theType, 8(SP).W = space for the function result
| Exit:  function result = number of resources of theType; 4 bytes popped
| Sets RMgrCurOnly and falls into CountResources, which walks all open maps
| from the top map (only CurMap when RMgrCurOnly is set), looks theType up
| in each type list (RETURNS_26) and adds that entry's count-1 field + 1.
|
Count1Resources:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| CountResources -- _CountResources ($A99C): same count over all open files.
| Pascal: FUNCTION CountResources(theType: ResType): INTEGER;
| Called 3,781 times during 30s boot-to-Finder.
CountResources:
        BSR     RESMGR_CONT_6                   | prologue; does not clear RMgrCurOnly
        MOVE.L  (A0),D3                         | D3 = resource type to count
        MOVEQ.L #0x0,D1                         | D1 = running count (starts at 0)
        BSR     RETURNS_20                      | first map: TopMap (CurMap if RMgrCurOnly)
COUNTRES_LOOP:
        BSR     RETURNS_26                      | find type D3 in this map's type list
        BMI.B   COUNTRES_NEXTMAP                | type not found in this map
        ADD     0x4(A2),D1                      | D1 += count-1 for this type
        ADDQ.W  #0x1,D1                         | adjust for count-1 encoding (+1)
COUNTRES_NEXTMAP:
        BSR     RETURNS_22                      | next map (none if RMgrCurOnly)
        BEQ.B   COUNTRES_LOOP                   | more maps, keep counting
        MOVE    D1,0xC(A6)                      | store total count as function result
        BRA     RESMGR_EXIT_5                   | StdFourExit

| ----------------------------------------------------------
|
| _Get1IxResource ($A80E): get the index'th resource of a given type in
| the current resource file only (Mac Plus addition, Inside Macintosh IV)
| Pascal: FUNCTION Get1IndResource(theType: ResType; index: INTEGER): Handle;
| Apple source name: Get1IndResource (System 7.1 ResourceMgr.a, MacSEROM.lst)
| Entry: 4(SP).W = index, 6(SP).L = theType, 10(SP).L = space for the result
| Exit:  function result = resource handle (NIL if none); 6 bytes popped
| Sets RMgrCurOnly and falls into GetIndResource, which counts entries of
| theType map by map (top map first; only CurMap when RMgrCurOnly is set)
| up to entry number index and loads it via CheckLoad. A call for index
| n+1 after index n (same type and mode) resumes at the cached position.
| index > count: resNotFound. index <= 0: resNotFound, and the result is
| left as pushed by the caller (not cleared).
|
Get1IxResource:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| GetIndResource -- _GetIndResource ($A99D): same over all open files.
| Pascal: FUNCTION GetIndResource(theType: ResType; index: INTEGER): Handle;
| Called 11,465 times during 30s boot-to-Finder.
GetIndResource:
        BSR     RESMGR_CONT_6                   | prologue; does not clear RMgrCurOnly
        MOVE    (A0)+,D7                        | D7 = 1-based index of desired resource
        BLE     GETIND_NOTFOUND                 | index <= 0: resNotFound (result not cleared)
        MOVE.L  (A0)+,D3                        | D3 = resource type to search for
        CLR.L   (A0)+                           | clear result handle (assume not found)
        MOVE.B  (RMgrCurOnly).w,D0              | D0 = current "search current only" flag
        CMP.B   (RMgrLastCurOnly).w,D0          | same search mode as last call?
        BNE.B   GETIND_FRESH                    | no, do a fresh search
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
        BSR     RETURNS_20                      | first map: TopMap (CurMap if RMgrCurOnly)
GETIND_FIND_TYPE:
        BSR     RETURNS_26                      | find type D3 in this map's type list
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
        BSR     RETURNS_22                      | next map (none if RMgrCurOnly)
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
| _Count1Types ($A81C): count the distinct resource types in the current
| resource file only (Mac Plus addition, Inside Macintosh IV)
| Pascal: FUNCTION Count1Types: INTEGER;
| Entry: 4(SP).W = space for the function result (no parameters)
| Exit:  function result = number of distinct resource types
| Sets RMgrCurOnly and falls into CountTypes. COUNT_UNIQ_TYPES pushes every
| type not seen before onto the stack (only CurMap's types when
| RMgrCurOnly is set); the following UNLK A6 discards that list again.
|
Count1Types:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| CountTypes -- _CountTypes ($A99E): FUNCTION CountTypes: Integer;
CountTypes:
        BSR     RESMGR_CONT_6                   | prologue; does not clear RMgrCurOnly
        BSR.B   COUNT_UNIQ_TYPES                | push the distinct types, D7 = their count
        UNLK    A6                              | tear down COUNT_UNIQ_TYPES's local frame
        MOVE    D7,0x8(A6)                      | store unique type count as result
        BRA     RESMGR_EXIT_6                   | epilogue: pop 0 bytes, return

| ----------------------------------------------------------
|
| COUNT_UNIQ_TYPES - collect the distinct resource types on the stack
|
| Walks the maps from RETURNS_20 (all open maps, or only CurMap when
| RMgrCurOnly is set) and pushes each type not already on the stack
| (linear search). Makes its own LINK A6 frame and returns via JMP (A0)
| with the list still on the stack: D7 = number of types, 0(SP) = the
| type found last. The caller removes the list with UNLK A6.
| Apple source name: CountITypes (System 7.1 ResourceMgr.a)
| Called during boot.
COUNT_UNIQ_TYPES:
        MOVE.L  (SP)+,A0                        | save return address in A0
        LINK    A6,#0x0                         | create frame (types pushed below SP)
        MOVEQ.L #0x0,D7                         | D7 = unique type count (starts at 0)
        BSR     RETURNS_20                      | first map: TopMap (CurMap if RMgrCurOnly)
CNTTYPE_MAP_LOOP:
        BSR     RETURNS_23                      | this map's type list: A2, D5 = count-1
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
        BSR     RETURNS_22                      | next map (none if RMgrCurOnly)
        BEQ.B   CNTTYPE_MAP_LOOP                | found map, scan its type list
        JMP     (A0)                            | return to caller (saved return addr)

| ----------------------------------------------------------
|
| _Get1IxType ($A80F): get the index'th distinct resource type in the
| current resource file only (Mac Plus addition, Inside Macintosh IV)
| Pascal: PROCEDURE Get1IndType(VAR theType: ResType; index: INTEGER);
| Apple source name: Get1IndType (System 7.1 ResourceMgr.a, MacSEROM.lst)
| Entry: 4(SP).W = index, 6(SP).L = address of theType
| Exit:  theType = the type, or 0 (four NUL bytes) if index is out of
|        range (ResErr is not set); 6 bytes popped
| Sets RMgrCurOnly and falls into GetIndType, which builds the type list
| with COUNT_UNIQ_TYPES and copies entry index-1 of it (index 1 = the
| type found last).
|
Get1IxType:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| GetIndType -- _GetIndType ($A99F): PROCEDURE GetIndType (VAR theType: ResType; index: Integer);
GetIndType:
        BSR     RESMGR_CONT_6                   | prologue; does not clear RMgrCurOnly
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
| _Unique1ID ($A810): return a resource ID that is not in use for a given
| type in the current resource file (Mac Plus addition, Inside Macintosh IV)
| Pascal: FUNCTION Unique1ID(theType: ResType): INTEGER;
| Entry: 4(SP).L = theType, 8(SP).W = space for the function result
| Exit:  function result = unused ID in 0..32767; 4 bytes popped
| Sets RMgrCurOnly and falls into UniqueID: the candidate (initially the
| low word of Ticks) is advanced by _Random and ANDed with $7FFF until no
| map in the walk (only CurMap when RMgrCurOnly is set) has that ID for
| theType. IDs 0..127 are not excluded (IM: call again if below 128).
|
Unique1ID:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| UniqueID -- _UniqueID ($A9C1): FUNCTION UniqueID (theType: ResType): Integer;
UniqueID:
        BSR     RESMGR_CONT_6                   | prologue; does not clear RMgrCurOnly
        MOVE    (Ticks_LoWord).w,D7             | D7 = initial seed from tick counter
UNIQID_RETRY:
        BSR     RETURNS_20                      | restart at first map (CurMap if RMgrCurOnly)
        SUBQ.W  #0x2,SP                         | allocate space for Random result
        _Random                                 | generate random word on stack
        ADD     (SP)+,D7                        | add randomness to candidate ID
        ANDI    #0x7FFF,D7                      | force positive (resource IDs 0-32767)
        MOVE.L  0x8(A6),D3                      | D3 = resource type from parameter
        MOVE    D7,D2                           | D2 = candidate ID to test
UNIQID_CHECK:
        BSR     RETURNS_26                      | find type D3 in this map's type list
        BMI.B   UNIQID_NEXTMAP                  | type not found, ID is unique here
        BSR     RETURNS_27                      | get ref list for this type
        BSR     RETURNS_25                      | search for ID D2 in ref list
        BEQ.B   UNIQID_RETRY                    | ID already exists, generate new one
UNIQID_NEXTMAP:
        BSR     RETURNS_22                      | next map (none if RMgrCurOnly)
        BEQ.B   UNIQID_CHECK                    | more maps, keep checking uniqueness
        MOVE    D2,0xC(A6)                      | store unique ID as function result
        BRA     RESMGR_EXIT_5                   | StdFourExit

| ----------------------------------------------------------
|
| _Get1Resource ($A81F): get a resource by type and ID from the current
| resource file only (Mac Plus addition, Inside Macintosh IV)
| Pascal: FUNCTION Get1Resource(theType: ResType; theID: INTEGER): Handle;
| Entry: 4(SP).W = theID, 6(SP).L = theType, 10(SP).L = space for the result
| Exit:  function result = resource handle (NIL if none); 6 bytes popped
| Sets RMgrCurOnly and falls into GetResource, which searches CurMap's map
| (the top map if CurMap is not found) and the maps after it; with
| RMgrCurOnly set only that first map. A hit is cached (RESMGR_CONT_14)
| and loaded via CheckLoad. Not found: NIL; ResErr is not set (noErr).
|
Get1Resource:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| GetResource -- _GetResource ($A9A0): searches CurMap and all files opened
| before it.
| Pascal: FUNCTION GetResource(theType: ResType; theID: INTEGER): Handle;
| Called 11,438 times during 30s boot-to-Finder.
GetResource:
        BSR     RESMGR_CONT_6                   | prologue; does not clear RMgrCurOnly
        BSR     RETURNS_21                      | start the search at CurMap's map
        BPL.B   GETRES_SEARCH                   | found CurMap, start search there
        BSR     RETURNS_20                      | CurMap not found: start at the top map
GETRES_SEARCH:
        MOVE    (A0)+,D2                        | D2 = resource ID to find
        MOVE.L  (A0)+,D3                        | D3 = resource type to find
        CLR.L   (A0)                            | clear result handle (assume not found)
GETRES_FIND_TYPE:
        BSR     RETURNS_26                      | find type D3 in this map's type list
        BMI.B   GETRES_NEXTMAP                  | type not in this map
        BSR     RETURNS_27                      | get ref list for this type
        BSR     RETURNS_25                      | search for ID D2 in ref list
        BEQ.B   GETRES_FOUND                    | found it, go load
GETRES_NEXTMAP:
        BSR     RETURNS_22                      | next map (none if RMgrCurOnly)
        BEQ.B   GETRES_FIND_TYPE                | more maps, keep searching
        BRA.B   GETRES_EXIT                     | not found: NIL, ResErr stays noErr

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
| _Get1NamedResource ($A820): get a resource by type and name from the
| current resource file only (Mac Plus addition, Inside Macintosh IV)
| Pascal: FUNCTION Get1NamedResource(theType: ResType; name: Str255): Handle;
| Entry: 4(SP).L = name pointer, 8(SP).L = theType, 12(SP).L = result space
| Exit:  function result = resource handle (NIL if none); 8 bytes popped
| Sets RMgrCurOnly and falls into GetNamedResource: for each map from
| CurMap on (only CurMap when RMgrCurOnly is set) the name of every entry
| of theType is compared with _CmpString (ignores case); the first
| match is loaded via CheckLoad. Not found: NIL and ResErr = resNotFound.
| The loop continues at RESMGR_SKIP.
|
Get1NamedResour:                                | MacPlusROM.lst spelling (15 characters) of Get1NamedResource
Get1NamedResource:
        ST.B    (RMgrCurOnly).w                 | restrict search to current map only
| GetNamedResource -- _GetNamedResource ($A9A1): FUNCTION GetNamedResource (theType: ResType; name: Str255): Handle;
GetNamedResource:
        BSR     RESMGR_CONT_6                   | prologue; does not clear RMgrCurOnly
        BSR.B   RETURNS_21                      | set up search from CurMap
        MOVE.L  (A0),A1                         | A1 = pointer to name string to find
        CLR.L   0x10(A6)                        | clear result handle (assume not found)
GETNAMED_LOOP:
        MOVE.L  0xC(A6),D3                      | D3 = resource type from parameter
        BSR     RETURNS_26                      | find type D3 in this map's type list
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
|
| GetNamedResource (continued): the name did not
| match -- try the next entry of the same type (RETURNS_28), then the next
| map (RETURNS_22; there is none for Get1NamedResource).
RESMGR_SKIP:
        BSR     RETURNS_28                      | advance to next ref entry in type list
        BEQ.B   GETNAMED_CMP_NAME               | same type: compare this entry's name
RESMGR_NEXT:
        BSR.B   RETURNS_22                      | next map (none if RMgrCurOnly)
        BEQ.B   GETNAMED_LOOP                   | found map - scan its type list
        MOVE    #-0xC0,(ResErr).w               | resNotFound: no more maps to search
        BRA.B   RESMGR_SKIP_2                   | skip to epilogue with resNotFound

| ----------------------------------------------------------
|
| RESMGR_FOUND - GetNamedResource: name matched, cache and load it
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
| RESMGR_CONT -- GetMap: find the map with refNum D6 (0 = SysMap).
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
| The map's mNext field (+$10) holds the next map handle.
RESMGR_FOUND_2:
        MOVE.L  0x10(A3),D0                     | get next map handle from chain link (mNext, +$10)
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
        MOVE.L  0x10(A3),A4                     | A4 = next map handle (mNext, +$10)
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
| The map's mTypes field (+$18) holds the offset to the type list.
| Returns: A2=first type entry, A3=type list base, D5=numTypes-1 (or -1).
RETURNS_23:
        MOVE.L  (A4),A3                         | dereference map handle
        ADDA    0x18(A3),A3                     | add type list offset (mTypes, +$18)
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
| Sets up a LINK frame whose 50 bytes of locals are an I/O parameter block.
| If ROMMapInsert is set, inserts ROM map into chain before searching.
| Returns A0 = 8(A6) = address of the last-pushed trap parameter.
| The seven search traps (CountResources ... GetNamedResource) enter at
| RESMGR_CONT_6, so RMgrCurOnly set by their "1" entry points survives.
| Apple source names: StdZEntry, Std1Entry, StdEntry (System 7.1 ResourceMgr.a)
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
        CLR     -0x1C(A6)                       | ioVRefNum (block +$16) := 0 (default volume)
        CLR     -0x18(A6)                       | ioVersNum/ioPermssn (block +$1A) := 0
        MOVE.B  (RMgrPerm).w,-0x17(A6)          | ioPermssn (block +$1B) := RMgrPerm
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
        ADDQ.W  #0x2,A0                         | skip the ref list offset: A0 -> next type entry
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
        ADDA.L  -0x4(A1),A0                     | A0 = zone + relative handle (block header +4)
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
| CHECKLOAD_CONT_3 - SetPL: master pointer flags of handle A0 from rAttr D1
|
| Called during boot.
CHECKLOAD_CONT_3:
        LSL.B   #0x3,D1                         | resLocked (bit 4) -> bit 7, resPurgeable (bit 5) -> X
        BPL.B   CHECKLOAD_NO_2                  | not locked
        MOVEQ.L #-0x7F,D1                       | D1 = $81: locked
        BRA.B   CHECKLOAD_CONT_4                | go set handle flags

| ----------------------------------------------------------
|
| CHECKLOAD_NO_2 - set handle flags for a resource that is not locked
|
| Called during boot.
CHECKLOAD_NO_2:
        MOVEQ.L #-0x80,D1                       | D1 = $80: not locked
CHECKLOAD_CONT_4:
        ROXR.B  #0x2,D1                         | D1 = lock (7) | purge from X (6) | resource (5)
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
        BSR.B   CHECKLOAD_CONT_10               | read the 4-byte length word of the resource data
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
        ADDQ.L  #0x4,D2                         | skip past the 4-byte length word
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
        BSR.B   CHECKLOAD_EMPTY_2               | write the 4-byte length word
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
        MOVE.L  (A1)+,D0                        | D0 = resDataOffset (map +0)
        MOVE.L  (A1)+,D1                        | D1 = map offset (map header+4)
        ADD.L   (A1)+,D0                        | D0 += dataSize (map +8) = end of data
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
        ADDQ.L  #0x4,D0                         | add 4 for the length word
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
        MOVE.L  D0,A1                           | A1 = size of the resource data area
        BMI.B   CHECKLOAD_NO_4                  | negative - invalid, recalculate
        CMPA.L  D7,A1                           | is the resource offset within the data area?
        BMI.B   CHECKLOAD_NO_4                  | no - offset beyond the data area
        BSR     FINDNEXT_FROM_CUR               | find next resource's data offset
        BMI.B   CHECKLOAD_NEXT                  | no next resource - use total data length
        CMPA.L  D0,A1                           | is total data > next resource offset?
        BPL.B   CHECKLOAD_NEXT_2                | yes - use gap between resources
CHECKLOAD_NEXT:
        MOVE.L  A1,D0                           | D0 = size of the resource data area
        BRA.B   CHECKLOAD_CONT_15               | compute available space from total

| ----------------------------------------------------------
|
| CHECKLOAD_NO_4
|
CHECKLOAD_NO_4:
        BSR     FINDNEXT_FROM_CUR               | find next resource's data offset
        BPL.B   CHECKLOAD_NEXT_2                | found - use gap to next resource
        BSR.B   CHECKLOAD_CONT_12               | compute total file size (max of data+map)
        SUB.L   (A0),D0                         | subtract resDataOffset (map +0)
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
| CHECKLOAD_CONT_17 -- place the resource data at the end of the data area.
CHECKLOAD_CONT_17:
        BSR.B   CHECKLOAD_CONT_14               | D1 = new disk size (data + 4-byte prefix)
        BSR.B   CHECKLOAD_CONT_12               | D0 = total file size
        MOVE.L  (A4),A0                         | dereference map handle
        SUB.L   (A0),D0                         | D0 = file size - data base = end of data area
        MOVE.B  0x4(A2),-(SP)                   | save resAttr byte (will be overwritten)
        MOVE.L  D0,0x4(A2)                      | store new 3-byte data offset in ref entry
        MOVE.B  (SP)+,0x4(A2)                   | restore resAttr byte over offset's high byte
        ADD.L   D1,D0                           | D0 = new end of data area
        MOVE.L  D0,0x8(A0)                      | dataSize (map +8) := new end of data
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
| WRITERESOURCE_CONT - entry for SizeRsrc, MaxSizeRsrc and RsrcMapEntry
|
| Presets their LONGINT function result to -1 (0xC(SP): above this BSR's
| return address, the trap return address and the handle parameter),
| then falls into WRITERESOURCE_CONT_2.
| Apple source name: Std2ResEntry (System 7.1 ResourceMgr.a)
| Called during boot.
WRITERESOURCE_CONT:
        MOVE.L  (MinusOne).w,0xC(SP)            | preset result to -1 (for SizeRsrc etc)
| WRITERESOURCE_CONT_2 -- prologue + find the ref entry of the handle
| parameter (A1 = handle, A2 = ref entry, A4 = map handle). If it is not
| a resource (ResErr = resNotFound), drops the caller's return address
| and exits popping 4 parameter bytes.
| Apple source name: StdResEntry (System 7.1 ResourceMgr.a)
| Called by: ReleaseResource, DetachResource, ChangedResource, WriteResource, HomeResFile
WRITERESOURCE_CONT_2:
        MOVE.L  (SP)+,D0                        | pop return address
        BSR     RESMGR_CONT_5                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  D0,-(SP)                        | push return address back
        MOVE.L  A0,D0                           | tests A0 = param ptr (A6+8), not the handle
        BEQ.B   WRITERESOURCE_SKIP_2            | never taken (NIL caught by RESMGR_CONT_12)
        MOVE.L  (A0),A1                         | A1 = theResource (handle parameter)
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
| _AddReference ($A9AC): obsolete trap, kept as a stub that always fails
| PROCEDURE AddReference(theResource: Handle; theID: INTEGER; name: Str255)
| (signature as given in System 7.1 ResourceMgr.a)
| Pops its 10 bytes of parameters and returns with ResErr = addRefFailed
| (-195). The 64K ROM implemented AddReference; this ROM keeps only the
| stub because MacWrite 2.2 still calls the trap (System 7.1
| ResourceMgr.a change history, 17oct85).
|
Trap1_1AC:                                      | MacPlusROM.lst placeholder for trap $A9AC (AddReference)
AddReference:
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    #0xA,SP                         | remove 10 bytes of parameters
        MOVE.L  A0,-(SP)                        | push return address back
        MOVE    #-0xC3,(ResErr).w               | addRefFailed (-195): always fails
        BRA.B   SETRESPURGE_EXIT                | clear flags and return

| ----------------------------------------------------------
|
| _RmveReference ($A9AE): obsolete trap, kept as a stub that always fails
| PROCEDURE RmveReference(theResource: Handle)
| (signature as given in System 7.1 ResourceMgr.a)
| Pops the 4-byte handle parameter and returns with ResErr = rmvRefFailed
| (-197). Like AddReference, a working routine in the 64K ROM that this
| ROM keeps only as a stub for MacWrite 2.2.
|
Trap1_1AE:                                      | MacPlusROM.lst placeholder for trap $A9AE (RmveReference)
RmveReference:
        MOVE.L  (SP)+,(SP)                      | collapse stack: remove 4-byte handle param
        MOVE    #-0xC5,(ResErr).w               | rmvRefFailed (-197): always fails
        BRA.B   SETRESPURGE_EXIT                | clear flags and return

| ----------------------------------------------------------
|
| _GetResAttrs ($A9A6)
|
| Called during boot.
GetResAttrs:
        BSR     RESMGR_CONT_5                   | prologue: clear CurOnly, ResErr, set up frame
        MOVE.L  (A0),A1                         | A1 = theResource (handle parameter)
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
        BSR     CHECKLOAD_CONT_17               | place the resource data at the end of the data area
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
        MOVE.L  (A0),A1                         | A1 = theResource (handle parameter)
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
| _SizeRsrc ($A9A5): size of a resource's data in bytes
| Pascal: FUNCTION SizeResource(theResource: Handle): LONGINT;
| Apple source name: SizeResource (System 7.1 ResourceMgr.a, MacSEROM.lst)
| Entry: 4(SP).L = theResource, 8(SP).L = space for the function result
| Exit:  function result = size, or -1 with ResErr = resNotFound if
|        theResource is not a resource handle; 4 bytes popped
| Loaded resource: its handle size. Otherwise the 4-byte length word is
| read from the file (CHECKLOAD_CONT_5); the attribute byte is saved and
| restored around that call because CHECKLOAD_CONT_7 clears resChanged.
| SIZERSRC_EXIT is shared with MaxSizeRsrc and RsrcMapEntry.
| New in ROM with the Plus: $A9A5 is unimplemented in the 64K ROM.
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
| SIZERSRC_NO - resource not loaded: read its length word from the file
|
| Called during boot.
SIZERSRC_NO:
        MOVE.B  0x4(A2),-(SP)                   | save resAttr byte (CHECKLOAD_CONT_5 modifies it)
        BSR     CHECKLOAD_CONT_5                | D0 = 4-byte length word read from the file
        MOVE.B  (SP)+,0x4(A2)                   | restore resAttr byte
SIZERSRC_EXIT:
        MOVE.L  D0,0xC(A6)                      | store size result in return value slot
        BRA     RESMGR_EXIT_5                   | epilogue: 4 param bytes

| ----------------------------------------------------------
|
| _MaxSizeRsrc ($A821): size of a resource without reading the disk
| (Mac Plus addition, Inside Macintosh IV)
| Pascal: FUNCTION MaxSizeRsrc(theResource: Handle): LONGINT;
| Entry: 4(SP).L = theResource, 8(SP).L = space for the function result
| Exit:  function result = size, or -1 with ResErr = resNotFound if
|        theResource is not a resource handle; 4 bytes popped
| Loaded resource: its handle size. Otherwise CHECKLOAD_NO_3 computes from
| the map in memory the room between the resource's data offset and the
| next resource (or the map / end of file); that includes the 4-byte
| length word, so the result is an upper bound.
|
MaxSizeRsrc:
        BSR     WRITERESOURCE_CONT              | prologue + find ref entry, preset result=-1
        TST.L   (A1)                            | is resource data loaded?
        BNE.B   MAXSIZERSRC_OK                  | yes - get handle size
        BSR     CHECKLOAD_NO_3                  | not loaded: room up to next resource (no I/O)
        BRA.B   MAXSIZERSRC_CONT                | store result

| ----------------------------------------------------------
|
| MAXSIZERSRC_OK - resource loaded: return actual handle size
|
MAXSIZERSRC_OK:
        MOVE.L  A1,A0                           | A0 = resource handle
        _GetHandleSize                          | D0 = handle size
MAXSIZERSRC_CONT:
        BRA.B   SIZERSRC_EXIT                   | store result in return value

| ----------------------------------------------------------
|
| _RsrcMapEntry ($A9C5): offset of a resource's reference entry in its map
| Pascal: FUNCTION RsrcMapEntry(theResource: Handle): LONGINT;
| Entry: 4(SP).L = theResource, 8(SP).L = space for the function result
| Exit:  function result = offset of the reference entry from the start
|        of the resource map in memory (masked to 24 bits), or -1 with
|        ResErr = resNotFound if theResource is not a resource handle
| New in this ROM ($A9C5 is unimplemented in the 64K ROM; System 7.1
| ResourceMgr.a history, 21aug85: "added new trap called RsrcMapEntry").
| Called via the trap by PRINT_CHK_DRVR (.Print driver resource).
|
Trap1_1C5:                                      | MacPlusROM.lst placeholder for trap $A9C5 (RsrcMapEntry)
RsrcMapEntry:
        BSR     WRITERESOURCE_CONT              | prologue + find ref entry, preset result=-1
        MOVE.L  A2,D0                           | D0 = absolute ref entry address
        SUB.L   (A4),D0                         | subtract map base = relative offset
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit offset
        BRA.B   SIZERSRC_EXIT                   | store offset as result
