| -----------------------------------------------------------
|
|
|     ****   *****   ***   ***   ***   *   *   ***
|     *   *  *      *   *   *   *   *  *   *  *   *
|     *   *  *      *       *   *   *  **  *  *
|     ****   ***    *  **   *   *   *  * * *   ***
|     * *    *      *   *   *   *   *  *  **      *
|     *  *   *      *   *   *   *   *  *   *  *   *
|     *   *  *****   ***   ***   ***   *   *   ***
|
|
|
|  QuickDraw Routines to operate on Regions.

| ---------------------------------------------------------------
|
| PROCEDURE StdRgn(verb: GrafVerb; rgn: RgnHandle);
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 6
|   VERB      = PARAMSIZE+8-2  (GrafVerb)
|   RGN       = VERB-4         (LONG, RgnHandle)
|
STDRGN:
    LINK        A6,#0x0                         | no locals
    MOVEM.L     D6-D7/A2-A4,-(A7)               | save regs
    MOVE.B      0xC(A6),D7                      | get verb
    JSR         CHECKPIC(PC)                    | set up A4,A3 and check PicSave
    BLE.B       STDRGN_NOTPIC                   | branch if not PicSave
    MOVE.B      D7,-(A7)                        | push verb
    JSR         PUTPICVERB(PC)                  | put additional params to thePic
    MOVE.W      #0x80,D0                        | put RgnNoun in hi nibble
    ADD.W       D7,D0                           | put verb in lo nibble
    JSR         DPUTPICBYTE(PC)                 | put opcode to thePic
    MOVE.L      0x8(A6),-(A7)                   | push RgnHandle
    JSR         PUTPICRGN(PC)                   | put region to thePic
STDRGN_NOTPIC:
    MOVE.L      0x8(A6),-(A7)                   | push RgnHandle
    JSR         PUSHVERB(PC)                    | push mode and pattern
    TST.B       D7                              | is verb FRAME ?
    BNE.B       STDRGN_NOTFR                    | no, continue
    TST.L       0x60(A3)                        | yes, is RgnSave true ?
    BEQ.B       STDRGN_NOTRGN                   | no, continue
    MOVE.L      0x8(A6),-(A7)                   | yes, push RgnHandle
    MOVE.L      -0x94(A4),-(A7)                 | push RgnBuf
    PEA.L       -0x96(A4)                       | push VAR RgnIndex
    PEA.L       -0x98(A4)                       | push VAR RgnMax
    JSR         PUTRGN(PC)                      | add inversion pts to TheRgn
STDRGN_NOTRGN:
    JSR         FRRGN(PC)                       | FrRgn(rgn,pnMode,pnPat)
    BRA.B       STDRGN_GOHOME                   | go to gohome
| ----------------------------------------------------------
|
| STDRGN_NOTFR -- non-frame verb: dispatch to DrawRgn
|
STDRGN_NOTFR:
    JSR         DRAWRGN(PC)                     | DrawRgn(rgn,mode,pat)
STDRGN_GOHOME:
    MOVEM.L     (A7)+,D6-D7/A2-A4               | restore regs
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDQ.W      #0x6,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from STDRGN_GOHOME via A0
| -----------------------------------------------------
|
| PROCEDURE FrameRgn(* rgn: RgnHandle *);
|
FRAMERGN:
    MOVEQ.L     #0x0,D0                         | verb = FRAME
    BRA.B       CALLRGN                         | share common code
| -----------------------------------------------------
|
| PROCEDURE PaintRgn(* rgn: RgnHandle *);
|
PAINTRGN:
    MOVEQ.L     #0x1,D0                         | verb = PAINT
    BRA.B       CALLRGN                         | share common code
| --------------------------------------------------------
|
| PROCEDURE EraseRgn(* rgn: RgnHandle *);
|
ERASERGN:
    MOVEQ.L     #0x2,D0                         | verb = ERASE
    BRA.B       CALLRGN                         | share common code
| --------------------------------------------------------
|
| PROCEDURE InvertRgn(* rgn: RgnHandle *);
|
INVERTRGN:
    MOVEQ.L     #0x3,D0                         | verb = INVERT
    BRA.B       CALLRGN                         | share common code
| --------------------------------------------------------
|
| PROCEDURE FillRgn(* rgn: RgnHandle; pat: Pattern *);
|
FILLRGN:
    MOVEA.L     (A7)+,A0                        | pop return addr
    MOVEA.L     (A7)+,A1                        | pop addr of pattern
    MOVE.L      A0,-(A7)                        | put return addr back
    MOVEA.L     (A5),A0                         | point to GrafGlobals
    MOVEA.L     (A0),A0                         | point to thePort
    LEA.L       0x28(A0),A0                     | point to FillPat
    MOVE.L      (A1)+,(A0)+                     | copy pat into FillPat
    MOVE.L      (A1)+,(A0)+                     | all eight bytes
    MOVEQ.L     #0x4,D0                         | verb = FILL
    NOP                                         | share common code with CallRgn
| ---------------------------------------------------------------
|
| PROCEDURE CallRgn(rgn: RgnHandle);
|
| Code shared by FrameRgn, PaintRgn, EraseRgn, InvertRgn, FillRgn.
| Enter with verb in D0.
|
CALLRGN:
    MOVEA.L     (A7)+,A0                        | pop return addr
    MOVEA.L     (A7)+,A1                        | pop rgn
    MOVE.B      D0,-(A7)                        | push verb
    MOVE.L      A1,-(A7)                        | push rgn
    MOVE.L      A0,-(A7)                        | restore return addr
    MOVEA.L     (A5),A0                         | get global ptr
    MOVEA.L     (A0),A0                         | get thePort
    MOVE.L      0x68(A0),D0                     | is GrafProcs nil ?
    MOVEA.L     (0x1144).W,A0                   | _StdRgn (rgnProc)
    BEQ.B       CALLRGN_USESTD                  | yes, use std proc
    MOVEA.L     D0,A0                           | put proc ptr in A0
    MOVEA.L     0x1C(A0),A0                     | no, get proc ptr
CALLRGN_USESTD:
    JMP         (A0)                            | go to it
| ----------------------------------------------------------------
|
| PROCEDURE DrawRgn(rgn: RgnHandle; mode: INTEGER; pat: Pattern);
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 10
|   RGN       = PARAMSIZE+8-4  (LONG, RgnHandle)
|   MODE      = RGN-2          (WORD)
|   PAT       = MODE-4         (LONG, addr of Pattern)
|
DRAWRGN:
    LINK        A6,#0x0                         | establish stack frame
    MOVEA.L     (A5),A0                         | point to GrafGlobals
    MOVEA.L     (A0),A0                         | point to thePort
    TST.W       0x42(A0)                        | is PnVis neg ?
    BMI.B       DRAWRGN_EXIT                    | yes, quit
    PEA.L       0x2(A0)                         | push srcBits
    MOVE.L      (A7),-(A7)                      | push dstBits
    PEA.L       0x8(A0)                         | push portBits+bounds (srcRect)
    MOVE.L      (A7),-(A7)                      | push dstRect
    MOVE.W      0xC(A6),-(A7)                   | push mode
    MOVE.L      0x8(A6),-(A7)                   | push pat
    MOVE.L      0x1C(A0),-(A7)                  | push clipRgn
    MOVE.L      0x18(A0),-(A7)                  | push visRgn
    MOVE.L      0xE(A6),-(A7)                   | push rgn
    JSR         RGNBLT(PC)                      | call RgnBlt
