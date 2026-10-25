| --------------------------------------------------------------
|
| --> DRAWTEXT.TEXT
|
| QuickDraw Character Generator
|
| Completely reworked 29 Apr 85 by Bill Atkinson to get 50% speed up.
| Takes advantage of optional height table at end of font.
|

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
DrText:
        LINK    A6,#-0xC4                       | SET UP STACK FRAME

| -------------------------------------------
|
| KERNED STRIKE FONT FORMAT OFFSETS:
|
.set FORMAT, 0                                  | WORD
.set MINCHAR, 2                                 | WORD
.set MAXCHAR, 4                                 | WORD
.set MAXWD, 6                                   | WORD
.set FBBOX, 8                                   | WORD
.set FBBOY, 10                                  | WORD
.set FBBDX, 12                                  | WORD
.set FBBDY, 14                                  | WORD
.set LENGTH, 16                                 | WORD
.set ASCENT, 18                                 | WORD
.set DESCENT, 20                                | WORD
.set XOFFSET, 22                                | WORD
.set RASTER, 24                                 | WORD

| ------------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
.set PARAMSIZE, 14                              | SIZE OF PARAMETERS
.set COUNT, PARAMSIZE+8-2                       | WORD
.set TEXTADDR, COUNT-4                          | LONG
.set NUMER, TEXTADDR-4                          | LONG, POINT
.set DENOM, NUMER-4                             | LONG, POINT

| -----------------------------------------------------------
|
| A6 OFFSETS OF LOCAL VARIABLES AFTER LINK:
|
.set SAVESTK, -4                                | LONG
.set TEXTRECT, SAVESTK-8                        | RECT
.set TEXTR2, TEXTRECT-8                         | RECT
.set MINRECT, TEXTR2-8                          | RECT
.set BUFEND, MINRECT-4                          | LONG
.set BUFSTART, BUFEND-4                         | LONG
.set BUFSIZE, BUFSTART-2                        | WORD
.set BUFROW, BUFSIZE-2                          | WORD
.set BUFLEFT, BUFROW-2                          | WORD
.set BUF2START, BUFLEFT-4                       | LONG
.set BUF2END, BUF2START-4                       | LONG
.set HEIGHT, BUF2END-2                          | WORD
.set SRCBITS, HEIGHT-14                         | BITMAP
.set DSTBITS, SRCBITS-14                        | BITMAP
.set FAKERGN, DSTBITS-10                        | RECTANGULAR REGION
.set FAKEPTR, FAKERGN-4                         | LONG, FAKE MASTER POINTER
.set SRCADDR, FAKEPTR-4                         | LONG
.set SRCROW, SRCADDR-2                          | WORD
.set FASTFLAG, SRCROW-2                         | BYTE
.set PENLOC, FASTFLAG-4                         | POINT
.set SRCPTR, PENLOC-4                           | LONG
.set DSTPTR, SRCPTR-4                           | LONG
.set STRETCH, DSTPTR-2                          | BOOLEAN
.set FROMRECT, STRETCH-8                        | RECT
.set TORECT, FROMRECT-8                         | RECT
.set SRCRECT, TORECT-8                          | RECT
.set DSTRECT, SRCRECT-8                         | RECT
.set SPWIDTH, DSTRECT-4                         | FIXED POINT
.set CHARLOC, SPWIDTH-4                         | FIXED POINT
.set INFO, CHARLOC-8                            | 4 WORDS
.set HEIGHTAB, INFO-4                           | LONG
.set WIDTAB, HEIGHTAB-4                         | LONG
.set LOCTAB, WIDTAB-4                           | LONG
.set TOPHT, LOCTAB-2                            | word
.set HEIGHTFLAG, TOPHT-2                        | byte
.set MAXMIN, HEIGHTFLAG-2                       | word
.set MINCH, MAXMIN-2                            | word
.set SAVEA5, MINCH-4                            | LONG
.set NUMER2, SAVEA5-4                           | Point
.set DENOM2, NUMER2-4                           | Point
.set VARSIZE, DENOM2                            | SIZE OF VARIABLES

        MOVEM.L D0-D7/A1-A4,-(SP)               | SAVE REGS
        MOVE.L  A7,-0x4(A6)                     | REMEMBER WHERE STACK WAS
        MOVE.L  A5,-0xBC(A6)                    | REMEMBER GLOBAL PTR
        MOVE.L  (A5),A4                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A4),A3                         | GET CURRENT GRAFPORT
        MOVE.L  0xC(A6),-0xC0(A6)               | SAVE ORIGINAL NUMER
        MOVE.L  0x8(A6),-0xC4(A6)               | SAVE ORIGINAL DENOM

|
| Call StdTxMeas to swap font and measure width.
|
        CLR     -(SP)                           | ROOM FOR FCN RESULT
        MOVE    0x14(A6),-(SP)                  | PUSH COUNT
        BLE     NOSHAD_EXIT                     | QUIT IF COUNT <= 0

| STACK CLEANED UP BY SAVESTK
        MOVE.L  0x10(A6),-(SP)                  | PUSH TEXTADDR
        PEA.L   0xC(A6)                         | PUSH VAR NUMER
        PEA.L   0x8(A6)                         | PUSH VAR DENOM
        PEA.L   -0xA4(A6)                       | PUSH VAR INFO
        MOVE.L  (0xFB4).w,A0                    | _StdTxMeas (txMeasProc)
        JSR     (A0)                            | CALL TXMEASPROC TO MEASURE WIDTH
        MOVE    (SP)+,D1                        | POP UNSCALED WIDTH RESULT

|
| StdTxMeas also stashes FMOutPtr in QD global FONTPTR,
| and unscaled fixed point text width inn FixTxWid.
|
        MOVE.L  FONTPTR(A4),A4                  | POINT TO FMOUTPUT
        MOVE.L  0x2(A4),A2                      | GET FONT HANDLE
        MOVE.L  (A2),A2                         | DE-REFERENCE IT
        MOVE    0xE(A2),-0xB2(A6)               | INIT TOPHT IN CASE OLD FONT
        BTST    #0x0,0x1(A2)                    | DOES FONT HAVE HEIGHT TABLE ?
        SNE.B   -0xB4(A6)                       | SAVE COMPUTED VALUE

|
| Setup textRect, the rectangle bounding the entire string.
|
        MOVE.L  PNLOC(A3),D2                    | GET PEN LOCATION
        MOVE.L  D2,-0x6A(A6)                    | SAVE COMPUTED VALUE
        MOVE    D2,-0xA(A6)                     | SAVE TO TEXTRECT+LEFT
        ADD     D1,D2                           | ADD WIDTH TO PEN H
        MOVEQ   #7,D0                           | get mode mask
        AND     TXMODE(A3),D0                   | is txMode = srcCopy ?
        BEQ.B   NOSLOP                          | yes, don't add slop
        CMPI    #0x3,D0                         | IS TXMODE = SRCBIC ?
        BGT.B   NOSLOP                          | yes, don't add slop
        ADDI    #0x20,D2                        | ADD SLOP FOR ITALIC OVERHANG
