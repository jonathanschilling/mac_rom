# Cross toolchain. Auto-detected: Debian/Ubuntu ship m68k-linux-gnu-*,
# Arch Linux and Homebrew ship m68k-elf-*. Override on the command line,
# e.g. `make CROSS=m68k-elf-` (or set AS/OBJCOPY individually).
CROSS   ?= $(or $(firstword $(foreach p,m68k-linux-gnu- m68k-elf-,$(if $(shell command -v $(p)as 2>/dev/null),$(p)))),m68k-linux-gnu-)
AS       = $(CROSS)as
OBJCOPY  = $(CROSS)objcopy
NM       = $(CROSS)nm

ASFLAGS = -m68000 --register-prefix-optional -Iinclude

# Reference ROM images (optional). They are not needed for building: when
# present, every build is additionally compared byte-for-byte against
# them; when absent, that step is skipped (see ROM_INFO_* below).
ROM_REF_DIR ?= ../macroms/Mac_ROMs/68k

ROM_REF_mac_128k     = $(ROM_REF_DIR)/64k/Macintosh 128K/1984-01 - 28BA61CE - Macintosh 128K.ROM
ROM_REF_mac_512k     = $(ROM_REF_DIR)/64k/Macintosh 512K/1984-10 - 28BA4E50 - Macintosh 512K.ROM
ROM_REF_mac_plus_v1  = $(ROM_REF_DIR)/128k/Macintosh Plus/1986-01 - 4D1EEEE1 - MacPlus v1.ROM
ROM_REF_mac_plus_v2  = $(ROM_REF_DIR)/128k/Macintosh Plus/1986-03 - 4D1EEAE1 - MacPlus v2.ROM
ROM_REF_mac_plus_v3  = $(ROM_REF_DIR)/128k/Macintosh Plus/1986-03 - 4D1F8172 - MacPlus v3.ROM
ROM_REF_mac_se       = $(ROM_REF_DIR)/256k/1987-03 - B2E362A8 - Mac SE.ROM
ROM_REF_mac_se_fdhd  = $(ROM_REF_DIR)/256k/1989-08 - B306E171 - Mac SE FDHD.ROM

# Hardcoded fingerprints of the original ROM images:
#   <size in bytes> <checksum stored at offset 0> <version word at offset 8> <MD5>
# Every build is checked against these by tools/verify_rom.sh (the stored
# checksum, the checksum recomputed over the image, the version word, the
# size and the MD5 must all match), so `make` verifies bit-identity even
# when the reference ROM images above are not available.
ROM_INFO_mac_128k    = 65536  28BA61CE 0069 1d7f52d2d490524954f6afce083d9593
ROM_INFO_mac_512k    = 65536  28BA4E50 0069 db7e6d3205a2b48023fba5aa867ac6d6
ROM_INFO_mac_plus_v1 = 131072 4D1EEEE1 0075 4d8d1e81fa606f57c7ed7188b8b5f410
ROM_INFO_mac_plus_v2 = 131072 4D1EEAE1 0075 16b516e13918a439cf9031ec24353610
ROM_INFO_mac_plus_v3 = 131072 4D1F8172 0075 8a41e0754ffd1bb00d8183875c55164c
ROM_INFO_mac_se      = 262144 B2E362A8 0276 9fb38bdcc0d53d9d380897ee53dc1322
ROM_INFO_mac_se_fdhd = 262144 B306E171 0276 886444d7abc1185112391b8656c7e448

# ROM_TARGET enumeration (must match include/rom_target.inc)
ROM_NUM_mac_128k     = 1
ROM_NUM_mac_512k     = 2
ROM_NUM_mac_plus_v1  = 3
ROM_NUM_mac_plus_v2  = 4
ROM_NUM_mac_plus_v3  = 5
ROM_NUM_mac_se       = 6
ROM_NUM_mac_se_fdhd  = 7

ENTRY_mac_128k     = rom_original.s
ENTRY_mac_512k     = rom_original.s
ENTRY_mac_plus_v1  = rom_plus.s
ENTRY_mac_plus_v2  = rom_plus.s
ENTRY_mac_plus_v3  = rom_plus.s
ENTRY_mac_se       = rom_se.s
ENTRY_mac_se_fdhd  = rom_se.s

PLUS_TARGETS     = mac_plus_v1 mac_plus_v2 mac_plus_v3
ORIGINAL_TARGETS = mac_128k mac_512k
SE_TARGETS       = mac_se mac_se_fdhd
ALL_TARGETS      = $(ORIGINAL_TARGETS) $(PLUS_TARGETS) $(SE_TARGETS)

# ROM map parameters (tools/rom_map.sh):
#   <size> <last offset> <seg> <entry id> <size name> <layout>
ROMMAP_mac_128k     = 00010000 FFFF  69 69 ROM64K  plus
ROMMAP_mac_512k     = 00010000 FFFF  69 69 ROM64K  plus
ROMMAP_mac_plus_v1  = 00020000 1FFFF 75 75 ROMPlus plus
ROMMAP_mac_plus_v2  = 00020000 1FFFF 75 75 ROMPlus plus
ROMMAP_mac_plus_v3  = 00020000 1FFFF 75 75 ROMPlus plus
ROMMAP_mac_se       = 00040000 3FFFF 76 75 Main    se
ROMMAP_mac_se_fdhd  = 00040000 3FFFF 76 75 Main    se

.PHONY: all verify $(ALL_TARGETS) rommap clean
.PRECIOUS: build/rom-%.o

all: verify

# Per-target build + verify: hardcoded fingerprints always, byte-for-byte
# cmp against the reference image when it is available.
$(ALL_TARGETS): %: build/rom-%.bin
	@sh tools/verify_rom.sh $* $< $(ROM_INFO_$*) "$(ROM_REF_$*)"

# Aggregate verifier. The recipe only runs when every per-target
# verification above has passed.
verify: $(ALL_TARGETS)
	@ref=0; \
	$(foreach t,$(ALL_TARGETS),[ -f "$(ROM_REF_$(t))" ] && ref=$$((ref+1));) \
	echo "Verified $(words $(ALL_TARGETS)) of $(words $(ALL_TARGETS)) ROMs against hardcoded size/checksum/version/MD5 fingerprints"; \
	echo "Compared $$ref of $(words $(ALL_TARGETS)) ROMs byte-for-byte against reference ROM images"; \
	echo "SUCCESS: ALL SEVEN ROMS BIT-IDENTICAL"

build/rom-%.o:
	@mkdir -p build
	$(AS) $(ASFLAGS) --defsym ROM_TARGET=$(ROM_NUM_$*) -o $@ $(ENTRY_$*)

build/rom-%.bin: build/rom-%.o
	$(OBJCOPY) -O binary $< $@

# ROM maps: build/rom-<target>.lst (layout of Apple's MPW ROM maps such as
# MacPlusROM.lst) and build/rom-<target>.lst.txt ("name 0xOFFSET l" for
# Ghidra). Pre-generated copies are in maps/.
rommap: $(patsubst %,build/rom-%.lst,$(ALL_TARGETS))

build/rom-%.lst: build/rom-%.bin
	sh tools/rom_map.sh $(NM) build/rom-$*.o $(ROMMAP_$*) $@ $@.txt

clean:
	rm -rf build
