| ------------------------------------------------------------
|
| --> GRAFASM.TEXT
|
| Miscellaneous unclassified routines.
|
| In the SE ROM the file starts with QuickDraw's NewHandle (allocate a
| handle, system error 25 if memory is full).

| ----------------------------------------------------------
|
| NewHandle: allocate a relocatable block (PtBuf, region buffer, etc.).
| Wraps the _NewHandle trap, popping the size param off the stack and
| returning the new handle in place of the caller's size word.
|
| INPUT:   word size on top of stack, return address below
| OUTPUT:  block handle on top of stack (replacing size)
| Errors out via FASTSLABMODE_ERR if allocation fails.
|
| Called by: OPENPOLY, NEWRGN, OPENRGN, INSETRGN_NOTRECT, JDONE_NO_2 (and 1 more)
NEWHANDLE:
    MOVEQ.L	#0x0,D0                             | CLEAR UPPER WORD OF SIZE
    MOVEA.L	(A7)+,A1                            | POP RETURN ADDRESS
    MOVE.W	(A7)+,D0                             | GET SIZE PARAMETER
    _NewHandle                                  | ALLOCATE HANDLE
    BNE.B	FASTSLABMODE_ERR                      | BRANCH IF ALLOCATION FAILED
    MOVE.L	A0,(A7)                              | RETURN HANDLE ON STACK
    JMP	(A1)                                    | RETURN TO CALLER
| ----------------------------------------------------------
|
| FASTSLABMODE_ERR: out-of-memory abort.
| Triggers a system error (dsMemFullErr=25) and drops into the debugger.
|
FASTSLABMODE_ERR:
    MOVEQ.L	#0x19,D0                            | LOAD OUT OF MEMORY ERROR CODE
    _SysError                                   | TRIGGER SYSTEM ERROR
    _Debugger                                   | DROP INTO DEBUGGER
| ----------------------------------------------------------
|
| SetHSize -- mAKE THE BUFFER BIGGER.
| Wraps _SetHandleSize, popping handle and new size off the stack.
|
| INPUT:   handle (long), new size (word), return address
| OUTPUT:  - (handle resized in place)
|
| Called by: DOLINE_NO, DVPOS_OK, PUTRECT, PUTPT, EMPTY (and 6 more)
SETHSIZE:
    MOVEQ.L	#0x0,D0                             | CLEAR UPPER WORD OF SIZE
    MOVEA.L	(A7)+,A1                            | POP RETURN ADDRESS
    MOVE.W	(A7)+,D0                             | GET NEW SIZE PARAMETER
    MOVEA.L	(A7)+,A0                            | GET HANDLE PARAMETER
    _SetHandleSize                              | SET HANDLE SIZE
    BNE.B	FASTSLABMODE_ERR                      | BRANCH IF ERROR
    JMP	(A1)                                    | RETURN TO CALLER
INITGRAF:
.set PARAMSIZE, 4                               | TOTAL BYTES OF PARAMS
.set GLOBALPTR, PARAMSIZE+8-4                   | LONG
    LINK	A6,#0x0                                | NO LOCALS
    MOVE.L	A4,-(A7)                             | SAVE REG
    MOVEA.L	0x8(A6),A4                          | GET POINTER TO QUICKDRAW GLOBALS
    MOVE.L	A4,(A5)                              | SAVE IN MAGIC LOCATION
    CLR.B	(QDExist).W                           | set lo-mem flag, QDExist
    LEA.L	-0xCA(A4),A0                          | SET UP START POINTER (LASTGRAFGLOB)
    LEA.L	0x4(A4),A1                            | SET UP LIMIT POINTER
