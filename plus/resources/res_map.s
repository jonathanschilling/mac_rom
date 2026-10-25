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

| InitResources: number of ROM resources (one master pointer each) and the
| size of the map that follows
  .short 0x0011                                 | 17 ROM resources
  .short 0x0148                                 | resource map size: $148 bytes

| Resource map
  .long 0x00000100                              | reserved for Offset to resource data
  .long 0x00008838                              | reserved for Offset to resource map
  .long 0x00008738                              | reserved for Length of resource data
  .long 0x00000148                              | reserved for Length of resource map
  .long 0x0000CC1C                              | reserved for handle to next resource map
  .short 0x0002                                 | reserved for file reference number
  .short 0x8000                                 | Resource file attributes
  .short 0x001C                                 | Offset to type list
  .short 0x0122                                 | Offset to resource name list

| Type list
  .short 0x0006                                 | Number of resource types - 1
  .long 0x44525652                              | Resource type DRVR
  .short 0x0004                                 | Number of resources of this type - 1
  .short 0x003A                                 | Offset to reference list
  .long 0x53455244                              | Resource type SERD
  .short 0x0000                                 | Number of resources of this type - 1
  .short 0x0076                                 | Offset to reference list
  .long 0x4D444546                              | Resource type MDEF
  .short 0x0000                                 | Number of resources of this type - 1
  .short 0x0082                                 | Offset to reference list
  .long 0x57444546                              | Resource type WDEF
  .short 0x0000                                 | Number of resources of this type - 1
  .short 0x008E                                 | Offset to reference list
  .long 0x5041434B                              | Resource type PACK
  .short 0x0002                                 | Number of resources of this type - 1
  .short 0x009A                                 | Offset to reference list
  .long 0x43555253                              | Resource type CURS
  .short 0x0003                                 | Number of resources of this type - 1
  .short 0x00BE                                 | Offset to reference list
  .long 0x464F4E54                              | Resource type FONT
  .short 0x0001                                 | Number of resources of this type - 1
  .short 0x00EE                                 | Offset to reference list

| end of Type list
| Reference list
| Resource type 'DRVR'
  .short 0x0002                                 | Resource ID
  .short 0x0017                                 | Offset to name
  .long 0x5801784C                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x0003                                 | Resource ID
  .short 0x0010                                 | Offset to name
  .long 0x580179C0                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x0004                                 | Resource ID
  .short 0x000A                                 | Offset to name
  .long 0x58017D30                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x000A                                 | Resource ID
  .short 0x0005                                 | Offset to name
  .long 0x58019DA0                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x0009                                 | Resource ID
  .short 0x0000                                 | Offset to name
  .long 0x5801A6FA                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle

| end of Resource type 'DRVR'
| Resource type 'SERD'
  .short 0x0000                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801B6D0                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle

| end of Resource type 'SERD'
| Resource type 'MDEF'
  .short 0x0000                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801BF40                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle

| end of Resource type 'MDEF'
| Resource type 'WDEF'
  .short 0x0000                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801C346                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle

| end of Resource type 'WDEF'
| Resource type 'PACK'
  .short 0x0007                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801C9E0                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x0005                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801CF2E                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x0004                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801DF94                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle

| end of Resource type 'PACK'
| Resource type 'CURS'
  .short 0x0002                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801F154                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x0003                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801F1A0                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x0001                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801F1EC                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x0004                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801F238                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle

| end of Resource type 'CURS'
| Resource type 'FONT'
  .short 0x0000                                 | Resource ID
  .short 0x001E                                 | Offset to name
  .long 0x5801F284                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle
  .short 0x000C                                 | Resource ID
  .short 0xFFFF                                 | Offset to name
  .long 0x5801F28C                              | Attributes + Offset to data block
  .long 0x00000000                              | reserved for handle

| end of Resource type 'FONT'
| end of Reference list
| Resource name list
| Name of resource type ''DRVR'' 9
  .byte 0x04                                    | length

| Name
  .ascii ".MPP"                                 | DRVR 9: AppleTalk MPP driver

| end of Name
| Name of resource type ''DRVR'' 10
  .byte 0x04                                    | length
  .ascii ".ATP"                                 | DRVR 10: AppleTalk ATP driver

| Name of resource type ''DRVR'' 4
  .byte 0x05                                    | length
  .ascii ".Sony"                                | DRVR 4: floppy disk driver

| Name of resource type ''DRVR'' 3
  .byte 0x06                                    | length
  .ascii ".Sound"                               | DRVR 3: sound driver

| Name of resource type ''DRVR'' 2
  .byte 0x06                                    | length
  .ascii ".Print"                               | DRVR 2: printer driver shell

| Name of resource type ''FONT'' 0
  .byte 0x07                                    | length
  .ascii "Chicago"                              | FONT 0: system font

| end of Resource name list
| end of Resource map

| Resources data

