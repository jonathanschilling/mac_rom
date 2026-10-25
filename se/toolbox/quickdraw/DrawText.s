| --------------------------------------------------------------
|
| --> DRAWTEXT.TEXT
|
| QuickDraw Character Generator
|
| Completely reworked 29 Apr 85 by Bill Atkinson to get 50% speed up.
| Takes advantage of optional height table at end of font.

| .PROC DrText,4
| .REF RightMask,MaskTab,RSect,ShieldCursor,ShowCursor
| .REF StdTxMeas,RectInRgn,MapRect,StretchBits,TrimRect
| ------------------------------------------------------------
|
| PROCEDURE DrText(count: INTEGER; textAddr: Ptr; numer,denom: Point);
|
| DRAWS CHARACTERS INTO THE CURRENT PORT'S BITMAP.
| THE FONT AND ATTRIBUTES ARE GIVEN IN THE CURRENT PORT'S CHARSTYLE.
| Called during boot.
| -------------------------------------------
|
| KERNED STRIKE FONT FORMAT OFFSETS (relative to font handle):
|   FORMAT 0,  MINCHAR 2,  MAXCHAR 4,  MAXWD 6,  FBBOX 8,  FBBOY 10,
|   FBBDX 12, FBBDY 14,    LENGTH 16, ASCENT 18, DESCENT 20, XOFFSET 22,
|   RASTER 24
|
| ------------------------------------------------------
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|   COUNT  +0x14 word, TEXTADDR +0x10 long, NUMER +0xC long-point,
|   DENOM  +0x8  long-point.
|
| A6 OFFSETS OF LOCAL VARIABLES AFTER LINK (-0xC4 frame):
|   SAVESTK    -0x004 long      (saved stack pointer)
|   TEXTRECT   -0x00C..-0x009 rect
|   TEXTR2     -0x014..-0x011 rect (mapped/stretched)
|   MINRECT    -0x01C..-0x019 rect (textrect ^ port ^ visrgn ^ cliprgn)
|   BUFEND     -0x020 long, BUFSTART -0x024 long
|   BUFSIZE    -0x026 word, BUFROW -0x028 word, BUFLEFT -0x02A word
|   BUF2START  -0x02E long, BUF2END  -0x032 long
|   HEIGHT     -0x034 word
|   SRCBITS    -0x042..-0x035 bitmap (14 bytes)
|   DSTBITS    -0x050..-0x043 bitmap (14 bytes)
|   FAKERGN    -0x05A..-0x051 region (10 bytes)
|   FAKEPTR    -0x05E long      (fake master ptr)
|   SRCADDR    -0x062 long
|   SRCROW     -0x064 word
|   FASTFLAG   -0x066 byte
|   PENLOC     -0x06A point
|   SRCPTR     -0x06E long, DSTPTR  -0x072 long
|   STRETCH    -0x074 byte      (boolean)
|   FROMRECT   -0x07C rect, TORECT  -0x084 rect
|   SRCRECT    -0x08C rect, DSTRECT -0x094 rect
|   SPWIDTH    -0x098 fixed, CHARLOC -0x09C fixed
|   INFO       -0xA4 four-word FontInfo block
|   HEIGHTAB   -0xA8 long, WIDTAB -0xAC long, LOCTAB -0xB0 long
|   TOPHT      -0xB2 word
|   HEIGHTFLAG -0xB4 byte
|   MAXMIN     -0xB6 word, MINCH -0xB8 word
|   SAVEA5     -0xBC long
|   NUMER2     -0xC0 point, DENOM2 -0xC4 point (saved original scale)
|
DRTEXT:
    LINK	A6,#-0xC4                              | SET UP STACK FRAME
    MOVEM.L	D0-D7/A1-A4,-(A7)                   | SAVE REGS
    MOVE.L	A7,-0x4(A6)                          | REMEMBER WHERE STACK WAS
    MOVE.L	A5,-0xBC(A6)                         | REMEMBER GLOBAL PTR
    MOVEA.L	(A5),A4                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A4),A3                             | GET CURRENT GRAFPORT
    MOVE.L	0xC(A6),-0xC0(A6)                    | SAVE ORIGINAL NUMER
    MOVE.L	0x8(A6),-0xC4(A6)                    | SAVE ORIGINAL DENOM
|
| Call StdTxMeas to swap font and measure width.
|
    CLR.W	-(A7)                                 | ROOM FOR FCN RESULT
    MOVE.W	0x14(A6),-(A7)                       | PUSH COUNT
    BLE.W	NOSHAD_EXIT                           | QUIT IF COUNT <= 0
| STACK CLEANED UP BY SAVESTK
    MOVE.L	0x10(A6),-(A7)                       | PUSH TEXTADDR
    PEA.L	0xC(A6)                               | PUSH VAR NUMER
    PEA.L	0x8(A6)                               | PUSH VAR DENOM
    PEA.L	-0xA4(A6)                             | PUSH VAR INFO
    MOVEA.L	(0x11B4).W,A0                       | _StdTxMeas (txMeasProc)
    JSR	(A0)                                    | CALL TXMEASPROC TO MEASURE WIDTH
    MOVE.W	(A7)+,D1                             | POP UNSCALED WIDTH RESULT
|
| StdTxMeas also stashes FMOutPtr in QD global FONTPTR,
| and unscaled fixed point text width inn FixTxWid.
|
    MOVEA.L	-0xB0(A4),A4                        | POINT TO FMOUTPUT (FONTPTR)
    MOVEA.L	0x2(A4),A2                          | GET FONT HANDLE
    MOVEA.L	(A2),A2                             | DE-REFERENCE IT
    MOVE.W	0xE(A2),-0xB2(A6)                    | INIT TOPHT IN CASE OLD FONT
    BTST	#0x0,0x1(A2)                           | DOES FONT HAVE HEIGHT TABLE ?
    SNE.B	-0xB4(A6)                             | SAVE COMPUTED VALUE
|
| Setup textRect, the rectangle bounding the entire string.
|
    MOVE.L	0x30(A3),D2                          | GET PEN LOCATION
    MOVE.L	D2,-0x6A(A6)                         | SAVE COMPUTED VALUE (PENLOC)
    MOVE.W	D2,-0xA(A6)                          | SAVE TO TEXTRECT+LEFT
    ADD.W	D1,D2                                 | ADD WIDTH TO PEN H
    MOVEQ.L	#0x7,D0                             | get mode mask
    AND.W	0x48(A3),D0                           | is txMode = srcCopy ?
    BEQ.B	NOSLOP                                | yes, don't add slop
    CMPI.W	#0x3,D0                              | IS TXMODE = SRCBIC ?
    BGT.B	NOSLOP                                | yes, don't add slop
    ADDI.W	#0x20,D2                             | ADD SLOP FOR ITALIC OVERHANG
NOSLOP:
    MOVE.W	D2,-0x6(A6)                          | SAVE TO TEXTRECT+RIGHT
    SWAP.W	D2                                   | GET PNLOC.V
    SUB.W	0x12(A2),D2                           | SUBTRACT ASCENT
    MOVE.W	D2,-0xC(A6)                          | SAVE TO TEXTRECT+TOP
    ADD.W	0xE(A2),D2                            | ADD HEIGHT
    MOVE.W	D2,-0x8(A6)                          | SAVE TO TEXTRECT+BOTTOM
    MOVE.L	-0xC(A6),-0x14(A6)                   | COPY BOUNDS TO EXTRA RECT
    MOVE.L	-0x8(A6),-0x10(A6)                   | COPY BOUNDS TO EXTRA RECT
