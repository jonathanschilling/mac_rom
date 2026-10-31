/*
	Types.r -- Rez templates for the standard Macintosh Toolbox and MacApp
	resource types used by Photoshop 1.0.1.  Read by rezc.py before the
	Photoshop sources.

	The binary layouts mirror Apple's MPW 3.x Types.r / SysTypes.r and
	MacApp 2.0's MacAppTypes.r (big-endian, fields packed MSB first).
	Only the subset needed by the original sources is defined here; the
	Photoshop-specific types ('FILT', 'TIP ', 'PLUT', 'OPTs', ...) are
	declared in the Photoshop .r files themselves.
*/

/* ------------------------------------------------------------------------
	MacApp 2.0 command numbers (MacAppTypes.r).  Defined as macros so they
	can be used in 'cmnu' items. */

#define noCommand				0
#define cAboutApp				1
#define cNew					10
#define cOpen					20
#define cSave					30
#define cClose					31
#define cSaveAs					32
#define cSaveCopy				33
#define cRevert					34
#define cQuit					36
#define cUndo					101
#define cCut					103
#define cCopy					104
#define cPaste					105
#define cClear					106
#define cShowClipboard			107
#define cSelectAll				110
#define cPageSetup				176
#define cPrint					177
#define cPrintOne				178
#define cChangePrinterStyle		179

/* ------------------------------------------------------------------------
	Region codes for 'vers' resources (SysTypes.r). */

#define verUS					0
#define verFrance				1
#define verBritain				2
#define verGermany				3
#define verItaly				4
#define verNetherlands			5
#define verFrBelgiumLux			6
#define verSweden				7
#define verSpain				8
#define verDenmark				9
#define verPortugal				10
#define verFrCanada				11
#define verNorway				12
#define verIsrael				13
#define verJapan				14
#define verAustralia			15
#define verArabia				16
#define verFinland				17
#define verFrSwiss				18
#define verGrSwiss				19
#define verGreece				20
#define verIceland				21
#define verMalta				22
#define verCyprus				23
#define verTurkey				24
#define verYugoslavia			25

/* ------------------------------------------------------------------------
	Dialog Manager */

type 'DLOG' {
	rect;											/* boundsRect */
	integer		documentProc,						/* procID */
				dBoxProc,
				plainDBox,
				altDBoxProc,
				noGrowDocProc,
				movableDBoxProc,
				zoomDocProc = 8,
				zoomNoGrow = 12,
				rDocProc = 16;
	byte		invisible, visible;					/* visible */
	fill byte;
	byte		noGoAway, goAway;					/* goAway */
	fill byte;
	unsigned hex longint;							/* refCon */
	integer;										/* itemsID */
	pstring;										/* title */
};

type 'ALRT' {
	rect;											/* boundsRect */
	integer;										/* itemsID */
	wide array [4] {								/* stages 4, 3, 2, 1 */
		boolean		OK, Cancel;						/* bold outline */
		boolean		invisible, visible;				/* draw alert */
		unsigned bitstring[2]
					silent = 0, sound1, sound2, sound3;
	};
};

type 'DITL' {
	integer = $$CountOf(DITLarray) - 1;				/* item count - 1 */
	wide array DITLarray {
		fill long;									/* item handle placeholder */
		rect;										/* display rectangle */
		switch {
		case Button:
			boolean		enabled, disabled;
			key bitstring[7] = 4;
			pstring;								/* title */

		case CheckBox:
			boolean		enabled, disabled;
			key bitstring[7] = 5;
			pstring;								/* title */

		case RadioButton:
			boolean		enabled, disabled;
			key bitstring[7] = 6;
			pstring;								/* title */

		case Control:
			boolean		enabled, disabled;
			key bitstring[7] = 7;
			byte = 2;
			integer;								/* 'CNTL' id */

		case StaticText:
			boolean		enabled, disabled;
			key bitstring[7] = 8;
			pstring;								/* text */

		case EditText:
			boolean		enabled, disabled;
			key bitstring[7] = 16;
			pstring;								/* text */

		case Icon:
			boolean		enabled, disabled;
			key bitstring[7] = 32;
			byte = 2;
			integer;								/* 'ICON' id */

		case Picture:
			boolean		enabled, disabled;
			key bitstring[7] = 64;
			byte = 2;
			integer;								/* 'PICT' id */

		case UserItem:
			boolean		enabled, disabled;
			key bitstring[7] = 0;
			fill byte;
		};
		align word;
	};
};

