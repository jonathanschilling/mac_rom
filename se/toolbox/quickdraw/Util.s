| -------------------------------------------------------------
|
| --> UTIL.TEXT
|
| SMALL UTILITY ROUTINES USED BY QuickDraw.

| ----------------------------------------------------------
| QuickDraw bit utilities (BitNot/And/Xor/Or/Shift/Tst/Set/Clr)
| Each is a Pascal-callable function with stacked args; pop ret
| addr to A0, do operation, store result over caller's last arg,
| then JMP (A0). All preserve A1, D2-D7.
| ----------------------------------------------------------
| BitNot ($A858) - returns bitwise NOT of long
BITNOT:
    MOVEA.L     (A7)+,A0                        | pop ret addr
    NOT.L       (A7)                            | invert long in place
    MOVE.L      (A7)+,(A7)                      | leave result in caller's slot
    JMP         (A0)                            | tail-call return from BITNOT via A0
| ----------------------------------------------------------
| BitAnd ($A858 sel ?) - long1 AND long2
BITAND:
    MOVEA.L     (A7)+,A0                        | pop ret addr
    MOVE.L      (A7)+,D0                        | D0 = long1
    AND.L       (A7)+,D0                        | D0 &= long2
    BRA.B       BITSHIFT_DONE                   | -> store + return
| ----------------------------------------------------------
| BitXor - long1 XOR long2
BITXOR:
    MOVEA.L     (A7)+,A0                        | pop ret addr
    MOVE.L      (A7)+,D0                        | D0 = long1
    MOVE.L      (A7)+,D1                        | D1 = long2
    EOR.L       D1,D0                           | D0 ^= D1
    BRA.B       BITSHIFT_DONE                   | -> store + return
| ----------------------------------------------------------
| BitOr - long1 OR long2
BITOR:
    MOVEA.L     (A7)+,A0                        | pop ret addr
    MOVE.L      (A7)+,D0                        | D0 = long1
    OR.L        (A7)+,D0                        | D0 |= long2
    BRA.B       BITSHIFT_DONE                   | -> store + return
| ----------------------------------------------------------
| BitShift(long, count: INTEGER) - positive=left, negative=right
BITSHIFT:
    MOVEA.L     (A7)+,A0                        | pop ret addr
    MOVE.W      (A7)+,D1                        | D1 = count
    BPL.B       SHLEFT                          | positive -> shift left
    NEG.W       D1                              | make positive
    MOVE.L      (A7)+,D0                        | D0 = long
    LSR.L       D1,D0                           | shift right
    BRA.B       BITSHIFT_DONE                   | -> store + return
SHLEFT:
    MOVE.L      (A7)+,D0                        | D0 = long
    LSL.L       D1,D0                           | shift left
BITSHIFT_DONE:
    MOVE.L      D0,(A7)                         | store result over last arg
    JMP         (A0)                            | tail-call return from BITSHIFT_DONE via A0
| ----------------------------------------------------------
| BitTst(bytePtr, bitNum) -> Boolean - test single bit
BITTST:
    BSR.B       BITCLR_CONT                     | shared ptr/bit setup
    MOVEA.L     (A7)+,A1                        | A1 = byte ptr
    BTST        D0,0x0(A1,D1.L)                 | test bit
    SNE.B       (A7)                            | (A7) = 0 or 0xFF
    NEG.B       (A7)                            | normalize to 0 or 1
    JMP         (A0)                            | tail-call return from BITTST via A0
| BitSet(bytePtr, bitNum) - set single bit
BITSET:
    BSR.B       BITCLR_CONT                     | shared ptr/bit setup
    MOVEA.L     (A7)+,A1                        | A1 = byte ptr
    BSET        D0,0x0(A1,D1.L)                 | set bit
    JMP         (A0)                            | tail-call return from BITSET via A0
| BitClr(bytePtr, bitNum) - clear single bit
BITCLR:
    BSR.B       BITCLR_CONT                     | shared ptr/bit setup
    MOVEA.L     (A7)+,A1                        | A1 = byte ptr
    BCLR        D0,0x0(A1,D1.L)                 | clear bit
    JMP         (A0)                            | tail-call return from BITCLR via A0
| ----------------------------------------------------------
| BITCLR_CONT - shared setup for BitTst/BitSet/BitClr
| Pops caller args: bitNum (long, on stack top), then the BSR's
| return addr (handler body), then the caller's outer ret addr.
| Computes: D0 = bit-within-byte (~bitNum), D1 = byte-offset, JMP
| back into the handler body via A1.
BITCLR_CONT:
    MOVEA.L     (A7)+,A1                        | A1 = handler body return
    MOVEA.L     (A7)+,A0                        | A0 = outer caller return
    MOVE.L      (A7)+,D1                        | D1 = bitNum
    MOVE.W      D1,D0                           | D0 = bitNum (low word)
    ASR.L       #0x3,D1                         | D1 = bitNum / 8 = byte offset
    NOT.W       D0                              | D0 = ~bitNum (BTST uses inverted)
    JMP         (A1)                            | back to handler