|
| Check for stretching
|
    MOVE.L	0xC(A6),D0                           | GET NUMERATOR
    CMP.L	0x8(A6),D0                            | ARE WE STRETCHING ?
    SNE.B	-0x74(A6)                             | SAVE BOOLEAN RESULT
    BEQ.B	NOSTRCH                               | CONTINUE IF NOT STRETCHING
|
| We will be stretching. Setup fromRect and toRect and map textR2.
|
    MULU.W	D0,D1                                | MULT WIDTH BY NUMER.H
    DIVU.W	0xA(A6),D1                           | DIVIDE BY DENOM+H
    MOVE.L	-0x6A(A6),D0                         | GET PENLOC
    MOVE.L	D0,-0x84(A6)                         | SAVE TO TORECT
    ADD.W	0xE(A6),D0                            | ADD NUMER+H
    MOVE.W	D0,-0x7E(A6)                         | SAVE TO TORECT+RIGHT
    SWAP.W	D0                                   | GET PENLOC.V
    ADD.W	0xC(A6),D0                            | ADD NUMER
    MOVE.W	D0,-0x80(A6)                         | SAVE TO TORECT+BOTTOM
    MOVE.L	-0x6A(A6),D0                         | GET PENLOC
    MOVE.L	D0,-0x7C(A6)                         | SAVE TO FROMRECT
    ADD.W	0xA(A6),D0                            | ADD DENOM+H
    MOVE.W	D0,-0x76(A6)                         | SAVE TO FROMRECT+RIGHT
    SWAP.W	D0                                   | GET PENLOC.V
    ADD.W	0x8(A6),D0                            | ADD DENOM
    MOVE.W	D0,-0x78(A6)                         | SAVE TO FROMRECT+BOTTOM
    PEA.L	-0x14(A6)                             | PUSH TEXTR2
    PEA.L	-0x7C(A6)                             | PUSH FROMRECT
    PEA.L	-0x84(A6)                             | PUSH TORECT
    JSR	MAPRECT(PC)                             | MAP TEXTR2 (PRESERVES ALL REGS)
NOSTRCH:
    ADD.W	D1,0x32(A3)                           | BUMP PEN BY (SCALED) TEXT WIDTH (PNLOC+H)
|
| Quit if the pen is hidden
|
    TST.W	0x42(A3)                              | IS PNVIS < 0 ?
    BLT.W	NOSHAD_EXIT                           | YES, QUIT
|
| Calc minRect: the intersection of textRect, bitMap bounds,
| clipRgn and visRgn bounding boxes. Quit if no intersection.
|
    PEA.L	-0x14(A6)                             | PUSH (MAPPED) TEXTRECT
    PEA.L	0x8(A3)                               | PUSH BITMAP BOUNDS
    MOVEA.L	0x1C(A3),A0                         | GET CLIPRGN HANDLE
    MOVEA.L	(A0),A0                             | DE-REFERENCE IT
    PEA.L	0x2(A0)                               | PUSH CLIPRGN BBOX
    MOVEA.L	0x18(A3),A0                         | GET VISRGN HANDLE
    MOVEA.L	(A0),A0                             | DE-REFERENCE IT
    PEA.L	0x2(A0)                               | PUSH VISRGN BBOX
    MOVE.W	#0x4,-(A7)                           | PUSH NRECTS=4
    PEA.L	-0x1C(A6)                             | PUSH DST ADDR
    JSR	RSECT(PC)                               | CALC INTERSECTION
    BEQ.W	NOSHAD_EXIT                           | QUIT IF NO INTERSECTION
|
| Set up srcAddr, srcRow, and height
|
    LEA.L	0x1A(A2),A0                           | GET START OF FONT BITMAP
    MOVE.L	A0,-0x62(A6)                         | SAVE COMPUTED VALUE
    MOVE.W	0x18(A2),D1                          | GET WORDS PER ROW IN FONT
    ADD.W	D1,D1                                 | DOUBLE FOR BYTES PER ROW
    MOVE.W	D1,-0x64(A6)                         | SAVE COMPUTED VALUE
    MOVE.W	0xE(A2),-0x34(A6)                    | SETUP HEIGHT FOR LATER
    TST.W	0x6(A4)                               | ARE BOLD OR ITALIC SET ?
|
| Test for fast case:
| not stretched, no color mapping, txMode = srcOr,
| not bold, italic, underlined, outlined or shadowed,
| visRgn and clipRgn both rectangular.
|
    BNE.W	DRTEXT_NOTFAST                        | NOT FAST UNLESS BOTH ZERO
    CMPI.W	#0x1,0x48(A3)                        | IS TXMODE = SRCOR ?
    BNE.W	DRTEXT_NOTFAST                        | NO, NOT FAST
    TST.W	0xA(A4)                               | ARE ULTHICK OR SHADOW SET ?
    BNE.W	DRTEXT_NOTFAST                        | NOT FAST UNLESS BOTH ZERO
    TST.B	-0x74(A6)                             | IS TEXT STRETCHED ?
    BNE.W	DRTEXT_NOTFAST                        | YES, NOT FAST
    MOVE.W	0x58(A3),D1                          | ARE WE COLOR MAPPING ?
    BMI.B	DRTEXT_NOCOLOR                        | YES, NO COLOR MAPPING
    MOVE.L	0x54(A3),D0                          | YES GET BACKGROUND COLOR
    NOT.L	D0                                    | INVERT IT
    AND.L	0x50(A3),D0                           | AND WITH FOREGROUND COLOR
    BTST	D1,D0                                  | IS THAT PLANE NORMAL ?
    BEQ.W	DRTEXT_NOTFAST                        | NO, NOT FAST
DRTEXT_NOCOLOR:
    MOVEA.L	0x1C(A3),A0                         | NOCOLOR: GET CLIPRGN HANDLE
    MOVEA.L	(A0),A0                             | DE-REFERENCE IT
    MOVEQ.L	#0xA,D0                             | SIZE OF RECTANGULAR RGN
    CMP.W	(A0),D0                               | IS CLIPRGN RECTANGULAR ?
    BNE.B	DRTEXT_NOTFAST                        | NO, NOT FAST
    MOVEA.L	0x18(A3),A1                         | GET VISRGN HANDLE
    MOVEA.L	(A1),A0                             | DE-REFERENCE IT
    CMP.W	(A0),D0                               | IS VISRGN RECTANGULAR ?
    BEQ.B	FAST                                  | YES, TAKE FAST OPTIMIZATION
|
| All systems go except for VisRgn not rectangular.
| Check if visRgn sect minRect is rectangular.
| IF TrimRect(visRgn,minRect) THEN take the fast way.
|
    MOVE.L	A1,-(A7)                             | PUSH VISRGN
    PEA.L	-0x1C(A6)                             | PUSH MINRECT
    JSR	TRIMRECT(PC)                            | CALL TRIMRECT
    BLT.W	NOSHAD_EXIT                           | quit if intersection empty
    BGT.B	DRTEXT_NOTFAST                        | continue if non-rectangular
|
| Fast case, go directly to screen.
| If text is clipped vertically, then clear heightflag and update TOPHT
|
| Called during boot.
FAST:
    ST.B	-0x66(A6)                              | REMEMBER WE'RE GOING FAST (FASTFLAG)
    MOVE.W	-0x1C(A6),D0                         | GET MINRECT TOP
    MOVE.W	-0x18(A6),D1                         | GET MINRECT BOTTOM
    SUB.W	-0xC(A6),D0                           | SUBTRACT TEXTRECT TOP
    BNE.B	VCLIP                                 | yes, handle clip
    CMP.W	-0x8(A6),D1                           | IS MINRECT BOTTOM >= TEXTRECT BOTTOM ?
    BEQ.B	VCLIP_NO                              | no, continue
