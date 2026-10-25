| CURS resources -- the standard cursors
|
| CURS 2 (crossCursor), 3 (plusCursor), 1 (iBeamCursor), 4 (watchCursor),
| in ROM order. Each is 68 bytes:
| Bytes 0-31: cursor image (16x16 bitmap, 2 bytes/row)
| Bytes 32-63: cursor mask (16x16 bitmap, 2 bytes/row)
| Bytes 64-65: hotspot.v (INTEGER)
| Bytes 66-67: hotspot.h (INTEGER)

| resource header
        .long   0xC000004C                      | ROM resource header: tag $C0, physical size $4C (8 + $44)
        .long   0x00000080                      | relative handle: master pointer at ROM zone + $80
_CURS_2_:
  .byte 0x04,0x00,0x04,0x00,0x04,0x00           | image rows 0-2: vertical bar
  .byte 0x04,0x00,0x04,0x00,0xFF,0xE0           | image rows 3-5: bar + horiz stroke
  .byte 0x04,0x00,0x04,0x00,0x04,0x00           | image rows 6-8: vertical bar
  .byte 0x04,0x00,0x04,0x00,0x04,0x00           | image rows 9-11: vertical bar (end)
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | img rows 12-14 + mask row 0: blank
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | mask rows 0-2: empty (transparent)
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | mask rows 3-5: empty
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | mask rows 6-8: empty
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | mask rows 9-11: empty
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | mask rows 12-14: empty
  .byte 0x00,0x00,0x00,0x00,0x00,0x05           | mask row 15 + hotspot.v = 5
  .byte 0x00,0x05                               | hotspot.h = 5

| end of resource : 'CURS' 2
        .long   0xC000004C                      | ROM resource header: tag $C0, physical size $4C (8 + $44)
        .long   0x00000084                      | relative handle: master pointer at ROM zone + $84

| resource : 'CURS' 3
| PlusCursor (3D plus sign for precision positioning)
| Standard cursor ID 3: plusCursor
| 3D beveled plus sign used for cell selection
| Mask outlines entire plus shape
| Hotspot at (8,8) = center of plus
_CURS_3_:
  .byte 0x00,0x00,0x07,0xC0,0x04,0x60           | image rows 0-2: top of vertical arm
  .byte 0x04,0x60,0x04,0x60,0x7C,0x7C           | image rows 3-5: arm + horiz top
  .byte 0x43,0x86,0x42,0x86,0x43,0x86           | image rows 6-8: center cross area
  .byte 0x7C,0x7E,0x3C,0x7E,0x04,0x60           | image rows 9-11: horiz bottom + arm
  .byte 0x04,0x60,0x07,0xE0,0x03,0xE0           | image rows 12-14: bottom of vert arm
  .byte 0x00,0x00,0x0F,0xC0,0x0F,0xE0           | img row 15 + mask rows 0-1: top mask
  .byte 0x0F,0xF0,0x0F,0xF0,0xFF,0xFF           | mask rows 2-4: arm + horiz mask
  .byte 0xFF,0xFE,0xFC,0x7F,0xFC,0x7F           | mask rows 5-7: full cross mask
  .byte 0xFC,0x7F,0xFF,0xFF,0x7F,0xFF           | mask rows 8-10: full cross mask
  .byte 0x7F,0xFF,0x0F,0xF0,0x0F,0xF0           | mask rows 11-13: horiz + arm mask
  .byte 0x07,0xF0,0x03,0xE0,0x00,0x08           | mask rows 14-15 + hotspot.v = 8
  .byte 0x00,0x08                               | hotspot.h = 8

| end of resource : 'CURS' 3
        .long   0xC000004C                      | ROM resource header: tag $C0, physical size $4C (8 + $44)
        .long   0x00000088                      | relative handle: master pointer at ROM zone + $88

| resource : 'CURS' 1
| IBeamCursor (I-beam text insertion cursor)
| Standard cursor ID 1: iBeamCursor
| Vertical bar with serifs top/bottom for text editing
| Mask is empty (transparent background)
| Hotspot at (4,7) = midpoint of vertical bar
_CURS_1_:
  .byte 0x0C,0x60,0x02,0x80,0x01,0x00           | image rows 0-2: top serifs + stem
  .byte 0x01,0x00,0x01,0x00,0x01,0x00           | image rows 3-5: vertical stem
  .byte 0x01,0x00,0x01,0x00,0x01,0x00           | image rows 6-8: vertical stem
  .byte 0x01,0x00,0x01,0x00,0x01,0x00           | image rows 9-11: vertical stem
  .byte 0x01,0x00,0x01,0x00,0x02,0x80           | image rows 12-14: stem + narrowing
  .byte 0x0C,0x60,0x00,0x00,0x00,0x00           | img row 15: bottom serifs + mask 0-1
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | mask rows 2-4: empty (transparent)
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | mask rows 5-7: empty
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | mask rows 8-10: empty
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | mask rows 11-13: empty
  .byte 0x00,0x00,0x00,0x00,0x00,0x04           | mask rows 14-15 + hotspot.v = 4
  .byte 0x00,0x07                               | hotspot.h = 7

| end of resource : 'CURS' 1
        .long   0xC000004C                      | ROM resource header: tag $C0, physical size $4C (8 + $44)
        .long   0x0000008C                      | relative handle: master pointer at ROM zone + $8C

| resource : 'CURS' 4
| WatchCursor (wristwatch for busy/wait state)
| Standard cursor ID 4: watchCursor
| Wristwatch icon shown during lengthy operations
| Mask is filled rectangle around watch body
| Hotspot at (8,8) = center of watch face
_CURS_4_:
  .byte 0x3F,0x00,0x3F,0x00,0x3F,0x00           | image rows 0-2: watchband top
  .byte 0x3F,0x00,0x40,0x80,0x84,0x40           | image rows 3-5: band + case top
  .byte 0x84,0x40,0x84,0x60,0x9C,0x60           | image rows 6-8: hour/minute hands
  .byte 0x80,0x40,0x80,0x40,0x40,0x80           | image rows 9-11: case bottom
  .byte 0x3F,0x00,0x3F,0x00,0x3F,0x00           | image rows 12-14: watchband bottom
  .byte 0x3F,0x00,0x3F,0x00,0x3F,0x00           | img row 15 + mask rows 0-1: band
  .byte 0x3F,0x00,0x3F,0x00,0x7F,0x80           | mask rows 2-4: band + case outline
  .byte 0xFF,0xC0,0xFF,0xC0,0xFF,0xC0           | mask rows 5-7: full case mask
  .byte 0xFF,0xC0,0xFF,0xC0,0xFF,0xC0           | mask rows 8-10: full case mask
  .byte 0x7F,0x80,0x3F,0x00,0x3F,0x00           | mask rows 11-13: case + band
  .byte 0x3F,0x00,0x3F,0x00,0x00,0x08           | mask rows 14-15 + hotspot.v = 8
  .byte 0x00,0x08                               | hotspot.h = 8

| end of resource : 'CURS' 4