| ----------------------------------------------------------
| Random ($A861) - linear-congruential 16-bit pseudorandom
| Pascal: function Random: INTEGER;
| State: RandSeed (long) at -0x7E(qdGlobals).
| Algorithm: seed = (seed * 16807) mod (2^31 - 1) - Park-Miller.
| Returns INTEGER -32768..32767 (low word of seed).
RANDOM:
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    MOVE.W      #0x41A7,D0                      | D0 = 16807 (multiplier low word)
    MOVE.W      D0,D2                           | D2 = same
    MULU.W      -0x7C(A0),D0                    | D0 = 16807 * seedLowWord
    MOVE.L      D0,D1                           | D1 = same
    CLR.W       D1                              | D1 high word, low cleared
    SWAP.W      D1                              | D1 = high*65536 of D0 (carry)
    MULU.W      -0x7E(A0),D2                    | D2 = 16807 * seedHighWord
    ADD.L       D1,D2                           | combine partial products
    MOVE.L      D2,D1                           | D1 = combined high
    ADD.L       D1,D1                           | * 2 (mod operation)
    CLR.W       D1                              | mask
    SWAP.W      D1                              | re-arrange
    ANDI.L      #0xFFFF,D0                      | D0 = low 16 bits
    SUBI.L      #0x7FFFFFFF,D0                  | apply Park-Miller modulo
    ANDI.L      #0x7FFF,D2                      | mask
    SWAP.W      D2                              | reposition
    ADD.L       D1,D2                           | combine
    ADD.L       D2,D0                           | final seed
    BPL.B       RANDOM_UPDATE                   | positive -> ok
    ADDI.L      #0x7FFFFFFF,D0                  | wrap (mod 2^31-1)
RANDOM_UPDATE:
    MOVE.L      D0,-0x7E(A0)                    | save new RandSeed
    CMPI.W      #0x8000,D0                      | INT_MIN (impossible result)?
    BNE.B       RANDOM_UPDATE_NO                | no
    CLR.W       D0                              | yes -> map to 0 (avoid -32768)
RANDOM_UPDATE_NO:
    MOVE.W      D0,0x4(A7)                      | result word in caller's slot
    RTS                                         | return from RANDOM_UPDATE_NO
| ----------------------------------------------------------
| ForeColor ($A862), BackColor ($A863) - set port color long
FORECOLOR:
    MOVEQ.L     #0x50,D0                        | offset in GrafPort = fgColor
    BRA.B       PORTLONG                        | -> shared store
BACKCOLOR:
    MOVEQ.L     #0x54,D0                        | offset in GrafPort = bkColor
PORTLONG:
    MOVEA.L     (A7)+,A1                        | pop ret addr
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    MOVEA.L     (A0),A0                         | A0 -> current GrafPort
    MOVE.L      (A7)+,0x0(A0,D0.W)              | port[D0] = caller's long
    JMP         (A1)                            | tail-call return from PORTLONG via A1
| ----------------------------------------------------------
| ColorBit ($A864) - set port colorBit (1-byte plane index)
COLORBIT:
    MOVEQ.L     #0x58,D0                        | offset = colrBit
PORTWORD:
    MOVEA.L     (A7)+,A1                        | pop ret addr
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    MOVEA.L     (A0),A0                         | A0 -> current GrafPort
    MOVE.W      (A7)+,0x0(A0,D0.W)              | port[D0] = caller's word
    JMP         (A1)                            | tail-call return from PORTWORD via A1
| ----------------------------------------------------------
| GetMaskTable ($A836) - return ptr to 16-entry MASKTAB
GETMASKTAB:
    LEA.L       MASKTAB(PC),A0                  | A0 -> MASKTAB
    RTS                                         | return from GETMASKTAB
| ----------------------------------------------------------
| LeftMask(D0) -> word in D0 - mask of bits left of bit D0
LEFTMASK:
    ANDI.W      #0xF,D0                         | D0 &= 15
    ADD.W       D0,D0                           | * 2 = word offset
    MOVE.W      LeftMaskTbl(PC,D0.W),D0         | D0 = LMASK[D0]
    RTS                                         | return from LEFTMASK
| RightMask(D0) -> word in D0 - mask of bits right of bit D0
RIGHTMASK:
    ANDI.W      #0xF,D0                         | D0 &= 15
    ADD.W       D0,D0                           | * 2 = word offset
    MOVE.W      MASKTAB(PC,D0.W),D0             | D0 = RMASK[D0]
    RTS                                         | return from RIGHTMASK
| BitMask(D0) -> word in D0 - mask with single bit at position D0
BITMASK:
    ANDI.W      #0xF,D0                         | D0 &= 15
    ADD.W       D0,D0                           | * 2 = word offset
    MOVE.W      DT_MMASKTAB_CONT_2(PC,D0.W),D0  | D0 = BMASK[D0]
    RTS                                         | return from BITMASK
