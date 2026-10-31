| Memory Manager
|
| Manages heap zones for dynamic memory allocation. Provides
| NewHandle, NewPtr, DisposHandle, DisposPtr, SetHandleSize,
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
| Offset 44: sparePtr Ptr used internally
| Offset 48: allocPtr Ptr used internally
| Offset 52: heapData Integer first usable byte in zone
| END;
|
| Block header (24-bit mode, 8 bytes, Inside Macintosh: Memory, pp 2-22):
| Long 0: bits 7-6 = block type (00=free, 01=nonreloc, 10=reloc)
| bits 3-0 = size correction (unused bytes at end)
| bits 23-0 of long = zone address or relative handle
| Long 1: physical size of block (including header)
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

| === Memory Manager system-globals init data (28 bytes) @ $2AB0 ===
| Source table for InitMemMgr below. First 14 bytes (7 words) are
| copied to ($031A) Lo3Bytes .. ($0326) MMDefFlags by the
| MOVE (A0)+,(A1)+; DBRA loop. Remaining 14 bytes ($2ABE-$2ACB)
| do not appear to be consumed by any known code path.
InitMemMgr_Data:
        .long   0x00FFFFFF                      | $031A Lo3Bytes = mask low 3 bytes
        .long   0x00000400                      | $031E MinStack = 1024
        .long   0x00002000                      | $0322 DefltStack = 8192
        .short  0x0000                          | $0326 MMDefFlags = 0
| --- $2ABE-$2ACB: 14 bytes unreferenced by any known code path ---
        .short  0x0000, 0x0B00                  | $2ABE-$2AC1
        .short  0x0000, 0x4B00                  | $2AC2-$2AC5
        .short  0x0020, 0x0000                  | $2AC6-$2AC9
        .short  0x0000                          | $2ACA-$2ACB

| ----------------------------------------------------------
| InitMemMgr -- initialize memory-manager system globals.
| Copies 14 bytes of init constants from InitMemMgr_Data to
| (Lo3Bytes).w .. (MMDefFlags).w, then calls _InitZone and
| stores TheZone in SysZone. Called once at boot from vectors.s.
| ----------------------------------------------------------
InitMemMgr:
        LEA.L   InitMemMgr_Data(PC),A0          | A0 = &init constants
        LEA.L     (Lo3Bytes).w,A1               | A1 = &(Lo3Bytes).w (dest start)
        MOVEQ.L #0x6,D0                         | D0 = 6 (loop 7 words)

| Copy InitZone parameter words
COPY_ZONE_PARAMS:
        MOVE    (A0)+,(A1)+                     | copy one word of init data to lowmem
        DBRA    D0,COPY_ZONE_PARAMS             | loop 7 words
        _InitZone                               | build the system zone
        MOVE.L  (TheZone).w,(SysZone).w         | SysZone := newly-built zone
        RTS                                     | return from InitMemMgr

| ----------------------------------------------------------
| _SetApplBase ($A057): set the start of the application heap zone
| Pascal: PROCEDURE SetApplBase(startPtr: Ptr);
| Entry: A0 = startPtr. Exit: D0 = noErr (from InitApplZone)
| If startPtr - 12 lies beyond the system zone's end, the system zone
| is extended to end there (ZoneAdjustEnd); then InitApplZone builds
| the application zone just after the system zone and its 12-byte
| trailer block. (IM II calls the trap macro _SetAppBase.)
SetAppBase:
        MOVEM.L D3/A2-A6,-(SP)                  | save registers
        MOVE.L  (SysZone).w,A6                  | A6 = system zone
        SUBA.W  #0xC,A0                         | adjust requested base by header overhead
        CMPA.L  (A6),A0                         | below system zone end?
        BLS.B   SETAPPBASE_SKIP                 | branch if <= (unsigned)
        JSR     ZoneAdjustEnd(PC)               | push SysZone end up to new base
SETAPPBASE_SKIP:
        BSR.B   InitApplZone                    | initialize application zone
        MOVEM.L (SP)+,D3/A2-A6                  | restore registers
        RTS                                     | return from SetAppBase

| ----------------------------------------------------------
| _InitApplZone ($A02C): reinitialize the application heap zone
| Pascal: PROCEDURE InitApplZone;
| Exit: D0 = noErr; TheZone = ApplZone = the new zone
| Calls _RsrcZoneInit, sets ApplLimit := BufPtr - DefltStack
| (ToMaxLimit) and builds a new zone (_InitZone: 64 master pointers,
| no grow-zone procedure) from the end of SysZone + 12 (past its
| trailer block), 6K long but ending at most at min(SP - MinStack,
| ApplLimit). HeapEnd := the zone's end. Also called by SetApplBase.
InitApplZone:
        MOVE.L  A6,-(SP)                        | save A6 (will be reloaded)
        _RsrcZoneInit                           | reset Resource Manager zone state
        CLR.L   (ApplZone).w                    | clear ApplZone before re-init
        JSR     ToMaxLimit(PC)                  | compute D1 = max usable end, D2 = appLimit
        MOVE.L  D2,(ApplLimit).w                | ApplLimit := BufPtr - DefltStack
        MOVE.L  (SysZone).w,A6                  | A6 = system zone
        MOVE.L  (A6),A0                         | A0 = SysZone end
        LEA.L     12(A0),A0                     | skip its 12-byte trailer -> ApplZone start
        MOVE.L  A0,A1                           | A1 = initial ApplZone end (running)
        ADDA.W  #0x1800,A1                      | add 6K initial ApplZone size
        CMPA.L  D1,A1                           | fits within max heap end?
        BCS.B   SETAPPBASE_OK                   | yes -> use 6K size
        MOVE.L  D1,A1                           | no -> clamp to max
SETAPPBASE_OK:
        CLR.L   -(SP)                           | push pGrowZone = NIL
        MOVE    #0x40,-(SP)                     | push cMoreMasters = 64
        MOVE.L  A1,-(SP)                        | push limitPtr = A1
        MOVE.L  A0,-(SP)                        | push startPtr = A0
        MOVE.L  SP,A0                           | A0 -> InitZone parameter block
        _InitZone                               | build the application zone
        ADDA.W  #0xE,SP                         | pop 14 bytes of params
        MOVE.L  (TheZone).w,A6                  | A6 = newly-built ApplZone
        MOVE.L  (A6),(HeapEnd).w                | HeapEnd := zone.bkLim
        MOVE.L  A6,(ApplZone).w                 | ApplZone := A6
        MOVEQ.L #0x0,D0                         | return noErr
        MOVEA.L  (SP)+,FP                       | restore A6
        RTS                                     | return from InitApplZone

| ----------------------------------------------------------
| Memory Manager proper starts here -- InitZone etc.
|
| _InitZone ($A019): initialize a heap zone from parameter block
| A0 = ptr to: startPtr, limitPtr, cMoreMasters, pGrowZone
| Called during boot.
InitZone:
        MOVEM.L A2-A3/A6,-(SP)                  | save registers
        MOVE.L  A0,A1                           | A1 = parameter block pointer
        MOVE.L  (A1)+,A6                        | A6 = zone start address
        MOVE.L  A6,(TheZone).w                  | set current zone
        MOVE.L  A6,A0                           | A0 = zone header (for zeroing)
        MOVE.L  A6,A2                           | A2 = zone header (for field init)
| zero the zone header (13 longwords = 52 bytes)
        MOVEQ.L #0xC,D1                         | 13-1 = 12
INITZONE_LOOP:
        CLR.L   (A0)+                           | clear zone header longword
        DBRA    D1,INITZONE_LOOP                | loop 13 longwords
        MOVE.L  (A1)+,A3                        | A3 = limitPtr from params
        MOVEQ.L #0xC,D1                         | D1 = 12 (sentinel block size)
        SUBA.L  D1,A3                           | A3 = sentinel block address
        MOVE.L  D1,(A3)                         | set sentinel block size
        MOVE.L  A3,(A2)+                        | zone.bkLim = sentinel address
        MOVE.L  A0,(A2)+                        | zone.hFstFree = first free block
        ADDQ.W  #0x4,A2                         | skip zone.purgePtr
        SUBA.L  A0,A3                           | A3 = free space bytes
        MOVE.L  A3,D0                           | D0 = free space count
        MOVE.L  D0,(A2)+                        | zone.zcbFree = total free bytes
        MOVE    (A1)+,D1                        | D1 = cMoreMasters from params
        MOVE.L  (A1)+,(A2)+                     | zone.pGrowZone = grow zone proc
        MOVE    D1,(A2)+                        | zone.moreMast = master ptr count
        MOVE    (MMDefFlags).w,(A2)+            | zone.flags = default flags
        JSR     MakeBKF(PC)                     | build the big initial free block
        JSR     HMakeMoreMasters(PC)            | allocate first master pointer block
        MOVEQ.L #0x0,D0                         | return noErr
        MOVEM.L (SP)+,A2-A3/A6                  | restore registers
        RTS                                     | return from InitZone

| ----------------------------------------------------------
| _GetZone ($A11A): return the current heap zone
| Pascal: FUNCTION GetZone: THz;
| Exit: A0 = TheZone, D0 = noErr
GetZone:
        MOVE.L  (TheZone).w,A0                  | A0 = current zone pointer (return value)
        BRA.B   INITZONE_EXIT                   | -> return noErr

| ----------------------------------------------------------
| _SetZone ($A01B): set the current heap zone
| Pascal: PROCEDURE SetZone(hz: THz);
| Entry: A0 = hz. Exit: D0 = noErr (exit shared with GetZone)
SetZone:
        MOVE.L  A0,(TheZone).w                  | set current zone to A0
INITZONE_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return noErr (GetZone, SetZone)

| ----------------------------------------------------------
| _CompactMem ($A04C): compact the current heap zone
| Pascal: FUNCTION CompactMem(cbNeeded: Size): Size;
| Entry: D0.L = cbNeeded; trap bit 10 (,SYS) = use the system heap
| Exit:  D0.L = size of the largest free block afterwards (0 if none)
| Sets fNSelCompct (bit 4 of the zone flags byte) around the CompactHp
| call, forcing a real compaction (relocatable blocks are moved down);
| nothing is purged. (The Plus ROM shares this code with its _MaxBlock,
| $A061, which the 64K ROM does not have.)
CompactMem:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        JSR     Actuals(PC)                     | round D0 to actual block size
        LEA.L     22(A6),A1                     | A1 = ptr to zone.flags (offset 0x16)
        MOVE.B  (A1),D2                         | D2 = save original flags
        BSET    #0x4,(A1)                       | set fNSelCompct: force compaction
        JSR     CompactHp(PC)                   | compact the heap
        MOVE.B  D2,(A1)                         | restore original flags
        MOVE.L  D1,D0                           | D0 = largest free block size
        BEQ.B   PURGEMEM_ERR                    | no free space -> return D0 = 0
        SUBQ.L  #0x8,D0                         | subtract 8-byte header from usable size
        MOVE.L  A0,D1                           | block of cbNeeded bytes found?
        BEQ.B   PURGEMEM_ERR                    | no -> return with A0 = nil
        BRA.B   PURGEMEM_EXIT_2                 | yes -> A0 = its data address, return

