| OS Utilities
|
| Small collection of OS helper traps that are assembled adjacent to
| the Segment Loader in ROM. Called from the Segment Loader's launch
| path and from client applications via A-line traps.
|
| Routines:
| SegStack - _Launch continuation: allocate aboveA5/belowA5
| space, copy jump table from CODE 0, _SetApplLimit.
| ExitToShell - _ExitToShell trap: release app heap, re-launch
| Finder (or the _UnloadSeg loop into Chain).
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
        MOVE    (BootDrive).w,fLeading(A0)      | set ioVRefNum to boot volume
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

| ----------------------------------------------------------
|
| Read Param
|
| _ReadParam: read PRAM into low-memory SysParam block
ReadParam:
        LEA.L   (SysParam_SPValid).w,A1         | A1 = dest (SysParam area)
        BSR.B   READPARAM_CONT                  | read 20 bytes from RTC PRAM
        MOVEQ.L #0x0,D0                         | noErr
        RTS                                     | return from ReadParam

| ----------------------------------------------------------
|
| READPARAM_CONT
|
| READPARAM_CONT: copy selected bytes from A1 to A0 based on D0 bitmask
| Iterates 20 bytes; if corresponding bit in D0 is set, copies byte
READPARAM_CONT:
        MOVEQ.L #0x13,D2                        | 20 bytes to scan
READPARAM_LOOP:
        LSR.L   #0x1,D0                         | shift out next bit
        BCC.B   READPARAM_SKIP                  | bit clear -> skip this byte
        MOVE.B  (A1),(A0)+                      | copy byte from source to dest
READPARAM_SKIP:
        ADDQ.L  #0x1,A1                         | advance source pointer
        DBF     D2,READPARAM_LOOP               | next byte
        RTS                                     | return from READPARAM_CONT

| ----------------------------------------------------------
|
| _WriteParam ($A038)
|
| _WriteParam ($A038): write SysParam block to RTC PRAM
| Writes the 20-byte parameter block, then verifies by reading back
WriteParam:
        BSR     WPOFF_CONT                      | write SysParam to RTC PRAM
| verify: read back and compare
        LEA.L   (Scratch20).w,A1                | temp buffer for readback
        BSR     ReadPRAM                        | read PRAM into temp
        LEA.L   (SysParam_SPValid).w,A0         | A0 = original SysParam
        MOVEQ.L #-0x57,D0                       | assume prWrErr (-87)
        MOVEQ.L #0x4,D2                         | 5 longwords = 20 bytes
WRITEPARAM_LOOP:
        CMPM.L  (A0)+,(A1)+                     | compare written vs read
        BNE.B   WRITEPARAM_ERR                  | mismatch -> error
        DBF     D2,WRITEPARAM_LOOP              | loop 5 longwords
        MOVEQ.L #0x0,D0                         | noErr (verified)
WRITEPARAM_ERR:
        RTS                                     | return from WriteParam

| ----------------------------------------------------------
|
| _ReadDateTime ($A039)
|
| _ReadDateTime ($A039): read date/time from RTC into Time global
ReadDateTime:
        BSR     INITUTIL_CONT                   | read 4-byte time from RTC chip
        MOVE.L  (Time).w,(A0)                   | copy Time to caller's buffer
        RTS                                     | return from ReadDateTime

| ----------------------------------------------------------
|
| _SetDateTime ($A03A)
|
| _SetDateTime ($A03A): set date/time in RTC
SetDateTime:
        MOVE.L  D0,(Time).w                     | store new time in global
        BRA     INITUTIL_CONT_2                 | -> write to RTC chip

| ----------------------------------------------------------
|
| _Delay ($A03B): delay for specified number of ticks (1/60 sec)
| A0 = tick count to delay
|
Delay:
        MOVE    #0x2000,SR                      | enable interrupts (so ticks advance)
        MOVE.L  (Ticks).w,D0                    | D0 = start tick count
        ADD.L   A0,D0                           | D0 = target tick count
DELAY_LOOP:
        CMP.L   (Ticks).w,D0                    | check current tick count against target
        BGT.B   DELAY_LOOP                      | loop until current ticks >= target
        RTS                                     | return from Delay

