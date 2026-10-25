| Sad Mac / Happy Mac icon display (ROM $078E-$0903)
|
| Draws the Mac icon with the sad face (after a failed startup test) or
| the happy face (a startup disk was found), and the disk icons with the
| question and X marks.
|
| Entry points:
| PutIcon @ $0790 -- the _PutIcon trap ($A9CA): decompress a 32x32 icon
| onto the screen. The boot code enters two bytes earlier, at
| PUTICON_REBASE ($078E), which first adds the RAM base A3 to A2.
| ShowSadMac @ $07CC -- A5 = return addr, draws the Mac-outline icon +
| sad-face overlay.
| ShowHappyMac @ $07F4 -- the same with the happy face.
|
| Internal helpers and data:
| ICON_XOR_PROPAGATE @ $07BC -- after RLE decode, delta-XOR each row with
| the one above to reconstruct the bitmap.
| PutSymbol @ $07FA -- copy a small glyph bitmap into the screen.
| ICON_MAC_OUTLINE @ $080C, ICON_DISK @ $0870 -- RLE-compressed icons.
| DT_mHappyMac, DT_mSadMac, DT_mQMark, DT_mXMark -- overlay glyphs.
| The System Error Handler (SysBeep, SysError, the alert) follows in
| os/sys_error.s.

| ----------------------------------------------------------
|
| PUTICON_REBASE - boot-code entry, two bytes before PutIcon:
| A2 += A3 (RAM base, $600000 or 0), then falls into PutIcon.
| Used by PlotDisk and DRAW_MAC_ICON.
PUTICON_REBASE:                                 | boot entry: A2 is RAM-relative
        ADDA.L  A3,A2                           | A2 += RAM base (screen buffer)
|
| _PutIcon ($A9CA): decompress a 32x32 icon onto the screen
| Entry: A2 = screen address of the icon's top-left byte,
|        A4 = compressed icon data, A6 = return address
| Exit:  via JMP (A6); A4 past the data; D2-D4, A0-A2 trashed
| Format: 16 flag bytes, each followed by its data bytes. Each flag
| bit (LSB first) yields one output byte: 1 = zero byte, 0 = next
| data byte. Output fills 4 bytes per screen row (64-byte stride),
| 32 rows; then every row is XORed with the one above (delta coding).
PutIcon:
        MOVEQ.L #0xF,D3                         | D3 = 15: 16 flag bytes (8 output bytes each)
        MOVE.L  A2,A0                           | A0 = save screen start for XOR-propagate
        MOVEQ.L #0x3,D2                         | D2 = 3 (4 bytes per row before row-skip)
| ----------------------------------------------------------
| ICON_ROW_LOOP - fetch the next flag byte (8 output bytes = 2 rows)
ICON_ROW_LOOP:                                  | ICON_ROW_LOOP
        MOVE    #0x100,D4                       | D4 bit 8 = sentinel (detect end of flag byte)
        MOVE.B  (A4)+,D4                        | D4 low byte = run-length flag bits
ICON_BIT_LOOP:                                  | ICON_BIT_LOOP
        LSR     #0x1,D4                         | shift next flag bit into carry
        BEQ.B   ICON_NEXT_ROW                   | sentinel reached: 8 bits used, next flag byte
        BCC.B   ICON_COPY_BYTE                  | carry=0: data byte comes from (A4) (skip zero)
        CLR.B   (A2)+                           | carry=1: write zero (white pixel column)
        BRA.B   ICON_BYTE_COUNT                 | -> byte counter
ICON_COPY_BYTE:                                 | ICON_COPY_BYTE
        MOVE.B   (A4)+,(A2)+                    | copy icon-data byte to screen buffer
ICON_BYTE_COUNT:                                | ICON_BYTE_COUNT
        DBRA    D2,ICON_BIT_LOOP                | continue decoding current flag byte
        ADDA.W  #0x3C,A2                        | skip remaining bytes to next screen row (60)
        MOVEQ.L #0x3,D2                         | reset byte counter (4 bytes per group)
        BRA.B   ICON_BIT_LOOP                   | continue decoding