VCLIP:
    CLR.B	-0xB4(A6)                             | can't use height table (HEIGHTFLAG)
    MOVE.B	D0,-0xB2(A6)                         | use adjusted top (TOPHT)
    SUB.W	-0x1C(A6),D1                          | CALC BUF HEIGHT = BOTTOM - TOP
    MOVE.B	D1,-0xB1(A6)                         | SAVE HEIGHT TO HEIGHTFLAG+1
VCLIP_NO:
    MOVE.W	-0xC(A6),D0                          | GET TEXTRECT TOP
    SUB.W	0x8(A3),D0                            | SUBTRACT PORTBOUNDS TOP
    MULS.W	0x6(A3),D0                           | MULTIPLY BY PORT ROWBYTES
    ADD.L	0x2(A3),D0                            | ADD BASEADDR
    MOVE.L	D0,-0x24(A6)                         | SET UP BUFSTART FOR LATER
    MOVE.W	0x6(A3),-0x28(A6)                    | SAVE PORT ROWBYTES TO BUFROW
    MOVE.W	0xA(A3),-0x2A(A6)                    | SAVE PORTBOUNDS LEFT (BUFLEFT)
    PEA.L	-0x1C(A6)                             | PUSH SHIELD RECT
    MOVE.L	0x8(A3),-(A7)                        | PUSH PORTBOUNDS TOP/LEFT
    JSR	SHIELDCURSOR(PC)                        | HIDE CURSOR IF IT INTERSECTS
    BRA.W	GETPTRS                               | BRANCH TO GETPTRS
|
| Slow case: Setup for an off-screen buffer.
|
| Calc bufLeft: (word-align to avoid shift)
|
| Called during boot.
DRTEXT_NOTFAST:
    CLR.B	-0x66(A6)                             | NOT GOING DIRECTLY TO SCREEN
    MOVE.W	-0xA(A6),D0                          | GET TEXTRECT LEFT
    SUB.W	0xA(A3),D0                            | SUBTRACT PORTBOUNDS LEFT
    ANDI.W	#0xFFF0,D0                           | TRUNCATE TO 16-BIT BOUNDARY
    SUBI.W	#0x20,D0                             | SUBTRACT SLOP
    ADD.W	0xA(A3),D0                            | ADD PORTBOUNDS LEFT
    MOVE.W	D0,-0x2A(A6)                         | SAVE COMPUTED VALUE (BUFLEFT)
    MOVE.W	-0x6(A6),D1                          | GET BUFRIGHT
|
| Calculate buffer size
|
    SUB.W	D0,D1                                 | WIDTH:=BUFRIGHT-BUFLEFT
    LSR.W	#0x5,D1                               | CONVERT DOTS TO LONGS
    ADDQ.W	#0x2,D1                              | ROUND UP DOTS TO LONGS AND ADD SLOP
    MOVE.W	-0x34(A6),D3                         | GET HEIGHT
    MULU.W	D1,D3                                | BUFSIZE:=HEIGHT*BUFROW LONGS
    MOVE.W	D3,-0x26(A6)                         | SAVE COMPUTED VALUE (BUFSIZE)
    LSL.W	#0x2,D1                               | QUAD BUFROW FOR BYTES
    MOVE.W	D1,-0x28(A6)                         | SAVE COMPUTED VALUE (BUFROW)
|
| Calculate total stack requirements for off-screen buffers.
|
    MOVE.L	D3,D2                                | GET BUFSIZE LONGS
    TST.B	0xB(A4)                               | ARE WE SHADOWING ?
    BEQ.W	DRTEXT_NOTFAST_CONT                   | BRANCH IF EQUAL
    ADD.L	D2,D2                                 | YES, CALC 2*BUFSIZE
    EXT.L	D1                                    | SIGN EXTEND BUFROW
    ADD.L	D1,D2                                 | CALC TOTAL LONGS
DRTEXT_NOTFAST_CONT:
    LSL.L	#0x2,D2                               | CONVERT LONGS TO BYTES
    ADDI.L	#0x400,D2                            | ADD 1K BYTES FOR EXTRA STACK MARGIN
    MOVE.L	A7,D0                                | GET CURRENT STACK POINTER
    SUB.L	(HeapEnd).W,D0                        | SUBTRACT (HeapEnd).w
|
| If stack is too small to allocate buffer(s), then recursively call
| DrText with the left half and the right half of the text string.
|
| _StackAvail ;Get StackAvail IN D0
    CMP.L	D0,D2                                 | IS stackNeeded > stackAvail ?
    BLE.B	DRTEXT_NOTFAST_NO                     | NO, CONTINUE
    MOVE.L	-0x6A(A6),0x30(A3)                   | RESTORE PNLOC
    MOVE.W	0x14(A6),D7                          | GET CHARACTER COUNT
    LSR.W	#0x1,D7                               | DIVIDE IN HALF
    BEQ.W	NOSHAD_EXIT                           | GIVE UP IF COUNT WAS ONLY ONE
    MOVE.W	D7,-(A7)                             | PUSH NEW COUNT
    MOVE.L	0x10(A6),-(A7)                       | PUSH TEXTADDR
    MOVE.L	-0xC0(A6),-(A7)                      | PUSH ORIGINAL NUMER
    MOVE.L	-0xC4(A6),-(A7)                      | PUSH ORIGINAL DENOM
    JSR	DRTEXT(PC)                              | DRAW THE FIRST HALF
    MOVE.W	0x14(A6),D0                          | GET ORIGINAL CHARACTER COUNT
    SUB.W	D7,D0                                 | SUBTRACT CHARS ALREADY DONE
    MOVE.W	D0,-(A7)                             | PUSH NEW COUNT
    MOVEA.L	0x10(A6),A0                         | GET ORIGINAL TEXTADDR
    ADDA.W	D7,A0                                | BUMP PAST CHARS ALREADY DONE
    MOVE.L	A0,-(A7)                             | PUSH NEW TEXTADDR
    MOVE.L	-0xC0(A6),-(A7)                      | PUSH ORIGINAL NUMER
    MOVE.L	-0xC4(A6),-(A7)                      | PUSH ORIGINAL DENOM
    JSR	DRTEXT(PC)                              | DRAW THE SECOND HALF
    BRA.W	NOSHAD_EXIT                           | AND QUIT !
| ----------------------------------------------------------
|
| DRTEXT_NOTFAST_NO
|
| Called during boot.
DRTEXT_NOTFAST_NO:
    SUBQ.W	#0x1,D3                              | ADJUST BUFSIZE FOR DBF LOOP
|
| Allocate and clear an off-screen buffer
|
    CLR.L	-(A7)                                 | PAD BUFFER WITH AN EXTRA ZERO
    MOVE.L	A7,-0x20(A6)                         | REMEMBER WHERE BUFFER ENDS
CLRLOOP:
    CLR.L	-(A7)                                 | CLEAR ONE LONG OF BUFFER
    DBF.W	D3,CLRLOOP                            | ALLOCATE AND CLEAR BUFFER
    MOVE.L	A7,-0x24(A6)                         | REMEMBER START OF BUFFER
    CLR.L	-(A7)                                 | PAD BUFFER WITH AN EXTRA ZERO