| ----------------------------------------------------------
| PurgeMem -- _PurgeMem ($A04D).
| D0.L = needed bytes -> purges blocks until enough space available.
| Returns memFullErr (-108) in D0 if even after purging the request
| cannot be satisfied.
PurgeMem:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        JSR     Actuals(PC)                     | round D0 to actual block size
        JSR     PurgeHeap(PC)                   | purge blocks until D0 bytes available
PURGEMEM_CONT:
        MOVE.L  A0,D0                           | A0 = free block found?
        BNE.B   PURGEMEM_EXIT                   | yes -> return success
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
        BRA.B   PURGEMEM_ERR                    | -> return error
PURGEMEM_EXIT:
        MOVEQ.L #0x0,D0                         | return noErr
PURGEMEM_EXIT_2:
        ADDQ.L  #0x8,A0                         | skip block header (return user ptr)
PURGEMEM_ERR:
        JMP     MMEpilogue(PC)                  | restore regs and return

| ----------------------------------------------------------
| FreeMem -- _FreeMem ($A01C).
| -> D0.L = total free bytes in current zone (sum of all free blocks).
| Returns the zcbFree field directly without compacting; for the
| largest contiguous free block see MaxMem and CompactMem.
FreeMem:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        MOVE.L  12(A6),D0                       | D0 = zone.zcbFree (total free bytes)
        BRA.B   PURGEMEM_ERR                    | -> return via epilogue

| ----------------------------------------------------------
| ResrvMem -- _ResrvMem ($A040).
| D0.L = needed bytes -> reserves space (compacts/purges as needed).
| Adjusts the request to account for master pointer space if the
| zone has no master pointers yet (first allocation reserves room
| for both the request and a moreMast block).
ResrvMem:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        TST.L   8(A6)                           | zone.hFstFree = nil? (no master ptrs)
        BNE.B   RESRVMEM_SKIP                   | has master ptrs -> skip adjustment
        MOVE    20(A6),D2                       | D2 = zone.moreMast count
        EXT.L    D2                             | sign-extend to longword
        ASL.L   #0x2,D2                         | multiply by 4 (4 bytes per master ptr)
        ADDQ.L  #0x8,D2                         | + 8 for block header
        ADD.L   D2,D0                           | add master ptr space to request
RESRVMEM_SKIP:
        JSR     MakePtrSpc(PC)                  | compact/purge to make D0 bytes available
        MOVE.L  A2,A0                           | A0 = found free block
        BRA.B   PURGEMEM_CONT                   | join PurgeMem return path

| ----------------------------------------------------------
| _MaxMem ($A11D): compact and purge the current zone; return the
| largest free block and how far the application zone could grow
| Pascal: FUNCTION MaxMem(VAR grow: Size): Size;
| Entry: trap bit 10 (,SYS) = use the system heap
| Exit:  D0.L = size of the largest free block (0 if none);
|        A0 = grow: bytes the application zone could still grow
|        (0 if the current zone is not ApplZone)
| BKCompacts with an 8 MB request and D2 = 0 compacts the zone and
| purges all purgeable blocks, without growing the zone or calling
| the grow-zone function. grow = min(SP - MinStack, ApplLimit) - HeapEnd.
MaxMem:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        MOVE.L  #0x00800000,D0                  | D0 = 8 MB (max possible block size)
        MOVEQ.L #0x0,D2                         | D2 = 0: don't try grow zone
        JSR     BKCompacts(PC)                  | compact + purge; D1 = largest free block
        MOVE.L  D1,D0                           | D0 = largest free block
        BEQ.B   MAXMEM_CONT                     | no free space -> D0 = 0
        SUBQ.L  #0x8,D0                         | subtract 8-byte block header
MAXMEM_CONT:
        SUBA.L  A0,A0                           | grow = 0 unless TheZone is ApplZone
        MOVE.L  (ApplZone).w,A1                 | A1 = application zone
        CMPA.L  (TheZone).w,A1                  | current zone is the ApplZone?
        BNE.B   MAXMEM_SKIP                     | no -> skip grow calculation
        MOVE.L  (ApplLimit).w,D2                | D2 = application heap limit
        JSR     MaxLimit(PC)                    | D1 = min(SP - MinStack, ApplLimit)
        SUB.L   (HeapEnd).w,D1                  | D1 -= current heap end
        MOVE.L  D1,A0                           | A0 = growable bytes (returned)
MAXMEM_SKIP:
        JMP     MMEpilogue(PC)                  | return via MMEpilogue

| ----------------------------------------------------------
| SetGrowZone -- _SetGrowZone ($A04B).
| Pascal: procedure SetGrowZone(growZone: ProcPtr);
| Stores the caller's grow-zone proc address into the current
| zone header at offset 16. The zone calls this proc when out
| of memory to give the application a chance to free more space.
SetGrowZone:
        MOVE.L  (TheZone).w,A1                  | A1 = current zone header
        MOVE.L  A0,16(A1)                       | store grow-zone proc at zone offset 16
        BRA.B   SETAPPLLIMIT_EXIT               | -> return noErr

| ----------------------------------------------------------
| SetApplLimit -- _SetApplLimit ($A02D).
| Pascal: procedure SetApplLimit(zoneLimit: Ptr);
| Sets the upper limit beyond which the application zone may
| not grow. A0 = new limit address.
SetApplLimit:
        MOVE.L  A0,(ApplLimit).w                | store new app heap upper limit
SETAPPLLIMIT_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from SETAPPLLIMIT_EXIT

| ----------------------------------------------------------
| _NewPtr ($A11E): allocate a nonrelocatable block
| Pascal: FUNCTION NewPtr(logicalSize: Size): Ptr;
| Entry: D0.L = logicalSize; trap bit 9 ($A31E, ,CLEAR) = clear the
|        block, bit 10 ($A51E, ,SYS) = allocate in the system heap
| Exit:  A0 = pointer to the block (nil on failure), D0 = noErr or
|        memFullErr (-108)
| MakePtrSpc first makes room as low in the zone as possible (moving
| relocatable blocks out of the way, purging if needed), then AllocBK
| allocates the block (A1 = nil: no master pointer); PTRZONE_CONT
| clears it if requested.
NewPtr:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        SUBA.L  A1,A1                           | A1 = nil (non-relocatable block)
        JSR     MakePtrSpc(PC)                  | make room low in the zone
        JSR     AllocBK(PC)                     | allocate block of D0 bytes
        BEQ.B   NEWPTR_ERR_2                    | failed -> return memFullErr
        BSR.B   PTRZONE_CONT                    | optionally clear block (trap bit 9)
NEWPTR_EXIT:
        MOVEQ.L #0x0,D0                         | return noErr
NEWPTR_ERR:
        JMP     MMEpilogue(PC)                  | return via MMEpilogue
NEWPTR_ERR_2:
        MOVEQ.L #-0x6C,D0                       | D0 = memFullErr (-108)
        BRA.B   NEWPTR_ERR                      | return error via epilogue

| ----------------------------------------------------------
| _DisposPtr ($A01F): release a nonrelocatable block
| Pascal: PROCEDURE DisposPtr(p: Ptr);
| Entry: A0 = p. Exit: D0 = noErr (memWZErr if A0 is a free block)
| DISPOSPTR_CONT (FreeBk, return noErr) is shared with DisposHandle.
DisposPtr:
        JSR     MMPPrologue(PC)                 | set up zone, save regs
DISPOSPTR_CONT:
        JSR     FreeBk(PC)                      | free block (+ its master ptr if relocatable)
        BRA.B   NEWPTR_EXIT                     | return noErr via epilogue

| ----------------------------------------------------------
| GetPtrSize -- _GetPtrSize ($A021): A0 = ptr -> D0.L = size.
GetPtrSize:
        JSR     MMPPrologue(PC)                 | dereference ptr, validate zone
        JSR     GetSize(PC)                     | D0 = logical size
        BRA.B   NEWPTR_ERR                      | -> return via epilogue

| ----------------------------------------------------------
| SetPtrSize -- _SetPtrSize ($A020): A0 = ptr, D0.L = newSize.
SetPtrSize:
        JSR     MMPPrologue(PC)                 | dereference ptr, validate zone
        JSR     SetSize(PC)                     | resize block in place or relocate
        BRA.B   NEWPTR_ERR                      | -> return via epilogue

| ----------------------------------------------------------
| PtrZone -- _PtrZone ($A148): A0 = ptr -> A0 = zone.
PtrZone:
        JSR     MMPPrologue(PC)                 | dereference ptr, find its zone
        MOVE.L  A6,A0                           | A0 = zone
        BRA.B   NEWPTR_EXIT                     | -> return noErr

| ----------------------------------------------------------
| PTRZONE_CONT - clear a newly allocated block if trap bit 9 (,CLEAR)
| is set (used by NewPtr, NewHandle). D1 = trap word, A0 = block
| data, D0 = logical size (cleared in words, rounded up).
PTRZONE_CONT:
        BTST    #0x9,D1                         | clear-on-allocate flag?
        BEQ.B   PTRZONE_NO                      | no ->
        MOVE.L  A0,-(SP)                        | save block pointer
        ADDQ.L  #0x1,D0                         | round up
        LSR.L   #0x1,D0                         | / 2 = word count
PTRZONE_CONT_2:
        CLR     (A0)+                           | zero a word
        SUBQ.L  #0x1,D0                         | decrement word count
        BGT.B   PTRZONE_CONT_2                  | more words remaining ->
        MOVE.L  (SP)+,A0                        | restore block pointer
PTRZONE_NO:
        RTS                                     | return from PTRZONE_NO

| ----------------------------------------------------------
| _NewHandle ($A122): allocate a relocatable block
| Pascal: FUNCTION NewHandle(logicalSize: Size): Handle;
| Entry: D0.L = logicalSize; trap bit 9 ($A322, ,CLEAR) = clear the
|        block, bit 10 ($A522, ,SYS) = allocate in the system heap
| Exit:  A0 = handle (nil on failure), D0 = noErr or memFullErr (-108)
| Takes a free master pointer (NextMaster, which may allocate a new
| block of them), allocates the block (AllocBK may compact, purge,
| grow the zone and call the grow-zone function) and clears it if
| requested; on failure the master pointer is released again.
| Called during boot.
NewHandle:
        JSR      MMPrologue(PC)                 | set up TheZone, save regs
        JSR     NextMaster(PC)                  | allocate master pointer -> A1
        BNE.B   NEWHANDLE_ALLOC                 | got one, allocate block ->
        MOVEQ.L #-0x6C,D0                       | memFullErr
        BRA.B   DISPOSHANDLE_EXIT               | -> return nil handle
NEWHANDLE_ALLOC:
        JSR     AllocBK(PC)                     | allocate block of D0 bytes -> A0
        BEQ.B   NEWHANDLE_2                     | failed ->
NEWHANDLE_CONT:
        BSR.B   PTRZONE_CONT                    | optionally clear block (trap bit 9)
        MOVE.L  A1,A0                           | A0 = handle (master pointer addr)
NEWHANDLE_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
NEWHANDLE_EXIT_2:
        JMP     MMEpilogue(PC)                  | restore and return
NEWHANDLE_2:
        MOVEQ.L #-0x6C,D0                       | memFullErr
        BRA.B   DISPOSHANDLE_CONT               | -> release master pointer