ICON_NEXT_ROW:                                  | ICON_NEXT_ROW
        DBRA    D3,ICON_ROW_LOOP                | 16 flag bytes (32 rows) total
        MOVE.L  A0,A1                           | A1 = icon start row (source for XOR)
        MOVEQ.L #0x1E,D3                        | D3 = 30: propagate icon down 31 more rows
| XOR each row with the previous to reconstruct delta-encoded image
ICON_XOR_PROPAGATE:
        ADDA.W  #0x40,A1                        | advance A1 to next screen row (64 bytes/row)
        MOVE.L  (A0),D4                         | D4 = previous row's 4 bytes (32 pixels)
        EOR.L   D4,(A1)                         | XOR previous row into current (delta decode)
        MOVE.L  A1,A0                           | current row becomes source for next iteration
        DBRA    D3,ICON_XOR_PROPAGATE           | repeat for 31 rows
        JMP     (A6)                            | return to caller (A6)
| ----------------------------------------------------------
| ShowSadMac -- draw sad-Mac icon on boot screen after test failure
| Return address in A5. Encodes as `LEA 0xE6(PC),A0` which loads A0
| with the pointer to the sad-face glyph data at $08B4 (DT_mSadMac),
| then falls through into DRAW_MAC_ICON's common outline+overlay loop.
ShowSadMac:
        LEA     DT_mSadMac(PC),A0               | A0 = sad-face glyph data at $08B4
DRAW_MAC_ICON:                                  | DRAW_MAC_ICON
        LEA     ICON_MAC_OUTLINE(PC),A4         | A4 = compressed Mac outline icon
        MOVE.L  A0,D7                           | D7 = save face-data ptr across PutIcon
        MOVE.L  #0x7CB5E,A2                     | A2 = SEScrnIcon (centered screen pos)
        LEA     DRAW_FACE_OVERLAY(PC),A6        | return to DRAW_FACE_OVERLAY after outline
        BRA.B   PUTICON_REBASE                  | decode and draw Mac outline icon
DRAW_FACE_OVERLAY:                              | DRAW_FACE_OVERLAY
        MOVE.L  #0x7CCDF,A2                     | A2 = SEScrnFace (face position in icon)
        MOVE.L  D7,A4                           | A4 = face data (sad/happy, saved in D7)
        LEA     ICON_DRAW_RETURN(PC),A6         | return to ICON_DRAW_RETURN after face
        BRA.W   PutSymbol                       | draw 10-row face bitmap (PutSymbol)
ICON_DRAW_RETURN:                               | ICON_DRAW_RETURN
        JMP     (A5)                            | return to original caller
ShowHappyMac:                                   | ShowHappyMac entry
        LEA     DT_mHappyMac(PC),A0             | A0 = happy-face glyph data
        BRA.B   DRAW_MAC_ICON                   | draw outline + happy face
PutSymbol:                                      | PutSymbol prologue
        ADDA.L  A3,A2                           | A2 += RAM base (adjust to real screen addr)
        MOVEQ.L #0x9,D2                         | D2 = 9 (10 rows to draw)
PUTSYMBOL_LOOP:                                 | copy one bitmap row
        MOVE.B  (A4)+,(A2)+                     | copy left byte of row
        MOVE.B  (A4)+,(A2)+                     | copy right byte of row
        ADDA.W  #0x3E,A2                        | skip to next screen row (64 - 2 written)
        DBRA    D2,PUTSYMBOL_LOOP               | repeat for all 10 rows
PUTSYMBOL_EXIT:
        JMP     (A6)                            | return to caller

