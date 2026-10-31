| =========================================================================
| PACK 5 -- Elems68K, the SANE elementary functions package
| =========================================================================
| ROM offsets +0x1B11A..+0x1C17F: the 8-byte header of the ROM resource at
| +0x1B11A, then the package, $105E bytes from +0x1B122 (_PACK_5_ in
| MacSEROM.lst) on; type PACK, ID 5, no name, attributes $58 (resSysHeap,
| resLocked, resProtected). The same in both SE ROMs.
|
| Elementary functions, compound interest and present value by Jerome T.
| Coonen, from Pascal code by David Hough and Colin McMaster and (trigs)
| Kenton Hanson (Apple's ELEMS68K.a). Version word 1, although the change
| history calls the lock fix of 26 Mar 85 "Version 2". The code is the
| PACK 5 of the Mac Plus ROM, assembled with the MPW assembler
| ("<C206/09oct86> bbm Modified to mpw aincludes"), which made the
| CLR.L D3 at START a MOVEQ #0,D3: that is the only byte difference. It
| follows Apple's System 7.1 sources Elems68K.a (= Elems68K1.a, 2, 3 and
| the constants Elems68KC.a) instruction for instruction, with ROMRSRC = 0:
| the package locks its own handle (AppPacks+20) for the call, which
| Apple dropped for the ROM resource only in July 1989 (Elems68K.a 1.2).
|
| Calling convention (Apple Numerics Manual; IM IV): _Elems68K = _Pack5
| ($A9EC) with the operand addresses and then the opcode word pushed:
|   (SP): return, 4(SP): opcode, 6(SP): dst address, 10(SP): src
|   address (x^i, x^y, Compound, Annuity), 14(SP): src2 address (Compound,
|   Annuity); the package pops opcode and addresses, preserves all
|   registers and saves/restores the caller's environment (FPROCENTRY,
|   FPROCEXIT), so only the exceptions of the result are signaled.
| Opcode: bit 15 = two or more addresses (OP2ADRS), bit 14 = three
| (OP3ADRS), bits 7-1 = the index into ELEMSTAB: $00 ln(x), $02 log2(x),
| $04 ln(1+x), $06 log2(1+x), $08 e^x, $0A 2^x, $0C e^x - 1, $0E 2^x - 1,
| $8010 x^i (i a 16-bit integer), $8012 x^y, $C014 Compound(r, n) =
| (1+r)^n, $C016 Annuity(r, n) = (1 - (1+r)^-n) / r, $18 sin, $1A cos,
| $1C tan, $1E atan, $20 RandomX. All operands are extended (80 bits)
| except the integer of x^i; the result replaces the dst.
| Invalid operations deliver a quiet NaN with code 33 (NANTRIG), 36
| (NANLOG), 37 (NANPOWER) or 38 (NANFINAN).
|
| Frame (LINK A6,#-48): 4(A6) return address, 8 opcode, 10 dst address,
| 14 src, 18 src2; -2(A6) ENV (the caller's environment), -4 I and -6 J
| (integer cells), -16 W, -26 X, -36 Y, -46 Z (extended cells), -48
| STLOCK (the handle's saved flags byte). Each function computes in A4
| (the dst) and the cells and calls FP68K (_FP68K, PACK 4) with operand
| addresses on the stack: a push comment names src and dst, the
| _FP68K line gives the operation; FCMPX leaves the comparison of dst
| with src in the CCR for the branches (FBccS names from SANEMacs.a).
| Recursive calls (x^y, Compound, Annuity) re-enter at _PACK_5_.
|
| Labels: Apple's names from these sources with the prefix ELEMS_
| (ELEMS_START, ELEMS_XPWRY, the constants ELEMS_FPK1 ...); the targets
| of Apple's local labels are ELEMS_<label>_<n> for the @n that follows
| that label (e.g. ELEMS_CLASSIFY_1).
| Sources: Apple's Elems68K.a, Elems68K1.a, Elems68K2.a, Elems68K3.a,
| Elems68KC.a (Mac OS 7.1 tree, Toolbox/SANE) and SANEMacs.a (opcodes,
| NaN codes, exception bits), the Apple Numerics Manual, Inside Macintosh
| IV ("SANE"), the Mac Plus PACK 5 (src/plus/resources/res_pack_5.s).
| =========================================================================

| -------------------------------------------------------------------------
| ROM resource header: a Memory Manager style block header (tag $C0 and
| the physical size, then a relative-handle field) in front of the
| resource data, as for every ROM resource.
| -------------------------------------------------------------------------
Resource_PACK_0005:
Resource_PACK_0005_Header:
    ROM_RESOURCE PACK_5                         | 8-byte resource header (include/romrsrc.inc)
| ----------------------------------------------------------
| Package header: branch to the entry, flags word, 'PACK', ID, version.
| Called by: the _Pack5 trap (_Elems68K, $A9EC); recursively by XPWRY
| (ELEMS_XPWRY), Compound (ELEMS_CMPTOFIN, ELEMS_CMPRESULT) and Annuity
| (ELEMS_ANNDOIT, ELEMS_ANNRESULT, ELEMS_ANNSPECIAL)
_PACK_5_:
    BRA.B       ELEMS_START                     | skip the package header to START
    .short      0x0000                          | flags word
    .ascii      "PACK"                          | resource type
    .short      0x0005                          | resource ID 5
    .short      0x0001                          | version 1
| ----------------------------------------------------------
| ELEMS_START -- the entry of _Elems68K: frame, registers,
| package locked; fetch the operand addresses and move the return address
| onto the deepest one (its old slot's high word = the byte count to pop at
| RESULTDELIVERED); classify the operands, save the caller's environment
| (FPROCENTRY), deliver NaN operands at once, else jump through ELEMSTAB.
| Registers from here on: A4 = dst address, D4 = src address (if any), D5 =
| src2 address (Compound, Annuity), else the dst address; D3 = opcode;
| D1 = class of dst/src2, D2 = class of src (15 if none), both minus FCINF
| (3) after the NaN check: -2/-1 NaN, 0 infinity, 1 zero, 2 normal,
| 3 denormal; bit 15 = sign of the operand.
ELEMS_START:
    LINK        A6,#-0x30                       | frame: ENV -2, I -4, J -6, cells W/X/Y/Z, STLOCK -48
    MOVEM.L     D0-D7/A0-A4,-(SP)               | preserve D0-D7/A0-A4: all registers are preserved
    MOVEQ.L     #0x0,D3                         | D3 := 0: error bits and opcode (CLR.L D3 in the source)
    MOVEA.L     (AppPacks_5).W,A0               | A0 = the PACK 5 handle (AppPacks+20)
    MOVE.B      (A0),-0x30(A6)                  | save its master pointer flags byte: the lock state (STLOCK)
    BSET        #0x7,(A0)                       | lock the package while it runs
    LEA.L       0x4(A6),A3                      | A3 -> the return address (STRET)
    LEA.L       0x8(A6),A0                      | A0 -> the opcode word (STOPCODE), then the operand addresses
    MOVE.W      (A0)+,D3                        | D3 = opcode; A0 -> the dst address
    BPL.B       ELEMS_DSTONLY                   | bit 15 (OP2ADRS) clear: one address only -> DSTONLY
    MOVEA.L     (A0)+,A4                        | A4 = dst address; A0 -> the src address
    MOVE.L      (A0),D4                         | D4 = src address
    BTST        #0xE,D3                         | three addresses (bit 14, OP3ADRS: Compound, Annuity)?
    BNE.B       ELEMS_HAVESRC2                  | yes -> HAVESRC2
    MOVE.L      (A3),(A0)                       | two addresses: return address onto the src address slot
    MOVE.W      #0xA,(A3)                       | KI2ADRS: pop 10 bytes (old return, opcode, dst)
    MOVE.L      A4,D5                           | D5 = dst address, as if it were src2
    MOVEQ.L     #0xF,D2                         | D2 = 15: a non-NaN src class, in case of x^i
    CMPI.W      #0x8010,D3                      | x^i (OPXPWRI)? its src is an integer, not to be classified
    BEQ.B       ELEMS_CLASSSKIP                 | yes -> CLASSSKIP
| CLASSCOM: classify the src
ELEMS_CLASSCOM:
    MOVEA.L     D4,A0                           | A0 = src address
    BSR.B       ELEMS_CLASSIFY                  | D0 = class of the src
    MOVE.W      D0,D2                           | D2 = src class
| CLASSSKIP
ELEMS_CLASSSKIP:
    BRA.B       ELEMS_CLASSDSTORSRC2            | -> classify the dst or src2
| HAVESRC2: three addresses (Compound, Annuity): src2 is the deepest
ELEMS_HAVESRC2:
    ADDQ.L      #0x4,A0                         | skip the src address
    MOVE.L      (A0),D5                         | D5 = src2 address
    MOVE.L      (A3),(A0)                       | return address onto the src2 address slot
    MOVE.W      #0xE,(A3)                       | KI3ADRS: pop 14 bytes (old return, opcode, dst, src)
    BRA.B       ELEMS_CLASSCOM                  | -> classify the src
| ----------------------------------------------------------
| ELEMS_CLASSIFY -- class of the extended at A0 (FCLASSX):
| D0.B = 1 signaling NaN, 2 quiet NaN, 3 infinity, 4 zero, 5 normal,
| 6 denormal; D0 bit 15 = the operand's sign. Uses cell I.
ELEMS_CLASSIFY:
    PEA.L       (A0)                            | src: the extended at A0
    PEA.L       -0x4(A6)                        | dst: cell I, receives the class
    MOVE.W      #0x1C,-(SP)                     | opword FCLASSX
    _FP68K                                      | I := class of (A0): -6..6, signed like the operand
    MOVE.W      -0x4(A6),D0                     | D0 = class
    BPL.B       ELEMS_CLASSIFY_1                | nonnegative operand ->
    NEG.W       D0                              | D0 = |class|
    ORI.W       #0x8000,D0                      | the operand's sign into bit 15
ELEMS_CLASSIFY_1:
    RTS                                         | return from CLASSIFY
| ----------------------------------------------------------
| ELEMS_DSTONLY -- one address (bit 15 of the opcode clear):
| the logarithms, exponentials, trig functions and RandomX.
ELEMS_DSTONLY:
    MOVEQ.L     #0xF,D2                         | D2 = 15: fake non-NaN src class
    MOVEA.L     (A0),A4                         | A4 = dst address
    MOVE.L      (A3),(A0)                       | return address onto the dst address slot
    MOVE.W      #0x6,(A3)                       | KI1ADRS: pop 6 bytes (old return, opcode)
    MOVE.L      A4,D5                           | D5 = dst address, as if it were src2
| CLASSDSTORSRC2: classify dst or src2, save the environment
ELEMS_CLASSDSTORSRC2:
    MOVEA.L     D5,A0                           | A0 = src2 or dst address
    BSR.B       ELEMS_CLASSIFY                  | D0 = its class
    MOVE.W      D0,D1                           | D1 = class of dst/src2
    PEA.L       -0x2(A6)                        | dst: cell ENV, receives the caller's environment
    MOVE.W      #0x17,-(SP)                     | opword FPROCENTRY
    _FP68K                                      | ENV := environment; flags and halts off, round to nearest
    SUBQ.B      #0x3,D2                         | src class - FCINF (3): negative for a NaN src
    BGE.B       ELEMS_NOT2NANS                  | src is no NaN ->
    MOVEA.L     D5,A0                           | src NaN: A0 = src2 or dst address
    MOVEA.L     A4,A1                           | A1 = dst address
    BSR.B       ELEMS_A0TOA1                    | (A4) := dst or src2 (bit copy)
    MOVE.L      D4,-(SP)                        | src: the src, a NaN
    PEA.L       (A4)                            | dst: (A4)
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := (A4) + src: FP68K picks the NaN to deliver
    BRA.B       ELEMS_NANEXIT                   | -> deliver
| NOT2NANS: the src is no NaN; the dst or src2 may be one
ELEMS_NOT2NANS:
    SUBQ.B      #0x3,D1                         | dst/src2 class - FCINF: negative for a NaN
    BGE.B       ELEMS_NONANS                    | no NaN at all ->
    MOVE.L      D5,-(SP)                        | src: the dst or src2, a NaN
    PEA.L       (A4)                            | dst: (A4)
    MOVE.W      #0xE,-(SP)                      | opword FX2X: a move that quiets a signaling NaN
    _FP68K                                      | (A4) := that NaN (invalid if it was signaling)
| NANEXIT
ELEMS_NANEXIT:
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver the NaN
| NONANS, LIFTOFF: no NaN operand; dispatch on the opcode
ELEMS_NONANS:
    MOVE.W      D3,D0                           | D0 = opcode
    ANDI.W      #0xFE,D0                        | OPMASK ($FE): the jump table index
    MOVE.W      ELEMS_ELEMSTAB(PC,D0.W),D0      | D0 = offset of the function from LIFTOFF (ELEMSTAB)
    JMP         ELEMS_NONANS(PC,D0.W)           | -> the function
| ----------------------------------------------------------
| ELEMS_ELEMSTAB -- offsets of the functions from LIFTOFF
| (ELEMS_NONANS), indexed by the opcode AND $FE.
ELEMS_ELEMSTAB:
    .short      ELEMS_LOGTOP-ELEMS_NONANS       | $00 FLNX     ln(x)        -> LOGTOP
    .short      ELEMS_LOGTOP-ELEMS_NONANS       | $02 FLOG2X   log2(x)      -> LOGTOP
    .short      ELEMS_LOGTOP-ELEMS_NONANS       | $04 FLN1X    ln(1+x)      -> LOGTOP
    .short      ELEMS_LOGTOP-ELEMS_NONANS       | $06 FLOG21X  log2(1+x)    -> LOGTOP
    .short      ELEMS_EXPTOP-ELEMS_NONANS       | $08 FEXPX    e^x          -> EXPTOP
    .short      ELEMS_EXPTOP-ELEMS_NONANS       | $0A FEXP2X   2^x          -> EXPTOP
    .short      ELEMS_EXP1TOP-ELEMS_NONANS      | $0C FEXP1X   e^x - 1      -> EXP1TOP
    .short      ELEMS_EXP1TOP-ELEMS_NONANS      | $0E FEXP21X  2^x - 1      -> EXP1TOP
    .short      ELEMS_XPWRITOP-ELEMS_NONANS     | $10 FXPWRI   x^i ($8010)  -> XPWRITOP
    .short      ELEMS_XPWRYTOP-ELEMS_NONANS     | $12 FXPWRY   x^y ($8012)  -> XPWRYTOP
    .short      ELEMS_COMPOUNDTOP-ELEMS_NONANS  | $14 FCOMPOUND ($C014)     -> COMPOUNDTOP
    .short      ELEMS_ANNUITYTOP-ELEMS_NONANS   | $16 FANNUITY ($C016)      -> ANNUITYTOP
    .short      ELEMS_SINTOP-ELEMS_NONANS       | $18 FSINX    sin(x)       -> SINTOP
    .short      ELEMS_COSTOP-ELEMS_NONANS       | $1A FCOSX    cos(x)       -> COSTOP
    .short      ELEMS_TANTOP-ELEMS_NONANS       | $1C FTANX    tan(x)       -> TANTOP
    .short      ELEMS_ATANTOP-ELEMS_NONANS      | $1E FATANX   atan(x)      -> ATANTOP
    .short      ELEMS_RANDTOP-ELEMS_NONANS      | $20 FRANDX   random(x)    -> RANDTOP
| ----------------------------------------------------------
| ELEMS_A0TOA1 -- copy the extended (10 bytes) at A0 to A1;
| A1 is reset to the head of the copy, A0 is left 8 bytes on.
| Called by: ELEMS_DSTONLY, ELEMS_LOG12R, ELEMS_LOG2R
| (LOG2R), ELEMS_LOGAPPROX, ELEMS_P0STUFF (and 18 more)
ELEMS_A0TOA1:
    MOVE.L      (A0)+,(A1)+                     | sign/exponent and significand bits 63-48
    MOVE.L      (A0)+,(A1)+                     | significand bits 47-16
    MOVE.W      (A0),(A1)                       | significand bits 15-0
    SUBQ.L      #0x8,A1                         | A1 back to the head of the copy
    RTS                                         | return from A0TOA1
| ----------------------------------------------------------
| ELEMS_POLYEVAL -- Horner's rule: (A0) := C0, then
| (A0) := (A0) * (A2) + Cj for j = 1..N. A1 -> the table: a degree word N,
| then N+1 extended coefficients, leading term first. A0 and A2 preserved;
| A1 is left past the table, so consecutive tables need A1 set only once.
| Uses D0.
| Called by: ELEMS_LOGAPPROX, ELEMS_EXPAPPROX,
| ELEMS_POVERQ
ELEMS_POLYEVAL:
    MOVE.W      (A1)+,D0                        | D0 = degree N, the loop count; A1 -> C0
    PEA.L       (A1)                            | src: C0, the leading coefficient
    PEA.L       (A0)                            | dst: the accumulator (A0)
    MOVE.W      #0xE,-(SP)                      | opword FX2X
    _FP68K                                      | (A0) := C0
| POLYLOOP
ELEMS_POLYLOOP:
    PEA.L       (A2)                            | src: the argument (A2)
    PEA.L       (A0)                            | dst: the accumulator
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A0) := (A0) * (A2)
    ADDQ.L      #0x8,A1                         | A1 -> the next coefficient, 10 bytes on ...
    ADDQ.L      #0x2,A1                         | ... in two steps
    PEA.L       (A1)                            | src: Cj
    PEA.L       (A0)                            | dst: the accumulator
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A0) := (A0) + Cj
    SUBQ.W      #0x1,D0                         | count the terms
    BGT.B       ELEMS_POLYLOOP                  | more ->
    ADDQ.L      #0x8,A1                         | A1 past the last coefficient, 10 bytes on ...
    ADDQ.L      #0x2,A1                         | ... in two steps
    RTS                                         | return from POLYEVAL
| ----------------------------------------------------------
| ELEMS_CLEARUFLOW, ELEMS_CLEAROFLOW, ELEMS_CLEARINVALID
| (CLEARINVALID), ELEMS_CLEARINEXACT -- clear one exception flag:
| get the environment, clear the flag bit (FB* numbers: bits of the high
| byte), set the environment. Uses D0.
| Called by: ELEMS_LOGAPPROX, ELEMS_EXP1ROOT,
| ELEMS_EXPAPPROX, ELEMS_XPWRK, ELEMS_COMPOUNDTOP
| (COMPOUNDTOP) (and 2 more)
ELEMS_CLEARUFLOW:
    MOVEQ.L     #0x1,D0                         | FBUFLOW: underflow flag, bit 1
    BRA.B       ELEMS_CLEARX                    | ->
| CLEAROFLOW
| Called by: ELEMS_EXPR, ELEMS_EXP1R, ELEMS_XPWRK,
| ELEMS_ANNDOIT
ELEMS_CLEAROFLOW:
    MOVEQ.L     #0x2,D0                         | FBOFLOW: overflow flag, bit 2
    BRA.B       ELEMS_CLEARX                    | ->
| CLEARINVALID
ELEMS_CLEARINVALID:
    MOVEQ.L     #0x0,D0                         | FBINVALID: invalid flag, bit 0
    BRA.B       ELEMS_CLEARX                    | ->
| CLEARINEXACT
| Called by: ELEMS_SPLIT2, ELEMS_SPLIT, ELEMS_XPWRY9ERR
| (XPWRY9ERR), ELEMS_NEGPWRY, ELEMS_XPWRYOK
ELEMS_CLEARINEXACT:
    MOVEQ.L     #0x4,D0                         | FBINEXACT: inexact flag, bit 4
| CLEARX: clear flag D0
ELEMS_CLEARX:
    SUBQ.L      #0x2,SP                         | room for the environment word
    PEA.L       (SP)                            | dst: that word
    MOVE.W      #0x3,-(SP)                      | opword FGETENV
    _FP68K                                      | (SP) := environment
    BCLR        D0,(SP)                         | clear flag D0 (bit of the high byte)
    PEA.L       (SP)                            | dst: the changed word
    MOVE.W      #0x1,-(SP)                      | opword FSETENV
    _FP68K                                      | environment := (SP)
| CLEAREXIT: shared exit of CLEARX, FORCEX, TESTX
ELEMS_CLEAREXIT:
    ADDQ.L      #0x2,SP                         | drop the word
    TST.B       D0                              | Z from D0.B: TESTX's result
    RTS                                         | return
| ----------------------------------------------------------
| ELEMS_FORCEOFLOW, ELEMS_FORCEUFLOW,
| ELEMS_FORCEDIVZER, ELEMS_FORCEINVALID, ELEMS_FORCEINEXACT
| (FORCEINEXACT) -- set an exception flag with FSETXCP (which also halts
| if that halt is enabled; within Elems all halts are off). Uses D0.
ELEMS_FORCEOFLOW:
    MOVEQ.L     #0x2,D0                         | FBOFLOW: overflow
    BRA.B       ELEMS_FORCEX                    | ->
| FORCEUFLOW
| Called by: ELEMS_LOGAPPROX, ELEMS_EXPR, ELEMS_EXP1TOP
| (EXP1TOP), ELEMS_ANNDOIT, ELEMS_TRIGFINI
ELEMS_FORCEUFLOW:
    MOVEQ.L     #0x1,D0                         | FBUFLOW: underflow
    BRA.B       ELEMS_FORCEX                    | ->
| FORCEDIVZER
ELEMS_FORCEDIVZER:
    MOVEQ.L     #0x3,D0                         | FBDIVZER: divide by zero
    BRA.B       ELEMS_FORCEX                    | ->
| FORCEINVALID
ELEMS_FORCEINVALID:
    MOVEQ.L     #0x0,D0                         | FBINVALID: invalid
    BRA.B       ELEMS_FORCEX                    | ->
| FORCEINEXACT
| Called by: ELEMS_LOGAPPROX, ELEMS_EXPR, ELEMS_EXP1TOP
| (EXP1TOP), ELEMS_EXP1R, ELEMS_EXPAPPROX (and 1 more)
ELEMS_FORCEINEXACT:
    MOVEQ.L     #0x4,D0                         | FBINEXACT: inexact
| FORCEX: set flag D0
| Called by: the four FORCE* entries above (BRA.B)
ELEMS_FORCEX:
    MOVE.W      D0,-(SP)                        | the exception number, an integer on the stack
    PEA.L       (SP)                            | dst: that integer
    MOVE.W      #0x15,-(SP)                     | opword FSETXCP
    _FP68K                                      | set exception D0
    BRA.B       ELEMS_CLEAREXIT                 | -> drop the word and return
| ----------------------------------------------------------
| ELEMS_TESTDIVZER, ELEMS_TESTUFLOW,
| ELEMS_TESTOFLOW, ELEMS_TESTINVALID, ELEMS_TESTINEXACT
| (TESTINEXACT) -- test an exception flag with FTESTXCP: Z set if the flag
| is clear, Z clear if it is set. Uses D0.
ELEMS_TESTDIVZER:
    MOVEQ.L     #0x3,D0                         | FBDIVZER: divide by zero
    BRA.B       ELEMS_TESTX                     | ->
| TESTUFLOW
ELEMS_TESTUFLOW:
    MOVEQ.L     #0x1,D0                         | FBUFLOW: underflow
    BRA.B       ELEMS_TESTX                     | ->
| TESTOFLOW
ELEMS_TESTOFLOW:
    MOVEQ.L     #0x2,D0                         | FBOFLOW: overflow
    BRA.B       ELEMS_TESTX                     | ->
| TESTINVALID
ELEMS_TESTINVALID:
    MOVEQ.L     #0x0,D0                         | FBINVALID: invalid
    BRA.B       ELEMS_TESTX                     | ->
| TESTINEXACT
ELEMS_TESTINEXACT:
    MOVEQ.L     #0x4,D0                         | FBINEXACT: inexact
| TESTX: test flag D0
| Called by: the four TEST* entries above (BRA.B)
ELEMS_TESTX:
    MOVE.W      D0,-(SP)                        | the exception number, an integer on the stack
    PEA.L       (SP)                            | dst: that integer, receives the answer
    MOVE.W      #0x1B,-(SP)                     | opword FTESTXCP
    _FP68K                                      | test exception D0: answer in the word's high byte
    MOVE.B      (SP),D0                         | D0.B = the answer, nonzero if the flag is set
    BRA.B       ELEMS_CLEAREXIT                 | -> drop the word, Z from D0.B, return
| ----------------------------------------------------------
| ELEMS_SCALBXX -- (A0) := (A0) * 2^(A1) for an extended
| integral (A1) of any size. FSCALBX takes a 16-bit integer, but because of
| the 15-bit exponent range two steps of at most 32767 (MAXINT) are enough
| to reach any over/underflow. A0, A1 and (A1) are not changed. Uses
| cells J and Y, A3.
ELEMS_SCALBXX:
    MOVE.W      #0x7FFF,-0x6(A6)                | J := 32767 (MAXINT): the first step
    LEA.L       -0x1A(A6),A3                    | A3 -> just past cell Y (STY+10)
    MOVE.L      0x6(A1),-(A3)                   | cell Y := (A1): significand bits 31-0, ...
    MOVE.L      0x2(A1),-(A3)                   | ... bits 63-32, ...
    MOVE.W      (A1),-(A3)                      | ... sign/exponent; A3 -> cell Y
    BCLR        #0x7,(A3)                       | Y := |(A1)|
    BSR.B       ELEMS_VSMAXINT                  | compare 32767 with Y
    BGE.B       ELEMS_SKIPFIRSTSCALB            | FBGES: 32767 >= Y: one step is enough ->
    PEA.L       ELEMS_FPKMAXINT(PC)             | src: 32767 (FPKMAXINT)
    PEA.L       (A3)                            | dst: cell Y
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | Y := Y - 32767
    TST.B       (A1)                            | (A1) negative?
    BPL.B       ELEMS_SCALBXX_1                 | no ->
    NEG.W       -0x6(A6)                        | J := -32767
ELEMS_SCALBXX_1:
    BSR.B       ELEMS_SCALEINT                  | (A0) := (A0) * 2^J: the first step
| SKIPFIRSTSCALB: if Y still exceeds 32767, scale by +-32767 again
ELEMS_SKIPFIRSTSCALB:
    BSR.B       ELEMS_VSMAXINT                  | compare 32767 with the rest in Y
    BGE.B       ELEMS_AT1                       | FBGES: 32767 >= Y -> scale by Y
    PEA.L       ELEMS_FPKMAXINT(PC)             | src: 32767 again: enough to over/underflow
    BRA.B       ELEMS_AT3                       | ->
| At1: scale by the rest
ELEMS_AT1:
    PEA.L       (A3)                            | src: cell Y, the rest
| At3: J := the scale step, signed like (A1)
ELEMS_AT3:
    PEA.L       -0x6(A6)                        | dst: cell J
    MOVE.W      #0x2010,-(SP)                   | opword FX2I: extended to 16-bit integer
    _FP68K                                      | J := src as an integer
    TST.B       (A1)                            | (A1) negative?
    BPL.B       ELEMS_SCALEINT                  | no ->
    NEG.W       -0x6(A6)                        | J := -J
| ----------------------------------------------------------
| ELEMS_SCALEINT -- (A0) := (A0) * 2^J, J = the integer in
| cell J.
ELEMS_SCALEINT:
    PEA.L       -0x6(A6)                        | src: cell J (integer)
    PEA.L       (A0)                            | dst: (A0)
    MOVE.W      #0x2018,-(SP)                   | opword FSCALBX, src format integer
    _FP68K                                      | (A0) := (A0) * 2^J
    RTS                                         | return from SCALEINT / SCALBXX
| ----------------------------------------------------------
| ELEMS_VSMAXINT -- compare 32767 (FPKMAXINT) with cell Y;
| the CCR as left by FCMPX (32767 against Y).
ELEMS_VSMAXINT:
    PEA.L       -0x24(A6)                       | src: cell Y
    PEA.L       ELEMS_FPKMAXINT(PC)             | dst: 32767 (FPKMAXINT)
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare 32767 with Y
    RTS                                         | return with the comparison in the CCR
| ----------------------------------------------------------
| ELEMS_LOGTOP -- ln(x), log2(x), ln(1+x), log2(1+x)
| (opcodes 0, 2, 4, 6): opcode bit 1 (BTLOGBASE2) selects base 2, bit 2
| (BTLOG1PLUSX) the argument 1+x. Everything is computed in base 2 from
| log2(1+z) (LOGAPPROX); ln needs a last multiplication by ln(2).
| log(+inf) = +inf; log(-inf), log of x < 0 and log(1+x) of x < -1 are
| invalid: NaN code 36 (NANLOG); log(+-0) and log(1 + -1) are -inf with
| divide by zero; log(1 +- 0) = +-0. D1.B = class - FCINF as left by START
| (0 infinity, 1 zero, 2 normal, 3 denormal), bit 15 = sign.
ELEMS_LOGTOP:
    SUBQ.B      #0x1,D1                         | D1.B: -1 infinity, 0 zero, 1 normal, 2 denormal
    BPL.B       ELEMS_LOGFINITE                 | finite ->
    TST.W       D1                              | infinite: sign
    BPL.W       ELEMS_PINFSTUFF                 | log(+inf) = +inf ->
| LOGERROR: invalid argument
ELEMS_LOGERROR:
    MOVEQ.L     #0x24,D0                        | NaN code 36 (NANLOG)
    BRA.W       ELEMS_ERRORNAN                  | -> deliver NaN(36), invalid
| LOGFINITE
ELEMS_LOGFINITE:
    BTST        #0x2,D3                         | log(1+x) (BTLOG1PLUSX)?
    BNE.B       ELEMS_LOG1PLUSX                 | yes ->
    TST.B       D1                              | x = 0?
    BEQ.B       ELEMS_LOG0                      | log(+-0) = -inf, divide by zero ->
    TST.W       D1                              | sign of x
    BMI.B       ELEMS_LOGERROR                  | x < 0: invalid ->
    BRA.B       ELEMS_LOG2R                     | x > 0 ->
| LOG1PLUSX: ln(1+x), log2(1+x) of a finite x
ELEMS_LOG1PLUSX:
    TST.B       D1                              | x = 0?
    BEQ.W       ELEMS_RESULTDELIVERED           | log(1 +- 0) = +-0, x itself ->
    PEA.L       (A4)                            | src: x (A4)
    PEA.L       ELEMS_FPKM1(PC)                 | dst: -1 (FPKM1)
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare -1 with x
    BHI.B       ELEMS_LOGERROR                  | FBUGTS: -1 > x or unordered: invalid ->
    BCS.B       ELEMS_LOG12R                    | FBLTS: -1 < x ->
| LOG0: x = 0 (log), x = -1 (log of 1+x)
ELEMS_LOG0:
    BRA.W       ELEMS_DIVM0STUFF                | x = -1: log(0) = -inf, divide by zero ->
| ----------------------------------------------------------
| ELEMS_LOG12R -- log2(1+T) for a finite T > -1, T <> 0.
| If 1+T lies outside sqrt(1/2)..sqrt(2), compute log2 of the sum 1+T
| (LOG2R); else LOGAPPROX on T itself, ignoring the rounded sum (accuracy
| for small T). The input T is saved in cell W first.
ELEMS_LOG12R:
    MOVEA.L     A4,A0                           | A0 -> T (A4)
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := T
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A4)                            | dst: (A4)
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := 1 + T
    PEA.L       ELEMS_FPKSQRTHALF(PC)           | src: sqrt(1/2) (FPKSQRTHALF)
    PEA.L       (A4)                            | dst: 1+T
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare 1+T with sqrt(1/2)
    BLE.B       ELEMS_LOG2R                     | FBULES: 1+T <= sqrt(1/2) -> log2 of the sum
    PEA.L       (A4)                            | src: 1+T
    PEA.L       ELEMS_FPKSQRT2(PC)              | dst: sqrt(2) (FPKSQRT2)
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare sqrt(2) with 1+T
    BLS.B       ELEMS_LOG2R                     | FBLES: sqrt(2) <= 1+T -> log2 of the sum
    MOVEA.L     A1,A0                           | A0 -> cell W, still T
    MOVEA.L     A4,A1                           | A1 -> dst (A4)
    BSR.W       ELEMS_A0TOA1                    | (A4) := T again
    BSR.W       ELEMS_LOGAPPROX                 | (A4) := log2(1+T)
    BRA.W       ELEMS_LOGFINI                   | -> times ln(2) for ln(1+x)