/* Color tables for dialogs and windows: an empty table (ctSize = -1)
   just makes the Dialog Manager create a color window. */
type 'dctb' {
	unsigned hex longint;							/* ctSeed */
	integer;										/* ctFlags */
	integer = $$CountOf(ColorSpec) - 1;				/* ctSize */
	wide array ColorSpec {
		integer		wContentColor,					/* part */
					wFrameColor,
					wTextColor,
					wHiliteColor,
					wTitleBarColor;
		unsigned integer;							/* red */
		unsigned integer;							/* green */
		unsigned integer;							/* blue */
	};
};

type 'wctb' as 'dctb';

/* ------------------------------------------------------------------------
	Window Manager */

type 'WIND' {
	rect;											/* boundsRect */
	integer		documentProc,						/* procID */
				dBoxProc,
				plainDBox,
				altDBoxProc,
				noGrowDocProc,
				movableDBoxProc,
				zoomDocProc = 8,
				zoomNoGrow = 12,
				rDocProc = 16;
	byte		invisible, visible;					/* visible */
	fill byte;
	byte		noGoAway, goAway;					/* goAway */
	fill byte;
	unsigned hex longint;							/* refCon */
	pstring		Untitled = "Untitled";				/* title */
};

/* ------------------------------------------------------------------------
	Menu Manager */

type 'MENU' {
	integer;										/* menuID */
	fill word[2];									/* menuWidth, menuHeight */
	integer		textMenuProc = 0;					/* MDEF id (high word of menuProc) */
	fill word;										/* (low word of menuProc) */
	unsigned hex bitstring[31]
				allEnabled = 0x7FFFFFFF;			/* enable flags of items 31..1 */
	boolean		disabled, enabled;					/* menu enabled (bit 0) */
	pstring		apple = "\0x14";					/* title */
	wide array {
		pstring;									/* item text */
		byte		noIcon;							/* icon number */
		char		noKey = "\0x00",				/* key equivalent */
					hierarchicalMenu = "\0x1B";
		char		noMark = "\0x00",				/* mark (submenu id) */
					check = "\0x12";
		fill bit;
		unsigned bitstring[7]
					plain, bold = 1, italic = 2, underline = 4,
					outline = 8, shadow = 16, condense = 32, extend = 64;
	};
	byte = 0;										/* end of items */
};

/* MacApp command menus: a 'MENU' whose items carry a command number. */
type 'cmnu' {
	integer;										/* menuID */
	fill word[2];									/* menuWidth, menuHeight */
	integer		textMenuProc = 0;					/* MDEF id */
	fill word;
	unsigned hex bitstring[31]
				allEnabled = 0x7FFFFFFF;			/* enable flags of items 31..1 */
	boolean		disabled, enabled;					/* menu enabled (bit 0) */
	pstring		apple = "\0x14";					/* title */
	wide array {
		pstring;									/* item text */
		byte		noIcon;							/* icon number */
		char		noKey = "\0x00",				/* key equivalent */
					hierarchicalMenu = "\0x1B";
		char		noMark = "\0x00",				/* mark (submenu id) */
					check = "\0x12";
		fill bit;
		unsigned bitstring[7]
					plain, bold = 1, italic = 2, underline = 4,
					outline = 8, shadow = 16, condense = 32, extend = 64;
		integer;									/* MacApp command number */
	};
	byte = 0;										/* end of items */
};

type 'MBAR' {
	integer = $$CountOf(MenuArray);
	wide array MenuArray {
		integer;									/* menu id */
	};
};

/* ------------------------------------------------------------------------
	Strings */

