| --------------------------------------------------------------
|
|
|     ****    ***   *    *   *   ***    ***   *   *   ***
|     *   *  *   *  *     * *   *   *  *   *  *   *  *   *
|     *   *  *   *  *      *    *      *   *  **  *  *
|     ****   *   *  *      *    *  **  *   *  * * *   ***
|     *      *   *  *      *    *   *  *   *  *  **      *
|     *      *   *  *      *    *   *  *   *  *   *  *   *
|     *       ***   *****  *     ***    ***   *   *   ***

| ---------------------------------------------------------------
|
| PROCEDURE StdPoly(verb: GrafVerb; poly: PolyHandle);
|
| A6 offsets of params and locals after LINK:
|   PARAMSIZE = 6
|   VERB      = PARAMSIZE+8-2  (GrafVerb)
|   POLY      = VERB-4         (LONG, PolyHandle)
|   MINRECT   = -8             (Rect)
|   VARSIZE   = MINRECT
|
STDPOLY:
    LINK	A6,#-0x8                               | allocate locals
    MOVEM.L	D5-D7/A2-A4,-(A7)                   | save regs
    MOVE.B	0xC(A6),D7                           | get verb
    JSR	CHECKPIC(PC)                            | set up A4,A3 and check PicSave
    BLE.B	STDPOLY_NOTPIC                        | branch if not PicSave
    MOVE.B	D7,-(A7)                             | push verb
    JSR	PUTPICVERB(PC)                          | put additional params to thePic
    MOVEQ.L	#0x70,D0                            | put PolyNoun in hi nibble
    ADD.W	D7,D0                                 | put verb in lo nibble
    JSR	DPUTPICBYTE(PC)                         | put opcode to thePic
    MOVE.L	0x8(A6),-(A7)                        | push PolyHandle
    JSR	PUTPICRGN(PC)                           | treat same as a region
STDPOLY_NOTPIC:
    MOVEA.L	0x8(A6),A2                          | get PolyHandle
    TST.B	D7                                    | is verb FRAME ?
    BNE.B	STDPOLY_NOTFR                         | no, continue
    MOVE.L	A2,-(A7)                             | push PolyHandle
    JSR	FRPOLY(PC)                              | FrPoly(poly)
    BRA.B	STDPOLY_GOHOME                        | and quit
| ----------------------------------------------------------
|
| STDPOLY_NOTFR -- non-frame verb: intersect bbox with vis/clip,
| then push verb+pattern and call DrawPoly.
|
STDPOLY_NOTFR:
    MOVEA.L	(A2),A0                             | de-reference PolyHandle
    PEA.L	0x2(A0)                               | push PolyBBox
    MOVEA.L	0x18(A3),A0                         | get visRgn handle
    MOVEA.L	(A0),A0                             | de-reference handle
    PEA.L	0x2(A0)                               | push visRgn bbox
    MOVEA.L	0x1C(A3),A0                         | get clipRgn handle
    MOVEA.L	(A0),A0                             | de-reference handle
    PEA.L	0x2(A0)                               | push clipRgn bbox
    MOVE.W	#0x3,-(A7)                           | push nRects = 3
    PEA.L	-0x8(A6)                              | put result in MinRect
    JSR	RSECT(PC)                               | calc intersection
    BEQ.B	STDPOLY_GOHOME                        | quit if no intersect
    MOVE.L	A2,-(A7)                             | push PolyHandle
    JSR	PUSHVERB(PC)                            | push mode and pattern
    JSR	DRAWPOLY(PC)                            | DrawPoly(poly,mode,pat)
STDPOLY_GOHOME:
    MOVEM.L	(A7)+,D5-D7/A2-A4                   | restore regs
    UNLK	A6                                     | restore A6
    MOVEA.L	(A7)+,A0                            | pop return addr
    ADDQ.W	#0x6,A7                              | strip params
    JMP	(A0)                                    | and return
| -----------------------------------------------------
|
| PROCEDURE FramePoly(* poly: PolyHandle *);
|
FRAMEPOLY:
    MOVEQ.L	#0x0,D0                             | verb = FRAME
    BRA.B	CALLPOLY                              | share common code
