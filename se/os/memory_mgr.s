| Memory Manager
|
| Apple sources: MemoryMgr.a and MemoryMgrInternal.a (MacSEROM.lst
| modules HEAP, HEAPGUTS) and BlockMove.a (module BLOCK2). Manages
| heap zones for dynamic memory allocation. Provides
| NewHandle, NewPtr, DisposeHandle, DisposePtr, SetHandleSize,
| CompactMem, PurgeMem, and other routines.
|
| Zone record (Inside Macintosh: Memory, Ch 2, pp 2-20):
| TYPE Zone = RECORD
| Offset 0: bkLim Ptr first byte after zone
| Offset 4: purgePtr Ptr used internally
| Offset 8: hFstFree Ptr first free master pointer
| Offset 12: zcbFree LongInt free bytes in zone
| Offset 16: gzProc ProcPtr grow-zone function
| Offset 20: moreMast Integer master ptrs to allocate (32 sys, 64 app)
| Offset 22: flags Integer used internally
| Offset 24: cntRel Integer reserved
| Offset 26: maxRel Integer reserved
| Offset 28: cntNRel Integer reserved
| Offset 30: maxNRel Integer reserved
| Offset 32: cntEmpty Integer reserved
| Offset 34: cntHandles Integer reserved
| Offset 36: minCBFree LongInt reserved
| Offset 40: purgeProc ProcPtr purge-warning procedure
| Offset 44: sparePtr Ptr used internally (here: StdGZ, system grow-zone proc)
| Offset 48: allocPtr Ptr used internally
| Offset 52: heapData Integer first usable byte in zone
| END;
|
| Block header (24-bit mode, 8 bytes, Inside Macintosh: Memory, pp 2-22):
| Long 0 (tagBC): high byte = tag: bits 7-6 = block type (00=free,
|   01=nonrelocatable, 10=relocatable), bits 3-0 = size correction (unused
|   bytes at end); low 3 bytes = physical block size (including header)
| Long 1 (handle): relocatable block: master pointer address minus zone
|   address (relative handle); nonrelocatable block: zone address
| Minimum block size = 12 bytes.
|
| Master pointer flags (high byte, 24-bit mode):
| Bit 7: lock (1=locked, cannot be moved)
| Bit 6: purge (1=purgeable)
| Bit 5: resource (1=owned by Resource Manager)
| Low 3 bytes: address of block contents (or NIL if purged)
|
| References:
| Inside Macintosh: Memory, Ch 2: Memory Manager (pp 2-3 to 2-93)
| Inside Macintosh Vol II, Ch 1: The Memory Manager (pp 7-52)

| Apple source module: HEAP
SETAPPLBASE:
    MOVEM.L     D3/A2-A6,-(SP)                  | save regs
    MOVEA.L     (SysZone).W,A6                  | A6 = system zone
    MOVE.L      A0,D0                           | round requested base
    ADDQ.L      #0x3,D0                         | up to
    ANDI.W      #0xFFFC,D0                      | longword boundary
    MOVEA.L     D0,A0                           | A0 = aligned base
    SUBA.W      #0xC,A0                         | adjust for zone header
    CMPA.L      (A6),A0                         | below system zone end?
    BLS.B       SETAPPBASE_SKIP                 | yes, skip ->
    JSR         ZONEADJUSTEND(PC)               | extend system zone
SETAPPBASE_SKIP:
    BSR.B       SETAPPBASE_CONT                 | init application zone globals
    MOVEM.L     (SP)+,D3/A2-A6                  | restore regs
    RTS                                         | return from SetAppBase
SETAPPBASE_CONT:
    MOVE.L      A6,-(SP)                        | save A6
    _RsrcZoneInit                               | init resource manager zone
    CLR.L       (ApplZone).W                    | clear application zone
    JSR         TOMAXLIMIT(PC)                  | D2 = max application limit
    MOVE.L      D2,(ApplLimit).W                | set application limit
    MOVE.L      D2,(HighHeapMark).W             | set high heap mark
    MOVEA.L     (SysZone).W,A6                  | get system zone
    MOVEA.L     (A6),A0                         | A0 = end of system zone
    LEA.L       0xC(A0),A0                      | + 12 = start of application zone
    MOVEA.L     A0,A1                           | initial zone end
    ADDA.W      #0x1800,A1                      | + 6K initial size
    CMPA.L      D1,A1                           | fits in available memory?
    BCS.B       SETAPPBASE_OK                   | yes ->
    MOVEA.L     D1,A1                           | limit to available memory
SETAPPBASE_OK:
    CLR.L       -(SP)                           | push pGrowZone (nil)
    MOVE.W      #0x40,-(SP)                     | push cMoreMasters (64)
    MOVE.L      A1,-(SP)                        | push limitPtr
    MOVE.L      A0,-(SP)                        | push startPtr
    MOVE.L      A0,(ApplZone).W                 | set ApplZone global
    MOVEA.L     SP,A0                           | A0 = param block on stack
    _InitZone                                   | initialize application zone
    ADDA.W      #0xE,SP                         | pop params
    MOVEA.L     (TheZone).W,A6                  | get current zone
    MOVE.L      (A6),(HeapEnd).W                | set HeapEnd global
    MOVEQ.L     #0x0,D0                         | clear error
    MOVE.W      D0,(MemErr).W                   | clear MemErr
    MOVEA.L     (SP)+,A6                        | restore A6
    RTS                                         | return from SetAppBase init
INITAPPLZONE:
    MOVE.L      (IAZNotify).W,D0                | notification hook
    BLE.B       INITAPPLZONE_SKIP               | none ->
    MOVEA.L     D0,A0                           | A0 = hook address
    JSR         (A0)                            | call notification hook
INITAPPLZONE_SKIP:
    MOVE.W      #0xFFFF,(WWExist).W             | reset Window Manager
    CLR.L       (MenuList).W                    | reset Menu Manager
    MOVE.L      (MinusOne).W,(LastSPExtra).W    | reset Font Manager
    ST.B        (SEvtEnb).W                     | enable system events
    MOVEQ.L     #0x1F,D0                        | 32 words = 64 bytes
INITAPPLZONE_LOOP:
    CLR.W       -(SP)                           | zero param block on stack
    DBF.W       D0,INITAPPLZONE_LOOP            | allocate 64 bytes
    MOVEA.L     SP,A0                           | A0 = param block
    MOVE.L      (VCBQHdr_Head).W,D0             | first VCB
INITAPPLZONE_LOOP_2:
    BEQ.B       INITAPPLZONE_DONE               | end of queue ->
    MOVEA.L     D0,A1                           | A1 = current VCB
    MOVE.W      0x48(A1),0x16(A0)               | ioVRefNum from VCB
    BEQ.B       INITAPPLZONE_SKIP_2             | offline volume, skip ->
    _FlushVol                                   | flush volume
INITAPPLZONE_SKIP_2:
    MOVE.L      (A1),D0                         | next VCB in queue
    BRA.B       INITAPPLZONE_LOOP_2             | loop all volumes
INITAPPLZONE_DONE:
    ADDA.W      #0x40,SP                        | pop param block
    BSR.W       SETAPPBASE_CONT                 | re-init application zone
    _InitAllPacks                               | initialize packages
    MOVEQ.L     #0x0,D0                         | noErr
    MOVE.W      D0,(MemErr).W                   | clear MemErr
    RTS                                         | return from InitApplZone
INITZONE:
    MOVEM.L     A2-A3/A6,-(SP)                  | save regs
    MOVEA.L     A0,A1                           | A1 = param block ptr
    MOVEA.L     (A1)+,A6                        | A6 = zone start (startPtr)
    MOVE.L      A6,(TheZone).W                  | set current zone
    MOVEA.L     A6,A0                           | A0 = zone header (for zeroing)
    MOVEA.L     A6,A2                           | A2 = zone header (for field init)
    MOVEQ.L     #0xC,D1                         | 13 longwords = 52 bytes
INITZONE_LOOP:
    CLR.L       (A0)+                           | zero zone header
    DBF.W       D1,INITZONE_LOOP                | loop 13 longwords
    MOVE.L      (A1)+,D1                        | D1 = limitPtr from params
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit address
    ANDI.W      #0xFFFC,D1                      | align to longword
    MOVEA.L     D1,A3                           | A3 = zone limit
    CMPA.L      (HighHeapMark).W,A3             | past current high water mark?
    BLT.B       INITZONE_ERR                    | no ->
    MOVE.L      SP,D1                           | D1 = stack pointer
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    CMPA.L      D1,A3                           | zone limit above stack?
    BGT.B       INITZONE_ERR                    | yes, bad limit ->
    MOVE.L      A3,(HighHeapMark).W             | update high water mark
| create the trailing free block (sentinel) at end of zone
INITZONE_ERR:
    MOVEQ.L     #0xC,D1                         | sentinel block size = 12
    SUBA.L      D1,A3                           | A3 = sentinel block address
    MOVE.L      D1,(A3)                         | set sentinel block size
    MOVE.L      A3,(A2)+                        | zone.bkLim = sentinel address
    MOVE.L      A0,(A2)+                        | zone.hFstFree = first free block
    ADDQ.W      #0x4,A2                         | skip zone.purgePtr
    SUBA.L      A0,A3                           | A3 = free space bytes
    MOVE.L      A3,D0                           | D0 = free space count
    MOVE.L      D0,(A2)+                        | zone.zcbFree = total free
    MOVE.W      (A1)+,D1                        | D1 = cMoreMasters from params
    MOVE.L      (A1)+,(A2)+                     | zone.pGrowZone from params
    LEA.L       STDGZ(PC),A1                    | default grow zone function
    MOVE.L      A1,0x18(A2)                     | zone.purgeProc = StdGZ
    MOVE.W      D1,(A2)+                        | zone.moreMast
    MOVE.W      (MMDefFlags).W,(A2)+            | zone.flags = default flags
    JSR         MAKEBKF(PC)                     | make initial free block
    JSR         HMAKEMOREMASTERS(PC)            | allocate master pointers
    MOVE.L      A6,D0                           | zone start address
    BTST        #0x1,D0                         | odd word-aligned? (check bit 1)
    BEQ.B       MEMINIT_DONE                    | no ->
    SUBQ.L      #0x2,0xC(A6)                    | adjust zcbFree for alignment pad
    LEA.L       0x34(A6),A0                     | A0 = first block header
    MOVEA.L     A0,A1                           | A1 = block header copy
    MOVE.L      (A0),D0                         | D0 = block size
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    ADDA.L      D0,A1                           | A1 = end of block
    ADDQ.B      #0x2,(A0)                       | bump block tag
    ADDQ.L      #0x2,(A0)                       | grow first block by 2
    SUBQ.L      #0x2,(A1)                       | shrink next block by 2
    MOVE.L      (A1),0x2(A1)                    | shift next block header
    ADDQ.L      #0x2,A1                         | A1 = new next block
    MOVE.L      A1,0x30(A6)                     | update zone.hFstFree
MEMINIT_DONE:
    MOVEM.L     (SP)+,A2-A3/A6                  | restore regs
INITZONE_EXIT:
    MOVEQ.L     #0x0,D0                         | noErr
    MOVE.W      D0,(MemErr).W                   | clear MemErr
    RTS                                         | return from InitZone
GETZONE:
    MOVEA.L     (TheZone).W,A0                  | A0 = current zone ptr
    BRA.B       INITZONE_EXIT                   | -> return noErr
SETZONE:
    MOVE.L      A0,(TheZone).W                  | set current zone
    BRA.B       INITZONE_EXIT                   | -> return noErr
MAXBLOCK:
    MOVE.L      #0x800000,D0                    | request full compaction
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    MOVEQ.L     #0x1,D1                         | D1 = 1: return largest block
    BRA.B       MAXBLOCK_OR_COMPACT             | -> compact and measure
COMPACTMEM:
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    MOVEQ.L     #0x0,D1                         | D1 = 0: don't return largest
MAXBLOCK_OR_COMPACT:
    JSR         ACTUALS(PC)                     | round D0 to actual block size
    LEA.L       0x16(A6),A1                     | A1 = zone.flags
    MOVE.B      (A1),D2                         | D2 = save original flags
    TST.B       D1                              | return largest block?
    BNE.B       COMPACTMEM_NO                   | yes, clear favor-contiguous ->
    BSET        #0x4,(A1)                       | set favor-contiguous bit
    BRA.B       MAXBLOCK_DO_COMPACT             | -> compact
COMPACTMEM_NO:
    BCLR        #0x4,(A1)                       | clear favor-contiguous bit
MAXBLOCK_DO_COMPACT:
    JSR         COMPACTHP(PC)                   | compact the heap
    MOVE.B      D2,(A1)                         | restore original flags
    MOVE.L      D1,D0                           | D0 = largest free block size
    BEQ.B       PURGEMEM_ERR                    | no free block ->
    SUBQ.L      #0x8,D0                         | - 8-byte block header
    MOVE.L      A0,D1                           | any free block?
    BEQ.B       PURGEMEM_ERR                    | no ->
    BRA.B       PURGEMEM_EXIT_2                 | -> return size
PURGEMEM:
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    JSR         ACTUALS(PC)                     | round D0 to actual block size
    JSR         PURGEHEAP(PC)                   | purge until D0 bytes available
PURGEMEM_CONT:
    MOVE.L      A0,D0                           | free block found?
    BNE.B       PURGEMEM_EXIT                   | yes ->
    MOVEQ.L     #-0x6C,D0                       | memFullErr (-108)
    BRA.B       PURGEMEM_ERR                    | -> return error
PURGEMEM_EXIT:
    MOVEQ.L     #0x0,D0                         | noErr
PURGEMEM_EXIT_2:
    ADDQ.L      #0x8,A0                         | A0 = block data (skip header)
| Called by: MAXBLOCK_DO_COMPACT, PURGEMEM_CONT, PURGESPACE, FREEMEM
PURGEMEM_ERR:
    JMP         MMEPILOGUE(PC)                  | restore regs and return
PURGESPACE:
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    JSR         TOTEPURGEABLES(PC)              | D0 = total, A0 = largest purgeable
    BRA.B       PURGEMEM_ERR                    | -> return via epilogue
FREEMEM:
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    MOVE.L      0xC(A6),D0                      | D0 = zone.zcbFree
    BRA.B       PURGEMEM_ERR                    | -> return via epilogue
RESRVMEM:
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    TST.L       0x8(A6)                         | zone.hFstFree nil? (no masters)
    BNE.B       RESRVMEM_MAKESPC                | has masters ->
    MOVE.W      0x14(A6),D2                     | zone.moreMast count
    EXT.L       D2                              | sign-extend
    ASL.L       #0x2,D2                         | * 4 = master pointer bytes
    ADDQ.L      #0x8,D2                         | + 8 block header
    ADD.L       D2,D0                           | add to request
RESRVMEM_MAKESPC:
    JSR         MAKEPTRSPC(PC)                  | make ptr-sized space
    MOVEA.L     A2,A0                           | A0 = free block
    BRA.B       PURGEMEM_CONT                   | -> check result
MAXMEM:
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    MOVE.L      #0x800000,D0                    | request full compaction
    MOVEQ.L     #0x0,D2                         | D2 = 0: no grow zone
    JSR         BKCOMPACTS(PC)                  | compact and measure
    MOVE.L      D1,D0                           | D0 = largest free block
    BEQ.B       MAXMEM_CONT                     | no free space ->
    SUBQ.L      #0x8,D0                         | - 8-byte block header
MAXMEM_CONT:
    SUBA.L      A0,A0                           | A0 = 0 (no grow info)
    MOVEA.L     (ApplZone).W,A1                 | application zone
    CMPA.L      (TheZone).W,A1                  | in app zone?
    BNE.B       MAXMEM_DONE                     | no -> skip grow calc
    MOVE.L      (ApplLimit).W,D2                | app heap limit
    JSR         MAXLIMIT(PC)                    | compute max growable limit
    SUB.L       (HeapEnd).W,D1                  | D1 = growable bytes
    MOVEA.L     D1,A0                           | A0 = grow size (returned)
MAXMEM_DONE:
    JMP         MMEPILOGUE(PC)                  | -> return via epilogue
SETGROWZONE:
    MOVEA.L     (TheZone).W,A1                  | A1 = current zone
    MOVE.L      A0,0x10(A1)                     | install grow-zone proc
    BRA.B       SETAPPLLIMIT_EXIT               | -> return noErr
SETAPPLLIMIT:
    MOVE.L      A0,D0                           | new limit
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    MOVEA.L     D0,A0                           | A0 = masked limit
    MOVE.L      A0,(ApplLimit).W                | set application limit
    MOVE.L      A0,(HighHeapMark).W             | update high heap mark
    MOVEA.L     (ApplZone).W,A1                 | application zone
    MOVEA.L     (A1),A1                         | A1 = zone.bkLim
    MOVEQ.L     #-0x6C,D0                       | memFullErr (-108)
    CMPA.L      A0,A1                           | bkLim > new limit?
    BHI.B       SETAPPLLIMIT_EXIT_2             | yes -> error
SETAPPLLIMIT_EXIT:
    MOVEQ.L     #0x0,D0                         | noErr
SETAPPLLIMIT_EXIT_2:
    MOVE.W      D0,(MemErr).W                   | set MemErr
    RTS                                         | return from SetApplLimit
STACKSPACE:
    MOVEQ.L     #0x18,D0                        | 24 bytes for saved regs
    ADD.L       SP,D0                           | D0 = adjusted SP
    ANDI.W      #0xFFFC,D0                      | align to longword
    MOVEA.L     (ApplZone).W,A0                 | application zone
    SUB.L       (A0),D0                         | D0 = SP - bkLim = free stack
    CLR.W       (MemErr).W                      | clear MemErr
    RTS                                         | return from StackSpace
MAXAPPLZONE:
    MOVE.L      (ApplLimit).W,D0                | app heap limit
    ANDI.W      #0xFFFC,D0                      | align to longword
    MOVE.L      D0,D1                           | D1 = aligned limit
    LEA.L       (HeapEnd).W,A1                  | A1 -> HeapEnd
    SUB.L       (A1),D0                         | D0 = limit - heap end
    MOVEQ.L     #0xC,D2                         | minimum block size (12)
    CMP.L       D2,D0                           | room for a block?
    BCS.B       MAXAPPLZONE_NO_ROOM             | no -> skip
    MOVEA.L     (A1),A0                         | A0 = old heap end (sentinel)
    MOVE.L      D0,(A0)                         | expand sentinel to fill gap
    MOVE.L      D1,(A1)                         | HeapEnd = new limit
    MOVEA.L     D1,A0                           | new sentinel address
    MOVEA.L     (ApplZone).W,A1                 | app zone header
    MOVE.L      A0,(A1)                         | zone.bkLim = new limit
    MOVE.L      D2,(A0)                         | new sentinel = 12 bytes
    ADD.L       D0,0xC(A1)                      | zone.zcbFree += gained space
