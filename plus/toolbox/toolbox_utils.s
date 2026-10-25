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
|
| _Munger ($A9E0): search for, replace, insert or delete bytes in a handle
| Pascal: FUNCTION Munger(h: Handle; offset: LONGINT; ptr1: Ptr; len1: LONGINT;
|                         ptr2: Ptr; len2: LONGINT): LONGINT;
| Entry: after LINK, h = $1C(A6), offset = $18(A6), ptr1 = $14(A6),
|        len1 = $10(A6), ptr2 = $0C(A6), len2 = $08(A6); result at $20(A6)
| Exit:  result = offset just past the replacement/insertion; the match
|        offset if ptr2 = nil; the offset of a deletion if len2 = 0;
|        -1 if the target is not found (24 bytes of parameters removed)
| Takes the handle size as the logical length (D5) with a slop of 0 and
| calls the shared core XMUNGER_CONT (ptr/len variants: see there, IM I-468).
|
Munger:
        LINK    A6,#-0x8                        | locals: -8(A6)=physical size, -4(A6)=slop
        MOVEM.L D2-D7/A2-A4,-(SP)               | save all working registers
        MOVE.L  0x1C(A6),A2                     | A2 = target handle
        MOVE.L  A2,A0                           | A0 = handle for GetHandleSize
        _GetHandleSize                          | D0 = current handle size
        MOVE.L  D0,D5                           | D5 = logical size = handle size
        MOVE.L  D0,-0x8(A6)                     | physical size = handle size
        CLR.L   -0x4(A6)                        | slop = 0: resize the handle exactly
        BSR.B   XMUNGER_CONT                    | perform search/replace operation
        MOVE.L  D2,0x20(A6)                     | store result offset in return value slot
        MOVEQ.L #0x18,D1                        | 24 bytes of params to strip from stack