NOSLOP:
        MOVE    D2,-0x6(A6)                     | SAVE TO TEXTRECT+RIGHT
        SWAP    D2                              | GET PNLOC.V
        SUB     0x12(A2),D2                     | SUBTRACT ASCENT
        MOVE    D2,-0xC(A6)                     | SAVE TO TEXTRECT+TOP
        ADD     0xE(A2),D2                      | ADD HEIGHT
        MOVE    D2,-0x8(A6)                     | SAVE TO TEXTRECT+BOTTOM
        MOVE.L  -0xC(A6),-0x14(A6)              | COPY BOUNDS TO EXTRA RECT
        MOVE.L  -0x8(A6),-0x10(A6)              | COPY BOUNDS TO EXTRA RECT

|
| Check for stretching
|
        MOVE.L  0xC(A6),D0                      | GET NUMERATOR
        CMP.L   0x8(A6),D0                      | ARE WE STRETCHING ?
        SNE.B   -0x74(A6)                       | SAVE BOOLEAN RESULT

        BEQ.B   NOSTRCH                         | CONTINUE IF NOT STRETCHING

|
| We will be stretching. Setup fromRect and toRect and map textR2.
|
        MULU    D0,D1                           | MULT WIDTH BY NUMER.H
        DIVU    0xA(A6),D1                      | DIVIDE BY DENOM+H
        MOVE.L  -0x6A(A6),D0                    | GET PENLOC
        MOVE.L  D0,-0x84(A6)                    | SAVE TO TORECT
        ADD     0xE(A6),D0                      | ADD NUMER+H
        MOVE    D0,-0x7E(A6)                    | SAVE TO TORECT+RIGHT
        SWAP    D0                              | GET PENLOC.V
        ADD     0xC(A6),D0                      | ADD NUMER
        MOVE    D0,-0x80(A6)                    | SAVE TO TORECT+BOTTOM
        MOVE.L  -0x6A(A6),D0                    | GET PENLOC
        MOVE.L  D0,-0x7C(A6)                    | SAVE TO FROMRECT
        ADD     0xA(A6),D0                      | ADD DENOM+H
        MOVE    D0,-0x76(A6)                    | SAVE TO FROMRECT+RIGHT
        SWAP    D0                              | GET PENLOC.V
        ADD     0x8(A6),D0                      | ADD DENOM
        MOVE    D0,-0x78(A6)                    | SAVE TO FROMRECT+BOTTOM
        PEA.L   -0x14(A6)                       | PUSH TEXTR2
        PEA.L   -0x7C(A6)                       | PUSH FROMRECT
        PEA.L   -0x84(A6)                       | PUSH TORECT
        JSR     MapRect(PC)                     | MAP TEXTR2 (PRESERVES ALL REGS)
NOSTRCH:
        ADD     D1,PNLOC+H(A3)                  | BUMP PEN BY (SCALED) TEXT WIDTH

|
| Quit if the pen is hidden
|
        TST     PNVIS(A3)                       | IS PNVIS < 0 ?
        BLT     NOSHAD_EXIT                     | YES, QUIT

|
| Calc minRect: the intersection of textRect, bitMap bounds,
| clipRgn and visRgn bounding boxes. Quit if no intersection.
|
        PEA.L   -0x14(A6)                       | PUSH (MAPPED) TEXTRECT

        PEA.L   PORTBOUNDS(A3)                  | PUSH BITMAP BOUNDS
        MOVE.L  CLIPRGN(A3),A0                  | GET CLIPRGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        PEA.L   RGNBBOX(A0)                     | PUSH CLIPRGN BBOX
        MOVE.L  VISRGN(A3),A0                   | GET VISRGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        PEA.L   RGNBBOX(A0)                     | PUSH VISRGN BBOX
        MOVE    #4,-(SP)                        | PUSH NRECTS=4
        PEA.L   -0x1C(A6)                       | PUSH DST ADDR
        JSR     RSect(PC)                       | CALC INTERSECTION
        BEQ     NOSHAD_EXIT                     | QUIT IF NO INTERSECTION

|
| Set up srcAddr, srcRow, and height
|
        LEA.L   0x1A(A2),A0                     | GET START OF FONT BITMAP
        MOVE.L  A0,-0x62(A6)                    | SAVE COMPUTED VALUE
        MOVE    0x18(A2),D1                     | GET WORDS PER ROW IN FONT

        ADD     D1,D1                           | DOUBLE FOR BYTES PER ROW
        MOVE    D1,-0x64(A6)                    | SAVE COMPUTED VALUE
        MOVE    0xE(A2),-0x34(A6)               | SETUP HEIGHT FOR LATER
        TST     0x6(A4)                         | ARE BOLD OR ITALIC SET ?

|
| Test for fast case:
| not stretched, no color mapping, txMode = srcOr,
| not bold, italic, underlined, outlined or shadowed,
| visRgn and clipRgn both rectangular.
|
        BNE     DRTEXT_NOTFAST                  | NOT FAST UNLESS BOTH ZERO
        CMPI    #0x1,TXMODE(A3)                 | IS TXMODE = SRCOR ?
        BNE     DRTEXT_NOTFAST                  | NO, NOT FAST
        TST     0xA(A4)                         | ARE ULTHICK OR SHADOW SET ?
        BNE     DRTEXT_NOTFAST                  | NOT FAST UNLESS BOTH ZERO
        TST.B   -0x74(A6)                       | IS TEXT STRETCHED ?
        BNE     DRTEXT_NOTFAST                  | YES, NOT FAST
        MOVE    COLRBIT(A3),D1                  | ARE WE COLOR MAPPING ?
        BMI.B   DRTEXT_NOCOLOR                  | YES, NO COLOR MAPPING
        MOVE.L  BKCOLOR(A3),D0                  | YES GET BACKGROUND COLOR
        NOT.L   D0                              | INVERT IT
        AND.L   FGCOLOR(A3),D0                  | AND WITH FOREGROUND COLOR
        BTST    D1,D0                           | IS THAT PLANE NORMAL ?
        BEQ     DRTEXT_NOTFAST                  | NO, NOT FAST
DRTEXT_NOCOLOR:
        MOVE.L  CLIPRGN(A3),A0                  | NOCOLOR: GET CLIPRGN HANDLE
        MOVE.L  (A0),A0                         | DE-REFERENCE IT
        MOVEQ   #10,D0                          | SIZE OF RECTANGULAR RGN
        CMP     (A0),D0                         | IS CLIPRGN RECTANGULAR ?
        BNE.B   DRTEXT_NOTFAST                  | NO, NOT FAST
        MOVE.L  VISRGN(A3),A1                   | GET VISRGN HANDLE
        MOVE.L  (A1),A0                         | DE-REFERENCE IT
        CMP     (A0),D0                         | IS VISRGN RECTANGULAR ?
        BEQ.B   FAST                            | YES, TAKE FAST OPTIMIZATION

|
| All systems go except for VisRgn not rectangular.
| Check if visRgn sect minRect is rectangular.
| IF TrimRect(visRgn,minRect) THEN take the fast way.
|
        MOVE.L  A1,-(SP)                        | PUSH VISRGN
        PEA.L   -0x1C(A6)                       | PUSH MINRECT
        JSR     TrimRect(PC)                    | CALL TRIMRECT
        BLT     NOSHAD_EXIT                     | quit if intersection empty
        BGT.B   DRTEXT_NOTFAST                  | continue if non-rectangular

