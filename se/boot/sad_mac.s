| Startup failure: Sad Mac / Happy Mac (StartFail)
|
| Apple source: StartFail.a. CRITERR shows the Sad Mac with the error
| code after a failed startup test; HAPPYMAC/SADMAC draw the Mac icon with
| the face, PUTSYMBOL a small glyph, PUTICON ($A9CA) decompresses a 32x32
| icon onto the screen.
|
| Mac Plus tree: boot/sad_mac.s (PutIcon etc.) and boot/vectors.s (CritErr).

| ----------------------------------------------------------
| CRITERR - critical error: save regs, erase screen, show sad Mac
| Saves all registers to SERegs ($3FFC80), turns off disk motor,
| erases screen to white, then draws the sad Mac icon with
| error code (D7 = high word, D6 = low word) as hex digits.
CRITERR:
    MOVEM.L	D0-D7/A0-A7,(0x3FFC80).L            | save all regs to SERegs area
    TST.B	(0xDFF1FF).L                          | IWM mtrOff ($DFE1FF + $1000): drive enable off, motor stops
    LEA.L	(0x3FA700).L,A2                       | A2 = screen buffer base (ScreenLow)
    MOVE.W	#0x156,D0                            | D0 = 342 (screen height)
    MOVE.W	#0x200,D1                            | D1 = 512 (screen width)
    MOVE.W	#0x40,D2                             | D2 = 64 (row bytes)
    MOVE.L	#0x5580,D3                           | D3 = 21888 (screen buffer size)
    MOVEA.L	A2,A3                               | A3 = save screen base
    LSR.W	#0x1,D0                               | D0 = 171 (half height)
    MULU.W	D2,D0                                | D0 = 10944 (midpoint offset)
    ADDA.L	D0,A3                                | A3 = screen midpoint
    LSR.W	#0x4,D1                               | D1 = 32 (half width in bytes)
    ADDA.W	D1,A3                                | A3 = center of screen
    MOVEQ.L	#-0x1,D0                            | D0 = $FFFFFFFF (white fill)
    LSR.L	#0x2,D3                               | D3 = 5472 (longwords to fill)
CRITERR_ERASE:
    MOVE.L	D0,(A2)+                             | fill 4 bytes white
    SUBQ.L	#0x1,D3                              | decrement counter
    BHI.B	CRITERR_ERASE                         | loop until screen erased
| Draw sad Mac icon: high 8 hex digits of error code
    MOVEA.L	A3,A2                               | A2 = screen center
    MOVE.L	D2,D0                                | D0 = row bytes
    MULU.W	#0x18,D0                             | D0 = 24 rows * 64 = 1536
    ADDA.L	D0,A2                                | A2 = position for high code
    SUBQ.W	#0x4,A2                              | adjust left by 4 bytes
    MOVE.L	D7,D0                                | D0 = high error code word
    MOVEQ.L	#0x7,D4                             | D4 = 8 hex digits - 1
    LEA.L	CRITERR_DRAW_LOW(PC),A6               | A6 = return after high digits
    JMP	HEX_DIGIT_LOOP(PC)                      | draw 8 high hex digits
CRITERR_DRAW_LOW:
    MOVEA.L	A3,A2                               | A2 = screen center
    MOVE.L	D2,D0                                | D0 = row bytes
    MULU.W	#0x24,D0                             | D0 = 36 rows * 64 = 2304
    ADDA.L	D0,A2                                | A2 = position for low code
    SUBQ.W	#0x4,A2                              | adjust left by 4 bytes
    MOVE.L	D6,D0                                | D0 = low error code word
    MOVEQ.L	#0x7,D4                             | D4 = 8 hex digits - 1
    LEA.L	CRITERR_SHOW_ICON(PC),A6              | A6 = return after low digits
    JMP	HEX_DIGIT_LOOP(PC)                      | draw 8 low hex digits
CRITERR_SHOW_ICON:
    LEA.L	CRITERR_DEADLOOP(PC),A6               | A6 = return after sad Mac
    JMP	SADMAC(PC)                              | draw sad Mac icon
CRITERR_DEADLOOP:
    JMP	TMRESTART(PC)                           | infinite loop (dead Mac)
