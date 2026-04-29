| Toolbox Miscellaneous Utilities
|
| This file holds a cluster of small Toolbox utility routines that
| share a single ROM region for space reasons. They cross several
| logical subsystems (Memory Manager helpers, QuickDraw color stubs,
| MacApp dispatch, fixed-point math, a handful of Dialog Manager
| extras). They sit between dialog_mgr.s (Dialog Manager internals)
| and fixmath.s (SANE math tail + Fix2X/X2Fix conversions + SystemEvent).
|
| Routine groups, in physical ROM order:
|   _Munger                                     (Memory Manager search/replace)
|   GetForeColor                                (QuickDraw color stub)
|   _HandToHand, _PtrToXHand, _PtrToHand,
|   _HandAndHand, _PtrAndHand                   (Memory Manager helpers)
|   StdOpcodeProc                               (MacApp dispatch hook)
|   LongMul, RestoreEntries, FixMul, ALGORITHM  (basic fixed-point math)
|   NewCDialog, DelComp                         (Dialog Manager overflow)
|   SaveEntries                                 (math helper)
|   FixRatio, LoWord, HiWord, FixRound          (more fixed-point math)
|   SetDeskCPat, GetCWMgrPort                   (Color/Window-Mgr stubs)
|
| Files cannot be reordered (ROM byte order is fixed); these routines
| live together because the ROM image places them adjacent.

| ----------------------------------------------------------
|
| _Munger ($A9E0)
|
| _Munger: search and replace bytes within a handle.
| Stack frame: handle(+$1C), offset(+$18), ptr1(+$14),
| len1(+$10), ptr2(+$0C), len2(+$08). Result at +$20.
| Searches for ptr1[len1] starting at offset in handle,
| replaces match with ptr2[len2]. Returns offset past match.
Munger:
        LINK    A6,#-0x8                        | locals: -8(A6)=origSize, -4(A6)=sizeDelta
        MOVEM.L D2-D7/A2-A4,-(SP)               | save all working registers
        MOVE.L  0x1C(A6),A2                     | A2 = target handle
        MOVE.L  A2,A0                           | A0 = handle for GetHandleSize
        _GetHandleSize                          | D0 = current handle size
        MOVE.L  D0,D5                           | D5 = handle size (working copy)
        MOVE.L  D0,-0x8(A6)                     | save original size in local
        CLR.L   -0x4(A6)                        | size delta = 0 (no replacement yet)
        BSR.B   GETFORECOLOR_CONT               | perform search/replace operation
        MOVE.L  D2,0x20(A6)                     | store result offset in return value slot
        MOVEQ.L #0x18,D1                        | 24 bytes of params to strip from stack
MUNGER_CONT:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore registers
        UNLK    A6                              | discard local frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    D1,SP                           | strip parameters from stack
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
| GetForeColor - _Munger variant with explicit offset and size.
| Extended stack frame with extra params at +$24 and +$20.
| Used when caller provides both search offset and handle size.
| ----------------------------------------------------------
GetForeColor:
        LINK    A6,#-0x8                        | locals: -8(A6)=origSize, -4(A6)=sizeDelta
        MOVEM.L D2-D7/A2-A4,-(SP)               | save all working registers
        MOVE.L  0x1C(A6),A2                     | A2 = target handle
        MOVE.L  A2,A0                           | A0 = handle for GetHandleSize
        _GetHandleSize                          | D0 = current handle size
        MOVE.L  D0,-0x8(A6)                     | save original size in local
        MOVE.L  0x24(A6),D5                     | D5 = caller-specified data length
        MOVE.L  0x20(A6),-0x4(A6)               | save caller's size delta in local
        BSR.B   GETFORECOLOR_CONT               | perform search/replace operation
        MOVE.L  D2,0x28(A6)                     | store result offset in return value slot
        MOVEQ.L #0x20,D1                        | 32 bytes of params to strip from stack
        BRA.B   MUNGER_CONT                     | shared epilogue