| ----------------------------------------------------------
| _DisposHandle ($A023): release a relocatable block and its handle
| Pascal: PROCEDURE DisposHandle(h: Handle);
| Entry: A0 = h. Exit: D0 = noErr (memWZErr if the block is free)
| An existing block is freed through DisposPtr's FreeBk path, which
| also returns the master pointer to the free list; for an empty
| handle only the master pointer is released.
| Called during boot.
DisposHandle:
        JSR     MMHPrologue(PC)                 | deref handle -> A0=block, A1=MP
        BNE.B   DISPOSPTR_CONT                  | block exists -> free via DisposPtr path
        MOVEQ.L #0x0,D0                         | noErr (empty handle, just release MP)
DISPOSHANDLE_CONT:
        JSR     ReleaseMP(PC)                   | release master pointer to free list
DISPOSHANDLE_EXIT:
        SUBA.L  A0,A0                           | A0 = nil (no block)
        BRA.B   NEWHANDLE_EXIT_2                | -> return via MMEpilogue
| ----------------------------------------------------------
| _GetHandleSize ($A025): return the logical size of a relocatable block
| Pascal: FUNCTION GetHandleSize(h: Handle): Size;
| Entry: A0 = h
| Exit:  D0.L = logical size, or nilHandleErr (-109) for an empty
|        handle (memWZErr if the block is free)
GetHandleSize:
        JSR     MMHPrologue(PC)                 | deref handle -> A0=block, A1=MP
        BEQ.B   SETHANDLESIZE_EMPTY             | nil/empty handle -> nilHandleErr
        JSR     GetSize(PC)                     | D0 = block size (from block header)
        BRA.B   SETHANDLESIZE_ERR               | -> return via MMEpilogue

| ----------------------------------------------------------
| _SetHandleSize ($A024): change the size of a relocatable block
| Pascal: PROCEDURE SetHandleSize(h: Handle; newSize: Size);
| Entry: A0 = h, D0.L = newSize
| Exit:  D0 = noErr, memFullErr (-108), or nilHandleErr (-109) for an
|        empty handle
| SetSize grows the block in place if the space after it can be
| freed, else moves it (unless locked); shrinking splits off the rest.
SetHandleSize:
        JSR     MMHPrologue(PC)                 | deref handle -> A0=block, A1=MP
        BNE.B   SETHANDLESIZE_DO                | block exists ->
SETHANDLESIZE_EMPTY:
        MOVEQ.L #-0x6D,D0                       | nilHandleErr
        BRA.B   SETHANDLESIZE_ERR               | -> return error
SETHANDLESIZE_DO:
        JSR     SetSize(PC)                     | resize block
SETHANDLESIZE_ERR:
        MOVE.L  A1,A0                           | A0 = handle
        BRA.B   NEWHANDLE_EXIT_2                | return via MMEpilogue

| ----------------------------------------------------------
| HandleZone -- _HandleZone ($A126). Returns zone of handle's block.
HandleZone:
        JSR     MMHPrologue(PC)                 | dereference, find zone -> A6
        MOVE.L  A6,A0                           | A0 = zone
        BRA.B   NEWHANDLE_EXIT                  | return noErr via MMEpilogue

| ----------------------------------------------------------
| RecoverHandle -- _RecoverHandle ($A128). Plus 653.
| Given a pointer, find its handle (master pointer).
RecoverHandle:
        JSR     MMPrologue(PC)                  | clear grow-zone protection
        MOVE.L  -4(A0),A1                       | get relative handle from block header
        ADDA.L  A6,A1                           | A1 = absolute master pointer addr
        BRA.B   SETHANDLESIZE_ERR               | return via MMEpilogue (A0=A1)

| ----------------------------------------------------------
| EmptyHandle -- _EmptyHandle ($A02B). Plus 676.
| Free the block and set master pointer to nil.
EmptyHandle:
        JSR     MMHPrologue(PC)                 | deref handle -> A0=block, A1=MP
        BNE.B   EMPTYHANDLE_CONT                | block exists -> release it
        MOVEQ.L #0x0,D0                         | already empty: noErr
        BRA.B   EMPTYHANDLE_EXIT                | skip, exit cleanly
EMPTYHANDLE_CONT:
        JSR     EH(PC)                          | release block, clear master pointer
EMPTYHANDLE_EXIT:
        BRA.B   SETHANDLESIZE_ERR               | -> return via SetHandleSize epilogue
| ----------------------------------------------------------
| ReallocHandle -- _ReAllocHandle ($A027) trap entry. Plus 698.
ReallocHandle:
        JSR     MMHPrologue(PC)                 | dereference handle
        TST.L   (A1)                            | block already exists?
        BEQ.B   REALLOCHANDLE_OK                | no, allocate one
        JSR     EH(PC)                          | yes, free existing block
        BNE.B   SETHANDLESIZE_ERR               | error -> exit
        MOVE.L  D2,D0                           | restore size param
REALLOCHANDLE_OK:
        MOVE.L  A1,(GZRootHnd).w                | protect handle from grow-zone purging
        CLR.L   (GZRootPtr).w                   | clear root ptr (handle-based alloc)
        JSR     AllocBK(PC)                     | allocate new block
        JSR     GETSIZE_CONT(PC)                | clear grow-zone protection
        MOVE.L  A0,D2                           | D2 = block address
        BNE.W   NEWHANDLE_CONT                  | success -> link to master ptr
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
        BRA.B   SETHANDLESIZE_ERR               | return error via epilogue

| ----------------------------------------------------------
| _HLock ($A029): lock a relocatable block
| Pascal: PROCEDURE HLock(h: Handle);
| Entry: A0 = h. Exit: D0 = noErr, or nilHandleErr (-109) for an empty
| handle. Sets the lock bit (bit 7) of the master pointer's flag byte.
HLock:
        JSR     MMHPrologue(PC)                 | deref handle -> A1 = MP
        BEQ.B   HNOPURGE_EXIT_2                 | nil handle -> nilHandleErr
        BSET    #0x7,(A1)                       | set lock bit
        BRA.B   HNOPURGE_EXIT                   | return noErr
| ----------------------------------------------------------
| _HUnLock ($A02A): unlock a relocatable block
| Pascal: PROCEDURE HUnlock(h: Handle);
| Entry: A0 = h. Exit: D0 = noErr, or nilHandleErr (-109) for an empty
| handle. Clears the lock bit (bit 7) of the master pointer's flag byte.
HUnlock:
        JSR     MMHPrologue(PC)                 | deref handle -> A1 = MP
        BEQ.B   HNOPURGE_EXIT_2                 | nil handle -> nilHandleErr
        BCLR    #0x7,(A1)                       | clear lock bit
        BRA.B   HNOPURGE_EXIT                   | return noErr
| ----------------------------------------------------------
| HPurge -- _HPurge ($A049). Plus 759.
HPurge:
        JSR     MMHPrologue(PC)                 | deref handle -> A1 = MP
        BEQ.B   HNOPURGE_EXIT_2                 | nil handle -> nilHandleErr
        BSET    #0x6,(A1)                       | set purge bit
        BRA.B   HNOPURGE_EXIT                   | return noErr
| ----------------------------------------------------------
| HNoPurge -- _HNoPurge ($A04A). Plus 771.
HNoPurge:
        JSR     MMHPrologue(PC)                 | deref handle -> A1 = MP
        BEQ.B   HNOPURGE_EXIT_2                 | nil handle -> nilHandleErr
        BCLR    #0x6,(A1)                       | clear purge bit
HNOPURGE_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
        BRA.B   HNOPURGE_EXIT_3                 | join MMEpilogue exit
HNOPURGE_EXIT_2:
        MOVEQ.L #-0x6D,D0                       | nilHandleErr (-109)
HNOPURGE_EXIT_3:
        JMP     MMEpilogue(PC)                  | return via MMEpilogue

| ----------------------------------------------------------
| DerefHandle -- handle dereference helper. Plus 1101.
DerefHandle:
        MOVE.L  A0,D0                           | D0 = handle value
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit
        MOVE.L  D0,A0                           | A0 = clean handle
        MOVE.L  A0,A1                           | A1 = handle
        MOVEA.L (A1),A0                         | A0 = dereferenced
        MOVE.L  A0,D0                           | D0 = block address
        RTS                                     | return from DerefHandle

| ----------------------------------------------------------
| DEREFHANDLE_CONT
| Called during boot (39,524 times in 30s trace).
DEREFHANDLE_CONT:
        MOVE.L  A0,D0                           | D0 = pointer value
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        MOVE.L  D0,A0                           | A0 = clean pointer
        SUBQ.L  #0x8,A0                         | back up to block header
        TST.B   (A0)                            | check tag byte
        BEQ.B   DEREFHANDLE_CONT_4              | free block -> memWZErr
        BMI.B   DEREFHANDLE_CONT_2              | relocatable -> use relHandle
        MOVE.L  4(A0),A6                        | A6 = zone (non-reloc: header+4 = zone)
        BRA.B   DEREFHANDLE_CONT_3              | -> verify zone
DEREFHANDLE_CONT_2:
        MOVE.L  A1,A6                           | A6 = master pointer addr
        SUBA.L  4(A0),A6                        | A6 -= relHandle = zone base
DEREFHANDLE_CONT_3:
        MOVEQ.L #0x0,D0                         | return noErr
DEREFHANDLE_EXIT_2:
        ADDQ.L  #0x8,A0                         | skip block header (return user ptr)
        RTS                                     | return from DEREFHANDLE_EXIT_2
DEREFHANDLE_CONT_4:
        MOVEQ.L #-0x6F,D0                       | D0 = memWZErr (-111)
        BRA.B   DEREFHANDLE_EXIT_2              | return error

| ----------------------------------------------------------
| MMP Prologue
| Called during boot.
MMPPrologue:
        MOVE.L  (SP)+,A1                        | pop return address into A1
        MOVEM.L D3-D7/A2-A6,-(SP)               | save all working registers
        MOVE.L  A1,-(SP)                        | push return address back
        MOVE.L  D0,D2                           | D2 = save D0 (trap parameter)
        SUBA.L  A1,A1                           | A1 = nil (pointer, not handle)
        BSR.B   DEREFHANDLE_CONT                | validate ptr, find its zone
        BMI.B   MMHPROLOGUE_ERR                 | invalid -> error exit
        MOVE.L  D2,D0                           | D0 = restore trap parameter
        RTS                                     | return from MMPPrologue
| Called by: DisposHandle, GetHandleSize, SetHandleSize, HandleZone, EmptyHandle (and 5 more)
MMHPrologue:
        MOVE.L  (SP)+,A1                        | pop return address into A1
        MOVEM.L D3-D7/A2-A6,-(SP)               | save all working registers
        MOVE.L  A1,-(SP)                        | push return address back
        MOVE.L  D0,D2                           | D2 = save D0 (trap parameter)
        MOVE.L  (TheZone).w,A6                  | A6 = current zone (default)
        BSR.B   DerefHandle                     | A0 = block from MP
        BEQ.B   MMHPROLOGUE_CONT                | empty handle -> skip ptr-validate
        BSR.B   DEREFHANDLE_CONT                | validate block, find zone -> A6
        BMI.B   MMHPROLOGUE_ERR                 | invalid block -> error exit
MMHPROLOGUE_CONT:
        MOVE.L  D2,D0                           | D0 = restore trap parameter
        MOVE.L  A0,D7                           | D7 = save block address
        RTS                                     | return from MMHPrologue