| ----------------------------------------------------------
| ELEMS_LOG2R -- log2(T) for a positive finite T at A4:
| T = 2^L * Q with sqrt(1/2) <= Q <= sqrt(2), log2(T) = L + log2(Q), and
| log2(Q) = log2(1 + (Q-1)) from LOGAPPROX. L is kept in cell W.
ELEMS_LOG2R:
    MOVEA.L     A4,A0                           | A0 -> T
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := T
    PEA.L       (A1)                            | dst: cell W
    MOVE.W      #0x1A,-(SP)                     | opword FLOGBX
    _FP68K                                      | W := logb(T) = L
    BCHG        #0x7,(A1)                       | W := -L
    MOVEA.L     A4,A0                           | A0 -> T
    BSR.W       ELEMS_SCALBXX                   | (A4) := T * 2^-L = Q, 1 <= Q < 2
    BCHG        #0x7,(A1)                       | W := L again
    PEA.L       ELEMS_FPKSQRT2(PC)              | src: sqrt(2) (FPKSQRT2)
    PEA.L       (A4)                            | dst: Q
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare Q with sqrt(2)
    BLE.W       ELEMS_AT11                      | FBULEL: Q <= sqrt(2) ->
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       -0x10(A6)                       | dst: cell W
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | W := L + 1
    PEA.L       ELEMS_FPK2(PC)                  | src: 2 (FPK2)
    PEA.L       (A4)                            | dst: Q
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := Q / 2
| At11: S = Q - 1 for LOGAPPROX, then add L
ELEMS_AT11:
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A4)                            | dst: Q
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | (A4) := S = Q - 1
    BSR.W       ELEMS_LOGAPPROX                 | (A4) := log2(1+S) = log2(Q)
    PEA.L       -0x10(A6)                       | src: cell W, L
    PEA.L       (A4)                            | dst: log2(Q)
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := L + log2(Q) = log2(T)
| LOGFINI: times ln(2) for the natural logarithms
ELEMS_LOGFINI:
    BTST        #0x1,D3                         | base 2 (BTLOGBASE2)?
    BNE.B       ELEMS_LOGFINI_1                 | yes: done ->
    PEA.L       ELEMS_FPKLOGE2(PC)              | src: ln(2) (FPKLOGE2)
    PEA.L       (A4)                            | dst: the log2 result
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := log2(..) * ln(2) = ln(..)
| log2: done
ELEMS_LOGFINI_1:
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_LOGAPPROX -- (A4) := log2(1+S) for S = (A4), 1+S
| in sqrt(1/2)..sqrt(2), special cases already filtered out:
| R := S / (2+S), log2(1+S) = R * P(R*R) / Q(R*R), coefficients LOG21P
| (ELEMS_LOG21P) and LOG21Q (ELEMS_LOG21Q). S = 0 is returned at once
| (no spurious inexact); a denormal S gives S / ln(2), since log2(1+tiny)
| = ln(1+tiny) / ln(2) and ln(1+tiny) = tiny + ..., with underflow. Cell W
| is left alone (LOG2R's L); Y holds R, X holds R*R; A0-A2 are used by
| POLYEVAL.
ELEMS_LOGAPPROX:
    PEA.L       (A4)                            | src: S (A4)
    PEA.L       -0x6(A6)                        | dst: cell J, receives the class
    MOVE.W      #0x1C,-(SP)                     | opword FCLASSX
    _FP68K                                      | J := class of S: -6..6
    MOVE.W      -0x6(A6),D0                     | D0 = class
    BPL.B       ELEMS_LOGAPPROX_1               | nonnegative ->
    NEG.W       D0                              | D0 = |class|
ELEMS_LOGAPPROX_1:
    SUBQ.W      #0x4,D0                         | FCZERO (4): S = 0?
    BNE.B       ELEMS_LANONZERO                 | no ->
    RTS                                         | S = 0: log2(1+0) = 0, (A4) unchanged
| LANONZERO: denormal S: S / ln(2), underflow
ELEMS_LANONZERO:
    SUBQ.W      #0x1,D0                         | FCNORM (5)?  (6 = FCDENORM)
    BEQ.B       ELEMS_LANORMAL                  | normal ->
    PEA.L       ELEMS_FPKLOGE2(PC)              | src for LAFINI's FDIVX: ln(2) (FPKLOGE2)
    BSR.W       ELEMS_FORCEUFLOW                | signal underflow: the result is tiny
    BRA.B       ELEMS_LAFINI                    | -> (A4) := S / ln(2)
| LANORMAL
ELEMS_LANORMAL:
    MOVEA.L     A4,A0                           | A0 -> S
    LEA.L       -0x1A(A6),A1                    | A1 -> cell X
    BSR.W       ELEMS_A0TOA1                    | X := S
    PEA.L       ELEMS_FPK2(PC)                  | src: 2 (FPK2)
    PEA.L       (A4)                            | dst: S
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := (A4) + 2
    PEA.L       (A4)                            | src: S + 2
    PEA.L       (A1)                            | dst: cell X, S
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | X := S / (S + 2) = R
    MOVEA.L     A1,A0                           | A0 -> cell X
    PEA.L       (A1)                            | src: R; two copies for the square
    PEA.L       (A1)                            | dst: R
    LEA.L       -0x24(A6),A1                    | A1 -> cell Y
    BSR.W       ELEMS_A0TOA1                    | Y := R
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := R * R
    MOVEA.L     A4,A0                           | A0 -> the result slot (A4)
    LEA.L       ELEMS_LOG21P(PC),A1             | A1 -> LOG21P, the coefficients of P (degree 5)
    LEA.L       -0x1A(A6),A2                    | A2 -> R*R (cell X)
    BSR.W       ELEMS_POLYEVAL                  | (A4) := P(R*R)
    PEA.L       -0x24(A6)                       | src: cell Y, R
    PEA.L       (A4)                            | dst: P(R*R)
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := R * P(R*R)
    LEA.L       -0x24(A6),A0                    | A0 -> cell Y, the result slot
    LEA.L       ELEMS_LOG21Q(PC),A1             | A1 -> LOG21Q, the coefficients of Q (degree 2)
    LEA.L       -0x1A(A6),A2                    | A2 -> R*R (cell X)
    BSR.W       ELEMS_POLYEVAL                  | Y := Q(R*R)
    BSR.W       ELEMS_CLEARUFLOW                | clear the underflows of the steps so far
    PEA.L       -0x24(A6)                       | src for LAFINI: cell Y, Q(R*R)
| LAFINI: divide, result inexact
ELEMS_LAFINI:
    PEA.L       (A4)                            | dst: R * P(R*R), or S for a denormal S
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := R*P(R*R) / Q(R*R)  (or S / ln(2))
    BSR.W       ELEMS_FORCEINEXACT              | the result is inexact
    RTS                                         | return from LOGAPPROX
| ----------------------------------------------------------
| ELEMS_P0STUFF .. ELEMS_MINFSTUFF -- deliver a
| special value: P0STUFF +0, M0STUFF -0, P1STUFF +1, M1STUFF -1,
| DIVP0STUFF divide by zero and +inf, PINFSTUFF +inf, DIVM0STUFF divide by
| zero and -inf, MINFSTUFF -inf; STUFFVAL copies the constant at A0 to the
| dst (A4), then RESULTDELIVERED.
| Called by: ELEMS_EXPTOP, ELEMS_EXPR, ELEMS_XPWRITOP
| (XPWRITOP), ELEMS_COMPOUNDTOP, ELEMS_ANNUITYTOP
ELEMS_P0STUFF:
    LEA.L       ELEMS_FPK0(PC),A0               | A0 -> +0 (FPK0)
    BRA.B       ELEMS_STUFFVAL                  | ->
| M0STUFF: -0
ELEMS_M0STUFF:
    LEA.L       ELEMS_FPKM0(PC),A0              | A0 -> -0 (FPKM0)
    BRA.B       ELEMS_STUFFVAL                  | ->
| P1STUFF: +1
| Called by: ELEMS_EXPTOP, ELEMS_XPWRITOP,
| ELEMS_COMPOUNDTOP, ELEMS_COSTOP
ELEMS_P1STUFF:
    LEA.L       ELEMS_FPK1(PC),A0               | A0 -> +1 (FPK1)
    BRA.B       ELEMS_STUFFVAL                  | ->
| M1STUFF: -1
ELEMS_M1STUFF:
    LEA.L       ELEMS_FPKM1(PC),A0              | A0 -> -1 (FPKM1)
    BRA.B       ELEMS_STUFFVAL                  | ->
| DIVP0STUFF: divide by zero, +inf
ELEMS_DIVP0STUFF:
    BSR.W       ELEMS_FORCEDIVZER               | signal divide by zero
| PINFSTUFF: +inf
| Called by: ELEMS_LOGTOP, ELEMS_EXPR, ELEMS_EXP1R,
| ELEMS_COMPOUNDTOP
ELEMS_PINFSTUFF:
    LEA.L       ELEMS_FPKINF(PC),A0             | A0 -> +inf (FPKINF)
    BRA.B       ELEMS_STUFFVAL                  | ->
| DIVM0STUFF: divide by zero, -inf
ELEMS_DIVM0STUFF:
    BSR.W       ELEMS_FORCEDIVZER               | signal divide by zero
| MINFSTUFF: -inf
ELEMS_MINFSTUFF:
    LEA.L       ELEMS_FPKMINF(PC),A0            | A0 -> -inf (FPKMINF)
| STUFFVAL: (A4) := the constant at A0, deliver
| Called by: the stubs P0STUFF .. PINFSTUFF above (BRA.B)
ELEMS_STUFFVAL:
    MOVEA.L     A4,A1                           | A1 -> dst
    BSR.W       ELEMS_A0TOA1                    | (A4) := the constant
    BRA.B       ELEMS_RESULTDELIVERED           | -> deliver (Apple STUFFEXIT)
| ----------------------------------------------------------
| ELEMS_ERRORNAN -- deliver a quiet NaN with the code in
| D0.B (nonzero) and signal invalid.
| Called by: ELEMS_LOGTOP, ELEMS_XPWRY9ERR, ELEMS_ERRFINAN
| (ERRFINAN), ELEMS_SINTOP, ELEMS_TANTOP
ELEMS_ERRORNAN:
    ORI.L       #0x7FFF4000,D0                  | D0 = $7FFF40nn: exponent $7FFF, quiet bit, NaN code nn
    MOVE.L      D0,(A4)+                        | sign/exponent and significand bits 63-48
    CLR.L       (A4)+                           | significand bits 47-16 := 0
    CLR.W       (A4)                            | significand bits 15-0 := 0
    SUBQ.L      #0x8,A4                         | A4 back to the head of the result
    BSR.W       ELEMS_FORCEINVALID              | signal invalid
| ----------------------------------------------------------
| ELEMS_RESULTDELIVERED -- the result is in (A4): restore
| the caller's environment and signal the exceptions raised here
| (FPROCEXIT), restore the package's lock state and the registers, pop
| opcode and addresses and return. START left the return address on the
| deepest operand address and, in the high word of the old return
| address slot, the number of bytes to pop down to it.
| Called by: ELEMS_DSTONLY, ELEMS_LOGTOP, ELEMS_LOG2R
| (LOG2R), ELEMS_P0STUFF, ELEMS_EXPTOP (and 16 more)
ELEMS_RESULTDELIVERED:
    PEA.L       -0x2(A6)                        | dst: cell ENV, the caller's environment
    MOVE.W      #0x19,-(SP)                     | opword FPROCEXIT
    _FP68K                                      | environment := ENV, then signal the exceptions raised here
    MOVEA.L     (AppPacks_5).W,A0               | A0 = the PACK 5 handle (AppPacks+20)
    MOVE.B      -0x30(A6),(A0)                  | restore its lock state (STLOCK)
    MOVEM.L     (SP)+,D0-D7/A0-A4               | restore all registers
    UNLK        A6                              | release the frame; (SP) = old return slot: the pop count
    ADDA.W      (SP),SP                         | pop the count: SP -> the moved return address
    RTS                                         | return; opcode and addresses are popped
| ----------------------------------------------------------
| ELEMS_EXPTOP -- e^x and 2^x (opcodes 8, $A; bit 1 =
| BTLOGBASE2: 2^x): the result is 2^K * ((2^frac - 1) + 1), with 2^frac - 1
| from EXPAPPROX. e^(+-0) = 1, e^-inf = +0, e^+inf = +inf; overflow gives
| +inf, underflow +0.
ELEMS_EXPTOP:
    SUBQ.B      #0x1,D1                         | D1.B: -1 infinity, 0 zero, 1 normal, 2 denormal
    BEQ.B       ELEMS_P1STUFF                   | e^(+-0) = 1 ->
    BGT.B       ELEMS_EXPNONZERO                | finite, nonzero ->
    TST.W       D1                              | infinite: sign
    BMI.B       ELEMS_P0STUFF                   | e^-inf = +0 ->
    BRA.B       ELEMS_RESULTDELIVERED           | e^+inf = +inf: x itself ->
| EXPNONZERO: 2^T: W := integer part, T := fraction (SPLIT2)
ELEMS_EXPNONZERO:
    BTST        #0x1,D3                         | 2^x (BTLOGBASE2)?
    BEQ.B       ELEMS_EXPR                      | no: e^x ->
    BSR.B       ELEMS_SPLIT2                    | W := integer part of T, T := fraction
    BRA.B       ELEMS_EXPROOT                   | -> 2^T * 2^W
| ----------------------------------------------------------
| ELEMS_EXPR -- e^T: with T = K * ln(2) + F, e^T = 2^K *
| ((2^(F/ln(2)) - 1) + 1): SPLIT sets W := K and T := F/ln(2), then the
| 2^x code (EXPROOT). A huge T overflows in SPLIT: +inf or +0.
ELEMS_EXPR:
    BSR.W       ELEMS_SPLIT                     | W := K, T := F/ln(2)
    BSR.W       ELEMS_TESTOFLOW                 | did the split overflow (huge T)?
    BEQ.B       ELEMS_EXPROOT                   | no ->
    BSR.W       ELEMS_FORCEINEXACT              | overflow or underflow: inexact
    TST.W       D1                              | sign of T
    BPL.B       ELEMS_PINFSTUFF                 | T > 0: overflow, +inf ->
    BSR.W       ELEMS_CLEAROFLOW                | T < 0: no overflow, ...
    BSR.W       ELEMS_FORCEUFLOW                | ... but an underflow
    BRA.W       ELEMS_P0STUFF                   | e^T = +0 ->
| ----------------------------------------------------------
| ELEMS_EXPROOT -- common root of e^x and 2^x:
| ((2^T - 1) + 1) * 2^W, the integer W possibly huge (SCALBXX).
ELEMS_EXPROOT:
    BSR.W       ELEMS_EXPAPPROX                 | (A4) := 2^T - 1
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A4)                            | dst: 2^T - 1
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := (2^T - 1) + 1
    MOVEA.L     A4,A0                           | A0 -> 2^T
    LEA.L       -0x10(A6),A1                    | A1 -> cell W, the integer part
    BSR.W       ELEMS_SCALBXX                   | (A4) := 2^T * 2^W
    BRA.B       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_SPLIT2 -- split T (A4) into the integer part W