| -----------------------------------------------------
|
| PROCEDURE PaintPoly(* poly: PolyHandle *);
|
PAINTPOLY:
    MOVEQ.L	#0x1,D0                             | verb = PAINT
    BRA.B	CALLPOLY                              | share common code
| --------------------------------------------------------
|
| PROCEDURE ErasePoly(* poly: PolyHandle *);
|
ERASEPOLY:
    MOVEQ.L	#0x2,D0                             | verb = ERASE
    BRA.B	CALLPOLY                              | share common code
| --------------------------------------------------------
|
| PROCEDURE InvertPoly(* poly: PolyHandle *);
|
INVERTPOLY:
    MOVEQ.L	#0x3,D0                             | verb = INVERT
    BRA.B	CALLPOLY                              | share common code
| --------------------------------------------------------
|
| PROCEDURE FillPoly(* poly: PolyHandle; pat: Pattern *);
|
FILLPOLY:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVEA.L	(A7)+,A1                            | pop addr of pattern
    MOVE.L	A0,-(A7)                             | put return addr back
    MOVEA.L	(A5),A0                             | get global ptr
    MOVEA.L	(A0),A0                             | get thePort
    LEA.L	0x28(A0),A0                           | point to FillPat
    MOVE.L	(A1)+,(A0)+                          | copy pat into FillPat
    MOVE.L	(A1)+,(A0)+                          | all eight bytes
    MOVEQ.L	#0x4,D0                             | verb = FILL
    NOP                                         | alignment padding
| ---------------------------------------------------------------
|
| PROCEDURE CallPoly(poly: PolyHandle);
|
| Code shared by FramePoly, PaintPoly, ErasePoly, InvertPoly, FillPoly.
| Enter with verb in D0.
|
CALLPOLY:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVEA.L	(A7)+,A1                            | pop poly
    MOVE.B	D0,-(A7)                             | push verb
    MOVE.L	A1,-(A7)                             | push poly
    MOVE.L	A0,-(A7)                             | restore return addr
    MOVEA.L	(A5),A0                             | get global ptr
    MOVEA.L	(A0),A0                             | get thePort
    MOVE.L	0x68(A0),D0                          | is GrafProcs nil ?
    MOVEA.L	(0x1114).W,A0                       | _StdPoly (polyProc)
    BEQ.B	CALLPOLY_USESTD                       | yes, use std proc
    MOVEA.L	D0,A0                               | put proc ptr in A0
    MOVEA.L	0x18(A0),A0                         | no, get proc ptr
CALLPOLY_USESTD:
    JMP	(A0)                                    | go to it
| ---------------------------------------------------------------
|
| FUNCTION OpenPoly: PolyHandle;
|
| STARTSIZE = 138 (enough for 32 points)
|
OPENPOLY:
    JSR	HIDEPEN(PC)                             | turn off drawing
    CLR.L	-(A7)                                 | make room for fcn result
    MOVE.W	#0x8A,-(A7)                          | push StartSize = 138
    JSR	NEWHANDLE(PC)                           | NewHandle(StartSize)
    MOVEA.L	(A7)+,A1                            | pop resulting handle
    MOVE.L	A1,0x4(A7)                           | put handle in fcn result
    MOVEA.L	(A5),A0                             | get global ptr
    MOVE.L	A1,-0xA2(A0)                         | remember handle in ThePoly
    MOVE.W	#0x8A,-0xA4(A0)                      | PolyMax := 138
    MOVEA.L	(A0),A0                             | get thePort
    MOVEQ.L	#0x1,D0                             | set D0 to 1 (TRUE)
    MOVE.L	D0,0x64(A0)                          | PolySave := TRUE
    MOVEA.L	(A1),A1                             | de-reference handle
    MOVE.W	#0xA,(A1)+                           | install PolySize = 10
    CLR.L	(A1)+                                 | zero out PolyBBox
    CLR.L	(A1)+                                 | finish zeroing PolyBBox
    RTS                                         | return from OPENPOLY
