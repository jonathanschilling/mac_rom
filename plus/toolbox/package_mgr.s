| Package Manager
|
| Provides InitPack, InitAllPacks for loading PACK resources,
| and the Pack0-Pack7 dispatch table. Also includes date/time
| conversion routines (SecondsToDate, DateToSeconds) and
| miscellaneous Color QuickDraw stubs.
|
| PACK resources are loaded on demand via the dispatch table below.
| Each PackN trap (A-line) becomes a BSR to PACK_DISPATCH, which uses the
| return address to identify which pack was called (each BSR is
| 2 bytes apart starting at Pack0). The pack handle is looked up
| in the AppPacks array (packs 0-7) or App2Packs (packs 8-15).
|
| References:
| Inside Macintosh Vol I, pp I-481..I-484: Package Manager
| Inside Macintosh Vol II, pp II-377..II-379: Secs2Date/Date2Secs
|

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
DisplayDispatch:                                | PACK 4: SANE Floating-Point Arithmetic
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack5:                                          | PACK 5: SANE Transcendental Functions
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
| Pack6 -- trap handler for _Pack6 ($A9ED).
Pack6:                                          | PACK 6: International Utilities
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
Pack7:                                          | PACK 7: Binary-Decimal Conversion
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
SetCPixel:                                      | CQD stub: SetCPixel
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
GetNextDevice:                                  | CQD stub: GetNextDevice
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
TestDeviceAttribute:                            | CQD stub: TestDeviceAttribute
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
SetDeviceAttribute:                             | CQD stub: SetDeviceAttribute
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
InitGDevice:                                    | CQD stub: InitGDevice
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
NewGDevice:                                     | CQD stub: NewGDevice
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
DisposeGDevice:                                 | CQD stub: DisposeGDevice
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
SetGDevice:                                     | CQD stub: SetGDevice
        BSR.B   PACK_DISPATCH                   | branch to pack dispatch
| ----------------------------------------------------------
|
| _Secs2Date ($A9C6) - SecondsToDate
|
| Converts seconds since midnight Jan 1 1904 to a DateTimeRec.
| Entry: D0.L = seconds since epoch
| A0 = pointer to 14-byte DateTimeRec
| Exit: DateTimeRec filled with year/month/day/hour/min/sec/dayOfWeek
|
| The algorithm divides total seconds into days + remainder,
| then extracts year from 4-year (1461-day) cycles, month
| from a scaled approximation, and time from modular division.
|
SecondsToDate:
        MOVEM.L D0-D4/A0,-(SP)                  | save registers
        MOVEQ.L #0x0,D1                         | D1 will hold remainder of seconds
        LSR.L   #0x1,D0                         | divide D0 by 2 (shift high bit to X)
        ROXR.L  #0x1,D1                         | shift X bit into D1 high bit
        DIVU    #-0x5740,D0                     | D0 / 43200: split into half-days
        SWAP    D0                              | D0.W = remainder (half-seconds in day)
        MOVE    D0,D1                           | D1.W = half-seconds within current day
        ROL.L   #0x1,D1                         | *2 to recover full seconds in day
        CLR     D0                              | clear remainder half
        SWAP    D0                              | D0.W = number of half-days since epoch
| --- extract year ---
        MOVE.L  D0,D2                           | D2 = half-days count
        ASL.L   #0x2,D2                         | *4: scale for 4-year cycle division
        DIVU    #0x5B5,D2                       | /1461: D2.W = 4-year cycles since 1904
        ADDI    #0x770,D2                       | +1904: D2.W = absolute year
        MOVE    D2,(A0)+                        | store dtYear
| --- determine if leap year ---
        MOVEQ.L #0x3B,D3                        | D3 = 59 (Jan+Feb days in non-leap year)
        ANDI    #0x3,D2                         | year mod 4
        BNE.B   S2D_NOT_LEAP                    | not divisible by 4: not leap
        ADDQ.W  #0x1,D3                         | leap year: 60 days through Feb
S2D_NOT_LEAP:
| --- extract month and day ---
        CLR     D2                              | clear low word (keep remainder in high)
        SWAP    D2                              | D2.W = remainder days * 4 from DIVU
        LSR     #0x2,D2                         | /4: day within year (0-based)
        MOVEQ.L #0x1,D4                         | D4 = month offset (starts at January)
        CMP     D3,D2                           | past Jan+Feb boundary?
        BLT.B   S2D_PAST_FEB                    | no: still in Jan or Feb
        ADDQ.W  #0x2,D4                         | yes: skip Jan+Feb, month starts at March
        SUB     D3,D2                           | subtract Jan+Feb days from day count
S2D_PAST_FEB:
        LSL.L   #0x7,D2                         | *128: scale day count for month approx
        MOVEQ.L #0x47,D3                        | D3 = 71 (rounding bias)
        ADD.L   D3,D2                           | add bias for accurate month extraction
        DIVU    #0xF4F,D2                       | /3919: ~128*avg_days/month; D2.W = month
        ADD     D4,D2                           | add month offset (1 or 3)
        SWAP    D2                              | D2.W = scaled remainder
        LSR     #0x7,D2                         | /128: recover day within month
        ADDQ.W  #0x1,D2                         | +1: 1-based day
        MOVE.L  D2,(A0)+                        | store dtMonth (high) + dtDay (low)
