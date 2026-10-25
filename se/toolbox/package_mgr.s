| Package Manager -- _InitPack, _InitAllPacks, _Pack0 ... _Pack15
|
| Apple source: PackageMgr.a (MacSEROM.lst module PACKDISPATCHER).
| InitPack loads one PACK resource and stores its handle in AppPacks
| (packs 0-7) or App2Packs (8-15); InitAllPacks loads them all. Each
| _PackN trap enters a BSR.B chain (Pack0 ... Pack15, 2 bytes apart) into
| PACK_DISPATCH, which takes the pack number from the return address,
| loads the pack if needed and jumps into it.
|
| References: Inside Macintosh Vol I, Ch 17 (The Package Manager);
| Inside Macintosh Vol IV (packs 8-15).

| ----------------------------------------------------------
| _InitPack ($A9EB) / INITPACK - install one Package by ID.
| Pascal: procedure InitPack(packID: INTEGER);
| Caller pushes packID then calls InitPack. Looks up 'PACK'
| resource, sets ROMMapInsert=$FF00 (mark in resource map),
| stores handle into AppPacks/App2Packs[packID] slot.
| ----------------------------------------------------------
| Apple source module: PACKDISPATCHER
INITPACK:
    SUBQ.L	#0x4,A7                              | room for handle result
    MOVE.L	#0x5041434B,-(A7)                    | push 'PACK' type
    MOVE.W	0xC(A7),-(A7)                        | push packID (caller's stack)
    MOVE.W	#0xFF00,(ROMMapInsert).W             | mark insert pos in ROM map
    _GetResource                                | get PACK resource
    MOVE.W	0x8(A7),D0                           | D0 = packID
    BSR.B	MAP_PACK_SLOT                         | A0 = AppPacks[D0] slot
    MOVE.L	(A7)+,(A0)                           | store handle in slot
    MOVEA.L	(A7)+,A0                            | A0 = caller's return addr
    ADDQ.L	#0x2,A7                              | strip packID param
    JMP	(A0)                                    | tail-call return from INITPACK via A0
| ----------------------------------------------------------
| _InitAllPacks ($A9E6) - install all 16 Packages.
| Pascal: procedure InitAllPacks;
| Pushes 16 packIDs (15..0) onto stack, each followed by the
| InitPack address, so the chain runs InitPack
| 16 times. Then clears FPState and installs default SANE
| halt handler in FPHaltVector.
| ----------------------------------------------------------
INITALLPACKS:
    MOVEA.L	(A7)+,A0                            | A0 = return address
    MOVEQ.L	#0xF,D0                             | start with packID 15
INITALL_PUSH_LOOP:
    MOVE.W	D0,-(A7)                             | push packID
    MOVE.L	A0,-(A7)                             | push return addr
    LEA.L	INITPACK(PC),A0                       | A0 = InitPack glue
    DBF.W	D0,INITALL_PUSH_LOOP                  | loop for all 16 packs
    MOVE.L	A0,-(A7)                             | push final InitPack ptr
    CLR.W	(FPState).W                           | FPState = 0 (no FP halt)
    LEA.L	SANE_HALT_HANDLER(PC),A0              | A0 = default halt handler
    MOVE.L	A0,(FPHaltVector).W                  | install FPHaltVector
    RTS                                         | start chain of InitPack calls
| ----------------------------------------------------------
|
| SANE_HALT_HANDLER - SANE floating-point halt handler (dsNoPk)
|
| Default FP halt vector installed by InitAllPacks.
| Triggers system error dsNoPk ($10 = 16).
|
SANE_HALT_HANDLER:
    MOVEQ.L	#0x10,D0                            | dsNoPk: "can't load package"
    _SysError                                   | trigger system error
| ----------------------------------------------------------
|
| MAP_PACK_SLOT - Map pack number to AppPacks/App2Packs slot
|
| Entry: D0.W = pack number (0-15)
| Exit: A0 = pointer to handle slot in AppPacks or App2Packs
| D0.W modified (0-7 range within chosen array)
|
MAP_PACK_SLOT:
    LEA.L	(App2Packs).W,A0                      | assume pack 8-15 (App2Packs array)
    SUBQ.W	#0x8,D0                              | subtract 8 to test range
    BGE.B	MAP_PACK_INDEXED                      | if >= 8, use App2Packs
    LEA.L	(AppPacks).W,A0                       | pack 0-7: use AppPacks array
    ADDQ.W	#0x8,D0                              | restore D0 to original 0-7 range
MAP_PACK_INDEXED:
    LSL.W	#0x2,D0                               | byte offset = idx * 4
    ADDA.W	D0,A0                                | A0 = AppPacks[idx]
    RTS                                         | return from MAP_PACK_INDEXED
| ----------------------------------------------------------
| PACK_DISPATCH - PACK trap dispatcher.
| Dispatch entry called from PACK0..PACK15 trap stubs.
| Computes pack ID from PC offset (each PACK# is BSR to here),
| loads the pack resource if not already in memory, then jumps
| to the pack's entry point with the original return addr in
| place to chain back to the caller.
| Called by: PACK0, PACK1, PACK2, PACK3, PACK4 (and 11 more)
| ----------------------------------------------------------
PACK_DISPATCH:
    MOVEM.L	D0/A0,-(A7)                         | save D0/A0
    MOVE.L	0x8(A7),D0                           | D0 = caller's BSR return addr
    LEA.L	PACK1(PC),A0                          | A0 = PACK1 (reference point)
    SUB.L	A0,D0                                 | D0 = bytes from PACK1 to caller
    LSR.W	#0x1,D0                               | D0 = pack index (0..15)
    BSR.B	MAP_PACK_SLOT                         | A0 = AppPacks[index]
    TST.L	(A0)                                  | pack handle installed?
    BEQ.B	PACKDISP_FAIL                         | no -> SysError
    MOVEA.L	(A0),A0                             | A0 = pack handle
    TST.L	(A0)                                  | pack loaded into memory?
    BNE.B	PACKDISP_LOADED                       | yes -> use it
    MOVE.L	A0,-(A7)                             | save handle
    MOVE.W	#0xFFFF,(ROMMapInsert).W             | scan all res files
    _LoadResource                               | reload pack into memory
    TST.L	(A0)                                  | now in memory?
    BEQ.B	PACKDISP_FAIL                         | no -> SysError
PACKDISP_LOADED:
    MOVE.L	(A0),D0                              | D0 = pack data ptr
    _StripAddress                               | strip 24->32 bit (68000 compat)
    MOVE.L	D0,0x8(A7)                           | replace caller's return = pack
    MOVEM.L	(A7)+,D0/A0                         | restore D0/A0
    RTS                                         | "return" enters pack code
| ----------------------------------------------------------
|
| PACKDISP_FAIL - Package load failure handler
|
| Computes system error ID = packNum + 17 (dsNoPk range)
| and calls _SysError. Error IDs 17-24 display
| "Can't load package" in the System Error Handler.
|
PACKDISP_FAIL:
    MOVE.L	0x8(A7),D0                           | D0 = caller addr (PACK#)
    LEA.L	PACK1(PC),A0                          | A0 = PACK1 base
    SUB.L	A0,D0                                 | D0 = bytes from PACK1
    LSR.W	#0x1,D0                               | D0 = pack number
    ADDI.W	#0x11,D0                             | + 17 = dsNoPk error ID
    _SysError                                   | trigger system error
PACK0:
    BSR.B	PACK_DISPATCH                         | dispatch PACK0 ($A9E7)
PACK1:
    BSR.B	PACK_DISPATCH                         | dispatch PACK1 ($A9E8)
PACK2:
    BSR.B	PACK_DISPATCH                         | dispatch PACK2 ($A9E9, Disk Init)
PACK3:
    BSR.B	PACK_DISPATCH                         | dispatch PACK3 ($A9EA, SF dialog)
PACK4:
    BSR.B	PACK_DISPATCH                         | dispatch PACK4 ($A9EB, FP arith)
PACK5:
    BSR.B	PACK_DISPATCH                         | dispatch PACK5 ($A9EC, Elems)
PACK6:
    BSR.B	PACK_DISPATCH                         | dispatch PACK6 ($A9ED, intl utils)
PACK7:
    BSR.B	PACK_DISPATCH                         | dispatch PACK7 ($A9EE, B2D conv)
PACK8:
    BSR.B	PACK_DISPATCH                         | dispatch PACK8 ($A816)
PACK9:
    BSR.B	PACK_DISPATCH                         | dispatch PACK9 ($A82B)
PACK10:
    BSR.B	PACK_DISPATCH                         | dispatch PACK10 ($A82C)
PACK11:
    BSR.B	PACK_DISPATCH                         | dispatch PACK11 ($A82D)
PACK12:
    BSR.B	PACK_DISPATCH                         | dispatch PACK12 ($A82E)
PACK13:
    BSR.B	PACK_DISPATCH                         | dispatch PACK13 ($A82F)
PACK14:
    BSR.B	PACK_DISPATCH                         | dispatch PACK14 ($A830)
PACK15:
    BSR.B	PACK_DISPATCH                         | dispatch PACK15 ($A831)
