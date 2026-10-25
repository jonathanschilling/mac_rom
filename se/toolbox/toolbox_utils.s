| Toolbox Utilities: byte-string munger, handle/pointer copying and
| MacApp method dispatch
|
| Routines, in physical ROM order:
|   _Munger ($A9E0), _XMunger ($A819)  search/replace/insert/delete bytes in
|                                      a handle (shared core XMUNGER_CONT)
|   _HandToHand ($A9E1), _PtrToXHand ($A9E2), _PtrToHand ($A9E3),
|   _HandAndHand ($A9E4), _PtrAndHand ($A9EF)
|                                      copy/concatenate data into handles
|                                      (register interface: A0/A1/D0)
|   _MethodDispatch ($A9F8)            MacApp (Object Pascal) method dispatch
|
| The fixed-point routines that follow in the ROM (_LongMul ... _Fix2Frac)
| are in fixmath.s. In Apple's sources this code and the fixed-point code
| form one file, Munger.a (System 7.1: Toolbox/Munger/Munger.a).
| The file sits between dialog_mgr.s and fixmath.s; ROM byte order is
| fixed, so the routines cannot be reordered.

| ----------------------------------------------------------
| _Munger ($A9E0) - search and replace bytes within a handle.
| Stack frame: handle(+$1C), offset(+$18), ptr1(+$14),
| len1(+$10), ptr2(+$0C), len2(+$08). Result at +$20.
| Searches for ptr1[len1] starting at offset in handle,
| replaces match with ptr2[len2]. Returns offset past match.
| ----------------------------------------------------------
| Apple source module: BYTES
MUNGER:
    LINK	A6,#-0x8                               | locals: -8(A6)=origSize, -4(A6)=sizeDelta
    MOVEM.L	D2-D7/A2-A4,-(A7)                   | save all working registers
    MOVEA.L	0x1C(A6),A2                         | A2 = target handle
    MOVEA.L	A2,A0                               | A0 = handle for GetHandleSize
    _GetHandleSize                              | D0 = current handle size
    MOVE.L	D0,D5                                | D5 = handle size (working copy)
    MOVE.L	D0,-0x8(A6)                          | save original size in local
    CLR.L	-0x4(A6)                              | size delta = 0 (no replacement yet)
    BSR.B	XMUNGER_CONT                          | perform search/replace operation
    MOVE.L	D2,0x20(A6)                          | store result offset in return value slot
    MOVEQ.L	#0x18,D1                            | 24 bytes of params to strip from stack
MUNGER_CONT:
    MOVEM.L	(A7)+,D2-D7/A2-A4                   | restore registers
    UNLK	A6                                     | discard local frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	D1,A7                                | strip parameters from stack
    JMP	(A0)                                    | tail-call return from MUNGER_CONT via A0
| ----------------------------------------------------------
| GetForeColor / Munger variant with explicit offset and size.
| Extended stack frame with extra params at +$24 and +$20.
| Used when caller provides both search offset and handle size.
| (XMUNGER in SE FDHD = GetForeColor entry in Plus.)
| ----------------------------------------------------------
XMUNGER:
    LINK	A6,#-0x8                               | locals: -8(A6)=origSize, -4(A6)=sizeDelta
    MOVEM.L	D2-D7/A2-A4,-(A7)                   | save all working registers
    MOVEA.L	0x1C(A6),A2                         | A2 = target handle
    MOVEA.L	A2,A0                               | A0 = handle for GetHandleSize
    _GetHandleSize                              | D0 = current handle size
    MOVE.L	D0,-0x8(A6)                          | save original size in local
    MOVE.L	0x24(A6),D5                          | D5 = caller-specified data length
    MOVE.L	0x20(A6),-0x4(A6)                    | save caller's size delta in local
    BSR.B	XMUNGER_CONT                          | perform search/replace operation
    MOVE.L	D2,0x28(A6)                          | store result offset in return value slot
    MOVEQ.L	#0x20,D1                            | 32 bytes of params to strip from stack
    BRA.B	MUNGER_CONT                           | shared epilogue