| ----------------------------------------------------------
| MASKTAB / LeftMaskTbl / DT_MMASKTAB_CONT_2: 17-entry x 16-bit
| QuickDraw word-boundary mask tables, each indexed by D0 = bit
| position 0..16. Returned in a single contiguous block by
| _GetMaskTable ($A836) so callers can address all three tables
| as MaskBC[0..50] from one base pointer.
|   MASKTAB           = right-side / "top bits set" masks
|     0->0x0000  1->0x8000  2->0xC000 ... 15->0xFFFE  16->0xFFFF
|   LeftMaskTbl        = left-side / "bottom bits set" masks
|     0->0xFFFF  1->0x7FFF  2->0x3FFF ... 15->0x0001  16->0x0000
|   DT_MMASKTAB_CONT_2 = single-bit isolated masks
|     0->0x8000  1->0x4000  2->0x2000 ... 15->0x0001
| Used by BitBlt edge-pixel handling and BUILDBBOX_BODY glyph-bbox
| mask construction.
MASKTAB:
    .short      0x0000
    .long       0x8000C000
    .long       0xE000F000
    .long       0xF800FC00
    .long       0xFE00FF00
    .long       0xFF80FFC0
    .long       0xFFE0FFF0
    .long       0xFFF8FFFC
    .short      0xFFFE
LeftMaskTbl:
    .short      0xFFFF
    .long       0x7FFF3FFF
    .long       0x1FFF0FFF
    .long       0x07FF03FF
    .long       0x01FF00FF
    .long       0x007F003F
    .long       0x001F000F
    .long       0x00070003
    .short      0x0001
DT_MMASKTAB_CONT_2:
    .short      0x8000
    .long       0x40002000
    .long       0x10000800
    .long       0x04000200
    .long       0x01000080
    .long       0x00400020
    .long       0x00100008
    .long       0x00040002
    .short      0x0001
| ----------------------------------------------------------
| PatExpand - expand 8-byte pattern to 16 longs
| Inputs:
|   A0 -> 8-byte pattern source
|   A1 -> 16 longs of destination buffer
|   A5 -> Pascal globals
|   D2 = horizontal global-local offset (for pre-rotate)
|   D7 = -1 to invert pattern, else 0
|   patStretch (0x5A in port) and PATALIGN drive stretch behavior
| Output: 16 longs of expanded pattern
| Clobbers: D0,D1,D2,A0,A1
| Called only from BitBlt, RgnBlt, DrawLine, DrawArc.
PATEXPAND:
    LINK        A6,#-0x10                       | allocate stack frame (16-byte TWOPAT scratch)
    MOVE.L      A4,-(A7)                        | save A4
    MOVEA.L     (A5),A4                         | A4 -> QuickDraw globals
    MOVEQ.L     #0x7,D0                         | mask for 3 lo bits
    AND.W       -0xA8(A4),D0                    | D0 = PATALIGN.v mod 8
    BEQ.B       PATEXPAND_SKIP                  | skip alignment fixup if 0
    MOVE.L      (A0),-0x10(A6)                  | first copy of pattern
    MOVE.L      (A0)+,-0x8(A6)                  | duplicate (advance src)
    MOVE.L      (A0),-0xC(A6)                   | second half of pattern
    MOVE.L      (A0),-0x4(A6)                   | duplicate
    LEA.L       -0x10(A6),A0                    | A0 -> aligned pattern buffer
    ADDA.W      D0,A0                           | A0 += PATALIGN.v offset
PATEXPAND_SKIP:
    ADD.W       -0xA6(A4),D2                    | D2 += PATALIGN.h
    MOVEQ.L     #0x7,D1                         | D1 = 7 (loop count: 8 input bytes)
    AND.W       D1,D2                           | D2 mod 8 (rotate count)
    MOVEA.L     (A4),A4                         | A4 -> current GrafPort
    MOVE.W      0x5A(A4),D0                     | D0 = patStretch
    CMPI.W      #0x2,D0                         | patStretch == 2 (DOUBLE)?
    BEQ.B       DOUBLE                          | yes -> double-size loop
    CMPI.W      #0xFFFE,D0                      | patStretch == -2 (THIN)?
    BEQ.B       THIN                            | yes -> thinned loop
| Fall through: NORMAL pattern (8x8 replication).
| ----------------------------------------------------------
| NORMAL - simple 8-byte pattern replicated as 16 longs
NORMAL:
    MOVE.B      (A0)+,D0                        | D0 = next pattern byte
    EOR.B       D7,D0                           | invert if mode bit 2 set
    ROL.B       D2,D0                           | align to local coords
    MOVE.B      D0,(A1)+                        | byte 0 of long
    MOVE.B      D0,(A1)+                        | byte 1 of long
    MOVE.W      -0x2(A1),(A1)+                  | replicate to long width
    MOVE.L      -0x4(A1),0x1C(A1)               | duplicate to scan +8
    DBF.W       D1,NORMAL                       | next pattern byte
    BRA.B       PATEXPAND_DONE                  | -> exit
