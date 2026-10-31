/*
	File:		RomResources.r (Macintosh Plus)

	Contains:	The resource fork of the Macintosh Plus ROM, in ROM order: what
				resources it holds and where their data come from. tools/rez/
				rezc.py --rom-asm turns it into the resource map and the order
				and relative handles of the resources (build/rez/plus_rsrc.inc);
				the macros of include/romrsrc.inc compute the 8-byte headers
				from the data between ROM_RESOURCE and ROM_RESOURCE_END in
				src/rom_plus_amalgamated.s. See tools/rez/RomTypes.r for the types.
*/

#include "RomTypes.r"

resource 'rrhd' (0) {
	0x54,						/* relative handle of the first resource: ROM zone + $54 */
	0xCC1C,						/* next-map handle: a value that Apple's build left in the map */
	2,							/* file reference number */
	mapReadOnly,				/* map attributes */
	"BASEOFROM",				/* label of ROM offset 0 */
	{	/* the name list starts with these names, in the order of Apple's map */
		'DRVR', 9;
		'DRVR', 10;
		'DRVR', 4;
		'DRVR', 3;
		'DRVR', 2;
		'FONT', 0
	}
};

resource 'rrsc' (1) {
	{
		asm { 'DRVR', 2, sysHeap+locked+protected, ".Print", "DRVR_2" };	/* the printer driver */
		asm { 'DRVR', 3, sysHeap+locked+protected, ".Sound", "DRVR_3" };	/* the Sound Driver */
		asm { 'DRVR', 4, sysHeap+locked+protected, ".Sony", "DRVR_4" };	/* the disk driver */
		asm { 'DRVR', 10, sysHeap+locked+protected, ".ATP", "DRVR_10" };	/* AppleTalk Transaction Protocol */
		asm { 'DRVR', 9, sysHeap+locked+protected, ".MPP", "DRVR_9" };	/* AppleTalk LAP, DDP and NBP */
		asm { 'SERD', 0, sysHeap+locked+protected, "", "SERD_0" };	/* the serial drivers .AIn/.AOut/.BIn/.BOut */
		asm { 'MDEF', 0, sysHeap+locked+protected, "", "MDEF_0" };	/* standard menu definition */
		asm { 'WDEF', 0, sysHeap+locked+protected, "", "WDEF_0" };	/* standard window definition */
		asm { 'PACK', 7, sysHeap+locked+protected, "", "PACK_7" };	/* Binary-Decimal Conversion Package */
		asm { 'PACK', 5, sysHeap+locked+protected, "", "PACK_5" };	/* SANE elementary functions */
		asm { 'PACK', 4, sysHeap+locked+protected, "", "PACK_4" };	/* SANE floating-point arithmetic */
		asm { 'CURS', 2, sysHeap+locked+protected, "", "CURS_2" };	/* crossCursor */
		asm { 'CURS', 3, sysHeap+locked+protected, "", "CURS_3" };	/* plusCursor */
		asm { 'CURS', 1, sysHeap+locked+protected, "", "CURS_1" };	/* iBeamCursor */
		asm { 'CURS', 4, sysHeap+locked+protected, "", "CURS_4" };	/* watchCursor */
		asm { 'FONT', 0, sysHeap+locked+protected, "Chicago", "FONT_0" };	/* the Chicago family: a name, no data */
		asm { 'FONT', 12, sysHeap+locked+protected, "", "FONT_12" }	/* Chicago 12 */
	}
};