|
| Fast case, go directly to screen.
| If text is clipped vertically, then clear heightflag and update TOPHT
|
| Called during boot.
FAST:
        ST.B    -0x66(A6)                       | REMEMBER WE'RE GOING FAST
        MOVE    -0x1C(A6),D0                    | GET MINRECT TOP
        MOVE    -0x18(A6),D1                    | GET MINRECT BOTTOM
        SUB     -0xC(A6),D0                     | SUBTRACT TEXTRECT TOP

        BNE.B   VCLIP                           | yes, handle clip
        CMP     -0x8(A6),D1                     | IS MINRECT BOTTOM >= TEXTRECT BOTTOM ?
        BEQ.B   VCLIP_NO                        | no, continue
VCLIP:
        CLR.B   -0xB4(A6)                       | can't use height table
        MOVE.B  D0,-0xB2(A6)                    | use adjusted top
        SUB     -0x1C(A6),D1                    | CALC BUF HEIGHT = BOTTOM - TOP
        MOVE.B  D1,-0xB1(A6)                    | SAVE HEIGHT TO HEIGHTFLAG
VCLIP_NO:
        MOVE    -0xC(A6),D0                     | GET TEXTRECT TOP
        SUB     0x8(A3),D0                      | SUBTRACT PORTBOUNDS TOP
        MULS    0x6(A3),D0                      | MULTIPLY BY PORT ROWBYTES
        ADD.L   0x2(A3),D0                      | ADD BASEADDR
        MOVE.L  D0,-0x24(A6)                    | SET UP BUFSTART FOR LATER
        MOVE    0x6(A3),-0x28(A6)               | SAVE PORT ROWBYTES TO DSTROW
        MOVE    0xA(A3),-0x2A(A6)               | SAVE PORTBOUNDS LEFT
        PEA.L   -0x1C(A6)                       | PUSH SHIELD RECT
        MOVE.L  0x8(A3),-(SP)                   | PUSH PORTBOUNDS TOP/LEFT
        JSR     ShieldCursor(PC)                | HIDE CURSOR IF IT INTERSECTS
        BRA     GETPTRS                         | BRANCH TO GETPTRS

|
| Slow case: Setup for an off-screen buffer.
|
| Calc bufLeft: (word-align to avoid shift)
|
| Called during boot.
DRTEXT_NOTFAST:
        CLR.B   -0x66(A6)                       | NOT GOING DIRECTLY TO SCREEN
        MOVE    -0xA(A6),D0                     | GET TEXTRECT LEFT
        SUB     0xA(A3),D0                      | SUBTRACT PORTBOUNDS LEFT
        ANDI    #-0x10,D0                       | TRUNCATE TO 16-BIT BOUNDARY
        SUBI    #0x20,D0                        | SUBTRACT SLOP
        ADD     0xA(A3),D0                      | ADD PORTBOUNDS LEFT
        MOVE    D0,-0x2A(A6)                    | SAVE COMPUTED VALUE
        MOVE    -0x6(A6),D1                     | SAVE TO BUFLEFT
|
| Calculate buffer size
|
        SUB     D0,D1                           | WIDTH:=BUFRIGHT-BUFLEFT
        LSR     #5,D1                           | CONVERT DOTS TO LONGS
        ADDQ.W  #0x2,D1                         | ROUND UP DOTS TO LONGS AND ADD SLOP
        MOVE    -0x34(A6),D3                    | GET HEIGHT
        MULU    D1,D3                           | BUFSIZE:=HEIGHT*BUFROW LONGS
        MOVE    D3,-0x26(A6)                    | SAVE COMPUTED VALUE
        LSL     #2,D1                           | QUAD BUFROW FOR BYTES
        MOVE    D1,-0x28(A6)                    | SAVE COMPUTED VALUE

|
| Calculate total stack requirements for off-screen buffers.
|
        MOVE.L  D3,D2                           | GET BUFSIZE LONGS
        TST.B   0xB(A4)                         | ARE WE SHADOWING ?
        BEQ     DRTEXT_NOTFAST_CONT             | BRANCH IF EQUAL
        ADD.L   D2,D2                           | YES, CALC 2*BUFSIZE
        EXT.L   D1                              | SIGN EXTEND BUFROW
        ADD.L   D1,D2                           | CALC TOTAL LONGS
DRTEXT_NOTFAST_CONT:
        LSL.L   #0x2,D2                         | CONVERT LONGS TO BYTES
        ADDI.L  #0x400,D2                       | ADD 1K BYTES FOR EXTRA STACK MARGIN
        MOVE.L  A7,D0                           | GET CURRENT STACK POINTER
        SUB.L   (HeapEnd).w,D0                  | SUBTRACT (HeapEnd).w

|
| If stack is too small to allocate buffer(s), then recursively call
| DrText with the left half and the right half of the text string.
|
| _StackAvail ;Get StackAvail IN D0
        CMP.L   D0,D2                           | IS stackNeeded > stackAvail ?
        BLE.B   DRTEXT_NOTFAST_NO               | NO, CONTINUE
        MOVE.L  -0x6A(A6),PNLOC(A3)             | GET PENLOC
        MOVE    0x14(A6),D7                     | GET CHARACTER COUNT
        LSR     #1,D7                           | DIVIDE IN HALF
        BEQ     NOSHAD_EXIT                     | GIVE UP IF COUNT WAS ONLY ONE
        MOVE    D7,-(SP)                        | PUSH NEW COUNT
        MOVE.L  0x10(A6),-(SP)                  | PUSH TEXTADDR
        MOVE.L  -0xC0(A6),-(SP)                 | PUSH ORIGINAL NUMER
        MOVE.L  -0xC4(A6),-(SP)                 | PUSH ORIGINAL DENOM
        JSR     DrText(PC)                      | DRAW THE FIRST HALF
        MOVE    0x14(A6),D0                     | GET ORIGINAL CHARACTER COUNT
        SUB     D7,D0                           | SUBTRACT CHARS ALREADY DONE
        MOVE    D0,-(SP)                        | PUSH NEW COUNT
        MOVE.L  0x10(A6),A0                     | GET ORIGINAL TEXTADDR
        ADD     D7,A0                           | BUMP PAST CHARS ALREADY DONE
        MOVE.L  A0,-(SP)                        | PUSH NEW TEXTADDR
        MOVE.L  -0xC0(A6),-(SP)                 | PUSH ORIGINAL NUMER
        MOVE.L  -0xC4(A6),-(SP)                 | PUSH ORIGINAL DENOM
        JSR     DrText(PC)                      | DRAW THE SECOND HALF
        BRA     NOSHAD_EXIT                     | AND QUIT !

| ----------------------------------------------------------
|
| DRTEXT_NOTFAST_NO
|
| Called during boot.
DRTEXT_NOTFAST_NO:
        SUBQ.W  #0x1,D3                         | ADJUST BUFSIZE FOR DBF LOOP

|
| Allocate and clear an off-screen buffer
|
        CLR.L   -(SP)                           | PAD BUFFER WITH AN EXTRA ZERO
        MOVE.L  A7,-0x20(A6)                    | REMEMBER WHERE BUFFER ENDS