| ----------------------------------------------------------
| DOUBLE - stretch each bit horizontally and vertically by 2
DOUBLE:
    CLR.W       D0                              | clear high byte
DLOOP:
    MOVE.B      (A0)+,D0                        | D0 = next pattern byte
    EOR.B       D7,D0                           | invert if mode bit 2 set
    ROL.B       D2,D0                           | align to local coords
    MOVE.B      D0,-(A7)                        | stash byte
    LSR.B       #0x4,D0                         | hi nibble
    MOVE.B      DoubleNibbleTbl(PC,D0.W),(A1)+  | hi-nibble doubled
    MOVEQ.L     #0xF,D0                         | mask lo nibble
    AND.B       (A7)+,D0                        | recover lo nibble
    MOVE.B      DoubleNibbleTbl(PC,D0.W),(A1)+  | lo-nibble doubled
    MOVE.W      -0x2(A1),(A1)+                  | replicate to long
    MOVE.L      -0x4(A1),(A1)+                  | duplicate scan
    DBF.W       D1,DLOOP                        | next byte
    BRA.B       PATEXPAND_DONE                  | -> exit
| ----------------------------------------------------------
| THIN - stretch by 2, replace each bit pair with 1+blank
THIN:
    CLR.W       D0                              | clear high byte
THINLP:
    MOVE.B      (A0)+,D0                        | D0 = next pattern byte
    EOR.B       D7,D0                           | invert if mode bit 2 set
    ROL.B       D2,D0                           | align to local coords
    MOVE.B      D0,-(A7)                        | stash byte
    LSR.B       #0x4,D0                         | hi nibble
    MOVE.B      PATEXPAND_DONE_CONT_2(PC,D0.W),(A1)+ | hi-nibble thinned
    MOVEQ.L     #0xF,D0                         | mask lo nibble
    AND.B       (A7)+,D0                        | recover lo nibble
    MOVE.B      PATEXPAND_DONE_CONT_2(PC,D0.W),(A1)+ | lo-nibble thinned
    MOVE.W      -0x2(A1),(A1)+                  | replicate to long
    CLR.L       (A1)+                           | blank scan
    DBF.W       D1,THINLP                       | next byte
PATEXPAND_DONE:
    MOVEA.L     (A7)+,A4                        | restore A4
    UNLK        A6                              | release frame
    RTS                                         | return from PatExpand
| ----------------------------------------------------------
| DoubleNibbleTbl / PATEXPAND_DONE_CONT_2: 16-entry x 1-byte
| nibble-doubling and nibble-thinning tables for PatExpand's
| bold/halftone variants. Indexed by D0 = nibble value 0..15.
|   DoubleNibbleTbl (DOUBLE_NIBBLE):
|     each output bit i is set if input bit (i/2) is set
|     (e.g. 0x5 = 0b0101 -> 0x33 = 0b00110011) -> bold thicken
|   PATEXPAND_DONE_CONT_2 (THIN_NIBBLE):
|     each output bit (i*2) copies input bit i, output odd
|     bits cleared (e.g. 0x5 = 0b0101 -> 0x11 = 0b00010001)
|     -> halftone thinning
DoubleNibbleTbl:
    .short      0x0003
    .long       0x0C0F3033
    .long       0x3C3FC0C3
    .long       0xCCCFF0F3
    .short      0xFCFF
PATEXPAND_DONE_CONT_2:
    .short      0x0001
    .long       0x04051011
    .long       0x14154041
    .long       0x44455051
    .short      0x5455
| ----------------------------------------------------------
| ColorMap(mode: INTEGER, pat: Pattern) - adjust mode/pat for color
| separation. Modifies caller's mode (0x1C(SP)) and pat (0x18(SP))
| in place. Preserves all registers.
| Used to map drawing modes onto a single color plane (colorBit).
COLORMAP:
    MOVEM.L     D0-D3/A0,-(A7)                  | save regs
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    MOVEA.L     (A0),A0                         | A0 -> current GrafPort
    MOVE.L      A0,D0                           | thePort nil?
    BEQ.B       COLOROK                         | yes -> leave color alone
    BTST        #0x0,D0                         | thePort odd?
    BNE.B       COLOROK                         | yes -> leave color alone
    MOVE.W      0x58(A0),D2                     | D2 = colrBit (color bit select)
    BMI.B       COLOROK                         | colrBit = -1 -> no color
    MOVE.W      0x1C(A7),D3                     | D3 = input mode
    MOVEQ.L     #0x3,D0                         | mask bottom 2 bits
    AND.W       D3,D0                           | D0 = mode & 3
    BEQ.B       COLORMAP_COPY                   | 0 -> COPY modes
    CMPI.W      #0x2,D0                         | 2 -> XOR modes (both fg/bg invariant)
    BEQ.B       COLOROK                         | leave alone
    BGT.B       BICMODE                         | 3 -> BIC (depends only on bg)
    MOVE.L      0x50(A0),D1                     | else 1 (OR): D1 = fgColor
