| =========================================================================
| PACK 4 -- FP68K, the SANE floating-point arithmetic package
| =========================================================================
| ROM offsets +0x1C180..+0x1D33F: the 8-byte header of the ROM resource at
| +0x1C180, then the package, $11B8 bytes from +0x1C188 (_PACK_4_ in
| MacSEROM.lst) on; type PACK, ID 4, no name, attributes $58 (resSysHeap,
| resLocked, resProtected). The same in both SE ROMs.
|
| Version 2 (header word): Jerome Coonen's FP68K of 26 March 1985, the
| same code as the PACK 4 of the Mac Plus ROM, but assembled with the MPW
| assembler ("18may86: moved to MPW" in Apple's FP68K.a), which turns each
| CLR.L Dn into MOVEQ #0,Dn: those 29 instructions are the only difference
| from the Plus bytes. The code follows Apple's System 7.1 sources FP68K.a
| (= FPEqus.a + FPCtrl.a + FPOps.a + FPBD.a) instruction for instruction;
| the 7.1 source already has the two later fixes the ROM contains
| ("Clear inexact if invalid" in IOFLOW, the saved modes in DBCORE).
| Labels: Apple's names from these sources with the prefix FP68K_
| (FP68K_UNPACK, FP68K_ARITHOP, the tables FP68K_ARITHTAB ...); the
| targets of Apple's local labels are FP68K_<label>_<n> for the @n that
| follows that label (e.g. FP68K_FPCOM_3).
|
| Calling convention (Apple Numerics Manual; IM IV): _FP68K = _Pack4
| ($A9EB) with the operand addresses and then an opword pushed:
|   (SP): return, 4(SP): opword, 6(SP): address 1 (destination), 10(SP):
|   address 2 (source), 14(SP): address 3 (Bin2Dec: the DecForm);
| the package pops opword and addresses; the CCR holds the result of a
| compare. All registers are preserved.
| Opword: bits 0-4 operation, bits 11-13 format of the operand that is
| not extended (0 extended 80 bits, 1 double, 2 single, 4 int16, 5 int32,
| 6 comp 64 bits). Even operations (OPMASKS/ARITHTAB): $00 add, $02 sub,
| $04 mul, $06 div, $08 cmp, $0A cmpx (signals unordered), $0C rem, $0E
| convert to extended, $10 convert from extended, $12 sqrt, $14 rint
| (round to integral), $16 tint (truncate), $18 scalb, $1A logb, $1C
| class. Odd operations (ODDBALL/ODDTAB): $01 setenv, $03 getenv, $05
| sethv, $07 gethv, $09 dec2bin, $0B bin2dec, $0D neg, $0F abs, $11
| copysign, $13 nextafter, $15 setxcp, $17 procentry, $19 procexit, $1B
| testxcp.
| The state (FPState, $A4A): the environment word, then the halt vector
| (long). Environment high byte: bits 0-4 exception flags (invalid,
| underflow, overflow, divide by zero, inexact), bits 5-6 rounding
| direction (00 nearest, 01 upward, 10 downward, 11 toward zero); low
| byte: bits 0-4 halt enables, bits 5-6 rounding precision (01 double,
| 10 single), bit 7 "last round was up" (RNDINC).
|
| Internal registers (FPCtrl.a): D6.hi = decoded opword (bit 31 single
| result, 30 double, 26 integer result, 23 dst in, 22 src in, 21 dst out,
| 16 two addresses), D6.lo = new exception flags (bits 8-12) and the
| signs (bit 7 src or result, 6 dst, 5 their XOR); unpacked operands:
| last one in D4:D5 (significand) / A4 (exponent), first one in A1:A2 /
| A3; D7 round/guard/sticky bits, later the CCR result in D7.hi; D2 NaN
| case (2 src, 4 dst, 6 both), D3 number case (0 num, 2 zero, 4 infinity
| per operand, combined 0..16 for two operands); A0 = FPState.
|
| Sources: Apple's FP68K.a, FPEqus.a, FPCtrl.a, FPOps.a, FPBD.a (Mac OS
| 7.1 tree, Toolbox/SANE) and SANEMacs.a (NaN codes, environment bits),
| the Apple Numerics Manual, Inside Macintosh IV ("SANE"), the Mac Plus
| PACK 4 (src/plus/resources/res_pack_4.s).
| =========================================================================

| -------------------------------------------------------------------------
| ROM resource header: a Memory Manager style block header (tag $C0 and
| the physical size, then a relative-handle field) in front of the
| resource data, as for every ROM resource.
| -------------------------------------------------------------------------
Resource_PACK_0004:
Resource_PACK_0004_Header:
    .long	0xC00011C0                            | ROM resource header: tag $C0, physical size $11C0 (8 + $11B8)
    .long	0x00000058                            | relative handle: master pointer at ROM zone + $58
| -------------------------------------------------------------------------
| Package header: branch to the entry, flags word, 'PACK', ID, version.
| -------------------------------------------------------------------------
_PACK_4_:
    BRA.B	FP68K_FPBEGIN                         | skip the package header to the entry FPBEGIN
    .short	0x0000                               | flags word
    .ascii	"PACK"                               | resource type
    .short	0x0004                               | resource ID 4
    .short	0x0002                               | version 2
| -------------------------------------------------------------------------
| FP68K_FPBEGIN -- the entry of _FP68K: a frame whose -2(A6)
| word later holds the byte count to pop (LKCNT), all registers saved,
| A0 = FPState.
| -------------------------------------------------------------------------
FP68K_FPBEGIN:
    LINK	A6,#-0x2                               | frame; -2(A6) = LKCNT, the byte count to pop
    MOVEM.L	D0-D7/A0-A4,-(SP)                   | save D0-D7/A0-A4: all registers are preserved
    MOVEA.W	#0xA4A,A0                           | A0 = FPState ($A4A): environment word, halt vector
    BRA.B	FP68K_FPCOM                           | -> FPCOM
| ----------------------------------------------------------
| FP68K_OPMASKS: information bits ORed into the opword,
| per operation (index = opword AND $1E): $80 dst in, $40 src in, $20 dst
| out, $100 the format field governs the dst, $01 two addresses.
FP68K_OPMASKS:
    .short	0x00E1                               | ADD: dst and src in, dst out, 2 addresses
    .short	0x00E1                               | SUB
    .short	0x00E1                               | MUL
    .short	0x00E1                               | DIV
    .short	0x00C1                               | CMP: no output (the result is the CCR)
    .short	0x00C1                               | CMPX
    .short	0x00E1                               | REM
    .short	0x0061                               | 2EXT (to extended): src in, dst out
    .short	0x0161                               | EXT2 (from extended): the format governs the dst
    .short	0x00A0                               | SQRT: dst in and out, 1 address
    .short	0x00A0                               | RINT
    .short	0x00A0                               | TINT
    .short	0x00A1                               | SCALB: like SQRT, the integer is the 2nd address
    .short	0x00A0                               | LOGB
    .short	0x0041                               | CLASS: src in, the integer result is the dst
| ----------------------------------------------------------
| FP68K_REFP68K -- second entry, for calls from inside the
| package: like FPBEGIN, but A0 already points to the state.
| Called by: FP68K_NEXTZ, FP68K_NXERR, FP68K_DBSTORE, FP68K_DBCORE_5, FP68K_NOTMINEXP (and 2 more)
FP68K_REFP68K:
    LINK	A6,#-0x2                               | frame; -2(A6) = LKCNT
    MOVEM.L	D0-D7/A0-A4,-(SP)                   | save D0-D7/A0-A4
| FP68K_FPCOM -- decode the opword: odd opwords go to
| ODDBALL; for arithmetic add the OPMASKS bits, the precision control and
| the format fields, unpack the operands, then dispatch (ARITHOP).
FP68K_FPCOM:
    MOVE.W	0x8(A6),D6                           | D6 = the opword (LKOP)
| decode selector: extract operation code and operand format
    MOVEQ.L	#0x1E,D7                            | OPAMASK: operation index bits 1-4
    AND.W	D6,D7                                 | D7 = operation * 2: table index
    BCLR	#0x0,D6                                | odd opword (bit 0)? clear the bit
    BNE.W	FP68K_ODDBALL                         | yes: environment and other odd operations (ODDBALL) ->
| look up operation descriptor from FP68K_OPMASKS table
    BCLR	#0x7,0x1(A0)                           | clear RNDINC (last round up) in the environment
    OR.W	FP68K_OPMASKS(PC,D7.W),D6              | add the information bits of the operation (OPMASKS)
| precision control to D6 bits 15-14; the format of the non-extended
| operand: source field (bits 11-13), or moved to the destination field
| (bits 8-10) when bit 8 says so; then that format overrides bits 15-14
    MOVEQ.L	#0x60,D0                            | PRECMSK: precision control bits 5-6
    AND.B	0x1(A0),D0                            | of the environment low byte
    ROR.W	#0x7,D0                               | $0060 -> $C000: bit 15 single, bit 14 double
    OR.W	D0,D6                                  | into the opword
| conversions from extended: the format field describes the destination
    BTST	#0x8,D6                                | bit 8: the format is the destination's (EXT2)?
    BEQ.B	FP68K_DEREF_OP                        | no ->
    MOVE.W	D6,D0                                | save the format bits
    ANDI.W	#0xFF,D6                             | clear all format bits in D6
    ANDI.W	#0x3800,D0                           | D0 = the format field (bits 11-13)
    MOVE.W	D0,D1                                | copy for the control bits
    LSL.W	#0x3,D1                               | its 2 low bits to bits 15-14 (single/double)
    ROR.W	#0x3,D0                               | the format into the destination field (bits 8-10)
    OR.W	D0,D6                                  | destination format
    OR.W	D1,D6                                  | single/double bits from the format
FP68K_DEREF_OP:
    SWAP.W	D6                                   | the decoded opword to D6.hi, where it stays
    MOVEQ.L	#0x0,D2                             | D2 := 0: NaN case index (2 src NaN, 4 dst NaN, 6 both)
    MOVE.L	D2,D3                                | D3 := 0: number case index (num/zero/inf pairs)
    MOVE.W	D2,D6                                | D6.W := 0: signs and exception flags
    BTST	#0x17,D6                               | destination is an input (DSTIN)?
    BEQ.B	FP68K_FPCOM_3                         | no ->
    MOVE.L	D6,D0                                | opword ...
    SWAP.W	D0                                   | ... in the low word ...
    ROR.W	#0x7,D0                               | ... destination format * 2 in bits 3-1
    MOVEA.L	0xA(A6),A3                          | A3 = address 1, the destination (LKADR1)
    BSR.W	FP68K_UNPACK                          | UNPACK the dst into D4:D5/A4
FP68K_FPCOM_3:
    BTST	#0x16,D6                               | source is an input (SRCIN)?
    BEQ.B	FP68K_FPCOM_4                         | no ->
    MOVEA.L	D4,A1                               | A1:A2 := the dst significand
    MOVEA.L	D5,A2                               | (low half)
    MOVE.L	A4,-(SP)                             | save the dst exponent across UNPACK
    ROR.B	#0x1,D6                               | dst sign to bit 6, bit 7 free for the src sign
    ADD.W	D2,D2                                 | NaN index * 2: dst NaN = 4
    MOVE.W	D3,D0                                | number index of the dst ...
    ADD.W	D3,D3                                 | ...
    ADD.W	D0,D3                                 | ... * 3: 0, 6, 12 (the src adds 0, 2, 4)
    MOVE.L	D6,D0                                | opword ...
    SWAP.W	D0                                   | ... in the low word ...
    ROL.W	#0x6,D0                               | ... source format * 2 in bits 3-1
    MOVEA.L	0xE(A6),A3                          | A3 = address 2, the source (LKADR2)
    BSR.W	FP68K_UNPACK                          | UNPACK the src into D4:D5/A4
    MOVEA.L	(SP)+,A3                            | A3 = the dst exponent
FP68K_FPCOM_4:
    ASL.B	#0x1,D6                               | V := src sign XOR dst sign
    BVC.B	FP68K_FPCOM_6                         | equal ->
    BSET	#0x6,D6                                | different: XOR bit (becomes bit 5)
FP68K_FPCOM_6:
    ROXR.B	#0x1,D6                              | back: bit 7 src sign, 6 dst sign, 5 XOR
    MOVE.W	D7,D0                                | D0 = operation * 2
    MOVEQ.L	#0x0,D7                             | D7 := 0: round/sticky bits, later the CCR result
    PEA.L	FP68K_PREPACK(PC)                     | the operation returns to PREPACK
    TST.W	D2                                    | NaN operands?
    BNE.W	FP68K_NANS                            | yes: NANS ->
| FP68K_ARITHOP: jump to the operation, D0 = opword AND
| $1E; the operation returns to FP68K_PREPACK.
FP68K_ARITHOP:
    MOVE.W	FP68K_ARITHTAB(PC,D0.W),D0           | D0 = offset of the operation (ARITHTAB)
    JMP	FP68K_ARITHOP(PC,D0.W)                  | -> the operation routine
| FP68K_ARITHTAB: operation routines, offsets from
| FP68K_ARITHOP.
FP68K_ARITHTAB:
    .short	FP68K_ADDTOP-FP68K_ARITHOP           | add (ADDTOP)
    .short	FP68K_SUBTOP-FP68K_ARITHOP           | sub (SUBTOP)
    .short	FP68K_MULTOP-FP68K_ARITHOP           | mul (MULTOP)
    .short	FP68K_DIVTOP-FP68K_ARITHOP           | div (DIVTOP)
    .short	FP68K_CMPTOP-FP68K_ARITHOP           | cmp (CMPTOP)
    .short	FP68K_CMPTOP-FP68K_ARITHOP           | cmpx (CMPTOP as well)
    .short	FP68K_REMTOP-FP68K_ARITHOP           | rem (REMTOP)
    .short	FP68K_CVT2E-FP68K_ARITHOP            | convert to extended (CVT2E)
    .short	FP68K_CVTE2-FP68K_ARITHOP            | convert from extended (CVTE2)
    .short	FP68K_SQRTTOP-FP68K_ARITHOP          | sqrt (SQRTTOP)
    .short	FP68K_RINT-FP68K_ARITHOP             | rint (RINT)
    .short	FP68K_TINT-FP68K_ARITHOP             | tint (TINT)
    .short	FP68K_SCALBTOP-FP68K_ARITHOP         | scalb (SCALBTOP)
    .short	FP68K_LOGBTOP-FP68K_ARITHOP          | logb (LOGBTOP)
    .short	FP68K_CLASSTOP-FP68K_ARITHOP         | class (CLASSTOP)
| FP68K_PREPACK -- the operation is done: store the result in
| the destination format unless the operation has no output (compares).
FP68K_PREPACK:
    BTST	#0x15,D6                               | a result to store (DSTOUT)?
    BEQ.B	FP68K_CHKERR                          | no (compare) ->
    MOVE.L	D6,D0                                | opword ...
    SWAP.W	D0                                   | ... in the low word ...
    ROR.W	#0x7,D0                               | ... destination format * 2
    BSR.W	FP68K_PACK                            | PACK the result to address 1
FP68K_CHKERR:
    SWAP.W	D7                                   | CHKERR: the CCR result to D7.lo
    MOVE.W	(A0),D0                              | D0 = the environment
    CLR.B	D6                                    | drop the signs
    OR.W	D6,D0                                  | OR in the new exceptions (bits 8-12)
    MOVE.W	D0,(A0)+                             | store; A0 -> the halt vector
    ROR.W	#0x8,D6                               | new exceptions to bits 0-4, beside the halt enables
    AND.W	D6,D0                                 | any of them with its halt enabled?
    BEQ.B	FP68K_PASTHALT                        | no ->
    MOVE.W	D7,-(SP)                             | halt: the CCR word ...
    MOVE.W	D0,-(SP)                             | ... and the halting exceptions: a 2-word record
    PEA.L	(SP)                                  | push its address
    MOVEM.L	0x6(A6),D0-D3                       | opword and the 3 addresses (plus one word) ...
    MOVEM.L	D0-D3,-(SP)                         | ... copied for the halt procedure
    ADDQ.L	#0x2,SP                              | drop the extra word
    MOVEA.L	(A0),A0                             | A0 = the halt vector
    JSR	(A0)                                    | call the halt procedure (Pascal conventions)
    MOVE.L	(SP)+,D7                             | D7 = the CCR word again
FP68K_PASTHALT:
    BTST	#0x10,D6                               | PASTHALT: two addresses (TWOADRS)?
    BEQ.B	FP68K_POP1                            | no: one address (POP1) ->
| FP68K_POP2: two addresses -- pop 10 bytes.
FP68K_POP2:
    MOVEQ.L	#0x10,D0                            | STKREM2: 16 bytes to pop
    MOVEQ.L	#0xE,D1                             | the return address goes to LKADR2
    BRA.B	FP68K_POPIT                           | -> POPIT
| ----------------------------------------------------------
| FP68K_POP1: one address -- pop opword and address.
FP68K_POP1:
    MOVEQ.L	#0xC,D0                             | STKREM1: 12 bytes to pop
    MOVEQ.L	#0xA,D1                             | the return address goes to LKADR1
| FP68K_POPIT -- D0 = bytes to pop at the end (LKCNT), D1 =
| frame offset of the slot that gets the return address (the last address
| parameter); unlink by hand, set the CCR, restore the registers, pop.
FP68K_POPIT:
    MOVE.W	D0,-0x2(A6)                          | LKCNT := bytes to pop
    MOVE.L	0x4(A6),0x0(A6,D1.W)                 | return address over the last parameter
    MOVEA.L	(A6),A6                             | unlink by hand: A6 = the caller's
    MOVE.W	D7,CCR                               | the CCR result (compares)
    MOVEM.L	(SP)+,D0-D7/A0-A4                   | restore the registers (CCR not affected)
    ADDA.W	(SP),SP                              | pop LKCNT bytes: SP -> the return address
    RTS                                         | return to the FP68K caller, its operands popped
| ----------------------------------------------------------
| FP68K_POP3: three addresses (binary to decimal only).
FP68K_POP3:
    MOVEQ.L	#0x14,D0                            | STKREM3: 20 bytes to pop
    MOVEQ.L	#0x12,D1                            | the return address goes to LKADR3
    BRA.B	FP68K_POPIT                           | -> POPIT
| ----------------------------------------------------------
| FP68K_UNPACK -- unpack the operand at A3, format
| code * 2 in D0 (dirty), into the internal form: sign in D6 bit 7,
| significand in D4:D5 (normalized, integer bit 31 of D4), exponent in A4
| (biased $3FFF, 32 bits). Integers are converted to extended. Sets D2 +=
| 2 for a NaN, D3 += 2 for zero, += 4 for infinity, D3 bit 31 for an
| unnormalized operand (for CLASS); a signaling NaN signals invalid and
| is made quiet. A3 is preserved.
| Called by: FP68K_FPCOM (twice), FP68K_B2D.
FP68K_UNPACK:
    MOVEQ.L	#0x0,D4                             | D4 := 0: clear the significand D4:D5 (UNPACK)
    MOVE.L	D4,D5                                | D5 := 0
    ANDI.W	#0xE,D0                              | D0 = format * 2
    MOVE.W	FP68K_UNPCASE(PC,D0.W),D0            | offset of the format's routine (UNPCASE)
    JMP	FP68K_UNPACK(PC,D0.W)                   | -> it
| FP68K_UNPCASE: unpack routine per format, offsets from
| FP68K_UNPACK.
FP68K_UNPCASE:
    .short	FP68K_UNPEXT-FP68K_UNPACK            | format 0 extended (UNPEXT)
    .short	FP68K_UNPDBL-FP68K_UNPACK            | format 1 double (UNPDBL)
    .short	FP68K_UNPSGL-FP68K_UNPACK            | format 2 single (UNPSGL)
    .short	FP68K_UNPEXT-FP68K_UNPACK            | format 3: as extended
    .short	FP68K_UNPI16-FP68K_UNPACK            | format 4 int16 (UNPI16)
    .short	FP68K_UNPI32-FP68K_UNPACK            | format 5 int32 (UNPI32)
    .short	FP68K_UNPC64-FP68K_UNPACK            | format 6 comp (UNPC64)
| FP68K_UNPI16: int16 -- left-aligned in D4, exponent 15.
FP68K_UNPI16:
    MOVEQ.L	#0xF,D0                             | D0 = 15: exponent of the integer once left-aligned in D4 (UNPI16)
    MOVE.W	(A3),D4                              | D4.W = the 16-bit integer operand
    SWAP.W	D4                                   | left-align it
    BRA.B	FP68K_UNPIGEN                         | -> UNPIGEN
| FP68K_UNPI32: int32 -- in D4, exponent 31.
FP68K_UNPI32:
    MOVEQ.L	#0x1F,D0                            | D0 = 31: exponent of the int32 in D4
    MOVE.L	(A3),D4                              | D4 = the int32 operand
    BRA.B	FP68K_UNPIGEN                         | -> UNPIGEN
