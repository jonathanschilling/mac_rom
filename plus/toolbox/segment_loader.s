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
| Called during boot (3,696 times in 30s trace).
| _LoadSeg ($A9F0): load a CODE segment into memory
| Called by jump table stubs when an unloaded segment is referenced
| D0 (from stack) = segment number
LoadSeg:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save registers
        MOVE    0x18(SP),D0                     | D0 = segment number (from JSR stub)
        BSR.B   LOADSEG_CONT                    | load CODE resource -> A0 = handle
        BEQ.B   LOADSEG_ERR                     | failed ->
| lock the segment in memory
        BTST    #0x7,(A0)                       | already locked?
        BNE.B   LOADSEG_OK                      | yes ->
        TST.B   (SegHiEnable).w                 | move segments high?
        BEQ.B   LOADSEG_NO                      | no ->
        _MoveHHi                                | move to top of heap first
LOADSEG_NO:
        BSet    #0x7,(A0)                       | lock the handle
| dereference and patch jump table entries
LOADSEG_OK:
        MOVE.L  (A0),-(SP)                      | get segment pointer
        CLR.B   (SP)                            | clear master pointer flags byte
        MOVE.L  (SP)+,A0                        | A0 = segment data pointer
| A0+0 = first jump table offset, A0+2 = entry count
        MOVE.L  A5,A1                           | A1 = app globals (A5)
        ADDA    (CurJTOffset).w,A1              | + jump table offset
        ADDA    (A0),A1                         | + segment's JT base offset
| check if already patched (JMP = $4EF9)
        CMPI    #0x4EF9,0x2(A1)                 | already has JMP instruction?
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
        MOVE.L  0x14(SP),A1                     | get return address (points inside jump table)
        SUBQ.L  #0x6,A1                         | adjust to point to start of jump table entry
        MOVE.L  A1,0x16(SP)                     | overwrite saved segment number with execution address
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore registers
        ADDQ.W  #0x2,SP                         | skip dummy word
        TST.B   (LoadTrap).w                    | trap on segment load?
        BEQ.B   LOADSEG_EXIT                    | no -> return
        _Debugger                               | yes -> break into debugger
LOADSEG_EXIT:
        RTS                                     | return to execute segment

| ----------------------------------------------------------
|
| LOADSEG_ERR
|
LOADSEG_ERR:
        MOVEQ.L #0xF,D0                         | DSLoadErr (15)
        _SysError                               | system error
        _Debugger                               | trap to debugger
| LOADSEG_CONT -- load CODE resource -> A0 = handle.
LOADSEG_CONT:
        SUBQ.W  #0x4,SP                         | space for result handle
        MOVE.L  #0x434F4445,-(SP)               | 'CODE' resource type
        MOVE    D0,-(SP)                        | resource ID (segment number)
        ST.B    (ResLoad).w                     | enable resource loading
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
| restore jump table stubs: MOVE.W #seg,-(SP); _LoadSeg
        MOVE.L  (A0),A0                         | dereference segment
        MOVE.L  A5,A1                           | A1 = globals
        ADDA    (CurJTOffset).w,A1              | + jump table offset
        ADDA    (A0),A1                         | + segment's JT base
        MOVE    0x2(A0),D0                      | D0 = entry count
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
        MOVE.L  (SP)+,(SP)                      | pop parameter
        RTS                                     | return from UnLoadSeg

| ----------------------------------------------------------
|
| UNLOADSEG_CONT
|
| Called during boot.
UNLOADSEG_CONT:
        MOVE.L  (VBLQueueHdr_Head).w,A1         | A1 = first VBL queue entry
UNLOADSEG_SKIP:
        MOVE.L  A1,D0                           | end of queue?
        BEQ.B   UNLOADSEG_OK                    | yes ->
        MOVE.L  A1,A0                           | A0 = current entry
        MOVE.L  (A0),A1                         | A1 = next entry (qLink)
        MOVE.L  fWidMax(A0),D0                  | D0 = VBL task address
        AND.L   (Lo3Bytes).w,D0                 | strip flags
        CMP.L   (ApplZone).w,D0                 | below app zone?
        BCS.B   UNLOADSEG_SKIP                  | yes, system -> skip
        CMP.L   (ROMBase).w,D0                  | in ROM?
        BCC.B   UNLOADSEG_SKIP                  | yes -> skip
        _VRemove                                | in app zone -> remove
        BRA.B   UNLOADSEG_SKIP                  | continue scan