| (rounded to nearest, cell W) and the fraction T - W (A4), |T - W| <= 1/2.
ELEMS_SPLIT2:
    MOVEA.L     A4,A0                           | A0 -> T
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := T
    PEA.L       (A1)                            | dst: cell W
    MOVE.W      #0x14,-(SP)                     | opword FRINTX
    _FP68K                                      | W := T rounded to an integer
    BSR.W       ELEMS_CLEARINEXACT              | the rounding error is no exception here
    PEA.L       (A1)                            | src: W, the integer part
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | (A4) := T - W, the fraction
    RTS                                         | return from SPLIT2
| ----------------------------------------------------------
| ELEMS_SPLIT -- split T (A4) for e^x and e^x - 1:
| T = K * ln(2) + F, with F = T REM ln(2); W := K = (T - F) / ln(2) (made
| integral), T := F / ln(2). Exits through CLEARINEXACT.
ELEMS_SPLIT:
    MOVEA.L     A4,A0                           | A0 -> T
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := T
    PEA.L       ELEMS_FPKLOGE2(PC)              | ln(2) (FPKLOGE2), the src of the FREMX and both FDIVX ...
    MOVE.L      (SP),-(SP)                      | ... pushed three times ...
    MOVE.L      (SP),-(SP)                      | ... (the copy on top is the FREMX src)
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0xC,-(SP)                      | opword FREMX
    _FP68K                                      | (A4) := T REM ln(2) = F, |F| <= ln(2)/2
    PEA.L       (A4)                            | src: F
    PEA.L       (A1)                            | dst: cell W, T
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | W := T - F
    PEA.L       (A1)                            | dst: cell W; src: the second ln(2) copy
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | W := (T - F) / ln(2) = K
    PEA.L       (A1)                            | dst: cell W
    MOVE.W      #0x14,-(SP)                     | opword FRINTX
    _FP68K                                      | W := K rounded: make sure it is an integer
    PEA.L       (A4)                            | dst: F; src: the last ln(2) copy
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := F / ln(2)
    BRA.W       ELEMS_CLEARINEXACT              | clear inexact (the roundings are no exception) and return