MMHPROLOGUE_ERR:
        ADDQ.L  #0x4,SP                         | discard caller's return addr
        BRA.B   MMEpilogue                      | unwind via MMEpilogue
| Called by: CompactMem, PurgeMem, FreeMem, ResrvMem, RESRVMEM_SKIP (and 3 more)
MMPrologue:
        MOVE.L  (SP)+,A1                        | pop return addr to A1
        MOVEM.L D3-D7/A2-A6,-(SP)               | save all working registers
        MOVE.L  A1,-(SP)                        | push return address back
        MOVE.L  (TheZone).w,A6                  | A6 = current zone (default)
        BTST    #0xA,D1                         | system-heap flag set in trap word?
        BEQ.B   MMPROLOGUE_NO                   | no -> use TheZone
        MOVE.L  (SysZone).w,A6                  | yes -> redirect to SysZone
MMPROLOGUE_NO:
        RTS                                     | return from MMPrologue
MMEpilogue:
        MOVEM.L (SP)+,D3-D7/A2-A6               | restore working registers
        RTS                                     | return from MMEpilogue

| ----------------------------------------------------------
| Make BKF
| Called during boot (46,442 times in 30s trace).
MakeBKF:
        MOVE.L  D0,(A0)                         | set block size in header
        CLR.B   (A0)                            | clear tag byte (= free block)
        RTS                                     | return from MakeBKF
EH:
        BTST    #0x7,(A1)                       | MP locked? (bit 7)
        BNE.B   EH_EXIT_3                       | yes -> can't empty, return memLockedErr
        SUBQ.L  #0x8,A0                         | A0 -> block header (back up by 8)
        BSR.B   EH_CONT_2                       | free block, notify, clear MP
        ADDQ.L  #0x8,A0                         | restore A0 to original pointer
        MOVEQ.L #0x0,D0                         | return noErr
EH_EXIT_2:
        RTS                                     | return from EH
EH_EXIT_3:
        MOVEQ.L #-0x70,D0                       | D0 = memLockedErr (-112)
        BRA.B   EH_EXIT_2                       | return error
EH_CONT:
        TST.L   0x28(A6)                        | zone.purgeProc installed?
        BEQ.B   EH_EXIT_4                       | free -> accumulate free space
        MOVEM.L D0-D2/A0-A1,-(SP)               | save registers
        MOVE.L  A1,-(SP)                        | push handle being purged
        MOVE.L  0x28(A6),A1                     | A1 = purge warning procedure
        JSR     (A1)                            | call subroutine via A1
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore registers
EH_EXIT_4:
        RTS                                     | return to caller (@ $2E34)
