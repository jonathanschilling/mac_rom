| ------------------------------------------------------------
|
| --> GRAFASM.TEXT
|
| Miscellaneous unclassified routines: InitGraf, OpenPort, InitPort,
| ClosePort, SetStdProcs, LocalToGlobal/GlobalToLocal, GrafDevice,
| SetPort/GetPort, SetPBits, PortSize, MovePortTo, SetOrigin, SetClip,
| GetClip, ClipRect, BackPat, AddPt, SubPt, SetPt, EqualPt.

| --------------------------------------------------
| PROCEDURE InitGraf(globalPtr: Ptr);
| Called during boot.
InitGraf:
        LINK    A6,#0x0                         | NO LOCALS
        MOVE.L  A4,-(SP)                        | SAVE REG
        MOVE.L  8(A6),A4                        | GET POINTER TO QUICKDRAW GLOBALS
        MOVE.L  A4,(A5)                         | SAVE IN MAGIC LOCATION
        LEA.L   -0xCA(A4),A0                    | SET UP START POINTER (LASTGRAFGLOB)
        LEA.L   4(A4),A1                        | SET UP LIMIT POINTER
CLRLP:
        CLR     (A0)+                           | CLEAR A WORD
        CMPA.L  A1,A0                           | CHECK LIMIT POINTER
        BNE.B   CLRLP                           | CLEAR ALL GLOBALS
        LEA.L     -0x90(A4),A4                  | POINT TO WIDEDATA
        MOVE.L  A4,D0                           | REMEMBER ADDR OF WIDEDATA
        MOVE    #0xA,(A4)+                      | wideData.rgnSize := 10
        MOVE.L  #0x80018001,(A4)+               | rgnBBox top-left = (-32767, -32767)
        MOVE.L  #0x7FFF7FFF,(A4)+               | rgnBBox bot-right = (+32767, +32767)
        MOVE.L  A4,D1                           | REMEMBER ADDR OF WIDEMASTER
        MOVE.L  D0,(A4)+                        | wideMaster := @wideData
        MOVE.L  D1,(A4)+                        | wideOpen := @wideMaster
        MOVEQ.L #0x1,D0                         | PREPARE RANDSEED INITIAL VALUE
        MOVE.L  D0,(A4)+                        | randSeed := 1
        CLR.L   -(SP)                           | reserve room for screenBase result
        JSR     PUSH_JScrnAddr(PC)              | get screen base address
        MOVE.L  (SP)+,(A4)+                     | screenBits.baseAddr := result
        PEA.L     8(A4)                         | push @screenBits.bottom
        PEA.L     6(A4)                         | push @screenBits.right
        JSR     PUSH_JScrnSize(PC)              | fill screen height/width
        MOVE    8(A4),D0                        | get screen width (pixels)
        LSR     #0x3,D0                         | /8 -> rowBytes
        MOVE    D0,(A4)+                        | screenBits.rowBytes := width/8
        CLR.L   (A4)+                           | screenBits.bounds.topLeft := 0
        ADDQ.W  #0x4,A4                         | skip past screenBits trailer
        MOVEQ.L #0x1A,D0                        | loop count = 26 longs (cursor + patterns)
        LEA     CURDATA(PC),A0                  | POINT TO CURSOR DATA
CRSRLP:
        MOVE.L  (A0)+,(A4)+                     | COPY A LONG INTO GLOBALS
        DBF     D0,CRSRLP                       | LOOP FOR 27 LONGS

| thePort := NIL
        MOVE.L  (SP)+,A4                        | RESTORE REG
        UNLK    A6                              | DESTROY STACK FRAME
        MOVE.L  (SP)+,(SP)                      | STRIP PARAMETER
        RTS                                     | AND RETURN