| ----------------------------------------------------------
|
| _CmpString ($A03C)
|
| _CmpString ($A03C): compare two strings (case-insensitive)
| D0.hi = length1, D0.lo = length2, A0 = str1, A1 = str2
| Returns D0 = 0 if equal, nonzero if different
CmpString:
        MOVE    D0,D2                           | D2 = length2
        SWAP    D0                              | D0.lo = length1
        CMP     D0,D2                           | same length?
        BNE.B   CMPSTRING                       | no, can't be equal ->
        SWAP    D0                              | restore D0
        BSR.B   RelString                       | compare chars
        BPL.B   CMPSTRING_CONT                  | str1 >= str2 ->
        NEG.L   D0                              | make positive (not equal)
CMPSTRING_CONT:
        RTS                                     | return from CmpString

| ----------------------------------------------------------
|
| CMPSTRING
|
| CmpString: lengths differ -> not equal
CMPSTRING:
        MOVEQ.L #0x1,D0                         | not equal (length mismatch)
        RTS                                     | return nonzero (strings differ)

| ----------------------------------------------------------
|
| _RelString ($A050): compare two strings, returning ordering
| D0.hi=len1, D0.lo=len2, A0=str1, A1=str2, D1=case/marks flags
| Returns: D0<0 if str1<str2, D0=0 if equal, D0>0 if str1>str2
|
RelString:
        BSR.B   RELSTRING_CONT_4                | set up comparison tables
        MOVEQ.L #0x0,D4                         | D4 = 0 (no secondary ordering)
        MOVE    D0,D2                           | D2 = length of string 2
        SWAP    D0                              | D0 = length of string 1
        CMP     D0,D2                           | compare lengths
        BEQ.B   RELSTRING_LOOP_2                | equal lengths ->
        BHI.B   RELSTRING_OK                    | string 2 is longer -> D4 = -1
        MOVEQ.L #0x1,D4                         | string 1 is longer -> D4 = 1
        MOVE    D2,D0                           | loop count = shorter string length
        CMP     D4,D4                           | set Z flag (so DBNE will fall through)
        BRA.B   RELSTRING_LOOP_2                | start loop

| ----------------------------------------------------------
|
| RELSTRING_OK
|
| Called during boot.
RELSTRING_OK:
        MOVEQ.L #-0x1,D4                        | string 2 is longer -> D4 = -1
        CMP     D4,D4                           | set Z flag
        BRA.B   RELSTRING_LOOP_2                | start loop

| ----------------------------------------------------------
|
| RELSTRING_LOOP
|
| Called during boot.
RELSTRING_LOOP:
        MOVEQ.L #0x0,D2                         | clear upper bits
        MOVE.B  (A0)+,D2                        | D2 = character from string 1
        BSR.B   RELSTRING_CONT                  | apply diacritic folding
        ADD     D2,D2                           | word offset
        MOVE    0x0(A3,D2.W),D3                 | D3 = weight of char 1
        MOVEQ.L #0x0,D2                         | clear upper bits
        MOVE.B  (A1)+,D2                        | D2 = character from string 2
        BSR.B   RELSTRING_CONT                  | apply diacritic folding
        ADD     D2,D2                           | word offset
        CMP     0x0(A3,D2.W),D3                 | compare char 1 weight with char 2 weight
RELSTRING_LOOP_2:
        DBNE    D0,RELSTRING_LOOP               | loop while equal and not at end
        BEQ.B   RELSTRING_EXIT_2                | strings equal -> return length diff
        BHI.B   RELSTRING_EXIT                  | string 1 > string 2 -> return 1
        MOVEQ.L #-0x1,D0                        | string 1 < string 2 -> return -1
        BRA.B   RELSTRING_EXIT_3                | exit

| ----------------------------------------------------------
|
| RELSTRING_EXIT
|
| Called during boot.
RELSTRING_EXIT:
        MOVEQ.L #0x1,D4                         | return 1
RELSTRING_EXIT_2:
        MOVE.L  D4,D0                           | return result in D0
RELSTRING_EXIT_3:
        BRA.B   RELSTRING_EXIT_4                | -> exit

| ----------------------------------------------------------
|
| RELSTRING_CONT
|
| Called during boot.
RELSTRING_CONT:
        TST     D1                              | check diacSens flag (bit 15)
        BPL.B   RELSTRING_CONT_2                | diacSens=true -> keep diacritics
        MOVE.B  UPPERSTRING_CONT(PC,D2.W),D2    | diacSens=false -> strip diacritics