| ----------------------------------------------------------
| ELEMS_EXP1TOP -- e^x - 1 and 2^x - 1 (opcodes $C, $E):
| the same exception code, then EXPAPPROX for 2^frac - 1. e^(+-0) - 1 =
| +-0, e^-inf - 1 = -1, e^+inf - 1 = +inf; a denormal x gives x (e^x - 1)
| or x * ln(2) (2^x - 1), with underflow and inexact.
ELEMS_EXP1TOP:
    SUBQ.B      #0x1,D1                         | D1.B: -1 infinity, 0 zero, 1 normal, 2 denormal
    BGT.B       ELEMS_EXP1FINITE                | finite, nonzero ->
    BEQ.W       ELEMS_EXPEASY                   | e^(+-0) - 1 = +-0: x itself ->
    TST.W       D1                              | infinite: sign
    BMI.W       ELEMS_M1STUFF                   | e^-inf - 1 = -1 ->
| EXPEASY: the argument is the result
ELEMS_EXPEASY:
    BRA.W       ELEMS_RESULTDELIVERED           | e^+inf - 1 = +inf: x itself ->
| EXP1FINITE: finite, nonzero
ELEMS_EXP1FINITE:
    SUBQ.B      #0x1,D1                         | D1.B: 0 normal, 1 denormal
    BTST        #0x1,D3                         | 2^x - 1 (BTLOGBASE2)?
    BEQ.B       ELEMS_EXP1R                     | no: e^x - 1 ->
    TST.B       D1                              | denormal?
    BEQ.B       ELEMS_EXP21RNORM                | no ->
    PEA.L       ELEMS_FPKLOGE2(PC)              | src: ln(2): 2^T - 1 = T * ln(2) for a tiny T
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := T * ln(2)
| EXP1OUT: tiny result
ELEMS_EXP1OUT:
    BSR.W       ELEMS_FORCEUFLOW                | signal underflow
    BSR.W       ELEMS_FORCEINEXACT              | signal inexact
    BRA.B       ELEMS_EXP1RDONE                 | -> deliver
| EXP21RNORM: 2^T - 1 of a normal T: W := integer part, T := fraction
ELEMS_EXP21RNORM:
    BSR.W       ELEMS_SPLIT2                    | W := integer part, T := fraction
    BRA.B       ELEMS_EXP1ROOT                  | -> 2^T - 1 and scaling
| ----------------------------------------------------------
| ELEMS_EXP1R -- e^T - 1: split T into K and F/ln(2), where
| T = K*ln(2) + F; on overflow deliver +inf or -1.
ELEMS_EXP1R:
    TST.B       D1                              | denormal?
    BNE.B       ELEMS_EXP1OUT                   | yes: e^T - 1 = T, with underflow and inexact ->
    BSR.B       ELEMS_SPLIT                     | W := K, T := F/ln(2)
    BSR.W       ELEMS_TESTOFLOW                 | did the split overflow?
    BEQ.B       ELEMS_EXP1ROOT                  | no ->
    BSR.W       ELEMS_FORCEINEXACT              | overflow or underflow: inexact
    TST.W       D1                              | sign of T
    BPL.W       ELEMS_PINFSTUFF                 | T > 0: overflow, +inf ->
    BSR.W       ELEMS_CLEAROFLOW                | T < 0: no overflow; inexact stays set
    BRA.W       ELEMS_M1STUFF                   | e^T - 1 = -1 ->
| ----------------------------------------------------------
| ELEMS_EXP1ROOT -- common root of e^x - 1 and 2^x - 1:
| 2^T - 1 for the fraction T; if the integer W is nonzero, finish with
| (((2^T - 1) + 1) * 2^W) - 1.
ELEMS_EXP1ROOT:
    BSR.W       ELEMS_EXPAPPROX                 | (A4) := 2^T - 1
    PEA.L       ELEMS_FPK0(PC)                  | src: +0 (FPK0)
    PEA.L       -0x10(A6)                       | dst: cell W
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare W with 0
    BEQ.B       ELEMS_EXP1RDONE                 | FBEQS: W = 0: 2^T - 1 is the result ->
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A4)                            | dst: 2^T - 1
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := (2^T - 1) + 1
    MOVEA.L     A4,A0                           | A0 -> 2^T
    LEA.L       -0x10(A6),A1                    | A1 -> cell W, the integer part
    BSR.W       ELEMS_SCALBXX                   | (A4) := 2^T * 2^W
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A4)                            | dst: 2^T * 2^W
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | (A4) := 2^T * 2^W - 1
    BSR.W       ELEMS_CLEARUFLOW                | clear underflow: it cannot occur with a nonzero W
| EXP1RDONE
ELEMS_EXP1RDONE:
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_EXPAPPROX -- (A4) := 2^T - 1 for T = (A4),
| |T| <= 1/2: 2 * T * P(T*T) / (Q(T*T) - T * P(T*T)), coefficients EXP21P
| (ELEMS_EXP21P) and EXP21Q (ELEMS_EXP21Q). T = 0 returns 0 without
| inexact. Uses cells X and Y, D0, A0-A2.
ELEMS_EXPAPPROX:
    PEA.L       ELEMS_FPK0(PC)                  | src: +0 (FPK0)
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare T with 0
    BNE.B       ELEMS_EXPHARD                   | FBNES: T <> 0 ->
    RTS                                         | T = 0: 2^0 - 1 = 0, exact; return
| EXPHARD: T <> 0
ELEMS_EXPHARD:
    LEA.L       -0x24(A6),A1                    | A1 -> cell Y
    MOVEA.L     A4,A0                           | A0 -> T
    BSR.W       ELEMS_A0TOA1                    | Y := T
    PEA.L       (A1)                            | src: T
    PEA.L       (A1)                            | dst: cell Y, T
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | Y := T * T
    LEA.L       -0x1A(A6),A0                    | A0 -> cell X, the result slot
    LEA.L       ELEMS_EXP21P(PC),A1             | A1 -> EXP21P, the coefficients of P (degree 3)
    LEA.L       -0x24(A6),A2                    | A2 -> T*T (cell Y)
    BSR.W       ELEMS_POLYEVAL                  | X := P(T*T)
    PEA.L       -0x1A(A6)                       | src: cell X, P(T*T)
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := T * P(T*T)
    LEA.L       -0x1A(A6),A0                    | A0 -> cell X, the result slot
    LEA.L       ELEMS_EXP21Q(PC),A1             | A1 -> EXP21Q, the coefficients of Q (degree 2)
    LEA.L       -0x24(A6),A2                    | A2 -> T*T (cell Y)
    BSR.W       ELEMS_POLYEVAL                  | X := Q(T*T)
    PEA.L       (A4)                            | src: T * P(T*T)
    PEA.L       -0x1A(A6)                       | dst: cell X, Q(T*T)
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | X := Q(T*T) - T * P(T*T)
    PEA.L       ELEMS_FPK2(PC)                  | src: 2 (FPK2)
    PEA.L       (A4)                            | dst: T * P(T*T)
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := 2 * T * P(T*T)
    PEA.L       -0x1A(A6)                       | src: cell X
    PEA.L       (A4)                            | dst: 2 * T * P(T*T)
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := 2T*P(T*T) / (Q(T*T) - T*P(T*T)) = 2^T - 1
    BSR.W       ELEMS_FORCEINEXACT              | the result is inexact
    BRA.W       ELEMS_CLEARUFLOW                | clear underflow and return from EXPAPPROX
| ----------------------------------------------------------
| ELEMS_XPWRITOP -- x^i (opcode $8010): the extended dst x
| to the power of the 16-bit integer src i. x^0 = 1 for every non-NaN x;
| (inf or 0)^i: the sign stays only for odd i, a negative i gives
| +-0 for infinities and +-inf with divide by zero for zeros; |i| <= 255
| (SMALLEXP): repeated multiplication (XPWRK), else 2^(i * log2|x|)
| (XPWRY) with the sign fixed afterwards.
ELEMS_XPWRITOP:
    MOVEA.L     D4,A0                           | A0 -> i, the integer src
    MOVE.W      (A0),D2                         | D2 = i (replaces the fake class 15)
    BEQ.W       ELEMS_P1STUFF                   | x^0 = 1 (a NaN x was delivered by START) ->
    SUBQ.B      #0x1,D1                         | D1.B: -1 infinity, 0 zero, 1 normal, 2 denormal
    BGT.B       ELEMS_FINPWRI                   | finite, nonzero x ->
    ASR.W       #0x1,D2                         | low bit of i (odd?) into C and X
    BCS.B       ELEMS_XPWRITOP_1                | i odd: the sign of x stays ->
    BCLR        #0x7,(A4)                       | i even: (A4) := |x| (BCLR leaves X alone)
ELEMS_XPWRITOP_1:
    ADDX.W      D2,D2                           | D2 = i again, the low bit back from X
    BPL.W       ELEMS_RESULTDELIVERED           | i > 0: (inf or 0)^i is x, the sign fixed ->
    TST.B       D1                              | infinity (-1) or zero (0)?
    BPL.B       ELEMS_ZPWRNEG                   | zero ->
    TST.B       (A4)                            | sign of the infinity
    BPL.W       ELEMS_P0STUFF                   | +inf^-n = +0 ->
    BRA.W       ELEMS_M0STUFF                   | -inf^-n = -0 (odd n) ->
| ZPWRNEG: 0^-n
ELEMS_ZPWRNEG:
    TST.B       (A4)                            | sign of the zero
    BPL.W       ELEMS_DIVP0STUFF                | +0^-n = +inf, divide by zero ->
    BRA.W       ELEMS_DIVM0STUFF                | -0^-n = -inf (odd n), divide by zero ->
| ----------------------------------------------------------
| ELEMS_FINPWRI -- nonzero finite x: a small |i| is
| multiplied out (the sign of x survives for odd i); a large one is
| converted to extended and evaluated with log and exp.
ELEMS_FINPWRI:
    MOVE.W      D2,D0                           | D0 = i
    BPL.B       ELEMS_FINPWRI_1                 | ->
    NEG.W       D0                              | D0 = |i|
ELEMS_FINPWRI_1:
    CMPI.W      #0xFF,D0                        | |i| > 255 (SMALLEXP)?
    BHI.B       ELEMS_XPWRBIG                   | yes: log and exp ->
    BSR.B       ELEMS_XPWRK                     | (A4) := x^i by multiplication
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_XPWRBIG -- |i| > 255: i converted to extended in
| cell W, |x|^W by XPWRY, then the sign of x for odd i.
ELEMS_XPWRBIG:
    MOVE.W      (A4),-(SP)                      | save the sign/exponent of x
    BCLR        #0x7,(A4)                       | (A4) := |x|
    MOVE.L      D4,-(SP)                        | src: i, the integer at D4
    PEA.L       -0x10(A6)                       | dst: cell W
    MOVE.L      (SP),D4                         | D4 -> cell W: the src (y) for XPWRY
    MOVE.W      #0x200E,-(SP)                   | opword FI2X
    _FP68K                                      | W := i as an extended
    BSR.W       ELEMS_XPWRY                     | (A4) := |x|^i (XPWRY preserves D2 = i)
    MOVE.W      (SP)+,D0                        | D0 = saved sign/exponent of x
    BPL.B       ELEMS_XPWRBIG_3                 | x > 0: done ->
    ASR.W       #0x1,D2                         | low bit of i into C
    BCC.B       ELEMS_XPWRBIG_3                 | i even: the result stays positive ->
    BSET        #0x7,(A4)                       | x < 0, i odd: the result is negative
ELEMS_XPWRBIG_3:
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_XPWRK -- (A4) := T^D2 for T = (A4), D0 = |D2|,
| D2 <> 0: T^|D2| by XPWRKLOOP, reciprocated at the end for a negative D2;
| if T^|D2| over- or underflowed, the power is recomputed from 1/T. The
| sign comes out right. Trashes A0, A1, D0 and cells I, W, X. (XPWRYOK also
| calls it with D2 = 0, for y = +-0: the result is 1.)
ELEMS_XPWRK:
    MOVEA.L     A4,A0                           | A0 -> T
    LEA.L       -0x1A(A6),A1                    | A1 -> cell X
    BSR.W       ELEMS_A0TOA1                    | X := T, the input (XPWRKLOOP squares (A4))
    BSR.B       ELEMS_XPWRKLOOP                 | W := T^|i|, A1 -> cell W
    TST.W       D2                              | i negative?
    BMI.B       ELEMS_XPWRKDIV                  | yes: reciprocate ->
| XPWRKSTORE
ELEMS_XPWRKSTORE:
    MOVEA.L     A1,A0                           | A0 -> T^|i| (cell W)
    MOVEA.L     A4,A1                           | A1 -> dst
    BRA.W       ELEMS_A0TOA1                    | (A4) := T^|i|; A0TOA1 returns from XPWRK
| XPWRKDIV: negative power: 1 / T^|i|
ELEMS_XPWRKDIV:
    LEA.L       ELEMS_FPK1(PC),A0               | A0 -> 1 (FPK1)
    LEA.L       (A4),A1                         | A1 -> dst (the cell X address of the loop is lost)
    BSR.W       ELEMS_A0TOA1                    | (A4) := 1
    BSR.W       ELEMS_TESTUFLOW                 | did T^|i| underflow?
    BNE.B       ELEMS_XPWRKCLEAR                | yes: redo with 1/T ->
    BSR.W       ELEMS_TESTOFLOW                 | did it overflow?
    BNE.B       ELEMS_XPWRKCLEAR                | yes: redo with 1/T ->
    PEA.L       -0x10(A6)                       | src: cell W, T^|i| from XPWRKLOOP
    PEA.L       (A4)                            | dst: 1
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := 1 / T^|i|
    RTS                                         | return from XPWRK
| XPWRKCLEAR: T^|i| over/underflowed: (1/T)^|i| instead
ELEMS_XPWRKCLEAR:
    BSR.W       ELEMS_CLEAROFLOW                | forget the overflow ...
    BSR.W       ELEMS_CLEARUFLOW                | ... and the underflow of the first try
    PEA.L       -0x1A(A6)                       | src: cell X, the saved input T
    PEA.L       (A4)                            | dst: 1
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := 1 / T
    MOVE.W      D2,D0                           | D0 = i again
    BPL.B       ELEMS_XPWRKCLEAR_11             | ->
    NEG.W       D0                              | D0 = |i|
ELEMS_XPWRKCLEAR_11:
    BSR.B       ELEMS_XPWRKLOOP                 | W := (1/T)^|i|
    BRA.B       ELEMS_XPWRKSTORE                | -> (A4) := W
| ----------------------------------------------------------
| ELEMS_XPWRKLOOP -- W := X^K, X = (A4), K = D0 > 0:
| binary powering from the low bit of K (W := W * X for a set bit, X :=
| X * X), so (A4) is squared in place. Returns A1 -> cell W. Uses cell W,
| A0; trashes D0.
ELEMS_XPWRKLOOP:
    LEA.L       ELEMS_FPK1(PC),A0               | A0 -> 1 (FPK1)
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := 1, the seed of the result
    BRA.B       ELEMS_XKLPENTRY                 | ->