| ==========================================================================
| $080C..$0903 -- boot-screen icon + face glyph data tables.
| Six bitmap tables used by PutIcon (RLE decoder, above) and
| PUTSYMBOL_LOOP to draw the boot screen:
| ICON_MAC_OUTLINE @ $080C (100 B) Mac computer outline, RLE-encoded
| ICON_DISK @ $0870 ( 48 B) floppy-disk icon (retry animation)
| DT_mHappyMac @ $08A0 ( 20 B) happy-face glyph (10 rows x 2 B)
| DT_mSadMac @ $08B4 ( 20 B) sad-face glyph (10 rows x 2 B)
| DT_mQMark @ $08C8 ( 30 B) question-mark glyph (15 rows x 2 B)
| DT_mXMark @ $08E6 ( 30 B) X-mark glyph (15 rows x 2 B)
| FDisasm originally rendered this region as a chaotic mix of "fake"
| instructions because several byte values happen to encode legal
| 68000 mnemonics. Rewritten here as pure `.byte` data with per-row
| commentary. Byte layout matches Plus's src/plus/boot/memtest.s
| tables exactly (lines 349-402).
| ==========================================================================

| ICON_MAC_OUTLINE -- compressed Macintosh computer outline (32x32 pixels,
| delta-encoded), decoded by PutIcon at SEScrnIcon. 100 bytes in PutIcon
| format: 16 flag bytes, each followed by its non-zero data bytes.
ICON_MAC_OUTLINE:
        .byte   0x00,0x57,0xFF,0xFF,0xD5,0xFF   | rows 1-2 (top edge)
        .byte   0xFF,0xFF,0xFF,0x06,0xF8,0x3F   | rows 2-3 (bezel top corners)
        .byte   0xE1,0xFF,0xFF,0x0F,0x60,0xE3   | rows 3-4 (screen area top)
        .byte   0xFF,0xFF,0x8F,0xE0,0x0F,0x66   | rows 4-5 (screen L/R borders)
        .byte   0xE0,0x0F,0xE0,0x0F,0x66,0xE0   | rows 5-6 (screen interior)
        .byte   0x0F,0xE0,0x0F,0x66,0xE0,0x0F   | rows 6-7 (screen interior)
        .byte   0xE0,0x0F,0x66,0xE0,0x0F,0xE0   | rows 7-8 (screen interior)
        .byte   0x0F,0x66,0xE0,0x0F,0xE0,0x0F   | rows 8-9 (screen interior)
        .byte   0x06,0xE0,0x0F,0xE3,0xFF,0xFF   | rows 9-10 (screen bottom)
        .byte   0x8F,0x60,0xE1,0xFF,0xFF,0x0F   | rows 10-11 (bezel divider)
        .byte   0xE0,0x0F,0x66,0xE0,0x0F,0xE0   | rows 11-12 (floppy slot area)
        .byte   0x0F,0x22,0xE3,0x3F,0x0F,0xE3   | rows 12-13 (floppy slot detail)
        .byte   0x3F,0x0F,0x66,0xE0,0x0F,0xE0   | rows 13-14 (lower bezel)
        .byte   0x0F,0x06,0xE0,0x0F,0xFF,0xFF   | rows 14-15 (bezel bottom)
        .byte   0xFF,0xFF,0x60,0xF7,0xFF,0xFF   | rows 15-16 (base top)
        .byte   0xDF,0xF0,0x1F,0x06,0xF0,0x1F   | rows 16+ (base front)
        .byte   0xF7,0xFF,0xFF,0xDF             | base bottom edge