DRAWRGN_EXIT:
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDA.W      #0xA,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from DRAWRGN_EXIT via A0
| --------------------------------------------------------
|
| PROCEDURE FrRgn(rgn: RgnHandle; mode: INTEGER; pat: Pattern);
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 10
|   RGN       = PARAMSIZE+8-4  (LONG, RgnHandle)
|   MODE      = RGN-2          (WORD)
|   PAT       = MODE-4         (LONG, addr of Pattern)
|
FRRGN:
    LINK        A6,#0x0                         | establish stack frame
    MOVEM.L     D7/A3-A4,-(A7)                  | save regs
    MOVEA.L     (A5),A4                         | point to GrafGlobals
    MOVEA.L     (A4),A3                         | point to thePort
    TST.W       0x42(A3)                        | is PnVis neg ?
    BMI.B       FRRGN_DONE                      | yes, quit
|
| Special-case rectangular region for speed
|
    MOVEA.L     0xE(A6),A0                      | get RgnHandle
    MOVEA.L     (A0),A0                         | de-reference it
    CMPI.W      #0xA,(A0)                       | is region rectangular ?
    BNE.B       FRRGN_NOTRECT                   | no, continue
    PEA.L       0x2(A0)                         | yes, push addr of bbox
    JSR         FRRECT(PC)                      | frame it
    BRA.B       FRRGN_DONE                      | and quit
| ----------------------------------------------------------
|
| FRRGN_NOTRECT -- non-rect region: alloc TempRgn, inset by PnSize,
| diff from original, draw the difference (which is the frame).
|
FRRGN_NOTRECT:
    CLR.L       -(A7)                           | make room for fcn result
    JSR         NEWRGN(PC)                      | allocate TempRgn
    MOVE.L      (A7)+,D7                        | put TempRgn in D7
    MOVE.L      0xE(A6),-(A7)                   | push rgn
    MOVE.L      D7,-(A7)                        | push TempRgn
    JSR         COPYRGN(PC)                     | copy rgn into TempRgn
    MOVE.L      D7,-(A7)                        | push TempRgn
    MOVE.L      0x34(A3),-(A7)                  | push PnSize
    JSR         INSETRGN(PC)                    | InsetRgn(TempRgn,PnSize)
    MOVE.L      0xE(A6),-(A7)                   | push rgn
    MOVE.L      D7,-(A7)                        | push TempRgn
    MOVE.L      D7,-(A7)                        | push TempRgn
    JSR         DIFFRGN(PC)                     | DiffRgn(rgn,TempRgn,TempRgn)
    MOVE.L      D7,-(A7)                        | push TempRgn
    MOVE.W      0xC(A6),-(A7)                   | push mode
    MOVE.L      0x8(A6),-(A7)                   | push pat
    JSR         DRAWRGN(PC)                     | DrawRgn(TempRgn,mode,pat)
    MOVEA.L     D7,A0                           | get TempRgn
    _DisposeHandle                              | discard it
FRRGN_DONE:
    MOVEM.L     (A7)+,D7/A3-A4                  | restore regs
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDA.W      #0xA,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from FRRGN_DONE via A0
| ---------------------------------------------------
|
| FUNCTION NewRgn;
|
| Allocate a new region and set it to the empty region.
|
| Called by: OPENPORT, SCROLLRECT, DRAWPICTURE_LOOP, DRAWPOLY, FRRGN_NOTRECT (and 2 more)
NEWRGN:
    MOVEM.L     D3/A2,-(A7)                     | save regs
    CLR.L       -(A7)                           | make room for fcn result
    MOVE.W      #0xA,-(A7)                      | push ByteCount=10
    JSR         NEWHANDLE(PC)                   | allocate a relocatable object
    MOVEA.L     (A7)+,A0                        | pop resulting handle
    MOVEM.L     (A7)+,D3/A2                     | restore regs
    MOVE.L      A0,0x4(A7)                      | store into NewRgn result
    MOVEA.L     (A0),A0                         | de-reference handle
    MOVE.W      #0xA,(A0)+                      | install RgnSize=10
    CLR.L       (A0)+                           | install RgnBBox=(0,0,0,0)
    CLR.L       (A0)+                           | clear RgnBBox bottom,right
    RTS                                         | return from NewRgn
| ---------------------------------------------------
|
| PROCEDURE DisposeRgn(rgn: RgnHandle);
|
DISPOSERGN:
    MOVEA.L     (A7)+,A1                        | pop return addr
    MOVEA.L     (A7)+,A0                        | pop handle
    _DisposeHandle                              | discard it
    JMP         (A1)                            | and return
| ---------------------------------------------------
|
| PROCEDURE OpenRgn;
|
OPENRGN:
    MOVEM.L     D3/A2-A4,-(A7)                  | save regs
    MOVEA.L     (A5),A4                         | point to GrafGlobals
    MOVEA.L     (A4),A0                         | point to thePort
    MOVEQ.L     #0x1,D0                         | get TRUE for RgnSave
    MOVE.L      D0,0x60(A0)                     | RgnSave := TRUE
    CLR.W       -0x96(A4)                       | RgnIndex := 0
    CLR.L       -(A7)                           | make room for fcn result
    MOVE.W      #0x100,-(A7)                    | push byte count = 256
    MOVE.W      (A7),-0x98(A4)                  | RgnMax := 256 too
    JSR         NEWHANDLE(PC)                   | allocate buffer
    MOVE.L      (A7)+,-0x94(A4)                 | RgnBuf := NewHandle(RgnMax)
    JSR         HIDEPEN(PC)                     | turn off drawing
    MOVEM.L     (A7)+,D3/A2-A4                  | restore regs
    RTS                                         | and return