COLORMAP_SHARE:
    BTST        D2,D1                           | test color bit in fg/bg
    BNE.B       COLOROK                         | bit set -> no change
    EORI.W      #0x2,D3                         | invert mode bit 2 (OR<->BIC)
    BRA.B       NEWMODE                         | -> store new mode
| BIC modes depend only on background color
BICMODE:
    MOVE.L      0x54(A0),D1                     | D1 = bkColor
    NOT.L       D1                              | invert (BIC = AND NOT)
    BRA.B       COLORMAP_SHARE                  | shared bit-test path
| COPY modes depend on both foreground and background
COLORMAP_COPY:
    MOVE.L      0x50(A0),D0                     | D0 = fgColor
    MOVE.L      0x54(A0),D1                     | D1 = bkColor
    BTST        D2,D0                           | fgColor bit set?
    BEQ.B       FORE0                           | no -> FORE0 path
    BTST        D2,D1                           | bkColor bit set?
    BEQ.B       COLOROK                         | no -> no change
    MOVEQ.L     #0x8,D3                         | yes -> mode = patCopy
USEPAT:
    MOVEA.L     (A5),A0                         | A0 -> QD globals
    LEA.L       -0x10(A0),A0                    | A0 -> BLACK pattern (qd globals - 16)
    MOVE.L      A0,0x18(A7)                     | replace caller's pat with BLACK
    BRA.B       NEWMODE                         | -> store new mode
| Foreground bit clear: depends on background
FORE0:
    BTST        D2,D1                           | bkColor bit set?
    BNE.B       INVMODE                         | yes -> invert mode
    MOVEQ.L     #0xC,D3                         | no -> mode = notPatCopy
    BRA.B       USEPAT                          | use BLACK pattern
| Invert: flip bit 2 of mode (notSrcXor etc.)
INVMODE:
    EORI.W      #0x4,D3                         | mode ^= 4
NEWMODE:
    MOVE.W      D3,0x1C(A7)                     | replace caller's mode with adjusted value
| Called by: COLORMAP, COLORMAP_SHARE, COLORMAP_COPY
COLOROK:
    MOVEM.L     (A7)+,D0-D3/A0                  | restore regs
    RTS                                         | return from ColorMap
| ----------------------------------------------------------
| GetPixel(h, v: INTEGER) -> Boolean - test pixel state at (h,v)
| in current GrafPort's local coords.
| Returns TRUE if pixel set (black on default GrafPort).
| Hides cursor before reading and restores via ShowCursor.
GETPIXEL:
    JSR         HIDECURSOR(PC)                  | hide cursor first
    MOVE.L      (A7)+,D2                        | save return addr
    MOVEA.L     (A5),A1                         | A1 -> QD globals
    MOVEA.L     (A1),A1                         | A1 -> current GrafPort
    MOVE.W      (A7)+,D0                        | D0 = v (caller param)
    SUB.W       0x8(A1),D0                      | v -= portRect.top -> global v
    MOVE.W      (A7)+,D1                        | D1 = h
    SUB.W       0xA(A1),D1                      | h -= portRect.left -> global h
    MULU.W      0x6(A1),D0                      | D0 = global_v * rowBytes
    MOVEA.L     0x2(A1),A1                      | A1 = baseAddr
    ADDA.L      D0,A1                           | A1 -> row of pixel
    MOVE.W      D1,D0                           | D0 = h
    NOT.W       D0                              | invert for BTST bit numbering
    LSR.W       #0x3,D1                         | D1 = h / 8 = byte offset
    BTST        D0,0x0(A1,D1.W)                 | test pixel bit
    SNE.B       (A7)                            | (A7) = 0 or 0xFF
    NEG.B       (A7)                            | normalize to 0 or 1
    MOVE.L      D2,-(A7)                        | restore return addr
    JMP         SHOWCURSOR(PC)                  | show cursor (tail-call)
| ----------------------------------------------------------
| StuffHex($A866) - copy hex string into memory location
| Pascal: procedure StuffHex(thingPtr: Ptr; s: Str255);
| Each pair of hex digits in s is decoded to a byte; written to
| consecutive bytes starting at thingPtr. NO range checking.
STUFFHEX:
    MOVEA.L     0x4(A7),A0                      | A0 = string ptr (length-prefixed)
    MOVEA.L     0x8(A7),A1                      | A1 = thingPtr (destination)
    MOVE.L      (A7),0x8(A7)                    | shift return addr down
    ADDQ.W      #0x8,A7                         | drop 8 bytes of args
    MOVE.B      (A0)+,D2                        | D2 = string length
    ANDI.W      #0xFE,D2                        | round to even (each byte = 2 hex chars)
    BEQ.B       ENDHEX                          | empty -> done
