| Sad Mac Icon Display and Boot-Screen Icon Drawing
|
| Contains the RLE icon decoder (DeviceLoop), Sad Mac / Happy Mac
| entry points, and compressed icon templates for the Macintosh
| outline, floppy disk, and the four symbolic overlays (happy/sad
| faces, question mark, X mark) drawn onto the boot screen.
|
| ShowSadMac is called when the power-on self-test (memtest.s) or a
| later failure condition forces a panic; the numeric error code has
| already been written above the icon by vectors.s:SADMAC_DRAW_CODE.
| The icon templates are delta-encoded (each row XOR-ed against the
| previous one) and decoded row-by-row by DeviceLoop.
|
| References:
| Inside Macintosh II, Ch 12: System Error Handler

| DeviceLoop - RLE-style icon decoder for boot screen icons
|
| Decodes compressed icon data from (A4) into the screen buffer at A2.
| The encoding uses a bit-flag byte: for each bit (LSB first), 1 = copy
| next data byte, 0 = write zero byte. After every 4 bytes, skip to next
| screen row (64-byte stride). Renders 16 rows of icon data.
| After rendering, XOR-propagates the image down 31 additional rows.
|
| Entry: A2 = screen destination, A4 = compressed icon data
| A6 = return address
| Called during boot.
DeviceLoop:
        MOVEQ.L #0xF,D3                         | D3 = 15: 16 rows of icon data to decode
        MOVE.L  A2,A0                           | A0 = save screen start for XOR propagation
        MOVEQ.L #0x3,D2                         | D2 = 3: 4 bytes per row before stride skip
ICON_ROW_LOOP:
        MOVE    #0x100,D4                       | D4 bit 8 = sentinel (detect end of flag byte)
        MOVE.B  (A4)+,D4                        | D4 low byte = run-length flag bits
ICON_BIT_LOOP:
        LSR     #0x1,D4                         | shift out next flag bit into carry
        BEQ.B   ICON_NEXT_ROW                   | sentinel reached: all 8 bits consumed, next row
        BCC.B   ICON_COPY_BYTE                  | carry=0: write zero byte (blank pixel column)
        CLR.B   (A2)+                           | write zero (white) byte to screen
        BRA.B   ICON_BYTE_COUNT                 | continue to byte counter

| ----------------------------------------------------------
|
| ICON_COPY_BYTE - copy one data byte from icon source to screen
|
| Called during boot.
ICON_COPY_BYTE:
        MOVE.B  (A4)+,(A2)+                     | copy icon data byte to screen buffer
ICON_BYTE_COUNT:
        DBF     D2,ICON_BIT_LOOP                | decrement byte counter, continue decoding row
        ADDA    #0x3C,A2                        | skip remaining 60 bytes to next screen row
        MOVEQ.L #0x3,D2                         | reset byte counter for next 4-byte group
        BRA.B   ICON_BIT_LOOP                   | continue decoding current flag byte

| ----------------------------------------------------------
|
| ICON_NEXT_ROW - advance to next icon row; after all rows, XOR-propagate
|
| Called during boot.
ICON_NEXT_ROW:
        DBF     D3,ICON_ROW_LOOP                | next row (16 total)
        MOVE.L  A0,A1                           | A1 = icon start row (source for XOR)
        MOVEQ.L #0x1E,D3                        | D3 = 30: propagate icon down 31 more rows
| XOR each row with the previous to reconstruct delta-encoded image
ICON_XOR_PROPAGATE:
        ADDA    #0x40,A1                        | advance A1 to next screen row (64 bytes/row)
        MOVE.L  (A0),D4                         | D4 = previous row's 4 bytes (32 pixels)
        EOR.L   D4,(A1)                         | XOR previous row into current (delta decode)
        MOVE.L  A1,A0                           | current row becomes source for next iteration
        DBF     D3,ICON_XOR_PROPAGATE           | repeat for 31 rows
        JMP     (A6)                            | return to caller

| ShowSadMac - draw Sad Mac icon on boot screen (test failure)
| return address in A5
ShowSadMac:
        LEA.L   DT_mSadMac(PC),A0               | A0 = sad Mac face expression data
