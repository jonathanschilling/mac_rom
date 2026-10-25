
| -------------------------------------------------------------------------
| Resource_tcsl_0000 (resource-code-or-driver)
| ROM offsets +0x1D88E..+0x1D91C.
| ROM resource type=tcsl id=0 name=- attr=0x58; header +0x1D88E, body +0x1D896
| -------------------------------------------------------------------------
|
| =========================================================================
| 'tcsl' 0 -- the hidden slide show of the SE team photos
| =========================================================================
| A small piece of code that shows the four pictures of 'bbmc' 0 (the
| next resource, resources/res_bbmc.s) one after the other on the
| whole screen, each for about 3 seconds, in an endless loop. Nothing in
| the ROM loads or calls it ('tcsl' appears only in the ROM resource
| map). It is started from a debugger: interrupt the machine with the
| programmer's switch and type G 41D89A (MacsBug or the ROM's MicroBug);
| G 41D896 (the start of the resource) works too, as the two words in
| front of the code decode to the harmless ORI.B #1,D0. The slide show
| never returns -- the only way out is the interrupt switch or a reset.
| It writes straight into the screen buffer and uses ApplScratch ($A78,
| 12 bytes) for its pointers, so it clobbers whatever application runs.
|
| 'bbmc' 0 format, as far as this code uses it:
|   +0   4 longs: offsets of frames 1..4 from the start of the resource
|        data (0x18, 0x5618, 0xA71C, 0xF700; then follow 0x14281 and 0,
|        not used here)
|   frame: 342 rows of PackBits data (UnpackBits), each row unpacking to
|        72 bytes = 576 pixels, the width of a MacPaint picture; the
|        left 512 pixels are shown (the SE screen is 512x342, 64 bytes
|        per row)
| A frame is unpacked row by row directly to the screen: after each
| 72-byte row the destination is moved back by 8 bytes, so that the 8
| bytes beyond the screen's width are overwritten by the next row; the
| 342nd row is unpacked to 64 bytes only, ending at the end of the
| screen. The frame index D7 (0, 4, 8, 12 = byte offset into the table)
| is advanced before each picture, so the order is 2, 3, 4, 1, 2, ...
| If 'bbmc' 0 cannot be found, the code breaks into the debugger.
|
| Sources: the code itself; the trigger G 41D89A is the one known for
| the SE ROM (also in the documented SE FDHD source package's
| EASTER_EGGS.md, which decodes the four frames to images).
| -------------------------------------------------------------------------

Resource_tcsl_0000:
| ROM resource header: a Memory Manager block header, as in front of
| the data of a handle. The relative handle locates the resource's
| master pointer in the ROM zone (INITRESOURCES_CONT_2): 0x54 + 4 *
| its index in the ROM map's reference lists.
Resource_tcsl_0000_Header:
    .long       0xC000008E                      | ROM resource header: tag $C0, physical size $8E (8 + $86)
    .long       0x00000060                      | relative handle: master pointer at ROM zone + $60
| ----------------------------------------------------------
| _tcsl_0_ -- two words of unknown meaning (as an instruction:
| ORI.B #1,D0), then the code
| ----------------------------------------------------------
_tcsl_0_:
    .short      0x0000                          | (unknown; ORI.B #1,D0 if executed)
    .short      0x0001                          | (the ORI's immediate byte)
| TCSL_SLIDESHOW -- the entry point at $41D89A (debugger: G 41D89A).
| Loads 'bbmc' 0, then shows its frames forever.
TCSL_SLIDESHOW:
    JSR         TCSL_LOADBBMC(PC)               | ApplScratch = 'bbmc' data, D7 = 0
| show the next picture, wait 3 seconds, repeat
TCSL_NEXTFRAME:
    ADDQ.W      #0x4,D7                         | next table entry ...
    ANDI.L      #0xC,D7                         | ... of the four: D7 = 0, 4, 8 or 12
    BSR.W       TCSL_DRAWFRAME                  | unpack that picture to the screen
    MOVEA.W     #0xB5,A0                        | 181 ticks (about 3 seconds)
    _Delay                                      | wait
    JMP         TCSL_NEXTFRAME(PC)              | and on to the next picture (forever)
| ----------------------------------------------------------
| TCSL_LOADBBMC -- get 'bbmc' 0 from the ROM resource map.
| Out: ApplScratch = pointer to its data (the frame offset table),
|      D7 = 0. Breaks into the debugger if it is not found.
| ----------------------------------------------------------
TCSL_LOADBBMC:
    MOVE.W      #0xFFFF,(ROMMapInsert).W        | look in the ROM map
    SUBQ.W      #0x4,SP                         | room for the handle
    MOVE.L      #0x62626D63,-(SP)               | resource type 'bbmc'
    CLR.W       -(SP)                           | resource ID 0
    _GetResource                                | get the pictures
    MOVE.L      (SP)+,D0                        | D0 = handle
    BEQ.W       TCSL_NOBBMC                     | not found -> debugger
    MOVEA.L     D0,A0                           | the handle
    MOVE.L      (A0),(ApplScratch).W            | ApplScratch = pointer to the data (in ROM)
    MOVEQ.L     #0x0,D7                         | frame index 0
    RTS                                         | return from TCSL_LOADBBMC
| ----------------------------------------------------------
| TCSL_DRAWFRAME -- unpack frame D7/4 of 'bbmc' 0 onto the screen.
| In:  D7 = 0, 4, 8, 12 (offset into the frame table),
|      ApplScratch = the 'bbmc' data.
| Uses ApplScratch+4 (source pointer) and ApplScratch+8 (destination
| pointer), the VAR parameters of UnpackBits. Changes D0-D3/A0-A1.
| Called by: TCSL_NEXTFRAME
| ----------------------------------------------------------
TCSL_DRAWFRAME:
    MOVEA.L     (ApplScratch).W,A0              | A0 = the frame table
    ADDA.W      D7,A0                           | -> entry D7/4
    MOVE.L      (A0),D3                         | D3 = offset of the frame
    MOVE.L      (ApplScratch).W,(ApplScratch_4).W | source = 'bbmc' data ...
    ADD.L       D3,(ApplScratch_4).W            | ... + offset = the frame's packed rows
    MOVE.L      (ScrnBase).W,(ApplScratch_8).W  | destination = top left of the screen
    MOVE.L      #0x154,D3                       | 341 rows in the loop (DBF)
TCSL_ROWLOOP:
    PEA.L       (ApplScratch_4).W               | VAR srcPtr
    PEA.L       (ApplScratch_8).W               | VAR dstPtr
    MOVE.W      #0x48,-(SP)                     | dstBytes = 72 (a 576-pixel row)
    _UnpackBits                                 | unpack one row; advances both pointers
    SUBQ.L      #0x8,(ApplScratch_8).W          | back by 8: next screen row (64 bytes on)
    DBF.W       D3,TCSL_ROWLOOP                 | next row
    PEA.L       (ApplScratch_4).W               | VAR srcPtr
    PEA.L       (ApplScratch_8).W               | VAR dstPtr
    MOVE.W      #0x40,-(SP)                     | dstBytes = 64: the last row ends the screen
    _UnpackBits                                 | unpack row 342
    RTS                                         | return from TCSL_DRAWFRAME
| 'bbmc' 0 not found: stop in the debugger (continuing would run into
| the next resource's header)
TCSL_NOBBMC:
    _Debugger                                   | break into the debugger