|
| Get pointers to location table, width table, and height table in font
|
| Called during boot.
GETPTRS:
    LEA.L	0x1A(A2),A0                           | GET START OF FONT BITMAP
    MOVE.W	0xE(A2),D0                           | GET HEIGHT OF FONT BITMAP
    MULU.W	-0x64(A6),D0                         | CALC TOTAL SIZE OF STRIKE
    ADDA.L	D0,A0                                | A1 := START OF LOC TABLE
    MOVE.L	A0,-0xB0(A6)                         | SAVE COMPUTED VALUE (LOCTAB)
    MOVEQ.L	#0x0,D0                             | get ready for unsigned word
    MOVE.W	0x10(A2),D0                          | HOW MANY WORDS IN STRIKE BODY
    ADD.L	D0,D0                                 | DOUBLE FOR BYTECOUNT
    LEA.L	0x10(A2,D0.L),A1                      | GET START OF WIDTH TABLE
    MOVE.L	A1,-0xAC(A6)                         | SAVE COMPUTED VALUE (WIDTAB)
    MOVE.W	0x4(A2),D0                           | GET MAXCHAR
    MOVE.W	0x2(A2),D1                           | GET MINCHAR
    MOVE.W	D1,-0xB8(A6)                         | STASH MINCHAR FOR LATER
    SUB.W	D1,D0                                 | CALC MAXCHAR-MINCHAR
    MOVE.W	D0,-0xB6(A6)                         | SAVE COMPUTED VALUE (MAXMIN)
    ADDQ.W	#0x3,D0                              | ADD 3 FOR MISSING SYMBOL AND EXTRAS
    ADD.W	D0,D0                                 | CALC 2*(MAX-MIN+3)
    BTST	#0x1,0x1(A2)                           | DOES FONT HAVE WIDTH TABLE ?
    BEQ.B	GETPTRS_NO                            | NO, CONTINUE
    ADD.W	D0,D0                                 | YES, SKIP OVER WIDTH TABLE
GETPTRS_NO:
    LEA.L	0x0(A1,D0.W),A0                       | CALC ADDRESS OF HEIGHT TABLE
    MOVE.L	A0,-0xA8(A6)                         | SAVE COMPUTED VALUE (HEIGHTAB)
|
| Set up space width
|
    MOVEA.L	(WidthPtr).W,A0                     | point to width table
    MOVE.L	0x80(A0),-0x98(A6)                   | get width of the space char
|
| Setup misc stuff in registers for speed
|
    MOVE.W	-0x2A(A6),D1                         | GET BUFLEFT
    MOVE.W	-0x68(A6),D0                         | GET PENLOC.H
    ADD.W	0x8(A2),D0                            | ADJUST FOR KERNING
    SUB.W	D1,D0                                 | MAKE CHARLOC RELATIVE TO BUFLEFT
    MOVE.W	D0,-0x9C(A6)                         | SAVE INITIAL CHARLOC (INT PART)
    MOVE.W	#0x8000,-0x9A(A6)                    | SET CHARLOC FRACT PART TO 0.5
    SUB.W	D1,-0x1A(A6)                          | OFFSET MINRECT LEFT BY BUFLEFT
    SUB.W	D1,-0x16(A6)                          | OFFSET MINRECT RIGHT BY BUFLEFT
    MOVEA.L	0x10(A6),A1                         | GET TEXTPTR
    BRA.B	NEXTCH                                | GO TO LOOP START
| ---------------------------------------------------
|
| Here's the main character drawing loop:
|
| Called during boot.
SPACECH:
    MOVE.L	-0x98(A6),D1                         | GET SPACE WIDTH
    ADD.L	D1,-0x9C(A6)                          | BUMP CHARLOC
SKIPCH:
    SUBQ.W	#0x1,0x14(A6)                        | DECREMENT CHAR COUNT
    BLE.W	STRDONE                               | QUIT IF CHARCOUNT <= 0
| Called by: GETPTRS_NO, MISSING, WIDE1, LONG1A, WORD1B
NEXTCH:
    CLR.W	D0                                    | get ready for byte
    MOVE.B	(A1)+,D0                             | GET NEXT CHAR
    CMPI.B	#0x20,D0                             | IS IT A SPACE CHARACTER?
    BEQ.B	SPACECH                               | YES, HANDLE IT
    MOVEA.L	(WidthPtr).W,A0                     | POINT TO WIDTH TABLE
    MOVE.W	D0,D4                                | COPY CHARACTER
    LSL.W	#0x2,D4                               | QUAD FOR TABLE OFFSET
    MOVE.L	0x0(A0,D4.W),D4                      | GET FIXED POINT WIDTH FOR CHAR
    SUB.W	-0xB8(A6),D0                          | SUBTRACT SAVED MINCHAR
    CMP.W	-0xB6(A6),D0                          | IS CH BETWEEN MINCHAR AND MAXCHAR ?
    BLS.B	OKCHAR                                | YES, CONTINUE
MISSING:
    MOVE.W	-0xB6(A6),D0                         | NO, USE MISSING SYMBOL
    ADDQ.W	#0x1,D0                              | ADD 1 FOR MISSING SYMBOL INDEX
    ADD.W	D0,D0                                 | INDEX := 2*(MISSING-MINCHAR)
    MOVEA.L	-0xAC(A6),A0                        | POINT TO WIDTH TABLE
    MOVE.W	0x0(A0,D0.W),D3                      | GET WIDTH OFFSET FROM TABLE
    BPL.B	NOTMISS                               | IS MISSING CHAR MISSING ?
    BRA.B	NEXTCH                                | YES, SKIP THIS CHAR
| ----------------------------------------------------------
|
| OKCHAR
|
| Called during boot.
OKCHAR:
    ADD.W	D0,D0                                 | INDEX := 2*(ASCII-MINCHAR)
    MOVEA.L	-0xAC(A6),A0                        | POINT TO WIDTH TABLE
    MOVE.W	0x0(A0,D0.W),D3                      | GET WIDTH OFFSET FROM TABLE
    BMI.B	MISSING                               | OFFSET NEG = MISSING CHAR
NOTMISS:
    LSR.W	#0x8,D3                               | GET OFFSET BYTE
    ADD.W	-0x9C(A6),D3                          | ADD CHARLOC INT PART TO SRC OFFSET
    ADD.L	D4,-0x9C(A6)                          | ADD FIXED POINT WIDTH TO CHARLOC
    MOVEA.L	-0xB0(A6),A0                        | POINT TO LOCATION TABLE
    MOVE.W	0x0(A0,D0.W),D1                      | GET START OFFSET FROM LOC TABLE
    MOVE.W	0x2(A0,D0.W),D2                      | GET END OFFSET FROM LOC TABLE
    SUB.W	D1,D2                                 | CALC WIDTH OF BITS
    BLE.B	SKIPCH                                | SKIP CHARBLT IF WIDTH <= 0
    ADD.W	D3,D2                                 | DSTRIGHT := DSTLEFT + WIDTH
    TST.B	-0xB4(A6)                             | does font have height table ?
    BEQ.B	NOTMISS_NO                            | no, continue
    MOVEA.L	-0xA8(A6),A0                        | get height table
    MOVE.W	0x0(A0,D0.W),-0xB2(A6)               | SAVE CHAR TOP TO TOPHT
| NOHEIGHT