| ----------------------------------------------------------
|
| UNLOADSEG_OK
|
| Called during boot.
UNLOADSEG_OK:
        RTS                                     | return from UNLOADSEG_CONT (VBL cleanup)

| ----------------------------------------------------------
|
| UNLOADSEG_CONT_2
|
| UNLOADSEG_CONT_2: CurPageOption > 0: reserve 24K for sound/screen buffer
UNLOADSEG_CONT_2:
        MOVE.L  (MemTop).w,D0                   | D0 = top of RAM
        SUBI.L  #0x5F00,D0                      | reserve 24320 bytes
        BRA     LAUNCH_CONT_2                   | -> clamp stack if needed

| ----------------------------------------------------------
|
| _Chain ($A9F3)
|
| _Chain ($A9F3): launch next app without full cleanup
Chain:
        CLR     (LaunchFlag).w                  | flag: chaining (not fresh launch)
        BRA.B   LAUNCH_CONT                     | -> common launch code

| ----------------------------------------------------------
|
| _Launch ($A9F2): launch an application
| Closes all DA drivers, reinitializes app heap, loads CODE 0
|
Launch:
        ST.B    (LaunchFlag).w                  | flag: full launch (close everything)
        MOVEM.L D0-D1/A0-A1,-(SP)               | save registers
| close all open desk accessories
        SUBA    #0x32,SP                        | param block on stack
        MOVE    #-0x1,0x1A(SP)                  | csCode = -1 (goodbye)
        MOVE.L  (UTableBase).w,A1               | unit table
        MOVE    (UnitTableEntryCount).w,D1      | number of units
LAUNCH_LOOP:
        MOVE.L  (A1)+,D0                        | D0 = unit table entry (DCE handle)
        BEQ.B   LAUNCH_EMPTY                    | empty slot ->
        MOVE.L  D0,A0                           | A0 = DCE handle
        MOVE.L  (A0),A0                         | dereference to DCE
        BTST    #0x4,0x4(A0)                    | is it a desk accessory?
        BEQ.B   LAUNCH_EMPTY                    | no ->
        MOVE    0x18(A0),0x18(SP)               | copy refNum to param block
        MOVE.L  A7,A0                           | A0 = param block
        _Control                                | send goodbye control call
LAUNCH_EMPTY:
        SUBQ.W  #0x1,D1                         | next unit
        BNE.B   LAUNCH_LOOP                     | loop all units
        ADDA    #0x32,SP                        | pop param block
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore regs
| LAUNCH_CONT: common launch/chain entry point
| A0 = ptr to launch parameter block: [filename ptr, pageOption, app name...]
LAUNCH_CONT:
        MOVE.L  A0,A3                           | A3 = launch param block
        MOVE.L  (A3)+,A0                        | A0 = app filename ptr
        MOVE    (A3)+,(CurPageOption).w         | save page option (sound/screen cfg)
        LEA.L   (CurApName).w,A1                | A1 = current app name buffer
        MOVEQ.L #0x20,D0                        | 32 bytes for Pascal string
        _BlockMove                              | copy app name
| close previous app's resource file
        MOVE    (CurApRefNum).w,D0              | previous app refNum
        BLE.B   LAUNCH_EMPTY_2                  | none open ->
        MOVE    D0,-(SP)                        | push refNum
        _CloseResFile                           | close it
        CLR     (CurApRefNum).w                 | clear refNum
LAUNCH_EMPTY_2:
        MOVE.L  (BufPtr).w,SP                   | reset stack to top of buffer area
        CLR.L   (StackLowPoint).w               | reset stack low-water mark
        TST     (LaunchFlag).w                  | full launch (not chain)?
        BEQ.B   LAUNCH_SKIP                     | chain -> skip heap reinit
| full launch: save desk scrap, reinitialize app heap
        MOVE.L  (ScrapHandle).w,D0              | desk scrap handle
        BLE.B   LAUNCH_NO                       | no scrap ->