| QuickDraw default globals data: arrow cursor + 5 standard patterns
| Patterns are 8x8 pixels, 1 bit per pixel, 1 byte per row.
| Bit 7 = leftmost pixel, bit 0 = rightmost pixel (MSB first).
| These are tiled to fill any area when used as pen, background, or fill patterns.
| (see also: github.com/jonathanschilling/PatternDrafter)
| arrow.data (16x16 cursor image, 1=black):
| ..**............
| .***............
| .****...........
| .*****..........
| .*******.........
| .*******........
| .*********.......
| .**.***.........
| .*...***.........
| .....***........
| ......**........
| ................
| ----------------------------------------------------------
| CURDATA -- default QuickDraw cursor + 5 standard patterns
| 68 bytes arrow cursor (16 rows shape + 16 rows mask + hotSpot)
| 40 bytes patterns: gray, ltGray, dkGray (50%), black, white
| ----------------------------------------------------------
CURDATA:                                        | arrow cursor shape
        .short  0x0000, 0x4000, 0x6000, 0x7000  | rows 0-3
        .short  0x7800, 0x7C00, 0x7E00, 0x7F00  | rows 4-7
        .short  0x7F80, 0x7C00, 0x6C00, 0x4600  | rows 8-11
        .short  0x0600, 0x0300, 0x0300, 0x0000  | rows 12-15
CURMASK:                                        | arrow cursor mask
        .short  0xC000, 0xE000, 0xF000, 0xF800  | rows 0-3
        .short  0xFC00, 0xFE00, 0xFF00, 0xFF80  | rows 4-7
        .short  0xFFC0, 0xFFE0, 0xFE00, 0xEF00  | rows 8-11
        .short  0xCF00, 0x8780, 0x0780, 0x0380  | rows 12-15
CURHOTSPOT:                                     | arrow hotSpot (1,1)
        .short  0x0001, 0x0001                  | hotSpot v/h
| Standard QuickDraw patterns (8 bytes each)
QDPATTERNS:
        .byte   0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD | gray
        .byte   0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22 | ltGray
        .byte   0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 | dkGray (50%)
        .byte   0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF | black
        .byte   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 | white

| ----------------------------------------------------------
| .PROC OpenPort,1
| PROCEDURE OpenPort(port: GrafPtr);
| _OpenPort ($A86F): allocate the port's clipRgn and visRgn, then
| fall through to InitPort, which initializes all other fields.
| Called during boot.
OpenPort:
        CLR.L   -(SP)                           | MAKE ROOM FOR FUNCTION RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A NEW REGION
        CLR.L   -(SP)                           | MAKE ROOM FOR FUNCTION RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A SECOND NEW REGION
        MOVE.L  12(SP),A0                       | POINT TO PORT
        MOVE.L  (SP)+,28(A0)                    | INSTALL NEW REGION INTO CLIPRGN
        MOVE.L  (SP)+,24(A0)                    | AND OTHER INTO VISRGN
| FALL THRU TO InitPort

