#!/bin/sh
# tools/verify_rom.sh - verify one assembled ROM image.
#
# Usage:
#   verify_rom.sh <target> <rom.bin> <size> <checksum> <version> <md5> [<reference.rom>]
#
# Every build is checked against hardcoded fingerprints of the original
# ROM image (passed in by the Makefile), so the verification also works
# for users who do not have the copyrighted reference ROM images:
#
#   size      image size in bytes
#   checksum  the ROM's own signature: the 32-bit checksum stored in
#             bytes 0-3 (hex, e.g. 4D1F8172). Both the stored value and
#             the checksum recomputed over the image (sum of all big-endian
#             16-bit words from offset 4 to the end, modulo 2^32) must
#             equal it.
#   version   the ROM version word at offset 8 (hex, e.g. 0075)
#   md5       MD5 digest of the whole image
#
# 256 KB (Mac SE) images also carry per-chip checksums at offsets $30 and
# $34: the byte sums of the even (high-byte chip) and odd (low-byte chip)
# addresses, with the checksum at $0 and these two longs taken as zero.
# They are recomputed and compared with the stored values as well.
#
# If <reference.rom> is given and the file exists, the image is also
# compared byte-for-byte against it (cmp). If it is missing, that step
# is skipped and the MD5 match stands in for it.
#
# Exits non-zero on any mismatch. Only POSIX sh, od, awk, wc, cmp and an
# MD5 tool (md5sum, md5 or openssl) are needed.

set -u

if [ $# -lt 6 ]; then
    echo "usage: $0 <target> <rom.bin> <size> <checksum> <version> <md5> [<reference.rom>]" >&2
    exit 2
fi

target=$1
rom=$2
exp_size=$3
exp_cksum=$(echo "$4" | tr 'a-f' 'A-F')
exp_ver=$(echo "$5" | tr 'a-f' 'A-F')
exp_md5=$(echo "$6" | tr 'A-F' 'a-f')
ref=${7-}

if [ ! -f "$rom" ]; then
    echo "FAIL: $target: $rom not found" >&2
    exit 1
fi

fail=0
report() {
    # report <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "  $1: $3 OK"
    else
        echo "  $1: expected $2, got $3 MISMATCH"
        fail=1
    fi
}

md5_of() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum < "$1" | cut -d' ' -f1
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q "$1"
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -md5 < "$1" | sed 's/^.*= *//'
    else
        echo "no-md5-tool"
    fi
}

hex_bytes() {
    # hex_bytes <file> <offset> <count>  ->  upper-case hex string
    od -An -v -tx1 -j "$2" -N "$3" "$1" | tr -d ' \n' | tr 'a-f' 'A-F'
}

size=$(wc -c < "$rom" | tr -d ' ')
stored=$(hex_bytes "$rom" 0 4)
version=$(hex_bytes "$rom" 8 2)
# Mac ROM checksum: sum of the big-endian 16-bit words from offset 4 to
# the end of the image, modulo 2^32. Printed as two 16-bit halves so that
# awk implementations with 32-bit printf never see a value above 65535.
computed=$(od -An -v -tu1 -j 4 "$rom" | awk '
    { for (i = 1; i <= NF; i++) {
          if (have_hi) { s += hi * 256 + $i; have_hi = 0 }
          else         { hi = $i; have_hi = 1 }
      } }
    END { s = s % 4294967296
          printf "%04X%04X\n", int(s / 65536), s % 65536 }')
md5=$(md5_of "$rom")
if [ "$size" -eq 262144 ]; then
    chips_stored="$(hex_bytes "$rom" 48 4) $(hex_bytes "$rom" 52 4)"
    chips_computed=$(od -An -v -tu1 "$rom" | awk '
        { for (i = 1; i <= NF; i++) {
              if (!((n >= 0 && n <= 3) || (n >= 48 && n <= 55))) {
                  if (n % 2 == 0) e += $i; else o += $i
              }
              n++
          } }
        END { e = e % 4294967296; o = o % 4294967296
              printf "%04X%04X %04X%04X\n", int(e / 65536), e % 65536,
                                            int(o / 65536), o % 65536 }')
fi

echo "$target: $rom"
report "size             " "$exp_size" "$size"
report "stored checksum  " "$exp_cksum" "$stored"
report "computed checksum" "$exp_cksum" "$computed"
report "ROM version      " "$exp_ver" "$version"
report "MD5              " "$exp_md5" "$md5"
if [ "$size" -eq 262144 ]; then
    report "chip checksums   " "$chips_computed" "$chips_stored"
fi

if [ -n "$ref" ] && [ -f "$ref" ]; then
    if cmp -s "$rom" "$ref"; then
        echo "  reference image  : identical (cmp) OK"
        method="cmp against reference image + checksum + MD5"
    else
        echo "  reference image  : DIFFERS from $ref"
        cmp -l "$rom" "$ref" 2>&1 | head -20 | sed 's/^/    /'
        fail=1
    fi
else
    echo "  reference image  : not found, byte-for-byte cmp skipped"
    method="checksum + MD5; reference image not available"
fi

if [ $fail -ne 0 ]; then
    echo "MISMATCH for $target"
    exit 1
fi
echo "SUCCESS: $target BIT-IDENTICAL ($method)"