| ----------------------------------------------------------
| FP68K_UNPC64: comp -- in D4:D5, exponent 63; the comp NaN
| $80000000:00000000 becomes a quiet NaN with code 20 (NANCOMP).
FP68K_UNPC64:
    MOVEQ.L	#0x3F,D0                            | D0 = 63: exponent of the comp in D4:D5
    MOVE.L	(A3),D4                              | high half
    MOVE.L	0x4(A3),D5                           | low half
    BEQ.B	FP68K_UNPC64_7                        | low half 0: maybe the comp NaN ->
    TST.L	D4                                    | sign of the comp
    BRA.B	FP68K_UNPCGEN                         | -> UNPCGEN
| ----------------------------------------------------------
| FP68K_UNPC64_7 (Apple UNPC64 @7): low half 0 -- the comp NaN?
FP68K_UNPC64_7:
    CMPI.L	#0x80000000,D4                       | the comp NaN $80000000:00000000?
    BNE.B	FP68K_UNPIGEN                         | no: maybe 0 -> UNPIGEN
| comp NaN: encode as extended NaN
    MOVEA.W	#0x7FFF,A4                          | NaN exponent
    MOVEQ.L	#0x14,D4                            | NaN code 20 (NANCOMP) ...
    SWAP.W	D4                                   | ... in bits 16-23
    BSET	#0x1E,D4                               | quiet NaN (QNANBIT)
    BRA.B	FP68K_UNPNAN                          | -> UNPNAN
| ----------------------------------------------------------
| FP68K_UNPIGEN: integer -- 0 is a zero; else take the
| magnitude (sign to D6), bias the exponent and normalize.
FP68K_UNPIGEN:
    TST.L	D4                                    | integer 0?
    BEQ.B	FP68K_UNP0                            | yes: zero (UNP0) ->
FP68K_UNPCGEN:
    BPL.B	FP68K_UNPCGEN_9                       | positive ->
    BSET	#0x7,D6                                | minus sign
    NEG.L	D5                                    | magnitude: negate the 64 bits
    NEGX.L	D4                                   | (high half)
FP68K_UNPCGEN_9:
    ADDI.W	#0x3FFF,D0                           | bias the exponent
    TST.L	D4                                    | leading bit set?
    BMI.B	FP68K_UNPNRM                          | yes: normalized (UNPNRM) ->
    BRA.B	FP68K_UNPCUNR                         | normalize, not marked unnormal (UNPCUNR) ->
| ----------------------------------------------------------
| FP68K_UNPEXT: extended -- split off the sign, check for
| $7FFF (infinity, NaN), zero and unnormalized values.
FP68K_UNPEXT:
    MOVE.W	(A3),D0                              | D0 = sign and exponent
    BPL.B	FP68K_UNPEXT_13                       | positive ->
    BSET	#0x7,D6                                | minus sign
    BCLR	#0xF,D0                                | D0 = exponent
FP68K_UNPEXT_13:
    MOVE.L	0x2(A3),D4                           | D4 = significand, high 32 bits (with the integer bit)
    MOVE.L	0x6(A3),D5                           | D5 = low 32 bits
    CMPI.W	#0x7FFF,D0                           | maximum exponent?
    BEQ.B	FP68K_UNPNIN                          | yes: infinity or NaN (UNPNIN) ->
    TST.L	D4                                    | integer bit set?
    BMI.B	FP68K_UNPNRM                          | yes: normalized (UNPNRM) ->
| FP68K_UNPZUN: zero or unnormalized?
FP68K_UNPZUN:
    TST.L	D4                                    | high bits 0?
    BNE.B	FP68K_UNPUNR                          | no: unnormalized ->
    TST.L	D5                                    | low bits 0?
    BNE.B	FP68K_UNPUNR                          | no: unnormalized ->
| FP68K_UNP0: zero -- A4 = 0, D3 += 2.
FP68K_UNP0:
    SUBA.L	A4,A4                                | exponent 0
    ADDQ.W	#0x2,D3                              | number case: zero
    RTS                                         | return: operand is zero (A4 = 0, D3 += 2)
| ----------------------------------------------------------
| FP68K_UNPUNR: unnormalized -- mark D3 bit 31, normalize
| (FP68K_UNPCUNR, Apple UNPCUNR, also the entry for integers).
FP68K_UNPUNR:
    BSET	#0x1F,D3                               | mark the operand unnormalized (for CLASS)
FP68K_UNPCUNR:
    SUBQ.W	#0x1,D0                              | exponent - 1 ...
    ADD.L	D5,D5                                 | ... significand * 2
    ADDX.L	D4,D4                                | (high half)
    BPL.B	FP68K_UNPCUNR                         | until the leading bit is set
FP68K_UNPNRM:
    EXT.L	D0                                    | 32-bit exponent ...
    MOVEA.L	D0,A4                               | ... in A4
    RTS                                         | return: normalized operand, exponent in A4 (UNPNRM)
| ----------------------------------------------------------
| FP68K_UNPNIN: maximum exponent -- infinity (D3 += 4) or NaN.
FP68K_UNPNIN:
    MOVEA.W	#0x7FFF,A4                          | exponent $7FFF
    BCLR	#0x1F,D4                               | ignore the integer bit
    TST.L	D4                                    | any significand bits?
    BNE.B	FP68K_UNPNAN                          | yes: NaN ->
    TST.L	D5                                    | (low half)
    BNE.B	FP68K_UNPNAN                          | NaN ->
    ADDQ.W	#0x4,D3                              | number case: infinity
    RTS                                         | return: operand is infinite (A4 = $7FFF, D3 += 4)
| ----------------------------------------------------------
| FP68K_UNPNAN: NaN -- set the quiet bit (bit 30); if it was
| clear the NaN was signaling: invalid. D2 += 2.
FP68K_UNPNAN:
    BSET	#0x1E,D4                               | quiet bit (bit 30): test and set
    BNE.B	FP68K_UNPNAN_1                        | was set: a quiet NaN ->
    BSET	#0x8,D6                                | signaling NaN: invalid (ERRI)
FP68K_UNPNAN_1:
    ADDQ.W	#0x2,D2                              | NaN case
    RTS                                         | return: operand is a NaN, made quiet (D2 += 2)
| FP68K_UNPSGL: single -- sign to D6, 8-bit exponent
| rebiased by $3F80, implicit leading 1; exponent 0 is zero or denormal,
| $FF infinity or NaN.
FP68K_UNPSGL:
    MOVEQ.L	#0x0,D0                             | D0 := 0: receives the 8-bit exponent of the single (UNPSGL)
    MOVE.L	(A3),D4                              | D4 = the single
    ADD.B	D6,D6                                 | make room for the sign in D6 bit 0 ...
    ADD.L	D4,D4                                 | sign of the single into X
    ROXR.B	#0x1,D6                              | ... and into D6 bit 7
    ROL.L	#0x8,D4                               | exponent to the low byte
    MOVE.B	D4,D0                                | D0 = biased exponent
    BEQ.B	FP68K_UNPSGL_21                       | 0: zero or denormal ->
    MOVE.B	#0x1,D4                              | replace the exponent by the implicit 1 ...
    ROR.L	#0x1,D4                               | ... and rotate it to bit 31
    CMPI.B	#0xFF,D0                             | maximum exponent?
    BEQ.B	FP68K_UNPNIN                          | yes: infinity or NaN ->
    ADDI.W	#0x3F80,D0                           | rebias: $7F -> $3FFF
    BRA.B	FP68K_UNPNRM                          | -> UNPNRM
| ----------------------------------------------------------
| FP68K_UNPSGL_21 (Apple UNPSGL @21): single with exponent 0 -- zero or
| denormal (no implicit bit, exponent $3F81).
FP68K_UNPSGL_21:
    MOVE.W	#0x3F81,D0                           | exponent of a single denormal
    ROR.L	#0x1,D4                               | align the fraction (no implicit 1)
    BRA.B	FP68K_UNPZUN                          | -> UNPZUN: zero or unnormalized
| ----------------------------------------------------------
| FP68K_UNPDBL: double -- sign to D6, align the 52-bit
| fraction left by 11, 11-bit exponent rebiased by $3C00, implicit 1.
FP68K_UNPDBL:
    MOVE.L	(A3),D4                              | D4 = high half of the double
    BPL.B	FP68K_UNPDBL_25                       | positive ->
    BSET	#0x7,D6                                | minus sign
FP68K_UNPDBL_25:
    MOVE.L	0x4(A3),D5                           | D5 = low half
    ROL.L	#0x8,D5                               | low half: rotate left by 11 ...
    ROL.L	#0x3,D5                               | ...
    ROL.L	#0x8,D4                               | high half: rotate left by 12: exponent to the low bits
    ROL.L	#0x4,D4                               | ...
    MOVE.W	D4,D0                                | D0 = exponent (with extra bits)
    LSR.L	#0x1,D4                               | make room for the leading bit
    ANDI.W	#0xF800,D4                           | clear the low 11 bits
    MOVE.W	D5,D1                                | the 11 bits rotated out of the low half ...
    ANDI.W	#0x7FF,D1                            | ...
    OR.W	D1,D4                                  | ... go into the high half
    ANDI.W	#0xF800,D5                           | and are cleared in the low half
    ANDI.W	#0x7FF,D0                            | D0 = 11-bit exponent
    BNE.B	FP68K_UNPDBL_31                       | not 0 ->
    MOVE.W	#0x3C01,D0                           | exponent of a double denormal
    BRA.W	FP68K_UNPZUN                          | -> UNPZUN: zero or unnormalized
| ----------------------------------------------------------
| FP68K_UNPDBL_31 (Apple UNPDBL @31): nonzero exponent -- infinity/NaN or
| normalized.
FP68K_UNPDBL_31:
    CMPI.W	#0x7FF,D0                            | maximum exponent?
    BEQ.W	FP68K_UNPNIN                          | yes: infinity or NaN ->
    BSET	#0x1F,D4                               | the implicit leading 1
    ADDI.W	#0x3C00,D0                           | rebias: $3FF -> $3FFF
    BRA.W	FP68K_UNPNRM                          | -> UNPNRM
| FP68K_INVALIDOP -- target of all invalid operations: signal
| invalid, deliver a quiet NaN with the code byte in D0 (NANADD 2, NANDIV
| 4, NANMUL 8, NANREM 9, NANSQRT 1, ...).
FP68K_INVALIDOP:
    BSET	#0x8,D6                                | signal invalid (ERRI)
    SWAP.W	D0                                   | the NaN code byte to bits 16-23
    BSET	#0x1E,D0                               | quiet NaN
    MOVE.L	D0,D4                                | significand high half
    MOVEQ.L	#0x0,D5                             | D5 := 0: low half of the new NaN (INVALIDOP)
    MOVEA.W	#0x7FFF,A4                          | NaN exponent
    BRA.B	FP68K_NANSRC                          | -> NANCOERCE
| ----------------------------------------------------------
| FP68K_NANS -- at least one NaN operand: one NaN is the
| result; of two the one with the larger code byte (the src if equal).
FP68K_NANS:
    CMPI.W	#0x2,D2                              | only the src a NaN?
    BEQ.B	FP68K_NANSRC                          | yes: it is in D4:D5 already (NANSRC) ->
    CMPI.W	#0x4,D2                              | only the dst?
    BEQ.B	FP68K_NANDST                          | yes: NANDST ->
    MOVE.L	#0xFF0000,D0                         | both: mask of the code byte
    MOVE.L	A1,D1                                | dst high half
    AND.L	D0,D1                                 | dst code
    AND.L	D4,D0                                 | src code
    CMP.L	D0,D1                                 | dst code - src code
    BLE.B	FP68K_NANSRC                          | not larger: the src NaN ->
| FP68K_NANDST: the dst NaN is the result.
FP68K_NANDST:
    ROL.B	#0x1,D6                               | the dst sign to bit 7
    MOVEA.L	A3,A4                               | dst exponent
    MOVE.L	A2,D5                                | dst significand
    MOVE.L	A1,D4                                | (high half)
| FP68K_NANSRC (Apple NANSRC/NANCOERCE) -- fit the NaN to the destination:
| an integer result gets the largest negative integer (invalid), a
| compare the result unordered, CLASS its class, a float result the NaN
| chopped to the format.
FP68K_NANSRC:
    BTST	#0x1A,D6                               | integer result (DSTINT: int16, int32, comp)?
    BEQ.B	FP68K_NANFLOAT                        | no: NANFLOAT ->
    MOVEQ.L	#0x0,D4                             | integer result of a NaN: D4 := 0 (int16 $8000, int32 $80000000, comp $80000000:0)
    MOVEQ.L	#0x1,D5                             | D5 := $80000000 ...
    ROR.L	#0x1,D5                               | ...
    BTST	#0x18,D6                               | dst format low bit (5 = int32)?
    BNE.B	FP68K_NANCOERCE_21                    | int32: $80000000 ->
    BTST	#0x19,D6                               | middle bit (6 = comp)?
    BNE.B	FP68K_NANCOERCE_41                    | comp ->
    SWAP.W	D5                                   | int16: $00008000
FP68K_NANCOERCE_21:
    BSET	#0x8,D6                                | invalid
    RTS                                         | return: int16/int32 NaN result in D5, invalid signaled
| ----------------------------------------------------------
| FP68K_NANCOERCE_41 (Apple NANCOERCE @41): comp result -- $80000000:00000000.
FP68K_NANCOERCE_41:
    EXG	D4,D5                                   | D4:D5 = $80000000:00000000
    RTS                                         | return: comp NaN $80000000:00000000 in D4:D5
| ----------------------------------------------------------
| FP68K_NANFLOAT: a floating result, or none (CMP, CLASS).
FP68K_NANFLOAT:
    BTST	#0x15,D6                               | a floating result (DSTOUT)?
    BNE.B	FP68K_FPNANOUT                        | yes: FPNANOUT ->
    BTST	#0x14,D6                               | opcode high bit (OPHIBIT): 0 compare, 1 class
    BNE.B	FP68K_NANFLOAT_5                      | CLASS ->
    MOVEQ.L	#0x2,D0                             | compare: CMPU ($02), unordered
    BRA.W	FP68K_CMPFIN                          | -> CMPFIN
| ----------------------------------------------------------
| FP68K_NANFLOAT_5 (Apple NANFLOAT @5): CLASS of a NaN -- 1 signaling (invalid
| was set by UNPACK: clear it again), 2 quiet.
FP68K_NANFLOAT_5:
    MOVEQ.L	#0x1,D0                             | class 1: signaling NaN ...
    BCLR	#0x8,D6                                | ... if UNPACK signaled invalid (clear it)
    BNE.B	FP68K_NANFLOAT_7                      | yes ->
    ADDQ.W	#0x1,D0                              | class 2: quiet NaN
FP68K_NANFLOAT_7:
    BRA.W	FP68K_CLASSFIN                        | -> CLASSFIN
| ----------------------------------------------------------
| FP68K_FPNANOUT: chop the NaN to the precision of the result;
| a NaN chopped to all-zero becomes code 21 (NANZERO).
FP68K_FPNANOUT:
    BTST	#0x1F,D6                               | single result (SPREC)?
    BEQ.B	FP68K_FPNANOUT_1                      | no ->
    MOVEQ.L	#0x0,D5                             | single: no low half ...
    MOVE.B	D5,D4                                | ... and only 24 bits
    BRA.B	FP68K_FPNANOUT_2                      | -> check for zero
| ----------------------------------------------------------
| FP68K_FPNANOUT_1 (Apple FPNANOUT @1): double result?
FP68K_FPNANOUT_1:
    BTST	#0x1E,D6                               | double result (DPREC)?
    BEQ.B	FP68K_FPNANOUT_2                      | no: extended ->
    ANDI.W	#0xF800,D5                           | double: 53 bits
FP68K_FPNANOUT_2:
    MOVE.L	D4,D0                                | significand without ...
    BCLR	#0x1E,D0                               | ... the quiet bit ...
    OR.L	D5,D0                                  | ... all zero?
    BNE.B	FP68K_FPNANOUT_3                      | no ->
    MOVEQ.L	#0x15,D4                            | NaN code 21 (NANZERO) ...
    SWAP.W	D4                                   | ... in bits 16-23
    BSET	#0x1E,D4                               | quiet
FP68K_FPNANOUT_3:
    RTS                                         | return: NaN cut to the destination precision, never all-zero (FPNANOUT)
| ----------------------------------------------------------
| FP68K_RDSTSGN: result := the dst operand with its sign;
| FP68K_RDST: the dst without its sign; FP68K_RSRCSGN (RSRC):
| the src, which is in D4:D5/A4 already. Case routines for "the result
| is one of the operands".
FP68K_RDSTSGN:
    ADD.B	D6,D6                                 | the dst sign (bit 6) to bit 7
FP68K_RDST:
    MOVE.L	A1,D4                                | result := the dst significand ...
    MOVE.L	A2,D5                                | ...
    MOVEA.L	A3,A4                               | ... and exponent
FP68K_RSRCSGN:
    RTS                                         | return (RSRC: the src is the result already)
| ----------------------------------------------------------
| FP68K_RTSHIFT -- shift D4:D5 right D0 bits (at most 66)
| into D7; the bits shifted out of D7 are sticky in D7 bit 0.
| FP68K_QRTSHIFT: without the limit.
FP68K_RTSHIFT:
    CMPI.W	#0x42,D0                             | more than 66 bits?
    BLS.B	FP68K_QRTSHIFT                        | no ->
    MOVE.W	#0x42,D0                             | shift 66 bits: everything sticky
FP68K_QRTSHIFT:
    LSR.L	#0x1,D4                               | QRTSHIFT: shift a 0 in
    ROXR.L	#0x1,D5                              | through the low half
    ROXR.W	#0x1,D7                              | into the round bits
    SCS.B	D1                                    | D1 = $FF if a bit fell out of D7
    OR.B	D1,D7                                  | keep it sticky
    SUBQ.W	#0x1,D0                              | count
    BNE.B	FP68K_QRTSHIFT                        | more ->
    RTS                                         | return: D4:D5 shifted right, lost bits sticky in D7 (RTSHIFT)
| ----------------------------------------------------------
| FP68K_ZNORMCOERCE -- a zero result keeps exponent 0 and
| is never coerced; anything else is normalized and coerced.
FP68K_ZNORMCOERCE:
    TST.L	D4                                    | high half 0?
    BNE.B	FP68K_NORMCOERCE                      | no ->
    TST.L	D5                                    | low half 0?
    BNE.B	FP68K_NORMCOERCE                      | no ->
    TST.W	D7                                    | round bits 0 too?
    BNE.B	FP68K_NORMCOERCE                      | no ->
    SUBA.L	A4,A4                                | zero: exponent 0
    RTS                                         | return: zero result (A4 = 0), no coercion (ZNORMCOERCE)
| ----------------------------------------------------------
| FP68K_NORMCOERCE: normalize a nonzero D4:D5:D7 (shift left,
| exponent - 1), then COERCE.
| Called by: FP68K_ZNORMCOERCE, FP68K_SUBMAG_7, FP68K_BOTH32
FP68K_NORMCOERCE:
    TST.L	D4                                    | leading 1?
    BRA.B	FP68K_NORMCOERCE_2                    | -> test
| ----------------------------------------------------------
|
| FP68K_NORMCOERCE_1: normalize loop - left-shift until MSB set
|
FP68K_NORMCOERCE_1:
    SUBQ.L	#0x1,A4                              | exponent - 1
    ADD.W	D7,D7                                 | shift D4:D5:D7 left
    ADDX.L	D5,D5                                | ...
    ADDX.L	D4,D4                                | ...
FP68K_NORMCOERCE_2:
    BPL.B	FP68K_NORMCOERCE_1                    | until normalized, then COERCE
| FP68K_COERCE -- round the result D4:D5/A4 (round bits in
| D7) to the precision of the operation: single and double have their
| own sequences (SCOERCE, DCOERCE); for extended: underflow check
| (UFLOW, threshold exponent 0), round (ROUND), overflow check (OFLOW,
| threshold $7FFE; "huge" = the largest finite value when the rounding
| direction demands it instead of infinity).
| Called by: FP68K_ADDNUM_15, FP68K_ADDD0, FP68K_DIVNUM_9, FP68K_CVT2E, FP68K_COMINT (and 2 more)
FP68K_COERCE:
    TST.L	D6                                    | single precision (bit 31)?
    BMI.W	FP68K_SCOERCE                         | yes: SCOERCE ->
    BTST	#0x1E,D6                               | double precision?
    BNE.W	FP68K_DCOERCE                         | yes: DCOERCE ->
    SUBA.L	A3,A3                                | extended underflow threshold: exponent 0
    BSR.B	FP68K_UFLOW                           | UFLOW
    MOVEQ.L	#0x0,D1                             | D1:D2 = 0:1: rounding increment = LSB of an extended
    MOVEQ.L	#0x1,D2                             | (low half 1)
    BTST	#0x0,D5                                | Z = NOT LSB for ROUND
    BSR.B	FP68K_ROUND                           | ROUND
    MOVEA.W	#0x7FFE,A3                          | extended overflow threshold
    BSR.B	FP68K_OFLOW                           | OFLOW
    BEQ.B	FP68K_COERCE_1                        | EQ: keep the value (or infinity) ->
    MOVEA.L	A3,A4                               | huge: the largest finite extended
    MOVEQ.L	#-0x1,D4                            | significand all ones
    MOVE.L	D4,D5                                | (low half)
FP68K_COERCE_1:
    RTS                                         | return: rounded extended in D4:D5/A4 (COERCE)