MAXAPPLZONE_NO_ROOM:
    BRA.B       SETAPPLLIMIT_EXIT               | -> return noErr
| ----------------------------------------------------------
|
| NewPtr: zone locked, allocate directly
|
NEWPTR:
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    SUBA.L      A1,A1                           | A1 = nil (no master ptr)
    JSR         MAKEPTRSPC(PC)                  | compact/purge for space
    JSR         ALLOCBK(PC)                     | allocate the block
    BEQ.B       NEWPTR_ERR_2                    | failed ->
    BSR.B       PTRZONE_CONT                    | optionally clear block
NEWPTR_EXIT:
    MOVEQ.L     #0x0,D0                         | noErr
MM_PTR_EPILOGUE:
    JMP         MMEPILOGUE(PC)                  | restore regs and return
NEWPTR_ERR_2:
    MOVEQ.L     #-0x6C,D0                       | memFullErr (-108)
    BRA.B       MM_PTR_EPILOGUE                 | -> return error
DISPOSEPTR:
    JSR         MMPPROLOGUE(PC)                 | set up from ptr, save regs
DISPOSPTR_CONT:
    BTST        #0x0,0x16(A6)                   | zone locked?
    BNE.B       DISPOSPTR_EXIT                  | yes -> error
    JSR         FREEBK(PC)                      | free the block
    BRA.B       NEWPTR_EXIT                     | -> return noErr
DISPOSPTR_EXIT:
    MOVEQ.L     #-0x63,D0                       | memWZErr (-99): zone locked
    BRA.B       MM_PTR_EPILOGUE                 | -> return error
GETPTRSIZE:
    JSR         MMPPROLOGUE(PC)                 | set up from ptr, save regs
    JSR         GETSIZE(PC)                     | D0 = block size
    BRA.B       MM_PTR_EPILOGUE                 | -> return via epilogue
SETPTRSIZE:
    JSR         MMPPROLOGUE(PC)                 | set up from ptr, save regs
    JSR         SETSIZE(PC)                     | resize block
    BRA.B       MM_PTR_EPILOGUE                 | -> return via epilogue
PTRZONE:
    JSR         MMPPROLOGUE(PC)                 | set up from ptr, save regs
    MOVEA.L     A6,A0                           | A0 = owning zone
    BRA.B       NEWPTR_EXIT                     | -> return noErr
| ----------------------------------------------------------
|
| PTRZONE_CONT
|
| PTRZONE_CONT: optionally clear allocated block (if _NewHandleClear/_NewPtrClear)
| Trap bit 9 = clear flag; D0 = block size, A0 = block start
PTRZONE_CONT:
    BTST        #0x9,D1                         | _NewPtrClear/_NewHandleClear?
    BEQ.B       MM_CLEAR_BLOCK_RTS              | no ->
    MOVE.L      A0,-(SP)                        | save block ptr
    ADDQ.L      #0x1,D0                         | round up to words
    LSR.L       #0x1,D0                         | D0 = word count
PTRZONE_CONT_2:
    CLR.W       (A0)+                           | zero one word
    SUBQ.L      #0x1,D0                         | decrement count
    BGT.B       PTRZONE_CONT_2                  | loop
    MOVEA.L     (SP)+,A0                        | restore block ptr
MM_CLEAR_BLOCK_RTS:
    RTS                                         | return from ClearBlock
NEWEMPTYHANDLE:
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    JSR         NEXTMASTER(PC)                  | allocate master pointer
    BEQ.B       NEWHANDLE_EMPTY                 | failed ->
    MOVEA.L     A1,A0                           | A0 = master pointer
    CLR.L       (A0)                            | set handle to nil (empty)
    MOVEQ.L     #0x0,D0                         | noErr
    JMP         MMEPILOGUE(PC)                  | -> return
NWHANDLE:
    JSR         MMPROLOGUE(PC)                  | set up zone, save regs
    JSR         NEXTMASTER(PC)                  | allocate master pointer
    BNE.B       NEWHANDLE_ALLOC                 | got one ->
NEWHANDLE_EMPTY:
    MOVEQ.L     #-0x6C,D0                       | memFullErr (-108)
    BRA.B       DISPOSHANDLE_EXIT               | -> return nil handle
NEWHANDLE_ALLOC:
    JSR         ALLOCBK(PC)                     | allocate data block
    BEQ.B       NEWHANDLE_2                     | failed ->
NEWHANDLE_CONT:
    BSR.B       PTRZONE_CONT                    | optionally clear block
    MOVEA.L     A1,A0                           | A0 = master pointer (handle)
MM_HANDLE_NOERR:
    MOVEQ.L     #0x0,D0                         | noErr
MM_HANDLE_EPILOGUE:
    JMP         MMEPILOGUE(PC)                  | -> return via epilogue
NEWHANDLE_2:
    MOVEQ.L     #-0x6C,D0                       | memFullErr (-108)
    BRA.B       DISPOSE_RELEASE_MP              | -> release master ptr
DSPOSEHANDLE:
    JSR         MMHPROLOGUE(PC)                 | set up from handle, save regs
    BNE.B       DISPOSPTR_CONT                  | has data -> free block
    MOVE.L      A1,D0                           | master ptr valid?
    BEQ.B       DISPOSHANDLE_EXIT               | nil -> return
    BTST        #0x0,0x16(A6)                   | zone locked?
    BNE.B       DISPOSE_LOCKED_EMPTY            | yes -> just empty handle
    MOVEQ.L     #0x0,D0                         | noErr
DISPOSE_RELEASE_MP:
    JSR         RELEASEMP(PC)                   | release master pointer
DISPOSHANDLE_EXIT:
    SUBA.L      A0,A0                           | A0 = nil
    BRA.B       MM_HANDLE_EPILOGUE              | -> return via epilogue
DISPOSE_LOCKED_EMPTY:
    CLR.L       (A1)                            | empty the handle
    BRA.B       MM_HANDLE_NOERR                 | -> return noErr
GETHANDLESIZE:
    JSR         MMHPROLOGUE(PC)                 | set up from handle, save regs
    BEQ.B       SETHANDLESIZE_EMPTY             | empty handle -> error
    JSR         GETSIZE(PC)                     | D0 = block size
    BRA.B       SETHANDLESIZE_ERR               | -> return handle
| ----------------------------------------------------------
|
| SetHandleSize: do the resize
|
SETHANDLESIZE:
    JSR         MMHPROLOGUE(PC)                 | set up from handle, save regs
    BNE.B       SETHANDLESIZE_DO                | has data -> resize
SETHANDLESIZE_EMPTY:
    MOVEQ.L     #-0x6D,D0                       | nilHandleErr (-109)
    BRA.B       SETHANDLESIZE_ERR               | -> return handle
SETHANDLESIZE_DO:
    JSR         SETSIZE(PC)                     | resize block
| Called by: GETHANDLESIZE, SETHANDLESIZE_EMPTY, EMPTYHANDLE_EXIT, REALLOCHANDLE, REALLOCHANDLE_OK (and 2 more)
SETHANDLESIZE_ERR:
    MOVEA.L     A1,A0                           | A0 = handle
    BRA.B       MM_HANDLE_EPILOGUE              | -> return via epilogue
HANDLEZONE:
    JSR         MMHPROLOGUE(PC)                 | set up from handle, save regs
    MOVEA.L     A6,A0                           | A0 = owning zone
    BRA.B       MM_HANDLE_NOERR                 | -> return noErr
RECOVERHANDLE:
    JSR         MMRHPROLOGUE(PC)                | set up from ptr, save regs
    MOVEA.L     -0x4(A0),A1                     | A1 = relative handle (from block header)
    ADDA.L      A6,A1                           | A1 = absolute handle
    MOVE.L      (A1),D2                         | D2 = master ptr contents
    AND.L       (Lo3Bytes).W,D2                 | mask to 24-bit
    MOVE.L      A0,D1                           | D1 = block ptr
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    SUB.L       D1,D2                           | verify: master ptr == block ptr?
    BEQ.B       RECOVERHANDLE_FOUND             | yes, valid ->
    MOVEQ.L     #-0x73,D2                       | memAdrErr (-115)
RECOVERHANDLE_FOUND:
    MOVE.W      D2,(MemErr).W                   | set MemErr
    MOVEA.L     A1,A0                           | A0 = recovered handle
    JMP         MMNOERREPILOGUE(PC)             | -> return (no error override)
EMPTYHANDLE:
    JSR         MMHPROLOGUE(PC)                 | set up from handle, save regs
    BNE.B       EMPTYHANDLE_DO                  | has data -> empty it
    MOVEQ.L     #0x0,D0                         | already empty: noErr
    BRA.B       EMPTYHANDLE_EXIT                | -> return handle
EMPTYHANDLE_DO:
    JSR         EH(PC)                          | empty the handle (free data)
EMPTYHANDLE_EXIT:
    BRA.B       SETHANDLESIZE_ERR               | -> return handle
REALLOCHANDLE:
    JSR         MMHPROLOGUE(PC)                 | set up from handle, save regs
    TST.L       (A1)                            | handle already empty?
    BEQ.B       REALLOCHANDLE_OK                | yes -> allocate directly
    BTST        #0x0,0x16(A6)                   | zone locked?
    BNE.B       REALLOCHANDLE_LOCKED            | yes -> check size
    JSR         EH(PC)                          | empty handle (free old data)
    BNE.B       SETHANDLESIZE_ERR               | error -> return
    MOVE.L      D2,D0                           | D0 = requested size
REALLOCHANDLE_OK:
    MOVE.L      A1,(GZRootHnd).W                | protect handle from GrowZone
    CLR.L       (GZRootPtr).W                   | no ptr to protect
    JSR         ALLOCBK(PC)                     | allocate new data block
    JSR         CLEARGZSTUFF(PC)                | clear GZ protection
    MOVE.L      A0,D2                           | block allocated?
    BNE.W       NEWHANDLE_CONT                  | yes -> clear and return
    MOVEQ.L     #-0x6C,D0                       | memFullErr (-108)
    BRA.B       SETHANDLESIZE_ERR               | -> return handle
REALLOCHANDLE_LOCKED:
    JSR         GETSIZE(PC)                     | D0 = current block size
    CMP.L       D0,D2                           | requested > current?
    BHI.B       REALLOCHANDLE_ERR_2             | yes -> can't grow locked
    MOVEQ.L     #-0x63,D0                       | memWZErr (-99)
    BRA.B       SETHANDLESIZE_ERR               | -> return handle
REALLOCHANDLE_ERR_2:
    MOVEQ.L     #-0x63,D0                       | memWZErr (-99)
    BRA.W       SETHANDLESIZE_ERR               | -> return handle
HLOCK:
    BSR.B       HNOPURGE_CONT                   | validate handle -> A1
    BEQ.B       HNOPURGE_EXIT_2                 | nil handle ->
    BSET        #0x7,(A1)                       | set lock bit
    BRA.B       HNOPURGE_EXIT                   | -> return noErr
HUNLOCK:
    BSR.B       HNOPURGE_CONT                   | validate handle -> A1
    BEQ.B       HNOPURGE_EXIT_2                 | nil handle ->
    BCLR        #0x7,(A1)                       | clear lock bit
    BRA.B       HNOPURGE_EXIT                   | -> return noErr
HPURGE:
    BSR.B       HNOPURGE_CONT                   | validate handle -> A1
    BEQ.B       HNOPURGE_EXIT_2                 | nil handle ->
    BSET        #0x6,(A1)                       | set purgeable bit
    BRA.B       HNOPURGE_EXIT                   | -> return noErr
HNOPURGE:
    BSR.B       HNOPURGE_CONT                   | validate handle -> A1
    BEQ.B       HNOPURGE_EXIT_2                 | nil handle ->
    BCLR        #0x6,(A1)                       | clear purgeable bit
| Called by: HLOCK, HUNLOCK, HPURGE, HRSRC, HNORSRC (and 1 more)
HNOPURGE_EXIT:
    MOVEQ.L     #0x0,D0                         | noErr
    BRA.B       HFLAGS_SET_MEMERR               | -> set MemErr
| Called by: HLOCK, HUNLOCK, HPURGE, HNOPURGE, HRSRC (and 3 more)
HNOPURGE_EXIT_2:
    MOVEQ.L     #-0x6D,D0                       | nilHandleErr (-109)
HFLAGS_SET_MEMERR:
    MOVE.W      D0,(MemErr).W                   | set MemErr
    RTS                                         | return from handle flag ops
HRSRC:
    BSR.B       HNOPURGE_CONT                   | validate handle -> A1
    BEQ.B       HNOPURGE_EXIT_2                 | nil handle ->
    BSET        #0x5,(A1)                       | set resource bit
    BRA.B       HNOPURGE_EXIT                   | -> return noErr
HNORSRC:
    BSR.B       HNOPURGE_CONT                   | validate handle -> A1
    BEQ.B       HNOPURGE_EXIT_2                 | nil handle ->
    BCLR        #0x5,(A1)                       | clear resource bit
    BRA.B       HNOPURGE_EXIT                   | -> return noErr
| ----------------------------------------------------------
|
| HNOPURGE_CONT
|
| HNOPURGE_CONT: validate handle for HLock/HUnlock/HPurge/HNoPurge
| A0 = handle -> A1 = master pointer address, Z set if nil
| Called by: HLOCK, HUNLOCK, HPURGE, HNOPURGE, HRSRC (and 3 more)
HNOPURGE_CONT:
    MOVE.L      A0,D0                           | get handle
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    BNE.B       HNOPURGE_EMPTY                  | valid handle ->
    ADDQ.L      #0x4,SP                         | pop return addr (skip caller)
    RTS                                         | return with Z set (nil)
HNOPURGE_EMPTY:
    MOVEA.L     D0,A1                           | A1 = master pointer address
    MOVE.L      (A1),D0                         | D0 = master ptr contents (Z if nil)
    RTS                                         | return from handle validate
HGETFLAGS:
    BSR.B       HNOPURGE_CONT                   | validate handle -> A1
    BEQ.B       HNOPURGE_EXIT_2                 | nil handle ->
    MOVEQ.L     #0x0,D0                         | clear high bytes
    MOVE.B      (A1),D0                         | D0 = flag byte
    CLR.W       (MemErr).W                      | noErr
    RTS                                         | return from HGetState
HSETFLAGS:
    MOVE.B      D0,D1                           | save new flags
    BSR.B       HNOPURGE_CONT                   | validate handle -> A1
    BEQ.B       HNOPURGE_EXIT_2                 | nil handle ->
    MOVE.B      D1,(A1)                         | set flag byte
    BRA.B       HNOPURGE_EXIT                   | -> return noErr
MOREMASTERS:
    MOVE.L      A6,-(SP)                        | save A6
    MOVEA.L     (TheZone).W,A6                  | A6 = current zone
    MOVEQ.L     #0x0,D0                         | assume noErr
    JSR         HMAKEMOREMASTERS(PC)            | allocate master pointer block
    BNE.B       MOREMASTERS_SKIP                | success ->
    MOVEQ.L     #-0x6C,D0                       | memFullErr (-108)
MOREMASTERS_SKIP:
    MOVEA.L     (SP)+,A6                        | restore A6
    MOVE.W      D0,(MemErr).W                   | set MemErr
    RTS                                         | return from MoreMasters
STRIPADDRESS:
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit address
    RTS                                         | return from StripAddress
| ----------------------------------------------------------
| MOVEHHI -- _MoveHHi ($A064): move the relocatable block of handle A0
| as high as possible in its heap zone (A6, found by MMHPROLOGUE): into
| the free block at the top of the zone if the data fits, otherwise in
| chunks through a buffer on the stack (at most the stack space above
| HighHeapMark, less 1K), compacting the zone after each chunk. The block
| stays where it is if the block above it is non-relocatable or locked.
| Result in D0 and MemErr: noErr, nilHandleErr (-109), memLockedErr
| (-117), -1 if the stack has no room for a 1K buffer.
| SE: TheZone is set to the block's zone during the move and restored
| at the end -- the frame on the stack is $16 bytes, the Plus's $12 --
| so that the _CompactMem calls compact the zone that holds the block;
| the Plus compacted TheZone even for a block in another zone.
| Frame (A5): +0 block header, +4 chunk size, +8 buffer size, +$C data
| address, +$10 master pointer flags, +$12 saved TheZone, +$16 buffer.
MOVEHHI:
    JSR         MMHPROLOGUE(PC)                 | set up from handle, save regs
    BNE.B       MOVEHHI_CONT                    | has data ->
    MOVEQ.L     #-0x6D,D0                       | nilHandleErr (-109)
MOVEHHI_RETURN:
    JMP         MMEPILOGUE(PC)                  | -> return via epilogue