| XKLPTOP
ELEMS_XKLPTOP:
    PEA.L       (A4)                            | src: X^(2^j)
    PEA.L       (A4)                            | dst: the same
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := X^(2^(j+1))
ELEMS_XKLPENTRY:
    LSR.W       #0x1,D0                         | next bit of K into C
    BCC.B       ELEMS_XKLPSKIP                  | clear ->
    PEA.L       (A4)                            | src: X^(2^j)
    PEA.L       (A1)                            | dst: W, the result so far
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | W := W * X^(2^j)
| XKLPSKIP
ELEMS_XKLPSKIP:
    TST.W       D0                              | more bits?
    BNE.B       ELEMS_XKLPTOP                   | yes ->
    RTS                                         | return from XPWRKLOOP: W = X^K
| ----------------------------------------------------------
| ELEMS_XPWRY -- (A4) := (A4)^(D4) for a positive (A4):
| 2^(y * log2(x)) through recursive calls of the package (FLOG2X, then
| FEXP2X). FMULX never meets 0 * inf here, so cases like inf^3 come out
| right. Cell X holds the intermediate values, in case src and dst are the
| same. D2 is preserved.
ELEMS_XPWRY:
    MOVEA.L     A4,A0                           | A0 -> x (dst)
    LEA.L       -0x1A(A6),A1                    | A1 -> cell X
    BSR.W       ELEMS_A0TOA1                    | X := x
    PEA.L       (A1)                            | dst: cell X
    MOVE.W      #0x2,-(SP)                      | Elems opcode FLOG2X
    BSR.W       _PACK_5_                        | X := log2(x): the package calls itself
    MOVE.L      D4,-(SP)                        | src: y, the operand at D4
    PEA.L       (A1)                            | dst: cell X
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := y * log2(x)
    PEA.L       (A1)                            | dst: cell X
    MOVE.W      #0xA,-(SP)                      | Elems opcode FEXP2X
    BSR.W       _PACK_5_                        | X := 2^X = x^y
    MOVEA.L     A1,A0                           | A0 -> cell X
    MOVEA.L     A4,A1                           | A1 -> dst
    BRA.W       ELEMS_A0TOA1                    | (A4) := x^y; A0TOA1 returns from XPWRY
| ----------------------------------------------------------
| ELEMS_XPWRYTOP -- x^y (opcode $8012), both extended:
| a negative x needs an integral y (NEGPWRY), the sign of the result then
| follows the parity of y; the rest is XPWRYCOM.
ELEMS_XPWRYTOP:
    TST.W       D1                              | x negative (bit 15: sign of the dst)?
    BMI.B       ELEMS_NEGPWRY                   | yes ->
    BSR.W       ELEMS_XPWRYCOM                  | (A4) := x^y for x >= 0
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_XPWRY9ERR, ELEMS_XPWRYERR -- invalid x^y:
| deliver NaN code 37 (NANPOWER). XPWRY9ERR is the entry from inside a
| subroutine: it drops the return address first.
ELEMS_XPWRY9ERR:
    ADDQ.L      #0x4,SP                         | from inside XPWRYCOM: drop its return address
| XPWRYERR
ELEMS_XPWRYERR:
    BSR.W       ELEMS_CLEARINEXACT              | signal invalid only
    MOVEQ.L     #0x25,D0                        | NaN code 37 (NANPOWER)
    BRA.W       ELEMS_ERRORNAN                  | -> deliver NaN(37), invalid
| ----------------------------------------------------------
| ELEMS_NEGPWRY -- x < 0: y must be finite and integral
| (else invalid); the parity of y (the inexact flag of y/2 rounded) is
| saved in cell J to set the sign after XPWRYCOM.
ELEMS_NEGPWRY:
    TST.B       D2                              | y class - FCINF: 0 = infinite
    BEQ.B       ELEMS_XPWRYERR                  | negative x to an infinite power: invalid ->
    MOVEA.L     D4,A0                           | A0 -> y (src)
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := y
    PEA.L       (A1)                            | dst: cell W
    MOVE.W      #0x14,-(SP)                     | opword FRINTX
    _FP68K                                      | W := y rounded to an integer
    BSR.W       ELEMS_TESTINEXACT               | inexact: y not integral?
    BNE.B       ELEMS_XPWRYERR                  | yes: negative x to a nonintegral power is invalid ->
    PEA.L       ELEMS_FPK2(PC)                  | src: 2 (FPK2)
    PEA.L       (A1)                            | dst: cell W, y
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | W := y / 2
    PEA.L       (A1)                            | dst: cell W
    MOVE.W      #0x14,-(SP)                     | opword FRINTX
    _FP68K                                      | W := y/2 rounded: inexact if y is odd
    PEA.L       -0x6(A6)                        | dst: cell J, receives the environment
    MOVE.W      #0x3,-(SP)                      | opword FGETENV
    _FP68K                                      | J := environment: its inexact flag = parity of y
    BSR.W       ELEMS_CLEARINEXACT              | clear that inexact
    BCLR        #0x7,(A4)                       | (A4) := |x|
    BSR.W       ELEMS_XPWRYCOM                  | (A4) := |x|^y
    BTST        #0x4,-0x6(A6)                   | y odd (FBINEXACT in the saved flags)?
    BEQ.B       ELEMS_NEGPWRY_1                 | even: the result stays positive ->
    BCHG        #0x7,(A4)                       | odd: negate the result
ELEMS_NEGPWRY_1:
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_XPWRYCOM -- (A4) := (A4)^(D4) for (A4) >= 0, (D4)
| no NaN; D1/D2 = the classes less FCINF. 2^(y * log2(x)) works as long
| as it never multiplies inf and 0. Special cases: 0^0, inf^0 and 1^inf
| are invalid (exits through XPWRY9ERR, which pops this routine's return
| address); 0^+y = +0, 0^-y = +inf with divide by zero; a small integral y
| (|y| <= 255) is multiplied out (XPWRK). An inexact left by log2(x) is
| cleared for an infinite y.
ELEMS_XPWRYCOM:
    SUBQ.B      #0x1,D1                         | D1.B (x): -1 infinity, 0 zero, 1 normal, 2 denormal
    BNE.B       ELEMS_NONPWRY                   | x <> 0 ->
    SUBQ.B      #0x1,D2                         | x = 0; D2.B (y): -1 infinity, 0 zero, 1 normal, 2 denormal
    BEQ.B       ELEMS_XPWRY9ERR                 | 0^0 is invalid (with the return address pop) ->
    TST.W       D2                              | sign of y
    BPL.B       ELEMS_XPWRYCOM_1                | 0^positive = +0 ->
    BSR.W       ELEMS_FORCEDIVZER               | 0^negative: divide by zero ...
    LEA.L       ELEMS_FPKINF(PC),A0             | ... and A0 -> +inf (FPKINF)
    BRA.B       ELEMS_XPWRYCOM_2                | ->
| @1: 0^positive
ELEMS_XPWRYCOM_1:
    LEA.L       ELEMS_FPK0(PC),A0               | A0 -> +0 (FPK0)
ELEMS_XPWRYCOM_2:
    MOVEA.L     A4,A1                           | A1 -> dst
    BRA.W       ELEMS_A0TOA1                    | (A4) := the constant; A0TOA1 returns from XPWRYCOM
| NONPWRY: x <> 0
ELEMS_NONPWRY:
    BPL.B       ELEMS_FINPWRY                   | x finite (D1.B > 0) ->
    SUBQ.B      #0x1,D2                         | x = +inf; y: -1 infinity, 0 zero, 1 normal, 2 denormal
    BNE.B       ELEMS_XPWRYOK                   | y <> 0 ->
    BRA.W       ELEMS_XPWRY9ERR                 | inf^0 is invalid ->
| FINPWRY: finite x; finite^inf has the special case 1^inf (invalid)
ELEMS_FINPWRY:
    SUBQ.B      #0x1,D2                         | y: -1 infinity, 0 zero, 1 normal, 2 denormal
    BPL.B       ELEMS_XPWRYOK                   | y finite: finite^finite is fine ->
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A4)                            | dst: x
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare x with 1
    BEQ.W       ELEMS_XPWRY9ERR                 | FBEQL: 1^inf is invalid ->
| ----------------------------------------------------------
| ELEMS_XPWRYOK -- finite^reasonable: a small integral y
| is multiplied out, else log and exp. The integer test converts y to 16
| bits: out of range = invalid (cleared again, it is undeserved), not
| integral = inexact. D6 keeps the class of y across XPWRK.
ELEMS_XPWRYOK:
    MOVE.W      D2,D6                           | D6 = class of y
    MOVE.L      D4,-(SP)                        | src: y, the operand at D4
    PEA.L       -0x4(A6)                        | dst: cell I
    MOVE.W      #0x2010,-(SP)                   | opword FX2I: extended to 16-bit integer
    _FP68K                                      | I := y as an integer
    BSR.W       ELEMS_TESTINVALID               | out of the integer range (invalid)?
    SNE.B       D7                              | D7 = $FF if so
    BSR.W       ELEMS_CLEARINVALID              | clear that undeserved invalid
    BSR.W       ELEMS_TESTINEXACT               | y not integral (inexact)?
    SNE.B       D1                              | D1 = $FF if so
    OR.B        D1,D7                           | either?
    BNE.B       ELEMS_XPWRYHARD                 | yes: log and exp ->
    MOVE.W      -0x4(A6),D2                     | D2 = i, the integral y
    MOVE.W      D2,D0                           | D0 = i
    BPL.B       ELEMS_XPWRYOK_1                 | ->
    NEG.W       D0                              | D0 = |i|
ELEMS_XPWRYOK_1:
    CMPI.W      #0xFF,D0                        | |i| <= 255 (SMALLEXP)?
    BLE.W       ELEMS_XPWRK                     | yes: multiply out; XPWRK returns from XPWRYCOM
| XPWRYHARD: 2^(y * log2(x))
ELEMS_XPWRYHARD:
    BSR.W       ELEMS_CLEARINEXACT              | clear the inexact of the conversion
    BSR.W       ELEMS_XPWRY                     | (A4) := 2^(y * log2(x))
    TST.B       D6                              | y infinite (class -1)?
    BMI.W       ELEMS_CLEARINEXACT              | yes: clear the inexact of log2(x); CLEARINEXACT returns
    RTS                                         | return from XPWRYCOM
