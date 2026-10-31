/*
	File:		RomTypes.r

	Contains:	Resource types that describe the resource fork of a ROM image,
				for tools/rez/rezc.py --rom-asm.

					rrhd -	ROM resource header	the two words that InitResources
												reads and the resource map: the
												parameters of the map
					rrsc -	ROM resources		the resources of the ROM, in ROM
												order, and where their data come from

				The type codes are those of Apple's RomTypes.r for the RomLayout
				tool (System 7.1 sources, Internal/Rez: 'rrhd' "Rom Resource
				Header", 'rrsc' "Rom Resource"; its 'rmap' means something else,
				a request to print a link map), with which Apple described the
				ROM resources of its later ROMs as resources of a Rez source.
				The fields are not Apple's: RomLayout placed resource files into
				a ROM image by address, while these types describe the resource
				fork of a Plus or SE ROM for the assembler.

				rezc.py reads these resources and writes the ROM resource fork
				as GNU as source (macros of include/romrsrc.inc): the two words
				that InitResources reads, the resource map, and the 8-byte header
				in front of each resource (Memory Manager block header: tag $C0
				with the physical size, then the relative handle of the
				resource's master pointer). Sizes, offsets and handles are
				computed; nothing of the map is written by hand.
*/

#ifndef __ROMTYPES_R__
#define __ROMTYPES_R__

/*
	ROM resource header: one per ROM (ID 0). The area header (number of
	resources, size of the map) and the resource map follow from it and from
	the 'rrsc' list.

	The map is that of an equivalent resource file: its first 16 bytes hold
	the header such a file would have (data offset $100, map offset, data
	length = the sum of 4 + size over all resources, map length).
*/
type 'rrhd' {
	unsigned hex longint;				/* relative handle of the first resource: the
										   offset of the first master pointer of the
										   resources in the ROM zone that InitResources
										   creates (each further resource: + 4) */
	unsigned hex longint;				/* next-map handle field of the map */
	integer;							/* file reference number field of the map */
	unsigned hex integer				/* map attributes */
		mapReadOnly = 0x8000, mapCompact = 0x4000, mapChanged = 0x2000;
	pstring;							/* label of ROM offset 0: the data offsets of
										   the map are relative to it */
	align word;
	integer = $$CountOf(NameOrder);
	array NameOrder {					/* the resources whose names come first in the
										   name list, in this order; the names of the
										   other resources follow in ROM order */
		literal longint;				/* resource type */
		integer;						/* resource ID */
	};
};

/*
	ROM resources: the resources of the ROM, in ROM order. Several 'rrsc'
	resources are taken in the order of their IDs.

	asm:	the data are assembled from the ROM source, between the macros
			ROM_RESOURCE symbol and ROM_RESOURCE_END symbol
	rez:	the data are those of the resource of this type and ID compiled
			from the Rez sources (name and attributes from its statement);
			the macro ROM_RESOURCE_REZ symbol places it in the ROM source
*/
type 'rrsc' {
	integer = $$CountOf(Resources);
	array Resources {
		switch {
		case asm:
			key integer = 1;
			literal longint;			/* resource type */
			integer;					/* resource ID */
			byte						/* resource attributes (Inside Macintosh I-111);
										   all resources of the Plus and SE ROMs have
										   sysHeap+locked+protected = $58, the value
										   that Apple's RomTypes.r calls kkResourceAttr */
				sysHeap = 0x40, purgeable = 0x20, locked = 0x10,
				protected = 0x08, preload = 0x04, changed = 0x02;
			pstring;					/* resource name; "" = none */
			pstring;					/* assembler symbol */
			align word;
		case rez:
			key integer = 2;
			literal longint;			/* resource type */
			integer;					/* resource ID */
			pstring;					/* assembler symbol */
			align word;
		};
	};
};

#endif /* __ROMTYPES_R__ */