| ----------------------------------------------------------
| .PROC InitPort,1
| PROCEDURE InitPort(port: GrafPtr);
| _InitPort ($A86D): initialize all fields of an existing GrafPort:
| SetPort(port), portBits := screenBits, portRect and visRgn :=
| screenBits.bounds, wide-open clipRgn, then the pen, pattern, text
| and procedure fields. Also reached as fall-through from OpenPort.
| Called during boot.
InitPort:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  4(SP),A1                        | GET PORT PARAM
        MOVE.L  A1,(A0)                         | SetPort(port)
        CLR     (A1)+                           | DEVICE := 0
        LEA.L     -0x7A(A0),A0                  | POINT TO SCREENBITS
        MOVE.L  (A0)+,(A1)+                     | portBits := screenBits
        MOVE    (A0)+,(A1)+                     | COPY ROWBYTES
        MOVE.L  (A0),(A1)+                      | COPY TOPLEFT
        MOVE.L  4(A0),(A1)+                     | COPY BOTRIGHT
        MOVE.L  (A0),(A1)+                      | portRect := screenBits.bounds
        MOVE.L  4(A0),(A1)+                     | all 8 bytes
        MOVE.L  (A1)+,-(SP)                     | visRgn := screenBits.bounds
        MOVE.L  A0,-(SP)                        | PUSH ADDR OF RECT
        JSR     RectRgn(PC)                     | CALL RECTRGN
        MOVE.L  4(SP),A1                        | GET PORT PARAM
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  -0x82(A0),-(SP)                 | PUSH WIDE OPEN RGN
        MOVE.L  28(A1),-(SP)                    | PUSH CLIPRGN
        JSR     CopyRgn(PC)                     | SET TO WIDE OPEN
        MOVE.L  4(SP),A1                        | GET PORT PARAM
        LEA.L     0x20(A1),A1                   | POINT TO BKPAT
        CLR.L   (A1)+                           | bkPat := white
        CLR.L   (A1)+                           | CLEAR SECOND LONG OF WHITE
        MOVEQ.L #-0x1,D0                        | GET ALL ONES
        MOVE.L  D0,(A1)+                        | fillPat := Black
        MOVE.L  D0,(A1)+                        | SECOND LONG OF BLACK
        CLR.L   (A1)+                           | pnLoc := (0,0)
        MOVE.L  #0x00010001,(A1)+               | pnSize := (1,1)
        MOVE    #0x8,(A1)+                      | pnMode := patCopy
        MOVE.L  D0,(A1)+                        | pnPat := black
        MOVE.L  D0,(A1)+                        | SECOND LONG OF BLACK
        CLR     (A1)+                           | pnVis := 0
        CLR.L   (A1)+                           | txFont, txFace := 0
        MOVE    #0x1,(A1)+                      | txMode := srcOr
        CLR     (A1)+                           | txSize := 0
        CLR.L   (A1)+                           | spExtra := 0.0
        MOVE.L  #0x21,(A1)+                     | fgColor := blackColor
        MOVE.L  #0x1E,(A1)+                     | bkColor := whiteColor
        CLR.L   (A1)+                           | colrBit,patStretch := 0
        CLR.L   (A1)+                           | picSave := Nil
        CLR.L   (A1)+                           | rgnSave := Nil
        CLR.L   (A1)+                           | polySave := Nil
        CLR.L   (A1)+                           | grafProcs := Nil
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| .PROC ClosePort,1
| PROCEDURE ClosePort(port: GrafPtr);
| Disposes of clipRgn and visRgn handles. Plus uses inline
| _DisposeHandle; classic uses DisposRgn (a Pascal-stack
| _DisposeHandle wrapper).
| Called during boot.
ClosePort:
        MOVE.L  4(SP),A0                        | GET PORT
        MOVE.L  28(A0),-(SP)                    | PUSH CLIPRGN HANDLE
        JSR     DisposRgn(PC)                   | DisposRgn(clipRgn)
        MOVE.L  4(SP),A0                        | GET PORT
        MOVE.L  24(A0),-(SP)                    | PUSH VISRGN HANDLE
        JSR     DisposRgn(PC)                   | DisposRgn(visRgn)
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| .PROC SetStdProcs,1
| PROCEDURE SetStdProcs(VAR procs: QDProcs);
| Fill a QDProcs record with standard QuickDraw procedure pointers.
| Order matches QDProcs (GrafTypes.s).
| Called during boot.
SetStdProcs:
        MOVE.L  4(SP),A1                        | GET ADDRESS OF PROC RECORD
        LEA     StdText(PC),A0                  | textProc = StdText
        MOVE.L  A0,(A1)+                        | install textProc
        LEA     StdLine(PC),A0                  | lineProc = StdLine
        MOVE.L  A0,(A1)+                        | install lineProc
