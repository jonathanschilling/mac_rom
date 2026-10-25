| ------------------------------------------------
|
| A6 OFFSETS OF PARAMETERS AFTER LINK:

| ----------------------------------------------------------------
|
| PROCEDURE PutRgn(Rgn: RgnHandle; bufHandle: Handle;
|                  VAR index, size: INTEGER);
|
| Expands a region out to an array of inversion points.
|
| A6 offsets of params after LINK:
|   PARAMSIZE = 16
|   RGNHANDLE = PARAMSIZE+8-4  (LONG, RgnHandle)
|   BUFHANDLE = RGNHANDLE-4    (LONG, Handle)
|   INDEX     = BUFHANDLE-4    (LONG, VAR)
|   SIZE      = INDEX-4        (LONG, VAR)
|
PUTRGN:
    LINK	A6,#0x0                                | no local vars
    MOVEM.L	D7/A2-A4,-(A7)                      | save regs
    MOVEA.L	0x10(A6),A4                         | get BufHandle
    MOVEA.L	0x14(A6),A3                         | get RgnHandle
    MOVEA.L	0xC(A6),A2                          | get VAR index
    MOVEA.L	(A3),A0                             | de-reference RgnHandle
    MOVE.W	(A0),D7                              | get RgnSize
    ADD.W	D7,D7                                 | needed bytes := RgnSize*2
    ADD.W	(A2),D7                               | add current index
    MOVEA.L	0x8(A6),A1                          | get VAR size
    CMP.W	(A1),D7                               | does it fit ?
    BLE.B	PUTRGN_FITS                           | yes, continue
    ADDI.W	#0x100,D7                            | else grow by 256 bytes
    MOVE.W	D7,(A1)                              | update size
    MOVE.L	A4,-(A7)                             | push BufHandle
    MOVE.W	D7,-(A7)                             | push new size
    JSR	SETHSIZE(PC)                            | grow the buffer
    MOVEA.L	(A3),A0                             | re-deref RgnHandle
    MOVEA.L	0xC(A6),A2                          | re-fetch VAR index
PUTRGN_FITS:
    MOVEA.L	(A4),A1                             | de-reference BufHandle
    ADDA.W	(A2),A1                              | offset to current index
    CMPI.W	#0xA,(A0)                            | rectangular region ?
    BNE.B	PUTRGN_NOTRECT                        | no, walk inversion-pts
    ADDQ.W	#0x2,A0                              | skip RgnSize
    MOVE.L	(A0),(A1)+                           | top, left
    MOVE.W	(A0)+,(A1)+                          | top vert
    MOVE.W	(A0)+,D0                             | left horiz
    MOVE.L	(A0),D1                              | bottom, right
    MOVE.W	D1,(A1)+                             | bottom vert
    MOVE.W	(A0),(A1)+                           | left horiz (closing edge)
    MOVE.W	D0,(A1)+                             | bottom-right horiz
    MOVE.L	D1,(A1)+                             | trailing terminator
    BRA.B	PUTRGN_DONE                           | done with rect
| ----------------------------------------------------------
|
| PUTRGN_NOTRECT -- copy V/H pairs verbatim (already in inversion-point form)
|
PUTRGN_NOTRECT:
    LEA.L	0xA(A0),A0                            | skip RgnSize+RgnBBox
PUTRGN_NXTVERT:
    MOVE.L	(A0)+,D7                             | get next vert and first horiz
NXTHOR:
    MOVE.L	D7,(A1)+                             | put pair
    MOVE.W	(A0)+,D7                             | get next horiz
    MOVE.L	D7,(A1)+                             | put pair
    MOVE.W	(A0)+,D7                             | get following horiz
    CMPI.W	#0x7FFF,D7                           | end-of-row marker ?
    BNE.B	NXTHOR                                | no, keep going
    CMPI.W	#0x7FFF,(A0)                         | end-of-region marker ?
    BNE.B	PUTRGN_NXTVERT                        | no, next vert
PUTRGN_DONE:
    SUBA.L	(A4),A1                              | bytes used = BufPtr - BufStart
    MOVE.W	A1,(A2)                              | update VAR index
    MOVEM.L	(A7)+,D7/A2-A4                      | restore regs
    UNLK	A6                                     | release stack frame
    MOVEA.L	(A7)+,A0                            | pop return address
    ADDA.W	#0x10,A7                             | strip 16 bytes of params
    JMP	(A0)                                    | tail-call return from PUTRGN_DONE via A0