| ----------------------------------------------------------
| FP68K_UFLOW -- if the exponent A4 is below the threshold
| A3, signal underflow and denormalize: shift right to exponent A3. (The
| signal is withdrawn by ROUND if the result is exact.)
FP68K_UFLOW:
    MOVE.L	A3,D0                                | threshold ...
    SUB.L	A4,D0                                 | ... - exponent
    BGT.B	FP68K_UFLOW_1                         | below the threshold: tiny ->
    RTS                                         | not tiny: return
| ----------------------------------------------------------
| FP68K_UFLOW_1 (Apple UFLOW @1): tiny result.
FP68K_UFLOW_1:
    BSET	#0x9,D6                                | signal underflow (ERRU)
    MOVEA.L	A3,A4                               | exponent := threshold
    BRA.B	FP68K_RTSHIFT                         | shift right threshold - exponent bits (RTSHIFT)
| ----------------------------------------------------------
| FP68K_ROUND -- round D4:D5 by the guard and sticky bits
| in D7.W; Z = NOT LSB on entry (BTST by the caller), D1:D2 = the
| increment for one LSB. Exact: clear the underflow signal; else signal
| inexact and round by the direction in the environment.
FP68K_ROUND:
    SNE.B	D0                                    | D0 = $FF if the LSB is 1
    TST.W	D7                                    | any round or sticky bits?
    BNE.B	FP68K_ROUND_1                         | yes: inexact ->
    BCLR	#0x9,D6                                | exact: no underflow signal (clear ERRU)
    RTS                                         | return: exact, nothing to round (ROUND)
| ----------------------------------------------------------
| FP68K_ROUND_1 (Apple ROUND @1): inexact -- by rounding direction.
FP68K_ROUND_1:
    BSET	#0xC,D6                                | signal inexact (ERRX)
    BTST	#0x5,(A0)                              | rounding direction low bit (RNDLO)?
    BEQ.B	FP68K_ROUND_5                         | 00 nearest or 10 downward ->
    BTST	#0x6,(A0)                              | high bit (RNDHI)?
    BEQ.B	FP68K_ROUND_3                         | 01 upward ->
    RTS                                         | 11 toward zero: truncated already
| ----------------------------------------------------------
| FP68K_ROUND_3 (Apple ROUND @3): upward -- round up if positive.
FP68K_ROUND_3:
    TST.B	D6                                    | positive?
    BPL.B	FP68K_ROUNDUP                         | yes: round up (ROUNDUP) ->
    RTS                                         | negative: truncate
| ----------------------------------------------------------
| FP68K_ROUND_5 (Apple ROUND @5): to nearest or downward.
FP68K_ROUND_5:
    BTST	#0x6,(A0)                              | RNDHI?
    BNE.B	FP68K_ROUND_7                         | 10 downward ->
    CMPI.W	#0x8000,D7                           | nearest: the rest vs one half
    BCC.B	FP68K_ROUND_51                        | at least one half ->
    RTS                                         | below one half: truncate
| ----------------------------------------------------------
| FP68K_ROUND_51 (Apple ROUND @51): at least one half -- more: up; exactly
| one half: up only if the LSB is 1 (to even).
FP68K_ROUND_51:
    BHI.B	FP68K_ROUNDUP                         | above one half: round up ->
    TST.B	D0                                    | exactly one half: LSB 1?
    BNE.B	FP68K_ROUNDUP                         | yes: up to even ->
    RTS                                         | LSB 0: even already
| ----------------------------------------------------------
| FP68K_ROUND_7 (Apple ROUND @7): downward -- round up the magnitude if
| negative.
FP68K_ROUND_7:
    TST.B	D6                                    | negative?
    BMI.B	FP68K_ROUNDUP                         | yes: round the magnitude up ->
    RTS                                         | positive: truncate
| ----------------------------------------------------------
| FP68K_ROUNDUP -- add the increment D1:D2; a carry out shifts
| right and bumps the exponent; RNDINC records the increment.
FP68K_ROUNDUP:
    BSET	#0x7,0x1(A0)                           | RNDINC: the last rounding went up
    ADD.L	D2,D5                                 | add the increment D1:D2
    ADDX.L	D1,D4                                | (high half)
    BCC.B	FP68K_ROUNDUP_9                       | no carry out ->
    ROXR.L	#0x1,D4                              | carry: shift it back in
    ADDQ.L	#0x1,A4                              | exponent + 1
FP68K_ROUNDUP_9:
    RTS                                         | return: significand rounded up, carry into the exponent (ROUNDUP)
| ----------------------------------------------------------
| FP68K_OFLOW -- if the exponent A4 is above the threshold
| A3: signal overflow and inexact, result infinity; returns EQ to keep
| infinity, NE if the largest finite value ("huge") must be stored
| instead (toward zero, or directed away from the sign).
FP68K_OFLOW:
    CMPA.L	A4,A3                                | threshold - exponent
    BLT.B	FP68K_OFLOW_1                         | above the threshold: overflow ->
    CLR.W	D0                                    | EQ: no overflow
    RTS                                         | return EQ: no overflow (OFLOW)
FP68K_OFLOW_1:
    BSET	#0xA,D6                                | signal overflow (ERRO)
    BSET	#0xC,D6                                | and inexact
    MOVEA.W	#0x7FFF,A4                          | infinity, with the sign of the result
    MOVEQ.L	#0x0,D4                             | D4 := 0: significand of infinity
    MOVE.L	D4,D5                                | (low half)
    MOVE.B	(A0),D1                              | rounding direction ...
    ANDI.B	#0x60,D1                             | ... bits 5-6
    BNE.B	FP68K_OFLOW_2                         | directed ->
    RTS                                         | nearest: return EQ, infinity
| ----------------------------------------------------------
| FP68K_OFLOW_2 (Apple OFLOW @2): directed rounding.
FP68K_OFLOW_2:
    CMPI.B	#0x60,D1                             | toward zero?
    BNE.B	FP68K_OFLOW_4                         | no: upward or downward ->
    TST.B	D1                                    | NE: huge
    RTS                                         | return NE: toward zero gives the largest finite value
| ----------------------------------------------------------
| FP68K_OFLOW_4 (Apple OFLOW @4): upward or downward -- depends on the sign.
FP68K_OFLOW_4:
    TST.B	D6                                    | sign of the result
    BMI.B	FP68K_OFLOW_5                         | negative ->
    CMPI.B	#0x20,D1                             | positive: EQ (infinity) if upward, else NE (huge)
    RTS                                         | return
| ----------------------------------------------------------
| FP68K_OFLOW_5 (Apple OFLOW @5): negative overflow.
FP68K_OFLOW_5:
    CMPI.B	#0x40,D1                             | negative: EQ (-infinity) if downward, else NE (huge)
    RTS                                         | return EQ (keep -inf) only if rounding downward
| ----------------------------------------------------------
| FP68K_SCOERCE -- coerce to single: underflow threshold
| $3F81, 24-bit significand (bits below into the sticky bits), increment
| $100, overflow threshold $407E, huge = 24 ones.
FP68K_SCOERCE:
    MOVEA.W	#0x3F81,A3                          | single underflow threshold
    BSR.W	FP68K_UFLOW                           | UFLOW
    TST.L	D5                                    | any bits in the low half?
    SNE.B	D0                                    | D0 = $FF if so
    OR.B	D0,D7                                  | sticky
    ADD.B	D4,D4                                 | bit 7 of D4 (the guard bit) to X
    ROXR.W	#0x1,D7                              | X into the guard position of D7
    OR.B	D4,D7                                  | the other low bits: sticky
    MOVEQ.L	#0x0,D5                             | D5 := 0: a single has no low significand bits (SCOERCE)
    CLR.B	D4                                    | clear the 8 bits below the 24-bit significand
    MOVE.L	#0x100,D1                            | D1:D2 = $100:0: rounding increment = LSB of a single
    MOVEQ.L	#0x0,D2                             | low half of the increment = 0
    BTST	#0x8,D4                                | Z = NOT LSB (bit 8)
    BSR.W	FP68K_ROUND                           | ROUND
    MOVEA.W	#0x407E,A3                          | single overflow threshold
    BSR.B	FP68K_OFLOW                           | OFLOW
    BEQ.B	FP68K_SCOERCE_3                       | EQ ->
    MOVEA.L	A3,A4                               | huge: the largest finite single
    MOVEQ.L	#-0x1,D4                            | 24 ones ...
    CLR.B	D4                                    | ... (low byte 0)
FP68K_SCOERCE_3:
    RTS                                         | return: rounded single in D4/A4 (SCOERCE)
| ----------------------------------------------------------
| FP68K_DCOERCE -- coerce to double: underflow threshold
| $3C01, 53-bit significand, increment $800 in D5, overflow threshold
| $43FE, huge = 53 ones.
FP68K_DCOERCE:
    MOVEA.W	#0x3C01,A3                          | double underflow threshold
    BSR.W	FP68K_UFLOW                           | UFLOW
    MOVE.W	#0x7FF,D0                            | the 11 bits below a double ...
    AND.W	D5,D0                                 | ...
    ANDI.W	#0xF800,D5                           | ... cleared in the significand
    LSL.W	#0x5,D0                               | and left-aligned
    LSR.W	#0x1,D7                               | make room for the guard bit
    BCC.B	FP68K_DCOERCE_1                       | no stray sticky bit ->
    BSET	#0x0,D7                                | keep it
FP68K_DCOERCE_1:
    OR.W	D0,D7                                  | the 11 bits into the round bits
    MOVEQ.L	#0x0,D1                             | D1:D2 = 0:$800: rounding increment = LSB of a double (DCOERCE)
    MOVE.L	#0x800,D2                            | (low half $800)
    BTST	#0xB,D5                                | Z = NOT LSB (bit 11)
    BSR.W	FP68K_ROUND                           | ROUND
    MOVEA.W	#0x43FE,A3                          | double overflow threshold
    BSR.W	FP68K_OFLOW                           | OFLOW
    BEQ.B	FP68K_DCOERCE_5                       | EQ ->
    MOVEA.L	A3,A4                               | huge: the largest finite double
    MOVEQ.L	#-0x1,D4                            | 53 ones: 32 ...
    MOVE.L	#0xFFFFF800,D5                       | ... and 21
FP68K_DCOERCE_5:
    RTS                                         | return: rounded double in D4:D5/A4 (DCOERCE)
| ----------------------------------------------------------
| FP68K_PACK -- store the result (sign D6 bit 7, exponent
| A4, significand D4:D5) at the dst address in the format code * 2 in
| D0; EQ on entry to the format routine means infinity or NaN.
FP68K_PACK:
    ANDI.W	#0xE,D0                              | D0 = format * 2
    MOVE.W	FP68K_PACKCASE(PC,D0.W),D0           | offset of the format's routine (PACKCASE)
    MOVEA.L	0xA(A6),A3                          | A3 = address 1, the destination
    MOVE.W	A4,D3                                | D3 = exponent
    CMPI.W	#0x7FFF,D3                           | EQ: infinity or NaN
    JMP	FP68K_PACK(PC,D0.W)                     | -> the format routine
| FP68K_PACKCASE: pack routine per format, offsets from
| FP68K_PACK.
FP68K_PACKCASE:
    .short	FP68K_PACKEXT-FP68K_PACK             | format 0 extended (PACKEXT)
    .short	FP68K_PACKDBL-FP68K_PACK             | format 1 double (PACKDBL)
    .short	FP68K_PACKSGL-FP68K_PACK             | format 2 single (PACKSGL)
    .short	0                                    | format 3: not used
    .short	FP68K_PACKI16-FP68K_PACK             | format 4 int16 (PACKI16)
    .short	FP68K_PACKI32-FP68K_PACK             | format 5 int32 (PACKI32)
    .short	FP68K_PACKC64-FP68K_PACK             | format 6 comp (PACKC64)
| FP68K_PACKI16: int16.
FP68K_PACKI16:
    MOVE.W	D5,(A3)                              | store the 16-bit integer result (PACKI16)
    RTS                                         | return: int16 stored
| ----------------------------------------------------------
| FP68K_PACKI32: int32.
FP68K_PACKI32:
    MOVE.L	D5,(A3)                              | store 32-bit long integer result
    RTS                                         | return: int32 stored (PACKI32)
| ----------------------------------------------------------
| FP68K_PACKC64: comp.
FP68K_PACKC64:
    MOVE.L	D4,(A3)+                             | store comp high 32 bits
    MOVE.L	D5,(A3)                              | store comp low 32 bits
    RTS                                         | return: comp stored (PACKC64)
| ----------------------------------------------------------
| FP68K_PACKEXT: extended -- an underflowed (single or
| double precision control) denormal is normalized again first.
FP68K_PACKEXT:
    BTST	#0x9,D6                                | underflow signaled (an S/D denormal)?
    BEQ.B	FP68K_PACKEXT_7                       | no: store ->
    TST.W	D3                                    | exponent 0?
    BEQ.B	FP68K_PACKEXT_7                       | yes: an extended denormal as it is ->
    TST.L	D4                                    | normalize it again: high half
    BNE.B	FP68K_PACKEXT_5                       | nonzero ->
    TST.L	D5                                    | low half
    BNE.B	FP68K_PACKEXT_1                       | nonzero: unnormal by more than 32 bits ->
    MOVEQ.L	#0x0,D3                             | zero significand: biased exponent 0 (a true zero)
    BRA.B	FP68K_PACKEXT_7                       | -> store
| ----------------------------------------------------------
| FP68K_PACKEXT_1 (Apple PACKEXT @1): normalize.
FP68K_PACKEXT_1:
    SUBQ.W	#0x1,D3                              | exponent - 1
    ADD.L	D5,D5                                 | significand * 2
    ADDX.L	D4,D4                                | (high half)
FP68K_PACKEXT_5:
    BPL.B	FP68K_PACKEXT_1                       | until normalized
FP68K_PACKEXT_7:
    TST.B	D6                                    | negative?
    BPL.B	FP68K_PACKEXT_11                      | no ->
    ADDI.W	#0x8000,D3                           | sign bit into the exponent word
FP68K_PACKEXT_11:
    MOVE.W	D3,(A3)+                             | sign and exponent
    MOVE.L	D4,(A3)+                             | significand high
    MOVE.L	D5,(A3)                              | significand low
    RTS                                         | return: 10-byte extended stored (PACKEXT)
| ----------------------------------------------------------
| FP68K_PACKSGL: single -- exponent rebiased, the integer
| bit dropped (a denormal decrements the exponent to 0), sign inserted;
| infinity and NaN get an exponent that becomes $FF.
FP68K_PACKSGL:
    BNE.B	FP68K_PACKSGL_1                       | finite ->
    MOVE.W	#0x4080,D3                           | infinity/NaN: becomes exponent $FF (decremented: no integer bit)
    BRA.B	FP68K_PACKSGL_5                       | -> pack
| ----------------------------------------------------------
| FP68K_PACKSGL_1 (Apple PACKSGL @1): finite.
FP68K_PACKSGL_1:
    TST.W	D3                                    | exponent 0?
    BNE.B	FP68K_PACKSGL_5                       | no ->
    MOVE.W	#0x3F81,D3                           | zero: the denormal exponent (becomes 0)
FP68K_PACKSGL_5:
    SUBI.W	#0x3F80,D3                           | rebias: $3FFF -> $7F
    ADD.L	D4,D4                                 | drop the integer bit
    BCS.B	FP68K_PACKSGL_7                       | it was 1: normal ->
    SUBQ.W	#0x1,D3                              | denormal (or zero): exponent - 1 = 0
FP68K_PACKSGL_7:
    OR.W	D3,D4                                  | exponent into the low bits
    ROR.L	#0x8,D4                               | rotate into place
    ADD.B	D6,D6                                 | sign to X
    ROXR.L	#0x1,D4                              | insert the sign
    MOVE.L	D4,(A3)                              | store the single
    RTS                                         | return: single stored (PACKSGL)
| ----------------------------------------------------------
| FP68K_PACKDBL: double -- likewise with 11 exponent bits,
| the significand shifted right by 11.
FP68K_PACKDBL:
    BNE.B	FP68K_PACKDBL_1                       | finite ->
    MOVE.W	#0x4400,D3                           | infinity/NaN: becomes exponent $7FF
    BRA.B	FP68K_PACKDBL_5                       | -> pack
| ----------------------------------------------------------
| FP68K_PACKDBL_1 (Apple PACKDBL @1): finite.
FP68K_PACKDBL_1:
    TST.W	D3                                    | exponent 0?
    BNE.B	FP68K_PACKDBL_5                       | no ->
    MOVE.W	#0x3C01,D3                           | zero: the denormal exponent
FP68K_PACKDBL_5:
    SUBI.W	#0x3C00,D3                           | rebias: $3FFF -> $3FF
    TST.L	D4                                    | integer bit?
    BMI.B	FP68K_PACKDBL_7                       | set: normal ->
    SUBQ.W	#0x1,D3                              | denormal: exponent - 1 = 0
FP68K_PACKDBL_7:
    MOVE.L	#0x7FF,D0                            | the low 11 bits of the high half ...
    AND.L	D4,D0                                 | ...
    OR.L	D0,D5                                  | ... go to the low half
    ROR.L	#0x8,D5                               | rotate right by 11 ...
    ROR.L	#0x3,D5                               | ...: the low 32 bits are ready
    ANDI.W	#0xF800,D4                           | clear the bits just moved
    ADD.L	D4,D4                                 | drop the integer bit
    OR.W	D3,D4                                  | exponent into the low bits
    ROR.L	#0x8,D4                               | rotate right by 11 ...
    ROR.L	#0x3,D4                               | ...
    ADD.B	D6,D6                                 | sign to X
    ROXR.L	#0x1,D4                              | insert the sign
    MOVE.L	D4,(A3)+                             | store the double: high half
    MOVE.L	D5,(A3)                              | low half
    RTS                                         | return: double stored (PACKDBL)
| ----------------------------------------------------------
| FP68K_SUBTOP -- subtract: flip the src sign (bit 7) and
| the XOR (bit 5), then add.
FP68K_SUBTOP:
    EORI.B	#0xA0,D6                             | flip the src sign (bit 7) and the XOR (bit 5)
FP68K_ADDTOP:
    MOVE.W	FP68K_ADDCASE(PC,D3.W),D3            | ADDTOP: offset of the case routine
    JMP	FP68K_ADDTOP(PC,D3.W)                   | -> it
| FP68K_ADDCASE: case routines by the number cases of
| (dst, src), offsets from FP68K_ADDTOP.
FP68K_ADDCASE:
    .short	FP68K_ADDNUM-FP68K_ADDTOP            | num, num: ADDNUM
    .short	FP68K_ADDS0-FP68K_ADDTOP             | num, 0: ADDS0: num + 0 = the dst
    .short	FP68K_RSRCSGN-FP68K_ADDTOP           | num, inf: RSRC: num + inf = inf
    .short	FP68K_ADDD0-FP68K_ADDTOP             | 0, num: ADDD0: 0 + num = the src
    .short	FP68K_ADD00-FP68K_ADDTOP             | 0, 0: ADD00: 0 + 0
    .short	FP68K_RSRCSGN-FP68K_ADDTOP           | 0, inf: RSRC: 0 + inf = inf
    .short	FP68K_RDSTSGN-FP68K_ADDTOP           | inf, num: RDSTSGN: inf + num = inf
    .short	FP68K_RDSTSGN-FP68K_ADDTOP           | inf, 0: RDSTSGN: inf + 0 = inf
    .short	FP68K_ADDINF-FP68K_ADDTOP            | inf, inf: ADDINF: inf + inf
| FP68K_ADDNUM -- two finite nonzero numbers: the operand
| with the larger exponent to D3:A2/A4, the other shifted right in D4:D5;
| add the magnitudes (carry: shift back) or subtract (SUBMAG), coerce.
FP68K_ADDNUM:
    MOVE.L	D4,D3                                | D3 = src high (ADDX needs a data register)
    MOVE.L	A1,D4                                | D4 = dst high
    EXG	D5,A2                                   | D5 = dst low, A2 = src low
    MOVE.W	A4,D0                                | src exponent ...
    SUB.W	A3,D0                                 | ... - dst exponent
    BEQ.B	FP68K_ADDNUM_3                        | equal: no shift ->
    BGT.B	FP68K_ADDNUM_1                        | src larger: shift the dst (in D4:D5) ->
    EXG	D5,A2                                   | dst larger: swap the operands
    EXG	D4,D3                                   | (high halves)
    NEG.W	D0                                    | shift count
    MOVEA.L	A3,A4                               | the larger exponent
    ADD.B	D6,D6                                 | the dst sign to bit 7 ...
    ASR.B	#0x1,D6                               | ... XOR bit back in place
FP68K_ADDNUM_1:
    BSR.W	FP68K_RTSHIFT                         | align the smaller operand (RTSHIFT)
FP68K_ADDNUM_3:
    BTST	#0x5,D6                                | signs differ?
    BNE.B	FP68K_SUBMAG                          | yes: subtract the magnitudes ->
| same signs: add mantissas
    ADD.L	A2,D5                                 | add the magnitudes
    ADDX.L	D3,D4                                | (high halves)
    BCC.B	FP68K_ADDNUM_15                       | no carry out ->
    ROXR.L	#0x1,D4                              | carry: shift right
    ROXR.L	#0x1,D5                              | ...
    ROXR.W	#0x1,D7                              | ... (no sticky bits can be lost)
    ADDQ.L	#0x1,A4                              | exponent + 1
