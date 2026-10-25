| -------------------------------------------------------------------------
| BASEOFROM (header/data/jump-vector)
| ROM offsets +0x00000..+0x00040.
| Checksum, reset vector, machine/version bytes, resource pointer and header jump slots
| -------------------------------------------------------------------------

BASEOFROM:
| Start of the ROM image.
| --- ROM-variant difference @ $0000 ---
| SE:      $B2E362A8
| SE FDHD: $B306E171
| Reason: 32-bit ROM checksum (sum of all words from offset 4)
.if ROM_TARGET == MAC_SE
    .long	0xB2E362A8                            | ROM checksum (Mac SE, 1987)
.else
    .long	0xB306E171                            | ROM checksum (Mac SE FDHD, 1989)
.endif
    .long	0x0040002A                            | Boot Vector = EBootStart
    .byte 0x02                                                        /* +0x00008 @0x400008 [header/data/jump-vector] FDisasm: 8      02                        DC.B      $02             ; Machine Type */
    .byte 0x76                                                        /* +0x00009 @0x400009 [header/data/jump-vector] FDisasm: 9      76                        DC.B      $76             ; Rom Version */
    .byte 0x4E,0xFA,0x00,0x34                                         /* +0x0000A @0x40000A [header/data/jump-vector] FDisasm: A      4EFA 0034                 Jmp       L0 */ | Jmp       L0
    .byte 0x4E,0xFA,0x00,0x30                                         /* +0x0000E @0x40000E [header/data/jump-vector] FDisasm: E      4EFA 0030                 Jmp       L0 */ | Jmp       L0
    .long	0x00000000                            | 0x00000000
    .long	0x00000000                            | 0x00000000
| Offset to ROM resource area.
ROM_ResourceForkOffset_PlusStyle:
    .long	0x0001AF1C                            | offset of Resources in ROM
    .byte 0x4E,0xFA,0x46,0x44                                         /* +0x0001E @0x40001E [header/data/jump-vector] FDisasm: 1E     4EFA 4644                 Jmp       P_tA0F7_mvDoEject */ | Jmp       P_tA0F7_mvDoEject
DT_mDispOff:
| Offset to compressed trap-dispatch table.
DISPOFF:
    .long	0x0001AA9C                            | offset to compressed A-line table
CRITICAL:
    .byte 0x4E,0xFA,0x10,0x6A                                         /* +0x00026 @0x400026 [header/data/jump-vector] FDisasm: 26     4EFA 106A                 Jmp       P_mCritErr */ | Jmp       P_mCritErr
| === EBootStart: first instruction after 68000 reset ===
| State: all regs = 0 except SP = 0x4D1F8172 (checksum), SR = 0x2700 (supervisor, IPL=7)
| ROM overlay is active: ROM appears at both 0x000000 and 0x400000.
EBootStart:
    .byte 0x4E,0xFA,0x00,0x14                                         /* +0x0002A @0x40002A [header/data/jump-vector] FDisasm: 2A     4EFA 0014                 Jmp       L0 */ | Jmp       L0
    .short	0x0000                               | (unused)
| Checksums of the two 128 KB ROM chips: the byte sums of all even
| addresses (high-byte chip) and of all odd addresses (low-byte chip),
| computed with the checksum at $0 and these two longs taken as zero.
| --- ROM-variant difference @ $0030 ---
| SE:      $00B22351, $00BF7673
| SE FDHD: $00B247B1, $00BE73A8
| Reason: per-chip byte sums of the different ROM contents
.if ROM_TARGET == MAC_SE
    .long	0x00B22351                            | byte sum of the high (even) chip
    .long	0x00BF7673                            | byte sum of the low (odd) chip
.else
    .long	0x00B247B1                            | byte sum of the high (even) chip
    .long	0x00BE73A8                            | byte sum of the low (odd) chip
.endif
    .long	0x00000000                            | '    '
    .long	0x00000000                            | '    '

