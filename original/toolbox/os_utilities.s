| OS Utilities
|
| Small collection of OS helper traps that are assembled adjacent to
| the Segment Loader in ROM. Called from the Segment Loader's launch
| path and from client applications via A-line traps.
|
| Routines:
| GetAppParms - _GetAppParms: return app name + ref num + parm handle.
| RDrvrInstall - load and install ROM-based DRVRs for a given range
| of driver numbers (used for .AIn/.AOut/.BIn/.BOut).
| ReadParam / WriteParam / ReadDateTime / SetDateTime
| - Utility / Parameter Manager traps for PRAM + RTC.
| Delay - _Delay trap: busy-wait D0 ticks using Ticks counter.
| CmpString / RelString / UpperString / CONVERSION_TBL / STRIP_TBL
| - Pascal-string compare / upper-case conversion.
|
| References: Inside Macintosh Vol II, Ch 7 (Operating System Utilities).

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
| _RDrvrInstall ($A04F)
| _RDrvrInstall: reinitialize desk accessory DCEs for new application
| Clears DCEs whose drivers lived in the app heap (now destroyed)
| Called during boot.
RDrvrInstall:
        MOVEM.L D0-D4/A0-A3,-(SP)               | save regs
        MOVE.L  (UTableBase).w,A3               | A3 = unit table
        MOVE    (UnitTableEntryCount).w,D3      | D3 = unit count
        MOVEQ.L #-0x1,D4                        | D4 = starting refNum (-1)
RDRVRINSTALL_CONT:
        MOVE.L  (A3)+,D0                        | D0 = unit table entry (DCE handle)
        BEQ.B   RDRVRINSTALL_SKIP               | empty slot -> next
        MOVE.L  D0,A1                           | A1 = DCE handle
        MOVE.L  (A1),A1                         | dereference to DCE
        BTST    #0x6,5(A1)                      | dRAMBased flag set?
        BEQ.B   RDRVRINSTALL_SKIP               | ROM driver -> leave alone
        MOVE.L  (A1),D0                         | D0 = driver entry pointer
        BEQ.B   RDRVRINSTALL_SKIP               | zero -> next
        CMP.L   (ApplZone).w,D0                 | driver code in app heap?
        BLT.B   RDRVRINSTALL_NO                 | system zone -> handle storage only
        MOVEQ.L #0x27,D0                        | loop count: 40 bytes (full DCE)
        MOVE.L  A1,A0                           | A0 = DCE start (zero target)
RDRVRINSTALL_LOOP:
        CLR.B   (A0)+                           | zero one byte
        DBF     D0,RDRVRINSTALL_LOOP            | loop 40 times
        BSET    #0x6,0x5(A1)                    | restore dRAMBased flag
        MOVE    D4,dCtlRefNum(A1)               | set dCtlRefNum = current refNum
RDRVRINSTALL_SKIP:
        SUBQ.W  #0x1,D4                         | next refNum (more negative)
        SUBQ.W  #0x1,D3                         | decrement unit count
        BNE.B   RDRVRINSTALL_CONT               | more units -> loop
        MOVEM.L (SP)+,D0-D4/A0-A3               | restore regs
        RTS                                     | return from RDrvrInstall
RDRVRINSTALL_NO:
        CLR.L   dCtlWindow(A1)                  | clear dCtlWindow
        MOVE.L  dCtlStorage(A1),D0              | D0 = dCtlStorage address
        CMP.L   (ApplZone).w,D0                 | storage in app zone?
        BLT.B   RDRVRINSTALL_SKIP               | not app zone: leave as-is
        CLR.L   dCtlStorage(A1)                 | in app zone: clear to let _DrvrInstall re-alloc
        BRA.B   RDRVRINSTALL_SKIP               | done with this DCE -> next unit

| ----------------------------------------------------------
| _ReadParam ($A037): read PRAM into low-memory SysParam block
ReadParam:
        LEA.L     (SysParam_SPValid).w,A1       | A1 = dest (SysParam area)
        BSR.B   READPARAM_CONT                  | read 20 bytes from RTC PRAM
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from _ReadParam
| READPARAM_CONT: copy selected bytes from A1 to A0 based on D0 bitmask.
| Iterates 20 bytes; if corresponding bit in D0 is set, copies byte.
READPARAM_CONT:
        MOVEQ.L #0x13,D2                        | loop count: 20 bytes (PRAM size minus 1)
READPARAM_LOOP:
        LSR.L   #0x1,D0                         | shift out next bit
        BCC.B   READPARAM_SKIP                  | bit clear -> skip this byte
        MOVE.B  (A1),(A0)+                      | copy byte from source to dest
READPARAM_SKIP:
        ADDQ.L  #0x1,A1                         | advance source pointer
        DBRA    D2,READPARAM_LOOP               | next byte
        RTS                                     | return from READPARAM_CONT