| ---------------------------------------------------
|
| PROCEDURE CloseRgn(* dstRgn: RgnHandle *);
|
| Sort array of inversion points and pack into region.
|
CLOSERGN:
    LINK        A6,#-0x2                        | establish stack frame
    MOVEM.L     D3/A2-A4,-(A7)                  | save regs
    MOVEA.L     (A5),A4                         | point to GrafGlobals
    MOVEA.L     (A4),A0                         | point to thePort
    TST.L       0x60(A0)                        | is RgnSave true ?
    BEQ.B       CLOSERGN_DONE                   | no, abort
    CLR.L       0x60(A0)                        | yes, RgnSave := FALSE
    JSR         SHOWPEN(PC)                     | undo the HidePen from OpenRgn
    MOVE.W      -0x96(A4),D0                    | get current RgnIndex
    LSR.W       #0x2,D0                         | div by 4
    MOVE.W      D0,-0x2(A6)                     | for PtCount
    MOVEA.L     -0x94(A4),A3                    | get RgnBuf handle
    MOVE.L      (A3),-(A7)                      | push buf pointer
    MOVE.W      D0,-(A7)                        | push PtCount
    JSR         SORTPOINTS(PC)                  | quicksort in VH order
    MOVE.L      (A3),-(A7)                      | push buf pointer
    PEA.L       -0x2(A6)                        | push VAR PtCount
    JSR         CULLPOINTS(PC)                  | cancel duplicate pairs
    MOVE.L      A3,-(A7)                        | push RgnBuf handle
    MOVE.W      -0x2(A6),-(A7)                  | push (updated) PtCount
    MOVE.L      0x8(A6),-(A7)                   | push DstRgn
    JSR         PACKRGN(PC)                     | pack points into DstRgn
    MOVEA.L     A3,A0                           | get RgnBuf handle
    _DisposeHandle                              | discard it
CLOSERGN_DONE:
    MOVEM.L     (A7)+,D3/A2-A4                  | restore regs
    UNLK        A6                              | release stack frame
    MOVE.L      (A7)+,(A7)                      | strip parameters
    RTS                                         | return from CLOSERGN_DONE
| ---------------------------------------------------
|
| PROCEDURE CopyRgn(* srcRgn, dstRgn: RgnHandle *);
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 8
|   SRCRGN    = PARAMSIZE+8-4  (RgnHandle)
|   DSTRGN    = SRCRGN-4       (RgnHandle)
|
| Called by: INITPORT, GETCLIP_SHARE, FRRGN_NOTRECT, XORRGN_COPY, SCROLLRECT (and 2 more)
COPYRGN:
    LINK        A6,#0x0                         | establish stack frame
    MOVEA.L     0xC(A6),A0                      | get SrcRgn handle
    MOVEA.L     0x8(A6),A1                      | get DstRgn handle
    CMPA.L      A0,A1                           | are they the same ?
    BEQ.B       EVEN_EXIT                       | yes, quit
    MOVEA.L     (A0),A0                         | de-reference SrcRgn handle
    MOVEA.L     (A1),A1                         | de-reference DstRgn handle
    MOVE.W      (A0),D0                         | get SrcRgn size
    CMP.W       (A1),D0                         | is DstRgn size same as SrcRgn size ?
    BEQ.B       COPY                            | yes, continue
    MOVEM.L     D0/D3/A2,-(A7)                  | save regs and ByteCount
    MOVE.L      0x8(A6),-(A7)                   | push DstRgn handle
    MOVE.W      D0,-(A7)                        | push NewSize = src size
    JSR         SETHSIZE(PC)                    | change size of dst
    MOVEM.L     (A7)+,D0/D3/A2                  | restore regs and ByteCount
    MOVEA.L     0xC(A6),A0                      | get SrcRgn handle
    MOVEA.L     0x8(A6),A1                      | get DstRgn handle
    MOVEA.L     (A0),A0                         | de-reference SrcRgn handle
    MOVEA.L     (A1),A1                         | de-reference DstRgn handle
COPY:
    LSR.W       #0x2,D0                         | LongCount := ByteCount DIV 4
    BCC.B       EVEN                            | was there an odd word ?
    MOVE.W      (A0)+,(A1)+                     | yes, do it to make even
    BRA.B       EVEN                            | and continue
| ----------------------------------------------------------
|
| COPYRGN_COPYLP -- inner long-by-long copy loop
|
COPYRGN_COPYLP:
    MOVE.L      (A0)+,(A1)+                     | copy a long of src to dst
EVEN:
    DBF.W       D0,COPYRGN_COPYLP               | loop for all longs
EVEN_EXIT:
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDQ.W      #0x8,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from EVEN_EXIT via A0
| ---------------------------------------------------
|
| PROCEDURE SetEmptyRgn(rgn: RgnHandle);
|
SETEMPTYRGN:
    MOVEA.L     (A7)+,A0                        | pop return addr
    CLR.L       -(A7)                           | push left, top
    CLR.L       -(A7)                           | push right, bottom
    MOVE.L      A0,-(A7)                        | restore return addr
    JMP         SETRECTRGN(PC)                  | double up on code
| ---------------------------------------------------
|
| PROCEDURE SetRectRgn(rgn: RgnHandle; left,top,right,bottom: INTEGER);
|
| Make a rectangular region from 4 integers.
|
SETRECTRGN:
    LINK        A6,#0x0                         | establish stack frame
    MOVEM.L     D3/A2,-(A7)                     | save regs
    MOVEA.L     0x10(A6),A0                     | get rgn handle
    MOVEA.L     (A0),A1                         | de-reference handle
    MOVEQ.L     #0xA,D0                         | expected RgnSize = 10
    CMP.W       (A1),D0                         | is current region 10 bytes ?
    BEQ.B       SETRECTRGN_OK                   | yes, continue
    MOVE.L      A0,-(A7)                        | push RgnHandle
    MOVE.W      D0,-(A7)                        | push size = 10 bytes
    JSR         SETHSIZE(PC)                    | change size of region
    MOVEA.L     0x10(A6),A0                     | get rgn handle
    MOVEA.L     (A0),A1                         | de-reference handle
    MOVE.W      #0xA,(A1)                       | set RgnSize to 10
SETRECTRGN_OK:
    MOVE.L      0xC(A6),0x2(A1)                 | set topLeft
    MOVE.L      0x8(A6),0x6(A1)                 | set botRight
    MOVE.W      0x4(A1),D0                      | get left
    CMP.W       0x8(A1),D0                      | compare to right
    BGE.B       SETRECTRGN_EMPTY                | yes, set to empty
    MOVE.W      0x2(A1),D0                      | get top
    CMP.W       0x6(A1),D0                      | compare to bottom
    BLT.B       SETRECTRGN_DONE                 | yes, continue
SETRECTRGN_EMPTY:
    CLR.L       0x2(A1)                         | empty topLeft
    CLR.L       0x6(A1)                         | empty botRight
SETRECTRGN_DONE:
    MOVEM.L     (A7)+,D3/A2                     | restore regs
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDA.W      #0xC,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from SETRECTRGN_DONE via A0
| ---------------------------------------------------
|
| PROCEDURE RectRgn(rgn: RgnHandle; r: Rect);
|
| Make a rectangular region from a rectangle.
|
RECTRGN:
    MOVEA.L     (A7)+,A0                        | pop return addr
    MOVEA.L     (A7)+,A1                        | pop addr of rect
    MOVE.L      (A1)+,-(A7)                     | push topLeft
    MOVE.L      (A1)+,-(A7)                     | push botRight
    MOVE.L      A0,-(A7)                        | restore return addr
    JMP         SETRECTRGN(PC)                  | use SetRectRgn