| ----------------------------------------------------------
| ELEMS_COMPOUNDTOP -- Compound (opcode $C014): dst :=
| (1 + r)^n, r = src2 (D5), n = src (D4). r < -1 (or unordered) is
| invalid: NaN code 38 (NANFINAN); n = 0 gives 1; r = 0 with an infinite n
| is invalid; an infinite n gives +0 or +inf by the signs of r and n;
| r = -1 gives +0 (n > 0) or +inf with divide by zero (n < 0); else
| 2^(n * log2(1 + r)), or e^(n * r) for |r| < 2^-128 (biased exponent
| $3F7F; Apple's comment says "Exponent -64").
ELEMS_COMPOUNDTOP:
    PEA.L       ELEMS_FPKM1(PC)                 | src: -1 (FPKM1)
    MOVE.L      D5,-(SP)                        | dst: r, the src2 operand at D5
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare r with -1
    BLT.W       ELEMS_ERRFINAN                  | FBULTL: r < -1 or unordered: invalid ->
    BGT.W       ELEMS_CMPGTM1                   | FBGTL: r > -1 ->
    SUBQ.B      #0x1,D2                         | r = -1; n: -1 infinity, 0 zero, 1 normal, 2 denormal
    BNE.B       ELEMS_CMPM1N                    | n <> 0 ->
| CMPTOZERO: (1 + r)^0 = 1
ELEMS_CMPTOZERO:
    BRA.W       ELEMS_P1STUFF                   | (1 + r)^0 = +1 ->
| CMPM1N: r = -1, n <> 0
ELEMS_CMPM1N:
    MOVEA.L     D4,A0                           | A0 -> n
    TST.B       (A0)                            | sign of n
    BMI.W       ELEMS_DIVP0STUFF                | (1 - 1)^negative = +inf, divide by zero ->
| CMPZERO
ELEMS_CMPZERO:
    BRA.W       ELEMS_P0STUFF                   | (1 - 1)^positive = +0 ->
| CMPGTM1: r > -1
ELEMS_CMPGTM1:
    SUBQ.B      #0x1,D2                         | n: -1 infinity, 0 zero, 1 normal, 2 denormal
    BEQ.B       ELEMS_CMPTOZERO                 | (1 + r)^0 = +1 ->
    BGT.B       ELEMS_CMPTOFIN                  | n finite ->
    SUBQ.B      #0x1,D1                         | n infinite; r: -1 infinity, 0 zero, ...
    BEQ.B       ELEMS_ERRFINAN                  | r = 0: 1^inf is invalid ->
    EOR.W       D2,D1                           | sign of r XOR sign of n (bit 15)
    BMI.B       ELEMS_CMPZERO                   | signs differ: +0 ->
    BRA.W       ELEMS_PINFSTUFF                 | signs equal: +inf ->
| CMPTOFIN: (1 + reasonable r)^finite n
ELEMS_CMPTOFIN:
    LEA.L       -0x1A(A6),A1                    | A1 -> cell X
    MOVEA.L     D5,A0                           | A0 -> r (src2)
    BSR.W       ELEMS_A0TOA1                    | X := r
    MOVE.W      (A1),D0                         | D0 = sign/exponent of r
    BCLR        #0xF,D0                         | clear the sign
    CMPI.W      #0x3F7F,D0                      | |r| < 2^-128 (biased exponent $3F7F)?
    BLT.B       ELEMS_CMPBASEE                  | yes: ln(1 + r) = r, use e^x ->
    PEA.L       (A1)                            | dst: cell X, r
    MOVE.W      #0x6,-(SP)                      | Elems opcode FLOG21X
    BSR.W       _PACK_5_                        | X := log2(1 + r): the package calls itself
    MOVE.L      D4,-(SP)                        | src: n, the operand at D4
    PEA.L       (A1)                            | dst: cell X, log2(1 + r)
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := n * log2(1 + r)
    PEA.L       (A1)                            | dst for cmpresult: cell X
    MOVE.W      #0xA,-(SP)                      | Elems opcode FEXP2X
    BRA.B       ELEMS_CMPRESULT                 | -> X := 2^X
| cmpbasee: tiny r: e^(n * r)
ELEMS_CMPBASEE:
    MOVE.L      D4,-(SP)                        | src: n, the operand at D4
    PEA.L       (A1)                            | dst: cell X, r (= ln(1 + r))
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := n * r
    PEA.L       (A1)                            | dst: cell X
    MOVE.W      #0x8,-(SP)                      | Elems opcode FEXPX
| cmpresult: X := 2^X or e^X, the opcode already pushed
ELEMS_CMPRESULT:
    BSR.W       ELEMS_CLEARUFLOW                | clear underflow ("Irrelevant!" says Apple)
    BSR.W       _PACK_5_                        | X := 2^X or e^X = (1 + r)^n
    MOVEA.L     A1,A0                           | A0 -> cell X
    MOVEA.L     A4,A1                           | A1 -> dst
    BSR.W       ELEMS_A0TOA1                    | (A4) := (1 + r)^n
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_ERRFINAN -- invalid financial argument: deliver NaN
| code 38 (NANFINAN).
ELEMS_ERRFINAN:
    MOVEQ.L     #0x26,D0                        | NaN code 38 (NANFINAN)
    BRA.W       ELEMS_ERRORNAN                  | -> deliver NaN(38), invalid
| ----------------------------------------------------------
| ELEMS_ANNUITYTOP -- Annuity (opcode $C016): dst :=
| (1 - (1 + r)^-n) / r, r = src2 (D5), n = src (D4). r < -1 (or
| unordered) is invalid: NaN code 38; r = -1: +0 for n = 0, +inf with
| divide by zero for n > 0, -1 for n < 0; n = 0: +0; r = 0: n (the
| limit); r = +inf: +0 for n > 0, -1 for n = -1, -0 for -1 < n < 0, -inf
| for n < -1; an infinite n: n if the signs of r and n differ, else 1/r;
| else ANNDOIT.
ELEMS_ANNUITYTOP:
    PEA.L       ELEMS_FPKM1(PC)                 | src: -1 (FPKM1)
    MOVE.L      D5,-(SP)                        | dst: r, the src2 operand at D5
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare r with -1
    BLT.B       ELEMS_ERRFINAN                  | FBULTL: r < -1 or unordered: invalid ->
    BNE.B       ELEMS_ANNOK                     | FBNES: r > -1 ->
    SUBQ.B      #0x1,D2                         | r = -1; n: -1 infinity, 0 zero, 1 normal, 2 denormal
    BEQ.B       ELEMS_ANN0                      | annuity(-1, 0) = +0 ->
    TST.W       D2                              | sign of n
    BPL.W       ELEMS_DIVP0STUFF                | n > 0: +inf, divide by zero ->
| ANNM1: -1
ELEMS_ANNM1:
    BRA.W       ELEMS_M1STUFF                   | n < 0: -1 ->
| ANNOK: r > -1
ELEMS_ANNOK:
    SUBQ.B      #0x1,D2                         | n: -1 infinity, 0 zero, 1 normal, 2 denormal
    BNE.B       ELEMS_ANNXN                     | n <> 0 ->
| ANN0: +0
ELEMS_ANN0:
    BRA.W       ELEMS_P0STUFF                   | annuity(r, 0) = +0 ->
| ANNXN: n <> 0; r zero or infinite?
ELEMS_ANNXN:
    SUBQ.B      #0x1,D1                         | r: -1 infinity, 0 zero, 1 normal, 2 denormal
    BGT.B       ELEMS_ANNROK                    | r normal or denormal ->
    BLT.B       ELEMS_ANNRINF                   | r = +inf ->
| ANNSRC: r = 0: the limit is n
ELEMS_ANNSRC:
    MOVEA.L     A4,A1                           | A1 -> dst
    MOVEA.L     D4,A0                           | A0 -> n
    BSR.W       ELEMS_A0TOA1                    | (A4) := n: annuity(0, n) = n
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ANNRINF: r = +inf
ELEMS_ANNRINF:
    TST.W       D2                              | sign of n (nonzero)
    BPL.B       ELEMS_ANN0                      | n > 0: +0 ->
    PEA.L       ELEMS_FPKM1(PC)                 | src: -1 (FPKM1)
    MOVE.L      D4,-(SP)                        | dst: n, the src operand at D4
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare n with -1
    BEQ.B       ELEMS_ANNM1                     | FBEQL: n = -1: -1 ->
    BGT.W       ELEMS_M0STUFF                   | FBGTL: -1 < n < 0: -0 ->
    BRA.W       ELEMS_MINFSTUFF                 | n < -1: -inf ->
| ANNROK: r normal or denormal; n infinite?
ELEMS_ANNROK:
    TST.B       D2                              | n infinite (-1)?
    BPL.B       ELEMS_ANNDOIT                   | no: compute ->
    EOR.W       D2,D1                           | sign of r XOR sign of n (bit 15)
    BMI.B       ELEMS_ANNSRC                    | signs differ: the result is n, +-inf ->
    MOVEA.L     D5,A0                           | A0 -> r (src2), the divisor
    LEA.L       -0x1A(A6),A1                    | A1 -> cell X
    BSR.W       ELEMS_A0TOA1                    | X := r
    PEA.L       (A1)                            | src for the FDIVX below: cell X, r
    MOVEA.L     A4,A1                           | A1 -> dst
    LEA.L       ELEMS_FPK1(PC),A0               | A0 -> 1 (FPK1)
    BSR.W       ELEMS_A0TOA1                    | (A4) := 1
    PEA.L       (A1)                            | dst: 1
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := 1 / r
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_ANNDOIT -- (1 - (1 + r)^-n) / r for finite
| nonzero n and r > -1, in cell X. A normal r: X := -n * log2(1 + r) and
| (1 + r)^-n - 1 = 2^X - 1 (FEXP21X); |r| < 2^-128: ln(1 + r) is about r,
| X := -n * r and e^X - 1 (FEXP1X); then 1 - (1 + r)^-n = -X, divided by
| r (annresult). When 2^X would be huge (X >= 256) and r >= 2^128, the
| result is -(r^-(n+1)) instead (annspecial), which avoids the overflow
| of the intermediate value. annclear clears the flags of the steps;
| an infinite result signals overflow, a zero or denormal one underflow.
ELEMS_ANNDOIT:
    LEA.L       -0x1A(A6),A1                    | A1 -> cell X
    MOVEA.L     D5,A0                           | A0 -> r (src2)
    BSR.W       ELEMS_A0TOA1                    | X := r
    MOVE.W      (A1),D0                         | D0 = sign/exponent of r
    BCLR        #0xF,D0                         | clear the sign
    CMPI.W      #0x3F7F,D0                      | |r| < 2^-128 (biased exponent $3F7F)?
    BLT.B       ELEMS_ANNBASEE                  | yes: ln(1 + r) = r, use e^x ->
    PEA.L       (A1)                            | dst: cell X, r
    MOVE.W      #0x6,-(SP)                      | Elems opcode FLOG21X
    BSR.W       _PACK_5_                        | X := log2(1 + r): the package calls itself
    MOVE.L      D4,-(SP)                        | src: n, the operand at D4
    PEA.L       (A1)                            | dst: cell X, log2(1 + r)
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := n * log2(1 + r)
    BCHG        #0x7,(A1)                       | X := -n * log2(1 + r)
    CMPI.W      #0x4007,(A1)                    | X >= 256 (sign/exponent word >= $4007)?
    BLT.B       ELEMS_ANNDOIT_1                 | no: 2^X = (1 + r)^-n is not huge ->
    MOVEA.L     D5,A0                           | A0 -> r
    CMPI.W      #0x407F,(A0)                    | r >= 2^128 (word >= $407F)?
    BGE.B       ELEMS_ANNSPECIAL                | yes: -(r^-(n+1)) instead ->
| @1: 2^X - 1
ELEMS_ANNDOIT_1:
    PEA.L       (A1)                            | dst for annresult: cell X
    MOVE.W      #0xE,-(SP)                      | Elems opcode FEXP21X
    BRA.B       ELEMS_ANNRESULT                 | -> X := 2^X - 1
| annbasee: tiny r, base e
ELEMS_ANNBASEE:
    MOVE.L      D4,-(SP)                        | src: n, the operand at D4
    PEA.L       (A1)                            | dst: cell X, r (= ln(1 + r))
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := n * r
    BCHG        #0x7,(A1)                       | X := -n * r
    PEA.L       (A1)                            | dst: cell X
    MOVE.W      #0xC,-(SP)                      | Elems opcode FEXP1X
| annresult: X := (1 + r)^-n - 1, the opcode already pushed
ELEMS_ANNRESULT:
    BSR.W       _PACK_5_                        | X := 2^X - 1 or e^X - 1 = (1 + r)^-n - 1
    BCHG        #0x7,(A1)                       | X := 1 - (1 + r)^-n
    MOVE.L      D5,-(SP)                        | src: r, the src2 operand at D5
    PEA.L       (A1)                            | dst: cell X
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | X := (1 - (1 + r)^-n) / r
| annclear: flags of the result
ELEMS_ANNCLEAR:
    BSR.W       ELEMS_CLEARUFLOW                | clear underflow ...
    BSR.W       ELEMS_CLEAROFLOW                | ... and overflow of the intermediate steps
    MOVEA.L     A1,A0                           | A0 -> cell X, the result
    BSR.W       ELEMS_CLASSIFY                  | D0 = its class
    SUBQ.B      #0x3,D0                         | FCINF: infinite?
    BNE.B       ELEMS_ANNCLEAR_1                | no ->
    BSR.W       ELEMS_FORCEOFLOW                | infinite: signal overflow
    BRA.B       ELEMS_ANNDOUT                   | ->
| @1: not infinite
ELEMS_ANNCLEAR_1:
    SUBQ.B      #0x2,D0                         | normal (class 5)?
    BEQ.B       ELEMS_ANNDOUT                   | yes ->
    BSR.W       ELEMS_FORCEUFLOW                | zero or denormal: signal underflow
| ANNDOUT: store the result
ELEMS_ANNDOUT:
    LEA.L       -0x1A(A6),A0                    | A0 -> cell X
    MOVEA.L     A4,A1                           | A1 -> dst
    BSR.W       ELEMS_A0TOA1                    | (A4) := the annuity
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_ANNSPECIAL -- huge r and (1 + r)^-n: the annuity is
| -(r^-(n+1)) = -2^(-(n+1) * log2(r)); A1 -> cell X.
ELEMS_ANNSPECIAL:
    MOVEA.L     D5,A0                           | A0 -> r (A1 -> cell X)
    BSR.W       ELEMS_A0TOA1                    | X := r
    PEA.L       (A1)                            | dst: cell X
    MOVE.W      #0x2,-(SP)                      | Elems opcode FLOG2X
    BSR.W       _PACK_5_                        | X := log2(r)
    LEA.L       -0x24(A6),A1                    | A1 -> cell Y
    MOVEA.L     D4,A0                           | A0 -> n
    BSR.W       ELEMS_A0TOA1                    | Y := n
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A1)                            | dst: cell Y
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | Y := n + 1
    PEA.L       (A1)                            | src: cell Y, n + 1
    LEA.L       -0x1A(A6),A1                    | A1 -> cell X again
    PEA.L       (A1)                            | dst: cell X, log2(r)
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := (n + 1) * log2(r)
    BCHG        #0x7,(A1)                       | X := -(n + 1) * log2(r)
    PEA.L       (A1)                            | dst: cell X
    MOVE.W      #0xA,-(SP)                      | Elems opcode FEXP2X
    BSR.W       _PACK_5_                        | X := 2^X = r^-(n+1)
    BCHG        #0x7,(A1)                       | X := -(r^-(n+1))
    BRA.B       ELEMS_ANNCLEAR                  | -> flags, store
| ----------------------------------------------------------
| ELEMS_SINTOP -- sin(x) (opcode $18): sin(+-0) = +-0,
| sin(+-inf) is invalid: NaN code 33 (NANTRIG). The argument is reduced
| modulo approximate pi/2 (TRIGREDUCTION) to |T| <= pi/4, x = q * pi/2 + T:
| q mod 2 selects sin (0) or cos (1) of T (SINGUTS, COSGUTS), q mod 4 = 2
| or 3 negates the result. D1 = class - FCINF; uses A0-A2.
ELEMS_SINTOP:
    MOVEQ.L     #0x21,D0                        | NaN code 33 (NANTRIG), for an infinite x
    MOVEQ.L     #0x0,D2                         | quotient adjustment 0 for sin
    SUBQ.B      #0x1,D1                         | D1.B: -1 infinity, 0 zero, 1 normal, 2 denormal
    BEQ.W       ELEMS_RESULTDELIVERED           | sin(+-0) = +-0 ->
| SINCOSCOM: sin and cos of a finite or infinite x
ELEMS_SINCOSCOM:
    BMI.W       ELEMS_ERRORNAN                  | sin, cos of +-inf: invalid, NaN(33) ->
    BSR.B       ELEMS_TRIGREDUCTION             | T := T REM pi/2, D2 += quotient
    BTST        #0x0,D2                         | quotient odd?
    BNE.B       ELEMS_SINCOSCOM_1               | yes: cos ->
    BSR.B       ELEMS_SINGUTS                   | even: (A4) := sin(T)
    BRA.B       ELEMS_SINCOSCOM_3               | ->
| @1: odd quotient
ELEMS_SINCOSCOM_1:
    BSR.W       ELEMS_COSGUTS                   | odd: (A4) := cos(T)
| @3: the sign from the quotient
ELEMS_SINCOSCOM_3:
    ANDI.W      #0x3,D2                         | quotient mod 4
    SUBQ.W      #0x2,D2                         | 2 or 3?
    BMI.B       ELEMS_TRIGFINI                  | no ->
    BCHG        #0x7,(A4)                       | yes: negate the result
| ----------------------------------------------------------
| ELEMS_TRIGFINI -- common end of sin, cos and tan: clear
| underflow, set inexact; a denormal result signals underflow again.
ELEMS_TRIGFINI:
    BSR.W       ELEMS_CLEARUFLOW                | clear underflow (tested again below)
    BSR.W       ELEMS_FORCEINEXACT              | the result is inexact
    PEA.L       (A4)                            | src: the result
    PEA.L       -0x4(A6)                        | dst: cell I, receives the class
    MOVE.W      #0x1C,-(SP)                     | opword FCLASSX
    _FP68K                                      | I := class of the result: -6..6
    MOVE.W      -0x4(A6),D0                     | D0 = class
    BPL.B       ELEMS_TRIGFINI_11               | ->
    NEG.W       D0                              | D0 = |class|
ELEMS_TRIGFINI_11:
    SUBQ.W      #0x6,D0                         | denormal (FCDENORM = 6)?
    BNE.B       ELEMS_TRIGFINI_13               | no ->
    BSR.W       ELEMS_FORCEUFLOW                | yes: signal underflow
ELEMS_TRIGFINI_13:
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| ELEMS_COSTOP -- cos(x) (opcode $1A): cos(+-0) = 1,
| cos(+-inf) is invalid (NaN code 33); otherwise the sin code with the
| quotient adjusted by 1, as cos(T) = sin(T + pi/2): q mod 2 selects
| cos (0) or sin (1), (q+1) mod 4 = 2 or 3 negates.
ELEMS_COSTOP:
    MOVEQ.L     #0x21,D0                        | NaN code 33 (NANTRIG), for an infinite x
    MOVEQ.L     #0x1,D2                         | quotient adjustment 1: cos(T) = sin(T + pi/2)
    SUBQ.B      #0x1,D1                         | D1.B: -1 infinity, 0 zero, 1 normal, 2 denormal
    BNE.B       ELEMS_SINCOSCOM                 | nonzero -> the sin/cos code
    BRA.W       ELEMS_P1STUFF                   | cos(+-0) = 1 ->
| ----------------------------------------------------------
| ELEMS_TRIGREDUCTION -- T := T REM approximate pi/2
| (A4), |T| <= pi/4; D2 := D2 (the quotient adjustment) + the low bits of
| the quotient (FREMX returns them in D0). Uses D0.
ELEMS_TRIGREDUCTION:
    PEA.L       ELEMS_FPKPI2(PC)                | src: pi/2 (FPKPI2, approximate)
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0xC,-(SP)                      | opword FREMX
    _FP68K                                      | (A4) := T REM pi/2; D0 = low quotient bits, signed
    ADD.W       D0,D2                           | D2 := adjustment + quotient
    RTS                                         | return from TRIGREDUCTION
| ----------------------------------------------------------
| ELEMS_SINGUTS -- (A4) := sin(T) for |T| <= pi/4:
| T - T * S * P(S)/Q(S), S = T*T, coefficients SINQ (ELEMS_SINQ) and
| SINP right behind it. Uses A0-A2, cells W, X, Y.
ELEMS_SINGUTS:
    LEA.L       ELEMS_SINQ(PC),A2               | A2 -> SINQ, the Q coefficients (SINP follows)
    BSR.B       ELEMS_POVERQ                    | W := S = T*T, X := P(S)/Q(S)
    PEA.L       (A4)                            | src: T
    PEA.L       (A2)                            | dst: cell W, S
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | W := S * T = T^3
    PEA.L       (A2)                            | src: cell W, T^3
    PEA.L       (A0)                            | dst: cell X, P/Q
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := T^3 * P(S)/Q(S)
    PEA.L       (A0)                            | src: cell X
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | (A4) := T - T^3 * P(S)/Q(S) = sin(T)
    RTS                                         | return from SINGUTS
| ----------------------------------------------------------
| ELEMS_T2POVERQ -- like POVERQ, then X := S * P(S)/Q(S):
| cell W = S = T*T, A0 -> cell X, A2 -> cell W. Uses cell Y.
ELEMS_T2POVERQ:
    BSR.B       ELEMS_POVERQ                    | W := S = T*T, X := P(S)/Q(S)
    PEA.L       (A2)                            | src: cell W, S
    PEA.L       (A0)                            | dst: cell X, P/Q
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := S * P(S)/Q(S)
    RTS                                         | return from T2POVERQ