| ----------------------------------------------------------
| HEX_DIGIT_LOOP - render hex digits to screen
| D0 = value to display, D4 = digit count - 1
| D2 = row bytes, A2 = screen position
| A6 = return address. Uses DT_HEX_FONT glyph table.
HEX_DIGIT_LOOP:
    ROL.L	#0x4,D0                               | rotate next nibble to low 4 bits
    MOVE.W	D0,D5                                | copy for masking
    ANDI.W	#0xF,D5                              | D5 = hex digit value (0-15)
    MULU.W	#0x3,D5                              | 3 bytes per glyph in font
    LEA.L	DT_HEX_FONT(PC,D5.W),A1               | A1 = glyph data for this digit
    MOVEQ.L	#-0x3D,D1                           | D1 = $C3 (background mask)
    MOVEQ.L	#0x2,D3                             | 3 bytes per glyph (6 scanlines)
GLYPH_DRAW_LOOP:
    MOVE.B	(A1),D5                              | read glyph byte
    LSR.W	#0x2,D5                               | shift right: upper pixel pair
    OR.W	D1,D5                                  | merge with background
    MOVE.B	D5,(A2)                              | write to screen (odd line)
    ADDA.W	D2,A2                                | advance one scanline
    MOVE.B	(A1)+,D5                             | read glyph byte again
    LSL.W	#0x2,D5                               | shift left: lower pixel pair
    OR.W	D1,D5                                  | merge with background
    MOVE.B	D5,(A2)                              | write to screen (even line)
    ADDA.W	D2,A2                                | advance one scanline
    DBF.W	D3,GLYPH_DRAW_LOOP                    | loop for 3 byte pairs
    MOVE.W	D2,D1                                | D1 = row bytes
    MULU.W	#0x6,D1                              | D1 = 6 scanlines * row bytes
    SUBA.L	D1,A2                                | move back up 6 scanlines
    ADDQ.W	#0x1,A2                              | advance 1 byte right
    DBF.W	D4,HEX_DIGIT_LOOP                     | loop for all digits
    JMP	(A6)                                    | return via A6
| ----------------------------------------------------------
|
| DT_HEX_FONT - Hex digit font table - 16 glyphs x 3 bytes each for error code display
|
| DT_HEX_FONT - 16 hex-digit glyphs, 3 bytes each (48 bytes total)
| Each glyph is 6 scanlines tall, encoded as 3 byte pairs.
DT_HEX_FONT:
    .byte 0x96,0x42,0x69,0xB3,0xBB,0xB1         | glyphs 0-1
    .byte 0x96,0xED,0xB0,0x0E,0x9E,0x69         | glyphs 2-3
    .byte 0x66,0x60,0xEE,0x07,0x1E,0x69         | glyphs 4-5
    .byte 0x87,0x16,0x69,0x0E,0xDD,0xBB         | glyphs 6-7
    .byte 0x96,0x96,0x69,0x96,0x68,0xE1         | glyphs 8-9
    .byte 0x96,0x60,0x66,0x16,0x16,0x61         | glyphs A-B
    .byte 0x87,0x77,0x78,0x16,0x66,0x61         | glyphs C-D
    .byte 0x07,0x17,0x70,0x07,0x17,0x77         | glyphs E-F
| ----------------------------------------------------------
| HAPPYMAC / SADMAC (sad Mac) - draw Mac icon with face
| HAPPYMAC draws happy face, SADMAC draws sad face.
| Both draw ICON_MAC_OUTLINE first, then overlay face bitmap.
HAPPYMAC:
    LEA.L	DT_mHappyMac(PC),A0                   | A0 = happy face bitmap
    BRA.B	DRAW_MAC_ICON                         | draw Mac icon
SADMAC:
    LEA.L	DT_mSadMac(PC),A0                     | A0 = sad face bitmap
DRAW_MAC_ICON:
    MOVEA.L	A6,A5                               | A5 = save caller return addr
    LEA.L	ICON_MAC_OUTLINE(PC),A4               | A4 = Mac outline icon data
    MOVE.L	A0,D5                                | D5 = save face bitmap ptr
    MOVEA.L	#0x3FCB5E,A2                        | A2 = screen pos for Mac icon
    LEA.L	DRAW_MAC_FACE(PC),A6                  | A6 = return after outline
    JMP	PUTICON(PC)                             | draw Mac outline via PUTICON
DRAW_MAC_FACE:
    MOVEA.L	#0x3FCCDF,A2                        | A2 = screen pos for face
    MOVEA.L	D5,A4                               | A4 = face bitmap data
    MOVEQ.L	#0x9,D2                             | D2 = 10 rows in face
    LEA.L	DRAW_MAC_RETURN(PC),A6                | A6 = return after face
    JMP	PUTSYMBOL(PC)                           | draw face overlay
DRAW_MAC_RETURN:
    JMP	(A5)                                    | return to original caller
