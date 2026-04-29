| Segment Loader -- _LoadSeg / _UnloadSeg / _Launch / Chain
|
| Loads and unloads the per-segment jump-table entries for CODE
| resources 1-N, and sets up the initial application environment
| from CODE 0. Invoked by Segment Loader traps and by _Launch at
| application startup.
|
| Entry points:
| LoadSeg - _LoadSeg trap impl: load CODE resource, patch jump-table
| entries to JMP to the loaded code.
| UnLoadSeg - _UnLoadSeg trap impl: restore JT "segment unloaded" stubs.
| Chain - _Chain: release current app segments and launch a new app
| with the same A5 world (Plus only).
| Launch - _Launch: parse CODE 0 header, unload current segments,
| select heap size, jump to app entry point via SegStack.
|
| Falls through into SegStack in os_utilities.s, which completes the
| _Launch sequence by setting up A5, SP, and the jump table.
|
| References: Inside Macintosh Vol II, Ch 2 (Segment Loader).

| ----------------------------------------------------------
|
| _LoadSeg ($A9F0)
|
| Called during boot.
| _LoadSeg ($A9F0): load a CODE segment into memory
| Called by jump table stubs when an unloaded segment is referenced.
| D0 (from stack) = segment number.
|
| Classic 1984 implementation: lacks the SegHiEnable/MoveHHi check that
| Plus added in 1986; classic always BSets the lock bit unconditionally.
LoadSeg:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save registers
        MOVE    0x18(SP),D0                     | D0 = segment number (from JSR stub)
        BSR.B   LOADSEG_CONT                    | load CODE resource -> A0 = handle
        BEQ.B   LOADSEG_ERR                     | failed -> trap into debugger
        BSET    #0x7,(A0)                       | lock the handle (no MoveHHi in classic)
| dereference and patch jump table entries
        MOVE.L  (A0),-(SP)                      | get segment pointer
        CLR.B   (SP)                            | clear master pointer flags byte
        MOVE.L  (SP)+,A0                        | A0 = segment data pointer
| A0+0 = first jump table offset, A0+2 = entry count
        MOVE.L  A5,A1                           | A1 = app globals (A5)
        ADDA.W  (CurJTOffset).w,A1              | + jump table offset
        ADDA.W  (A0),A1                         | + segment's JT base offset
| check if already patched (JMP = $4EF9)
        CMPI    #0x4EF9,0x4(A1)                 | already has JMP instruction?
        BEQ.B   LOADSEG_EMPTY                   | yes, already patched ->
| patch each jump table entry: replace stub with JMP to loaded code
        MOVE    0x2(A0),D0                      | D0 = number of entries
        BEQ.B   LOADSEG_EMPTY                   | none ->
        MOVE    0x18(SP),D1                     | D1 = segment number
        MOVEQ.L #0x0,D2                         | clear D2 for word extend
LOADSEG_LOOP:
        MOVE    (A1)+,D2                        | D2 = code offset within segment
        MOVE    D1,-0x2(A1)                     | store segment number (for UnLoadSeg)
        MOVE    #0x4EF9,(A1)+                   | write JMP.L opcode
        PEA.L   0x4(A0,D2.L)                    | push absolute code address
        MOVE.L  (SP)+,(A1)+                     | write absolute code address
        SUBQ.W  #0x1,D0                         | decrement entry count
        BNE.B   LOADSEG_LOOP                    | loop for all entries
LOADSEG_EMPTY:
        MOVE.L  20(SP),A1                       | get return address (points inside jump table)
        SUBQ.L  #0x6,A1                         | adjust to point to start of jump table entry
        MOVE.L  A1,22(SP)                       | overwrite saved segment number with execution address
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore registers
        ADDQ.W  #0x2,SP                         | skip dummy word
        TST.B   (LoadTrap).w                    | trap on segment load?
        BEQ.B   LOADSEG_EXIT                    | no -> normal return
        _Debugger                               | yes -> break into debugger
