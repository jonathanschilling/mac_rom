| Toolbox Utilities -- _Munger, _HandToHand, _PtrToXHand, _PtrToHand, _HandAndHand, _PtrAndHand
|
| Apple source: Munger.a (MacSEROM.lst module BYTES): Munger searches for,
| replaces, inserts or deletes bytes in a handle; the others copy or
| concatenate data into handles (register interface A0/A1/D0). The 64K
| ROM's fixed-point routines are not here but in toolbox/fixmath.s,
| inside the QuickDraw area.
|
| References: Inside Macintosh Vol I, Ch 16 (Toolbox Utilities: Munger);
| Inside Macintosh Vol II, Ch 13 (Operating System Utilities: HandToHand ...)

| ----------------------------------------------------------
|
| _Munger ($A9E0): find, replace, insert or delete bytes in a handle
| Pascal: FUNCTION Munger(h: Handle; offset: LongInt; ptr1: Ptr; len1: LongInt;
|                         ptr2: Ptr; len2: LongInt): LongInt;
| len1 = 0: insert (ptr2,len2) at offset. len1 < 0, or offset+len1 past
| the end: len1 := size-offset; len1 > size: not found. ptr1 = NIL: the
| len1 bytes at offset are the target; else (ptr1,len1) is searched for
| from offset. ptr2 = NIL just returns the match offset; otherwise the
| target is deleted (BlockMove down, SetHandleSize) and (ptr2,len2), if
| len2 <> 0, inserted there (SetHandleSize, BlockMove up, copy).
| Exit: result = offset of the target or insertion point, -1 if not
| found. (The Plus version returns offset+len2 after an insertion, as
| documented in IM; this one returns the start offset.)
|
Munger:
        LINK    A6,#0x0                         | no locals
        MOVEM.L D2-D7/A2-A4,-(SP)               | save working registers
        MOVE.L  28(A6),A2                       | A2 = target handle
        MOVE.L  A2,A0                           | A0 = handle for GetHandleSize
        _GetHandleSize                          | D0 = current handle size
        MOVE.L  D0,D5                           | D5 = handle size
        MOVE.L  24(A6),D2                       | D2 = offset
        MOVE.L  20(A6),A3                       | A3 = ptr1 (search pattern)
        MOVE.L  12(A6),A4                       | A4 = ptr2 (replacement)
        MOVE.L  16(A6),D3                       | D3 = len1 (search length)
        BEQ.B   MUNGER_NO_2                     | len=0: skip search, just insert at offset
        BPL.B   MUNGER_OK                       | positive length: use as-is
MUNGER_CONT_2:
        MOVE.L  D5,D3                           | len1 < 0 or too long: len1 := size-offset
        SUB.L   D2,D3                           | D3 = remaining bytes from offset
MUNGER_OK:
        MOVE.L  D5,D0                           | D0 = handle data size
        SUB.L   D3,D0                           | D0 = size - searchLen
        BLT.B   MUNGER_FOUND                    | pattern longer than data: not found
        SUB.L   D2,D0                           | D0 = bytes available after offset
        BLT.B   MUNGER_CONT_2                   | offset+len1 > size: len1 := size-offset
        MOVE.L  A3,D0                           | test search pointer
        BEQ.B   MUNGER_EMPTY                    | nil search ptr: delete D3 bytes at offset
        MOVE.L  (A2),D6                         | D6 = dereferenced handle base address
        MOVE.L  D5,D7                           | D7 = end limit for search
        ADD.L   D6,D7                           | D7 = absolute end address
        ADD.L   D2,D6                           | D6 = absolute start address (base+offset)
MUNGER_RETRY:
        MOVE.L  D3,D1                           | D1 = pattern length for comparison
        MOVE.L  D6,A0                           | A0 = current position in handle data
        MOVE.L  A3,A1                           | A1 = search pattern pointer
MUNGER_LOOP:
        CMP.L   D6,D7                           | past end of searchable region?
        BCS.B   MUNGER_FOUND                    | yes: pattern not found
        CMPM.B  (A0)+,(A1)+                     | compare next pattern byte
        BNE.B   MUNGER_NEXT                     | mismatch: advance to next position
        SUBQ.L  #0x1,D1                         | decrement pattern bytes left
        BNE.B   MUNGER_LOOP                     | continue comparing pattern bytes
        MOVE.L  D6,D2                           | match found: D2 = match address
        SUB.L   (A2),D2                         | convert to offset from handle start
        BRA.B   MUNGER_CONT_6                   | go perform replacement
MUNGER_NEXT:
        ADDQ.L  #0x1,D6                         | move to next byte in handle data
        BRA.B   MUNGER_RETRY                    | retry pattern match from new position
MUNGER_FOUND:                                   | not-found exit (despite the name)
        MOVEQ.L #-0x1,D2                        | D2 = -1 (not found sentinel)
        BRA.B   ENTRY_5_CONT_13                 | return not-found result
MUNGER_CONT_6:
        MOVE.L  A4,D0                           | test replacement pointer
        BEQ.B   ENTRY_5_CONT_13                 | nil: search-only, return offset
MUNGER_EMPTY:
        MOVE.L  D5,D0                           | D0 = handle data size
        SUB.L   D3,D0                           | subtract search pattern length
        MOVE.L  D0,D5                           | D5 = new size after deletion
        SUB.L   D2,D0                           | D0 = bytes after match to move
        MOVE.L  (A2),A1                         | A1 = handle base (dest for move)
        ADDA.L  D2,A1                           | A1 = match position (destination)
        MOVE.L  A1,A0                           | A0 = source: end of matched region
        ADDA.L  D3,A0                           | advance past matched bytes
        _BlockMove                              | move trailing data over deleted region
        MOVE.L  A2,A0                           | A0 = handle
        MOVE.L  D5,D0                           | D0 = new (smaller) size
        _SetHandleSize                          | shrink handle to new (smaller) size