| ---------------------------------------------------
|
| PROCEDURE OffsetRgn(rgn: RgnHandle; dh,dv: INTEGER);
|
OFFSETRGN:
    MOVEA.L     (A7)+,A1                        | pop return addr
    MOVE.W      (A7)+,D1                        | pop dv
    MOVE.W      (A7)+,D0                        | pop dh
    MOVEA.L     (A7)+,A0                        | pop rgn handle
    MOVEA.L     (A0),A0                         | de-reference it
    ADDQ.W      #0x2,A0                         | skip region size
| ------------------------------------------------------
|
| Offset the bounding box
|
    ADD.W       D1,(A0)+                        | add dv to top
    ADD.W       D0,(A0)+                        | add dh to left
    ADD.W       D1,(A0)+                        | add dv to bottom
    ADD.W       D0,(A0)+                        | add dh to right
    CMPI.W      #0xA,-0xA(A0)                   | is region rectangular ?
| ---------------------------------------------------------------------
|
| If non-rectangular region, offset the coordinates too.
|
    BEQ.B       OFFSETRGN_DONE                  | if so, we're all done
OFFSETRGN_NXTVERT:
    ADD.W       D1,(A0)+                        | offset vertical coord dv
OFFSETRGN_NXTHOR:
    ADD.W       D0,(A0)+                        | offset left coord dh
    ADD.W       D0,(A0)+                        | offset right coord dh
    CMPI.W      #0x7FFF,(A0)                    | is horiz end marker ?
    BNE.B       OFFSETRGN_NXTHOR                | no, loop
    ADDQ.W      #0x2,A0                         | skip end marker
    CMPI.W      #0x7FFF,(A0)                    | is horiz end marker ?
    BNE.B       OFFSETRGN_NXTVERT               | no, loop for more
OFFSETRGN_DONE:
    JMP         (A1)                            | done: return
| ---------------------------------------------------------
|
| PROCEDURE InsetRgn(rgn: RgnHandle; dh,dv: INTEGER);
|
| Inset a region by (dh,dv). Outset if dh or dv neg.
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 8
|   RGN       = PARAMSIZE+8-4  (LONG, RgnHandle)
|   DH        = RGN-2          (WORD)
|   DV        = DH-2           (WORD)
|
INSETRGN:
    LINK        A6,#0x0                         | no local vars
    MOVEM.L     D3-D7/A2-A4,-(A7)               | save regs
    MOVE.L      0x8(A6),D6                      | get DH and DV
    BEQ.B       JGOHOME                         | quit if both are zero
    MOVEA.L     0xC(A6),A4                      | get RgnHandle
    MOVEA.L     (A4),A3                         | de-reference it
    MOVE.W      (A3)+,D7                        | get RgnSize
    CMPI.W      #0xA,D7                         | is region rectangular ?
| --------------------------------------------------------------
|
| If rectangular region, call InsetRect and check for empty.
|
    BNE.B       INSETRGN_NOTRECT                | no, continue
    MOVE.L      A3,-(A7)                        | push addr of RgnBBox
    MOVE.L      D6,-(A7)                        | push DH and DV
    JSR         INSETRECT(PC)                   | InsetRect(rgn^^.RgnBBox,dh,dv)
    MOVE.W      0x2(A3),D0                      | get bbox left
    CMP.W       0x6(A3),D0                      | is left >= right ?
    BGE.B       INSETRGN_EMPTY                  | yes, return empty rgn
    MOVE.W      (A3),D0                         | get bbox top
    CMP.W       0x4(A3),D0                      | is top >= bottom ?
    BLT.B       JGOHOME                         | no, continue
INSETRGN_EMPTY:
    CLR.L       (A3)+                           | empty: set RgnBBox to (0,0,0,0)
    CLR.L       (A3)+                           | return empty region
JGOHOME:
    BRA.B       INSETRGN_GOHOME                 | all done
| -----------------------------------------------------
|
| INSETRGN_NOTRECT -- region is not rectangular: allocate
| a point buffer in the heap, do horizontal then vertical inset.
|
INSETRGN_NOTRECT:
    ADD.W       D7,D7                           | bytes needed = RgnSize*2
    CLR.L       -(A7)                           | room for fcn result
    MOVE.W      D7,-(A7)                        | push BytesNeeded
    JSR         NEWHANDLE(PC)                   | allocate PtBuf
    MOVEA.L     (A7)+,A3                        | put PtBuf handle in A3
    BSR.B       HINSET                          | inset horiz and flip
    SWAP.W      D6                              | get DV instead of DH
    BSR.B       HINSET                          | inset vertical and flip back
    BRA.B       INSETRGN_DONE                   | all done
| --------------------------------------------------------------------------
|
| HINSET -- local routine to inset horizontally, swap H and V coords,
| and re-sort.
|
| Calls: RgnOp(rgn,rgn,bufHandle,maxBytes,op,dh,TRUE)
|
HINSET:
    CLR.W       -(A7)                           | room for fcn result
    MOVE.L      A4,-(A7)                        | push RgnA = user rgn
    MOVE.L      A4,-(A7)                        | push RgnB = user rgn also
    MOVE.L      A3,-(A7)                        | push BufHandle
    MOVE.W      D7,-(A7)                        | push MaxBytes
    MOVE.W      #0x8,-(A7)                      | push op = INSET
    MOVE.W      D6,-(A7)                        | push DH
    ST.B        -(A7)                           | push OkGrow = TRUE
    JSR         RGNOP(PC)                       | perform region operation
    MOVE.W      (A7)+,D5                        | pop PtCount result
|
| Swap vert and horiz coords of all inversion points
|
    MOVEA.L     (A3),A0                         | de-reference PtBuf handle
    MOVE.W      D5,D1                           | copy PtCount
    BRA.B       SWAP2                           | go to loop start
| ----------------------------------------------------------
|
| SWAPLP -- swap H and V of each inversion point
|
SWAPLP:
    MOVE.L      (A0),D0                         | get a point
    SWAP.W      D0                              | swap its coordinates
    MOVE.L      D0,(A0)+                        | put it back into array
SWAP2:
    DBF.W       D1,SWAPLP                       | loop for all points
|
| Re-sort the points in V.H order
|
    MOVE.L      (A3),-(A7)                      | push PtBuf ptr
    MOVE.W      D5,-(A7)                        | push PtCount
    JSR         SORTPOINTS(PC)                  | re-sort into VH order