| Continue J-vector install: rect/RRect/oval/arc/poly/rgn/comment/textWid/getPic/putPic.
        LEA     StdRect(PC),A0                  | rectProc = StdRect
        MOVE.L  A0,(A1)+                        | install rectProc
        LEA     StdRRect(PC),A0                 | rRectProc = StdRRect
        MOVE.L  A0,(A1)+                        | install rRectProc
        LEA     StdOval(PC),A0                  | ovalProc = StdOval
        MOVE.L  A0,(A1)+                        | install ovalProc
        LEA     StdArc(PC),A0                   | arcProc = StdArc
        MOVE.L  A0,(A1)+                        | install arcProc
        LEA     StdPoly(PC),A0                  | polyProc = StdPoly
        MOVE.L  A0,(A1)+                        | install polyProc
        LEA     StdRgn(PC),A0                   | rgnProc = StdRgn
        MOVE.L  A0,(A1)+                        | install rgnProc
        LEA     StdBits(PC),A0                  | bitsProc = StdBits
        MOVE.L  A0,(A1)+                        | install bitsProc
        LEA     StdComment(PC),A0               | commentProc = StdComment
        MOVE.L  A0,(A1)+                        | install commentProc
        LEA     StdTxMeas(PC),A0                | txMeasProc = StdTxMeas
        MOVE.L  A0,(A1)+                        | install txMeasProc
        LEA     StdGetPic(PC),A0                | getPicProc = StdGetPic
        MOVE.L  A0,(A1)+                        | install getPicProc
        LEA     StdPutPic(PC),A0                | putPicProc = StdPutPic
        MOVE.L  A0,(A1)+                        | install putPicProc
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from SetStdProcs

| ----------------------------------------------------------
| .PROC LocalToGlobal,1
|
| _LocalToGlobal ($A870): convert a point from local to global coordinates
| Pascal: PROCEDURE LocalToGlobal(VAR pt: Point);
| pt := pt - thePort^.portBits.bounds.topLeft (GrafPort offsets 8/10).
| Preserves all registers. The 1983 GrafAsm.a shares one body with
| GlobalToLocal (ADD or NEG+ADD); the 1984 ROM has two separate copies.
| Called during boot.
LocalToGlobal:
        MOVEM.L D0/A0-A1,-(SP)                  | save regs
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  16(SP),A1                       | A1 = VAR pt addr
        MOVE    8(A0),D0                        | D0 = portBits.bounds.top
        SUB     D0,(A1)+                        | pt.v -= bounds.top
        MOVE    10(A0),D0                       | D0 = portBits.bounds.left
        SUB     D0,(A1)+                        | pt.h -= bounds.left
        MOVEM.L (SP)+,D0/A0-A1                  | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from LocalToGlobal

| ----------------------------------------------------------
| .DEF GlobalToLocal
|
| _GlobalToLocal ($A871): convert a point from global to local coordinates
| Pascal: PROCEDURE GlobalToLocal(VAR pt: Point);
| pt := pt + thePort^.portBits.bounds.topLeft. Preserves all registers.
| Called during boot.
GlobalToLocal:
        MOVEM.L D0/A0-A1,-(SP)                  | save regs
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  16(SP),A1                       | A1 = VAR pt addr
        MOVE    8(A0),D0                        | D0 = portBits.bounds.top
        ADD     D0,(A1)+                        | pt.v += bounds.top
        MOVE    10(A0),D0                       | D0 = portBits.bounds.left
        ADD     D0,(A1)+                        | pt.h += bounds.left
        MOVEM.L (SP)+,D0/A0-A1                  | restore regs
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from GlobalToLocal

| ----------------------------------------------------------
| PROCEDURE GrafDevice(device: INTEGER);
GrafDevice:
        MOVEQ.L #0x0,D0                         | port offset 0 = device
        JMP     L_mPortWord(PC)                 | install word into port

| ----------------------------------------------------------
| PROCEDURE SetPort(gp: GrafPtr).
SetPort:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  4(SP),(A0)                      | install new thePort
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from SetPort

| ----------------------------------------------------------
| PROCEDURE GetPort(VAR gp: GrafPtr).
GetPort:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  4(SP),A1                        | A1 = VAR addr
        MOVE.L  (A0),(A1)                       | copy thePort to VAR
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from GetPort