| ---------------------------------------------------------------
|
| PROCEDURE ClosePoly;
|
CLOSEPOLY:
    MOVEM.L	D3-D7/A4,-(A7)                      | save regs
    MOVEA.L	(A5),A4                             | get global ptr
    MOVEA.L	(A4),A0                             | get thePort
    CLR.L	0x64(A0)                              | PolySave := FALSE
    MOVEA.L	-0xA2(A4),A4                        | get ThePoly handle
    MOVEA.L	(A4),A0                             | de-reference ThePoly
    MOVE.W	(A0)+,D7                             | get PolySize
    CLR.L	(A0)+                                 | zero out PolyBBox
    CLR.L	(A0)+                                 | finish zeroing PolyBBox
    MOVE.W	D7,D6                                | NPoints = PolySize
    SUBI.W	#0xA,D6                              | NPoints = PolySize - 10
    LSR.W	#0x2,D6                               | NPoints = (Size-10) DIV 4
    BEQ.B	EMPTY                                 | quit if no points
| -----------------------------------------------------
|
| Scan for bounding box of polygon
|
    MOVE.W	(A0)+,D1                             | top := first point vert
    MOVE.W	D1,D2                                | bottom := first point vert
    MOVE.W	(A0)+,D3                             | left := first point horiz
    MOVE.W	D3,D4                                | right := first point horiz
    SUBQ.W	#0x1,D6                              | prepare for DBF
    BRA.B	RIGHTOK                               | go to loop start
| ----------------------------------------------------------
|
| CLOSEPOLY_NEXTPT -- update bounding box per vertex
|
CLOSEPOLY_NEXTPT:
    MOVE.W	(A0)+,D0                             | get vert coord
    CMP.W	D1,D0                                 | is vert < bbox top ?
    BGE.B	CLOSEPOLY_TOPOK                       | no, continue
    MOVE.W	D0,D1                                | yes, update bbox top
CLOSEPOLY_TOPOK:
    CMP.W	D2,D0                                 | is vert > bbox bottom ?
    BLE.B	CLOSEPOLY_BOTOK                       | no, continue
    MOVE.W	D0,D2                                | yes, update bbox bottom
CLOSEPOLY_BOTOK:
    MOVE.W	(A0)+,D0                             | get horiz coord
    CMP.W	D3,D0                                 | is horiz < bbox left ?
    BGE.B	CLOSEPOLY_LEFTOK                      | no, continue
    MOVE.W	D0,D3                                | yes, update bbox left
CLOSEPOLY_LEFTOK:
    CMP.W	D4,D0                                 | is horiz > bbox right ?
    BLE.B	RIGHTOK                               | no, continue
    MOVE.W	D0,D4                                | yes, update bbox right
RIGHTOK:
    DBF.W	D6,CLOSEPOLY_NEXTPT                   | loop all points
    MOVEA.L	(A4),A0                             | de-reference ThePoly
    LEA.L	0x2(A0),A0                            | point to PolyBBox
    MOVE.W	D1,(A0)+                             | install bbox top
    MOVE.W	D3,(A0)+                             | install bbox left
    MOVE.W	D2,(A0)+                             | install bbox bottom
    MOVE.W	D4,(A0)+                             | install bbox right
| --------------------------------------------------------
|
| EMPTY -- trim ThePoly to final size, show pen and quit
|
EMPTY:
    MOVE.L	A4,-(A7)                             | push ThePoly handle
    MOVE.W	D7,-(A7)                             | push ByteCount = PolySize
    JSR	SETHSIZE(PC)                            | trim to minimum size
    JSR	SHOWPEN(PC)                             | restore PnVis
    MOVEM.L	(A7)+,D3-D7/A4                      | restore regs
    RTS                                         | and return
| ---------------------------------------------------
|
| PROCEDURE KillPoly(poly: PolyHandle);
|
KILLPOLY:
    MOVEA.L	(A7)+,A1                            | pop return addr
    MOVEA.L	(A7)+,A0                            | pop handle
    _DisposeHandle                              | discard it
    JMP	(A1)                                    | and return
