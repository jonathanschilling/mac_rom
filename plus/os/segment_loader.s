| Segment Loader -- _LoadSeg, _UnLoadSeg, _Chain, _Launch, _ExitToShell, _GetAppParms
|
| Apple source: SegmentLoader.a (MacSEROM.lst module LOADER). LoadSeg
| loads a CODE resource and patches its jump-table entries to JMPs into
| the code; UnloadSeg restores the "segment unloaded" entries. Launch and
| Chain start an application: CODE 0 header, heap size, SegStack (above-A5
| and below-A5 space, jump table copy, _SetApplLimit). ExitToShell
| relaunches the Finder; GetAppParms returns the application's name,
| resource file and parameter handle; RDrvrInstall (Apple's
| InstallRDrivers) installs the RAM-based drivers listed in the unit table
| (the serial drivers .AIn/.AOut/.BIn/.BOut).
|
| References: Inside Macintosh Vol II, Ch 2 (The Segment Loader).

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
        MOVE    D1,-0x2(A1)                     | store segment number (for UnloadSeg)
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
UnloadSeg:
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
        RTS                                     | return from UnloadSeg

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
        BTST    #0x4,0x4(A0)                    | dNeedGoodBye (needs a goodbye kiss)?
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

| ----------------------------------------------------------
|
| Seg Stack
|
| SegStack: set up application memory layout from CODE 0 header
| CODE 0 format: [aboveA5 size, belowA5 size, JT length, JT offset]
| Called during boot.
SegStack:
        SUBA.L  (A0)+,SP                        | allocate above-A5 space (app globals)
        MOVE.L  A7,A5                           | A5 = boundary between above/below
        SUBA.L  (A0)+,SP                        | allocate below-A5 space (jump table)
        MOVE.L  A5,(CurrentA5).w                | save A5 for app
        MOVE.L  A7,(CurStackBase).w             | stack starts here
        MOVE.L  A7,(StackLowPoint).w            | init stack low-water mark
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
| set heap limit (stack reserve)
        MOVE.L  A7,A0                           | A0 = current stack base
        SUBA.L  (DefltStack).w,A0               | subtract default stack reserve
        _SetApplLimit                           | set max heap grow point
| clear all data registers for clean app entry
        MOVEQ.L #0x0,D7                         | clear D7
        MOVEQ.L #0x0,D6                         | clear D6
        MOVEQ.L #0x0,D5                         | clear D5
        MOVEQ.L #0x0,D4                         | clear D4
        MOVEQ.L #0x0,D3                         | clear D3
        MOVEQ.L #0x0,D2                         | clear D2
        MOVEQ.L #0x0,D1                         | clear D1
        MOVEQ.L #0x0,D0                         | clear D0
| set address registers to safe "odd" values (trap on dereference)
        MOVE.L  #0xF80000,A2                    | invalid address (in ROM area)
        MOVE.L  A2,A1                           | A1 = invalid (trap on deref)
        MOVE.L  A2,A0                           | A0 = invalid (trap on deref)
        MOVE.L  A2,(ResetStackPtr).w            | save for ExitToShell
        JSR     (A3)                            | jump to first JT entry (app main)
| _ExitToShell ($A9F4): quit current application, return to Finder
ExitToShell:
        SUBA.L  A0,A0                           | A0 = NIL (no grow zone proc)
        _SetGrowZone                            | clear grow zone proc
        SUBQ.W  #0x4,SP                         | room for result
        _LoadScrap                              | load desk scrap from disk
        ADDQ.W  #0x4,SP                         | discard result
| build SetVol param block to restore boot volume
        MOVEQ.L #0x1F,D0                        | 32 words = 64 bytes
EXITTOSHELL_LOOP:
        CLR     -(SP)                           | zero the param block
        DBF     D0,EXITTOSHELL_LOOP             | loop 32 words
        MOVE.L  A7,A0                           | A0 = param block on stack
        MOVE    (BootDrive).w,ioVRefNum(A0)     | set ioVRefNum to boot volume
        _SetVol                                 | restore default volume
        ADDA    #0x40,SP                        | pop param block
| launch Finder
        LEA.L   (LoaderPBlock).w,A0             | A0 = loader param block
        MOVE.L  A0,A1                           | A1 = write cursor into block
        PEA.L   (FinderName).w                  | push Finder filename
        MOVE.L  (SP)+,(A1)+                     | store in param block
        CLR.L   (A1)+                           | clear remaining fields
        BRA     Launch                          | jump to Launch

