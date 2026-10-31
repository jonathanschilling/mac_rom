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

LOADER:                                         | Apple source module (MacSEROM.lst)
LOADSEG:
    MOVEM.L     D0-D2/A0-A1,-(SP)               | save regs
    MOVE.W      0x18(SP),D0                     | D0 = segment number (from stack)
    BSR.B       GETCODERSRC                     | load CODE resource
    BEQ.B       LOADSEG_ERR                     | not found -> fatal
    _HGetState                                  | get handle state
    BTST        #0x7,D0                         | already locked?
    BNE.B       LOADER_LOCKED                   | yes, skip lock ->
    TST.B       (SegHiEnable).W                 | high-loading enabled?
    BEQ.B       LOADER_NO_MOVEHHI               | no ->
    _MoveHHi                                    | move handle high
LOADER_NO_MOVEHHI:
    _HLock                                      | lock code segment
LOADER_LOCKED:
    MOVE.L      (A0),D0                         | dereference handle
    _StripAddress                               | strip high bits (24/32-bit)
    MOVEA.L     D0,A0                           | A0 = code segment ptr
    MOVEA.L     A5,A1                           | A1 = app globals
    ADDA.W      (CurJTOffset).W,A1              | + jump table offset
    ADDA.W      (A0),A1                         | + segment's JT offset
    CMPI.W      #0x4EF9,0x2(A1)                 | already loaded? (JMP abs)
    BEQ.B       LOADSEG_EMPTY                   | yes, skip patching ->
    MOVE.W      0x2(A0),D0                      | D0 = number of entries
    BEQ.B       LOADSEG_EMPTY                   | none ->
    MOVE.W      0x18(SP),D1                     | D1 = segment number
    MOVEQ.L     #0x0,D2                         | clear offset
LOADSEG_LOOP:
    MOVE.W      (A1)+,D2                        | get entry offset
    MOVE.W      D1,-0x2(A1)                     | store segment number
    MOVE.W      #0x4EF9,(A1)+                   | write JMP opcode
    PEA.L       0x4(A0,D2.L)                    | compute absolute entry address
    MOVE.L      (SP)+,(A1)+                     | write JMP target
    SUBQ.W      #0x1,D0                         | next entry
    BNE.B       LOADSEG_LOOP                    | loop for all entries
LOADSEG_EMPTY:
    MOVEA.L     0x14(SP),A1                     | return address
    SUBQ.L      #0x6,A1                         | back up past MOVE.W #seg / _LoadSeg
    MOVE.L      A1,0x16(SP)                     | patch return to re-execute JT entry
    MOVEM.L     (SP)+,D0-D2/A0-A1               | restore regs
    ADDQ.W      #0x2,SP                         | pop segment number
    TST.B       (LoadTrap).W                    | debugger trap on load?
    BEQ.B       LOADSEG_EXIT                    | no ->
    _Debugger                                   | break into debugger
LOADSEG_EXIT:
    RTS                                         | return (re-executes JT entry)
LOADSEG_ERR:
    MOVEQ.L     #0xF,D0                         | DS error 15: segment not found
    _SysError                                   | fatal error
    _Debugger                                   | break if returns
GETCODERSRC:
    ST.B        (ResLoad).W                     | ensure auto-load is on
    SUBQ.W      #0x4,SP                         | space for result handle
    MOVE.L      #0x434F4445,-(SP)               | push 'CODE' type
    MOVE.W      D0,-(SP)                        | push segment number
    _GetResource                                | load CODE resource
    MOVEA.L     (SP)+,A0                        | A0 = resource handle
    MOVE.L      A0,D0                           | D0 = handle (test for nil)
    RTS                                         | return from GetCodeResource
UNLOADSEG:
    MOVEA.L     0x4(SP),A0                      | A0 = routine address from arg
    CMPI.W      #0x4EF9,(A0)                    | JMP opcode? (segment loaded?)
    BNE.B       UNLOADSEG_DONE                  | not loaded, nothing to do ->
    MOVE.W      -0x2(A0),D0                     | D0 = segment number
    BSR.B       GETCODERSRC                     | get CODE resource handle
    _HUnlock                                    | unlock segment
    MOVEA.L     (A0),A0                         | dereference handle
    MOVEA.L     A5,A1                           | A1 = app globals
    ADDA.W      (CurJTOffset).W,A1              | + jump table offset
    ADDA.W      (A0),A1                         | + segment's JT offset
    MOVE.W      0x2(A0),D0                      | D0 = number of entries
    BEQ.B       UNLOADSEG_DONE                  | none ->
