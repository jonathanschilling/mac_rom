| ------------------------------------------------------------
|
| --> GRAFASM.TEXT
|
| Miscellaneous unclassified routines.
|

| .PROC InitGraf,1
| --------------------------------------------------
|
| PROCEDURE InitGraf(globalPtr: Ptr);
|
| Called during boot.
InitGraf:
.set PARAMSIZE, 4                               | TOTAL BYTES OF PARAMS
.set GLOBALPTR, PARAMSIZE+8-4                   | LONG

        LINK    A6,#0                           | NO LOCALS
        MOVE.L  A4,-(SP)                        | SAVE REG
        MOVE.L  0x8(A6),A4                      | GET POINTER TO QUICKDRAW GLOBALS
        MOVE.L  A4,(A5)                         | SAVE IN MAGIC LOCATION

|
| new addition 22 Apr 85
|
        CLR.B   (QDExist).w                     | set lo-mem flag, QDExist
        LEA.L   LASTGRAFGLOB(A4),A0             | SET UP START POINTER
        LEA.L   0x4(A4),A1                      | SET UP LIMIT POINTER
CLRLP:
        CLR.W   (A0)+                           | CLEAR A WORD
        CMPA.L  A1,A0                           | CHECK LIMIT POINTER
        BNE.B   CLRLP                           | CLEAR ALL GLOBALS

| QDSpareD..QDSpare3 = all zeros
| playIndex := 0
| fontPtr = Nil
| FixTxWid := 0.0
| patAlign := (0,0)
| polyMax := 0
| thePoly := Nil
| QDSpare0 := 0
| playPic := Nil
| rgnMax := 0
| rgnIndex := 0
| rgnBuf := Nil
        LEA.L   WIDEDATA(A4),A4                 | POINT TO WIDEDATA
        MOVE.L  A4,D0                           | REMEMBER ADDR OF WIDEDATA
        MOVE    #10,(A4)+                       | wideData.rgnSize := 10
        MOVE.L  #0x80018001,(A4)+               | wideData.rgnBBox :=
        MOVE.L  #0x7FFF7FFF,(A4)+               | (-32767,-32767,32767,32767)
        MOVE.L  A4,D1                           | REMEMBER ADDR OF WIDEMASTER
        MOVE.L  D0,(A4)+                        | wideMaster := @wideData
        MOVE.L  D1,(A4)+                        | wideOpen := @wideMaster
        MOVEQ   #1,D0                           | PREPARE RANDSEED INITIAL VALUE
        MOVE.L  D0,(A4)+                        | randSeed := 1
        MOVE.L  A4,-(SP)                        | point to screenBits
        _ScrnBitMap                             | FILL IN SCREENBITS

| _GetScrnBits ;fill in screenBits
        ADD     #14,A4                          | bump past screenBits
        MOVEQ   #26,D0                          | INIT LOOP COUNT
        LEA.L   CURDATA(PC),A0                  | POINT TO CURSOR DATA
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
|

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
CURDATA:
  .byte 0x00,0x00,0x40,0x00,0x60,0x00           | ARROW DATA ROWS 0-2
  .byte 0x70,0x00,0x78,0x00,0x7C,0x00           | ARROW DATA ROWS 3-5
  .byte 0x7E,0x00,0x7F,0x00,0x7F,0x80           | ARROW DATA ROWS 6-8
  .byte 0x7C,0x00,0x6C,0x00,0x46,0x00           | ARROW DATA ROWS 9-11
  .byte 0x06,0x00,0x03,0x00,0x03,0x00           | ARROW DATA ROWS 12-14
  .byte 0x00,0x00                               | ARROW DATA ROW 15