| ----------------------------------------------------------
| PROCEDURE SetPortBits(bm: BitMap).
SetPBits:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L     2(A0),A0                      | POINT TO PORTBITS
        MOVE.L  4(SP),A1                        | POINT TO BITMAP
        MOVE.L  (A1)+,(A0)+                     | COPY BASEADDR
        MOVE    (A1)+,(A0)+                     | COPY ROWBYTES
SETPORTBITS_SHARE:
        MOVE.L  (A1)+,(A0)+                     | SHARE: COPY BOUNDS.TOPLEFT
        MOVE.L  (A1)+,(A0)+                     | COPY BOUNDS.BOTRIGHT
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| .PROC PortSize,2
| ----------------------------------------------------------
| PROCEDURE PortSize(width,height: INTEGER);
| Called during boot.
PortSize:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE    0x12(A0),D0                     | GET PORTRECT.LEFT
        ADD     0x6(SP),D0                      | ADD WIDTH
        MOVE    D0,0x16(A0)                     | UPDATE PORTRECT.RIGHT
        MOVE    0x10(A0),D0                     | GET PORTRECT.TOP
        ADD     0x4(SP),D0                      | ADD HEIGHT
        MOVE    D0,0x14(A0)                     | UPDATE PORTRECT.BOTTOM
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| PROCEDURE MovePortTo(leftGlobal, topGlobal: INTEGER);
MovePortTo:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE    18(A0),D0                       | GET PORTRECT.LEFT
        SUB     10(A0),D0                       | CONVERT TO GLOBAL
        SUB     6(SP),D0                        | SUB LEFTGLOBAL FOR DH
        MOVE    16(A0),D1                       | GET PORTRECT.TOP
        SUB     8(A0),D1                        | CONVERT TO GLOBAL
        SUB     4(SP),D1                        | SUB TOPGLOBAL FOR DV
        ADD     D0,10(A0)                       | 10(A0) += D0
        ADD     D0,14(A0)                       | 14(A0) += D0
        ADD     D1,8(A0)                        | 8(A0) += D1
        ADD     D1,12(A0)                       | 12(A0) += D1
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| PROCEDURE SetOrigin(h, v: INTEGER);
| Adjust port origin and offset clipRgn.
SetOrigin:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  4(SP),D0                        | D0 = (h,v) packed
        CMP.L   16(A0),D0                       | already at this origin?
        BEQ.B   SETORIGIN_DONE                  | yes, skip
        MOVE    6(SP),D0                        | GET H
        SUB     18(A0),D0                       | dh = h - portRect.left
        MOVE    4(SP),D1                        | GET V
        SUB     16(A0),D1                       | dv = v - portRect.top
        ADD     D0,10(A0)                       | 10(A0) += D0
        ADD     D0,14(A0)                       | 14(A0) += D0
        ADD     D1,8(A0)                        | 8(A0) += D1
        ADD     D1,12(A0)                       | 12(A0) += D1
        ADD     D0,18(A0)                       | 18(A0) += D0
        ADD     D0,22(A0)                       | 22(A0) += D0
        ADD     D1,16(A0)                       | 16(A0) += D1
        ADD     D1,20(A0)                       | 20(A0) += D1
        MOVE.L  24(A0),-(SP)                    | PUSH PARMS FOR LATER
        MOVE    D0,-(SP)                        | push dh for OfsetRgn
        MOVE    D1,-(SP)                        | push dv for OfsetRgn
        JSR     OfsetRgn(PC)                    | slide clipRgn by (dh,dv)
SETORIGIN_DONE:
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| ----------------------------------------------------------
| PROCEDURE SetClip(rgn: RgnHandle); copy rgn into theport^.clipRgn.
SetClip:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (A5),A1                         | A1 = QD globals
        MOVE.L  (A1),A1                         | A1 = thePort
        MOVE.L  28(A1),-(SP)                    | PUSH thePort^.clipRgn (dst)
        MOVE.L  A0,-(SP)                        | restore return addr
        JMP     CopyRgn(PC)                     | CopyRgn(srcRgn, dstRgn)