UNLOADSEG_LOOP:
    MOVE.W      (A1),D1                         | save segment number
    MOVE.L      0x4(A1),D2                      | absolute target address
    SUB.L       A0,D2                           | - segment base
    SUBQ.L      #0x4,D2                         | - header = offset in segment
    MOVE.W      D2,(A1)+                        | restore entry offset
    MOVE.W      #0x3F3C,(A1)+                   | write MOVE.W #imm,-(SP)
    MOVE.W      D1,(A1)+                        | segment number as immediate
    MOVE.W      #0xA9F0,(A1)+                   | write _LoadSeg trap
    SUBQ.W      #0x1,D0                         | next entry
    BNE.B       UNLOADSEG_LOOP                  | loop for all entries
UNLOADSEG_DONE:
    MOVE.L      (SP)+,(SP)                      | pop routine addr, keep return
    RTS                                         | return from UNLOADSEG_LOOP
APPHEAP_TEST:
    _StripAddress                               | strip high bits
    CMP.L       (ApplZone).W,D0                 | below application zone?
    BCS.B       APPHEAP_TEST_RTS                | yes, not in app heap ->
    CMP.L       (BufPtr).W,D0                   | above buffer ptr?
    BCC.B       APPHEAP_TEST_RTS                | yes, not in app heap ->
    MOVEQ.L     #0x0,D0                         | in app heap: return 0
APPHEAP_TEST_RTS:
    TST.L       D0                              | set condition codes
    RTS                                         | return from UNLOADSEG_LOOP
UNLOADSEG_CONT:
    MOVEA.L     (VBLQueueHdr_Head).W,A1         | first VBL task
VBL_SCAN_LOOP:
    MOVE.L      A1,D0                           | end of list?
    BEQ.B       UNLOADSEG_OK                    | yes ->
    MOVEA.L     A1,A0                           | A0 = current VBL task
    MOVEA.L     (A0),A1                         | A1 = next VBL task
    MOVE.L      0x6(A0),D0                      | vblAddr (task address)
    BSR.B       APPHEAP_TEST                    | in application heap?
    BNE.B       VBL_SCAN_LOOP                   | no, keep it ->
    _VRemove                                    | remove app VBL task
    BRA.B       VBL_SCAN_LOOP                   | continue scanning
UNLOADSEG_OK:
    RTS                                         | return from RemoveAppVBLs
UNLOADSEG_CONT_2:
    MOVE.L      (MemTop).W,D0                   | top of RAM
    SUBI.L      #0x5F00,D0                      | - 24K = smaller stack size
    BRA.W       LAUNCH_CONT_2                   | -> check stack
CHAIN:
    CLR.W       (LaunchFlag).W                  | chain: no full relaunch
    BRA.B       LAUNCH_CONT                     | -> common entry
LAUNCH:
    ST.B        (LaunchFlag).W                  | full launch flag
    MOVEM.L     D0-D1/A0-A1,-(SP)               | save regs
    SUBA.W      #0x32,SP                        | allocate param block
    MOVE.W      #0xFFFF,0x1A(SP)                | csCode = goodbye (-1)
    MOVEA.L     (UTableBase).W,A1               | unit table base
    MOVE.W      (UnitTableEntryCount).W,D1      | number of unit table entries
LAUNCH_LOOP:
    MOVE.L      (A1)+,D0                        | get DCE handle
    BEQ.B       LAUNCH_EMPTY                    | nil ->
    MOVEA.L     D0,A0                           | dereference
    MOVEA.L     (A0),A0                         | DCE ptr
    BTST        #0x4,0x4(A0)                    | dNeedGoodBye flag?
    BEQ.B       LAUNCH_EMPTY                    | no ->
    MOVE.W      0x18(A0),0x18(SP)               | copy dCtlRefNum to csParam
    MOVEA.L     SP,A0                           | param block ptr
    _Control                                    | send goodbye kiss
LAUNCH_EMPTY:
    SUBQ.W      #0x1,D1                         | next device
    BNE.B       LAUNCH_LOOP                     | loop for all devices
    ADDA.W      #0x32,SP                        | deallocate param block
    MOVEM.L     (SP)+,D0-D1/A0-A1               | restore regs