HEXLOOP:
    BSR.B       NEXTHEX                         | D0 = hi nibble (binary)
    MOVE.B      D0,D1                           | save
    BSR.B       NEXTHEX                         | D0 = lo nibble
    LSL.B       #0x4,D1                         | hi nibble << 4
    ADD.B       D0,D1                           | combine
    MOVE.B      D1,(A1)+                        | store byte
    SUBQ.W      #0x2,D2                         | 2 chars consumed
    BNE.B       HEXLOOP                         | more digits -> continue
ENDHEX:
    RTS                                         | return from StuffHex
| ----------------------------------------------------------
| NEXTHEX - read one hex digit from (A0)+ and convert to binary
| Returns: D0.B = 0..15 (no validation)
NEXTHEX:
    MOVE.B      (A0)+,D0                        | get digit
    CMPI.B      #0x39,D0                        | > '9'?
    BLE.B       SMALL                           | no -> already 0..9
    ADDI.B      #0x9,D0                         | yes ('A'..'F') -> add 9 to align
SMALL:
    ANDI.B      #0xF,D0                         | mask to nibble
    RTS                                         | return from SMALL
| ----------------------------------------------------------
| XorSlab - XOR a horizontal slab of pixels into A0's row
| Inputs: A0 = bufAddr, D3 = left pixel, D4 = right pixel.
| Computes left/right word-boundary masks via MASKTAB then XORs the
| combined mask into the buffer row at the right word offsets.
XORSLAB:
    MOVE.L      A0,D1                           | save bufAddr for later
    LEA.L       MASKTAB(PC),A0                  | A0 -> MASKTAB
    MOVEQ.L     #0xF,D0                         | 4-bit mask
    MOVE.W      D3,D5                           | D5 = left
    AND.W       D0,D5                           | left mod 16
    ADD.W       D5,D5                           | * 2 for table
    MOVE.W      0x0(A0,D5.W),D5                 | D5 = leftMask
    NOT.W       D5                              | invert (leftMask -> bits to keep)
    MOVE.W      D4,D6                           | D6 = right
    AND.W       D0,D6                           | right mod 16
    ADD.W       D6,D6                           | * 2 for table
    MOVE.W      0x0(A0,D6.W),D6                 | D6 = rightMask
    MOVEA.L     D1,A0                           | restore bufAddr
    ASR.W       #0x4,D3                         | left / 16 = leftWord
    ADDA.W      D3,A0                           | A0 += leftWord
    ADDA.W      D3,A0                           | * 2 for byte offset
    ASR.W       #0x4,D4                         | right / 16
    SUB.W       D3,D4                           | wordCount = rightWord - leftWord
    BGT.B       XORSLAB_NOTIN1                  | not all in one word
    AND.W       D5,D6                           | combine left+right masks
    EOR.W       D6,(A0)                         | XOR mask into buffer
    RTS                                         | return from XORSLAB
| Multi-word: do left, middle (if any), then right
XORSLAB_NOTIN1:
    EOR.W       D5,(A0)+                        | XOR leftMask
    BRA.B       XORSLAB_INVLONG_CONT            | -> count check
XORSLAB_INVLONG:
    NOT.L       (A0)+                           | invert two whole words
XORSLAB_INVLONG_CONT:
    SUBQ.W      #0x2,D4                         | full long words remaining?
    BGT.B       XORSLAB_INVLONG                 | yes (>= 2) -> next pair
    BLT.B       XORSLAB_ENDWORD                 | no, just a tail word
    NOT.W       (A0)+                           | exactly one full word
XORSLAB_ENDWORD:
    EOR.W       D6,(A0)                         | XOR rightMask
    RTS                                         | return from XORSLAB_ENDWORD
| ----------------------------------------------------------
| DrawSlab - draw a horizontal slab via mode-specific scan routine
| Inputs:
|   D1 = left, D2 = right, D6 = pattern
|   A0 = MaskTab base (used relative; +0x20 = right masks)
|   A1 = dstPtr (row start), A2 = maskPtr (row mask)
|   A3 = minRect (clip), A4 = mode-specific scan handler
| Clips left/right to minRect, builds left/right masks, computes
| word count + dst/mask offsets, falls through to JMP (A4).
DRAWSLAB:
    CMP.W       0x2(A3),D1                      | left < minRect.left?
    BGE.B       DRAWSLAB_LEFTOK                 | no -> ok
    MOVE.W      0x2(A3),D1                      | yes -> clip to minRect.left
DRAWSLAB_LEFTOK:
    CMP.W       0x6(A3),D2                      | right > minRect.right?
    BLE.B       DRAWSLAB_RIGHTOK                | no -> ok
    MOVE.W      0x6(A3),D2                      | yes -> clip to minRect.right