| ----------------------------------------------------------
| XMUNGER_CONT - Munger core: search for pattern in handle, replace if found.
| Params from stack frame:
| D2 = offset (+$18), A3 = search ptr (+$14),
| A4 = replace ptr (+$0C), D3 = search len (+$10).
| D5 = handle data size. A2 = target handle.
| Returns D2 = offset of match (or -1 if not found).
| ----------------------------------------------------------
XMUNGER_CONT:
    MOVE.L	0x18(A6),D2                          | D2 = starting search offset
    MOVEA.L	0x14(A6),A3                         | A3 = search pattern pointer
    MOVEA.L	0xC(A6),A4                          | A4 = replacement data pointer
    MOVE.L	0x10(A6),D3                          | D3 = search pattern length
    BEQ.W	XMUNGER_NO_2                          | len=0: no search, just insert at offset
    BPL.B	XMUNGER_OK                            | positive: use as-is
XMUNGER_CONT_2:
    MOVE.L	D5,D3                                | negative len: search from offset to end
    SUB.L	D2,D3                                 | D3 = remaining bytes from offset
XMUNGER_OK:
    MOVE.L	D5,D0                                | D0 = handle data size
    SUB.L	D3,D0                                 | D0 = size - searchLen
    BLT.B	XMUNGER_NOTFOUND                      | pattern longer than data: not found
    SUB.L	D2,D0                                 | D0 = bytes available after offset
    BLT.B	XMUNGER_CONT_2                        | offset past valid range: clamp
    MOVE.L	A3,D0                                | test search pointer
    BEQ.B	XMUNGER_EMPTY                         | nil search ptr: delete D3 bytes at offset
    MOVE.L	(A2),D6                              | D6 = dereferenced handle base address
    MOVE.L	D5,D7                                | D7 = end limit for search
    SUB.L	D3,D7                                 | D7 = last valid start position
    ADD.L	D6,D7                                 | D7 = absolute end address
    ADD.L	D2,D6                                 | D6 = absolute start address (base+offset)
XMUNGER_RETRY:
    MOVE.L	D3,D1                                | D1 = pattern length for comparison
    SUBQ.L	#0x1,D1                              | adjust for DBF loop (count-1)
    MOVEA.L	D6,A0                               | A0 = current position in handle data
    MOVEA.L	A3,A1                               | A1 = search pattern pointer
XMUNGER_LOOP:
    CMP.L	D6,D7                                 | past end of searchable region?
    BCS.B	XMUNGER_NOTFOUND                      | yes: pattern not found
    CMPM.B	(A0)+,(A1)+                          | compare next byte of pattern
    BNE.B	XMUNGER_NEXT                          | mismatch: advance to next position
    DBF.W	D1,XMUNGER_LOOP                       | continue comparing pattern bytes
    MOVE.L	D6,D2                                | match found: D2 = absolute match address
    SUB.L	(A2),D2                               | convert to offset from handle start
    BRA.B	XMUNGER_CONT_6                        | go perform replacement
| ----------------------------------------------------------
| XMUNGER_NEXT - Advance search position by one byte and retry.
| ----------------------------------------------------------
XMUNGER_NEXT:
    ADDQ.L	#0x1,D6                              | move to next byte in handle data
    BRA.B	XMUNGER_RETRY                         | retry pattern match from new position
| ----------------------------------------------------------
| XMUNGER_NOTFOUND - Search failed: pattern not found in handle.
| ----------------------------------------------------------
XMUNGER_NOTFOUND:
    MOVEQ.L	#-0x1,D2                            | D2 = -1 (not found sentinel)
    BRA.B	XMUNGER_EXIT_2                        | return not-found result
| ----------------------------------------------------------
| XMUNGER_CONT_3 - Move D0 bytes from A0 to A1 (safe for overlapping regions).
| Handles zero-length and single-byte cases without BlockMove.
| ----------------------------------------------------------
XMUNGER_CONT_3:
    CMPA.L	A0,A1                                | source == dest?
    BEQ.B	XMUNGER_EXIT                          | yes: nothing to move
    SUBQ.L	#0x1,D0                              | adjust count for BlockMove (needs count-1)
    BLE.B	XMUNGER_CONT_4                        | 0 or 1 byte: handle specially
    ADDQ.L	#0x1,D0                              | restore count for BlockMove
    _BlockMove                                  | move D0 bytes from A0 to A1
    RTS                                         | return from BlockMove