| --- extract hour, minute, second ---
        DIVU    #0xE10,D1                       | D1 / 3600: D1.W = hours
        MOVE    D1,(A0)+                        | store dtHour
        CLR     D1                              | clear quotient, keep remainder in high
        SWAP    D1                              | D1.W = remaining seconds
        DIVU    #0x3C,D1                        | /60: D1.W = minutes, rem = seconds
        SWAP    D1                              | seconds in low, minutes in high
        MOVE.L  D1,(A0)+                        | store dtMinute (high) + dtSecond (low)
| --- extract day of week ---
        ADDQ.W  #0x5,D0                         | Jan 1 1904 was a Friday (day 6);
        DIVU    #0x7,D0                         | +5 aligns so remainder 0 = Sunday
        SWAP    D0                              | D0.W = day of week (0=Sun..6=Sat)
        ADDQ.W  #0x1,D0                         | +1: 1-based (1=Sun..7=Sat)
        MOVE    D0,(A0)                         | store dtDayOfWeek
        MOVEM.L (SP)+,D0-D4/A0                  | restore registers
        RTS                                     | return to caller

| ----------------------------------------------------------
|
| _Date2Secs ($A9C7) - DateToSeconds
|
| Converts a DateTimeRec to seconds since midnight Jan 1 1904.
| Entry: A0 = pointer to 14-byte DateTimeRec
| Exit: D0.L = seconds since epoch
|
| Reads fields in reverse order (dtMinute/dtSecond first, then
| dtHour, dtDay, dtMonth, dtYear) using predecrement addressing.
|
DateToSeconds:
        MOVEM.L D1-D4,-(SP)                     | save registers
        MOVEQ.L #0x0,D0                         | D0 accumulates total seconds
        ADDQ.L  #0x8,A0                         | A0 -> dtMinute field
| --- accumulate time-of-day seconds ---
        MOVE.L  (A0),D1                         | D1 = dtMinute:dtSecond (two words)
        MOVE    D1,D0                           | D0.W = dtSecond
        SWAP    D1                              | D1.W = dtMinute
        MOVE    -(A0),D2                        | D2.W = dtHour
        MOVEQ.L #0x3C,D3                        | D3 = 60
        MULU    D3,D2                           | D2 = hours * 60 = total minutes contrib
        ADD     D1,D2                           | D2 += dtMinute
        MULU    D3,D2                           | D2 = total minutes * 60 = seconds
        ADD.L   D2,D0                           | D0 = time-of-day in seconds
| --- accumulate day count ---
        MOVE    -(A0),D1                        | D1.W = dtDay
        SUBQ.W  #0x1,D1                         | make 0-based (day 1 = offset 0)
        MOVE    -(A0),D2                        | D2.W = dtMonth
        MOVE    -(A0),D3                        | D3.W = dtYear
        MOVE    D3,D4                           | D4 = year (saved for leap test)
        SUBI    #0x770,D3                       | D3 = years since 1904
        MULU    #0x5B5,D3                       | *1461: days per 4-year cycle
        ADDQ.L  #0x3,D3                         | +3 for rounding in integer division
        LSR.L   #0x2,D3                         | /4: total days from whole years
        ADD     D3,D1                           | D1 = day offset + year-days
| --- add month days ---
        SUBQ.W  #0x1,D2                         | make month 0-based
        CMPI    #0x1,D2                         | Jan or Feb? (month 0 or 1)
        BLE.B   D2S_IN_JAN_FEB                  | yes: skip leap-year Jan+Feb adjustment
        SUBQ.W  #0x2,D2                         | subtract 2: month relative to March
        MOVEQ.L #0x3B,D3                        | D3 = 59 (Jan+Feb in non-leap year)
        ANDI    #0x3,D4                         | test if leap year (year mod 4)
        BNE.B   D2S_NOT_LEAP                    | not leap: 59 days for Jan+Feb
        ADDQ.W  #0x1,D3                         | leap year: 60 days for Jan+Feb
D2S_NOT_LEAP:
        ADD     D3,D1                           | add Jan+Feb days to offset
D2S_IN_JAN_FEB:
        MULU    #0xF4D,D2                       | *3917: scaled month approximation
        ADDI    #0x34,D2                        | +52: rounding bias
        LSR     #0x7,D2                         | /128: days from completed months
        ADD     D2,D1                           | D1 = total day count since epoch
| --- convert days to seconds ---
        MULU    #-0x5740,D1                     | *43200: half-seconds per day (unsigned)
        ADD.L   D1,D1                           | *2: full seconds per day (86400)
        ADD.L   D1,D0                           | D0 = total seconds since epoch
        MOVEM.L (SP)+,D1-D4                     | restore registers
        RTS                                     | return to caller
