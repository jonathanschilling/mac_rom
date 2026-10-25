| Package Manager (1984): InitPack, InitAllPacks and the Pack0..Pack7 trap
| entries with their common dispatcher.
|
| Apple source: PackageMgr.a (MacSEROM.lst module PACKDISPATCHER).
| Pack0..Pack7 ($A9E7..$A9EE) are consecutive 2-byte BSR.B PACK_DISPATCH
| instructions. PACK_DISPATCH derives the package number from the return
| address, takes the handle from AppPacks[n] (LoadResource if purged) and
| replaces the return address by the package code address, so its RTS
| enters the package with the caller's stack and registers. A missing
| package is fatal (SysError 17+n). InitPack fills AppPacks[n].
| Secs2Date and Date2Secs follow in os/date_utils.s.
|
| References:
| Inside Macintosh Vol I, Ch 17: The Package Manager

| ----------------------------------------------------------
|
| _InitPack ($A9E5): make a package available
| Pascal: PROCEDURE InitPack(packID: INTEGER);
| With ResLoad off, AppPacks[packID] := GetResource('PACK', packID).
|
InitPack:
        CLR     -(SP)                           | push resLoad = FALSE
        _SetResLoad                             | disable auto-resource-loading
        SUBQ.L  #0x4,SP                         | space for GetResource result
        MOVE.L  #0x5041434B,-(SP)               | push 32-bit immediate 'PACK'
        MOVE    12(SP),-(SP)                    | push pack ID param
        _GetResource                            | get PACK resource
        MOVE    8(SP),D0                        | D0 = pack ID
        LSL     #0x2,D0                         | multiply by 4 = AppPacks slot
        LEA.L     (AppPacks).w,A1               | A1 = AppPacks table base
        MOVE.L  (SP)+,0(A1,D0.W)                | AppPacks[id] = handle
        MOVE.B  #0x1,-(SP)                      | push resLoad = TRUE
        _SetResLoad                             | re-enable auto-resource-loading
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.L  #0x2,SP                         | strip 2-byte param
        JMP     (A0)                            | RTS
| ----------------------------------------------------------
|
| _InitAllPacks ($A9E6): initialize the standard packages
| Pascal: PROCEDURE InitAllPacks;
| InitPack(4), (5), (6) and (7) (floating point, transcendental functions,
| International Utilities, binary-decimal conversion), then FPState := 0
| and FPHaltVector := SANE_HALT_HANDLER (SysError 16).
|
InitAllPacks:
        MOVE    #0x4,-(SP)                      | push pack 4 (FP68K)
        BSR.B   InitPack                        | install PACK 4
        MOVE    #0x5,-(SP)                      | push pack 5 (Elems68K)
        BSR.B   InitPack                        | install PACK 5
        MOVE    #0x6,-(SP)                      | push pack 6 (Intl)
        BSR.B   InitPack                        | install PACK 6
        MOVE    #0x7,-(SP)                      | push pack 7 (DecStr68K)
        BSR.B   InitPack                        | install PACK 7
        CLR     (FPState).w                     | clear FP state
        LEA     SANE_HALT_HANDLER(PC),A0        | A0 = SANE halt handler
        MOVE.L  A0,(FPHaltVector).w             | install FP halt vector
        RTS                                     | return from InitAllPacks
SANE_HALT_HANDLER:
        MOVEQ.L #0x10,D0                        | D0 = SysError code 16
        _SysError                               | invoke SysError (FP halt)
PACK_DISPATCH:
        MOVEM.L D0/A0,-(SP)                     | save D0/A0
        MOVE.L  8(SP),D0                        | D0 = return addr of the BSR in PackN
        LEA     Pack1(PC),A0                    | A0 = pack 1 BSR slot addr
        SUB.L   A0,D0                           | D0 = 2*n (n = package number)
        ADD     D0,D0                           | D0 = 4*n = AppPacks offset
        LEA.L     (AppPacks).w,A0               | A0 = AppPacks base
        ADDA.L  D0,A0                           | A0 = AppPacks[packID]
        TST.L   (A0)                            | pack handle present?
        BEQ.B   PACKDISP_FAIL                   | no: SysError
        MOVE.L  (A0),A0                         | A0 = package handle
        TST.L   (A0)                            | pack code loaded?
        BNE.B   PACKDISP_LOADED                 | yes: jump to it
        MOVE.L  A0,-(SP)                        | push handle for LoadResource
        _LoadResource                           | reload pack code
PACKDISP_LOADED:
        MOVE.L  (A0),8(SP)                      | overwrite return = pack code
        MOVEM.L (SP)+,D0/A0                     | restore D0/A0
        RTS                                     | jump to pack dispatch entry
PACKDISP_FAIL:
        LSR     #0x2,D0                         | D0 /= 4 = pack number
        ADDI    #0x11,D0                        | D0 += 0x11 = SysError code
        _SysError                               | fatal: pack not installed
| ----------------------------------------------------------
| Pack dispatch BSR table -- each BSR.B is 2 bytes; PACK_DISPATCH
| uses the return address to compute which pack was called.
Pack0:                                          | PACK 0: List Manager
        BSR.B   PACK_DISPATCH                   | dispatch PACK 0
Pack1:
        BSR.B   PACK_DISPATCH                   | dispatch PACK 1
| _Pack2 ($A9E9): package 2 (Disk Initialization)
Pack2:
        BSR.B   PACK_DISPATCH                   | dispatch PACK 2
| _Pack3 ($A9EA): package 3 (Standard File)
Pack3:
        BSR.B   PACK_DISPATCH                   | dispatch PACK 3
| _FP68K = _Pack4 ($A9EB): package 4 (floating-point arithmetic)
Pack4:
        BSR.B   PACK_DISPATCH                   | dispatch PACK 4 (FP68K)
| _Elems68K = _Pack5 ($A9EC): package 5 (transcendental functions)
Pack5:
        BSR.B   PACK_DISPATCH                   | dispatch PACK 5 (Elems68K)
| _Pack6 ($A9ED): package 6 (International Utilities)
Pack6:
        BSR.B   PACK_DISPATCH                   | dispatch PACK 6 (Intl)
| _DECSTR68K = _Pack7 ($A9EE): package 7 (binary-decimal conversion)
Pack7:
        BSR.B   PACK_DISPATCH                   | dispatch PACK 7 (DecStr68K)

