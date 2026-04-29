| Memory Manager
|
| Manages heap zones for dynamic memory allocation. Provides
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

| ----------------------------------------------------------
|
| Memory Manager A-trap handlers (Plus-only extensions)
|
| _SetAppBase ($A05C), _InitApplZone ($A02C). Classic has these
| dispatched inline through the trap table without dedicated labels;
| Plus has them explicitly.
| ----------------------------------------------------------

| ----------------------------------------------------------
|
| Set App Base
|
| Called during boot.
SetAppBase:
        MOVEM.L D3/A2-A6,-(SP)                  | save registers
        MOVE.L  (SysZone).w,A6                  | A6 = system zone
        SUBA    #0xC,A0                         | adjust requested base
        CMPA.L  (A6),A0                         | below system zone end?
        BLS.B   SETAPPBASE_SKIP                 | yes -> skip adjustment
        JSR     ZoneAdjustEnd(PC)               | adjust system zone end to new base
SETAPPBASE_SKIP:
        BSR.B   SETAPPBASE_CONT                 | initialize application zone globals
        MOVEM.L (SP)+,D3/A2-A6                  | restore registers
        RTS                                     | return from SetAppBase

| ----------------------------------------------------------
|
| SETAPPBASE_CONT
|
| Called during boot.
SETAPPBASE_CONT:
        MOVE.L  A6,-(SP)                        | save A6
        _RsrcZoneInit                           | initialize resource manager zone
        CLR.L   (ApplZone).w                    | clear application zone
        JSR     ToMaxLimit(PC)                  | get max application limit
        MOVE.L  D2,(ApplLimit).w                | set application limit
        MOVE.L  D2,(HighHeapMark).w             | set high heap mark
        MOVE.L  (SysZone).w,A6                  | get system zone
        MOVE.L  (A6),A0                         | get end of system zone
        LEA.L   fFRectWidth(A0),A0              | adjust to start of application zone
        MOVE.L  A0,A1                           | initial application zone end
        ADDA    #0x1800,A1                      | add 6K initial size
        CMPA.L  D1,A1                           | fits in available memory?
        BCS.B   SETAPPBASE_OK                   | yes ->
        MOVE.L  D1,A1                           | no -> limit to available memory
SETAPPBASE_OK:
        CLR.L   -(SP)                           | push dummy parameter space
        MOVE    #0x40,-(SP)                     | cMoreMasters = 64
        MOVE.L  A1,-(SP)                        | cLimit = initial end
        MOVE.L  A0,-(SP)                        | pZone = start
        MOVE.L  A0,(ApplZone).w                 | set ApplZone global
        MOVE.L  A7,A0                           | A0 points to parameters on stack
        _InitZone                               | initialize application zone
        ADDA    #0xE,SP                         | pop parameters
        MOVE.L  (TheZone).w,A6                  | get current zone
        MOVE.L  (A6),(HeapEnd).w                | set heap end global
        MOVEQ.L #0x0,D0                         | clear error
        MOVE    D0,(MemErr).w                   | clear MemErr global
        MOVE.L  (SP)+,A6                        | restore A6
        RTS                                     | return from SETAPPBASE_CONT

| ----------------------------------------------------------
|
| _InitApplZone ($A02C)
|
| Called during boot.
InitApplZone:
        MOVE.L  (IAZNotify).w,D0                | get notification hook
        BLE.B   INITAPPLZONE_SKIP               | if none, skip
        MOVE.L  D0,A0                           | A0 = hook address
        JSR     (A0)                            | call notification hook
INITAPPLZONE_SKIP:
        MOVE    #-0x1,(WWExist).w               | reset Window Manager global
        CLR.L   (MenuList).w                    | reset Menu Manager global
        CLR.L   (LastFOND).w                    | reset Font Manager global
        MOVE    #-0x1,(FONDID).w                | reset Font Manager global
        ST.B    (SEvtEnb).w                     | enable System Event Manager
        MOVEQ.L #0x1F,D0                        | set up loop for 64 bytes
INITAPPLZONE_LOOP:
        CLR     -(SP)                           | clear parameter block on stack
        DBF     D0,INITAPPLZONE_LOOP            | loop
        MOVE.L  A7,A0                           | A0 = parameter block
        MOVE.L  (VCBQHdr_Head).w,D0             | D0 = first VCB
INITAPPLZONE_LOOP_2:
        BEQ.B   INITAPPLZONE_DONE               | end of queue -> done
        MOVE.L  D0,A1                           | A1 = current VCB
        MOVE    0x48(A1),fLeading(A0)           | set ioVRefNum
        BEQ.B   INITAPPLZONE_SKIP_2             | if 0, skip
        _FlushVol                               | flush volume
INITAPPLZONE_SKIP_2:
        MOVE.L  (A1),D0                         | next VCB
        BRA.B   INITAPPLZONE_LOOP_2             | loop

| ----------------------------------------------------------
|
| INITAPPLZONE_DONE
|
| Called during boot.
INITAPPLZONE_DONE:
        ADDA    #0x40,SP                        | pop parameter block
        BSR     SETAPPBASE_CONT                 | re-initialize application zone
        _InitAllPacks                           | initialize packages
        MOVEQ.L #0x0,D0                         | return noErr
        MOVE    D0,(MemErr).w                   | clear MemErr
        RTS                                     | return from InitApplZone

| ROM section: src/os/memory_mgr.asm
| Called during boot.
| _InitZone ($A019): initialize a heap zone from parameter block
| A0 = ptr to: startPtr, limitPtr, cMoreMasters, pGrowZone
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
        DBF     D1,INITZONE_LOOP                | loop 13 longwords
| set zone limit (bkLim)
        MOVE.L  (A1)+,D1                        | D1 = limitPtr from params
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit address
        MOVE.L  D1,A3                           | A3 = zone limit
| update HighHeapMark if this zone extends higher
        CMPA.L  (HighHeapMark).w,A3             | past current high water mark?
        BLT.B   INITZONE_ERR                    | no ->
        MOVE.L  A7,D1                           | D1 = current stack pointer
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit
        CMPA.L  D1,A3                           | zone limit above stack?
        BGT.B   INITZONE_ERR                    | yes, don't update (bad limit) ->
        MOVE.L  A3,(HighHeapMark).w             | update high water mark
| create the trailing free block (sentinel) at end of zone
INITZONE_ERR:
        MOVEQ.L #0xC,D1                         | sentinel block size = 12 bytes
        SUBA.L  D1,A3                           | A3 = sentinel block address
        MOVE.L  D1,(A3)                         | set sentinel block size
        MOVE.L  A3,(A2)+                        | zone.bkLim = sentinel address
| initialize zone header fields
        MOVE.L  A0,(A2)+                        | zone.hFstFree = first free block (after header)
        ADDQ.W  #0x4,A2                         | skip zone.purgePtr
        SUBA.L  A0,A3                           | A3 = free space bytes
        MOVE.L  A3,D0                           | D0 = free space count
        MOVE.L  D0,(A2)+                        | zone.zcbFree = total free space
        MOVE    (A1)+,D1                        | D1 = cMoreMasters from params
        MOVE.L  (A1)+,(A2)+                     | zone.pGrowZone = grow zone proc
        LEA.L   StdGZ(PC),A1                    | default grow zone function
        MOVE.L  A1,0x18(A2)                     | zone.purgeProc = StdGZ
        MOVE    D1,(A2)+                        | zone.moreMast = master pointer count
        MOVE    (MMDefFlags).w,(A2)+            | zone.flags = default flags
| create the initial free block and master pointer block
        JSR     MakeBKF(PC)                     | make the big free block
        JSR     HMakeMoreMasters(PC)            | allocate initial master pointers
        MOVEM.L (SP)+,A2-A3/A6                  | restore registers
INITZONE_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
        MOVE    D0,(MemErr).w                   | clear MemErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Get Back Color
|
GetBackColor:
        MOVE.L  (TheZone).w,A0                  | A0 = current zone pointer (return value)
        BRA.B   INITZONE_EXIT                   | -> return noErr

| ----------------------------------------------------------
|
| Get C Cursor
|
GetCCursor:
        MOVE.L  A0,(TheZone).w                  | set current zone to A0
        BRA.B   INITZONE_EXIT                   | -> return noErr

| ----------------------------------------------------------
|
| _MaxBlock ($A061)
| -> D0.L = largest contiguous free block
|
MaxBlock:
        MOVE.L  #0x800000,D0                    | D0 = max possible (request full compact)
        JSR     MMPrologue(PC)                  | set up zone, save regs
        MOVEQ.L #0x1,D1                         | D1 = 1: return largest block
        BRA.B   USERDELAY_CONT                  | -> compact and measure

| ----------------------------------------------------------
|
| User Delay
|
UserDelay:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        MOVEQ.L #0x0,D1                         | D1 = 0: don't return largest block
USERDELAY_CONT:
        JSR     Actuals(PC)                     | round D0 to actual block size
        LEA.L   0x16(A6),A1                     | A1 = ptr to zone.flags
        MOVE.B  (A1),D2                         | D2 = save original flags
        TST.B   D1                              | return largest block?
        BNE.B   USERDELAY_NO                    | no -> set favor-contiguous flag
        BSET    #0x4,(A1)                       | set favor-contiguous bit (bit 4)
        BRA.B   USERDELAY_CONT_2                | -> compact heap

| ----------------------------------------------------------
|
| USERDELAY_NO
|
USERDELAY_NO:
        BClr    #0x4,(A1)                       | clear favor-contiguous bit
USERDELAY_CONT_2:
        JSR     CompactHp(PC)                   | compact the heap
        MOVE.B  D2,(A1)                         | restore original flags
        MOVE.L  D1,D0                           | D0 = largest free block size
        BEQ.B   PURGEMEM_ERR                    | no free block found?
        SUBQ.L  #0x8,D0                         | subtract 8-byte header from usable size
        MOVE.L  A0,D1                           | any free block found?
        BEQ.B   PURGEMEM_ERR                    | no -> return zero
        BRA.B   PURGEMEM_EXIT_2                 | -> return size

| ----------------------------------------------------------
|
| _PurgeMem ($A04D)
| D0.L = needed -> (purges until space available)
|
| Called during boot.
PurgeMem:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        JSR     Actuals(PC)                     | round D0 to actual block size
        JSR     PurgeHeap(PC)                   | purge blocks until D0 bytes available
PURGEMEM_CONT:
        MOVE.L  A0,D0                           | A0 = free block found?
        BNE.B   PURGEMEM_EXIT                   | yes -> return success
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
        BRA.B   PURGEMEM_ERR                    | -> return error

| ----------------------------------------------------------
|
| PURGEMEM_EXIT
|
| Called during boot.
PURGEMEM_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
PURGEMEM_EXIT_2:
        ADDQ.L  #0x8,A0                         | A0 = block data (skip 8-byte header)
PURGEMEM_ERR:
        JMP     MMEpilogue(PC)                  | restore regs and return

| PurgeSpace -- trap handler at selector $A062.
| ----------------------------------------------------------
|
| Purge Space
|
PurgeSpace:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        JSR     TotEPurgeables(PC)              | D0 = total, A0 = largest purgeable
        BRA.B   PURGEMEM_ERR                    | -> return via epilogue

| ----------------------------------------------------------
|
| _FreeMem ($A01C)
| -> D0.L = total free bytes
|
FreeMem:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        MOVE.L  0xC(A6),D0                      | D0 = zone.zcbFree (total free bytes)
        BRA.B   PURGEMEM_ERR                    | -> return via epilogue

| ----------------------------------------------------------
|
| _ResrvMem ($A040)
| D0.L = needed -> (reserves space)
|
| Called during boot.
ResrvMem:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        TST.L   0x8(A6)                         | zone.hFstFree = nil? (no master ptrs)
        BNE.B   RESRVMEM_SKIP                   | has master ptrs -> skip adjustment
        MOVE    0x14(A6),D2                     | D2 = zone.moreMast count
        EXT.L   D2                              | sign-extend to long
        ASL.L   #0x2,D2                         | * 4 = bytes for master pointers
        ADDQ.L  #0x8,D2                         | + 8 for block header
        ADD.L   D2,D0                           | add master ptr space to request
RESRVMEM_SKIP:
        JSR     MakePtrSpc(PC)                  | compact/purge to make ptr-sized space
        MOVE.L  A2,A0                           | A0 = free block found
        BRA.B   PURGEMEM_CONT                   | -> check result

| ----------------------------------------------------------
|
| Alloc Cursor
|
AllocCursor:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        MOVE.L  #0x800000,D0                    | D0 = max possible (compact fully)
        MOVEQ.L #0x0,D2                         | D2 = 0: don't try grow zone
        JSR     BKCompacts(PC)                  | compact heap and measure
        MOVE.L  D1,D0                           | D0 = largest free block
        BEQ.B   ALLOCCURSOR_CONT                | any free space?
        SUBQ.L  #0x8,D0                         | subtract 8-byte block header
ALLOCCURSOR_CONT:
        SUBA.L  A0,A0                           | A0 = nil (no grow info)
        MOVE.L  (ApplZone).w,A1                 | A1 = application zone
        CMPA.L  (TheZone).w,A1                  | is this the app zone?
        BNE.B   ALLOCCURSOR_SKIP                | no -> skip grow calculation
        MOVE.L  (ApplLimit).w,D2                | D2 = application heap limit
        JSR     MaxLimit(PC)                    | compute max growable limit
        SUB.L   (HeapEnd).w,D1                  | D1 -= current heap end
        MOVE.L  D1,A0                           | A0 = growable bytes (returned)
ALLOCCURSOR_SKIP:
        JMP     MMEpilogue(PC)                  | -> return via epilogue

| ----------------------------------------------------------
|
| _SetGrowZone ($A04B)
| A0 = proc -> (installs grow-zone function)
|
| Called during boot.
SetGrowZone:
        MOVE.L  (TheZone).w,A1                  | A1 = current zone
        MOVE.L  A0,0x10(A1)                     | install grow-zone proc at offset 16
        BRA.B   SETAPPLLIMIT_EXIT               | -> return noErr

| ----------------------------------------------------------
|
| _SetApplLimit ($A02D)
| A0 = limit -> (sets application heap limit)
|
| Called during boot.
SetApplLimit:
        MOVE.L  A0,D0                           | D0 = new limit
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        MOVE.L  D0,A0                           | A0 = masked limit
        MOVE.L  A0,(ApplLimit).w                | store new application limit
        MOVE.L  A0,(HighHeapMark).w             | update high heap mark
        MOVE.L  (ApplZone).w,A1                 | A1 = application zone
        MOVE.L  (A1),A1                         | A1 = zone.bkLim (end of zone)
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
        CMPA.L  A0,A1                           | bkLim past new limit?
        BHI.B   SETAPPLLIMIT_EXIT_2             | no -> return noErr
SETAPPLLIMIT_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
SETAPPLLIMIT_EXIT_2:
        MOVE    D0,(MemErr).w                   | set MemErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _StackSpace ($A065)
| -> D0.L = bytes between SP and heap end
|
StackSpace:
        MOVEQ.L #0x18,D0                        | D0 = 24 (skip 6 saved regs on stack)
        ADD.L   A7,D0                           | D0 = SP + 24 (adjusted stack pointer)
        MOVE.L  (ApplZone).w,A0                 | A0 = application zone
        SUB.L   (A0),D0                         | D0 = SP - bkLim = free stack space
        CLR     (MemErr).w                      | clear MemErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _MaxApplZone ($A063)
| -> (grows app zone to maximum)
|
MaxApplZone:
        MOVE.L  (ApplLimit).w,D0                | D0 = application heap limit
        MOVE.L  D0,D1                           | D1 = save limit
        LEA.L   (HeapEnd).w,A1                  | A1 -> HeapEnd low-memory global
        SUB.L   (A1),D0                         | D0 = limit - current heap end
        MOVEQ.L #0xC,D2                         | D2 = 12 (minimum block size)
        CMP.L   D2,D0                           | enough room for a block?
        BCS.B   MAXAPPLZONE_SKIP                | no -> skip
        MOVE.L  (A1),A0                         | A0 = old heap end (sentinel block)
        MOVE.L  D0,(A0)                         | expand sentinel to fill gap
        MOVE.L  D1,(A1)                         | update HeapEnd to new limit
        MOVE.L  D1,A0                           | A0 = new limit address
        MOVE.L  (ApplZone).w,A1                 | A1 = application zone header
        MOVE.L  A0,(A1)                         | update zone.bkLim to new sentinel
        MOVE.L  D2,(A0)                         | write sentinel block (12-byte free)
        ADD.L   D0,0xC(A1)                      | add expansion to zone.zcbFree