| ----------------------------------------------------------
| XMUNGER_CONT_4 - Handle 0 or 1 byte move without BlockMove.
| ----------------------------------------------------------
XMUNGER_CONT_4:
    BLT.B	XMUNGER_EXIT                          | count was 0: nothing to move
    MOVE.B	(A0),(A1)                            | move single byte
XMUNGER_EXIT:
    MOVEQ.L	#0x0,D0                             | clear D0 (success)
    RTS                                         | return from single byte move
| ----------------------------------------------------------
| MungerResizeIfDiff - Resize handle if new size differs from original.
| Entry: D0 = desired new size. Uses -8(A6) = original size,
| -4(A6) = slack tolerance. Only resizes if change exceeds slack.
| ----------------------------------------------------------
MungerResizeIfDiff:
    MOVE.L	D0,-(A7)                             | save desired size
    SUB.L	-0x8(A6),D0                           | D0 = desired - original size
    BEQ.B	XMUNGER_NO                            | same size: no resize needed
    BGT.B	XMUNGER_CONT_5                        | growing: must resize
    NEG.L	D0                                    | D0 = amount of shrinkage
    CMP.L	-0x4(A6),D0                           | compare shrinkage vs slack tolerance
    BGT.B	XMUNGER_CONT_5                        | shrunk more than slack: resize
XMUNGER_NO:
    ADDQ.W	#0x4,A7                              | discard saved size (no resize needed)
    BRA.B	XMUNGER_EXIT                          | return success (D0=0)
| ----------------------------------------------------------
| XMUNGER_CONT_5 - Resize handle to new size (adding slack tolerance).
| ----------------------------------------------------------
XMUNGER_CONT_5:
    MOVE.L	(A7)+,D0                             | restore desired size
    ADD.L	-0x4(A6),D0                           | add slack tolerance to new size
    _SetHandleSize                              | resize the handle
    RTS                                         | return from handle resize
| ----------------------------------------------------------
| XMUNGER_CONT_6 - Pattern found at offset D2: perform replacement.
| If replacement ptr (A4) is nil, return match offset only.
| Otherwise fall through to delete matched bytes and insert.
| ----------------------------------------------------------
XMUNGER_CONT_6:
    MOVE.L	A4,D0                                | test replacement pointer
    BEQ.B	XMUNGER_EXIT_2                        | nil: search-only, return offset
XMUNGER_EMPTY:
    MOVE.L	0x8(A6),D4                           | D4 = replacement length from frame
    BNE.B	XMUNGER_EMPTY_2                       | non-zero: replace different lengths
    MOVE.L	D5,D0                                | D0 = handle data size
    SUB.L	D3,D0                                 | subtract search pattern length
    MOVE.L	D0,D5                                | D5 = new size after deletion
    SUB.L	D2,D0                                 | D0 = bytes after match to move
    MOVEA.L	(A2),A1                             | A1 = handle base (dest for move)
    ADDA.L	D2,A1                                | A1 = match position (destination)
    MOVEA.L	A1,A0                               | A0 = source: end of matched region
    ADDA.L	D3,A0                                | advance past matched bytes
    BSR.B	XMUNGER_CONT_3                        | move trailing data over deleted region
    MOVEA.L	A2,A0                               | A0 = handle for resize
    MOVE.L	D5,D0                                | D0 = new (smaller) handle size
    BSR.B	MungerResizeIfDiff                    | shrink handle if beyond slack
XMUNGER_EXIT_2:
    BRA.B	XMUNGER_RTS                           | return
| ----------------------------------------------------------
| XMUNGER_NO_2 - No search pattern (D3=0): pure insert at offset D2.
| Inserts D4 bytes of replacement data at the given offset.
| ----------------------------------------------------------
XMUNGER_NO_2:
    MOVE.L	0x8(A6),D4                           | D4 = replacement length
    BEQ.B	XMUNGER_RTS                           | zero length: nothing to insert
    MOVE.L	D5,D0                                | D0 = current handle size
    ADD.L	D4,D0                                 | D0 = new size after insertion
    MOVEA.L	A2,A0                               | A0 = handle for resize
    BSR.B	MungerResizeIfDiff                    | grow handle to fit insertion
    BNE.B	XMUNGER_RTS                           | resize failed: abort
    MOVEA.L	(A2),A1                             | A1 = handle base
    ADDA.L	D2,A1                                | A1 = insertion point
    MOVEA.L	A1,A0                               | A0 = data at insertion point
    ADDA.L	D4,A1                                | A1 = shifted dest past insertion
    MOVE.L	D5,D0                                | D0 = trailing bytes to move
    SUB.L	D2,D0                                 | subtract offset from total
    BSR.B	XMUNGER_CONT_3                        | shift trailing data forward