| ----------------------------------------------------------
| GETFORECOLOR_CONT - Munger core: search for pattern in handle, replace if found.
| Params from stack frame:
| D2 = offset (+$18), A3 = search ptr (+$14),
| A4 = replace ptr (+$0C), D3 = search len (+$10).
| D5 = handle data size. A2 = target handle.
| Returns D2 = offset of match (or -1 if not found).
| ----------------------------------------------------------
GETFORECOLOR_CONT:
        MOVE.L  0x18(A6),D2                     | D2 = starting search offset
        MOVE.L  0x14(A6),A3                     | A3 = search pattern pointer
        MOVE.L  0xC(A6),A4                      | A4 = replacement data pointer
        MOVE.L  0x10(A6),D3                     | D3 = search pattern length
        BEQ     GETFORECOLOR_NO_2               | len=0: no search, just insert at offset
        BPL.B   GETFORECOLOR_OK                 | positive: use as-is
GETFORECOLOR_CONT_2:
        MOVE.L  D5,D3                           | negative len: search from offset to end
        SUB.L   D2,D3                           | D3 = remaining bytes from offset
GETFORECOLOR_OK:
        MOVE.L  D5,D0                           | D0 = handle data size
        SUB.L   D3,D0                           | D0 = size - searchLen
        BLT.B   GETFORECOLOR_FOUND              | pattern longer than data: not found
        SUB.L   D2,D0                           | D0 = bytes available after offset
        BLT.B   GETFORECOLOR_CONT_2             | offset past valid range: clamp
        MOVE.L  A3,D0                           | test search pointer
        BEQ.B   GETFORECOLOR_EMPTY              | nil search ptr: delete D3 bytes at offset
        MOVE.L  (A2),D6                         | D6 = dereferenced handle base address
        MOVE.L  D5,D7                           | D7 = end limit for search
        SUB.L   D3,D7                           | D7 = last valid start position
        ADD.L   D6,D7                           | D7 = absolute end address
        ADD.L   D2,D6                           | D6 = absolute start address (base+offset)
GETFORECOLOR_RETRY:
        MOVE.L  D3,D1                           | D1 = pattern length for comparison
        SUBQ.L  #0x1,D1                         | adjust for DBF loop (count-1)
        MOVE.L  D6,A0                           | A0 = current position in handle data
        MOVE.L  A3,A1                           | A1 = search pattern pointer
GETFORECOLOR_LOOP:
        CMP.L   D6,D7                           | past end of searchable region?
        BCS.B   GETFORECOLOR_FOUND              | yes: pattern not found
        CMPM.B  (A0)+,(A1)+                     | compare next byte of pattern
        BNE.B   GETFORECOLOR_NEXT               | mismatch: advance to next position
        DBF     D1,GETFORECOLOR_LOOP            | continue comparing pattern bytes
        MOVE.L  D6,D2                           | match found: D2 = absolute match address
        SUB.L   (A2),D2                         | convert to offset from handle start
        BRA.B   GETFORECOLOR_CONT_6             | go perform replacement

| ----------------------------------------------------------
| GETFORECOLOR_NEXT - Advance search position by one byte and retry.
| ----------------------------------------------------------
GETFORECOLOR_NEXT:
        ADDQ.L  #0x1,D6                         | move to next byte in handle data
        BRA.B   GETFORECOLOR_RETRY              | retry pattern match from new position

| ----------------------------------------------------------
| GETFORECOLOR_FOUND - Search failed: pattern not found in handle.
| ----------------------------------------------------------
GETFORECOLOR_FOUND:
        MOVEQ.L #-0x1,D2                        | D2 = -1 (not found sentinel)
        BRA.B   GETFORECOLOR_EXIT_2             | return not-found result

| ----------------------------------------------------------
| GETFORECOLOR_CONT_3 - Move D0 bytes from A0 to A1 (safe for overlapping regions).
| Handles zero-length and single-byte cases without BlockMove.
| ----------------------------------------------------------
GETFORECOLOR_CONT_3:
        CMPA.L  A0,A1                           | source == dest?
        BEQ.B   GETFORECOLOR_EXIT               | yes: nothing to move
        SUBQ.L  #0x1,D0                         | adjust count for BlockMove (needs count-1)
        BLE.B   GETFORECOLOR_CONT_4             | 0 or 1 byte: handle specially
        ADDQ.L  #0x1,D0                         | restore count for BlockMove
        _BlockMove                              | move D0 bytes from A0 to A1
        RTS                                     | return from BlockMove