MAXAPPLZONE_SKIP:
        BRA.B   SETAPPLLIMIT_EXIT               | -> return noErr

| ----------------------------------------------------------
|
| Get C Icon
|
| Called during boot.
GetCIcon:
        JSR     MMPrologue(PC)                  | set up zone, save regs
        SUBA.L  A1,A1                           | A1 = nil (non-relocatable block)
        JSR     MakePtrSpc(PC)                  | compact/purge to make space
        JSR     AllocBK(PC)                     | allocate block of D0 bytes
        BEQ.B   GETCICON_ERR_2                  | failed -> return memFullErr
        BSR.B   PTRZONE_CONT                    | optionally clear block (trap bit 9)
GETCICON_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
GETCICON_ERR:
        JMP     MMEpilogue(PC)                  | restore and return

| ----------------------------------------------------------
|
| GETCICON_ERR_2
|
GETCICON_ERR_2:
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
        BRA.B   GETCICON_ERR                    | -> return error

| ----------------------------------------------------------
|
| Dispos Ptr
|
| Called during boot.
DisposPtr:
        JSR     MMPPrologue(PC)                 | dereference ptr, validate zone
DISPOSPTR_CONT:
        BTst    #0x0,0x16(A6)                   | zone read-only? (flags bit 0)
        BNE.B   DISPOSPTR_EXIT                  | yes -> return memROZErr
        JSR     FreeBk(PC)                      | free the block
        BRA.B   GETCICON_EXIT                   | -> return noErr

| ----------------------------------------------------------
|
| DISPOSPTR_EXIT
|
DISPOSPTR_EXIT:
        MOVEQ.L #-0x63,D0                       | memROZErr (-99): read-only zone
        BRA.B   GETCICON_ERR                    | -> return error

| ----------------------------------------------------------
|
| _GetPtrSize ($A021)
| A0 = ptr -> D0.L = size
|
GetPtrSize:
        JSR     MMPPrologue(PC)                 | dereference ptr, validate zone
        JSR     GetSize(PC)                     | D0 = logical size (phys - header - correction)
        BRA.B   GETCICON_ERR                    | -> return via epilogue

| ----------------------------------------------------------
|
| _SetPtrSize ($A020)
| A0 = ptr, D0.L = newSize -> D0 = error
|
| Called during boot.
SetPtrSize:
        JSR     MMPPrologue(PC)                 | dereference ptr, validate zone
        JSR     SetSize(PC)                     | resize block in place or relocate
        BRA.B   GETCICON_ERR                    | -> return via epilogue

| PtrZone -- trap handler at selector $A048.
| ----------------------------------------------------------
|
| Ptr Zone
|
PtrZone:
        JSR     MMPPrologue(PC)                 | dereference ptr, find its zone
        MOVE.L  A6,A0                           | A0 = zone (found by DEREFHANDLE_CONT)
        BRA.B   GETCICON_EXIT                   | -> return noErr

| ----------------------------------------------------------
|
| PTRZONE_CONT
|
| PTRZONE_CONT: optionally clear allocated block (if _NewHandleClear/_NewPtrClear)
| Trap bit 9 = clear flag; D0 = block size, A0 = block start
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
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _NewEmptyHandle ($A066): allocate a master pointer with nil handle
|
NewEmptyHandle:
        JSR     MMPrologue(PC)                  | set up TheZone, save regs
        JSR     NextMaster(PC)                  | get free master pointer -> A1
        BEQ.B   HILITECOLOR_EMPTY               | none available ->
        MOVE.L  A1,A0                           | A0 = handle (master pointer)
        CLR.L   (A0)                            | set master pointer to nil
        MOVEQ.L #0x0,D0                         | noErr
        JMP     MMEpilogue(PC)                  | restore and return

| ----------------------------------------------------------
|
| _NewHandle ($A022/$A122/$A322/$A522/$A622/$A722):
| allocate relocatable block, return handle in A0
| D0 = requested size
|
HiliteColor:
        JSR     MMPrologue(PC)                  | set up TheZone, save regs
        JSR     NextMaster(PC)                  | allocate master pointer -> A1
        BNE.B   NEWHANDLE                       | got one ->
HILITECOLOR_EMPTY:
        MOVEQ.L #-0x6C,D0                       | memFullErr
        BRA.B   CHAREXTRA_EXIT                  | -> return nil handle

| ----------------------------------------------------------
|
| NewHandle: allocate the block
|
NEWHANDLE:
        JSR     AllocBK(PC)                     | allocate block of D0 bytes -> A0
        BEQ.B   NEWHANDLE_2                     | failed ->
HILITECOLOR_CONT:
        BSR.B   PTRZONE_CONT                    | optionally clear block (trap bit 9)
        MOVE.L  A1,A0                           | A0 = handle (master pointer address)
HILITECOLOR_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
HILITECOLOR_EXIT_2:
        JMP     MMEpilogue(PC)                  | restore and return

| ----------------------------------------------------------
|
| NewHandle: allocation failed
|
NEWHANDLE_2:
        MOVEQ.L #-0x6C,D0                       | memFullErr
        BRA.B   CHAREXTRA_CONT                  | -> release master pointer

| ----------------------------------------------------------
|
| _NewPtr ($A01E/$A11E/$A31E/$A51E/$A61E/$A71E):
| allocate non-relocatable block, return pointer in A0
| D0 = requested size
|
CharExtra:
        JSR     MMHPrologue(PC)                 | set up TheZone, get handle if needed
  .short 0x6680                                 | BNE.B DISPOSPTR_CONT
        MOVE.L  A1,D0                           | D0 = requested size
        BEQ.B   CHAREXTRA_EXIT                  | zero size -> return nil
        BTST    #0x0,0x16(A6)                   | zone locked?
        BNE.B   NEWPTR                          | yes -> allocate without compacting
        MOVEQ.L #0x0,D0                         | noErr (already allocated via MMHPrologue)
CHAREXTRA_CONT:
        JSR     ReleaseMP(PC)                   | release master pointer on failure
CHAREXTRA_EXIT:
        SUBA.L  A0,A0                           | A0 = nil (no block allocated)
        BRA.B   HILITECOLOR_EXIT_2              | -> return

| ----------------------------------------------------------
|
| NewPtr: zone locked, allocate directly
|
NEWPTR:
        CLR.L   (A1)                            | clear master pointer (block at A0)
        BRA.B   HILITECOLOR_EXIT                | -> return success

| ----------------------------------------------------------
|
| Dispose C Icon
|
| _GetHandleSize ($A025): return size of handle's block in D0
DisposeCIcon:
        JSR     MMHPrologue(PC)                 | dereference handle -> A0=block, A1=master ptr
        BEQ.B   DISPOSECTABLE_EMPTY             | nil/empty handle ->
        JSR     GetSize(PC)                     | D0 = block size (from block header)
        BRA.B   DISPOSECTABLE_ERR               | -> return

| ----------------------------------------------------------
|
| _SetHandleSize ($A024): resize handle's block
| D0 = new size, A0 = handle
|
DisposeCTable:
        JSR     MMHPrologue(PC)                 | dereference handle
        BNE.B   SETHANDLESIZE                   | block exists ->
DISPOSECTABLE_EMPTY:
        MOVEQ.L #-0x6D,D0                       | nilHandleErr
        BRA.B   DISPOSECTABLE_ERR               | -> return error

| ----------------------------------------------------------
|
| SetHandleSize: do the resize
|
SETHANDLESIZE:
        JSR     SetSize(PC)                     | resize block (may move it)
DISPOSECTABLE_ERR:
        MOVE.L  A1,A0                           | A0 = handle (for caller)
        BRA.B   HILITECOLOR_EXIT_2              | -> epilogue

| ----------------------------------------------------------
|
| _HandleZone ($A126): return zone containing handle's block
| A0 = handle -> A0 = zone pointer
|
HandleZone:
        JSR     MMHPrologue(PC)                 | dereference, find zone -> A6
        MOVE.L  A6,A0                           | A0 = zone pointer
        BRA.B   HILITECOLOR_EXIT                | -> return noErr

| ----------------------------------------------------------
|
| _RecoverHandle ($A128): given a pointer, find its handle
| A0 = pointer -> A0 = handle
|
RecoverHandle:
        JSR     MMPrologue(PC)                  | set up zone
        MOVE.L  -0x4(A0),A1                     | get relative handle from block header
        ADDA.L  A6,A1                           | A1 = absolute master pointer address
| verify the master pointer actually points back to this block
        MOVE.L  (A1),D2                         | D2 = master pointer contents
        AND.L   (Lo3Bytes).w,D2                 | mask to 24-bit address
        MOVE.L  A0,D1                           | D1 = original pointer
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit
        SUB.L   D1,D2                           | should be zero if valid
        BEQ.B   RECOVERHANDLE_FOUND             | matches ->
        MOVEQ.L #-0x73,D2                       | memAdrErr: bad address
RECOVERHANDLE_FOUND:
        MOVE    D2,(MemErr).w                   | set MemErr
        MOVE.L  A1,A0                           | A0 = handle
        JMP     L_mMMNoErrEpilogue(PC)          | return (error already in MemErr)

| ----------------------------------------------------------
|
| _EmptyHandle ($A02B)
| A0 = handle -> (master ptr set to NIL)
|
| Called during boot.
EmptyHandle:
        JSR     MMHPrologue(PC)                 | dereference handle -> A0=block, A1=MP
        BNE.B   EMPTYHANDLE_CONT                | block exists -> release it
        MOVEQ.L #0x0,D0                         | already empty: noErr
        BRA.B   EMPTYHANDLE_EXIT                | -> return

| ----------------------------------------------------------
|
| EMPTYHANDLE_CONT
|
| Called during boot.
EMPTYHANDLE_CONT:
        JSR     EH(PC)                          | release block, clear master pointer
EMPTYHANDLE_EXIT:
        BRA.B   DISPOSECTABLE_ERR               | -> return via SetHandleSize epilogue

| ----------------------------------------------------------
|
| _ReallocHandle ($A027)
| A0 = handle, D0.L = size -> (reallocated)
|
| Called during boot.
ReallocHandle:
        JSR     MMHPrologue(PC)                 | dereference handle -> A0=block, A1=MP
        TST.L   (A1)                            | is master pointer nil?
        BEQ.B   REALLOCHANDLE_OK                | yes -> allocate new block
        BTST    #0x0,0x16(A6)                   | zone read-only? (flags bit 0)
        BNE.B   REALLOCHANDLE_ERR               | yes -> return error
        JSR     EH(PC)                          | release existing block
        BNE.B   DISPOSECTABLE_ERR               | error? -> return
        MOVE.L  D2,D0                           | D0 = original requested size
REALLOCHANDLE_OK:
        MOVE.L  A1,(GZRootHnd).w                | protect handle from grow-zone purging
        CLR.L   (GZRootPtr).w                   | clear root ptr (handle-based alloc)
        JSR     AllocBK(PC)                     | allocate new block
        JSR     ClearGZStuff(PC)                | clear grow-zone protection
        MOVE.L  A0,D2                           | D2 = block address
        BNE     HILITECOLOR_CONT                | success -> link to master ptr
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
        BRA.B   DISPOSECTABLE_ERR               | -> return error

| ----------------------------------------------------------
|
| REALLOCHANDLE_ERR
|
REALLOCHANDLE_ERR:
        JSR     GetSize(PC)                     | get current block size
        CMP.L   D0,D2                           | compare with requested size
        BHI.B   REALLOCHANDLE_ERR_2             | requested > current -> error
        MOVEQ.L #-0x63,D0                       | memROZErr (-99)
  .short 0x6080                                 | Bra.B DISPOSECTABLE_ERR
REALLOCHANDLE_ERR_2:
        MOVEQ.L #-0x63,D0                       | memROZErr (-99)
        BRA     DISPOSECTABLE_ERR               | -> return error

| ----------------------------------------------------------
|
| Get Device List
|
| Called during boot (5,560 times in 30s trace).
GetDeviceList:
        BSR.B   HNOPURGE_CONT                   | validate handle -> A1 = master ptr
        BEQ.B   HNOPURGE_EXIT_2                 | nil -> return nilHandleErr
        BSET    #0x7,(A1)                       | set lock bit (bit 7) in MP flags
        BRA.B   HNOPURGE_EXIT                   | -> return noErr

| ----------------------------------------------------------
|
| Component Dispatch
|
| Called during boot.
ComponentDispatch:
        BSR.B   HNOPURGE_CONT                   | validate handle -> A1 = master ptr
        BEQ.B   HNOPURGE_EXIT_2                 | nil -> return nilHandleErr
        BCLR    #0x7,(A1)                       | clear lock bit (bit 7) in MP flags
        BRA.B   HNOPURGE_EXIT                   | -> return noErr

| ----------------------------------------------------------
|
| _HPurge ($A049)
| A0 = handle -> (purgeable)
|
| Called during boot.
HPurge:
        BSR.B   HNOPURGE_CONT                   | validate handle -> A1 = master ptr
        BEQ.B   HNOPURGE_EXIT_2                 | nil -> return nilHandleErr
        BSET    #0x6,(A1)                       | set purge bit (bit 6) in MP flags
        BRA.B   HNOPURGE_EXIT                   | -> return noErr

| ----------------------------------------------------------
|
| _HNoPurge ($A04A)
| A0 = handle -> (not purgeable)
|
| Called during boot.
HNoPurge:
        BSR.B   HNOPURGE_CONT                   | validate handle -> A1 = master ptr
        BEQ.B   HNOPURGE_EXIT_2                 | nil -> return nilHandleErr
        BCLR    #0x6,(A1)                       | clear purge bit (bit 6) in MP flags
HNOPURGE_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
        BRA.B   HNOPURGE_EXIT_3                 | -> store MemErr and return

| ----------------------------------------------------------
|
| HNOPURGE_EXIT_2
|
| Called during boot.
HNOPURGE_EXIT_2:
        MOVEQ.L #-0x6D,D0                       | nilHandleErr (-109)
HNOPURGE_EXIT_3:
        MOVE    D0,(MemErr).w                   | store error code in MemErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| HNOPURGE_CONT
|
| HNOPURGE_CONT: validate handle for HLock/HUnlock/HPurge/HNoPurge
| A0 = handle -> A1 = master pointer address, Z set if nil
HNOPURGE_CONT:
        MOVE.L  A0,D0                           | get handle
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit
        BNE.B   HNOPURGE_EMPTY                  | non-nil ->
        ADDQ.L  #0x4,SP                         | nil handle: pop return address
        RTS                                     | return to caller's caller (skip)
| handle is valid
HNOPURGE_EMPTY:
        MOVE.L  D0,A1                           | A1 = master pointer address
        MOVE.L  (A1),D0                         | D0 = master pointer contents
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _MoreMasters ($A036)
| -> (allocates 32 more master pointers)
|
| Called during boot.
MoreMasters:
        MOVE.L  A6,-(SP)                        | save A6 (zone pointer)
        MOVE.L  (TheZone).w,A6                  | A6 = current zone
        MOVEQ.L #0x0,D0                         | D0 = 0 (no error yet)
        JSR     HMakeMoreMasters(PC)            | allocate more master pointers
        BNE.B   MOREMASTERS_SKIP                | success? -> skip
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
MOREMASTERS_SKIP:
        MOVE.L  (SP)+,A6                        | restore A6
        MOVE    D0,(MemErr).w                   | set MemErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _MoveHHi ($A064)
| A0 = handle -> (moved to top of heap)
|
| Called during boot (3,693 times in 30s trace).
| _MoveHHi ($A064): move relocatable block to top of heap
MoveHHi:
        JSR     MMHPrologue(PC)                 | dereference handle -> A0=block, A1=master ptr
        BNE.B   MOVEHHI_CONT                    | block exists ->
        MOVEQ.L #-0x6D,D0                       | nilHandleErr
MOVEHHI_ERR:
        JMP     MMEpilogue(PC)                  | return with error in D0