CLRLOOP:
        CLR.L   -(SP)                           | CLEAR ONE LONG OF BUFFER
        DBF     D3,CLRLOOP                      | ALLOCATE AND CLEAR BUFFER
        MOVE.L  A7,-0x24(A6)                    | REMEMBER START OF BUFFER
        CLR.L   -(SP)                           | PAD BUFFER WITH AN EXTRA ZERO

|
| Get pointers to location table, width table, and height table in font
|
| Called during boot.
GETPTRS:
        LEA.L   0x1A(A2),A0                     | GET START OF FONT BITMAP
        MOVE    0xE(A2),D0                      | GET HEIGHT OF FONT BITMAP
        MULU    -0x64(A6),D0                    | CALC TOTAL SIZE OF STRIKE

|
| Get pointers to location table, width table, and height table in font
|
        ADD.L   D0,A0                           | A1 := START OF LOC TABLE
        MOVE.L  A0,-0xB0(A6)                    | SAVE COMPUTED VALUE
        CLR.L   D0                              | get ready for unsigned word
        MOVE    0x10(A2),D0                     | HOW MANY WORDS IN STRIKE BODY
        ADD.L   D0,D0                           | DOUBLE FOR BYTECOUNT
        LEA.L   0x10(A2,D0.L),A1                | GET START OF WIDTH TABLE
        MOVE.L  A1,-0xAC(A6)                    | SAVE COMPUTED VALUE
        MOVE    0x4(A2),D0                      | GET MAXCHAR
        MOVE    0x2(A2),D1                      | GET MINCHAR
        MOVE    D1,-0xB8(A6)                    | STASH MINCHAR FOR LATER
        SUB     D1,D0                           | CALC MAXCHAR-MINCHAR
        MOVE    D0,-0xB6(A6)                    | SAVE COMPUTED VALUE | SIZE OF HEIGHT TABLE
        ADDQ.W  #0x3,D0                         | ADD 3 FOR MISSING SYMBOL AND EXTRAS
        ADD     D0,D0                           | CALC 2*(MAX-MIN+3)
        BTST    #0x1,0x1(A2)                    | DOES FONT HAVE WIDTH TABLE ?
        BEQ.B   GETPTRS_NO                      | NO, CONTINUE
        ADD     D0,D0                           | YES, SKIP OVER WIDTH TABLE
GETPTRS_NO:
        LEA.L   0x0(A1,D0.W),A0                 | CALC ADDRESS OF HEIGHT TABLE
        MOVE.L  A0,-0xA8(A6)                    | SAVE COMPUTED VALUE

|
| Set up space width
|
        MOVE.L  (WidthPtr).w,A0                 | point to width table
        MOVE.L  0x80(A0),-0x98(A6)              | get width of the space char

|
| Setup misc stuff in registers for speed
|
        MOVE    -0x2A(A6),D1                    | GET BUFLEFT
        MOVE    -0x68(A6),D0                    | GET PENLOC.H
        ADD     0x8(A2),D0                      | ADJUST FOR KERNING

        SUB     D1,D0                           | MAKE CHARLOC RELATIVE TO BUFLEFT
        MOVE    D0,-0x9C(A6)                    | SAVE INITIAL CHARLOC (INT PART)
        MOVE    #-0x8000,-0x9A(A6)              | SET CHARLOC FRACT PART TO 0.5
        SUB     D1,-0x1A(A6)                    | OFFSET MINRECT LEFT BY BUFLEFT
        SUB     D1,-0x16(A6)                    | OFFSET MINRECT RIGHT BY BUFLEFT
        MOVE.L  0x10(A6),A1                     | GET TEXTPTR
        BRA.B   NEXTCH                          | GO TO LOOP START

| ---------------------------------------------------
|
| Here's the main character drawing loop:
|
| Called during boot.
SPACECH:
        MOVE.L  -0x98(A6),D1                    | GET SPACE WIDTH
        ADD.L   D1,-0x9C(A6)                    | BUMP CHARLOC
SKIPCH:
        SUBQ.W  #0x1,0x14(A6)                   | DECREMENT CHAR COUNT

| ---------------------------------------------------
|
| Here's the main character drawing loop:
|
        BLE     STRDONE                         | QUIT IF CHARCOUNT <= 0
NEXTCH:
        CLR     D0                              | get ready for byte
        MOVE.B  (A1)+,D0                        | GET NEXT CHAR
        CMPI.B  #0x20,D0                        | IS IT A SPACE CHARACTER?
        BEQ.B   SPACECH                         | YES, HANDLE IT
        MOVE.L  (WidthPtr).w,A0                 | POINT TO WIDTH TABLE
        MOVE    D0,D4                           | COPY CHARACTER
        LSL     #2,D4                           | QUAD FOR TABLE OFFSET
        MOVE.L  0x0(A0,D4.W),D4                 | GET FIXED POINT WIDTH FOR CHAR
        SUB     -0xB8(A6),D0                    | SUBTRACT SAVED MINCHAR
        CMP     -0xB6(A6),D0                    | IS CH BETWEEN MINCHAR AND MAXCHAR ?
        BLS.B   OKCHAR                          | YES, CONTINUE
MISSING:
        MOVE    -0xB6(A6),D0                    | NO, USE MISSING SYMBOL
        ADDQ.W  #0x1,D0                         | ADD 1 FOR MISSING SYMBOL INDEX
        ADD     D0,D0                           | INDEX := 2*(MISSING-MINCHAR)
        MOVE.L  -0xAC(A6),A0                    | POINT TO WIDTH TABLE
        MOVE    0x0(A0,D0.W),D3                 | GET WIDTH OFFSET FROM TABLE
        BPL.B   NOTMISS                         | IS MISSING CHAR MISSING ?
        BRA.B   NEXTCH                          | YES, SKIP THIS CHAR

| ----------------------------------------------------------
|
| OKCHAR
|
| Called during boot.
OKCHAR:
        ADD     D0,D0                           | INDEX := 2*(ASCII-MINCHAR)
        MOVE.L  -0xAC(A6),A0                    | POINT TO WIDTH TABLE
        MOVE    0x0(A0,D0.W),D3                 | GET WIDTH OFFSET FROM TABLE
        BMI.B   MISSING                         | OFFSET NEG = MISSING CHAR
NOTMISS:
        LSR     #8,D3                           | GET OFFSET BYTE
        ADD     -0x9C(A6),D3                    | ADD CHARLOC INT PART TO SRC OFFSET
        ADD.L   D4,-0x9C(A6)                    | ADD FIXED POINT WIDTH TO CHARLOC
        MOVE.L  -0xB0(A6),A0                    | POINT TO LOCATION TABLE
        MOVE    0x0(A0,D0.W),D1                 | GET START OFFSET FROM LOC TABLE
        MOVE    0x2(A0,D0.W),D2                 | GET END OFFSET FROM LOC TABLE
        SUB     D1,D2                           | CALC WIDTH OF BITS
        BLE.B   SKIPCH                          | SKIP CHARBLT IF WIDTH <= 0
        ADD     D3,D2                           | DSTRIGHT := DSTLEFT + WIDTH
        TST.B   -0xB4(A6)                       | does font have height table ?
        BEQ.B   NOTMISS_NO                      | no, continue
        MOVE.L  -0xA8(A6),A0                    | get height table
        MOVE    0x0(A0,D0.W),-0xB2(A6)          | SAVE CHAR TOP TO TOPHT

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
        TST.B   -0x66(A6)                       | ARE WE GOING FAST ?