RELSTRING_CONT_2:
        TST.B   D1                              | check caseSens flag (bit 7)
        BMI.B   RELSTRING_CONT_3                | caseSens=true -> keep case
        MOVE.B  0x0(A2,D2.W),D2                 | caseSens=false -> fold to lowercase
RELSTRING_CONT_3:
        RTS                                     | return from RELSTRING_CONT

| ----------------------------------------------------------
|
| RELSTRING_CONT_4
|
| RELSTRING_CONT_4: set up character comparison tables for string operations
| D1 encodes case/marks sensitivity flags
| A2 = uppercase table (CONVERSION_TBL), A3 = diacritical stripping table (STRIP_TBL)
RELSTRING_CONT_4:
        MOVE.L  (SP)+,D2                        | save return address
        MOVEM.L D2-D4/A2-A3,-(SP)               | save regs
        LEA.L   CONVERSION_TBL(PC),A2           | A2 = uppercase conversion table
        LEA.L   STRIP_TBL(PC),A3                | A3 = diacritical strip table
        ROL     #0x6,D1                         | extract sensitivity flags
        ROR.B   #0x1,D1                         | position flags for testing
        MOVEQ.L #0x0,D2                         | clear comparison result
        RTS                                     | return from RELSTRING_CONT_4 (tables ready)

| ----------------------------------------------------------
|
| RELSTRING_EXIT_4
|
| RelString/CmpString exit: restore regs
RELSTRING_EXIT_4:
        MOVEM.L (SP)+,D3-D4/A2-A3               | restore regs
        RTS                                     | return from RelString/CmpString

| ----------------------------------------------------------
|
| _UpperString ($A054): convert string to uppercase in place
| D0 = string length, A0 = string ptr, D1 = case/marks flags
|
UpperString:
        BSR.B   RELSTRING_CONT_4                | set up conversion tables
        BRA.B   UPPERSTRING_LOOP_2              | -> convert loop

| ----------------------------------------------------------
|
| UPPERSTRING_LOOP
|
UPPERSTRING_LOOP:
        MOVE.B  (A0),D2                         | D2 = character
        BSR.B   RELSTRING_CONT                  | apply case/diacritic folding
        MOVE.B  D2,(A0)+                        | write folded character back
UPPERSTRING_LOOP_2:
        DBF     D0,UPPERSTRING_LOOP             | loop over all characters
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        BRA.B   RELSTRING_EXIT_4                | -> exit

