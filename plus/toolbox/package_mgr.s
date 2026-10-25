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
|
| _InitPack ($A9E5)
|
| Loads a single PACK resource by ID and stores its handle
| in the AppPacks/App2Packs array.
| Pascal: PROCEDURE InitPack(packID: INTEGER);
|
InitPack:
        SUBQ.L  #0x4,SP                         | reserve space for GetResource result
        MOVE.L  #0x5041434B,-(SP)               | push resType 'PACK'
        MOVE    0xC(SP),-(SP)                   | push packID from original parameter
        MOVE    #-0x100,(ROMMapInsert).w        | search ROM resource map first
        _GetResource                            | get handle to PACK resource
        MOVE    0x8(SP),D0                      | retrieve packID
        BSR.B   MAP_PACK_SLOT                   | A0 = pointer to AppPacks[packID] slot
        MOVE.L  (SP)+,(A0)                      | store PACK handle in AppPacks slot
        MOVE.L  (SP)+,A0                        | pop return address
        ADDQ.L  #0x2,SP                         | pop packID parameter
        JMP     (A0)                            | return to caller

| ----------------------------------------------------------
|
| _InitAllPacks ($A9E6)
|
| Builds a stack frame that calls InitPack for each of the
| 16 packages (IDs 0-15). Pushes alternating packID/return-addr
| pairs so the RTS chain calls InitPack 16 times. Also
| initializes SANE floating-point state.
| Pascal: PROCEDURE InitAllPacks;
|
InitAllPacks:
        MOVE.L  (SP)+,A0                        | save original return address
        MOVEQ.L #0xF,D0                         | loop counter: packs 15 down to 0
INITALL_PUSH_LOOP:
        MOVE    D0,-(SP)                        | push packID parameter for InitPack
        MOVE.L  A0,-(SP)                        | push return address (original caller)
        LEA.L   InitPack(PC),A0                 | A0 = InitPack entry point
        DBF     D0,INITALL_PUSH_LOOP            | loop until all 16 packIDs pushed
        MOVE.L  A0,-(SP)                        | push final return to InitPack (pack 0)
        CLR     (FPState).w                     | clear SANE FP exception state
        LEA.L   SANE_HALT_HANDLER(PC),A0        | A0 = SANE halt vector (dsNoPk)
        MOVE.L  A0,(FPHaltVector).w             | set SANE halt vector to system error
        RTS                                     | chain into first InitPack call

| ----------------------------------------------------------
|
| SANE_HALT_HANDLER - SANE floating-point halt handler (dsNoPk)
|
| Default FP halt vector installed by InitAllPacks.
| Triggers system error dsNoPk ($10 = 16).
|
SANE_HALT_HANDLER:
        MOVEQ.L #0x10,D0                        | dsNoPk: "can't load package"
        _SysError                               | trigger system error
| ----------------------------------------------------------
|
| MAP_PACK_SLOT - Map pack number to AppPacks/App2Packs slot
|
| Entry: D0.W = pack number (0-15)
| Exit: A0 = pointer to handle slot in AppPacks or App2Packs
| D0.W modified (0-7 range within chosen array)
|
MAP_PACK_SLOT:
        LEA.L   (App2Packs).w,A0                | assume pack 8-15 (App2Packs array)
        SUBQ.W  #0x8,D0                         | subtract 8 to test range
        BGE.B   MAP_PACK_INDEXED                | if >= 8, use App2Packs
        LEA.L   (AppPacks).w,A0                 | pack 0-7: use AppPacks array
        ADDQ.W  #0x8,D0                         | restore D0 to original 0-7 range
MAP_PACK_INDEXED:
        LSL     #0x2,D0                         | D0 *= 4 (handle is 4 bytes)
        ADDA    D0,A0                           | A0 = &AppPacks[packNum]
        RTS                                     | return with A0 pointing to slot