| arrow.mask (16x16 cursor mask, 1=opaque):
  .byte 0xC0,0x00,0xE0,0x00                     | ARROW MASK ROWS 0-1
  .byte 0xF0,0x00,0xF8,0x00,0xFC,0x00           | ARROW MASK ROWS 2-4
  .byte 0xFE,0x00,0xFF,0x00,0xFF,0x80           | ARROW MASK ROWS 5-7
  .byte 0xFF,0xC0,0xFF,0xE0,0xFE,0x00           | ARROW MASK ROWS 8-10
  .byte 0xEF,0x00,0xCF,0x00,0x87,0x80           | ARROW MASK ROWS 11-13
  .byte 0x07,0x80,0x03,0x80                     | ARROW MASK ROWS 14-15

| arrow.hotspot = (1,1):
  .byte 0x00,0x01,0x00,0x01                     | HOTSPOT V=1, H=1

| dkGray pattern (75% black):
| .###.### 0x77
| ##.###.# 0xDD
| (repeats)
  .byte 0x77,0xDD,0x77,0xDD                     | DKGRAY ROWS 0-3
  .byte 0x77,0xDD,0x77,0xDD                     | DKGRAY ROWS 4-7

| ltGray pattern (25% black):
| #.....#. 0x88
| ..#..... 0x22
| (repeats)
  .byte 0x88,0x22                               | LTGRAY ROWS 0-1
  .byte 0x88,0x22,0x88,0x22,0x88,0x22           | LTGRAY ROWS 2-7

| gray pattern (50% checkerboard):
| #.#.#.#. 0xAA
| .#.#.#.# 0x55
| (repeats)
  .byte 0xAA,0x55,0xAA,0x55                     | GRAY ROWS 0-3
  .byte 0xAA,0x55,0xAA,0x55                     | GRAY ROWS 4-7

| black pattern (100% black):
| ######## 0xFF
| (repeats)
  .byte 0xFF,0xFF,0xFF,0xFF                     | BLACK ROWS 0-3
  .byte 0xFF,0xFF,0xFF,0xFF                     | BLACK ROWS 4-7

| white pattern (0%, all white):
| ........ 0x00
| (repeats)
  .byte 0x00,0x00                               | WHITE ROWS 0-1
  .byte 0x00,0x00,0x00,0x00,0x00,0x00           | WHITE ROWS 2-7