CLRLP:
    CLR.W	(A0)+                                 | CLEAR A WORD
    CMPA.L	A1,A0                                | CHECK LIMIT POINTER
    BNE.B	CLRLP                                 | CLEAR ALL GLOBALS
    LEA.L	-0x90(A4),A4                          | POINT TO WIDEDATA
    MOVE.L	A4,D0                                | REMEMBER ADDR OF WIDEDATA
    MOVE.W	#0xA,(A4)+                           | wideData.rgnSize := 10
    MOVE.L	#0x80018001,(A4)+                    | wideData.rgnBBox :=
    MOVE.L	#0x7FFF7FFF,(A4)+                    | (-32767,-32767,32767,32767)
    MOVE.L	A4,D1                                | REMEMBER ADDR OF WIDEMASTER
    MOVE.L	D0,(A4)+                             | wideMaster := @wideData
    MOVE.L	D1,(A4)+                             | wideOpen := @wideMaster
    MOVEQ.L	#0x1,D0                             | PREPARE RANDSEED INITIAL VALUE
    MOVE.L	D0,(A4)+                             | randSeed := 1
    MOVE.L	A4,-(A7)                             | point to screenBits
    _ScrnBitMap                                 | FILL IN SCREENBITS
    ADDA.W	#0xE,A4                              | bump past screenBits
    MOVEQ.L	#0x1A,D0                            | INIT LOOP COUNT (27 longs)
    LEA.L	CURDATA(PC),A0                        | POINT TO CURSOR DATA
CRSRLP:
    MOVE.L	(A0)+,(A4)+                          | COPY A LONG INTO GLOBALS
    DBF.W	D0,CRSRLP                             | LOOP FOR 27 LONGS
    MOVEA.L	(A7)+,A4                            | RESTORE REG
    UNLK	A6                                     | DESTROY STACK FRAME
    MOVE.L	(A7)+,(A7)                           | STRIP PARAMETER
    RTS                                         | AND RETURN
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
| The 108-byte CURDATA blob is encoded here as 1 short + 26 longs + 1
| short to match the original ROM's 16-bit-aligned word layout. The .long
| boundaries do NOT align with the logical fields (each cursor row is 2
| bytes, hotspot is 4 bytes, each pattern is 8 bytes). The byte stream is:
|
|   bytes  0..31  : arrow.data    (16 rows x 2 bytes, MSB-first bitmap)
|   bytes 32..63  : arrow.mask    (16 rows x 2 bytes)
|   bytes 64..67  : arrow.hotspot (V word=1, H word=1)
|   bytes 68..75  : dkGray pattern (75% black)
|   bytes 76..83  : ltGray pattern (25% black)
|   bytes 84..91  : gray pattern   (50% checkerboard)
|   bytes 92..99  : black pattern  (100% black, all 0xFF)
|   bytes 100..107: white pattern  (0%, all 0x00)
CURDATA:
    .short	0x0000
    .long	0x40006000
    .long	0x70007800
    .long	0x7C007E00
    .long	0x7F007F80
    .long	0x7C006C00
    .long	0x46000600
    .long	0x03000300
    .long	0x0000C000
    .long	0xE000F000
    .long	0xF800FC00
    .long	0xFE00FF00
    .long	0xFF80FFC0
    .long	0xFFE0FE00
    .long	0xEF00CF00
    .long	0x87800780
    .long	0x03800001
    .long	0x000177DD
    .long	0x77DD77DD
    .long	0x77DD8822
    .long	0x88228822
    .long	0x8822AA55
    .long	0xAA55AA55
    .long	0xAA55FFFF
    .long	0xFFFFFFFF
    .long	0xFFFF0000
    .long	0x00000000
    .short	0x0000
