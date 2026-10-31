| romrsrc.inc -- the resource fork of a ROM: the block-header constants and
| the macros used by the resource regions and by the files that
| tools/rez/rezc.py --rom-asm generates from src/rez/<tree>/RomResources.r.
|
| Layout of a ROM resource fork (Mac Plus and SE; the long at +$1A of the ROM
| header points to its first word):
|   ROM_RESOURCE_AREA     number of ROM resources (word), size of the map (word)
|   ROM_RESOURCE_MAP      the resource map, in the format of a resource file's
|                         map (Inside Macintosh I-128), except that the data
|                         offsets are relative to ROM offset 0
|   for each resource, in ROM order:
|     ROM_RESOURCE sym    the 8-byte resource header: a Memory Manager block
|                         header -- tag byte and physical size (8 + the data,
|                         rounded up to even), then the relative handle: the
|                         offset of the resource's master pointer in the "ROM
|                         zone" that InitResources creates in the system heap
|                         (LoadROMResource adds it to the zone address)
|     ...                 the data
|     ROM_RESOURCE_END sym
| Nothing of this is written by hand: rezc.py computes the map and the order
| and relative handles of the resources from RomResources.r, and these macros
| compute the sizes from the data between ROM_RESOURCE and ROM_RESOURCE_END.

| Memory Manager block header (MPW SysEqu.a tagBC; Inside Macintosh II-24):
| bits 31-30 block type, 27-24 size correction (physical size - 8 - logical
| size), 23-0 physical size.
.equ blkTypeShift, 30                           | position of the block type
.equ blkCorrShift, 24                           | position of the size correction
.equ blkSizeMask, 0x00FFFFFF                    | physical size
| block types (tybkFree, tybkNRel, tybkRel of SysEqu.a)
.equ blkFree, 0                                 | free block
.equ blkNRel, 1                                 | nonrelocatable block
.equ blkRel, 2                                  | relocatable block
.equ blkROM, 3                                  | both type bits set: the type of the
                                                | ROM resource headers, which the
                                                | Memory Manager never allocates
| tag of the ROM resource headers: block type 3, size correction 0 ($C0)
.equ romRsrcTag, (blkROM << blkTypeShift)

| ROM_RESOURCE sym -- the header in front of the data of resource `sym`
| (symbol of RomResources.r); checks that the resources come in the order
| of RomResources.r.
.macro ROM_RESOURCE sym
    .if .LROMRSRC_SEQ != .LROMRSRC_\sym\()_INDEX
    .error "ROM resource \sym: not in the place that RomResources.r gives it"
    .endif
    .balign 2, 0                                | the header at an even address
.LROMRSRC_\sym\()_HDR:
    .long   romRsrcTag + .LROMRSRC_\sym\()_PHYS | tag, physical size
    .long   .LROMRSRC_\sym\()_RELH              | relative handle
.LROMRSRC_\sym\()_DATA:
    .set .LROMRSRC_SEQ, .LROMRSRC_SEQ + 1
.endm

| ROM_RESOURCE_END sym -- the end of the data of resource `sym`: pads an odd
| size to even with a zero byte and sets the sizes for the header and map.
.macro ROM_RESOURCE_END sym
.LROMRSRC_\sym\()_LEND:
    .balign 2, 0
    .set .LROMRSRC_\sym\()_PHYS, . - .LROMRSRC_\sym\()_HDR
    .set .LROMRSRC_\sym\()_SIZE, .LROMRSRC_\sym\()_LEND - .LROMRSRC_\sym\()_DATA
.endm

| ROM_RESOURCE_REZ sym -- a resource whose data rezc.py compiled from Rez
| (macro ROMREZ_sym of the generated file).
.macro ROM_RESOURCE_REZ sym
    ROM_RESOURCE \sym
    ROMREZ_\sym
    ROM_RESOURCE_END \sym
.endm

| Resource map structures (Inside Macintosh I-128), used by the generated
| ROM_RESOURCE_MAP.

| RMAP_TYPE "TYPE", count, reflist -- one entry of the type list
.macro RMAP_TYPE type, count, refs
    .ascii  "\type"                             | resource type
    .short  \count - 1                          | number of resources of this type - 1
    .short  \refs - .LRMAP_TYPES                | offset of the reference list
.endm

| RMAP_REF id, nameoffset, attributes, sym -- one entry of a reference list
.macro RMAP_REF id, name, attrs, sym
    .short  \id                                 | resource ID
    .short  \name                               | offset of the name, -1 = none
    .long   (\attrs << 24) + (.LROMRSRC_\sym\()_DATA - .LROMRSRC_BASE) | attributes, data offset
    .long   0                                   | handle (in the RAM copy of the map)
.endm