LOADSEG_EXIT:
        RTS                                     | return to caller (resumes inside loaded segment)

| ----------------------------------------------------------
| LOADSEG_ERR
LOADSEG_ERR:
        MOVEQ.L #0xF,D0                         | DSLoadErr (15)
        _SysError                               | system error
        _Debugger                               | trap to debugger
LOADSEG_CONT:
        SUBQ.W  #0x4,SP                         | space for GetResource Handle result
        MOVE.L  #0x434F4445,-(SP)               | push 'CODE' resource type
        MOVE    D0,-(SP)                        | push CODE resource ID (segment number)
        _GetResource                            | load it
        MOVE.L  (SP)+,A0                        | A0 = result handle
        MOVE.L  A0,D0                           | set condition codes
        RTS                                     | return CODE handle in A0

| ----------------------------------------------------------
|
| _UnLoadSeg ($A9F1)
|
| _UnLoadSeg ($A9F1): mark a CODE segment as unlocked (purgeable)
| Reverts jump table entries from JMP to LoadSeg stubs
UnLoadSeg:
        MOVE.L  0x4(SP),A0                      | A0 = routine address in segment
        CMPI    #0x4EF9,(A0)                    | is it a JMP (loaded)?
        BNE.B   UNLOADSEG_EMPTY                 | no, already unloaded ->
        MOVE    -0x2(A0),D0                     | D0 = segment number (before JMP)
        BSR.B   LOADSEG_CONT                    | get CODE resource handle -> A0
        BCLR    #0x7,(A0)                       | unlock the handle
        MOVE.L  (A0),A0                         | dereference segment
        MOVE.L  A5,A1                           | A1 = globals
        ADDA.W  (CurJTOffset).w,A1              | + jump table offset
        ADDA.W  (A0),A1                         | + segment's JT base
        MOVE    2(A0),D0                        | D0 = entry count
        BEQ.B   UNLOADSEG_EMPTY                 | none ->
UNLOADSEG_LOOP:
        MOVE    (A1),D1                         | D1 = seg number from patched entry
        MOVE.L  0x4(A1),D2                      | D2 = absolute code address
        SUB.L   A0,D2                           | make relative to segment
        SUBQ.L  #0x4,D2                         | adjust for header
        MOVE    D2,(A1)+                        | store code offset
        MOVE    #0x3F3C,(A1)+                   | MOVE.W #imm,-(SP) opcode
        MOVE    D1,(A1)+                        | segment number
        MOVE    #-0x5610,(A1)+                  | _LoadSeg trap ($A9F0)
        SUBQ.W  #0x1,D0                         | decrement count
        BNE.B   UNLOADSEG_LOOP                  | loop for all entries
UNLOADSEG_EMPTY:
        MOVE.L   (SP)+,(SP)                     | pop A0 frame, leave return address on top
        RTS                                     | return from _UnLoadSeg

| ----------------------------------------------------------
| LAUNCH_RESERVE_LIMIT -- reserve 24K of stack/heap-limit on launch.
| Reached via BRA.W from Launch's stack-clamp setup.
LAUNCH_RESERVE_LIMIT:
        MOVE.L  (MemTop).w,D0                   | D0 = top of RAM
        SUBI.L  #0x5F00,D0                      | reserve 24320 bytes
        BRA.W   LAUNCH_CLAMP_STACK              | -> clamp stack if needed

| ----------------------------------------------------------
| Chain -- _Chain ($A9F3): launch next app without full cleanup.
| Plus equivalent: segment_loader.s 178.
Chain:
        CLR     (LaunchFlag).w                  | flag: chaining (not fresh launch)
        BRA.B   LAUNCH_COPY_APNAME              | -> common launch code

| ----------------------------------------------------------
| Launch -- _Launch ($A9F2): launch an application.
| Classic version is much simpler than Plus's (Plus closes all
| DAs first; classic skips that).
Launch:
        ST      (LaunchFlag).w                  | flag: full launch (true)