| ----------------------------------------------------------
| GETFORECOLOR_CONT_4 - Handle 0 or 1 byte move without BlockMove.
| ----------------------------------------------------------
GETFORECOLOR_CONT_4:
        BLT.B   GETFORECOLOR_EXIT               | count was 0: nothing to move
        MOVE.B  (A0),(A1)                       | move single byte
GETFORECOLOR_EXIT:
        MOVEQ.L #0x0,D0                         | clear D0 (success)
        RTS                                     | return from single byte move

| ----------------------------------------------------------
| ENTRY_6 - Resize handle if new size differs from original.
| Entry: D0 = desired new size. Uses -8(A6) = original size,
| -4(A6) = slack tolerance. Only resizes if change exceeds slack.
| ----------------------------------------------------------
ENTRY_6:
        MOVE.L  D0,-(SP)                        | save desired size
        SUB.L   -0x8(A6),D0                     | D0 = desired - original size
        BEQ.B   GETFORECOLOR_NO                 | same size: no resize needed
        BGT.B   GETFORECOLOR_CONT_5             | growing: must resize
        NEG.L   D0                              | D0 = amount of shrinkage
        CMP.L   -0x4(A6),D0                     | compare shrinkage vs slack tolerance
        BGT.B   GETFORECOLOR_CONT_5             | shrunk more than slack: resize
GETFORECOLOR_NO:
        ADDQ.W  #0x4,SP                         | discard saved size (no resize needed)
        BRA.B   GETFORECOLOR_EXIT               | return success (D0=0)

| ----------------------------------------------------------
| GETFORECOLOR_CONT_5 - Resize handle to new size (adding slack tolerance).
| ----------------------------------------------------------
GETFORECOLOR_CONT_5:
        MOVE.L  (SP)+,D0                        | restore desired size
        ADD.L   -0x4(A6),D0                     | add slack tolerance to new size
        _SetHandleSize                          | resize the handle
        RTS                                     | return from handle resize

| ----------------------------------------------------------
| GETFORECOLOR_CONT_6 - Pattern found at offset D2: perform replacement.
| If replacement ptr (A4) is nil, return match offset only.
| Otherwise fall through to delete matched bytes and insert.
| ----------------------------------------------------------
GETFORECOLOR_CONT_6:
        MOVE.L  A4,D0                           | test replacement pointer
        BEQ.B   GETFORECOLOR_EXIT_2             | nil: search-only, return offset
GETFORECOLOR_EMPTY:
        MOVE.L  0x8(A6),D4                      | D4 = replacement length from frame
        BNE.B   GETFORECOLOR_EMPTY_2            | non-zero: replace different lengths
        MOVE.L  D5,D0                           | D0 = handle data size
        SUB.L   D3,D0                           | subtract search pattern length
        MOVE.L  D0,D5                           | D5 = new size after deletion
        SUB.L   D2,D0                           | D0 = bytes after match to move
        MOVE.L  (A2),A1                         | A1 = handle base (dest for move)
        ADDA.L  D2,A1                           | A1 = match position (destination)
        MOVE.L  A1,A0                           | A0 = source: end of matched region
        ADDA.L  D3,A0                           | advance past matched bytes
        BSR.B   GETFORECOLOR_CONT_3             | move trailing data over deleted region
        MOVE.L  A2,A0                           | A0 = handle for resize
        MOVE.L  D5,D0                           | D0 = new (smaller) handle size
        BSR.B   ENTRY_6                         | shrink handle if beyond slack
GETFORECOLOR_EXIT_2:
        BRA.B   GETFORECOLOR_ERR                | return

