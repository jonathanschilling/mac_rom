| ROM resource map
|
| The Resource Manager map of the ROM resources (Inside Macintosh I-128
| layout: copy of the resource header, next-map handle, file reference,
| attributes, type list offset, name list offset; type list, reference
| lists, name list). The Resource Manager searches it when ROMMapInsert is
| set. The two words in front of it (ROM_Resource_Area_Header; the long at
| +0x1A of the ROM header points to them) give the number of ROM resources
| (28) and the size of the map ($1FA).
| Each resource below starts with an 8-byte ROM resource header in front
| of its data, in the form of a Memory Manager block header: tag $C0 with
| the physical size, then the relative handle -- the offset of the
| resource's master pointer from the start of the "ROM zone" that
| InitResources creates in the system heap, with one master pointer per
| ROM resource from zone + $54 on, in ROM order ($54 ... $C0); see the
| banner of src/plus/resources/res_map.s.
|
| None of this is written by hand. The resource fork is described in Rez,
| in src/rez/se/RomResources.r (the resources in ROM order, their names
| and attributes, the map's fields); tools/rez/rezc.py turns it into
| build/rez/se_rsrc.inc: the map with its counts and offsets, and the
| index and relative handle of each resource. Each resource file wraps its
| data in ROM_RESOURCE / ROM_RESOURCE_END (include/romrsrc.inc), which
| write the 8-byte header and take the size from the data. The data of
| 'bbmc' (0) are $14281 bytes long; ROM_RESOURCE_END pads them to even, and
| the map's copy of the resource header counts the odd length, as Apple's
| map does.
| ROM offsets +0x1AF1C..+0x1B11A.

    .include "romrsrc.inc"                      | macros of the ROM resource fork
    .include "se_rsrc.inc"                      | generated from src/rez/se/RomResources.r
| InitResources: number of ROM resources (one master pointer each) and the
| size of the map that follows
ROM_Resource_Area_Header:
    ROM_RESOURCE_AREA                           | number of resources, map size
| The resource map (Inside Macintosh I-128; the data offsets are
| relative to ROM offset 0)
ROM_Resource_Map:
    ROM_RESOURCE_MAP                            | the map (generated from RomResources.r)