| copy scrap data to stack temporarily (heap will be destroyed)
        MOVE.L  D0,A0                           | A0 = scrap handle
        _GetHandleSize                          | D0 = scrap size
        ADDQ.L  #0x1,D0                         | round up to even
        BCLR    #0x0,D0                         | force even alignment
        SUBA.L  D0,SP                           | allocate on stack
        MOVE.L  A7,A1                           | A1 = stack dest
        MOVE.L  (A0),A0                         | dereference scrap handle
        MOVE.L  D0,-(SP)                        | push size (for later restore)
        _BlockMove                              | copy scrap to stack
LAUNCH_NO:
| clear all hook vectors and system state before reinit
        CLR.L   (DragHook).w                    | clear drag hook
        CLR.L   (DeskHook).w                    | clear desk hook
        LEA.L   (CloseOrnHook).w,A0             | A0 = close ornament hook area
        CLR.L   (A0)+                           | clear CloseOrnHook
        CLR.L   (A0)+                           | clear RestProc
        CLR.L   (A0)+                           | clear SaveProc
        CLR     (TaskLock).w                    | unlock event task
        CLR.L   (ResErrProc).w                  | clear resource error proc
        CLR.L   (EjectNotify).w                 | clear eject notify proc
        BSR     UNLOADSEG_CONT                  | remove app VBL tasks
        _InitApplZone                           | reinitialize application heap
        CLR     (CurApRefNum).w                 | clear app refNum
| restore desk scrap from stack into new heap
        TST.L   (ScrapHandle).w                 | had scrap?
        BLE.B   LAUNCH_NO_2                     | no ->
        MOVE.L  (SP)+,D1                        | D1 = scrap size
        MOVE.L  D1,D0                           | D0 = size for NewHandle
        _NewHandle                              | allocate new scrap handle
        MOVE.L  A0,(ScrapHandle).w              | save new handle
        MOVE.L  D1,D0                           | D0 = byte count
        MOVE.L  (A0),A1                         | A1 = new scrap data ptr
        MOVE.L  A7,A0                           | A0 = stack (saved scrap data)
        _BlockMove                              | copy scrap from stack to new handle
        ADDA.L  D1,SP                           | pop scrap data from stack
LAUNCH_NO_2:
        _RDrvrInstall                           | reinitialize desk accessory drivers
| LAUNCH_SKIP: open application resource file and load CODE 0
LAUNCH_SKIP:
        SUBQ.L  #0x2,SP                         | space for OpenResFile result
        PEA.L   (CurApName).w                   | push app filename
| check for 'LC' launch control signature in param block
        CMPI    #0x4C43,(A3)+                   | 'LC' signature?
        BNE.B   LAUNCH_NO_3                     | no ->
        ADDQ.L  #0x5,A3                         | skip 5 bytes of LC data
        BTST    #0x6,(A3)+                      | permission bit set?
        BEQ.B   LAUNCH_NO_3                     | no ->
        MOVE.B  #0x1,(RMgrPerm).w               | set resource perm flag for OpenResFile
LAUNCH_NO_3:
        _OpenResFile                            | open app resource file
        MOVE    (SP)+,(CurApRefNum).w           | save reference number
        BLE     EXITTOSHELL_ERR                 | failed -> system error
| load CODE resource 0 (jump table segment)
        MOVEQ.L #0x0,D0                         | CODE 0
        BSR     LOADSEG_CONT                    | load CODE resource -> A0
        BEQ     EXITTOSHELL_ERR                 | failed -> system error
        MOVE.L  A0,(SaveSegHandle).w            | save CODE 0 handle
        MOVE.L  (A0),A0                         | dereference to CODE 0 data
| configure stack based on CurPageOption
        TST     (CurPageOption).w               | check page option
        BEQ.B   L_SegStack                      | 0: default stack ->
        BPL     UNLOADSEG_CONT_2                | >0: small reservation ->
| negative: reserve 55K for sound/screen buffers
        MOVE.L  (MemTop).w,D0                   | D0 = top of RAM
        SUBI.L  #0xD900,D0                      | reserve 55552 bytes
LAUNCH_CONT_2:
        CMP.L   A7,D0                           | new top above current SP?
        BGE.B   L_SegStack                      | yes, no need to lower SP ->
        MOVE.L  D0,SP                           | lower SP for sound/screen buffers
L_SegStack:
        MOVE.L  (0x7E0).w,A3                    | dispatch vector: _SwapFont (SegStack)
        JMP     (A3)                            | jump to SegStack