| ----------------------------------------------------------
| GETFORECOLOR_NO_2 - No search pattern (D3=0): pure insert at offset D2.
| Inserts D4 bytes of replacement data at the given offset.
| ----------------------------------------------------------
GETFORECOLOR_NO_2:
        MOVE.L  0x8(A6),D4                      | D4 = replacement length
        BEQ.B   GETFORECOLOR_ERR                | zero length: nothing to insert
        MOVE.L  D5,D0                           | D0 = current handle size
        ADD.L   D4,D0                           | D0 = new size after insertion
        MOVE.L  A2,A0                           | A0 = handle for resize
        BSR.B   ENTRY_6                         | grow handle to fit insertion
        BNE.B   GETFORECOLOR_ERR                | resize failed: abort
        MOVE.L  (A2),A1                         | A1 = handle base
        ADDA.L  D2,A1                           | A1 = insertion point
        MOVE.L  A1,A0                           | A0 = data at insertion point
        ADDA.L  D4,A1                           | A1 = shifted dest past insertion
        MOVE.L  D5,D0                           | D0 = trailing bytes to move
        SUB.L   D2,D0                           | subtract offset from total
        BSR.B   GETFORECOLOR_CONT_3             | shift trailing data forward
GETFORECOLOR_CONT_7:
        MOVE.L  (A2),A1                         | A1 = handle base (may have moved)
        ADDA.L  D2,A1                           | A1 = dest for replacement data
        MOVE.L  A4,A0                           | A0 = replacement data source
        MOVE.L  D4,D0                           | D0 = replacement data length
        BSR     GETFORECOLOR_CONT_3             | copy replacement data into handle
        ADD.L   D4,D2                           | advance offset past inserted data
GETFORECOLOR_ERR:
        RTS                                     | return from Munger replacement

| ----------------------------------------------------------
| GETFORECOLOR_EMPTY_2 - Replace with different-length data.
| D4 = replacement length, D3 = search pattern length.
| Handles both shorter and longer replacements.
| ----------------------------------------------------------
GETFORECOLOR_EMPTY_2:
        MOVE.L  D4,D1                           | D1 = replacement length
        SUB.L   D3,D1                           | D1 = size delta (replace - search)
        BEQ.B   GETFORECOLOR_CONT_7             | same length: overwrite in place
        BGT.B   GETFORECOLOR_CONT_8             | longer: may need to expand first
        BSR.B   GETFORECOLOR_CONT_9             | shorter: collapse gap before resize
GETFORECOLOR_CONT_8:
        MOVE.L  A2,A0                           | A0 = handle for resize
        MOVE.L  D5,D0                           | D0 = current handle data size
        ADD.L   D1,D0                           | D0 = new size (current + delta)
        BSR     ENTRY_6                         | resize handle
        BNE.B   GETFORECOLOR_ERR                | resize failed: abort
        TST.L   D1                              | was replacement longer?
        BMI.B   GETFORECOLOR_CONT_7             | shorter (already collapsed): copy data
        BSR.B   GETFORECOLOR_CONT_9             | longer: expand gap for replacement
        BRA.B   GETFORECOLOR_CONT_7             | copy replacement data into gap

| ----------------------------------------------------------
| GETFORECOLOR_CONT_9 - Shift trailing data within handle to open/close gap.
| Moves bytes from (base+offset+searchLen) to
| (base+offset+replaceLen), covering all trailing data.
| ----------------------------------------------------------
GETFORECOLOR_CONT_9:
        MOVE.L  (A2),A1                         | A1 = handle base address
        ADDA.L  D2,A1                           | A1 = match offset in handle
        MOVE.L  A1,A0                           | A0 = source start
        ADDA.L  D3,A0                           | A0 += searchLen (past matched bytes)
        ADDA.L  D4,A1                           | A1 += replaceLen (replacement end)
        MOVE.L  D5,D0                           | D0 = total handle data size
        SUB.L   D3,D0                           | subtract search pattern length
        SUB.L   D2,D0                           | subtract offset = trailing byte count
        BRA     GETFORECOLOR_CONT_3             | move the trailing data block