EH_CONT_2:
        MOVE.L  D0,-(SP)                        | save D0 (caller's size)
        MOVE.L  (A0),D0                         | D0 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit = physical size
        BSR.B   EH_CONT                         | notify purge proc
        CLR.L   (A1)                            | clear master pointer (block purged)
        BSR.B   MakeBKF                         | convert to free block
        BSR.W   AdjustFree                      | add freed space to zcbFree
        MOVE.L  (SP)+,D0                        | restore D0
        RTS                                     | return from EH_CONT_2
PurgeHeap:
        MOVEM.L D2/A1-A4,-(SP)                  | save D2 and A1-A4
PURGEHEAP_CONT:
        MOVE.L  (A6),A3                         | A3 = zone.bkLim (end sentinel)
        LEA.L     0x34(A6),A0                   | A0 = zone.heapData (first block)
        BTST    #0x6,22(A6)                     | fast-purge flag? (flags bit 6)
        BNE.B   PURGEHEAP_OK_2                  | yes -> purge from current purgePtr
        MOVE.L  A0,A2                           | A2 = first block (scan start)
        MOVEQ.L #0x0,D2                         | D2 = 0: accumulated free space
PURGEHEAP_NO:
        MOVE.L  (A2),D1                         | D1 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit size
        MOVE.L  A2,A4                           | A4 = current block (save position)
        ADDA.L  D1,A2                           | A2 = next block
        TST.B   (A4)                            | check tag byte of current block
        BEQ.B   PURGEHEAP_CONT_2                | free -> accumulate free space
        BPL.B   PURGEHEAP_OK                    | non-reloc -> barrier, reset count
        MOVE.L  4(A4),A1                        | get relHandle of relocatable block
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        TST.B   (A1)                            | check MP flags: locked?
        BMI.B   PURGEHEAP_OK                    | yes -> barrier, reset count
        BTST    #0x6,(A1)                       | is handle purgeable? (bit 6)
        BEQ.B   PURGEHEAP_NO_2                  | no -> can't purge, track position
        CMPA.L  4(A6),A4                        | compare 4(A6) vs A4 (purgePtr)
        BCS.B   PURGEHEAP_SKIP                  | carry: skip accumulator reset
PURGEHEAP_CONT_2:
        ADD.L   D1,D2                           | add block size to accumulated free
        CMP.L   D0,D2                           | enough free space for request?
        BCS.B   PURGEHEAP_NO_2                  | no -> keep scanning
        BRA.B   PURGEHEAP_OK_3                  | yes -> start purging

PURGEHEAP_OK:
        MOVEQ    #0x0,D2                        | reset accumulated free-bytes counter
PURGEHEAP_SKIP:                                 | @ $2E92 (skip-reset entry)
        MOVEA.L  A2,A0                          | A0 = block base for CMPA in next step
PURGEHEAP_NO_2:
        CMPA.L  A3,A2                           | reached end-sentinel?
        BCS.B   PURGEHEAP_NO                    | no -> continue scanning
        LEA.L     0x34(A6),A0                   | A0 = zone.heapData (restart scan)
        CMPA.L  4(A6),A0                        | purgePtr already at start?
        BEQ.B   PURGEHEAP_OK_2                  | yes -> give up
        MOVE.L  A0,4(A6)                        | update purgePtr for next pass
        BRA.B   PURGEHEAP_CONT                  | -> rescan from beginning
PURGEHEAP_OK_2:                                 | call subroutine via A1
        MOVEA.L  A3,A2                          | A2 = end-sentinel (force final pass)
PURGEHEAP_OK_3:
        MOVE.L  (A0),D1                         | D1 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit size
        TST.B   (A0)                            | is block free?
        BPL.B   PURGEHEAP_SKIP_2                | yes -> skip to next
        MOVE.L  4(A0),A1                        | get relHandle
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        TST.B   (A1)                            | check MP flags
        BMI.B   PURGEHEAP_SKIP_2                | locked -> skip
        BTST    #0x6,(A1)                       | purgeable? (bit 6)
        BEQ.B   PURGEHEAP_SKIP_2                | not purgeable -> skip
        BSR.W   EH_CONT_2                       | purge this block (free + notify)
        CMP.L   D0,D1                           | freed size >= request?
        BCC.B   PURGEHEAP_DONE                  | yes -> done purging
PURGEHEAP_SKIP_2:
        ADDA.L  D1,A0                           | advance past this block
        MOVE.L  A0,4(A6)                        | update purgePtr
        CMPA.L  A2,A0                           | reached scan limit?
        BCS.B   PURGEHEAP_OK_3                  | no -> continue purging
PURGEHEAP_DONE:
        BSR.B   CompactHeap_Trampoline          | trampoline -> CompactHp at $3046
        MOVEM.L (SP)+,D2/A1-A4                  | restore D2 and A1-A4
        RTS                                     | return from PurgeHeap

| ----------------------------------------------------------
| TOTEPURGEABLES_CONT_3
TOTEPURGEABLES_CONT_3:
        MOVE.L  16(A6),D2                       | D2 = zone.gzProc
        BEQ.B   TOTEPURGEABLES_EXIT_2           | no grow-zone func -> return
        MOVEM.L D0-D1/D3-A6,-(SP)               | save all registers
        MOVE.L  16(A6),A1                       | A1 = grow-zone function
        CLR.L   -(SP)                           | push room for result
        MOVE.L  D0,-(SP)                        | push needed size
        JSR     (A1)                            | call subroutine via A1
        MOVE.L  (SP)+,D2                        | D2 = result (0 = failed)
        MOVEM.L (SP)+,D0-D1/D3-A6               | restore all registers
TOTEPURGEABLES_EXIT_2:
        RTS                                     | return from grow-zone helper
CompactHeap_Trampoline:                         | @ $2EFA (BSR.S reach extender)
        BRA.W   CompactHp                       | long branch to compactor @ $3046
BKCompacts:
        MOVEM.L D0/D2,-(SP)                     | save D0 (needed size), D2
        BSR.B   CompactHeap_Trampoline          | compact heap
        CMP.L   D1,D0                           | big enough block found?
        BLS.B   BKCOMPACTS_RETRY_DONE           | yes -> done
        CMPA.L  (ApplZone).w,A6                 | are we in the application zone?
        BNE.B   BKCOMPACTS_SKIP                 | no -> skip heap expansion
        TST.L   D2                              | D2 = grow allowed?
        BEQ.B   BKCOMPACTS_SKIP                 | no -> skip expansion
        BSR.W   ZONEADJUSTEND_CONT_3            | try expanding application heap
        BSR.B   CompactHeap_Trampoline          | compact again after expansion
        CMP.L   D1,D0                           | block found?
        BLS.B   BKCOMPACTS_RETRY_DONE           | yes -> done
BKCOMPACTS_SKIP:
        BSR.W   PurgeHeap                       | purge purgeable blocks
        CMP.L   D1,D0                           | block found?
        BLS.B   BKCOMPACTS_RETRY_DONE           | yes -> done
        TST.L   D2                              | grow-zone allowed?
        BEQ.B   BKCOMPACTS_RETRY_DONE           | no -> give up
BKCOMPACTS_RETRY:
        BSR.B   TOTEPURGEABLES_CONT_3           | call grow-zone function
        BSR.B   CompactHeap_Trampoline          | compact again
        CMP.L   D1,D0                           | block found?
        BLS.B   BKCOMPACTS_RETRY_DONE           | yes -> done
        TST.L   D2                              | grow-zone returned more?
        BNE.B   BKCOMPACTS_RETRY                | yes -> retry grow-zone
        SUBA.L  A0,A0                           | A0 = nil (no block found)
BKCOMPACTS_RETRY_DONE:
        MOVE.L  A0,D2                           | D2 = found block address
        MOVEM.L (SP)+,D0/D2                     | restore D0/D2
        RTS                                     | return from BKCompacts

| ----------------------------------------------------------
| B Find S
| Called during boot (15,878 times in 30s trace).
BFindS:
        MOVEM.L D1-D2/A1-A2,-(SP)               | save working registers
        MOVE.L  (Lo3Bytes).w,D2                 | D2 = Lo3Bytes mask (0x00FFFFFF)
        LEA.L     0x30(A6),A2                   | A2 = ptr to zone.allocPtr
        BTST    #0x5,22(A6)                     | rover search? (flags bit 5)
        BEQ.B   BFINDS_RETRY                    | no -> use allocPtr
        CLR.L   (A2)                            | clear allocPtr (start from beginning)
BFINDS_RETRY:
        MOVE.L  (A2),D1                         | D1 = allocPtr (roving pointer)
        MOVE.L  D1,A1                           | A1 = start of search
        BNE.B   BFINDS_EMPTY                    | non-nil? -> start there
        LEA.L     0x34(A6),A1                   | A1 = zone.heapData (search from start)
BFINDS_EMPTY:
        MOVE.L  (A1),D1                         | update allocPtr for next search
        TST.B   (A1)                            | block tag = 0 (free)?
        BEQ.B   BFINDS_CONT_2                   | yes -> check size
BFINDS_NO:
        AND.L   D2,D1                           | mask to 24-bit size
        ADDA.L  D1,A1                           | advance past this block
        BRA.B   BFINDS_EMPTY                    | loop
BFINDS_CONT_2:
        CMPA.L  (A6),A1                         | past zone end?
        BCC.B   BFINDS_ERR                      | yes -> retry from start
| ----------------------------------------------------------
| BFINDS_OK
| Called during boot (30,345 times in 30s trace).
BFINDS_OK:
        MOVE.L  A1,A0                           | A0 = start of free region
        ADDA.L  D1,A0                           | A0 = end of free region
        TST.B   (A0)                            | next block also free?
        BNE.B   BFINDS_NO_2                     | no -> check if big enough
        CMPA.L  (A6),A0                         | reached zone end?
        BCC.B   BFINDS_NO_2                     | yes -> stop coalescing
        ADD.L   (A0),D1                         | merge: add next block's size
        MOVE.L  D1,(A1)                         | update coalesced block size
        BRA.B   BFINDS_OK                       | -> try merging more
BFINDS_NO_2:
        CMP.L   D0,D1                           | D1 (coalesced size) >= D0 (needed)?
        BCS.B   BFINDS_NO                       | too small -> next block
        MOVE.L  A1,A0                           | A0 = free block address
        BRA.B   BFINDS_EXIT                     | -> return success
BFINDS_ERR:
        TST.L   (A2)                            | was allocPtr set?
        BEQ.B   BFINDS_ERR_2                    | no -> search failed
        CLR.L   (A2)                            | clear allocPtr
        BRA.B   BFINDS_RETRY                    | -> retry from zone.heapData
BFINDS_ERR_2:
        SUBA.L  A0,A0                           | A0 = nil (search failed)
BFINDS_EXIT:
        MOVE.L  A0,(A2)                         | update zone.allocPtr
        MOVEM.L (SP)+,D1-D2/A1-A2               | restore registers
        RTS                                     | return from BFindS
| Called by: NewPtr, NEWHANDLE_ALLOC, REALLOCHANDLE_OK, HMAKEMOREMASTERS_CONT, MAKEPTRSPC_CONT_5
AllocBK:
        MOVEM.L D0-D5,-(SP)                     | save registers
        MOVE.L  D0,D4                           | D4 = requested size (preserved)
        BSR.W   Actuals                         | round D0 to actual block size (+ header + align)
        BSR.B   BFindS                          | search free list for big enough block
        BNE.B   ALLOCBK_FOUND                   | found one ->
        MOVEQ.L #-0x1,D2                        | D2 = -1 (compact fully)
        BSR.W   BKCompacts                      | compact + purge + grow zone
        BNE.B   ALLOCBK_FOUND                   | found space ->
        SUBA.L  A0,A0                           | A0 = nil (alloc failed)
        BRA.B   ALLOCBK_ERR                     | -> return failure
ALLOCBK_FOUND:
        MOVE.L  D0,D2                           | D2 = actual size needed
        MOVE.L  (A0),D0                         | D0 = free block's total size
        MOVE.L  A1,D5                           | D5 = master pointer
        BEQ.B   ALLOCBK_EMPTY                   | nil -> non-relocatable block
        SUB.L   A6,D5                           | make handle zone-relative
        MOVEQ.L #0x2,D1                         | tag = $80 (relocatable)
        MOVEQ.L #-0x1,D3                        | size correction = -1
        BRA.B   ALLOCBK_CONT                    | build header + carve block
ALLOCBK_EMPTY:
        MOVE.L   FP,D5                          | D4 = total free block size
        MOVEQ    #0x1,D1                        | tag = 0x40 (non-reloc)
        MOVEQ    #0x0,D3                        | D3 = 0 (no high-allocation)

| build the block header and split free space
ALLOCBK_CONT:
        BSR.B   ALLOCBK_CONT_3                  | split: carve D2 from free block, leave remainder
        MOVE.L  D5,4(A0)                        | block header: relHandle (zone-relative)
        MOVE.L  D4,D0                           | D0 = original requested size
        BSR.B   ALLOCBK_CONT_2                  | set block tag/size in header
        ADDQ.L  #0x8,A0                         | A0 = block data (past 8-byte header)
        MOVE.L  A1,D5                           | master pointer address
        BEQ.B   ALLOCBK_ERR                     | nil (non-relocatable) ->
        MOVE.L  A0,(A1)                         | store block address in master pointer
ALLOCBK_ERR:
        MOVE.L  A0,D0                           | D0 = block address (or nil)
        MOVEM.L (SP)+,D0-D5                     | restore registers
        RTS                                     | return from AllocBK

| ----------------------------------------------------------
| ALLOCBK_CONT_2
| Called during boot (34,443 times in 30s trace).
ALLOCBK_CONT_2:
        MOVE.L  D1,-(SP)                        | save D1
        MOVE.L  (A0),D1                         | D1 = block header word 0
        AND.L   (Lo3Bytes).w,D1                 | mask to physical size
        SUBQ.L  #0x8,D1                         | subtract 8-byte header
        SUB.L   D0,D1                           | subtract logical size
        ANDI.B  #0xF,D1                         | D1 = correction & 0xF
        ANDI.B  #0xC0,(A0)                      | clear old correction bits
        OR.B    D1,(A0)                         | OR in new correction nibble
        MOVE.L  (SP)+,D1                        | restore D1
        RTS                                     | return from ALLOCBK_CONT_2
ALLOCBK_CONT_3:
        MOVEM.L D0-D2/D4/A1,-(SP)               | save working registers
        MOVE.L  D0,D4                           | D4 = total free block size
        SUB.L   D2,D0                           | D0 = remainder after carving
        MOVE.L  A0,A1                           | A1 = start of free block
        CMPI.L  #0xC,D0                         | remainder >= 12 (min block)?
        BCS.B   ALLOCBK_NO_2                    | no -> use entire free block
        TST     D3                              | D3 != 0? (reloc block, favor high)
        BEQ.B   ALLOCBK_NO                      | no -> allocate at bottom
        TST.B   22(A6)                          | zone.flags bit 7: alloc-high?
        BPL.B   ALLOCBK_NO                      | no -> allocate at bottom
        ADDA.L  D0,A1                           | A1 = allocate at high end
        BRA.B   ALLOCBK_CONT_4                  | -> create remainder at bottom
ALLOCBK_NO:
        ADDA.L  D2,A0                           | A0 = address of remainder
ALLOCBK_CONT_4:
        BSR.W   MakeBKF                         | build new free block from remainder
        BRA.B   ALLOCBK_CONT_5                  | record allocation, set tag/size
ALLOCBK_NO_2:
        MOVE.L  D4,D2                           | allocate entire free block (no split)
ALLOCBK_CONT_5:
        MOVE.L  D2,D0                           | D0 = allocation size
        NEG.L   D0                              | negate (subtract from zcbFree)
        BSR.W   AdjustFree                      | update zone.zcbFree
        MOVE.L  A1,A0                           | A0 = carved block address
        ROR.L   #0x2,D1                         | rotate tag bits into position
        ADD.L   D2,D1                           | D1 = tag + size
        MOVE.L  D1,(A0)                         | write block header
        MOVEM.L (SP)+,D0-D2/D4/A1               | restore registers
        RTS                                     | return from ALLOCBK_CONT_3
ALLOCBK_CONT_6:
        MOVE.L  D0,-(SP)                        | save count around trap
        _BlockMove                              | move D0 bytes A0->A1
        MOVE.L  (SP)+,D0                        | restore count
        RTS                                     | return from ALLOCBK_CONT_6
CompactHp:
        MOVEM.L D0/D2-D5/A1-A4,-(SP)            | save working registers
        MOVE.L  D0,D3                           | D3 = needed size (compaction target)
        MOVEQ.L #0x0,D1                         | D1 = 0: largest free block found
        LEA.L     0x34(A6),A0                   | A0 = zone.heapData (first block)

| ----------------------------------------------------------
| COMPACTHP_SKIP
| Called during boot.
COMPACTHP_SKIP:
        MOVE.L  (A0),D4                         | D4 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D4                 | mask to 24-bit size
        ADDA.L  D4,A0                           | advance past this block
        CMPA.L  (A6),A0                         | past zone end?
        BCC.B   COMPACTHP_OK                    | yes -> begin compaction phase
        TST.B    (A0)                           | first block free?
        BNE.B    COMPACTHP_SKIP                 | no -> skip past it
COMPACTHP_OK:
        BTst    #0x4,0x16(A6)                   | check fast-compact flag (bit 4)
        SEQ.B   D5                              | D5 = FF if not set, 00 if set
        MOVE.L  A0,A2                           | A2 = remember start position
COMPACTHP_CONT_2:
        MOVEA.L  A0,A1                          | A1 = current free-region anchor
        MOVEQ    #0x0,D2                        | D2 = 0 (free-bytes accumulator)
COMPACTHP_CONT_3:
        CMPA.L  (A6),A0                         | reached zone end?
        BCC.B   COMPACTHP_OK_4                  | yes -> finalize region
        MOVE.L  (A0),D0                         | D0 = block size
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit
        TST.B   (A0)                            | is block free?
        BEQ.B   COMPACTHP_OK_2                  | yes -> accumulate
        BPL.B   COMPACTHP_OK_3                  | non-reloc -> barrier
        MOVE.L  4(A0),A3                        | get relHandle
        ADDA.L  A6,A3                           | A3 = absolute master pointer
        TST.B   (A3)                            | check MP flags: locked?
        BMI.B   COMPACTHP_OK_3                  | yes -> barrier (can't move locked)
        TST.B   D5                              | fast-compact mode?
        BNE.B   COMPACTHP_SKIP_2                | yes -> don't move blocks
        LEA.L     8(A1),A4                      | A4 = destination (free region + 8)
        MOVE.B  (A3),D4                         | D4 = save MP flags
        MOVE.L  A4,(A3)                         | update MP to new location
        MOVE.B  D4,(A3)                         | restore MP flags byte
        BSR.B   ALLOCBK_CONT_6                  | BlockMove block to A1 dest
        ADDA.L  D0,A1                           | A1 advances past moved block
        BRA.B   COMPACTHP_SKIP_2                | -> continue scanning
COMPACTHP_OK_2:
        ADD.L   D0,D2                           | add free block size to accumulated
        MOVE.L  A1,A3                           | A3 = last free block position
        CMP.L   D3,D2                           | accumulated >= target?
        BCS.B   COMPACTHP_SKIP_2                | no -> keep scanning
        TST.B   D5                              | fast-compact mode?
        BEQ.B   COMPACTHP_OK_5                  | yes -> finalize with A3 as allocPtr
        CLR.B   D5                              | clear fast-compact for next pass
        MOVE.L  A2,A0                           | A0 = restart from saved position
        BRA.B   COMPACTHP_CONT_2                | -> rescan for real compaction
COMPACTHP_SKIP_2:
        ADDA.L  D0,A0                           | advance to next block
        BRA.B   COMPACTHP_CONT_3                | loop
COMPACTHP_OK_3:
        BSR.B   COMPACTHP_CONT_4                | flush coalesced free block
        BRA.B   COMPACTHP_SKIP                  | restart with barrier as anchor
COMPACTHP_OK_4:
        SUBA.L  A3,A3                           | A3 = nil (no allocPtr hint)
COMPACTHP_OK_5:
        BSR.B   COMPACTHP_CONT_4                | finalize last free region
        MOVE.L  A3,A0                           | A0 = allocPtr hint (from compaction)
        MOVE.L  A0,0x30(A6)                     | update zone.allocPtr
        MOVEM.L (SP)+,D0/D2-D5/A1-A4            | restore all working registers
        RTS                                     | return from CompactHp

| ----------------------------------------------------------
| COMPACTHP_CONT_4
| Called during boot.
COMPACTHP_CONT_4:
        TST.L   D2                              | any accumulated free space?
        BEQ.B   COMPACTHP_DONE                  | zero -> nothing to flush
        TST.B   D5                              | fast-compact mode (no actual moves)?
        BNE.B   COMPACTHP_SKIP_3                | yes -> don't write free block
        MOVE.L  D2,(A1)                         | write coalesced free block at A1
COMPACTHP_SKIP_3:
        CMP.L   D2,D1                           | D2 > D1? (larger than best so far)
        BCC.B   COMPACTHP_DONE                  | no -> keep current best
        MOVE.L  D2,D1                           | D1 = new largest free block size
COMPACTHP_DONE:
        RTS                                     | return from COMPACTHP_DONE
ToMaxLimit:
        MOVE.L  (BufPtr).w,D2                   | D2 = BufPtr (top of usable RAM)
        SUB.L    0x322,D2                       | subtract DefltStack (default stack reserve)

| MaxLimit -- compute max growable limit.
MaxLimit:
        MOVE.L  SP,D1                           | D1 = current stack pointer
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit
        SUB.L   (MinStack).w,D1                 | D1 -= minimum stack reserve
        CMP.L   D2,D1                           | D1 < D2?
        BCS.B   MAXLIMIT_OK                     | yes -> use D1 (stack-limited)
        MOVE.L  D2,D1                           | D1 = D2 (use heap limit)
MAXLIMIT_OK:
        RTS                                     | return to caller (@ $30F2)
| ----------------------------------------------------------
| Zone Adjust End
| Called during boot.
ZoneAdjustEnd:
        MOVEM.L D0/A0/A2-A3,-(SP)               | save registers
        MOVE.L  A0,A3                           | A3 = new end address
        MOVE.L  (A6),A0                         | A0 = old bkLim (old sentinel)
        MOVE.L  A3,D0                           | D0 = expansion size
        SUB.L   A0,D0                           | D0 = new - old sentinel
        MOVE.L  #0xC,(A3)                       | write sentinel block (12 bytes)
        BSR.W   MakeBKF                         | convert old sentinel to free block
        BSR.W   AdjustFree                      | add expansion to zone.zcbFree
        MOVE.L  A3,(A6)                         | update zone.bkLim
        MOVEM.L (SP)+,D0/A0/A2-A3               | restore registers
        RTS                                     | return from ZoneAdjustEnd
ZONEADJUSTEND_CONT_3:
        MOVEM.L D0-D2/A0,-(SP)                  | save D0-D2/A0
        ADDI.L  #0x400,D0                       | round growth up by 1024
        ANDI    #-0x400,D0                      | align growth to 1K boundary
        MOVE.L  (ApplLimit).w,D2                | D2 = current ApplLimit
        BSR.B   MaxLimit                        | compute D1 = max growable end
        MOVE.L  (HeapEnd).w,D2                  | D2 = current heap end
        CMP.L   D2,D1                           | already at max?
        BLS.B   ZONEADJUSTEND_OK                | branch if <= (unsigned)
        ADD.L   D0,D2                           | D2 = desired new end
        CMP.L   D2,D1                           | fits in max?
        BCS.B   ZONEADJUSTEND_NO                | no -> clamp to max
        MOVE.L  D2,D1                           | D1 = desired new end
        BRA.B   ZONEADJUSTEND_CONT_2            | commit expansion
ZONEADJUSTEND_NO:
        MOVE.L  D1,D0                           | D0 = available expansion
        SUB.L   (HeapEnd).w,D0                  | D0 = max limit - current end
        CMPI.L  #0xC,D0                         | less than minimum block?
        BCS.B   ZONEADJUSTEND_OK                | yes -> can't expand
ZONEADJUSTEND_CONT_2:
        MOVE.L  D1,(HeapEnd).w                  | HeapEnd := new end
        MOVE.L  D1,A0                           | A0 = new end (for ZoneAdjustEnd)
        BSR.B   ZoneAdjustEnd                   | extend bkLim and free block
ZONEADJUSTEND_OK:
        MOVEM.L (SP)+,D0-D2/A0                  | restore registers
        RTS                                     | return from ZONEADJUSTEND_CONT_3

| ----------------------------------------------------------
| Actuals
| Called during boot (34,515 times in 30s trace).
Actuals:
        ADDQ.L  #0x8,D0                         | add 8-byte block header
        ADDQ.L  #0x1,D0                         | add 1 for word alignment
        ANDI    #-0x2,D0                        | round down to even (word-align)
        CMPI.L  #0xC,D0                         | less than minimum (12)?
        BCC.B   ACTUALS_OK                      | no -> size is valid
        MOVEQ.L #0xC,D0                         | enforce minimum 12-byte block
ACTUALS_OK:
        RTS                                     | return to caller (@ $316A)
| ----------------------------------------------------------
| Get Size
| Called during boot (24,078 times in 30s trace).
GetSize:
        MOVE.L  D1,-(SP)                        | save D1
        SUBQ.L  #0x8,A0                         | back up to block header
        MOVEQ.L #0xF,D1                         | D1 = 0xF: mask for size correction
        AND.B   (A0),D1                         | D1 = correction nibble from tag byte
        MOVE.L  (A0),D0                         | D0 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit physical size
        SUBQ.L  #0x8,D0                         | subtract 8-byte header
        SUB.L   D1,D0                           | subtract size correction = logical size
        ADDQ.L  #0x8,A0                         | restore A0 to data pointer
        MOVE.L  (SP)+,D1                        | restore D1
        RTS                                     | return from GetSize
GETSIZE_CONT:
        CLR.L   (GZRootHnd).w                   | clear grow-zone protection (handle)
        CLR.L   (GZRootPtr).w                   | clear grow-zone protection (ptr)
        RTS                                     | return from GETSIZE_CONT
SetSize:
        MOVEM.L D1-D5/A0-A2,-(SP)               | save working registers
        MOVE.B  (A1),-(SP)                      | save MP flags on stack
        MOVE.L  D0,D1                           | D1 = new logical size
        BSR.B   Actuals                         | round to actual block size
        MOVE.L  D0,D3                           | D3 = actual size needed
        BSR.B   GetSize                         | D0 = current logical size
        CMP.L   D0,D1                           | same size?
        BEQ.W   SETSIZE_OK_5                    | yes -> just update correction
        MOVE.L  A0,A2                           | A2 = block header
        SUBQ.L  #0x8,A2                         | back up to header
        MOVE.L  (A2),D2                         | D2 = current header (tag+size)
        AND.L   (Lo3Bytes).w,D2                 | mask to physical size
        MOVE.L  D2,D4                           | D4 = current physical size
        CMP.L   D2,D3                           | new vs current physical?
        BEQ.B   SETSIZE_NO_5                    | same physical size -> just update tag
        BCS.B   SETSIZE_CONT_4                  | shrinking -> split off remainder
        MOVE.L  A1,(GZRootHnd).w                | protect this handle from grow-zone
        MOVE.L  A0,(GZRootPtr).w                | protect this ptr from grow-zone
        MOVE.L  A2,A0                           | A0 = our block header
        MOVE.L  D3,D0                           | D0 = additional bytes needed
        SUB.L   D2,D0                           | D0 = new - old
        ADDA.L  D2,A2                           | A2 = end of old block
        BSET    #0x7,(A1)                       | temporarily lock during SetSize
        BSR.W   MAKEPTRSPC_CONT_2               | recursive SetSize for extension
        BCLR    #0x7,(A1)                       | unlock after SetSize
        MOVE.L  A2,D4                           | D4 = result address
        BNE.B   SETSIZE_CONT_6                  | extension succeeded -> grow in place
        MOVE.L   A1,D4                          | D4 = handle (for re-alloc check)
        BEQ.B    SETSIZE_CONT_5                 | non-reloc -> can't relocate -> err
        TST.B   (SP)                            | saved MP flag bit 7 (locked)?
        BMI.B   SETSIZE_CONT_5                  | locked -> can't relocate -> err
        MOVE.L  D1,D0                           | D0 = new logical size
        BSR.W   MAKEPTRSPC_CONT_5               | allocate new block, copy, free old
        BSR.B   GETSIZE_CONT                    | clear grow-zone protection
        BRA.B   SETSIZE_ERR                     | return success/failure
SETSIZE_CONT_5:
        BSR.B   GETSIZE_CONT                    | clear grow-zone protection
        MOVEQ.L #-0x6C,D0                       | D0 = memFullErr (-108)
        BRA.B   SETSIZE_ERR                     | return error
SETSIZE_CONT_6:
        BSR.B   GETSIZE_CONT                    | clear grow-zone protection
        MOVE.L  (A2),D0                         | D0 = following block header
        MOVE.L  D0,D4                           | D4 = following block size
        ADD.L   D2,D4                           | D4 = combined merged size
        MOVE.L  A0,A2                           | A2 = our block header again
        MOVE.B  (A2),D5                         | D5 = save tag byte
        MOVE.L  D4,(A2)                         | write merged header (size only)
        MOVE.B  D5,(A2)                         | restore tag byte
        NEG.L   D0                              | D0 = -size of consumed block
        BSR.B   AdjustFree                      | zcbFree -= absorbed size
SETSIZE_CONT_4:
        SUB.L   D3,D4                           | D4 = leftover bytes after carve
        CMPI.L  #0xC,D4                         | leftover < min block (12)?
        BCS.B   SETSIZE_NO_5                    | yes -> absorb, no split
        MOVE.L  A2,A0                           | A0 = our block header
        ADDA.L  D3,A0                           | A0 = address of split-off remainder
        MOVE.B  (A2),D5                         | D5 = save tag byte
        MOVE.L  D3,(A2)                         | unlink: zone.hFstFree = next free MP
        MOVE.B  D5,(A2)                         | D0 = A1 (NE = success)
        MOVE.L  D4,D0                           | D0 = remainder size
        BSR.W   MakeBKF                         | build new free block
        BSR.B   AdjustFree                      | zcbFree += remainder size
SETSIZE_NO_5:
        MOVE.L  A2,A0                           | A0 = block header
        MOVE.L  D1,D0                           | D0 = new logical size
        BSR.W   ALLOCBK_CONT_2                  | update size correction nibble
SETSIZE_OK_5:
        MOVEQ.L #0x0,D0                         | return noErr
SETSIZE_ERR:
        MOVE.B  (SP)+,(A1)                      | restore MP flags from stack
        MOVEM.L (SP)+,D1-D5/A0-A2               | restore D1-D5, A0-A2
        RTS                                     | return from SetSize

| ----------------------------------------------------------
| Adjust Free
| Called during boot (56,518 times in 30s trace).
AdjustFree:
        ADD.L   D0,12(A6)                       | zone.zcbFree += D0
        BMI.B   ADJUSTFREE_ERR_2                | went negative? -> system error
        RTS                                     | return from AdjustFree
ADJUSTFREE_ERR_2:
        MOVEQ.L #0x1F,D0                        | D0 = 31 (dsZcbFreeErr: zcbFree went negative)
        _SysError                               | system error trap

| NextMaster -- get free master pointer -> A1.
NextMaster:
        MOVEM.L D0/A0,-(SP)                     | save D0 and A0
        MOVE.L  8(A6),A1                        | A1 = zone.hFstFree (free MP list head)
        MOVE.L  A1,D0                           | D0 = A1 (for Z flag test)
        BNE.B   NEXTMASTER_CONT                 | any free master pointers?
        BSR.B   HMakeMoreMasters                | no -> allocate more
        BEQ.B   NEXTMASTER_ERR                  | allocation failed? -> return nil
NEXTMASTER_CONT:
        MOVE.L  (A1),8(A6)                      | unlink: zone.hFstFree = (*A1)
        MOVE.L  A1,D0                           | D0 = master ptr (NE = success)
NEXTMASTER_ERR:
        MOVEM.L (SP)+,D0/A0                     | restore D0/A0
        RTS                                     | return from NextMaster
HMakeMoreMasters:
        MOVEM.L D0-D1/A0,-(SP)                  | save registers
        MOVE    20(A6),D0                       | D0 = zone.moreMast count
        EXT.L    D0                             | sign-extend to longword
        BGT.B   HMAKEMOREMASTERS_CONT           | valid count? (> 0)
        MOVEQ.L #0x20,D0                        | default to 32 master pointers
HMAKEMOREMASTERS_CONT:
        MOVE.L  D0,D1                           | D1 = number of master pointers
        ASL.L   #0x2,D0                         | D0 = byte size (4 bytes per MP)
        BSR.B   MakePtrSpc                      | find/make space for ptr block
        SUBA.L  A1,A1                           | A1 = nil (non-relocatable)
        BSR.W   AllocBK                         | allocate block for master pointers
        BEQ.B   HMAKEMOREMASTERS_ERR            | failed? -> return
        MOVE.L  A0,A1                           | A1 = first master pointer in block
HMAKEMOREMASTERS_CONT_2:
        BSR.B   ReleaseMP                       | link MP into free list
        ADDQ.L  #0x4,A1                         | advance to next MP slot
        SUBQ.W  #0x1,D1                         | count down
        BNE.B   HMAKEMOREMASTERS_CONT_2         | more to do
        SUBQ.L  #0x4,A1                         | back up to last valid MP
HMAKEMOREMASTERS_ERR:
        MOVE.L  A1,D0                           | D0 = last MP (or nil)
        MOVEM.L (SP)+,D0-D1/A0                  | restore D0-D1/A0
        RTS                                     | return from HMakeMoreMasters
ReleaseMP:
        MOVE.L  8(A6),(A1)                      | A2 = new scan start
        MOVE.L  A1,8(A6)                        | zone.hFstFree = A1 (push on free list)
        RTS                                     | return from ReleaseMP
MakePtrSpc:
        MOVEM.L D0-D3/A0-A1/A3,-(SP)            | save D0-D3/A0-A1/A3
        BSR.W   Actuals                         | round D0 to actual block size
        CMPA.L  (ApplZone).w,A6                 | in application zone?
        SEQ     D3                              | D3 = -1 if yes (allow grow)
MAKEPTRSPC_RETRY:
        LEA.L     0x34(A6),A0                   | A0 = zone.heapData (scan start)
        MOVE.L  (A6),A3                         | A3 = zone.bkLim (zone end)
        MOVE.L  A0,A2                           | A2 = scan start position
        MOVEQ.L #0x0,D2                         | D2 = 0: accumulated free+purgeable
MAKEPTRSPC_NO:
        MOVE.L  (A0),D1                         | D1 = block header
        AND.L   (Lo3Bytes).w,D1                 | D1 = block size (mask 24-bit)
        TST.B   (A0)                            | free block?
        BEQ.B   MAKEPTRSPC_OK                   | yes -> accumulate
        BPL.B   MAKEPTRSPC_OK_3                 | non-reloc -> barrier
        MOVE.L  4(A0),A1                        | D1 = bytes needed
        ADDA.L  A6,A1                           | A1 = absolute MP from relHandle
        TST.B   (A1)                            | MP locked?
        BMI.B   MAKEPTRSPC_OK_3                 | yes -> barrier
MAKEPTRSPC_OK:
        ADD.L   D1,D2                           | D2 += block size
        ADDA.L  D1,A0                           | advance past block
        CMP.L   D0,D2                           | enough space accumulated?
        BCS.B   MAKEPTRSPC_NO_3                 | no -> keep scanning
        BSR.B   MAKEPTRSPC_CONT_2               | purge/compact this region
        MOVE.L  A2,D2                           | D2 = A2 (NE = success)
        BNE.B   MAKEPTRSPC_EXIT_2               | success? -> return
        BRA.B   MAKEPTRSPC_CONT                 | -> continue scanning
MAKEPTRSPC_OK_3:
        ADDA.L  D1,A0                           | advance past barrier
MAKEPTRSPC_CONT:
        MOVE.L  A0,A2                           | A2 = new scan anchor (after barrier)
        MOVEQ.L #0x0,D2                         | D2 = 0 (reset accumulator)
MAKEPTRSPC_NO_3:
        CMPA.L  A3,A0                           | reached zone end?
        BCS.B   MAKEPTRSPC_NO                   | no -> keep scanning
        ADDQ.B  #0x1,D3                         | increment retry counter
        BNE.B   MAKEPTRSPC_RETRY_2              | first retry? -> try expanding heap
        BSR.W   ZONEADJUSTEND_CONT_3            | expand application heap
        BRA.B   MAKEPTRSPC_RETRY                | rescan after grow
MAKEPTRSPC_RETRY_2:
        SUBA.L  A2,A2                           | A2 = nil (search failed)
MAKEPTRSPC_EXIT_2:
        MOVEM.L (SP)+,D0-D3/A0-A1/A3            | restore D0-D3/A0-A1/A3
        RTS                                     | return from MakePtrSpc

| ----------------------------------------------------------
| MAKEPTRSPC_CONT_2
| Called during boot (7,495 times in 30s trace).
MAKEPTRSPC_CONT_2:
        MOVEM.L D0-D3/A0-A1/A3,-(SP)            | save registers
        MOVE.L  D0,D1                           | D1 = bytes needed
        MOVE.L  A2,A3                           | A3 = scan start
        MOVEQ.L #0x0,D3                         | D3 = 0: bytes freed so far
MAKEPTRSPC_CONT_3:
        CMP.L   D1,D3                           | freed enough?
        BCC.B   MAKEPTRSPC_OK_5                 | yes -> finalize
        CMPA.L  (A6),A3                         | past zone end?
        BCC.B   MAKEPTRSPC_OK_5                 | yes -> finalize
        TST.B   (A3)                            | is block free?
        BEQ.B   MAKEPTRSPC_OK_4                 | yes -> count it
        BPL.B   MAKEPTRSPC_OK_5                 | non-reloc -> stop (barrier)
        MOVE.L  4(A3),A1                        | get relHandle
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        MOVE.B  (A1),D2                         | D2 = MP flags byte
        BMI.B   MAKEPTRSPC_OK_5                 | locked? -> stop (barrier)
        BSR.B   MAKEPTRSPC_CONT_4               | try relocating block out
        BEQ.B   MAKEPTRSPC_OK_4                 | moved successfully? -> count as free
        BTST    #0x6,D2                         | is block purgeable?
        BEQ.B   MAKEPTRSPC_OK_5                 | no -> stop (can't free this block)
        MOVE.L  (A1),A0                         | A0 = block data via master pointer
        SUBQ.L  #0x8,A0                         | back up to block header
        BSR.W   EH_CONT_2                       | purge block (free + notify)
MAKEPTRSPC_OK_4:
        MOVE.L  A3,A0                           | A0 = current scan position
        MOVE.L  (A0),D0                         | D0 = block size
        CMPA.L  0x30(A6),A0                     | block contains zone.allocPtr?
        BNE.B   MAKEPTRSPC_SKIP                 | no -> keep scanning
        CLR.L   0x30(A6)                        | clear allocPtr (will be rebuilt)
MAKEPTRSPC_SKIP:
        ADD.L   D0,D3                           | D3 += block size (freed bytes accumulator)
        ADDA.L  D0,A3                           | A3 += block size (advance scan pointer)
        BRA.B   MAKEPTRSPC_CONT_3               | back to loop head
MAKEPTRSPC_OK_5:
        AND.L   (Lo3Bytes).w,D3                 | mask D3 to 24-bit
        BEQ.B   MAKEPTRSPC_SKIP_2               | nothing freed? -> skip write
        MOVE.L  D3,(A2)                         | write coalesced free block
MAKEPTRSPC_SKIP_2:
        CMP.L   D1,D3                           | freed enough?
        BCC.B   MAKEPTRSPC_ERR                  | no -> A2 = nil (failed)
        SUBA.L  A2,A2                           | A2 = nil (failure)
MAKEPTRSPC_ERR:
        CLR.L   0x30(A6)                        | clear allocPtr
        MOVEM.L (SP)+,D0-D3/A0-A1/A3            | restore registers
        RTS                                     | return from MAKEPTRSPC_CONT_2
MAKEPTRSPC_CONT_4:
        MOVE.L  A0,-(SP)                        | save A0
        MOVE.L  D3,D0                           | D0 = bytes freed so far
        BEQ.B   MAKEPTRSPC_SKIP_3               | nothing freed yet? -> skip
        MOVE.L  D3,(A2)                         | mark freed region as non-reloc temp
        ORI.L    #0x40000000,(A2)               | set non-reloc tag in placeholder header
        MOVE.L  A6,4(A2)                        | relHandle = zone base
        NEG.L   D0                              | negate for AdjustFree (subtract)
        BSR.W   AdjustFree                      | subtract from zcbFree
MAKEPTRSPC_SKIP_3:
        MOVE.L  (A1),A0                         | A0 = block data (via master ptr)
        BSR.W   GetSize                         | D0 = logical size of block
        BSR.B   MAKEPTRSPC_CONT_5               | allocate new block, move data
        MOVE.L  D0,A0                           | A0 = D0 (result for caller)
        MOVE.L  D3,D0                           | D0 = bytes freed
        BEQ.B   MAKEPTRSPC_SKIP_4               | nothing freed? -> skip
        MOVE.L  D3,(A2)                         | restore free block at old region
        BSR.W   AdjustFree                      | add freed space back to zcbFree
MAKEPTRSPC_SKIP_4:
        MOVE.L  A0,D0                           | D0 = result (NE = success)
        MOVE.L  (SP)+,A0                        | restore A0
        RTS                                     | return from MAKEPTRSPC_CONT_4
MAKEPTRSPC_CONT_5:
        MOVEM.L D1/A0-A2,-(SP)                  | save D1/A0-A2
        MOVE.L  A1,A2                           | A2 = master pointer addr
        MOVE.L  A1,(GZMoveHnd).w                | record handle being relocated
        MOVE.B  (A2),D1                         | D1 = save MP flags byte
        BCLR    #0x6,(A2)                       | clear purgeable bit (don't purge during move)
        SUBA.L  A1,A1                           | A1 = nil (will allocate non-reloc temp)
        BSR.W   AllocBK                         | allocate new block of D0 bytes
        BEQ.B   MAKEPTRSPC_ERR_3                | failed -> restore flags, return err
        TST.L   (A2)                            | block currently allocated?
        BEQ.B   MAKEPTRSPC_NO_4                 | no (empty handle) -> just link
        MOVE.L  A0,A1                           | A1 = new block (destination)
        MOVE.L  (A2),A0                         | A0 = old block (source)
        BSR.W   GetSize                         | D0 = logical size to copy
        BSR.W   ALLOCBK_CONT_6                  | BlockMove: copy contents
        SUBQ.L  #0x8,A0                         | A0 = old block header
        MOVEQ.L #-0x40,D0                       | D0 = 0xC0 (tag-swap mask)
        EOR.B   D0,(A0)                         | flip non-reloc <-> reloc tag
        ADDQ.L  #0x4,A0                         | A0 -> relHandle field
        SUBQ.L  #0x8,A1                         | A1 = new block header
        EOR.B   D0,(A1)                         | flip tag on new block too
        ADDQ.L  #0x4,A1                         | A1 -> relHandle field of new
        MOVE.L  (A0),(A1)+                      | copy old relHandle into new (post-incr)
        MOVE.L  A1,(A2)                         | MP -> new block data
        MOVE.B  D1,(A2)                         | restore MP flags
        MOVE.L  A6,(A0)+                        | old block now points to zone (free)
MAKEPTRSPC_NO_4:
        BSR.B   FreeBk                          | free old block
        MOVEQ.L #0x0,D0                         | return success (Z = 0)
MAKEPTRSPC_ERR_2:
        CLR.L   (GZMoveHnd).w                   | clear move-in-progress marker
        MOVEM.L (SP)+,D1/A0-A2                  | restore D1/A0-A2
        RTS                                     | return from MAKEPTRSPC_CONT_5
MAKEPTRSPC_ERR_3:
        MOVE.B  D1,(A2)                         | restore MP flags
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
        BRA.B   MAKEPTRSPC_ERR_2                | -> return error

| ----------------------------------------------------------
| Free Bk
| Called during boot (15,711 times in 30s trace).
FreeBk:
        MOVEM.L D0-D1/A0-A1,-(SP)               | save registers
        SUBQ.L  #0x8,A0                         | back up to block header
        MOVE.L  (A0),D0                         | D0 = block header (tag+size)
        MOVE.L  D0,D1                           | D1 = copy for tag extraction
        AND.L   (Lo3Bytes).w,D0                 | mask to physical size
        EOR.L   D0,D1                           | D1 = tag bits only
        BEQ.B   FREEBK_SKIP                     | tag = 0? -> already free, skip
        BPL.B   FREEBK_NO                       | non-reloc? -> no master pointer
        MOVE.L  4(A0),A1                        | get relHandle
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        BSR.W   ReleaseMP                       | return MP to free list
FREEBK_NO:
        BSR.W   MakeBKF                         | convert to free block
        BSR.W   AdjustFree                      | zcbFree += freed bytes
FREEBK_SKIP:
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore D0-D1/A0-A1
        RTS                                     | return from FreeBk

| ----------------------------------------------------------
| _BlockMove ($A02E): copy a block of memory (overlap-safe)
| Pascal: PROCEDURE BlockMove(sourcePtr, destPtr: Ptr; byteCount: Size);
| Entry: A0 = sourcePtr, A1 = destPtr, D0.L = byteCount
| Exit:  D0 = noErr (0)
| Copies backwards from the end if the destination lies above the
| source (24-bit compare), else forwards. An odd distance between
| source and destination means a byte loop; otherwise it aligns to an
| even address, moves 48-byte chunks with MOVEM (BlockMove_Fast, for
| 124 bytes or more), then longs, then the last 0-3 bytes.
BlockMove:
        TST.L   D0                              | count == 0?
        BEQ.B   BLKMOVE_BYTE_FWD_RTS            | yes -> nothing to do
        MOVE.L  A0,D2                           | D2 = source addr
        AND.L   (Lo3Bytes).w,D2                 | mask source to 24-bit
        MOVE.L  A1,D1                           | D1 = dest addr
        AND.L   (Lo3Bytes).w,D1                 | mask dest to 24-bit
        SUB.L   D2,D1                           | D1 = dest - src
        BLT.B   BLKMOVE_NO_OFFSET               | dest < src -> forward copy
        ADDA.L  D0,A0                           | A0 -> end of src (reverse)
        ADDA.L  D0,A1                           | A1 -> end of dest (reverse)
BLKMOVE_NO_OFFSET:
        LSR     #0x1,D1                         | odd alignment?
        BCC.B   BLKMOVE_DIR_DISPATCH            | even -> word/long copy
BLKMOVE_TAIL_FIXUP:                             | tail-byte fixup entry
        TST.L   D1                              | D1 sign: forward or backward?
        BPL.B   BLKMOVE_BYTE_BACK_LOOP          | backward direction -> back loop

| ============================================================
| BlockMove fast-path ($341A-$34AD, 148 bytes)
| The ROM places it just before the .Sound driver header; logically
| it is the tail of the Memory Manager _BlockMove implementation.
| ============================================================
| ----------------------------------------------------------
| BLKMOVE_BYTE_FWD_LOOP - copy D0 bytes forward, one at a time
BLKMOVE_BYTE_FWD_LOOP:
        MOVE.B  (A0)+,(A1)+                     | copy one byte forward
        SUBQ.L  #0x1,D0                         | decrement byte counter
        BNE.B   BLKMOVE_BYTE_FWD_LOOP           | loop until done
BLKMOVE_BYTE_FWD_RTS:
        RTS                                     | return from BLKMOVE_BYTE_FWD_RTS
BLKMOVE_BYTE_BACK_LOOP:
        MOVE.B  -(A0),-(A1)                     | copy one byte backward
        SUBQ.L  #0x1,D0                         | decrement byte counter
        BNE.B   BLKMOVE_BYTE_BACK_LOOP          | loop until done
        RTS                                     | return from BLKMOVE_BYTE_BACK_LOOP
BLKMOVE_DIR_DISPATCH:
        MOVE    A0,D2                           | D2 = source addr (low word)
        LSR     #0x1,D2                         | test source alignment
        BCC.B   BLKMOVE_SKIP_ODD                | even -> word/long path
        TST.L   D1                              | forward or backward?
        BPL.B   BLKMOVE_BYTE_BACK               | backward -> read pre-decrement
        MOVE.B  (A0)+,(A1)+                     | forward: copy odd byte to align
        BRA.B   BLKMOVE_DEC_D0                  | decrement count
BLKMOVE_BYTE_BACK:
        MOVE.B  -(A0),-(A1)                     | backward: copy odd byte
BLKMOVE_DEC_D0:
        SUBQ.L  #0x1,D0                         | count -= 1
BLKMOVE_SKIP_ODD:
        MOVEQ.L #0x7C,D2                        | D2 = 124 (fast-path threshold)
        CMP.L   D2,D0                           | enough bytes for fast path?
        BCS.B   BLKMOVE_TAIL                    | no -> tail copy
        BSR.B   BlockMove_Fast                  | yes -> 48 bytes per iter
BLKMOVE_TAIL:
        CMPI    #0x4,D0                         | at least 4 bytes left?
        BLT.B   BLKMOVE_TAIL_BYTES              | no -> finish in byte loop
        MOVE    D0,D2                           | D2 = byte count
        LSR     #0x2,D2                         | D2 = longword count
        SUBQ.W  #0x1,D2                         | D2 = DBF count - 1
        TST.L   D1                              | direction?
        BMI.B   BLKMOVE_FWD_LONG_LOOP           | forward -> post-incr loop
BLKMOVE_BACK_LONG_LOOP:
        MOVE.L  -(A0),-(A1)                     | copy one longword backward
        DBRA    D2,BLKMOVE_BACK_LONG_LOOP       | loop D2+1 times
        BRA.B   BLKMOVE_TAIL_BYTES              | finish tail bytes
BLKMOVE_FWD_LONG_LOOP:
        MOVE.L  (A0)+,(A1)+                     | copy one longword forward
        DBRA    D2,BLKMOVE_FWD_LONG_LOOP        | loop D2+1 times
BLKMOVE_TAIL_BYTES:
        MOVEQ.L #0x3,D2                         | D2 = 3 (tail-byte count mask)
        AND.L   D2,D0                           | D0 = remaining byte count (0..3)
        BNE.B   BLKMOVE_TAIL_FIXUP              | tail bytes remain: finish in byte loop
        RTS                                     | return from BlockMove
| BlockMove_Fast - block-move 48 bytes (12 longs) per iteration
| D0 = total byte count, D1 sign: + = forward, - = backward
BlockMove_Fast:
        MOVEM.L D1/D3-D7/A2-A6,-(SP)            | save all work registers
        MOVE    #0x30,-(SP)                     | push 0x30 = 48 (block stride)
        DIVU    (SP),D0                         | D0 = D0 / 48
        SUBQ.W  #0x1,D0                         | D0 = loop count - 1 (for DBF)
        TST.L   D1                              | forward or backward?
        BMI.B   BLKMOVE_FORWARD                 | negative: forward copy
| Backward copy: A0/A1 point PAST end of block
        SUBA.W  (SP),A0                         | A0 -= 48 (one-time rewind)
BLKMOVE_BACK_LOOP:
        MOVEM.L (A0)+,D1-D7/A2-A6               | load 48 bytes (12 longs)
        MOVEM.L D1-D7/A2-A6,-(A1)               | store 48 bytes (predec)
        SUBA.W  #0x60,A0                        | A0 -= 96 for next iteration
        DBF     D0,BLKMOVE_BACK_LOOP            | loop 48 bytes at a time
        ADDA.W  (SP),A0                         | re-add stride (final fixup)
        BRA.B   BLKMOVE_FAST_EXIT               | restore regs and return
BLKMOVE_FORWARD:
        ADDA.W  (SP),A1                         | A1 += 48 (advance past initial MOVEM)
BLKMOVE_FORWARD_LOOP:
        MOVEM.L (A0)+,D1-D7/A2-A6               | (A0)+ -> D1-D7/A2-A6
        MOVEM.L D1-D7/A2-A6,-(A1)               | D1-D7/A2-A6 -> -(A1)
        ADDA.W  #0x60,A1                        | skip past block we just stored
        DBRA    D0,BLKMOVE_FORWARD_LOOP         | loop D0+1 iterations
        SUBA.W  (SP),A1                         | rewind A1 to actual end
BLKMOVE_FAST_EXIT:
        ADDQ.L  #0x2,SP                         | pop the saved stride from stack
        MOVEM.L (SP)+,D1/D3-D7/A2-A6            | restore work registers
        SWAP    D0                              | return tail count in D0 lo word
        RTS                                     | return from BlockMove_Fast