| NOHEIGHT

| -----------------------------------------------------------------------
|
| Horizontal clip only if FastFlag: (else stretch,outline,shadow,italic die)
|
| skip if hidden on left, string done if hidden on right.
|
| at this point: D1: srcLeft
| D2: dstRight
| D3: dstLeft
|
        BEQ.B   HORIZOK                         | NO, DON'T CLIP
        CMP     -0x1A(A6),D3                    | COMPARE MINRECT+LEFT
        BGE.B   NOTMISS_NO_2                    | NO, CONTINUE
        CMP     -0x1A(A6),D2                    | COMPARE MINRECT+LEFT
        BLE     SKIPCH                          | YES, SKIP THIS CHAR
        MOVE    -0x1A(A6),D0                    | GET MINRECT+LEFT
        SUB     D3,D0                           | DISCARD:=MINRECT.LEFT-DSTLEFT
        ADD     D0,D1                           | SRCLEFT:=SRCLEFT+DISCARD
        ADD     D0,D3                           | DSTLEFT:=DSTLEFT+DISCARD
        CMP     -0x16(A6),D2                    | COMPARE MINRECT+RIGHT
        BLE.B   HORIZOK                         | NO, CONTINUE
        BRA.B   TRIMRT                          | YES, TRIM RIGHT

| ----------------------------------------------------------
|
| NOTMISS_NO_2
|
| Called during boot.
NOTMISS_NO_2:
        CMP     -0x16(A6),D2                    | COMPARE MINRECT+RIGHT
        BLE.B   HORIZOK                         | YES, CONTINUE
        CMP     -0x16(A6),D3                    | COMPARE MINRECT+RIGHT
        BGE     STRDONE                         | YES, IGNORE REST OF STRING
TRIMRT:
        MOVE    -0x16(A6),D2                    | GET MINRECT+RIGHT

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
        MOVE    D3,D5                           | COPY DSTLEFT
        SUB     D1,D5                           | SUB SRC LEFT
        MOVEQ.L #0xF,D0                         | get a 4 bit mask
        AND     D0,D5                           | SHIFTCNT:=DELTA HORIZ MOD 16

|
| Setup srcAddr in A4, address of leftmost word
|
        MOVE.L  -0x62(A6),A4                    | GET START OF SRC BITMAP

        ADD     D5,D1                           | CALC SRCLEFT+SHIFTCNT
        ASR     #4,D1                           | CONVERT FROM DOTS TO WORDS
        ADD     D1,D1                           | DOUBLE FOR BYTES
        SUBQ.W  #0x2,D1                         | BACK UP ONE WORD FOR SRC
        ADD     D1,A4                           | LEAVE SRCPTR IN A4

|
| Setup dstPtr in A5, address of leftmost dst word
|
        MOVE.L  -0x24(A6),A5                    | GET START OF DST BITMAP

        MOVE    D3,D1                           | GET A COPY OF DSTLEFT
        ASR     #4,D1                           | CONVERT FROM DOTS TO WORDS
        ADD     D1,A5                           | ADD TO DSTPTR
        ADD     D1,A5                           | TWICE FOR BYTES

|
| Setup leftMask in D3 and rightMask in D4
|
        LEA.L   DT_mMaskTab(PC),A0              | point to mask table
        AND     D0,D3                           | get bottom 4 bits of dstLeft
        ADD     D3,D3                           | double for table index
        MOVE    0x0(A0,D3.W),D3                 | GET MASK FOR LEFT EDGE
        NOT     D3                              | invert it for leftMask
        MOVE    D2,D6                           | copy dstRight
        AND     D0,D2                           | get bottom 4 bits of dstRight
        ADD     D2,D2                           | double for table index
        MOVE    0x0(A0,D2.W),D4                 | GET MASK FOR RIGHT EDGE

|
| Get srcRow, dstRow, and char height into regs
|
        MOVE    -0x64(A6),A2                    | GET SRCROW
        MOVE    -0x28(A6),A3                    | GET BUFROW
        MOVE    #0xFF,D7                        | INIT ROW COUNTER HIGH BYTE
        ADD.B   -0xB1(A6),D7                    | ADD BUFHEIGHT-1 TO ROW COUNTER

        BMI     SKIPCH                          | OOPS HEIGHT WAS ZERO !

|
| Adjust srcPtr and dstPtr for charTop
|
        CLR.W   D0                              | get ready for byte
        MOVE.B  -0xB2(A6),D0                    | get char top
        MOVE    A2,D2                           | get srcRow in D-reg
        MULU    D0,D2                           | calc charTop * srcRow
        ADD.L   D2,A4                           | add to srcPtr
        MOVE    A3,D2                           | get dstRow in D-reg
        MULU    D0,D2                           | calc charTop * dstRow
        ADD.L   D2,A5                           | add to dstPtr

|
| Branch based on total number of dst words
|
        ASR     #4,D6                           | CALC (DSTRIGHT) DIV 16
        SUB     D1,D6                           | CALC TOTAL NUMBER OF WORDS-1
        BEQ.B   WORD1                           | BR IF DST ALL IN ONE WORD
        SUBQ.W  #0x1,D6                         | ADJUST DST WORD COUNT FOR DBF
        BEQ.B   LONG1                           | BR IF DST ALL IN ONE LONG
        ADDQ.W  #0x1,D7                         | ADJUST ROW COUNT FOR DBF
        BRA.B   WIDE1                           | DST WIDER THAN ONE LONG

|
| Slow loop only taken in wierd cases where dst wider than a long.
|
MAIN1:
        MOVE.L  (A4),D0                         | GET SRC FROM BITMAP
        ADDQ.W  #0x2,A4                         | BUMP SRCPTR TO NEXT WORD
        LSR.L   D5,D0                           | ALIGN TO DST
        AND     D1,D0                           | MASK EXTRA TO ZEROS
        OR      D0,(A5)+                        | OR SRC INTO DST
        MOVEQ   #-1,D1                          | FLUSH MASK
        DBF     D2,MAIN1                        | LOOP TILL LAST WORD
        MOVE.L  (A4),D0                         | GET SRC FROM BITMAP
        LSR.L   D5,D0                           | ALIGN TO DST
        AND     D4,D0                           | MASK WITH RIGHTMASK
        OR      D0,(A5)                         | OR SRC INTO DST
        MOVE.L  -0x6E(A6),A4                    | RESTORE SRCPTR TO LEFT
        ADD     A2,A4                           | BUMP TO NEXT ROW
        MOVE.L  -0x72(A6),A5                    | RESTORE DSTPTR TO LEFT
        ADD     A3,A5                           | BUMP DST TO NEXT ROW
WIDE1:
        MOVE.L  A4,-0x6E(A6)                    | REMEMBER SRCPTR AT LEFT
        MOVE.L  A5,-0x72(A6)                    | REMEMBER DSTPTR AT LEFT
        MOVE    D3,D1                           | MASK:=LEFTMASK
        MOVE    D6,D2                           | GET WORDCOUNT
        DBF     D7,MAIN1                        | LOOP ALL ROWS
        SUBQ.W  #0x1,0x14(A6)                   | DECREMENT CHAR COUNT
        BGT     NEXTCH                          | LOOP IF MORE CHARS LEFT
        BRA     STRDONE                         | QUIT IF CHARCOUNT <= 0