| ----------------------------------------------------------
|
| _HandToHand ($A9E1) - Duplicate a handle.
| Entry: A0 = source handle. Exit: A0 = new handle (copy).
| Preserves source handle's master pointer flags byte.
|
HandToHand:
        MOVE.B  (A0),-(SP)                      | save source master pointer flags byte
        MOVE.L  A0,-(SP)                        | save source handle address
        BCLR    #0x6,(A0)                       | clear purgeable bit before copy
        MOVE.L  A0,A1                           | A1 = source handle (for deref later)
        _GetHandleSize                          | D0 = size of source handle data
        TST.L   D0                              | negative = error from GetHandleSize
        BMI.B   HANDTOHAND_ERR                  | error: skip copy, restore flags
        MOVE.L  D0,D1                           | D1 = byte count for BlockMove
        _NewHandle                              | A0 = new handle of same size
        MOVE.L  (A1),A1                         | A1 = dereferenced source data ptr
        BSR.B   PTRTOHAND_CONT                  | copy source data into new handle
HANDTOHAND_ERR:
        MOVE.L  (SP)+,A1                        | restore original source handle
        MOVE.B  (SP)+,(A1)                      | restore master pointer flags byte
        RTS                                     | return from HandToHand

| ----------------------------------------------------------
| _PtrToXHand ($A9E2) - Copy D0 bytes from ptr A0 into
| existing handle A1. Resizes handle to D0 bytes first.
| ----------------------------------------------------------
PtrToXHand:
        EXG     A0,A1                           | A0 = dest handle, A1 = source ptr
        MOVE.L  D0,D1                           | D1 = byte count
        _SetHandleSize                          | resize handle to D1 bytes
        BRA.B   PTRTOHAND_CONT                  | copy data from A1 into handle A0

| ----------------------------------------------------------
| _PtrToHand ($A9E3) - Create new handle with copy of D0
| bytes from ptr A0. Exit: A0 = new handle.
| ----------------------------------------------------------
PtrToHand:
        MOVE.L  A0,A1                           | A1 = source pointer
        MOVE.L  D0,D1                           | D1 = byte count
        _NewHandle                              | A0 = new handle of size D1
| PTRTOHAND_CONT -- copy source data into new handle.
PTRTOHAND_CONT:
        BNE.B   PTRTOHAND_ERR                   | allocation/resize failed: return error
        MOVEQ.L #0x0,D2                         | D2 = 0 (offset = start of handle)
| PTRTOHAND_CONT_2 -- append source data at offset D2.
PTRTOHAND_CONT_2:
        MOVE.L  A0,-(SP)                        | save dest handle on stack
        MOVE.L  (A0),A0                         | dereference dest handle to data ptr
        ADDA.L  D2,A0                           | offset into dest (for append ops)
        EXG     A0,A1                           | A0 = source data, A1 = dest in handle
        MOVE.L  D1,D0                           | D0 = byte count for BlockMove
        _BlockMove                              | copy data into handle
        MOVE.L  (SP)+,A0                        | restore handle in A0
PTRTOHAND_ERR:
        RTS                                     | return from PtrToHand

| ----------------------------------------------------------
| _HandAndHand ($A9E4) - Append handle A0's data to end
| of handle A1. Both handles preserved. A0 flags restored.
| ----------------------------------------------------------
HandAndHand:
        MOVE.B  (A0),-(SP)                      | save source master pointer flags
        MOVE.L  A0,-(SP)                        | save source handle
        BCLR    #0x6,(A0)                       | clear purgeable bit on source
        _GetHandleSize                          | D0 = source handle size
        TST.L   D0                              | negative = error
        BMI.B   HANDTOHAND_ERR                  | error: restore flags and return
        MOVE.L  D0,D1                           | D1 = source byte count to copy
        EXG     A1,A0                           | A0 = dest handle, A1 = source handle
        _GetHandleSize                          | D0 = dest handle current size
        MOVE.L  D0,D2                           | D2 = append offset (old dest size)
        BMI.B   HANDTOHAND_ERR                  | error: restore and return
        ADD.L   D1,D0                           | D0 = new dest size (old + source)
        _SetHandleSize                          | grow dest handle
        BNE.B   HANDTOHAND_ERR                  | resize failed: restore and return
        MOVE.L  (A1),A1                         | dereference source handle for copy
        BSR.B   PTRTOHAND_CONT_2                | append source data at offset D2
        BRA.B   HANDTOHAND_ERR                  | restore source handle flags