| ----------------------------------------------------------
| ELEMS_POVERQ -- for T = (A4) and A2 -> a Q coefficient
| table with the P table right behind it: W := S = T*T, Y := Q(S),
| X := P(S) / Q(S); returns A0 -> cell X, A2 -> cell W. Used by T2POVERQ
| and ATANGUTS.
| Called by: ELEMS_SINGUTS, ELEMS_T2POVERQ,
| ELEMS_ATANGUTS
ELEMS_POVERQ:
    MOVEA.L     A4,A0                           | A0 -> T
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := T
    PEA.L       (A1)                            | src: cell W, T
    PEA.L       (A1)                            | dst: the same
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | W := T*T = S
    EXG         A1,A2                           | A1 -> the Q table, A2 -> cell W
    LEA.L       -0x24(A6),A0                    | A0 -> cell Y, the result slot
    BSR.W       ELEMS_POLYEVAL                  | Y := Q(S); A1 -> the P table behind it
    PEA.L       (A0)                            | src for the FDIVX below: cell Y, Q(S)
    LEA.L       -0x1A(A6),A0                    | A0 -> cell X, the result slot
    BSR.W       ELEMS_POLYEVAL                  | X := P(S)
    PEA.L       (A0)                            | dst: cell X, P(S)
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | X := P(S) / Q(S)
    RTS                                         | return from POVERQ: A0 -> X, A2 -> W
| ----------------------------------------------------------
| ELEMS_COSGUTS -- (A4) := cos(T) for |T| <= pi/4, S =
| T*T: for S <= 1/4, 1 - S/2 + S*S * P(S)/Q(S); else, with Z = |T| - 1/2,
| 7/8 - (Z/2 + (Z*Z/2 - S*S * P(S)/Q(S))), the same value with less
| rounding error. Coefficients COSQ (ELEMS_COSQ) and COSP behind it.
| Uses A0-A2, cells W, X, Y.
ELEMS_COSGUTS:
    LEA.L       ELEMS_COSQ(PC),A2               | A2 -> COSQ, the Q coefficients (COSP follows)
    BSR.B       ELEMS_T2POVERQ                  | W := S = T*T, X := S * P(S)/Q(S)
    PEA.L       (A2)                            | src: cell W, S
    PEA.L       (A0)                            | dst: cell X
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := S*S * P(S)/Q(S)
    PEA.L       ELEMS_FPKFOURTH(PC)             | src: 1/4 (FPKFOURTH)
    PEA.L       (A2)                            | dst: cell W, S
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare S with 1/4
    BGT.B       ELEMS_CGBIG                     | FBGTS: S > 1/4: the long form ->
    PEA.L       ELEMS_FPKHALF(PC)               | src: 1/2 (FPKHALF)
    PEA.L       (A2)                            | dst: cell W, S
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | W := S/2
    PEA.L       (A2)                            | src: cell W, S/2
    PEA.L       (A0)                            | dst: cell X, S*S*P/Q
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | X := S*S*P/Q - S/2
    MOVEA.L     A4,A1                           | A1 -> dst
    BSR.W       ELEMS_A0TOA1                    | (A4) := X
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A4)                            | dst: (A4)
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := 1 - S/2 + S*S*P/Q = cos(T)
    RTS                                         | return from COSGUTS
| CGBIG: S > 1/4: the long form
ELEMS_CGBIG:
    BCLR        #0x7,(A4)                       | (A4) := |T|
    PEA.L       ELEMS_FPKHALF(PC)               | src: 1/2 (FPKHALF)
    PEA.L       (A4)                            | dst: |T|
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | (A4) := Z = |T| - 1/2
    PEA.L       (A0)                            | src for the FSUBX below: cell X, S*S*P/Q
    MOVEA.L     A4,A0                           | A0 -> Z
    MOVEA.L     A2,A1                           | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := Z
    PEA.L       ELEMS_FPKHALF(PC)               | src: 1/2 (FPKHALF)
    PEA.L       (A1)                            | dst: cell W, Z
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | W := Z/2
    PEA.L       (A1)                            | src: cell W, Z/2
    PEA.L       (A4)                            | dst: Z
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := Z*Z/2
    PEA.L       (A4)                            | dst: Z*Z/2; src: cell X, pushed above
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | (A4) := Z*Z/2 - S*S*P/Q
    PEA.L       (A1)                            | src: cell W, Z/2
    PEA.L       (A4)                            | dst: (A4)
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := Z/2 + (Z*Z/2 - S*S*P/Q)
    BCHG        #0x7,(A4)                       | negate it
    PEA.L       ELEMS_FPK78(PC)                 | src: 7/8 (FPK78)
    PEA.L       (A4)                            | dst: (A4)
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := 7/8 - (Z/2 + (Z*Z/2 - S*S*P/Q)) = cos(T)
    RTS                                         | return from COSGUTS
| ----------------------------------------------------------
| ELEMS_TANTOP -- tan(x) (opcode $1C): tan(+-0) = +-0,
| tan(+-inf) is invalid (NaN code 33). Reduced modulo pi/2 like sin;
| tan(pi/2 + T) = -1/tan(T) and tan(pi + T) = tan(T), so an odd quotient
| gives -1/tan(T). Uses A0-A2, D0-D2.
ELEMS_TANTOP:
    MOVEQ.L     #0x21,D0                        | NaN code 33 (NANTRIG), for an infinite x
    MOVEQ.L     #0x0,D2                         | no quotient adjustment for tan
    SUBQ.B      #0x1,D1                         | D1.B: -1 infinity, 0 zero, 1 normal, 2 denormal
    BMI.W       ELEMS_ERRORNAN                  | tan(+-inf): invalid, NaN(33) ->
    BEQ.W       ELEMS_RESULTDELIVERED           | tan(+-0) = +-0 ->
    BSR.W       ELEMS_TRIGREDUCTION             | T := T REM pi/2, D2 = quotient
    BSR.B       ELEMS_TANGUTS                   | (A4) := tan(T)
    ROR.W       #0x1,D2                         | bit 0 of the quotient into C
    BCC.B       ELEMS_TANTOP_21                 | even: tan(T) ->
    BCHG        #0x7,(A4)                       | odd: -tan(T) ...
    MOVEA.L     A4,A0                           | A0 -> -tan(T)
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := -tan(T)
    PEA.L       (A1)                            | src for the FDIVX below: cell W
    LEA.L       ELEMS_FPK1(PC),A0               | A0 -> 1 (FPK1)
    MOVEA.L     A4,A1                           | A1 -> dst
    BSR.W       ELEMS_A0TOA1                    | (A4) := 1
    PEA.L       (A4)                            | dst: 1
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := 1 / -tan(T)
    BSR.W       ELEMS_TESTDIVZER                | tan(T) was 0 (divide by zero)?
    BEQ.B       ELEMS_TANTOP_21                 | no ->
    BCHG        #0x7,(A4)                       | yes: flip the sign of the infinity (sign of the argument)
ELEMS_TANTOP_21:
    BRA.W       ELEMS_TRIGFINI                  | -> inexact, underflow check, deliver
| ----------------------------------------------------------
| ELEMS_TANGUTS -- (A4) := tan(T) for |T| <= pi/4, S =
| T*T: for S <= 1/4, T + (T^3/3 + T^5 * P(S)/Q(S)); else, with T' =
| (T - 3/4)/3, T + (S/4 + S*T' + T^5 * P(S)/Q(S)) (S/4 + S*T' = T^3/3).
| Coefficients TANQ (ELEMS_TANQ) and TANP behind it. Cell Z keeps
| T^3.
ELEMS_TANGUTS:
    LEA.L       ELEMS_TANQ(PC),A2               | A2 -> TANQ, the Q coefficients (TANP follows)
    BSR.W       ELEMS_T2POVERQ                  | W := S = T*T, X := S * P(S)/Q(S)
    MOVEA.L     A4,A0                           | A0 -> T
    LEA.L       -0x2E(A6),A1                    | A1 -> cell Z
    BSR.W       ELEMS_A0TOA1                    | Z := T
    PEA.L       (A2)                            | src: cell W, S
    PEA.L       (A1)                            | dst: cell Z, T
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | Z := T * S = T^3
    PEA.L       (A1)                            | src: cell Z, T^3
    LEA.L       -0x1A(A6),A0                    | A0 -> cell X
    PEA.L       (A0)                            | dst: cell X, S*P/Q
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | X := T^5 * P(S)/Q(S)
    PEA.L       ELEMS_FPKFOURTH(PC)             | src: 1/4 (FPKFOURTH)
    PEA.L       (A2)                            | dst: cell W, S
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare S with 1/4
    BGT.B       ELEMS_TGBIG                     | FBGTS: S > 1/4: the longer formula ->
    PEA.L       ELEMS_FPK3(PC)                  | src: 3 (FPK3)
    PEA.L       (A1)                            | dst: cell Z, T^3
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | Z := T^3 / 3
    PEA.L       (A1)                            | src: cell Z
    PEA.L       (A0)                            | dst: cell X
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | X := T^3/3 + T^5 * P/Q
    BRA.B       ELEMS_TGFIN                     | -> add T
| TGBIG: S > 1/4: the longer formula
ELEMS_TGBIG:
    PEA.L       (A0)                            | src for the FADDX below: cell X, T^5 * P/Q
    MOVEA.L     A4,A0                           | A0 -> T
    LEA.L       -0x24(A6),A1                    | A1 -> cell Y
    BSR.W       ELEMS_A0TOA1                    | Y := T
    PEA.L       ELEMS_FPK34(PC)                 | src: 3/4 (FPK34)
    PEA.L       (A1)                            | dst: cell Y, T
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | Y := T - 3/4
    PEA.L       ELEMS_FPK3(PC)                  | src: 3 (FPK3)
    PEA.L       (A1)                            | dst: cell Y
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | Y := (T - 3/4) / 3 = T'
    PEA.L       (A2)                            | src: cell W, S
    PEA.L       (A1)                            | dst: cell Y, T'
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | Y := S * T'
    PEA.L       (A1)                            | dst: cell Y; src: cell X, pushed above
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | Y := S*T' + T^5 * P/Q
    PEA.L       ELEMS_FPKFOURTH(PC)             | src: 1/4 (FPKFOURTH)
    PEA.L       (A2)                            | dst: cell W, S
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | W := S/4
    PEA.L       (A2)                            | src: cell W, S/4
    PEA.L       (A1)                            | dst: cell Y
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | Y := S/4 + S*T' + T^5 * P/Q
    MOVEA.L     A1,A0                           | A0 -> cell Y
| TGFIN: add (A0), X or Y, to T
ELEMS_TGFIN:
    PEA.L       (A0)                            | src: cell X or Y
    PEA.L       (A4)                            | dst: T
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := T + (...) = tan(T)
    RTS                                         | return from TANGUTS
| ----------------------------------------------------------
| ELEMS_ATANTOP -- atan(x) (opcode $1E) for any x:
| atan(+-0) = +-0, atan(+-inf) = +-pi/2; else atan(-T) = -atan(T) and
| ATANGUTS for |T|. D1 = class - FCINF, its bit 15 the sign of x. Uses
| A0-A2, D0-D2.
ELEMS_ATANTOP:
    SUBQ.B      #0x1,D1                         | D1.B: -1 infinity, 0 zero, 1 normal, 2 denormal
    BGE.B       ELEMS_ATFINITE                  | finite ->
    LEA.L       ELEMS_FPKPI2(PC),A0             | atan(+-inf) = +-pi/2: A0 -> pi/2 (FPKPI2)
    MOVEA.L     A4,A1                           | A1 -> dst
    BSR.W       ELEMS_A0TOA1                    | (A4) := pi/2
    CLR.B       D1                              | D1.W = the sign of x (bit 15)
    OR.W        D1,(A4)                         | with the sign of x
    BRA.B       ELEMS_ATQUICK                   | -> deliver
| ATFINITE
ELEMS_ATFINITE:
    BNE.B       ELEMS_ATHARD                    | nonzero ->
| ATQUICK
ELEMS_ATQUICK:
    BRA.W       ELEMS_RESULTDELIVERED           | atan(+-0) = +-0, atan(+-inf) = +-pi/2 ->
| ATHARD: finite, nonzero
ELEMS_ATHARD:
    BCLR        #0x7,(A4)                       | (A4) := |T|; the sign stays in D1 bit 15
    BSR.B       ELEMS_ATANGUTS                  | (A4) := atan(|T|)
    CLR.B       D1                              | D1.W = the sign (bit 15)
    OR.W        D1,(A4)                         | atan(T) = sign * atan(|T|)
    BRA.W       ELEMS_TRIGFINI                  | -> inexact, underflow check, deliver
| ----------------------------------------------------------
| ELEMS_ATANGUTS -- (A4) := atan(T) for T > 0. T > 1 is
| inverted first (atan(T) = pi/2 - atan(1/T); D2 = -1). Then for T <=
| ATNCONS = 2 - sqrt(3) = tan(pi/12) = 0.2679: T - T * P(T*T)/Q(T*T)
| (ATANQ, ATANP); else, with x2 = 1/sqrt(3) = tan(pi/6) (FPKX2) and x2fx2
| = x2 - atan(x2) (FPKX2FX2): T - (A + B * P(B*B)/Q(B*B) + x2fx2), A =
| (T - x2)/(1 + 1/(T*x2)), B = (T - x2)/(1 + T*x2); since T - x2 - A = B
| this is pi/6 + atan(B). The reduced T is kept on the stack meanwhile.
ELEMS_ATANGUTS:
    MOVEQ.L     #0x0,D2                         | D2 := 0: not inverted
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare T with 1
    BLS.B       ELEMS_AGNOINV                   | FBLES: T <= 1 ->
    MOVEQ.L     #-0x1,D2                        | D2 := -1: inverted
    MOVEA.L     A4,A0                           | A0 -> T
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := T
    PEA.L       (A1)                            | src for the FDIVX below: cell W, T
    LEA.L       ELEMS_FPK1(PC),A0               | A0 -> 1 (FPK1)
    MOVEA.L     A4,A1                           | A1 -> dst
    BSR.W       ELEMS_A0TOA1                    | (A4) := 1
    PEA.L       (A1)                            | dst: 1 (A1 = A4)
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := 1 / T
| AGNOINV: 0 < T <= 1
ELEMS_AGNOINV:
    MOVE.L      (A4)+,-(SP)                     | push a copy of the reduced T: bytes 0-3, ...
    MOVE.L      (A4)+,-(SP)                     | ... bytes 4-7, ...
    MOVE.W      (A4),-(SP)                      | ... bytes 8-9
    SUBQ.L      #0x8,A4                         | A4 back to the head
    PEA.L       ELEMS_FPKATNCONS(PC)            | src: 2 - sqrt(3) = tan(pi/12) (FPKATNCONS)
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x8,-(SP)                      | opword FCMPX
    _FP68K                                      | compare T with ATNCONS
    BGT.B       ELEMS_AGLONGFORM                | FBGTS: T > ATNCONS: the long form ->
    LEA.L       ELEMS_ATANQ(PC),A2              | A2 -> ATANQ, the Q coefficients (ATANP follows)
    BSR.W       ELEMS_POVERQ                    | W := T*T, X := P(T*T)/Q(T*T)
    PEA.L       (A0)                            | src: cell X, P/Q
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := T * P/Q
    BRA.W       ELEMS_AGFINI                    | -> T - (A4)
