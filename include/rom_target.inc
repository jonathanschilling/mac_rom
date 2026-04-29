| ===========================================================================
| rom_target.inc -- select which Macintosh ROM this build should produce
|
| Five supported targets span two generations of Macintosh ROM:
|
|     Value  Name            Date     Size    Checksum
|     1      MAC_128K        1984-01  64 KB   $28BA61CE
|     2      MAC_512K        1984-10  64 KB   $28BA4E50
|     3      MAC_PLUS_V1     1986-01  128 KB  $4D1EEEE1
|     4      MAC_PLUS_V2     1986-03  128 KB  $4D1EEAE1
|     5      MAC_PLUS_V3     1986-03  128 KB  $4D1F8172   (default)
|
| The 1984 64 KB ROMs (Mac 128K and Mac 512K) are the "original"
| generation — not to be confused with the "Macintosh Classic", a
| later 1990 product that shares neither bytes nor source.
|
| Override via the assembler command line:
|     m68k-linux-gnu-as --defsym ROM_TARGET=1 ...
|
| The Makefile sets this automatically per target (`mac_128k`, `mac_512k`,
| `mac_plus_v1`, `mac_plus_v2`, `mac_plus_v3`). The bare `make` target
| builds and verifies all five.
|
| Derived selector constants (computed below):
|
|     ROM_IS_ORIGINAL  1 when ROM_TARGET is MAC_128K or MAC_512K
|     ROM_IS_PLUS      1 when ROM_TARGET is any MAC_PLUS_*
|     ROM_SIZE         $10000 (64 KB) for the original, $20000 (128 KB) for Plus
|
| Intended usage pattern:
|
|     .if ROM_IS_PLUS
|         | Plus-only code / driver / routine
|     .endif
|
|     .if ROM_TARGET == MAC_PLUS_V3
|         | v3-specific patch
|     .elseif ROM_TARGET == MAC_PLUS_V2
|         | v2-specific patch
|     .else
|         | v1 code path
|     .endif
|
| The Plus evolution (v1 → v2 → v3) is covered by six inline diff sites
| in vectors.s / interrupts.s / file_mgr_cache.s / extra.s. The 1984
| original generation lives under src/original/ (with the 128K↔512K
| diffs wrapped inline as `.if ROM_TARGET == MAC_128K` blocks) and has
| its own entry files src/original/rom_128k.s and rom_512k.s. The Plus
| tree under src/plus/ is entry-point src/plus/rom_plus.s.
| ===========================================================================

| Enumeration of supported ROM targets.
.equ MAC_128K,     1
.equ MAC_512K,     2
.equ MAC_PLUS_V1,  3
.equ MAC_PLUS_V2,  4
.equ MAC_PLUS_V3,  5

| Default target: most widely deployed (and where the current source
| tree has 100% coverage). Allows the legacy `make` behaviour for a
| bare invocation without a `--defsym`.
.ifndef ROM_TARGET
  .equ ROM_TARGET, MAC_PLUS_V3
.endif

.if (ROM_TARGET < MAC_128K)                     | | (ROM_TARGET > MAC_PLUS_V3)
  .error "ROM_TARGET must be one of MAC_128K(1), MAC_512K(2), MAC_PLUS_V1(3), MAC_PLUS_V2(4), MAC_PLUS_V3(5)"
.endif

| Generation-level aliases — prefer these for whole-file or
| whole-subsystem gating (Plus added HFS, SCSI, Time Manager, etc. that
| simply do not exist in the 1984 original ROMs).
.equ ROM_IS_ORIGINAL, (ROM_TARGET <= MAC_512K)
.equ ROM_IS_PLUS,     (ROM_TARGET >= MAC_PLUS_V1)

| ROM physical size (used where the assembled binary needs a trailing
| `.fill` or a verified `.org` boundary).
.if ROM_IS_ORIGINAL
  .equ ROM_SIZE, 0x10000
.else
  .equ ROM_SIZE, 0x20000
.endif