| check if block is locked (can't move locked blocks)
MOVEHHI_CONT:
        MOVE.L  A1,A4                           | A4 = save master pointer
        TST.B   (A4)                            | check lock bit (bit 7 of MP flags)
        BPL.B   MOVEHHI_NO                      | not locked ->
        MOVEQ.L #-0x75,D0                       | memLockedErr
        BRA.B   MOVEHHI_ERR                     | -> return error
| scan from block to bkLim, measuring free space above
MOVEHHI_NO:
        MOVE.L  (A6),A3                         | A3 = bkLim (zone end sentinel)
        SUBQ.L  #0x8,A0                         | back up to block header
        MOVE.L  (A0),D1                         | D1 = block size (from header)
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit size
        MOVE.L  D1,D7                           | D7 = data size (block - 8 header)
        SUBQ.L  #0x8,D7                         | subtract 8-byte block header
        MOVEQ.L #0x0,D0                         | D0 = accumulated free space above
        ADDA.L  D1,A0                           | A0 = next block after ours
        CMPA.L  A3,A0                           | at zone end?
        BCC     MOVEHHI_EXIT                    | yes, already at top ->
        TST.B   (A0)                            | next block free? (tag byte 0)
        BEQ.B   MOVEHHI_OK                      | yes ->
        BPL     MOVEHHI_EXIT                    | next is non-reloc? -> can't move past
        MOVE.L  0x4(A0),A0                      | get relHandle of next block
        ADDA.L  A6,A0                           | A0 = master pointer of next block
        TST.B   (A0)                            | next block locked?
        BMI     MOVEHHI_EXIT                    | yes -> can't move past locked block
MOVEHHI_OK:
        MOVE.L  A7,D1                           | D1 = current stack pointer
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit
        SUB.L   (HighHeapMark).w,D1             | D1 = stack - high heap mark = available
        MOVE.L  #0x400,D2                       | D2 = 0x400 (1KB minimum stack buffer)
        MOVE.L  D2,D0                           | D0 = stack buffer
        ADD.L   D7,D0                           | D0 = buffer + data size needed
        CMP.L   D0,D1                           | enough stack space?
        BLT.B   MOVEHHI_NO_2                    | no -> use available amount
        MOVE.L  D0,D1                           | D1 = capped to needed amount
MOVEHHI_NO_2:
        MOVEQ.L #-0x1,D0                        | D0 = -1 (flag: using stack approach)
        CMP.L   D2,D1                           | enough stack for minimum buffer?
        BLT     MOVEHHI_EXIT                    | no -> can't move, exit
        SUBI.L  #0x80,D2                        | subtract safety margin
        SUB.L   D2,D1                           | D1 = usable stack buffer size
        SUBA.L  D1,SP                           | allocate stack buffer
        SUBA    #0x12,SP                        | align stack frame
        MOVE.L  A7,A5                           | A5 = stack frame base
        MOVE.L  D1,0x8(A5)                      | frame+8 = buffer size
        MOVE.L  (A4),A0                         | A0 = block data pointer
        SUBQ.W  #0x8,A0                         | back up to block header
        MOVE.L  (A0),(A5)                       | frame+0 = block header word 0
        MOVE.L  (A4),D0                         | D0 = master pointer contents
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        MOVE.L  D0,0xC(A5)                      | frame+12 = block data address
        MOVE.B  (A4),0x10(A5)                   | frame+16 = MP flags byte
        BSR     MOVEHHI_CONT_5                  | find free block above our block
        TST.B   (A2)                            | is it free? (tag byte = 0)
        BNE.B   MOVEHHI_NO_3                    | no -> need compaction approach
        MOVE.L  (A2),D1                         | D1 = free block size
        MOVE.L  D1,D0                           | D0 = free size
        SUBQ.L  #0x8,D0                         | subtract header
        CMP.L   D0,D7                           | enough room for data?
        BHI.B   MOVEHHI_NO_3                    | no -> need compaction
        SUB.L   D7,D0                           | D0 = leftover after data
        BEQ.B   MOVEHHI_CONT_2                  | exact fit?
        MOVEQ.L #0xC,D2                         | D2 = 12 (min block size)
        CMP.L   D2,D0                           | leftover < min block? -> can't split
        BCS.B   MOVEHHI_NO_3                    | leftover < min? -> use compaction
MOVEHHI_CONT_2:
        MOVE.L  (A4),A0                         | restore from master pointer
        MOVE.L  A2,A1                           | A1 = end of free block
        ADDA.L  D1,A1                           | A1 = end of free block
MOVEHHI_CONT_3:
        MOVE.L  D7,D0                           | A1 = destination (end - size)
        SUBA.L  D0,A1                           | subtract moved bytes from zcbFree
        SUB.L   D0,0xC(A6)                      | subtract data size from zcbFree
        _BlockMove                              | copy block data to new location
        MOVE.L  A4,A0                           | A0 = handle
        _EmptyHandle                            | release old block (sets MP to nil)
        BRA.B   MOVEHHI_OK_2                    | -> finalize new block

| ----------------------------------------------------------
|
| MOVEHHI_NO_3
|
MOVEHHI_NO_3:
        MOVEQ.L #0x0,D6                         | D6 = 0: total bytes moved so far
        BSR     MOVEHHI_CONT_6                  | copy chunk to stack buffer
        BSR     MOVEHHI_CONT_8                  | compact heap
        BSR     MOVEHHI_CONT_5                  | find free block at top
MOVEHHI_NEXT:
        MOVE.L  (A2),D1                         | D1 = free block size
        MOVE.L  0x4(A5),D0                      | D0 = chunk size from frame
        LEA.L   0x12(A5),A0                     | A0 = stack buffer data
        MOVE.L  A2,A1                           | A1 = end of free block
        ADDA.L  D1,A1                           | A1 = free block end
        SUBA.L  D0,A1                           | A1 = destination (end - chunk)
        ADD.L   D0,D6                           | accumulate total moved
        SUB.L   D0,0xC(A6)                      | subtract from zcbFree
        _BlockMove                              | copy chunk from stack to heap
        TST.L   D7                              | all data moved?
        BEQ.B   MOVEHHI_OK_2                    | yes -> finalize
        MOVE.L  A1,D0                           | D0 = remaining free space
        SUB.L   A2,D0                           | D0 = free - used = leftover
        BEQ.B   MOVEHHI_NEXT_2                  | no leftover -> direct copy next chunk
        MOVE.L  D0,D1                           | D0 = leftover
        SUBQ.L  #0x8,D1                         | subtract header
        SUB.L   D7,D1                           | D1 = leftover - data remaining
        BCS.B   MOVEHHI_NO_4                    | not enough room -> mark as used
        BEQ.B   MOVEHHI_CONT_4                  | exact fit?
        MOVEQ.L #0xC,D2                         | D2 = 12 (min block size)
        CMP.L   D1,D2                           | leftover too small to split? -> mark
        BCS.B   MOVEHHI_NO_4                    | too small to split -> mark as used
MOVEHHI_CONT_4:
        MOVE.L  (A4),A0                         | restore from MP
        BRA.B   MOVEHHI_CONT_3                  | -> direct move into free space

| ----------------------------------------------------------
|
| MOVEHHI_NO_4
|
MOVEHHI_NO_4:
        MOVE.L  D0,(A2)                         | set free block to leftover size
MOVEHHI_NEXT_2:
        MOVEM.L (A1),D4-D5                      | save 8 bytes of data being overwritten
        MOVE.L  A6,0x4(A1)                      | set relHandle = zone base (non-reloc)
        MOVE.L  D6,(A1)                         | total bytes moved as block size
        MOVE.B  #0x40,(A1)                      | tag = non-relocatable ($40)
        MOVE.L  A1,-(SP)                        | save temp block address
        BSR.B   MOVEHHI_CONT_6                  | copy chunk to stack buffer
        BSR     MOVEHHI_CONT_8                  | compact heap
        BSR.B   MOVEHHI_CONT_5                  | find free block at top
        MOVE.L  (SP)+,A1                        | restore temp block address
        MOVEM.L D4-D5,(A1)                      | restore saved 8 bytes
        BRA.B   MOVEHHI_NEXT                    | -> copy next chunk from stack

| ----------------------------------------------------------
|
| MOVEHHI_OK_2
|
| Called during boot.
MOVEHHI_OK_2:
        SUBQ.L  #0x8,A1                         | back up to block header position
        SUBQ.L  #0x8,0xC(A6)                    | subtract header size from zcbFree
        MOVE.L  A1,D0                           | D0 = gap between free block and dest
        SUB.L   A2,D0                           | D0 = free space before new block
        BEQ.B   MOVEHHI_SKIP                    | no gap -> skip
        MOVE.L  D0,(A2)                         | set remaining free block size
MOVEHHI_SKIP:
        MOVE.L  A1,A2                           | A2 = new block header location
        MOVE.L  (A5),(A2)+                      | write block header word 0 (from frame)
        MOVE.L  A4,A0                           | A0 = handle address
        SUBA.L  A6,A0                           | make zone-relative
        MOVE.L  A0,(A2)+                        | write relHandle in block header
        MOVE.L  A2,(A4)                         | update master pointer to new data
        MOVE.B  0x10(A5),(A4)                   | restore MP flags from frame
        MOVEQ.L #0x0,D0                         | noErr
        ADDA.L  0x8(A5),SP                      | deallocate stack buffer
        ADDA    #0x12,SP                        | deallocate stack frame
MOVEHHI_EXIT:
        JMP     MMEpilogue(PC)                  | -> return via epilogue

| ----------------------------------------------------------
|
| MOVEHHI_CONT_5
|
| Called during boot.
MOVEHHI_CONT_5:
        MOVE.L  (A4),D0                         | D0 = master pointer contents
        BEQ.B   MOVEHHI_EMPTY                   | nil (purged) -> start from heapData
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        MOVE.L  D0,A0                           | A0 = block data pointer
        SUBQ.W  #0x8,A0                         | back up to block header
        BRA.B   MOVEHHI_NO_5                    | -> scan forward

| ----------------------------------------------------------
|
| MOVEHHI_EMPTY
|
MOVEHHI_EMPTY:
        LEA.L   0x34(A6),A0                     | A0 = zone.heapData (first block)
MOVEHHI_NO_5:
        MOVE.L  (A0),D1                         | D1 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit size
        TST.B   (A0)                            | is this block free?
        BEQ.B   MOVEHHI_OK_3                    | yes -> candidate for merge
        BPL.B   MOVEHHI_OK_4                    | non-reloc -> stop (can't move past)
        MOVE.L  0x4(A0),A1                      | get relHandle of reloc block
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        TST.B   (A1)                            | is block locked?
        BMI.B   MOVEHHI_OK_4                    | yes -> stop (can't move past locked)
MOVEHHI_OK_3:
        MOVE.L  A0,A2                           | A2 = this free/unlocked block
        ADDA.L  D1,A0                           | advance past it
        CMPA.L  A3,A0                           | past zone end?
        BCS.B   MOVEHHI_NO_5                    | no -> continue scanning
        BRA.B   MOVEHHI_DONE                    | -> done, A2 = last candidate

| ----------------------------------------------------------
|
| MOVEHHI_OK_4
|
MOVEHHI_OK_4:
        CMPA.L  0xC(A5),A0                      | past our block's original position?
        BLS.B   MOVEHHI_OK_3                    | no -> include in candidate range
MOVEHHI_DONE:
        RTS                                     | return to caller

| MOVEHHI_CONT_6 -- copy chunk to stack buffer.
| ----------------------------------------------------------
|
| MOVEHHI_CONT_6
|
MOVEHHI_CONT_6:
        MOVE.L  0x8(A5),D0                      | D0 = stack buffer size
        CMP.L   D7,D0                           | buffer >= remaining data?
        BLT.B   MOVEHHI_NO_6                    | no -> use buffer size
        MOVE.L  D7,D0                           | yes -> only copy remaining data
MOVEHHI_NO_6:
        LEA.L   0x12(A5),A1                     | A1 = stack buffer area
        MOVE.L  (A4),A0                         | A0 = block data pointer
        ADDA.L  D7,A0                           | point to end of block data
        SUBA.L  D0,A0                           | back up by chunk size (copy from end)
        SUB.L   D0,D7                           | D7 -= chunk (remaining data decreases)
        MOVE.L  D0,0x4(A5)                      | frame+4 = chunk size
        MOVE.L  D0,D1                           | D1 = byte count for BlockMove
        _BlockMove                              | copy chunk from block to stack buffer
        MOVE.L  A4,A0                           | A0 = handle
        MOVE.L  D7,D0                           | D0 = remaining data size
        BNE.B   MOVEHHI_CONT_7                  | any data left?
        _EmptyHandle                            | no -> release entire handle
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MOVEHHI_CONT_7
|
MOVEHHI_CONT_7:
        MOVE.L  (A0),A0                         | A0 = master pointer -> block data
        SUBQ.W  #0x8,A0                         | back up to block header
        MOVE.B  (A0),D2                         | D2 = save tag byte
        ADDQ.L  #0x8,D0                         | D0 = remaining + header
        MOVE.L  D0,(A0)                         | update block size in header
        MOVE.B  D2,(A0)                         | restore tag byte
        ADDA.L  D0,A0                           | A0 = end of shrunken block
        MOVE.L  D1,(A0)                         | create free block from freed tail
        ADD.L   D1,0xC(A6)                      | add freed space to zcbFree
        RTS                                     | return to caller

| MOVEHHI_CONT_8 -- compact heap.
| ----------------------------------------------------------
|
| MOVEHHI_CONT_8
|
MOVEHHI_CONT_8:
        MOVE.L  #0x800000,D0                    | D0 = max possible (compact everything)
        _CompactMem                             | call _CompactMem trap
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Deref Handle
|
| Called during boot (39,538 times in 30s trace).
DerefHandle:
        MOVE.L  A0,D0                           | D0 = handle value
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        MOVE.L  D0,A0                           | A0 = clean handle
        MOVE.L  D0,A1                           | A1 = handle (for zone lookup)
        BEQ.B   DEREFHANDLE_EXIT                | nil handle? -> return
        MOVE.L  (A1),A0                         | A0 = dereference: master ptr contents
        MOVE.L  A0,D0                           | D0 = block address (Z set if nil)
DEREFHANDLE_EXIT:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DEREFHANDLE_CONT
|
| Called during boot (39,524 times in 30s trace).
DEREFHANDLE_CONT:
        MOVE.L  A0,D0                           | D0 = pointer value
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        MOVE.L  D0,A0                           | A0 = clean pointer
        SUBQ.L  #0x8,A0                         | back up to block header
        TST.B   (A0)                            | check tag byte
        BEQ.B   DEREFHANDLE_CONT_4              | free block -> memWZErr
        BMI.B   DEREFHANDLE_CONT_2              | relocatable -> use relHandle
        MOVE.L  0x4(A0),A6                      | A6 = zone (non-reloc: header+4 = zone)
        BRA.B   DEREFHANDLE_CONT_3              | -> verify zone

| ----------------------------------------------------------
|
| DEREFHANDLE_CONT_2
|
| Called during boot (39,521 times in 30s trace).
DEREFHANDLE_CONT_2:
        MOVE.L  A1,A6                           | A6 = master pointer address
        SUBA.L  0x4(A0),A6                      | A6 -= relHandle = zone base address
DEREFHANDLE_CONT_3:
        BSR.B   DEREFHANDLE_CONT_5              | verify zone integrity
DEREFHANDLE_EXIT_2:
        ADDQ.L  #0x8,A0                         | restore A0 to block data pointer
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| DEREFHANDLE_CONT_4
|
DEREFHANDLE_CONT_4:
        MOVEQ.L #-0x6F,D0                       | memWZErr (-111): bad block in zone
        BRA.B   DEREFHANDLE_EXIT_2              | -> return with A0 at data

| ----------------------------------------------------------
|
| DEREFHANDLE_CONT_5
|
| Called during boot (54,193 times in 30s trace).
DEREFHANDLE_CONT_5:
        MOVE.L  A0,-(SP)                        | save A0 on stack
        MOVE.L  A6,D0                           | D0 = zone pointer
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit address
        MOVE.L  D0,A6                           | A6 = clean zone pointer
        MOVE.L  0x38(A6),D0                     | D0 = zone.sparePtr (self-pointer)
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit
        SUB.L   A6,D0                           | subtract zone base: should be 0
        BEQ.B   DEREFHANDLE_FOUND               | matches -> zone is valid (D0=0)
        MOVEQ.L #-0x71,D0                       | memAZErr (-113): bad zone pointer
DEREFHANDLE_FOUND:
        MOVE.L  (SP)+,A0                        | restore A0
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MMP Prologue
|
| Called during boot.
MMPPrologue:
        MOVE.L  (SP)+,A1                        | pop return address into A1
        MOVEM.L D3-D7/A2-A6,-(SP)               | save all working registers
        MOVE.L  A1,-(SP)                        | push return address back
        MOVE.L  D0,D2                           | D2 = save D0 (trap parameter)
        SUBA.L  A1,A1                           | A1 = nil (pointer, not handle)
        BSR.B   DEREFHANDLE_CONT                | validate ptr, find zone -> A6
        BMI.B   MMHPROLOGUE_ERR                 | bad zone -> abort
        MOVE.L  D2,D0                           | D0 = restore trap parameter
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MMH Prologue
|
| Called during boot (39,538 times in 30s trace).
MMHPrologue:
        MOVE.L  (SP)+,A1                        | pop return address into A1
        MOVEM.L D3-D7/A2-A6,-(SP)               | save all working registers
        MOVE.L  A1,-(SP)                        | push return address back
        MOVE.L  D0,D2                           | D2 = save D0 (trap parameter)
        MOVE.L  (TheZone).w,A6                  | A6 = current zone (default)
        BSR.B   DerefHandle                     | dereference handle -> A0, A1
        BEQ.B   MMHPROLOGUE_EMPTY               | nil handle -> try zone validation
        BSR.B   DEREFHANDLE_CONT                | validate block, find zone -> A6
MMHPROLOGUE_CONT:
        BMI.B   MMHPROLOGUE_ERR                 | bad zone -> abort
        MOVE.L  D2,D0                           | D0 = restore trap parameter
        MOVE.L  A0,D7                           | D7 = save block address
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MMHPROLOGUE_EMPTY
|
| Called during boot.
MMHPROLOGUE_EMPTY:
        BSR.B   DEREFHANDLE_CONT_5              | validate zone integrity
        BRA.B   MMHPROLOGUE_CONT                | -> check result

| ----------------------------------------------------------
|
| MMHPROLOGUE_ERR
|
MMHPROLOGUE_ERR:
        ADDQ.L  #0x4,SP                         | discard return address
        BRA.B   MMEPILOGUE_ERR                  | -> epilogue with error

| ----------------------------------------------------------
|
| MM Prologue
|
| Called during boot (14,652 times in 30s trace).
MMPrologue:
        MOVE.L  (SP)+,A1                        | pop return address into A1
        MOVEM.L D3-D7/A2-A6,-(SP)               | save all working registers
        MOVE.L  A1,-(SP)                        | push return address back
        MOVE.L  D0,D2                           | D2 = save D0 (trap parameter)
        MOVE.L  (TheZone).w,A6                  | A6 = current zone
        BTST    #0xA,D1                         | trap bit 10: sys zone flag?
        BEQ.B   MMPROLOGUE_NO                   | no -> use TheZone
        MOVE.L  (SysZone).w,A6                  | A6 = system zone
MMPROLOGUE_NO:
        BSR.B   DEREFHANDLE_CONT_5              | verify zone integrity
        BMI.B   MMHPROLOGUE_ERR                 | bad zone -> abort
        MOVE.L  D2,D0                           | D0 = restore trap parameter
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MM Epilogue
|
| Called during boot (54,190 times in 30s trace).
MMEpilogue:
        CLR     (MemErr).w                      | clear MemErr (optimistic)
        TST.L   D0                              | test error code in D0
        BGE.B   L_mMMNoErrEpilogue              | no error -> skip
MMEPILOGUE_ERR:
        MOVE    D0,(MemErr).w                   | set MemErr to error code
L_mMMNoErrEpilogue:
        MOVEM.L (SP)+,D3-D7/A2-A6               | restore all working registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Make BKF
|
| Called during boot (46,442 times in 30s trace).
MakeBKF:
        MOVE.L  D0,(A0)                         | set block size in header
        CLR.B   (A0)                            | clear tag byte (= free block)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| EH
|
| Called during boot.
EH:
        BTST    #0x7,(A1)                       | is handle locked?
        BNE.B   EH_EXIT_3                       | yes -> return memLockedErr
        BTST    #0x0,0x16(A6)                   | zone read-only? (flags bit 0)
        BNE.B   EH_OK                           | yes -> just clear MP without freeing
        SUBQ.L  #0x8,A0                         | back up to block header
        BSR.B   EH_CONT_2                       | free block, call purge proc, release MP
        ADDQ.L  #0x8,A0                         | restore to data pointer
EH_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
EH_EXIT_2:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| EH_EXIT_3
|
EH_EXIT_3:
        MOVEQ.L #-0x70,D0                       | memLockedErr (-112)
        BRA.B   EH_EXIT_2                       | -> return

| ----------------------------------------------------------
|
| EH_OK
|
EH_OK:
        CLR.L   (A1)                            | just clear master pointer (RO zone)
        BRA.B   EH_EXIT                         | -> return noErr

| ----------------------------------------------------------
|
| EH_CONT
|
| Called during boot.
EH_CONT:
        TST.L   0x28(A6)                        | zone.purgeProc installed?
        BEQ.B   EH_EXIT_4                       | no -> return
        MOVEM.L D0-D2/A0-A1,-(SP)               | save registers
        MOVE.L  A1,-(SP)                        | push handle being purged
        MOVE.L  0x28(A6),A1                     | A1 = purge warning procedure
        JSR     (A1)                            | call purge warning proc
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore registers
EH_EXIT_4:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| EH_CONT_2
|
| Called during boot.
EH_CONT_2:
        MOVE.L  D0,-(SP)                        | save D0 (caller's size)
        MOVE.L  (A0),D0                         | D0 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit = physical size
        BSR.B   EH_CONT                         | notify purge proc
        CLR.L   (A1)                            | clear master pointer (block purged)
        BSR.B   MakeBKF                         | convert to free block
        BSR     AdjustFree                      | add freed space to zcbFree
        MOVE.L  (SP)+,D0                        | restore D0
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Purge Heap
|
| Called during boot.
PurgeHeap:
        MOVEM.L D2/A1-A4,-(SP)                  | save working registers
PURGEHEAP_CONT:
        MOVE.L  (A6),A3                         | A3 = zone.bkLim (end sentinel)
        LEA.L   0x34(A6),A0                     | A0 = zone.heapData (first block)
        BTST    #0x6,0x16(A6)                   | fast-purge flag? (flags bit 6)
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
        MOVE.L  0x4(A4),A1                      | get relHandle of relocatable block
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        TST.B   (A1)                            | check MP flags: locked?
        BMI.B   PURGEHEAP_OK                    | yes -> barrier, reset count
        BTST    #0x6,(A1)                       | is handle purgeable? (bit 6)
        BEQ.B   PURGEHEAP_NO_2                  | no -> can't purge, track position
        CMPA.L  0x4(A6),A4                      | before purgePtr?
        BCS.B   PURGEHEAP_SKIP                  | yes -> skip this purgeable block
PURGEHEAP_CONT_2:
        ADD.L   D1,D2                           | add block size to accumulated free
        CMP.L   D0,D2                           | enough free space for request?
        BCS.B   PURGEHEAP_NO_2                  | no -> keep scanning
        BRA.B   PURGEHEAP_OK_3                  | yes -> start purging

| ----------------------------------------------------------
|
| PURGEHEAP_OK
|
| Called during boot.
PURGEHEAP_OK:
        MOVEQ.L #0x0,D2                         | D2 = 0: reset accumulated free
PURGEHEAP_SKIP:
        MOVE.L  A2,A0                           | A0 = next scan position
PURGEHEAP_NO_2:
        CMPA.L  A3,A2                           | past zone end?
        BCS.B   PURGEHEAP_NO                    | no -> continue scanning
        LEA.L   0x34(A6),A0                     | A0 = zone.heapData (restart scan)
        CMPA.L  0x4(A6),A0                      | purgePtr at start? (nothing to retry)
        BEQ.B   PURGEHEAP_OK_2                  | yes -> give up
        MOVE.L  A0,0x4(A6)                      | update purgePtr for next pass
        BRA.B   PURGEHEAP_CONT                  | -> rescan from beginning

| ----------------------------------------------------------
|
| PURGEHEAP_OK_2
|
| Called during boot.
PURGEHEAP_OK_2:
        MOVE.L  A3,A2                           | A2 = bkLim (purge everything to end)
PURGEHEAP_OK_3:
        MOVE.L  (A0),D1                         | D1 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit size
        TST.B   (A0)                            | is block free?
        BPL.B   PURGEHEAP_SKIP_2                | yes -> skip to next
        MOVE.L  0x4(A0),A1                      | get relHandle
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        TST.B   (A1)                            | check MP flags
        BMI.B   PURGEHEAP_SKIP_2                | locked -> skip
        BTST    #0x6,(A1)                       | purgeable? (bit 6)
        BEQ.B   PURGEHEAP_SKIP_2                | no -> skip
        BSR     EH_CONT_2                       | purge this block (free + notify)
        CMP.L   D0,D1                           | freed size >= request?
        BCC.B   PURGEHEAP_DONE                  | yes -> done purging
PURGEHEAP_SKIP_2:
        ADDA.L  D1,A0                           | advance past this block
        MOVE.L  A0,0x4(A6)                      | update purgePtr
        CMPA.L  A2,A0                           | past target?
        BCS.B   PURGEHEAP_OK_3                  | no -> continue purging
PURGEHEAP_DONE:
        BSR.B   TOTEPURGEABLES_RETRY            | compact freed space
        MOVEM.L (SP)+,D2/A1-A4                  | restore registers
        RTS                                     | return to caller

| TotEPurgeables -- d0 = total, A0 = largest purgeable.
| ----------------------------------------------------------
|
| Tot E Purgeables
|
TotEPurgeables:
        MOVEQ.L #0x0,D0                         | D0 = 0: total free+purgeable space
        MOVE.L  D0,D1                           | D1 = 0: current contiguous run
        MOVE.L  D0,A0                           | A0 = nil: largest contiguous block
        LEA.L   0x34(A6),A1                     | A1 = zone.heapData (scan start)
TOTEPURGEABLES_CONT:
        CMPA.L  (A6),A1                         | past zone end?
        BCC.B   TOTEPURGEABLES_OK_2             | yes -> finalize
        MOVE.L  (A1),D2                         | D2 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D2                 | mask to 24-bit size
        TST.B   (A1)                            | is block free?
        BEQ.B   TOTEPURGEABLES_OK               | yes -> add to run
        BPL.B   TOTEPURGEABLES_CONT_2           | non-reloc -> barrier
        MOVE.L  0x4(A1),A2                      | get relHandle
        ADDA.L  A6,A2                           | A2 = absolute master pointer
        TST.B   (A2)                            | check MP flags
        BMI.B   TOTEPURGEABLES_CONT_2           | locked -> barrier
        BTST    #0x6,(A2)                       | purgeable? (bit 6)
        BEQ.B   TOTEPURGEABLES_EXIT             | no -> barrier
TOTEPURGEABLES_OK:
        ADD.L   D2,D1                           | add block size to contiguous run
TOTEPURGEABLES_EXIT:
        ADDA.L  D2,A1                           | advance to next block
        BRA.B   TOTEPURGEABLES_CONT             | -> continue scanning

| ----------------------------------------------------------
|
| TOTEPURGEABLES_CONT_2
|
TOTEPURGEABLES_CONT_2:
        PEA.L   TOTEPURGEABLES_EXIT(PC)         | push return address (re-enter at TOTEPURGEABLES_OK_2)
TOTEPURGEABLES_OK_2:
        ADD.L   D1,D0                           | D0 += contiguous run
        CMPA.L  D1,A0                           | A0 >= D1? (already have larger)
        BCC.B   TOTEPURGEABLES_OK_3             | yes -> keep current largest
        MOVE.L  D1,A0                           | A0 = new largest contiguous block
TOTEPURGEABLES_OK_3:
        MOVEQ.L #0x0,D1                         | D1 = 0: reset contiguous run
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| TOTEPURGEABLES_CONT_3
|
TOTEPURGEABLES_CONT_3:
        MOVE.L  0x2C(A6),D2                     | D2 = zone.gzProc
        BEQ.B   TOTEPURGEABLES_EXIT_2           | no grow-zone func -> return
        MOVEM.L D0-D1/D3-D7/A0-A6,-(SP)         | save all registers
        MOVE.L  0x2C(A6),A1                     | A1 = grow-zone function
        CLR.L   -(SP)                           | push room for result
        MOVE.L  D0,-(SP)                        | push needed size
        JSR     (A1)                            | call grow-zone function
        MOVE.L  (SP)+,D2                        | D2 = result (0 = failed)
        MOVEM.L (SP)+,D0-D1/D3-D7/A0-A6         | restore all registers
TOTEPURGEABLES_EXIT_2:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| TOTEPURGEABLES_RETRY
|
| Called during boot.
TOTEPURGEABLES_RETRY:
        BRA     CompactHp                       | -> fall through to CompactHp

| ----------------------------------------------------------
|
| BK Compacts
|
| Called during boot.
BKCompacts:
        MOVEM.L D0/D2,-(SP)                     | save D0 (needed size), D2
        BSR.B   TOTEPURGEABLES_RETRY            | compact heap
        CMP.L   D1,D0                           | big enough block found?
        BLS.B   BKCOMPACTS_DONE                 | yes -> done
        CMPA.L  (ApplZone).w,A6                 | is this the application zone?
        BNE.B   BKCOMPACTS_SKIP                 | no -> skip heap expansion
        TST.L   D2                              | D2 = grow allowed?
        BEQ.B   BKCOMPACTS_SKIP                 | no -> skip
        BSR     ZONEADJUSTEND_CONT              | try expanding application heap
        BSR.B   TOTEPURGEABLES_RETRY            | compact again after expansion
        CMP.L   D1,D0                           | block found?
        BLS.B   BKCOMPACTS_DONE                 | yes -> done
BKCOMPACTS_SKIP:
        BSR     PurgeHeap                       | purge purgeable blocks
        CMP.L   D1,D0                           | block found?
        BLS.B   BKCOMPACTS_DONE                 | yes -> done
        TST.L   D2                              | grow-zone allowed?
        BEQ.B   BKCOMPACTS_DONE                 | no -> give up
BKCOMPACTS_RETRY:
        BSR.B   TOTEPURGEABLES_CONT_3           | call grow-zone function
        BSR.B   TOTEPURGEABLES_RETRY            | compact again
        CMP.L   D1,D0                           | block found?
        BLS.B   BKCOMPACTS_DONE                 | yes -> done
        TST.L   D2                              | grow-zone returned more?
        BNE.B   BKCOMPACTS_RETRY                | yes -> retry grow-zone
        SUBA.L  A0,A0                           | A0 = nil (allocation failed)
BKCOMPACTS_DONE:
        MOVE.L  A0,D2                           | D2 = result address (for Z flag)
        MOVEM.L (SP)+,D0/D2                     | restore D0, D2
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| B Find S
|
| Called during boot (15,878 times in 30s trace).
BFindS:
        MOVEM.L D1-D2/A1-A2,-(SP)               | save working registers
        MOVE.L  (Lo3Bytes).w,D2                 | D2 = Lo3Bytes mask (0x00FFFFFF)
        LEA.L   0x30(A6),A2                     | A2 = ptr to zone.allocPtr
        BTST    #0x5,0x16(A6)                   | rover search? (flags bit 5)
        BEQ.B   BFINDS_RETRY                    | no -> use allocPtr
        CLR.L   (A2)                            | clear allocPtr (start from beginning)
BFINDS_RETRY:
        MOVE.L  (A2),D1                         | D1 = allocPtr (roving pointer)
        MOVE.L  D1,A1                           | A1 = start of search
        BNE.B   BFINDS_EMPTY                    | non-nil? -> start there
        LEA.L   0x34(A6),A1                     | A1 = zone.heapData (search from start)
BFINDS_EMPTY:
        CMPA.L  (A6),A1                         | past zone end?
        BCC.B   BFINDS_ERR                      | yes -> wrap around or fail
        MOVE.L  (A1),D1                         | D1 = block header (tag+size)
        TST.B   (A1)                            | is block free? (tag = 0)
        BEQ.B   BFINDS_OK                       | yes -> try to coalesce
BFINDS_NO:
        AND.L   D2,D1                           | mask to 24-bit size
        ADDA.L  D1,A1                           | advance past this block
        BRA.B   BFINDS_EMPTY                    | -> check next block

| ----------------------------------------------------------
|
| BFINDS_OK
|
| Called during boot (30,345 times in 30s trace).
BFINDS_OK:
        MOVE.L  A1,A0                           | A0 = start of free region
        ADDA.L  D1,A0                           | A0 = end of free region
        TST.B   (A0)                            | next block also free?
        BNE.B   BFINDS_NO_2                     | no -> check if big enough
        CMPA.L  (A6),A0                         | past zone end?
        BCC.B   BFINDS_NO_2                     | yes -> stop coalescing
        ADD.L   (A0),D1                         | merge: add next block's size
        MOVE.L  D1,(A1)                         | update coalesced block size
        BRA.B   BFINDS_OK                       | -> try merging more

| ----------------------------------------------------------
|
| BFINDS_NO_2
|
| Called during boot (15,988 times in 30s trace).
BFINDS_NO_2:
        CMP.L   D0,D1                           | D1 (coalesced size) >= D0 (needed)?
        BCS.B   BFINDS_NO                       | no -> keep searching
        MOVE.L  A1,A0                           | A0 = free block address
        BRA.B   BFINDS_EXIT                     | -> return success

| ----------------------------------------------------------
|
| BFINDS_ERR
|
| Called during boot.
BFINDS_ERR:
        TST.L   (A2)                            | was allocPtr set?
        BEQ.B   BFINDS_ERR_2                    | no -> search failed
        CLR.L   (A2)                            | clear allocPtr
        BRA.B   BFINDS_RETRY                    | -> retry from zone.heapData

| ----------------------------------------------------------
|
| BFINDS_ERR_2
|
| Called during boot.
BFINDS_ERR_2:
        SUBA.L  A0,A0                           | A0 = nil (not found)
BFINDS_EXIT:
        MOVE.L  A0,(A2)                         | update allocPtr for next search
        MOVEM.L (SP)+,D1-D2/A1-A2               | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Alloc BK
|
| AllocBK: core block allocation - find or make space for D0 bytes
| D0 = requested size -> A0 = block data ptr (or nil), Z set if failed
| A1 = master pointer (for relocatable) or nil (for non-relocatable)
| Called by: GetCIcon, NEWHANDLE, REALLOCHANDLE_OK, HMAKEMOREMASTERS_CONT, MAKEPTRSPC_CONT_5
AllocBK:
        MOVEM.L D0-D5,-(SP)                     | save registers
        MOVE.L  D0,D4                           | D4 = requested size (preserved)
        BSR     Actuals                         | round D0 to actual block size (+ header + align)
        BSR.B   BFindS                          | search free list for big enough block
        BNE.B   ALLOCBK                         | found one ->
| no block found: compact heap and try again
        MOVEQ.L #-0x1,D2                        | D2 = -1 (compact fully)
        BSR     BKCompacts                      | compact + purge + grow zone
        BNE.B   ALLOCBK                         | found space ->
        SUBA.L  A0,A0                           | A0 = nil (allocation failed)
        BRA.B   ALLOCBK_ERR                     | -> return failure

| ----------------------------------------------------------
|
| AllocBK: carve block from free space at A0
| D0 = actual size needed, A0 = free block, A1 = master pointer or nil
|
ALLOCBK:
        MOVE.L  D0,D2                           | D2 = actual size needed
        MOVE.L  (A0),D0                         | D0 = free block's total size
        MOVE.L  A1,D5                           | D5 = master pointer
        BEQ.B   ALLOCBK_EMPTY                   | nil -> non-relocatable block
| relocatable block: store relative handle in block header
        SUB.L   A6,D5                           | make handle zone-relative
        MOVEQ.L #0x2,D1                         | tag = $80 (relocatable)
        MOVEQ.L #-0x1,D3                        | size correction = -1
        BRA.B   ALLOCBK_CONT                    | ->
| non-relocatable block: no handle
ALLOCBK_EMPTY:
        MOVE.L  A6,D5                           | zone-relative = zone base
        MOVEQ.L #0x1,D1                         | tag = $40 (non-relocatable)
        MOVEQ.L #0x0,D3                         | size correction = 0
| build the block header and split free space
ALLOCBK_CONT:
        BSR.B   ALLOCBK_CONT_3                  | split: carve D2 from free block, leave remainder
        MOVE.L  D5,0x4(A0)                      | block header: relHandle (zone-relative)
        MOVE.L  D4,D0                           | D0 = original requested size
        BSR.B   ALLOCBK_CONT_2                  | set block tag/size in header
        ADDQ.L  #0x8,A0                         | A0 = block data (past 8-byte header)
| update master pointer to point to block data
        MOVE.L  A1,D5                           | master pointer address
        BEQ.B   ALLOCBK_ERR                     | nil (non-relocatable) ->
        MOVE.L  A0,(A1)                         | store block address in master pointer
ALLOCBK_ERR:
        MOVE.L  A0,D0                           | D0 = block ptr (for Z flag: NE = success)
        MOVEM.L (SP)+,D0-D5                     | restore registers (Z flag preserved)
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| ALLOCBK_CONT_2
|
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
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| ALLOCBK_CONT_3
|
| Called during boot (15,878 times in 30s trace).
ALLOCBK_CONT_3:
        MOVEM.L D0-D2/D4/A1,-(SP)               | save working registers
        MOVE.L  D0,D4                           | D4 = total free block size
        SUB.L   D2,D0                           | D0 = remainder after carving
        MOVE.L  A0,A1                           | A1 = start of free block
        CMPI.L  #0xC,D0                         | remainder >= 12 (min block)?
        BCS.B   ALLOCBK_NO_2                    | no -> use entire free block
        TST     D3                              | D3 != 0? (reloc block, favor high)
        BEQ.B   ALLOCBK_NO                      | no -> allocate at bottom
        TST.B   0x16(A6)                        | zone.flags bit 7: alloc-high?
        BPL.B   ALLOCBK_NO                      | no -> allocate at bottom
        ADDA.L  D0,A1                           | A1 = allocate at high end
        BRA.B   ALLOCBK_CONT_4                  | -> create remainder at bottom

| ----------------------------------------------------------
|
| ALLOCBK_NO
|
| Called during boot (15,867 times in 30s trace).
ALLOCBK_NO:
        ADDA.L  D2,A0                           | A0 = remainder block (at top)
ALLOCBK_CONT_4:
        BSR     MakeBKF                         | write free block header for remainder
        BRA.B   ALLOCBK_CONT_5                  | -> finalize

| ----------------------------------------------------------
|
| ALLOCBK_NO_2
|
| Called during boot.
ALLOCBK_NO_2:
        MOVE.L  D4,D2                           | D2 = entire free block (no remainder)
ALLOCBK_CONT_5:
        MOVE.L  D2,D0                           | D0 = allocation size
        NEG.L   D0                              | negate (subtract from zcbFree)
        BSR     AdjustFree                      | update zone.zcbFree
        MOVE.L  A1,A0                           | A0 = carved block address
        ROR.L   #0x2,D1                         | rotate tag bits into position
        ADD.L   D2,D1                           | D1 = tag + size
        MOVE.L  D1,(A0)                         | write block header
        MOVEM.L (SP)+,D0-D2/D4/A1               | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| ALLOCBK_CONT_6
|
| Called during boot (1,397 times in 30s trace).
ALLOCBK_CONT_6:
        MOVEM.L D0-D2/A0-A2,-(SP)               | save registers across call
        MOVE.L  (0x4B8).w,A2                    | dispatch vector: _BlockMove
        JSR     (A2)                            | call BlockMove via vector
        MOVEM.L (SP)+,D0-D2/A0-A2               | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Compact Hp
|
| Called during boot.
CompactHp:
        MOVEM.L D0/D2-D5/A1-A4,-(SP)            | save working registers
        MOVE.L  D0,D3                           | D3 = needed size (compaction target)
        MOVEQ.L #0x0,D1                         | D1 = 0: largest free block found
        LEA.L   0x34(A6),A0                     | A0 = zone.heapData (first block)
        BRA.B   COMPACTHP_CONT                  | -> start scanning

| ----------------------------------------------------------
|
| COMPACTHP_SKIP
|
| Called during boot.
COMPACTHP_SKIP:
        MOVE.L  (A0),D4                         | D4 = block header (tag+size)
        AND.L   (Lo3Bytes).w,D4                 | mask to 24-bit size
        ADDA.L  D4,A0                           | advance past this block
        CMPA.L  (A6),A0                         | past zone end?
        BCC.B   COMPACTHP_OK                    | yes -> finalize
COMPACTHP_CONT:
        TST.B   (A0)                            | is block free?
        BNE.B   COMPACTHP_SKIP                  | no -> skip non-free blocks
COMPACTHP_OK:
        BTst    #0x4,0x16(A6)                   | check fast-compact flag (bit 4)
        SEQ.B   D5                              | D5 = FF if not set, 00 if set
        MOVE.L  A0,A2                           | A2 = remember start position
COMPACTHP_CONT_2:
        MOVE.L  A0,A1                           | A1 = start of free region
        MOVEQ.L #0x0,D2                         | D2 = 0: accumulated free space
COMPACTHP_CONT_3:
        CMPA.L  (A6),A0                         | past zone end?
        BCC.B   COMPACTHP_OK_4                  | yes -> finalize region
        MOVE.L  (A0),D0                         | D0 = block size
        AND.L   (Lo3Bytes).w,D0                 | mask to 24-bit
        TST.B   (A0)                            | is block free?
        BEQ.B   COMPACTHP_OK_2                  | yes -> accumulate
        BPL.B   COMPACTHP_OK_3                  | non-reloc -> barrier
        MOVE.L  0x4(A0),A3                      | get relHandle
        ADDA.L  A6,A3                           | A3 = absolute master pointer
        TST.B   (A3)                            | check MP flags: locked?
        BMI.B   COMPACTHP_OK_3                  | yes -> barrier (can't move locked)
        TST.B   D5                              | fast-compact mode?
        BNE.B   COMPACTHP_SKIP_2                | yes -> don't move blocks
        LEA.L   0x8(A1),A4                      | A4 = destination (free region + 8)
        MOVE.B  (A3),D4                         | D4 = save MP flags
        MOVE.L  A4,(A3)                         | update MP to new location
        MOVE.B  D4,(A3)                         | restore MP flags byte
        BSR.B   ALLOCBK_CONT_6                  | move block data via BlockMove vector
        ADDA.L  D0,A1                           | A1 advances past moved block
        BRA.B   COMPACTHP_SKIP_2                | -> continue scanning

| ----------------------------------------------------------
|
| COMPACTHP_OK_2
|
| Called during boot.
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

| ----------------------------------------------------------
|
| COMPACTHP_SKIP_2
|
| Called during boot.
COMPACTHP_SKIP_2:
        ADDA.L  D0,A0                           | advance past block
        BRA.B   COMPACTHP_CONT_3                | -> continue scanning

| ----------------------------------------------------------
|
| COMPACTHP_OK_3
|
| Called during boot.
COMPACTHP_OK_3:
        BSR.B   COMPACTHP_CONT_4                | finalize free region
        BRA.B   COMPACTHP_SKIP                  | -> scan for next free region

| ----------------------------------------------------------
|
| COMPACTHP_OK_4
|
| Called during boot.
COMPACTHP_OK_4:
        SUBA.L  A3,A3                           | A3 = nil (no allocPtr hint)
COMPACTHP_OK_5:
        BSR.B   COMPACTHP_CONT_4                | finalize last free region
        MOVE.L  A3,A0                           | A0 = allocPtr hint (from compaction)
        MOVE.L  A0,0x30(A6)                     | update zone.allocPtr
        MOVEM.L (SP)+,D0/D2-D5/A1-A4            | restore all working registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| COMPACTHP_CONT_4
|
| Called during boot.
COMPACTHP_CONT_4:
        TST.L   D2                              | any accumulated free space?
        BEQ.B   COMPACTHP_DONE                  | no -> done
        TST.B   D5                              | fast-compact mode (no actual moves)?
        BNE.B   COMPACTHP_SKIP_3                | yes -> don't write free block
        MOVE.L  D2,(A1)                         | write coalesced free block at A1
COMPACTHP_SKIP_3:
        CMP.L   D2,D1                           | D2 > D1? (larger than best so far)
        BCC.B   COMPACTHP_DONE                  | no -> keep current best
        MOVE.L  D2,D1                           | D1 = new largest free block size
COMPACTHP_DONE:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| To Max Limit
|
| Called during boot.
ToMaxLimit:
        MOVE.L  (BufPtr).w,D2                   | D2 = screen buffer pointer
        SUB.L   (DefltStack).w,D2               | D2 -= default stack size
| MaxLimit -- compute max growable limit.
MaxLimit:
        MOVE.L  A7,D1                           | D1 = current stack pointer
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit
        SUB.L   (MinStack).w,D1                 | D1 -= minimum stack reserve
        CMP.L   D2,D1                           | D1 < D2?
        BCS.B   MAXLIMIT_OK                     | yes -> use D1 (stack-limited)
        MOVE.L  D2,D1                           | D1 = D2 (use heap limit)
MAXLIMIT_OK:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Zone Adjust End
|
| Called during boot.
ZoneAdjustEnd:
        MOVEM.L D0/A0/A2-A3,-(SP)               | save registers
        MOVE.L  A0,A3                           | A3 = new end address
        MOVE.L  (A6),A0                         | A0 = old bkLim (old sentinel)
        MOVE.L  A3,D0                           | D0 = expansion size
        SUB.L   A0,D0                           | D0 = new - old sentinel
        MOVE.L  #0xC,(A3)                       | write sentinel block (12 bytes)
        BSR     MakeBKF                         | convert old sentinel to free block
        BSR     AdjustFree                      | add expansion to zone.zcbFree
        MOVE.L  A3,(A6)                         | update zone.bkLim
        MOVEM.L (SP)+,D0/A0/A2-A3               | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| ZONEADJUSTEND_CONT
|
| Called during boot.
ZONEADJUSTEND_CONT:
        MOVEM.L D0-D3/A0-A2,-(SP)               | save registers
        ADDI.L  #0x400,D0                       | add 1KB safety margin
        ANDI    #-0x400,D0                      | round down to 1KB boundary
        MOVE.L  D0,D3                           | D3 = rounded expansion size
        MOVE.L  (ApplLimit).w,D2                | D2 = application heap limit
        BSR.B   MaxLimit                        | compute max limit from stack
        MOVE.L  (HeapEnd).w,D2                  | D2 = current heap end
        CMP.L   D2,D1                           | current end >= max?
        BLS.B   ZONEADJUSTEND_OK                | yes -> can't expand
        ADD.L   D0,D2                           | D2 = current end + requested
        BCS.B   ZONEADJUSTEND_OK                | overflow? -> can't expand
        CMP.L   D2,D1                           | requested > available?
        BCS.B   ZONEADJUSTEND_NO                | no -> use available
        MOVE.L  D2,D1                           | D1 = target end
        MOVEQ.L #0x0,D3                         | D3 = 0 (used all available)
        BRA.B   ZONEADJUSTEND_CONT_2            | -> expand heap

| ----------------------------------------------------------
|
| ZONEADJUSTEND_NO
|
ZONEADJUSTEND_NO:
        MOVE.L  D1,D0                           | D0 = available expansion
        SUB.L   (HeapEnd).w,D0                  | D0 = max limit - current end
        CMPI.L  #0xC,D0                         | less than minimum block?
        BCS.B   ZONEADJUSTEND_OK                | yes -> can't expand
ZONEADJUSTEND_CONT_2:
        MOVE.L  D1,(HeapEnd).w                  | update HeapEnd
        MOVE.L  D1,A0                           | A0 = new end address
        BSR.B   ZoneAdjustEnd                   | adjust zone end, add free block
ZONEADJUSTEND_OK:
        MOVEM.L (SP)+,D0-D3/A0-A2               | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Actuals
|
| Called during boot (34,515 times in 30s trace).
Actuals:
        ADDQ.L  #0x8,D0                         | add 8-byte block header
        ADDQ.L  #0x1,D0                         | add 1 for word alignment
        ANDI    #-0x2,D0                        | round down to even (word-align)
        CMPI.L  #0xC,D0                         | less than minimum (12)?
        BCC.B   ACTUALS_OK                      | no -> size is valid
        MOVEQ.L #0xC,D0                         | enforce minimum 12-byte block
ACTUALS_OK:
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Get Size
|
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
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Clear GZ Stuff
|
| Called during boot (7,457 times in 30s trace).
ClearGZStuff:
        CLR.L   (GZRootHnd).w                   | clear grow-zone root handle
        CLR.L   (GZRootPtr).w                   | clear grow-zone root pointer
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Set Size
|
| Called during boot (18,577 times in 30s trace).
SetSize:
        MOVEM.L D1-D6/A0-A3,-(SP)               | save working registers
        MOVE.B  (A1),-(SP)                      | save MP flags on stack
        MOVE.L  D0,D1                           | D1 = new logical size
        BSR.B   Actuals                         | round to actual block size
        MOVE.L  D0,D3                           | D3 = actual size needed
        BSR.B   GetSize                         | D0 = current logical size
        CMP.L   D0,D1                           | same size?
        BEQ     SETSIZE_OK_5                    | yes -> just update correction
        MOVE.L  A0,A2                           | A2 = block header
        SUBQ.L  #0x8,A2                         | back up to header
        MOVE.L  (A2),D2                         | D2 = current header (tag+size)
        AND.L   (Lo3Bytes).w,D2                 | mask to physical size
        MOVE.L  D2,D4                           | D4 = current physical size
        CMP.L   D2,D3                           | new vs current physical?
        BEQ     SETSIZE_NO_5                    | equal -> just update correction
        BCS     SETSIZE_CONT_4                  | smaller -> shrink in place
        MOVE.L  D3,D5                           | D5 = additional bytes needed
        SUB.L   D2,D5                           | D5 = new - current
        MOVE.L  A1,(GZRootHnd).w                | protect handle during grow-zone
        MOVE.L  A0,(GZRootPtr).w                | protect pointer during grow-zone
        MOVE.L  A2,A3                           | A3 = end of current block
        ADDA.L  D4,A3                           | A3 = current end
        MOVEQ.L #0x0,D6                         | D6 = 0: accumulated free after block
SETSIZE_CONT:
        CMPA.L  (A6),A3                         | past zone end?
        BCC.B   SETSIZE_OK                      | yes -> not enough free space
        TST.B   (A3)                            | next block free?
        BNE.B   SETSIZE_OK                      | no -> can't extend
        ADD.L   (A3),D6                         | D6 += free block size
        ADDA.L  (A3),A3                         | advance past free block
        BRA.B   SETSIZE_CONT                    | -> check for more free blocks

| ----------------------------------------------------------
|
| SETSIZE_OK
|
| Called during boot (7,440 times in 30s trace).
SETSIZE_OK:
        SUB.L   D6,D5                           | D5 -= accumulated free
        BLS     SETSIZE_EMPTY                   | enough free? -> extend in place
        MOVE.L  A1,D0                           | D0 = master pointer
        BEQ     SETSIZE_EMPTY                   | nil -> can't relocate (ptr block)
        TST.B   (SP)                            | locked? (check saved flags on stack)
        BMI     SETSIZE_EMPTY                   | yes -> can't relocate
        LEA.L   0x34(A6),A3                     | A3 = zone.heapData (scan start)
SETSIZE_CONT_2:
        CMPA.L  A2,A3                           | reached our block?
        BCC.B   SETSIZE_OK_4                    | yes -> no room before us
        MOVE.L  (A3),D0                         | D0 = block header
        TST.B   (A3)                            | is block free?
        BEQ.B   SETSIZE_OK_2                    | yes -> try coalescing
        AND.L   (Lo3Bytes).w,D0                 | mask to size
        ADDA.L  D0,A3                           | advance past block
        MOVEQ.L #0x0,D0                         | D0 = 0: reset free counter
        BRA.B   SETSIZE_CONT_2                  | -> continue scanning

| ----------------------------------------------------------
|
| SETSIZE_OK_2
|
| Called during boot.
SETSIZE_OK_2:
        MOVE.L  A3,A0                           | A0 = start of free region
        MOVEQ.L #0x0,D0                         | D0 = 0: reset accumulated free
SETSIZE_OK_3:
        CMPA.L  0x30(A6),A3                     | is this the allocPtr?
        BNE.B   SETSIZE_SKIP                    | no -> skip
        MOVE.L  A0,0x30(A6)                     | update allocPtr past coalesced region
SETSIZE_SKIP:
        ADD.L   (A3),D0                         | D0 += free block size
        ADDA.L  (A3),A3                         | advance past free block
        TST.B   (A3)                            | next block also free?
        BEQ.B   SETSIZE_OK_3                    | yes -> keep coalescing
        MOVE.L  D0,(A0)                         | write coalesced free block size
        BRA.B   SETSIZE_CONT_2                  | -> continue scanning for our block

| ----------------------------------------------------------
|
| SETSIZE_OK_4
|
| Called during boot.
SETSIZE_OK_4:
        MOVE.L  D5,D6                           | D6 = additional bytes still needed
        LSR.L   #0x2,D6                         | D6 / 4: tolerance threshold
        CMP.L   D6,D0                           | free block before us big enough?
        BLS.B   SETSIZE_NO_3                    | no -> try extending after
        MOVEQ.L #0xC,D6                         | D6 = 12 (minimum block size)
        CMP.L   D5,D6                           | D5 (still needed) >= 12?
        BLS.B   SETSIZE_NO                      | no -> can't split, use 12 minimum
        MOVE.L  D6,D5                           | D5 = 12 (minimum allocation)
SETSIZE_NO:
        MOVEQ.L #0x18,D6                        | D6 = 24 (header + min + safety)
        ADD.L   D5,D6                           | D6 = 24 + needed
        CMP.L   D6,D0                           | free block >= 24 + needed?
        BCS.B   SETSIZE_NO_2                    | no -> use entire free block
        SUB.L   D5,D0                           | carve needed from end of free block
        MOVE.L  D0,(A0)                         | update free block size (remainder)
        ADDA.L  D0,A0                           | A0 = new block position
        MOVE.L  D5,D0                           | D0 = carved size
SETSIZE_NO_2:
        MOVE.L  A0,(A1)                         | update MP to new block + 8
        ADDQ.L  #0x8,(A1)                       | adjust for data offset
        MOVE.B  (SP),(A1)                       | restore MP flags
        MOVEM.L D0/A1,-(SP)                     | save D0 and A1
        CMPA.L  0x30(A6),A2                     | is old block at allocPtr?
        BNE.B   SETSIZE_SKIP_2                  | no -> skip
        MOVE.L  A0,0x30(A6)                     | update allocPtr to new location
SETSIZE_SKIP_2:
        exg     A0,A2                           | swap old and new block addresses
        MOVE.L  A2,A1                           | A1 = new block, A2 = old block
        MOVE.L  D4,D0                           | D0 = old physical size
        BSR     ALLOCBK_CONT_6                  | copy block data to new location
        MOVE.L  A2,A0                           | A0 = old block end
        ADDA.L  D4,A0                           | advance by old size
        MOVE.L  (SP)+,(A0)                      | write free block at old location
        MOVE.L  (SP)+,A1                        | restore A1
        LEA.L   0x8(A2),A0                      | A0 = new block data pointer
        MOVE.L  A0,(GZRootPtr).w                | update GZRootPtr to new location
        BRA.B   SETSIZE_EMPTY                   | -> extend at new position

| ----------------------------------------------------------
|
| SETSIZE_NO_3
|
| Called during boot.
SETSIZE_NO_3:
        MOVE.L  A2,A0                           | A0 = block header
        ADDA.L  D4,A0                           | advance past current size
        MOVE.L  (A0),D0                         | D0 = next block header
        AND.L   (Lo3Bytes).w,D0                 | mask to size
        CMP.L   D0,D3                           | new size fits within next block?
        BCC.B   SETSIZE_EMPTY                   | yes -> extend in place
        TST.B   (A0)                            | next block free?
        BNE.B   SETSIZE_NO_4                    | no -> must relocate block
SETSIZE_EMPTY:
        MOVE.L  A2,A0                           | A0 = our block header
        MOVE.L  D3,D0                           | D0 = additional bytes needed
        SUB.L   D2,D0                           | D0 = new - old
        ADDA.L  D2,A2                           | A2 = end of old block
        BSET    #0x7,(A1)                       | temporarily lock during SetSize
        BSR     MAKEPTRSPC_CONT_2               | recursive SetSize for extension
        BCLR    #0x7,(A1)                       | unlock after SetSize
        MOVE.L  A2,D4                           | D4 = result address
        BNE.B   SETSIZE_CONT_3                  | success? -> merge
SETSIZE_NO_4:
        MOVE.L  A1,D4                           | D4 = master pointer (nil for ptr)
        BEQ.B   SETSIZE_EMPTY_2                 | nil -> can't relocate
        TST.B   (SP)                            | locked? (saved flags)
        BMI.B   SETSIZE_EMPTY_2                 | yes -> can't relocate
        MOVE.L  D1,D0                           | D0 = new logical size
        BCLR    #0x6,(A1)                       | clear purge bit for reallocation
        BSR     MAKEPTRSPC_CONT_5               | allocate new block, move data
        MOVE.B  (SP),(A1)                       | restore MP flags
        BSR     ClearGZStuff                    | clear grow-zone protection
        BRA.B   SETSIZE_ERR                     | -> return result

| ----------------------------------------------------------
|
| SETSIZE_EMPTY_2
|
SETSIZE_EMPTY_2:
        BSR     ClearGZStuff                    | clear grow-zone protection
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
        BRA.B   SETSIZE_ERR                     | -> return error

| ----------------------------------------------------------
|
| SETSIZE_CONT_3
|
| Called during boot (7,436 times in 30s trace).
SETSIZE_CONT_3:
        BSR     ClearGZStuff                    | clear grow-zone protection
        MOVE.L  (A2),D0                         | D0 = free block size
        MOVE.L  D0,D4                           | D4 = new physical size
        ADD.L   D2,D4                           | D4 = old + free
        MOVE.L  A0,A2                           | A2 = block header
        MOVE.B  (A2),D5                         | D5 = save tag byte
        MOVE.L  D4,(A2)                         | write new physical size
        MOVE.B  D5,(A2)                         | restore tag byte
        NEG.L   D0                              | negate freed size
        BSR.B   AdjustFree                      | subtract from zcbFree
SETSIZE_CONT_4:
        SUB.L   D3,D4                           | D4 = excess (physical - needed)
        CMPI.L  #0xC,D4                         | excess >= 12 (min block)?
        BCS.B   SETSIZE_NO_5                    | no -> keep it all
        BTST    #0x0,0x16(A6)                   | zone read-only? (flags bit 0)
        BNE.B   SETSIZE_ERR_2                   | yes -> return error
        MOVE.L  A2,A0                           | A0 = block header
        ADDA.L  D3,A0                           | advance by new size
        MOVE.B  (A2),D5                         | D5 = save tag byte
        MOVE.L  D3,(A2)                         | write new (smaller) physical size
        MOVE.B  D5,(A2)                         | restore tag byte
        MOVE.L  D4,D0                           | D0 = excess as free block
        BSR     MakeBKF                         | create free block from excess
        BSR.B   AdjustFree                      | add excess to zcbFree
SETSIZE_NO_5:
        MOVE.L  A2,A0                           | A0 = block header
        MOVE.L  D1,D0                           | D0 = new logical size
        BSR     ALLOCBK_CONT_2                  | update size correction nibble
SETSIZE_OK_5:
        MOVEQ.L #0x0,D0                         | noErr
SETSIZE_ERR:
        MOVE.B  (SP)+,(A1)                      | restore MP flags from stack
        MOVEM.L (SP)+,D1-D6/A0-A3               | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| SETSIZE_ERR_2
|
SETSIZE_ERR_2:
        MOVEQ.L #-0x63,D0                       | memROZErr (-99): read-only zone
        BRA.B   SETSIZE_ERR                     | -> return error

| ----------------------------------------------------------
|
| Adjust Free
|
| Called during boot (56,518 times in 30s trace).
AdjustFree:
        ADD.L   D0,0xC(A6)                      | zone.zcbFree += D0
        BMI.B   ADJUSTFREE_ERR                  | went negative? -> system error
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| ADJUSTFREE_ERR
|
ADJUSTFREE_ERR:
        MOVEQ.L #0x21,D0                        | dsMemFullErr (33): heap corrupted
        _SysError                               | fatal: negative free space
| NextMaster -- get free master pointer -> A1.
NextMaster:
        MOVEM.L D0/A0,-(SP)                     | save D0 and A0
        MOVE.L  0x8(A6),A1                      | A1 = zone.hFstFree (free MP list head)
        MOVE.L  A1,D0                           | D0 = A1 (for Z flag test)
        BNE.B   NEXTMASTER_CONT                 | any free master pointers?
        BSR.B   HMakeMoreMasters                | no -> allocate more
        BEQ.B   NEXTMASTER_ERR                  | allocation failed? -> return nil
NEXTMASTER_CONT:
        MOVE.L  (A1),0x8(A6)                    | unlink: zone.hFstFree = next free MP
        MOVE.L  A1,D0                           | D0 = A1 (NE = success)
NEXTMASTER_ERR:
        MOVEM.L (SP)+,D0/A0                     | restore D0 and A0
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| H Make More Masters
|
| Called during boot.
HMakeMoreMasters:
        MOVEM.L D0-D1/A0,-(SP)                  | save registers
        MOVE    0x14(A6),D0                     | D0 = zone.moreMast count
        EXT.L   D0                              | sign-extend to long
        BGT.B   HMAKEMOREMASTERS_CONT           | valid count? (> 0)
        MOVEQ.L #0x20,D0                        | default to 32 master pointers
HMAKEMOREMASTERS_CONT:
        MOVE.L  D0,D1                           | D1 = number of master pointers
        ASL.L   #0x2,D0                         | D0 = count * 4 bytes
        BSR.B   MakePtrSpc                      | find/make space for ptr block
        SUBA.L  A1,A1                           | A1 = nil (non-relocatable)
        BSR     AllocBK                         | allocate block for master pointers
        BEQ.B   HMAKEMOREMASTERS_ERR            | failed? -> return
        MOVE.L  A0,A1                           | A1 = first master pointer in block
HMAKEMOREMASTERS_CONT_2:
        BSR.B   ReleaseMP                       | link MP into free list
        ADDQ.L  #0x4,A1                         | advance to next MP slot
        SUBQ.W  #0x1,D1                         | count down
        BNE.B   HMAKEMOREMASTERS_CONT_2         | more to do
        SUBQ.L  #0x4,A1                         | back up to last valid MP
HMAKEMOREMASTERS_ERR:
        MOVE.L  A1,D0                           | D0 = A1 (NE = success)
        MOVEM.L (SP)+,D0-D1/A0                  | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Release MP
|
| Called during boot (14,917 times in 30s trace).
ReleaseMP:
        MOVE.L  0x8(A6),(A1)                    | link: MP->next = zone.hFstFree
        MOVE.L  A1,0x8(A6)                      | zone.hFstFree = this MP
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Make Ptr Spc
|
| Called during boot.
MakePtrSpc:
        MOVEM.L D0-D4/A0-A1/A3-A4,-(SP)         | save working registers
        BSR     Actuals                         | round D0 to actual block size
        MOVE.L  A6,A4                           | A4 = current zone
        CMPA.L  (ApplZone).w,A6                 | is this the application zone?
        SEQ.B   D3                              | D3 = FF if app zone, 00 otherwise
MAKEPTRSPC_RETRY:
        LEA.L   0x34(A4),A0                     | A0 = zone.heapData (first block)
        MOVE.L  (A6),A3                         | A3 = zone.bkLim (zone end)
        MOVE.L  A0,A2                           | A2 = scan start position
        MOVEQ.L #0x0,D2                         | D2 = 0: accumulated free+purgeable
MAKEPTRSPC_NO:
        MOVE.L  (A0),D1                         | D1 = block header
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit size
        TST.B   (A0)                            | is block free?
        BEQ.B   MAKEPTRSPC_OK                   | yes -> accumulate
        BPL.B   MAKEPTRSPC_OK_3                 | non-reloc -> barrier
        MOVE.L  0x4(A0),A1                      | get relHandle
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        TST.B   (A1)                            | check MP flags: locked?
        BMI.B   MAKEPTRSPC_OK_3                 | yes -> barrier
MAKEPTRSPC_OK:
        ADD.L   D1,D2                           | D2 += block size
        ADDA.L  D1,A0                           | advance past block
        CMP.L   D0,D2                           | enough space accumulated?
        BCS.B   MAKEPTRSPC_NO_3                 | no -> keep scanning
        BSR.B   MAKEPTRSPC_CONT_2               | purge/compact this region
        MOVE.L  A2,D2                           | D2 = result (A2 = free block)
        BNE.B   MAKEPTRSPC_EXIT                 | success? -> return
        LEA.L   0x34(A4),A2                     | A2 = zone.heapData (retry)
MAKEPTRSPC_NO_2:
        MOVE.L  (A2),D1                         | D1 = block size
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit
        ADDA.L  D1,A2                           | advance past block
        CMPA.L  A0,A2                           | past our freed region?
        BHI.B   MAKEPTRSPC_OK_2                 | yes -> resume from here
        CMPA.L  A3,A2                           | past zone end?
        BCS.B   MAKEPTRSPC_NO_2                 | no -> keep scanning
MAKEPTRSPC_OK_2:
        MOVE.L  A2,A0                           | A0 = resume position
        SUBA.L  A2,A2                           | A2 = nil (reset scan)
MAKEPTRSPC_EXIT:
        MOVE.L  A2,D2                           | D2 = A2 (NE = success)
        BNE.B   MAKEPTRSPC_EXIT_2               | success? -> return
        BRA.B   MAKEPTRSPC_CONT                 | -> continue scanning

| ----------------------------------------------------------
|
| MAKEPTRSPC_OK_3
|
| Called during boot.
MAKEPTRSPC_OK_3:
        ADDA.L  D1,A0                           | advance past non-free block
MAKEPTRSPC_CONT:
        MOVE.L  A0,A2                           | A2 = new scan start
        MOVEQ.L #0x0,D2                         | D2 = 0: reset accumulator
MAKEPTRSPC_NO_3:
        CMPA.L  A3,A0                           | past zone end?
        BCS.B   MAKEPTRSPC_NO                   | no -> continue scanning
        ADDQ.B  #0x1,D3                         | increment retry counter
        BNE.B   MAKEPTRSPC_RETRY_2              | first retry? -> try expanding heap
        BSR     ZONEADJUSTEND_CONT              | expand application heap
        BRA.B   MAKEPTRSPC_RETRY                | -> retry scan

| ----------------------------------------------------------
|
| MAKEPTRSPC_RETRY_2
|
MAKEPTRSPC_RETRY_2:
        SUBA.L  A2,A2                           | A2 = nil (not found)
MAKEPTRSPC_EXIT_2:
        MOVEM.L (SP)+,D0-D4/A0-A1/A3-A4         | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MAKEPTRSPC_CONT_2
|
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
        MOVE.L  0x4(A3),A1                      | get relHandle
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        MOVE.B  (A1),D2                         | D2 = MP flags byte
        BMI.B   MAKEPTRSPC_OK_5                 | locked? -> stop (barrier)
        BSR.B   MAKEPTRSPC_CONT_4               | try relocating block out
        BEQ.B   MAKEPTRSPC_OK_4                 | moved successfully? -> count as free
        BTST    #0x6,D2                         | is block purgeable?
        BEQ.B   MAKEPTRSPC_OK_5                 | no -> stop (can't free this block)
        MOVE.L  (A1),A0                         | A0 = block data via master pointer
        SUBQ.L  #0x8,A0                         | back up to block header
        BSR     EH_CONT_2                       | purge block (free + notify)
MAKEPTRSPC_OK_4:
        MOVE.L  A3,A0                           | A0 = current scan position
        MOVE.L  (A0),D0                         | D0 = block size
        CMPA.L  0x30(A6),A0                     | is this the allocPtr?
        BNE.B   MAKEPTRSPC_SKIP                 | no -> skip
        CLR.L   0x30(A6)                        | clear allocPtr (will be rebuilt)
MAKEPTRSPC_SKIP:
        ADD.L   D0,D3                           | D3 += block size freed
        ADDA.L  D0,A3                           | A3 = advance past block
        BRA.B   MAKEPTRSPC_CONT_3               | -> continue scanning

| ----------------------------------------------------------
|
| MAKEPTRSPC_OK_5
|
| Called during boot (7,495 times in 30s trace).
MAKEPTRSPC_OK_5:
        AND.L   (Lo3Bytes).w,D3                 | mask D3 to 24-bit
        BEQ.B   MAKEPTRSPC_SKIP_2               | nothing freed? -> skip write
        MOVE.L  D3,(A2)                         | write coalesced free block
MAKEPTRSPC_SKIP_2:
        CMP.L   D1,D3                           | freed enough?
        BCC.B   MAKEPTRSPC_ERR                  | no -> A2 = nil (failed)
        SUBA.L  A2,A2                           | A2 = nil
MAKEPTRSPC_ERR:
        CLR.L   0x30(A6)                        | clear allocPtr
        MOVEM.L (SP)+,D0-D3/A0-A1/A3            | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MAKEPTRSPC_CONT_4
|
| Called during boot (1,336 times in 30s trace).
MAKEPTRSPC_CONT_4:
        MOVE.L  A0,-(SP)                        | save A0
        MOVE.L  D3,D0                           | D0 = bytes freed so far
        BEQ.B   MAKEPTRSPC_SKIP_3               | nothing freed yet? -> skip
        MOVE.L  D3,(A2)                         | mark freed region as non-reloc temp
        ORI.L   #0x40000000,(A2)                | tag = non-relocatable ($40000000)
        MOVE.L  A6,0x4(A2)                      | relHandle = zone base
        NEG.L   D0                              | negate for AdjustFree (subtract)
        BSR     AdjustFree                      | subtract from zcbFree
MAKEPTRSPC_SKIP_3:
        MOVE.L  (A1),A0                         | A0 = block data (via master ptr)
        BSR     GetSize                         | D0 = logical size of block
        BSR.B   MAKEPTRSPC_CONT_5               | allocate new block, move data
        MOVE.L  D0,A0                           | A0 = D0 (result for caller)
        MOVE.L  D3,D0                           | D0 = bytes freed
        BEQ.B   MAKEPTRSPC_SKIP_4               | nothing freed? -> skip
        MOVE.L  D3,(A2)                         | restore free block at old region
        BSR     AdjustFree                      | add freed space back to zcbFree
MAKEPTRSPC_SKIP_4:
        MOVE.L  A0,D0                           | D0 = result (NE = success)
        MOVE.L  (SP)+,A0                        | restore A0
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MAKEPTRSPC_CONT_5
|
| Called during boot (1,340 times in 30s trace).
MAKEPTRSPC_CONT_5:
        MOVEM.L D1-D2/A0-A2,-(SP)               | save registers
        MOVE.L  A1,A2                           | A2 = master pointer
        MOVE.L  A1,(GZMoveHnd).w                | record handle being moved
        MOVE.B  (A2),D1                         | D1 = save MP flags
        SUBA.L  A1,A1                           | A1 = nil (non-reloc allocation)
        BSR     AllocBK                         | allocate new block
        BEQ.B   MAKEPTRSPC_ERR_3                | failed? -> return error
        TST.L   (A2)                            | block has data?
        BEQ.B   MAKEPTRSPC_NO_4                 | no -> just free old
        MOVE.L  A0,A1                           | A1 = new block data
        MOVE.L  (A2),A0                         | A0 = old block data
        BSR     GetSize                         | D0 = old block logical size
        BSR     ALLOCBK_CONT_6                  | copy old data to new block
        SUBQ.L  #0x8,A0                         | A0 = old block header
        SUBQ.L  #0x8,A1                         | A1 = new block header
        MOVEQ.L #-0x10,D0                       | D0 = 0xF0: mask for tag+correction
        AND.B   (A0),D0                         | D0 = old block's tag+correction
        EOR.B   D0,(A0)                         | clear old header's tag+correction
        MOVEQ.L #-0x10,D2                       | D2 = 0xF0: mask for new block
        AND.B   (A1),D2                         | D2 = new block's tag+correction
        EOR.B   D2,(A1)                         | clear new header's tag+correction
        OR.B    D0,(A1)                         | copy old tag+correction to new header
        OR.B    D2,(A0)                         | copy new tag+correction to old header
        ADDQ.L  #0x4,A0                         | A0 = old relHandle field
        ADDQ.L  #0x4,A1                         | A1 = new relHandle field
        MOVE.L  (A0),(A1)+                      | copy relHandle, A1 -> new data ptr
        MOVE.L  A1,(A2)                         | update master pointer to new block
        MOVE.B  D1,(A2)                         | restore MP flags
        MOVE.L  A6,(A0)+                        | old relHandle = zone base (non-reloc)
MAKEPTRSPC_NO_4:
        BSR.B   FreeBk                          | free old block
        MOVEQ.L #0x0,D0                         | noErr
MAKEPTRSPC_ERR_2:
        CLR.L   (GZMoveHnd).w                   | clear GZMoveHnd
        MOVEM.L (SP)+,D1-D2/A0-A2               | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| MAKEPTRSPC_ERR_3
|
MAKEPTRSPC_ERR_3:
        MOVE.B  D1,(A2)                         | restore MP flags
        MOVEQ.L #-0x6C,D0                       | memFullErr (-108)
        BRA.B   MAKEPTRSPC_ERR_2                | -> return error

| ----------------------------------------------------------
|
| Free Bk
|
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
        MOVE.L  0x4(A0),A1                      | get relHandle
        ADDA.L  A6,A1                           | A1 = absolute master pointer
        BSR     ReleaseMP                       | return MP to free list
FREEBK_NO:
        BSR     MakeBKF                         | convert to free block
        BSR     AdjustFree                      | add freed space to zcbFree
FREEBK_SKIP:
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| Std GZ
|
StdGZ:
        MOVE.L  (SP)+,A1                        | A1 = return address
        LEA.L   (GZRootHnd).w,A2                | A2 -> GZRootHnd, GZRootPtr, GZMoveHnd
        MOVEM.L (A2),D3-D5                      | D3=GZRootHnd, D4=GZRootPtr, D5=GZMoveHnd
        TST.L   D5                              | GZMoveHnd set?
        BEQ.B   STDGZ_NO                        | no -> try reserve
        CMP.L   D3,D5                           | GZMoveHnd == GZRootHnd?
        BNE.B   STDGZ_NO_2                      | no -> try purgeable
STDGZ_NO:
        BTst    #0x3,0x16(A6)                   | grow-zone disabled? (flags bit 3)
        BNE.B   STDGZ_OK                        | yes -> try user grow-zone
        MOVE.L  (SP),D0                         | D0 = needed size from stack
        CLR.L   (A2)+                           | clear GZRootHnd
        CLR.L   (A2)+                           | clear GZRootPtr
        CLR.L   (A2)+                           | clear GZMoveHnd
        MOVE.L  (TheZone).w,-(SP)               | save TheZone
        MOVE.L  A6,(TheZone).w                  | set TheZone to this heap
        _ResrvMem                               | try to reserve space
        MOVE.L  (SP)+,(TheZone).w               | restore TheZone
        MOVEM.L D3-D5,-(A2)                     | restore GZ vars
        TST.L   D0                              | reservation failed?
        BMI.B   STDGZ_OK                        | yes -> try user grow-zone
        MOVE.L  (SP)+,(SP)                      | pop needed size, keep return addr
        JMP     (A1)                            | return (retry allocation)

| ----------------------------------------------------------
|
| STDGZ_NO_2
|
STDGZ_NO_2:
        BTst    #0x2,0x16(A6)                   | purge disabled? (flags bit 2)
        BNE.B   STDGZ_OK                        | yes -> try user grow-zone
STDGZ_NO_3:
        ADDQ.W  #0x4,SP                         | pop needed size (give up)
        JMP     (A1)                            | return (retry with less)

| ----------------------------------------------------------
|
| STDGZ_OK
|
STDGZ_OK:
        MOVE.L  0x10(A6),D2                     | D2 = user grow-zone proc
        BEQ.B   STDGZ_NO_3                      | no user proc -> give up
        MOVE.L  A1,-(SP)                        | push return address
        MOVE.L  D2,-(SP)                        | push user proc address
        RTS                                     | call user grow-zone proc via RTS

| ----------------------------------------------------------
|
| _BlockMove ($A02E)
| A0 = src, A1 = dst, D0.L = count -> (copied)
|
| Called during boot (5,329 times in 30s trace).
BlockMove:
        TST.L   D0                              | zero or negative count?
        BLE.B   BLOCKMOVE_EXIT                  | yes -> return noErr
        MOVE.L  A0,D2                           | D2 = src address
        AND.L   (Lo3Bytes).w,D2                 | mask to 24-bit
        MOVE.L  A1,D1                           | D1 = dst address
        AND.L   (Lo3Bytes).w,D1                 | mask to 24-bit
        SUB.L   D2,D1                           | D1 = dst - src
        BLT.B   BLOCKMOVE_CONT                  | dst < src? -> copy forward
        ADDA.L  D0,A0                           | adjust src to end (copy backward)
        ADDA.L  D0,A1                           | adjust dst to end (copy backward)
BLOCKMOVE_CONT:
        LSR     #0x1,D1                         | odd alignment?
        BCC.B   BLOCKMOVE_NO_3                  | no -> use word-aligned copy
        TST.L   D1                              | D1 sign: forward or backward?
        BPL.B   BLOCKMOVE_LOOP_2                | forward -> byte-copy backward loop
BLOCKMOVE_LOOP:
        SUBQ.L  #0x8,D0                         | 8 bytes left?
        BLE.B   BLOCKMOVE_NO                    | no -> copy remainder
        MOVE.B  (A0)+,(A1)+                     | copy byte 1 of 8
        MOVE.B  (A0)+,(A1)+                     | copy byte 2 of 8
        MOVE.B  (A0)+,(A1)+                     | copy byte 3 of 8
        MOVE.B  (A0)+,(A1)+                     | copy byte 4 of 8
        MOVE.B  (A0)+,(A1)+                     | copy byte 5 of 8
        MOVE.B  (A0)+,(A1)+                     | copy byte 6 of 8
        MOVE.B  (A0)+,(A1)+                     | copy byte 7 of 8
        MOVE.B  (A0)+,(A1)+                     | copy byte 8 of 8
        BRA.B   BLOCKMOVE_LOOP                  | -> continue 8-byte loop

| ----------------------------------------------------------
|
| BLOCKMOVE_NO
|
| Called during boot.
BLOCKMOVE_NO:
        NEG     D0                              | negate remainder (0..7)
        ADD     D0,D0                           | * 2 = jump table offset
        JMP     BLOCKMOVE_CONT_2(PC,D0.W)       | jump into unrolled copy tail

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_2
|
| Called during boot.
BLOCKMOVE_CONT_2:
        MOVE.B  (A0)+,(A1)+                     | copy byte 7 (if needed)
        MOVE.B  (A0)+,(A1)+                     | copy byte 6
        MOVE.B  (A0)+,(A1)+                     | copy byte 5
        MOVE.B  (A0)+,(A1)+                     | copy byte 4
        MOVE.B  (A0)+,(A1)+                     | copy byte 3
        MOVE.B  (A0)+,(A1)+                     | copy byte 2
        MOVE.B  (A0)+,(A1)+                     | copy byte 1
        MOVE.B  (A0)+,(A1)+                     | copy byte 0
BLOCKMOVE_EXIT:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| BLOCKMOVE_LOOP_2
|
| Called during boot (3,452 times in 30s trace).
BLOCKMOVE_LOOP_2:
        SUBQ.L  #0x8,D0                         | 8 bytes left?
        BLE.B   BLOCKMOVE_NO_2                  | no -> copy remainder
        MOVE.B  -(A0),-(A1)                     | copy byte 8 of 8 (backward)
        MOVE.B  -(A0),-(A1)                     | copy byte 7
        MOVE.B  -(A0),-(A1)                     | copy byte 6
        MOVE.B  -(A0),-(A1)                     | copy byte 5
        MOVE.B  -(A0),-(A1)                     | copy byte 4
        MOVE.B  -(A0),-(A1)                     | copy byte 3
        MOVE.B  -(A0),-(A1)                     | copy byte 2
        MOVE.B  -(A0),-(A1)                     | copy byte 1
        BRA.B   BLOCKMOVE_LOOP_2                | -> continue backward loop

| ----------------------------------------------------------
|
| BLOCKMOVE_NO_2
|
| Called during boot (1,485 times in 30s trace).
BLOCKMOVE_NO_2:
        NEG     D0                              | negate remainder
        ADD     D0,D0                           | * 2 = jump table offset
        JMP     BLOCKMOVE_CONT_3(PC,D0.W)       | jump into unrolled backward tail

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_3
|
| Called during boot.
BLOCKMOVE_CONT_3:
        MOVE.B  -(A0),-(A1)                     | copy byte 7 (backward, if needed)
        MOVE.B  -(A0),-(A1)                     | copy byte 6
        MOVE.B  -(A0),-(A1)                     | copy byte 5
        MOVE.B  -(A0),-(A1)                     | copy byte 4
        MOVE.B  -(A0),-(A1)                     | copy byte 3
        MOVE.B  -(A0),-(A1)                     | copy byte 2
        MOVE.B  -(A0),-(A1)                     | copy byte 1
        MOVE.B  -(A0),-(A1)                     | copy byte 0
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| BLOCKMOVE_NO_3
|
| Called during boot (3,821 times in 30s trace).
BLOCKMOVE_NO_3:
        MOVE    A0,D2                           | D2 = src low word (for alignment)
        TST.L   D1                              | D1 sign: forward or backward?
        BPL     BLOCKMOVE_CONT_69               | backward -> word-aligned backward
        LSR     #0x1,D2                         | src odd?
        BCC.B   BLOCKMOVE_NO_4                  | no -> already word-aligned
        MOVE.B  (A0)+,(A1)+                     | copy 1 byte to align
        SUBQ.L  #0x1,D0                         | decrement count
BLOCKMOVE_NO_4:
        SUBI.L  #0x20,D0                        | subtract 32 from count
        BMI.B   BLOCKMOVE_CONT_4                | < 32 bytes? -> small copy
        CMPI.L  #0xA0,D0                        | >= 192 bytes? -> use MOVEM
        BLT.B   BLOCKMOVE_LOOP_4                | no -> 32-byte loop
        MOVEM.L D3-D7/A2-A6,-(SP)               | save registers for MOVEM copy
        SUBI.L  #0x30,D0                        | adjust count for 48-byte chunks
        ADDA    #0x30,A1                        | pre-advance dst for predecrement
BLOCKMOVE_LOOP_3:
        MOVEM.L (A0)+,D1-D7/A2-A6               | load 48 bytes (12 longs) from src
        MOVEM.L D1-D7/A2-A6,-(A1)               | store 48 bytes to dst (predecrement)
        ADDA    #0x60,A1                        | re-advance dst past written data
        SUBI.L  #0x30,D0                        | subtract 48 from count
        BGT.B   BLOCKMOVE_LOOP_3                | > 0? -> continue MOVEM loop
        SUBA    #0x30,A1                        | undo dst pre-advance
        ADDI    #0x30,D0                        | adjust count back
        MOVEM.L (SP)+,D3-D7/A2-A6               | restore registers
BLOCKMOVE_LOOP_4:
        MOVE.L  (A0)+,(A1)+                     | copy long 1 of 8
        MOVE.L  (A0)+,(A1)+                     | copy long 2 of 8
        MOVE.L  (A0)+,(A1)+                     | copy long 3 of 8
        MOVE.L  (A0)+,(A1)+                     | copy long 4 of 8
        MOVE.L  (A0)+,(A1)+                     | copy long 5 of 8
        MOVE.L  (A0)+,(A1)+                     | copy long 6 of 8
        MOVE.L  (A0)+,(A1)+                     | copy long 7 of 8
        MOVE.L  (A0)+,(A1)+                     | copy long 8 of 8
        SUBI    #0x20,D0                        | subtract 32 from count
        BGE.B   BLOCKMOVE_LOOP_4                | >= 0? -> continue loop
BLOCKMOVE_CONT_4:
        ADD     D0,D0                           | D0 * 2 = jump table offset
        JMP     BLOCKMOVE_CONT_45(PC,D0.W)      | jump into unrolled long-copy tail

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_5
|
| Called during boot.
BLOCKMOVE_CONT_5:
        MOVE.L  (A0)+,(A1)+                     | copy long 7
BLOCKMOVE_CONT_6:
        MOVE.L  (A0)+,(A1)+                     | copy long 6
BLOCKMOVE_CONT_7:
        MOVE.L  (A0)+,(A1)+                     | copy long 5
BLOCKMOVE_CONT_8:
        MOVE.L  (A0)+,(A1)+                     | copy long 4
BLOCKMOVE_CONT_9:
        MOVE.L  (A0)+,(A1)+                     | copy long 3
BLOCKMOVE_CONT_10:
        MOVE.L  (A0)+,(A1)+                     | copy long 2
BLOCKMOVE_CONT_11:
        MOVE.L  (A0)+,(A1)+                     | copy long 1
BLOCKMOVE_CONT_12:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_13
|
| Called during boot.
BLOCKMOVE_CONT_13:
        BRA.B   BLOCKMOVE_CONT_12               | -> 0 longs remaining

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_14
|
| Called during boot.
BLOCKMOVE_CONT_14:
        BRA.B   BLOCKMOVE_CONT_61               | -> 0 longs + 3 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_15
|
| Called during boot.
BLOCKMOVE_CONT_15:
        BRA.B   BLOCKMOVE_CONT_52               | -> 0 longs + 2 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_16
|
| Called during boot.
BLOCKMOVE_CONT_16:
        BRA.B   BLOCKMOVE_CONT_60               | -> 0 longs + 1 byte (via BLOCKMOVE_CONT_60)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_17
|
| Called during boot.
BLOCKMOVE_CONT_17:
        BRA.B   BLOCKMOVE_CONT_11               | -> 7 longs remaining

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_18
|
| Called during boot.
BLOCKMOVE_CONT_18:
        BRA.B   BLOCKMOVE_CONT_68               | -> 7 longs + 3 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_19
|
| Called during boot.
BLOCKMOVE_CONT_19:
        BRA.B   BLOCKMOVE_CONT_51               | -> 7 longs + 2 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_20
|
| Called during boot.
BLOCKMOVE_CONT_20:
        BRA.B   BLOCKMOVE_CONT_59               | -> 7 longs + 1 byte

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_21
|
| Called during boot.
BLOCKMOVE_CONT_21:
        BRA.B   BLOCKMOVE_CONT_10               | -> 6 longs remaining

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_22
|
| Called during boot.
BLOCKMOVE_CONT_22:
        BRA.B   BLOCKMOVE_CONT_67               | -> 6 longs + 3 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_23
|
| Called during boot.
BLOCKMOVE_CONT_23:
        BRA.B   BLOCKMOVE_CONT_50               | -> 6 longs + 2 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_24
|
| Called during boot.
BLOCKMOVE_CONT_24:
        BRA.B   BLOCKMOVE_CONT_58               | -> 6 longs + 1 byte

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_25
|
| Called during boot.
BLOCKMOVE_CONT_25:
        BRA.B   BLOCKMOVE_CONT_9                | -> 5 longs remaining

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_26
|
| Called during boot.
BLOCKMOVE_CONT_26:
        BRA.B   BLOCKMOVE_CONT_66               | -> 5 longs + 3 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_27
|
| Called during boot.
BLOCKMOVE_CONT_27:
        BRA.B   BLOCKMOVE_CONT_49               | -> 5 longs + 2 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_28
|
| Called during boot.
BLOCKMOVE_CONT_28:
        BRA.B   BLOCKMOVE_CONT_57               | -> 5 longs + 1 byte

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_29
|
| Called during boot.
BLOCKMOVE_CONT_29:
        BRA.B   BLOCKMOVE_CONT_8                | -> 4 longs remaining

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_30
|
BLOCKMOVE_CONT_30:
        BRA.B   BLOCKMOVE_CONT_65               | -> 4 longs + 3 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_31
|
| Called during boot.
BLOCKMOVE_CONT_31:
        BRA.B   BLOCKMOVE_CONT_48               | -> 4 longs + 2 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_32
|
BLOCKMOVE_CONT_32:
        BRA.B   BLOCKMOVE_CONT_56               | -> 4 longs + 1 byte

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_33
|
| Called during boot.
BLOCKMOVE_CONT_33:
        BRA.B   BLOCKMOVE_CONT_7                | -> 3 longs remaining

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_34
|
BLOCKMOVE_CONT_34:
        BRA.B   BLOCKMOVE_CONT_64               | -> 3 longs + 3 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_35
|
BLOCKMOVE_CONT_35:
        BRA.B   BLOCKMOVE_CONT_47               | -> 3 longs + 2 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_36
|
BLOCKMOVE_CONT_36:
        BRA.B   BLOCKMOVE_CONT_55               | -> 3 longs + 1 byte

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_37
|
| Called during boot.
BLOCKMOVE_CONT_37:
        BRA.B   BLOCKMOVE_CONT_6                | -> 2 longs remaining

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_38
|
BLOCKMOVE_CONT_38:
        BRA.B   BLOCKMOVE_CONT_63               | -> 2 longs + 3 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_39
|
| Called during boot.
BLOCKMOVE_CONT_39:
        BRA.B   BLOCKMOVE_CONT_46               | -> 2 longs + 2 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_40
|
BLOCKMOVE_CONT_40:
        BRA.B   BLOCKMOVE_CONT_54               | -> 2 longs + 1 byte

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_41
|
| Called during boot.
BLOCKMOVE_CONT_41:
        BRA.B   BLOCKMOVE_CONT_5                | -> 1 long remaining

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_42
|
BLOCKMOVE_CONT_42:
        BRA.B   BLOCKMOVE_CONT_62               | -> 1 long + 3 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_43
|
| Called during boot.
BLOCKMOVE_CONT_43:
        BRA.B   BLOCKMOVE_CONT_45               | -> 1 long + 2 bytes

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_44
|
BLOCKMOVE_CONT_44:
        BRA.B   BLOCKMOVE_CONT_53               | -> 1 long + 1 byte

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_45
|
| Called during boot.
BLOCKMOVE_CONT_45:
        MOVE.L  (A0)+,(A1)+                     | copy long 8
BLOCKMOVE_CONT_46:
        MOVE.L  (A0)+,(A1)+                     | copy long 7
BLOCKMOVE_CONT_47:
        MOVE.L  (A0)+,(A1)+                     | copy long 6
BLOCKMOVE_CONT_48:
        MOVE.L  (A0)+,(A1)+                     | copy long 5
BLOCKMOVE_CONT_49:
        MOVE.L  (A0)+,(A1)+                     | copy long 4
BLOCKMOVE_CONT_50:
        MOVE.L  (A0)+,(A1)+                     | copy long 3
BLOCKMOVE_CONT_51:
        MOVE.L  (A0)+,(A1)+                     | copy long 2
BLOCKMOVE_CONT_52:
        MOVE    (A0)+,(A1)+                     | copy word tail
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_53
|
BLOCKMOVE_CONT_53:
        MOVE.L  (A0)+,(A1)+                     | copy long 8
BLOCKMOVE_CONT_54:
        MOVE.L  (A0)+,(A1)+                     | copy long 7
BLOCKMOVE_CONT_55:
        MOVE.L  (A0)+,(A1)+                     | copy long 6
BLOCKMOVE_CONT_56:
        MOVE.L  (A0)+,(A1)+                     | copy long 5
BLOCKMOVE_CONT_57:
        MOVE.L  (A0)+,(A1)+                     | copy long 4
BLOCKMOVE_CONT_58:
        MOVE.L  (A0)+,(A1)+                     | copy long 3
BLOCKMOVE_CONT_59:
        MOVE.L  (A0)+,(A1)+                     | copy long 2
BLOCKMOVE_CONT_60:
        MOVE    (A0)+,(A1)+                     | copy word
BLOCKMOVE_CONT_61:
        MOVE.B  (A0)+,(A1)+                     | copy trailing byte
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_62
|
BLOCKMOVE_CONT_62:
        MOVE.L  (A0)+,(A1)+                     | copy long 8
BLOCKMOVE_CONT_63:
        MOVE.L  (A0)+,(A1)+                     | copy long 7
BLOCKMOVE_CONT_64:
        MOVE.L  (A0)+,(A1)+                     | copy long 6
BLOCKMOVE_CONT_65:
        MOVE.L  (A0)+,(A1)+                     | copy long 5
BLOCKMOVE_CONT_66:
        MOVE.L  (A0)+,(A1)+                     | copy long 4
BLOCKMOVE_CONT_67:
        MOVE.L  (A0)+,(A1)+                     | copy long 3
BLOCKMOVE_CONT_68:
        MOVE.L  (A0)+,(A1)+                     | copy long 2
        MOVE.B  (A0)+,(A1)+                     | copy trailing byte
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_69
|
| Called during boot (3,684 times in 30s trace).
BLOCKMOVE_CONT_69:
        LSR     #0x1,D2                         | src odd?
        BCC.B   BLOCKMOVE_NO_5                  | no -> already aligned
        MOVE.B  -(A0),-(A1)                     | copy 1 byte to align (backward)
        SUBQ.L  #0x1,D0                         | decrement count
BLOCKMOVE_NO_5:
        SUBI.L  #0x20,D0                        | subtract 32 from count
        BMI.B   BLOCKMOVE_CONT_70               | < 32? -> small copy
        CMPI.L  #0xA0,D0                        | >= 192 bytes? -> use MOVEM
        BLT.B   BLOCKMOVE_LOOP_6                | no -> 32-byte loop
        MOVEM.L D3-D7/A2-A6,-(SP)               | save registers for MOVEM
        SUBI.L  #0x30,D0                        | adjust for 48-byte chunks
        SUBA    #0x30,A0                        | pre-retreat src for postincrement
BLOCKMOVE_LOOP_5:
        MOVEM.L (A0)+,D1-D7/A2-A6               | load 48 bytes from src
        MOVEM.L D1-D7/A2-A6,-(A1)               | store 48 bytes to dst (predecrement)
        SUBA    #0x60,A0                        | re-retreat src past read data
        SUBI.L  #0x30,D0                        | subtract 48 from count
        BGT.B   BLOCKMOVE_LOOP_5                | > 0? -> continue MOVEM loop
        ADDA    #0x30,A0                        | undo src pre-retreat
        ADDI    #0x30,D0                        | adjust count back
        MOVEM.L (SP)+,D3-D7/A2-A6               | restore registers
BLOCKMOVE_LOOP_6:
        MOVE.L  -(A0),-(A1)                     | copy long 8 of 8 (backward)
        MOVE.L  -(A0),-(A1)                     | copy long 7
        MOVE.L  -(A0),-(A1)                     | copy long 6
        MOVE.L  -(A0),-(A1)                     | copy long 5
        MOVE.L  -(A0),-(A1)                     | copy long 4
        MOVE.L  -(A0),-(A1)                     | copy long 3
        MOVE.L  -(A0),-(A1)                     | copy long 2
        MOVE.L  -(A0),-(A1)                     | copy long 1
        SUBI    #0x20,D0                        | subtract 32 from count
        BGE.B   BLOCKMOVE_LOOP_6                | >= 0? -> continue loop
BLOCKMOVE_CONT_70:
        ADD     D0,D0                           | D0 * 2 = jump table offset
        JMP     BCPY_WD7(PC,D0.W)               | jump into unrolled backward tail

| ----------------------------------------------------------
|
| BLOCKMOVE_LOOP_7
|
| Called during boot.
BLOCKMOVE_LOOP_7:
        MOVE.L  -(A0),-(A1)                     | copy long 7 (backward)
BLOCKMOVE_LOOP_8:
        MOVE.L  -(A0),-(A1)                     | copy long 6
BLOCKMOVE_LOOP_9:
        MOVE.L  -(A0),-(A1)                     | copy long 5
BLOCKMOVE_CONT_71:
        MOVE.L  -(A0),-(A1)                     | copy long 4
BLOCKMOVE_CONT_72:
        MOVE.L  -(A0),-(A1)                     | copy long 3
BLOCKMOVE_CONT_73:
        MOVE.L  -(A0),-(A1)                     | copy long 2
BLOCKMOVE_CONT_74:
        MOVE.L  -(A0),-(A1)                     | copy long 1
BLOCKMOVE_CONT_75:
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_76
|
| Called during boot.
BLOCKMOVE_CONT_76:
        BRA.B   BLOCKMOVE_CONT_75               | -> 0 longs remaining (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_77
|
| Called during boot.
BLOCKMOVE_CONT_77:
        BRA.B   BCPY_WDB_TAIL                   | -> 0 longs + 3 bytes (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_78
|
| Called during boot.
BLOCKMOVE_CONT_78:
        BRA.B   BCPY_WD_TAIL                    | -> 0 longs + 2 bytes (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_79
|
| Called during boot.
BLOCKMOVE_CONT_79:
        BRA.B   BCPY_WDB_WORD                   | -> 0 longs + 1 byte (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_80
|
| Called during boot.
BLOCKMOVE_CONT_80:
        BRA.B   BLOCKMOVE_CONT_74               | -> 7 longs remaining (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_81
|
| Called during boot.
BLOCKMOVE_CONT_81:
        BRA.B   BCPY_BT1                        | -> 7 longs + 3 bytes (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_82
|
| Called during boot (1,364 times in 30s trace).
BLOCKMOVE_CONT_82:
        BRA.B   BCPY_WD1                        | -> 7 longs + 2 bytes (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_83
|
BLOCKMOVE_CONT_83:
        BRA.B   BCPY_WDB1                       | -> 7 longs + 1 byte (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_84
|
| Called during boot.
BLOCKMOVE_CONT_84:
        BRA.B   BLOCKMOVE_CONT_73               | -> 6 longs remaining (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_85
|
| Called during boot.
BLOCKMOVE_CONT_85:
        BRA.B   BCPY_BT2                        | -> 6 longs + 3 bytes (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_86
|
| Called during boot (1,065 times in 30s trace).
BLOCKMOVE_CONT_86:
        BRA.B   BCPY_WD2                        | -> 6 longs + 2 bytes (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_87
|
| Called during boot.
BLOCKMOVE_CONT_87:
        BRA.B   BCPY_WDB2                       | -> 6 longs + 1 byte (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_88
|
| Called during boot.
BLOCKMOVE_CONT_88:
        BRA.B   BLOCKMOVE_CONT_72               | -> 5 longs remaining (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_89
|
BLOCKMOVE_CONT_89:
        BRA.B   BCPY_BT3                        | -> 5 longs + 3 bytes (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_90
|
| Called during boot.
BLOCKMOVE_CONT_90:
        BRA.B   BCPY_WD3                        | -> 5 longs + 2 bytes (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_91
|
| Called during boot.
BLOCKMOVE_CONT_91:
        BRA.B   BCPY_WDB3                       | -> 5 longs + 1 byte (backward)

| ----------------------------------------------------------
|
| BLOCKMOVE_CONT_92
|
| Called during boot.
BLOCKMOVE_CONT_92:
        BRA.B   BLOCKMOVE_CONT_71               | -> 4 longs remaining (backward)