FP68K_ADDNUM_15:
    BRA.W	FP68K_COERCE                          | -> COERCE
| ----------------------------------------------------------
| FP68K_SUBMAG -- subtract the larger from the smaller; zero
| -> a signed zero; a borrow means the guess was wrong: negate back.
FP68K_SUBMAG:
    NOT.B	D6                                    | assume |larger| > |smaller|: flip the sign
    SUB.L	A2,D5                                 | smaller - larger
    SUBX.L	D3,D4                                | (high halves)
    BEQ.B	FP68K_ZEROSUM                         | all 64 bits 0: exact zero (ZEROSUM) ->
    BCC.B	FP68K_SUBMAG_7                        | no borrow ->
    NEG.W	D7                                    | borrow: negate the difference ...
    NEGX.L	D5                                   | ...
    NEGX.L	D4                                   | ...
    NOT.B	D6                                    | ... and flip the sign back
FP68K_SUBMAG_7:
    BRA.W	FP68K_NORMCOERCE                      | -> NORMCOERCE
| ----------------------------------------------------------
| FP68K_ADD00 -- 0 + 0: signs equal: that zero; else +0,
| or -0 when rounding downward. FP68K_ZEROSUM: an exact zero sum.
FP68K_ADD00:
    BTST	#0x5,D6                                | signs differ?
    BEQ.B	FP68K_ADDQ00                          | no: that zero ->
FP68K_ZEROSUM:
    SUBA.L	A4,A4                                | exponent 0
    CLR.B	D6                                    | +0 ...
    BTST	#0x6,(A0)                              | ... unless rounding downward (10)
    BEQ.B	FP68K_ADDQ00                          | no -> positive zero
    BTST	#0x5,(A0)                              | RNDLO set: toward zero (11)?
    BNE.B	FP68K_ADDQ00                          | yes: +0 ->
    NOT.B	D6                                    | downward: -0
FP68K_ADDQ00:
    RTS                                         | return: zero sum, not coerced (ADDQ00)
| ----------------------------------------------------------
| FP68K_ADDS0: num + 0 -- the result is the dst; then
| coerce. FP68K_ADDD0: 0 + num -- the src; coerce.
FP68K_ADDS0:
    MOVE.L	A2,D5                                | result := the dst (low half)
    MOVE.L	A1,D4                                | (high half)
    MOVEA.L	A3,A4                               | (exponent)
    ADD.B	D6,D6                                 | with the dst sign (bit 6 -> 7)
FP68K_ADDD0:
    BRA.W	FP68K_COERCE                          | ADDD0: -> COERCE
| ----------------------------------------------------------
| FP68K_ADDINF: inf + inf -- equal signs: inf; else invalid.
FP68K_ADDINF:
    BTST	#0x5,D6                                | signs differ?
    BNE.B	FP68K_ADDINF_25                       | yes: invalid ->
    RTS                                         | no: infinity
| ----------------------------------------------------------
| FP68K_ADDINF_25 (Apple ADDINF @25): +inf + -inf: invalid, NaN code 2
| (NANADD).
FP68K_ADDINF_25:
    MOVEQ.L	#0x2,D0                             | NaN code 2 (NANADD)
    BRA.W	FP68K_INVALIDOP                       | -> INVALIDOP
| ----------------------------------------------------------
| FP68K_MULTOP -- multiply: sign = XOR of the signs, NaN code
| 8 (NANMUL) in case of 0 * inf; dispatch by the number cases.
FP68K_MULTOP:
    ROL.B	#0x2,D6                               | XOR of the signs (bit 5) to bit 7: the result sign
    MOVEQ.L	#0x8,D0                             | NaN code 8 (NANMUL), for 0 * inf
    MOVE.W	FP68K_MULCASE(PC,D3.W),D3            | offset of the case routine
    JMP	FP68K_MULTOP(PC,D3.W)                   | -> it
| FP68K_MULCASE: case routines by (dst, src), offsets from
| FP68K_MULTOP.
FP68K_MULCASE:
    .short	FP68K_MULNUM-FP68K_MULTOP            | num, num: MULNUM
    .short	FP68K_RSRCSGN-FP68K_MULTOP           | num, 0: RSRC: num * 0 = 0
    .short	FP68K_RSRCSGN-FP68K_MULTOP           | num, inf: RSRC: num * inf = inf
    .short	FP68K_RDST-FP68K_MULTOP              | 0, num: RDST: 0 * num = 0
    .short	FP68K_RSRCSGN-FP68K_MULTOP           | 0, 0: RSRC: 0 * 0 = 0
    .short	FP68K_INVALIDOP-FP68K_MULTOP         | 0, inf: INVALIDOP: 0 * inf
    .short	FP68K_RDST-FP68K_MULTOP              | inf, num: RDST: inf * num = inf
    .short	FP68K_INVALIDOP-FP68K_MULTOP         | inf, 0: INVALIDOP: inf * 0
    .short	FP68K_RSRCSGN-FP68K_MULTOP           | inf, inf: RSRC: inf * inf = inf
| FP68K_MULNUM -- two finite nonzero numbers: exponent =
| sum - ($3FFF - 1); the 64 x 64 bit product from four 32 x 32 products
| (MULU32), with shortcuts when the low halves are 0 (SRC32, BOTH32);
| the low 64 bits only feed the sticky bits. A0 counts carries.
FP68K_MULNUM:
    ADDA.L	A3,A4                                | exponent sum ...
    SUBA.W	#0x3FFE,A4                           | ... - (bias - 1): the point is right of the 2 leading product bits
    MOVEM.L	D5-D6/A0,-(SP)                      | save src low, D6, A0 (A0 counts carries)
    MOVEA.L	D4,A3                               | A3 = src high
    MOVEQ.L	#0x0,D4                             | D4 := 0: clear the product D4:D5 (and A0, the carry count)
    MOVE.L	D4,D5                                | (low half)
    MOVEA.L	D4,A0                               | A0 := 0: carries out of D4
    MOVE.L	(SP),D1                              | D1 = src low
    BNE.B	FP68K_SRC64                           | nonzero: 64-bit src (SRC64) ->
    MOVE.L	A2,D0                                | D0 = dst low
    BEQ.B	FP68K_BOTH32                          | both low halves 0: one 32 x 32 product (BOTH32) ->
    BRA.B	FP68K_SRC32                           | 64 x 32 (SRC32) ->
FP68K_SRC64:
    MOVE.L	A2,D0                                | SRC64: dst low ...
    BSR.B	FP68K_MULU32                          | ... * src low (MULU32)
    TST.L	D5                                    | its low 32 bits ...
    SNE.B	D7                                    | ... only sticky
    MOVE.L	D4,D5                                | shift the product right 32 bits
    MOVEQ.L	#0x0,D4                             | low partial product shifted down 32 bits: D4 := 0
    MOVE.L	(SP),D1                              | src low ...
    MOVE.L	A1,D0                                | ... * dst high
    BSR.B	FP68K_MULU32                          | MULU32
FP68K_SRC32:
    MOVE.L	A3,D1                                | SRC32: src high ...
    MOVE.L	A2,D0                                | ... * dst low
    BSR.B	FP68K_MULU32                          | MULU32
    TST.W	D5                                    | more sticky bits ...
    SNE.B	D0                                    | ...
    OR.B	D0,D7                                  | ... on top of the earlier ones
    SWAP.W	D5                                   | the next 16 bits ...
    OR.W	D5,D7                                  | ... become the round bits
    MOVE.L	D4,D5                                | shift right 32 bits
    MOVE.L	A0,D4                                | the carries
FP68K_BOTH32:
    MOVE.L	A3,D1                                | BOTH32: src high ...
    MOVE.L	A1,D0                                | ... * dst high
    BSR.B	FP68K_MULU32                          | MULU32
    MOVEM.L	(SP)+,D0/D6/A0                      | restore D6, A0 (D0 = the saved src low, discarded)
    BRA.W	FP68K_NORMCOERCE                      | -> NORMCOERCE
| ----------------------------------------------------------
| FP68K_MULU32 -- D4:D5 += D0 * D1 (32 x 32 bits, from four
| 16 x 16 MULUs), a carry out of D4 increments A0. Uses D2, D3, D6.
FP68K_MULU32:
    MOVE.W	D1,D2                                | Y (D0 = A:B, D1 = X:Y)
    MOVE.W	D1,D3                                | Y
    MULU.W	D0,D2                                | D2 = B * Y
    MOVE.W	D0,D6                                | B
    SWAP.W	D0                                   | A
    SWAP.W	D1                                   | X
    MULU.W	D1,D6                                | D6 = B * X
    MULU.W	D0,D3                                | D3 = A * Y
    MULU.W	D0,D1                                | D1 = A * X
    SWAP.W	D2                                   | (B * Y).hi to the low word
    MOVEQ.L	#0x0,D0                             | D0 := 0: (B*Y).hi zero-extended into it next (MULU32)
    MOVE.W	D2,D0                                | D0 = (B * Y).hi
    ADD.L	D0,D3                                 | A * Y + (B * Y).hi: no carry possible
    ADD.L	D6,D3                                 | + B * X; the carry stays in X
    MOVE.W	D3,D2                                | low word of the sum ...
    SWAP.W	D2                                   | ... above (B * Y).lo: D2 = low 32 bits of the product
    CLR.W	D3                                    | replace the low half of the sum ...
    ADDX.W	D3,D3                                | ... by the carry X
    SWAP.W	D3                                   | D3 = carry:sum.hi
    ADD.L	D3,D1                                 | D1 = high 32 bits of the product
    ADD.L	D2,D5                                 | add the product to D4:D5
    ADDX.L	D1,D4                                | (high half)
    BCC.B	FP68K_MULU32_1                        | no carry out ->
    ADDQ.W	#0x1,A0                              | count the carry
FP68K_MULU32_1:
    RTS                                         | return: 32x32 product added into D4:D5, carry-out counted in A0
| ----------------------------------------------------------
| FP68K_DIVTOP -- divide: sign = XOR of the signs, NaN code
| 4 (NANDIV); dispatch by the number cases.
FP68K_DIVTOP:
    ROL.B	#0x2,D6                               | XOR of the signs to bit 7: the result sign
    MOVEQ.L	#0x4,D0                             | NaN code 4 (NANDIV), for 0/0 and inf/inf
    MOVE.W	FP68K_DIVCASE(PC,D3.W),D3            | offset of the case routine
    JMP	FP68K_DIVTOP(PC,D3.W)                   | -> it
| FP68K_DIVCASE: case routines by (dst, src), offsets from
| FP68K_DIVTOP.
FP68K_DIVCASE:
    .short	FP68K_DIVNUM-FP68K_DIVTOP            | num, num: DIVNUM
    .short	FP68K_DIVBY0-FP68K_DIVTOP            | num, 0: DIVBY0: num / 0 = inf
    .short	FP68K_DIVBYI-FP68K_DIVTOP            | num, inf: DIVBYI: num / inf = 0
    .short	FP68K_RDST-FP68K_DIVTOP              | 0, num: RDST: 0 / num = 0
    .short	FP68K_INVALIDOP-FP68K_DIVTOP         | 0, 0: INVALIDOP: 0 / 0
    .short	FP68K_RDST-FP68K_DIVTOP              | 0, inf: RDST: 0 / inf = 0
    .short	FP68K_RDST-FP68K_DIVTOP              | inf, num: RDST: inf / num = inf
    .short	FP68K_RDST-FP68K_DIVTOP              | inf, 0: RDST: inf / 0 = inf
    .short	FP68K_INVALIDOP-FP68K_DIVTOP         | inf, inf: INVALIDOP: inf / inf
| FP68K_DIVBY0: num / 0 -- divide by zero, infinity.
FP68K_DIVBY0:
    BSET	#0xB,D6                                | signal divide by zero (ERRZ)
    MOVEA.W	#0x7FFF,A4                          | infinity
    MOVEQ.L	#0x0,D4                             | D4 := 0: significand of infinity (x / 0)
    MOVE.L	D4,D5                                | (low half)
    RTS                                         | return: infinity, division by zero signaled (DIVBY0)
| ----------------------------------------------------------
| FP68K_DIVBYI: num / inf -- zero.
FP68K_DIVBYI:
    SUBA.L	A4,A4                                | zero: exponent 0
    MOVE.L	A4,D4                                | significand 0
    MOVE.L	D4,D5                                | (low half)
    RTS                                         | return: zero (finite / infinity, DIVBYI)
| ----------------------------------------------------------
| FP68K_DIVNUM -- two finite nonzero numbers: exponent =
| difference + $3FFF; 65 quotient bits by restoring division (33 for a
| single operation), one more if the dividend is smaller; the remainder
| gives the sticky bit; coerce.
FP68K_DIVNUM:
    EXG	A3,A4                                   | A4 = dst exponent, A3 = src exponent
    SUBA.L	A3,A4                                | difference
    ADDA.W	#0x3FFF,A4                           | rebias
    MOVEQ.L	#0x41,D0                            | 65 quotient bits (the last one for rounding)
    TST.L	D6                                    | single operation?
    BPL.B	FP68K_DIVNUM_3                        | no ->
    MOVEQ.L	#0x21,D0                            | single: 33 bits
FP68K_DIVNUM_3:
    CMP.L	A1,D4                                 | divisor - dividend (high halves)
    BNE.B	FP68K_DIVNUM_5                        | ...
    CMP.L	A2,D5                                 | (low halves)
FP68K_DIVNUM_5:
    BLS.B	FP68K_DIVNUM_7                        | divisor <= dividend ->
    ADDQ.W	#0x1,D0                              | dividend smaller: one more quotient bit ...
    SUBQ.L	#0x1,A4                              | ... and exponent - 1
FP68K_DIVNUM_7:
    MOVE.L	A1,D1                                | D1:D2 = dividend (dst)
    MOVE.L	A2,D2                                | (low half)
    MOVE.L	D4,D3                                | D3:A2 = divisor (src)
    MOVEA.L	D5,A2                               | (low half)
    BSR.B	FP68K_RESTORE                         | RESTORE: quotient in D4:D5, remainder in D1:D2
    TST.L	D6                                    | single operation?
    BPL.B	FP68K_DIVNUM_9                        | no ->
    MOVE.L	D5,D4                                | single: left-align the 32-bit quotient
    MOVEQ.L	#0x0,D5                             | single: 32 quotient bits now in D4, D5 := 0
FP68K_DIVNUM_9:
    MOVE.W	#0x10,CCR                            | X := 1: the leading quotient bit, shifted out ...
    ROXR.L	#0x1,D4                              | ... comes back in, the last bit becomes the round bit
    ROXR.L	#0x1,D5                              | ...
    ROXR.W	#0x1,D7                              | ...
    OR.L	D2,D1                                  | remainder nonzero ...
    SNE.B	D7                                    | ... sticky
    BRA.W	FP68K_COERCE                          | -> COERCE
| ----------------------------------------------------------
| FP68K_RESTORE -- restoring division: D0 quotient bits of
| D1:D2 / D3:A2 into D4:D5 (the leading ones are shifted out), remainder
| left in D1:D2. Also used by REM and binary-to-decimal.
| Called by: FP68K_DIVNUM, FP68K_REMDIV, FP68K_BD9_7.
FP68K_RESTORE:
    MOVEQ.L	#0x0,D4                             | D4 := 0: clear the quotient D4:D5 (RESTORE)
    MOVE.L	D4,D5                                | (low half)
    BRA.B	FP68K_RESTORE_2                       | no shift before the first step
| ----------------------------------------------------------
| FP68K_RESTORE_1 (Apple RESTORE @1): shift quotient and remainder left.
FP68K_RESTORE_1:
    ADD.L	D5,D5                                 | quotient * 2
    ADDX.L	D4,D4                                | (carry out ignored)
    ADD.L	D2,D2                                 | remainder * 2
    ADDX.L	D1,D1                                | (high half)
    BCS.B	FP68K_RESTORE_4                       | carry out: certainly >= divisor ->
FP68K_RESTORE_2:
    CMP.L	D3,D1                                 | remainder - divisor (high halves)
    BNE.B	FP68K_RESTORE_3                       | ...
    CMP.L	A2,D2                                 | (low halves)
FP68K_RESTORE_3:
    BCS.B	FP68K_RESTORE_5                       | smaller: quotient bit 0 ->
FP68K_RESTORE_4:
    ADDQ.B	#0x1,D5                              | quotient bit 1
    SUB.L	A2,D2                                 | remainder - divisor
    SUBX.L	D3,D1                                | (high halves)
FP68K_RESTORE_5:
    SUBQ.W	#0x1,D0                              | count
    BNE.B	FP68K_RESTORE_1                       | more bits ->
    RTS                                         | return: quotient in D4:D5, remainder in D1:D2