| ----------------------------------------------------------
|
| LONG1
|
| Called during boot.
LONG1:
        SUBQ.W  #0x2,A3                         | ADJUST DSTROW TO ACCOUNT FOR POST-INCREMENT

|
| Optimize if dst fits in one long. (30% of normal characters do)
|
| Called during boot.
LONG1A:
        MOVE.L  (A4),D0                         | GET SRC DATA
        LSR.L   D5,D0                           | ALIGN TO DST
        AND     D3,D0                           | MASK EXTRA WITH LEFTMASK
        OR      D0,(A5)+                        | OR RESULT INTO DST
        MOVE.L  0x2(A4),D0                      | GET SECOND WORD OF SRC
        LSR.L   D5,D0                           | ALIGN IT
        AND     D4,D0                           | MASK EXTRA WITH RIGHTMASK
        OR      D0,(A5)                         | OR RESULT INTO DST
        ADD     A2,A4                           | BUMP SRCPTR TO NEXT ROW
        ADD     A3,A5                           | BUMP DSTPTR TO NEXT ROW
        DBF     D7,LONG1A                       | LOOP ALL ROWS
        SUBQ.W  #0x1,0x14(A6)                   | DECREMENT CHAR COUNT
        BGT     NEXTCH                          | LOOP IF MORE CHARS LEFT
        BRA     STRDONE                         | QUIT IF CHARCOUNT <= 0

|
| Optimize if dst fits in one word. (70% of normal characters do)
|
| Called during boot.
WORD1:
        AND     D4,D3                           | COMBINE LEFT AND RIGHT MASKS
WORD1B:
        MOVE.L  (A4),D0                         | GET SRC DATA
        LSR.L   D5,D0                           | ALIGN TO DST
        AND     D3,D0                           | MASK EXTRA TO ZEROS
        OR      D0,(A5)                         | OR RESULT INTO DST
        ADD     A2,A4                           | BUMP SRCPTR TO NEXT ROW
        ADD     A3,A5                           | BUMP DSTPTR TO NEXT ROW
        DBF     D7,WORD1B                       | LOOP ALL ROWS
        SUBQ.W  #0x1,0x14(A6)                   | DECREMENT CHAR COUNT
        BGT     NEXTCH                          | LOOP IF MORE CHARS LEFT
STRDONE:
        MOVE.L  -0xBC(A6),A5                    | RESTORE GLOBAL PTR
        TST.B   -0x66(A6)                       | WERE WE GOING DIRECT TO SCREEN ?
        BEQ.B   STRDONE_CONT                    | BRANCH IF EQUAL
        JSR     ShowCursor(PC)                  | YES, RESTORE CURSOR
        BRA     NOSHAD_EXIT                     | AND QUIT

| ----------------------------------------------------------
|
| STRDONE_CONT
|
| Called during boot.
STRDONE_CONT:
        MOVE.L  (A5),A0                         | GET QUICKDRAW GLOBALS POINTER
        MOVE.L  (A0),A3                         | GET CURRENT GRAFPORT
        MOVE.L  FONTPTR(A0),A4                  | POINT TO FMOUTPUT
        MOVE.L  0x2(A4),A2                      | GET FONT HANDLE
        MOVE.L  (A2),A2                         | DE-REFERENCE IT
        MOVE    -0x9C(A6),D7                    | GET FINAL CHARLOC INT PART
        SUB     0x8(A2),D7                      | UN-ADJUST FROM KERNING

|
| Make buffer bold if necessary:
|
| Called during boot.
CKBOLD:
        CLR     D2                              | GET READY FOR BYTE
        MOVE.B  0x6(A4),D2                      | GET NUMBER OF OVERSTRIKES
        BRA.B   NXTBOLD                         | BOLD BUFFER IF ANY

| ----------------------------------------------------------
|
| BOLDIT
|
| Called during boot.
BOLDIT:
        MOVE.L  -0x24(A6),A0                    | POINT TO START OF BUFFER
        MOVE    -0x26(A6),D1                    | HOW MANY LONGS IN BUF
        SUB     D0,D0                           | CLEAR X-BIT
BOLDLP:
        MOVE.L  (A0),D0                         | GET ONE LONG
        ROXR.L  #1,D0                           | ROTATE RIGHT WITH EXTEND
        OR.L    D0,(A0)+                        | OR BACK INTO BUFFER
        DBF     D1,BOLDLP                       | LOOP ENTIRE BUFFER
NXTBOLD:
        DBF     D2,BOLDIT                       | LOOP FOR EACH OVERSTRIKE

|
| Slant the buffer if necessary:
| Work from bottom of buffer up, shifting each row right.
| Work right to left to avoid clobbering src.
|
        CLR     D2                              | GET READY FOR BYTE
        MOVE.B  0x7(A4),D2                      | DO WE NEED ITALIC ?
        BEQ.B   CHECKUL                         | NO, CONTINUE
        MOVE.L  -0x20(A6),A1                    | DSTPTR:=END OF BUFFER
        MOVE    -0x28(A6),D3                    | GET BUFFER ROWBYTES
        SUB     D3,A1                           | BACK UP DSTPTR TO END OF 2ND ROW
        LSR     #1,D3                           | WORDCNT:=ROWBYTES DIV 2
        SUBQ.W  #0x1,D3                         | ADJUST BUFSIZE FOR DBF LOOP
        MOVE    -0x34(A6),D6                    | INIT ROW COUNTER
        CLR     D4                              | INIT OFFSET
        BRA.B   DOSLANT                         | GO TO LOOP START

| ----------------------------------------------------------
|
| NXTROW
|
NXTROW:
        ADD     D2,D4                           | OFFSET:=OFFSET+ITALIC
        MOVE    D4,D0                           | COPY OFFSET
        LSR     #4,D0                           | DELTA := OFFSET SCALED BY 16
        MOVEQ.L #0xF,D5                         | GET A 4-BIT MASK
        AND     D0,D5                           | SHIFTCNT:=DELTA MOD 16
        LSR     #4,D0                           | DELWORD:=DELTA DIV 16
        MOVE.L  A1,A0                           | SRCPTR:=DSTPTR
        SUBQ.W  #0x4,A0                         | BACK UP TWO WORDS
        SUB     D0,A0                           | SUBTRACT DELWORD
        SUB     D0,A0                           | TWICE BECAUSE WORDS
        MOVE    D3,D1                           | INIT LOOP TO WORDCNT
NXTWORD:
        MOVE.L  (A0),D0                         | GET A LONG OF SRC
        SUBQ.W  #0x2,A0                         | BACK UP SRC PTR ONE WORD
        LSR.L   D5,D0                           | SHIFT SRC TO ALIGN WITH DST
        MOVE    D0,-(A1)                        | STORE IN DST AND BUMP DSTPTR
        DBF     D1,NXTWORD                      | LOOP ALL WORDS THIS ROW