| DRAW_MAC_ICON - common icon drawing: decode Macintosh outline + overlay face
DRAW_MAC_ICON:
        LEA.L   ICON_MAC_OUTLINE(PC),A4         | A4 = compressed Mac outline icon (ICON_MAC_OUTLINE)
        MOVE.L  A0,D7                           | D7 = save face data pointer across DeviceLoop
        MOVE.L  #0x3FCB5E,A2                    | A2 = centered screen position for icon (SEScrnIcon)
        LEA.L   DRAW_FACE_OVERLAY(PC),A6        | return to DRAW_FACE_OVERLAY after drawing outline
        BRA.B   DeviceLoop                      | decode and draw Mac outline icon

| ----------------------------------------------------------
|
| DRAW_FACE_OVERLAY - overlay the face expression onto the Mac icon
|
| Called during boot.
DRAW_FACE_OVERLAY:
        MOVE.L  #0x3FCCDF,A2                    | A2 = screen position for face area (SEScrnFace)
        MOVE.L  D7,A4                           | A4 = face data (happy or sad, saved in D7)
        LEA.L   ICON_DRAW_RETURN(PC),A6         | return to ICON_DRAW_RETURN after drawing face
        BRA     PutSymbol                       | draw 10-row face bitmap into icon

| ----------------------------------------------------------
|
| ICON_DRAW_RETURN - return from icon drawing chain
|
| Called during boot.
ICON_DRAW_RETURN:
        JMP     (A5)                            | return to original caller

| ShowHappyMac - draw Happy Mac icon (all tests passed)
| return address in A5
| Called during boot.
ShowHappyMac:
        LEA.L   DT_mHappyMac(PC),A0             | A0 = happy Mac face expression data
        BRA.B   DRAW_MAC_ICON                   | draw Mac outline + happy face

| PutSymbol - draw a 10-row, 2-byte-wide bitmap at screen position A2
| Entry: A4 = bitmap data (20 bytes: 10 rows x 2 bytes), A2 = screen dest
| A6 = return address
| Called during boot.
PutSymbol:
        MOVEQ.L #0x9,D2                         | D2 = 9: loop 10 rows (0..9)
PUTSYMBOL_LOOP:
        MOVE.B  (A4)+,(A2)+                     | copy left byte of bitmap row to screen
        MOVE.B  (A4)+,(A2)+                     | copy right byte of bitmap row to screen
        ADDA    #0x3E,A2                        | skip to next screen row (64 - 2 bytes written)
        DBF     D2,PUTSYMBOL_LOOP               | repeat for all 10 rows
        JMP     (A6)                            | return to caller

| ----------------------------------------------------------
|
| ICON_MAC_OUTLINE - compressed Macintosh computer outline icon (32x32, delta-encoded)
| Decoded by DeviceLoop into a 32-pixel-wide icon at SEScrnIcon.
ICON_MAC_OUTLINE:
  .byte 0x00,0x57,0xFF,0xFF,0xD5,0xFF           | Mac outline icon rows 1-2 (top edge)
  .byte 0xFF,0xFF,0xFF,0x06,0xF8,0x3F           | rows 2-3 (bezel top corners)
  .byte 0xE1,0xFF,0xFF,0x0F,0x60,0xE3           | rows 3-4 (screen area top)
  .byte 0xFF,0xFF,0x8F,0xE0,0x0F,0x66           | rows 4-5 (screen left/right borders)
  .byte 0xE0,0x0F,0xE0,0x0F,0x66,0xE0           | rows 5-6 (screen interior)
  .byte 0x0F,0xE0,0x0F,0x66,0xE0,0x0F           | rows 6-7 (screen interior)
  .byte 0xE0,0x0F,0x66,0xE0,0x0F,0xE0           | rows 7-8 (screen interior)
  .byte 0x0F,0x66,0xE0,0x0F,0xE0,0x0F           | rows 8-9 (screen interior)
  .byte 0x06,0xE0,0x0F,0xE3,0xFF,0xFF           | rows 9-10 (screen bottom)
  .byte 0x8F,0x60,0xE1,0xFF,0xFF,0x0F           | rows 10-11 (bezel divider)
  .byte 0xE0,0x0F,0x66,0xE0,0x0F,0xE0           | rows 11-12 (floppy slot area)
  .byte 0x0F,0x22,0xE3,0x3F,0x0F,0xE3           | rows 12-13 (floppy slot detail)
  .byte 0x3F,0x0F,0x66,0xE0,0x0F,0xE0           | rows 13-14 (lower bezel)
  .byte 0x0F,0x06,0xE0,0x0F,0xFF,0xFF           | rows 14-15 (bezel bottom)
  .byte 0xFF,0xFF,0x60,0xF7,0xFF,0xFF           | rows 15-16 (base top)
  .byte 0xDF,0xF0,0x1F,0x06,0xF0,0x1F           | rows 16+ (base front)
  .byte 0xF7,0xFF,0xFF,0xDF                     | base bottom edge

