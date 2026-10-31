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
| _Secs2Date ($A9C6) / SECS2DATE - convert seconds since 1904
| to date components (year, month, day, hour, minute, second,
| dayOfWeek).
| In: D0 = seconds since 1904-01-01, A0 = DateTimeRec ptr.
| Out: A0+0 = year, +2 = month, +4 = day, +6 = hour,
|      +8 = minute, +10 = second, +12 = dayOfWeek.
| Constants: $A8C0 = seconds/day, $5B5 = days*4/year (avg),
|            $770 = 1904, $F4F = 4015 (mday-of-year mult).
| ----------------------------------------------------------
PACKMGREND:                                     | MacSEROM.lst: end marker of the module before
SEXYDATE:                                       | Apple source module (MacSEROM.lst)
SECS2DATE:
    MOVEM.L     D0-D4/A0,-(A7)                  | save scratch
    MOVEQ.L     #0x0,D1                         | clear D1
    LSR.L       #0x1,D0                         | D0 = seconds / 2
    ROXR.L      #0x1,D1                         | D1 = bit shifted out
    DIVU.W      #0xA8C0,D0                      | D0 = days, rem = secs in day*2
    SWAP.W      D0                              | swap so D0=secs*2-rem, hi=days
    MOVE.W      D0,D1                           | D1 = secs*2 of day
    ROL.L       #0x1,D1                         | D1 = secs of day (undo shift)
    CLR.W       D0                              | (D0 = days only)
    SWAP.W      D0                              | D0 = total days since 1904
    MOVE.L      D0,D2                           | D2 = days
    ASL.L       #0x2,D2                         | D2 = days * 4
    DIVU.W      #0x5B5,D2                       | D2 = years, rem = day-of-year
    ADDI.W      #0x770,D2                       | year = years + 1904
    MOVE.W      D2,(A0)+                        | store year
    MOVEQ.L     #0x3B,D3                        | D3 = 59 (Feb day-count adj)
    ANDI.W      #0x3,D2                         | leap year (year mod 4 == 0)?
    BNE.B       S2D_NOT_LEAP                    | no -> 59
    ADDQ.W      #0x1,D3                         | yes -> 60
S2D_NOT_LEAP:
    CLR.W       D2                              | clear D2 low
    SWAP.W      D2                              | D2 = day-of-year remainder
    LSR.W       #0x2,D2                         | D2 = day-of-year * 4 / 4 = doy
    MOVEQ.L     #0x1,D4                         | D4 = 1 (month adj for Jan/Feb)
    CMP.W       D3,D2                           | doy past Feb 28/29?
    BLT.B       S2D_PAST_FEB                    | no -> month adj 1
    ADDQ.W      #0x2,D4                         | yes -> month adj 3
    SUB.W       D3,D2                           | doy -= 59/60 (rebase Mar=0)
S2D_PAST_FEB:
    LSL.L       #0x7,D2                         | D2 = doy * 128
    MOVEQ.L     #0x47,D3                        | D3 = 71 (rounding adj)
    ADD.L       D3,D2                           | D2 = doy*128 + 71
    DIVU.W      #0xF4F,D2                       | D2 = month, rem = doy-of-month
    ADD.W       D4,D2                           | + month adj (1 or 3)
    SWAP.W      D2                              | swap to get rem
    LSR.W       #0x7,D2                         | D2 = doy-of-month
    ADDQ.W      #0x1,D2                         | + 1 (1-based day)
    MOVE.L      D2,(A0)+                        | store month, day
    DIVU.W      #0xE10,D1                       | D1 = hour, rem = secs of hour
    MOVE.W      D1,(A0)+                        | store hour
    CLR.W       D1                              | clear low D1
    SWAP.W      D1                              | D1 = secs of hour
    DIVU.W      #0x3C,D1                        | D1 = min, rem = secs
    SWAP.W      D1                              | swap to put min in low word
    MOVE.L      D1,(A0)+                        | store minute, second
    ADDQ.W      #0x5,D0                         | day-of-week: +5 (1904 = Fri)
    DIVU.W      #0x7,D0                         | mod 7
    SWAP.W      D0                              | get remainder
    ADDQ.W      #0x1,D0                         | + 1 (1=Sun..7=Sat)
    MOVE.W      D0,(A0)                         | store dayOfWeek
    MOVEM.L     (A7)+,D0-D4/A0                  | restore scratch
    RTS                                         | return from SECS2DATE
| ----------------------------------------------------------
| _Date2Secs ($A9C7) - convert date components to seconds.
| Pascal: procedure Date2Secs(d: DateTimeRec; var secs: LongInt);
| In: A0 = DateTimeRec ptr (year/month/day/hour/min/sec).
| Out: D0 = seconds since 1904-01-01.
| Inverse of _Secs2Date.
| ----------------------------------------------------------
DATE2SECS:
    MOVEM.L     D1-D4,-(A7)                     | save scratch
    MOVEQ.L     #0x0,D0                         | clear D0
    ADDQ.L      #0x8,A0                         | A0 -> minute field
    MOVE.L      (A0),D1                         | D1 = minute:second
    MOVE.W      D1,D0                           | D0 = second
    SWAP.W      D1                              | D1 = minute
    MOVE.W      -(A0),D2                        | D2 = hour
    MOVEQ.L     #0x3C,D3                        | D3 = 60
    MULU.W      D3,D2                           | hour * 60
    ADD.W       D1,D2                           | + minute
    MULU.W      D3,D2                           | * 60 = total seconds
    ADD.L       D2,D0                           | D0 += seconds
    MOVE.W      -(A0),D1                        | D1 = day
    SUBQ.W      #0x1,D1                         | day - 1 (0-based)
    MOVE.W      -(A0),D2                        | D2 = month
    MOVE.W      -(A0),D3                        | D3 = year
    MOVE.W      D3,D4                           | D4 = year (for leap test)
    SUBI.W      #0x770,D3                       | D3 = year - 1904
    MULU.W      #0x5B5,D3                       | * 1461 (days*4/4yrs)
    ADDQ.L      #0x3,D3                         | + 3 (rounding)
    LSR.L       #0x2,D3                         | / 4 = days since 1904
    ADD.W       D3,D1                           | + day
    SUBQ.W      #0x1,D2                         | month - 1 (0-based)
    CMPI.W      #0x1,D2                         | Jan or Feb (0,1)?
    BLE.B       D2S_IN_JAN_FEB                  | yes -> no leap adj
    SUBQ.W      #0x2,D2                         | rebase: Mar = 0
    MOVEQ.L     #0x3B,D3                        | D3 = 59
    ANDI.W      #0x3,D4                         | leap?
    BNE.B       D2S_NOT_LEAP                    | no
    ADDQ.W      #0x1,D3                         | yes -> 60
D2S_NOT_LEAP:
    ADD.W       D3,D1                           | + 59/60 (Jan+Feb days)
D2S_IN_JAN_FEB:
    MULU.W      #0xF4D,D2                       | month * 3917
    ADDI.W      #0x34,D2                        | + 52 (rounding)
    LSR.W       #0x7,D2                         | / 128
    ADD.W       D2,D1                           | + cumulative days for month
    MULU.W      #0xA8C0,D1                      | days * 43200 (= secs/2/day)
    ADD.L       D1,D1                           | * 2 = secs/day
    ADD.L       D1,D0                           | total secs
    MOVEM.L     (A7)+,D1-D4                     | restore scratch
    RTS                                         | return from DATE2SECS