| .PROC OpenPort,1
| .REF NewRgn
| -------------------------------------------------------------
|
| PROCEDURE OpenPort(port: GrafPtr);
| { allocate clipRgn and visRgn, then call InitPort.
|
| Called during boot.
OPENPORT:
    CLR.L	-(A7)                                 | MAKE ROOM FOR FUNCTION RESULT
    JSR	NEWRGN(PC)                              | ALLOCATE A NEW REGION
    CLR.L	-(A7)                                 | MAKE ROOM FOR FUNCTION RESULT
    JSR	NEWRGN(PC)                              | ALLOCATE A SECOND NEW REGION
    MOVEA.L	0xC(A7),A0                          | POINT TO PORT
    MOVE.L	(A7)+,0x1C(A0)                       | INSTALL NEW REGION INTO CLIPRGN
    MOVE.L	(A7)+,0x18(A0)                       | AND OTHER INTO VISRGN
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
INITPORT:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	0x4(A7),A1                          | GET PORT PARAM
    MOVE.L	A1,(A0)                              | SetPort(port)
    CLR.W	(A1)+                                 | DEVICE := 0
    LEA.L	-0x7A(A0),A0                          | POINT TO SCREENBITS
    MOVE.L	(A0)+,(A1)+                          | portBits.baseAddr := screenBits.baseAddr
    MOVE.W	(A0)+,(A1)+                          | COPY ROWBYTES
    MOVE.L	(A0),(A1)+                           | COPY TOPLEFT
    MOVE.L	0x4(A0),(A1)+                        | COPY BOTRIGHT
    MOVE.L	(A0),(A1)+                           | portRect := screenBits.bounds
    MOVE.L	0x4(A0),(A1)+                        | all 8 bytes
    MOVE.L	(A1)+,-(A7)                          | visRgn := screenBits.bounds
    MOVE.L	A0,-(A7)                             | PUSH ADDR OF RECT
    JSR	RECTRGN(PC)                             | CALL RECTRGN
    MOVEA.L	0x4(A7),A1                          | GET PORT PARAM
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVE.L	-0x82(A0),-(A7)                      | PUSH WIDE OPEN RGN
    MOVE.L	0x1C(A1),-(A7)                       | PUSH CLIPRGN
    JSR	COPYRGN(PC)                             | SET TO WIDE OPEN
    MOVEA.L	0x4(A7),A1                          | GET PORT PARAM
    LEA.L	0x20(A1),A1                           | POINT TO BKPAT
    CLR.L	(A1)+                                 | bkPat := white
    CLR.L	(A1)+                                 | CLEAR SECOND LONG OF WHITE
    MOVEQ.L	#-0x1,D0                            | GET ALL ONES
    MOVE.L	D0,(A1)+                             | fillPat := Black
    MOVE.L	D0,(A1)+                             | SECOND LONG OF BLACK
    CLR.L	(A1)+                                 | pnLoc := (0,0)
    MOVE.L	#0x10001,(A1)+                       | pnSize := (1,1)
    MOVE.W	#0x8,(A1)+                           | pnMode := patCopy
    MOVE.L	D0,(A1)+                             | pnPat := black
    MOVE.L	D0,(A1)+                             | SECOND LONG OF BLACK
    CLR.W	(A1)+                                 | pnVis := 0
    CLR.L	(A1)+                                 | txFont, txFace := 0
    MOVE.W	#0x1,(A1)+                           | txMode := srcOr
    CLR.W	(A1)+                                 | txSize := 0
    CLR.L	(A1)+                                 | spExtra := 0.0
    MOVE.L	#0x21,(A1)+                          | fgColor := blackColor
    MOVE.L	#0x1E,(A1)+                          | bkColor := whiteColor
    CLR.L	(A1)+                                 | colrBit,patStretch := 0
    CLR.L	(A1)+                                 | picSave := Nil
    CLR.L	(A1)+                                 | rgnSave := Nil
    CLR.L	(A1)+                                 | polySave := Nil
    CLR.L	(A1)+                                 | grafProcs := Nil
    MOVE.L	(A7)+,(A7)                           | STRIP PARAM
    RTS                                         | AND RETURN
|
| .PROC ClosePort,1
| -------------------------------------------------------------
|
| PROCEDURE ClosePort(port: GrafPtr);
|
| { just disposes of clipRgn and visRgn }
|
| Called during boot.
CLOSEPORT:
    MOVEA.L	0x4(A7),A0                          | GET PORT
    MOVEA.L	0x1C(A0),A0                         | GET CLIPRGN HANDLE
    _DisposeHandle                              | DISCARD IT
    MOVEA.L	0x4(A7),A0                          | GET PORT
    MOVEA.L	0x18(A0),A0                         | GET VISRGN HANDLE
    _DisposeHandle                              | DISCARD IT
    MOVE.L	(A7)+,(A7)                           | STRIP PARAM
    RTS                                         | AND RETURN
| .PROC SetStdProcs
| Fill a QDProcs record with standard QuickDraw procedure pointers
| from the Toolbox trap dispatch table. Order matches QDProcs (GrafTypes.s).
| (SE FDHD trap-table addresses are offset 0x200 from Plus's; the entries
| themselves still point at _StdText/_StdLine/etc.)
SETSTDPROCS:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDRESS
    MOVEA.L	(A7)+,A1                            | POP PROCS POINTER
    MOVE.L	(0x1008).W,(A1)+                     | textProc = _StdText
    MOVE.L	(0x1040).W,(A1)+                     | lineProc = _StdLine
    MOVE.L	(0x1080).W,(A1)+                     | rectProc = _StdRect
    MOVE.L	(0x10BC).W,(A1)+                     | rRectProc = _StdRRect
    MOVE.L	(0x10D8).W,(A1)+                     | ovalProc = _StdOval
    MOVE.L	(0x10F4).W,(A1)+                     | arcProc = _StdArc
    MOVE.L	(0x1114).W,(A1)+                     | polyProc = _StdPoly
    MOVE.L	(0x1144).W,(A1)+                     | rgnProc = _StdRgn
    MOVE.L	(0x11AC).W,(A1)+                     | bitsProc = _StdBits
    MOVE.L	(0x11C4).W,(A1)+                     | commentProc = _StdComment
    MOVE.L	(0x11B4).W,(A1)+                     | txMeasProc = _StdTxMeas
    MOVE.L	(0x11B8).W,(A1)+                     | getPicProc = _StdGetPic
    MOVE.L	(0x11C0).W,(A1)+                     | putPicProc = _StdPutPic
    JMP	(A0)                                    | AND RETURN
| .PROC LocalToGlobal,1
| .DEF GlobalToLocal,AddPt,SubPt,SetPort,GetPort
| -------------------------------------------------------------
|
| PROCEDURE LocalToGlobal(VAR pt: Point);
|
| restores all registers.
| Called during boot.
LOCALTOGLOBAL:
    MOVEM.L	D0-D2/A0-A1,-(A7)                   | SAVE REGS
    MOVEQ.L	#0x1,D2                             | INDICATE SUB
    BRA.B	GLOBALTOLOCAL_CONT                    | SHARE COMMON CODE
| -------------------------------------------------------------
|
| PROCEDURE GlobalToLocal(VAR pt: Point);
|
| restores all registers.
|
| Called during boot (62,271 times in 30s trace).
GLOBALTOLOCAL:
    MOVEM.L	D0-D2/A0-A1,-(A7)                   | SAVE REGS
    MOVEQ.L	#0x0,D2                             | INDICATE ADD
GLOBALTOLOCAL_CONT:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | POINT TO CURRENT GRAFPORT
    MOVEA.L	0x18(A7),A1                         | POINT TO VAR PT
    MOVE.W	0x8(A0),D0                           | GET DV
    MOVE.W	0xA(A0),D1                           | GET DH
    BSR.B	ADDSUB                                | CONVERT TO LOCAL
    MOVEM.L	(A7)+,D0-D2/A0-A1                   | RESTORE REGS
    BRA.B	SHARE3                                | STRIP 4 BYTES AND RETURN
| ----------------------------------------------------------
|
| ADDSUB: shared core for AddPt / SubPt / LocalToGlobal / GlobalToLocal.
| D2=0 -> add (DV,DH) into (A1); D2 nonzero -> subtract (negate DV/DH first).
|
| Called during boot (62,279 times in 30s trace).
ADDSUB:
    TST.W	D2                                    | CHECK ADD OR SUB FLAG
    BEQ.B	JUSTADD                               | IF ADD FLAG, GO ADD
    NEG.W	D0                                    | NEGATE DV FOR SUB
    NEG.W	D1                                    | NEGATE DH FOR SUB
JUSTADD:
    ADD.W	D0,(A1)+                              | ADD DV
    ADD.W	D1,(A1)+                              | ADD DH
    RTS                                         | AND RETURN
| -------------------------------------------------------------
|
| PROCEDURE AddPt(src: Point; VAR dst: Point);
| { add two points together, restores all regs }
ADDPT:
    MOVEM.L	D0-D2/A1,-(A7)                      | SAVE REGS
    MOVEQ.L	#0x0,D2                             | INDICATE ADD
    BRA.B	SHARE2                                | SHARE COMMON CODE
| -------------------------------------------------------------
|
| PROCEDURE SubPt(src: Point; VAR dst: Point);
| { subtract src Point from dst point, restores all regs }
|
SUBPT:
    MOVEM.L	D0-D2/A1,-(A7)                      | SAVE REGS
    MOVEQ.L	#0x1,D2                             | INDICATE SUB
SHARE2:
    MOVEA.L	0x14(A7),A1                         | POINT TO DST
    MOVE.W	0x18(A7),D0                          | GET SRC DV
    MOVE.W	0x1A(A7),D1                          | GET SRC DH
    BSR.B	ADDSUB                                | CONVERT TO LOCAL
    MOVEM.L	(A7)+,D0-D2/A1                      | RESTORE REGS
    MOVE.L	(A7)+,(A7)                           | STRIP PARAM
SHARE3:
    MOVE.L	(A7)+,(A7)                           | STRIP PARAM
    RTS                                         | AND RETURN
| ----------------------------------------------------------
|
| PROCEDURE SetPort(gp: GrafPtr);
| { switch the current port to a different GrafPort }
| Called during boot (30,216 times in 30s trace).
SETPORT:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVE.L	0x4(A7),(A0)                         | SAVE NEW PORT IN THEPORT
    BRA.B	SHARE3                                | STRIP 4 BYTES AND RETURN
| ----------------------------------------------------------
|
| PROCEDURE GetPort(VAR gp: GrafPtr);
| { inquire the current GrafPort }
|
| Called during boot (17,610 times in 30s trace).
GETPORT:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	0x4(A7),A1                          | POINT TO VAR GP
    MOVE.L	(A0),(A1)                            | RETURN CURRENT PORT
    BRA.B	SHARE3                                | STRIP 4 BYTES AND RETURN
| .PROC GrafDevice,1
| .REF PortWord
| ----------------------------------------------------------
|
| PROCEDURE GrafDevice(device: INTEGER);
|
GRAFDEVICE:
    MOVEQ.L	#0x0,D0                             | SET DEVICE TO 0
    JMP	PORTWORD(PC)                            | INSTALL PARAM INTO THEPORT
| .PROC SetPortBits,1
| .DEF BackPat
| ----------------------------------------------------------
|
| PROCEDURE SetPortBits(bm: BitMap);
| { re-direct output to a different BitMap }
|
SETPORTBITS:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    LEA.L	0x2(A0),A0                            | POINT TO PORTBITS
    MOVEA.L	0x4(A7),A1                          | POINT TO BITMAP
    MOVE.L	(A1)+,(A0)+                          | COPY BASEADDR
    MOVE.W	(A1)+,(A0)+                          | COPY ROWBYTES
SETPORTBITS_SHARE:
    MOVE.L	(A1)+,(A0)+                          | SHARE: COPY BOUNDS.TOPLEFT
    MOVE.L	(A1)+,(A0)+                          | COPY BOUNDS.BOTRIGHT
    MOVE.L	(A7)+,(A7)                           | STRIP 4 BYTES
    RTS                                         | AND RETURN
| ----------------------------------------------------------
|
| PROCEDURE BackPat(pat: Pattern);
| { set the background pattern }
BACKPAT:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    LEA.L	0x20(A0),A0                           | POINT TO BKPAT
    MOVEA.L	0x4(A7),A1                          | GET ADDR OF PATTERN
    BRA.B	SETPORTBITS_SHARE                     | SHARE COPY CODE
| .PROC PortSize,2
| ----------------------------------------------------------
|
| PROCEDURE PortSize(width,height: INTEGER);
|
| Called during boot.
PORTSIZE:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    MOVE.W	0x12(A0),D0                          | GET PORTRECT.LEFT
    ADD.W	0x6(A7),D0                            | ADD WIDTH
    MOVE.W	D0,0x16(A0)                          | UPDATE PORTRECT.RIGHT
    MOVE.W	0x10(A0),D0                          | GET PORTRECT.TOP
    ADD.W	0x4(A7),D0                            | ADD HEIGHT
    MOVE.W	D0,0x14(A0)                          | UPDATE PORTRECT.BOTTOM
    MOVE.L	(A7)+,(A7)                           | STRIP 4 BYTES
    RTS                                         | AND RETURN
| .PROC MovePortTo,2
| .DEF SetOrigin,ClipRect
| .REF OffsetRgn,RectRgn
| ----------------------------------------------------------
|
| PROCEDURE MovePortTo(leftGlobal,topGlobal: INTEGER);
| { move portRect to a different part of the bitmap }
|
| Called during boot.
MOVEPORTTO:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    MOVE.W	0x12(A0),D0                          | GET PORTRECT.LEFT
    SUB.W	0xA(A0),D0                            | CONVERT TO GLOBAL
    SUB.W	0x6(A7),D0                            | SUB LEFTGLOBAL FOR DH
    MOVE.W	0x10(A0),D1                          | GET PORTRECT.TOP
    SUB.W	0x8(A0),D1                            | CONVERT TO GLOBAL
    SUB.W	0x4(A7),D1                            | SUB TOPGLOBAL FOR DV
    MOVE.L	(A7)+,(A7)                           | STRIP 4 BYTES
| OFSPORT -- oFFSET PORTBITS.BOUNDS.
OFSPORT:
    LEA.L	0x8(A0),A0                            | OFFSET PORTBITS.BOUNDS DH,DV
| OFSRECT -- oFFSET PORTRECT.
OFSRECT:
    ADD.W	D1,(A0)+                              | OFFSET TOP
    ADD.W	D0,(A0)+                              | OFFSET LEFT
    ADD.W	D1,(A0)+                              | OFFSET BOTTOM
    ADD.W	D0,(A0)+                              | OFFSET RIGHT
    RTS                                         | AND RETURN
| ----------------------------------------------------------
|
| PROCEDURE SetOrigin(h,v: INTEGER);
| { re-define the local coords by adjusting portBits.bounds, }
| { portRect, and visRgn }
|
| Called during boot.
SETORIGIN:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    MOVE.L	0x4(A7),D0                           | GET V AND H BOTH
    CMP.L	0x10(A0),D0                           | SAME AS ALREADY IN THEPORT ?
    BEQ.B	SETORIGIN_DONE                        | YES, QUIT
    MOVE.W	0x6(A7),D0                           | GET H
    SUB.W	0x12(A0),D0                           | DH:=H-PORTRECT.LEFT
    MOVE.W	0x4(A7),D1                           | GET V
    SUB.W	0x10(A0),D1                           | DV:=V-PORTRECT.TOP
    MOVE.L	0x18(A0),-(A7)                       | PUSH PARMS FOR LATER
    MOVE.W	D0,-(A7)                             | PUSH DH
    MOVE.W	D1,-(A7)                             | PUSH DV
    BSR.B	OFSPORT                               | OFFSET PORTBITS.BOUNDS
    LEA.L	(A0),A0                               | POINT A0 AT PORTRECT
    BSR.B	OFSRECT                               | OFFSET PORTRECT
    JSR	OFFSETRGN(PC)                           | OFFSET VISRGN
SETORIGIN_DONE:
    MOVE.L	(A7)+,(A7)                           | DONE: STRIP 4 BYTES
    RTS                                         | AND RETURN
| ----------------------------------------------------------
|
| PROCEDURE ClipRect(r: Rect);
| { Make the current grafport's clipRgn match a given rectangle }
|
| Called during boot (64,069 times in 30s trace).
CLIPRECT:
    MOVEA.L	(A5),A0                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A0),A0                             | GET CURRENT GRAFPORT
    MOVE.L	0x1C(A0),-(A7)                       | PUSH CLIPRGN
    MOVE.L	0x8(A7),-(A7)                        | PUSH RECT POINTER
    JSR	RECTRGN(PC)                             | CLIPRGN := r
    BRA.B	SETORIGIN_DONE                        | STRIP PARAM AND RETURN
| ----------------------------------------------------------
|
| PROCEDURE SetClip(rgn: RgnHandle);
| { COPY rgn INTO THEPORT^.CLIPRGN }
|
SETCLIP:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDRESS
    MOVEA.L	(A5),A1                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A1),A1                             | POINT TO CURRENT PORT
    MOVE.L	0x1C(A1),-(A7)                       | PUSH CLIPRGN AS DST
    BRA.B	GETCLIP_SHARE                         | SHARE CopyRgn TAIL