| ----------------------------------------------------------
|
| UPPERSTRING_CONT
|
UPPERSTRING_CONT:
  .byte 0x00,0x01,0x02,0x03,0x04,0x05           | $00-$05: identity (control chars)
  .byte 0x06,0x07,0x08,0x09,0x0A,0x0B           | $06-$0B: identity
  .byte 0x0C,0x0D,0x0E,0x0F,0x10,0x11           | $0C-$11: identity
  .byte 0x12,0x13,0x14,0x15,0x16,0x17           | $12-$17: identity
  .byte 0x18,0x19,0x1A,0x1B,0x1C,0x1D           | $18-$1D: identity
  .byte 0x1E,0x1F,0x20,0x21,0x22,0x23           | $1E-$23: identity (space, punct)
  .byte 0x24,0x25,0x26,0x27,0x28,0x29           | $24-$29: identity
  .byte 0x2A,0x2B,0x2C,0x2D,0x2E,0x2F           | $2A-$2F: identity
  .byte 0x30,0x31,0x32,0x33,0x34,0x35           | $30-$35: digits 0-5
  .byte 0x36,0x37,0x38,0x39,0x3A,0x3B           | $36-$3B: digits 6-9, colon, semicolon
  .byte 0x3C,0x3D,0x3E,0x3F,0x40,0x41           | $3C-$41: punctuation, 'A'
  .byte 0x42,0x43,0x44,0x45,0x46,0x47           | $42-$47: 'B'-'G'
  .byte 0x48,0x49,0x4A,0x4B,0x4C,0x4D           | $48-$4D: 'H'-'M'
  .byte 0x4E,0x4F,0x50,0x51,0x52,0x53           | $4E-$53: 'N'-'S'
  .byte 0x54,0x55,0x56,0x57,0x58,0x59           | $54-$59: 'T'-'Y'
  .byte 0x5A,0x5B,0x5C,0x5D,0x5E,0x5F           | $5A-$5F: 'Z', brackets, etc.
  .byte 0x60,0x61,0x62,0x63,0x64,0x65           | $60-$65: backtick, 'a'-'e'
  .byte 0x66,0x67,0x68,0x69,0x6A,0x6B           | $66-$6B: 'f'-'k'
  .byte 0x6C,0x6D,0x6E,0x6F,0x70,0x71           | $6C-$71: 'l'-'q'
  .byte 0x72,0x73,0x74,0x75,0x76,0x77           | $72-$77: 'r'-'w'
  .byte 0x78,0x79,0x7A,0x7B,0x7C,0x7D           | $78-$7D: 'x'-'z', braces, pipe
  .byte 0x7E,0x7F,0x41,0x41,0x43,0x45           | $7E-$83: tilde,DEL; A-dier,A-ring->A,C-ced->C,E-acu->E
  .byte 0x4E,0x4F,0x55,0x61,0x61,0x61           | $84-$89: N-til->N,O-dier->O,U-dier->U,a-acu->a,a-grv->a,a-cir->a
  .byte 0x61,0x61,0x61,0x63,0x65,0x65           | $8A-$8F: a-dier->a,a-til->a,a-ring->a,c-ced->c,e-acu->e,e-grv->e
  .byte 0x65,0x65,0x69,0x69,0x69,0x69           | $90-$95: e-cir->e,e-dier->e,i-acu->i,i-grv->i,i-cir->i,i-dier->i
  .byte 0x6E,0x6F,0x6F,0x6F,0x6F,0x6F           | $96-$9B: n-til->n,o-acu->o,o-grv->o,o-cir->o,o-dier->o,o-til->o
  .byte 0x75,0x75,0x75,0x75,0xA0,0xA1           | $9C-$A1: u-acu->u,u-grv->u,u-cir->u,u-dier->u; dagger,degree
  .byte 0xA2,0xA3,0xA4,0xA5,0xA6,0xA7           | $A2-$A7: cent,pound,section,bullet,para,germandbls
  .byte 0xA8,0xA9,0xAA,0xAB,0xAC,0xAD           | $A8-$AD: registered,copyright,TM,acute,dieresis,notequal
  .byte 0xAE,0x4F,0xB0,0xB1,0xB2,0xB3           | $AE-$B3: AE->AE,O-slash->O; infinity,plusminus,leq,geq
  .byte 0xB4,0xB5,0xB6,0xB7,0xB8,0xB9           | $B4-$B9: yen,mu,delta,sigma,Pi,pi
  .byte 0xBA,0x61,0x6F,0xBD,0xBE,0x6F           | $BA-$BF: integral,a-ord->a,o-ord->o; Omega,ae->ae,o-slash->o
  .byte 0xC0,0xC1,0xC2,0xC3,0xC4,0xC5           | $C0-$C5: invquest,invexcl,not,radical,florin,approx
  .byte 0xC6,0xC7,0xC8,0xC9,0xCA,0x41           | $C6-$CB: Delta,guillemet-l,guillemet-r,ellipsis,nbsp,A-grv->A
  .byte 0x41,0x4F,0xCE,0xCF,0xD0,0xD1           | $CC-$D1: A-til->A,O-til->O; OE,oe,endash,emdash
  .byte 0xD2,0xD3,0xD4,0xD5,0xD6,0xD7           | $D2-$D7: ldquote,rdquote,lsquote,rsquote,divide,diamond
  .byte 0x79,0xD9,0xDA,0xDB,0xDC,0xDD           | $D8-$DD: y-dier->y; Ydieresis; fraction,currency,lsaquo,rsaquo
  .byte 0xDE,0xDF,0xE0,0xE1,0xE2,0xE3           | $DE-$E3: fi,fl,dagger2,middot,sbquote,dblsbquote
  .byte 0xE4,0xE5,0xE6,0xE7,0xE8,0xE9           | $E4-$E9: perthousand,A-cir,E-cir,A-acu,E-dier,E-grv
  .byte 0xEA,0xEB,0xEC,0xED,0xEE,0xEF           | $EA-$EF: I-acu,I-cir,I-dier,I-grv,O-acu,O-cir
  .byte 0xF0,0xF1,0xF2,0xF3,0xF4,0xF5           | $F0-$F5: apple,O-grv,U-acu,U-cir,U-grv,dotlessi
  .byte 0xF6,0xF7,0xF8,0xF9,0xFA,0xFB           | $F6-$FB: circumflex,tilde,macron,breve,dotaccent,ring
  .byte 0xFC,0xFD,0xFE,0xFF                     | $FC-$FF: cedilla,hungarumlaut,ogonek,caron