| ----------------------------------------------------------------------- | CLEAR HIGH WORD FOR DIVIDE
| | DIVIDE BY 8
| Horizontal clip only if FastFlag: (else stretch,outline,shadow,italic die)
|
| skip if hidden on left, string done if hidden on right.
|
| at this point: D1: srcLeft
| D2: dstRight
| D3: dstLeft
|
| Called during boot.
NOTMISS_NO:
    TST.B	-0x66(A6)                             | ARE WE GOING FAST ?
    BEQ.B	HORIZOK                               | NO, DON'T CLIP
    CMP.W	-0x1A(A6),D3                          | COMPARE MINRECT+LEFT
    BGE.B	NOTMISS_NO_2                          | NO, CONTINUE
    CMP.W	-0x1A(A6),D2                          | COMPARE MINRECT+LEFT
    BLE.W	SKIPCH                                | YES, SKIP THIS CHAR
    MOVE.W	-0x1A(A6),D0                         | GET MINRECT+LEFT
    SUB.W	D3,D0                                 | DISCARD:=MINRECT.LEFT-DSTLEFT
    ADD.W	D0,D1                                 | SRCLEFT:=SRCLEFT+DISCARD
    ADD.W	D0,D3                                 | DSTLEFT:=DSTLEFT+DISCARD
    CMP.W	-0x16(A6),D2                          | COMPARE MINRECT+RIGHT
    BLE.B	HORIZOK                               | NO, CONTINUE
    BRA.B	TRIMRT                                | YES, TRIM RIGHT
| ----------------------------------------------------------
|
| NOTMISS_NO_2
|
| Called during boot.
NOTMISS_NO_2:
    CMP.W	-0x16(A6),D2                          | COMPARE MINRECT+RIGHT
    BLE.B	HORIZOK                               | YES, CONTINUE
    CMP.W	-0x16(A6),D3                          | COMPARE MINRECT+RIGHT
    BGE.W	STRDONE                               | YES, IGNORE REST OF STRING
TRIMRT:
    MOVE.W	-0x16(A6),D2                         | GET MINRECT+RIGHT
| HORIZOK

| --------------------------------------------------------------
|
| Inputs to local block CharBlt:
|
| srcAddr(A6)
| srcRow(A6)
| bufStart(A6) = dstAddr
| bufRow(A6) = dstRow
| D1 = srcLeft
| D2 = dstRight relative to buffer, > dstLeft
| D3 = dstLeft relative to buffer
| TOPHT(A6) top and height
|
| CLOBBERS: D0,D1,D2,D3,D4,D5,D6,D7,A0,A2,A3,A4,A5
| PRESERVES: A1,A6,SP
|
|
| Setup shift count in D5 (relative shift between src and dst)
|
| Called during boot.
HORIZOK:
    MOVE.W	D3,D5                                | COPY DSTLEFT
    SUB.W	D1,D5                                 | SUB SRC LEFT
    MOVEQ.L	#0xF,D0                             | get a 4 bit mask
    AND.W	D0,D5                                 | SHIFTCNT:=DELTA HORIZ MOD 16
|
| Setup srcAddr in A4, address of leftmost word
|
    MOVEA.L	-0x62(A6),A4                        | GET START OF SRC BITMAP
    ADD.W	D5,D1                                 | CALC SRCLEFT+SHIFTCNT
    ASR.W	#0x4,D1                               | CONVERT FROM DOTS TO WORDS
    ADD.W	D1,D1                                 | DOUBLE FOR BYTES
    SUBQ.W	#0x2,D1                              | BACK UP ONE WORD FOR SRC
    ADDA.W	D1,A4                                | LEAVE SRCPTR IN A4
|
| Setup dstPtr in A5, address of leftmost dst word
|
    MOVEA.L	-0x24(A6),A5                        | GET START OF DST BITMAP
    MOVE.W	D3,D1                                | GET A COPY OF DSTLEFT
    ASR.W	#0x4,D1                               | CONVERT FROM DOTS TO WORDS
    ADDA.W	D1,A5                                | ADD TO DSTPTR
    ADDA.W	D1,A5                                | TWICE FOR BYTES
|
| Setup leftMask in D3 and rightMask in D4
|
    LEA.L	MASKTAB(PC),A0                        | point to mask table
    AND.W	D0,D3                                 | get bottom 4 bits of dstLeft
    ADD.W	D3,D3                                 | double for table index
    MOVE.W	0x0(A0,D3.W),D3                      | GET MASK FOR LEFT EDGE
    NOT.W	D3                                    | invert it for leftMask
    MOVE.W	D2,D6                                | copy dstRight
    AND.W	D0,D2                                 | get bottom 4 bits of dstRight
    ADD.W	D2,D2                                 | double for table index
    MOVE.W	0x0(A0,D2.W),D4                      | GET MASK FOR RIGHT EDGE
|
| Get srcRow, dstRow, and char height into regs
|
    MOVEA.W	-0x64(A6),A2                        | GET SRCROW
    MOVEA.W	-0x28(A6),A3                        | GET BUFROW
    MOVE.W	#0xFF,D7                             | INIT ROW COUNTER HIGH BYTE
    ADD.B	-0xB1(A6),D7                          | ADD BUFHEIGHT-1 TO ROW COUNTER
    BMI.W	SKIPCH                                | OOPS HEIGHT WAS ZERO !
|
| Adjust srcPtr and dstPtr for charTop
|
    CLR.W	D0                                    | get ready for byte
    MOVE.B	-0xB2(A6),D0                         | get char top
    MOVE.W	A2,D2                                | get srcRow in D-reg
    MULU.W	D0,D2                                | calc charTop * srcRow
    ADDA.L	D2,A4                                | add to srcPtr
    MOVE.W	A3,D2                                | get dstRow in D-reg
    MULU.W	D0,D2                                | calc charTop * dstRow
    ADDA.L	D2,A5                                | add to dstPtr
|
| Branch based on total number of dst words
|
    ASR.W	#0x4,D6                               | CALC (DSTRIGHT) DIV 16
    SUB.W	D1,D6                                 | CALC TOTAL NUMBER OF WORDS-1
    BEQ.B	WORD1                                 | BR IF DST ALL IN ONE WORD
    SUBQ.W	#0x1,D6                              | ADJUST DST WORD COUNT FOR DBF
    BEQ.B	LONG1                                 | BR IF DST ALL IN ONE LONG
    ADDQ.W	#0x1,D7                              | ADJUST ROW COUNT FOR DBF
    BRA.B	WIDE1                                 | DST WIDER THAN ONE LONG
|
| Slow loop only taken in wierd cases where dst wider than a long.
|
MAIN1:
    MOVE.L	(A4),D0                              | GET SRC FROM BITMAP
    ADDQ.W	#0x2,A4                              | BUMP SRCPTR TO NEXT WORD
    LSR.L	D5,D0                                 | ALIGN TO DST
    AND.W	D1,D0                                 | MASK EXTRA TO ZEROS
    OR.W	D0,(A5)+                               | OR SRC INTO DST
    MOVEQ.L	#-0x1,D1                            | FLUSH MASK
    DBF.W	D2,MAIN1                              | LOOP TILL LAST WORD
    MOVE.L	(A4),D0                              | GET SRC FROM BITMAP
    LSR.L	D5,D0                                 | ALIGN TO DST
    AND.W	D4,D0                                 | MASK WITH RIGHTMASK
    OR.W	D0,(A5)                                | OR SRC INTO DST
    MOVEA.L	-0x6E(A6),A4                        | RESTORE SRCPTR TO LEFT
    ADDA.W	A2,A4                                | BUMP TO NEXT ROW
    MOVEA.L	-0x72(A6),A5                        | RESTORE DSTPTR TO LEFT
    ADDA.W	A3,A5                                | BUMP DST TO NEXT ROW