|
| Pack the resulting points
|
    MOVE.L      A3,-(A7)                        | push PtBuf handle
    MOVE.W      D5,-(A7)                        | push PtCount
    MOVE.L      A4,-(A7)                        | push rgn handle
    JSR         PACKRGN(PC)                     | PackRgn(PtBuf,PtCount,rgn)
    RTS                                         | return to local caller
| ----------------------------------------------
|
| INSETRGN_DONE -- discard point buffer and quit
|
INSETRGN_DONE:
    MOVEA.L     A3,A0                           | get PtBuf handle
    _DisposeHandle                              | discard it
INSETRGN_GOHOME:
    MOVEM.L     (A7)+,D3-D7/A2-A4               | restore regs
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDQ.W      #0x8,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from INSETRGN_GOHOME via A0
| ---------------------------------------------------
|
| FUNCTION EmptyRgn(rgn: RgnHandle): BOOLEAN;
|
EMPTYRGN:
    MOVEA.L     (A7)+,A0                        | pop return addr
    MOVEA.L     (A7)+,A1                        | pop RgnHandle
    MOVEA.L     (A1),A1                         | de-reference handle
    PEA.L       0x2(A1)                         | push RgnBBox
    MOVE.L      A0,-(A7)                        | push return addr
    JMP         EMPTYRECT(PC)                   | use EmptyRect code
| -------------------------------------------------------
|
| FUNCTION EqualRgn(rgnA, rgnB: RgnHandle): BOOLEAN;
|
| Returns TRUE if RgnA and RgnB describe the same area.
|
EQUALRGN:
    MOVEA.L     0x4(A7),A0                      | get RgnA handle
    MOVEA.L     0x8(A7),A1                      | get RgnB handle
    CMPA.L      A0,A1                           | are they the same ?
    BEQ.B       EQUALRGN_LOOP2_OK               | yes, the regions are the same
    MOVEA.L     (A0),A0                         | de-reference rgn A
    MOVEA.L     (A1),A1                         | de-reference rgn B
    MOVE.W      (A0),D0                         | get RgnSize A
    MOVE.W      D0,D1                           | make an extra copy
    LSR.W       #0x2,D1                         | div by 4 for long count
    SUBQ.W      #0x1,D1                         | adjust for DBF
EQUALRGN_LOOP:
    CMPM.L      (A0)+,(A1)+                     | compare a long
    DBNE.W      D1,EQUALRGN_LOOP                | look till different or count
    BNE.B       EQUALRGN_LOOP2_CONT             | different -> FALSE
    ANDI.W      #0x3,D0                         | get remaining bytes
    BEQ.B       EQUALRGN_LOOP2_OK               | if no more, we made it
EQUALRGN_LOOP2:
    CMPM.B      (A0)+,(A1)+                     | compare a byte
    BNE.B       EQUALRGN_LOOP2_CONT             | br if different
    SUBQ.W      #0x1,D0                         | adjust for DBF
    BNE.B       EQUALRGN_LOOP2                  | loop last 1..3 bytes
EQUALRGN_LOOP2_OK:
    MOVEQ.L     #0x1,D0                         | return TRUE
    BRA.B       EQUALRGN_DONE                   | go to done
| ----------------------------------------------------------
|
| EQUALRGN_LOOP2_CONT -- regions differ, return FALSE
|
EQUALRGN_LOOP2_CONT:
    MOVEQ.L     #0x0,D0                         | return FALSE
EQUALRGN_DONE:
    MOVE.B      D0,0xC(A7)                      | set result
    MOVEA.L     (A7)+,A0                        | pop return addr
    ADDQ.W      #0x8,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from EQUALRGN_DONE via A0