ICON_DISK:
  .byte 0x00,0x7F,0xFF,0xFF,0xF5,0xFE           | disk icon rows 1-2 (top edge)
  .byte 0xFF,0xFE,0xFF,0x33,0x70,0x0F           | rows 2-3 (disk label area)
  .byte 0xF8,0x07,0xF7,0x03,0xFF,0xBB           | rows 3-4 (disk label detail)
  .byte 0xF8,0x70,0x98,0x01,0xFF,0xFF           | rows 4-5 (metal slider area)
  .byte 0xFF,0xFE,0xFF,0x00,0x07,0xFF           | rows 5-6 (disk body)
  .byte 0xFF,0xE0,0x0F,0xFF,0xFF,0xF0           | rows 6-7 (disk body center)
  .byte 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF           | rows 7-8 (disk body lower)
  .byte 0xFF,0x0F,0x77,0xFF,0xFF,0xEF           | rows 8+ (disk bottom edge)

DT_mHappyMac:
  .byte 0x00,0x00,0x11,0x10,0x11,0x10           | rows 1-3: blank, eyes open, eyes
  .byte 0x01,0x00,0x01,0x00,0x03,0x00           | rows 4-6: nose, nose, nose bridge
  .byte 0x00,0x00,0x08,0x40,0x07,0x80           | rows 7-8: blank, smile corners
  .byte 0x00,0x00                               | rows 9-10: smile arc, blank

DT_mSadMac:
  .byte 0x28,0x28,0x10,0x10,0x28,0x28           | rows 1-3: X-eyes left, X-center, X-right
  .byte 0x00,0x00,0x04,0x80,0x03,0x00           | rows 4-6: blank, nose, nose bridge
  .byte 0x00,0x00,0x0F,0xC0,0x10,0x30           | rows 7-8: blank, frown top
  .byte 0x00,0x08                               | rows 9-10: frown arc, blank

DT_mQMark:
  .byte 0x00,0x00,0x00,0x00,0x07,0xE0           | rows 1-3: blank, blank, top arc
  .byte 0x0F,0xF0,0x0C,0x30,0x0C,0x30           | rows 4-6: full arc, right side, right
  .byte 0x00,0x70,0x00,0xE0,0x01,0xC0           | rows 7-9: curve down, curve, stem
  .byte 0x01,0x80,0x01,0x80,0x00,0x00           | rows 10-12: stem, stem, blank
  .byte 0x01,0x80,0x01,0x80,0x00,0x00           | rows 13-15: dot, dot, blank

DT_mXMark:
  .byte 0x00,0x00,0x00,0x00,0x10,0x08           | rows 1-3: blank, blank, outer tips
  .byte 0x38,0x1C,0x1C,0x38,0x0E,0x70           | rows 4-6: upper arms, crossing, narrowing
  .byte 0x07,0xE0,0x03,0xC0,0x03,0xC0           | rows 7-9: center top, center, center bottom
  .byte 0x07,0xE0,0x0E,0x70,0x1C,0x38           | rows 10-12: widening, lower arms, spreading
  .byte 0x38,0x1C,0x10,0x08,0x00,0x00           | rows 13-15: outer tips, endpoints, blank