WIDE1:
    MOVE.L	A4,-0x6E(A6)                         | REMEMBER SRCPTR AT LEFT
    MOVE.L	A5,-0x72(A6)                         | REMEMBER DSTPTR AT LEFT
    MOVE.W	D3,D1                                | MASK:=LEFTMASK
    MOVE.W	D6,D2                                | GET WORDCOUNT
    DBF.W	D7,MAIN1                              | LOOP ALL ROWS
    SUBQ.W	#0x1,0x14(A6)                        | DECREMENT CHAR COUNT
    BGT.W	NEXTCH                                | LOOP IF MORE CHARS LEFT
    BRA.W	STRDONE                               | QUIT IF CHARCOUNT <= 0
| ----------------------------------------------------------
|
| LONG1
|
| Called during boot.
LONG1:
    SUBQ.W	#0x2,A3                              | ADJUST DSTROW TO ACCOUNT FOR POST-INCREMENT
|
| Optimize if dst fits in one long. (30% of normal characters do)
|
| Called during boot.
LONG1A:
    MOVE.L	(A4),D0                              | GET SRC DATA
    LSR.L	D5,D0                                 | ALIGN TO DST
    AND.W	D3,D0                                 | MASK EXTRA WITH LEFTMASK
    OR.W	D0,(A5)+                               | OR RESULT INTO DST
    MOVE.L	0x2(A4),D0                           | GET SECOND WORD OF SRC
    LSR.L	D5,D0                                 | ALIGN IT
    AND.W	D4,D0                                 | MASK EXTRA WITH RIGHTMASK
    OR.W	D0,(A5)                                | OR RESULT INTO DST
    ADDA.W	A2,A4                                | BUMP SRCPTR TO NEXT ROW
    ADDA.W	A3,A5                                | BUMP DSTPTR TO NEXT ROW
    DBF.W	D7,LONG1A                             | LOOP ALL ROWS
    SUBQ.W	#0x1,0x14(A6)                        | DECREMENT CHAR COUNT
    BGT.W	NEXTCH                                | LOOP IF MORE CHARS LEFT
    BRA.W	STRDONE                               | QUIT IF CHARCOUNT <= 0
|
| Optimize if dst fits in one word. (70% of normal characters do)
|
| Called during boot.
WORD1:
    AND.W	D4,D3                                 | COMBINE LEFT AND RIGHT MASKS
WORD1B:
    MOVE.L	(A4),D0                              | GET SRC DATA
    LSR.L	D5,D0                                 | ALIGN TO DST
    AND.W	D3,D0                                 | MASK EXTRA TO ZEROS
    OR.W	D0,(A5)                                | OR RESULT INTO DST
    ADDA.W	A2,A4                                | BUMP SRCPTR TO NEXT ROW
    ADDA.W	A3,A5                                | BUMP DSTPTR TO NEXT ROW
    DBF.W	D7,WORD1B                             | LOOP ALL ROWS
    SUBQ.W	#0x1,0x14(A6)                        | DECREMENT CHAR COUNT
    BGT.W	NEXTCH                                | LOOP IF MORE CHARS LEFT
STRDONE:
    MOVEA.L	-0xBC(A6),A5                        | RESTORE GLOBAL PTR
    TST.B	-0x66(A6)                             | WERE WE GOING DIRECT TO SCREEN ?
    BEQ.B	STRDONE_CONT                          | BRANCH IF EQUAL
    JSR	SHOWCURSOR(PC)                          | YES, RESTORE CURSOR
    BRA.W	NOSHAD_EXIT                           | AND QUIT
| ----------------------------------------------------------
|
| STRDONE_CONT
|
| Called during boot.
STRDONE_CONT:
    MOVEA.L	(A5),A0                             | GET QUICKDRAW GLOBALS POINTER
    MOVEA.L	(A0),A3                             | GET CURRENT GRAFPORT
    MOVEA.L	-0xB0(A0),A4                        | POINT TO FMOUTPUT (FONTPTR)
    MOVEA.L	0x2(A4),A2                          | GET FONT HANDLE
    MOVEA.L	(A2),A2                             | DE-REFERENCE IT
    MOVE.W	-0x9C(A6),D7                         | GET FINAL CHARLOC INT PART
    SUB.W	0x8(A2),D7                            | UN-ADJUST FROM KERNING
|
| Make buffer bold if necessary:
|
| Called during boot.
| CKBOLD inlined:
    CLR.W	D2                                    | GET READY FOR BYTE
    MOVE.B	0x6(A4),D2                           | GET NUMBER OF OVERSTRIKES
    BRA.B	NXTBOLD                               | BOLD BUFFER IF ANY
| ----------------------------------------------------------
|
| BOLDIT: bold the buffer one extra-stroke pass.
|
| Called during boot.
BOLDIT:
    MOVEA.L	-0x24(A6),A0                        | POINT TO START OF BUFFER
    MOVE.W	-0x26(A6),D1                         | HOW MANY LONGS IN BUF
    SUB.W	D0,D0                                 | CLEAR X-BIT
BOLDLP:
    MOVE.L	(A0),D0                              | GET ONE LONG
    ROXR.L	#0x1,D0                              | ROTATE RIGHT WITH EXTEND
    OR.L	D0,(A0)+                               | OR BACK INTO BUFFER
    DBF.W	D1,BOLDLP                             | LOOP ENTIRE BUFFER
NXTBOLD:
    DBF.W	D2,BOLDIT                             | LOOP FOR EACH OVERSTRIKE
|
| Slant the buffer if necessary:
| Work from bottom of buffer up, shifting each row right.
| Work right to left to avoid clobbering src.
|
    CLR.W	D2                                    | GET READY FOR BYTE
    MOVE.B	0x7(A4),D2                           | DO WE NEED ITALIC ?
    BEQ.B	CHECKUL                               | NO, CONTINUE
    MOVEA.L	-0x20(A6),A1                        | DSTPTR:=END OF BUFFER
    MOVE.W	-0x28(A6),D3                         | GET BUFFER ROWBYTES
    SUBA.W	D3,A1                                | BACK UP DSTPTR TO END OF 2ND ROW
    LSR.W	#0x1,D3                               | WORDCNT:=ROWBYTES DIV 2
    SUBQ.W	#0x1,D3                              | ADJUST BUFSIZE FOR DBF LOOP
    MOVE.W	-0x34(A6),D6                         | INIT ROW COUNTER
    CLR.W	D4                                    | INIT OFFSET
    BRA.B	DOSLANT                               | GO TO LOOP START
| ----------------------------------------------------------
|
| NXTROW: italic-slant inner loop.
|
NXTROW:
    ADD.W	D2,D4                                 | OFFSET:=OFFSET+ITALIC
    MOVE.W	D4,D0                                | COPY OFFSET
    LSR.W	#0x4,D0                               | DELTA := OFFSET SCALED BY 16
    MOVEQ.L	#0xF,D5                             | GET A 4-BIT MASK
    AND.W	D0,D5                                 | SHIFTCNT:=DELTA MOD 16
    LSR.W	#0x4,D0                               | DELWORD:=DELTA DIV 16
    MOVEA.L	A1,A0                               | SRCPTR:=DSTPTR
    SUBQ.W	#0x4,A0                              | BACK UP TWO WORDS
    SUBA.W	D0,A0                                | SUBTRACT DELWORD
    SUBA.W	D0,A0                                | TWICE BECAUSE WORDS
    MOVE.W	D3,D1                                | INIT LOOP TO WORDCNT
NXTWORD:
    MOVE.L	(A0),D0                              | GET A LONG OF SRC
    SUBQ.W	#0x2,A0                              | BACK UP SRC PTR ONE WORD
    LSR.L	D5,D0                                 | SHIFT SRC TO ALIGN WITH DST
    MOVE.W	D0,-(A1)                             | STORE IN DST AND BUMP DSTPTR
    DBF.W	D1,NXTWORD                            | LOOP ALL WORDS THIS ROW