| ---------------------------------------------------
|
| PROCEDURE OffsetPoly(poly: PolyHandle; dh,dv: INTEGER);
|
OFFSETPOLY:
    MOVEA.L	(A7)+,A0                            | pop return addr
    MOVE.W	(A7)+,D0                             | pop dv
    MOVE.W	(A7)+,D1                             | pop dh
    MOVEA.L	(A7)+,A1                            | pop PolyHandle
    MOVEA.L	(A1),A1                             | de-reference PolyHandle
    MOVE.W	(A1)+,D2                             | get PolySize
    SUBQ.W	#0x2,D2                              | # points = PolySize - 2
    LSR.W	#0x2,D2                               | # points = (Size-2) DIV 4
    SUBQ.W	#0x1,D2                              | prepare for DBF
OFFSETPOLY_NEXTPT:
    ADD.W	D0,(A1)+                              | offset vert coord
    ADD.W	D1,(A1)+                              | offset horiz coord
    DBF.W	D2,OFFSETPOLY_NEXTPT                  | loop for all points
    JMP	(A0)                                    | and return
| -------------------------------------------------------------
|
| PROCEDURE MapPoly(poly: PolyHandle; fromRect, toRect: Rect);
|
| A6 offsets of parameters and locals after LINK:
|   PARAMSIZE = 12
|   POLY      = PARAMSIZE+8-4  (LONG, RgnHandle)
|   FROMRECT  = POLY-4         (LONG, addr of Rect)
|   TORECT    = FROMRECT-4     (LONG, addr of Rect)
|
MAPPOLY:
    LINK	A6,#0x0                                | allocate stack frame
    MOVEM.L	D7/A2-A4,-(A7)                      | save regs
|
| Quit fast if FromRect = ToRect
|
    MOVEA.L	0xC(A6),A2                          | point to FromRect
    MOVEA.L	0x8(A6),A3                          | point to ToRect
    MOVE.L	(A2),D0                              | get topLeft of FromRect
    CMP.L	(A3),D0                               | is topLeft same ?
    BNE.B	MAPPOLY_NOTSAME                       | no, continue
    MOVE.L	0x4(A2),D0                           | get botRight of FromRect
    CMP.L	0x4(A3),D0                            | yes, is botRight same too ?
    BEQ.B	MAPPOLY_DONE                          | if so, just quit
MAPPOLY_NOTSAME:
    MOVEA.L	0x10(A6),A4                         | get PolyHandle
    MOVEA.L	(A4),A4                             | de-reference PolyHandle
    PEA.L	0x2(A4)                               | push addr of bbox
    MOVE.L	A2,-(A7)                             | push FromRect
    MOVE.L	A3,-(A7)                             | push ToRect
    JSR	MAPRECT(PC)                             | map PolyBBox
    MOVEQ.L	#0xA,D0                             | sizeof poly header
    MOVE.W	(A4),D7                              | get PolySize
    SUB.W	D0,D7                                 | PolySize - 10
    LSR.W	#0x2,D7                               | NPoints = (PolySize-10) DIV 4
    ADDA.W	D0,A4                                | point to first point
    BRA.B	MAPPOLY_START                         | go to loop start
| ----------------------------------------------------------
|
| MAPPOLY_NEXTPT
|
MAPPOLY_NEXTPT:
    MOVE.L	A4,-(A7)                             | push addr of point
    MOVE.L	A2,-(A7)                             | push FromRect
    MOVE.L	A3,-(A7)                             | push ToRect
    JSR	MAPPT(PC)                               | map this point
    ADDQ.W	#0x4,A4                              | bump pointer to next point
MAPPOLY_START:
    DBF.W	D7,MAPPOLY_NEXTPT                     | loop all points in poly
MAPPOLY_DONE:
    MOVEM.L	(A7)+,D7/A2-A4                      | restore regs
    UNLK	A6                                     | restore A6
    MOVEA.L	(A7)+,A0                            | pop return addr
    ADDA.W	#0xC,A7                              | strip params
    JMP	(A0)                                    | and return