| ----------------------------------------------------------
|
| PACK_DISPATCH - Pack load-and-jump dispatcher
|
| Called via the BSR table below. Uses return address to
| determine which pack was requested: distance from Pack1
| divided by 2 gives the pack number (each BSR is 2 bytes).
| If the pack handle is not yet loaded or dereferenced,
| loads it via _LoadResource, then jumps to the pack code.
|
PACK_DISPATCH:
        MOVEM.L D0/A0,-(SP)                     | save registers
        MOVE.L  0x8(SP),D0                      | D0 = return address (after BSR)
        LEA.L   Pack1(PC),A0                    | A0 = address of Pack1 entry
        SUB.L   A0,D0                           | byte offset from Pack1
        LSR     #0x1,D0                         | /2 = pack number (Pack0 = -1+1 = 0)
        BSR.B   MAP_PACK_SLOT                   | A0 = &AppPacks[packNum]
        TST.L   (A0)                            | is handle non-nil?
        BEQ.B   PACKDISP_FAIL                   | nil handle: fatal error
        MOVE.L  (A0),A0                         | dereference: A0 = master pointer
        TST.L   (A0)                            | is master pointer non-nil?
        BNE.B   PACKDISP_LOADED                 | already loaded: jump to pack code
        MOVE.L  A0,-(SP)                        | push handle for _LoadResource
        MOVE    #-0x1,(ROMMapInsert).w          | search ROM map first
        _LoadResource                           | load pack into memory
        TST.L   (A0)                            | did load succeed?
        BEQ.B   PACKDISP_FAIL                   | still nil: fatal error
PACKDISP_LOADED:
        MOVE.L  (A0),0x8(SP)                    | replace return addr with pack entry
        MOVEM.L (SP)+,D0/A0                     | restore registers
        CLR.B   (SP)                            | clear selector high byte on stack
        RTS                                     | jump to loaded pack code

| ----------------------------------------------------------
|
| PACKDISP_FAIL - Package load failure handler
|
| Computes system error ID = packNum + 17 (dsNoPk range)
| and calls _SysError. Error IDs 17-24 display
| "Can't load package" in the System Error Handler.
|
PACKDISP_FAIL:
        MOVE.L  0x8(SP),D0                      | get return address again
        LEA.L   Pack1(PC),A0                    | A0 = Pack1 entry point
        SUB.L   A0,D0                           | byte offset from Pack1
        LSR     #0x1,D0                         | /2 = pack number
        ADDI    #0x11,D0                        | +17 = system error ID
        _SysError                               | display "Can't load package N"
| ----------------------------------------------------------
|
| Pack dispatch BSR table
|
| Each BSR.B PACK_DISPATCH is exactly 2 bytes. PACK_DISPATCH uses the return
| address to compute which pack was called.
| Packs 0-7: standard Mac packages
| Packs 8-15: Color QuickDraw stubs (not present on Mac Plus,
| these dispatch entries exist for forward compatibility)
|
Pack0:                                          | PACK 0: List Manager
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
| Pack1 -- trap handler for _Pack1 ($A9E8).
Pack1:                                          | PACK 1: (reserved)
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
| Pack2 -- trap handler for _Pack2 ($A9E9).
Pack2:                                          | PACK 2: Disk Initialization Manager
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
| Pack3 -- trap handler for _Pack3 ($A9EA).
Pack3:                                          | PACK 3: Standard File Package
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack4:                                          | PACK 4: SANE Floating-Point Arithmetic
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack5:                                          | PACK 5: SANE Transcendental Functions
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
| Pack6 -- trap handler for _Pack6 ($A9ED).
Pack6:                                          | PACK 6: International Utilities
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack7:                                          | PACK 7: Binary-Decimal Conversion
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack8:                                          | CQD stub: Pack8
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack9:                                          | CQD stub: Pack9
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack10:                                         | CQD stub: Pack10
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack11:                                         | CQD stub: Pack11
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack12:                                         | CQD stub: Pack12
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack13:                                         | CQD stub: Pack13
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack14:                                         | CQD stub: Pack14
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack15:                                         | CQD stub: Pack15
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
