| Operating System Utilities
|
| Apple source: SysUtil.a (MacSEROM.lst module SYSUTIL). In ROM order:
|   ReadParam, WriteParam      - parameter RAM: low-memory copy SysParam <->
|                                clock chip
|   ReadDateTime, SetDateTime  - the clock (Time)
|   Delay                      - wait D0 ticks
|   CmpString (EqualString), RelString, UprString, with the character
|                                tables CONVERSION_TBL / STRIP_TBL
|   ReadPRAM                   - read the 20 bytes of parameter RAM
|   InitUtil                   - _InitUtil: copy parameter RAM to SysParam,
|                                write the defaults if it is invalid
|   WPOn, WPOff                - clock chip write protect
| The bit-level clock chip access (ClkRW, _ReadXPRam, _WriteXPRam) is in
| hw/rtc.s.
|
| References: Inside Macintosh Vol II, Ch 13 (Operating System Utilities).

| ----------------------------------------------------------
|
| Read Param
|
| _ReadParam: read PRAM into low-memory SysParam block
Trap0_37:                                       | MacPlusROM.lst placeholder for trap $A037 (ReadParam)
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
        BNE.B   CMPSTRING_LENDIFF               | no, can't be equal ->
        SWAP    D0                              | restore D0
        BSR.B   RelString                       | compare chars
        BPL.B   CMPSTRING_CONT                  | str1 >= str2 ->
        NEG.L   D0                              | make positive (not equal)
CMPSTRING_CONT:
        RTS                                     | return from CmpString

| ----------------------------------------------------------
|
| CMPSTRING_LENDIFF
|
| CmpString: lengths differ -> not equal
CMPSTRING_LENDIFF:
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
        MOVE.B  UPRSTRING_CONT(PC,D2.W),D2      | diacSens=false -> strip diacritics
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
| Toolbox trap $A854, UprString's trap number in the 64K ROM, dispatches
| here as well (MacPlusROM.lst: Trap1_54).
Trap1_54:                                       | MacPlusROM.lst placeholder for trap $A854 (UprString)
UprString:
        BSR.B   RELSTRING_CONT_4                | set up conversion tables
        BRA.B   UPRSTRING_LOOP_2                | -> convert loop

| ----------------------------------------------------------
|
| UPRSTRING_LOOP
|
UPRSTRING_LOOP:
        MOVE.B  (A0),D2                         | D2 = character
        BSR.B   RELSTRING_CONT                  | apply case/diacritic folding
        MOVE.B  D2,(A0)+                        | write folded character back
UPRSTRING_LOOP_2:
        DBF     D0,UPRSTRING_LOOP               | loop over all characters
        MOVEQ.L #0x0,D0                         | D0 = 0 (success)
        BRA.B   RELSTRING_EXIT_4                | -> exit

| ----------------------------------------------------------
|
| UPRSTRING_CONT
|
UPRSTRING_CONT:
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
| ReadPRAM: read 20 bytes from RTC PRAM into buffer at A1
| PRAM is split: 16 bytes at RTC registers $C1-$FC, 4 bytes at $A1-$AC
ReadPRAM:
        MOVEM.L D1-D2/D5/A1,-(SP)               | save regs
        MOVEQ.L #-0x3F,D1                       | D1 = $C1 (first PRAM read command)
        MOVEQ.L #0xF,D5                         | 16 bytes in first block
        BSR.B   READPRAM_LOOP                   | read 16 bytes
        MOVEQ.L #-0x5F,D1                       | D1 = $A1 (second PRAM block)
        MOVEQ.L #0x3,D5                         | 4 bytes in second block
        BSR.B   READPRAM_LOOP                   | read 4 bytes
        MOVEM.L (SP)+,D1-D2/D5/A1               | restore regs
        RTS                                     | return from ReadPRAM

| ----------------------------------------------------------
|
| READPRAM_LOOP: read consecutive RTC registers into buffer at A1
| D1 = starting RTC command, D5 = byte count - 1
|
| Called during boot.
READPRAM_LOOP:
        JSR     ClkRW(PC)                       | read one byte from RTC -> D2
        MOVE.B  D2,(A1)+                        | store byte, advance pointer
        ADDQ.B  #0x4,D1                         | next RTC register address
        DBF     D5,READPRAM_LOOP                | loop
        RTS                                     | return from READPRAM_LOOP

| ----------------------------------------------------------
|
| READPRAM_CONT
|
READPRAM_CONT:
  .byte 0xA8,0x00,0x00,0x00,0xCC,0x0A
  .byte 0xCC,0x0A,0x00,0x00,0x00,0x00
  .byte 0x00,0x02,0x63,0x00,0x03,0x88
  .byte 0x00,0x4C