XMUNGER_CONT_7:
    MOVEA.L	(A2),A1                             | A1 = handle base (may have moved)
    ADDA.L	D2,A1                                | A1 = dest for replacement data
    MOVEA.L	A4,A0                               | A0 = replacement data source
    MOVE.L	D4,D0                                | D0 = replacement data length
    BSR.W	XMUNGER_CONT_3                        | copy replacement data into handle
    ADD.L	D4,D2                                 | advance offset past inserted data
XMUNGER_RTS:
    RTS                                         | return from Munger replacement
| ----------------------------------------------------------
| XMUNGER_EMPTY_2 - Replace with different-length data.
| D4 = replacement length, D3 = search pattern length.
| Handles both shorter and longer replacements.
| ----------------------------------------------------------
XMUNGER_EMPTY_2:
    MOVE.L	D4,D1                                | D1 = replacement length
    SUB.L	D3,D1                                 | D1 = size delta (replace - search)
    BEQ.B	XMUNGER_CONT_7                        | same length: overwrite in place
    BGT.B	XMUNGER_CONT_8                        | longer: may need to expand first
    BSR.B	XMUNGER_CONT_9                        | shorter: collapse gap before resize
XMUNGER_CONT_8:
    MOVEA.L	A2,A0                               | A0 = handle for resize
    MOVE.L	D5,D0                                | D0 = current handle data size
    ADD.L	D1,D0                                 | D0 = new size (current + delta)
    BSR.W	MungerResizeIfDiff                    | resize handle
    BNE.B	XMUNGER_RTS                           | resize failed: abort
    TST.L	D1                                    | was replacement longer?
    BMI.B	XMUNGER_CONT_7                        | shorter (already collapsed): copy data
    BSR.B	XMUNGER_CONT_9                        | longer: expand gap for replacement
    BRA.B	XMUNGER_CONT_7                        | copy replacement data into gap
| ----------------------------------------------------------
| XMUNGER_CONT_9 - Shift trailing data within handle to open/close gap.
| Moves bytes from (base+offset+searchLen) to
| (base+offset+replaceLen), covering all trailing data.
| ----------------------------------------------------------
XMUNGER_CONT_9:
    MOVEA.L	(A2),A1                             | A1 = handle base address
    ADDA.L	D2,A1                                | A1 = match offset in handle
    MOVEA.L	A1,A0                               | A0 = source start
    ADDA.L	D3,A0                                | A0 += searchLen (past matched bytes)
    ADDA.L	D4,A1                                | A1 += replaceLen (replacement end)
    MOVE.L	D5,D0                                | D0 = total handle data size
    SUB.L	D3,D0                                 | subtract search pattern length
    SUB.L	D2,D0                                 | subtract offset = trailing byte count
    BRA.W	XMUNGER_CONT_3                        | move the trailing data block
| ----------------------------------------------------------
| _HandToHand ($A9E1) - Duplicate a handle.
| Entry: A0 = source handle. Exit: A0 = new handle (copy).
| Preserves source handle's master pointer state via HGetState/HSetState.
| ----------------------------------------------------------
HANDTOHAND:
    _HGetState                                  | D0 = source handle state byte
    MOVE.B	D0,-(A7)                             | save state byte on stack
    MOVE.L	A0,-(A7)                             | save source handle address
    _HNoPurge                                   | clear purgeable bit before copy
    MOVEA.L	A0,A1                               | A1 = source handle (for deref later)
    _GetHandleSize                              | D0 = size of source handle data
    TST.L	D0                                    | negative = error from GetHandleSize
    BMI.B	PTRTOHAND_FINALIZE                    | error: skip copy, restore state
    MOVE.L	D0,D1                                | D1 = byte count for BlockMove
    _NewHandle                                  | A0 = new handle of same size
    MOVEA.L	(A1),A1                             | A1 = dereferenced source data ptr
    BSR.B	PTRTOHAND_CONT                        | copy source data into new handle