MUNGER_NO_2:
        MOVE.L  8(A6),D4                        | D4 = replacement length
        BEQ.B   ENTRY_5_CONT_13                 | zero length: nothing to insert
        MOVE.L  D5,D0                           | D0 = current handle size
        ADD.L   D4,D0                           | D0 = new size after insertion
        MOVE.L  A2,A0                           | A0 = handle
        _SetHandleSize                          | grow handle to fit insertion
        BNE.B   ENTRY_5_CONT_13                 | resize failed: abort
        MOVE.L  (A2),A1                         | A1 = handle base (may have moved)
        ADDA.L  D2,A1                           | A1 = insertion point
        MOVE.L  A1,A0                           | A0 = insertion point (tail source)
        ADDA.L  D4,A1                           | A1 = shifted dest past insertion
        MOVE.L  D5,D0                           | D0 = trailing bytes to move
        SUB.L   D2,D0                           | subtract offset from total
        _BlockMove                              | shift trailing data forward
        MOVE.L  (A2),A1                         | A1 = handle base (may have moved)
        ADDA.L  D2,A1                           | A1 = dest for replacement data
        MOVE.L  A4,A0                           | A0 = replacement data source
        MOVE.L  D4,D0                           | D0 = replacement data length
        _BlockMove                              | copy replacement data into handle
ENTRY_5_CONT_13:                                | Munger exit: result = D2
        MOVE.L  D2,0x20(A6)                     | store result offset in return slot
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore working registers
        UNLK    A6                              | tear down frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA.W  #0x18,SP                        | strip 24 bytes of params
        JMP     (A0)                            | RTS

| ----------------------------------------------------------
| HandToHand -- _HandToHand ($A9E1).
| Make a copy of a handle. Entry: A0 = source handle.
| Exit: A0 = new handle (copy).
HandToHand:
        MOVE.L  A0,A1                           | A1 = source handle (saved for deref)
        _GetHandleSize                          | D0 = source size
        MOVE.L  D0,D1                           | D1 = byte count
        _NewHandle                              | A0 = new handle
        MOVE.L  (A1),A1                         | A1 = source data ptr
        BRA.B   PTRTOHAND_CONT                  | -> common copy path

| ----------------------------------------------------------
| PtrToXHand -- _PtrToXHand ($A9E2).
| Copy D0 bytes from ptr A0 into existing handle A1.
PtrToXHand:
        EXG     A0,A1                           | A0 = dest handle, A1 = source ptr
        MOVE.L  D0,D1                           | D1 = byte count
        _SetHandleSize                          | resize handle to D1 bytes
        BRA.B   PTRTOHAND_CONT                  | -> common copy path

| ----------------------------------------------------------
| PtrToHand -- _PtrToHand ($A9E3).
| Create a new handle and copy D0 bytes from ptr A0.
PtrToHand:
        MOVE.L  A0,A1                           | A1 = source ptr
        MOVE.L  D0,D1                           | D1 = byte count
        _NewHandle                              | A0 = new handle
PTRTOHAND_CONT:
        BNE.B   PTRTOHAND_ERR                   | NewHandle/SetHandleSize failed: bail
        MOVEQ.L #0x0,D2                         | dest offset = 0
PTRTOHAND_CONT_2:
        MOVE.L  A0,-(SP)                        | save dest handle for return
        MOVE.L  (A0),A0                         | dereference dest handle to data ptr
        ADDA.L  D2,A0                           | advance to dest offset
        EXG     A0,A1                           | A0=src ptr, A1=dest data ptr
        MOVE.L  D1,D0                           | D0 = byte count for BlockMove
        _BlockMove                              | copy bytes from source to handle data
        MOVE.L  (SP)+,A0                        | restore handle in A0
PTRTOHAND_ERR:
        RTS                                     | return (also the error exit)
| ----------------------------------------------------------
|
| _HandAndHand ($A9E4): append the data of handle A0 to handle A1
| Pascal: FUNCTION HandAndHand(aHndl, bHndl: Handle): OSErr;
| Entry: A0 = aHndl (source), A1 = bHndl (destination)
| Exit:  A0 = bHndl, D0 = result code
| D0 := GetHandleSize(aHndl), A0 := aHndl^, then falls into PtrAndHand.
| Note: the source is dereferenced before bHndl is grown; the Plus
| version dereferences it after the _SetHandleSize.
|
HandAndHand:
        _GetHandleSize                          | D0 = size of aHndl
        MOVEA.L (A0),A0                         | A0 = aHndl^ (source data)
| ----------------------------------------------------------
|
| _PtrAndHand ($A9EF): append D0 bytes from pointer A0 to handle A1
| Pascal: FUNCTION PtrAndHand(pntr: Ptr; hndl: Handle; size: LongInt): OSErr;
| Entry: A0 = source pointer, A1 = handle, D0 = byte count
| Exit:  A0 = handle, D0 = result code
| Grows the handle by D0 bytes (_SetHandleSize) and copies the data to
| its old end through PtrToHand's copy tail (PTRTOHAND_CONT_2).
|
PtrAndHand:
        MOVE.L  D0,D1                           | D1 = source byte count
        EXG     A1,A0                           | A0=dest handle, A1=source ptr
        _GetHandleSize                          | D0 = current dest size
        MOVE.L  D0,D2                           | D2 = old size = append offset
        ADD.L   D1,D0                           | D0 = oldSize + addLen
        _SetHandleSize                          | grow dest handle to new size
        BNE.B   PTRTOHAND_ERR                   | SetHandleSize failed: abort
        BRA.B   PTRTOHAND_CONT_2                | share copy path (D2 = old end)