DRAWSLAB_RIGHTOK:
    CMP.W       D2,D1                           | left >= right (empty)?
    BGE.B       DONESLAB                        | yes -> nothing to draw
    MOVEQ.L     #0xF,D3                         | mask for low 4 bits
    MOVE.W      D1,D0                           | D0 = left (will become leftWord)
    AND.W       D3,D1                           | left mod 16
    ADD.W       D1,D1                           | * 2 for word stride
    MOVE.W      0x20(A0,D1.W),D1                | D1 = leftMask (right-half table)
    AND.W       D2,D3                           | right mod 16
    ADD.W       D3,D3                           | * 2
    MOVE.W      0x0(A0,D3.W),D3                 | D3 = rightMask
    ASR.W       #0x4,D2                         | right / 16 = rightWord
    ASR.W       #0x4,D0                         | left / 16 = leftWord
    SUB.W       D0,D2                           | D2 = wordCount = rightWord - leftWord
    ADD.W       D0,D0                           | * 2 for byte offset
    ADDA.W      D0,A1                           | A1 += leftWord*2 = dst offset
    ADDA.W      D0,A2                           | A2 += leftWord*2 = mask offset
    TST.W       D2                              | set Z if all in one word
    JMP         (A4)                            | dispatch to mode handler
| ----------------------------------------------------------
| DONESLAB - exit DrawSlab when nothing to draw
DONESLAB:
    RTS                                         | return from DONESLAB
| ---------------------------------------------------------
| Per-mode scan-line routines for DrawSlab.
| Entry: A1=dstPtr, A2=maskPtr, D1=leftMask, D2=wordCnt,
|        D3=rightMask, D6=pattern. Z-flag set if all in one word.
| Clobbers D0,D1,D2,A1,A2.
| ---------------------------------------------------------
| MODE 8 or 12: pattern -> dst (PATCOPY / NOTPATCOPY)
DRAWSLAB_END8:
    AND.W       D3,D1                           | combine right + left masks
NEXT8:
    MOVE.W      D6,D0                           | D0 = pattern data
    AND.W       (A2)+,D1                        | merge mask + clipRgn mask
    AND.W       D1,D0                           | mask pattern bits
    NOT.W       D1                              | notMask = ~mask
    AND.W       (A1),D1                         | preserve old dst bits
    OR.W        D0,D1                           | combine with patterned bits
    MOVE.W      D1,(A1)+                        | write to dst
    MOVEQ.L     #-0x1,D1                        | flush mask -> all 1s
    SUBQ.W      #0x1,D2                         | dec word count
NEXT8_CONT:
    BGT.B       NEXT8                           | loop full words
    BEQ.B       DRAWSLAB_END8                   | last word with right mask
    RTS                                         | return from NEXT8_CONT
| MODE 9 or 13: pattern OR dst -> dst (PATOR / NOTPATOR)
END9:
    AND.W       D3,D1                           | combine masks
NEXT9:
    AND.W       D6,D1                           | mask pattern bits
    AND.W       (A2)+,D1                        | merge with clipRgn mask
    OR.W        D1,(A1)+                        | OR into dst
    MOVEQ.L     #-0x1,D1                        | flush mask
    SUBQ.W      #0x1,D2                         | dec word count
NEXT9_CONT:
    BGT.B       NEXT9                           | loop
    BEQ.B       END9                            | last word
    RTS                                         | return from NEXT9_CONT
| MODE 10 or 14: pattern XOR dst -> dst (PATXOR / NOTPATXOR)
END10:
    AND.W       D3,D1                           | combine masks
NEXT10:
    AND.W       D6,D1                           | mask pattern
    AND.W       (A2)+,D1                        | + clip mask
    EOR.W       D1,(A1)+                        | XOR into dst
    MOVEQ.L     #-0x1,D1                        | flush mask
    SUBQ.W      #0x1,D2                         | dec
NEXT10_CONT:
    BGT.B       NEXT10                          | loop
    BEQ.B       END10                           | last word
    RTS                                         | return from NEXT10_CONT
| MODE 11 or 15: pattern BIC dst -> dst (PATBIC / NOTPATBIC)
END11:
    AND.W       D3,D1                           | combine masks
NEXT11:
    AND.W       D6,D1                           | mask pattern
    AND.W       (A2)+,D1                        | + clip mask
    NOT.W       D1                              | invert (BIC = AND NOT)
    AND.W       D1,(A1)+                        | clear bits in dst
    MOVEQ.L     #-0x1,D1                        | flush mask
    SUBQ.W      #0x1,D2                         | dec
NEXT11_CONT:
    BGT.B       NEXT11                          | loop
    BEQ.B       END11                           | last word
    RTS                                         | return from NEXT11_CONT
| ----------------------------------------------------------
| SlabMode(D2 = mode) -> A4 = mode-specific scan handler
| Maps low 2 bits of mode to a JMP address from MODETAB.
SLABMODE:
    ANDI.W      #0x3,D2                         | mode & 3
    LEA.L       SLABMODE_MODE_TBL(PC),A4        | A4 -> SLABMODE_MODE_TBL
    MOVE.B      0x0(A4,D2.W),D2                 | D2 = byte offset to scan handler
    SUBA.W      D2,A4                           | A4 = scan handler addr (subtract: handlers are below table)
    RTS                                         | return from SLABMODE