LAUNCH_COPY_APNAME:
        MOVE    4(A0),(CurPageOption).w         | save page option (sound/screen cfg)
        MOVE.L  (A0)+,A0                        | A0 = app filename ptr (post-increment past it)
        LEA.L     (CurApName).w,A1              | A1 = current app name buffer
        MOVEQ.L #0x20,D0                        | 32 bytes for Pascal string
        _BlockMove                              | copy app name into low-mem global
        MOVE    (CurApRefNum).w,D0              | previous app's resource refNum
        BLE.B   Launch_RestoreScrap             | none open -> skip CloseResFile
        MOVE    D0,-(SP)                        | push refNum to close
        _CloseResFile                           | close previous app's resource file
        CLR     (CurApRefNum).w                 | clear refNum (no app file open)
Launch_RestoreScrap:
        MOVE.L  (BufPtr).w,SP                   | reset stack to top of buffer area
        CLR.L   (StackLowPoint).w               | reset stack low-water mark
        TST     (LaunchFlag).w                  | full launch (not chain)?
        BEQ.B   LAUNCH_CLEAR_HOOKS              | chain -> skip heap reinit
        MOVE.L  (ScrapHandle).w,D0              | desk scrap handle
        BLE.B   LAUNCH_INIT_APPLZONE            | no scrap -> skip save/restore
        MOVE.L  D0,A0                           | A0 = scrap handle for sizing
        _GetHandleSize                          | D0 = scrap byte count
        SUBA.L  D0,SP                           | SP -= D0
        MOVE.L  SP,A1                           | A1 = stack dest for scrap copy
        MOVE.L  (A0),A0                         | dereference scrap handle to data
        MOVE.L  D0,-(SP)                        | push size for later restore
        _BlockMove                              | copy scrap to stack (heap is about to die)
LAUNCH_INIT_APPLZONE:
        _InitApplZone                           | reinitialize application heap
        CLR     (CurApRefNum).w                 | clear app refNum (heap wiped)
        TST.L   (ScrapHandle).w                 | had scrap to restore?
        BLE.B   LAUNCH_REINSTALL_DRVRS          | no -> skip restore
        MOVE.L  (SP)+,D1                        | D1 = saved scrap size
        MOVE.L  D1,D0                           | D0 = size for NewHandle
        _NewHandle                              | allocate new scrap handle in fresh heap
        MOVE.L  A0,(ScrapHandle).w              | save new handle to global
        MOVE.L  D1,D0                           | D0 = byte count for BlockMove
        MOVE.L  (A0),A1                         | A1 = new scrap data ptr
        MOVE.L  SP,A0                           | A0 = stack source (saved scrap data)
        _BlockMove                              | copy scrap from stack to new handle
        ADDA.L  D1,SP                           | SP += D1
LAUNCH_REINSTALL_DRVRS:
        _RDrvrInstall                           | reinitialize desk accessory drivers
LAUNCH_CLEAR_HOOKS:
        CLR.L   (DragHook).w                    | clear Drag Manager hook
        CLR.L   (DeskHook).w                    | clear Desk Accessory hook
        LEA.L     (CloseOrnHook).w,A0           | A0 = close ornament hook area
        CLR.L   (A0)+                           | clear CloseOrnHook
        CLR.L   (A0)+                           | clear next hook slot
        CLR.L   (A0)+                           | clear next hook slot
        CLR     (TaskLock).w                    | unlock event task
        CLR.L   (ResErrProc).w                  | clear resource error proc
        SUBQ.W  #0x2,SP                         | space for OpenResFile result
        PEA.L     (CurApName).w                 | push app filename
        _OpenResFile                            | open app resource file
        MOVE    (SP)+,(CurApRefNum).w           | save reference number
        BLE.W   SEGSTACK_ERR                    | failed -> system error
        MOVEQ.L #0x0,D0                         | CODE 0
        BSR.W   LOADSEG_CONT                    | load CODE resource -> A0
        BEQ.W   SEGSTACK_ERR                    | failed -> system error
        MOVE.L  A0,(SaveSegHandle).w            | save CODE 0 handle
        MOVE.L  (A0),A0                         | dereference to CODE 0 data
        TST     (CurPageOption).w               | check page option
        BEQ.B   SegStack                        | 0: default stack ->
        BPL.W   LAUNCH_RESERVE_LIMIT            | >0: small reservation ->
        MOVE.L  (MemTop).w,D0                   | D0 = top of RAM
        SUBI.L  #0xD900,D0                      | reserve 55552 bytes