| ----------------------------------------------------------
| _WriteParam ($A038): write SysParam block to RTC PRAM (selective).
| Caller passes bitmask in D0; only bytes with set bit are written.
| Then verify by reading back and comparing.
WriteParam:
        LEA.L     (SysParam_SPValid).w,A1       | A1 = source (SysParam area)
        EXG     A0,A1                           | A0 := SysParam, A1 := caller buffer
        BSR.B   READPARAM_CONT                  | selectively copy bytes per bitmask
        BSR.W   WPOFF_CONT                      | write SysParam to RTC PRAM
        LEA.L     (Scratch20).w,A1              | temp buffer for readback
        BSR.W   ReadPRAM                        | read PRAM into temp
        LEA.L     (SysParam_SPValid).w,A0       | A0 = original SysParam
        MOVEQ.L #-0x57,D0                       | assume prWrErr (-87)
        MOVEQ.L #0x4,D2                         | 5 longwords = 20 bytes
WRITEPARAM_LOOP:
        CMPM.L  (A0)+,(A1)+                     | compare written vs read-back
        BNE.B   WRITEPARAM_ERR                  | mismatch -> return prWrErr
        DBRA    D2,WRITEPARAM_LOOP              | loop 5 longwords
        MOVEQ.L #0x0,D0                         | noErr (verified)
WRITEPARAM_ERR:
        RTS                                     | return from _WriteParam

| ----------------------------------------------------------
| _ReadDateTime ($A039): read date/time from RTC into Time global,
| then return it via A0.
ReadDateTime:
        BSR.W   INITUTIL_CONT                   | read 4-byte time from RTC chip
        MOVE.L  (Time).w,(A0)                   | copy Time to caller's buffer
        RTS                                     | return from _ReadDateTime

| ----------------------------------------------------------
| _SetDateTime ($A03A): set date/time in RTC.
| Caller passes new time in D0.
SetDateTime:
        MOVE.L  D0,(Time).w                     | store new time in global
        BRA.W   INITUTIL_CONT_2                 | -> write to RTC chip

| ----------------------------------------------------------
| _Delay ($A03B): delay for specified number of ticks (1/60 sec)
| A0 = tick count to delay
Delay:
        MOVE    #0x2000,SR                      | enable interrupts (so ticks advance)
        MOVE.L  (Ticks).w,D0                    | D0 = start tick count
        ADD.L   A0,D0                           | D0 = target tick count
DELAY_LOOP:
        CMP.L   (Ticks).w,D0                    | check current tick count against target
        BGT.B   DELAY_LOOP                      | loop until current ticks >= target
        RTS                                     | return from Delay

| ----------------------------------------------------------
| CmpString -- _CmpString trap implementation. Compares two Pascal
| strings byte-by-byte using a character-translation helper for
| diacritic/case stripping. Returns Z=1 if equal.
| Stack on entry: D0 (high:low) packs the two byte counts.
CmpString:
        MOVE.L   D3,-(SP)                       | save D3 (compare uses scratch byte)
        MOVE    D0,D2                           | D2 = length2 (low word of D0)
        SWAP    D0                              | D0.lo = length1
UPPERSTRING_XLATE_BASE:                         | PC-rel base for char-translate tbl
        CMP     D0,D2                           | same length?
        BNE.B   CMPSTRING_NEQ                   | length mismatch -> not equal
        MOVEQ.L #0x0,D2                         | D2.b = 0 (clear before MOVE.B)
        BRA.B   CMPSTRING_NEXT                  | enter loop tail (DBRA test)
CMPSTRING_LOOP:
        MOVE.B  (A1)+,D2                        | D2 = next char from string 2
        BSR.B   STRING_XLATE                    | fold to upper/strip diacritics
        MOVE.B  D2,D3                           | D3 = folded char from string 2
        MOVE.B  (A0)+,D2                        | D2 = next char from string 1
        BSR.B   STRING_XLATE                    | fold to upper/strip diacritics
        CMP.B   D2,D3                           | same folded character?
        BNE.B   CMPSTRING_NEQ                   | differ -> not equal
CMPSTRING_NEXT:
        DBRA    D0,CMPSTRING_LOOP               | next byte (D0 = length-1 counter)
        MOVEQ.L #0x0,D0                         | return 0 (equal)
        BRA.B   CMPSTRING_EXIT                  | -> restore D3 and return
CMPSTRING_NEQ:
        MOVEQ.L #0x1,D0                         | return 1 (not equal)
CMPSTRING_EXIT:
        MOVE.L  (SP)+,D3                        | restore D3
        RTS                                     | return from _CmpString
STRING_XLATE:
        BTST    #0x9,D1                         | diacSens flag set?
        BEQ.B   STRING_XLATE_LOWER              | diacSens=0 -> skip diacritic strip
        CMPI.B  #0x80,D2                        | below high-ASCII?
        BCS.B   STRING_XLATE_LOWER              | ASCII -> no diacritic mapping
        CMPI.B  #0xCD,D2                        | above accented-letter range?
        BHI.B   STRING_XLATE_LOWER              | branch if > (unsigned)
        MOVE.B  UPPERSTRING_XLATE_BASE(PC,D2.W),D2 | D2 = xlate byte at PC+D2-0x38