| LAUNCH_CONT: common launch/chain entry point
| A0 = ptr to launch parameter block: [filename ptr, pageOption, app name...]
LAUNCH_CONT:
    MOVEA.L     A0,A3                           | A3 = launch parameter block
    MOVEA.L     (A3)+,A0                        | A0 = filename ptr
    MOVE.W      (A3)+,(CurPageOption).W         | page option
    LEA.L       (CurApName).W,A1                | dest = CurApName
    MOVEQ.L     #0x20,D0                        | 32 bytes
    _BlockMove                                  | copy app name
    MOVEQ.L     #0x0,D3                         | D3 = extended launch flags
    CMPI.W      #0x4C43,(A3)+                   | 'LC' signature? (extended block)
    BNE.B       LAUNCH_NO_LC                    | no ->
    ADDQ.W      #0x4,A3                         | skip extension length
    MOVE.W      (A3)+,D3                        | D3 = extended flags
LAUNCH_NO_LC:
    MOVE.W      (CurApRefNum).W,D0              | current app resource file
    BLE.B       LAUNCH_EMPTY_2                  | none open ->
    MOVE.W      D0,-(SP)                        | push refnum
    _CloseResFile                               | close old app's resource file
    CLR.W       (CurApRefNum).W                 | clear refnum
LAUNCH_EMPTY_2:
    MOVEA.L     (BufPtr).W,SP                   | reset stack to BufPtr
    CLR.L       (StackLowPoint).W               | clear stack low-water mark
    TST.W       (LaunchFlag).W                  | full launch?
    BEQ.B       LAUNCH_OPEN_RFORK               | no (chain), skip cleanup ->
    MOVE.L      (ScrapHandle).W,D0              | desk scrap handle
    BLE.B       LAUNCH_NO                       | no scrap ->
    MOVEA.L     D0,A0                           | scrap handle
    _GetHandleSize                              | D0 = scrap size
    ADDQ.L      #0x1,D0                         | round up
    BCLR        #0x0,D0                         | to even
    SUBA.L      D0,SP                           | allocate on stack
    MOVEA.L     SP,A1                           | A1 = stack buffer
    MOVEA.L     (A0),A0                         | dereference scrap
    MOVE.L      D0,-(SP)                        | save scrap size
    _BlockMove                                  | copy scrap to stack
LAUNCH_NO:
    CLR.L       (DragHook).W                    | clear drag hook
    CLR.L       (DeskHook).W                    | clear desk hook
    LEA.L       (CloseOrnHook).W,A0             | clear ornament hooks
    CLR.L       (A0)+                           | CloseOrnHook
    CLR.L       (A0)+                           | RestProc
    CLR.L       (A0)+                           | SaveProc
    CLR.W       (TaskLock).W                    | unlock tasks
    CLR.L       (ResErrProc).W                  | clear resource error proc
    CLR.L       (EjectNotify).W                 | clear eject notification
    BSR.W       UNLOADSEG_CONT                  | remove app VBL tasks
    _InitApplZone                               | reinitialize application zone
    CLR.W       (CurApRefNum).W                 | clear app refnum
    TST.L       (ScrapHandle).W                 | had a scrap?
    BLE.B       LAUNCH_NO_2                     | no ->
    MOVE.L      (SP)+,D1                        | D1 = scrap size
    MOVE.L      D1,D0                           | D0 = size for NewHandle
    _NewHandle                                  | allocate new scrap handle
    MOVE.L      A0,(ScrapHandle).W              | store new handle
    MOVE.L      D1,D0                           | D0 = byte count
    MOVEA.L     (A0),A1                         | A1 = new scrap buffer
    MOVEA.L     SP,A0                           | A0 = stack copy
    _BlockMove                                  | restore scrap from stack
    ADDA.L      D1,SP                           | pop stack copy
LAUNCH_NO_2:
    _RDrvrInstall                               | reinstall RAM drivers
LAUNCH_OPEN_RFORK:
    SUBQ.W      #0x2,SP                         | space for result
    PEA.L       (CurApName).W                   | push app filename
    MOVEQ.L     #0x0,D0                         | read-only by default
    BTST        #0x6,D3                         | extended flag: read/write?
    BEQ.B       LAUNCH_SET_PERM                 | no ->
    MOVEQ.L     #0x1,D0                         | read/write permission