LAUNCH_CLAMP_STACK:
        CMP.L   SP,D0                           | new top vs current SP
        BGE.B   SegStack                        | D0 >= SP: keep current SP
        MOVEA.L D0,SP                           | else shrink SP down to D0
| ----------------------------------------------------------
| Seg Stack
| SegStack: set up application memory layout from CODE 0 header
| CODE 0 format: [aboveA5 size, belowA5 size, JT length, JT offset]
| Called during boot.
SegStack:
        SUBA.L  (A0)+,SP                        | allocate above-A5 space (app globals)
        MOVE.L  SP,A5                           | A5 = boundary between above/below
        SUBA.L  (A0)+,SP                        | allocate below-A5 space (jump table)
        MOVE.L  A5,(CurrentA5).w                | save A5 for app
        MOVE.L  SP,(CurStackBase).w             | stack starts here
        MOVE.L  SP,(StackLowPoint).w            | init stack low-water mark
        MOVE.L  (A0)+,D0                        | D0 = jump table size (bytes)
        MOVE.L  (A0)+,A1                        | A1 = jump table offset from A5
        MOVE    A1,(CurJTOffset).w              | save JT offset
        ADDA.L  A5,A1                           | A1 = absolute JT address
        LEA.L   0x2(A1),A3                      | A3 = first JT entry (skip header)
        _BlockMove                              | copy JT from CODE 0 to app memory
        MOVE.L  (SaveSegHandle).w,-(SP)         | push CODE 0 handle
        _ReleaseResource                        | release CODE 0 (data now in JT)
| initialize app A5 globals area
        LEA.L   0x8(A5),A0                      | A0 = app globals at A5+8
        CLR.L   (A0)+                           | clear grafGlobals pointer
        CLR.L   (A0)+                           | clear thePort
        MOVE.L  (AppParmHandle).w,(A0)+         | store Finder parameter handle
        CLR     (A0)+                           | clear remaining word
        MOVE.L  SP,A0                           | A0 = current stack base
        SUBA.L  (DefltStack).w,A0               | subtract default stack reserve
        _SetApplLimit                           | set max heap grow point
        MOVEQ.L #0x0,D7                         | clear D7
        JSR     (A3)                            | call subroutine via A3
        MOVE    (CurApRefNum).w,-(SP)           | set dCtlRefNum = current refNum
        _CloseResFile                           | close app's resource file
        CLR     (CurApRefNum).w                 | no app file open
        LEA.L     (LoaderPBlock).w,A0           | A0 = launch parameter block
        MOVE.L  A0,A1                           | A1 = also points to LoaderPBlock for fill
        PEA.L     (FinderName).w                | push pointer to "Finder" name
        MOVE.L  (SP)+,(A1)+                     | store FinderName ptr as filename field
        CLR.L   (A1)+                           | clear page-option / app-flags field
        BRA.W   Launch                          | re-launch Finder (ExitToShell tail)
SEGSTACK_ERR:
        MOVEQ.L #0x1A,D0                        | D0 = dsBadLaunch (26: can't launch application)
        _SysError                               | system error (halts)
        _Debugger                               | (unreachable) drop to debugger
