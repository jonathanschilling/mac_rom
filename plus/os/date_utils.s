| Date conversion -- _Secs2Date / _Date2Secs
|
| Apple source: SexyDate.a (MacSEROM.lst module SEXYDATE). Convert between
| the clock's seconds since midnight, January 1, 1904 and a DateTimeRec
| (year, month, day, hour, minute, second, dayOfWeek). Register interface:
| Secs2Date takes D0 = seconds, A0 -> DateTimeRec; Date2Secs takes
| A0 -> DateTimeRec and returns D0 = seconds.
|
| References: Inside Macintosh Vol II, Ch 13: Operating System Utilities
| (II-379/380)

| ----------------------------------------------------------
|
| _Secs2Date ($A9C6) - Secs2Date
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
Secs2Date:
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
        RTS                                     | return from S2D_PAST_FEB

| ----------------------------------------------------------
|
| _Date2Secs ($A9C7) - Date2Secs
|
| Converts a DateTimeRec to seconds since midnight Jan 1 1904.
| Entry: A0 = pointer to 14-byte DateTimeRec
| Exit: D0.L = seconds since epoch
|
| Reads fields in reverse order (dtMinute/dtSecond first, then
| dtHour, dtDay, dtMonth, dtYear) using predecrement addressing.
|
Date2Secs:
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
        RTS                                     | return from D2S_IN_JAN_FEB