| ----------------------------------------------------------
| FP68K_REMTOP -- IEEE remainder dst REM src, at most half
| the divisor in magnitude; the low 7 bits of the integer quotient, with
| its sign, go to the caller in D0 (the saved D0.W at 6(SP)). Precision
| control is not applied. NaN code 9 (NANREM).
FP68K_REMTOP:
    CLR.W	0x6(SP)                               | quotient := 0 (the saved D0.W)
    ADD.B	D6,D6                                 | dst sign to bit 7 (the result's), the quotient sign to bit 6
    MOVEQ.L	#0x9,D0                             | NaN code 9 (NANREM)
    ANDI.L	#0x3FFFFFFF,D6                       | no precision control: extended (P754)
    MOVE.W	FP68K_REMCASE(PC,D3.W),D3            | offset of the case routine
    JMP	FP68K_REMTOP(PC,D3.W)                   | -> it
| FP68K_REMCASE: case routines by (dst, src), offsets from
| FP68K_REMTOP.
FP68K_REMCASE:
    .short	FP68K_REMNUM-FP68K_REMTOP            | num, num: REMNUM
    .short	FP68K_INVALIDOP-FP68K_REMTOP         | num, 0: INVALIDOP: num rem 0
    .short	FP68K_REMDST-FP68K_REMTOP            | num, inf: REMDST: num rem inf = num
    .short	FP68K_RDST-FP68K_REMTOP              | 0, num: RDST: 0 rem num = 0
    .short	FP68K_INVALIDOP-FP68K_REMTOP         | 0, 0: INVALIDOP: 0 rem 0
    .short	FP68K_RDST-FP68K_REMTOP              | 0, inf: RDST: 0 rem inf = 0
    .short	FP68K_INVALIDOP-FP68K_REMTOP         | inf, num: INVALIDOP: inf rem num
    .short	FP68K_INVALIDOP-FP68K_REMTOP         | inf, 0: INVALIDOP: inf rem 0
    .short	FP68K_INVALIDOP-FP68K_REMTOP         | inf, inf: INVALIDOP: inf rem inf
| FP68K_REMNUM: finite / finite -- DEXP - SEXP + 2 quotient
| bits are needed; none: the dst is the remainder.
FP68K_REMNUM:
    MOVE.L	A3,D0                                | dst exponent ...
    ADDQ.L	#0x2,D0                              | ...
    SUB.L	A4,D0                                 | ... - src exponent + 2: quotient bits to compute
    BGT.B	FP68K_REMDIV                          | some: divide (REMDIV) ->
| FP68K_REMDST: the dst is the remainder.
FP68K_REMDST:
    MOVE.L	A1,D4                                | result := the dst
    MOVE.L	A2,D5                                | ...
    MOVEA.L	A3,A4                               | ...
    BRA.B	FP68K_REMFIN                          | -> REMFIN
| ----------------------------------------------------------
| FP68K_REMDIV -- divide through the first fraction bit;
| low quotient bit 1 and remainder > 0 (or = 0 with an odd quotient): the
| remainder becomes divisor - remainder with the sign flipped and the
| quotient + 1.
FP68K_REMDIV:
    SUBQ.L	#0x1,A4                              | remainder exponent: src - 1 (at most half the divisor)
    MOVE.L	A1,D1                                | dividend: the dst
    MOVE.L	A2,D2                                | ...
    MOVE.L	D4,D3                                | divisor: the src
    MOVEA.L	D5,A2                               | ...
    BSR.B	FP68K_RESTORE                         | RESTORE: all quotient bits through the first fraction bit
    BTST	#0x0,D5                                | first fraction bit of the quotient
    BEQ.B	FP68K_REMQUO                          | 0: remainder < half the divisor, done ->
    TST.L	D1                                    | remainder 0 (exactly half)?
    BNE.B	FP68K_REMDIV_3                        | no: > half ->
    TST.L	D2                                    | ...
    BNE.B	FP68K_REMDIV_3                        | no: > half ->
    BTST	#0x1,D5                                | exactly half: low integer quotient bit
    BEQ.B	FP68K_REMDIV_5                        | even: keep the quotient ->
FP68K_REMDIV_3:
    BCHG	#0x7,D6                                | flip the remainder sign
    ADDQ.W	#0x2,D5                              | quotient + 1 (in bit 1)
FP68K_REMDIV_5:
    EXG	D2,A2                                   | swap divisor and remainder
    EXG	D1,D3                                   | ...
    SUB.L	A2,D2                                 | remainder := divisor - remainder
    SUBX.L	D3,D1                                | (high halves)
| FP68K_REMQUO: store the quotient bits (sign from D6 bit 6).
FP68K_REMQUO:
    LSR.B	#0x1,D5                               | drop the fraction bit: low 7 integer quotient bits
    BTST	#0x6,D6                                | quotient negative (signs differed)?
    BEQ.B	FP68K_REMQUO_9                        | no ->
    NEG.B	D5                                    | negate it
FP68K_REMQUO_9:
    EXT.W	D5                                    | signed byte to word
    MOVE.W	D5,0x6(SP)                           | into the saved D0.W: the caller gets it in D0
    MOVE.L	D1,D4                                | result := the remainder
    MOVE.L	D2,D5                                | (low half)
| FP68K_REMFIN: store the remainder (ZNORMCOERCE).
FP68K_REMFIN:
    BRA.W	FP68K_ZNORMCOERCE                     | -> ZNORMCOERCE
| ----------------------------------------------------------
| FP68K_CMPTOP -- compare (CMP, CMPX): call the case routine
| for the number cases; it returns the CCR value in D0: CMPG $00 (dst >
| src), CMPL $19 (less), CMPE $04 (equal), CMPU $02 (unordered).
| FP68K_CMPFIN: CMPX signals invalid when unordered; the CCR
| value goes to D7.hi (CHKERR moves it to the CCR).
FP68K_CMPTOP:
    MOVE.W	FP68K_CMPCASE(PC,D3.W),D3            | offset of the case routine (CMPCASE)
    JSR	FP68K_CMPTOP(PC,D3.W)                   | call it: D0 = CCR value
FP68K_CMPFIN:
    CMPI.W	#0x2,D0                              | CMPFIN: unordered (CMPU)?
    BNE.B	FP68K_CMPFIN_1                        | no ->
    BTST	#0x11,D6                               | CMPX (OPIFCPX)?
    BEQ.B	FP68K_CMPFIN_1                        | no ->
    BSET	#0x8,D6                                | CMPX unordered: invalid
FP68K_CMPFIN_1:
    MOVE.W	D0,D7                                | CCR value ...
    SWAP.W	D7                                   | ... to D7.hi
    RTS                                         | return: comparison result as CCR bits in D7.hi (CMPFIN)
| FP68K_CMPCASE: case routines by (dst, src), offsets from
| FP68K_CMPTOP.
FP68K_CMPCASE:
    .short	FP68K_CMPNUM-FP68K_CMPTOP            | num, num: CMPNUM
    .short	FP68K_CMPS0-FP68K_CMPTOP             | num, 0: CMPS0
    .short	FP68K_CMPD0-FP68K_CMPTOP             | num, inf: CMPD0: num vs inf like 0 vs num
    .short	FP68K_CMPD0-FP68K_CMPTOP             | 0, num: CMPD0
    .short	FP68K_CMP0-FP68K_CMPTOP              | 0, 0: CMP0: 0 vs 0 equal
    .short	FP68K_CMPD0-FP68K_CMPTOP             | 0, inf: CMPD0
    .short	FP68K_CMPS0-FP68K_CMPTOP             | inf, num: CMPS0: inf vs num like num vs 0
    .short	FP68K_CMPS0-FP68K_CMPTOP             | inf, 0: CMPS0
    .short	FP68K_CMPINF-FP68K_CMPTOP            | inf, inf: CMPINF
| FP68K_CMPS0: num vs 0 -- as 0 vs -num: the dst sign to
| bit 7, inverted.
FP68K_CMPS0:
    ADD.B	D6,D6                                 | dst sign to bit 7 ...
    NOT.B	D6                                    | ... inverted: 0 vs -num
| FP68K_CMPD0: 0 vs. number -- D0 = CMPG ($00) or CMPL ($19)
FP68K_CMPD0:
    MOVEQ.L	#0x0,D0                             | D0 = CMPG ($00, greater): dst > src if src < 0
    TST.B	D6                                    | sign of the source
    BMI.B	FP68K_CMPD0_1                         | negative: greater ->
    MOVEQ.L	#0x19,D0                            | D0 = CMPL ($19, less): dst < positive src
FP68K_CMPD0_1:
    RTS                                         | return D0 = CMPG or CMPL (CMPD0)
| ----------------------------------------------------------
| FP68K_CMPINF: inf vs inf -- equal if the signs are equal,
| else as 0 vs num. FP68K_CMP0: equal.
FP68K_CMPINF:
    BTST	#0x5,D6                                | signs differ?
    BNE.B	FP68K_CMPD0                           | yes: as 0 vs num ->
FP68K_CMP0:
    MOVEQ.L	#0x4,D0                             | CMP0: CMPE ($04), equal
    RTS                                         | return D0 = CMPE ($04): equal (CMP0)
| ----------------------------------------------------------
| FP68K_CMPNUM: num vs num -- different signs: as 0 vs num;
| else compare exponents, then significands; for negative operands the
| order flips.
FP68K_CMPNUM:
    BTST	#0x5,D6                                | signs differ?
    BNE.B	FP68K_CMPD0                           | yes: as 0 vs num ->
    CMPA.L	A4,A3                                | dst exponent - src exponent
    BGT.B	FP68K_CMPNUM_1                        | dst larger ->
    BLT.B	FP68K_CMPNUM_2                        | dst smaller ->
    CMPA.L	D4,A1                                | equal: high halves
    BHI.B	FP68K_CMPNUM_1                        | dst larger ->
    BCS.B	FP68K_CMPNUM_2                        | dst smaller ->
    CMPA.L	D5,A2                                | low halves
    BEQ.B	FP68K_CMP0                            | equal: CMP0 ->
    BCS.B	FP68K_CMPNUM_2                        | dst smaller ->
FP68K_CMPNUM_1:
    NOT.B	D6                                    | dst larger: invert the sign test
FP68K_CMPNUM_2:
    MOVEQ.L	#0x19,D0                            | D0 = CMPL ($19): dst < src ...
    TST.B	D6                                    | ... unless both are negative
    BPL.B	FP68K_CMPNUM_21                       | positive: less ->
    MOVEQ.L	#0x0,D0                             | negative: CMPG ($00), greater
FP68K_CMPNUM_21:
    RTS                                         | return D0 = CMPL or CMPG (CMPNUM)
| ----------------------------------------------------------
| FP68K_CVT2E -- convert to extended (format of the src in
| the opword): only finite nonzero values need coercing.
FP68K_CVT2E:
    TST.W	D3                                    | finite nonzero (D3 = 0)?
    BEQ.W	FP68K_COERCE                          | yes: COERCE ->
    RTS                                         | zero or infinity: as it is
| ----------------------------------------------------------
| FP68K_RINT -- round to an integral value in the current
| rounding direction: align the binary point (IPALIGN) and coerce.
FP68K_RINT:
    TST.W	D3                                    | finite nonzero?
    BEQ.B	FP68K_RINT_1                          | yes ->
    RTS                                         | zero or infinity: as it is
| ----------------------------------------------------------
| FP68K_RINT_1 (Apple RINT @1): finite nonzero.
FP68K_RINT_1:
    BSR.B	FP68K_IPALIGN                         | IPALIGN: the binary point at the right end
    MOVEA.W	(A0),A2                             | save the environment (COMINT restores it)
    BRA.B	FP68K_COMINT                          | -> COMINT
| ----------------------------------------------------------
| FP68K_TINT -- truncate to an integral value: as RINT with
| the direction forced to toward zero.
FP68K_TINT:
    TST.W	D3                                    | finite nonzero?
    BEQ.B	FP68K_TINT_1                          | yes ->
    RTS                                         | zero or infinity: as it is
| ----------------------------------------------------------
| FP68K_TINT_1 (Apple TINT @1): finite nonzero. (Apple's source notes a
| bug comment about the chop encoding; the code sets 11, toward zero.)
FP68K_TINT_1:
    BSR.B	FP68K_IPALIGN                         | IPALIGN
    MOVEA.W	(A0),A2                             | save the environment
    BSET	#0x6,(A0)                              | rounding direction ...
    BSET	#0x5,(A0)                              | ... 11: toward zero
| FP68K_COMINT: coerce (rounding the fraction bits away),
| restore the environment, normalize the result or make it zero.
FP68K_COMINT:
    BSR.W	FP68K_COERCE                          | COERCE: round the fraction bits away (maybe to 0)
    MOVE.W	A2,(A0)                              | restore the environment (keeps no new flags)
    TST.L	D4                                    | normalized?
    BMI.B	FP68K_COMINT_9                        | yes ->
    BNE.B	FP68K_COMINT_5                        | unnormalized ->
    TST.L	D5                                    | ...
    BNE.B	FP68K_COMINT_5                        | ...
    SUBA.L	A4,A4                                | zero: exponent 0
    BRA.B	FP68K_COMINT_9                        | -> return
| ----------------------------------------------------------
| FP68K_COMINT_5 (Apple COMINT @5): normalize.
FP68K_COMINT_5:
    SUBQ.L	#0x1,A4                              | exponent - 1
    ADD.L	D5,D5                                 | significand * 2
    ADDX.L	D4,D4                                | ...
    BPL.B	FP68K_COMINT_5                        | until normalized
FP68K_COMINT_9:
    RTS                                         | return: integral value, normalized or zero (COMINT)
| ----------------------------------------------------------
| FP68K_IPALIGN -- put the binary point right of bit 23,
| 52 or 63 (single, double, extended): shift the fraction bits into D7.
| Returns LE if the value has no fraction bits (too big), GT if shifted.
FP68K_IPALIGN:
    TST.L	D6                                    | single?
    BMI.B	FP68K_IPALIGN_1                       | yes ->
    BTST	#0x1E,D6                               | double?
    BEQ.B	FP68K_IALIGN                          | no: extended (IALIGN) ->
    MOVEQ.L	#0x34,D0                            | double: point right of bit 52
    BRA.W	FP68K_FINALIGN                        | -> FINALIGN
| ----------------------------------------------------------
| FP68K_IPALIGN_1 (Apple IPALIGN @1): single.
FP68K_IPALIGN_1:
    MOVEQ.L	#0x17,D0                            | single: right of bit 23
    BRA.W	FP68K_FINALIGN                        | -> FINALIGN
| ----------------------------------------------------------
| FP68K_IALIGN: extended; FP68K_FINALIGN common.
FP68K_IALIGN:
    MOVEQ.L	#0x3F,D0                            | extended: right of bit 63
FP68K_FINALIGN:
    ADDI.W	#0x3FFF,D0                           | biased exponent of such an integer
    MOVE.W	D0,D1                                | save it: the new exponent
    SUB.L	A4,D0                                 | - exponent = bits to shift out
    BGT.B	FP68K_FINALIGN_7                      | some ->
    RTS                                         | none: return LE (an integer already, too big)
| ----------------------------------------------------------
| FP68K_FINALIGN_7 (Apple FINALIGN @7): shift right D0 bits to the new exponent.
FP68K_FINALIGN_7:
    MOVEA.W	D1,A4                               | exponent := the integer exponent
    BSR.W	FP68K_RTSHIFT                         | RTSHIFT D0 bits into D7
    MOVE.W	#0x0,CCR                             | CCR := 0: return GT (aligned)
    RTS                                         | return GT: binary point right-aligned (FINALIGN)
| ----------------------------------------------------------
| FP68K_CVTE2 -- convert from extended: to a float as CVT2E;
| to int16/int32/comp: zero is done, infinity overflows, else align the
| point at the right (IALIGN), round, check the range (IOFLOW).
FP68K_CVTE2:
    BTST	#0x1A,D6                               | integer destination (DSTINT)?
    BEQ.B	FP68K_CVT2E                           | no: as CVT2E ->
    CMPI.W	#0x2,D3                              | zero?
    BNE.B	FP68K_CVTE2_2                         | no ->
    RTS                                         | zero: done
| ----------------------------------------------------------
| FP68K_CVTE2_2 (Apple CVTE2 @2): infinity -> overflow.
FP68K_CVTE2_2:
    CMPI.W	#0x4,D3                              | infinity?
    BNE.B	FP68K_CVTE2_4                         | no ->
    MOVEQ.L	#-0x1,D4                            | make sure IOFLOW finds an overflow
    BRA.B	FP68K_IOFLOW                          | -> IOFLOW
FP68K_CVTE2_4:
    BSR.B	FP68K_IALIGN                          | IALIGN: point right of D5
    BLE.B	FP68K_IOFLOW                          | LE: too big, overflow ->
    MOVEQ.L	#0x0,D1                             | D1:D2 = 0:1: round as an extended (CVTE2)
    MOVEQ.L	#0x1,D2                             | (low half 1)
    BTST	#0x0,D5                                | Z = NOT LSB
    BSR.W	FP68K_ROUND                           | ROUND (cannot carry out: the lead bit is 0)
| FP68K_IOFLOW -- integer range check: limit $8000 (int16),
| $80000000 (int32), comp: the leading bit; the limit itself is allowed
| only for a negative value. Overflow: the limit (largest negative
| integer, comp: the comp NaN), invalid without inexact.
FP68K_IOFLOW:
    MOVEQ.L	#0x1,D1                             | D1 := $80000000 ...
    ROR.L	#0x1,D1                               | ...
    BTST	#0x18,D6                               | int32 (DSTLO)?
    BNE.B	FP68K_IOFLOW_21                       | yes: limit $80000000 ->
    BTST	#0x19,D6                               | comp (DSTMD)?
    BNE.B	FP68K_IOFLOW_41                       | yes ->
    SWAP.W	D1                                   | int16: limit $00008000
FP68K_IOFLOW_21:
    TST.L	D4                                    | any high bits?
    BNE.B	FP68K_IOFLOW_25                       | yes: overflow ->
    CMP.L	D1,D5                                 | magnitude vs the limit
    BHI.B	FP68K_IOFLOW_25                       | above: overflow ->
    BCS.B	FP68K_IOFLOW_23                       | below: fits ->
    TST.B	D6                                    | equal: allowed only if negative
    BPL.B	FP68K_IOFLOW_25                       | positive: overflow ->
FP68K_IOFLOW_23:
    TST.B	D6                                    | negative?
    BPL.B	FP68K_IOFLOW_24                       | no ->
    NEG.L	D5                                    | negate the 64 bits
    NEGX.L	D4                                   | ...
FP68K_IOFLOW_24:
    RTS                                         | return: integer in D4:D5, negated if negative (IOFLOW)
| ----------------------------------------------------------
| FP68K_IOFLOW_25 (Apple IOFLOW @25): overflow -- the limit value, invalid.
FP68K_IOFLOW_25:
    MOVE.L	D1,D5                                | the limit: the largest negative int16/int32
FP68K_IOFLOW_27:
    BSET	#0x8,D6                                | invalid ...
    BCLR	#0xC,D6                                | ... without inexact
    RTS                                         | return: integer overflow -- largest negative integer, invalid
FP68K_IOFLOW_41:
    TST.L	D4                                    | comp: leading bit set?
    BPL.B	FP68K_IOFLOW_23                       | no: fits ->
    MOVEQ.L	#0x0,D5                             | comp overflow: D4:D5 := $80000000:0, the comp NaN
    MOVE.L	D1,D4                                | (high half $80000000)
    BRA.B	FP68K_IOFLOW_27                       | -> invalid
| ----------------------------------------------------------
| FP68K_SQRTTOP -- square root: +-0 and +inf are their own
| roots, negative operands invalid (NANSQRT 1); otherwise halve the
| exponent and extract the root bit by bit (restoring, two radicand bits
| per step, 65 steps), the rest gives the sticky bit; coerce.
FP68K_SQRTTOP:
    CMPI.W	#0x2,D3                              | +-0?
    BNE.B	FP68K_SQRTTOP_1                       | no ->
    RTS                                         | sqrt(+-0) = +-0
| ----------------------------------------------------------
| FP68K_SQRTTOP_1 (Apple SQRTTOP @1): not zero.
FP68K_SQRTTOP_1:
    MOVEQ.L	#0x1,D0                             | NaN code 1 (NANSQRT)
    TST.B	D6                                    | negative (number or infinity)?
    BMI.W	FP68K_INVALIDOP                       | yes: INVALIDOP ->
    CMPI.W	#0x4,D3                              | +inf?
    BNE.B	FP68K_SQRTTOP_10                      | no ->
    RTS                                         | sqrt(+inf) = +inf
| ----------------------------------------------------------
| FP68K_SQRTTOP_10 (Apple SQRTTOP @10): finite positive. Root in D0.B:D4:D5,
| radicand in D1.B:D2:D3:D6:D7, step counter in A3.
FP68K_SQRTTOP_10:
    MOVE.W	A4,D0                                | D0 = exponent
    ASR.W	#0x1,D0                               | halve it
    MOVE.W	SR,D1                                | save C: 1 if the true exponent is even
    BCC.B	FP68K_SQRTTOP_12                      | C = 0 (odd) ->
    ADDQ.W	#0x1,D0                              | even: + 1 (rebias by $2000 in all)
FP68K_SQRTTOP_12:
    ADDI.W	#0x1FFF,D0                           | rebias
    MOVEA.W	D0,A4                               | the root's exponent
    MOVEA.L	D6,A1                               | save D6 ...
    MOVEA.L	D7,A2                               | ... and D7
    MOVE.L	D5,D7                                | radicand D6:D7 := the significand
    MOVE.L	D4,D6                                | ...
    MOVEQ.L	#0x0,D3                             | D3 := 0: clear the upper radicand D2:D3 (SQRTTOP)
    MOVE.L	D3,D2                                | (D2 too)
    ADD.L	D7,D7                                 | radicand left 1 bit: point between D3 and D6
    ADDX.L	D6,D6                                | ...
    ADDX.W	D3,D3                                | ...
    MOVE.W	D1,CCR                               | C from the exponent halving
    BCS.B	FP68K_SQRTTOP_14                      | even exponent: one shift ->
    ADD.L	D7,D7                                 | odd: one more
    ADDX.L	D6,D6                                | ...
    ADDX.W	D3,D3                                | ...
FP68K_SQRTTOP_14:
    MOVE.L	D2,D0                                | root D0.B:D4:D5 := ...0011
    MOVE.L	D2,D4                                | ...
    MOVEQ.L	#0x3,D5                             | ...: the first root bit is 1 (normalized)
    SUBQ.W	#0x1,D3                              | first step done: radicand - 1
    MOVEQ.L	#0x41,D1                            | 65 steps ...
    MOVEA.W	D1,A3                               | ... counted in A3
    MOVEQ.L	#0x0,D1                             | D1 := 0: radicand top bits (the count is in A3)
| FP68K_SQRTTOP_20 (Apple SQRTTOP @20): one root bit -- radicand left 2 bits,
| root <root>1 -> <root>01, try radicand - root.
FP68K_SQRTTOP_20:
    ADD.L	D7,D7                                 | radicand left 2 bits
    ADDX.L	D6,D6                                | ...
    ADDX.L	D3,D3                                | ...
    ADDX.L	D2,D2                                | ...
    ADDX.W	D1,D1                                | ...
    ADD.L	D7,D7                                 | (second bit)
    ADDX.L	D6,D6                                | ...
    ADDX.L	D3,D3                                | ...
    ADDX.L	D2,D2                                | ...
    ADDX.W	D1,D1                                | ...
    ADD.L	D5,D5                                 | root left 1 bit: <root>1 -> <root>10 ...
    ADDX.L	D4,D4                                | ...
    ADDX.W	D0,D0                                | ...
    SUBQ.W	#0x1,D5                              | ... -> <root>01
    SUB.L	D5,D3                                 | radicand - root
    SUBX.L	D4,D2                                | ...
    SUBX.W	D0,D1                                | ...
    BCC.B	FP68K_SQRTTOP_22                      | no borrow: the root bit is 1 ->
    ADD.L	D5,D3                                 | borrow: add it back, the root bit is 0
    ADDX.L	D4,D2                                | ...
    ADDX.W	D0,D1                                | ...
    BRA.B	FP68K_SQRTTOP_24                      | -> count
| ----------------------------------------------------------
| FP68K_SQRTTOP_22 (Apple SQRTTOP @22): the root bit is 1.
FP68K_SQRTTOP_22:
    ADDQ.W	#0x2,D5                              | <root>01 -> <root>11: bit 1
FP68K_SQRTTOP_24:
    EXG	D0,A3                                   | the counter ...
    SUBQ.W	#0x1,D0                              | ... - 1 ...
    EXG	D0,A3                                   | ... back to A3
    BNE.B	FP68K_SQRTTOP_20                      | more steps ->
    MOVE.L	A1,D6                                | restore D6 (opword etc.)
    MOVE.L	A2,D7                                | and D7
    OR.L	D2,D1                                  | remainder nonzero?
    OR.L	D3,D1                                  | ...
    BNE.B	FP68K_SQRTTOP_30                      | yes: the appended 1 stays as sticky bit ->
    SUBQ.W	#0x1,D5                              | exact: drop the appended 1
FP68K_SQRTTOP_30:
    MOVEQ.L	#0x3,D1                             | shift the 66 root bits right 3 into place
FP68K_SQRTTOP_32:
    LSR.W	#0x1,D0                               | ...
    ROXR.L	#0x1,D4                              | ...
    ROXR.L	#0x1,D5                              | ...
    ROXR.W	#0x1,D7                              | ... the low bits become the round bits
    SUBQ.W	#0x1,D1                              | count
    BNE.B	FP68K_SQRTTOP_32                      | 3 times
    BRA.W	FP68K_COERCE                          | -> COERCE
| ----------------------------------------------------------
| FP68K_LOGBTOP -- logb: the unbiased exponent as a floating
| value; logb(+-0) = -inf with divide by zero, logb(+-inf) = +inf.
FP68K_LOGBTOP:
    CLR.B	D6                                    | the operand sign does not matter
    CMPI.W	#0x2,D3                              | operand is zero (D3 = 2)?
    BNE.B	FP68K_LOGBTOP_1                       | no -> infinity?
    ORI.W	#0x880,D6                             | logb(0): division by zero (ERRZ) and minus sign
    MOVEA.W	#0x7FFF,A4                          | exponent of infinity
    MOVEQ.L	#0x0,D4                             | D4 := 0: significand of -infinity
    MOVE.L	D4,D5                                | (low half)
    RTS                                         | return: logb(+-0) = -inf
| ----------------------------------------------------------
| FP68K_LOGBTOP_1 (Apple LOGBTOP @1): not zero.
FP68K_LOGBTOP_1:
    CMPI.W	#0x4,D3                              | infinity?
    BNE.B	FP68K_UNPACK_EXPONENT                 | no: finite ->
    RTS                                         | logb(+-inf) = +inf (sign cleared)
FP68K_UNPACK_EXPONENT:
    MOVEQ.L	#0x0,D5                             | D5 := 0: the exponent becomes an integer in D4
    SUBA.W	#0x3FFF,A4                           | unbiased exponent ...
    MOVE.L	A4,D4                                | ... as an integer in D4
    BPL.B	FP68K_LOGBTOP_12                      | positive ->
    ORI.B	#0x80,D6                              | negative: minus sign ...
    NEG.L	D4                                    | ... and the magnitude
FP68K_LOGBTOP_12:
    MOVEA.W	#0x401E,A4                          | exponent 31 (biased): D4 is an integer
    BRA.W	FP68K_ZNORMCOERCE                     | -> ZNORMCOERCE
| ----------------------------------------------------------
| FP68K_SCALBTOP -- scalb: x * 2^n, the int16 n at the
| second address: add n to the exponent and coerce; 0 and inf unchanged.
FP68K_SCALBTOP:
    TST.W	D3                                    | finite nonzero?
    BEQ.B	FP68K_SCALBTOP_1                      | yes ->
    RTS                                         | zero or infinity: as it is
| ----------------------------------------------------------
| FP68K_SCALBTOP_1 (Apple SCALBTOP @1): finite nonzero.
FP68K_SCALBTOP_1:
    MOVEA.L	0xE(A6),A3                          | A3 = address 2: the int16 n
    ADDA.W	(A3),A4                              | exponent + n
    BRA.W	FP68K_COERCE                          | -> COERCE: over/underflow
| ----------------------------------------------------------
| FP68K_CLASSTOP -- class of the src: the SANE class + 1,
| negated for a negative operand: 1 signaling NaN, 2 quiet NaN, 3
| infinity, 4 zero, 5 normal, 6 denormal (NaNs come through NANFLOAT);
| stored as an int16 at the dst address (FP68K_CLASSFIN, Apple CLASSFIN).
FP68K_CLASSTOP:
    MOVEQ.L	#0x5,D0                             | class 5: normal
    TST.L	D3                                    | D3 bit 31: unnormalized (from UNPACK)
    BMI.B	FP68K_CLASSTOP_99                     | yes: 6, denormal ->
    BEQ.B	FP68K_CLASSFIN                        | D3 = 0: a normal number ->
    SUBQ.W	#0x2,D0                              | 3: infinity?
    CMPI.W	#0x4,D3                              | D3 = 4?
    BEQ.B	FP68K_CLASSFIN                        | yes ->
FP68K_CLASSTOP_99:
    ADDQ.W	#0x1,D0                              | zero: 4 (denormal: 6)
FP68K_CLASSFIN:
    TST.B	D6                                    | CLASSFIN: negative operand?
    BEQ.B	FP68K_CLASSFIN_100                    | no ->
    NEG.W	D0                                    | negative: negated class
FP68K_CLASSFIN_100:
    MOVEA.L	0xA(A6),A3                          | A3 = address 1: the int16 result
    MOVE.W	D0,(A3)                              | store the class
    RTS                                         | return: class code stored at the destination (CLASSFIN)
| ----------------------------------------------------------
| FP68K_ODDBALL -- odd opwords: A1 = address 1, A2 = address
| 2; D7 = opword AND $1E = (operation - 1) indexes ODDTAB.
FP68K_ODDBALL:
    MOVEM.L	0xA(A6),A1-A2                       | A1 = address 1, A2 = address 2
    MOVE.W	FP68K_ODDTAB(PC,D7.W),D7             | offset of the routine (ODDTAB)
    JMP	FP68K_ODDBALL(PC,D7.W)                  | -> it
| FP68K_ODDTAB: routines for the odd operations, offsets
| from FP68K_ODDBALL.
FP68K_ODDTAB:
    .short	FP68K_PUTW-FP68K_ODDBALL             | $01 setenv (PUTW)
    .short	FP68K_GETW-FP68K_ODDBALL             | $03 getenv (GETW)
    .short	FP68K_PUTV-FP68K_ODDBALL             | $05 set halt vector (PUTV)
    .short	FP68K_GETV-FP68K_ODDBALL             | $07 get halt vector (GETV)
    .short	FP68K_D2B-FP68K_ODDBALL              | $09 decimal to binary (D2B)
    .short	FP68K_B2D-FP68K_ODDBALL              | $0B binary to decimal (B2D)
    .short	FP68K_NEGZ-FP68K_ODDBALL             | $0D negate (NEGZ)
    .short	FP68K_ABSZ-FP68K_ODDBALL             | $0F abs (ABSZ)
    .short	FP68K_CPSZ-FP68K_ODDBALL             | $11 copysign (CPSZ)
    .short	FP68K_NEXTZ-FP68K_ODDBALL            | $13 nextafter (NEXTZ)
    .short	FP68K_SETXCP-FP68K_ODDBALL           | $15 set exception (SETXCP)
    .short	FP68K_ENTRYP-FP68K_ODDBALL           | $17 procentry (ENTRYP)
    .short	FP68K_EXITP-FP68K_ODDBALL            | $19 procexit (EXITP)
    .short	FP68K_TESTXCP-FP68K_ODDBALL          | $1B test exception (TESTXCP)
| FP68K_PUTW: setenv -- environment := the word at (A1).
FP68K_PUTW:
    MOVE.W	(A1),(A0)                            | environment := (A1)
    BRA.B	FP68K_GO1                             | -> POP1
| ----------------------------------------------------------
| FP68K_ENTRYP: procentry -- save the environment at (A1),
| then set the default environment (0: no flags, no halts, to nearest).
FP68K_ENTRYP:
    MOVE.W	(A0),(A1)                            | save the environment at (A1)
    CLR.W	(A0)                                  | default environment
    BRA.B	FP68K_GO1                             | -> POP1
| ----------------------------------------------------------
| FP68K_GETW: getenv -- the environment word to (A1).
FP68K_GETW:
    MOVE.W	(A0),(A1)                            | environment to (A1)
    BRA.B	FP68K_GO1                             | -> POP1
| ----------------------------------------------------------
| FP68K_PUTV: set the halt vector from (A1).
FP68K_PUTV:
    MOVE.L	(A1),0x2(A0)                         | halt vector := (A1)
    BRA.B	FP68K_GO1                             | -> POP1
| ----------------------------------------------------------
| FP68K_GETV: the halt vector to (A1).
FP68K_GETV:
    MOVE.L	0x2(A0),(A1)                         | halt vector to (A1)
    BRA.B	FP68K_GO1                             | -> POP1
| ----------------------------------------------------------
| FP68K_NEGZ: negate -- flip the sign bit of the operand
| at (A1), any format.
FP68K_NEGZ:
    BCHG	#0x7,(A1)                              | flip the sign bit (the first byte, any format)
    BRA.B	FP68K_GO1                             | -> POP1
| ----------------------------------------------------------
| FP68K_ABSZ: abs -- clear the sign bit of (A1).
FP68K_ABSZ:
    BCLR	#0x7,(A1)                              | clear the sign bit
| ----------------------------------------------------------
| FP68K_GO1: return, one address (POP1).
| Called by: FP68K_PUTW, FP68K_ENTRYP, FP68K_GETW, FP68K_PUTV, FP68K_GETV (and 2 more)
FP68K_GO1:
    BRA.W	FP68K_POP1                            | -> POP1: one address
| ----------------------------------------------------------
| FP68K_TESTXCP -- test the exception whose number (0-4)
| is the word at (A1): the byte at (A1) := 1 if its flag is set, else 0.
FP68K_TESTXCP:
    MOVE.W	(A1),D0                              | D0 = exception number (FBINVALID 0 .. FBINEXACT 4)
    BTST	D0,(A0)                                | its flag in the environment high byte
    SNE.B	D0                                    | D0 = $FF if set
    NEG.B	D0                                    | 1 or 0
    MOVE.B	D0,(A1)                              | the BOOLEAN result over the input word
    BRA.B	FP68K_GO1                             | -> POP1
| ----------------------------------------------------------
| FP68K_CPSZ: copysign -- the sign of the operand at (A1)
| (the "dst") onto the one at (A2).
FP68K_CPSZ:
    BTST	#0x7,(A1)                              | sign of the "dst" (A1)
    BEQ.B	FP68K_CPSZ_1                          | positive ->
    BSET	#0x7,(A2)                              | negative: set the sign of (A2)
    BRA.B	FP68K_CPSZ_2                          | -> POP2
| ----------------------------------------------------------
| FP68K_CPSZ_1 (Apple CPSZ @1): positive.
FP68K_CPSZ_1:
    BCLR	#0x7,(A2)                              | clear the sign of (A2)
FP68K_CPSZ_2:
    BRA.W	FP68K_POP2                            | -> POP2: two addresses
| ----------------------------------------------------------
| FP68K_NEXTZ -- nextafter: change the operand at (A2)
| (the "src", single, double or extended) by one unit in the last place
| toward the one at (A1); a NaN wins as in a multiply. Calls the package
| recursively (REFP68K) to convert, compare and classify; signals
| overflow or underflow (with inexact) for an infinite or denormal
| result; exits through CHKERR. Frame (A4): 0 dst, 10 src (extended),
| 20 the class integer.
FP68K_NEXTZ:
    SUBA.W	#0x16,SP                             | frame: 2 extendeds and an int16
    MOVEA.L	SP,A4                               | A4 = the frame
    MOVE.W	D6,D5                                | opword ...
    ANDI.W	#0x3800,D5                           | ... D5 = its format bits
    ADDQ.W	#0x1,D6                              | TWOADRS (bit 0) for the exit
    SWAP.W	D6                                   | opword to D6.hi as for arithmetic
    CLR.W	D6                                    | no flags, no signs
    MOVE.L	A2,-(SP)                             | convert the src ...
    PEA.L	0xA(A4)                               | ... to extended at 10(A4)
    MOVEQ.L	#0xE,D0                             | OP2EXT ...
    OR.W	D5,D0                                  | ... with the format
    MOVE.W	D0,-(SP)                             | ...
    BSR.W	FP68K_REFP68K                         | REFP68K
    CLR.L	(A4)                                  | 0.0 at (A4)
    CLR.L	0x4(A4)                               | ...
    CLR.W	0x8(A4)                               | ...
    PEA.L	(A4)                                  | compare 0 ...
    PEA.L	0xA(A4)                               | ... with the src
    MOVE.W	#0x8,-(SP)                           | OPCMP
    BSR.W	FP68K_REFP68K                         | REFP68K
    SNE.B	D4                                    | D4.B = $FF if the src is nonzero
    MOVE.L	A1,-(SP)                             | convert the dst ...
    PEA.L	(A4)                                  | ... to extended at (A4)
    MOVE.W	D0,-(SP)                             | (OP2EXT with the format)
    BSR.W	FP68K_REFP68K                         | REFP68K
    PEA.L	(A4)                                  | compare the dst ...
    PEA.L	0xA(A4)                               | ... with the src
    MOVE.W	#0x8,-(SP)                           | OPCMP
    BSR.W	FP68K_REFP68K                         | REFP68K
    BVC.B	FP68K_NXORD                           | ordered ->
    PEA.L	(A4)                                  | unordered (a NaN): multiply dst ...
    PEA.L	0xA(A4)                               | ... into src: the precedent NaN
    MOVE.W	#0x4,-(SP)                           | OPMUL
    BSR.W	FP68K_REFP68K                         | REFP68K
    PEA.L	0xA(A4)                               | convert the NaN back ...
    MOVE.L	A2,-(SP)                             | ... to the src in its format
    MOVEQ.L	#0x10,D0                            | OPEXT2 ...
    OR.W	D5,D0                                  | ... with the format
    MOVE.W	D0,-(SP)                             | ...
    BSR.W	FP68K_REFP68K                         | REFP68K
    BRA.W	FP68K_NXFIN                           | -> NXFIN
| ----------------------------------------------------------
| FP68K_NXORD: ordered -- equal: done; else increment or
| decrement the src magnitude.
FP68K_NXORD:
    BEQ.B	FP68K_NXFIN                           | equal: nothing to do ->
    BCC.B	FP68K_NXGREAT                         | src > dst ->
    BTST	#0x7,(A2)                              | src < dst: src negative?
    BEQ.B	FP68K_NXINC                           | positive: increment (NXINC) ->
    BRA.B	FP68K_NXDEC                           | negative: decrement (NXDEC) ->
| ----------------------------------------------------------
| FP68K_NXGREAT: src > dst -- decrement if positive,
| increment if negative.
FP68K_NXGREAT:
    BTST	#0x7,(A2)                              | src negative?
    BEQ.B	FP68K_NXDEC                           | positive: decrement ->
| FP68K_NXINC: increment by one ulp, per format.
FP68K_NXINC:
    BTST	#0xC,D5                                | single ($1000)?
    BEQ.B	FP68K_NXINC_11                        | no ->
    ADDQ.L	#0x1,(A2)                            | single + 1 ulp
    BRA.B	FP68K_NXERR                           | -> NXERR
| ----------------------------------------------------------
|
| FP68K_NXINC_11
|
FP68K_NXINC_11:
    BTST	#0xB,D5                                | double ($0800)?
    BEQ.B	FP68K_NXINC_15                        | no: extended ->
    ADDQ.L	#0x1,0x4(A2)                         | double + 1 ulp: low half ...
    BCC.B	FP68K_NXINC_13                        | ...
    ADDQ.L	#0x1,(A2)                            | ... with the carry
FP68K_NXINC_13:
    BRA.B	FP68K_NXERR                           | -> NXERR
| ----------------------------------------------------------
| FP68K_NXINC_15 (Apple NXINC @15): extended -- an infinite result gets a 0
| integer bit.
FP68K_NXINC_15:
    ADDQ.L	#0x1,0x6(A2)                         | extended + 1 ulp: low significand ...
    BCC.B	FP68K_NXERR                           | ...
    ADDQ.L	#0x1,0x2(A2)                         | ... high significand ...
    BCC.B	FP68K_NXERR                           | ...
    ROXR.W	0x2(A2)                              | ... carry out: integer bit back in ...
    ADDQ.W	#0x1,(A2)                            | ... and exponent + 1
    CMPI.W	#0x7FFF,(A2)                         | +infinity now?
    BEQ.B	FP68K_NXINC_16                        | yes ->
    CMPI.W	#0xFFFF,(A2)                         | -infinity?
    BNE.B	FP68K_NXERR                           | no ->
FP68K_NXINC_16:
    BCLR	#0x7,0x2(A2)                           | infinity has integer bit 0
| ----------------------------------------------------------
| FP68K_NXERR -- classify the new value: infinity ->
| overflow + inexact, zero or denormal -> underflow + inexact.
| Called by: FP68K_NXINC, FP68K_NXDEC, FP68K_NXDEC_201, FP68K_NXDEC_21, FP68K_NXDEC_25
FP68K_NXERR:
    MOVE.L	A2,-(SP)                             | classify the new src ...
    PEA.L	0x14(A4)                              | ... into 20(A4)
    MOVEQ.L	#0x1C,D0                            | OPCLASS ...
    OR.W	D5,D0                                  | ... with the format
    MOVE.W	D0,-(SP)                             | ...
    BSR.W	FP68K_REFP68K                         | REFP68K
    MOVE.W	0x14(A4),D1                          | D1 = the class
    BPL.B	FP68K_NXERR_1                         | positive ->
    NEG.W	D1                                    | drop the sign
FP68K_NXERR_1:
    CMPI.W	#0x3,D1                              | infinity (CLINF)?
    BNE.B	FP68K_NXERR_3                         | no ->
    ORI.W	#0x1400,D6                            | overflow and inexact (ERRWXO)
    BRA.B	FP68K_NXFIN                           | -> NXFIN
| ----------------------------------------------------------
|
| FP68K_NXERR_3
|
FP68K_NXERR_3:
    CMPI.W	#0x5,D1                              | normal (CLNORM)?
    BEQ.B	FP68K_NXFIN                           | yes: no exception ->
    ORI.W	#0x1200,D6                            | zero or denormal: underflow and inexact (ERRWXU)
| FP68K_NXFIN: drop the frame, exit through CHKERR.
FP68K_NXFIN:
    ADDA.W	#0x16,SP                             | drop the frame
    BRA.W	FP68K_CHKERR                          | -> CHKERR
| ----------------------------------------------------------
| FP68K_NXDEC -- decrement by one ulp; a zero (D4 = 0) is
| incremented instead with the sign flipped (next(-0, 3) = +min).
FP68K_NXDEC:
    BTST	#0xC,D5                                | single?
    BEQ.B	FP68K_NXDEC_21                        | no ->
    TST.B	D4                                    | src nonzero?
    BNE.B	FP68K_NXDEC_201                       | yes: just decrement ->
    BCHG	#0x7,(A2)                              | zero: flip the sign ...
    ADDQ.L	#0x1,(A2)                            | ... and make it the smallest denormal
    BRA.B	FP68K_NXERR                           | -> NXERR
| ----------------------------------------------------------
|
| FP68K_NXDEC_201: decrement single by 1 ULP
|
FP68K_NXDEC_201:
    SUBQ.L	#0x1,(A2)                            | single - 1 ulp
    BRA.B	FP68K_NXERR                           | -> NXERR
| ----------------------------------------------------------
|
| FP68K_NXDEC_21: decrement double by 1 ULP
|
FP68K_NXDEC_21:
    BTST	#0xB,D5                                | double?
    BEQ.B	FP68K_NXDEC_25                        | no: extended ->
    TST.B	D4                                    | src nonzero?
    BNE.B	FP68K_NXDEC_211                       | yes: just decrement ->
    BCHG	#0x7,(A2)                              | zero: flip the sign ...
    ADDQ.W	#0x1,0x6(A2)                         | ... smallest denormal
    BRA.B	FP68K_NXERR                           | -> NXERR
| ----------------------------------------------------------
|
| FP68K_NXDEC_211: decrement double low word, borrow into high
|
FP68K_NXDEC_211:
    SUBQ.L	#0x1,0x4(A2)                         | double - 1 ulp: low half ...
    BCC.B	FP68K_NXDEC_213                       | ...
    SUBQ.L	#0x1,(A2)                            | ... with the borrow
FP68K_NXDEC_213:
    BRA.B	FP68K_NXERR                           | -> NXERR
| ----------------------------------------------------------
|
| FP68K_NXDEC_25: decrement extended by 1 ULP
|
FP68K_NXDEC_25:
    TST.B	D4                                    | src nonzero?
    BNE.B	FP68K_NXDEC_251                       | yes: just decrement ->
    BCHG	#0x7,(A2)                              | zero: flip the sign ...
    ADDQ.W	#0x1,0x8(A2)                         | ... smallest denormal
    BRA.B	FP68K_NXERR                           | -> NXERR
| ----------------------------------------------------------
|
| FP68K_NXDEC_251: decrement extended mantissa, handle borrow through exponent
|
FP68K_NXDEC_251:
    SUBQ.L	#0x1,0x6(A2)                         | extended - 1 ulp: low significand
    BCC.B	FP68K_NXDEC_259                       | no borrow: done ->
    SUBQ.L	#0x1,0x2(A2)                         | high significand
    BMI.B	FP68K_NXDEC_257                       | integer bit still 1 (or borrowed out) ->
    TST.W	(A2)                                  | integer bit now 0: minimum exponent?
    BEQ.B	FP68K_NXDEC_259                       | yes: a denormal, done ->
    CMPI.W	#0x8000,(A2)                         | (negative)
    BEQ.B	FP68K_NXDEC_259                       | done ->
    ADDI.W	#0x8000,0x2(A2)                      | renormalize: integer bit back ...
    BRA.B	FP68K_NXDEC_258                       | ... exponent - 1 ->
| ----------------------------------------------------------
|
| FP68K_NXDEC_257: mantissa borrow into exponent
|
FP68K_NXDEC_257:
    BCC.B	FP68K_NXDEC_259                       | no borrow out: done ->
FP68K_NXDEC_258:
    SUBQ.W	#0x1,(A2)                            | exponent - 1
FP68K_NXDEC_259:
    BRA.W	FP68K_NXERR                           | -> NXERR
| ----------------------------------------------------------
| FP68K_SETXCP -- signal the exception whose number is the
| word at (A1), with the halt if it is enabled: exit through CHKERR.
FP68K_SETXCP:
    SWAP.W	D6                                   | opword to D6.hi as for arithmetic
    CLR.W	D6                                    | no flags, no signs
    MOVE.W	(A1),D0                              | D0 = exception number (0-4)
    ADDQ.W	#0x8,D0                              | into the flag byte (bits 8-12)
    BSET	D0,D6                                  | signal it
    BRA.B	FP68K_EPEXIT                          | -> CHKERR
| ----------------------------------------------------------
| FP68K_EXITP: procexit -- restore the environment saved
| at (A1), then signal the exceptions that were raised in between (they
| may halt): exit through CHKERR.
FP68K_EXITP:
    SWAP.W	D6                                   | opword to D6.hi
    MOVE.W	#0x1F00,D6                           | mask of the exception flags
    AND.W	(A0),D6                               | D6 = the exceptions raised since procentry
    MOVE.W	(A1),(A0)                            | restore the saved environment
FP68K_EPEXIT:
    BRA.W	FP68K_CHKERR                          | -> CHKERR: signal them again
| ----------------------------------------------------------
| FP68K_D2B -- decimal to binary (Dec2Num): the decimal
| record at (A2) (sgn, exp, sig: up to 19 digits plus a lost-digits 20th,
| '0' zero, 'I' infinity, 'N'+hex a NaN) to the format in the opword at
| (A1). The digits become a 64-bit integer, scaled by 10^exp in DBCORE
| (with the rounding direction chosen for the scale factor), converted
| by a recursive call. Frame (A3): 20 bytes, two extendeds.
FP68K_D2B:
    SUBA.W	#0x14,SP                             | frame: 2 extendeds
    MOVEA.L	SP,A3                               | A3 = the frame
    LEA.L	0x4(A2),A4                            | A4 = d.sig (length byte)
    MOVE.W	0x2(A2),D3                           | D3 = d.exp
    SWAP.W	D6                                   | keep the opword in D6.hi
    MOVEQ.L	#0x0,D4                             | D4 := 0: clear the digit accumulator D4:D5 (D2B)
    MOVE.L	D4,D5                                | (low half)
    MOVE.L	D4,D7                                | D7.B: lost-digits flag (the 20th digit)
    MOVEQ.L	#0x13,D2                            | at most 19 digits
    MOVE.B	(A4)+,D6                             | D6.B = length of d.sig
    BEQ.B	FP68K_DBZSTO                          | empty: 0.0 ->
    MOVE.B	(A4),D0                              | D0 = first character
    CMPI.B	#0x49,D0                             | 'I'?
    BEQ.B	FP68K_DBNFIN                          | infinity ->
    CMPI.B	#0x4E,D0                             | 'N' (capital only)?
    BNE.B	FP68K_DBZER                           | no: digits ->
    MOVE.B	-0x1(A4),D2                          | D2 = character count ...
    ADDQ.L	#0x1,A4                              | ... A4 -> the first hex digit ...
    SUBQ.B	#0x1,D2                              | ... without the 'N'
    MOVEQ.L	#0x8,D0                             | 8 hex digits for the high half ...
    CMPI.B	#0x4,D2                              | ... if there are at least 4
    BGE.B	FP68K_D2B_31                          | yes ->
    SUBQ.B	#0x4,D0                              | fewer: 4 leading zeros ...
    ADD.B	D2,D0                                 | ... and the digits there are
FP68K_D2B_31:
    BSR.B	FP68K_D2B_35                          | hex digits into D5
    MOVE.L	D5,D4                                | high half of the NaN
    MOVEQ.L	#0x0,D5                             | first 8 hex digits now in D4; D5 := 0 for the next 8
    MOVEQ.L	#0x8,D0                             | the next 8 hex digits ...
    BSR.B	FP68K_D2B_35                          | ... into D5
    BRA.B	FP68K_D2B_39                          | -> check the code
| ----------------------------------------------------------
| FP68K_D2B_35 (Apple D2B @35) -- shift D0 hex digits into D5 (zeros once
| the D2 string characters are used up).
FP68K_D2B_35:
    ROL.L	#0x4,D5                               | make room for a digit
    SUBQ.B	#0x1,D2                              | characters left?
    BMI.B	FP68K_D2B_37                          | no: a 0 digit ->
    MOVE.B	(A4)+,D1                             | next hex character
    CMPI.B	#0x39,D1                             | a letter?
    BLE.B	FP68K_D2B_36                          | no: 0-9 ->
    ADDI.B	#0x9,D1                              | A-F: + 9 ('A' = $41 -> $4A)
FP68K_D2B_36:
    ANDI.B	#0xF,D1                              | digit value
    OR.B	D1,D5                                  | into D5
FP68K_D2B_37:
    SUBQ.W	#0x1,D0                              | count
    BNE.B	FP68K_D2B_35                          | more ->
    RTS                                         | return: D0 hex digits shifted into D5
| ----------------------------------------------------------
| FP68K_D2B_39 (Apple D2B @39): a NaN with an all-zero code gets code 21.
FP68K_D2B_39:
    ANDI.L	#0x7FFFFFFF,D4                       | ignore the leading bit; anything left?
    BNE.B	FP68K_DBNFIN                          | yes ->
    MOVEQ.L	#0x15,D4                            | no: NaN code 21 (NANZERO) ...
    SWAP.W	D4                                   | ... in bits 16-23
    BSET	#0x1E,D4                               | quiet
FP68K_DBNFIN:
    MOVE.W	#0x7FFF,D0                           | DBNFIN: exponent $7FFF (infinity, NaN)
    BRA.B	FP68K_DBSSTO                          | -> add the sign and store
| ----------------------------------------------------------
| FP68K_DBZER: '0' -> a signed zero; FP68K_DBZSTO
| (Apple DBZSTO) stores it, FP68K_DBSSTO adds the sign.
FP68K_DBZER:
    CMPI.B	#0x30,D0                             | '0'?
    BNE.B	FP68K_SIGDIGS                         | no: significant digits (SIGDIGS) ->
FP68K_DBZSTO:
    MOVEQ.L	#0x0,D0                             | D0 := 0: exponent word of a signed zero (DBZSTO)
FP68K_DBSSTO:
    TST.B	(A2)                                  | d.sgn (high byte) negative?
    BEQ.B	FP68K_DBSSTO_1                        | no -> positive
    BSET	#0xF,D0                                | sign bit into the exponent word
FP68K_DBSSTO_1:
    BSR.W	FP68K_TOA3                            | TOA3: store at (A3)
    BRA.W	FP68K_DBSTORE                         | -> DBSTORE
| ----------------------------------------------------------
| FP68K_DIG10: D4:D5 := D4:D5 * 10 (D0:D1 = * 2).
FP68K_DIG10:
    ADD.L	D5,D5                                 | * 2
    ADDX.L	D4,D4                                | ...
    MOVE.L	D5,D1                                | D0:D1 = * 2
    MOVE.L	D4,D0                                | ...
    ADD.L	D5,D5                                 | * 4
    ADDX.L	D4,D4                                | ...
    ADD.L	D5,D5                                 | * 8
    ADDX.L	D4,D4                                | ...
    ADD.L	D1,D5                                 | * 8 + * 2 = * 10
    ADDX.L	D0,D4                                | ...
    RTS                                         | return: D4:D5 := D4:D5 * 10 (DIG10)
| ----------------------------------------------------------
| FP68K_SIGDIGS: digits into D4:D5; the 20th goes to D7.B for
| rounding (TRAILDIG).
FP68K_SIGDIGS:
    BSR.B	FP68K_DIG10                           | value * 10 (DIG10)
    MOVEQ.L	#0xF,D0                             | digit mask
    AND.B	(A4)+,D0                              | D0 = next digit
    ADD.L	D0,D5                                 | add it
    CLR.W	D0                                    | for the carry
    ADDX.L	D0,D4                                | ...
    SUBQ.B	#0x1,D6                              | characters left?
    BEQ.B	FP68K_CANON                           | no: CANON ->
    SUBQ.B	#0x1,D2                              | 19 digits used?
    BNE.B	FP68K_SIGDIGS                         | no: next digit ->
    MOVE.B	#0xF,D7                              | TRAILDIG: the 20th digit ...
    AND.B	(A4),D7                               | ... in D7.B: lost digits for rounding
    BRA.B	FP68K_DONEDIG                         | -> DONEDIG
| ----------------------------------------------------------
| FP68K_CANONTOP: fewer than 19 digits -- append zeros (* 10)
| while the exponent is above 27 (exact scaling limit).
FP68K_CANONTOP:
    CMPI.W	#0x1B,D3                             | exponent at most 27?
    BLE.B	FP68K_DONEDIG                         | yes: DONEDIG ->
    BSR.B	FP68K_DIG10                           | append a zero: * 10 ...
    SUBQ.W	#0x1,D3                              | ... and exponent - 1
FP68K_CANON:
    SUBQ.W	#0x1,D2                              | CANON: digit positions left?
    BNE.B	FP68K_CANONTOP                        | yes: CANONTOP ->
FP68K_DONEDIG:
    MOVE.W	#0x403E,D0                           | DONEDIG: exponent 63 (biased): D4:D5 is an integer
    TST.B	(A2)                                  | d.sgn negative?
    BEQ.B	FP68K_DONEDIG_1                       | no ->
    BSET	#0xF,D0                                | sign
FP68K_DONEDIG_1:
    BSR.B	FP68K_TOA3                            | TOA3: (unnormalized) extended at (A3)
    BSR.B	FP68K_DBCORE                          | DBCORE: * 10^d.exp
| FP68K_DBSTORE: convert the extended at (A3) to the
| destination format (a recursive EXT2 call), drop the frame, return
| through POP2.
FP68K_DBSTORE:
    SWAP.W	D6                                   | the opword back
    ANDI.W	#0x3800,D6                           | its format bits ...
    ORI.W	#0x10,D6                              | ... with OPEXT2: convert from extended
    PEA.L	(A3)                                  | src: the extended
    MOVE.L	0xA(A6),-(SP)                        | dst: address 1
    MOVE.W	D6,-(SP)                             | opword
    BSR.W	FP68K_REFP68K                         | REFP68K
    ADDA.W	#0x14,SP                             | drop the frame
    BRA.W	FP68K_POP2                            | -> POP2
| ----------------------------------------------------------
| FP68K_TOA3: store D0.W:D4:D5 as an extended at (A3).
FP68K_TOA3:
    MOVE.W	D0,(A3)+                             | sign and exponent
    MOVE.L	D4,(A3)+                             | significand high
    MOVE.L	D5,(A3)                              | significand low
    SUBQ.L	#0x6,A3                              | A3 back to the start
    RTS                                         | return: extended D0.W:D4:D5 stored at (A3) (TOA3)
| ----------------------------------------------------------
| FP68K_DBCORE -- common core of both conversions (steps B4-
| B7 / D5-D8 of Coonen's algorithms): compute 10^|D3| (POW10) with the
| rounding direction set so that the scale error goes the safe way,
| multiply or divide the value at (A3) by it (toward zero), then OR the
| inexact information (rounding errors, lost digits D7.B) into its last
| bit: an added half-ulp for directed rounding, a jammed LSB for nearest
| (jam1lsb). The caller's modes are restored, the new flags kept.
FP68K_DBCORE:
    MOVE.B	(A0),D6                              | D6 = environment high byte (direction, flags)
    MOVE.B	D6,-(SP)                             | save it
    ANDI.B	#0x60,D6                             | rounding direction
    BEQ.B	FP68K_DBCORE_51                       | nearest ->
    MOVEQ.L	#0x40,D1                            | assume downward for the scale factor
    TST.B	(A3)                                  | value negative?
    BPL.B	FP68K_DBCORE_30                       | no ->
    CMPI.B	#0x40,D6                             | negative and downward?
    BEQ.B	FP68K_DBCORE_37                       | yes: upward for the factor ->
    BRA.B	FP68K_DBCORE_40                       | -> sign of the exponent
| ----------------------------------------------------------
| FP68K_DBCORE_51 (Apple DBCORE @51): to nearest -- clear the flags.
FP68K_DBCORE_51:
    MOVE.B	D6,(A0)                              | nearest, flags cleared
    BRA.B	FP68K_DBCORE_50                       | -> scale
| ----------------------------------------------------------
|
| FP68K_DBCORE_30
|
FP68K_DBCORE_30:
    CMPI.B	#0x20,D6                             | positive and upward?
    BNE.B	FP68K_DBCORE_40                       | no ->
FP68K_DBCORE_37:
    EORI.B	#0x60,D1                             | upward for the factor
FP68K_DBCORE_40:
    TST.W	D3                                    | negative exponent (a division)?
    BPL.B	FP68K_DBCORE_43                       | no ->
    EORI.B	#0x60,D1                             | flip upward <-> downward
FP68K_DBCORE_43:
    MOVE.B	D1,(A0)                              | direction for POW10, flags cleared
FP68K_DBCORE_50:
    LEA.L	0xA(A3),A1                            | A1 = 10(A3): the factor
    BSR.W	FP68K_POW10                           | POW10: 10^|D3|
    ORI.B	#0x60,(A0)                            | scale toward zero
    PEA.L	0xA(A3)                               | src: the factor
    PEA.L	(A3)                                  | dst: the value
    MOVEQ.L	#0x4,D0                             | OPMUL ...
    TST.W	D3                                    | ... for a positive exponent
    BPL.B	FP68K_DBCORE_5                        | ...
    MOVEQ.L	#0x6,D0                             | OPDIV for a negative one
FP68K_DBCORE_5:
    MOVE.W	D0,-(SP)                             | opword
    BSR.W	FP68K_REFP68K                         | REFP68K: scale
    BTST	#0x4,(A0)                              | inexact (power, multiply or divide)?
    SNE.B	D0                                    | ...
    TST.B	D7                                    | lost digits (D7.B)?
    SNE.B	D7                                    | ...
    OR.B	D7,D0                                  | D0 = $FF if either
    MOVE.B	(A0),D1                              | new environment high byte ...
    ANDI.B	#0x1F,D1                             | ... its flags ...
    OR.B	(SP)+,D1                               | ... + the old direction and flags
    MOVE.B	D1,(A0)                              | store
    NEG.B	D0                                    | 0 or 1
    BEQ.B	FP68K_DBCORERETURN                    | exact: done ->
    BSET	#0x4,(A0)                              | inexact (for lost digits)
    TST.B	D6                                    | rounding to nearest?
    BEQ.B	FP68K_JAM1LSB                         | yes: jam a 1 into the LSB ->
    CMPI.B	#0x60,D6                             | toward zero?
    BEQ.B	FP68K_DBCORERETURN                    | yes: ignore the extra information ->
    MOVE.L	#0x1,-(SP)                           | directed: add half an ulp: low 32 bits 1 ...
    CLR.L	-(SP)                                 | ... high 32 bits 0 ...
    MOVE.W	(A3),-(SP)                           | ... sign/exponent of the value ...
    SUBQ.W	#0x1,(SP)                            | ... - 1, but watch for ...
    BCS.B	FP68K_MINEXP                          | ... 0000 -> FFFF ...
    BVC.B	FP68K_NOTMINEXP                       | ... and 8000 -> 7FFF
FP68K_MINEXP:
    ADDQ.W	#0x1,(SP)                            | MINEXP: keep the minimum exponent
FP68K_NOTMINEXP:
    PEA.L	(SP)                                  | src: the half-ulp
    PEA.L	(A3)                                  | dst: the value
    CLR.W	-(SP)                                 | FOADD (0)
    BSR.W	FP68K_REFP68K                         | REFP68K
    ADDA.W	#0xA,SP                              | drop the half-ulp
    BRA.B	FP68K_DBCORERETURN                    | -> return
| ----------------------------------------------------------
| FP68K_JAM1LSB: set the LSB of a finite result.
FP68K_JAM1LSB:
    MOVE.W	(A3),D0                              | sign/exponent: watch for $7FFF and $FFFF ...
    ADDQ.W	#0x1,D0                              | ...
    ADD.W	D0,D0                                 | ... (0 after these two)
    BEQ.B	FP68K_DBCORERETURN                    | infinity/NaN: leave it ->
    BSET	#0x0,0x9(A3)                           | set the LSB
FP68K_DBCORERETURN:
    RTS                                         | return: scaled value at (A3), modes restored (DBCORE)
| -------------------------------------------------------------------------
| FP68K_TAB10: powers of ten for POW10, 7 words per entry: N, the
| rounding error of the table value (+1 rounded up, -1 down, 0 exact),
| then 10^N in extended. Searched from the top entry (POWER_TBL, Apple
| TAB10E) down.
| -------------------------------------------------------------------------
FP68K_TAB10:
    .short	14,0,0x402D,0xB5E6,0x20F4,0x8000,0x0000 | 10^14, exact
    .short	27,0,0x4058,0xCECB,0x8F27,0xF420,0x0F3A | 10^27, exact
    .short	55,1,0x40B5,0xD0CF,0x4B50,0xCFE2,0x0766 | 10^55, rounded up
    .short	108,1,0x4165,0xDA01,0xEE64,0x1A70,0x8DEA | 10^108, rounded up
    .short	206,-1,0x42AB,0x9F79,0xA169,0xBD20,0x3E41 | 10^206, rounded down
    .short	412,1,0x4557,0xC6B0,0xA096,0xA952,0x02BE | 10^412, rounded up
    .short	824,1,0x4AB0,0x9A35,0xB246,0x41D0,0x5953 | 10^824, rounded up
    .short	1648,1,0x5561,0xB9C9,0x4B7F,0xA8D7,0x6515 | 10^1648, rounded up
POWER_TBL:
    .short	3296,1,0x6AC4,0x86D4,0x8D66,0x26C2,0x7EEC | 10^3296, rounded up
| FP68K_POW10 -- 10^|D3| into the extended at (A1): below
| 15 straight from TAB10S, else the product of TAB10 entries (exponents
| above 5000 are held at 5000: overflow), each corrected by its rounding
| error when that would go against the rounding direction. Changes D0-D2,
| A2; D1 bit 31 set after the first factor (PTMUL multiplies from then
| on). An inexact table value sets the inexact flag directly.
FP68K_POW10:
    MOVEQ.L	#0x9,D1                             | D1 = 9 TAB10 entries (D1.hi = 0: first factor)
    MOVE.W	D3,D0                                | exponent ...
    BPL.B	FP68K_POW10_1                         | ...
    NEG.W	D0                                    | ... absolute value
FP68K_POW10_1:
    CMPI.W	#0xF,D0                              | below 15?
    BCS.B	FP68K_PTQUICK                         | yes: straight from TAB10S (PTQUICK) ->
    CMPI.W	#0x1388,D0                           | above 5000?
    BCS.B	FP68K_POW10_10                        | no ->
    MOVE.W	#0x1388,D0                           | 5000: overflows anyway
FP68K_POW10_10:
    LEA.L	POWER_TBL(PC),A2                      | A2 = the top TAB10 entry (TAB10E)
| FP68K_PTLOOP: next table entry.
FP68K_PTLOOP:
    CMP.W	(A2),D0                               | exponent vs the entry's N
    BCS.B	FP68K_PTSKIP                          | smaller: skip the entry (PTSKIP) ->
    SUB.W	(A2)+,D0                              | exponent - N; A2 -> the error word
    TST.W	(A2)                                  | an inexact table value?
    BEQ.B	FP68K_PTLOOP_31                       | exact: use it ->
    BSET	#0x4,(A0)                              | inexact flag, directly
    BTST	#0x6,(A0)                              | RNDHI: downward or toward zero?
    BEQ.B	FP68K_PTLOOP_13                       | no ->
    TST.W	(A2)                                  | rounded down (error <= 0)?
    BLE.B	FP68K_PTLOOP_31                       | yes: fine for these directions ->
    BRA.B	FP68K_PTLOOP_15                       | rounded up: correct it ->
| ----------------------------------------------------------
|
| FP68K_PTLOOP_13
|
FP68K_PTLOOP_13:
    BTST	#0x5,(A0)                              | RNDLO (with RNDHI clear): upward?
    BEQ.B	FP68K_PTLOOP_31                       | no: nearest, as it is ->
    TST.W	(A2)                                  | rounded up (error >= 0)?
    BGE.B	FP68K_PTLOOP_31                       | yes: fine ->
| FP68K_PTLOOP_15 (Apple POW10 @15): correct the table value by one LSB, on
| a copy on the stack.
FP68K_PTLOOP_15:
    MOVE.L	A2,-(SP)                             | save the pointer to the error word
    MOVE.W	0xA(A2),-(SP)                        | copy: the low significand word ...
    TST.W	(A2)+                                 | ... error +1 or -1; A2 -> the value
    BPL.B	FP68K_PTLOOP_21                       | +1 (rounded up): subtract 1 ->
    ADDQ.W	#0x1,(SP)                            | -1: add 1 to the LSB
    BRA.B	FP68K_PTLOOP_23                       | ...
| ----------------------------------------------------------
|
| FP68K_PTLOOP_21
|
FP68K_PTLOOP_21:
    SUBQ.W	#0x1,(SP)                            | subtract 1 from the LSB
FP68K_PTLOOP_23:
    MOVE.L	0x4(A2),-(SP)                        | the middle 32 significand bits
    MOVE.L	(A2),-(SP)                           | exponent and the high 16 bits
    MOVEA.L	SP,A2                               | A2 = the corrected copy
    BSR.B	FP68K_PTMUL                           | PTMUL
    ADDQ.L	#0x8,SP                              | drop the copy ...
    ADDQ.L	#0x2,SP                              | ...
    MOVEA.L	(SP)+,A2                            | A2 = the error word again
    ADDQ.L	#0x2,A2                              | A2 -> the value
    BRA.B	FP68K_PTLOOP_33                       | ...
| ----------------------------------------------------------
| FP68K_PTLOOP_31 (Apple POW10 @31): the table value as it is.
FP68K_PTLOOP_31:
    ADDQ.L	#0x2,A2                              | skip the error word
    BSR.B	FP68K_PTMUL                           | PTMUL
FP68K_PTLOOP_33:
    SUBQ.L	#0x4,A2                              | A2 -> the entry
FP68K_PTSKIP:
    SUBA.W	#0xE,A2                              | PTSKIP: the next lower entry (14 bytes down)
    SUBQ.W	#0x1,D1                              | entries left
    BNE.B	FP68K_PTLOOP                          | ...
FP68K_PTQUICK:
    MULU.W	#0xA,D0                              | PTQUICK: rest (0-14) * 10
    LEA.L	FP68K_TAB10S(PC,D0.W),A2              | A2 = 10^rest in TAB10S
| FP68K_PTMUL: (A1) := (A2), or (A1) * (A2) when D1 bit 31
| is set.
FP68K_PTMUL:
    TST.L	D1                                    | first factor (D1 bit 31 clear)?
    BPL.B	FP68K_PTMUL_42                        | yes: copy it ->
    PEA.L	(A2)                                  | src: the power
    PEA.L	(A1)                                  | dst: the product so far
    MOVE.W	#0x4,-(SP)                           | OPMUL
    BSR.W	FP68K_REFP68K                         | REFP68K
    RTS                                         | return: (A1) := (A1) * (A2) (PTMUL)
| ----------------------------------------------------------
|
| FP68K_PTMUL_42
|
FP68K_PTMUL_42:
    MOVE.W	(A2)+,(A1)+                          | (A1) := (A2): sign/exponent
    MOVE.L	(A2)+,(A1)+                          | significand
    MOVE.L	(A2),(A1)                            | ...
    SUBQ.L	#0x6,A1                              | A1 back
    SUBQ.L	#0x6,A2                              | A2 back
    BSET	#0x1F,D1                               | multiply from now on
    RTS                                         | return: first factor copied to (A1); multiply from now on
| -------------------------------------------------------------------------
| FP68K_TAB10S: 10^0 .. 10^14, exact, in extended.
| -------------------------------------------------------------------------
FP68K_TAB10S:
    .short	0x3FFF,0x8000,0x0000,0x0000,0x0000   | 10^0 = 1
    .short	0x4002,0xA000,0x0000,0x0000,0x0000   | 10^1 = 10
    .short	0x4005,0xC800,0x0000,0x0000,0x0000   | 10^2 = 100
    .short	0x4008,0xFA00,0x0000,0x0000,0x0000   | 10^3 = 1000
    .short	0x400C,0x9C40,0x0000,0x0000,0x0000   | 10^4 = 10000
    .short	0x400F,0xC350,0x0000,0x0000,0x0000   | 10^5 = 100000
    .short	0x4012,0xF424,0x0000,0x0000,0x0000   | 10^6 = 1000000
    .short	0x4016,0x9896,0x8000,0x0000,0x0000   | 10^7 = 10000000
    .short	0x4019,0xBEBC,0x2000,0x0000,0x0000   | 10^8 = 100000000
    .short	0x401C,0xEE6B,0x2800,0x0000,0x0000   | 10^9 = 1000000000
    .short	0x4020,0x9502,0xF900,0x0000,0x0000   | 10^10 = 10000000000
    .short	0x4023,0xBA43,0xB740,0x0000,0x0000   | 10^11 = 100000000000
    .short	0x4026,0xE8D4,0xA510,0x0000,0x0000   | 10^12 = 1000000000000
    .short	0x402A,0x9184,0xE72A,0x0000,0x0000   | 10^13 = 10000000000000
    .short	0x402D,0xB5E6,0x20F4,0x8000,0x0000   | 10^14 = 100000000000000
| ----------------------------------------------------------
| FP68K_B2D -- binary to decimal (Num2Dec): the value at
| (A2) (format in the opword) to the decimal record at (A1), by the
| DecForm at address 3 (style: 0 float, nonzero fixed; digits). NaN:
| 'N' and 16 hex digits; zero '0', infinity 'I'; else estimate
| floor(log10|x|) (BD1), scale to an integer of the wanted digits
| (DBCORE, rint), retry if the estimate was low, '?' if a fixed result
| has more than 19 digits, then the digits (BD9). Frame (A3): 30 bytes.
FP68K_B2D:
    MOVE.W	D6,D0                                | D0 = opword: source format field next (B2D)
    ROL.W	#0x6,D0                               | source format * 2 in bits 3-1
    MOVEQ.L	#0x0,D2                             | D2 := 0: NaN flag for UNPACK
    MOVE.L	D2,D3                                | D3 := 0: number case
    MOVE.L	D2,D6                                | D6 := 0: sign and flags
    MOVE.L	D2,D7                                | D7 := 0: round bits
    MOVEA.L	A2,A3                               | A3 = address 2, the binary value
    BSR.W	FP68K_UNPACK                          | UNPACK it
    MOVE.W	A4,D0                                | D0 = its exponent
    MOVEA.L	0x12(A6),A4                         | A4 = address 3, the DecForm
    SUBA.W	#0x1E,SP                             | frame: 3 extendeds
    MOVEA.L	SP,A3                               | A3 = the frame
    ROL.B	#0x1,D6                               | sign to bit 0
    MOVE.B	D6,(A1)                              | d.sgn (high byte)
    MOVE.B	#0x1,0x4(A1)                         | d.sig length 1 by default
    TST.W	D2                                    | a NaN?
    BEQ.B	FP68K_B2D_10                          | no ->
    ADDQ.L	#0x4,A1                              | A1 -> d.sig
    MOVE.B	#0x11,(A1)+                          | length 17: 'N' and 16 hex digits
    MOVE.B	#0x4E,(A1)+                          | d.sig[1] := 'N': the sig of a NaN
    BSR.B	FP68K_B2D_31                          | the high 8 hex digits from D4
    MOVE.L	D5,D4                                | the low half ...
    BSR.B	FP68K_B2D_31                          | ... the next 8
    SUBA.W	#0x16,A1                             | A1 back to the record
    BRA.W	FP68K_BDFIN                           | -> BDFIN
| ----------------------------------------------------------
| FP68K_B2D_31 (Apple B2D @31): D4 as 8 hex digits to (A1)+.
FP68K_B2D_31:
    MOVEQ.L	#0x8,D0                             | 8 digits
FP68K_B2D_33:
    ROL.L	#0x4,D4                               | next nibble, high to low
    MOVEQ.L	#0xF,D1                             | nibble mask
    AND.B	D4,D1                                 | D1 = nibble
    ORI.B	#0x30,D1                              | + '0'
    CMPI.B	#0x39,D1                             | beyond 9?
    BLE.B	FP68K_B2D_35                          | no ->
    ADDQ.B	#0x7,D1                              | A-F
FP68K_B2D_35:
    MOVE.B	D1,(A1)+                             | store it
    SUBQ.W	#0x1,D0                              | count
    BNE.B	FP68K_B2D_33                          | more ->
    RTS                                         | return: 8 hex digits of D4 stored at (A1)+
| ----------------------------------------------------------
| FP68K_B2D_10 (Apple B2D @10): zero ('0') or infinity ('I'), else BD1.
FP68K_B2D_10:
    TST.W	D3                                    | finite nonzero (D3 = 0)?
    BEQ.B	FP68K_BD1                             | yes: BD1 ->
    MOVEQ.L	#0x30,D0                            | '0' ...
    CMPI.W	#0x2,D3                              | ... for zero
    BEQ.B	FP68K_B2D_16                          | ...
    MOVEQ.L	#0x49,D0                            | 'I' for infinity
FP68K_B2D_16:
    MOVE.B	D0,0x5(A1)                           | the 1-character d.sig
    BRA.W	FP68K_BDFIN                           | -> BDFIN
| ----------------------------------------------------------
| FP68K_BD1 -- finite nonzero: log2|x| ~ exp.frac in D1;
| denormalize back to extended format and store at (A3); float style:
| D4 = floor(log10|x|) + 1 = log10(2) * log2|x| + 1 (16 bits suffice).
FP68K_BD1:
    MOVE.L	D4,D1                                | integer bit.fraction ...
    MOVE.W	D0,D1                                | ... exponent in the low word ...
    SUBI.W	#0x3FFF,D1                           | ... unbiased ...
    SWAP.W	D1                                   | ... exponent above int.frac ...
    ADD.W	D1,D1                                 | ... D1 = exp.frac, about log2|x|
    TST.W	D0                                    | negative exponent (normalized denormal)?
    BPL.B	FP68K_BD1_7                           | no ->
FP68K_BD1_3:
    LSR.L	#0x1,D4                               | denormalize again: shift right ...
    ROXR.L	#0x1,D5                              | ...
    ADDQ.W	#0x1,D0                              | ... exponent + 1 ...
    BMI.B	FP68K_BD1_3                           | ... up to 0
FP68K_BD1_7:
    ROR.W	#0x1,D6                               | sign to bit 15 ...
    OR.W	D6,D0                                  | ... of the exponent word
    BSR.W	FP68K_TOA3                            | TOA3: x at (A3)
    MOVEQ.L	#0x0,D4                             | D4 := 0: receives the log10 estimate
    TST.B	(A4)                                  | DecForm style fixed?
    BNE.B	FP68K_BD3                             | yes: no estimate needed ->
| estimate decimal exponent using log10(2) approximation
| log10(2) ~ 0x4D104D42 / 2^32 ~ 0.30103
    MOVE.L	#0x4D104D42,D0                       | log10(2) * 2^32, rounded down
    TST.L	D1                                    | log2|x| negative?
    BPL.B	FP68K_BD1_1                           | no ->
    ADDQ.W	#0x1,D0                              | yes: bump it, to be sure of the floor
FP68K_BD1_1:
    MOVE.L	D0,D4                                | D0 = A:B, D1 = X:Y
    SWAP.W	D4                                   | D4.W = A
    MULU.W	D1,D4                                | D4 = A * Y
    CLR.W	D4                                    | ...
    SWAP.W	D4                                   | D4.W = (A * Y).hi
    SWAP.W	D1                                   | D1.W = X
    MOVE.W	D1,D5                                | ...
    MULS.W	D0,D5                                | D5 = B * X (signed)
    SWAP.W	D5                                   | ...
    EXT.L	D5                                    | D5 = (B * X).hi with sign
    ADD.L	D5,D4                                 | + (no carry or borrow possible)
    SWAP.W	D0                                   | D0.W = A
    MULS.W	D1,D0                                | D0 = A * X
    ADD.L	D0,D4                                 | +
    SWAP.W	D4                                   | D4.W = floor(log10|x|)
    ADDQ.W	#0x1,D4                              | + 1: digits left of the point
| FP68K_BD3: decimal exponent = -(digits - D4); keep a copy of
| x at 20(A3) for a retry; scale, round to an integer, compare with
| 10^N (N = digits, fixed: 19).
FP68K_BD3:
    BSR.W	FP68K_BDGETCNT                        | D3 = digits (BDGETCNT)
    SUB.W	D4,D3                                 | scale = digits - D4 (D4 = 0 for fixed)
    MOVEA.L	0xA(A6),A1                          | A1 = address 1, the decimal record
    MOVE.W	D3,0x2(A1)                           | d.exp := -scale ...
    NEG.W	0x2(A1)                               | ...
    MOVE.W	(A3),0x14(A3)                        | keep x at 20(A3) for a retry
    MOVE.L	0x2(A3),0x16(A3)                     | ...
    MOVE.L	0x6(A3),0x1A(A3)                     | ...
    BSR.W	FP68K_DBCORE                          | DBCORE: x * 10^scale
    PEA.L	(A3)                                  | round it to an integer ...
    MOVE.W	#0x14,-(SP)                          | ... OPRINT, in the caller's direction
    BSR.W	FP68K_REFP68K                         | REFP68K
    LEA.L	0xA(A3),A1                            | A1 = 10(A3): 10^N above the scaled value
    TST.B	(A4)                                  | style?
    BNE.B	FP68K_BD3_3                           | fixed ->
    BSR.B	FP68K_BDGETCNT                        | float: N = digits
    BRA.B	FP68K_BD3_5                           | ...
| ----------------------------------------------------------
|
| FP68K_BD3_3
|
FP68K_BD3_3:
    MOVEQ.L	#0x13,D3                            | fixed: N = 19
FP68K_BD3_5:
    BSR.W	FP68K_POW10                           | POW10: 10^N at (A1)
    MOVE.W	(A3),D0                              | compare |scaled| with 10^N: exponents ...
    BCLR	#0xF,D0                                | ...
    CMP.W	(A1),D0                               | ...
    BNE.B	FP68K_BD3_13                          | ...
    MOVE.L	0x2(A3),D0                           | significands, high ...
    CMP.L	0x2(A1),D0                            | ...
    BNE.B	FP68K_BD3_13                          | ...
    MOVE.L	0x6(A3),D0                           | ... and low
    CMP.L	0x6(A1),D0                            | ...
FP68K_BD3_13:
    BCS.B	FP68K_BD85                            | below 10^N: fine (BD85) ->
    TST.B	(A4)                                  | too big: style?
    BNE.B	FP68K_BD3_15                          | fixed: '?' ->
    ADDQ.W	#0x1,D4                              | float: the estimate was low by one
    MOVE.W	0x14(A3),(A3)                        | restore x ...
    MOVE.L	0x16(A3),0x2(A3)                     | ...
    MOVE.L	0x1A(A3),0x6(A3)                     | ...
    BRA.B	FP68K_BD3                             | ... and scale again (BD3)
| ----------------------------------------------------------
| FP68K_BD3_15 (Apple BD3 @15): fixed style, too many digits -- '?'.
FP68K_BD3_15:
    MOVEA.L	0xA(A6),A1                          | A1 = the decimal record
    MOVE.B	#0x3F,0x5(A1)                        | d.sig := '?'
    BRA.W	FP68K_BDFIN                           | -> BDFIN
| ----------------------------------------------------------
| FP68K_BDGETCNT -- D3 = the digit count of the DecForm:
| fixed style as given, float style held to 1..19.
FP68K_BDGETCNT:
    MOVE.W	0x2(A4),D3                           | D3 = DecForm digits
    TST.B	(A4)                                  | fixed style?
    BNE.B	FP68K_BDGETCNT_3                      | yes: as it is ->
    TST.W	D3                                    | float: at most 0?
    BLE.B	FP68K_BDGETCNT_1                      | yes: 1 ->
    CMPI.W	#0x13,D3                             | more than 19?
    BLE.B	FP68K_BDGETCNT_3                      | no ->
    MOVEQ.L	#0x13,D3                            | 19
    BRA.B	FP68K_BDGETCNT_3                      | -> return
| ----------------------------------------------------------
|
| FP68K_BDGETCNT_1: force minimum 1 digit
|
FP68K_BDGETCNT_1:
    MOVEQ.L	#0x1,D3                             | minimum 1 significant digit
FP68K_BDGETCNT_3:
    RTS                                         | return D3 = digit count (float: 1..19) (BDGETCNT)
| ----------------------------------------------------------
| FP68K_BD85: float style -- a scaled value below
| 10^(N-1) is replaced by 10^(N-1).
FP68K_BD85:
    TST.B	(A4)                                  | fixed style?
    BNE.B	FP68K_BD9                             | yes: BD9 ->
    BSR.B	FP68K_BDGETCNT                        | N = digits
    SUBQ.W	#0x1,D3                              | N - 1
    BSR.W	FP68K_POW10                           | POW10: 10^(N-1) at (A1)
    MOVE.W	(A3),D0                              | compare |scaled| with it ...
    BCLR	#0xF,D0                                | ...
    CMP.W	(A1),D0                               | ...
    BNE.B	FP68K_BD85_13                         | ...
    MOVE.L	0x2(A3),D0                           | ...
    CMP.L	0x2(A1),D0                            | ...
    BNE.B	FP68K_BD85_13                         | ...
    MOVE.L	0x6(A3),D0                           | ...
    CMP.L	0x6(A1),D0                            | ...
FP68K_BD85_13:
    BCC.B	FP68K_BD9                             | not below: BD9 ->
    MOVE.W	(A1),(A3)                            | below: use 10^(N-1) ...
    MOVE.L	0x2(A1),0x2(A3)                      | ...
    MOVE.L	0x6(A1),0x6(A3)                      | ...
    NOP                                         | (no operation) and fall into BD9
FP68K_BD9:
    MOVEA.L	0xA(A6),A1                          | BD9: A1 = the decimal record
    MOVE.W	(A3),D3                              | D3 = sign/exponent of the scaled value
    MOVE.L	0x2(A3),D1                           | D1 = high significand
    BNE.B	FP68K_BD9_3                           | nonzero ->
    MOVE.B	#0x30,0x5(A1)                        | zero (fixed style): d.sig := '0'
    BRA.W	FP68K_BDFIN                           | -> BDFIN
| ----------------------------------------------------------
| FP68K_BD9_3 (Apple BD9 @3): right-align the integer (exponent 63),
| divide by 10^19 into a fraction, + 1 ulp (so .99999 does not chop to
| the wrong digit), then 19 times * 10: each digit that falls off the
| left, leading zeros skipped.
FP68K_BD9_3:
    MOVE.L	0x6(A3),D2                           | D2 = low significand
    BCLR	#0xF,D3                                | drop the sign
    SUBI.W	#0x403E,D3                           | exponent - 63 (biased)
    BEQ.B	FP68K_BD9_7                           | 0: a 64-bit integer already ->
FP68K_BD9_5:
    LSR.L	#0x1,D1                               | right-align: shift right ...
    ROXR.L	#0x1,D2                              | ...
    ADDQ.W	#0x1,D3                              | ... up to exponent 63
    BMI.B	FP68K_BD9_5                           | ...
FP68K_BD9_7:
| divide 64-bit integer by 10^19 to extract decimal digits
| divisor = 10^19 = $8AC72304:89E80000
    MOVE.L	#0x8AC72304,D3                       | divisor D3:A2 = 10^19 ...
    MOVEA.L	#0x89E80000,A2                      | ...
    MOVEQ.L	#0x41,D0                            | 65 quotient bits
    BSR.W	FP68K_RESTORE                         | RESTORE: D4:D5 = the integer / 10^19, a fraction
    ADDQ.L	#0x1,D5                              | + 1 ulp so that .99999 does not chop wrong ...
    ADDX.L	D0,D4                                | ... (D0 = 0 after RESTORE)
    ADDQ.L	#0x4,A1                              | A1 -> d.sig
    MOVEA.L	A1,A2                               | A2 = output pointer ...
    CLR.B	(A2)+                                 | ... after the length byte := 0
    MOVEQ.L	#0x13,D6                            | 19 digits
| FP68K_BD9_11: extract decimal digits via multiply-by-10 (x*10 = x*8 + x*2)
FP68K_BD9_11:
    ADD.L	D5,D5                                 | fraction * 2 ...
    ADDX.L	D4,D4                                | ...
    ADDX.W	D0,D0                                | ... (the integer part in D0)
    MOVE.L	D5,D3                                | save * 2
    MOVE.L	D4,D2                                | ...
    MOVE.W	D0,D1                                | ...
    ADD.L	D5,D5                                 | * 4
    ADDX.L	D4,D4                                | ...
    ADDX.W	D0,D0                                | ...
    ADD.L	D5,D5                                 | * 8
    ADDX.L	D4,D4                                | ...
    ADDX.W	D0,D0                                | ...
    ADD.L	D3,D5                                 | * 8 + * 2 = * 10
    ADDX.L	D2,D4                                | ...
    ADDX.W	D1,D0                                | D0.B = the digit that fell off the left
    TST.W	D0                                    | zero so far (no digit seen: high byte 0 too)?
    BEQ.B	FP68K_BD9_12                          | yes: a leading zero ->
    ORI.L	#0x130,D0                             | ASCII digit; bit 8 marks 'first digit seen'
    MOVE.B	D0,(A2)+                             | store it
    CLR.B	D0                                    | keep the mark in the high byte
    ADDQ.B	#0x1,(A1)                            | d.sig length + 1
FP68K_BD9_12:
    SUBQ.B	#0x1,D6                              | count
    BNE.B	FP68K_BD9_11                          | more ->
FP68K_BDFIN:
    ADDA.W	#0x1E,SP                             | BDFIN: drop the frame
    BRA.W	FP68K_POP3                            | -> POP3: three addresses