| ----------------------------------------------------------
| _PtrAndHand ($A9EF) - Append D0 bytes from ptr A0 to
| end of handle A1. Entry: A0=ptr, A1=handle, D0=count.
| ----------------------------------------------------------
PtrAndHand:
        MOVE.L  D0,D1                           | D1 = byte count to append
        EXG     A1,A0                           | A0 = dest handle, A1 = source ptr
        _GetHandleSize                          | D0 = current handle size
        MOVE.L  D0,D2                           | D2 = append offset (current size)
        ADD.L   D1,D0                           | D0 = new size (current + append)
        _SetHandleSize                          | grow handle
        BNE.B   PTRTOHAND_ERR                   | resize failed: return error
        BRA.B   PTRTOHAND_CONT_2                | copy source data at offset D2

| ----------------------------------------------------------
|
| StdOpcodeProc - MacApp opcode dispatcher.
| Looks up an opcode in a dispatch table, caches result,
| and jumps to the handler. Uses MASuperTab for inheritance.
|
StdOpcodeProc:
        MOVE.L  (SP)+,A0                        | A0 = ptr to inline dispatch table
        MOVE.L  0x4(SP),A1                      | A1 = object handle from stack param
        MOVE.L  (A1),A1                         | dereference object handle
        MOVE    (A1),D0                         | D0 = class ID from object header
        MOVE    (A0)+,D1                        | D1 = entry count - 1 for DBCC loop
        CMP     (A0),D0                         | does cached class ID match?
        BNE.B   STDOPCODEPROC_NO                | no: search table for this class
STDOPCODEPROC_CONT:
        MOVE    0x2(A0),D0                      | D0 = cached handler offset
        BCLR    #0x0,D0                         | test/clear PC-relative flag bit
        BEQ.B   STDOPCODEPROC_CONT_2            | bit 0 clear: offset from A5
        JMP     0x2(A0,D0.W)                    | bit 0 was set: PC-relative jump

| ----------------------------------------------------------
| STDOPCODEPROC_CONT_2 - Jump to handler via A5-relative offset (JT entry).
| ----------------------------------------------------------
STDOPCODEPROC_CONT_2:
        JMP     0x0(A5,D0.W)                    | jump via A5 (app globals) offset

| ----------------------------------------------------------
| STDOPCODEPROC_NO - Cache miss: search dispatch table for matching class.
| Walks the class inheritance chain via MASuperTab.
| ----------------------------------------------------------
STDOPCODEPROC_NO:
        MOVE    D0,(A0)                         | cache current class ID in table slot 0
        MOVE.L  (MASuperTab).w,A1               | A1 = MacApp superclass table handle
        MOVE.L  (A1),A1                         | dereference to superclass table data
        MOVE.L  A0,D2                           | D2 = save table base for cache update
STDOPCODEPROC_LOOP:
        ADDQ.L  #0x4,A0                         | advance to next table entry (4 bytes each)
STDOPCODEPROC_RETRY:
        CMP     (A0),D0                         | does this entry match the class ID?
        DBCC    D1,STDOPCODEPROC_LOOP           | no match and entries left: try next
        BEQ     STDOPCODEPROC_FOUND             | found matching entry: cache and dispatch
        MOVE    0x0(A1,D0.W),D0                 | D0 = superclass ID from MASuperTab
        BNE.B   STDOPCODEPROC_RETRY             | non-zero: search again with parent class
        MOVE.L  D2,A1                           | no superclass found: error
        CLR.L   (A1)                            | clear cached class ID (invalidate)
        MOVE.L  (MAErrProc).w,A1                | A1 = MacApp error handler proc
        JMP     (A1)                            | jump to error handler (no return)

| ----------------------------------------------------------
| STDOPCODEPROC_FOUND - Found handler: cache offset and dispatch.
| ----------------------------------------------------------
STDOPCODEPROC_FOUND:
        MOVE.L  D2,A1                           | A1 = table base (slot 0)
        MOVE    0x2(A0),0x2(A1)                 | cache handler offset in slot 0
        BRA.B   STDOPCODEPROC_CONT              | dispatch to cached handler
