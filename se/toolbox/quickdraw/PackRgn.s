| .PROC PACKRGN,3
| .REF SETSIZE
| -----------------------------------------------------------------
|
| PROCEDURE PackRgn(srcHandle: Handle; nPoints: INTEGER; dstRgn: RgnHandle);
|
| Converts a sorted array of inversion points into a region.
| Calls storage allocator to make more room and trim result to minimum size.
|
| OUTPUT IS IN THE FOLLOWING FORM:
|
| RGNSIZE
| RGNBBOX
| V H .. H 32767
| V=32767
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:
|
| Called during boot (7,415 times in 30s trace).

| -----------------------------------------------------------------
|
| PROCEDURE PackRgn(srcHandle: Handle; nPoints: INTEGER;
|                   dstRgn: RgnHandle);
|
| Converts a sorted array of inversion points into a region.
| Calls storage allocator to make more room and trim result to
| minimum size.
|
| Output is in the following form:
|   RgnSize
|   RgnBBox
|   V H .. H 32767
|   V=32767
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 10
|   SRCHANDLE = PARAMSIZE+8-4  (LONG)
|   NPOINTS   = SRCHANDLE-2    (INTEGER)
|   DSTRGN    = NPOINTS-4      (LONG, Handle)
| Locals:
|   BBOX = -8 (Rect)
|
PACKRGN:
    LINK        A6,#-0x8                        | allocate local variables
    MOVEM.L     D0-D7/A1-A4,-(A7)               | save regs
    MOVEA.L     0xE(A6),A4                      | get src handle
    MOVEA.L     0x8(A6),A3                      | get dst RgnHandle
    MOVE.W      0xC(A6),D6                      | get number of points
    MOVEA.L     (A3),A1                         | de-reference DstRgn
    MOVE.W      (A1),D5                         | get current RgnSize
    MOVEA.L     (A4),A0                         | de-reference SrcHandle
| ------------------------------------------------------------------------
|
| Check NPoints to special-case empty and rectangular regions
|
    MOVEQ.L     #0xA,D7                         | init RgnSize to empty rgn size
    CLR.L       -0x8(A6)                        | init bounding box to empty
    CLR.L       -0x4(A6)                        | init botRight of bounding box
    CMPI.W      #0x4,D6                         | how many points in source ?
    BGT.B       PACKRGN_NO                      | more than 4, not rectangular
    BLT.B       PACKRGN_DONE                    | less than 4, empty region
    MOVE.L      (A0),-0x8(A6)                   | get topLeft of bounding box
    MOVE.L      0xC(A0),-0x4(A6)                | get botRight of bounding box
    BRA.B       PACKRGN_DONE                    | install RgnSize and bbox and quit
| ------------------------------------------------------------------------
|
| PACKRGN_NO -- more than four points, non-rectangular.
| Scan for bbox left and right.
|
PACKRGN_NO:
    MOVE.W      (A0),-0x8(A6)                   | bbox top := first point.v
    MOVE.W      0x2(A0),D1                      | init MinH to first horiz
    MOVE.W      D1,D2                           | init MaxH to first horiz also
    MOVE.W      D6,D3                           | get number of points in src
PACKRGN_LOOP:
    SUBQ.W      #0x1,D3                         | any points left ?
    BLT.B       ENDSCAN                         | no, quit scanning
    MOVE.L      (A0)+,D0                        | yes, get next point
    CMP.W       D1,D0                           | is pt.h < MinH ?
    BGE.B       PACKRGN_NO_2                    | no, continue
    MOVE.W      D0,D1                           | yes, MinH := pt.h
    BRA.B       PACKRGN_LOOP                    | loop for more
| ----------------------------------------------------------
|
| PACKRGN_NO_2 -- check upper bound
|
PACKRGN_NO_2:
    CMP.W       D2,D0                           | is pt.h > MaxH ?
    BLE.B       PACKRGN_LOOP                    | no, go for next
    MOVE.W      D0,D2                           | yes, MaxH := pt.h
    BRA.B       PACKRGN_LOOP                    | go for next