| .PROC OpenPort,1
| .REF NewRgn
| -------------------------------------------------------------
|
| PROCEDURE OpenPort(port: GrafPtr);
| { allocate clipRgn and visRgn, then call InitPort.
|
| Called during boot.
OpenPort:
        CLR.L   -(SP)                           | MAKE ROOM FOR FUNCTION RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A NEW REGION
        CLR.L   -(SP)                           | MAKE ROOM FOR FUNCTION RESULT
        JSR     NewRgn(PC)                      | ALLOCATE A SECOND NEW REGION
        MOVE.L  0xC(SP),A0                      | POINT TO PORT
        MOVE.L  (SP)+,CLIPRGN(A0)               | INSTALL NEW REGION INTO CLIPRGN
        MOVE.L  (SP)+,VISRGN(A0)                | AND OTHER INTO VISRGN
| | FALL THRU TO InitPort

| .PROC InitPort,1
| .REF RectRgn,CopyRgn
| -------------------------------------------------------------
|
| PROCEDURE InitPort(port: GrafPtr);
|
| { initialize all fields of an existing GrafPort }
|
| Called during boot.
InitPort:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  0x4(SP),A1                      | GET PORT PARAM
        MOVE.L  A1,(A0)                         | SetPort(port)
        CLR.W   (A1)+                           | DEVICE := 0
        LEA.L   SCREENBITS(A0),A0               | POINT TO SCREENBITS
        MOVE.L  (A0)+,(A1)+                     | portBits := screenBits
        MOVE    (A0)+,(A1)+                     | COPY ROWBYTES
        MOVE.L  (A0),(A1)+                      | COPY TOPLEFT
        MOVE.L  0x4(A0),(A1)+                   | COPY BOTRIGHT
        MOVE.L  (A0),(A1)+                      | portRect := screenBits.bounds
        MOVE.L  0x4(A0),(A1)+                   | all 8 bytes
        MOVE.L  (A1)+,-(SP)                     | visRgn := screenBits.bounds
        MOVE.L  A0,-(SP)                        | PUSH ADDR OF RECT
        JSR     RectRgn(PC)                     | CALL RECTRGN
        MOVE.L  0x4(SP),A1                      | GET PORT PARAM
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  WIDEOPEN(A0),-(SP)              | PUSH WIDE OPEN RGN
        MOVE.L  CLIPRGN(A1),-(SP)               | PUSH CLIPRGN
        JSR     CopyRgn(PC)                     | SET TO WIDE OPEN
        MOVE.L  0x4(SP),A1                      | GET PORT PARAM
        LEA.L   BKPAT(A1),A1                    | POINT TO BKPAT
        CLR.L   (A1)+                           | bkPat := white
        CLR.L   (A1)+                           | CLEAR SECOND LONG OF WHITE
        MOVEQ   #-1,D0                          | GET ALL ONES
        MOVE.L  D0,(A1)+                        | fillPat := Black
        MOVE.L  D0,(A1)+                        | SECOND LONG OF BLACK
        CLR.L   (A1)+                           | pnLoc := (0,0)
        MOVE.L  #0x10001,(A1)+                  | pnSize := (1,1)
        MOVE    #8,(A1)+                        | pnMode := patCopy
        MOVE.L  D0,(A1)+                        | pnPat := black
        MOVE.L  D0,(A1)+                        | SECOND LONG OF BLACK
        CLR.W   (A1)+                           | pnVis := 0
        CLR.L   (A1)+                           | txFont, txFace := 0
        MOVE    #1,(A1)+                        | txMode := srcOr
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

|
| .PROC ClosePort,1
| -------------------------------------------------------------
|
| PROCEDURE ClosePort(port: GrafPtr);
|
| { just disposes of clipRgn and visRgn }
|
| Called during boot.
ClosePort:
        MOVE.L  0x4(SP),A0                      | GET PORT
        MOVE.L  CLIPRGN(A0),A0                  | GET CLIPRGN HANDLE
        _DisposeHandle                          | DISCARD IT
| _DisposHandle | DISCARD IT
        MOVE.L  0x4(SP),A0                      | GET PORT
        MOVE.L  VISRGN(A0),A0                   | GET VISRGN HANDLE
        _DisposeHandle                          | DISCARD IT
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | AND RETURN

| .PROC SetStdProcs
| Fill a QDProcs record with standard QuickDraw procedure pointers
| from the Toolbox trap dispatch table. Order matches QDProcs (GrafTypes.s).
SetStdProcs:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDRESS
        MOVE.L  (SP)+,A1                        | POP PROCS POINTER
        MOVE.L  (0xE08).w,(A1)+                 | textProc = _StdText
        MOVE.L  (0xE40).w,(A1)+                 | lineProc = _StdLine
        MOVE.L  (0xE80).w,(A1)+                 | rectProc = _StdRect
        MOVE.L  (0xEBC).w,(A1)+                 | rRectProc = _StdRRect
        MOVE.L  (0xED8).w,(A1)+                 | ovalProc = _StdOval
        MOVE.L  (0xEF4).w,(A1)+                 | arcProc = _StdArc
        MOVE.L  (0xF14).w,(A1)+                 | polyProc = _StdPoly
        MOVE.L  (0xF44).w,(A1)+                 | rgnProc = _StdRgn
        MOVE.L  (0xFAC).w,(A1)+                 | bitsProc = _StdBits
        MOVE.L  (0xFC4).w,(A1)+                 | commentProc = _StdComment
        MOVE.L  (0xFB4).w,(A1)+                 | txMeasProc = _StdTxMeas
        MOVE.L  (0xFB8).w,(A1)+                 | getPicProc = _StdGetPic
        MOVE.L  (0xFC0).w,(A1)+                 | putPicProc = _StdPutPic
        JMP     (A0)                            | AND RETURN

| .PROC LocalToGlobal,1
| .DEF GlobalToLocal,AddPt,SubPt,SetPort,GetPort
| -------------------------------------------------------------
|
| PROCEDURE LocalToGlobal(VAR pt: Point);
|
| restores all registers.
| Called during boot.
LocalToGlobal:
        MOVEM.L D0-D2/A0-A1,-(SP)               | SAVE REGS
        MOVEQ.L #0x1,D2                         | INDICATE SUB
        BRA.B   GLOBALTOLOCAL_CONT              | SHARE COMMON CODE

| -------------------------------------------------------------
|
| PROCEDURE GlobalToLocal(VAR pt: Point);
|
| restores all registers.
|
| Called during boot (62,271 times in 30s trace).
GlobalToLocal:
        MOVEM.L D0-D2/A0-A1,-(SP)               | SAVE REGS
        CLR.L   D2                              | INDICATE ADD
GLOBALTOLOCAL_CONT:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | POINT TO CURRENT GRAFPORT
        MOVE.L  0x18(SP),A1                     | POINT TO VAR PT
        MOVE    0x8(A0),D0                      | GET DV
        MOVE    0xA(A0),D1                      | GET DH
        BSR.B   ADDSUB                          | CONVERT TO LOCAL
        MOVEM.L (SP)+,D0-D2/A0-A1               | RESTORE REGS
        BRA.B   SHARE3                          | STRIP 4 BYTES AND RETURN

| ----------------------------------------------------------
|
| ADDSUB
|
| Called during boot (62,279 times in 30s trace).
ADDSUB:
        TST     D2                              | CHECK ADD OR SUB FLAG
        BEQ.B   JUSTADD                         | IF ADD FLAG, GO ADD
        NEG     D0                              | NEGATE DV FOR SUB
        NEG     D1                              | NEGATE DH FOR SUB
JUSTADD:
        ADD     D0,(A1)+                        | ADD DV
        ADD     D1,(A1)+                        | ADD DH
        RTS                                     | AND RETURN

| -------------------------------------------------------------
|
| PROCEDURE AddPt(src: Point; VAR dst: Point);
| { add two points together, restores all regs }
AddPt:
        MOVEM.L D0-D2/A1,-(SP)                  | SAVE REGS
        CLR.L   D2                              | INDICATE ADD
        BRA.B   SHARE2                          | SHARE COMMON CODE

| -------------------------------------------------------------
|
| PROCEDURE SubPt(src: Point; VAR dst: Point);
| { subtract src Point from dst point, restores all regs }
|
SubPt:
        MOVEM.L D0-D2/A1,-(SP)                  | SAVE REGS
        MOVEQ.L #0x1,D2                         | INDICATE SUB
SHARE2:
        MOVE.L  0x14(SP),A1                     | POINT TO DST
        MOVE    0x18(SP),D0                     | GET SRC DV
        MOVE    0x1A(SP),D1                     | GET SRC DH
        BSR.B   ADDSUB                          | CONVERT TO LOCAL
        MOVEM.L (SP)+,D0-D2/A1                  | RESTORE REGS
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
SHARE3:
        MOVE.L  (SP)+,(SP)                      | STRIP PARAM
        RTS                                     | AND RETURN

| ----------------------------------------------------------
|
| PROCEDURE SetPort(gp: GrafPtr);
| { switch the current port to a different GrafPort }
| Called during boot (30,216 times in 30s trace).
SetPort:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  0x4(SP),(A0)                    | SAVE NEW PORT IN THEPORT
        BRA.B   SHARE3                          | STRIP 4 BYTES AND RETURN

| ----------------------------------------------------------
|
| PROCEDURE GetPort(VAR gp: GrafPtr);
| { inquire the current GrafPort }
|
| Called during boot (17,610 times in 30s trace).
GetPort:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  0x4(SP),A1                      | POINT TO VAR GP
        MOVE.L  (A0),(A1)                       | RETURN CURRENT PORT
        BRA.B   SHARE3                          | STRIP 4 BYTES AND RETURN


| .PROC GrafDevice,1
| .REF PortWord
| ----------------------------------------------------------
|
| PROCEDURE GrafDevice(device: INTEGER);
|
GrafDevice:
        MOVEQ.L #0x0,D0                         | SET DEVICE TO 0
        JMP     L_mPortWord(PC)                 | INSTALL PARAM INTO THEPORT

| .PROC SetPortBits,1
| .DEF BackPat
| ----------------------------------------------------------
|
| PROCEDURE SetPortBits(bm: BitMap);
| { re-direct output to a different BitMap }
|
SetPBits:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L   PORTBITS(A0),A0                 | POINT TO PORTBITS
        MOVE.L  0x4(SP),A1                      | POINT TO BITMAP
        MOVE.L  (A1)+,(A0)+                     | COPY BASEADDR
        MOVE    (A1)+,(A0)+                     | COPY ROWBYTES
SETPORTBITS_SHARE:
        MOVE.L  (A1)+,(A0)+                     | SHARE: COPY BOUNDS.TOPLEFT
        MOVE.L  (A1)+,(A0)+                     | COPY BOUNDS.BOTRIGHT
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
        RTS                                     | AND RETURN

| ----------------------------------------------------------
|
| PROCEDURE BackPat(pat: Pattern);
| { set the background pattern }
BackPat:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        LEA.L   BKPAT(A0),A0                    | POINT TO BKPAT
        MOVE.L  0x4(SP),A1                      | GET ADDR OF PATTERN
        BRA.B   SETPORTBITS_SHARE               | SHARE COPY CODE

| .PROC PortSize,2
| ----------------------------------------------------------
|
| PROCEDURE PortSize(width,height: INTEGER);
|
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

| .PROC MovePortTo,2
| .DEF SetOrigin,ClipRect
| .REF OffsetRgn,RectRgn
| ----------------------------------------------------------
|
| PROCEDURE MovePortTo(leftGlobal,topGlobal: INTEGER);
| { move portRect to a different part of the bitmap }
|
| Called during boot.
MovePortTo:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE    0x12(A0),D0                     | GET PORTRECT.LEFT
        SUB     0xA(A0),D0                      | CONVERT TO GLOBAL
        SUB     0x6(SP),D0                      | SUB LEFTGLOBAL FOR DH
        MOVE    0x10(A0),D1                     | GET PORTRECT.TOP
        SUB     0x8(A0),D1                      | CONVERT TO GLOBAL
        SUB     0x4(SP),D1                      | SUB TOPGLOBAL FOR DV
        MOVE.L  (SP)+,(SP)                      | STRIP 4 BYTES
| OFSPORT -- oFFSET PORTBITS.BOUNDS.
OFSPORT:
        LEA.L   0x8(A0),A0                      | OFFSET PORTBITS.BOUNDS DH,DV
| OFSRECT -- oFFSET PORTRECT.
OFSRECT:
        ADD     D1,(A0)+                        | OFFSET TOP
        ADD     D0,(A0)+                        | OFFSET LEFT
        ADD     D1,(A0)+                        | OFFSET BOTTOM
        ADD     D0,(A0)+                        | OFFSET RIGHT
        RTS                                     | AND RETURN

| ----------------------------------------------------------
|
| PROCEDURE SetOrigin(h,v: INTEGER);
| { re-define the local coords by adjusting portBits.bounds, }
| { portRect, and visRgn }
|
| Called during boot.
SetOrigin:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  0x4(SP),D0                      | GET V AND H BOTH
        CMP.L   0x10(A0),D0                     | SAME AS ALREADY IN THEPORT ?

| ----------------------------------------------------------
|
        BEQ.B   SETORIGIN_DONE                  | YES, QUIT
        MOVE    0x6(SP),D0                      | GET H
        SUB     0x12(A0),D0                     | DH:=H-PORTRECT.LEFT
        MOVE    0x4(SP),D1                      | GET V
        SUB     0x10(A0),D1                     | DV:=V-PORTRECT.TOP
        MOVE.L  VISRGN(A0),-(SP)                | PUSH PARMS FOR LATER
        MOVE    D0,-(SP)                        | PUSH DH
        MOVE    D1,-(SP)                        | PUSH DV
        BSR.B   OFSPORT                         | OFFSET PORTBITS.BOUNDS
        LEA.L   (A0),A0                         | POINT A0 AT PORTRECT
        BSR.B   OFSRECT                         | OFFSET PORTRECT
        JSR     OffsetRgn(PC)                   | OFFSET VISRGN
SETORIGIN_DONE:
        MOVE.L  (SP)+,(SP)                      | DONE: STRIP 4 BYTES
        RTS                                     | AND RETURN

| ----------------------------------------------------------
|
| PROCEDURE ClipRect(r: Rect);
| { Make the current grafport's clipRgn match a given rectangle }
|
| Called during boot (64,069 times in 30s trace).
ClipRect:
        MOVE.L  (A5),A0                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A0),A0                         | GET CURRENT GRAFPORT
        MOVE.L  CLIPRGN(A0),-(SP)               | PUSH CLIPRGN
        MOVE.L  0x8(SP),-(SP)                   | PUCH ADDR OF RECT
        JSR     RectRgn(PC)                     | CALL RECTRGN
        BRA.B   SETORIGIN_DONE                  | STRIP PARAM AND RETURN

| .PROC SetClip,1
| .DEF GetClip
| .REF CopyRgn
| ----------------------------------------------------------
|
| PROCEDURE SetClip(rgn: RgnHandle);
|
| copy rgn into theport^.clipRgn
|
| Called during boot (2,787 times in 30s trace).
SetClip:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (A5),A1                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A1),A1                         | GET CURRENT GRAFPORT
        MOVE.L  CLIPRGN(A1),-(SP)               | PUSH THEPORT^.CLIPRGN
        BRA.B   GETCLIP_SHARE                   | GO TO SHARE