DOSLANT:
        DBF     D6,NXTROW                       | LOOP FOR ALL ROWS IN BUFFER

|
| Underline characters in buffer if necessary.
|
| Use characters in buffer to hide parts of the underline.
|
| Called during boot.
CHECKUL:
        TST.B   0xA(A4)                         | IS ULTHICK ZERO ?

        BEQ     NOTUL                           | YES, CONTINUE
        MOVE.L  -0x24(A6),A0                    | POINT TO BUFFER START
        MOVE    -0x28(A6),D1                    | GET BYTES PER ROW OF BUFFER
        MOVE    0x12(A2),D0                     | GET ASCENT
        MOVE    0x14(A2),D2                     | GET DESCENT
        MULU    D1,D0                           | CALC ASCENT * BYTES PER ROW
        ADD.L   D0,A0                           | POINT TO BASELINE ROW
        MOVE.L  A0,A1                           | SET BASELINE+1 PTR
        MOVE.L  A0,A2                           | SET BASELINE+2 PTR
        ADD     D1,A1                           | POINT TO BASELINE+1
        CMPI    #0x2,D2                         | IS DESCENT LESS THAN 2?
        BLT.B   NOTUL                           | NO, SKIP UNDERLINE
        BEQ.B   ONLY2                           | ONLY USE 2 IF DESCENT=2
        ADD     D1,A2                           | ADD ROWBYTES TO A2
        ADD     D1,A2                           | POINT TO BASELINE+2
ONLY2:
        SUB     D1,SP                           | ALLOCATE TEMP SCANBUF
        MOVE.L  A3,-(SP)                        | SAVE GRAFPORT
        LEA.L   0x4(SP),A3                      | POINT TO START OF TEMP
        LSR     #2,D1                           | CONVERT BYTES TO LONGS
        SUBQ.W  #0x1,D1                         | ADJUST LONG COUNT FOR DBF
        MOVE    D1,D2                           | COPY LOOP COUNT
        SUB     D0,D0                           | CLEAR X-BIT
UL1:
        MOVE.L  (A0)+,D0                        | GET FROM BASELINE
        OR.L    (A1)+,D0                        | OR WITH BASELINE+1
        OR.L    (A2)+,D0                        | OR WITH BASELINE+2
        MOVE.L  D0,(A3)                         | PUT RESULT TO TEMP
        ROXR.L  #1,D0                           | SHIFT WITH CARRY
        OR.L    D0,(A3)+                        | OR INTO TEMP
        DBF     D1,UL1                          | LOOP ALL LONGS IN ROW
        MOVE.L  A1,A0                           | COPY END PTR
        SUB     D0,D0                           | CLEAR X-BIT
UL2:
        MOVE.L  -(A3),D0                        | GET FROM TEMP
        ROXL.L  #1,D0                           | SHIFT LEFT WITH CARRY
        OR.L    (A3),D0                         | OR WITH TEMP
        NOT.L   D0                              | INVERT
        OR.L    D0,-(A1)                        | DRAW SOME UNDERLINE
        DBF     D2,UL2                          | LOOP ALL LONGS IN ROW
        MOVE.L  (SP)+,A3                        | RESTORE GRAFPORT

|
| Trim right edge of underline. (left edge trimmed by StretchBits)
|
        MOVE    -0x28(A6),D0                    | GET BYTES PER ROW OF BUFFER

        LSL     #3,D0                           | TIMES 8 FOR DOTS WIDE
        SUB     D7,D0                           | OVERSHOOT:=BUFRIGHT-LASTRIGHT
        SUBQ.W  #0x1,D0                         | ADJUST LONG COUNT FOR DBF
        LSR     #4,D0                           | CONVERT DOTS TO WORDCOUNT
        BRA.B   UL3                             | GO TO LOOP START

| ----------------------------------------------------------
|
| ULTRIM
|
ULTRIM:
        CLR     -(A0)                           | ERASE SOME UNDERLINE
UL3:
        DBF     D0,ULTRIM                       | LOOP ALL FULL WORDS
        ADD     -0x2A(A6),D7                    | UNDO BUFFER RELATIVE
        MOVE    D7,D0                           | GET LAST RIGHT COORD
        SUB     0xA(A3),D0                      | SUBTRACT PORTBITS+BOUNDS+LEFT
        JSR     RightMask(PC)                   | COMPUTE A MASK
        AND     D0,-(A0)                        | ERASE LAST PARTIAL WORD
NOTUL:
        MOVE    #0xA,-0x5A(A6)                  | SAVE TO FAKEPTR
        MOVE.L  0x8(A3),-0x58(A6)               | GET PORTBITS+BOUNDS+TOP
        MOVE.L  0xC(A3),-0x54(A6)               | SET FAKERGN BOTTOM/RIGHT BOUNDS

|
| Setup fakeRgn, a dummy rectangular region
|
        LEA.L   -0x5A(A6),A0                    | GET ADDR OF FAKERGN
        MOVE.L  A0,-0x5E(A6)                    | POINT FAKE MASTERPTR TO IT

|
| Setup bitMaps to transfer from buffer to screen.
|
| srcBits := buffer
|
        LEA.L   -0x42(A6),A0                    | POINT TO SRCBITS
        MOVE.L  -0x24(A6),(A0)+                 | SET UP BASEADDR
        MOVE    -0x28(A6),(A0)+                 | SET UP ROWBYTES
        MOVE    -0xC(A6),(A0)+                  | SET UP BOUNDS TOP
        MOVE    -0x2A(A6),(A0)+                 | SET UP BOUNDS LEFT
        MOVE.L  -0x8(A6),(A0)+                  | SET UP BOUNDS BOTTOM AND RIGHT

|
| dstBits := portBits
|

        LEA.L   PORTBITS(A3),A2                 | POINT TO PORTBITS
        LEA.L   -0x50(A6),A0                    | POINT TO DSTBITS
        MOVE.L  (A2)+,(A0)+                     | COPY BASEADDR
        MOVE    (A2)+,(A0)+                     | COPY ROWBYTES
        MOVE.L  (A2)+,(A0)+                     | COPY BOUNDS.TOPLEFT
        MOVE.L  (A2)+,(A0)+                     | COPY BOUNDS.BOTRIGHT

|
| check if any shadowing:
|
        CLR     D3                              | GET READY FOR BYTE
        MOVE.B  0xB(A4),D3                      | GET SHADOW COUNT
        BEQ     NOSHAD                          | SKIP IF NO SHADOWING

|
| Shadowing will be used. Allocate buf2, 4 scans taller than BUF1.
| Clear out new 4 scanlines, and copy BUF1 into the rest.
|
        MOVE    -0x28(A6),D0                    | GET 4 * NUMBER OF LONGS PER ROW
        SUBQ.W  #0x1,D0                         | ADJUST LONG COUNT FOR DBF

        CLR.L   -(SP)                           | ALLOW ONE LONG OF SLOP
        MOVE.L  A7,-0x32(A6)                    | REMEMBER END OF BUF2
CLR2:
        CLR.L   -(SP)                           | ALLOCATE AND CLEAR A LONG
        DBF     D0,CLR2                         | CLEAR 4 SCANLINES WORTH
        MOVE    -0x26(A6),D0                    | GET NUMBER OF LONGS IN BUF1
        SUBQ.W  #0x1,D0                         | ADJUST LONG COUNT FOR DBF
        MOVE.L  -0x20(A6),A0                    | POINT TO END OF BUF1