| ----------------------------------------------------------
|
| SLABMODE_MODE_TBL
|
SLABMODE_MODE_TBL:
    .long       0x4E3C2A16
| .BYTE MODETAB-MASK9
| .BYTE MODETAB-MASK10
| .BYTE MODETAB-MASK11

| ---------------------------------------------------------------
|
| FAST LOOPS, OPTIMIZED FOR BLACK PATTERN AND RECTANGLE CLIPPED
|
| FAST BLACK SLAB:
|
| Called during boot.
SLABMODE_CONT:
    BEQ.B       MERGE8                          | BR IF ALL IN ONE WORD
    OR.W        D1,(A1)+                        | OR LEFTMASK INTO DST
    SUBQ.W      #0x2,D2                         | ADJUST WORDCOUNT FOR DBF
    BLT.B       LAST8                           | BR IF NO UNMASKED WORDS
    MOVEQ.L     #-0x1,D1                        | GET SOME BLACK
LOOP8:
    MOVE.W      D1,(A1)+                        | WRITE A WORD OF BLACK
    DBF.W       D2,LOOP8                        | LOOP ALL UNMASKED WORDS
MERGE8:
    AND.W       D1,D3                           | COMBINE LEFTMASK AND RIGHTMASK
LAST8:
    OR.W        D3,(A1)+                        | OR RIGHTMASK INTO DST
    RTS                                         | AND RETURN
| ----------------------------------------------------------
|
| LAST8_CONT
|
| FAST XOR SLAB.
|
| Called during boot.
LAST8_CONT:
    BEQ.B       MERGE10                         | BR IF ALL IN ONE WORD
    EOR.W       D1,(A1)+                        | XOR LEFTMASK INTO DST
    SUBQ.W      #0x2,D2                         | ADJUST WORDCOUNT FOR DBF
    BLT.B       LAST10                          | BR IF NO UNMASKED WORDS
LOOP10:
    NOT.W       (A1)+                           | INVERT A WORD OF DST
    DBF.W       D2,LOOP10                       | LOOP ALL UNMASKED WORDS
    BRA.B       LAST10                          | THEN FINISH UP LAST WITH MASK
| ----------------------------------------------------------
|
| MERGE10
|
MERGE10:
    AND.W       D1,D3                           | COMBINE LEFTMASK AND RIGHTMASK
LAST10:
    EOR.W       D3,(A1)+                        | XOR RIGHTMASK INTO DST
    RTS                                         | AND RETURN
| ----------------------------------------------------------
|
| LAST10_CONT
|
| FAST WHITE SLAB.
|
| Called during boot.
LAST10_CONT:
    BEQ.B       MERGE11                         | BR IF ALL IN ONE WORD
    NOT.W       D1                              | FORM NOT LEFTMASK
    AND.W       D1,(A1)+                        | AND NOT LEFTMASK INTO DST
    SUBQ.W      #0x2,D2                         | ADJUST WORDCOUNT FOR DBF
    BLT.B       LAST11                          | BR IF NO UNMASKED WORDS
LOOP11:
    CLR.W       (A1)+                           | CLEAR A WORD OF DST
    DBF.W       D2,LOOP11                       | LOOP ALL UNMASKED WORDS
    BRA.B       LAST11                          | THEN FINISH UP LAST WITH MASK
| ----------------------------------------------------------
|
| MERGE11
|
MERGE11:
    AND.W       D1,D3                           | COMBINE LEFTMASK AND RIGHTMASK
LAST11:
    NOT.W       D3                              | FORM NOT RIGHTMASK
    AND.W       D3,(A1)+                        | AND NOT RIGHTMASK INTO DST
    RTS                                         | AND RETURN
| --------------------------------------------------------------------
|
| PROCEDURE FastSlabMode, Call when rect clipped and pattern black.
|
| INPUT:  D2 = MODE (clobbered): 0=black, 1=xor, 2=white
| OUTPUT: A4 = MODECASE
|
FASTSLABMODE:
    ANDI.W      #0x3,D2                         | GET LO 2 BITS OF MODE
    LEA.L       FASTSLABMODE_MODE_TBL(PC),A4    | POINT TO MODE TABLE
    MOVE.B      0x0(A4,D2.W),D2                 | GET OFFSET FROM FASTTAB
    SUBA.W      D2,A4                           | GET CASE JUMP ADDRESS
    RTS                                         | return from FastSlabMode
| ----------------------------------------------------------
|
| FASTSLABMODE_MODE_TBL: byte offsets back from table to per-mode handler.
| 0x56 -> SLABMODE_CONT (mode 0, black)
| 0x40 -> LAST8_CONT    (mode 1, xor)
| 0x2A -> LAST10_CONT   (mode 2, white)
| 0x00 -> table base    (mode 3, undefined; would loop)
|
FASTSLABMODE_MODE_TBL:
    .short      0x5640                          | FAST SLAB MODE OFFSETS: 0,1
    .short      0x2A00                          | FAST SLAB MODE OFFSETS: 2,3
