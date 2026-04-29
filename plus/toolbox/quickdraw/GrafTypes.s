| QuickDraw equates and structure offsets
| From GrafTypes.a (Bill Atkinson, 1983)

| -----------------------------------------------------------------
|
| --> GRAFTYPES.TEXT
|
| QUICKDRAW TYPE DECLARATIONS, USED BY ALL GRAPHICS ROUTINES
|
.equ NIL, 0                                     | IMPLEMENTATION VALUE OF NIL

| -----------------------------------------------
|
| QuickDraw VERBS:
|
.equ FRAME, 0                                   | DRAW OUTLINE
.equ PAINT, 1                                   | FILL WITH PEN PATTERN
.equ ERASE, 2                                   | FILL WITH BACKGROUND
.equ INVERT, 3                                  | XOR PIXELS
.equ FILL, 4                                    | FILL WITH GIVEN PATTERN

| -----------------------------------------------
|
| QuickDraw transfer MODES:
|
.equ SRCCOPY, 0                                 | SRC -> DST
.equ SRCOR, 1                                   | SRC OR DST -> DST
.equ SRCXOR, 2                                  | SRC XOR DST -> DST
.equ SRCBIC, 3                                  | (NOT SRC) AND DST -> DST
.equ NOTSRCCOPY, 4                              | NOT SRC -> DST
.equ NOTSRCOR, 5                                | (NOT SRC) OR DST -> DST
.equ NOTSRCXOR, 6                               | (NOT SRC) XOR DST -> DST
.equ NOTSRCBIC, 7                               | SRC AND DST -> DST
.equ PATCOPY, 8                                 | PAT -> DST
.equ PATOR, 9                                   | PAT OR DST -> DST
.equ PATXOR, 10                                 | PAT XOR DST -> DST
.equ PATBIC, 11                                 | (NOT PAT) AND DST -> DST
.equ NOTPATCOPY, 12                             | NOT PAT -> DST
.equ NOTPATOR, 13                               | (NOT PAT) OR DST -> DST
.equ NOTPATXOR, 14                              | (NOT PAT) XOR DST -> DST
.equ NOTPATBIC, 15                              | PAT AND DST -> DST

| -----------------------------------------------
|
| QuickDraw Color Separation:
|
.equ NORMALBIT, 0                               | normal screen mapping
.equ INVERSEBIT, 1                              | inverse screen mapping
.equ REDBIT, 4                                  | RGB additive mapping
.equ GREENBIT, 3                                | for photos from screen
.equ BLUEBIT, 2                                 | blue plane
.equ CYANBIT, 8                                 | CMYBk subtractive mapping
.equ MAGENTABIT, 7                              | for ink jet printer
.equ YELLOWBIT, 6                               | yellow plane
.equ BLACKBIT, 5                                | black plane

.equ BLACKCOLOR, 33                             | color value for black
.equ WHITECOLOR, 30                             | color value for white
.equ REDCOLOR, 205                              | color value for red
.equ GREENCOLOR, 341                            | color value for green
.equ BLUECOLOR, 409                             | color value for blue
.equ CYANCOLOR, 273                             | color value for cyan
.equ MAGENTACOLOR, 137                          | color value for magenta
.equ YELLOWCOLOR, 69                            | color value for yellow

| -----------------------------------------------
|
| OFFSETS WITHIN A POINT:
|
.equ V, 0                                       | WORD
.equ H, 2                                       | WORD

| -----------------------------------------------
|
| OFFSETS WITHIN A RECT:
|
.equ TOPLEFT, 0                                 | POINT
.equ BOTRIGHT, 4                                | POINT

.equ TOP, 0                                     | INTEGER
.equ LEFT, 2                                    | INTEGER
.equ BOTTOM, 4                                  | INTEGER
.equ RIGHT, 6                                   | INTEGER

| -----------------------------------------------
|
| OFFSETS WITHIN A BITMAP:
|
.equ BASEADDR, 0                                | LONG
.equ ROWBYTES, 4                                | WORD
.equ BOUNDS, 6                                  | RECT

| -----------------------------------------------
|
| OFFSETS WITHIN A CURSOR:
|
.equ DATA, 0                                    | 16 WORDS
.equ MASK, 32                                   | 16 WORDS
.equ HOTSPOT, 64                                | POINT

| -----------------------------------------------
|
| OFFSETS WITHIN A POLYGON:
|
.equ POLYSIZE, 0                                | WORD, TOTAL BYTES
.equ POLYBBOX, 2                                | RECT
.equ POLYPOINTS, 10                             | ARRAY[0..0] OF Point

| -----------------------------------------------
|
| OFFSETS WITHIN A REGION:
|
.equ RGNSIZE, 0                                 | WORD, TOTAL BYTES
.equ RGNBBOX, 2                                 | RECT
.equ RGNDATA, 10                                | START OF RGN DATA

| -----------------------------------------------
|
| OFFSETS WITHIN A PICTURE:
|
.equ PICSIZE, 0                                 | WORD, TOTAL BYTES
.equ PICFRAME, 2                                | RECT
.equ PICDATA, 10                                | START OF BYTE CODES

