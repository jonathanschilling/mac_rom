| =========================================================================
| ROM resource map
| =========================================================================
| ROM offsets +0x176F8..+0x17843: two words for InitResources (the long at
| +0x1A of the ROM header points to them), then the Resource Manager map
| of the ROM resources in the layout of Inside Macintosh I-128 (copy of the
| resource header, next-map handle, file reference, attributes, type list
| offset, name list offset; type list, reference lists, name list).
| InitResources copies the map into a locked handle (ROMMapHandle) with
| file reference 1; the Resource Manager searches it when ROMMapInsert is
| set (Inside Macintosh: More Macintosh Toolbox, "ROM Resources", 1-134).
|
| The 17 resources, in ROM order (the files after this one):
|   DRVR 2 .Print, DRVR 3 .Sound, DRVR 4 .Sony, DRVR 10 .ATP, DRVR 9 .MPP,
|   SERD 0 (the serial drivers), MDEF 0, WDEF 0, PACK 7 (binary-decimal
|   conversion), PACK 5 (SANE elementary functions), PACK 4 (SANE
|   arithmetic), CURS 2, 3, 1, 4, FONT 0 'Chicago' (the family's name
|   entry, no data) and FONT 12 (Chicago 12).
|
| The ROM resource header: the data of every resource is preceded by 8
| bytes in the form of a Memory Manager block header -- tag $C0 with the
| physical size (8 + data size), then the relative handle: the offset of
| the resource's master pointer from the start of the "ROM zone".
| InitResources (INITRESOURCES_CONT_2) creates that zone in the system
| heap: the zone header ($34 bytes) and its first master pointer block (4
| masters), then a nonrelocatable block with one master pointer per ROM
| resource (the count word below), whose data starts at zone + $54; then
| the handle of the map copy. So the relative handles run $54, $58, ... in
| ROM order. LoadROMResource (RESMGR_OK_4) takes zone + relative handle as
| the resource's handle and points its master pointer at the data in ROM.
|
| None of this is written by hand. The resource fork is described in Rez,
| in src/rez/plus/RomResources.r (the resources in ROM order, their names
| and attributes, the map's fields); tools/rez/rezc.py turns it into
| build/rez/plus_rsrc.inc: the map with its counts and offsets, and the
| index and relative handle of each resource. Each resource file wraps its
| data in ROM_RESOURCE / ROM_RESOURCE_END (include/romrsrc.inc), which
| write the 8-byte header and take the size from the data.

    .include "romrsrc.inc"                      | macros of the ROM resource fork
    .include "plus_rsrc.inc"                    | generated from src/rez/plus/RomResources.r
| InitResources: number of ROM resources (one master pointer each) and the
| size of the map that follows
    ROM_RESOURCE_AREA                           | number of resources, map size
| The resource map (Inside Macintosh I-128; the data offsets are
| relative to ROM offset 0)
    ROM_RESOURCE_MAP                            | the map (generated from RomResources.r)