| check if block is locked (can't move locked blocks)
MOVEHHI_CONT:
    MOVEA.L     A1,A4                           | A4 = save master pointer
    TST.B       (A4)                            | check lock bit (bit 7)
    BPL.B       MOVEHHI_NO                      | not locked ->
    MOVEQ.L     #-0x75,D0                       | memLockedErr (-117)
    BRA.B       MOVEHHI_RETURN                  | -> return error
| scan from block to bkLim, measuring free space above
MOVEHHI_NO:
    MOVEA.L     (A6),A3                         | A3 = bkLim (zone end)
    SUBQ.L      #0x8,A0                         | back up to block header
    MOVE.L      (A0),D1                         | D1 = block size
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    MOVE.L      D1,D7                           | D7 = data size
    SUBQ.L      #0x8,D7                         | - 8-byte header
    MOVEQ.L     #0x0,D0                         | clear
    ADDA.L      D1,A0                           | A0 = next block
    CMPA.L      A3,A0                           | at zone end?
    BCC.W       MOVEHHI_EPILOGUE                | yes, already at top ->
    TST.B       (A0)                            | next block free? (tag=0)
    BEQ.B       MOVEHHI_OK                      | yes ->
    BPL.W       MOVEHHI_EPILOGUE                | non-relocatable -> can't move
    MOVEA.L     0x4(A0),A0                      | rel handle of next block
    ADDA.L      A6,A0                           | A0 = master ptr of next block
    TST.B       (A0)                            | next block locked?
    BMI.W       MOVEHHI_EPILOGUE                | yes -> can't move past
MOVEHHI_OK:
    MOVE.L      SP,D1                           | current stack ptr
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    SUB.L       (HighHeapMark).W,D1             | D1 = available stack space
    MOVE.L      #0x400,D2                       | 1KB minimum stack buffer
    MOVE.L      D2,D0                           | D0 = buffer + data needed
    ADD.L       D7,D0                           | total stack space needed
    CMP.L       D0,D1                           | enough?
    BLT.B       MOVEHHI_NO_2                    | no, cap to available ->
    MOVE.L      D0,D1                           | cap to needed amount
MOVEHHI_NO_2:
    MOVEQ.L     #-0x1,D0                        | D0 = -1: stack approach
    CMP.L       D2,D1                           | minimum buffer available?
    BLT.W       MOVEHHI_EPILOGUE                | no -> can't move
    SUBI.L      #0x80,D2                        | safety margin (128 bytes)
    SUB.L       D2,D1                           | D1 = usable buffer size
    SUBA.L      D1,SP                           | allocate stack buffer
    SUBA.W      #0x16,SP                        | + stack frame (22 bytes)
    MOVEA.L     SP,A5                           | A5 = stack frame base
    MOVE.L      D1,0x8(A5)                      | frame+8 = buffer size
    MOVE.L      (TheZone).W,0x12(A5)            | frame+18 = save TheZone
    MOVE.L      A6,(TheZone).W                  | set TheZone to owner zone
    MOVEA.L     (A4),A0                         | block data ptr
    SUBQ.W      #0x8,A0                         | back up to header
    MOVE.L      (A0),(A5)                       | frame+0 = block header
    MOVE.L      (A4),D0                         | master ptr contents
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    MOVE.L      D0,0xC(A5)                      | frame+12 = data address
    MOVE.B      (A4),0x10(A5)                   | frame+16 = MP flags
    BSR.W       MOVEHHI_CONT_5                  | find free block at top
    TST.B       (A2)                            | free block? (tag=0)
    BNE.B       MOVEHHI_NO_3                    | no -> need compaction
    MOVE.L      (A2),D1                         | D1 = free block size
    MOVE.L      D1,D0                           | D0 = free block size
    SUBQ.L      #0x8,D0                         | - 8-byte block header = room for data
    CMP.L       D0,D7                           | data fits?
    BHI.B       MOVEHHI_NO_3                    | no -> compaction
    SUB.L       D7,D0                           | leftover after data
    BEQ.B       MOVEHHI_CONT_2                  | exact fit ->
    MOVEQ.L     #0xC,D2                         | min block size
    CMP.L       D2,D0                           | leftover too small?
    BCS.B       MOVEHHI_NO_3                    | yes -> compaction
MOVEHHI_CONT_2:
    MOVEA.L     (A4),A0                         | source = block data
    MOVEA.L     A2,A1                           | A1 = the free block
    ADDA.L      D1,A1                           | + its size: A1 = end of the free block
MOVEHHI_CONT_3:
    MOVE.L      D7,D0                           | D0 = data size
    SUBA.L      D0,A1                           | dest = end - data size
    SUB.L       D0,0xC(A6)                      | zone.zcbFree -= data size
    _BlockMove                                  | copy data to high position
    MOVEA.L     A4,A0                           | handle
    _EmptyHandle                                | release old block
    BRA.B       MOVEHHI_OK_2                    | -> finalize
MOVEHHI_NO_3:
    MOVEQ.L     #0x0,D6                         | D6 = total bytes moved
    BSR.W       MOVEHHI_CONT_6                  | copy chunk to stack buffer
    BSR.W       MOVEHHI_CONT_8                  | compact heap
    BSR.W       MOVEHHI_CONT_5                  | find free block at top
MOVEHHI_NEXT:
    MOVE.L      (A2),D1                         | D1 = free block size
    MOVE.L      0x4(A5),D0                      | D0 = chunk size from frame
    LEA.L       0x16(A5),A0                     | A0 = stack buffer data
    MOVEA.L     A2,A1                           | A1 = the free block
    ADDA.L      D1,A1                           | + its size: A1 = end of the free block
    SUBA.L      D0,A1                           | - chunk = dest addr
    ADD.L       D0,D6                           | accumulate total moved
    SUB.L       D0,0xC(A6)                      | zcbFree -= chunk
    _BlockMove                                  | copy chunk from stack to heap
    TST.L       D7                              | all data moved?
    BEQ.B       MOVEHHI_OK_2                    | yes -> finalize
    MOVE.L      A1,D0                           | remaining free space
    SUB.L       A2,D0                           | = dest - free block start
    BEQ.B       MOVEHHI_NEXT_2                  | no leftover -> next chunk
    MOVE.L      D0,D1                           | D1 = leftover
    SUBQ.L      #0x8,D1                         | - header
    SUB.L       D7,D1                           | - data remaining
    BCS.B       MOVEHHI_NO_4                    | not enough -> mark used
    BEQ.B       MOVEHHI_CONT_4                  | exact fit ->
    MOVEQ.L     #0xC,D2                         | min block size
    CMP.L       D1,D2                           | too small to split?
    BCS.B       MOVEHHI_NO_4                    | yes -> mark as used
MOVEHHI_CONT_4:
    MOVEA.L     (A4),A0                         | source = block data
    BRA.B       MOVEHHI_CONT_3                  | -> direct move into free space
| ----------------------------------------------------------
|
| MOVEHHI_NO_4
|
MOVEHHI_NO_4:
    MOVE.L      D0,(A2)                         | mark leftover as free block
MOVEHHI_NEXT_2:
    MOVEM.L     (A1),D4-D5                      | save block header at dest
    MOVE.L      A6,0x4(A1)                      | set rel zone ptr
    MOVE.L      D6,(A1)                         | set block size = moved so far
    MOVE.B      #0x40,(A1)                      | tag = non-relocatable (temp)
    MOVE.L      A1,-(SP)                        | save dest ptr
    BSR.B       MOVEHHI_CONT_6                  | copy next chunk to stack
    BSR.W       MOVEHHI_CONT_8                  | compact heap
    BSR.B       MOVEHHI_CONT_5                  | find free block at top
    MOVEA.L     (SP)+,A1                        | restore dest ptr
    MOVEM.L     D4-D5,(A1)                      | restore original header
    BRA.B       MOVEHHI_NEXT                    | -> copy chunk to heap
| ----------------------------------------------------------
|
| MOVEHHI_OK_2
|
| Called during boot.
MOVEHHI_OK_2:
    SUBQ.L      #0x8,A1                         | back up for block header
    SUBQ.L      #0x8,0xC(A6)                    | zcbFree -= 8 (header)
    MOVE.L      A1,D0                           | D0 = new block header address
    SUB.L       A2,D0                           | - free block start = gap below the new block
    BEQ.B       MOVEHHI_SKIP                    | no gap ->
    MOVE.L      D0,(A2)                         | create free block in gap
MOVEHHI_SKIP:
    MOVEA.L     A1,A2                           | A2 = new block location
    MOVE.L      (A5),(A2)+                      | restore block header
    MOVEA.L     A4,A0                           | master ptr
    SUBA.L      A6,A0                           | relative to zone
    MOVE.L      A0,(A2)+                        | set relHandle
    MOVE.L      A2,(A4)                         | update master ptr to new data
    MOVE.B      0x10(A5),(A4)                   | restore MP flags
    MOVE.L      0x12(A5),(TheZone).W            | restore TheZone
    MOVEQ.L     #0x0,D0                         | noErr
    ADDA.L      0x8(A5),SP                      | deallocate stack buffer
    ADDA.W      #0x16,SP                        | + frame
MOVEHHI_EPILOGUE:
    JMP         MMEPILOGUE(PC)                  | -> return via epilogue
| ----------------------------------------------------------
|
| MOVEHHI_CONT_5
|
| Called during boot.
MOVEHHI_CONT_5:
    MOVE.L      (A4),D0                         | D0 = master pointer contents
    BEQ.B       MOVEHHI_EMPTY                   | nil (purged) -> start from heapData
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit address
    MOVEA.L     D0,A0                           | A0 = block data
    SUBQ.W      #0x8,A0                         | back up to header
    BRA.B       MOVEHHI_NO_5                    | -> scan from block
| ----------------------------------------------------------
|
| MOVEHHI_EMPTY
|
MOVEHHI_EMPTY:
    LEA.L       0x34(A6),A0                     | A0 = zone.heapData (first block)
MOVEHHI_NO_5:
    MOVE.L      (A0),D1                         | D1 = block size
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    TST.B       (A0)                            | check block type
    BEQ.B       MOVEHHI_OK_3                    | free -> accumulate
    BPL.B       MOVEHHI_OK_4                    | non-reloc -> check if ours
    MOVEA.L     0x4(A0),A1                      | rel handle
    ADDA.L      A6,A1                           | master ptr
    TST.B       (A1)                            | locked?
    BMI.B       MOVEHHI_OK_4                    | yes -> check if ours
MOVEHHI_OK_3:
    MOVEA.L     A0,A2                           | A2 = highest free/movable block
    ADDA.L      D1,A0                           | advance to next block
    CMPA.L      A3,A0                           | reached bkLim?
    BCS.B       MOVEHHI_NO_5                    | no -> keep scanning
    BRA.B       MOVEHHI_DONE                    | done ->
| ----------------------------------------------------------
|
| MOVEHHI_OK_4
|
MOVEHHI_OK_4:
    CMPA.L      0xC(A5),A0                      | past our block?
    BLS.B       MOVEHHI_OK_3                    | no -> keep scanning
MOVEHHI_DONE:
    RTS                                         | return (A2 = best free block)
MOVEHHI_CONT_6:
    MOVE.L      0x8(A5),D0                      | D0 = stack buffer capacity
    CMP.L       D7,D0                           | larger than remaining data?
    BLT.B       MOVEHHI_NO_6                    | no, use buffer size ->
    MOVE.L      D7,D0                           | cap to remaining data
MOVEHHI_NO_6:
    LEA.L       0x16(A5),A1                     | A1 = stack buffer
    MOVEA.L     (A4),A0                         | A0 = start of the data (master pointer)
    ADDA.L      D7,A0                           | + data left to move: end of that data
    SUBA.L      D0,A0                           | A0 = source (tail of data)
    SUB.L       D0,D7                           | D7 -= copied amount
    MOVE.L      D0,0x4(A5)                      | frame+4 = chunk size
    MOVE.L      D0,D1                           | D1 = byte count
    _BlockMove                                  | copy chunk to stack buffer
    MOVEA.L     A4,A0                           | handle
    MOVE.L      D7,D0                           | remaining data
    BNE.B       MOVEHHI_CONT_7                  | still more -> shrink block
    _EmptyHandle                                | all copied -> empty handle
    RTS                                         | return from MOVEHHI_NO_6
| ----------------------------------------------------------
|
| MOVEHHI_CONT_7
|
MOVEHHI_CONT_7:
    MOVEA.L     (A0),A0                         | dereference handle
    SUBQ.W      #0x8,A0                         | back up to header
    MOVE.B      (A0),D2                         | save tag byte
    ADDQ.L      #0x8,D0                         | D0 = remaining + header
    MOVE.L      D0,(A0)                         | shrink block size
    MOVE.B      D2,(A0)                         | restore tag byte
    ADDA.L      D0,A0                           | A0 = freed tail area
    MOVE.L      D1,(A0)                         | create free block (size = copied)
    ADD.L       D1,0xC(A6)                      | zcbFree += freed space
    RTS                                         | return from chunk copy
| MOVEHHI_CONT_8 -- compact heap.
| ----------------------------------------------------------
|
| MOVEHHI_CONT_8
|
MOVEHHI_CONT_8:
    MOVE.L      #0x800000,D0                    | D0 = max possible (compact everything)
    _CompactMem                                 | call _CompactMem trap
    RTS                                         | return from MOVEHHI_CONT_8
| HEAPGUTS -- dereference a handle: A1 = handle A0 masked to 24 bits,
| A0 = D0 = its master pointer (0 for a nil handle); Z set if the
| handle or the master pointer is nil.
| (Apple module HEAPGUTS starts here; MacSEROM.lst lists no routine name.)
HEAPGUTS:
    MOVE.L      A0,D0                           | get handle
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    MOVEA.L     D0,A0                           | A0 = handle (masked)
    MOVEA.L     D0,A1                           | A1 = handle copy
    BEQ.B       DEREFHANDLE_EXIT                | nil handle ->
    MOVEA.L     (A1),A0                         | A0 = *handle (dereference)
    MOVE.L      A0,D0                           | D0 = ptr (for testing)
DEREFHANDLE_EXIT:
    RTS                                         | return from DerefHandle
| ----------------------------------------------------------
|
| DEREFHANDLE_CONT
|
| Called during boot (39,524 times in 30s trace).
DEREFHANDLE_CONT:
    MOVE.L      A0,D0                           | D0 = pointer value
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit address
    MOVEA.L     D0,A0                           | A0 = ptr (masked)
    SUBQ.L      #0x8,A0                         | back up to block header
    TST.B       (A0)                            | check block type
    BEQ.B       DEREFHANDLE_CONT_4              | free block -> error
    BMI.B       DEREFHANDLE_CONT_2              | relocatable -> get zone from rel handle
    MOVEA.L     0x4(A0),A6                      | non-reloc: zone ptr in header
    BRA.B       DEREFHANDLE_CONT_3              | -> validate zone
| ----------------------------------------------------------
|
| DEREFHANDLE_CONT_2
|
| Called during boot (39,521 times in 30s trace).
DEREFHANDLE_CONT_2:
    MOVEA.L     A1,A6                           | A6 = master ptr addr
    SUBA.L      0x4(A0),A6                      | - relHandle offset = zone ptr
DEREFHANDLE_CONT_3:
    BSR.B       DEREFHANDLE_CONT_5              | validate zone
DEREFHANDLE_EXIT_2:
    ADDQ.L      #0x8,A0                         | A0 = block data (skip header)
    RTS                                         | return from block lookup
| ----------------------------------------------------------
|
| DEREFHANDLE_CONT_4
|
DEREFHANDLE_CONT_4:
    MOVEQ.L     #-0x6F,D0                       | memAZErr (-111): free block
    BRA.B       DEREFHANDLE_EXIT_2              | -> return error
| ----------------------------------------------------------
|
| DEREFHANDLE_CONT_5
|
| Called during boot (54,193 times in 30s trace).
DEREFHANDLE_CONT_5:
    MOVE.L      A0,-(SP)                        | save A0
    MOVE.L      A6,D0                           | zone ptr
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    MOVEA.L     D0,A6                           | A6 = masked zone
    MOVE.L      0x38(A6),D0                     | zone.zcbCheck (self-ptr)
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    SUB.L       A6,D0                           | valid if zone == zcbCheck
    BEQ.B       DEREFHANDLE_FOUND               | matches ->
    MOVEQ.L     #-0x71,D0                       | memBCErr (-113): bad zone check
DEREFHANDLE_FOUND:
    MOVEA.L     (SP)+,A0                        | restore A0
    RTS                                         | return (Z if valid)
MMPPROLOGUE:
    MOVEA.L     (SP)+,A1                        | pop return address
    MOVEM.L     D3-D7/A2-A6,-(SP)               | save regs
    MOVE.L      A1,-(SP)                        | push return address
    MOVE.L      D0,D2                           | D2 = save size/param
    SUBA.L      A1,A1                           | no master ptr
    BSR.B       DEREFHANDLE_CONT                | find zone from ptr -> A6
    BMI.B       MMHPROLOGUE_ERR                 | bad zone -> error
    MOVE.L      D2,D0                           | restore D0
    RTS                                         | return to trap handler
| Called by: DSPOSEHANDLE, GETHANDLESIZE, SETHANDLESIZE, HANDLEZONE, EMPTYHANDLE (and 2 more)
MMHPROLOGUE:
    MOVEA.L     (SP)+,A1                        | pop return address
    MOVEM.L     D3-D7/A2-A6,-(SP)               | save regs
    MOVE.L      A1,-(SP)                        | push return address
    MOVE.L      D0,D2                           | D2 = save size/param
    MOVEA.L     (TheZone).W,A6                  | A6 = default zone
    BSR.B       HEAPGUTS                        | dereference handle -> A0,A1
    BEQ.B       MMHPROLOGUE_FIND_ZONE           | empty handle -> find zone
    BSR.B       DEREFHANDLE_CONT                | find zone from block -> A6
MMHPROLOGUE_CHECK:
    BMI.B       MMHPROLOGUE_ERR                 | bad zone -> error
    MOVE.L      D2,D0                           | restore D0
    MOVE.L      A0,D7                           | D7 = save block ptr
    RTS                                         | return (Z if empty handle)
MMHPROLOGUE_FIND_ZONE:
    MOVE.L      A1,D0                           | handle nil?
    BEQ.B       MMHPROLOGUE_VALIDATE            | yes -> use TheZone
    CMPA.L      (ApplZone).W,A6                 | TheZone is app zone?
    BEQ.B       MMHPROLOGUE_TRY_SYS             | yes -> try sys zone
    CMPA.L      (SysZone).W,A6                  | TheZone is sys zone?
    BNE.B       MMHPROLOGUE_VALIDATE            | no -> validate
    MOVEA.L     (ApplZone).W,A6                 | try app zone
MMHPROLOGUE_TRY_SYS:
    CMP.L       A6,D0                           | master ptr in this zone?
    BHI.B       MMHPROLOGUE_VALIDATE            | no ->
    MOVEA.L     (SysZone).W,A6                  | try sys zone
MMHPROLOGUE_VALIDATE:
    BSR.B       DEREFHANDLE_CONT_5              | validate zone
    BRA.B       MMHPROLOGUE_CHECK               | -> check result
MMHPROLOGUE_ERR:
    ADDQ.L      #0x4,SP                         | pop return address
    BRA.B       MMEPILOGUE_ERR                  | -> return error
| Called by: MAXBLOCK, COMPACTMEM, PURGEMEM, PURGESPACE, FREEMEM (and 5 more)
MMPROLOGUE:
    MOVEA.L     (SP)+,A1                        | pop return address
    MOVEM.L     D3-D7/A2-A6,-(SP)               | save regs
    MOVE.L      A1,-(SP)                        | push return address
    MOVE.L      D0,D2                           | D2 = save size/param
    MOVEA.L     (TheZone).W,A6                  | A6 = default zone
    BTST        #0xA,D1                         | SYS trap bit? (bit 10)
    BEQ.B       MMPROLOGUE_ZONE                 | no -> use TheZone
    MOVEA.L     (SysZone).W,A6                  | use system zone
MMPROLOGUE_ZONE:
    BSR.W       DEREFHANDLE_CONT_5              | validate zone
    BMI.B       MMHPROLOGUE_ERR                 | bad zone -> error
    MOVE.L      D2,D0                           | restore D0
    RTS                                         | return to trap handler
MMRHPROLOGUE:
    MOVEA.L     (SP)+,A1                        | pop return address
    MOVEM.L     D3-D7/A2-A6,-(SP)               | save regs
    MOVE.L      A1,-(SP)                        | push return address
    MOVE.L      D0,D2                           | D2 = save param
    MOVEA.L     (TheZone).W,A6                  | A6 = default zone
    BTST        #0xA,D1                         | SYS trap bit?
    BNE.B       MMRHPROLOGUE_TRY_SYS            | yes -> use sys zone
    CMPA.L      (SysZone).W,A6                  | TheZone is sys zone?
    BEQ.B       MMRHPROLOGUE_CHK_LOC            | yes -> check ptr location
    CMPA.L      (ApplZone).W,A6                 | TheZone is app zone?
    BNE.B       MMRHPROLOGUE_VALIDATE           | no -> validate TheZone
MMRHPROLOGUE_TRY_SYS:
    MOVEA.L     (SysZone).W,A6                  | start with sys zone
MMRHPROLOGUE_CHK_LOC:
    MOVE.L      A0,D0                           | ptr value
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    CMP.L       (ApplZone).W,D0                 | ptr in app zone?
    BLS.B       MMRHPROLOGUE_VALIDATE           | no -> keep sys zone
    MOVEA.L     (ApplZone).W,A6                 | use app zone
MMRHPROLOGUE_VALIDATE:
    BSR.W       DEREFHANDLE_CONT_5              | validate zone
    BMI.B       MMHPROLOGUE_ERR                 | bad zone -> error
    MOVE.L      D2,D0                           | restore D0
    RTS                                         | return to trap handler
| Called by: PURGEMEM_ERR, MAXMEM_DONE, MM_PTR_EPILOGUE, NEWEMPTYHANDLE, MM_HANDLE_EPILOGUE (and 2 more)
MMEPILOGUE:
    CLR.W       (MemErr).W                      | assume noErr
    TST.L       D0                              | check result
    BGE.B       MMNOERREPILOGUE                 | >= 0 -> no error
MMEPILOGUE_ERR:
    MOVE.W      D0,(MemErr).W                   | set MemErr
MMNOERREPILOGUE:
    MOVEM.L     (SP)+,D3-D7/A2-A6               | restore regs
    RTS                                         | return from MMNOERREPILOGUE
| Called by: INITZONE_ERR, EH_CONT_2, ALLOCBK_CONT_4, ZONEADJUSTEND, SETSIZE_CONT_4 (and 1 more)
MAKEBKF:
    MOVE.L      D0,(A0)                         | set block size
    CLR.B       (A0)                            | tag = 0 (free block)
    RTS                                         | return from MakeBKF
| ----------------------------------------------------------
|
| EH
|
| Called during boot.
EH:
    BTST        #0x7,(A1)                       | handle locked?
    BNE.B       EH_EXIT_3                       | yes -> error
    BTST        #0x0,0x16(A6)                   | zone locked?
    BNE.B       EH_OK                           | yes -> just nil the MP
    SUBQ.L      #0x8,A0                         | back up to block header
    BSR.B       EH_CONT_2                       | free block and adjust heap
    ADDQ.L      #0x8,A0                         | restore data ptr
EH_EXIT:
    MOVEQ.L     #0x0,D0                         | noErr
EH_EXIT_2:
    RTS                                         | return from EH
| ----------------------------------------------------------
|
| EH_EXIT_3
|
EH_EXIT_3:
    MOVEQ.L     #-0x70,D0                       | memPurErr (-112): locked
    BRA.B       EH_EXIT_2                       | -> return error
| ----------------------------------------------------------
|
| EH_OK
|
EH_OK:
    CLR.L       (A1)                            | nil the master pointer
    BRA.B       EH_EXIT                         | -> return noErr
| ----------------------------------------------------------
|
| EH_CONT
|
| Called during boot.
EH_CONT:
    TST.L       0x28(A6)                        | zone.purgeProc installed?
    BEQ.B       EH_EXIT_4                       | no -> return
    MOVEM.L     D0-D2/A0-A1,-(SP)               | save regs
    MOVE.L      A1,-(SP)                        | push handle
    MOVEA.L     0x28(A6),A1                     | A1 = purge notification proc
    JSR         (A1)                            | call purge proc
    MOVEM.L     (SP)+,D0-D2/A0-A1               | restore regs
EH_EXIT_4:
    RTS                                         | return from purge notify
| ----------------------------------------------------------
|
| EH_CONT_2
|
| Called during boot.
EH_CONT_2:
    MOVE.L      D0,-(SP)                        | save D0
    MOVE.L      (A0),D0                         | D0 = block size
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit
    BSR.B       EH_CONT                         | call purge notification
    CLR.L       (A1)                            | nil the master pointer
    BSR.B       MAKEBKF                         | mark block as free
    BSR.W       ADJUSTFREE                      | merge adjacent free blocks
    MOVE.L      (SP)+,D0                        | restore D0
    RTS                                         | return from EH helper
PURGEHEAP:
    MOVEM.L     D2/A1-A4,-(SP)                  | save regs
PURGEHEAP_CONT:
    MOVEA.L     (A6),A3                         | A3 = bkLim
    LEA.L       0x34(A6),A0                     | A0 = first block (heapData)
    BTST        #0x6,0x16(A6)                   | already purging?
    BNE.B       PURGEHEAP_OK_2                  | yes -> skip scan
    MOVEA.L     A0,A2                           | A2 = scan ptr
    MOVEQ.L     #0x0,D2                         | D2 = accumulated free+purgeable
PURGEHEAP_NO:
    MOVE.L      (A2),D1                         | D1 = block size
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    MOVEA.L     A2,A4                           | A4 = current block
    ADDA.L      D1,A2                           | advance to next block
    TST.B       (A4)                            | block type
    BEQ.B       PURGEHEAP_CONT_2                | free -> accumulate
    BPL.B       PURGEHEAP_OK                    | non-reloc -> reset
    MOVEA.L     0x4(A4),A1                      | rel handle
    ADDA.L      A6,A1                           | master ptr
    TST.B       (A1)                            | locked?
    BMI.B       PURGEHEAP_OK                    | yes -> reset
    BTST        #0x6,(A1)                       | purgeable?
    BEQ.B       PURGEHEAP_NO_2                  | no -> skip
    CMPA.L      0x4(A6),A4                      | past purgePtr?
    BCS.B       PURGEHEAP_SKIP                  | no -> reset
PURGEHEAP_CONT_2:
    ADD.L       D1,D2                           | accumulate free+purgeable
    CMP.L       D0,D2                           | enough space?
    BCS.B       PURGEHEAP_NO_2                  | not yet -> continue
    BRA.B       PURGEHEAP_OK_3                  | enough -> start purging
| ----------------------------------------------------------
|
| PURGEHEAP_OK
|
| Called during boot.
PURGEHEAP_OK:
    MOVEQ.L     #0x0,D2                         | reset accumulator
PURGEHEAP_SKIP:
    MOVEA.L     A2,A0                           | update start-of-run
PURGEHEAP_NO_2:
    CMPA.L      A3,A2                           | reached bkLim?
    BCS.B       PURGEHEAP_NO                    | no -> continue scan
    LEA.L       0x34(A6),A0                     | first block
    CMPA.L      0x4(A6),A0                      | purgePtr wrapped?
    BEQ.B       PURGEHEAP_OK_2                  | yes -> can't find space
    MOVE.L      A0,0x4(A6)                      | reset purgePtr
    BRA.B       PURGEHEAP_CONT                  | -> retry from start
| ----------------------------------------------------------
|
| PURGEHEAP_OK_2
|
| Called during boot.
PURGEHEAP_OK_2:
    MOVEA.L     A3,A2                           | limit = bkLim (purge to end)
PURGEHEAP_OK_3:
    MOVE.L      (A0),D1                         | D1 = block size
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    TST.B       (A0)                            | block type
    BPL.B       PURGEHEAP_SKIP_2                | free/non-reloc -> skip
    MOVEA.L     0x4(A0),A1                      | rel handle
    ADDA.L      A6,A1                           | master ptr
    TST.B       (A1)                            | locked?
    BMI.B       PURGEHEAP_SKIP_2                | yes -> skip
    BTST        #0x6,(A1)                       | purgeable?
    BEQ.B       PURGEHEAP_SKIP_2                | no -> skip
    BSR.W       EH_CONT_2                       | purge this block
    CMP.L       D0,D1                           | freed enough?
    BCC.B       PURGEHEAP_DONE                  | yes -> done
PURGEHEAP_SKIP_2:
    ADDA.L      D1,A0                           | advance to next block
    MOVE.L      A0,0x4(A6)                      | update purgePtr
    CMPA.L      A2,A0                           | past scan limit?
    BCS.B       PURGEHEAP_OK_3                  | no -> continue purging
PURGEHEAP_DONE:
    BSR.B       TOTEPURGEABLES_RETRY            | compact after purge
    MOVEM.L     (SP)+,D2/A1-A4                  | restore regs
    RTS                                         | return from PurgeHeap
TOTEPURGEABLES:
    MOVEQ.L     #0x0,D0                         | D0 = total purgeable + free
    MOVE.L      D0,D1                           | D1 = current run size
    MOVEA.L     D0,A0                           | A0 = largest contiguous run
    LEA.L       0x34(A6),A1                     | A1 = first block
TOTEPURGEABLES_CONT:
    CMPA.L      (A6),A1                         | reached bkLim?
    BCC.B       TOTEPURGEABLES_OK_2             | yes -> finish
    MOVE.L      (A1),D2                         | D2 = block size
    AND.L       (Lo3Bytes).W,D2                 | mask to 24-bit
    TST.B       (A1)                            | block type
    BEQ.B       TOTEPURGEABLES_OK               | free -> count
    BPL.B       TOTEPURGEABLES_CONT_2           | non-reloc -> break run
    MOVEA.L     0x4(A1),A2                      | rel handle
    ADDA.L      A6,A2                           | master ptr
    TST.B       (A2)                            | locked?
    BMI.B       TOTEPURGEABLES_CONT_2           | yes -> break run
    BTST        #0x6,(A2)                       | purgeable?
    BEQ.B       TOTEPURGEABLES_EXIT             | no -> skip (not purgeable)
TOTEPURGEABLES_OK:
    ADD.L       D2,D1                           | add to current run
TOTEPURGEABLES_EXIT:
    ADDA.L      D2,A1                           | advance to next block
    BRA.B       TOTEPURGEABLES_CONT             | -> continue scan
| ----------------------------------------------------------
|
| TOTEPURGEABLES_CONT_2
|
TOTEPURGEABLES_CONT_2:
    PEA.L       TOTEPURGEABLES_EXIT(PC)         | return to loop after updating run
TOTEPURGEABLES_OK_2:
    ADD.L       D1,D0                           | total += current run
    CMPA.L      D1,A0                           | new largest?
    BCC.B       TOTEPURGEABLES_OK_3             | no ->
    MOVEA.L     D1,A0                           | A0 = new largest run
TOTEPURGEABLES_OK_3:
    MOVEQ.L     #0x0,D1                         | reset current run
    RTS                                         | return (or continue loop)
| ----------------------------------------------------------
|
| TOTEPURGEABLES_CONT_3
|
TOTEPURGEABLES_CONT_3:
    MOVE.L      0x2C(A6),D2                     | D2 = zone.gzProc
    BEQ.B       TOTEPURGEABLES_EXIT_2           | no grow-zone func -> return
    MOVEM.L     D0-D1/D3-D7/A0-A6,-(SP)         | save all regs
    MOVEA.L     0x2C(A6),A1                     | A1 = grow-zone function
    CLR.L       -(SP)                           | space for result
    MOVE.L      D0,-(SP)                        | push needed bytes
    JSR         (A1)                            | call grow-zone func
    MOVE.L      (SP)+,D2                        | D2 = result (0 = can't grow)
    MOVEM.L     (SP)+,D0-D1/D3-D7/A0-A6         | restore all regs
TOTEPURGEABLES_EXIT_2:
    RTS                                         | return from GrowZone call
| ----------------------------------------------------------
|
| TOTEPURGEABLES_RETRY
|
| Called during boot.
TOTEPURGEABLES_RETRY:
    BRA.W       COMPACTHP                       | -> compact heap
BKCOMPACTS:
    MOVEM.L     D0/D2,-(SP)                     | save regs
    BSR.B       TOTEPURGEABLES_RETRY            | compact heap
    CMP.L       D1,D0                           | largest block >= needed?
    BLS.B       BKCOMPACTS_DONE                 | yes -> done
    CMPA.L      (ApplZone).W,A6                 | in app zone?
    BNE.B       BKCOMPACTS_SKIP                 | no -> skip grow
    TST.L       D2                              | grow allowed?
    BEQ.B       BKCOMPACTS_SKIP                 | no ->
    BSR.W       ZONEADJUSTEND_CONT              | try growing zone
    BSR.B       TOTEPURGEABLES_RETRY            | compact again
    CMP.L       D1,D0                           | enough now?
    BLS.B       BKCOMPACTS_DONE                 | yes -> done
BKCOMPACTS_SKIP:
    BSR.W       PURGEHEAP                       | purge purgeable blocks
    CMP.L       D1,D0                           | enough now?
    BLS.B       BKCOMPACTS_DONE                 | yes -> done
    TST.L       D2                              | grow-zone allowed?
    BEQ.B       BKCOMPACTS_DONE                 | no -> give up
BKCOMPACTS_RETRY:
    BSR.B       TOTEPURGEABLES_CONT_3           | call grow-zone func
    BSR.B       TOTEPURGEABLES_RETRY            | compact again
    CMP.L       D1,D0                           | enough now?
    BLS.B       BKCOMPACTS_DONE                 | yes -> done
    TST.L       D2                              | grow-zone returned more?
    BNE.B       BKCOMPACTS_RETRY                | yes -> try again
    SUBA.L      A0,A0                           | A0 = nil (no free block)
| Called by: BKCOMPACTS, BKCOMPACTS_SKIP, BKCOMPACTS_RETRY
BKCOMPACTS_DONE:
    MOVE.L      A0,D2                           | D2 = result
    MOVEM.L     (SP)+,D0/D2                     | restore regs
    RTS                                         | return from BKCompacts
P_BFindS:
    MOVEM.L     D1-D2/A1-A2,-(SP)               | save regs
    MOVE.L      (Lo3Bytes).W,D2                 | D2 = 24-bit mask
    LEA.L       0x30(A6),A2                     | A2 = zone.hFstFree rover
    BTST        #0x5,0x16(A6)                   | first-fit disabled?
    BEQ.B       BFINDS_RETRY                    | no -> use rover
    CLR.L       (A2)                            | reset rover
BFINDS_RETRY:
    MOVE.L      (A2),D1                         | D1 = rover position
    MOVEA.L     D1,A1                           | A1 = scan start
    BNE.B       BFINDS_EMPTY                    | have rover ->
    LEA.L       0x34(A6),A1                     | start from first block
BFINDS_EMPTY:
    CMPA.L      (A6),A1                         | at bkLim?
    BCC.B       BFINDS_ERR                      | yes -> not found
    MOVE.L      (A1),D1                         | D1 = block header
    TST.B       (A1)                            | free block? (tag=0)
    BEQ.B       BFINDS_OK                       | yes -> check size
BFINDS_NO:
    AND.L       D2,D1                           | D1 = block size
    ADDA.L      D1,A1                           | advance to next block
    BRA.B       BFINDS_EMPTY                    | -> continue scan
| ----------------------------------------------------------
|
| BFINDS_OK
|
| Called during boot (30,345 times in 30s trace).
BFINDS_OK:
    MOVEA.L     A1,A0                           | A0 = free block start
    ADDA.L      D1,A0                           | A0 = next block
    TST.B       (A0)                            | next block also free?
    BNE.B       BFINDS_NO_2                     | no -> check size
    CMPA.L      (A6),A0                         | at bkLim?
    BCC.B       BFINDS_NO_2                     | yes -> check size
    ADD.L       (A0),D1                         | merge: add next free size
    MOVE.L      D1,(A1)                         | update merged block size
    BRA.B       BFINDS_OK                       | -> try merging more
| ----------------------------------------------------------
|
| BFINDS_NO_2
|
| Called during boot (15,988 times in 30s trace).
BFINDS_NO_2:
    CMP.L       D0,D1                           | block >= needed size?
    BCS.B       BFINDS_NO                       | no -> keep scanning
    MOVEA.L     A1,A0                           | A0 = found block
    BRA.B       BFINDS_EXIT                     | -> return success
| ----------------------------------------------------------
|
| BFINDS_ERR
|
| Called during boot.
BFINDS_ERR:
    TST.L       (A2)                            | rover was non-zero?
    BEQ.B       BFINDS_ERR_2                    | no -> truly not found
    CLR.L       (A2)                            | reset rover
    BRA.B       BFINDS_RETRY                    | -> scan from start
| ----------------------------------------------------------
|
| BFINDS_ERR_2
|
| Called during boot.
BFINDS_ERR_2:
    SUBA.L      A0,A0                           | A0 = nil (not found)
BFINDS_EXIT:
    MOVE.L      A0,(A2)                         | update rover
    MOVEM.L     (SP)+,D1-D2/A1-A2               | restore regs
    RTS                                         | return from BFindS
| ----------------------------------------------------------
|
| AllocBK: carve block from free space at A0
| D0 = actual size needed, A0 = free block, A1 = master pointer or nil
|
| Called by: NEWPTR, NEWHANDLE_ALLOC, REALLOCHANDLE_OK, HMAKEMOREMASTERS_CONT, MAKEPTRSPC_CONT_5
ALLOCBK:
    MOVEM.L     D0-D5,-(SP)                     | save regs
    MOVE.L      D0,D4                           | D4 = save original size
    BSR.W       ACTUALS                         | round to actual block size
    BSR.B       P_BFindS                        | find free block >= D0
    BNE.B       ALLOCBK_FOUND                   | found ->
    MOVEQ.L     #-0x1,D2                        | D2 = try all strategies
    BSR.W       BKCOMPACTS                      | compact + purge + grow
    BNE.B       ALLOCBK_FOUND                   | found ->
    SUBA.L      A0,A0                           | A0 = nil (allocation failed)
    BRA.B       ALLOCBK_ERR                     | -> return failure
ALLOCBK_FOUND:
    MOVE.L      D0,D2                           | D2 = actual size
    MOVE.L      (A0),D0                         | D0 = free block header
    MOVE.L      A1,D5                           | master ptr
    BEQ.B       ALLOCBK_EMPTY                   | nil -> non-relocatable
    SUB.L       A6,D5                           | D5 = relative handle
    MOVEQ.L     #0x2,D1                         | D1 = tag type (relocatable)
    MOVEQ.L     #-0x1,D3                        | D3 = -1 (allocate at high end)
    BRA.B       ALLOCBK_CONT                    | -> build header
| non-relocatable block: no handle
ALLOCBK_EMPTY:
    MOVE.L      A6,D5                           | D5 = zone ptr (for non-reloc)
    MOVEQ.L     #0x1,D1                         | D1 = tag type (non-reloc)
    MOVEQ.L     #0x0,D3                         | D3 = 0 (allocate at low end)
| build the block header and split free space
ALLOCBK_CONT:
    BSR.B       ALLOCBK_CONT_3                  | split free block
    MOVE.L      D5,0x4(A0)                      | set relHandle/zone ptr
    MOVE.L      D4,D0                           | original size
    BSR.B       ALLOCBK_CONT_2                  | set correction byte
    ADDQ.L      #0x8,A0                         | A0 = block data
    MOVE.L      A1,D5                           | master ptr valid?
    BEQ.B       ALLOCBK_ERR                     | no -> skip MP update
    MOVE.L      A0,(A1)                         | master ptr = data address
ALLOCBK_ERR:
    MOVE.L      A0,D0                           | D0 = data ptr (Z if nil)
    MOVEM.L     (SP)+,D0-D5                     | restore regs
    RTS                                         | return from AllocBk
| ----------------------------------------------------------
|
| ALLOCBK_CONT_2
|
| Called during boot (34,443 times in 30s trace).
ALLOCBK_CONT_2:
    MOVE.L      D1,-(SP)                        | save D1
    MOVE.L      (A0),D1                         | D1 = block header
    AND.L       (Lo3Bytes).W,D1                 | block size
    SUBQ.L      #0x8,D1                         | - header
    SUB.L       D0,D1                           | - data size = correction
    ANDI.B      #0xF,D1                         | keep low 4 bits
    ANDI.B      #0xC0,(A0)                      | clear tag low bits
    OR.B        D1,(A0)                         | set correction nibble
    MOVE.L      (SP)+,D1                        | restore D1
    RTS                                         | return from SetCorrection
| ----------------------------------------------------------
|
| ALLOCBK_CONT_3
|
| Called during boot (15,878 times in 30s trace).
ALLOCBK_CONT_3:
    MOVEM.L     D0-D2/D4/A1,-(SP)               | save regs
    MOVE.L      D0,D4                           | D4 = free block size
    SUB.L       D2,D0                           | D0 = leftover after alloc
    MOVEA.L     A0,A1                           | A1 = free block start
    CMPI.L      #0xC,D0                         | leftover >= min block?
    BCS.B       ALLOCBK_NO_2                    | no -> use entire block
    TST.W       D3                              | relocatable?
    BEQ.B       ALLOCBK_NO                      | no -> low end
    TST.B       0x16(A6)                        | zone favoring high?
    BPL.B       ALLOCBK_NO                      | no -> low end
    ADDA.L      D0,A1                           | A1 = alloc at high end
    BRA.B       ALLOCBK_CONT_4                  | -> create leftover block
| ----------------------------------------------------------
|
| ALLOCBK_NO
|
| Called during boot (15,867 times in 30s trace).
ALLOCBK_NO:
    ADDA.L      D2,A0                           | A0 = leftover block start
ALLOCBK_CONT_4:
    BSR.W       MAKEBKF                         | make leftover as free block
    BRA.B       ALLOCBK_CONT_5                  | -> finalize
ALLOCBK_NO_2:
    MOVE.L      D4,D2                           | no split: use entire block
ALLOCBK_CONT_5:
    MOVE.L      D2,D0                           | D0 = allocated size
    NEG.L       D0                              | negate for AdjustFree
    BSR.W       ADJUSTFREE                      | zcbFree -= allocated size
    MOVEA.L     A1,A0                           | A0 = new block start
    ROR.L       #0x2,D1                         | build tag byte from type bits
    ADD.L       D2,D1                           | + block size
    MOVE.L      D1,(A0)                         | write block header
    MOVEM.L     (SP)+,D0-D2/D4/A1               | restore regs
    RTS                                         | return from SplitFree
| ----------------------------------------------------------
|
| ALLOCBK_CONT_6
|
| Called during boot (1,397 times in 30s trace).
ALLOCBK_CONT_6:
    MOVEM.L     D0-D2/A0-A2,-(SP)               | save regs
    MOVEA.L     (0x4B8).W,A2                    | block-move notification vector
    JSR         (A2)                            | call notification
    MOVEM.L     (SP)+,D0-D2/A0-A2               | restore regs
    RTS                                         | return from BlockMoveNotify
COMPACTHP:
    MOVEM.L     D0/D2-D5/A1-A4,-(SP)            | save regs
    MOVE.L      D0,D3                           | D3 = minimum needed size
    MOVEQ.L     #0x0,D1                         | D1 = largest free block
    LEA.L       0x34(A6),A0                     | A0 = first block (heapData)
    BRA.B       COMPACTHP_CONT                  | -> scan loop
| ----------------------------------------------------------
|
| COMPACTHP_SKIP
|
| Called during boot.
COMPACTHP_SKIP:
    MOVE.L      (A0),D4                         | block size
    AND.L       (Lo3Bytes).W,D4                 | mask to 24-bit
    ADDA.L      D4,A0                           | advance past non-free block
    CMPA.L      (A6),A0                         | at bkLim?
    BCC.B       COMPACTHP_OK                    | yes -> measure free space
COMPACTHP_CONT:
    TST.B       (A0)                            | free block? (tag=0)
    BNE.B       COMPACTHP_SKIP                  | no -> skip
COMPACTHP_OK:
    BTST        #0x4,0x16(A6)                   | favor-contiguous flag?
    SEQ.B       D5                              | D5 = FF if not set, 0 if set
    MOVEA.L     A0,A2                           | A2 = free block start
COMPACTHP_CONT_2:
    MOVEA.L     A0,A1                           | A1 = destination for moves
    MOVEQ.L     #0x0,D2                         | D2 = accumulated free space
COMPACTHP_CONT_3:
    CMPA.L      (A6),A0                         | at bkLim?
    BCC.B       COMPACTHP_OK_4                  | yes -> done with this run
    MOVE.L      (A0),D0                         | D0 = block header
    AND.L       (Lo3Bytes).W,D0                 | block size
    TST.B       (A0)                            | block type
    BEQ.B       COMPACTHP_OK_2                  | free -> accumulate
    BPL.B       COMPACTHP_OK_3                  | non-reloc -> can't move
    MOVEA.L     0x4(A0),A3                      | rel handle
    ADDA.L      A6,A3                           | master ptr
    TST.B       (A3)                            | locked?
    BMI.B       COMPACTHP_OK_3                  | yes -> can't move
    TST.B       D5                              | favor-contiguous?
    BNE.B       COMPACTHP_SKIP_2                | yes -> don't move
    LEA.L       0x8(A1),A4                      | A4 = new data address
    MOVE.B      (A3),D4                         | save MP flags
    MOVE.L      A4,(A3)                         | update master ptr
    MOVE.B      D4,(A3)                         | restore MP flags
    BSR.B       ALLOCBK_CONT_6                  | notify block move
    ADDA.L      D0,A1                           | advance dest past moved block
    BRA.B       COMPACTHP_SKIP_2                | -> advance source
| ----------------------------------------------------------
|
| COMPACTHP_OK_2
|
| Called during boot.
COMPACTHP_OK_2:
    ADD.L       D0,D2                           | accumulate free space
    MOVEA.L     A1,A3                           | A3 = best free block ptr
    CMP.L       D3,D2                           | enough free space?
    BCS.B       COMPACTHP_SKIP_2                | not yet -> continue
    TST.B       D5                              | favor-contiguous mode?
    BEQ.B       COMPACTHP_OK_5                  | no -> done
    CLR.B       D5                              | switch to move mode
    MOVEA.L     A2,A0                           | restart from free block start
    BRA.B       COMPACTHP_CONT_2                | -> compact with moves
| ----------------------------------------------------------
|
| COMPACTHP_SKIP_2
|
| Called during boot.
COMPACTHP_SKIP_2:
    ADDA.L      D0,A0                           | advance to next block
    BRA.B       COMPACTHP_CONT_3                | -> continue scan
| ----------------------------------------------------------
|
| COMPACTHP_OK_3
|
| Called during boot.
COMPACTHP_OK_3:
    BSR.B       COMPACTHP_CONT_4                | finalize free space
    BRA.B       COMPACTHP_SKIP                  | -> skip non-movable block
| ----------------------------------------------------------
|
| COMPACTHP_OK_4
|
| Called during boot.
COMPACTHP_OK_4:
    SUBA.L      A3,A3                           | no best block
COMPACTHP_OK_5:
    BSR.B       COMPACTHP_CONT_4                | finalize free space
    MOVEA.L     A3,A0                           | A0 = largest free block
    MOVE.L      A0,0x30(A6)                     | update zone.hFstFree rover
    MOVEM.L     (SP)+,D0/D2-D5/A1-A4            | restore regs
    RTS                                         | return from TE_PUT_STYL_SCRAP
| ----------------------------------------------------------
|
| COMPACTHP_CONT_4
|
| Called during boot.
COMPACTHP_CONT_4:
    TST.L       D2                              | any accumulated free space?
    BEQ.B       COMPACTHP_DONE                  | no free space -> return
    TST.B       D5                              | favor-contiguous (no moves)?
    BNE.B       COMPACTHP_SKIP_3                | yes -> don't write header
    MOVE.L      D2,(A1)                         | create free block (size = D2)
COMPACTHP_SKIP_3:
    CMP.L       D2,D1                           | new largest?
    BCC.B       COMPACTHP_DONE                  | no -> keep D1
    MOVE.L      D2,D1                           | D1 = new largest free block
COMPACTHP_DONE:
    RTS                                         | return from FinalizeRun
TOMAXLIMIT:
    MOVE.L      (BufPtr).W,D2                   | D2 = BufPtr
    SUB.L       (DefltStack).W,D2               | - default stack = max limit
MAXLIMIT:
    ANDI.W      #0xFFFC,D2                      | align to longword
    MOVE.L      SP,D1                           | current SP
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    SUB.L       (MinStack).W,D1                 | - min stack reserve
    ANDI.W      #0xFFFC,D1                      | align to longword
    CMP.L       D2,D1                           | SP-based limit lower?
    BCS.B       MAXLIMIT_OK                     | yes -> use it
    MOVE.L      D2,D1                           | use ApplLimit-based
MAXLIMIT_OK:
    RTS                                         | D1 = max growable limit
ZONEADJUSTEND:
    MOVEM.L     D0/A0/A2-A3,-(SP)               | save regs
    MOVEA.L     A0,A3                           | A3 = new bkLim
    MOVEA.L     (A6),A0                         | A0 = old bkLim (sentinel)
    MOVE.L      A3,D0                           | D0 = new - old
    SUB.L       A0,D0                           | = expansion size
    MOVE.L      #0xC,(A3)                       | new sentinel = 12 bytes
    BSR.W       MAKEBKF                         | mark old sentinel as free
    BSR.W       ADJUSTFREE                      | merge with adjacent free
    MOVE.L      A3,(A6)                         | zone.bkLim = new end
    MOVEM.L     (SP)+,D0/A0/A2-A3               | restore regs
    RTS                                         | return from ZoneAdjustEnd
| ----------------------------------------------------------
|
| ZONEADJUSTEND_CONT
|
| Called during boot.
ZONEADJUSTEND_CONT:
    MOVEM.L     D0-D3/A0-A2,-(SP)               | save regs
    ADDI.L      #0x400,D0                       | round up to 1KB
    ANDI.W      #0xFC00,D0                      | align to 1KB boundary
    MOVE.L      D0,D3                           | D3 = requested growth
    MOVE.L      (ApplLimit).W,D2                | ApplLimit
    BSR.B       MAXLIMIT                        | D1 = max growable limit
    MOVE.L      (HeapEnd).W,D2                  | D2 = current heap end
    CMP.L       D2,D1                           | any room to grow?
    BLS.B       ZONEADJUSTEND_OK                | no ->
    ADD.L       D0,D2                           | D2 = desired new end
    BCS.B       ZONEADJUSTEND_OK                | overflow ->
    CMP.L       D2,D1                           | requested fits?
    BCS.B       ZONEADJUSTEND_NO                | no -> use max
    MOVE.L      D2,D1                           | cap to requested
    MOVEQ.L     #0x0,D3                         | no leftover
    BRA.B       ZONEADJUSTEND_CONT_2            | -> grow zone
| ----------------------------------------------------------
|
| ZONEADJUSTEND_NO
|
ZONEADJUSTEND_NO:
    MOVE.L      D1,D0                           | D0 = growth amount
    SUB.L       (HeapEnd).W,D0                  | = max - current end
    CMPI.L      #0xC,D0                         | room for min block?
    BCS.B       ZONEADJUSTEND_OK                | no -> skip
ZONEADJUSTEND_CONT_2:
    MOVE.L      D1,(HeapEnd).W                  | update HeapEnd
    MOVEA.L     D1,A0                           | A0 = new end address
    BSR.B       ZONEADJUSTEND                   | adjust zone end, add free block
ZONEADJUSTEND_OK:
    MOVEM.L     (SP)+,D0-D3/A0-A2               | restore registers
    RTS                                         | return from ZONEADJUSTEND_OK
| Called by: MAXBLOCK_OR_COMPACT, PURGEMEM, ALLOCBK, SETSIZE, MAKEPTRSPC
ACTUALS:
    ADDQ.L      #0x8,D0                         | add 8-byte block header
    ADDQ.L      #0x1,D0                         | add 1 for word alignment
    ANDI.W      #0xFFFE,D0                      | round down to even (word-align)
    CMPI.L      #0xC,D0                         | less than minimum (12)?
    BCC.B       ACTUALS_OK                      | no -> size is valid
    MOVEQ.L     #0xC,D0                         | enforce minimum 12-byte block
ACTUALS_OK:
    RTS                                         | return from ACTUALS_OK
| Called by: GETPTRSIZE, GETHANDLESIZE, REALLOCHANDLE_LOCKED, SETSIZE, MAKEPTRSPC_SKIP_3 (and 1 more)
GETSIZE:
    MOVE.L      D1,-(SP)                        | save D1
    SUBQ.L      #0x8,A0                         | back up to block header
    MOVEQ.L     #0xF,D1                         | D1 = 0xF: mask for size correction
    AND.B       (A0),D1                         | D1 = correction nibble from tag byte
    MOVE.L      (A0),D0                         | D0 = block header (tag+size)
    AND.L       (Lo3Bytes).W,D0                 | mask to 24-bit physical size
    SUBQ.L      #0x8,D0                         | subtract 8-byte header
    SUB.L       D1,D0                           | subtract size correction = logical size
    ADDQ.L      #0x8,A0                         | restore A0 to data pointer
    MOVE.L      (SP)+,D1                        | restore D1
    RTS                                         | return from GETSIZE
CLEARGZSTUFF:
    CLR.L       (GZRootHnd).W                   | clear grow-zone root handle
    CLR.L       (GZRootPtr).W                   | clear grow-zone root pointer
    RTS                                         | return from CLEARGZSTUFF
SETSIZE:
    MOVEM.L     D1-D6/A0-A3,-(SP)               | save working registers
    MOVE.B      (A1),-(SP)                      | save MP flags on stack
    MOVE.L      D0,D1                           | D1 = new logical size
    BSR.B       ACTUALS                         | round to actual block size
    MOVE.L      D0,D3                           | D3 = actual size needed
    BSR.B       GETSIZE                         | D0 = current logical size
    CMP.L       D0,D1                           | same size?
    BEQ.W       SETSIZE_OK_5                    | yes -> just update correction
    MOVEA.L     A0,A2                           | A2 = block header
    SUBQ.L      #0x8,A2                         | back up to header
    MOVE.L      (A2),D2                         | D2 = current header (tag+size)
    AND.L       (Lo3Bytes).W,D2                 | mask to physical size
    MOVE.L      D2,D4                           | D4 = current physical size
    CMP.L       D2,D3                           | new vs current physical?
    BEQ.W       SETSIZE_NO_5                    | equal -> just update correction
    BCS.W       SETSIZE_CONT_4                  | smaller -> shrink in place
    MOVE.L      D3,D5                           | D5 = additional bytes needed
    SUB.L       D2,D5                           | D5 = new - current
    MOVE.L      A1,(GZRootHnd).W                | protect handle during grow-zone
    MOVE.L      A0,(GZRootPtr).W                | protect pointer during grow-zone
    MOVEA.L     A2,A3                           | A3 = end of current block
    ADDA.L      D4,A3                           | A3 = current end
    MOVEQ.L     #0x0,D6                         | D6 = 0: accumulated free after block
SETSIZE_CONT:
    CMPA.L      (A6),A3                         | past zone end?
    BCC.B       SETSIZE_OK                      | yes -> not enough free space
    TST.B       (A3)                            | next block free?
    BNE.B       SETSIZE_OK                      | no -> can't extend
    ADD.L       (A3),D6                         | D6 += free block size
    ADDA.L      (A3),A3                         | advance past free block
    BRA.B       SETSIZE_CONT                    | -> check for more free blocks
| ----------------------------------------------------------
|
| SETSIZE_OK
|
| Called during boot (7,440 times in 30s trace).
SETSIZE_OK:
    SUB.L       D6,D5                           | D5 -= accumulated free
    BLS.W       SETSIZE_EMPTY                   | enough free? -> extend in place
    MOVE.L      A1,D0                           | D0 = master pointer
    BEQ.W       SETSIZE_EMPTY                   | nil -> can't relocate (ptr block)
    TST.B       (SP)                            | locked? (check saved flags on stack)
    BMI.W       SETSIZE_EMPTY                   | yes -> can't relocate
    LEA.L       0x34(A6),A3                     | A3 = zone.heapData (scan start)
SETSIZE_CONT_2:
    CMPA.L      A2,A3                           | reached our block?
    BCC.B       SETSIZE_OK_4                    | yes -> no room before us
    MOVE.L      (A3),D0                         | D0 = block header
    TST.B       (A3)                            | is block free?
    BEQ.B       SETSIZE_OK_2                    | yes -> try coalescing
    AND.L       (Lo3Bytes).W,D0                 | mask to size
    ADDA.L      D0,A3                           | advance past block
    MOVEQ.L     #0x0,D0                         | D0 = 0: reset free counter
    BRA.B       SETSIZE_CONT_2                  | -> continue scanning
| ----------------------------------------------------------
|
| SETSIZE_OK_2
|
| Called during boot.
SETSIZE_OK_2:
    MOVEA.L     A3,A0                           | A0 = start of free region
    MOVEQ.L     #0x0,D0                         | D0 = 0: reset accumulated free
SETSIZE_OK_3:
    CMPA.L      0x30(A6),A3                     | is this the allocPtr?
    BNE.B       SETSIZE_SKIP                    | no -> skip
    MOVE.L      A0,0x30(A6)                     | update allocPtr past coalesced region
SETSIZE_SKIP:
    ADD.L       (A3),D0                         | D0 += free block size
    ADDA.L      (A3),A3                         | advance past free block
    TST.B       (A3)                            | next block also free?
    BEQ.B       SETSIZE_OK_3                    | yes -> keep coalescing
    MOVE.L      D0,(A0)                         | write coalesced free block size
    BRA.B       SETSIZE_CONT_2                  | -> continue scanning for our block
| ----------------------------------------------------------
|
| SETSIZE_OK_4
|
| Called during boot.
SETSIZE_OK_4:
    MOVE.L      D5,D6                           | D6 = additional bytes still needed
    LSR.L       #0x2,D6                         | D6 / 4: tolerance threshold
    CMP.L       D6,D0                           | free block before us big enough?
    BLS.B       SETSIZE_NO_3                    | no -> try extending after
    MOVEQ.L     #0xC,D6                         | D6 = 12 (minimum block size)
    CMP.L       D5,D6                           | D5 (still needed) >= 12?
    BLS.B       SETSIZE_NO                      | no -> can't split, use 12 minimum
    MOVE.L      D6,D5                           | D5 = 12 (minimum allocation)
SETSIZE_NO:
    MOVEQ.L     #0x18,D6                        | D6 = 24 (header + min + safety)
    ADD.L       D5,D6                           | D6 = 24 + needed
    CMP.L       D6,D0                           | free block >= 24 + needed?
    BCS.B       SETSIZE_NO_2                    | no -> use entire free block
    SUB.L       D5,D0                           | carve needed from end of free block
    MOVE.L      D0,(A0)                         | update free block size (remainder)
    ADDA.L      D0,A0                           | A0 = new block position
    MOVE.L      D5,D0                           | D0 = carved size
SETSIZE_NO_2:
    MOVE.L      A0,(A1)                         | update MP to new block + 8
    ADDQ.L      #0x8,(A1)                       | adjust for data offset
    MOVE.B      (SP),(A1)                       | restore MP flags
    MOVEM.L     D0/A1,-(SP)                     | save D0 and A1
    CMPA.L      0x30(A6),A2                     | is old block at allocPtr?
    BNE.B       SETSIZE_SKIP_2                  | no -> skip
    MOVE.L      A0,0x30(A6)                     | update allocPtr to new location
SETSIZE_SKIP_2:
    EXG         A0,A2                           | swap old and new block addresses
    MOVEA.L     A2,A1                           | A1 = new block, A2 = old block
    MOVE.L      D4,D0                           | D0 = old physical size
    BSR.W       ALLOCBK_CONT_6                  | copy block data to new location
    MOVEA.L     A2,A0                           | A0 = old block end
    ADDA.L      D4,A0                           | advance by old size
    MOVE.L      (SP)+,(A0)                      | write free block at old location
    MOVEA.L     (SP)+,A1                        | restore A1
    LEA.L       0x8(A2),A0                      | A0 = new block data pointer
    MOVE.L      A0,(GZRootPtr).W                | update GZRootPtr to new location
    BRA.B       SETSIZE_EMPTY                   | -> extend at new position
| ----------------------------------------------------------
|
| SETSIZE_NO_3
|
| Called during boot.
SETSIZE_NO_3:
    MOVEA.L     A2,A0                           | A0 = block header
    ADDA.L      D4,A0                           | advance past current size
    MOVE.L      (A0),D0                         | D0 = next block header
    AND.L       (Lo3Bytes).W,D0                 | mask to size
    CMP.L       D0,D3                           | new size fits within next block?
    BCC.B       SETSIZE_EMPTY                   | yes -> extend in place
    TST.B       (A0)                            | next block free?
    BNE.B       SETSIZE_NO_4                    | no -> must relocate block
| Called by: SETSIZE_OK, SETSIZE_SKIP_2, SETSIZE_NO_3
SETSIZE_EMPTY:
    MOVEA.L     A2,A0                           | A0 = our block header
    MOVE.L      D3,D0                           | D0 = additional bytes needed
    SUB.L       D2,D0                           | D0 = new - old
    ADDA.L      D2,A2                           | A2 = end of old block
    BSET        #0x7,(A1)                       | temporarily lock during SetSize
    BSR.W       MAKEPTRSPC_CONT_2               | recursive SetSize for extension
    BCLR        #0x7,(A1)                       | unlock after SetSize
    MOVE.L      A2,D4                           | D4 = result address
    BNE.B       SETSIZE_CONT_3                  | success? -> merge
SETSIZE_NO_4:
    MOVE.L      A1,D4                           | D4 = master pointer (nil for ptr)
    BEQ.B       SETSIZE_EMPTY_2                 | nil -> can't relocate
    TST.B       (SP)                            | locked? (saved flags)
    BMI.B       SETSIZE_EMPTY_2                 | yes -> can't relocate
    MOVE.L      D1,D0                           | D0 = new logical size
    BCLR        #0x6,(A1)                       | clear purge bit for reallocation
    BSR.W       MAKEPTRSPC_CONT_5               | allocate new block, move data
    MOVE.B      (SP),(A1)                       | restore MP flags
    BSR.W       CLEARGZSTUFF                    | clear grow-zone protection
    BRA.B       SETSIZE_ERR                     | -> return result
| ----------------------------------------------------------
|
| SETSIZE_EMPTY_2
|
SETSIZE_EMPTY_2:
    BSR.W       CLEARGZSTUFF                    | clear grow-zone protection
    MOVEQ.L     #-0x6C,D0                       | memFullErr (-108)
    BRA.B       SETSIZE_ERR                     | -> return error
| ----------------------------------------------------------
|
| SETSIZE_CONT_3
|
| Called during boot (7,436 times in 30s trace).
SETSIZE_CONT_3:
    BSR.W       CLEARGZSTUFF                    | clear grow-zone protection
    MOVE.L      (A2),D0                         | D0 = free block size
    MOVE.L      D0,D4                           | D4 = new physical size
    ADD.L       D2,D4                           | D4 = old + free
    MOVEA.L     A0,A2                           | A2 = block header
    MOVE.B      (A2),D5                         | D5 = save tag byte
    MOVE.L      D4,(A2)                         | write new physical size
    MOVE.B      D5,(A2)                         | restore tag byte
    NEG.L       D0                              | negate freed size
    BSR.B       ADJUSTFREE                      | subtract from zcbFree
SETSIZE_CONT_4:
    SUB.L       D3,D4                           | D4 = excess (physical - needed)
    CMPI.L      #0xC,D4                         | excess >= 12 (min block)?
    BCS.B       SETSIZE_NO_5                    | no -> keep it all
    BTST        #0x0,0x16(A6)                   | zone read-only? (flags bit 0)
    BNE.B       SETSIZE_ERR_2                   | yes -> return error
    MOVEA.L     A2,A0                           | A0 = block header
    ADDA.L      D3,A0                           | advance by new size
    MOVE.B      (A2),D5                         | D5 = save tag byte
    MOVE.L      D3,(A2)                         | write new (smaller) physical size
    MOVE.B      D5,(A2)                         | restore tag byte
    MOVE.L      D4,D0                           | D0 = excess as free block
    BSR.W       MAKEBKF                         | create free block from excess
    BSR.B       ADJUSTFREE                      | add excess to zcbFree
SETSIZE_NO_5:
    MOVEA.L     A2,A0                           | A0 = block header
    MOVE.L      D1,D0                           | D0 = new logical size
    BSR.W       ALLOCBK_CONT_2                  | update size correction nibble
SETSIZE_OK_5:
    MOVEQ.L     #0x0,D0                         | noErr
SETSIZE_ERR:
    MOVE.B      (SP)+,(A1)                      | restore MP flags from stack
    MOVEM.L     (SP)+,D1-D6/A0-A3               | restore registers
    RTS                                         | return from SETSIZE_ERR
| ----------------------------------------------------------
|
| SETSIZE_ERR_2
|
SETSIZE_ERR_2:
    MOVEQ.L     #-0x63,D0                       | memROZErr (-99): read-only zone
    BRA.B       SETSIZE_ERR                     | -> return error
| Called by: EH_CONT_2, ALLOCBK_CONT_5, ZONEADJUSTEND, SETSIZE_CONT_3, SETSIZE_CONT_4 (and 3 more)
ADJUSTFREE:
    ADD.L       D0,0xC(A6)                      | zone.zcbFree += D0
    BMI.B       ADJUSTFREE_ERR                  | went negative? -> system error
    RTS                                         | return from ADJUSTFREE
| ----------------------------------------------------------
|
| ADJUSTFREE_ERR
|
ADJUSTFREE_ERR:
    MOVEQ.L     #0x21,D0                        | dsMemFullErr (33): heap corrupted
    _SysError                                   | fatal: negative free space
NEXTMASTER:
    MOVEM.L     D0/A0,-(SP)                     | save D0 and A0
    MOVEA.L     0x8(A6),A1                      | A1 = zone.hFstFree (free MP list head)
    MOVE.L      A1,D0                           | D0 = A1 (for Z flag test)
    BNE.B       NEXTMASTER_CONT                 | any free master pointers?
    BSR.B       HMAKEMOREMASTERS                | no -> allocate more
    BEQ.B       NEXTMASTER_ERR                  | allocation failed? -> return nil
NEXTMASTER_CONT:
    MOVE.L      (A1),0x8(A6)                    | unlink: zone.hFstFree = next free MP
    MOVE.L      A1,D0                           | D0 = A1 (NE = success)
NEXTMASTER_ERR:
    MOVEM.L     (SP)+,D0/A0                     | restore D0 and A0
    RTS                                         | return from NEXTMASTER_ERR
HMAKEMOREMASTERS:
    MOVEM.L     D0-D1/A0,-(SP)                  | save registers
    MOVE.W      0x14(A6),D0                     | D0 = zone.moreMast count
    EXT.L       D0                              | sign-extend to long
    BGT.B       HMAKEMOREMASTERS_CONT           | valid count? (> 0)
    MOVEQ.L     #0x20,D0                        | default to 32 master pointers
HMAKEMOREMASTERS_CONT:
    MOVE.L      D0,D1                           | D1 = number of master pointers
    ASL.L       #0x2,D0                         | D0 = count * 4 bytes
    BSR.B       MAKEPTRSPC                      | find/make space for ptr block
    SUBA.L      A1,A1                           | A1 = nil (non-relocatable)
    BSR.W       ALLOCBK                         | allocate block for master pointers
    BEQ.B       HMAKEMOREMASTERS_ERR            | failed? -> return
    MOVEA.L     A0,A1                           | A1 = first master pointer in block
HMAKEMOREMASTERS_CONT_2:
    BSR.B       RELEASEMP                       | link MP into free list
    ADDQ.L      #0x4,A1                         | advance to next MP slot
    SUBQ.W      #0x1,D1                         | count down
    BNE.B       HMAKEMOREMASTERS_CONT_2         | more to do
    SUBQ.L      #0x4,A1                         | back up to last valid MP
HMAKEMOREMASTERS_ERR:
    MOVE.L      A1,D0                           | D0 = A1 (NE = success)
    MOVEM.L     (SP)+,D0-D1/A0                  | restore registers
    RTS                                         | return from HMAKEMOREMASTERS_ERR
RELEASEMP:
    MOVE.L      0x8(A6),(A1)                    | link: MP->next = zone.hFstFree
    MOVE.L      A1,0x8(A6)                      | zone.hFstFree = this MP
    RTS                                         | return from RELEASEMP
MAKEPTRSPC:
    MOVEM.L     D0-D4/A0-A1/A3-A4,-(SP)         | save working registers
    BSR.W       ACTUALS                         | round D0 to actual block size
    MOVEA.L     A6,A4                           | A4 = current zone
    CMPA.L      (ApplZone).W,A6                 | is this the application zone?
    SEQ.B       D3                              | D3 = FF if app zone, 00 otherwise
MAKEPTRSPC_RETRY:
    LEA.L       0x34(A4),A0                     | A0 = zone.heapData (first block)
    MOVEA.L     (A6),A3                         | A3 = zone.bkLim (zone end)
    MOVEA.L     A0,A2                           | A2 = scan start position
    MOVEQ.L     #0x0,D2                         | D2 = 0: accumulated free+purgeable
MAKEPTRSPC_SCAN_LOOP:
    MOVE.L      (A0),D1                         | D1 = block header
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit size
    TST.B       (A0)                            | is block free?
    BEQ.B       MAKEPTRSPC_OK                   | yes -> accumulate
    BPL.B       MAKEPTRSPC_OK_3                 | non-reloc -> barrier
    MOVEA.L     0x4(A0),A1                      | get relHandle
    ADDA.L      A6,A1                           | A1 = absolute master pointer
    TST.B       (A1)                            | check MP flags: locked?
    BMI.B       MAKEPTRSPC_OK_3                 | yes -> barrier
MAKEPTRSPC_OK:
    ADD.L       D1,D2                           | D2 += block size
    ADDA.L      D1,A0                           | advance past block
    CMP.L       D0,D2                           | enough space accumulated?
    BCS.B       MAKEPTRSPC_NO_3                 | no -> keep scanning
    BSR.B       MAKEPTRSPC_CONT_2               | purge/compact this region
    MOVE.L      A2,D2                           | D2 = result (A2 = free block)
    BNE.B       MAKEPTRSPC_EXIT                 | success? -> return
    LEA.L       0x34(A4),A2                     | A2 = zone.heapData (retry)
MAKEPTRSPC_NO_2:
    MOVE.L      (A2),D1                         | D1 = block size
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    ADDA.L      D1,A2                           | advance past block
    TST.B       (A2)                            | scan past relocatable+unlocked
    BPL.B       MAKEPTRSPC_PAST_FREED           | non-reloc/free -> check position
    MOVEA.L     0x4(A2),A1                      | get relHandle
    ADDA.L      A6,A1                           | A1 = absolute master pointer
    TST.B       (A1)                            | locked?
    BPL.B       MAKEPTRSPC_CONTINUE             | no -> keep scanning
MAKEPTRSPC_PAST_FREED:
    CMPA.L      A0,A2                           | past our freed region?
    BHI.B       MAKEPTRSPC_OK_2                 | yes -> resume from here
MAKEPTRSPC_CONTINUE:
    CMPA.L      A3,A2                           | past zone end?
    BCS.B       MAKEPTRSPC_NO_2                 | no -> keep scanning
MAKEPTRSPC_OK_2:
    MOVEA.L     A2,A0                           | A0 = resume position
    SUBA.L      A2,A2                           | A2 = nil (reset scan)
MAKEPTRSPC_EXIT:
    MOVE.L      A2,D2                           | D2 = A2 (NE = success)
    BNE.B       MAKEPTRSPC_EXIT_2               | success? -> return
    BRA.B       MAKEPTRSPC_CONT                 | -> continue scanning
MAKEPTRSPC_OK_3:
    ADDA.L      D1,A0                           | advance past non-free block
MAKEPTRSPC_CONT:
    MOVEA.L     A0,A2                           | A2 = new scan start
    MOVEQ.L     #0x0,D2                         | D2 = 0: reset accumulator
MAKEPTRSPC_NO_3:
    CMPA.L      A3,A0                           | past zone end?
    BCS.B       MAKEPTRSPC_SCAN_LOOP            | no -> continue scanning
    ADDQ.B      #0x1,D3                         | increment retry counter
    BNE.B       MAKEPTRSPC_RETRY_2              | first retry? -> try expanding heap
    BSR.W       ZONEADJUSTEND_CONT              | expand application heap
    BRA.B       MAKEPTRSPC_RETRY                | -> retry scan
| ----------------------------------------------------------
|
| MAKEPTRSPC_RETRY_2
|
MAKEPTRSPC_RETRY_2:
    SUBA.L      A2,A2                           | A2 = nil (not found)
MAKEPTRSPC_EXIT_2:
    MOVEM.L     (SP)+,D0-D4/A0-A1/A3-A4         | restore registers
    RTS                                         | return from MAKEPTRSPC_EXIT_2
| ----------------------------------------------------------
|
| MAKEPTRSPC_CONT_2
|
| Called during boot (7,495 times in 30s trace).
MAKEPTRSPC_CONT_2:
    MOVEM.L     D0-D3/A0-A1/A3,-(SP)            | save registers
    MOVE.L      D0,D1                           | D1 = bytes needed
    MOVEA.L     A2,A3                           | A3 = scan start
    MOVEQ.L     #0x0,D3                         | D3 = 0: bytes freed so far
MAKEPTRSPC_CONT_3:
    CMP.L       D1,D3                           | freed enough?
    BCC.B       MAKEPTRSPC_OK_5                 | yes -> finalize
    CMPA.L      (A6),A3                         | past zone end?
    BCC.B       MAKEPTRSPC_OK_5                 | yes -> finalize
    TST.B       (A3)                            | is block free?
    BEQ.B       MAKEPTRSPC_OK_4                 | yes -> count it
    BPL.B       MAKEPTRSPC_OK_5                 | non-reloc -> stop (barrier)
    MOVEA.L     0x4(A3),A1                      | get relHandle
    ADDA.L      A6,A1                           | A1 = absolute master pointer
    MOVE.B      (A1),D2                         | D2 = MP flags byte
    BMI.B       MAKEPTRSPC_OK_5                 | locked? -> stop (barrier)
    BSR.B       MAKEPTRSPC_CONT_4               | try relocating block out
    BEQ.B       MAKEPTRSPC_OK_4                 | moved successfully? -> count as free
    BTST        #0x6,D2                         | is block purgeable?
    BEQ.B       MAKEPTRSPC_OK_5                 | no -> stop (can't free this block)
    MOVEA.L     (A1),A0                         | A0 = block data via master pointer
    SUBQ.L      #0x8,A0                         | back up to block header
    BSR.W       EH_CONT_2                       | purge block (free + notify)
MAKEPTRSPC_OK_4:
    MOVEA.L     A3,A0                           | A0 = current scan position
    MOVE.L      (A0),D0                         | D0 = block size
    CMPA.L      0x30(A6),A0                     | is this the allocPtr?
    BNE.B       MAKEPTRSPC_SKIP                 | no -> skip
    CLR.L       0x30(A6)                        | clear allocPtr (will be rebuilt)
MAKEPTRSPC_SKIP:
    ADD.L       D0,D3                           | D3 += block size freed
    ADDA.L      D0,A3                           | A3 = advance past block
    BRA.B       MAKEPTRSPC_CONT_3               | -> continue scanning
| ----------------------------------------------------------
|
| MAKEPTRSPC_OK_5
|
| Called during boot (7,495 times in 30s trace).
MAKEPTRSPC_OK_5:
    AND.L       (Lo3Bytes).W,D3                 | mask D3 to 24-bit
    BEQ.B       MAKEPTRSPC_SKIP_2               | nothing freed? -> skip write
    MOVE.L      D3,(A2)                         | write coalesced free block
MAKEPTRSPC_SKIP_2:
    CMP.L       D1,D3                           | freed enough?
    BCC.B       MAKEPTRSPC_ERR                  | no -> A2 = nil (failed)
    SUBA.L      A2,A2                           | A2 = nil
MAKEPTRSPC_ERR:
    CLR.L       0x30(A6)                        | clear allocPtr
    MOVEM.L     (SP)+,D0-D3/A0-A1/A3            | restore registers
    RTS                                         | return from MAKEPTRSPC_ERR
| ----------------------------------------------------------
|
| MAKEPTRSPC_CONT_4
|
| Called during boot (1,336 times in 30s trace).
MAKEPTRSPC_CONT_4:
    MOVE.L      A0,-(SP)                        | save A0
    MOVE.L      D3,D0                           | D0 = bytes freed so far
    BEQ.B       MAKEPTRSPC_SKIP_3               | nothing freed yet? -> skip
    MOVE.L      D3,(A2)                         | mark freed region as non-reloc temp
    ORI.L       #0x40000000,(A2)                | tag = non-relocatable ($40000000)
    MOVE.L      A6,0x4(A2)                      | relHandle = zone base
    NEG.L       D0                              | negate for AdjustFree (subtract)
    BSR.W       ADJUSTFREE                      | subtract from zcbFree
MAKEPTRSPC_SKIP_3:
    MOVEA.L     (A1),A0                         | A0 = block data (via master ptr)
    BSR.W       GETSIZE                         | D0 = logical size of block
    BSR.B       MAKEPTRSPC_CONT_5               | allocate new block, move data
    MOVEA.L     D0,A0                           | A0 = D0 (result for caller)
    MOVE.L      D3,D0                           | D0 = bytes freed
    BEQ.B       MAKEPTRSPC_SKIP_4               | nothing freed? -> skip
    MOVE.L      D3,(A2)                         | restore free block at old region
    BSR.W       ADJUSTFREE                      | add freed space back to zcbFree
MAKEPTRSPC_SKIP_4:
    MOVE.L      A0,D0                           | D0 = result (NE = success)
    MOVEA.L     (SP)+,A0                        | restore A0
    RTS                                         | return from MAKEPTRSPC_SKIP_4
| ----------------------------------------------------------
|
| MAKEPTRSPC_CONT_5
|
| Called during boot (1,340 times in 30s trace).
MAKEPTRSPC_CONT_5:
    MOVEM.L     D1-D2/A0-A2,-(SP)               | save registers
    MOVEA.L     A1,A2                           | A2 = master pointer
    MOVE.L      A1,(GZMoveHnd).W                | record handle being moved
    MOVE.B      (A2),D1                         | D1 = save MP flags
    SUBA.L      A1,A1                           | A1 = nil (non-reloc allocation)
    BSR.W       ALLOCBK                         | allocate new block
    BEQ.B       MAKEPTRSPC_ERR_3                | failed? -> return error
    TST.L       (A2)                            | block has data?
    BEQ.B       MAKEPTRSPC_NO_4                 | no -> just free old
    MOVEA.L     A0,A1                           | A1 = new block data
    MOVEA.L     (A2),A0                         | A0 = old block data
    BSR.W       GETSIZE                         | D0 = old block logical size
    BSR.W       ALLOCBK_CONT_6                  | copy old data to new block
    SUBQ.L      #0x8,A0                         | A0 = old block header
    SUBQ.L      #0x8,A1                         | A1 = new block header
    MOVEQ.L     #-0x10,D0                       | D0 = 0xF0: mask for tag+correction
    AND.B       (A0),D0                         | D0 = old block's tag+correction
    EOR.B       D0,(A0)                         | clear old header's tag+correction
    MOVEQ.L     #-0x10,D2                       | D2 = 0xF0: mask for new block
    AND.B       (A1),D2                         | D2 = new block's tag+correction
    EOR.B       D2,(A1)                         | clear new header's tag+correction
    OR.B        D0,(A1)                         | copy old tag+correction to new header
    OR.B        D2,(A0)                         | copy new tag+correction to old header
    ADDQ.L      #0x4,A0                         | A0 = old relHandle field
    ADDQ.L      #0x4,A1                         | A1 = new relHandle field
    MOVE.L      (A0),(A1)+                      | copy relHandle, A1 -> new data ptr
    MOVE.L      A1,(A2)                         | update master pointer to new block
    MOVE.B      D1,(A2)                         | restore MP flags
    MOVE.L      A6,(A0)+                        | old relHandle = zone base (non-reloc)
MAKEPTRSPC_NO_4:
    BSR.B       FREEBK                          | free old block
    MOVEQ.L     #0x0,D0                         | noErr
MAKEPTRSPC_ERR_2:
    CLR.L       (GZMoveHnd).W                   | clear GZMoveHnd
    MOVEM.L     (SP)+,D1-D2/A0-A2               | restore registers
    RTS                                         | return from MAKEPTRSPC_ERR_2
| ----------------------------------------------------------
|
| MAKEPTRSPC_ERR_3
|
MAKEPTRSPC_ERR_3:
    MOVE.B      D1,(A2)                         | restore MP flags
    MOVEQ.L     #-0x6C,D0                       | memFullErr (-108)
    BRA.B       MAKEPTRSPC_ERR_2                | -> return error
FREEBK:
    MOVEM.L     D0-D1/A0-A1,-(SP)               | save registers
    SUBQ.L      #0x8,A0                         | back up to block header
    MOVE.L      (A0),D0                         | D0 = block header (tag+size)
    MOVE.L      D0,D1                           | D1 = copy for tag extraction
    AND.L       (Lo3Bytes).W,D0                 | mask to physical size
    EOR.L       D0,D1                           | D1 = tag bits only
    BEQ.B       FREEBK_SKIP                     | tag = 0? -> already free, skip
    BPL.B       FREEBK_NORELOC                  | non-reloc? -> no master pointer
    MOVEA.L     0x4(A0),A1                      | get relHandle
    ADDA.L      A6,A1                           | A1 = absolute master pointer
    BSR.W       RELEASEMP                       | return MP to free list
FREEBK_NORELOC:
    BSR.W       MAKEBKF                         | convert to free block
    BSR.W       ADJUSTFREE                      | add freed space to zcbFree
FREEBK_SKIP:
    MOVEM.L     (SP)+,D0-D1/A0-A1               | restore registers
    RTS                                         | return from FREEBK_SKIP
STDGZ:
    MOVEA.L     (SP)+,A1                        | A1 = return address
    LEA.L       (GZRootHnd).W,A2                | A2 -> GZRootHnd, GZRootPtr, GZMoveHnd
    MOVEM.L     (A2),D3-D5                      | D3=GZRootHnd, D4=GZRootPtr, D5=GZMoveHnd
    TST.L       D5                              | GZMoveHnd set?
    BEQ.B       STDGZ_NO                        | no -> try reserve
    CMP.L       D3,D5                           | GZMoveHnd == GZRootHnd?
    BNE.B       STDGZ_NO_2                      | no -> try purgeable
STDGZ_NO:
    BTST        #0x3,0x16(A6)                   | grow-zone disabled? (flags bit 3)
    BNE.B       STDGZ_OK                        | yes -> try user grow-zone
    MOVE.L      (SP),D0                         | D0 = needed size from stack
    CLR.L       (A2)+                           | clear GZRootHnd
    CLR.L       (A2)+                           | clear GZRootPtr
    CLR.L       (A2)+                           | clear GZMoveHnd
    MOVE.L      (TheZone).W,-(SP)               | save TheZone
    MOVE.L      A6,(TheZone).W                  | set TheZone to this heap
    _ResrvMem                                   | try to reserve space
    MOVE.L      (SP)+,(TheZone).W               | restore TheZone
    MOVEM.L     D3-D5,-(A2)                     | restore GZ vars
    TST.L       D0                              | reservation failed?
    BMI.B       STDGZ_OK                        | yes -> try user grow-zone
    MOVE.L      (SP)+,(SP)                      | pop needed size, keep return addr
    JMP         (A1)                            | return (retry allocation)
| ----------------------------------------------------------
|
| STDGZ_NO_2
|
STDGZ_NO_2:
    BTST        #0x2,0x16(A6)                   | purge disabled? (flags bit 2)
    BNE.B       STDGZ_OK                        | yes -> try user grow-zone
STDGZ_NO_3:
    ADDQ.W      #0x4,SP                         | pop needed size (give up)
    JMP         (A1)                            | return (retry with less)
| ----------------------------------------------------------
|
| STDGZ_OK
|
STDGZ_OK:
    MOVE.L      0x10(A6),D2                     | D2 = user grow-zone proc
    BEQ.B       STDGZ_NO_3                      | no user proc -> give up
    MOVE.L      A1,-(SP)                        | push return address
    MOVE.L      D2,-(SP)                        | push user proc address
    RTS                                         | call user grow-zone proc via RTS
| Apple source module: BLOCK2
BLOCKMOVE:
    TST.L       D0                              | zero or negative count?
    BLE.B       BLOCKMOVE_EXIT                  | yes -> return noErr
    MOVE.L      A0,D2                           | D2 = src address
    AND.L       (Lo3Bytes).W,D2                 | mask to 24-bit
    MOVE.L      A1,D1                           | D1 = dst address
    AND.L       (Lo3Bytes).W,D1                 | mask to 24-bit
    SUB.L       D2,D1                           | D1 = dst - src
    BLT.B       BLOCKMOVE_CONT                  | dst < src? -> copy forward
    ADDA.L      D0,A0                           | adjust src to end (copy backward)
    ADDA.L      D0,A1                           | adjust dst to end (copy backward)
BLOCKMOVE_CONT:
    LSR.W       #0x1,D1                         | odd alignment?
    BCC.B       BLOCKMOVE_NO_3                  | no -> use word-aligned copy
    TST.L       D1                              | D1 sign: forward or backward?
    BPL.B       BLOCKMOVE_LOOP_2                | forward -> byte-copy backward loop
BLOCKMOVE_LOOP:
    SUBQ.L      #0x8,D0                         | 8 bytes left?
    BLE.B       BLOCKMOVE_NO                    | no -> copy remainder
    MOVE.B      (A0)+,(A1)+                     | copy byte 1 of 8
    MOVE.B      (A0)+,(A1)+                     | copy byte 2 of 8
    MOVE.B      (A0)+,(A1)+                     | copy byte 3 of 8
    MOVE.B      (A0)+,(A1)+                     | copy byte 4 of 8
    MOVE.B      (A0)+,(A1)+                     | copy byte 5 of 8
    MOVE.B      (A0)+,(A1)+                     | copy byte 6 of 8
    MOVE.B      (A0)+,(A1)+                     | copy byte 7 of 8
    MOVE.B      (A0)+,(A1)+                     | copy byte 8 of 8
    BRA.B       BLOCKMOVE_LOOP                  | -> continue 8-byte loop
| ----------------------------------------------------------
|
| BLOCKMOVE_NO
|
| Called during boot.
BLOCKMOVE_NO:
    NEG.W       D0                              | negate remainder (0..7)
    ADD.W       D0,D0                           | * 2 = jump table offset
    JMP         BLOCKMOVE_CONT_2(PC,D0.W)       | jump into unrolled copy tail
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_2
|
| Called during boot.
BLOCKMOVE_CONT_2:
    MOVE.B      (A0)+,(A1)+                     | copy byte 7 (if needed)
    MOVE.B      (A0)+,(A1)+                     | copy byte 6
    MOVE.B      (A0)+,(A1)+                     | copy byte 5
    MOVE.B      (A0)+,(A1)+                     | copy byte 4
    MOVE.B      (A0)+,(A1)+                     | copy byte 3
    MOVE.B      (A0)+,(A1)+                     | copy byte 2
    MOVE.B      (A0)+,(A1)+                     | copy byte 1
    MOVE.B      (A0)+,(A1)+                     | copy byte 0
BLOCKMOVE_EXIT:
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BLOCKMOVE_EXIT
| ----------------------------------------------------------
|
| BLOCKMOVE_LOOP_2
|
| Called during boot (3,452 times in 30s trace).
BLOCKMOVE_LOOP_2:
    SUBQ.L      #0x8,D0                         | 8 bytes left?
    BLE.B       BLOCKMOVE_NO_2                  | no -> copy remainder
    MOVE.B      -(A0),-(A1)                     | copy byte 8 of 8 (backward)
    MOVE.B      -(A0),-(A1)                     | copy byte 7
    MOVE.B      -(A0),-(A1)                     | copy byte 6
    MOVE.B      -(A0),-(A1)                     | copy byte 5
    MOVE.B      -(A0),-(A1)                     | copy byte 4
    MOVE.B      -(A0),-(A1)                     | copy byte 3
    MOVE.B      -(A0),-(A1)                     | copy byte 2
    MOVE.B      -(A0),-(A1)                     | copy byte 1
    BRA.B       BLOCKMOVE_LOOP_2                | -> continue backward loop
| ----------------------------------------------------------
|
| BLOCKMOVE_NO_2
|
| Called during boot (1,485 times in 30s trace).
BLOCKMOVE_NO_2:
    NEG.W       D0                              | negate remainder
    ADD.W       D0,D0                           | * 2 = jump table offset
    JMP         BLOCKMOVE_CONT_3(PC,D0.W)       | jump into unrolled backward tail
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_3
|
| Called during boot.
BLOCKMOVE_CONT_3:
    MOVE.B      -(A0),-(A1)                     | copy byte 7 (backward, if needed)
    MOVE.B      -(A0),-(A1)                     | copy byte 6
    MOVE.B      -(A0),-(A1)                     | copy byte 5
    MOVE.B      -(A0),-(A1)                     | copy byte 4
    MOVE.B      -(A0),-(A1)                     | copy byte 3
    MOVE.B      -(A0),-(A1)                     | copy byte 2
    MOVE.B      -(A0),-(A1)                     | copy byte 1
    MOVE.B      -(A0),-(A1)                     | copy byte 0
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BLOCKMOVE_CONT_3
| ----------------------------------------------------------
|
| BLOCKMOVE_NO_3
|
| Called during boot (3,821 times in 30s trace).
BLOCKMOVE_NO_3:
    MOVE.W      A0,D2                           | D2 = src low word (for alignment)
    TST.L       D1                              | D1 sign: forward or backward?
    BPL.W       BLOCKMOVE_CONT_69               | backward -> word-aligned backward
    LSR.W       #0x1,D2                         | src odd?
    BCC.B       BLOCKMOVE_FWD_ALIGNED           | no -> already word-aligned
    MOVE.B      (A0)+,(A1)+                     | copy 1 byte to align
    SUBQ.L      #0x1,D0                         | decrement count
BLOCKMOVE_FWD_ALIGNED:
    SUBI.L      #0x20,D0                        | subtract 32 from count
    BMI.B       BLOCKMOVE_CONT_4                | < 32 bytes? -> small copy
    CMPI.L      #0xA0,D0                        | >= 192 bytes? -> use MOVEM
    BLT.B       BLOCKMOVE_LOOP_4                | no -> 32-byte loop
    MOVEM.L     D3-D7/A2-A6,-(SP)               | save registers for MOVEM copy
    SUBI.L      #0x30,D0                        | adjust count for 48-byte chunks
    ADDA.W      #0x30,A1                        | pre-advance dst for predecrement
BLOCKMOVE_LOOP_3:
    MOVEM.L     (A0)+,D1-D7/A2-A6               | load 48 bytes (12 longs) from src
    MOVEM.L     D1-D7/A2-A6,-(A1)               | store 48 bytes to dst (predecrement)
    ADDA.W      #0x60,A1                        | re-advance dst past written data
    SUBI.L      #0x30,D0                        | subtract 48 from count
    BGT.B       BLOCKMOVE_LOOP_3                | > 0? -> continue MOVEM loop
    SUBA.W      #0x30,A1                        | undo dst pre-advance
    ADDI.W      #0x30,D0                        | adjust count back
    MOVEM.L     (SP)+,D3-D7/A2-A6               | restore registers
BLOCKMOVE_LOOP_4:
    MOVE.L      (A0)+,(A1)+                     | copy long 1 of 8
    MOVE.L      (A0)+,(A1)+                     | copy long 2 of 8
    MOVE.L      (A0)+,(A1)+                     | copy long 3 of 8
    MOVE.L      (A0)+,(A1)+                     | copy long 4 of 8
    MOVE.L      (A0)+,(A1)+                     | copy long 5 of 8
    MOVE.L      (A0)+,(A1)+                     | copy long 6 of 8
    MOVE.L      (A0)+,(A1)+                     | copy long 7 of 8
    MOVE.L      (A0)+,(A1)+                     | copy long 8 of 8
    SUBI.W      #0x20,D0                        | subtract 32 from count
    BGE.B       BLOCKMOVE_LOOP_4                | >= 0? -> continue loop
BLOCKMOVE_CONT_4:
    ADD.W       D0,D0                           | D0 * 2 = jump table offset
    JMP         BCPYF_WD8(PC,D0.W)              | jump into unrolled long-copy tail
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_5
|
| Called during boot.
BLOCKMOVE_CONT_5:
    MOVE.L      (A0)+,(A1)+                     | copy long 7
BLOCKMOVE_CONT_6:
    MOVE.L      (A0)+,(A1)+                     | copy long 6
BLOCKMOVE_CONT_7:
    MOVE.L      (A0)+,(A1)+                     | copy long 5
BLOCKMOVE_CONT_8:
    MOVE.L      (A0)+,(A1)+                     | copy long 4
BLOCKMOVE_CONT_9:
    MOVE.L      (A0)+,(A1)+                     | copy long 3
BLOCKMOVE_CONT_10:
    MOVE.L      (A0)+,(A1)+                     | copy long 2
BLOCKMOVE_CONT_11:
    MOVE.L      (A0)+,(A1)+                     | copy long 1
BCPYF_RTS:
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BLOCKMOVE_CONT_11
BCPYF_T0_0:
    BRA.B       BCPYF_RTS                       | -> 0 longs remaining
BCPYF_T0_3:
    BRA.B       BLOCKMOVE_CONT_61               | -> 0 longs + 3 bytes
BCPYF_T0_2:
    BRA.B       BLOCKMOVE_CONT_52               | -> 0 longs + 2 bytes
BCPYF_T0_1:
    BRA.B       BLOCKMOVE_CONT_60               | -> 0 longs + 1 byte
BCPYF_T7_0:
    BRA.B       BLOCKMOVE_CONT_11               | -> 7 longs remaining
BCPYF_T7_3:
    BRA.B       BLOCKMOVE_CONT_68               | -> 7 longs + 3 bytes
BCPYF_T7_2:
    BRA.B       BLOCKMOVE_CONT_51               | -> 7 longs + 2 bytes
BCPYF_T7_1:
    BRA.B       BLOCKMOVE_CONT_59               | -> 7 longs + 1 byte
BCPYF_T6_0:
    BRA.B       BLOCKMOVE_CONT_10               | -> 6 longs remaining
BCPYF_T6_3:
    BRA.B       BLOCKMOVE_CONT_67               | -> 6 longs + 3 bytes
BCPYF_T6_2:
    BRA.B       BLOCKMOVE_CONT_50               | -> 6 longs + 2 bytes
BCPYF_T6_1:
    BRA.B       BLOCKMOVE_CONT_58               | -> 6 longs + 1 byte
BCPYF_T5_0:
    BRA.B       BLOCKMOVE_CONT_9                | -> 5 longs remaining
BCPYF_T5_3:
    BRA.B       BLOCKMOVE_CONT_66               | -> 5 longs + 3 bytes
BCPYF_T5_2:
    BRA.B       BLOCKMOVE_CONT_49               | -> 5 longs + 2 bytes
BCPYF_T5_1:
    BRA.B       BLOCKMOVE_CONT_57               | -> 5 longs + 1 byte
BCPYF_T4_0:
    BRA.B       BLOCKMOVE_CONT_8                | -> 4 longs remaining
BCPYF_T4_3:
    BRA.B       BLOCKMOVE_CONT_65               | -> 4 longs + 3 bytes
BCPYF_T4_2:
    BRA.B       BLOCKMOVE_CONT_48               | -> 4 longs + 2 bytes
BCPYF_T4_1:
    BRA.B       BLOCKMOVE_CONT_56               | -> 4 longs + 1 byte
BCPYF_T3_0:
    BRA.B       BLOCKMOVE_CONT_7                | -> 3 longs remaining
BCPYF_T3_3:
    BRA.B       BLOCKMOVE_CONT_64               | -> 3 longs + 3 bytes
BCPYF_T3_2:
    BRA.B       BLOCKMOVE_CONT_47               | -> 3 longs + 2 bytes
BCPYF_T3_1:
    BRA.B       BLOCKMOVE_CONT_55               | -> 3 longs + 1 byte
BCPYF_T2_0:
    BRA.B       BLOCKMOVE_CONT_6                | -> 2 longs remaining
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_38
|
BLOCKMOVE_CONT_38:
    BRA.B       BLOCKMOVE_CONT_63               | -> 2 longs + 3 bytes
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_39
|
| Called during boot.
BLOCKMOVE_CONT_39:
    BRA.B       BLOCKMOVE_CONT_46               | -> 2 longs + 2 bytes
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_40
|
BLOCKMOVE_CONT_40:
    BRA.B       BLOCKMOVE_CONT_54               | -> 2 longs + 1 byte
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_41
|
| Called during boot.
BLOCKMOVE_CONT_41:
    BRA.B       BLOCKMOVE_CONT_5                | -> 1 long remaining
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_42
|
BLOCKMOVE_CONT_42:
    BRA.B       BLOCKMOVE_CONT_62               | -> 1 long + 3 bytes
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_43
|
| Called during boot.
BLOCKMOVE_CONT_43:
    BRA.B       BCPYF_WD8                       | -> 1 long + 2 bytes
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_44
|
BLOCKMOVE_CONT_44:
    BRA.B       BCPYF_WDB8                      | -> 1 long + 1 byte
BCPYF_WD8:
    MOVE.L      (A0)+,(A1)+                     | copy long 8
BLOCKMOVE_CONT_46:
    MOVE.L      (A0)+,(A1)+                     | copy long 7
BLOCKMOVE_CONT_47:
    MOVE.L      (A0)+,(A1)+                     | copy long 6
BLOCKMOVE_CONT_48:
    MOVE.L      (A0)+,(A1)+                     | copy long 5
BLOCKMOVE_CONT_49:
    MOVE.L      (A0)+,(A1)+                     | copy long 4
BLOCKMOVE_CONT_50:
    MOVE.L      (A0)+,(A1)+                     | copy long 3
BLOCKMOVE_CONT_51:
    MOVE.L      (A0)+,(A1)+                     | copy long 2
BLOCKMOVE_CONT_52:
    MOVE.W      (A0)+,(A1)+                     | copy word tail
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BLOCKMOVE_CONT_52
BCPYF_WDB8:
    MOVE.L      (A0)+,(A1)+                     | copy long 8
BLOCKMOVE_CONT_54:
    MOVE.L      (A0)+,(A1)+                     | copy long 7
BLOCKMOVE_CONT_55:
    MOVE.L      (A0)+,(A1)+                     | copy long 6
BLOCKMOVE_CONT_56:
    MOVE.L      (A0)+,(A1)+                     | copy long 5
BLOCKMOVE_CONT_57:
    MOVE.L      (A0)+,(A1)+                     | copy long 4
BLOCKMOVE_CONT_58:
    MOVE.L      (A0)+,(A1)+                     | copy long 3
BLOCKMOVE_CONT_59:
    MOVE.L      (A0)+,(A1)+                     | copy long 2
BLOCKMOVE_CONT_60:
    MOVE.W      (A0)+,(A1)+                     | copy word tail
BLOCKMOVE_CONT_61:
    MOVE.B      (A0)+,(A1)+                     | copy byte tail
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BLOCKMOVE_CONT_61
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_62
|
BLOCKMOVE_CONT_62:
    MOVE.L      (A0)+,(A1)+                     | copy long 8
BLOCKMOVE_CONT_63:
    MOVE.L      (A0)+,(A1)+                     | copy long 7
BLOCKMOVE_CONT_64:
    MOVE.L      (A0)+,(A1)+                     | copy long 6
BLOCKMOVE_CONT_65:
    MOVE.L      (A0)+,(A1)+                     | copy long 5
BLOCKMOVE_CONT_66:
    MOVE.L      (A0)+,(A1)+                     | copy long 4
BLOCKMOVE_CONT_67:
    MOVE.L      (A0)+,(A1)+                     | copy long 3
BLOCKMOVE_CONT_68:
    MOVE.L      (A0)+,(A1)+                     | copy long 2
    MOVE.B      (A0)+,(A1)+                     | copy byte tail
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BLOCKMOVE_CONT_68
| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_69
|
| Called during boot (3,684 times in 30s trace).
BLOCKMOVE_CONT_69:
    LSR.W       #0x1,D2                         | src odd? (low bit of A0)
    BCC.B       BCPYB_ALIGNED                   | no -> already aligned
    MOVE.B      -(A0),-(A1)                     | copy 1 byte to align
    SUBQ.L      #0x1,D0                         | decrement count
BCPYB_ALIGNED:
    SUBI.L      #0x20,D0                        | subtract 32 from count
    BMI.B       BLOCKMOVE_CONT_70               | < 32 bytes? -> small copy
    CMPI.L      #0xA0,D0                        | >= 192 bytes? -> use MOVEM
    BLT.B       BLOCKMOVE_LOOP_6                | no -> 32-byte loop
    MOVEM.L     D3-D7/A2-A6,-(SP)               | save registers for MOVEM copy
    SUBI.L      #0x30,D0                        | adjust count for 48-byte chunks
    SUBA.W      #0x30,A0                        | pre-back-off src for postincrement
BLOCKMOVE_LOOP_5:
    MOVEM.L     (A0)+,D1-D7/A2-A6               | load 48 bytes (12 longs) from src
    MOVEM.L     D1-D7/A2-A6,-(A1)               | store 48 bytes to dst (predecrement)
    SUBA.W      #0x60,A0                        | re-back-off src past read data
    SUBI.L      #0x30,D0                        | subtract 48 from count
    BGT.B       BLOCKMOVE_LOOP_5                | > 0? -> continue MOVEM loop
    ADDA.W      #0x30,A0                        | undo src pre-back-off
    ADDI.W      #0x30,D0                        | adjust count back
    MOVEM.L     (SP)+,D3-D7/A2-A6               | restore registers
BLOCKMOVE_LOOP_6:
    MOVE.L      -(A0),-(A1)                     | copy long 1 of 8 (backward)
    MOVE.L      -(A0),-(A1)                     | copy long 2 of 8
    MOVE.L      -(A0),-(A1)                     | copy long 3 of 8
    MOVE.L      -(A0),-(A1)                     | copy long 4 of 8
    MOVE.L      -(A0),-(A1)                     | copy long 5 of 8
    MOVE.L      -(A0),-(A1)                     | copy long 6 of 8
    MOVE.L      -(A0),-(A1)                     | copy long 7 of 8
    MOVE.L      -(A0),-(A1)                     | copy long 8 of 8
    SUBI.W      #0x20,D0                        | subtract 32 from count
    BGE.B       BLOCKMOVE_LOOP_6                | >= 0? -> continue loop
BLOCKMOVE_CONT_70:
    ADD.W       D0,D0                           | D0 * 2 = jump table offset
    JMP         BCPY_WD8(PC,D0.W)               | jump into unrolled backward tail
| ----------------------------------------------------------
|
| BLOCKMOVE_LOOP_7
|
| Called during boot.
BLOCKMOVE_LOOP_7:
    MOVE.L      -(A0),-(A1)                     | copy long 7 (backward)
BLOCKMOVE_LOOP_8:
    MOVE.L      -(A0),-(A1)                     | copy long 6
BLOCKMOVE_LOOP_9:
    MOVE.L      -(A0),-(A1)                     | copy long 5
BLOCKMOVE_CONT_71:
    MOVE.L      -(A0),-(A1)                     | copy long 4
BLOCKMOVE_CONT_72:
    MOVE.L      -(A0),-(A1)                     | copy long 3
BLOCKMOVE_CONT_73:
    MOVE.L      -(A0),-(A1)                     | copy long 2
BLOCKMOVE_CONT_74:
    MOVE.L      -(A0),-(A1)                     | copy long 1
BCPY_DISPATCH_0_RTS:
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BLOCKMOVE_CONT_74
BCPY_DISPATCH_0:
    BRA.B       BCPY_DISPATCH_0_RTS             | -> 0 longs remaining
BCPY_DISPATCH_3:
    BRA.B       BCPY_WDB_TAIL                   | -> 0 longs + 3 bytes
BCPY_DISPATCH_2:
    BRA.B       BCPY_WD_TAIL                    | -> 0 longs + 2 bytes
BCPY_DISPATCH_1:
    BRA.B       BCPY_WDB_WORD                   | -> 0 longs + 1 byte
BCPY_DISPATCH_4:
    BRA.B       BLOCKMOVE_CONT_74               | -> 1 long remaining
BCPY_DISPATCH_7:
    BRA.B       BCPY_BT1                        | -> 1 long + 3 bytes
BCPY_DISPATCH_6:
    BRA.B       BCPY_WD1                        | -> 1 long + 2 bytes
BCPY_DISPATCH_5:
    BRA.B       BCPY_WDB1                       | -> 1 long + 1 byte
BCPY_DISPATCH_8:
    BRA.B       BLOCKMOVE_CONT_73               | -> 2 longs remaining
BCPY_DISPATCH_11:
    BRA.B       BCPY_BT2                        | -> 2 longs + 3 bytes
BCPY_DISPATCH_10:
    BRA.B       BCPY_WD2                        | -> 2 longs + 2 bytes
BCPY_DISPATCH_9:
    BRA.B       BCPY_WDB2                       | -> 2 longs + 1 byte
BCPY_DISPATCH_12:
    BRA.B       BLOCKMOVE_CONT_72               | -> 3 longs remaining
BCPY_DISPATCH_15:
    BRA.B       BCPY_BT3                        | -> 3 longs + 3 bytes
BCPY_DISPATCH_14:
    BRA.B       BCPY_WD3                        | -> 3 longs + 2 bytes
BCPY_DISPATCH_13:
    BRA.B       BCPY_WDB3                       | -> 3 longs + 1 byte
BCPY_DISPATCH_16:
    BRA.B       BLOCKMOVE_CONT_71               | -> 4 longs remaining
BCPY_DISPATCH_19:
    BRA.B       BCPY_BT4                        | -> 4 longs + 3 bytes
BCPY_DISPATCH_18:
    BRA.B       BCPY_WD4                        | -> 4 longs + 2 bytes
BCPY_DISPATCH_17:
    BRA.B       BCPY_WDB4                       | -> 4 longs + 1 byte
BCPY_DISPATCH_20:
    BRA.B       BLOCKMOVE_LOOP_9                | -> 5 longs remaining
BCPY_DISPATCH_23:
    BRA.B       BCPY_BT5                        | -> 5 longs + 3 bytes
BCPY_DISPATCH_22:
    BRA.B       BCPY_WD5                        | -> 5 longs + 2 bytes
BCPY_DISPATCH_21:
    BRA.B       BCPY_WDB5                       | -> 5 longs + 1 byte
BCPY_DISPATCH_24:
    BRA.B       BLOCKMOVE_LOOP_8                | -> 6 longs remaining
| Entry: copy 2 longs + 1 byte (9 bytes total)
BCPY_ENT_BT9:
    BRA.B       BCPY_BT6                        | jump into unrolled copy loop
| Entry: copy 2 longs + 1 word (10 bytes total)
BCPY_ENT_WD10:
    BRA.B       BCPY_WD6                        | jump into unrolled copy loop
| Entry: copy 2 longs + 1 word + 1 byte (11 bytes total)
BCPY_ENT_WDB11:
    BRA.B       BCPY_WDB6                       | jump into unrolled copy loop
| Entry: copy 5 longs + 1 word (22 bytes total)
BCPY_ENT_WD22:
    BRA.B       BLOCKMOVE_LOOP_7                | jump into unrolled copy loop
| Entry: copy 1 long + 1 byte (5 bytes total)
BCPY_ENT_BT5:
    BRA.B       BCPY_BT7                        | jump into unrolled copy loop
| Entry: copy 1 long + 1 word (6 bytes total)
BCPY_ENT_WD6:
    BRA.B       BCPY_WD8                        | -> 7 longs + 2 bytes
| Entry: copy 1 long + 1 word + 1 byte (7 bytes total)
BCPY_ENT_WDB7:
    BRA.B       BCPY_WDB8                       | -> 7 longs + 1 byte
BCPY_WD8:
    MOVE.L      -(A0),-(A1)                     | copy long 8 (backward)
BCPY_WD6:
    MOVE.L      -(A0),-(A1)                     | copy long 7
BCPY_WD5:
    MOVE.L      -(A0),-(A1)                     | copy long 6
BCPY_WD4:
    MOVE.L      -(A0),-(A1)                     | copy long 5
BCPY_WD3:
    MOVE.L      -(A0),-(A1)                     | copy long 4
BCPY_WD2:
    MOVE.L      -(A0),-(A1)                     | copy long 3
BCPY_WD1:
    MOVE.L      -(A0),-(A1)                     | copy long 2
BCPY_WD_TAIL:
    MOVE.W      -(A0),-(A1)                     | copy word tail
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BCPY_WD_TAIL
BCPY_WDB8:
    MOVE.L      -(A0),-(A1)                     | copy long 8 (backward)
BCPY_WDB6:
    MOVE.L      -(A0),-(A1)                     | copy long 7
BCPY_WDB5:
    MOVE.L      -(A0),-(A1)                     | copy long 6
BCPY_WDB4:
    MOVE.L      -(A0),-(A1)                     | copy long 5
BCPY_WDB3:
    MOVE.L      -(A0),-(A1)                     | copy long 4
BCPY_WDB2:
    MOVE.L      -(A0),-(A1)                     | copy long 3
BCPY_WDB1:
    MOVE.L      -(A0),-(A1)                     | copy long 2
BCPY_WDB_WORD:
    MOVE.W      -(A0),-(A1)                     | copy word
BCPY_WDB_TAIL:
    MOVE.B      -(A0),-(A1)                     | copy byte tail
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BCPY_WDB_TAIL
| ----------------------------------------------------------
| Variant C: copy N longwords + 1 byte, predecrement
BCPY_BT7:
    MOVE.L      -(A0),-(A1)                     | copy long 8 (backward)
BCPY_BT6:
    MOVE.L      -(A0),-(A1)                     | copy long 7
BCPY_BT5:
    MOVE.L      -(A0),-(A1)                     | copy long 6
BCPY_BT4:
    MOVE.L      -(A0),-(A1)                     | copy long 5
BCPY_BT3:
    MOVE.L      -(A0),-(A1)                     | copy long 4
BCPY_BT2:
    MOVE.L      -(A0),-(A1)                     | copy long 3
BCPY_BT1:
    MOVE.L      -(A0),-(A1)                     | copy long 2
    MOVE.B      -(A0),-(A1)                     | copy byte tail
    MOVEQ.L     #0x0,D0                         | noErr
    RTS                                         | return from BCPY_BT1