DOSLANT:
    DBF.W	D6,NXTROW                             | LOOP FOR ALL ROWS IN BUFFER
|
| Underline characters in buffer if necessary.
|
| Use characters in buffer to hide parts of the underline.
|
| Called during boot.
CHECKUL:
    TST.B	0xA(A4)                               | IS ULTHICK ZERO ?
    BEQ.W	NOTUL                                 | YES, CONTINUE
    MOVEA.L	-0x24(A6),A0                        | POINT TO BUFFER START
    MOVE.W	-0x28(A6),D1                         | GET BYTES PER ROW OF BUFFER
    MOVE.W	0x12(A2),D0                          | GET ASCENT
    MOVE.W	0x14(A2),D2                          | GET DESCENT
    MULU.W	D1,D0                                | CALC ASCENT * BYTES PER ROW
    ADDA.L	D0,A0                                | POINT TO BASELINE ROW
    MOVEA.L	A0,A1                               | SET BASELINE+1 PTR
    MOVEA.L	A0,A2                               | SET BASELINE+2 PTR
    ADDA.W	D1,A1                                | POINT TO BASELINE+1
    CMPI.W	#0x2,D2                              | IS DESCENT LESS THAN 2?
    BLT.B	NOTUL                                 | NO, SKIP UNDERLINE
    BEQ.B	ONLY2                                 | ONLY USE 2 IF DESCENT=2
    ADDA.W	D1,A2                                | ADD ROWBYTES TO A2
    ADDA.W	D1,A2                                | POINT TO BASELINE+2
ONLY2:
    SUBA.W	D1,A7                                | ALLOCATE TEMP SCANBUF
    MOVE.L	A3,-(A7)                             | SAVE GRAFPORT
    LEA.L	0x4(A7),A3                            | POINT TO START OF TEMP
    LSR.W	#0x2,D1                               | CONVERT BYTES TO LONGS
    SUBQ.W	#0x1,D1                              | ADJUST LONG COUNT FOR DBF
    MOVE.W	D1,D2                                | COPY LOOP COUNT
    SUB.W	D0,D0                                 | CLEAR X-BIT
UL1:
    MOVE.L	(A0)+,D0                             | GET FROM BASELINE
    OR.L	(A1)+,D0                               | OR WITH BASELINE+1
    OR.L	(A2)+,D0                               | OR WITH BASELINE+2
    MOVE.L	D0,(A3)                              | PUT RESULT TO TEMP
    ROXR.L	#0x1,D0                              | SHIFT WITH CARRY
    OR.L	D0,(A3)+                               | OR INTO TEMP
    DBF.W	D1,UL1                                | LOOP ALL LONGS IN ROW
    MOVEA.L	A1,A0                               | COPY END PTR
    SUB.W	D0,D0                                 | CLEAR X-BIT
UL2:
    MOVE.L	-(A3),D0                             | GET FROM TEMP
    ROXL.L	#0x1,D0                              | SHIFT LEFT WITH CARRY
    OR.L	(A3),D0                                | OR WITH TEMP
    NOT.L	D0                                    | INVERT
    OR.L	D0,-(A1)                               | DRAW SOME UNDERLINE
    DBF.W	D2,UL2                                | LOOP ALL LONGS IN ROW
    MOVEA.L	(A7)+,A3                            | RESTORE GRAFPORT
|
| Trim right edge of underline. (left edge trimmed by StretchBits)
|
    MOVE.W	-0x28(A6),D0                         | GET BYTES PER ROW OF BUFFER
    LSL.W	#0x3,D0                               | TIMES 8 FOR DOTS WIDE
    SUB.W	D7,D0                                 | OVERSHOOT:=BUFRIGHT-LASTRIGHT
    SUBQ.W	#0x1,D0                              | ADJUST LONG COUNT FOR DBF
    LSR.W	#0x4,D0                               | CONVERT DOTS TO WORDCOUNT
    BRA.B	UL3                                   | GO TO LOOP START
| ----------------------------------------------------------
|
| ULTRIM
|
ULTRIM:
    CLR.W	-(A0)                                 | ERASE SOME UNDERLINE
UL3:
    DBF.W	D0,ULTRIM                             | LOOP ALL FULL WORDS
    ADD.W	-0x2A(A6),D7                          | UNDO BUFFER RELATIVE
    MOVE.W	D7,D0                                | GET LAST RIGHT COORD
    SUB.W	0xA(A3),D0                            | SUBTRACT PORTBITS+BOUNDS+LEFT
    JSR	RIGHTMASK(PC)                           | COMPUTE A MASK
    AND.W	D0,-(A0)                              | ERASE LAST PARTIAL WORD
NOTUL:
|
| Setup fakeRgn, a dummy rectangular region
|
    MOVE.W	#0xA,-0x5A(A6)                       | SAVE FAKERGN.RGNSIZE = 10
    MOVE.L	0x8(A3),-0x58(A6)                    | GET PORTBITS+BOUNDS+TOP
    MOVE.L	0xC(A3),-0x54(A6)                    | SET FAKERGN BOTTOM/RIGHT BOUNDS
    LEA.L	-0x5A(A6),A0                          | GET ADDR OF FAKERGN
    MOVE.L	A0,-0x5E(A6)                         | POINT FAKE MASTERPTR TO IT
|
| Setup bitMaps to transfer from buffer to screen.
|
| srcBits := buffer
|
    LEA.L	-0x42(A6),A0                          | POINT TO SRCBITS
    MOVE.L	-0x24(A6),(A0)+                      | SET UP BASEADDR
    MOVE.W	-0x28(A6),(A0)+                      | SET UP ROWBYTES
    MOVE.W	-0xC(A6),(A0)+                       | SET UP BOUNDS TOP
    MOVE.W	-0x2A(A6),(A0)+                      | SET UP BOUNDS LEFT
    MOVE.L	-0x8(A6),(A0)+                       | SET UP BOUNDS BOTTOM AND RIGHT
|
| dstBits := portBits
|
    LEA.L	0x2(A3),A2                            | POINT TO PORTBITS
    LEA.L	-0x50(A6),A0                          | POINT TO DSTBITS
    MOVE.L	(A2)+,(A0)+                          | COPY BASEADDR
    MOVE.W	(A2)+,(A0)+                          | COPY ROWBYTES
    MOVE.L	(A2)+,(A0)+                          | COPY BOUNDS.TOPLEFT
    MOVE.L	(A2)+,(A0)+                          | COPY BOUNDS.BOTRIGHT
|
| check if any shadowing:
|
    CLR.W	D3                                    | GET READY FOR BYTE
    MOVE.B	0xB(A4),D3                           | GET SHADOW COUNT
    BEQ.W	NOSHAD                                | SKIP IF NO SHADOWING
|
| Shadowing will be used. Allocate buf2, 4 scans taller than BUF1.
| Clear out new 4 scanlines, and copy BUF1 into the rest.
|
    MOVE.W	-0x28(A6),D0                         | GET 4 * NUMBER OF LONGS PER ROW
    SUBQ.W	#0x1,D0                              | ADJUST LONG COUNT FOR DBF
    CLR.L	-(A7)                                 | ALLOW ONE LONG OF SLOP
    MOVE.L	A7,-0x32(A6)                         | REMEMBER END OF BUF2
