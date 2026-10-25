| -------------------------------------------------------------------------
| ROM header ($00-$3F): checksum, reset vectors, ROM version, entry points
|
| Apple source: StartInit.a (System 7.1: OS/StartMgr/StartInit.a, "START
| OF ROM"); BASEOFROM is defined in StartTop.a (MacSEROM.lst lists
| BASEOFROM, MYFIRSTPROC and MYROM at $0). The labels STARTPC ...
| RESETENTRY and STARTBOOT are the names of that source. Its 1992 header
| has fields that are still zero in the SE: the ROM release word at $12,
| the foreign-OS table offset at $16, the RomLoc byte at $2E (added in
| March 1989) and the ROM size from $40 on.
|
| Software outside the ROM finds the ROM's entry points and tables
| through this header, at fixed offsets from ROMBase: the entry points
| are JMP instructions, the two pointers are offsets from the start of
| the ROM. In the ROM itself, INITDISPATCHER (boot/boot_install.s) reads
| DISPOFF, InitResources (toolbox/resource_mgr.s) reads ROMRSRC, and the
| .ATP and .MPP drivers test the ROM version byte at +$09.
|
| Mac Plus tree: boot/vectors.s. The 1986 header has the checksum, the
| reset vector, the version word, the resource offset and the eject and
| reset entries at the same offsets; it branches into the boot code at
| $0A-$16 and is zero at $22/$26.
| -------------------------------------------------------------------------

BASEOFROM:
| Start of the ROM image. The ROM runs at $400000 (ROMBase). At reset the
| SE also maps it to address 0 (the overlay), so that the 68000 can fetch
| its two reset vectors from $0 and $4.
|
| +$00: the ROM checksum, the sum of all 16-bit words from offset 4 on
| (P_ChecksumRom in boot/memtest.s checks it at startup). The 68000 also
| loads it as the initial supervisor stack pointer; the start code sets
| up SP before it uses the stack.
| --- ROM-variant difference @ $0000 ---
| SE:      $B2E362A8
| SE FDHD: $B306E171
| Reason: 32-bit ROM checksum (sum of all words from offset 4)
.if ROM_TARGET == MAC_SE
    .long       0xB2E362A8                      | +$00: ROM checksum (Mac SE, 1987)
.else
    .long       0xB306E171                      | +$00: ROM checksum (Mac SE FDHD, 1989)
.endif
| +$04: the initial PC. It lies in the ROM's own address range: the first
| access to $400000-$4FFFFF switches the overlay off, so RAM is at address
| 0 from the first instruction on. (The Plus switches the overlay off
| through VIA port A bit 4; the SE uses that bit as the drive select line
| vDriveSel.)
STARTPC:
    .long       RESETENTRY-BASEOFROM+0x400000   | +$04: initial PC = RESETENTRY ($40002A)
| +$08: the ROM version word ($0276). Apple's StartInit.a calls the high
| byte the machine number. Software tests the low byte, the ROM version
| proper ($75 Mac Plus, $76 SE): the .ATP and .MPP drivers compare it with
| $76 to find the SE's additions (e.g. the timing constant TimeDBRA).
ROMVERSION:
    .byte       0x02                            | +$08: machine number
    .byte       0x76                            | +$09: ROM version
| +$0A, +$0E: restart entries (Apple: StBoot, "jump to start code for a
| restart", and BadDisk, "eject disk, and reboot"). In the SE both restart
| at STARTBOOT; the Plus branches to its eject-and-try-next-drive code at
| +$0E.
STBOOT:
    JMP         STARTBOOT(PC)                   | +$0A: restart: jump to the start code
BADDISK:
    JMP         STARTBOOT(PC)                   | +$0E: restart after a bad startup disk
    .long       0x00000000                      | +$12: zero (ROM release word in later ROMs)
    .long       0x00000000                      | +$16: zero (foreign-OS table offset, later ROMs)
| +$1A: offset of the ROM resources: the two words in front of the
| resource map (number of ROM resources, map size; at the end of
| os/dispatch_table.s). InitResources adds it to ROMBase.
ROMRSRC:
    .long       ROM_Resource_Area_Header-BASEOFROM | +$1A: offset of the ROM resource header
| +$1E: eject entry (Apple: Eject; the label EJECT is the _Eject trap).
| DOEJECT ejects a disk, first asking the EjectNotify hook.
    JMP         DOEJECT(PC)                     | +$1E: eject a disk (os/file_mgr_vol.s)
| +$22: offset of the compressed trap dispatch table; INITDISPATCHER
| (boot/boot_install.s) adds it to ROMBase.
DISPOFF:
    .long       DISPTABLE-BASEOFROM             | +$22: offset of DISPTABLE (os/dispatch_table.s)
| +$26: critical-error entry: the sad Mac (CRITERR, boot/sad_mac.s).
CRITICAL:
    JMP         CRITERR(PC)                     | +$26: critical error: sad Mac
| +$2A: reset entry; the initial PC at +$04 points here (EBootStart in the
| Plus and 128K trees).
RESETENTRY:
    JMP         STARTBOOT(PC)                   | +$2A: reset: jump to the start code at $40
    .short      0x0000                          | +$2E: zero (RomLoc byte in later ROMs)
| +$30: checksums of the ROM chips. Apple's StartInit.a names the four
| longs at $30-$3C "ROM checksum byte 0" to "byte 3". The SE has two ROM
| chips on its 16-bit data bus and fills the first two: the byte sums of
| all even addresses (high-byte chip) and of all odd addresses (low-byte
| chip), computed with the checksum at $0 and these two longs taken as
| zero.
| --- ROM-variant difference @ $0030 ---
| SE:      $00B22351, $00BF7673
| SE FDHD: $00B247B1, $00BE73A8
| Reason: per-chip byte sums of the different ROM contents
.if ROM_TARGET == MAC_SE
    .long       0x00B22351                      | +$30: byte sum of the high (even) chip
    .long       0x00BF7673                      | +$34: byte sum of the low (odd) chip
.else
    .long       0x00B247B1                      | +$30: byte sum of the high (even) chip
    .long       0x00BE73A8                      | +$34: byte sum of the low (odd) chip
.endif
    .long       0x00000000                      | +$38: ROM checksum byte 2: unused
    .long       0x00000000                      | +$3C: ROM checksum byte 3: unused
| The start code follows at $40 (STARTBOOT, boot/boot_install.s).