LAUNCH_SET_PERM:
    MOVE.B      D0,(RMgrPerm).W                 | set resource file permission
    _OpenResFile                                | open app's resource fork
    MOVE.W      (SP)+,(CurApRefNum).W           | store app refnum
    BLE.W       EXITTOSHELL_ERR                 | open failed ->
    MOVEQ.L     #0x0,D0                         | segment 0 (jump table)
    BSR.W       GETCODERSRC                     | load CODE 0
    BEQ.W       EXITTOSHELL_ERR                 | not found ->
    MOVE.L      A0,(SaveSegHandle).W            | save CODE 0 handle
    MOVEA.L     (A0),A0                         | dereference
    TST.W       (CurPageOption).W               | stack size option?
    BEQ.B       L_SegStack                      | default ->
    BPL.W       UNLOADSEG_CONT_2                | small stack ->
    MOVE.L      (MemTop).W,D0                   | top of RAM
    SUBI.L      #0xD900,D0                      | - 55K = larger stack size
LAUNCH_CONT_2:
    CMP.L       SP,D0                           | below current stack?
    BGE.B       L_SegStack                      | no, keep current ->
    MOVEA.L     D0,SP                           | lower stack pointer
L_SegStack:
    MOVEA.L     (0x7E0).W,A3                    | SegStack vector
    JMP         (A3)                            | dispatch to SegStack
VSEGSTACK:
    SUBA.L      (A0)+,SP                        | subtract above-A5 size
    MOVEA.L     SP,A5                           | A5 = app globals base
    SUBA.L      (A0)+,SP                        | subtract below-A5 size
    MOVE.L      A5,(CurrentA5).W                | set CurrentA5
    MOVE.L      SP,(CurStackBase).W             | set stack base
    MOVE.L      SP,(StackLowPoint).W            | init low-water mark
    MOVE.L      (A0)+,D0                        | D0 = jump table size
    MOVEA.L     (A0)+,A1                        | A1 = jump table offset
    MOVE.W      A1,(CurJTOffset).W              | set CurJTOffset
    ADDA.L      A5,A1                           | A1 = jump table address
    LEA.L       0x2(A1),A3                      | A3 = first JT entry
    _BlockMove                                  | copy CODE 0 jump table
    MOVE.L      (SaveSegHandle).W,-(SP)         | push CODE 0 handle
    _ReleaseResource                            | release CODE 0 resource
    LEA.L       0x8(A5),A0                      | A0 -> the application parameters at 8(A5)
    CLR.L       (A0)+                           | 8(A5): standard input (Lisa Pascal) := nil
    CLR.L       (A0)+                           | 12(A5): standard output := nil
    MOVE.L      (AppParmHandle).W,(A0)+         | 16(A5): the Finder parameters (AppParmHandle)
    CLR.W       (A0)+                           | 20(A5): physExec flag (Lisa Pascal) := 0
    MOVEA.L     SP,A0                           | A0 = stack ptr
    SUBA.L      (DefltStack).W,A0               | - default stack size
    _SetApplLimit                               | set application heap limit
    MOVEQ.L     #0x0,D7                         | D0-D7 := 0: the application starts in a constant state
    MOVEQ.L     #0x0,D6                         | D6 := 0
    MOVEQ.L     #0x0,D5                         | D5 := 0
    MOVEQ.L     #0x0,D4                         | D4 := 0
    MOVEQ.L     #0x0,D3                         | D3 := 0
    MOVEQ.L     #0x0,D2                         | D2 := 0
    MOVEQ.L     #0x0,D1                         | D1 := 0
    MOVEQ.L     #0x0,D0                         | D0 := 0
    MOVEA.L     #0xF80000,A2                    | A2 = $F80000, the diagnostic ROM space (Apple: DiagROM)
    MOVEA.L     A2,A1                           | A1 := DiagROM
    MOVEA.L     A2,A0                           | A0 := DiagROM
    MOVE.L      A2,(ResetStackPtr).W            | location 0 := DiagROM: NIL handles point to harmless ROM space
    JSR         (A3)                            | enter application at 1st JT entry
EXITTOSHELL:
    SUBA.L      A0,A0                           | nil
    _SetGrowZone                                | clear grow zone proc
    SUBQ.W      #0x4,SP                         | space for result
    _LoadScrap                                  | load desk scrap to memory
    ADDQ.W      #0x4,SP                         | pop result
    MOVEQ.L     #0x1F,D0                        | 32 words = 64 bytes
