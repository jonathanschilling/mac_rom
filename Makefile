# Toolchain (Debian)
AS      = m68k-linux-gnu-as
OBJCOPY = m68k-linux-gnu-objcopy

# Toolchain (Arch Linux)
#AS      = m68k-elf-as
#OBJCOPY = m68k-elf-objcopy

ASFLAGS = -m68000 --register-prefix-optional -Iinclude

# Reference ROM binaries.
# The bit-identity verifier compares against these.
ROM_REF_DIR ?= ../macroms/Mac_ROMs/68k

ROM_REF_mac_128k    = $(ROM_REF_DIR)/64k/Macintosh\ 128K/1984-01\ -\ 28BA61CE\ -\ Macintosh\ 128K.ROM
ROM_REF_mac_512k    = $(ROM_REF_DIR)/64k/Macintosh\ 512K/1984-10\ -\ 28BA4E50\ -\ Macintosh\ 512K.ROM
ROM_REF_mac_plus_v1 = $(ROM_REF_DIR)/128k/Macintosh\ Plus/1986-01\ -\ 4D1EEEE1\ -\ MacPlus\ v1.ROM
ROM_REF_mac_plus_v2 = $(ROM_REF_DIR)/128k/Macintosh\ Plus/1986-03\ -\ 4D1EEAE1\ -\ MacPlus\ v2.ROM
ROM_REF_mac_plus_v3 = $(ROM_REF_DIR)/128k/Macintosh\ Plus/1986-03\ -\ 4D1F8172\ -\ MacPlus\ v3.ROM

# ROM_TARGET enumeration (must match include/rom_target.inc)
ROM_NUM_mac_128k    = 1
ROM_NUM_mac_512k    = 2
ROM_NUM_mac_plus_v1 = 3
ROM_NUM_mac_plus_v2 = 4
ROM_NUM_mac_plus_v3 = 5

ENTRY_mac_128k    = rom_original.s
ENTRY_mac_512k    = rom_original.s
ENTRY_mac_plus_v1 = rom_plus.s
ENTRY_mac_plus_v2 = rom_plus.s
ENTRY_mac_plus_v3 = rom_plus.s

PLUS_TARGETS     = mac_plus_v1 mac_plus_v2 mac_plus_v3
ORIGINAL_TARGETS = mac_128k mac_512k
ALL_TARGETS      = $(ORIGINAL_TARGETS) $(PLUS_TARGETS)

.PHONY: all verify $(ALL_TARGETS) clean

all: verify

$(ALL_TARGETS): %: build/rom-%.bin
	@cmp $< $(ROM_REF_$*) >/dev/null 2>&1 \
	  && echo "SUCCESS: $* BIT-IDENTICAL" \
	  || (echo "MISMATCH for $*:"; cmp -l $< $(ROM_REF_$*) 2>&1 | head -20; exit 1)

verify: $(ALL_TARGETS)
	@plus_ok=0; orig_ok=0; \
	cmp build/rom-mac_plus_v1.bin $(ROM_REF_mac_plus_v1) >/dev/null 2>&1 && plus_ok=$$((plus_ok+1)); \
	cmp build/rom-mac_plus_v2.bin $(ROM_REF_mac_plus_v2) >/dev/null 2>&1 && plus_ok=$$((plus_ok+1)); \
	cmp build/rom-mac_plus_v3.bin $(ROM_REF_mac_plus_v3) >/dev/null 2>&1 && plus_ok=$$((plus_ok+1)); \
	cmp build/rom-mac_128k.bin    $(ROM_REF_mac_128k)    >/dev/null 2>&1 && orig_ok=$$((orig_ok+1)); \
	cmp build/rom-mac_512k.bin    $(ROM_REF_mac_512k)    >/dev/null 2>&1 && orig_ok=$$((orig_ok+1)); \
	echo "Plus variants bit-identical:    $$plus_ok of 3"; \
	echo "Original variants bit-identical: $$orig_ok of 2"; \
	if [ $$plus_ok = 3 ] && [ $$orig_ok = 2 ]; then \
	  echo "SUCCESS: ALL FIVE ROMS BIT-IDENTICAL"; \
	fi

build/rom-%.o:
	@mkdir -p build
	$(AS) $(ASFLAGS) --defsym ROM_TARGET=$(ROM_NUM_$*) -o $@ $(ENTRY_$*)

build/rom-%.bin: build/rom-%.o
	$(OBJCOPY) -O binary $< $@

clean:
	rm -rf build