| -----------------------------------------------
|
| OFFSETS WITHIN QDProcs RECORD:
|
.equ TEXTPROC, 0                                | PROCPTR
.equ LINEPROC, TEXTPROC+4                       | PROCPTR
.equ RECTPROC, LINEPROC+4                       | PROCPTR
.equ RRECTPROC, RECTPROC+4                      | PROCPTR
.equ OVALPROC, RRECTPROC+4                      | PROCPTR
.equ ARCPROC, OVALPROC+4                        | PROCPTR
.equ POLYPROC, ARCPROC+4                        | PROCPTR
.equ RGNPROC, POLYPROC+4                        | PROCPTR
.equ BITSPROC, RGNPROC+4                        | PROCPTR
.equ COMMENTPROC, BITSPROC+4                    | PROCPTR
.equ TXMEASPROC, COMMENTPROC+4                  | PROCPTR
.equ GETPICPROC, TXMEASPROC+4                   | PROCPTR
.equ PUTPICPROC, GETPICPROC+4                   | PROCPTR

| -----------------------------------------------
|
| OFFSETS WITHIN A GRAFPORT:
|
.equ DEVICE, 0                                  | WORD
| PORTBITS -- call close hook.
.equ PORTBITS, DEVICE+2                         | BITMAP
.equ PORTRECT, PORTBITS+14                      | RECT
.equ VISRGN, PORTRECT+8                         | RGNPTR
.equ CLIPRGN, VISRGN+4                          | RGNPTR
.equ BKPAT, CLIPRGN+4                           | PATTERN
.equ FILLPAT, BKPAT+8                           | PATTERN
.equ PNLOC, FILLPAT+8                           | POINT
.equ PNSIZE, PNLOC+4                            | POINT
.equ PNMODE, PNSIZE+4                           | WORD
.equ PNPAT, PNMODE+2                            | PATTERN
.equ PNVIS, PNPAT+8                             | WORD
.equ TXFONT, PNVIS+2                            | WORD
.equ TXFACE, TXFONT+2                           | WORD
.equ TXMODE, TXFACE+2                           | WORD
.equ TXSIZE, TXMODE+2                           | WORD
.equ SPEXTRA, TXSIZE+2                          | Fixed Point
.equ FGCOLOR, SPEXTRA+4                         | LONG
.equ BKCOLOR, FGCOLOR+4                         | LONG
.equ COLRBIT, BKCOLOR+4                         | WORD
.equ PATSTRETCH, COLRBIT+2                      | WORD
.equ PICSAVE, PATSTRETCH+2                      | handle
.equ RGNSAVE, PICSAVE+4                         | handle
.equ POLYSAVE, RGNSAVE+4                        | handle
.equ GRAFPROCS, POLYSAVE+4                      | Pointer
.equ PORTREC, GRAFPROCS+4                       | SIZE OF A GRAFPORT
.equ PORTBOUNDS, PORTBITS+BOUNDS                | PORTBITS.BOUNDS OFFSET

| -----------------------------------------------------
|
| OFFSETS IN A REGION STATE RECORD:
|
.equ RGNPTR, 0                                  | LONG
.equ DATAPTR, RGNPTR+4                          | LONG
.equ SCANBUF, DATAPTR+4                         | LONG
.equ SCANSIZE, SCANBUF+4                        | WORD
.equ THISV, SCANSIZE+2                          | WORD
.equ NEXTV, THISV+2                             | WORD
.equ MINH, NEXTV+2                              | WORD
.equ MAXH, MINH+2                               | WORD
.equ LEFTH, MAXH+2                              | WORD
.equ RGNREC, LEFTH+2                            | SIZE OF A REGION RECORD

| -----------------------------------------------------
|
| Offsets in a PicSave record:
|
.equ THEPIC, 0                                  | PICHANDLE
.equ PICMAX, THEPIC+4                           | LongInt
.equ PICINDEX, PICMAX+4                         | LongInt
.equ PICCLIPRGN, PICINDEX+4                     | RgnHandle
.equ PICBKPAT, PICCLIPRGN+4                     | Pattern
.equ PICTXFONT, PICBKPAT+8                      | WORD
.equ PICTXFACE, PICTXFONT+2                     | Style
.equ PICTXMODE, PICTXFACE+2                     | WORD
.equ PICTXSIZE, PICTXMODE+2                     | WORD
.equ PICSPEXTRA, PICTXSIZE+2                    | Fixed Point
.equ PICTXNUMER, PICSPEXTRA+4                   | Point
.equ PICTXDENOM, PICTXNUMER+4                   | Point
.equ PICTXLOC, PICTXDENOM+4                     | Point
.equ PICPNLOC, PICTXLOC+4                       | Point
.equ PICPNSIZE, PICPNLOC+4                      | Point
.equ PICPNMODE, PICPNSIZE+4                     | WORD
.equ PICPNPAT, PICPNMODE+2                      | Pattern
.equ PICFILLPAT, PICPNPAT+8                     | Pattern
.equ PICTHERECT, PICFILLPAT+8                   | Rect
.equ PICOVSIZE, PICTHERECT+8                    | Point
.equ PICORIGIN, PICOVSIZE+4                     | Point
.equ PICFGCOLOR, PICORIGIN+4                    | Long
.equ PICBKCOLOR, PICFGCOLOR+4                   | Long