| ----------------------------------------------------------
|
| PROCEDURE GetClip(rgn: RgnHandle);
| { COPY THEPORT^.CLIPRGN INTO rgn }
|
GETCLIP:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDRESS
    MOVE.L	(A7)+,D0                             | POP DST RGNHANDLE
    MOVEA.L	(A5),A1                             | POINT TO QUICKDRAW GLOBALS
    MOVEA.L	(A1),A1                             | POINT TO CURRENT PORT
    MOVE.L	0x1C(A1),-(A7)                       | PUSH CLIPRGN AS SRC
    MOVE.L	D0,-(A7)                             | PUSH DST RGNHANDLE
GETCLIP_SHARE:
    MOVE.L	A0,-(A7)                             | RESTORE RETURN ADDRESS
    JMP	COPYRGN(PC)                             | TAIL-CALL CopyRgn
| ----------------------------------------------------------
|
| PROCEDURE SetPt(VAR pt: Point; h,v: INTEGER);
| { stuff h,v into a Point variable }
SETPT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDRESS
    MOVE.L	(A7)+,D0                             | POP H,V (long: V hi, H lo)
    MOVEA.L	(A7)+,A1                            | POP VAR PT POINTER
    MOVE.L	D0,(A1)                              | INSTALL V,H
    JMP	(A0)                                    | RETURN
| ----------------------------------------------------------
|
| FUNCTION EqualPt(pt1,pt2: Point): BOOLEAN;
| { return TRUE if pt1=pt2 }
EQUALPT:
    MOVEA.L	(A7)+,A0                            | POP RETURN ADDRESS
    MOVE.L	(A7)+,D0                             | POP PT1
    CMP.L	(A7)+,D0                              | COMPARE WITH PT2
    SEQ.B	(A7)                                  | SET BYTE-RESULT IF EQUAL
    NEG.B	(A7)                                  | TURN $01 INTO $FF (Pascal TRUE)
    JMP	(A0)                                    | RETURN