| ----------------------------------------------------------
|
| EXITTOSHELL_ERR
|
| Launch failed: dsFinderErr (error 26)
EXITTOSHELL_ERR:
        MOVEQ.L #0x1A,D0                        | dsFinderErr
        _SysError                               | show system error
        _Debugger                               | drop into debugger
| _GetAppParms ($A9F5): get current application info
| Pascal: procedure GetAppParms(VAR apName: Str255; VAR apRefNum: INTEGER; VAR apParam: Handle);
GetAppParms:
        MOVE.L  (SP)+,A0                        | pop return address
        MOVE.L  (SP)+,A1                        | A1 = VAR apParam
        MOVE.L  0x10(A5),(A1)                   | apParam = app A5 global at offset $10
        MOVE.L  (SP)+,A1                        | A1 = VAR apRefNum
        MOVE    (CurApRefNum).w,(A1)            | apRefNum from global
        MOVE.L  (SP)+,A1                        | A1 = VAR apName (pointer)
        MOVE.L  A0,-(SP)                        | push return address back to stack
        LEA.L   (CurApName).w,A0                | A0 = source string (CurApName global)
        MOVEQ.L #0x20,D0                        | D0 = length (32 bytes)
        _BlockMove                              | copy application name
        RTS                                     | return from GetAppParms

| ----------------------------------------------------------
|
| _RDrvrInstall ($A04F)
|
| _RDrvrInstall: reinitialize desk accessory DCEs for new application
| Clears DCEs whose drivers lived in the app heap (now destroyed)
| Called during boot.
RDrvrInstall:
        MOVEM.L D0-D4/A0-A3,-(SP)               | save regs
        MOVE.L  (UTableBase).w,A3               | A3 = unit table
        MOVE    (UnitTableEntryCount).w,D3      | D3 = unit count
        MOVEQ.L #-0x1,D4                        | D4 = starting refNum (-1)
RDRVRINSTALL_CONT:
        MOVE.L  (A3)+,D0                        | D0 = DCE handle for this unit
        BEQ.B   RDRVRINSTALL_SKIP               | empty slot ->
        MOVE.L  D0,A1                           | A1 = DCE handle
        MOVE.L  (A1),D0                         | dereference DCE handle
        BEQ.B   RDRVRINSTALL_SKIP               | nil (purged) ->
        MOVE.L  D0,A1                           | A1 = DCE record pointer
        BTST    #0x6,0x5(A1)                    | dRAMBased flag set?
        BEQ.B   RDRVRINSTALL_SKIP               | no, ROM driver -> skip
        MOVE.L  (A1),D0                         | D0 = driver pointer
        BEQ.B   RDRVRINSTALL_SKIP               | nil ->
        MOVE.L  0x14(A1),D1                     | D1 = saved dCtlStorage
        CMP.L   (ApplZone).w,D0                 | driver in app zone?
        BLT.B   RDRVRINSTALL_NO                 | no, system driver -> keep
| driver was in app heap: zero out DCE (40 bytes)
        MOVEQ.L #0x27,D0                        | 40 bytes - 1
        MOVE.L  A1,A0                           | A0 = DCE to clear
RDRVRINSTALL_LOOP:
        CLR.B   (A0)+                           | zero one byte
        DBF     D0,RDRVRINSTALL_LOOP            | loop 40 times
        BSET    #0x6,0x5(A1)                    | restore dRAMBased flag
        MOVE    D4,0x18(A1)                     | set dCtlRefNum = current refNum
RDRVRINSTALL_NO:
        CLR.L   0x1E(A1)                        | clear dCtlMenu
        MOVE.L  0x14(A1),D0                     | D0 = dCtlStorage address
        CMP.L   (ApplZone).w,D0                 | storage in app zone?
        BLT.B   RDRVRINSTALL_NO_2               | no ->
        MOVEQ.L #0x0,D1                         | clear storage (was in app zone)
RDRVRINSTALL_NO_2:
        MOVE.L  D1,0x14(A1)                     | update dCtlStorage
RDRVRINSTALL_SKIP:
        SUBQ.W  #0x1,D4                         | next refNum (more negative)
        SUBQ.W  #0x1,D3                         | decrement unit count
        BNE.B   RDRVRINSTALL_CONT               | more units ->
        MOVEM.L (SP)+,D0-D4/A0-A3               | restore regs
        RTS                                     | return from RDrvrInstall