EXITTOSHELL_LOOP:
    CLR.W       -(SP)                           | zero param block on stack
    DBF.W       D0,EXITTOSHELL_LOOP             | allocate 64 bytes
    MOVEA.L     SP,A0                           | A0 = param block
    MOVE.W      (BootDrive).W,0x16(A0)          | ioVRefNum = boot volume
    _SetVol                                     | set default volume
    ADDA.W      #0x40,SP                        | pop param block
    LEA.L       (LoaderPBlock).W,A0             | A0 = loader param block
    MOVEA.L     A0,A1                           | copy ptr
    PEA.L       (FinderName).W                  | push Finder name ptr
    MOVE.L      (SP)+,(A1)+                     | store filename in pblock
    CLR.L       (A1)+                           | clear page option
    _Launch                                     | launch Finder
| ----------------------------------------------------------
|
| EXITTOSHELL_ERR
|
| Launch failed: dsFinderErr (error 26)
EXITTOSHELL_ERR:
    MOVEQ.L     #0x1A,D0                        | dsFinderErr (error 26)
    _SysError                                   | fatal: can't find Finder
    _Debugger                                   | break if returns
GETAPPPARMS:
    MOVEA.L     (SP)+,A0                        | return address
    MOVEA.L     (SP)+,A1                        | VAR appParmHandle
    MOVE.L      0x10(A5),(A1)                   | return AppParmHandle
    MOVEA.L     (SP)+,A1                        | VAR appRefNum
    MOVE.W      (CurApRefNum).W,(A1)            | return CurApRefNum
    MOVEA.L     (SP)+,A1                        | VAR appName (StringPtr)
    MOVE.L      A0,-(SP)                        | push return address
    LEA.L       (CurApName).W,A0                | source = CurApName
    MOVEQ.L     #0x20,D0                        | 32 bytes
    _BlockMove                                  | copy app name
    RTS                                         | return from GetAppParms
INSTALLRDRIVERS:
    MOVEM.L     D0-D4/A0-A3,-(SP)               | save regs
    MOVEA.L     (UTableBase).W,A3               | unit table base
    MOVE.W      (UnitTableEntryCount).W,D3      | number of entries
    MOVEQ.L     #-0x1,D4                        | D4 = unit number (-1, -2, ...)
RDRVRINSTALL_LOOP_TOP:
    MOVE.L      (A3)+,D0                        | get DCE handle
    BEQ.B       RDRVRINSTALL_SKIP               | nil ->
    MOVEA.L     D0,A1                           | dereference handle
    MOVE.L      (A1),D0                         | DCE ptr
    BEQ.B       RDRVRINSTALL_SKIP               | nil ->
    MOVEA.L     D0,A1                           | A1 = DCE
    BTST        #0x6,0x5(A1)                    | dRAMBased flag?
    BEQ.B       RDRVRINSTALL_SKIP               | no, ROM driver ->
    MOVE.L      (A1),D0                         | dCtlDriver
    BEQ.B       RDRVRINSTALL_SKIP               | nil ->
    MOVE.L      0x14(A1),D1                     | dCtlDelay
    BSR.W       APPHEAP_TEST                    | in app heap?
    BNE.B       RDRVRINSTALL_NO                 | no, keep it ->
    MOVEQ.L     #0x31,D0                        | 50 bytes to clear
    MOVEA.L     A1,A0                           | DCE ptr
RDRVRINSTALL_LOOP:
    CLR.B       (A0)+                           | zero DCE
    DBF.W       D0,RDRVRINSTALL_LOOP            | clear 50 bytes
    BSET        #0x6,0x5(A1)                    | set dRAMBased flag
    MOVE.W      D4,0x18(A1)                     | dCtlRefNum = unit number
RDRVRINSTALL_NO:
    CLR.L       0x1E(A1)                        | clear dCtlCurTicks
    MOVE.L      D1,D0                           | dCtlDelay address
    BSR.W       APPHEAP_TEST                    | in app heap?
    BNE.B       RDRVRINSTALL_NO_2               | no ->
    MOVEQ.L     #0x0,D1                         | clear if in app heap
RDRVRINSTALL_NO_2:
    MOVE.L      D1,0x14(A1)                     | restore or clear dCtlDelay
RDRVRINSTALL_SKIP:
    SUBQ.W      #0x1,D4                         | next unit number
    SUBQ.W      #0x1,D3                         | decrement count
    BNE.B       RDRVRINSTALL_LOOP_TOP           | loop for all units
    MOVEM.L     (SP)+,D0-D4/A0-A3               | restore regs
    RTS                                         | return from RDrvrInstall
