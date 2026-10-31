#!/bin/sh
# tools/rom_map.sh - write a ROM map of an assembled ROM, in the layout of
# Apple's MPW ROM maps (MacPlusROM.lst / MacSEROM.lst, "ROM.List" format)
# and as "name 0xOFFSET l" lines (the joevt/68k-mac-rom-maps format used
# by Ghidra's ImportSymbolsScript.py).
#
# usage:
#   rom_map.sh <nm> <rom.o> <size-hex8> <last-hex> <seg> <id> <size-name> \
#              <style> <out.lst> <out.lst.txt> [<flags>]
#
#   <nm>         m68k nm program (e.g. m68k-linux-gnu-nm)
#   <size-hex8>  ROM size as 8 hex digits (e.g. 00020000)
#   <last-hex>   last ROM offset in hex (e.g. 1FFFF)
#   <seg> <id>   " seg Main <seg>" header and "$<id>,$<offset>" entries
#   <size-name>  " size <size-name> <last-hex>" trailer
#   <style>      plus (MacPlusROM.lst layout) or se (MacSEROM.lst layout)
#   <flags>      optional table "<style> <name> <offset-hex> <flag>": the
#                flags of the Apple map entries (#, E, #E, R), so that their
#                lines come out byte-identical to Apple's map
#
# Every label of the ROM image is listed, sorted by offset (labels at the
# same offset in source order). A label ending in __MAP is listed without
# that suffix (Apple names that cannot be assembler symbols). Apple map
# entries get Apple's flag, other labels at a ROM resource (_TYPE_id_name)
# the R flag. This is the shell/awk twin of tools/gen_rom_map.py (default
# mode), for trees without Python.

set -eu
[ $# -eq 10 ] || [ $# -eq 11 ] || { echo "usage: $0 nm rom.o size-hex8 last-hex seg id size-name style out.lst out.lst.txt [flags]" >&2; exit 2; }
nm=$1 obj=$2 size=$3 last=$4 seg=$5 id=$6 sname=$7 style=$8 lst=$9
shift 9
txt=$1 flags=${2:-}

"$nm" -p "$obj" | awk -v size="$size" '
    ($2 == "t" || $2 == "T") && NF == 3 && substr($3, 1, 1) != "." &&
    length($1) == 8 && toupper($1) < size { print toupper($1), NR, $3 }' |
sort -k1,1 -k2,2n |
awk -v seg="$seg" -v id="$id" -v sname="$sname" -v last="$last" \
    -v style="$style" -v txt="$txt" -v flags="$flags" '
    function pad(s) {
        if (length(s) <= 8) return s "\t\t"
        if (length(s) == 9) return s " \t"
        return s "\t"
    }
    BEGIN {
        print " seg RAM FD"; print " loc 0"
        print "RAMStart\t\tRAM\tFD,0"; print "RAMEnd\t\tRAM\tFD,FFFFE"
        print " size RAM FFFFF"; print ""
        print " seg Main " seg
        if (style == "plus") print " loc 400000"
        printf "" > txt
        if (flags != "")
            while ((getline line < flags) > 0) {
                split(line, f, " ")
                if (f[1] == style) flag[f[2] SUBSEP f[3]] = f[4]
            }
    }
    {
        off = $1; sub(/^0+/, "", off); if (off == "") off = "0"
        addr = "$" id ",$" off
        name = $3; sub(/__MAP$/, "", name)
        if ((name SUBSEP off) in flag) fl = flag[name SUBSEP off]
        else if (name ~ /^_[A-Za-z ][A-Za-z ][A-Za-z ][A-Za-z ]_[0-9]+_/) fl = "R"
        else fl = ""
        if (fl != "")
            print pad(name) "Main\t" pad(addr) (style == "se" ? " " : "") fl
        else
            print pad(name) "Main\t" addr
        print name " 0x" off " l" >> txt
    }
    END {
        print " size " sname " " last
        print "size_Main 0x" last " l" >> txt
    }' > "$lst"