| _InitUtil ($A03F): initialize Parameter RAM from RTC
| Reads PRAM, validates it, reinitializes if invalid
| Called during boot before most other managers
InitUtil:
        CLR     -(SP)                           | space for result
        BSR     WPOff                           | disable RTC write protect
| reset RTC test register
        MOVEQ.L #0x31,D1                        | RTC command: write test register
        CLR.B   D2                              | data = 0 (clear test mode)
        JSR     ClkRW(PC)                       | write to RTC
        BSR     WPOn                            | re-enable write protect
| read PRAM and date/time
        LEA.L   (SysParam_SPValid).w,A1         | A1 = SysParam destination
        BSR.B   ReadPRAM                        | read 20 bytes from PRAM
        BSR.B   INITUTIL_CONT                   | read date/time from RTC -> Time
| validate PRAM magic byte
        MOVEQ.L #0x0,D0                         | assume noErr
        CMPI.B  #0xA8,(A1)                      | valid PRAM signature? ($A8)
        BEQ.B   INITUTIL_OK                     | yes ->
| invalid PRAM: initialize with defaults from READPRAM_CONT
        MOVE    #-0x58,(SP)                     | prInitErr (-88)
        MOVEQ.L #0x4,D1                         | 5 longwords = 20 bytes
        LEA.L   READPRAM_CONT(PC),A0            | A0 = default PRAM values
INITUTIL_LOOP:
        MOVE.L  (A0)+,(A1)+                     | copy defaults to SysParam
        DBF     D1,INITUTIL_LOOP                | loop 5 longwords
        BSR     WPOFF_CONT                      | write defaults to RTC PRAM
| check for extended PRAM (Mac Plus has 256 bytes)
INITUTIL_OK:
        BTst    #0x6,(HWCfgFlags).w             | extended PRAM available?
        BEQ.B   INITUTIL_NO                     | no ->
        LEA.L   (Scratch20).w,A0                | temp buffer for extended PRAM
        MOVE.L  #0x4000C,D0                     | D0 = length 4, offset 12
        _ReadXPRam                              | read extended PRAM signature
        MOVE.L  #0x42756773,D1                  | D1 = 'Bugs' signature
        CMP.L   (A0),D1                         | signature matches?
        BEQ.B   INITUTIL_NO                     | yes -> extended PRAM is initialized
        MOVE    #-0x58,(SP)                     | set prInitErr
        MOVE.L  D1,(A0)                         | write 'Bugs' signature to buffer
        MOVE.L  #0x4000C,D0                     | D0 = length 4, offset 12
        _WriteXPRam                             | initialize signature in XPRAM
        MOVEQ.L #0x20,D1                        | start zeroing from offset 32 ($20)
INITUTIL_DONE:
        MOVEQ.L #0x4,D0                         | length 4
        SWAP    D0                              | D0.hi = 4
        MOVE    D1,D0                           | D0.lo = offset
        CLR.L   (A0)                            | clear buffer
        _WriteXPRam                             | write 0 to XPRAM
        ADDQ.B  #0x4,D1                         | next offset (wraps at 256)
        CMPI.B  #0x8,D1                         | stop when reaching offset 8 (skips 8..31)
        BNE.B   INITUTIL_DONE                   | loop until done
INITUTIL_NO:
        MOVE    (SP)+,D0                        | D0 = initialization error code
        BNE.B   INITUTIL_ERR                    | if error, skip setting flag
        BSET    #0x5,(HWCfgFlags).w             | set flag: PRAM initialized successfully
INITUTIL_ERR:
        EXT.L   D0                              | sign-extend error code
        RTS                                     | return from InitUtil

| ----------------------------------------------------------
|
| INITUTIL_CONT
|
| Called during boot.
| INITUTIL_CONT: read date/time from RTC chip (4 bytes, read twice for consistency)
| RTC stores seconds since midnight Jan 1, 1904 as 4 bytes
| Reads twice and compares to detect mid-update glitches
INITUTIL_CONT:
        MOVEM.L D1-D2/D4-D5/A2-A3,-(SP)         | save registers
        MOVEQ.L #0x1,D4                         | retry count = 1 (read up to 2x)
        MOVEQ.L #0x0,D0                         | assume noErr
INITUTIL_LOOP_2:
        MOVEQ.L #-0x63,D1                       | RTC command: read seconds ($9D)
        MOVEQ.L #0x7,D5                         | 8 reads (4 bytes * 2 for verify)
        LEA.L   (Scratch20).w,A2                | dest buffer
        MOVE.L  A2,A3                           | save start for comparison