| Called by: HANDANDHAND, HANDTOHAND
PTRTOHAND_FINALIZE:
    MOVE.L	D0,D1                                | D1 = error code (0 = success)
    MOVEA.L	A0,A1                               | A1 = result handle (new or original)
    MOVEA.L	(A7)+,A0                            | restore source handle to A0
    MOVE.B	(A7)+,D0                             | restore saved state byte
    _HSetState                                  | restore source handle state
    MOVE.L	D1,D0                                | D0 = error code for return
    MOVEA.L	A1,A0                               | A0 = result handle
    RTS                                         | return from HandToHand
| ----------------------------------------------------------
| _PtrToXHand ($A9E2) - Copy D0 bytes from ptr A0 into
| existing handle A1. Resizes handle to D0 bytes first.
| ----------------------------------------------------------
PTRTOXHAND:
    EXG	A0,A1                                   | A0 = dest handle, A1 = source ptr
    MOVE.L	D0,D1                                | D1 = byte count
    _SetHandleSize                              | resize handle to D1 bytes
    BRA.B	PTRTOHAND_CONT                        | copy data from A1 into handle A0
| ----------------------------------------------------------
| _PtrToHand ($A9E3) - Create new handle with copy of D0
| bytes from ptr A0. Exit: A0 = new handle.
| ----------------------------------------------------------
PTRTOHAND:
    MOVEA.L	A0,A1                               | A1 = source pointer
    MOVE.L	D0,D1                                | D1 = byte count
    _NewHandle                                  | A0 = new handle of size D1
| PTRTOHAND_CONT -- copy source data into new handle.
PTRTOHAND_CONT:
    BNE.B	PTRTOHAND_RTS                         | allocation/resize failed: return error
    MOVEQ.L	#0x0,D2                             | D2 = 0 (offset = start of handle)
| PTRTOHAND_CONT_2 -- append source data at offset D2.
PTRTOHAND_CONT_2:
    MOVE.L	A0,-(A7)                             | save dest handle on stack
    MOVEA.L	(A0),A0                             | dereference dest handle to data ptr
    ADDA.L	D2,A0                                | offset into dest (for append ops)
    EXG	A0,A1                                   | A0 = source data, A1 = dest in handle
    MOVE.L	D1,D0                                | D0 = byte count for BlockMove
    _BlockMove                                  | copy data into handle
    MOVEA.L	(A7)+,A0                            | restore handle in A0
PTRTOHAND_RTS:
    RTS                                         | return from PtrToHand/PtrToXHand
| ----------------------------------------------------------
| _HandAndHand ($A9E4) - Append handle A0's data to end
| of handle A1. Both handles preserved. A0 state restored.
| ----------------------------------------------------------
HANDANDHAND:
    _HGetState                                  | D0 = source handle state byte
    MOVE.B	D0,-(A7)                             | save state byte on stack
    MOVE.L	A0,-(A7)                             | save source handle
    _HNoPurge                                   | clear purgeable bit on source
    _GetHandleSize                              | D0 = source handle size
    TST.L	D0                                    | negative = error
    BMI.B	PTRTOHAND_FINALIZE                    | error: restore state and return
    MOVE.L	D0,D1                                | D1 = source byte count to copy
    EXG	A1,A0                                   | A0 = dest handle, A1 = source handle
    _GetHandleSize                              | D0 = dest handle current size
    MOVE.L	D0,D2                                | D2 = append offset (old dest size)
    BMI.B	PTRTOHAND_FINALIZE                    | error: restore and return
    ADD.L	D1,D0                                 | D0 = new dest size (old + source)
    _SetHandleSize                              | grow dest handle
    BNE.B	PTRTOHAND_FINALIZE                    | resize failed: restore and return
    MOVEA.L	(A1),A1                             | dereference source handle for copy
    BSR.B	PTRTOHAND_CONT_2                      | append source data at offset D2
    BRA.B	PTRTOHAND_FINALIZE                    | restore source handle state
