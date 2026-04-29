| Extra Area (ROM tail)
|
| Contains a SCSI patch applied to ROM v3, developer initials
| (easter egg), and the ROM build date "Wed, Nov 6, 1985".

| SCSI patch, easter egg, date string
| ROM section: src/extra/extra.asm
| Called during boot (v3 only; see ROM-variant notes below).
|
| --- ROM-variant difference @ $1FFC0-$1FFCF (first 16 bytes of area) ---
| v1/v2: these 16 bytes are the opening of a developer-initials easter
| egg: "ALR ELR BA BMB E" (continuing below as "HB JTC SC DLD...").
| v3: these 16 bytes are the SCSI-patch subroutine `EXTRA_CONT`. The
| callers at $08AC (InitIOMgr) and effectively $7D4A (CheckSCSI)
| jump here to reset the SCSI bus and call the boot continuation
| at ROM+$7D40. The easter egg is still present from byte 16
| onwards -- only its opening 16 chars are overlaid by the code.
| Reason: Apple chose this area because it already contained only
| decorative ASCII (credits+date), so repurposing the first 16
| bytes gave them a hook-point for the SCSI patch without
| disturbing any real code or data.
.if ROM_TARGET < MAC_PLUS_V3
| Plus v1/v2: opening of the developer-initials easter egg (16 bytes).
  .ascii "ALR ELR BA BMB E"
.else
| Plus v3: SCSI-patch subroutine (16 bytes) -- overwrites the 16-char
| prefix of the easter egg. Invoked via `JSR (0x41FFC0).l` from InitIOMgr.
EXTRA_CONT:
        CLR     (SCSIDrvrs).w                   | clear SCSI driver count
        CLR     -(SP)                           | push selector 0 = SCSIReset
        _SCSIDispatch                           | reset SCSI bus
        JSR     (0x407D40).l                    | call CheckSCSI (ROM + $7D40)
        RTS                                     | return to main boot sequence
.endif

| Remainder of the developer-initials easter egg -- present in all three
| ROMs. Together with the v1/v2 opening, the full text reads:
| 'ALR ELR BA BMB EHB JTC SC DLD PWD KWK LAK SEL B'
| initials of: ?, Erich Ringewald, Bill Atkinson, Bill (Monroe) Bruffey,
| Ernie Beernink, Jerome (Toby) Coonen, Steve Capps, Donn Denman,
| Patrick W. Penzias Dirks, ?, Larry Kenyon, and ?.
| Sources: 'The Macintosh Secret Trick List' by Brian Kendig
| (contributed by Scott Lindhurst and Ed Tecot).
  .ascii "HB JTC SC DLD PWD KWK LAK SEL B"

| ROM build date string
  .ascii "Wed, Nov 6, 1985"
  .byte 0x10

| end of Extra area
| end of ROM