| ----------------------------------------------------------
| ICON_DISK -- 32x32 floppy-disk icon used during the read-failure
| animation that cycles between Mac outline and disk. 48 bytes in
| PutIcon format (16 flag bytes + 32 data bytes). Drawn by PlotDisk.
ICON_DISK:
        .byte   0x00,0x7F,0xFF,0xFF,0xF5,0xFE   | rows 1-2 (top edge)
        .byte   0xFF,0xFE,0xFF,0x33,0x70,0x0F   | rows 2-3 (disk label area)
        .byte   0xF8,0x07,0xF7,0x03,0xFF,0xBB   | rows 3-4 (label detail)
        .byte   0xF8,0x70,0x98,0x01,0xFF,0xFF   | rows 4-5 (metal slider area)
        .byte   0xFF,0xFE,0xFF,0x00,0x07,0xFF   | rows 5-6 (disk body)
        .byte   0xFF,0xE0,0x0F,0xFF,0xFF,0xF0   | rows 6-7 (disk body centre)
        .byte   0xFF,0xFF,0xFF,0xFF,0xFF,0xFF   | rows 7-8 (disk body lower)
        .byte   0xFF,0x0F,0x77,0xFF,0xFF,0xEF   | rows 8+ (disk bottom edge)

| ----------------------------------------------------------
| DT_mHappyMac -- happy-face overlay (10 rows x 2 bytes = 20 bytes).
| Drawn on top of ICON_MAC_OUTLINE's screen area to show "boot success".
DT_mHappyMac:
        .byte   0x00,0x00,0x11,0x10,0x11,0x10   | rows 1-3 (blank, eyes, eyes)
        .byte   0x01,0x00,0x01,0x00,0x03,0x00   | rows 4-6 (nose, nose, nose bridge)
        .byte   0x00,0x00,0x08,0x40,0x07,0x80   | rows 7-9 (blank, smile corners)
        .byte   0x00,0x00                       | row 10 (smile arc tail)

| ----------------------------------------------------------
| DT_mSadMac -- sad-face overlay (10 rows x 2 bytes = 20 bytes). Drawn
| when the boot read fails repeatedly. Eyes are X-shapes; frown at bottom.
DT_mSadMac:
        .byte   0x28,0x28,0x10,0x10,0x28,0x28   | rows 1-3 (X eyes L/centre/R)
        .byte   0x00,0x00,0x04,0x80,0x03,0x00   | rows 4-6 (blank, nose, bridge)
        .byte   0x00,0x00,0x0F,0xC0,0x10,0x30   | rows 7-9 (blank, frown top)
        .byte   0x00,0x08                       | row 10 (frown arc)

| ----------------------------------------------------------
| DT_mQMark -- question-mark glyph (15 rows x 2 bytes = 30 bytes).
| Overlay for "?" icon shown during initial disk-search animation.
DT_mQMark:
        .byte   0x00,0x00,0x00,0x00,0x07,0xE0   | rows 1-3 (blank, blank, top arc)
        .byte   0x0F,0xF0,0x0C,0x30,0x0C,0x30   | rows 4-6 (full arc, right side)
        .byte   0x00,0x70,0x00,0xE0,0x01,0xC0   | rows 7-9 (curve, curve, stem)
        .byte   0x01,0x80,0x01,0x80,0x00,0x00   | rows 10-12 (stem, stem, blank)
        .byte   0x01,0x80,0x01,0x80,0x00,0x00   | rows 13-15 (dot, dot, blank)

| ----------------------------------------------------------
| DT_mXMark -- X-mark glyph (15 rows x 2 bytes = 30 bytes). Overlay
| shown when the read fails on a specific drive.
DT_mXMark:
        .byte   0x00,0x00,0x00,0x00,0x10,0x08   | rows 1-3 (blank, blank, outer tips)
        .byte   0x38,0x1C,0x1C,0x38,0x0E,0x70   | rows 4-6 (upper arms, crossing, narrow)
        .byte   0x07,0xE0,0x03,0xC0,0x03,0xC0   | rows 7-9 (centre top, centre, centre bot)
        .byte   0x07,0xE0,0x0E,0x70,0x1C,0x38   | rows 10-12 (widen, lower arms, spread)
        .byte   0x38,0x1C,0x10,0x08,0x00,0x00   | rows 13-15 (outer tips, endpoints, blank)