CLR2:
    CLR.L	-(A7)                                 | ALLOCATE AND CLEAR A LONG
    DBF.W	D0,CLR2                               | CLEAR 4 SCANLINES WORTH
    MOVE.W	-0x26(A6),D0                         | GET NUMBER OF LONGS IN BUF1
    SUBQ.W	#0x1,D0                              | ADJUST LONG COUNT FOR DBF
    MOVEA.L	-0x20(A6),A0                        | POINT TO END OF BUF1
COPYLP:
    MOVE.L	-(A0),-(A7)                          | COPY FROM BUF1 TO NEW BUF2
    DBF.W	D0,COPYLP                             | COPY ALL OF BUF1
    MOVE.L	A7,-0x2E(A6)                         | REMEMBER START OF BUF2
    CLR.L	-(A7)                                 | ALLOW ONE LONG OF SLOP
    ANDI.W	#0x3,D3                              | LIMIT SHADOW OFFSET TO 3
|
| Bold buf2 across to the right enough for shadow.
|
    MOVE.W	D3,D2                                | INIT BOLD COUNTER
ACROSS1:
    MOVEA.L	-0x2E(A6),A0                        | POINT TO START OF BUFFER2
    MOVE.W	-0x26(A6),D1                         | INIT COUNT OF LONGS
    SUB.W	D0,D0                                 | CLEAR X-BIT
ACROSS2:
    MOVE.L	(A0),D0                              | GET A LONG FROM BUF2
    ROXR.L	#0x1,D0                              | SHIFT IT RIGHT EXTENDED
    OR.L	D0,(A0)+                               | OR IT BACK INTO BUFFER
    DBF.W	D1,ACROSS2                            | LOOP FOR ALL LONGS
    DBF.W	D2,ACROSS1                            | BOLD RIGHT 2,3, OR 4 TIMES
|
| Bold BUF2 down enough for shadow.
|
    MOVEA.L	-0x2E(A6),A2                        | GET LIMIT POINTER
DOWN1:
    MOVEA.L	-0x32(A6),A1                        | DSTPTR:=END OF BUF2
    MOVEA.L	A1,A0                               | SET SRC PTR TO END OF BUF2
    SUBA.W	-0x3E(A6),A0                         | SUBTRACT ROWBYTES TO POINT TO LINE ABOVE
DOWN2:
    MOVE.L	-(A0),D0                             | GET A LONG FROM LINE ABOVE
    OR.L	D0,-(A1)                               | OR INTO THIS LINE
    CMPA.L	A2,A0                                | IS SRCPTR <= BUF2START ?
    BGT.B	DOWN2                                 | NO, LOOP ALL LONGS
    DBF.W	D3,DOWN1                              | BOLD DOWN 2,3, OR 4 TIMES
|
| Alter srcBits to use BUF2
|
    MOVE.L	A2,-0x42(A6)                         | UPDATE SRCBITS BASEADDR TO BUF2
    ADDQ.W	#0x4,-0x38(A6)                       | INCREASE SRCBITS BOUNDS BOTTOM BY 4
|
| Push params and call StretchBits to transfer shadow to screen
|
    MOVE.L	-0xC(A6),-0x8C(A6)                   | SRCRECT := TEXTRECT
    MOVE.L	-0x8(A6),-0x88(A6)                   | DSTRECT := SRCRECT
    ADDQ.W	#0x4,-0x88(A6)                       | INCREASE DSTRECT BOTTOM BY 4 FOR SHADOW
    MOVE.L	-0x8C(A6),-0x94(A6)                  | SAVE TO DSTRECT
    MOVE.L	-0x88(A6),-0x90(A6)                  | COPY SRCRECT BOT/RIGHT TO DSTRECT
    LEA.L	-0x94(A6),A0                          | POINT TO DSTRECT
    SUBQ.W	#0x1,(A0)+                           | EXPAND DSTRECT BOUND BY 1
    SUBQ.W	#0x1,(A0)+                           | EXPAND DSTRECT BOUND BY 1
    SUBQ.W	#0x1,(A0)+                           | EXPAND DSTRECT BOUND BY 1
    SUBQ.W	#0x1,(A0)+                           | EXPAND DSTRECT BOUND BY 1
    TST.B	-0x74(A6)                             | ARE WE STRETCHING TEXT?
    BEQ.B	DOWN2_CONT                            | BRANCH IF EQUAL
    PEA.L	-0x94(A6)                             | PUSH DSTRECT
    PEA.L	-0x7C(A6)                             | PUSH FROMRECT
    PEA.L	-0x84(A6)                             | PUSH TORECT
    JSR	MAPRECT(PC)                             | THEN MAPPED FOR SCALING
DOWN2_CONT:
    PEA.L	-0x42(A6)                             | PUSH SRCBITS
    PEA.L	-0x50(A6)                             | PUSH DSTBITS
    PEA.L	-0x8C(A6)                             | PUSH SRCRECT
    PEA.L	-0x94(A6)                             | PUSH DSTRECT
    MOVEQ.L	#0x7,D0                             | GET A 3-BIT MASK
    AND.W	0x48(A3),D0                           | GET TEXTMODE MOD 7
    MOVE.W	D0,-(A7)                             | PUSH SHADOW MODE
    MOVE.L	0x1C(A3),-(A7)                       | PUSH CLIPRGN HANDLE
    MOVE.L	0x18(A3),-(A7)                       | PUSH VISRGN HANDLE
    PEA.L	-0x5E(A6)                             | PUSH FAKE HANDLE
    JSR	STRETCHBITS(PC)                         | TRANSFER BUFFER TO SCREEN
|
| restore altered srcBits
|
    MOVE.L	-0x24(A6),-0x42(A6)                  | GET BUFSTART
    SUBQ.W	#0x4,-0x38(A6)                       | RESTORE SRCBITS BOUNDS BOTTOM
|
| Push params and call StretchBits to transfer buffer to screen
|
| Called during boot.
NOSHAD:
    PEA.L	-0x42(A6)                             | PUSH SRCBITS
    PEA.L	-0x50(A6)                             | PUSH DSTBITS
    PEA.L	-0xC(A6)                              | PUSH SRCRECT = TEXTRECT
    PEA.L	-0x14(A6)                             | PUSH DSTRECT = TEXTR2
    MOVE.W	0x48(A3),-(A7)                       | PUSH TEXTMODE
    TST.B	0xB(A4)                               | ARE WE USING SHADOW ?
    BEQ.B	NOSHAD_NO                             | NO, CONTINUE
    MOVE.W	#0x2,(A7)                            | YES, USE XOR MODE
NOSHAD_NO:
    ANDI.W	#0x7,(A7)                            | MASK OUT TXMODE SLANT/BOLD BITS
    MOVE.L	0x1C(A3),-(A7)                       | PUSH CLIPRGN HANDLE
    MOVE.L	0x18(A3),-(A7)                       | PUSH VISRGN HANDLE
    PEA.L	-0x5E(A6)                             | PUSH FAKE HANDLE
    JSR	STRETCHBITS(PC)                         | TRANSFER BUFFER TO SCREEN
| Called by: NOSTRCH, DRTEXT_NOTFAST_CONT, DRTEXT, DRTEXT_NOCOLOR, STRDONE
NOSHAD_EXIT:
    MOVEA.L	-0x4(A6),A7                         | STRIP BUFFER
    MOVEM.L	(A7)+,D0-D7/A1-A4                   | RESTORE REGS
    UNLK	A6                                     | TEAR DOWN STACK FRAME
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDRESS
    ADDA.W	#0xE,A7                              | POP 14 BYTES OF PARAMETERS
    JMP	(A0)                                    | RETURN TO CALLER