type 'STR ' {
	pstring;
};

type 'STR#' {
	integer = $$CountOf(StringArray);
	array StringArray {
		pstring;
	};
};

/* ------------------------------------------------------------------------
	QuickDraw */

type 'CURS' {
	hex string [32];								/* data */
	hex string [32];								/* mask */
	point;											/* hotSpot (v, h) */
};

type 'PICT' {
	unsigned integer;								/* picSize */
	rect;											/* picFrame */
	hex string;										/* picture opcodes */
};

type 'PAT ' {
	hex string [8];
};

type 'PAT#' {
	integer = $$CountOf(PatArray);
	array PatArray {
		hex string [8];
	};
};

type 'ICON' {
	hex string [128];
};

type 'ICN#' {
	array {
		hex string [128];							/* icon, then mask */
	};
};

/* Palette Manager */
type 'pltt' {
	integer = $$CountOf(ColorInfo);					/* pmEntries */
	fill long;										/* pmDataFields */
	fill word;
	fill long;
	fill long;
	wide array ColorInfo {
		unsigned integer;							/* red */
		unsigned integer;							/* green */
		unsigned integer;							/* blue */
		integer		pmCourteous, pmDithered, pmTolerant,	/* usage */
					pmAnimated = 4, pmExplicit = 8;
		integer;									/* tolerance */
		fill word;									/* private flags */
		fill long;									/* private */
	};
};

/* ------------------------------------------------------------------------
	Finder and Process Manager */

type 'vers' {
	hex byte;										/* major revision (BCD) */
	hex byte;										/* minor revision (BCD) */
	hex byte	development = 0x20,					/* release stage */
				alpha = 0x40,
				beta = 0x60,
				final = 0x80,
				release = 0x80;
	hex byte;										/* non-final release number */
	integer;										/* region code */
	pstring;										/* short version string */
	pstring;										/* long version string */
};

type 'SIZE' {
	boolean		dontSaveScreen, saveScreen;
	boolean		ignoreSuspendResumeEvents, acceptSuspendResumeEvents;
	boolean		enableOptionSwitch, disableOptionSwitch;
	boolean		cannotBackground, canBackground;
	boolean		notMultiFinderAware, multiFinderAware;
	boolean		backgroundAndForeground, onlyBackground;
	boolean		dontGetFrontClicks, getFrontClicks;
	boolean		ignoreChildDiedEvents, acceptChildDiedEvents;
	boolean		not32BitCompatible, is32BitCompatible;
	boolean		reserved;
	boolean		reserved;
	boolean		reserved;
	boolean		reserved;
	boolean		reserved;
	boolean		reserved;
	boolean		reserved;
	unsigned longint;								/* preferred memory size */
	unsigned longint;								/* minimum memory size */
};

type 'BNDL' {
	literal longint;								/* signature */
	integer;										/* version id */
	integer = $$CountOf(TypeArray) - 1;
	array TypeArray {
		literal longint;							/* type ('ICN#', 'FREF') */
		integer = $$CountOf(IDArray) - 1;
		wide array IDArray {
			integer;								/* local id */
			integer;								/* resource id */
		};
	};
};

type 'FREF' {
	literal longint;								/* file type */
	integer;										/* local icon id */
	pstring;										/* file name */
};

/* ------------------------------------------------------------------------
	MacApp 2.0 */

/* Error message table: entries map a range of error codes to an index in
   the current string list; "whichList, 0, id" selects the 'STR#' list
   used by the following entries. */
type 'errs' {
	integer = $$CountOf(ErrsArray);
	wide array ErrsArray {
		integer		whichList = 0;					/* first error, or whichList */
		integer;									/* last error */
		integer;									/* string index, or 'STR#' id */
	};
};

/* Memory reserve adjustments */
type 'mem!' {
	longint;										/* add to temporary reserve */
	longint;										/* add to permanent reserve */
	longint;										/* add to stack space */
};

/* Segments that must be resident: a list of segment names */
type 'seg!' as 'STR#';