| ----------------------------------------------------------
| PUTSYMBOL - draw a 2-byte-wide bitmap to screen
| A4 = bitmap data, A2 = screen destination, D2 = row count - 1.
PUTSYMBOL:
    MOVE.B	(A4)+,(A2)+                          | copy byte 1 of row
    MOVE.B	(A4)+,(A2)+                          | copy byte 2 of row
    ADDA.W	#0x40,A2                             | advance one scanline (64 bytes)
    SUBQ.W	#0x2,A2                              | back up 2 bytes (stay in column)
    DBF.W	D2,PUTSYMBOL                          | loop for all rows
    JMP	(A6)                                    | return via A6
| ----------------------------------------------------------
| PUTICON - draw RLE-compressed icon to screen (32x32 delta-encoded)
| A4 = icon data, A2 = screen destination.
| Control byte: bit=1 means clear (black), bit=0 means copy source.
| After all rows decoded, XOR-propagates rows to reconstruct image.
PUTICON:
    MOVEQ.L	#0xF,D3                             | 16 compressed rows
    MOVEA.L	A2,A0                               | A0 = save start position
    MOVEQ.L	#0x3,D2                             | 4 bytes per scanline
PUTICON_ROW:
    MOVE.W	#0x100,D4                            | sentinel bit in position 8
    MOVE.B	(A4)+,D4                             | read control byte
PUTICON_BYTE:
    LSR.W	#0x1,D4                               | shift out next control bit
    BEQ.B	PUTICON_NEXTROW                       | sentinel reached: end of row
    BCC.B	PUTICON_COPY                          | CC=1: copy source byte
    CLR.B	(A2)+                                 | CC=0: write zero (black)
    BRA.B	PUTICON_ADVANCE                       | next byte
PUTICON_COPY:
    MOVE.B	(A4)+,(A2)+                          | copy icon data byte to screen
PUTICON_ADVANCE:
    DBF.W	D2,PUTICON_BYTE                       | loop for 4 bytes per row
    ADDA.W	#0x40,A2                             | advance one scanline
    SUBQ.W	#0x4,A2                              | stay in same column
    MOVEQ.L	#0x3,D2                             | reset byte counter
    BRA.B	PUTICON_BYTE                          | continue decoding
PUTICON_NEXTROW:
    DBF.W	D3,PUTICON_ROW                        | loop for 16 rows
| XOR-propagate: each row XORed with previous to decode delta encoding
    MOVEA.L	A0,A1                               | A1 = icon start position
    MOVEQ.L	#0x1E,D3                            | 30 more rows to propagate
ICON_XOR_PROPAGATE:
    ADDA.W	#0x40,A1                             | advance to next scanline
    MOVE.L	(A0),D4                              | D4 = previous row data
    EOR.L	D4,(A1)                               | XOR with current = decoded row
    MOVEA.L	A1,A0                               | A0 = current row (for next iter)
    DBF.W	D3,ICON_XOR_PROPAGATE                 | loop all remaining rows
    JMP	(A6)                                    | return via A6
| ----------------------------------------------------------
|
| ICON_MAC_OUTLINE - compressed Macintosh computer outline icon (32x32, delta-encoded)
| Decoded by LOC_34A08 into a 32-pixel-wide icon at SEScrnIcon.
ICON_MAC_OUTLINE:
    .long	0x0057FFFF
    .long	0xD5FFFFFF
    .long	0xFF06F83F
    .long	0xE1FFFF0F
    .long	0x60E3FFFF
    .long	0x8FE00F66
    .long	0xE00FE00F
    .long	0x66E00FE0
    .long	0x0F66E00F
    .long	0xE00F66E0
    .long	0x0FE00F66
    .long	0xE00FE00F
    .long	0x06E00FE3
    .long	0xFFFF8F60
    .long	0xE1FFFF0F
    .long	0xE00F66E0
    .long	0x0FE00F22
    .long	0xE33F0FE3
    .long	0x3F0F66E0
    .long	0x0FE00F06
    .long	0xE00FFFFF
    .long	0xFFFF60F7
    .long	0xFFFFDFF0
    .long	0x1F06F01F
    .long	0xF7FFFFDF
DT_mHappyMac:
    .long	0x00001110
    .long	0x11100100
    .long	0x01000300
    .long	0x00000840
    .long	0x07800000
DT_mSadMac:
    .long	0x28281010
    .long	0x28280000
    .long	0x04800300
    .long	0x00000FC0
    .long	0x10300008

