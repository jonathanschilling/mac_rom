/*
	File:		RomResources.r (Macintosh SE and SE FDHD)

	Contains:	The resource fork of the Macintosh SE and SE FDHD ROMs, in ROM
				order: what resources it holds and where their data come from.
				Both ROMs have the same map; the FDHD's .Sony driver has other
				data in a slot of the same size. tools/rez/rezc.py --rom-asm
				turns this file into the resource map and the order and
				relative handles of the resources (build/rez/se_rsrc.inc); the
				macros of include/romrsrc.inc compute the 8-byte headers from
				the data between ROM_RESOURCE and ROM_RESOURCE_END in
				src/rom_se_amalgamated.s. See tools/rez/RomTypes.r for the types.
*/

#include "RomTypes.r"

resource 'rrhd' (0) {
	0x54,						/* relative handle of the first resource: ROM zone + $54 */
	0,							/* next-map handle (0 in the SE ROMs' map) */
	2,							/* file reference number */
	mapReadOnly,				/* map attributes */
	"BASEOFROM",				/* label of ROM offset 0 */
	{	/* the name list starts with these names, in the order of Apple's map */
		'DRVR', 10;
		'DRVR', 9;
		'FONT', 0;
		'DRVR', 4;
		'DRVR', 3;
		'DRVR', 40
	}
};

resource 'rrsc' (1) {
	{
		asm { 'PACK', 5, sysHeap+locked+protected, "", "PACK_5" };	/* SANE elementary functions */
		asm { 'PACK', 4, sysHeap+locked+protected, "", "PACK_4" };	/* SANE floating-point arithmetic */
		asm { 'PACK', 7, sysHeap+locked+protected, "", "PACK_7" };	/* Binary-Decimal Conversion Package */
		asm { 'tcsl', 0, sysHeap+locked+protected, "", "tcsl_0" };	/* the hidden slide show (code) */
		asm { 'bbmc', 0, sysHeap+locked+protected, "", "bbmc_0" };	/* the hidden team photos (data) */
		asm { 'SERD', 0, sysHeap+locked+protected, "", "SERD_0" };	/* the serial drivers .AIn/.AOut/.BIn/.BOut */
		asm { 'DRVR', 10, sysHeap+locked+protected, ".ATP", "DRVR_10" };	/* AppleTalk Transaction Protocol */
		asm { 'DRVR', 9, sysHeap+locked+protected, ".MPP", "DRVR_9" };	/* AppleTalk LAP, DDP and NBP */
		asm { 'DRVR', 4, sysHeap+locked+protected, ".Sony", "DRVR_4" };	/* the disk driver */
		asm { 'DRVR', 3, sysHeap+locked+protected, ".Sound", "DRVR_3" };	/* the Sound Driver */
		asm { 'DRVR', 40, sysHeap+locked+protected, ".XPP", "DRVR_40" };	/* AppleTalk Session Protocol and AFP */
		asm { 'CDEF', 0, sysHeap+locked+protected, "", "CDEF_0" };	/* buttons, check boxes, radio buttons */
		asm { 'CDEF', 1, sysHeap+locked+protected, "", "CDEF_1" };	/* scroll bars */
		asm { 'KCHR', 0, sysHeap+locked+protected, "", "KCHR_0" };	/* keyboard character map (U.S.) */
		asm { 'KMAP', 0, sysHeap+locked+protected, "", "KMAP_0" };	/* keyboard map */
		asm { 'MBDF', 0, sysHeap+locked+protected, "", "MBDF_0" };	/* menu bar definition */
		asm { 'MDEF', 0, sysHeap+locked+protected, "", "MDEF_0" };	/* standard menu definition */
		asm { 'WDEF', 1, sysHeap+locked+protected, "", "WDEF_1" };	/* rounded-corner window definition */
		asm { 'WDEF', 0, sysHeap+locked+protected, "", "WDEF_0" };	/* standard window definition */
		asm { 'CURS', 4, sysHeap+locked+protected, "", "CURS_4" };	/* watchCursor */
		asm { 'CURS', 1, sysHeap+locked+protected, "", "CURS_1" };	/* iBeamCursor */
		asm { 'CURS', 3, sysHeap+locked+protected, "", "CURS_3" };	/* plusCursor */
		asm { 'CURS', 2, sysHeap+locked+protected, "", "CURS_2" };	/* crossCursor */
		asm { 'FONT', 12, sysHeap+locked+protected, "", "FONT_12" };	/* Chicago 12 */
		asm { 'FONT', 0, sysHeap+locked+protected, "Chicago", "FONT_0" };	/* the Chicago family: a name, no data */
		asm { 'FONT', 393, sysHeap+locked+protected, "", "FONT_393" };	/* Geneva 9 */
		asm { 'FONT', 396, sysHeap+locked+protected, "", "FONT_396" };	/* Geneva 12 */
		asm { 'FONT', 521, sysHeap+locked+protected, "", "FONT_521" }	/* Monaco 9 */
	}
};