| ---------------------------------------------------------
|
| PROCEDURE SectRgn(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| Calculate the intersection of two regions.
|
SECTRGN:
    MOVEQ.L     #0x0,D0                         | op = SectScan
    BRA.B       DORGNOP                         | share common code
| ---------------------------------------------------------
|
| PROCEDURE UnionRgn(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| Calculate the union of two regions.
|
UNIONRGN:
    MOVEQ.L     #0x4,D0                         | op = UNION
    BRA.B       DORGNOP                         | share common code
| ---------------------------------------------------------
|
| PROCEDURE DiffRgn(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| Calculate the difference A-B of two regions.
|
DIFFRGN:
    MOVEQ.L     #0x2,D0                         | op = DIFF
    BRA.B       DORGNOP                         | share common code
| ---------------------------------------------------------
|
| PROCEDURE XorRgn(srcRgnA,srcRgnB,dstRgn: RgnHandle);
| Calculate the exclusive or of two regions.
|
XORRGN:
    MOVEQ.L     #0x6,D0                         | op = XOR
    NOP                                         | align
| ---------------------------------------------------------
|
| PROCEDURE DoRgnOp(srcRgnA,srcRgnB,dstRgn: RgnHandle);
|
| Computes the Intersection, Difference, Union, or Xor of two
| regions. Enter with op in D0:
|   op = 0: SectScan
|        2: DIFF A-B
|        4: UNION
|        6: XOR
|
DORGNOP:
    LINK        A6,#-0x8                        | establish stack frame
    MOVEM.L     D3-D7/A2-A4,-(A7)               | save regs
    MOVE.W      D0,D5                           | copy op into D5
    MOVEA.L     0x10(A6),A2                     | get RgnA
    MOVEA.L     0xC(A6),A3                      | get RgnB
    MOVEA.L     0x8(A6),A4                      | get DstRgn
    MOVEQ.L     #0x2,D7                         | constant for DIFF op
|
| Are the two input regions the same ?
|
    CLR.B       -(A7)                           | make room for fcn result
    MOVE.L      A2,-(A7)                        | push RgnA
    MOVE.L      A3,-(A7)                        | push RgnB
    JSR         EQUALRGN(PC)                    | call EqualRgn
    TST.B       (A7)+                           | are they the same ?
    BEQ.B       XORRGN_NOTSAME                  | no, continue
|
| The two regions are the same. If SectScan or UNION
| then copy RgnA into DstRgn, else zero out DstRgn.
|
    AND.W       D7,D5                           | was op SectScan or UNION ?
    BNE.B       XORRGN_ZERO                     | no, zero out DstRgn
XORRGN_COPY:
    MOVE.L      A2,-(A7)                        | push RgnA
    MOVE.L      A4,-(A7)                        | push DstRgn
    JSR         COPYRGN(PC)                     | copy RgnA into DstRgn
    BRA.B       JDONE                           | and quit
| ----------------------------------------------------------
|
| XORRGN_ZERO -- set destination region to empty
|
XORRGN_ZERO:
    MOVE.L      A4,-(A7)                        | push DstRgn
    JSR         SETEMPTYRGN(PC)                 | set it to empty
    BRA.B       JDONE                           | and quit
|
| IF OP = DIFF AND RGNB = EMPTY, COPY RGNA INTO DST
|
XORRGN_NOTSAME:
    MOVEA.L     (A2),A0                         | de-reference RgnA
    MOVEA.L     (A3),A1                         | de-reference RgnB
    CMP.W       D7,D5                           | is op = DIFF ?
    BGT.B       UNIXOR                          | no, its UNION or XOR
    BLT.B       BBOXES                          | no, it's SectScan
    MOVE.W      0x4(A1),D0                      | get left
    CMP.W       0x8(A1),D0                      | compare to right
    BGE.B       XORRGN_COPY                     | yes, copy RgnA into Dst
|
| If op = SectScan or DIFF, then intersect the bounding boxes.
|
BBOXES:
    PEA.L       0x2(A0)                         | push RgnA^^.RgnBBox
    PEA.L       0x2(A1)                         | push RgnB^^.RgnBBox
    MOVE.W      D7,-(A7)                        | push nRects = 2
    PEA.L       -0x8(A6)                        | push dst = TempRect
    JSR         RSECT(PC)                       | calc intersection
    BNE.B       NOTEMPTY                        | br if result not empty
|
| The bounding boxes don't intersect.
| If op = SectScan, then return empty.
| If op = DIFF, then copy RgnA into DstRgn.
|
    TST.W       D5                              | is op = SectScan ?
    BEQ.B       XORRGN_ZERO                     | yes, return empty
    BRA.B       XORRGN_COPY                     | no, copy SrcA into DstRgn
|
| IF OP = SectScan, then check for both inputs rectangular.
|
NOTEMPTY:
    MOVEA.L     (A2),A0                         | de-reference RgnA
    MOVEA.L     (A3),A1                         | de-reference RgnB
    TST.W       D5                              | is op = SectScan ?
    BNE.B       JDONE_NO_2                      | no, continue
    MOVEQ.L     #0xA,D0                         | expected RgnSize = 10
    CMP.W       (A0),D0                         | is RgnA rectangular ?
    BNE.B       JDONE_NO_2                      | no, continue
    CMP.W       (A1),D0                         | is RgnB rectangular ?
    BNE.B       JDONE_NO_2                      | no, continue
    MOVE.L      A4,-(A7)                        | push DstRgn
    PEA.L       -0x8(A6)                        | push TempRect
    JSR         RECTRGN(PC)                     | RectRgn(DstRgn,TempRect)
JDONE:
    BRA.B       JDONE_DONE                      | go to done
| ----------------------------------------------------------
|
| UNIXOR -- op = UNION or XOR: if either region is empty,
| copy the other.
|
UNIXOR:
    MOVE.W      0x4(A1),D0                      | get left
    CMP.W       0x8(A1),D0                      | compare to right
    BGE.B       XORRGN_COPY                     | yes, copy RgnA into Dst
    MOVE.W      0x4(A0),D0                      | get RgnA left
    CMP.W       0x8(A0),D0                      | compare to RgnA right
    BLT.B       JDONE_NO_2                      | no, continue
    MOVEA.L     A3,A2                           | yes, get RgnB instead
    BRA.B       XORRGN_COPY                     | copy RgnB into Dst
| ----------------------------------------------------------
|
| JDONE_NO_2 -- general path: alloc PtBuf, RgnOp, PackRgn
|
JDONE_NO_2:
    MOVE.W      (A0),D4                         | get RgnA size
    ADD.W       (A1),D4                         | add RgnB size
    ADD.W       D4,D4                           | try double for ByteCount
    CLR.L       -(A7)                           | make room for fcn result
    MOVE.W      D4,-(A7)                        | push ByteCount
    JSR         NEWHANDLE(PC)                   | allocate PtBuf
    MOVEA.L     (A7)+,A3                        | get PtBuf handle in A3
|
| PtCount := RgnOp(srcA,srcB,bufHandle,maxBytes,op,0,TRUE);
|
    CLR.W       -(A7)                           | make room for fcn result
    MOVE.L      0x10(A6),-(A7)                  | push RgnA
    MOVE.L      0xC(A6),-(A7)                   | push RgnB
    MOVE.L      A3,-(A7)                        | push BufHandle
    MOVE.W      D4,-(A7)                        | push MaxBytes
    MOVE.W      D5,-(A7)                        | push op
    CLR.W       -(A7)                           | push DH=0
    ST.B        -(A7)                           | push OkGrow = TRUE
    JSR         RGNOP(PC)                       | perform region operation
    MOVE.W      (A7)+,D6                        | get PtCount
    MOVE.L      A3,-(A7)                        | push PtBuf handle
    MOVE.W      D6,-(A7)                        | push PtCount
    MOVE.L      A4,-(A7)                        | push DstRgn
    JSR         PACKRGN(PC)                     | PackRgn(PtBuf,PtCount,DstRgn)
    MOVEA.L     A3,A0                           | get PtBuf handle
    _DisposeHandle                              | discard it
JDONE_DONE:
    MOVEM.L     (A7)+,D3-D7/A2-A4               | restore regs
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDA.W      #0xC,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from JDONE_DONE via A0
| ------------------------------------------------------------
|
| FUNCTION PtInRgn(pt: Point; rgn: RgnHandle): BOOLEAN;
|
| Tests if a given point is inside a region.
|
| A6 offsets of parameters after LINK:
|   PARAMSIZE = 8
|   RESULT    = PARAMSIZE+8    (BOOLEAN)
|   PT        = RESULT-4       (Point, value)
|   RGN       = PT-4           (LONG, handle)
|
PTINRGN:
    LINK        A6,#0x0                         | no local vars
    MOVE.L      D3,-(A7)                        | save reg
    MOVE.W      0xE(A6),D1                      | get pt.h
    MOVE.W      0xC(A6),D2                      | get pt.v
    CLR.W       D3                              | init Inside := FALSE
| -----------------------------------------------------------
|
| First check bounding box
|
    MOVEA.L     0x8(A6),A0                      | get rgn handle
    MOVEA.L     (A0),A0                         | de-reference it
    CMP.W       0x4(A0),D1                      | is pt.h < bbox left ?
    BLT.B       NEXTHOR_EXIT                    | yes, return FALSE
    CMP.W       0x8(A0),D1                      | is pt.h >= bbox right ?
    BGE.B       NEXTHOR_EXIT                    | yes, return FALSE
    CMP.W       0x2(A0),D2                      | is pt.v < bbox top ?
    BLT.B       NEXTHOR_EXIT                    | yes, return FALSE
    CMP.W       0x6(A0),D2                      | is pt.v >= bbox bottom ?
    BGE.B       NEXTHOR_EXIT                    | yes, return FALSE
    CMPI.W      #0xA,(A0)                       | is region rectangular ?
    BNE.B       PTINRGN_NO                      | no, continue
    NOT.W       D3                              | yes, return TRUE
    BRA.B       NEXTHOR_EXIT                    | go to done
| ------------------------------------------------------------------
|
| PT is inside bounding box and region is not rectangular.
| Look at the inversion points to determine if pt in region.
|
PTINRGN_NO:
    LEA.L       0xA(A0),A0                      | point to first vert coord
PTINRGN_NEXT:
    CMP.W       (A0)+,D2                        | is next vert > pt.v ?
    BLT.B       NEXTHOR_EXIT                    | yes, quit
NEXTHOR:
    MOVE.W      (A0)+,D0                        | get horiz coord
    CMPI.W      #0x7FFF,D0                      | is horiz end marker ?
    BEQ.B       PTINRGN_NEXT                    | yes, get next vert coord
    CMP.W       D1,D0                           | is horiz <= pt.h ?
    BGT.B       NEXTHOR                         | no, ignore this point
    NOT.W       D3                              | yes, toggle Inside
    BRA.B       NEXTHOR                         | and go for more points
| ----------------------------------------------------------
|
| NEXTHOR_EXIT -- return boolean result
|
| Called by: PTINRGN, PTINRGN_NEXT
NEXTHOR_EXIT:
    NEG.B       D3                              | boolean result is 0 or 1
    MOVE.B      D3,0x10(A6)                     | return boolean fcn result
    MOVE.L      (A7)+,D3                        | restore reg
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDQ.W      #0x8,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from NEXTHOR_EXIT via A0
| --------------------------------------------------
|
| FUNCTION RectInRgn(r: Rect; rgn: RgnHandle): BOOLEAN;
|
| Returns TRUE if any part of the rectangle intersects the region.
|
| A6 offsets of parameters after LINK:
|   PARAMSIZE = 8
|   RESULT    = PARAMSIZE+8    (byte, BOOLEAN)
|   RECT      = RESULT-4       (LONG, VAR addr)
|   RGN       = RECT-4         (LONG, RgnHandle)
|
| Locals:
|   MINRECT   = -8             (Rect)
|   SAVESTACK = MINRECT-4      (LONG)
|   STATE     = SAVESTACK-RgnRec (region state record)
|
RECTINRGN:
    LINK        A6,#-0x24                       | establish stack frame
    MOVEM.L     D0-D7/A1-A5,-(A7)               | save registers
    MOVE.L      A7,-0xC(A6)                     | remember stack start
    CLR.B       0x10(A6)                        | init boolean result to FALSE
    MOVEA.L     0x8(A6),A1                      | get region handle
    MOVEA.L     (A1),A1                         | de-reference it
| --------------------------------------------------------------
|
| First check if rectangle intersects bounding box of region
|
    MOVE.L      0xC(A6),-(A7)                   | push pointer to rect
    PEA.L       0x2(A1)                         | push pointer to RgnBBox
    MOVE.W      #0x2,-(A7)                      | push nRects = 2
    PEA.L       -0x8(A6)                        | push addr where to put result
    JSR         RSECT(PC)                       | calc intersection
    BEQ.B       TRUE_EXIT                       | quit if no intersection
    CMPI.W      #0xA,(A1)                       | is region rectangular ?
    BEQ.B       TRUE                            | yes, return TRUE
| ------------------------------------------------------------
|
| The region is non-rectangular and the rectangle intersects
| the region's bounding box. Play back the portion of the
| region within MinRect and see if any part is actually inside
| the rectangle.
|
| Initialize Rgn state record at top.
    MOVEA.L     A1,A0                           | get RgnPtr in A0
    LEA.L       -0x24(A6),A1                    | get state record in A1
    MOVE.W      -0x6(A6),D0                     | get MinRect left
    MOVE.W      -0x2(A6),D1                     | get MinRect right
    MOVE.W      D0,D2                           | BufLeft := MinH
    JSR         INITRGN(PC)                     | init record, allocate buffer
| ------------------------------------------------------------
|
| Play the region back into scan buffer until it gets down to
| MinRect, then check each scanline for non-zero playback.
| Quit and return TRUE if non-zero found before rgn goes beyond MinRect.
|
    MOVE.W      0xC(A1),D5                      | get BufSize = # longs - 1
    MOVE.W      -0x8(A6),D0                     | get MinRect top
    JSR         SEEKRGN(PC)                     | seek the region to MinRect top
    MOVE.W      -0x4(A6),D6                     | get MinRect bottom
TESTBUF:
    MOVEA.L     0x8(A1),A0                      | point to buffer start
    MOVE.W      D5,D0                           | init loop count to BufSize
NXTLONG:
    TST.L       (A0)+                           | is scan buf non-zero ?
    DBNE.W      D0,NXTLONG                      | test longs till non-zero or end
    BNE.B       TRUE                            | found non-zero, return TRUE
    MOVE.W      0x10(A1),D0                     | get next vertical in rgn
    CMP.W       D0,D6                           | is next rgn vert beyond bottom ?
    BLE.B       TRUE_EXIT                       | yes, return FALSE
    JSR         SEEKRGN(PC)                     | no, seek to next vert change
    BRA.B       TESTBUF                         | and see if it is non-zero
| ----------------------------------------------------------
|
| TRUE -- mark result and exit
|
TRUE:
    ADDQ.B      #0x1,0x10(A6)                   | set boolean result to TRUE
TRUE_EXIT:
    MOVEA.L     -0xC(A6),A7                     | strip scan buffer if any
    MOVEM.L     (A7)+,D0-D7/A1-A5               | restore registers
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDQ.W      #0x8,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from TRUE_EXIT via A0
| ------------------------------------------------------
|
| FUNCTION TrimRect(rgn: RgnHandle; VAR dstRect: Rect): CCR TRISTATE;
|
| Result in condition codes:
|   = result rectangular, dstRect trimmed
|   < result empty, dstRect not modified
|   > result non-rect, dstRect not modified
|
| If the intersection of rgn and dstRect is rectangular, then
| return EQUAL and put the intersection into dstRect. If empty
| or not rectangular, return FALSE and don't modify dstRect.
|
| Does not call the storage allocator.
|
| 1. Fake up a rect rgn on the stack from dstRect.
| 2. Call RgnOp with max bytes = 24, OkGrow = FALSE.
| 3a. PtCount = 4 -> rect, return TRUE and update dstRect.
| 3b. PtCount < 4 -> empty, return TRUE and clear dstRect.
| 3c. PtCount > 4 -> not rect, return FALSE.
|
TRIMRECT:
    LINK        A6,#-0x2A                       | establish stack frame
    MOVEM.L     D0-D2/A1,-(A7)                  | save all regs used
    LEA.L       -0x18(A6),A0                    | point to buffer
    MOVE.L      A0,-0x1C(A6)                    | install into fake master
    LEA.L       -0x26(A6),A1                    | point to region data
    MOVE.L      A1,-0x2A(A6)                    | install into fake master
    MOVE.W      #0xA,(A1)+                      | install RgnSize = 10
    MOVEA.L     0x8(A6),A0                      | point to dstRect
    MOVE.L      (A0)+,(A1)+                     | copy dstRect topLeft
    MOVE.L      (A0)+,(A1)+                     | copy dstRect botRight
|
| RgnOp(rgn,rectRgn,BufHandle,24,sect,0,FALSE)
|
    CLR.W       -(A7)                           | room for fcn result
    MOVE.L      0xC(A6),-(A7)                   | push rgn
    PEA.L       -0x2A(A6)                       | push fake RgnHandle
    PEA.L       -0x1C(A6)                       | push BufHandle
    MOVE.W      #0x18,-(A7)                     | push MaxBytes = 24
    CLR.L       -(A7)                           | push op = SectScan, dh = 0
    CLR.B       -(A7)                           | push OkGrow = FALSE
    JSR         RGNOP(PC)                       | RgnOp(rgn,rectRgn,buf,24,op,dh,FALSE)
    MOVEA.L     0x8(A6),A0                      | point to dstRect
    CMPI.W      #0x4,(A7)+                      | is PtCount 4 ? (rectangular)
    BNE.B       TRIMRECT_EXIT                   | no, return < or > in CCR
    MOVE.L      -0x18(A6),(A0)+                 | update dstRect.topLeft
    MOVE.L      -0xC(A6),(A0)+                  | update dstRect.botRight
    SUB.W       D0,D0                           | set EQUAL flag
TRIMRECT_EXIT:
    MOVEM.L     (A7)+,D0-D2/A1                  | restore all regs
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return addr into A0
    ADDQ.W      #0x8,A7                         | strip parameters
    JMP         (A0)                            | jump thru A0 to return
| -------------------------------------------------------------
|
| PROCEDURE MapRgn(rgn: RgnHandle; fromRect, toRect: Rect);
|
| A6 offsets of parameters and locals after LINK:
|   PARAMSIZE = 12
|   RGN       = PARAMSIZE+8-4  (LONG, RgnHandle)
|   FROMRECT  = RGN-4          (LONG, addr of Rect)
|   TORECT    = FROMRECT-4     (LONG, addr of Rect)
| Locals:
|   INDEX   = -2  (INTEGER)
|   SIZE    = -4  (WORD)
|   PTCOUNT = -6  (WORD)
|
MAPRGN:
    LINK        A6,#-0x6                        | establish stack frame
    MOVEM.L     D3/D6-D7/A2-A4,-(A7)            | save regs
|
| Quit fast if FromRect = ToRect
|
    MOVEA.L     0xC(A6),A0                      | point to FromRect
    MOVEA.L     0x8(A6),A1                      | point to ToRect
    CMPM.L      (A0)+,(A1)+                     | is topLeft same ?
    BNE.B       MAPRGN_NO                       | no, continue
    CMPM.L      (A0)+,(A1)+                     | yes, is botRight same too ?
    BEQ.B       MAPRGN_EXIT                     | if so, just quit
|
| SPECIAL CASE RECTANGULAR RGN
|
MAPRGN_NO:
    MOVEA.L     0x10(A6),A4                     | get RgnHandle
    MOVEA.L     (A4),A0                         | de-reference rgn
    CMPI.W      #0xA,(A0)                       | is region rectangular ?
    BNE.B       MAPRGN_NO_2                     | no, continue
    PEA.L       0x2(A0)                         | yes, push RgnBBox
    MOVE.L      0xC(A6),-(A7)                   | push FromRect
    MOVE.L      0x8(A6),-(A7)                   | push ToRect
    JSR         MAPRECT(PC)                     | MapRect(rgn^^.RgnBBox,from,to)
MAPRGN_EXIT:
    BRA.B       MAPRGN_DONE                     | go to done
| ----------------------------------------------------------
|
| MAPRGN_NO_2 -- non-rect region: unpack to inversion-points,
| MapPt each, then SortPoints + CullPoints + PackRgn.
|
MAPRGN_NO_2:
    CLR.L       -(A7)                           | room for fcn result
    MOVE.W      #0x100,-(A7)                    | push ByteCount = 256
    MOVE.W      (A7),-0x4(A6)                   | size := 256 bytes
    JSR         NEWHANDLE(PC)                   | allocate PtBuf
    MOVEA.L     (A7)+,A3                        | get PtBuf handle in A3
    CLR.W       -0x2(A6)                        | index := 0
    MOVE.L      A4,-(A7)                        | push rgn
    MOVE.L      A3,-(A7)                        | push PtBuf handle
    PEA.L       -0x2(A6)                        | push VAR index
    PEA.L       -0x4(A6)                        | push VAR size
    JSR         PUTRGN(PC)                      | unpack rgn into inversion pts
    MOVE.W      -0x2(A6),D7                     | get index
    LSR.W       #0x2,D7                         | PtCount := index DIV 4
|
| Map all inversion points
|
    MOVE.W      D7,D6                           | copy PtCount for loop count
    MOVEA.L     (A3),A2                         | de-reference PtBuf handle
    BRA.B       MAPRGN_LOOP_2                   | go to loop start
| ----------------------------------------------------------
|
| MAPRGN_LOOP -- map each inversion point through (FromRect, ToRect)
|
MAPRGN_LOOP:
    MOVE.L      A2,-(A7)                        | push addr of an inv pt
    MOVE.L      0xC(A6),-(A7)                   | push FromRect
    MOVE.L      0x8(A6),-(A7)                   | push ToRect
    JSR         MAPPT(PC)                       | map this point
    ADDQ.L      #0x4,A2                         | advance to next point
MAPRGN_LOOP_2:
    DBF.W       D6,MAPRGN_LOOP                  | loop all inversion points
    MOVE.L      (A3),-(A7)                      | push PtBuf ptr
    MOVE.W      D7,-(A7)                        | push PtCount
    JSR         SORTPOINTS(PC)                  | SortPoints(PtBuf^,PtCount)
    MOVE.L      (A3),-(A7)                      | push PtBuf ptr
    MOVE.W      D7,-0x6(A6)                     | put PtCount in memory
    PEA.L       -0x6(A6)                        | push VAR PtCount
    JSR         CULLPOINTS(PC)                  | CullPoints(PtBuf^,PtCount)
    MOVE.L      A3,-(A7)                        | push PtBuf handle
    MOVE.W      -0x6(A6),-(A7)                  | push PtCount
    MOVE.L      A4,-(A7)                        | push rgn
    JSR         PACKRGN(PC)                     | PackRgn(PtBuf,PtCount,rgn)
    MOVEA.L     A3,A0                           | push PtBuf handle
    _DisposeHandle                              | discard it
MAPRGN_DONE:
    MOVEM.L     (A7)+,D3/D6-D7/A2-A4            | restore regs
    UNLK        A6                              | release stack frame
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDA.W      #0xC,A7                         | strip parameters
    JMP         (A0)                            | tail-call return from MAPRGN_DONE via A0