CONVERSION_TBL:
  .byte 0x00,0x01,0x02,0x03,0x04,0x05           | $00-$05: identity (control chars)
  .byte 0x06,0x07,0x08,0x09,0x0A,0x0B           | $06-$0B: identity
  .byte 0x0C,0x0D,0x0E,0x0F,0x10,0x11           | $0C-$11: identity
  .byte 0x12,0x13,0x14,0x15,0x16,0x17           | $12-$17: identity
  .byte 0x18,0x19,0x1A,0x1B,0x1C,0x1D           | $18-$1D: identity
  .byte 0x1E,0x1F,0x20,0x21,0x22,0x23           | $1E-$23: identity (space, punct)
  .byte 0x24,0x25,0x26,0x27,0x28,0x29           | $24-$29: identity
  .byte 0x2A,0x2B,0x2C,0x2D,0x2E,0x2F           | $2A-$2F: identity
  .byte 0x30,0x31,0x32,0x33,0x34,0x35           | $30-$35: digits (identity)
  .byte 0x36,0x37,0x38,0x39,0x3A,0x3B           | $36-$3B: digits, punct (identity)
  .byte 0x3C,0x3D,0x3E,0x3F,0x40,0x41           | $3C-$41: punct, 'A' (identity)
  .byte 0x42,0x43,0x44,0x45,0x46,0x47           | $42-$47: 'B'-'G' (identity)
  .byte 0x48,0x49,0x4A,0x4B,0x4C,0x4D           | $48-$4D: 'H'-'M' (identity)
  .byte 0x4E,0x4F,0x50,0x51,0x52,0x53           | $4E-$53: 'N'-'S' (identity)
  .byte 0x54,0x55,0x56,0x57,0x58,0x59           | $54-$59: 'T'-'Y' (identity)
  .byte 0x5A,0x5B,0x5C,0x5D,0x5E,0x5F           | $5A-$5F: 'Z', punct (identity)
  .byte 0x61,0x41,0x42,0x43,0x44,0x45           | $60-$65: backtick->a; a->A,b->B,c->C,d->D,e->E
  .byte 0x46,0x47,0x48,0x49,0x4A,0x4B           | $66-$6B: f->F,g->G,h->H,i->I,j->J,k->K
  .byte 0x4C,0x4D,0x4E,0x4F,0x50,0x51           | $6C-$71: l->L,m->M,n->N,o->O,p->P,q->Q
  .byte 0x52,0x53,0x54,0x55,0x56,0x57           | $72-$77: r->R,s->S,t->T,u->U,v->V,w->W
  .byte 0x58,0x59,0x5A,0x7B,0x7C,0x7D           | $78-$7D: x->X,y->Y,z->Z; braces, pipe
  .byte 0x7E,0x7F,0x80,0x81,0x82,0x83           | $7E-$83: tilde,DEL; Mac hi-ASCII uppercase
  .byte 0x84,0x85,0x86,0x87,0xCB,0x89           | $84-$89: a-grv->$CB (A-grv)
  .byte 0x80,0xCC,0x81,0x82,0x83,0x8F           | $8A-$8F: a-dier->$80,a-til->$CC,etc.
  .byte 0x90,0x91,0x92,0x93,0x94,0x95           | $90-$95: e-cir,e-dier,i-acu,i-grv,i-cir,i-dier
  .byte 0x84,0x97,0x98,0x99,0x85,0xCD           | $96-$9B: n-til->$84,o-acu,o-grv,o-cir,o-dier->$CD
  .byte 0x9C,0x9D,0x9E,0x86,0xA0,0xA1           | $9C-$A1: u-acu,u-grv,u-cir,u-dier->$86;symbols
  .byte 0xA2,0xA3,0xA4,0xA5,0xA6,0xA7           | $A2-$A7: symbols (identity)
  .byte 0xA8,0xA9,0xAA,0xAB,0xAC,0xAD           | $A8-$AD: symbols (identity)
  .byte 0xAE,0xAF,0xB0,0xB1,0xB2,0xB3           | $AE-$B3: symbols (identity)
  .byte 0xB4,0xB5,0xB6,0xB7,0xB8,0xB9           | $B4-$B9: symbols (identity)
  .byte 0xBA,0xBB,0xBC,0xBD,0xAE,0xAF           | $BA-$BF: ae->AE ($AE),oe->OE ($AF)
  .byte 0xC0,0xC1,0xC2,0xC3,0xC4,0xC5           | $C0-$C5: symbols (identity)
  .byte 0xC6,0xC7,0xC8,0xC9,0xCA,0xCB           | $C6-$CB: symbols (identity)
  .byte 0xCC,0xCD,0xCE,0xCE,0xD0,0xD1           | $CC-$D1: OE/oe uppercased; symbols
  .byte 0xD2,0xD3,0xD4,0xD5,0xD6,0xD7           | $D2-$D7: quotes, symbols (identity)
  .byte 0xD8,0xD9,0xDA,0xDB,0xDC,0xDD           | $D8-$DD: symbols (identity)
  .byte 0xDE,0xDF,0xE0,0xE1,0xE2,0xE3           | $DE-$E3: symbols (identity)
  .byte 0xE4,0xE5,0xE6,0xE7,0xE8,0xE9           | $E4-$E9: symbols (identity)
  .byte 0xEA,0xEB,0xEC,0xED,0xEE,0xEF           | $EA-$EF: symbols (identity)
  .byte 0xF0,0xF1,0xF2,0xF3,0xF4,0xF5           | $F0-$F5: symbols (identity)
  .byte 0xF6,0xF7,0xF8,0xF9,0xFA,0xFB           | $F6-$FB: symbols (identity)
  .byte 0xFC,0xFD,0xFE,0xFF                     | $FC-$FF: symbols (identity)