STRING_XLATE_LOWER:
        BTST    #0xA,D1                         | caseSens flag set?
        BNE.B   STRING_XLATE_DONE               | caseSens=1 -> keep case as-is
        CMPI.B  #0x61,D2                        | below 'a'?
        BCS.B   STRING_XLATE_DONE               | yes -> already upper or non-letter
        CMPI.B  #0x9F,D2                        | above lowercase 'z'+accents range?
        BHI.B   STRING_XLATE_AC                 | yes -> check next range
        MOVE.B  STRING_XLATE_DONE+1(PC,D2.W),D2 | D2 = 2nd xlate byte (offset into code tbl)
        BRA.B   STRING_XLATE_DONE               | done -> return uppercase
STRING_XLATE_AC:
        CMPI.B  #0xBE,D2                        | below ligature range?
        BCS.B   STRING_XLATE_DONE               | yes -> done
        CMPI.B  #0xBF,D2                        | in AE/OE ligature range?
        BHI.B   STRING_XLATE_AE                 | branch if > (unsigned)
        SUBI.B  #0x10,D2                        | fold ae/oe -> AE/OE
        BRA.B   STRING_XLATE_DONE               | done -> return uppercase ligature
STRING_XLATE_AE:
        CMPI.B  #0xCF,D2                        | specifically lowercase oe?
        BNE.B   STRING_XLATE_DONE               | no -> done
        SUBQ.B  #0x1,D2                         | fold oe -> OE
STRING_XLATE_DONE:
        RTS                                     | return folded char in D2

| ----------------------------------------------------------
| UpperString -- _UpperString ($A054). Plus os_utilities.s 389.
| Convert Pascal string to uppercase in place.
UpperString:
        MOVEQ.L #0x0,D2                         | start at offset 0
        BRA.B   UPPERSTRING_LOOP_2              | enter loop tail
UPPERSTRING_LOOP:
        MOVE.B  (A0),D2                         | D2 = character
        BSR.B   STRING_XLATE                    | apply case/diacritic folding
        MOVE.B  D2,(A0)+                        | write folded character back
UPPERSTRING_LOOP_2:
        DBRA    D0,UPPERSTRING_LOOP             | loop over all characters
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        RTS                                     | return from _UpperString

| ----------------------------------------------------------
| UPPERSTRING_TBL -- 142-byte character-conversion table used by
| UpperString's inner routine to map lower-case and accented lower-case
| characters to their upper-case equivalents. Indexed by the input
| character (byte value); the looked-up byte is the replacement. Covers
| ASCII lower-case 'a'..'z' plus Mac Roman accented lower-case letters
| ($8B..$9E) that map to their base upper-case forms.
| Layout follows the MacRoman character tables (Inside Macintosh Vol I
| Appendix K). Previous disassembly rendered this as pseudo-instructions
| (BSR.B, MULU, etc.) because many of the bytes coincidentally form
| legal 68000 opcodes when interpreted as code.
UPPERSTRING_TBL:
        .byte   0x41,0x41,0x43,0x45,0x4E,0x4F,0x55,0x61 | $4E94: "AACENOUa"
        .byte   0x61,0x61,0x61,0x61,0x61,0x63,0x65,0x65 | $4E9C: "aaaaacee"
        .byte   0x65,0x65,0x69,0x69,0x69,0x69,0x6E,0x6F | $4EA4: "eeiiiino"
        .byte   0x6F,0x6F,0x6F,0x6F,0x75,0x75,0x75,0x75 | $4EAC: "oooouuuu"
        .byte   0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7 | $4EB4: high ASCII passthrough
        .byte   0xA8,0xA9,0xAA,0xAB,0xAC,0xAD,0xAE,0x4F | $4EBC: ..., 'O' (AE->O?)
        .byte   0xB0,0xB1,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7 | $4EC4: high ASCII passthrough
        .byte   0xB8,0xB9,0xBA,0x61,0x6F,0xBD,0xBE,0x6F | $4ECC: ..., 'a', 'o', ..., 'o'
        .byte   0xC0,0xC1,0xC2,0xC3,0xC4,0xC5,0xC6,0xC7 | $4ED4: high ASCII passthrough
        .byte   0xC8,0xC9,0xCA,0x41,0x41,0x4F,0x41,0x42 | $4EDC: ..., 'A', 'A', 'O', 'A', 'B'
        .byte   0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A | $4EE4: "CDEFGHIJ" passthrough
        .byte   0x4B,0x4C,0x4D,0x4E,0x4F,0x50,0x51,0x52 | $4EEC: "KLMNOPQR" passthrough
        .byte   0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A | $4EF4: "STUVWXYZ" passthrough
        .byte   0x7B,0x7C,0x7D,0x7E,0x7F,0x80,0x81,0x82 | $4EFC: "{|}~...."
        .byte   0x83,0x84,0x85,0x86,0x87,0xCB,0x89,0x80 | $4F04: ...0xCB is 'E' mapping
        .byte   0xCC,0x81,0x82,0x83,0x8F,0x90,0x91,0x92 | $4F0C: 'I', ...
        .byte   0x93,0x94,0x95,0x84,0x97,0x98,0x99,0x85 | $4F14: ...
        .byte   0xCD,0x9C,0x9D,0x9E,0x86,0x00   | $4F1C: 'I', ..., null terminator