.equ PICSAVEREC, PICBKCOLOR+4                   | total size in bytes

| -----------------------------------------------------
|
| QuickDraw GLOBAL VARIABLES:
|
| 52(A5) CONTAINS A POINTER TO THEPORT.
| ALL OTHER GLOBAL VARIABLES ARE EXPRESSED RELATIVE TO THEPORT.
|
.equ GRAFGLOBALS, 0                             | A5 OFFSET TO GLOBALPTR

| -----------------------------------------------------------
|
| QuickDraw PUBLIC GLOBAL VARIABLES:
|
.equ THEPORT, 0                                 | GrafPtr

| QuickDraw Patterns: 8 bytes each (8x8 pixels, 1 bit/pixel, MSB=left)
| Tiled to fill areas. Used for pen, background, and fill operations.
| Stored in QD globals at negative offsets from A4 (grafGlobals pointer).
.equ WHITE, THEPORT-8                           | Pattern: 0x00 x8 (all white)
.equ BLACK, WHITE-8                             | Pattern: 0xFF x8 (all black)
.equ GRAY, BLACK-8                              | Pattern: 0xAA,0x55 (50% checkerboard)
.equ LTGRAY, GRAY-8                             | Pattern: 0x88,0x22 (25% dots)
.equ DKGRAY, LTGRAY-8                           | Pattern: 0x77,0xDD (75% dense)
.equ ARROW, DKGRAY-68                           | Cursor (32B data + 32B mask + 4B hotspot)
.equ SCREENBITS, ARROW-14                       | BitMap
.equ RANDSEED, SCREENBITS-4                     | LONGINT

| ------------------------------------------------------------
|
| QuickDraw private global variables:
|
.equ WIDEOPEN, RANDSEED-4                       | RgnHandle
.equ WIDEMASTER, WIDEOPEN-4                     | RGNPTR
.equ WIDEDATA, WIDEMASTER-10                    | Fake Region
.equ RGNBUF, WIDEDATA-4                         | PointsHandle
.equ RGNINDEX, RGNBUF-2                         | INTEGER
.equ RGNMAX, RGNINDEX-2                         | INTEGER
.equ PLAYPIC, RGNMAX-4                          | Long
.equ QDSPARE0, PLAYPIC-2                        | unused word
.equ THEPOLY, QDSPARE0-4                        | POLYHANDLE
.equ POLYMAX, THEPOLY-2                         | INTEGER
.equ PATALIGN, POLYMAX-4                        | Point
.equ FIXTXWID, PATALIGN-4                       | Fixed Point
.equ FONTPTR, FIXTXWID-4                        | long, ^FMOutput record
.equ PLAYINDEX, FONTPTR-4                       | long
.equ QDSPARE3, PLAYINDEX-2                      | unused word
.equ QDSPARE4, QDSPARE3-2                       | unused word
.equ QDSPARE5, QDSPARE4-2                       | unused word
.equ QDSPARE6, QDSPARE5-2                       | unused word
.equ QDSPARE7, QDSPARE6-2                       | unused word
.equ QDSPARE8, QDSPARE7-2                       | unused word
.equ QDSPARE9, QDSPARE8-2                       | unused word
.equ QDSPAREA, QDSPARE9-2                       | unused word
.equ QDSPAREB, QDSPAREA-2                       | unused word
.equ QDSPAREC, QDSPAREB-2                       | unused word
.equ QDSPARED, QDSPAREC-2                       | unused word
.equ LASTGRAFGLOB, QDSPARED                     | OFFSET OF LAST QD GLOBAL
.equ GRAFSIZE, 4-LASTGRAFGLOB                   | total size in bytes

| ----------------------------------------------
|
| Trap Macros used by QuickDraw:
|

| .MACRO _LongMul
| .WORD $A867
| .MACRO _FixMul
| .WORD $A868
| .MACRO _FixRatio
| .WORD $A869
| .MACRO _NewHandle
| .WORD $A122
| .MACRO _DisposHandle
| .WORD $A023
| .MACRO _SetHandleSize
| .WORD $A024
| .MACRO _GetHandleSize
| .WORD $A025
| .MACRO _HLock
| .WORD $A029
| .MACRO _HUnlock
| .WORD $A02A
| .MACRO _GetScrnBits
| .WORD $A833 ;new trap number
| .MACRO _StackAvail
| MOVE.L SP,D0 ;copy stack pointer
| SUB.L $114,D0 ;subtract HeapEnd for stack avail
| .MACRO _SwapFont
| MOVE.L $8E0,A0 ;get pointer to FMSwapFont
| JSR (A0) ;call font manager