STRIP_TBL:
  .byte 0x00,0x00,0x01,0x00,0x02,0x00
  .byte 0x03,0x00,0x04,0x00,0x05,0x00
  .byte 0x06,0x00,0x07,0x00,0x08,0x00
  .byte 0x09,0x00,0x0A,0x00,0x0B,0x00
  .byte 0x0C,0x00,0x0D,0x00,0x0E,0x00
  .byte 0x0F,0x00,0x10,0x00,0x11,0x00
  .byte 0x12,0x00,0x13,0x00,0x14,0x00
  .byte 0x15,0x00,0x16,0x00,0x17,0x00
  .byte 0x18,0x00,0x19,0x00,0x1A,0x00
  .byte 0x1B,0x00,0x1C,0x00,0x1D,0x00
  .byte 0x1E,0x00,0x1F,0x00,0x20,0x00
  .byte 0x21,0x00,0x22,0x00,0x23,0x00
  .byte 0x24,0x00,0x25,0x00,0x26,0x00
  .byte 0x27,0x00,0x28,0x00,0x29,0x00
  .byte 0x2A,0x00,0x2B,0x00,0x2C,0x00
  .byte 0x2D,0x00,0x2E,0x00,0x2F,0x00
  .byte 0x30,0x00,0x31,0x00,0x32,0x00
  .byte 0x33,0x00,0x34,0x00,0x35,0x00
  .byte 0x36,0x00,0x37,0x00,0x38,0x00
  .byte 0x39,0x00,0x3A,0x00,0x3B,0x00
  .byte 0x3C,0x00,0x3D,0x00,0x3E,0x00
  .byte 0x3F,0x00,0x40,0x00,0x41,0x00
  .byte 0x42,0x00,0x43,0x00,0x44,0x00
  .byte 0x45,0x00,0x46,0x00,0x47,0x00
  .byte 0x48,0x00,0x49,0x00,0x4A,0x00
  .byte 0x4B,0x00,0x4C,0x00,0x4D,0x00
  .byte 0x4E,0x00,0x4F,0x00,0x50,0x00
  .byte 0x51,0x00,0x52,0x00,0x53,0x00
  .byte 0x54,0x00,0x55,0x00,0x56,0x00
  .byte 0x57,0x00,0x58,0x00,0x59,0x00
  .byte 0x5A,0x00,0x5B,0x00,0x5C,0x00
  .byte 0x5D,0x00,0x5E,0x00,0x5F,0x00
  .byte 0x61,0x00,0x41,0x80,0x42,0x80
  .byte 0x43,0x80,0x44,0x80,0x45,0x80
  .byte 0x46,0x80,0x47,0x80,0x48,0x80
  .byte 0x49,0x80,0x4A,0x80,0x4B,0x80
  .byte 0x4C,0x80,0x4D,0x80,0x4E,0x80
  .byte 0x4F,0x80,0x50,0x80,0x51,0x80
  .byte 0x52,0x80,0x53,0x80,0x54,0x80
  .byte 0x55,0x80,0x56,0x80,0x57,0x80
  .byte 0x58,0x80,0x59,0x80,0x5A,0x80
  .byte 0x7B,0x00,0x7C,0x00,0x7D,0x00
  .byte 0x7E,0x00,0x7F,0x00,0x41,0x08
  .byte 0x41,0x0C,0x43,0x10,0x45,0x02
  .byte 0x4E,0x0A,0x4F,0x08,0x55,0x08
  .byte 0x41,0x82,0x41,0x84,0x41,0x86
  .byte 0x41,0x88,0x41,0x8A,0x41,0x8C
  .byte 0x43,0x90,0x45,0x82,0x45,0x84
  .byte 0x45,0x86,0x45,0x88,0x49,0x82
  .byte 0x49,0x84,0x49,0x86,0x49,0x88
  .byte 0x4E,0x8A,0x4F,0x82,0x4F,0x84
  .byte 0x4F,0x86,0x4F,0x88,0x4F,0x8A
  .byte 0x55,0x82,0x55,0x84,0x55,0x86
  .byte 0x55,0x88,0xA0,0x00,0xA1,0x00
  .byte 0xA2,0x00,0xA3,0x00,0xA4,0x00
  .byte 0xA5,0x00,0xA6,0x00,0x53,0x82
  .byte 0xA8,0x00,0xA9,0x00,0xAA,0x00
  .byte 0xAB,0x00,0xAC,0x00,0xAD,0x00
  .byte 0x41,0x14,0x4F,0x0E,0xB0,0x00
  .byte 0xB1,0x00,0xB2,0x00,0xB3,0x00
  .byte 0xB4,0x00,0xB5,0x00,0xB6,0x00
  .byte 0xB7,0x00,0xB8,0x00,0xB9,0x00
  .byte 0xBA,0x00,0x41,0x92,0x4F,0x92
  .byte 0xBD,0x00,0x41,0x94,0x4F,0x8E
  .byte 0xC0,0x00,0xC1,0x00,0xC2,0x00
  .byte 0xC3,0x00,0xC4,0x00,0xC5,0x00
  .byte 0xC6,0x00,0x22,0x06,0x22,0x08
  .byte 0xC9,0x00,0x20,0x00,0x41,0x04
  .byte 0x41,0x0A,0x4F,0x0A,0x4F,0x14
  .byte 0x4F,0x94,0xD0,0x00,0xD1,0x00
  .byte 0x22,0x02,0x22,0x04,0x27,0x02
  .byte 0x27,0x04,0xD6,0x00,0xD7,0x00
  .byte 0x59,0x88,0xD9,0x00,0xDA,0x00
  .byte 0xDB,0x00,0xDC,0x00,0xDD,0x00
  .byte 0xDE,0x00,0xDF,0x00,0xE0,0x00
  .byte 0xE1,0x00,0xE2,0x00,0xE3,0x00
  .byte 0xE4,0x00,0xE5,0x00,0xE6,0x00
  .byte 0xE7,0x00,0xE8,0x00,0xE9,0x00
  .byte 0xEA,0x00,0xEB,0x00,0xEC,0x00
  .byte 0xED,0x00,0xEE,0x00,0xEF,0x00
  .byte 0xF0,0x00,0xF1,0x00,0xF2,0x00
  .byte 0xF3,0x00,0xF4,0x00,0xF5,0x00
  .byte 0xF6,0x00,0xF7,0x00,0xF8,0x00
  .byte 0xF9,0x00,0xFA,0x00,0xFB,0x00
  .byte 0xFC,0x00,0xFD,0x00,0xFE,0x00
  .byte 0xFF,0x00