| ----------------------------------------------------------
|
| PROCEDURE GetClip(rgn: RgnHandle);
|
| copy from theport^.clipRgn into rgn.
|
| Called during boot (2,785 times in 30s trace).
GetClip:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | POP RGN HANDLE
        MOVE.L  (A5),A1                         | POINT TO QUICKDRAW GLOBALS
        MOVE.L  (A1),A1                         | GET CURRENT GRAFPORT
        MOVE.L  CLIPRGN(A1),-(SP)               | PUSH THEPORT^.CLIPRGN
        MOVE.L  D0,-(SP)                        | PUSH RGN
GETCLIP_SHARE:
        MOVE.L  A0,-(SP)                        | SHARE: RESTORE RETURN ADDR
        JMP     CopyRgn(PC)                     | AND GO TO COPYRGN

| .PROC SetPt
| -------------------------------------------------------------
|
| PROCEDURE SetPt(VAR pt: Point; h,v: INTEGER);
|
| Called during boot.
SetPt:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | POP H,V
        MOVE.L  (SP)+,A1                        | POP VAR ADDR OF PT
        MOVE.L  D0,(A1)                         | STORE H,V INTO PT
        JMP     (A0)                            | RETURN

| .PROC EqualPt
| ----------------------------------------------------------
|
| FUNCTION EqualPt(pt1,pt2: Point): BOOLEAN;
|
| CLOBBERS D0,A0.
|
EqualPt:
        MOVE.L  (SP)+,A0                        | POP RETURN ADDR
        MOVE.L  (SP)+,D0                        | pop point1
        CMP.L   (SP)+,D0                        | is point2 = point1 ?
        SEQ     (SP)                            | IF YES, SET TO TRUE
        NEG.B   (SP)                            | CONVERT -1 TO 1
        JMP     (A0)                            | RETURN