| MUNGER_CONT -- shared exit of Munger/XMunger (Apple: mungeBye);
| D1 = number of parameter bytes to remove
MUNGER_CONT:
        MOVEM.L (SP)+,D2-D7/A2-A4               | restore registers
        UNLK    A6                              | discard local frame
        MOVE.L  (SP)+,A0                        | pop return address
        ADDA    D1,SP                           | strip parameters from stack
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _XMunger ($A819): Munger with a caller-supplied logical length and slop
| Parameters (Pascal order): logical, slop: LONGINT, then h, offset, ptr1,
| len1, ptr2, len2 as for Munger; LONGINT result.
| Entry: after LINK, logical = $24(A6), slop = $20(A6), h = $1C(A6) ...
|        len2 = $08(A6); result at $28(A6)
| Exit:  result as for Munger; 32 bytes of parameters removed
| The logical length replaces GetHandleSize as the length of the data, so
| the handle may be physically larger than its contents. When the core
| has to resize, it adds the slop to the new size, and it skips a shrink
| that stays within the slop of the physical size (see XMUNGER_SETSIZE).
|
XMunger:
        LINK    A6,#-0x8                        | locals: -8(A6)=physical size, -4(A6)=slop
        MOVEM.L D2-D7/A2-A4,-(SP)               | save all working registers
        MOVE.L  0x1C(A6),A2                     | A2 = target handle
        MOVE.L  A2,A0                           | A0 = handle for GetHandleSize
        _GetHandleSize                          | D0 = current handle size
        MOVE.L  D0,-0x8(A6)                     | physical size = handle size
        MOVE.L  0x24(A6),D5                     | D5 = logical size (caller's parameter)
        MOVE.L  0x20(A6),-0x4(A6)               | slop = caller's slop parameter
        BSR.B   XMUNGER_CONT                    | perform search/replace operation
        MOVE.L  D2,0x28(A6)                     | store result offset in return value slot
        MOVEQ.L #0x20,D1                        | 32 bytes of params to strip from stack
        BRA.B   MUNGER_CONT                     | shared epilogue

| ----------------------------------------------------------
| XMUNGER_CONT - Munger/XMunger core.
| Entry: A2 = handle, D5 = logical data length, -8(A6) = physical size,
|        -4(A6) = slop, Munger parameters at $08..$18(A6)
| Loads D2 = offset, A3 = ptr1, A4 = ptr2, D3 = len1 (D4 = len2 later):
|   len1 = 0: insert (ptr2,len2) at offset (XMUNGER_NO_2)
|   len1 < 0: target runs from offset to the end; len1 > length: not found;
|     offset+len1 > length: len1 is clipped to length - offset
|   ptr1 = nil: no search, replace/delete len1 bytes at offset (XMUNGER_EMPTY)
|   else search (ptr1,len1) from offset; then ptr2 = nil returns the match
|     offset, len2 = 0 deletes the match, else (ptr2,len2) replaces it
| Exit:  D2 = result offset (-1 = not found)
| Apple source name: MungeGuts (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
XMUNGER_CONT:
        MOVE.L  0x18(A6),D2                     | D2 = starting search offset
        MOVE.L  0x14(A6),A3                     | A3 = search pattern pointer
        MOVE.L  0xC(A6),A4                      | A4 = replacement data pointer
        MOVE.L  0x10(A6),D3                     | D3 = search pattern length
        BEQ     XMUNGER_NO_2                    | len=0: no search, just insert at offset
        BPL.B   XMUNGER_OK                      | positive: use as-is
XMUNGER_CONT_2:
        MOVE.L  D5,D3                           | len1 < 0 or too long: len1 = length - offset
        SUB.L   D2,D3                           | D3 = remaining bytes from offset
XMUNGER_OK:
        MOVE.L  D5,D0                           | D0 = data length
        SUB.L   D3,D0                           | D0 = size - searchLen
        BLT.B   XMUNGER_NOTFOUND                | pattern longer than data: not found
        SUB.L   D2,D0                           | D0 = length - len1 - offset
        BLT.B   XMUNGER_CONT_2                  | offset+len1 > length: clip len1
        MOVE.L  A3,D0                           | test search pointer
        BEQ.B   XMUNGER_EMPTY                   | ptr1 = nil: replace len1 bytes at offset
        MOVE.L  (A2),D6                         | D6 = dereferenced handle base address
        MOVE.L  D5,D7                           | D7 = end limit for search
        SUB.L   D3,D7                           | D7 = last valid start position
        ADD.L   D6,D7                           | D7 = address of last possible match
        ADD.L   D2,D6                           | D6 = absolute start address (base+offset)
XMUNGER_RETRY:
        MOVE.L  D3,D1                           | D1 = pattern length for comparison
        SUBQ.L  #0x1,D1                         | adjust for DBF loop (count-1)
        MOVE.L  D6,A0                           | A0 = current position in handle data
        MOVE.L  A3,A1                           | A1 = search pattern pointer
XMUNGER_LOOP:
        CMP.L   D6,D7                           | past end of searchable region?
        BCS.B   XMUNGER_NOTFOUND                | yes: pattern not found
        CMPM.B  (A0)+,(A1)+                     | compare next byte of pattern
        BNE.B   XMUNGER_NEXT                    | mismatch: advance to next position
        DBF     D1,XMUNGER_LOOP                 | continue comparing pattern bytes
        MOVE.L  D6,D2                           | match found: D2 = absolute match address
        SUB.L   (A2),D2                         | convert to offset from handle start
        BRA.B   XMUNGER_CONT_6                  | go perform replacement

| ----------------------------------------------------------
| XMUNGER_NEXT - Advance search position by one byte and retry.
| ----------------------------------------------------------
XMUNGER_NEXT:
        ADDQ.L  #0x1,D6                         | move to next byte in handle data
        BRA.B   XMUNGER_RETRY                   | retry pattern match from new position

| ----------------------------------------------------------
| XMUNGER_NOTFOUND - target not found (despite the label name): D2 = -1.
| Also taken when len1 is longer than the data.
| ----------------------------------------------------------
XMUNGER_NOTFOUND:
        MOVEQ.L #-0x1,D2                        | D2 = -1 (not found sentinel)
        BRA.B   XMUNGER_EXIT_2                  | return not-found result

| ----------------------------------------------------------
| XMUNGER_CONT_3 - Move D0 bytes from A0 to A1 (overlap-safe _BlockMove);
| moves of 0 or 1 byte, or with A0 = A1, are done without the trap.
| Exit: D0 = 0 (noErr).
| Apple source name: bm (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
XMUNGER_CONT_3:
        CMPA.L  A0,A1                           | source == dest?
        BEQ.B   XMUNGER_EXIT                    | yes: nothing to move
        SUBQ.L  #0x1,D0                         | count - 1 <= 0: zero or one byte?
        BLE.B   XMUNGER_CONT_4                  | 0 or 1 byte: handle specially
        ADDQ.L  #0x1,D0                         | restore count for BlockMove
        _BlockMove                              | move D0 bytes from A0 to A1
        RTS                                     | return (D0 = noErr from _BlockMove)

| ----------------------------------------------------------
| XMUNGER_CONT_4 - Handle 0 or 1 byte move without BlockMove.
| ----------------------------------------------------------
XMUNGER_CONT_4:
        BLT.B   XMUNGER_EXIT                    | count was 0: nothing to move
        MOVE.B  (A0),(A1)                       | move single byte
XMUNGER_EXIT:
        MOVEQ.L #0x0,D0                         | D0 = noErr (Z set for the callers' BNE)
        RTS                                     | return D0 = 0 (also XMUNGER_SETSIZE no-resize exit)

| ----------------------------------------------------------
| XMUNGER_SETSIZE - SetHandleSize cover that honours the slop.
| Entry: A0 = handle, D0 = new logical size; -8(A6) = physical size,
|        -4(A6) = slop
| Same size, or shrinking by no more than the slop: no call, D0 = 0.
| Otherwise _SetHandleSize to D0 + slop (XMUNGER_CONT_5).
| Exit: D0 = result code, condition codes set from D0
| Apple source name: shs (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
XMUNGER_SETSIZE:
        MOVE.L  D0,-(SP)                        | save desired size
        SUB.L   -0x8(A6),D0                     | D0 = new size - physical size
        BEQ.B   XMUNGER_NO                      | same size: no resize needed
        BGT.B   XMUNGER_CONT_5                  | growing: must resize
        NEG.L   D0                              | D0 = amount of shrinkage
        CMP.L   -0x4(A6),D0                     | compare shrinkage with slop
        BGT.B   XMUNGER_CONT_5                  | shrinks by more than slop: resize
XMUNGER_NO:
        ADDQ.W  #0x4,SP                         | discard saved size (no resize needed)
        BRA.B   XMUNGER_EXIT                    | return success (D0=0)

| ----------------------------------------------------------
| XMUNGER_CONT_5 - Resize the handle to the new size plus the slop.
| ----------------------------------------------------------
XMUNGER_CONT_5:
        MOVE.L  (SP)+,D0                        | restore desired size
        ADD.L   -0x4(A6),D0                     | add slop to the new size
        _SetHandleSize                          | resize the handle
        RTS                                     | return D0 = result code (CCR set by trap)

| ----------------------------------------------------------
| XMUNGER_CONT_6 - target found at offset D2: ptr2 (A4) = nil just
| returns the match offset.
| XMUNGER_EMPTY (also entered directly when ptr1 = nil): len2 = 0 deletes
| the len1 bytes at D2 and shrinks the handle; len2 <> 0 replaces them
| (XMUNGER_EMPTY_2).
| Apple source names: tryDelete, doDelete (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
XMUNGER_CONT_6:
        MOVE.L  A4,D0                           | test replacement pointer
        BEQ.B   XMUNGER_EXIT_2                  | nil: search-only, return offset
XMUNGER_EMPTY:
        MOVE.L  0x8(A6),D4                      | D4 = replacement length from frame
        BNE.B   XMUNGER_EMPTY_2                 | len2 <> 0: replace
        MOVE.L  D5,D0                           | D0 = handle data size
        SUB.L   D3,D0                           | subtract search pattern length
        MOVE.L  D0,D5                           | D5 = new size after deletion
        SUB.L   D2,D0                           | D0 = bytes after match to move
        MOVE.L  (A2),A1                         | A1 = handle base (dest for move)
        ADDA.L  D2,A1                           | A1 = match position (destination)
        MOVE.L  A1,A0                           | A0 = source: end of matched region
        ADDA.L  D3,A0                           | advance past matched bytes
        BSR.B   XMUNGER_CONT_3                  | move trailing data over deleted region
        MOVE.L  A2,A0                           | A0 = handle for resize
        MOVE.L  D5,D0                           | D0 = new (smaller) handle size
        BSR.B   XMUNGER_SETSIZE                 | shrink handle unless within slop
XMUNGER_EXIT_2:
        BRA.B   XMUNGER_RTS                     | return

| ----------------------------------------------------------
| XMUNGER_NO_2 - len1 = 0: pure insert of (ptr2,len2) at offset D2.
| Grows the handle, shifts the tail up, copies the data in (XMUNGER_CONT_7)
| and returns D2 = offset + len2 (XMUNGER_RTS is the normal return).
| Apple source names: doInsert, finishUp, goHome (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
XMUNGER_NO_2:
        MOVE.L  0x8(A6),D4                      | D4 = replacement length
        BEQ.B   XMUNGER_RTS                     | zero length: nothing to insert
        MOVE.L  D5,D0                           | D0 = current handle size
        ADD.L   D4,D0                           | D0 = new size after insertion
        MOVE.L  A2,A0                           | A0 = handle for resize
        BSR.B   XMUNGER_SETSIZE                 | grow handle to fit insertion
        BNE.B   XMUNGER_RTS                     | resize failed: abort
        MOVE.L  (A2),A1                         | A1 = handle base
        ADDA.L  D2,A1                           | A1 = insertion point
        MOVE.L  A1,A0                           | A0 = data at insertion point
        ADDA.L  D4,A1                           | A1 = shifted dest past insertion
        MOVE.L  D5,D0                           | D0 = old length
        SUB.L   D2,D0                           | D0 = bytes after offset to move
        BSR.B   XMUNGER_CONT_3                  | shift trailing data forward
XMUNGER_CONT_7:
        MOVE.L  (A2),A1                         | A1 = handle base (may have moved)
        ADDA.L  D2,A1                           | A1 = dest for replacement data
        MOVE.L  A4,A0                           | A0 = replacement data source
        MOVE.L  D4,D0                           | D0 = replacement data length
        BSR     XMUNGER_CONT_3                  | copy replacement data into handle
        ADD.L   D4,D2                           | result = offset + len2
XMUNGER_RTS:
        RTS                                     | return D2 = result offset

| ----------------------------------------------------------
| XMUNGER_EMPTY_2 - Replace the len1 (D3) bytes at D2 with (ptr2,len2).
| D1 = len2 - len1. Equal: copy in place. Shrinking: move the tail down
| first, then resize. Growing: resize first, then move the tail up.
| Then copy the replacement in (XMUNGER_CONT_7).
| Apple source name: doReplace (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
XMUNGER_EMPTY_2:
        MOVE.L  D4,D1                           | D1 = replacement length
        SUB.L   D3,D1                           | D1 = size delta (replace - search)
        BEQ.B   XMUNGER_CONT_7                  | same length: overwrite in place
        BGT.B   XMUNGER_CONT_8                  | growing: resize first, move tail after
        BSR.B   XMUNGER_CONT_9                  | shorter: collapse gap before resize
XMUNGER_CONT_8:
        MOVE.L  A2,A0                           | A0 = handle for resize
        MOVE.L  D5,D0                           | D0 = current handle data size
        ADD.L   D1,D0                           | D0 = new size (current + delta)
        BSR     XMUNGER_SETSIZE                 | resize handle
        BNE.B   XMUNGER_RTS                     | resize failed: abort
        TST.L   D1                              | D1 < 0: shrinking, tail already moved
        BMI.B   XMUNGER_CONT_7                  | shorter (already collapsed): copy data
        BSR.B   XMUNGER_CONT_9                  | longer: expand gap for replacement
        BRA.B   XMUNGER_CONT_7                  | copy replacement data into gap

| ----------------------------------------------------------
| XMUNGER_CONT_9 - Shift trailing data within handle to open/close gap.
| Moves bytes from (base+offset+searchLen) to
| (base+offset+replaceLen), covering all trailing data.
| Apple source name: MoveTail (System 7.1 Toolbox/Munger/Munger.a)
| ----------------------------------------------------------
XMUNGER_CONT_9:
        MOVE.L  (A2),A1                         | A1 = handle base address
        ADDA.L  D2,A1                           | A1 = match offset in handle
        MOVE.L  A1,A0                           | A0 = source start
        ADDA.L  D3,A0                           | A0 += searchLen (past matched bytes)
        ADDA.L  D4,A1                           | A1 += replaceLen (replacement end)
        MOVE.L  D5,D0                           | D0 = total handle data size
        SUB.L   D3,D0                           | subtract search pattern length
        SUB.L   D2,D0                           | subtract offset = trailing byte count
        BRA     XMUNGER_CONT_3                  | move the trailing data block

| ----------------------------------------------------------
|
| _HandToHand ($A9E1): copy a relocatable block into a new handle
| Pascal: FUNCTION HandToHand(VAR theHndl: Handle): OSErr;
| Entry: A0 = source handle
| Exit:  A0 = new handle (copy), D0 = result code
| The source is made unpurgeable (BCLR #6 of its master pointer flags)
| during the copy and its flags byte is restored on exit (HANDTOHAND_ERR,
| shared with HandAndHand). If _GetHandleSize fails (D0 < 0), that error
| is returned with A0 = source handle.
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
| _PtrToXHand ($A9E2): copy D0 bytes from ptr A0 into existing handle A1
| Pascal: FUNCTION PtrToXHand(srcPtr: Ptr; dstHndl: Handle;
|                             size: LONGINT): OSErr;
| Entry: A0 = source pointer, A1 = destination handle, D0 = byte count
| Exit:  A0 = destination handle, D0 = result code
| Sets the handle size to D0, then copies via PTRTOHAND_CONT.
| ----------------------------------------------------------
PtrToXHand:
        EXG     A0,A1                           | A0 = dest handle, A1 = source ptr
        MOVE.L  D0,D1                           | D1 = byte count
        _SetHandleSize                          | resize handle to D1 bytes
        BRA.B   PTRTOHAND_CONT                  | copy data from A1 into handle A0

| ----------------------------------------------------------
| _PtrToHand ($A9E3): copy D0 bytes from ptr A0 into a new handle
| Pascal: FUNCTION PtrToHand(srcPtr: Ptr; VAR dstHndl: Handle;
|                            size: LONGINT): OSErr;
| Entry: A0 = source pointer, D0 = byte count
| Exit:  A0 = new handle, D0 = result code
| ----------------------------------------------------------
PtrToHand:
        MOVE.L  A0,A1                           | A1 = source pointer
        MOVE.L  D0,D1                           | D1 = byte count
        _NewHandle                              | A0 = new handle of size D1
| PTRTOHAND_CONT (Apple: cloneCommon) -- if the preceding Memory Manager
| trap failed (Z clear) return its code; else copy D1 bytes from A1 to the
| start of handle A0.
PTRTOHAND_CONT:
        BNE.B   PTRTOHAND_ERR                   | allocation/resize failed: return error
        MOVEQ.L #0x0,D2                         | D2 = 0 (offset = start of handle)
| PTRTOHAND_CONT_2 (Apple: clone2Common) -- copy D1 bytes from A1 to the
| data of handle A0 at offset D2. Exit: A0 = handle, D0 = 0.
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
| _HandAndHand ($A9E4): append the data of handle A0 to handle A1
| Pascal: FUNCTION HandAndHand(aHndl, bHndl: Handle): OSErr;
| Entry: A0 = source handle (aHndl), A1 = destination handle (bHndl)
| Exit:  A0 = destination handle, D0 = result code
| As in HandToHand, the source is made unpurgeable during the call and
| its master pointer flags byte is restored on exit.
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
| _PtrAndHand ($A9EF): append D0 bytes from ptr A0 to the end of handle A1
| Pascal: FUNCTION PtrAndHand(pntr: Ptr; hndl: Handle;
|                             size: LONGINT): OSErr;
| Entry: A0 = source pointer, A1 = handle, D0 = byte count
| Exit:  A0 = handle, D0 = result code
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
| _MethodDispatch ($A9F8): MacApp (Object Pascal) method dispatcher
| Nonstandard stack interface (Apple Munger.a, from MacApp's Method.TEXT):
| Entry: (SP) = address of the method's selector table (the trap's return
|        address: the table follows the _MethodDispatch trap word),
|        4(SP) = real return address, 8(SP) = receiver (object handle)
| Table: word count-1, cache (class #, offset), then (class #, offset)
|        pairs, 4 bytes each
| The receiver's class # is the first word of the object. If it equals
| the cached class #, dispatch through the cached offset; otherwise search
| the table, walking up the superclass chain in MASuperTab, and cache the
| hit. Offset bit 0 clear: jump to A5+offset (jump table entry); bit 0 set:
| jump relative to the offset word. Not found: clear the cache and jump
| to MAErrProc.
|
MethodDispatch:
        MOVE.L  (SP)+,A0                        | A0 = ptr to inline dispatch table
        MOVE.L  0x4(SP),A1                      | A1 = receiver (object handle)
        MOVE.L  (A1),A1                         | dereference object handle
        MOVE    (A1),D0                         | D0 = receiver's class # (first word)
        MOVE    (A0)+,D1                        | D1 = entry count - 1 for DBCC loop
        CMP     (A0),D0                         | does cached class ID match?
        BNE.B   METHODDISPATCH_NO               | no: search table for this class
METHODDISPATCH_CONT:
        MOVE    0x2(A0),D0                      | D0 = method offset (cache or found entry)
        BCLR    #0x0,D0                         | bit 0: 0 = A5-relative, 1 = A0-relative
        BEQ.B   METHODDISPATCH_CONT_2           | bit 0 clear: offset from A5
        JMP     0x2(A0,D0.W)                    | bit 0 set: jump relative to the offset word

| ----------------------------------------------------------
| METHODDISPATCH_CONT_2 - Jump to handler via A5-relative offset (JT entry).
| ----------------------------------------------------------
METHODDISPATCH_CONT_2:
        JMP     0x0(A5,D0.W)                    | jump to jump-table entry at A5+offset

| ----------------------------------------------------------
| METHODDISPATCH_NO - Cache miss: search dispatch table for matching class.
| Walks the class inheritance chain via MASuperTab.
| ----------------------------------------------------------
METHODDISPATCH_NO:
        MOVE    D0,(A0)                         | cache current class ID in table slot 0
        MOVE.L  (MASuperTab).w,A1               | A1 = MacApp superclass table handle
        MOVE.L  (A1),A1                         | dereference to superclass table data
        MOVE.L  A0,D2                           | D2 = address of the cache
METHODDISPATCH_LOOP:
        ADDQ.L  #0x4,A0                         | advance to next table entry (4 bytes each)
METHODDISPATCH_RETRY:
        CMP     (A0),D0                         | does this entry match the class ID?
        DBCC    D1,METHODDISPATCH_LOOP          | loop until entry class <= D0 or count out
        BEQ     METHODDISPATCH_FOUND            | found matching entry: cache and dispatch
        MOVE    0x0(A1,D0.W),D0                 | D0 = superclass ID from MASuperTab
        BNE.B   METHODDISPATCH_RETRY            | non-zero: search again with parent class
        MOVE.L  D2,A1                           | no superclass left: method not found
        CLR.L   (A1)                            | clear the cache (class # and offset)
        MOVE.L  (MAErrProc).w,A1                | A1 = MacApp error handler proc
        JMP     (A1)                            | jump to MAErrProc

| ----------------------------------------------------------
| METHODDISPATCH_FOUND - Found handler: cache offset and dispatch.
| ----------------------------------------------------------
METHODDISPATCH_FOUND:
        MOVE.L  D2,A1                           | A1 = address of the cache
        MOVE    0x2(A0),0x2(A1)                 | copy the method offset into the cache
        BRA.B   METHODDISPATCH_CONT             | dispatch via this entry's offset