| AGLONGFORM: T > ATNCONS
ELEMS_AGLONGFORM:
    MOVEA.L     A4,A0                           | A0 -> T
    LEA.L       -0x10(A6),A1                    | A1 -> cell W
    BSR.W       ELEMS_A0TOA1                    | W := T
    PEA.L       ELEMS_FPKX2(PC)                 | src: x2 = 1/sqrt(3) (FPKX2)
    PEA.L       (A1)                            | dst: cell W, T
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | W := T * x2
    PEA.L       (A1)                            | src for the FDIVX below: cell W, T*x2
    LEA.L       ELEMS_FPK1(PC),A0               | A0 -> 1 (FPK1)
    LEA.L       -0x24(A6),A1                    | A1 -> cell Y
    BSR.W       ELEMS_A0TOA1                    | Y := 1
    PEA.L       (A1)                            | dst: cell Y; src: cell W, pushed above
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | Y := 1 / (T*x2)
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       (A1)                            | dst: cell Y
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | Y := 1 + 1/(T*x2)
    PEA.L       ELEMS_FPK1(PC)                  | src: 1 (FPK1)
    PEA.L       -0x10(A6)                       | dst: cell W, T*x2
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | W := 1 + T*x2
    PEA.L       ELEMS_FPKX2(PC)                 | src: x2 (FPKX2)
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | (A4) := T - x2
    MOVEA.L     A4,A0                           | A0 -> T - x2
    LEA.L       -0x2E(A6),A1                    | A1 -> cell Z
    BSR.W       ELEMS_A0TOA1                    | Z := T - x2
    PEA.L       -0x10(A6)                       | src: cell W, 1 + T*x2
    PEA.L       (A4)                            | dst: T - x2
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | (A4) := (T - x2)/(1 + T*x2) = B
    PEA.L       -0x24(A6)                       | src: cell Y, 1 + 1/(T*x2)
    PEA.L       (A1)                            | dst: cell Z, T - x2
    MOVE.W      #0x6,-(SP)                      | opword FDIVX
    _FP68K                                      | Z := (T - x2)/(1 + 1/(T*x2)) = A
    LEA.L       ELEMS_ATANQ(PC),A2              | A2 -> ATANQ (ATANP follows)
    BSR.W       ELEMS_POVERQ                    | W := B*B, X := P(B*B)/Q(B*B); Y clobbered, Z = A kept
    PEA.L       (A0)                            | src: cell X, P/Q
    PEA.L       (A4)                            | dst: B
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := B * P/Q
    PEA.L       ELEMS_FPKX2FX2(PC)              | src: x2 - atan(x2) (FPKX2FX2)
    PEA.L       (A4)                            | dst: B * P/Q
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := B*P/Q + x2fx2
    PEA.L       -0x2E(A6)                       | src: cell Z, A
    PEA.L       (A4)                            | dst: (A4)
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := A + B*P/Q + x2fx2
| ----------------------------------------------------------
| ELEMS_AGFINI -- (A4) := T - RES, or pi/2 - (T - RES)
| if T was inverted; T is the copy on the stack.
ELEMS_AGFINI:
    LEA.L       -0x8(A6),A1                     | A1 -> 8 bytes into cell W (STW+8)
    MOVE.W      (SP)+,(A1)                      | pop the saved T into cell W: bytes 8-9, ...
    MOVE.L      (SP)+,-(A1)                     | ... bytes 4-7, ...
    MOVE.L      (SP)+,-(A1)                     | ... bytes 0-3; A1 -> cell W
    PEA.L       (A1)                            | src: cell W, the saved T
    PEA.L       (A4)                            | dst: RES
    MOVE.W      #0x2,-(SP)                      | opword FSUBX
    _FP68K                                      | (A4) := RES - T
    TST.W       D2                              | inverted?
    BNE.B       ELEMS_AGSUBPI2                  | yes ->
    BCHG        #0x7,(A4)                       | (A4) := T - RES = atan(T)
    RTS                                         | return from ATANGUTS
| AGSUBPI2: inverted: pi/2 - (T - RES)
ELEMS_AGSUBPI2:
    PEA.L       ELEMS_FPKPI2(PC)                | src: pi/2 (FPKPI2)
    PEA.L       (A4)                            | dst: RES - T
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := pi/2 - (T - RES) = atan(1/T)
    RTS                                         | return from ATANGUTS
| ----------------------------------------------------------
| ELEMS_RANDTOP -- RandomX (opcode $20): next T := (7^5 *
| T) MOD (2^31 - 1), after Linus Schrage, "A More Portable FORTRAN Random
| Number Generator", ACM TOMS 5(2), June 1979, pp. 132-138 (Apple's
| comment says "ARand * T + PRand"). T must be an integer strictly
| between 0 and 2^31 - 1.
ELEMS_RANDTOP:
    PEA.L       ELEMS_FPKARAND(PC)              | src: 7^5 = 16807 (FPKARAND)
    PEA.L       (A4)                            | dst: T
    MOVE.W      #0x4,-(SP)                      | opword FMULX
    _FP68K                                      | (A4) := T * 7^5
    PEA.L       ELEMS_FPKPRAND(PC)              | src: 2^31 - 1 (FPKPRAND)
    PEA.L       (A4)                            | dst: T * 7^5
    MOVE.W      #0xC,-(SP)                      | opword FREMX
    _FP68K                                      | (A4) := (T * 7^5) REM (2^31 - 1): |result| <= (2^31 - 1)/2
    TST.B       (A4)                            | negative?
    BPL.B       ELEMS_RANDTOP_1                 | no ->
    PEA.L       ELEMS_FPKPRAND(PC)              | src: 2^31 - 1 (FPKPRAND)
    PEA.L       (A4)                            | dst: (A4)
    CLR.W       -(SP)                           | opword FADDX
    _FP68K                                      | (A4) := (A4) + (2^31 - 1)
ELEMS_RANDTOP_1:
    BRA.W       ELEMS_RESULTDELIVERED           | -> deliver
| ----------------------------------------------------------
| Constants (Apple ELEMS68KC.a, generated by HexWriter from ELEMSDEC.TEXT):
| the polynomial tables for POLYEVAL (a degree word N, then N+1 extended
| coefficients, leading term first; each P table follows its Q table where
| POVERQ needs that) and the extended constants FPK*. FPKPI4 and FPKE are
| not referenced.
ELEMS_LOG21P:
    .short      0x0005                          | LOG21P: degree 5, 6 coefficients follow
    .short      0x3FF6,0xB946,0x46AF,0xF6CE,0x3BFF | z^5: 0.00282706475988
    .short      0x3FF9,0x94F4,0x3221,0x4D61,0xFBEB | z^4: 0.0181828478912
    .short      0x3FFB,0xDC97,0x8903,0xD944,0x7893 | z^3: 0.107710905485
    .short      0x3FFF,0x9F9E,0x3946,0x57CA,0x1D05 | z^2: 1.24701610503
    .short      0xC001,0xCD6B,0xC53A,0x46EC,0xDC9A | z^1: -6.41940556891
    .short      0x4001,0xB483,0x97E7,0xBAE6,0xFCE0 | z^0: 5.64106364498
| LOG21Q: Q of LOGAPPROX
ELEMS_LOG21Q:
    .short      0x0002                          | LOG21Q: degree 2, 3 coefficients follow
    .short      0x3FFF,0x8000,0x0000,0x0000,0x0000 | z^2: 1
    .short      0xC000,0xB818,0x35C3,0xCE0A,0x5E1D | z^1: -2.87647766229
    .short      0x3FFF,0xFA3E,0xDF0E,0xDDF4,0x1A96 | z^0: 1.95504368044
| EXP21P: P of EXPAPPROX
ELEMS_EXP21P:
    .short      0x0003                          | EXP21P: degree 3, 4 coefficients follow
    .short      0xBFEE,0xFF88,0x90C8,0x1B20,0x9B79 | z^3: -1.52309810634e-05
    .short      0x3FF9,0xDA5C,0x84EF,0xB813,0x272F | z^2: 0.0266554447569
    .short      0x4003,0x97D3,0xBAEA,0xF80F,0xFD45 | z^1: 18.9783838613
    .short      0x4009,0xAB86,0x71A1,0x95BE,0xFF0C | z^0: 1372.201371
| EXP21Q: Q of EXPAPPROX
ELEMS_EXP21Q:
    .short      0x0002                          | EXP21Q: degree 2, 3 coefficients follow
    .short      0x3FFF,0x8000,0x0000,0x0000,0x0000 | z^2: 1
    .short      0x4006,0xD548,0x7002,0x984B,0x5AB4 | z^1: 213.282959139
    .short      0x400A,0xF775,0x612E,0x96B7,0x0780 | z^0: 3959.33622607
ELEMS_FPK1:
    .short      0x3FFF,0x8000,0x0000,0x0000,0x0000 | FPK1: 1
ELEMS_FPKM1:
    .short      0xBFFF,0x8000,0x0000,0x0000,0x0000 | FPKM1: -1
ELEMS_FPK0:
    .short      0x0000,0x0000,0x0000,0x0000,0x0000 | FPK0: +0
ELEMS_FPKM0:
    .short      0x8000,0x0000,0x0000,0x0000,0x0000 | FPKM0: -0
ELEMS_FPK2:
    .short      0x4000,0x8000,0x0000,0x0000,0x0000 | FPK2: 2
ELEMS_FPKMAXINT:
    .short      0x400D,0xFFFE,0x0000,0x0000,0x0000 | FPKMAXINT: 32767 = 2^15 - 1 (MAXINT)
ELEMS_FPKINF:
    .short      0x7FFF,0x0000,0x0000,0x0000,0x0000 | FPKINF: +inf
ELEMS_FPKMINF:
    .short      0xFFFF,0x0000,0x0000,0x0000,0x0000 | FPKMINF: -inf
ELEMS_FPK3:
    .short      0x4000,0xC000,0x0000,0x0000,0x0000 | FPK3: 3
ELEMS_FPKFOURTH:
    .short      0x3FFD,0x8000,0x0000,0x0000,0x0000 | FPKFOURTH: 1/4 = 0.25
ELEMS_FPKHALF:
    .short      0x3FFE,0x8000,0x0000,0x0000,0x0000 | FPKHALF: 1/2 = 0.5
ELEMS_FPK34:
    .short      0x3FFE,0xC000,0x0000,0x0000,0x0000 | FPK34: 3/4 = 0.75
ELEMS_FPK78:
    .short      0x3FFE,0xE000,0x0000,0x0000,0x0000 | FPK78: 7/8 = 0.875
ELEMS_FPKPI2:
    .short      0x3FFF,0xC90F,0xDAA2,0x2168,0xC235 | FPKPI2: pi/2 (approximate) = 1.57079632679
    .short      0x3FFE,0xC90F,0xDAA2,0x2168,0xC235 | FPKPI4: pi/4 (not used) = 0.785398163397
ELEMS_FPKARAND:
    .short      0x400D,0x834E,0x0000,0x0000,0x0000 | FPKARAND: 7^5 = 16807 (ARand)
ELEMS_FPKPRAND:
    .short      0x401D,0xFFFF,0xFFFE,0x0000,0x0000 | FPKPRAND: 2^31 - 1 (PRand) = 2147483647
ELEMS_FPKSQRT2:
    .short      0x3FFF,0xB504,0xF333,0xF9DE,0x6484 | FPKSQRT2: sqrt(2) = 1.41421356237
ELEMS_FPKSQRTHALF:
    .short      0x3FFE,0xB504,0xF333,0xF9DE,0x6484 | FPKSQRTHALF: sqrt(1/2) = 0.707106781187
    .short      0x4000,0xADF8,0x5458,0xA2BB,0x4A9B | FPKE: e (not used) = 2.71828182846
ELEMS_FPKLOGE2:
    .short      0x3FFE,0xB172,0x17F7,0xD1CF,0x79AC | FPKLOGE2: ln(2) = 0.69314718056
ELEMS_FPKX2:
    .short      0x3FFE,0x93CD,0x3A2C,0x8198,0xE26A | FPKX2: x2 = 1/sqrt(3) = tan(pi/6) = 0.57735026919
ELEMS_FPKX2FX2:
    .short      0x3FFA,0xDC2A,0x86B1,0x5FDB,0x6462 | FPKX2FX2: x2 - atan(x2) = 1/sqrt(3) - pi/6 = 0.0537514935913
ELEMS_FPKATNCONS:
    .short      0x3FFD,0x8930,0xA2F4,0xF66A,0xB18A | FPKATNCONS: 2 - sqrt(3) = tan(pi/12) = 0.267949192431
| SINQ, SINP: Q and P of SINGUTS (sn7.text, 14 May 83)
ELEMS_SINQ:
    .short      0x0003                          | SINQ: degree 3, 4 coefficients follow
    .short      0x3FFF,0x8000,0x0000,0x0000,0x0000 | z^3: 1
    .short      0x4007,0x88D8,0xB844,0xA6A8,0x5A30 | z^2: 273.693123418
    .short      0x400E,0x8A15,0x8A49,0x0979,0x2320 | z^1: 35349.540177
    .short      0x4013,0xFAA9,0xFE26,0xFE63,0xF22B | z^0: 2053439.76904
    .short      0x0003                          | SINP: degree 3, 4 coefficients follow
    .short      0xBFFE,0xC250,0x86AE,0x43F5,0xCBF5 | z^3: -0.759041230722
    .short      0x4006,0x9E76,0xEC66,0xBEE7,0x6BA2 | z^2: 158.464544698
    .short      0xC00C,0xAF51,0xA1D6,0xC4C4,0xAA01 | z^1: -11220.4080458
    .short      0x4011,0xA71B,0xFEC4,0xA997,0xF6CE | z^0: 342239.961507
| COSQ, COSP: Q and P of COSGUTS (cs7.text, 14 May 83)
ELEMS_COSQ:
    .short      0x0003                          | COSQ: degree 3, 4 coefficients follow
    .short      0x3FFF,0x8000,0x0000,0x0000,0x0000 | z^3: 1
    .short      0x4007,0xA6D9,0x6A95,0xFBDF,0x9685 | z^2: 333.698565243
    .short      0x400E,0xC7A7,0xEA65,0xE85D,0x156B | z^1: 51111.9156175
    .short      0x4014,0xD26E,0x871C,0x7B17,0x52B2 | z^0: 3447713.77781
    .short      0x0003                          | COSP: degree 3, 4 coefficients follow
    .short      0xBFFB,0xD57E,0x18D7,0xA6F6,0xD758 | z^3: -0.104244417268
    .short      0x4003,0xE364,0x937E,0x32B3,0xD072 | z^2: 28.4241094455
    .short      0xC00A,0xA62D,0x4056,0x586B,0xC045 | z^1: -2658.82820735
    .short      0x4010,0x8C49,0xAF68,0x520F,0x8C7A | z^0: 143654.740742
| TANQ, TANP: Q and P of TANGUTS (tn7.text, 23 May 83)
ELEMS_TANQ:
    .short      0x0003                          | TANQ: degree 3, 4 coefficients follow
    .short      0xBFFF,0x8000,0x0000,0x0000,0x0000 | z^3: -1
    .short      0x4005,0xB513,0x0324,0x83C0,0x0955 | z^2: 90.5371333514
    .short      0xC009,0xD1FF,0xB242,0x5762,0xE0CF | z^1: -1679.99051015
    .short      0x400A,0xE190,0x9309,0x9376,0x66AB | z^0: 3609.0358978
    .short      0x0003                          | TANP: degree 3, 4 coefficients follow
    .short      0xBFE9,0xB1FC,0x3363,0xD79B,0x2838 | z^3: -3.31523193325e-07
    .short      0x3FFD,0xAA9D,0x71D8,0x3EC7,0x4CD1 | z^2: 0.333232457778
    .short      0xC003,0xE9CD,0x8E24,0xB965,0x7DBB | z^1: -29.2253687734
    .short      0x4007,0xF09A,0x3670,0x9D4B,0x1836 | z^0: 481.204786374
| ATANQ, ATANP: Q and P of ATANGUTS (atn8.text, 17 May 83)
ELEMS_ATANQ:
    .short      0x0004                          | ATANQ: degree 4, 5 coefficients follow
    .short      0x3FFF,0x98D3,0x1EAE,0x2AFA,0x5DAD | z^4: 1.19394286637
    .short      0x4003,0x8F79,0x4CD8,0xB3CD,0xEFD9 | z^3: 17.9342286043
    .short      0x4005,0x8E37,0xED85,0x70B8,0xB368 | z^2: 71.1092340183
    .short      0x4005,0xCDA4,0xBEA1,0xAC59,0xF3B8 | z^1: 102.821766903
    .short      0x4004,0xC405,0x9C55,0x4CF0,0xC656 | z^0: 49.0054791764
    .short      0x0004                          | ATANP: degree 4, 5 coefficients follow
    .short      0x3FFF,0x8000,0x0000,0x0000,0x0000 | z^4: 1
    .short      0x4002,0xA23B,0x6C13,0x1F92,0x0E30 | z^3: 10.1395073649
    .short      0x4003,0xC3C8,0x593D,0xFA3A,0x486F | z^2: 24.4728264658
    .short      0x4003,0x82AE,0x6838,0xDDF5,0xD945 | z^1: 16.3351597255
    .short      0x0000,0x0000,0x0000,0x0000,0x0000 | z^0: +0
    ROM_RESOURCE_END PACK_5                     | end of the data: pads to even, sets the sizes