| --------------------------------------------------------
|
| PROCEDURE FrPoly(poly: PolyHandle);
|
| MoveTo first point, DoLine to each subsequent point.
|
FRPOLY:
    LINK	A6,#0x0                                | allocate stack frame
    MOVEM.L	D6-D7/A4,-(A7)                      | save regs
    MOVEA.L	0x8(A6),A4                          | get PolyHandle
    MOVEA.L	(A4),A0                             | de-reference it
    MOVE.W	(A0),D7                              | get PolySize
    SUBI.W	#0xA,D7                              | PolySize - 10
    LSR.W	#0x2,D7                               | NPoints = (Size-10) DIV 4
    BEQ.B	FRPOLY_DONE                           | quit if empty polygon
    MOVE.L	0xA(A0),-(A7)                        | push first point
    JSR	MOVETO(PC)                              | MoveTo(first point)
    MOVEQ.L	#0xE,D6                             | start at second point (offset 14)
    SUBQ.W	#0x1,D7                              | prepare for DBF
    BRA.B	FRPOLY_START                          | got to loop start
| ----------------------------------------------------------
|
| FRPOLY_NEXTPT
|
FRPOLY_NEXTPT:
    MOVEA.L	(A4),A0                             | de-reference PolyHandle
    MOVE.L	0x0(A0,D6.W),-(A7)                   | push next point
    ADDQ.W	#0x4,D6                              | bump offset by 4 bytes
    JSR	DOLINE(PC)                              | DoLine(pt)
FRPOLY_START:
    DBF.W	D7,FRPOLY_NEXTPT                      | loop for all points
FRPOLY_DONE:
    MOVEM.L	(A7)+,D6-D7/A4                      | restore regs
    UNLK	A6                                     | restore A6
    MOVE.L	(A7)+,(A7)                           | strip param and adjust return addr
    RTS                                         | and return
| --------------------------------------------------------
|
| PROCEDURE DrawPoly(poly: PolyHandle; mode: INTEGER; VAR pat: Pattern);
|
| A6 offsets of params and locals after LINK:
|   PARAMSIZE = 10
|   POLY      = PARAMSIZE+8-4  (LONG, PolyHandle)
|   MODE      = POLY-2         (WORD)
|   PAT       = MODE-4         (LONG, addr of Pattern)
|
DRAWPOLY:
    LINK	A6,#0x0                                | no local vars
    MOVE.L	A4,-(A7)                             | save reg
    MOVEA.L	(A5),A0                             | get global ptr
    MOVEA.L	(A0),A0                             | get thePort
    TST.W	0x42(A0)                              | is PnVis neg ?
    BMI.B	DRAWPOLY_DONE                         | yes, quit
    JSR	OPENRGN(PC)                             | OpenRgn
    MOVE.L	0xE(A6),-(A7)                        | push PolyHandle
    JSR	FRPOLY(PC)                              | FrPoly(poly)
    MOVEA.L	0xE(A6),A0                          | get PolyHandle
    MOVEA.L	(A0),A0                             | de-reference it
    MOVE.L	0xA(A0),-(A7)                        | push first point
    JSR	DOLINE(PC)                              | make sure it closes
    CLR.L	-(A7)                                 | room for fcn result
    JSR	NEWRGN(PC)                              | allocate TempRgn
    MOVEA.L	(A7),A4                             | put TempRgn in A4
    JSR	CLOSERGN(PC)                            | CloseRgn(TempRgn)
    MOVE.L	A4,-(A7)                             | push TempRgn
    MOVE.W	0xC(A6),-(A7)                        | push mode
    MOVE.L	0x8(A6),-(A7)                        | push addr of pattern
    JSR	DRAWRGN(PC)                             | DrawRgn(TempRgn,mode,pat)
    MOVEA.L	A4,A0                               | get TempRgn
    _DisposeHandle                              | discard it
DRAWPOLY_DONE:
    MOVEM.L	(A7)+,A4                            | restore reg
    UNLK	A6                                     | restore A6
    MOVEA.L	(A7)+,A0                            | pop return addr
    ADDA.W	#0xA,A7                              | strip params
    JMP	(A0)                                    | and return