COPYLP:
        MOVE.L  -(A0),-(SP)                     | COPY FROM BUF1 TO NEW BUF2
        DBF     D0,COPYLP                       | COPY ALL OF BUF1
        MOVE.L  A7,-0x2E(A6)                    | REMEMBER START OF BUF2
        CLR.L   -(SP)                           | ALLOW ONE LONG OF SLOP
        ANDI    #0x3,D3                         | LIMIT SHADOW OFFSET TO 3

|
| Bold buf2 across to the right enough for shadow.
|
        MOVE    D3,D2                           | INIT BOLD COUNTER
ACROSS1:
        MOVE.L  -0x2E(A6),A0                    | POINT TO START OF BUFFER2
        MOVE    -0x26(A6),D1                    | INIT COUNT OF LONGS
        SUB     D0,D0                           | CLEAR X-BIT
ACROSS2:
        MOVE.L  (A0),D0                         | GET A LONG FROM BUF2
        ROXR.L  #1,D0                           | SHIFT IT RIGHT EXTENDED
        OR.L    D0,(A0)+                        | OR IT BACK INTO BUFFER
        DBF     D1,ACROSS2                      | LOOP FOR ALL LONGS
        DBF     D2,ACROSS1                      | BOLD RIGHT 2,3, OR 4 TIMES

|
| Bold BUF2 down enough for shadow.
|
        MOVE.L  -0x2E(A6),A2                    | GET LIMIT POINTER
DOWN1:
        MOVE.L  -0x32(A6),A1                    | DSTPTR:=END OF BUF2

|
| Bold BUF2 down enough for shadow.
|
        MOVE.L  A1,A0                           | SET SRC PTR TO END OF BUF2
        SUBA    -0x3E(A6),A0                    | SUBTRACT ROWBYTES TO POINT TO LINE ABOVE
DOWN2:
        MOVE.L  -(A0),D0                        | GET A LONG FROM LINE ABOVE
        OR.L    D0,-(A1)                        | OR INTO THIS LINE
        CMP.L   A2,A0                           | IS SRCPTR <= BUF2START ?
        BGT.B   DOWN2                           | NO, LOOP ALL LONGS
        DBF     D3,DOWN1                        | BOLD DOWN 2,3, OR 4 TIMES
        MOVE.L  A2,-0x42(A6)                    | UPDATE SRCBITS BASEADDR TO BUF2
        ADDQ.W  #0x4,-0x38(A6)                  | INCREASE SRCBITS BOUNDS BOTTOM BY 4

|
| Alter srcBits to use BUF2
|

|
| Push params and call StretchBits to transfer shadow to screen
|
        MOVE.L  -0xC(A6),-0x8C(A6)              | SRCRECT := TEXTRECT
        MOVE.L  -0x8(A6),-0x88(A6)              | DSTRECT := SRCRECT
        ADDQ.W  #0x4,-0x88(A6)                  | INCREASE DSTRECT BOTTOM BY 4 FOR SHADOW
        MOVE.L  -0x8C(A6),-0x94(A6)             | SAVE TO DSTRECT
        MOVE.L  -0x88(A6),-0x90(A6)             | COPY SRCRECT BOT/RIGHT TO DSTRECT
        LEA.L   -0x94(A6),A0                    | POINT TO DSTRECT
        SUBQ.W  #0x1,(A0)+                      | EXPAND DSTRECT BOUND BY 1
        SUBQ.W  #0x1,(A0)+                      | EXPAND DSTRECT BOUND BY 1
        SUBQ.W  #0x1,(A0)+                      | EXPAND DSTRECT BOUND BY 1
        SUBQ.W  #0x1,(A0)+                      | EXPAND DSTRECT BOUND BY 1
        TST.B   -0x74(A6)                       | ARE WE STRETCHING TEXT?
        BEQ.B   DOWN2_CONT                      | BRANCH IF EQUAL
        PEA.L   -0x94(A6)                       | PUSH DSTRECT
        PEA.L   -0x7C(A6)                       | PUSH FROMRECT
        PEA.L   -0x84(A6)                       | PUSH TORECT


        JSR     MapRect(PC)                     | THEN MAPPED FOR SCALING
DOWN2_CONT:
        PEA.L   -0x42(A6)                       | PUSH SRCBITS
        PEA.L   -0x50(A6)                       | PUSH DSTBITS
        PEA.L   -0x8C(A6)                       | PUSH SRCRECT
        PEA.L   -0x94(A6)                       | PUSH DSTRECT
        MOVEQ   #7,D0                           | GET A 3-BIT MASK
        AND     TXMODE(A3),D0                   | GET TEXTMODE MOD 7
        MOVE    D0,-(SP)                        | PUSH SHADOW MODE
        MOVE.L  CLIPRGN(A3),-(SP)               | PUSH CLIPRGN HANDLE
        MOVE.L  VISRGN(A3),-(SP)                | PUSH VISRGN HANDLE
        PEA.L   -0x5E(A6)                       | PUSH FAKE HANDLE
        JSR     StretchBits(PC)                 | TRANSFER BUFFER TO SCREEN
        MOVE.L  -0x24(A6),-0x42(A6)             | GET BUFSTART
        SUBQ.W  #0x4,-0x38(A6)                  | RESTORE SRCBITS BOUNDS BOTTOM

|
| restore altered srcBits
|

|
| Push params and call StretchBits to transfer buffer to screen
|
| Called during boot.
NOSHAD:
        PEA.L   -0x42(A6)                       | PUSH SRCBITS
        PEA.L   -0x50(A6)                       | PUSH DSTBITS
        PEA.L   -0xC(A6)                        | PUSH SRCRECT = TEXTRECT
        PEA.L   -0x14(A6)                       | PUSH DSTRECT = TEXTR2

|
| restore altered srcBits
|

|
| Push params and call StretchBits to transfer buffer to screen
|
        MOVE    TXMODE(A3),-(SP)                | PUSH TEXTMODE
        TST.B   0xB(A4)                         | ARE WE USING SHADOW ?
        BEQ.B   NOSHAD_NO                       | NO, CONTINUE
        MOVE    #2,(SP)                         | YES, USE XOR MODE
NOSHAD_NO:
        ANDI    #0x7,(SP)                       | MASK OUT TXMODE SLANT/BOLD BITS
        MOVE.L  CLIPRGN(A3),-(SP)               | PUSH CLIPRGN HANDLE
        MOVE.L  VISRGN(A3),-(SP)                | PUSH VISRGN HANDLE
        PEA.L   -0x5E(A6)                       | PUSH FAKE HANDLE
        JSR     StretchBits(PC)                 | TRANSFER BUFFER TO SCREEN
NOSHAD_EXIT:
        MOVE.L  -0x4(A6),SP                     | STRIP BUFFER
        MOVEM.L (SP)+,D0-D7/A1-A4               | RESTORE REGS
        UNLK    A6                              | TEAR DOWN STACK FRAME
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        ADDA    #0xE,SP                         | POP 14 BYTES OF PARAMETERS
        JMP     (A0)                            | RETURN TO CALLER