| ----------------------------------------------------------
| PROCEDURE GetClip(rgn: RgnHandle); copy theport^.clipRgn into rgn.
GetClip:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | POP arg RGN HANDLE
        MOVE.L  (A5),A1                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A1),A1                         | GET CURRENT GRAFPORT
        MOVE.L  28(A1),-(SP)                    | PUSH THEPORT^.CLIPRGN (src)
        MOVE.L  D0,-(SP)                        | PUSH arg RGN (dst)
        MOVE.L  A0,-(SP)                        | restore return addr
        JMP     CopyRgn(PC)                     | CopyRgn(src, dst)

| ----------------------------------------------------------
| PROCEDURE ClipRect(r: Rect); set thePort^.clipRgn to a rect.
ClipRect:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        MOVE.L  4(SP),A1                        | A1 = rect ptr
        MOVE.L  28(A0),-(SP)                    | push clipRgn
        MOVE.L  A1,-(SP)                        | push rect
        JSR     RectRgn(PC)                     | RectRgn equivalent
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from ClipRect

| ----------------------------------------------------------
| PROCEDURE BackPat(pat: Pattern); set thePort^.bkPat.
BackPat:
        MOVE.L  (A5),A0                         | A0 = QD globals
        MOVE.L  (A0),A0                         | A0 = thePort
        LEA.L     0x20(A0),A0                   | A0 = bkPat
        MOVE.L  4(SP),A1                        | A1 = source pat
        MOVE.L  (A1)+,(A0)+                     | copy pat into bkPat
        MOVE.L  (A1)+,(A0)+                     | all 8 bytes
        MOVE.L  (SP)+,(SP)                      | strip param
        RTS                                     | return from BackPat

| ----------------------------------------------------------
| PROCEDURE AddPt(src: Point; VAR dst: Point);
AddPt:
        MOVEM.L D0/A0,-(SP)                     | save regs
        MOVE.L  12(SP),A0                       | A0 = VAR dst
        MOVE    16(SP),D0                       | D0 = src.v
        ADD     D0,(A0)+                        | dst.v += src.v
        MOVE    18(SP),D0                       | D0 = src.h
        ADD     D0,(A0)+                        | dst.h += src.h
        MOVEM.L (SP)+,D0/A0                     | restore regs
        MOVE.L  (SP)+,(SP)                      | strip dst
        MOVE.L  (SP)+,(SP)                      | strip src
        RTS                                     | return from AddPt

| ----------------------------------------------------------
| PROCEDURE SubPt(src: Point; VAR dst: Point);
SubPt:
        MOVEM.L D0/A0,-(SP)                     | save regs
        MOVE.L  12(SP),A0                       | A0 = VAR dst
        MOVE    16(SP),D0                       | D0 = src.v
        SUB     D0,(A0)+                        | dst.v -= src.v
        MOVE    18(SP),D0                       | D0 = src.h
        SUB     D0,(A0)+                        | dst.h -= src.h
        MOVEM.L (SP)+,D0/A0                     | restore regs
        MOVE.L  (SP)+,(SP)                      | strip dst
        MOVE.L  (SP)+,(SP)                      | strip src
        RTS                                     | return from SubPt

| .PROC SetPt
| -------------------------------------------------------------
| PROCEDURE SetPt(VAR pt: Point; h,v: INTEGER);
| Called during boot.
SetPt:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | POP H,V
        MOVE.L  (SP)+,A1                        | POP VAR ADDR OF PT
        MOVE.L  D0,(A1)                         | STORE H,V INTO PT
        JMP     (A0)                            | RETURN

| .PROC EqualPt
| ----------------------------------------------------------
| FUNCTION EqualPt(pt1,pt2: Point): BOOLEAN;
| CLOBBERS D0,A0.
EqualPt:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | pop point1
        CMP.L   (SP)+,D0                        | is point2 = point1 ?
        SEQ     (SP)                            | IF YES, SET TO TRUE
        NEG.B   (SP)                            | CONVERT -1 TO 1
        JMP     (A0)                            | RETURN