| ----------------------------------------------------------
| _PtrAndHand ($A9EF) - Append D0 bytes from ptr A0 to
| end of handle A1. Entry: A0=ptr, A1=handle, D0=count.
| ----------------------------------------------------------
PTRANDHAND:
    MOVE.L	D0,D1                                | D1 = byte count to append
    EXG	A1,A0                                   | A0 = dest handle, A1 = source ptr
    _GetHandleSize                              | D0 = current handle size
    MOVE.L	D0,D2                                | D2 = append offset (current size)
    ADD.L	D1,D0                                 | D0 = new size (current + append)
    _SetHandleSize                              | grow handle
    BNE.B	PTRTOHAND_RTS                         | resize failed: return error
    BRA.B	PTRTOHAND_CONT_2                      | copy source data at offset D2
| ----------------------------------------------------------
| StdOpcodeProc / METHODDISPATCH - MacApp opcode dispatcher.
| Looks up an opcode in a dispatch table, caches result,
| and jumps to the handler. Uses MASuperTab for inheritance.
| ----------------------------------------------------------
METHODDISPATCH:
    MOVEA.L	(A7)+,A0                            | A0 = ptr to inline dispatch table
    MOVEA.L	0x4(A7),A1                          | A1 = object handle from stack param
    MOVEA.L	(A1),A1                             | dereference object handle
    MOVE.W	(A1),D0                              | D0 = class ID from object header
    MOVE.W	(A0)+,D1                             | D1 = entry count - 1 for DBCC loop
    CMP.W	(A0),D0                               | does cached class ID match?
    BNE.B	STDOPCODE_SEARCH_TABLE                | no: search table for this class
METHODDISPATCH_CONT:
    MOVE.W	0x2(A0),D0                           | D0 = cached handler offset
    BCLR	#0x0,D0                                | test/clear PC-relative flag bit
    BNE.B	STDOPCODE_PCREL_JMP                   | bit 0 was set: PC-relative jump
    JMP	0x0(A5,D0.W)                            | jump via A5 (app globals) offset
STDOPCODE_PCREL_JMP:
    JMP	0x2(A0,D0.W)                            | bit 0 was set: PC-relative jump
| ----------------------------------------------------------
| Cache miss: search dispatch table for matching class.
| Walks the class inheritance chain via MASuperTab.
| ----------------------------------------------------------
STDOPCODE_SEARCH_TABLE:
    MOVE.W	D0,(A0)                              | cache current class ID in table slot 0
    MOVE.L	A0,D2                                | D2 = save table base for cache update
| First loop: scan dispatch table for current class ID
METHODDISPATCH_LOOP:
    ADDQ.L	#0x4,A0                              | advance to next table entry
    CMP.W	(A0),D0                               | does this entry match the class ID?
    DBCC.W	D1,METHODDISPATCH_LOOP               | no match and entries left: try next
    BEQ.B	METHODDISPATCH_FOUND                  | found matching entry: cache and dispatch
    MOVEA.L	(MASuperTab).W,A1                   | A1 = MacApp superclass table handle
    MOVEA.L	(A1),A1                             | dereference to superclass table data
    BRA.B	STDOPCODE_PARENT_CLASS                | walk inheritance chain via MASuperTab
| Second loop: continue scanning with parent class ID
STDOPCODE_NEXT_ENTRY:
    ADDQ.L	#0x4,A0                              | advance to next table entry
METHODDISPATCH_RETRY:
    CMP.W	(A0),D0                               | does this entry match the parent class?
    DBCC.W	D1,STDOPCODE_NEXT_ENTRY              | no match and entries left: try next
    BEQ.B	METHODDISPATCH_FOUND                  | found matching entry: cache and dispatch
STDOPCODE_PARENT_CLASS:
    MOVE.W	0x0(A1,D0.W),D0                      | D0 = superclass ID from MASuperTab
    BNE.B	METHODDISPATCH_RETRY                  | non-zero: search again with parent class
    MOVEA.L	D2,A1                               | no superclass found: error path
    CLR.L	(A1)                                  | clear cached class ID (invalidate)
    MOVEA.L	(MAErrProc).W,A1                    | A1 = MacApp error handler proc
    JMP	(A1)                                    | jump to error handler (no return)
| Found handler: cache offset and dispatch.
METHODDISPATCH_FOUND:
    MOVEA.L	D2,A1                               | A1 = table base (slot 0)
    MOVE.W	0x2(A0),0x2(A1)                      | cache handler offset in slot 0
    BRA.B	METHODDISPATCH_CONT                   | dispatch to cached handler
