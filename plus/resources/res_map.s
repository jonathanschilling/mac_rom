| Resource Map (type list, reference list, name list)
| ROM Resource Fork
|
| Contains the ROM's built-in resources at offset $176F8:
| DRVR 2 '.Print' - Print Driver
| DRVR 3 '.Sound' - Sound Driver
| DRVR 4 '.Sony' - Disk Driver (Sony 3.5" floppy)
| DRVR 9 '.MPP' - AppleTalk MPP driver
| DRVR 10 '.ATP' - AppleTalk ATP driver
| SERD 0 - Serial Driver
| MDEF 0 - Standard Menu Definition
| WDEF 0 - Standard Window Definition
| PACK 4,5,7 - SANE floating-point packages
| CURS 1-4 - Standard cursors (iBeam, cross, plus, watch)
| FONT 0 'Chicago' - System font (12pt)
| FONT 12 - Additional font
|
| References:
| Inside Macintosh Vol I, Ch 5: Resource Manager - Resource File Format

| ROM resource fork (DRVR, FONT, CURS, etc.)
| ROM section: src/resources/resources.asm

| Resources in ROM
  .short 0x0011                                 | ?
  .short 0x0148                                 | resource map size

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

| resource header
  .long 0xC0000174                              | Length
  .long 0x00000054                              | ?