INITUTIL_LOOP_3:
        JSR     ClkRW(PC)                       | read one RTC register byte
        MOVE.B  D2,(A2)+                        | store byte
        SUBQ.B  #0x4,D1                         | next register address
        DBF     D5,INITUTIL_LOOP_3              | loop 8 times
| verify: first 4 bytes should match second 4 bytes
        CMPM.L  (A3)+,(A3)+                     | compare first 4 with second 4
        BEQ.B   INITUTIL_FOUND                  | match -> valid read
        DBF     D4,INITUTIL_LOOP_2              | retry once
        MOVEQ.L #-0x55,D0                       | clkRdErr (-85): read failed
INITUTIL_FOUND:
        MOVE.L  (Scratch20).w,(Time).w          | store in Time global
        MOVEM.L (SP)+,D1-D2/D4-D5/A2-A3         | restore registers
        TST.L   D0                              | set condition codes
        RTS                                     | return from INITUTIL_CONT (ReadTime)

| ----------------------------------------------------------
|
| INITUTIL_CONT_2: write date/time to RTC chip (for SetDateTime)
| Writes 4 bytes, reads back to verify
INITUTIL_CONT_2:
        MOVEM.L D1-D5,-(SP)                     | save registers
        BSR.B   WPOff                           | disable write protect
        MOVE.L  (Time).w,D3                     | D3 = time value to write
        MOVEQ.L #0x1,D5                         | retry count
INITUTIL_LOOP_4:
        MOVE.L  D3,D2                           | D2 = data to write (shifts out)
        MOVEQ.L #0x1,D1                         | RTC command: write seconds ($01)
        MOVEQ.L #0x3,D4                         | 4 bytes to write
INITUTIL_LOOP_5:
        JSR     ClkRW(PC)                       | write one byte to RTC
        ADDQ.B  #0x4,D1                         | next register
        LSR.L   #0x8,D2                         | shift to next byte
        DBF     D4,INITUTIL_LOOP_5              | loop 4 bytes
| verify: read back and compare
        BSR.B   INITUTIL_CONT                   | read time from RTC
        BNE.B   INITUTIL_ERR_2                  | read error -> done
        CMP.L   (Time).w,D3                     | written value matches read?
        BEQ.B   INITUTIL_ERR_2                  | yes -> success
        DBF     D5,INITUTIL_LOOP_4              | retry once
        MOVEQ.L #-0x56,D0                       | clkWrErr (-86): write failed
INITUTIL_ERR_2:
        BSR.B   WPOn                            | re-enable write protect
        MOVEM.L (SP)+,D1-D5                     | restore regs
        RTS                                     | return from SetDateTime

| ----------------------------------------------------------
|
| WP On
|
| WPOn: enable RTC write protect (write $D5 to WP register)
WPOn:
        MOVEQ.L #0x35,D1                        | RTC command: write protect register
        MOVEQ.L #-0x2B,D2                       | data = $D5 (enable WP)
        JMP     ClkRW(PC)                       | write to RTC

| ----------------------------------------------------------
|
| WPOff: disable RTC write protect (write $55 to WP register)
|
WPOff:
        MOVEQ.L #0x35,D1                        | RTC command: write protect register
        MOVEQ.L #0x55,D2                        | data = $55 (disable WP)
        JMP     ClkRW(PC)                       | write to RTC

| ----------------------------------------------------------
|
| WPOFF_CONT: write SysParam (20 bytes) to RTC PRAM
|
WPOFF_CONT:
        MOVEM.L D1-D3/A2,-(SP)                  | save regs
        BSR.B   WPOff                           | disable write protect
        LEA.L   (SysParam_SPValid).w,A2         | A2 = source (SysParam block)
        MOVE.B  #0x41,D1                        | RTC write command for first block
        MOVEQ.L #0xF,D3                         | 16 bytes in first block
        BSR.B   WPOFF_LOOP                      | write 16 bytes
        MOVE.B  #0x21,D1                        | RTC write command for second block
        MOVEQ.L #0x3,D3                         | 4 bytes in second block
        BSR.B   WPOFF_LOOP                      | write 4 bytes
        BSR.B   WPOn                            | re-enable write protect
        MOVEM.L (SP)+,D1-D3/A2                  | restore regs
        RTS                                     | return from WPOFF_CONT (WritePRAM)

| ----------------------------------------------------------
|
| WPOFF_LOOP: write consecutive bytes from A2 to RTC registers
| D1 = starting RTC command, D3 = byte count - 1
|
WPOFF_LOOP:
        MOVE.B  (A2)+,D2                        | D2 = next byte to write
        JSR     ClkRW(PC)                       | write to RTC register
        ADDQ.B  #0x4,D1                         | next RTC register address
        DBF     D3,WPOFF_LOOP                   | loop
        RTS                                     | return from WPOFF_LOOP

