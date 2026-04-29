| Package Manager (classic 1984 -- date/time only)
|
| The classic 64 KB ROM does not implement the InitPack / Pack0..Pack7
| dispatch infrastructure that Plus has (the Package Manager A-traps
| $A9E5..$A9EF are all "unimplemented" stubs in 1984). The only code
| in this file is the date/time conversion pair (SecondsToDate /
| DateToSeconds) -- the rest of Plus's package_mgr.s (InitPack,
| INITALL_PUSH_LOOP, SANE_HALT_HANDLER, MAP_PACK_*, PACK_DISPATCH,
| Pack0..Pack7) has no classic counterpart and lives only in Plus.
|
| References:
| Inside Macintosh Vol II, pp II-377..II-379: Secs2Date/Date2Secs
| ----------------------------------------------------------

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
        MOVE.L  8(SP),D0                        | D0 = caller's return addr
        LEA     Pack1(PC),A0                    | A0 = pack 1 BSR slot addr
        SUB.L   A0,D0                           | D0 = byte offset from Pack1
        ADD     D0,D0                           | *2 = AppPacks long index
        LEA.L     (AppPacks).w,A0               | A0 = AppPacks base
        ADDA.L  D0,A0                           | A0 = AppPacks[packID]
        TST.L   (A0)                            | pack handle present?
        BEQ.B   PACKDISP_FAIL                   | no: SysError
        MOVE.L  (A0),A0                         | D2 = half-days count
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
        BSR.B   PACK_DISPATCH                   | dispatch PACK 2
        BSR.B   PACK_DISPATCH                   | dispatch PACK 3
        BSR.B   PACK_DISPATCH                   | dispatch PACK 4 (FP68K)
        BSR.B   PACK_DISPATCH                   | dispatch PACK 5 (Elems68K)
        BSR.B   PACK_DISPATCH                   | dispatch PACK 6 (Intl)
        BSR.B   PACK_DISPATCH                   | dispatch PACK 7 (DecStr68K)

| _Secs2Date ($A9C6) - SecondsToDate
| Converts seconds since midnight Jan 1 1904 to a DateTimeRec.
| Entry: D0.L = seconds since epoch
| A0 = pointer to 14-byte DateTimeRec
| Exit: DateTimeRec filled with year/month/day/hour/min/sec/dayOfWeek
| The algorithm divides total seconds into days + remainder,
| then extracts year from 4-year (1461-day) cycles, month
| from a scaled approximation, and time from modular division.
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
        RTS                                     | return from SecondsToDate (DateTimeRec filled)
        MOVEM.L D1-D4,-(SP)                     | save registers
        MOVEQ.L #0x0,D0                         | D0 accumulates total seconds
        ADDQ.L  #0x8,A0                         | A0 -> dtMinute field
        MOVE.L  (A0),D1                         | D1 = dtMinute:dtSecond (two words)
        MOVE    D1,D0                           | D0.W = dtSecond
        SWAP    D1                              | D1.W = dtMinute
        MOVE    -(A0),D2                        | D2.W = dtHour
        MOVEQ.L #0x3C,D3                        | D3 = 60 (seconds-per-minute multiplier)
        MULU    D3,D2                           | D2 = hour*60 (minutes-from-hours)
        ADD     D1,D2                           | D2 = hour*60 + minute (total minutes)
        MULU    D3,D2                           | D2 = total-minutes*60 (seconds in time-of-day)
        ADD.L   D2,D0                           | D0 = time-of-day in seconds
        MOVE    -(A0),D1                        | D1.W = dtDay
        SUBQ.W  #0x1,D1                         | make 0-based (day 1 = offset 0)
        MOVE    -(A0),D2                        | D2.W = dtMonth
        MOVE    -(A0),D3                        | D3.W = dtYear
        MOVE    D3,D4                           | D4 = year (saved for leap test)
        SUBI    #0x770,D3                       | D3 = years since 1904
        MULU    #0x5B5,D3                       | D3 = D3 *u #0x5B5
        ADDQ.L  #0x3,D3                         | +3 for rounding in integer division
        LSR.L   #0x2,D3                         | /4: total days from whole years
        ADD     D3,D1                           | D1 = day offset + year-days
        SUBQ.W  #0x1,D2                         | make month 0-based
        CMPI    #0x1,D2                         | Jan or Feb? (month 0 or 1)
        BLE.B   S2D_IN_JAN_FEB                  | yes: skip leap-year Jan+Feb adjustment
        SUBQ.W  #0x2,D2                         | subtract 2: month relative to March
        MOVEQ.L #0x3B,D3                        | D3 = 59 (Jan+Feb in non-leap year)
        ANDI    #0x3,D4                         | test if leap year (year mod 4)
        BNE.B   S2D_PAST_FEB_NO                 | not leap: 59 days for Jan+Feb
        ADDQ.W  #0x1,D3                         | leap year: 60 days for Jan+Feb
S2D_PAST_FEB_NO:
        ADD.W    D3,D1                          | add Jan+Feb days (59 or 60) to day count
S2D_IN_JAN_FEB:
        MULU    #0xF4D,D2                       | *3917: scaled month approximation
        ADDI    #0x34,D2                        | +52: rounding bias
        LSR     #0x7,D2                         | /128: days from completed months
        ADD     D2,D1                           | D1 = total day count since epoch
| --- convert days to seconds ---
        MULU    #-0x5740,D1                     | *43200: half-seconds per day (unsigned)
        ADD.L   D1,D1                           | *2: full seconds per day (86400)
        ADD.L   D1,D0                           | D0 = total seconds since epoch
        MOVEM.L (SP)+,D1-D4                     | restore registers
        RTS                                     | return from DateToSeconds (D0 = seconds since epoch)

| ----------------------------------------------------------
| Date-to-seconds tail: bytes at $FFF8..$FFFB are actually a brief
| micro-helper used by the packer (ADDQ.W #1,A0 / SUBQ.B #1,-(A0)).
        ADDQ.W  #0x1,A0                         | advance A0 by 1
        SUBQ.B  #0x1,-(A0)                      | decrement the byte at -(A0)

| ----------------------------------------------------------
| $FFFC..$FFFF -- "WDA " ASCII marker. Identical in 128K and 512K
| ROMs, and carried forward in the Mac Plus ROM too. The "WDA"
| prefix historically stood for "Window Definition Area" or similar
| (Apple never documented this four-byte tag officially).
        .ascii "WDA "                           | 4-char ROM-end marker