| ----------------------------------------------------------
|
| ENDSCAN -- finalize bbox, allocate worst-case region buffer
|
ENDSCAN:
    MOVE.W      D1,-0x6(A6)                     | bbox left := MinH
    MOVE.W      D2,-0x2(A6)                     | bbox right := MaxH
    MOVE.W      -0x4(A0),-0x4(A6)               | bbox bottom := last point.v
| ----------------------------------------------------------------
|
| Expand DstRgn to hold worst case = 12 + 4*NPoints bytes
|
    MOVEQ.L     #0x3,D5                         | init size calculation
    ADD.W       D6,D5                           | get NPoints + 3
    LSL.W       #0x2,D5                         | times 4
    MOVE.L      A3,-(A7)                        | push DstRgn
    MOVE.W      D5,-(A7)                        | push new ByteCount
    JSR         SETHSIZE(PC)                    | make it that big
| ----------------------------------------------------
|
| Newly de-reference src and dst handles
|
    MOVEA.L     (A4),A0                         | de-reference src handle
    MOVEA.L     (A3),A1                         | de-reference DstRgn handle
    ADDA.W      D7,A1                           | skip over RgnSize & bbox
    SUBQ.W      #0x1,D6                         | DBRA count = NPoints - 1
    MOVE.W      (A0)+,D0                        | get first vert coord
    MOVE.W      #0x7FFF,D1                      | prepare constant 32767
    BRA.B       PACKRGN_START                   | go to loop start
| ----------------------------------------------------------
|
| NEXTPT -- emit a (V,H) pair, terminating each row with 32767
|
NEXTPT:
    CMP.W       (A0)+,D0                        | same vert coord ?
    BEQ.B       VSAME                           | yes, continue
    MOVE.W      D1,(A1)+                        | put end-of-row marker
    MOVE.W      -0x2(A0),D0                     | get new vert coord
PACKRGN_START:
    MOVE.W      D0,(A1)+                        | put vert coord
VSAME:
    MOVE.W      (A0)+,(A1)+                     | put horiz coord
    DBF.W       D6,NEXTPT                       | loop for all points
    MOVE.W      D1,(A1)+                        | put end-of-row marker
    MOVE.W      D1,(A1)+                        | put final vert = 32767
    MOVEA.L     (A3),A0                         | de-reference DstRgn handle
    SUBA.L      A0,A1                           | subtract from DstPtr
    MOVE.W      A1,D7                           | to compute RgnSize
| --------------------------------------------------------
|
| Install RgnSize and RgnBBox
|
PACKRGN_DONE:
    MOVEA.L     (A3),A0                         | de-reference DstRgn handle
    MOVE.W      D7,(A0)+                        | install RgnSize
    MOVE.L      -0x8(A6),(A0)+                  | install bounding box topLeft
    MOVE.L      -0x4(A6),(A0)+                  | and botRight
| --------------------------------------------------------
|
| Trim DstRgn to exact size if it isn't already
|
    CMP.W       D7,D5                           | is it already the right size ?
    BEQ.B       PACKRGN_SIZEOK                  | yes, skip
    MOVE.L      A3,-(A7)                        | push DstRgn handle
    MOVE.W      D7,-(A7)                        | push new size
    JSR         SETHSIZE(PC)                    | trim to exact size
| ------------------------------------------------------
|
| Clean up the stack and go home
|
PACKRGN_SIZEOK:
    MOVEM.L     (A7)+,D0-D7/A1-A4               | restore registers
    UNLK        A6                              | unlink local variables
    MOVEA.L     (A7)+,A0                        | pop return address
    ADDA.W      #0xA,A7                         | strip 10 bytes of params
    JMP         (A0)                            | tail-call return from PACKRGN_SIZEOK via A0
